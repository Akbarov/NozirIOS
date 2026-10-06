import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let every15 = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)

@MainActor
private func setup(_ script: FakeFamily.Script) -> (LocationTrackingModel, FakeFamily) {
    let fake = FakeFamily(script)
    return (LocationTrackingModel(childId: childId, childName: "Ali", family: FamilyStore(service: fake)), fake)
}

@MainActor
@Suite struct LocationTrackingModelTests {
    @Test func theRuleIsReadAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.tracking == every15)
        #expect(!model.canSave)

        model.setInterval(30)

        #expect(model.tracking?.intervalMinutes == 30)
        #expect(model.canSave)
    }

    @Test func loadingAgainKeepsTheEditsInProgress() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.load()

        #expect(model.tracking?.intervalMinutes == 30)
        #expect(model.canSave)
    }

    @Test func aFailedFirstLoadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)
        await model.load()
        #expect(model.tracking == nil)
        #expect(model.loadFailure != nil)

        await model.load()

        #expect(model.tracking == every15)
        #expect(model.loadFailure == nil)
    }

    @Test func turningOffKeepsTheNumbers() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)
        await model.load()

        model.setEnabled(false)

        #expect(model.tracking == LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100))
    }

    @Test func savingNamesTheVersionItWasReadAt() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let changed = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 1, moveMetres: 50)
        script.locationTracking = [.success(snapshot(version: 5, tracking: changed))]
        let (model, fake) = setup(script)
        await model.load()
        model.setZoneInterval(1)
        model.setMove(50)

        await model.save()

        #expect(await fake.locationTrackingWrites == [RuleWrite(value: changed, version: 4)])
        #expect(model.notice == .saved)
        #expect(!model.canSave)
    }

    @Test func aSecondSaveUsesTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let first = LocationTracking(isEnabled: true, intervalMinutes: 30, zoneIntervalMinutes: 3, moveMetres: 100)
        let second = LocationTracking(isEnabled: true, intervalMinutes: 5, zoneIntervalMinutes: 3, moveMetres: 100)
        script.locationTracking = [.success(snapshot(version: 5, tracking: first)), .success(snapshot(version: 6, tracking: second))]
        let (model, fake) = setup(script)
        await model.load()
        model.setInterval(30)
        await model.save()

        model.setInterval(5)
        await model.save()

        #expect(await fake.locationTrackingWrites.map(\.version) == [4, 5])
    }

    // Review Focus 4.
    @Test func aConflictReloadsAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 7, tracking: elsewhere))]
        script.locationTracking = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, fake) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(model.tracking == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.count == 1)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 2)
    }

    @Test func aFrozenChildSaysWhy() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, _) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.message == .childNotActive)
        #expect(model.canSave)
    }

    // Spec: a plan lock is not an inline message; the view shows the lock card.
    @Test func aSaveThatNeedsThePlanKeepsTheMessageAndDoesNotRetry() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, fake) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.message == .subscriptionRequired)
        #expect(model.notice == nil)
        #expect(await fake.locationTrackingWrites.count == 1)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aRuleThatCannotBeReadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.loadFailure == .noConnection)
        #expect(model.tracking == nil)

        await model.load()
        #expect(model.loadFailure == nil)
        #expect(model.tracking == every15)
    }
}
