import Foundation
import Testing
import NozirConfig
@testable import NozirAppFeature

private func serverConfig(days: Int?, policy: String) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: false,
        featureFlags: [:],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: policy,
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support",
        dataDeletionDelayDays: days
    )
}

@Suite struct PrivacyConfigTests {
    @Test func theWaitAndThePolicyAreTheServers() {
        let config = PrivacyConfig(serverConfig(days: 7, policy: "https://nozir.syncoder.uz/privacy"))

        #expect(config == PrivacyConfig(deletionDelayDays: 7, policyURL: URL(string: "https://nozir.syncoder.uz/privacy")))
    }

    @Test func noConfigNamesNothing() {
        #expect(PrivacyConfig(nil) == .absent)
    }

    // Review Focus 5: a wait that is not a wait is not stated.
    @Test(arguments: [0, -3])
    func aWaitOfNoDaysIsNotNamed(days: Int) {
        #expect(PrivacyConfig(serverConfig(days: days, policy: "https://nozir.syncoder.uz/privacy")).deletionDelayDays == nil)
    }

    @Test func anOlderServerWithoutTheWaitNamesNoNumber() {
        #expect(PrivacyConfig(serverConfig(days: nil, policy: "https://nozir.syncoder.uz/privacy")).deletionDelayDays == nil)
    }

    // Review Focus 5: a link that opens nothing is worse than no link.
    @Test(arguments: ["", "   ", "nozir.syncoder.uz/privacy", "mailto:privacy@nozir.uz", "https://"])
    func aPolicyThatIsNotAWebPageHasNoRow(policy: String) {
        #expect(PrivacyConfig(serverConfig(days: 7, policy: policy)).policyURL == nil)
    }

    @Test func aPolicyWithSpacesAroundItIsStillALink() {
        let config = PrivacyConfig(serverConfig(days: 7, policy: "  https://nozir.syncoder.uz/privacy \n"))

        #expect(config.policyURL == URL(string: "https://nozir.syncoder.uz/privacy"))
    }
}
