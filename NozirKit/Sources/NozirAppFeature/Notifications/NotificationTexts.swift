import Foundation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P16 in words and tones (Android `NotificationHeadline`, `NotificationHeadlineRes`,
/// `ZoneCrossingHeadline`, `NotificationMoment`, `NotificationRow`,
/// `NotificationCardTone`, `NotificationsContent`, `DeviceOfflineSetting`).
/// The server sends a key and its arguments, never text.
enum NotificationTexts {
    private static let digestKey = "notification.digest.suppressed"
    private static let appInstalledKey = "notification.app.installed"
    private static let bedtimeDelayKey = "notification.bedtimeDelay.requested"
    private static let countArg = "count"
    private static let childNameArg = "childName"
    private static let zoneNameArg = "zoneName"

    // MARK: Headline

    /// Android's order: the digest's count, the new-apps count, a named zone
    /// crossing, a bedtime ask, then the type's own sentence.
    static func headline(_ notification: ParentNotification, _ l10n: L10n) -> String {
        let count = notification.localisationArgs[countArg]
        if notification.localisationKey == digestKey, let count {
            return l10n.notificationDigestSuppressed(count)
        }
        if notification.localisationKey == appInstalledKey, let count {
            return l10n.notificationAppInstalledCount(count)
        }
        if let named = zoneCrossing(notification, l10n) {
            return named
        }
        if notification.localisationKey == bedtimeDelayKey {
            return l10n.notificationBedtimeDelayRequested
        }
        return typeHeadline(notification.type, l10n)
    }

    /// "Umar «Uy»ga yetib keldi"; nil unless both names are there.
    private static func zoneCrossing(_ notification: ParentNotification, _ l10n: L10n) -> String? {
        guard let child = LocationTexts.present(notification.localisationArgs[childNameArg] ?? notification.childName),
              let zone = LocationTexts.present(notification.localisationArgs[zoneNameArg]) else { return nil }
        switch notification.type {
        case .safeZoneEntered: return l10n.notificationSafeZoneEnteredNamed(child, zone)
        case .safeZoneLeft: return l10n.notificationSafeZoneLeftNamed(child, zone)
        default: return nil
        }
    }

    private static func typeHeadline(_ type: NotificationType, _ l10n: L10n) -> String {
        switch type {
        case .sosTriggered: l10n.notificationSosTriggered
        case .safeZoneEntered: l10n.notificationSafeZoneEntered
        case .safeZoneLeft: l10n.notificationSafeZoneLeft
        case .protectionBroken: l10n.notificationProtectionBroken
        case .protectionRestored: l10n.notificationProtectionRestored
        case .deviceOffline: l10n.notificationDeviceOffline
        case .extraTimeRequested: l10n.notificationExtraTimeRequested
        case .challengeNeedsApproval: l10n.notificationChallengeNeedsApproval
        case .dailySummaryReady: l10n.notificationDailySummaryReady
        case .weeklyReportReady: l10n.notificationWeeklyReportReady
        case .limitReached: l10n.notificationLimitReached
        case .bedtimeViolation: l10n.notificationBedtimeViolation
        case .usageAnomaly: l10n.notificationUsageAnomaly
        case .rulesChanged: l10n.notificationRulesChanged
        case .subscriptionExpiring: l10n.notificationSubscriptionExpiring
        case .childAppOutdated: l10n.notificationChildAppOutdated
        case .appInstalled: l10n.notificationAppInstalled
        case .unknown: l10n.notificationUnknown
        }
    }

    // MARK: When, and for whom

    /// "Bugun 17:45", "Kecha 08:00", "15-avgust 08:12" on the phone's clock.
    static func moment(_ date: Date, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        let day = LocalDate(date, in: calendar)
        let today = LocalDate(now, in: calendar)
        let clock = DateTexts.timeOfDay(date, calendar: calendar)
        if day == today {
            return l10n.notificationMomentToday(clock)
        }
        if day == today.adding(days: -1) {
            return l10n.notificationMomentYesterday(clock)
        }
        return l10n.notificationMomentDate(DateTexts.dayAndMonth(day, l10n), clock)
    }

    /// "Ali · Bugun 17:45", or just the moment for a family-wide row.
    static func caption(_ notification: ParentNotification, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        let when = moment(notification.occurredAt, now: now, l10n, calendar: calendar)
        guard let name = LocationTexts.present(notification.childName) else { return when }
        return l10n.notificationChildAndMoment(name, when)
    }

    /// "Ilova ichida qoldi" for the tiers that never ring the phone.
    static func inAppNote(_ tier: NotificationTier, _ l10n: L10n) -> String? {
        tier.isImportant ? nil : l10n.notificationsInAppOnly
    }

    // MARK: Tones

    static func dotLevel(_ tier: NotificationTier) -> NozirStatusLevel {
        switch tier {
        case .good: .good
        case .attention: .attention
        case .action: .action
        case .critical: .critical
        }
    }

    /// GOOD is plain so the rows that matter stand out; iOS has no ACTION card
    /// (plan deviation N2), so ACTION shares the attention card.
    static func cardTone(_ tier: NotificationTier) -> NozirCardTone {
        switch tier {
        case .good: .plain
        case .attention, .action: .attention
        case .critical: .critical
        }
    }

    // MARK: Empty list

    static func emptyTitle(_ filter: NotificationFilter, _ l10n: L10n) -> String {
        filter == .important ? l10n.notificationsEmptyImportantTitle : l10n.notificationsEmptyTitle
    }

    static func emptyBody(_ filter: NotificationFilter, _ l10n: L10n) -> String {
        filter == .important ? l10n.notificationsEmptyImportantBody : l10n.notificationsEmptyBody
    }

    // MARK: "Telefon jim qolsa"

    /// Android's presets, in minutes (plan deviation N1); all inside 60…2880.
    static let offlinePresets = [60, 120, 240, 360, 720, 1440]

    /// "6 s" on the segment.
    static func presetLabel(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.notificationsOfflinePreset(minutes / 60)
    }

    /// "6 soat" for VoiceOver, so the short segment label is never read alone.
    static func presetAccessibilityLabel(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.notificationsOfflineValue(minutes / 60)
    }

    /// "Hozir: 6 soat"; a value that is not whole hours keeps its minutes.
    static func offlineCurrent(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let value = rest == 0 ? l10n.notificationsOfflineValue(hours) : l10n.durationLongHoursMinutes(hours, rest)
        return l10n.notificationsOfflineCurrent(value)
    }
}
