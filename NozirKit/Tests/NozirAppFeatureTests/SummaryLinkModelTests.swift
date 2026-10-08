import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()
private let linkId = UUID()
private let ali = makeChild("Ali", id: aliId)
private let vali = makeChild("Vali")

/// The family list is read before the screen opens (`preload`), as
/// `SignedInModel.start()` does; `children` answers every read in order.
@MainActor
private func setup(
    _ script: FakeInsights.Script,
    children: [Result<[Child], ApiFailure>] = [.success([ali])],
    preload: Bool = true
) async -> (SummaryLinkModel, FakeInsights, FakeFamily) {
    var familyScript = FakeFamily.Script()
    familyScript.children = children
    let familyService = FakeFamily(familyScript)
    let store = FamilyStore(service: familyService)
    if preload { try? await store.refresh() }
    let insights = FakeInsights(script)
    return (SummaryLinkModel(summaryId: linkId, insights: insights, family: store), insights, familyService)
}

private func linked(_ period: SummaryPeriod?, start: String, end: String) -> InsightSummary {
    insight(childId: aliId, start: start, end: end, period: period)
}

@MainActor
@Suite struct SummaryLinkModelTests {
    // Spec §4.2: DAILY → P06 on exactly that day, named from the family list.
    @Test func aDailyLinkOpensThatDay() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, insights, _) = await setup(script)

        #expect(model.phase == .loading)
        await model.load()

        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await insights.calls == ["summary \(linkId.uuidString.lowercased())"])
    }

    // Review Focus 2: WEEKLY → P07 on exactly that week, not this one.
    @Test func aWeeklyLinkOpensThatWeek() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.weekly, start: "2026-09-14", end: "2026-09-20"))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))
    }

    // 404: removed, or another family's — the same answer.
    @Test func aSummaryThatIsGoneSaysSo() async {
        var script = FakeInsights.Script()
        script.byId = [.failure(notFound)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .gone)
    }

    @Test func aSummaryOfNoKnownPeriodIsGone() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(nil, start: "2026-10-01", end: "2026-10-31"))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .gone)
    }

    // Plan deviations L1, L2: the list is asked for once before "gone", for either period.
    @Test func aChildNoLongerInTheFamilyIsGone() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.weekly, start: "2026-09-14", end: "2026-09-20"))]
        let (model, _, family) = await setup(script, children: [.success([vali]), .success([vali])])

        await model.load()

        #expect(model.phase == .gone)
        #expect(await family.calls == ["children", "children"])
    }

    // Plan deviation L1: a list not read yet (start() failed, or a child added
    // on another phone) is read first.
    @Test func aFamilyNotReadYetIsAskedFor() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _, family) = await setup(script, preload: false)

        await model.load()

        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await family.calls == ["children"])
    }

    @Test func aFamilyThatCannotBeReadIsAFailure() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _, _) = await setup(script, children: [], preload: false)

        await model.load()

        #expect(model.phase == .failed(.noConnection))
    }

    // Spec §4.2 and plan deviation L3: any other failure is said in our words,
    // and "Qayta urinish" asks again.
    @Test func otherFailuresAreSaidAndCanBeRetried() async {
        var script = FakeInsights.Script()
        script.byId = [
            .failure(offline),
            .failure(.server(status: 403, error: ApiError(code: .subscriptionRequired))),
            .success(linked(.daily, start: "2026-10-04", end: "2026-10-04")),
        ]
        let (model, insights, _) = await setup(script)

        await model.load()
        #expect(model.phase == .failed(.noConnection))
        await model.load()
        #expect(model.phase == .failed(.subscriptionRequired))
        await model.load()
        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await insights.calls.count == 3)
    }

    // Review Focus 1: an earlier answer arriving after a retry never lands.
    @Test(.timeLimit(.minutes(5))) func aStaleAnswerNeverLands() async {
        let gate = PauseGate()
        var script = FakeInsights.Script()
        script.byId = [
            .success(linked(.daily, start: "2026-10-04", end: "2026-10-04")),
            .success(linked(.weekly, start: "2026-09-14", end: "2026-09-20")),
        ]
        script.byIdGate = gate
        let (model, _, _) = await setup(script)

        let first = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))

        await gate.release()
        await first.value

        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))
    }

    // Review Focus 6, plan deviation L4: the link hands its place to the
    // summary; when it is no longer on top nothing is pushed.
    @Test func theLinkHandsItsPlaceToTheSummaryOnlyWhileOnTop() {
        let link = SignedInView.HomeStep.summaryLink(linkId)
        let daily = SignedInView.HomeStep.summary(aliId, "Ali", date: day("2026-10-04"))

        #expect(SummaryLinkModel.path([.notifications, link], replacing: linkId, with: daily) == [.notifications, daily])
        #expect(SummaryLinkModel.path([.notifications], replacing: linkId, with: daily) == [.notifications])
        let other = SignedInView.HomeStep.summaryLink(UUID())
        #expect(SummaryLinkModel.path([.notifications, link, .notifications, other], replacing: linkId, with: daily)
            == [.notifications, link, .notifications, other])
    }
}
