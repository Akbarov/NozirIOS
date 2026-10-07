import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private var tashkent: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}

private func at(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// 15:00 in Tashkent on 7 October.
private let now = at("2026-10-07T10:00:00Z")

@Suite struct NotificationTextsTests {
    private let l10n = L10n(.uz)

    private func headline(_ type: NotificationType, key: String = "x", args: [String: String] = [:], childName: String? = "Ali") -> String {
        NotificationTexts.headline(parentNotification(type: type, key: key, args: args, childName: childName), l10n)
    }

    // Spec §4.2: otherwise by type (Android `headlineRes`).
    @Test func everyKnownTypeHasItsSentence() {
        let table: [(NotificationType, String)] = [
            (.sosTriggered, l10n.notificationSosTriggered),
            (.safeZoneEntered, l10n.notificationSafeZoneEntered),
            (.safeZoneLeft, l10n.notificationSafeZoneLeft),
            (.protectionBroken, l10n.notificationProtectionBroken),
            (.protectionRestored, l10n.notificationProtectionRestored),
            (.deviceOffline, l10n.notificationDeviceOffline),
            (.extraTimeRequested, l10n.notificationExtraTimeRequested),
            (.challengeNeedsApproval, l10n.notificationChallengeNeedsApproval),
            (.dailySummaryReady, l10n.notificationDailySummaryReady),
            (.weeklyReportReady, l10n.notificationWeeklyReportReady),
            (.limitReached, l10n.notificationLimitReached),
            (.bedtimeViolation, l10n.notificationBedtimeViolation),
            (.usageAnomaly, l10n.notificationUsageAnomaly),
            (.rulesChanged, l10n.notificationRulesChanged),
            (.subscriptionExpiring, l10n.notificationSubscriptionExpiring),
            (.childAppOutdated, l10n.notificationChildAppOutdated),
            (.appInstalled, l10n.notificationAppInstalled),
        ]
        for (type, expected) in table {
            #expect(headline(type) == expected)
        }
        #expect(headline(.sosTriggered) == "SOS yuborildi")
    }

    // Review Focus 6 and spec §7: the four new backend types read as "Yangi bildirishnoma".
    @Test func anUnknownTypeReadsAsANewNotification() {
        #expect(headline(.unknown("TRIAL_ENDING")) == l10n.notificationUnknown)
        #expect(headline(.unknown("")) == "Yangi bildirishnoma")
    }

    // Android `NotificationHeadline`: the digest and the app count carry their number;
    // without it the type's own sentence (the digest is DAILY_SUMMARY_READY on the wire).
    @Test func theDigestAndTheAppCountCarryTheirNumber() {
        #expect(headline(.dailySummaryReady, key: "notification.digest.suppressed", args: ["count": "3"]) == l10n.notificationDigestSuppressed("3"))
        #expect(headline(.dailySummaryReady, key: "notification.digest.suppressed") == l10n.notificationDailySummaryReady)
        #expect(headline(.appInstalled, key: "notification.app.installed", args: ["count": "2"]) == l10n.notificationAppInstalledCount("2"))
        #expect(headline(.appInstalled, key: "notification.app.installed") == l10n.notificationAppInstalled)
    }

    // Android `zoneCrossingHeadline`: both names, the arg's child name before the row's.
    @Test func aZoneCrossingNamesTheChildAndTheZone() {
        let key = "notification.safeZone.entered"
        #expect(headline(.safeZoneEntered, key: key, args: ["childName": "Umar", "zoneName": "Uy"]) == l10n.notificationSafeZoneEnteredNamed("Umar", "Uy"))
        #expect(headline(.safeZoneEntered, key: key, args: ["zoneName": " Maktab №5 "]) == l10n.notificationSafeZoneEnteredNamed("Ali", "Maktab №5"))
        #expect(headline(.safeZoneLeft, key: "notification.safeZone.left", args: ["zoneName": "Uy"]) == l10n.notificationSafeZoneLeftNamed("Ali", "Uy"))
        #expect(headline(.safeZoneLeft, key: "notification.safeZone.left", args: ["zoneName": "Uy"], childName: nil) == l10n.notificationSafeZoneLeft)
        #expect(headline(.safeZoneEntered, key: key, args: ["zoneName": "  "]) == l10n.notificationSafeZoneEntered)
        #expect(headline(.safeZoneEntered, key: key) == l10n.notificationSafeZoneEntered)
        #expect(headline(.limitReached, args: ["zoneName": "Uy"]) == l10n.notificationLimitReached)
    }

    // Android `headlineResForKey`: a bedtime ask shares the extra-time type.
    @Test func aBedtimeAskIsNotCalledExtraTime() {
        #expect(headline(.extraTimeRequested, key: "notification.bedtimeDelay.requested") == l10n.notificationBedtimeDelayRequested)
        #expect(headline(.extraTimeRequested, key: "notification.extraTime.requested") == l10n.notificationExtraTimeRequested)
    }

    // Android `asNotificationMoment`, on the phone's clock.
    @Test func theMomentIsTodayYesterdayOrADate() {
        #expect(NotificationTexts.moment(at("2026-10-07T03:15:00Z"), now: now, l10n, calendar: tashkent) == "Bugun 08:15")
        #expect(NotificationTexts.moment(at("2026-10-06T19:30:00Z"), now: now, l10n, calendar: tashkent) == "Bugun 00:30")
        #expect(NotificationTexts.moment(at("2026-10-06T18:59:00Z"), now: now, l10n, calendar: tashkent) == "Kecha 23:59")
        #expect(NotificationTexts.moment(at("2026-10-05T18:59:00Z"), now: now, l10n, calendar: tashkent) == "5-oktabr 23:59")
        #expect(NotificationTexts.moment(at("2026-08-15T03:12:00Z"), now: now, l10n, calendar: tashkent) == "15-avgust 08:12")
    }

    @Test func theCaptionNamesTheChildWhenThereIsOne() {
        let row = parentNotification(occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(row, now: now, l10n, calendar: tashkent) == l10n.notificationChildAndMoment("Ali", "Bugun 08:15"))
        let digest = parentNotification(childId: nil, childName: nil, occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(digest, now: now, l10n, calendar: tashkent) == "Bugun 08:15")
        let blank = parentNotification(childName: " ", occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(blank, now: now, l10n, calendar: tashkent) == "Bugun 08:15")
    }

    // A tier that never rings the phone says so; the dot and card follow the tier (plan deviation N2).
    @Test func theTierDecidesTheNoteTheDotAndTheCard() {
        #expect(NotificationTexts.inAppNote(.good, l10n) == l10n.notificationsInAppOnly)
        #expect(NotificationTexts.inAppNote(.attention, l10n) == "Ilova ichida qoldi")
        #expect(NotificationTexts.inAppNote(.action, l10n) == nil)
        #expect(NotificationTexts.inAppNote(.critical, l10n) == nil)
        #expect(NotificationTexts.dotLevel(.good) == .good)
        #expect(NotificationTexts.dotLevel(.attention) == .attention)
        #expect(NotificationTexts.dotLevel(.action) == .action)
        #expect(NotificationTexts.dotLevel(.critical) == .critical)
        #expect(NotificationTexts.cardTone(.good) == .plain)
        #expect(NotificationTexts.cardTone(.attention) == .attention)
        #expect(NotificationTexts.cardTone(.action) == .attention)
        #expect(NotificationTexts.cardTone(.critical) == .critical)
    }

    @Test func theEmptyStateFollowsTheFilter() {
        #expect(NotificationTexts.emptyTitle(.all, l10n) == l10n.notificationsEmptyTitle)
        #expect(NotificationTexts.emptyBody(.all, l10n) == l10n.notificationsEmptyBody)
        #expect(NotificationTexts.emptyTitle(.important, l10n) == l10n.notificationsEmptyImportantTitle)
        #expect(NotificationTexts.emptyBody(.important, l10n) == l10n.notificationsEmptyImportantBody)
    }

    // Plan deviation N1 (Android `DeviceOfflineSetting`): whole hours read as hours, anything else keeps its minutes.
    @Test func theOfflineSettingIsInHours() {
        #expect(NotificationTexts.offlinePresets == [60, 120, 240, 360, 720, 1440])
        #expect(NotificationTexts.offlinePresets.allSatisfy {
            (NotificationPreferences.minDeviceOfflineMinutes...NotificationPreferences.maxDeviceOfflineMinutes).contains($0)
        })
        #expect(NotificationTexts.presetLabel(360, l10n) == "6 s")
        #expect(NotificationTexts.presetAccessibilityLabel(360, l10n) == "6 soat")
        #expect(NotificationTexts.offlineCurrent(360, l10n) == "Hozir: 6 soat")
        #expect(NotificationTexts.offlineCurrent(2880, l10n) == "Hozir: 48 soat")
        #expect(NotificationTexts.offlineCurrent(90, l10n) == l10n.notificationsOfflineCurrent(l10n.durationLongHoursMinutes(1, 30)))
    }
}
