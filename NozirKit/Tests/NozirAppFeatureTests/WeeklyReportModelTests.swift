import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let aliId = UUID()
private let valiId = UUID()

/// "Today" that a test can move.
@MainActor
private final class Today {
    var value: LocalDate

    init(_ text: String) {
        value = day(text)
    }
}

private func usage(_ minutes: [Int], from monday: LocalDate) -> [DailyUsage] {
    minutes.enumerated().map { DailyUsage(date: monday.adding(days: $0.offset), usedMinutes: $0.element, limitMinutes: 120) }
}

@MainActor
private func setup(_ script: FakeInsights.Script, today: Today? = nil) -> (WeeklyReportModel, FakeInsights) {
    let clock = today ?? Today("2026-10-07")
    let insights = FakeInsights(script)
    let model = WeeklyReportModel(childId: aliId, insights: insights, today: { clock.value })
    return (model, insights)
}

@MainActor
@Suite struct WeeklyReportModelTests {
    private let l10n = L10n(.uz)

    @Test func fiftyThreeWeeksEndingWithThisOne() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.weeks.count == 53)
        #expect(model.weeks.last == day("2026-10-05"))
        #expect(model.weeks.first == day("2025-10-06"))
        #expect(model.currentWeek == day("2026-10-05"))
        #expect(model.selectedWeek == day("2026-10-05"))
        #expect(zip(model.weeks, model.weeks.dropFirst()).allSatisfy { $0.adding(days: 7) == $1 })
    }

    @Test func aWeekIsItsUsageAndItsObservations() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([30, 60, 0], from: from) }
        script.weekly = { _, monday in
            insight(childId: aliId, start: monday.text, end: monday.adding(days: 6).text, paragraphs: ["Bir.", "Ikki."], risk: .attention)
        }
        let (model, insights) = setup(script)

        await model.appear()

        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.days.map(\.usedMinutes) == [30, 60, 0, 0, 0, 0, 0])
        #expect(page.days.map(\.isFuture) == [false, false, false, true, true, true, true])
        #expect(page.observations == ["Bir.", "Ikki."])
        #expect(page.risk == .attention)
        let calls = await insights.calls
        #expect(calls.prefix(2) == ["usage 2026-10-05…2026-10-11", "weekly 2026-10-05"])
    }

    @Test func thePreviousWeekIsFetchedAhead() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let (model, insights) = setup(script)

        await model.appear()

        #expect(await insights.calls == [
            "usage 2026-10-05…2026-10-11", "weekly 2026-10-05",
            "usage 2026-09-28…2026-10-04", "weekly 2026-09-28",
        ])
        #expect(model.pages[day("2026-09-28")] != nil)
    }

    @Test func aWeekSeenIsNotAskedForAgain() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let (model, insights) = setup(script)
        await model.appear()
        let before = await insights.calls.count

        await model.show(day("2026-10-05"))
        await model.appear()

        #expect(await insights.calls.count == before)
    }

    @Test func aWeeklySummaryFailureLeavesTheChart() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10, 20], from: from) }
        script.weekly = { _, _ in throw offline }
        let (model, _) = setup(script)

        await model.appear()

        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.observations.isEmpty)
        #expect(page.days[1].usedMinutes == 20)
    }

    @Test func aUsageFailureIsAnErrorAndCanBeRetried() async {
        var script = FakeInsights.Script()
        script.usage = { _, _, _ in throw offline }
        let (model, insights) = setup(script)
        await model.appear()
        #expect(model.pages[day("2026-10-05")] == .failed(.noConnection))

        await insights.add { $0.usage = { _, from, _ in usage([5], from: from) } }
        await model.retry(day("2026-10-05"))

        guard case .loaded = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
    }

    @Test func anotherChildStartsFromNothing() async {
        var script = FakeInsights.Script()
        script.usage = { child, from, _ in usage([child == aliId ? 10 : 90], from: from) }
        let (model, insights) = setup(script)
        await model.appear()

        await model.setChild(valiId)

        #expect(model.childId == valiId)
        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.days[0].usedMinutes == 90)
        #expect(await insights.childIds.suffix(4) == [valiId, valiId, valiId, valiId])
    }

    @Test func aNewWeekMovesTheReportOn() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let today = Today("2026-10-11")
        let (model, _) = setup(script, today: today)
        await model.appear()

        today.value = day("2026-10-12")
        await model.appear()

        #expect(model.currentWeek == day("2026-10-12"))
        #expect(model.selectedWeek == day("2026-10-12"))
        #expect(model.weeks.count == 53)
    }

    @Test func weeksStepWithinTheRange() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.week(before: day("2026-10-05")) == day("2026-09-28"))
        #expect(model.week(after: day("2026-10-05")) == nil)
        #expect(model.week(before: day("2025-10-06")) == nil)
    }

    @Test func titlesSayThisWeekAndLastWeek() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.title(of: day("2026-10-05"), l10n) == l10n.weeklyReportTitle)
        #expect(model.title(of: day("2026-09-28"), l10n) == l10n.weeklyReportTitleLastWeek)
        #expect(model.title(of: day("2026-09-21"), l10n) == l10n.screenWeeklyReportTitle)
        #expect(WeeklyReportModel.range(of: day("2026-09-28"), l10n) == DateTexts.weekRange(day("2026-09-28"), day("2026-10-04"), l10n))
    }

    @Test func theChartMarksThePeakAndLeavesTheFutureBlank() {
        let monday = day("2026-10-05")
        let page = WeeklyReportModel.Page(
            days: [30, 60, 60, 0, 0, 0, 0].enumerated().map {
                WeeklyReportModel.Day(date: monday.adding(days: $0.offset), usedMinutes: $0.element, isFuture: $0.offset >= 3)
            },
            observations: [],
            risk: .good
        )

        let columns = WeeklyReportModel.columns(page, l10n)

        #expect(columns.map(\.label) == l10n.weekdayNamesShort)
        #expect(columns.map(\.fraction) == [0.5, 1, 1, 0, 0, 0, 0])
        #expect(columns.map(\.isPeak) == [false, true, false, false, false, false, false])
        #expect(columns[0].valueLabel == Durations.short(30, l10n))
        #expect(columns[3].valueLabel == "")
        #expect(WeeklyReportModel.peakLine(page, l10n) == l10n.weeklyPeakLine(l10n.weekdayNames[1].lowercased(), Durations.long(60, l10n)))
        let spoken = [
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[0], Durations.short(30, l10n)),
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[1], Durations.short(60, l10n)),
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[2], Durations.short(60, l10n)),
        ]
        #expect(WeeklyReportModel.chartDescription(columns, l10n) == l10n.weeklyChartDescription(spoken.joined(separator: ", ")))
    }

    @Test func aQuietWeekHasNoPeakAndWithoutObservationsIsEmpty() {
        let monday = day("2026-10-05")
        let zeros = (0..<7).map { WeeklyReportModel.Day(date: monday.adding(days: $0), usedMinutes: 0, isFuture: false) }

        #expect(WeeklyReportModel.peakLine(WeeklyReportModel.Page(days: zeros, observations: [], risk: .good), l10n) == nil)
        #expect(WeeklyReportModel.isEmpty(WeeklyReportModel.Page(days: zeros, observations: [], risk: .good)))
        #expect(!WeeklyReportModel.isEmpty(WeeklyReportModel.Page(days: zeros, observations: ["Bir."], risk: .good)))
    }
}
