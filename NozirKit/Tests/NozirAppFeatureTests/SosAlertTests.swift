import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let childId = UUID()
private let now = Date(timeIntervalSince1970: 1_791_200_000)

private func sos(name: String?, minutesAgo: Double = 5) -> ActiveSos {
    ActiveSos(sosId: UUID(), childId: childId, childName: name, triggeredAt: now.addingTimeInterval(-minutesAgo * 60))
}

@Suite struct SosAlertTests {
    private let l10n = L10n(.uz)

    @Test func theAlarmSaysWhoAndWhen() {
        let alert = SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil)

        #expect(alert.title(l10n) == l10n.homeSosBannerTitleNamed("Ali"))
        #expect(alert.when(now: now, l10n) == l10n.homeSosBannerBodyWhen("5 daqiqa oldin"))
    }

    // Review Focus 5.
    @Test func aNamelessSosTakesTheNameFromTheFamily() {
        let child = makeChild("Vali", id: childId, phone: "+998901234567")

        let alert = SosAlert(sos(name: nil), child: child, emergencyNumber: nil)

        #expect(alert.childName == "Vali")
        #expect(alert.title(l10n) == l10n.homeSosBannerTitleNamed("Vali"))
        #expect(alert.callChildTitle(l10n) == l10n.sosActionCallChild("Vali"))
    }

    @Test func aBlankNameIsNoName() {
        let alert = SosAlert(sos(name: "  "), child: nil, emergencyNumber: nil)

        #expect(alert.childName == nil)
        #expect(alert.title(l10n) == l10n.homeSosBannerTitle)
        #expect(alert.callChildTitle(l10n) == l10n.sosActionCallChildUnnamed)
    }

    @Test func aChildWithANumberIsCalledOnIt() {
        let alert = SosAlert(sos(name: "Ali"), child: makeChild("Ali", id: childId, phone: "+998901234567"), emergencyNumber: nil)

        #expect(alert.childCallURL == URL(string: "tel:+998901234567"))
    }

    // Review Focus 5.
    @Test func aChildWithoutANumberCannotBeCalled() {
        #expect(SosAlert(sos(name: "Ali"), child: makeChild("Ali", id: childId, phone: nil), emergencyNumber: nil).childCallURL == nil)
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil).childCallURL == nil)
    }

    @Test func theEmergencyNumberComesFromTheConfig() {
        let alert = SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: "112")

        #expect(alert.emergencyTitle(l10n) == l10n.sosActionCallEmergency("112"))
        #expect(alert.emergencyCallURL == URL(string: "tel:112"))
    }

    @Test func noEmergencyNumberNoButton() {
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil).emergencyTitle(l10n) == nil)
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: "").emergencyCallURL == nil)
    }
}
