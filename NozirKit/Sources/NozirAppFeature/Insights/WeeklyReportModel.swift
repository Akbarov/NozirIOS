import Foundation
import Observation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P07. Fifty-three ISO weeks (this one last) for one child; each page is the
/// week's daily usage and the weekly summary's paragraphs. Pages stay in memory
/// by Monday; the week before the one shown is fetched ahead; one load per
/// (child, week) at a time, owned by the model. Usage then summary, one after the other (plan
/// deviation E3); a summary failure, 403/404 included, only hides observations.
@MainActor
@Observable
final class WeeklyReportModel {
    struct Day: Equatable {
        let date: LocalDate
        let usedMinutes: Int
        /// A day still to come: no figure over it.
        let isFuture: Bool
    }

    struct Page: Equatable {
        let days: [Day]
        let observations: [String]
        let risk: StatusLevel
    }

    enum PageState: Equatable {
        case loading
        case loaded(Page)
        case failed(UserMessage)
    }

    private struct Key: Hashable {
        let child: UUID
        let week: LocalDate
    }

    static let weekCount = 53

    private(set) var childId: UUID
    /// Mondays, oldest first; the last is this week.
    private(set) var weeks: [LocalDate]
    /// The page on screen; the view's pager writes it.
    var selectedWeek: LocalDate
    private(set) var pages: [LocalDate: PageState] = [:]

    private let insights: any InsightsService
    private let today: @MainActor () -> LocalDate
    private struct Load {
        let id: UUID
        let task: Task<Void, Never>
    }

    @ObservationIgnored private var loads: [Key: Load] = [:]

    /// `initialWeek` (P16a): the week a link names. Its Monday is shown when
    /// the fifty-three weeks hold it; otherwise this week (plan deviation L5).
    init(
        childId: UUID,
        insights: any InsightsService,
        today: @escaping @MainActor () -> LocalDate,
        initialWeek: LocalDate? = nil
    ) {
        self.childId = childId
        self.insights = insights
        self.today = today
        let current = today().monday
        let weeks = Self.weeks(endingAt: current)
        self.weeks = weeks
        if let asked = initialWeek?.monday, weeks.contains(asked) {
            selectedWeek = asked
        } else {
            selectedWeek = current
        }
    }

    static func weeks(endingAt current: LocalDate) -> [LocalDate] {
        (0..<weekCount).map { current.adding(days: -7 * (weekCount - 1 - $0)) }
    }

    var currentWeek: LocalDate {
        weeks[weeks.count - 1]
    }

    /// Whenever the screen or the shown page appears. A Monday that has come
    /// since the screen was built moves the report on to the new week.
    func appear() async {
        let current = today().monday
        if current != currentWeek {
            weeks = Self.weeks(endingAt: current)
            selectedWeek = current
            pages = [:]
        }
        await show(selectedWeek)
    }

    /// Opening the tab again: the report asks the server again for the shown
    /// week and the one before it, a failed page included. A loaded page stays
    /// on screen while it is asked for and is replaced only by a new answer;
    /// other weeks already seen stay cached. A load already running for the
    /// same page is joined, and its answer written. A Monday that has come
    /// since moves the report on to the new week, as `appear()` does.
    func refresh() async {
        let current = today().monday
        if current != currentWeek {
            weeks = Self.weeks(endingAt: current)
            selectedWeek = current
            pages = [:]
        }
        let week = selectedWeek
        await reload(week)
        if let previous = self.week(before: week) {
            await reload(previous)
        }
    }

    /// Loads `week` (if not already there) and then the week before it.
    func show(_ week: LocalDate) async {
        await loadIfNeeded(week)
        if let previous = self.week(before: week) {
            await loadIfNeeded(previous)
        }
    }

    func retry(_ week: LocalDate) async {
        pages[week] = nil
        await loadIfNeeded(week)
    }

    /// Statistics' child switcher: the same week, a different child, nothing cached.
    func setChild(_ id: UUID) async {
        guard id != childId else { return }
        childId = id
        pages = [:]
        await show(selectedWeek)
    }

    func week(before week: LocalDate) -> LocalDate? {
        guard let index = weeks.firstIndex(of: week), index > 0 else { return nil }
        return weeks[index - 1]
    }

    func week(after week: LocalDate) -> LocalDate? {
        guard let index = weeks.firstIndex(of: week), index < weeks.count - 1 else { return nil }
        return weeks[index + 1]
    }

    /// Asks again for `week`: a loaded page is fetched in the background and
    /// stays as it is until an answer replaces it; a failed or missing page
    /// takes the ordinary path, spinner first.
    private func reload(_ week: LocalDate) async {
        switch pages[week] {
        case .loaded?:
            await load(Key(child: childId, week: week))
        case .failed?:
            pages[week] = nil
            await loadIfNeeded(week)
        case .loading?, nil:
            await loadIfNeeded(week)
        }
    }

    /// Loads happen in model-owned tasks, so a caller's cancellation (the view's
    /// `.task` restarting on a swipe) never abandons a page another caller is
    /// waiting on: a second caller joins the load already running.
    private func loadIfNeeded(_ week: LocalDate) async {
        let child = childId
        switch pages[week] {
        case .loaded?, .failed?: return
        case .loading?, nil: break
        }
        let key = Key(child: child, week: week)
        if loads[key] == nil { pages[week] = .loading }
        await load(key)
    }

    /// Joins the load already running for `key`, or starts one in a
    /// model-owned task, and waits for it.
    private func load(_ key: Key) async {
        if let running = loads[key] {
            await running.task.value
            return
        }
        let id = UUID()
        let task = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.fetch(key, id: id)
        }
        loads[key] = Load(id: id, task: task)
        await task.value
    }

    private func fetch(_ key: Key, id: UUID) async {
        defer {
            if loads[key]?.id == id { loads[key] = nil }
        }
        let child = key.child
        let week = key.week
        do {
            let usage = try await insights.dailyUsage(of: child, from: week, to: week.adding(days: 6))
            let summary = try? await insights.weeklySummary(of: child, weekStart: week)
            guard child == childId else { return }
            pages[week] = .loaded(Page(
                days: Self.days(of: week, from: usage, today: today()),
                observations: summary?.paragraphs ?? [],
                risk: summary?.riskLevel ?? .good
            ))
        } catch is CancellationError {
            // Nothing arrived; leave the page to be asked for again.
            if child == childId, pages[week] == .loading { pages[week] = nil }
        } catch {
            guard child == childId else { return }
            // A refresh that fails leaves the chart already on screen.
            if case .loaded? = pages[week] { return }
            pages[week] = .failed(UserMessage(error))
        }
    }

    /// Monday to Sunday; a day the server left out counts as zero.
    static func days(of week: LocalDate, from usage: [DailyUsage], today: LocalDate) -> [Day] {
        let minutes = Dictionary(usage.map { ($0.date, $0.usedMinutes) }, uniquingKeysWith: { first, _ in first })
        return (0..<7).map { offset in
            let date = week.adding(days: offset)
            return Day(date: date, usedMinutes: minutes[date] ?? 0, isFuture: date > today)
        }
    }

    /// "Bu hafta", "Oʻtgan hafta", then the report's own name.
    func title(of week: LocalDate, _ l10n: L10n) -> String {
        if week == currentWeek { return l10n.weeklyReportTitle }
        if week == currentWeek.adding(days: -7) { return l10n.weeklyReportTitleLastWeek }
        return l10n.screenWeeklyReportTitle
    }

    nonisolated static func range(of week: LocalDate, _ l10n: L10n) -> String {
        DateTexts.weekRange(week, week.adding(days: 6), l10n)
    }

    /// Android `weeklyChartColumns`: short weekday, short duration (blank for
    /// days to come), height from zero, the first equal peak marked.
    nonisolated static func columns(_ page: Page, _ l10n: L10n) -> [NozirChartColumn] {
        let minutes = page.days.map(\.usedMinutes)
        let fractions = ChartMath.fractions(minutes)
        let peak = ChartMath.peakIndex(minutes)
        return page.days.enumerated().map { index, day in
            NozirChartColumn(
                id: index,
                label: DateTexts.shortWeekday(day.date, l10n),
                valueLabel: day.isFuture ? "" : Durations.short(day.usedMinutes, l10n),
                fraction: fractions[index],
                isPeak: index == peak
            )
        }
    }

    /// The chart as VoiceOver reads it: every day that has a figure.
    nonisolated static func chartDescription(_ columns: [NozirChartColumn], _ l10n: L10n) -> String {
        let spoken = columns
            .filter { !$0.valueLabel.isEmpty }
            .map { l10n.weeklyChartDayValue($0.label, $0.valueLabel) }
        return l10n.weeklyChartDescription(spoken.joined(separator: l10n.weeklyChartDaySeparator))
    }

    /// "Eng koʻp: seshanba — 1 soat 0 daqiqa"; nil for a week of zeros.
    nonisolated static func peakLine(_ page: Page, _ l10n: L10n) -> String? {
        guard let peak = ChartMath.peakIndex(page.days.map(\.usedMinutes)) else { return nil }
        let day = page.days[peak]
        return l10n.weeklyPeakLine(DateTexts.weekday(day.date, l10n).lowercased(), Durations.long(day.usedMinutes, l10n))
    }

    /// No use at all and nothing observed.
    nonisolated static func isEmpty(_ page: Page) -> Bool {
        page.days.allSatisfy { $0.usedMinutes == 0 } && page.observations.isEmpty
    }
}
