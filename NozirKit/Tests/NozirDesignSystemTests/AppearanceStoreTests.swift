import Foundation
import SwiftUI
import Testing
@testable import NozirDesignSystem

@MainActor
@Suite struct AppearanceStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceStoreTests.\(UUID().uuidString)")!
    }

    @Test func aNewInstallFollowsThePhone() {
        let store = AppearanceStore(defaults: freshDefaults())

        #expect(store.mode == .system)
        #expect(store.mode.colorScheme == nil)
    }

    @Test func aChoiceIsRemembered() {
        let defaults = freshDefaults()
        AppearanceStore(defaults: defaults).set(.dark)

        let again = AppearanceStore(defaults: defaults)

        #expect(again.mode == .dark)
        #expect(again.mode.colorScheme == .dark)
    }

    @Test func lightMeansLight() {
        #expect(AppearanceMode.light.colorScheme == .light)
    }
}
