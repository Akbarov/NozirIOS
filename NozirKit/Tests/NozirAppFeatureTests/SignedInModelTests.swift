import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private actor SentLocales {
    private(set) var values: [String] = []

    func record(_ locale: String) {
        values.append(locale)
    }
}

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales()
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        signOut: {}
    )
    return (model, fake)
}

@MainActor
@Suite struct SignedInModelTests {
    @Test func anEmptyFamilyGoesStraightToAddingAChild() async {
        var script = FakeFamily.Script()
        script.children = [.success([])]
        let (model, _) = setup(script)

        await model.start()

        #expect(model.isAddingChild)
    }

    @Test func aFamilyWithChildrenStaysHome() async {
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, _) = setup(script)

        await model.start()

        #expect(!model.isAddingChild)
        #expect(model.tab == .home)
    }

    @Test func aListThatCannotBeLoadedDoesNotTrapTheParentAndIsAskedAgain() async {
        var script = FakeFamily.Script()
        script.children = [.failure(offline), .success([])]
        let (model, _) = setup(script)

        await model.start()
        #expect(!model.isAddingChild)

        await model.start()
        #expect(model.isAddingChild)
    }

    @Test func startingTwiceAsksOnce() async {
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, fake) = setup(script)

        await model.start()
        await model.start()

        #expect(await fake.calls == ["children"])
    }

    @Test func aLanguageTheServerMissedIsSentOnStart() async {
        let defaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!
        defaults.set("ru", forKey: "nozir.appLanguage")
        defaults.set(true, forKey: LocaleSync.unsentKey)
        let sent = SentLocales()
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, _) = setup(script, defaults: defaults, sent: sent)

        await model.start()

        #expect(await sent.values == ["ru"])
    }

    @Test func theAddFlowOpensAndCloses() {
        let (model, _) = setup(FakeFamily.Script())

        model.presentAddChild()
        #expect(model.isAddingChild)
        model.tab = .profile
        model.finishAddChild()
        #expect(!model.isAddingChild)
        #expect(model.tab == .home)
    }
}
