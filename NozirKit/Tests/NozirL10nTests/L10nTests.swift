import Foundation
import Testing
@testable import NozirL10n

@Suite struct L10nTests {
    @Test func aStringFollowsTheLanguage() {
        #expect(L10n(.uz).welcomeTitle == "Bolangizning telefonini kuzatmang")
        #expect(L10n(.ru).welcomeTitle == "Не следите за телефоном ребёнка")
        #expect(L10n(.en).welcomeTitle == "Don't watch your child's phone")
    }

    @Test func argumentsLandWhereEachTranslationPutsThem() {
        #expect(L10n(.uz).addChildAgeMode(9, "Yulduzcha") == "9 yosh — «Yulduzcha» rejimi")
        #expect(L10n(.en).addChildAgeMode(9, "Star") == "9 years old — “Star” mode")
    }

    @Test func aPaddedNumberKeepsItsZero() {
        #expect(L10n(.uz).durationShortHoursMinutes(2, 5) == "2s 05d")
    }

    @Test func aStringWithoutATranslationIsUzbek() {
        #expect(L10n(.en).phoneFieldPrefix == "🇺🇿 +998")
    }

    @Test func anIOSStringReplacesTheAndroidOne() {
        #expect(L10n(.uz).updateRequiredStoreMissing.contains("App Store"))
        #expect(L10n(.en).dataErrorNotAuthenticated.contains("Telegram"))
        #expect(L10n(.ru).bedtimeDaysSeparator == ", ")
    }

    @Test func weekdaysStartOnMonday() {
        #expect(L10n(.uz).weekdayNamesShort == ["Du", "Se", "Ch", "Pa", "Ju", "Sh", "Ya"])
    }
}

@MainActor
@Suite struct LanguageStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LanguageStoreTests.\(UUID().uuidString)")!
    }

    @Test func aSavedChoiceWins() {
        let defaults = freshDefaults()
        defaults.set("ru", forKey: LanguageStore.key)

        let store = LanguageStore(defaults: defaults, preferredLanguages: ["en-US"])

        #expect(store.current == .ru)
    }

    @Test func withoutAChoiceThePhonesFirstLanguageIsUsed() {
        let store = LanguageStore(defaults: freshDefaults(), preferredLanguages: ["ru-UZ", "en-US"])

        #expect(store.current == .ru)
    }

    @Test func aFirstLanguageNozirDoesNotSpeakMeansUzbek() {
        let store = LanguageStore(defaults: freshDefaults(), preferredLanguages: ["de-DE", "en-US"])

        #expect(store.current == .uz)
    }

    @Test func choosingChangesTheTextAndIsRemembered() {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz-UZ"])

        store.set(.en)

        #expect(store.l10n.welcomeTitle == "Don't watch your child's phone")
        #expect(LanguageStore(defaults: defaults, preferredLanguages: ["ru"]).current == .en)
    }
}
