import Foundation
import Testing
@testable import NozirAuth

private let leftover = TokenPair(
    accessToken: "acc-old",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969),
    refreshToken: "ref-old",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "nozir.tests.\(UUID().uuidString)")!
}

// User decision: reinstalling the app signs the parent out. The keychain
// outlives an uninstall; UserDefaults do not.
@Suite struct FreshInstallTests {
    @Test func aSessionFoundOnTheFirstLaunchIsFromAPreviousInstallAndIsDropped() {
        let store = InMemoryTokenStore(leftover)

        FreshInstall.clearSessionLeftByPreviousInstall(store: store, defaults: freshDefaults())

        #expect(store.load() == nil)
    }

    @Test func laterLaunchesKeepTheSession() throws {
        let defaults = freshDefaults()
        let store = InMemoryTokenStore()
        FreshInstall.clearSessionLeftByPreviousInstall(store: store, defaults: defaults)
        try store.save(leftover)

        FreshInstall.clearSessionLeftByPreviousInstall(store: store, defaults: defaults)

        #expect(store.load() == leftover)
    }
}
