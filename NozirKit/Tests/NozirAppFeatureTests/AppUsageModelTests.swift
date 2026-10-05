import Foundation
import Testing
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()

private func app(_ packageId: String, _ minutes: Int, name: String = "") -> AppUsageEntry {
    AppUsageEntry(packageId: packageId, displayName: name, minutes: minutes)
}

private func breakdown(_ range: UsageRange, _ entries: [AppUsageEntry]) -> AppBreakdown {
    AppBreakdown(range: range, totalMinutes: entries.reduce(0) { $0 + $1.minutes }, entries: entries)
}

/// Holds the "today" answer until the test lets it go; every other range answers at once.
private actor GatedInsights: InsightsService {
    private var todayAsked = false
    private var askedWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        guard range == .today else { return breakdown(range, [app("b", 70)]) }
        todayAsked = true
        askedWaiter?.resume()
        askedWaiter = nil
        await withCheckedContinuation { release = $0 }
        return breakdown(.today, [app("a", 10)])
    }

    func waitUntilTodayIsAsked() async {
        if todayAsked { return }
        await withCheckedContinuation { askedWaiter = $0 }
    }

    func answerToday() {
        release?.resume()
        release = nil
    }

    func home() async throws -> ParentHome { throw offline }
    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary { throw offline }
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary { throw offline }
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] { throw offline }
}

@MainActor
@Suite struct AppUsageModelTests {
    private let l10n = L10n(.uz)

    @Test func todayIsAskedFirst() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, [app("a", 10)]) }
        let insights = FakeInsights(script)
        let model = AppUsageModel(childId: aliId, insights: insights)

        await model.load()

        #expect(model.range == .today)
        #expect(model.state == .loaded(breakdown(.today, [app("a", 10)])))
        #expect(await insights.calls == ["apps TODAY"])
        #expect(await insights.childIds == [aliId])
    }

    @Test func anotherRangeIsAskedAgain() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, [app("a", range == .lastThirtyDays ? 900 : 10)]) }
        let insights = FakeInsights(script)
        let model = AppUsageModel(childId: aliId, insights: insights)
        await model.load()

        model.range = .lastThirtyDays
        await model.load()

        #expect(model.total == 900)
        #expect(await insights.calls == ["apps TODAY", "apps LAST_30_DAYS"])
    }

    // Review Focus 1.
    @Test(.timeLimit(.minutes(1)))
    func aLateAnswerForAnOldRangeIsIgnored() async {
        let gated = GatedInsights()
        let model = AppUsageModel(childId: aliId, insights: gated)
        let first = Task { await model.load() }
        await gated.waitUntilTodayIsAsked()

        model.range = .lastSevenDays
        await model.load()
        await gated.answerToday()
        await first.value

        #expect(model.range == .lastSevenDays)
        #expect(model.state == .loaded(breakdown(.lastSevenDays, [app("b", 70)])))
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledRefreshKeepsWhatIsOnScreen() async {
        let insights = HangingInsights(hanging: [2])
        let model = AppUsageModel(childId: aliId, insights: insights)
        await model.load()
        let old = model.state
        guard case .loaded = old else { Issue.record("first load did not load"); return }

        let refresh = Task { await model.load() }
        await insights.waitUntilAsked("apps", 2)
        #expect(model.state == old)

        refresh.cancel()
        await refresh.value

        #expect(model.state == old)
    }

    @Test(.timeLimit(.minutes(1)))
    func aCancelledFirstLoadOffersARetry() async {
        let insights = HangingInsights(hanging: [1])
        let model = AppUsageModel(childId: aliId, insights: insights)
        let first = Task { await model.load() }
        await insights.waitUntilAsked("apps", 1)
        #expect(model.state == .loading)

        first.cancel()
        await first.value

        #expect(model.state == .failed(.noConnection))
    }

    @Test func aFailureIsAnErrorAndCanBeRetried() async {
        let insights = FakeInsights()
        let model = AppUsageModel(childId: aliId, insights: insights)
        await model.load()
        #expect(model.state == .failed(.noConnection))

        await insights.add { $0.apps = { _, range in breakdown(range, [app("a", 10)]) } }
        await model.load()

        #expect(model.state == .loaded(breakdown(.today, [app("a", 10)])))
    }

    @Test func noAppsIsEmpty() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, []) }
        let model = AppUsageModel(childId: aliId, insights: FakeInsights(script))

        await model.load()

        #expect(model.isEmpty)
        #expect(model.entries.isEmpty)
    }

    @Test func entriesAreFoldedWithOthersLast() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in
            breakdown(range, [app("nozir.other_apps", 5), app("a", 10), app("b", 40), app("c", 30), app("d", 20), app("e", 15)])
        }
        let model = AppUsageModel(childId: aliId, insights: FakeInsights(script))

        await model.load()

        #expect(model.entries.map(\.packageId) == ["b", "c", "d", "e", "nozir.other_apps"])
        #expect(model.entries.last?.minutes == 15)
        #expect(model.total == 120)
        #expect(!model.isEmpty)
    }

    @Test func namesAndColoursFollowTheChartRule() {
        #expect(AppUsageModel.name(of: app("nozir.other_apps", 5, name: "Other"), l10n) == l10n.appUsageOther)
        #expect(AppUsageModel.name(of: app("com.google.android.youtube", 5, name: "com.google.android.youtube"), l10n) == "YouTube")
        #expect(AppUsageModel.colorIndex(of: app("a", 1), at: 0) == 0)
        #expect(AppUsageModel.colorIndex(of: app("d", 1), at: 3) == 3)
        #expect(AppUsageModel.colorIndex(of: app("nozir.other_apps", 1), at: 1) == nil)
        #expect(AppUsageModel.colorIndex(of: app("z", 1), at: 4) == nil)
    }

    @Test func theBarIsSaidAloud() {
        let entries = [app("org.telegram.messenger", 30), app("nozir.other_apps", 15)]

        let expected = l10n.appUsageChartDescription([
            l10n.appUsageChartEntry("Telegram", Durations.short(30, l10n)),
            l10n.appUsageChartEntry(l10n.appUsageOther, Durations.short(15, l10n)),
        ].joined(separator: l10n.weeklyChartDaySeparator))

        #expect(AppUsageModel.chartDescription(entries, l10n) == expected)
    }

    @Test func rangesHaveTheirNames() {
        #expect(AppUsageModel.rangeTitle(.today, l10n) == l10n.rangeToday)
        #expect(AppUsageModel.rangeTitle(.lastSevenDays, l10n) == l10n.rangeSevenDays)
        #expect(AppUsageModel.rangeTitle(.lastThirtyDays, l10n) == l10n.rangeThirtyDays)
    }

    // Spec §5.5: the bar, like the legend and the table, is each app's share of the total.
    @Test func theBarIsTheShareOfTheTotal() {
        let entries = [app("a", 30), app("b", 10)]

        #expect(AppUsageModel.barFractions(entries, total: 80) == [0.375, 0.125])
        #expect(AppUsageModel.barFractions(entries, total: 0) == [0, 0])
        #expect(AppUsageModel.barFractions(entries, total: 20) == [1, 0.5])
        #expect(AppUsageModel.barFractions([app("a", -5)], total: 20) == [0])
    }
}
