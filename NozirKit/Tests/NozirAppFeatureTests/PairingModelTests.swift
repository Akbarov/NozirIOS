import Foundation
import Testing
import NozirFamily
@testable import NozirAppFeature

/// Lets `run()` wait a fixed number of times, then cancels it the way a
/// screen that goes away does.
private actor Ticks {
    private var left: Int

    init(_ count: Int) {
        left = count
    }

    func take() throws {
        guard left > 0 else { throw CancellationError() }
        left -= 1
    }
}

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    child: Child = makeChild("Ali"),
    ticks: Int = 0
) -> (PairingModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(child)
    let counter = Ticks(ticks)
    let model = PairingModel(child: child, family: family, pollInterval: .seconds(4), sleep: { _ in try await counter.take() })
    return (model, fake, family)
}

@MainActor
@Suite struct PairingModelTests {
    @Test func aChildWithoutAPhoneGetsACodeAtOnce() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(nil)]
        script.issueCode = [.success(pairingCode("472918"))]
        let (model, fake, _) = setup(script)

        await model.run()

        #expect(model.phase == .waiting(pairingCode("472918")))
        #expect(await fake.calls == ["currentCode", "issueCode"])
    }

    @Test func aLiveCodeIsShownNotReplaced() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode(state: .appInstalled))]
        let (model, fake, _) = setup(script)

        await model.run()

        #expect(model.isAppInstalled)
        #expect(await fake.calls == ["currentCode"])
    }

    @Test func aPairedChildsPhoneIsReplacedOnlyAfterTheParentSaysSo() async {
        let device = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: true)
        var script = FakeFamily.Script()
        script.devices = [.success([device])]
        script.currentCode = [.success(nil)]
        script.issueCode = [.success(pairingCode("111222"))]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))

        await model.run()
        #expect(model.phase == .noCode)
        #expect(model.connectedDevice == device)

        await model.requestNewCode()
        #expect(model.isConfirmingReplacement)
        #expect(await fake.calls == ["devices", "currentCode"])

        await model.confirmReplacement()
        #expect(model.phase == .waiting(pairingCode("111222")))
        #expect(!model.isConfirmingReplacement)
    }

    @Test func dismissingTheQuestionSendsNothing() async {
        let device = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: false)
        var script = FakeFamily.Script()
        script.devices = [.success([device])]
        script.currentCode = [.success(nil)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))
        await model.run()

        await model.requestNewCode()
        model.dismissReplacement()

        #expect(!model.isConfirmingReplacement)
        #expect(await fake.calls == ["devices", "currentCode"])
    }

    // Review Focus 1.
    @Test func aRedeemedCodeIsSeenThroughTheChild() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .success(nil)]
        script.child = [.success(makeChild("Ali", id: ali.id, state: .paired))]
        let (model, _, family) = setup(script, child: ali, ticks: 5)

        await model.run()

        #expect(model.phase == .paired)
        #expect(family.child(ali.id)?.pairingState == .paired)
    }

    @Test func anExpiredCodeOffersANewOne() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .success(nil)]
        script.child = [.success(ali)]
        let (model, _, _) = setup(script, child: ali, ticks: 1)

        await model.run()

        #expect(model.phase == .noCode)
    }

    // Review Focus 3.
    @Test func leavingTheScreenStopsThePolling() async {
        var script = FakeFamily.Script()
        script.currentCode = Array(repeating: .success(pairingCode()), count: 10)
        let (model, fake, _) = setup(script, ticks: 2)

        await model.run()

        #expect(await fake.calls == ["currentCode", "currentCode", "currentCode"])
    }

    @Test func aDroppedConnectionKeepsWaitingAndSaysSo() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .failure(offline)]
        let (model, _, _) = setup(script, ticks: 1)

        await model.run()

        #expect(model.phase == .waiting(pairingCode()))
        #expect(model.message == .noConnection)
    }

    @Test func theNextGoodAnswerClearsTheMessage() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .failure(offline), .success(pairingCode())]
        let (model, _, _) = setup(script, ticks: 2)

        await model.run()

        #expect(model.message == nil)
    }

    @Test func withoutACodeNothingIsPolled() async {
        var script = FakeFamily.Script()
        script.devices = [.success([])]
        script.currentCode = [.success(nil)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired), ticks: 3)

        await model.run()

        #expect(model.phase == .noCode)
        #expect(await fake.calls == ["devices", "currentCode"])
    }

    @Test func aFirstLookThatFailsOffersTheButton() async {
        var script = FakeFamily.Script()
        script.currentCode = [.failure(offline)]
        let (model, _, _) = setup(script)

        await model.run()

        #expect(model.phase == .noCode)
        #expect(model.message == .noConnection)
    }

    private func rePairScript(devicesAfter: [ChildDevice], first: ChildDevice) -> FakeFamily.Script {
        var script = FakeFamily.Script()
        script.devices = [.success([first]), .success(devicesAfter)]
        script.currentCode = [.success(nil), .success(nil)]
        script.issueCode = [.success(pairingCode("111222"))]
        return script
    }

    @Test func aRePairWithTheSamePhoneIsNotPaired() async {
        let d1 = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: true)
        let ali = makeChild("Ali", state: .paired)
        var script = rePairScript(devicesAfter: [d1], first: d1)
        script.child = [.success(ali)]
        let (model, _, _) = setup(script, child: ali, ticks: 1)
        await model.run()
        await model.requestNewCode()
        await model.confirmReplacement()

        await model.run()

        #expect(model.phase == .noCode)
    }

    @Test func aRePairWithANewPhoneIsPaired() async {
        let d1 = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: true)
        let d2 = ChildDevice(id: UUID(), manufacturer: "Samsung", model: "A15", isOnline: true)
        let ali = makeChild("Ali", state: .paired)
        var script = rePairScript(devicesAfter: [d2], first: d1)
        script.child = [.success(ali)]
        let (model, _, _) = setup(script, child: ali, ticks: 1)
        await model.run()
        await model.requestNewCode()
        await model.confirmReplacement()

        await model.run()

        #expect(model.phase == .paired)
        #expect(model.connectedDevice == d2)
    }

    @Test func aPairedChildIsAskedEvenWhenTheDeviceReadFailed() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(nil)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))
        await model.run()

        await model.requestNewCode()

        #expect(model.isConfirmingReplacement)
        #expect(!(await fake.calls).contains("issueCode"))
    }

    @Test func aPairedChildWhosePhoneCouldNotBeReadIsNotGivenACodeBlindly() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(nil)]
        script.devices = [.failure(offline), .failure(offline)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))
        await model.run()

        await model.requestNewCode()
        await model.confirmReplacement()

        #expect(!(await fake.calls).contains("issueCode"))
        #expect(model.message == .noConnection)
        #expect(model.phase == .noCode)
    }

    @Test func aPairedChildWhosePhoneIsReadOnTheSecondTryRecordsItWithTheCode() async {
        let d1 = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: true)
        var script = FakeFamily.Script()
        script.currentCode = [.success(nil)]
        script.devices = [.failure(offline), .success([d1])]
        script.issueCode = [.success(pairingCode("333444"))]
        let (model, _, _) = setup(script, child: makeChild("Ali", state: .paired))
        await model.run()

        await model.requestNewCode()
        await model.confirmReplacement()

        #expect(model.phase == .waiting(pairingCode("333444")))
        #expect(model.connectedDevice == d1)
    }

    @Test func aFirstLookThatWasCancelledLooksAgain() async {
        var script = FakeFamily.Script()
        script.cancelNextCurrentCode = true
        let (model, fake, _) = setup(script)
        await model.run()
        #expect(model.phase == .loading)

        await fake.add { $0.currentCode = [.success(pairingCode())] }
        await model.run()

        #expect(model.phase == .waiting(pairingCode()))
    }
}
