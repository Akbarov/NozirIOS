import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation
import NozirPrivacy
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
    sent: SentLocales = SentLocales(),
    insights: FakeInsights = FakeInsights(),
    extraTime: FakeExtraTime = FakeExtraTime(),
    protection: FakeProtection = FakeProtection(),
    notifications: FakeNotifications = FakeNotifications(),
    privacy: FakePrivacy = FakePrivacy(),
    privacyConfig: PrivacyConfig = .absent,
    signOutLocally: @escaping @MainActor () -> Void = {}
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        insights: insights,
        extraTime: extraTime,
        protection: protection,
        notifications: notifications,
        location: FakeLocation(),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        emergencyNumber: { "112" },
        privacy: privacy,
        privacyConfig: { privacyConfig },
        signOutLocally: signOutLocally,
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

    // P20: the screen gets the config of the moment it opens, and a recorded
    // request ends the session here without the server's logout.
    @Test func thePrivacyScreenReadsTheConfigAndEndsTheSessionLocally() async {
        var familyScript = FakeFamily.Script()
        familyScript.me = [.success(ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER"))]
        var privacyScript = FakePrivacy.Script()
        privacyScript.disclosure = [.success(sampleDisclosure)]
        privacyScript.current = [.success(nil)]
        privacyScript.request = [.success(recordedRequest)]
        var endedLocally = 0
        let (model, _) = setup(
            familyScript,
            privacy: FakePrivacy(privacyScript),
            privacyConfig: PrivacyConfig(deletionDelayDays: 7, policyURL: nil),
            signOutLocally: { endedLocally += 1 }
        )
        let privacy = model.makePrivacyModel()

        await privacy.load()
        privacy.startDelete()
        await privacy.confirmDelete()

        #expect(privacy.deleteBody(L10n(.uz)) == L10n(.uz).privacyDeleteBodyWithDays(7))
        #expect(endedLocally == 1)
    }

    // P17 (T1): the screen is for the ask tapped, with that child's minutes from Home.
    @Test func theTimeRequestScreenIsForTheAskTapped() async {
        let id = UUID()
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk(id: id)])]
        let (model, _) = setup(FakeFamily.Script(), extraTime: FakeExtraTime(script))

        let screen = model.makeTimeRequestModel(id: id, usedMinutesToday: 95)
        await screen.load()

        #expect(screen.requestId == id)
        #expect(screen.usedMinutesToday == 95)
        #expect(screen.phase == .ready)
    }

    // P18 (P4): the screen is for the child tapped, named from the family list.
    @Test func theProtectionScreenIsForTheChildTapped() async {
        let ali = makeChild("Ali")
        var family = FakeFamily.Script()
        family.children = [.success([ali])]
        var script = FakeProtection.Script()
        script.status = [.success(protectionStatus(childId: ali.id))]
        let (model, _) = setup(family, protection: FakeProtection(script))
        try? await model.family.refresh()

        let screen = model.makeProtectionModel(childId: ali.id)
        await screen.load()

        #expect(screen.childId == ali.id)
        #expect(screen.childName == "Ali")
        #expect(screen.phase == .ready)
        #expect(model.makeProtectionModel(childId: UUID()).childName == nil)
    }

    // P16 (spec §4.2): the screen reads the session's service.
    @Test func theNotificationsScreenUsesTheSessionsService() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([parentNotification()]))]
        script.preferences = [.success(notificationPreferences())]
        let notifications = FakeNotifications(script)
        let (model, _) = setup(FakeFamily.Script(), notifications: notifications)

        let screen = model.makeNotificationsModel()
        await screen.appear()

        #expect(screen.phase == .ready)
        #expect(screen.items.count == 1)
        #expect(screen.offlineAfterMinutes == 360)
        #expect(await notifications.calls == ["page", "preferences"])
    }

    // P16a (Review Focus 3): Home's and Statistics' calls open what they always
    // opened; a day or a week given is the one opened.
    @Test func theSummaryScreensOpenOnTheDayOrWeekAsked() async {
        let id = UUID()
        let insights = FakeInsights()
        let (model, _) = setup(FakeFamily.Script(), insights: insights)

        await model.makeDailySummaryModel(childId: id, childName: "Ali").load()
        await model.makeDailySummaryModel(childId: id, childName: "Ali", date: day("2026-10-01")).load()

        #expect(await insights.calls == ["daily latest", "daily 2026-10-01"])
        let thisWeek = model.makeWeeklyModel(childId: id)
        #expect(thisWeek.selectedWeek == thisWeek.currentWeek)
        let earlier = thisWeek.currentWeek.adding(days: -14)
        #expect(model.makeWeeklyModel(childId: id, weekStart: earlier.adding(days: 2)).selectedWeek == earlier)
    }

    @Test func anUndatedStepIsTheOldOne() {
        let id = UUID()
        #expect(SignedInView.HomeStep.summary(id, "Ali") == .summary(id, "Ali", date: nil))
        #expect(SignedInView.HomeStep.weekly(id) == .weekly(id, weekStart: nil))
        #expect(SignedInView.HomeStep.summary(id, "Ali") != .summary(id, "Ali", date: day("2026-10-01")))
    }
}
