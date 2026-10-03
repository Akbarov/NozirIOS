import Testing
@testable import NozirNetworking

@Suite struct ClientIdentityTests {
    // Backend ClientVersions.parseVersion reads the text between "/" and the
    // first space, so the version must sit exactly there.
    @Test func headerNamesTheParentAppAndIOS() {
        let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
        #expect(identity.headerValue == "nozir-parent/1.0.0 (ios; 17.5)")
    }
}
