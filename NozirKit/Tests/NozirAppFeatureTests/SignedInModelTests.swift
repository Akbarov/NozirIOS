import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirL10n
import NozirLocation
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
        insights: FakeInsights(),
        location: FakeLocation(),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        emergencyNumber: { "112" },
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

    @Test func closingTheAddFlowReloadsHome() {
        let (model, _) = setup(FakeFamily.Script())
        let before = model.homeRefresh

        model.presentAddChild()
        model.finishAddChild()

        #expect(model.homeRefresh == before + 1)
    }

    @Test func screensShareTheFamilyAndTheEmergencyNumber() {
        let (model, _) = setup(FakeFamily.Script())

        #expect(model.statistics.family === model.family)
        #expect(model.makeHomeModel().family === model.family)
        #expect(model.currentEmergencyNumber == "112")
    }

    @Test func theLocationTabSharesTheFamily() {
        let (model, _) = setup(FakeFamily.Script())

        #expect(model.locationTab.family === model.family)
    }

    @Test func zoneAndTrackingScreensAreForTheChildAsked() {
        let (model, _) = setup(FakeFamily.Script())
        let child = makeChild("Ali")
        let zoneId = UUID()

        let zone = model.makeSafeZoneModel(childId: child.id, zoneId: zoneId)
        #expect(zone.childId == child.id)
        #expect(zone.zoneId == zoneId)
        #expect(zone.isEditing)
        #expect(!model.makeSafeZoneModel(childId: child.id, zoneId: nil).isEditing)
        #expect(model.makeLocationTrackingModel(childId: child.id).childId == child.id)
    }

    @Test func theRulesScreensShareTheHubsSession() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.children = [.success([ali, makeChild("Vali")])]
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        script.bonus = [.success(BonusConfig(ruleVersion: 4, maxDailyBonusMinutes: 30, challenges: []))]
        let (model, fake) = setup(script)
        try? await model.family.refresh()

        let session = model.makeRulesSession(childId: ali.id)

        #expect(session.childId == ali.id)
        #expect(session.childName == "Ali")
        let daily = model.makeDailyLimitModel(session: session)
        let bedtime = model.makeBedtimeModel(session: session)
        let bonus = model.makeBonusModel(session: session)
        let tracking = model.makeLocationTrackingModel(session: session)
        #expect(daily.session === session)
        #expect(bedtime.session === session)
        #expect(bonus.session === session)
        #expect(tracking.childId == ali.id)
        #expect(tracking.childName == "Ali")

        // Behaviour, not identity: once the session has loaded, none of them reads "rules" again.
        await session.load()
        await tracking.load()
        await bedtime.load()
        await daily.load()
        await bonus.load()
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(tracking.tracking != nil)
        #expect(bedtime.bedtime != nil)
    }

    @Test func theAppRuleScreensShareTheHubsSession() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.children = [.success([ali])]
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy("com.roblox.client", name: "Roblox", mode: .dailyLimit, minutes: 30)]))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, fake) = setup(script)
        try? await model.family.refresh()
        let session = model.makeRulesSession(childId: ali.id)

        let list = model.makeAppRulesModel(session: session)
        let editor = model.makeAppRuleModel(session: session, packageId: "org.telegram.messenger", displayName: "Telegram")

        #expect(list.session === session)
        #expect(editor.session === session)
        #expect(editor.packageId == "org.telegram.messenger")
        #expect(editor.displayName == "Telegram")

        // Behaviour, not identity: once the session has loaded, neither reads "rules" again,
        // and the phone's apps are read once however often P11 appears.
        await session.load()
        await list.load()
        await editor.load()
        await list.load()
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
        #expect(list.addableApps == [telegramApp])
        #expect(editor.name == "Telegram")
        #expect(editor.canSave)
    }

    @Test func theProfileHubOpensOnTheFirstChildAndCanSwitch() async {
        let ali = makeChild("Ali")
        let vali = makeChild("Vali")
        var script = FakeFamily.Script()
        script.children = [.success([ali, vali])]
        let (model, _) = setup(script)
        try? await model.family.refresh()

        let hub = model.makeRulesHubModel(childId: nil, picksChild: true)

        #expect(hub.selectedChildId == ali.id)
        #expect(hub.showsSwitcher)
        #expect(hub.dailyLimit?.session === hub.session)
        let aliSession = hub.session

        hub.select(vali.id)

        #expect(hub.selectedChildId == vali.id)
        #expect(hub.session !== aliSession)
        #expect(hub.session?.childId == vali.id)
        #expect(hub.dailyLimit?.session === hub.session)
    }

    @Test func aChildsDetailsHubIsForThatChildOnly() async {
        let vali = makeChild("Vali")
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali"), vali])]
        let (model, _) = setup(script)
        try? await model.family.refresh()

        let hub = model.makeRulesHubModel(childId: vali.id, picksChild: false)

        #expect(hub.selectedChildId == vali.id)
        #expect(!hub.showsSwitcher)
    }

    @Test func theProfileShowsRulesOnlyWithAChild() async {
        var script = FakeFamily.Script()
        script.children = [.success([]), .success([makeChild("Ali")])]
        let (model, _) = setup(script)
        let profile = model.makeProfileModel()

        try? await model.family.refresh()
        #expect(!profile.showsRules)

        try? await model.family.refresh()
        #expect(profile.showsRules)
    }
}
