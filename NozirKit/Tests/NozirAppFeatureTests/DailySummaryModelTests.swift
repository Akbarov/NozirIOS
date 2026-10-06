import Foundation
import Testing
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()

@MainActor
private func setup(_ script: FakeInsights.Script, date: LocalDate? = nil) -> (DailySummaryModel, FakeInsights) {
    let insights = FakeInsights(script)
    return (DailySummaryModel(childId: aliId, childName: "Ali", date: date, insights: insights), insights)
}

@MainActor
@Suite struct DailySummaryModelTests {
    private let l10n = L10n(.uz)

    @Test func theLatestSummaryAndItsWeeksQuestion() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.success(daily)]
        script.weekly = { _, _ in insight(childId: aliId, start: "2026-09-28", end: "2026-10-04", question: "Nima yoqdi?") }
        let (model, insights) = setup(script)

        await model.load()

        #expect(model.state == .loaded(daily))
        #expect(model.question == "Nima yoqdi?")
        // 2026-10-04 is a Sunday: its week starts on Monday 2026-09-28.
        #expect(await insights.calls == ["daily latest", "weekly 2026-09-28"])
        #expect(await insights.childIds == [aliId, aliId])
    }

    @Test func aDayGivenIsTheDayAsked() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-01", end: "2026-10-01"))]
        let (model, insights) = setup(script, date: day("2026-10-01"))

        await model.load()

        #expect(await insights.calls.first == "daily 2026-10-01")
    }

    @Test func aSummaryNotWrittenYetIsNotAnError() async {
        var script = FakeInsights.Script()
        script.daily = [.failure(notFound)]
        let (model, insights) = setup(script)

        await model.load()

        #expect(model.state == .notReady)
        #expect(await insights.calls == ["daily latest"])
    }

    @Test func theFreePlanIsTold() async {
        var script = FakeInsights.Script()
        script.daily = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.state == .failed(.subscriptionRequired))
    }

    @Test func aWeeklyFailureIsSilent() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.success(daily)]
        script.weekly = { _, _ in throw offline }
        let (model, _) = setup(script)

        await model.load()

        #expect(model.state == .loaded(daily))
        #expect(model.question == nil)
    }

    @Test func aFailureCanBeRetried() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.failure(offline), .success(daily)]
        let (model, _) = setup(script)
        await model.load()
        #expect(model.state == .failed(.noConnection))

        await model.retry()

        #expect(model.state == .loaded(daily))
    }

    @Test(.timeLimit(.minutes(5)))
    func aCancelledRetryKeepsTheSummaryOnScreen() async {
        let insights = HangingInsights(hanging: [2])
        let model = DailySummaryModel(childId: aliId, childName: "Ali", insights: insights)
        await model.load()
        let old = model.state
        guard case .loaded = old else { Issue.record("first load did not load"); return }

        let refresh = Task { await model.retry() }
        await insights.waitUntilAsked("daily", 2)
        #expect(model.state == old)

        refresh.cancel()
        await refresh.value

        #expect(model.state == old)
    }

    @Test(.timeLimit(.minutes(5)))
    func aCancelledFirstRetryOffersAnotherTry() async {
        let insights = HangingInsights(hanging: [1])
        let model = DailySummaryModel(childId: aliId, childName: "Ali", insights: insights)
        let first = Task { await model.retry() }
        await insights.waitUntilAsked("daily", 1)

        first.cancel()
        await first.value

        #expect(model.state == .failed(.noConnection))
    }

    @Test func comingBackDoesNotAskAgain() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-04", end: "2026-10-04"))]
        let (model, insights) = setup(script)
        await model.load()

        await model.load()

        #expect(await insights.calls.filter { $0.hasPrefix("daily") }.count == 1)
    }

    @Test func theHeaderNamesTheChildAndTheDay() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _) = setup(script)
        #expect(model.subtitle(l10n) == nil)

        await model.load()

        #expect(model.title(l10n) == l10n.dailySummaryChildToday("Ali"))
        #expect(model.subtitle(l10n) == DateTexts.weekdayAndDate(day("2026-10-04"), l10n))
    }

    @Test(.timeLimit(.minutes(5)))
    func loadingAgainAfterAFailureShowsTheSpinner() async {
        let insights = HangingInsights(hanging: [1, 2])
        let model = DailySummaryModel(childId: aliId, childName: "Ali", insights: insights)
        let first = Task { await model.load() }
        await insights.waitUntilAsked("daily", 1)
        first.cancel()
        await first.value
        #expect(model.state == .failed(.noConnection))

        let second = Task { await model.load() }
        await insights.waitUntilAsked("daily", 2)
        #expect(model.state == .loading)

        second.cancel()
        await second.value
        #expect(model.state == .failed(.noConnection))
    }
}
