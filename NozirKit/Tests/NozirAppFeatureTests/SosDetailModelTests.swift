import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let sosId = UUID()
private let childId = UUID()
private let triggered = Date(timeIntervalSince1970: 1_791_300_000)

private let seed = ActiveSos(sosId: sosId, childId: childId, childName: "Ali", triggeredAt: triggered)

private func detail(
    status: SosStatus = .active,
    name: String? = "Ali",
    phone: String? = "+998901234567",
    hasLocation: Bool = true,
    latitude: Double = 41.3111,
    longitude: Double = 69.2797,
    acknowledgedAt: Date? = nil
) -> SosAlertDetail {
    SosAlertDetail(
        id: sosId,
        childId: childId,
        childName: name,
        childPhoneE164: phone,
        triggeredAt: triggered,
        status: status,
        batteryPercent: 31,
        deviceOnline: true,
        latitude: hasLocation ? latitude : nil,
        longitude: hasLocation ? longitude : nil,
        accuracyMeters: 12,
        locationFixAt: hasLocation ? triggered : nil,
        acknowledgedAt: acknowledgedAt
    )
}

@MainActor
private func setup(_ script: FakeLocation.Script, child: Child? = nil) -> (SosDetailModel, FakeLocation) {
    let fake = FakeLocation(script)
    return (SosDetailModel(seed: seed, child: child, emergencyNumber: "112", location: fake), fake)
}

@MainActor
@Suite struct SosDetailModelTests {
    private let l10n = L10n(.uz)

    @Test func theBannersWordsShowBeforeTheDetailArrives() {
        let (model, _) = setup(FakeLocation.Script())

        #expect(model.phase == .loading)
        #expect(model.childName == "Ali")
        #expect(model.triggeredAt == triggered)
        #expect(!model.canAcknowledge)
    }

    @Test func theDetailFillsTheScreen() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.detail == detail())
        #expect(model.canAcknowledge)
        #expect(model.call.childCallURL == URL(string: "tel:+998901234567"))
        #expect(model.call.emergencyCallURL == URL(string: "tel:112"))
        #expect(model.directionsURL == URL(string: "https://maps.apple.com/?daddr=41.311100,69.279700"))
    }

    @Test func anAlarmThatIsGoneIsNotAnError() async {
        var script = FakeLocation.Script()
        script.sos = [.failure(notFound)]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
    }

    @Test func aFailureWithNothingShownCanBeRetried() async {
        var script = FakeLocation.Script()
        script.sos = [.failure(.unexpectedStatus(500)), .success(detail())]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    @Test func goingOfflineKeepsTheAlarmOnScreen() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail()), .failure(offline)]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.detail == detail())
        #expect(model.isOffline)
    }

    @Test func acknowledgingSettlesTheAlarm() async {
        var script = FakeLocation.Script()
        let seenAt = triggered.addingTimeInterval(120)
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged, acknowledgedAt: seenAt))]
        let (model, fake) = setup(script)
        await model.load()

        await model.acknowledge()

        #expect(model.detail?.status == .acknowledged)
        #expect(!model.canAcknowledge)
        #expect(await fake.calls == ["sos", "acknowledge"])
    }

    // Review Focus 5: the second tap lands while the first is still in flight.
    @Test(.timeLimit(.minutes(1)))
    func twoTapsAcknowledgeOnce() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged))]
        script.acknowledgeGate = gate
        let (model, fake) = setup(script)
        await model.load()

        let first = Task { await model.acknowledge() }
        await gate.untilPaused()
        #expect(model.isAcknowledging)
        await model.acknowledge()
        #expect(await fake.calls.filter { $0 == "acknowledge" }.count == 1)

        await gate.release()
        await first.value
        #expect(model.detail?.status == .acknowledged)
        #expect(await fake.calls.filter { $0 == "acknowledge" }.count == 1)
    }

    // Review Focus 5.
    @Test(.timeLimit(.minutes(1)))
    func aFailedAcknowledgeCanBeRetried() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.failure(offline), .success(detail(status: .acknowledged))]
        let (model, fake) = setup(script)
        await model.load()

        await model.acknowledge()
        #expect(model.acknowledgeFailed)
        #expect(model.canAcknowledge)

        await model.acknowledge()
        #expect(!model.acknowledgeFailed)
        #expect(model.detail?.status == .acknowledged)
        #expect(await fake.calls.filter { $0 == "acknowledge" }.count == 2)
    }

    @Test(arguments: [SosStatus.acknowledged, .cancelledByChild, .resolved, .unknown])
    func aSettledOrUnknownAlarmOffersNoAcknowledge(status: SosStatus) async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(status: status))]
        let (model, fake) = setup(script)
        await model.load()

        await model.acknowledge()

        #expect(!model.canAcknowledge)
        #expect(await fake.calls.contains("acknowledge") == false)
    }

    @Test func withoutTheAlarmsNumberTheFamilyListIsUsed() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(phone: nil))]
        let (model, _) = setup(script, child: makeChild("Ali", id: childId, phone: "+998907654321"))

        await model.load()

        #expect(model.call.childCallURL == URL(string: "tel:+998907654321"))
    }

    @Test func noNumberAnywhereCannotBeCalled() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(phone: nil))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.call.childCallURL == nil)
        #expect(model.call.callChildTitle(l10n) == l10n.sosActionCallChild("Ali"))
    }

    @Test func noPositionNoDirections() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(hasLocation: false))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.directionsURL == nil)
    }

    @Test func theAlarmsNameWinsOverTheBanners() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(name: "Alijon"))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.childName == "Alijon")
    }

    @Test func fixedPrecisionKeepsTheDirectionsFreeOfExponents() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(latitude: 0.00001, longitude: 69.2797))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.directionsURL == URL(string: "https://maps.apple.com/?daddr=0.000010,69.279700"))
    }

    @Test func aBlankConfiguredNumberFallsBackToTheCompiledOne() {
        #expect(SosDetailModel.dialNumber(configured: nil, fallback: "112") == "112")
        #expect(SosDetailModel.dialNumber(configured: "", fallback: "112") == "112")
        #expect(SosDetailModel.dialNumber(configured: "  \n", fallback: "112") == "112")
        #expect(SosDetailModel.dialNumber(configured: " 103 ", fallback: "112") == "103")
    }

    @Test(.timeLimit(.minutes(1)))
    func aLateOlderAnswerDoesNotUndoAcknowledge() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add {
            $0.sos = [.success(detail())]
            $0.sosGate = gate
        }

        let late = Task { await model.load() }
        await gate.untilPaused()
        await model.acknowledge()
        await gate.release()
        await late.value

        #expect(model.detail?.status == .acknowledged)
        #expect(!model.canAcknowledge)
    }

    @Test(.timeLimit(.minutes(1)))
    func aLateFailureAfterAcknowledgeIsNotOffline() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add {
            $0.sos = [.failure(offline)]
            $0.sosGate = gate
        }

        let late = Task { await model.load() }
        await gate.untilPaused()
        await model.acknowledge()
        await gate.release()
        await late.value

        #expect(!model.isOffline)
        #expect(model.detail?.status == .acknowledged)
    }

    @Test(.timeLimit(.minutes(1)))
    func aFailedAcknowledgeDoesNotDiscardARefreshInFlight() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.failure(offline)]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add {
            $0.sos = [.success(detail(status: .resolved))]
            $0.sosGate = gate
        }

        let refresh = Task { await model.load() }
        await gate.untilPaused()
        await model.acknowledge()
        #expect(model.acknowledgeFailed)
        await gate.release()
        await refresh.value

        #expect(model.detail?.status == .resolved)
    }

    @Test func anAlarmThatEndsUnderAShownDetailSaysSoAndStopsAcknowledging() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail()), .failure(notFound)]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.detail == detail())
        #expect(model.isGone)
        #expect(!model.canAcknowledge)
    }
}
