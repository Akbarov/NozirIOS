import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let vali = makeChild("Vali")

@MainActor
private func setup(
    _ script: FakeLocation.Script,
    children: [Child] = [ali],
    rules: [Result<RuleSnapshot, ApiFailure>] = [],
    pause: @escaping @Sendable (Duration) async throws -> Void = { _ in }
) async -> (LocationModel, FakeLocation, FakeFamily) {
    var familyScript = FakeFamily.Script()
    familyScript.children = [.success(children)]
    familyScript.rules = rules
    let familyFake = FakeFamily(familyScript)
    let store = FamilyStore(service: familyFake)
    try? await store.refresh()
    let fake = FakeLocation(script)
    return (LocationModel(family: store, location: fake, pause: pause), fake, familyFake)
}

@MainActor
@Suite struct LocationModelTests {
    @Test func noChildrenIsNoChild() async {
        let (model, fake, _) = await setup(FakeLocation.Script(), children: [])

        await model.load()

        #expect(model.phase == .noChild)
        #expect(await fake.calls.isEmpty)
    }

    @Test func aFixIsShownWithZonesAndTheTrackingRule() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .success([zone(for: ali.id)])
        let tracking = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)
        let (model, fake, _) = await setup(script, rules: [.success(snapshot(version: 1, tracking: tracking))])

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
        #expect(model.zones.map(\.name) == ["Maktab"])
        #expect(model.tracking == tracking)
        #expect(await fake.calls == ["location", "zones"])
    }

    @Test func aPhoneThatNeverReportedIsNotAnError() async {
        let (model, _, _) = await setup(FakeLocation.Script())

        await model.load()

        #expect(model.phase == .neverReported)
        #expect(model.snapshot == nil)
    }

    @Test func aFreePlanSeesTheLock() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .locked)
    }

    // A lapsed plan never blocks deleting: the zones are still read and shown.
    @Test func aLockedLoadStillReadsTheZones() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        script.zones[ali.id] = .success([zone(for: ali.id, isActive: false)])
        let (model, fake, _) = await setup(script)

        await model.load()

        #expect(model.phase == .locked)
        #expect(model.zones.map(\.name) == ["Maktab"])
        #expect(await fake.calls == ["location", "zones"])
    }

    @Test(.timeLimit(.minutes(1)))
    func aLockedLoadOfAnotherChildNeverShowsTheOldZones() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        script.zones[ali.id] = .success([zone(for: ali.id)])
        script.zonesGate = gate
        let (model, _, _) = await setup(script, children: [ali, vali])

        let late = Task { await model.load() }
        await gate.untilPaused()
        model.selectedChildId = vali.id
        await model.load()
        await gate.release()
        await late.value

        #expect(model.childId == vali.id)
        #expect(model.zones.isEmpty)
    }

    @Test func aFirstFailureIsAFullError() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(offline)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .failed(.noConnection))
    }

    @Test func aLaterOfflineLoadKeepsThePinAndSaysSo() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .failure(offline)]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
        #expect(model.isOffline)
    }

    @Test func aLaterServerFailureKeepsThePinWithAMessage() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .failure(.unexpectedStatus(500))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.load()

        #expect(model.snapshot == fixAt())
        #expect(!model.isOffline)
        #expect(model.inlineMessage == .serverProblem)
    }

    @Test func zonesThatCannotBeReadAreQuietlyLeftOut() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .failure(offline)
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.zones.isEmpty)
        #expect(model.inlineMessage == nil)
    }

    @Test func theFirstChildByDefaultAndAnotherChildStartsFresh() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .success([zone(for: ali.id)])
        let (model, fake, _) = await setup(script, children: [ali, vali])
        await model.load()
        #expect(model.childId == ali.id)
        #expect(model.showsSwitcher)

        model.selectedChildId = vali.id
        await model.load()

        #expect(model.childId == vali.id)
        #expect(model.phase == .neverReported)
        #expect(model.snapshot == nil)
        #expect(model.zones.isEmpty)
        #expect(await fake.childIds.suffix(2) == [vali.id, vali.id])
    }

    @Test func theCameraOpensOnThePinThenAZoneThenTashkent() async {
        var zoneOnly = FakeLocation.Script()
        zoneOnly.zones[ali.id] = .success([zone(for: ali.id)])
        let (model, _, _) = await setup(zoneOnly)
        // Nothing is decided before the first load has finished.
        #expect(model.cameraTarget == nil)
        await model.load()
        #expect(model.cameraTarget == Coordinate(latitude: 41.30, longitude: 69.25))

        var withFix = zoneOnly
        withFix.locations[ali.id] = [.success(fixAt())]
        let (fixed, _, _) = await setup(withFix)
        await fixed.load()
        #expect(fixed.cameraTarget == Coordinate(latitude: 41.3111, longitude: 69.2797))

        let (empty, _, _) = await setup(FakeLocation.Script())
        await empty.load()
        #expect(empty.cameraTarget == LocationModel.fallbackCentre)
    }

    @Test(.timeLimit(.minutes(1)))
    func switchingChildDoesNotSendTheCameraToTashkent() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        let (model, fake, _) = await setup(script, children: [ali, vali])
        await model.load()
        await fake.add { $0.zonesGate = gate }

        model.selectedChildId = vali.id
        let loading = Task { await model.load() }
        await gate.untilPaused()
        // The old pin is gone and the new child's zones are not in yet: no target.
        #expect(model.cameraTarget == nil)
        await gate.release()
        await loading.value

        #expect(model.cameraTarget == LocationModel.fallbackCentre)
    }

    // MARK: "Where are they now"

    @Test func anUnreachablePhoneIsSaidAtOnce() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.success(false)]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .unreachable)
        #expect(await fake.calls.filter { $0 == "location" }.count == 1)
    }

    @Test func aNewerFixEndsTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(fixAt()), .success(fixAt(minutesAfter: 1, latitude: 41.32))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .idle)
        #expect(model.snapshot == fixAt(minutesAfter: 1, latitude: 41.32))
        #expect(await fake.calls.filter { $0 == "location" }.count == 3)
    }

    // Review Focus 2.
    @Test func anOldReasonDoesNotEndTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(reasonAt(minutesAfter: 0))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .idle)
        #expect(model.snapshot == reasonAt(minutesAfter: 0))
        #expect(await fake.calls.filter { $0 == "location" }.count == 1 + LocationModel.pollAttempts)
    }

    // Review Focus 2.
    @Test func aNewerReasonEndsTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(reasonAt(minutesAfter: 2, .noFix))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.snapshot == reasonAt(minutesAfter: 2, .noFix))
        #expect(await fake.calls.filter { $0 == "location" }.count == 2)
    }

    @Test func aPhoneThatNeverReportedCanStillBeAsked() async {
        var script = FakeLocation.Script()
        script.requests = [.success(true)]
        let (model, fake, _) = await setup(script)
        await model.load()
        #expect(model.phase == .neverReported)
        await fake.add { $0.locations[ali.id] = [.success(fixAt())] }

        await model.requestFix()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
    }

    @Test func aRateLimitSaysWhenToTryAgain() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.failure(.server(status: 429, error: ApiError(code: .rateLimited, retryAfterSeconds: 30)))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .failed(.rateLimited(seconds: 30)))
    }

    @Test func aStaleRequestMessageDoesNotOutliveTheScreen() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.success(false), .failure(.server(status: 429, error: ApiError(code: .rateLimited, retryAfterSeconds: 30)))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.requestFix()
        #expect(model.request == .unreachable)
        model.cancelRequest()
        #expect(model.request == .idle)

        await model.requestFix()
        #expect(model.request == .failed(.rateLimited(seconds: 30)))
        model.cancelRequest()
        #expect(model.request == .idle)
    }

    @Test(.timeLimit(.minutes(1)))
    func twoTapsAskOnce() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        let (model, fake, _) = await setup(script, pause: { _ in await gate.pause() })
        await model.load()

        let first = Task { await model.requestFix() }
        await gate.untilPaused()
        await model.requestFix()
        #expect(model.request == .waiting)
        await fake.add { $0.locations[ali.id] = [.success(fixAt(minutesAfter: 1))] }
        await gate.release()
        await first.value

        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
        #expect(model.snapshot == fixAt(minutesAfter: 1))
    }

    // Review Focus 1.
    @Test(.timeLimit(.minutes(1)))
    func aWaitForAnotherChildNeverLandsOnScreen() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(fixAt(minutesAfter: 5, latitude: 40.0))]
        script.locations[vali.id] = [.success(fixAt(latitude: 39.6, longitude: 66.9))]
        let (model, fake, _) = await setup(script, children: [ali, vali], pause: { _ in await gate.pause() })
        await model.load()

        let wait = Task { await model.requestFix() }
        await gate.untilPaused()
        model.selectedChildId = vali.id
        await model.load()
        await gate.release()
        await wait.value

        #expect(model.childId == vali.id)
        #expect(model.snapshot == fixAt(latitude: 39.6, longitude: 66.9))
        #expect(model.request == .idle)
        let aliLocations = zip(await fake.calls, await fake.childIds).filter { $0.0 == "location" && $0.1 == ali.id }.count
        #expect(aliLocations == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func closingTheScreenStopsTheWait() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(fixAt(minutesAfter: 5, latitude: 40.0))]
        let (model, fake, _) = await setup(script, pause: { _ in await gate.pause() })
        await model.load()

        model.startRequest()
        await gate.untilPaused()
        #expect(model.request == .waiting)
        model.cancelRequest()
        #expect(model.request == .idle)
        let before = await fake.calls
        await gate.release()
        // Let the cancelled task run to its end.
        for _ in 0..<20 { await Task.yield() }

        #expect(model.request == .idle)
        #expect(await fake.calls == before)
        #expect(model.snapshot == fixAt())
    }

    @Test func anOlderAnswerDoesNotReplaceANewerFix() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt(minutesAfter: 5)), .success(fixAt())]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.load()

        #expect(model.snapshot == fixAt(minutesAfter: 5))
        #expect(model.phase == .ready)
    }

    @Test func aFreePlanFoundWhileAskingLocksTheScreen() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.phase == .locked)
        #expect(model.request == .idle)
    }

    @Test func goingOfflineClearsAMessageAndAMessageClearsOffline() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .failure(.unexpectedStatus(500)), .failure(offline), .failure(.unexpectedStatus(500))]
        let (model, _, _) = await setup(script)
        await model.load()
        await model.load()
        #expect(model.inlineMessage == .serverProblem)

        await model.load()
        #expect(model.isOffline)
        #expect(model.inlineMessage == nil)

        await model.load()
        #expect(!model.isOffline)
        #expect(model.inlineMessage == .serverProblem)
    }

    @Test func newerMeansALaterFixOrALaterReason() {
        #expect(LocationModel.isNewer(fixAt(), than: nil))
        #expect(!LocationModel.isNewer(LocationSnapshot(isStale: true), than: nil))
        #expect(LocationModel.isNewer(fixAt(minutesAfter: 1), than: fixAt()))
        #expect(!LocationModel.isNewer(fixAt(), than: fixAt(minutesAfter: 1)))
        #expect(LocationModel.isNewer(reasonAt(minutesAfter: 1), than: reasonAt(minutesAfter: 0)))
        #expect(!LocationModel.isNewer(reasonAt(minutesAfter: 0), than: reasonAt(minutesAfter: 0)))
        #expect(LocationModel.isNewer(reasonAt(minutesAfter: -5), than: fixAt()))
    }
}
