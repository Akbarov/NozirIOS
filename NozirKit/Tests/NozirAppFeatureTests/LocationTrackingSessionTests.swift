import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let every15 = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)
private let every30 = LocationTracking(isEnabled: true, intervalMinutes: 30, zoneIntervalMinutes: 3, moveMetres: 100)

/// P12b opened from the hub: the session is already loaded, as P09 leaves it.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (LocationTrackingModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    await session.load()
    let model = LocationTrackingModel(childId: ali.id, childName: "Ali", family: family, session: session)
    return (model, session, fake)
}

@MainActor
@Suite struct LocationTrackingSessionTests {
    @Test func theRuleComesFromTheSessionWithoutAskingAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 4, tracking: every15))]
        let (model, _, fake) = await setup(script)

        await model.load()

        #expect(model.tracking == every15)
        #expect(!model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aSessionThatCouldNotReadShowsWhy() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .failure(offline)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.tracking == nil)
        #expect(model.loadFailure == .noConnection)
    }

    @Test func aSaveGoesBackToTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.success(snapshot(version: 5, tracking: every30))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(await fake.locationTrackingWrites == [RuleWrite(value: every30, version: 4)])
        #expect(session.version == 5)
        #expect(session.snapshot?.locationTracking == every30)
        #expect(model.notice == .saved)
        #expect(!model.canSave)
    }

    @Test func itWritesOnTheVersionAnotherScreenLeft() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.success(snapshot(version: 6, tracking: every30))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)
        session.accept(snapshot(version: 5, limit: ScreenTimeLimit(schoolDayMinutes: 60, weekendMinutes: 60, maxDailyBonusMinutes: 60), tracking: every15))

        await model.save()

        #expect(await fake.locationTrackingWrites.map(\.version) == [5])
        #expect(model.notice == .saved)
    }

    @Test func aConflictReloadsTheSessionAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 7, tracking: elsewhere))]
        script.locationTracking = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(model.tracking == elsewhere)
        #expect(session.version == 7)
        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.count == 1)
    }

    @Test func aRuleChangedElsewhereUnderTheEditIsNotWrittenOver() async {
        var script = FakeFamily.Script()
        let elsewhere = LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)
        // A pull to refresh brought another phone's change to this very rule.
        session.accept(snapshot(version: 6, tracking: elsewhere))

        await model.save()

        #expect(model.notice == .conflict)
        #expect(model.tracking == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.isEmpty)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, _, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.isEmpty)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.cancelNextWrite = true
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.tracking == every30)
        #expect(model.canSave)
        #expect(session.version == 4)
        #expect(await fake.locationTrackingWrites.count == 1)
    }
}
