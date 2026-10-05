import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

/// Records what reached the server and can refuse it.
private actor LocaleEndpoint {
    private(set) var sent: [String] = []
    private var failures: Int

    init(failing failures: Int = 0) {
        self.failures = failures
    }

    func send(_ locale: String) throws {
        if failures > 0 {
            failures -= 1
            throw offline
        }
        sent.append(locale)
    }
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ProfileModelTests.\(UUID().uuidString)")!
}

@MainActor
@Suite struct LocaleSyncTests {
    @Test func aChoiceTakesEffectAtOnceAndReachesTheServer() async {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
        let endpoint = LocaleEndpoint()
        let sync = LocaleSync(store: store, defaults: defaults, send: { try await endpoint.send($0) })

        await sync.choose(.ru)

        #expect(store.current == .ru)
        #expect(await endpoint.sent == ["ru"])
        #expect(!defaults.bool(forKey: LocaleSync.unsentKey))
    }

    @Test func aChoiceTheServerMissedIsSentOnTheNextStart() async {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
        let offlineEndpoint = LocaleEndpoint(failing: 1)
        await LocaleSync(store: store, defaults: defaults, send: { try await offlineEndpoint.send($0) }).choose(.en)
        #expect(defaults.bool(forKey: LocaleSync.unsentKey))

        let endpoint = LocaleEndpoint()
        await LocaleSync(store: store, defaults: defaults, send: { try await endpoint.send($0) }).resumeIfNeeded()

        #expect(await endpoint.sent == ["en"])
        #expect(!defaults.bool(forKey: LocaleSync.unsentKey))
    }

    @Test func nothingUnsentMeansNothingSent() async {
        let defaults = freshDefaults()
        let endpoint = LocaleEndpoint()
        let sync = LocaleSync(store: LanguageStore(defaults: defaults, preferredLanguages: ["uz"]), defaults: defaults, send: { try await endpoint.send($0) })

        await sync.resumeIfNeeded()

        #expect(await endpoint.sent.isEmpty)
    }
}

@MainActor
private func setup(_ script: FakeFamily.Script, signOut: @escaping @MainActor () async -> Void = {}) -> (ProfileModel, FamilyStore, LanguageStore, AppearanceStore) {
    let defaults = freshDefaults()
    let family = FamilyStore(service: FakeFamily(script))
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let appearance = AppearanceStore(defaults: defaults)
    let sync = LocaleSync(store: language, defaults: defaults, send: { _ in })
    let model = ProfileModel(family: family, language: language, appearance: appearance, localeSync: sync, currentYear: 2026, signOut: signOut)
    return (model, family, language, appearance)
}

@MainActor
@Suite struct ProfileModelTests {
    @Test func loadingReadsTheParentAndTheChildren() async {
        var script = FakeFamily.Script()
        script.me = [.success(ParentProfile(displayName: "Zohid", phoneE164: "+998901234567", locale: "uz"))]
        script.children = [.success([makeChild("Ali", birthYear: 2015)])]
        let (model, family, _, _) = setup(script)

        await model.load()

        #expect(model.displayName(L10n(.uz)) == "Zohid")
        #expect(model.phone == "+998 90 123 45 67")
        #expect(family.children.map(\.displayName) == ["Ali"])
        #expect(model.age(of: family.children[0]) == 11)
        #expect(model.message == nil)
    }

    @Test func aParentWithoutANameIsCalledParent() async {
        var script = FakeFamily.Script()
        script.me = [.success(ParentProfile(displayName: "  ", phoneE164: nil, locale: "uz"))]
        let (model, _, _, _) = setup(script)

        await model.load()

        #expect(model.displayName(L10n(.uz)) == L10n(.uz).profileNoName)
        #expect(model.phone == nil)
    }

    @Test func aListThatCannotBeLoadedSaysSo() async {
        let (model, _, _, _) = setup(FakeFamily.Script())

        await model.load()

        #expect(model.message == .noConnection)
    }

    @Test func languageAndThemeAreTheParentsChoice() async {
        let (model, _, language, appearance) = setup(FakeFamily.Script())

        await model.choose(AppLanguage.en)
        model.choose(AppearanceMode.dark)

        #expect(language.current == .en)
        #expect(appearance.mode == .dark)
    }

    @Test func signingOutRunsOnce() async {
        var count = 0
        let (model, _, _, _) = setup(FakeFamily.Script(), signOut: { count += 1 })

        await model.signOut()

        #expect(count == 1)
    }

    @Test func eachPairingStateHasItsLabel() {
        let l10n = L10n(.uz)
        let expected: [(PairingState, String, NozirStatusLevel)] = [
            (.paired, l10n.profileChildStatePaired, .good),
            (.appInstalled, l10n.profileChildStateAppInstalled, .attention),
            (.codeIssued, l10n.profileChildStateCodeIssued, .attention),
            (.notPaired, l10n.profileChildStateNotPaired, .action),
        ]
        for (state, label, level) in expected {
            let status = ProfileModel.status(of: state, l10n)
            #expect(status.label == label)
            #expect(status.level == level)
        }
    }
}
