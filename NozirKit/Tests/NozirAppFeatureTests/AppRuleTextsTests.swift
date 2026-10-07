import Foundation
import Testing
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private let l10n = L10n(.uz)

@MainActor
@Suite struct AppRuleTextsTests {
    @Test func anAppIsCalledByItsLabelOrABetterNameThanItsId() {
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: "Roblox Beta") == "Roblox Beta")
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: nil) == "Roblox")
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: "com.roblox.client") == "Roblox")
        #expect(AppRuleTexts.name(packageId: "uz.payme.app", displayName: "  ") == "Payme")
        #expect(AppRuleTexts.name(telegramApp) == "Telegram")
    }

    @Test func eachModeHasItsLine() {
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .unrestricted), l10n) == l10n.appRuleNone)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .alwaysBlocked), l10n) == l10n.appRuleAlways)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .dailyLimit, minutes: 45), l10n) == l10n.appRuleDailyLimit(Durations.short(45, l10n)))
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .scheduleBlock, windows: [schoolHours]), l10n) == l10n.appRuleSchedule("08:00", "13:00"))
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .scheduleBlock), l10n) == l10n.appRuleNone)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .unknown("FOCUS_ONLY")), l10n) == nil)
    }

    @Test func onlyRulesThatCloseTheAppAreAccented() {
        #expect(AppRuleTexts.closesTheApp(appPolicy("a", mode: .scheduleBlock, windows: [schoolHours])))
        #expect(AppRuleTexts.closesTheApp(appPolicy("a", mode: .alwaysBlocked)))
        #expect(!AppRuleTexts.closesTheApp(appPolicy("a", mode: .scheduleBlock)))
        #expect(!AppRuleTexts.closesTheApp(appPolicy("a", mode: .dailyLimit, minutes: 30)))
        #expect(!AppRuleTexts.closesTheApp(appPolicy("a", mode: .unrestricted)))
    }

    @Test func theHubCountsRulesButNotNoLimit() {
        let free = [appPolicy("a", mode: .unrestricted)]
        let some = free + [
            appPolicy("b", mode: .dailyLimit, minutes: 30),
            appPolicy("c", mode: .alwaysBlocked),
            appPolicy("d", mode: .unknown("FOCUS_ONLY")),
        ]

        #expect(AppRuleTexts.hubRow([], l10n) == l10n.rulesLinkAppsNone)
        #expect(AppRuleTexts.hubRow(free, l10n) == l10n.rulesLinkAppsNone)
        #expect(AppRuleTexts.hubRow(some, l10n) == l10n.rulesLinkAppsCount(3))
    }

    @Test func theModesHaveTheirLabels() {
        #expect(AppRuleTexts.modeLabel(.unrestricted, l10n) == l10n.appRuleModeNone)
        #expect(AppRuleTexts.modeLabel(.dailyLimit, l10n) == l10n.appRuleModeDailyLimit)
        #expect(AppRuleTexts.modeLabel(.scheduleBlock, l10n) == l10n.appRuleModeSchedule)
        #expect(AppRuleTexts.modeLabel(.alwaysBlocked, l10n) == l10n.appRuleAlways)
    }

    @Test func anUnknownModeNeverShowsTheServersRawName() {
        let label = AppRuleTexts.modeLabel(.unknown("FOCUS_ONLY"), l10n)

        #expect(label == l10n.appRuleNone)
        #expect(!label.contains("FOCUS_ONLY"))
    }

    @Test func searchFoldsCaseSpacesAndUzbekApostrophes() {
        #expect(AppSearch.key("  O\u{02BB}QUV ") == "o'quv")
        #expect(AppSearch.key("O\u{2019}quv") == "o'quv")
        #expect(AppSearch.key("o`quv") == "o'quv")
        #expect(AppSearch.key("o\u{02BC}quv") == "o'quv")
        let oquv = InstalledApp(packageId: "uz.oquv.app", displayName: "O\u{02BB}quv markazi")

        #expect(AppSearch.matching([oquv, robloxApp], "o'QUV") == [oquv])
    }

    @Test func searchFindsTheMiddleOfANameItsFriendlyNameAndThePackage() {
        let brawl = InstalledApp(packageId: "com.supercell.brawlstars", displayName: nil)
        let apps = [robloxApp, telegramApp, brawl]

        #expect(AppSearch.matching(apps, "gram") == [telegramApp])
        #expect(AppSearch.matching(apps, "Brawl S") == [brawl])
        #expect(AppSearch.matching(apps, "org.telegram") == [telegramApp])
        #expect(AppSearch.matching(apps, "   ") == apps)
        #expect(AppSearch.matching(apps, "zzz").isEmpty)
    }
}
