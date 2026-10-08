import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let notYourChild = ApiFailure.server(status: 403, error: ApiError(code: .notYourChild))

/// Overlay never turned on, battery skipped, autostart switched itself off; usage access works.
private let fourKinds = protectionStatus(childId: childId, level: .broken, permissions: [
    protectionPermission(.usageAccess, .granted),
    protectionPermission(.overlay),
    protectionPermission(.battery, .skipped),
    protectionPermission(.oemAutostart, revoked: true, key: "oem.xiaomi.autostart"),
])

private let allWorking = protectionStatus(childId: childId, level: .healthy, permissions: [
    protectionPermission(.usageAccess, .granted),
    protectionPermission(.oemAutostart, .granted),
])

@MainActor
private func setup(_ script: FakeProtection.Script, name: String? = "Ali") -> (ProtectionModel, FakeProtection) {
    let fake = FakeProtection(script)
    return (ProtectionModel(childId: childId, childName: name, service: fake), fake)
}

@MainActor
@Suite struct ProtectionModelTests {
    @Test func theStatusIsLoaded() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.status == fourKinds)
        #expect(model.kindsToFix == [.overlay, .battery, .oemAutostart])
        #expect(model.childName == "Ali")
        #expect(await fake.calls == ["status"])
    }

    // Review Focus 3 (P1): a removed child is an answer, not a fault.
    @Test(arguments: [notFound, notYourChild])
    func aChildNoLongerInTheFamilyIsMissing(failure: ApiFailure) async {
        var script = FakeProtection.Script()
        script.status = [.failure(failure)]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(model.status == nil)
        #expect(model.toast == nil)
        #expect(model.kindsToFix.isEmpty)
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeProtection.Script()
        script.status = [.failure(.unexpectedStatus(500)), .success(fourKinds)]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    // Spec §4.2: offline (no connection or a timeout) keeps what is on screen.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func goingOfflineKeepsTheStatusOnScreen(failure: ApiFailure) async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .failure(failure), .success(allWorking)]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.status == fourKinds)
        #expect(model.isOffline)
        #expect(model.toast == nil)

        await model.load()
        #expect(!model.isOffline)
        #expect(model.status == allWorking)
        #expect(model.kindsToFix.isEmpty)
    }

    // A server fault over a shown status is not "offline".
    @Test func aServerFaultOverAShownStatusIsSaidNotCalledOffline() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(!model.isOffline)
        #expect(model.toast == .serverProblem)
        #expect(model.status == fourKinds)
        #expect(model.phase == .ready)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var script = FakeProtection.Script()
        script.status = [.success(allWorking), .success(fourKinds)]
        script.statusGate = gate
        let (model, _) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.status == fourKinds)
    }

    // Review Focus 1 and 4 (D3): every kind not granted, in the server's order, once.
    @Test func sendingSendsEveryKindNotGranted() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.success(())]
        let (model, fake) = setup(script)
        await model.load()

        await model.sendInstructions()

        #expect(await fake.sent == [[.overlay, .battery, .oemAutostart]])
        #expect(model.wereInstructionsSent)
        #expect(!model.isSending)
        #expect(model.toast == nil)
    }

    // Review Focus 4: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSendOnce() async {
        let gate = PauseGate()
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.success(())]
        script.sendGate = gate
        let (model, fake) = setup(script)
        await model.load()

        let first = Task { await model.sendInstructions() }
        await gate.untilPaused()
        #expect(model.isSending)
        await model.sendInstructions()

        await gate.release()
        await first.value
        #expect(await fake.sent.count == 1)
        #expect(model.wereInstructionsSent)
        #expect(!model.isSending)
    }

    // Review Focus 4: said once, nothing claimed, and the button works again.
    @Test func aFailedSendIsSaidOnceAndCanBeTriedAgain() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.failure(offline), .success(())]
        let (model, fake) = setup(script)
        await model.load()

        await model.sendInstructions()
        #expect(model.toast == .noConnection)
        #expect(!model.wereInstructionsSent)
        #expect(!model.isSending)
        #expect(await fake.sent.count == 1)

        model.toast = nil
        await model.sendInstructions()
        #expect(await fake.sent.count == 2)
        #expect(model.wereInstructionsSent)
        #expect(model.toast == nil)
    }

    @Test func nothingToFixOrNothingLoadedSendsNothing() async {
        var script = FakeProtection.Script()
        script.status = [.success(allWorking)]
        let (model, fake) = setup(script)

        await model.sendInstructions()
        await model.load()
        await model.sendInstructions()

        #expect(await fake.calls == ["status"])
        #expect(!model.wereInstructionsSent)
    }

    // Spec §4.2: "sent" lasts the screen's life, through a refresh.
    @Test func aRefreshKeepsTheSentNote() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .success(fourKinds)]
        script.send = [.success(())]
        let (model, _) = setup(script)
        await model.load()
        await model.sendInstructions()

        await model.load()

        #expect(model.wereInstructionsSent)
    }
}
