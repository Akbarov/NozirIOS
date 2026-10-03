import Foundation
import Testing
@testable import NozirAuth

private let sample = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969.123456),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

// The keychain is shared by the whole test process: one test at a time, each
// on a service name nothing else uses.
//
// Disabled: a package test bundle has no app host, so the keychain answers
// errSecMissingEntitlement (-34018) on the simulator. Keychain behaviour is
// verified by hand in Task 13 (relaunching the app keeps the parent signed in).
@Suite(.serialized, .disabled("needs an app host: errSecMissingEntitlement (-34018)"))
struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "tut.mobile.nozirparent.tests.\(UUID().uuidString)")

    @Test func anEmptyKeychainHasNoSession() {
        #expect(store.load() == nil)
    }

    @Test func whatIsSavedIsReadBackExactly() throws {
        defer { store.clear() }
        try store.save(sample)
        #expect(store.load() == sample)
    }

    @Test func savingAgainReplacesTheOldPair() throws {
        defer { store.clear() }
        try store.save(sample)
        let rotated = TokenPair(
            accessToken: "acc-2",
            accessTokenExpiresAt: sample.accessTokenExpiresAt.addingTimeInterval(900),
            refreshToken: "ref-2",
            refreshTokenExpiresAt: sample.refreshTokenExpiresAt
        )
        try store.save(rotated)
        #expect(store.load() == rotated)
    }

    @Test func clearRemovesTheSession() throws {
        try store.save(sample)
        store.clear()
        #expect(store.load() == nil)
    }
}

@Suite struct InMemoryTokenStoreTests {
    @Test func savesLoadsAndClears() throws {
        let store = InMemoryTokenStore()
        try store.save(sample)
        #expect(store.load() == sample)
        store.clear()
        #expect(store.load() == nil)
    }
}
