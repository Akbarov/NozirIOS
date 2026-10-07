import Foundation

/// `NotificationType`, as far as this app has words for it. Anything else —
/// `TRIAL_ENDING`, `TRIAL_ENDED`, `SUBSCRIPTION_EXPIRED`, `SUBSCRIPTION_LAPSED`
/// or a type added later — is kept as it came: the record is complete, so the
/// row stays ("Yangi bildirishnoma").
public enum NotificationType: Hashable, Sendable {
    case sosTriggered
    case safeZoneEntered
    case safeZoneLeft
    case protectionBroken
    case protectionRestored
    case deviceOffline
    case extraTimeRequested
    case challengeNeedsApproval
    case dailySummaryReady
    case weeklyReportReady
    case limitReached
    case bedtimeViolation
    case usageAnomaly
    case rulesChanged
    case subscriptionExpiring
    case childAppOutdated
    case appInstalled
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "SOS_TRIGGERED": self = .sosTriggered
        case "SAFE_ZONE_ENTERED": self = .safeZoneEntered
        case "SAFE_ZONE_LEFT": self = .safeZoneLeft
        case "PROTECTION_BROKEN": self = .protectionBroken
        case "PROTECTION_RESTORED": self = .protectionRestored
        case "DEVICE_OFFLINE": self = .deviceOffline
        case "EXTRA_TIME_REQUESTED": self = .extraTimeRequested
        case "CHALLENGE_NEEDS_APPROVAL": self = .challengeNeedsApproval
        case "DAILY_SUMMARY_READY": self = .dailySummaryReady
        case "WEEKLY_REPORT_READY": self = .weeklyReportReady
        case "LIMIT_REACHED": self = .limitReached
        case "BEDTIME_VIOLATION": self = .bedtimeViolation
        case "USAGE_ANOMALY": self = .usageAnomaly
        case "RULES_CHANGED": self = .rulesChanged
        case "SUBSCRIPTION_EXPIRING": self = .subscriptionExpiring
        case "CHILD_APP_OUTDATED": self = .childAppOutdated
        case "APP_INSTALLED": self = .appInstalled
        default: self = .unknown(rawValue)
        }
    }
}

/// `NotificationTier`. The tier is what a row's colour means, so a row whose
/// tier this app cannot read is the one row that is dropped.
public enum NotificationTier: String, Sendable {
    case good = "GOOD"
    case attention = "ATTENTION"
    case action = "ACTION"
    case critical = "CRITICAL"

    /// What "Muhim" keeps; GOOD and ATTENTION never ring the phone.
    public var isImportant: Bool {
        self == .action || self == .critical
    }
}

/// `NotificationFilter`: the "Hammasi" / "Muhim" control.
public enum NotificationFilter: String, CaseIterable, Sendable {
    case all = "ALL"
    case important = "IMPORTANT"
}

/// `NotificationResponse`. The server sends no text: a key, its arguments and
/// a type; every word is the app's.
public struct ParentNotification: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let type: NotificationType
    public let tier: NotificationTier
    public let localisationKey: String
    public let localisationArgs: [String: String]
    /// Nil for a family-wide row (the digest).
    public let childId: UUID?
    public let childName: String?
    /// `nozir://…`; read by `NotificationLink` in the app.
    public let deepLink: String?
    public let occurredAt: Date
    public let readAt: Date?

    public init(
        id: UUID,
        type: NotificationType,
        tier: NotificationTier,
        localisationKey: String = "",
        localisationArgs: [String: String] = [:],
        childId: UUID? = nil,
        childName: String? = nil,
        deepLink: String? = nil,
        occurredAt: Date,
        readAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.tier = tier
        self.localisationKey = localisationKey
        self.localisationArgs = localisationArgs
        self.childId = childId
        self.childName = childName
        self.deepLink = deepLink
        self.occurredAt = occurredAt
        self.readAt = readAt
    }

    public var isRead: Bool {
        readAt != nil
    }

    /// The same row, read at `moment` (the list marks it before the server hears).
    public func markedRead(at moment: Date) -> ParentNotification {
        ParentNotification(
            id: id, type: type, tier: tier, localisationKey: localisationKey,
            localisationArgs: localisationArgs, childId: childId, childName: childName,
            deepLink: deepLink, occurredAt: occurredAt, readAt: moment
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, type, tier, localisationKey, localisationArgs, childId, childName, deepLink, occurredAt, readAt
    }

    /// `id`, `tier` and `occurredAt` are required; everything else is read defensively.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let rawTier = try container.decode(String.self, forKey: .tier)
        guard let tier = NotificationTier(rawValue: rawTier) else {
            throw DecodingError.dataCorruptedError(forKey: .tier, in: container, debugDescription: "Unknown tier \(rawTier)")
        }
        self.tier = tier
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        type = NotificationType(rawValue: (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "")
        localisationKey = (try? container.decodeIfPresent(String.self, forKey: .localisationKey)) ?? ""
        localisationArgs = (try? container.decodeIfPresent([String: String].self, forKey: .localisationArgs)) ?? [:]
        childId = try? container.decodeIfPresent(UUID.self, forKey: .childId)
        childName = try? container.decodeIfPresent(String.self, forKey: .childName)
        deepLink = try? container.decodeIfPresent(String.self, forKey: .deepLink)
        readAt = try? container.decodeIfPresent(Date.self, forKey: .readAt)
    }
}

/// `NotificationPage`. `nextCursor` is opaque and absent on the last page; a
/// page may be empty, and rows this app cannot read are dropped one by one.
public struct NotificationPage: Decodable, Equatable, Sendable {
    public let items: [ParentNotification]
    public let nextCursor: String?

    public init(items: [ParentNotification], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items, nextCursor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decodeIfPresent([LossyNotification].self, forKey: .items) ?? []
        items = rows.compactMap(\.value)
        nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// One element of `items`, or nil when it cannot be read: one broken row never
/// empties the page.
private struct LossyNotification: Decodable {
    let value: ParentNotification?

    init(from decoder: any Decoder) throws {
        value = try? ParentNotification(from: decoder)
    }
}

/// `NotificationPreferencesResponse` / `NotificationPreferencesBody`. The write
/// is a full replace, so every field is carried and decoded strictly: a value
/// filled in by guesswork would be written back as the parent's.
/// `mutedTypes` stays raw — a type this app does not know must stay muted.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    /// `NotificationDefaults` on the server; the server still clamps.
    public static let minDeviceOfflineMinutes = 60
    public static let maxDeviceOfflineMinutes = 2880

    public let dailyPushCap: Int
    /// "HH:mm"; absent when not set.
    public let quietHoursStart: String?
    public let quietHoursEnd: String?
    public let mutedTypes: [String]
    public let smsForCriticalEnabled: Bool
    public let deviceOfflineAfterMinutes: Int

    public init(
        dailyPushCap: Int,
        quietHoursStart: String?,
        quietHoursEnd: String?,
        mutedTypes: [String],
        smsForCriticalEnabled: Bool,
        deviceOfflineAfterMinutes: Int
    ) {
        self.dailyPushCap = dailyPushCap
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.mutedTypes = mutedTypes
        self.smsForCriticalEnabled = smsForCriticalEnabled
        self.deviceOfflineAfterMinutes = deviceOfflineAfterMinutes
    }

    /// Everything else exactly as it was.
    public func withDeviceOfflineAfter(minutes: Int) -> NotificationPreferences {
        NotificationPreferences(
            dailyPushCap: dailyPushCap,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            mutedTypes: mutedTypes,
            smsForCriticalEnabled: smsForCriticalEnabled,
            deviceOfflineAfterMinutes: minutes
        )
    }
}
