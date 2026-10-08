import Foundation

/// `RiskLevel` on the wire (the home card calls it `statusLevel`). A value this
/// app does not know reads as good rather than breaking the list.
public enum StatusLevel: String, Sendable, Decodable {
    case good = "GOOD"
    case attention = "ATTENTION"
    case action = "ACTION"
    case critical = "CRITICAL"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StatusLevel(rawValue: raw) ?? .good
    }
}

/// `ChildHomeCardDto`. `ageGroup` is not read: the age comes from the family list.
public struct ChildHomeCard: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let avatarKey: String?
    public let usedMinutes: Int
    public let limitMinutes: Int
    public let statusLevel: StatusLevel
    /// The only thing that lifts a card to the top; a quiet card is "no news".
    public let needsAttention: Bool
    public let summarySentence: String?
    public let placeLabel: String?
    public let placeSince: Date?
    public let deviceOnline: Bool
    public let lastSeenAt: Date?

    public init(
        id: UUID,
        displayName: String,
        avatarKey: String? = nil,
        usedMinutes: Int = 0,
        limitMinutes: Int = 0,
        statusLevel: StatusLevel = .good,
        needsAttention: Bool = false,
        summarySentence: String? = nil,
        placeLabel: String? = nil,
        placeSince: Date? = nil,
        deviceOnline: Bool = true,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarKey = avatarKey
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
        self.statusLevel = statusLevel
        self.needsAttention = needsAttention
        self.summarySentence = summarySentence
        self.placeLabel = placeLabel
        self.placeSince = placeSince
        self.deviceOnline = deviceOnline
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case id = "childId"
        case displayName, avatarKey, usedMinutes, limitMinutes, statusLevel, needsAttention
        case summarySentence, placeLabel, placeSince, deviceOnline, lastSeenAt
    }
}

/// `ActiveSosDto`: the unanswered alarm. `childName` is nil when the child was removed.
public struct ActiveSos: Decodable, Hashable, Sendable {
    public let sosId: UUID
    public let childId: UUID
    public let childName: String?
    public let triggeredAt: Date

    public init(sosId: UUID, childId: UUID, childName: String?, triggeredAt: Date) {
        self.sosId = sosId
        self.childId = childId
        self.childName = childName
        self.triggeredAt = triggeredAt
    }
}

/// `ParentHomeResponse`, the parts P05 draws in this slice. The legacy
/// `activeSosId` is not read (plan deviation E1).
public struct ParentHome: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let children: [ChildHomeCard]
    public let familySummary: String?
    public let activeSos: ActiveSos?
    /// P17 rows, newest first. A list that cannot be read is no list: Home
    /// still loads (plan deviation T6).
    public let pendingExtraTimeRequests: [ExtraTimeRequest]
    /// P18 row. Absent or unreadable is nil: no row, and Home still loads.
    public let protection: HomeProtection?

    public init(
        date: LocalDate,
        children: [ChildHomeCard],
        familySummary: String? = nil,
        activeSos: ActiveSos? = nil,
        pendingExtraTimeRequests: [ExtraTimeRequest] = [],
        protection: HomeProtection? = nil
    ) {
        self.date = date
        self.children = children
        self.familySummary = familySummary
        self.activeSos = activeSos
        self.pendingExtraTimeRequests = pendingExtraTimeRequests
        self.protection = protection
    }

    enum CodingKeys: String, CodingKey {
        case date, children, familySummary, activeSos, pendingExtraTimeRequests, protection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(LocalDate.self, forKey: .date)
        children = try container.decodeIfPresent([ChildHomeCard].self, forKey: .children) ?? []
        familySummary = try container.decodeIfPresent(String.self, forKey: .familySummary)
        activeSos = try container.decodeIfPresent(ActiveSos.self, forKey: .activeSos)
        pendingExtraTimeRequests = (try? container.decodeIfPresent([ExtraTimeRequest].self, forKey: .pendingExtraTimeRequests)) ?? []
        protection = try? container.decodeIfPresent(HomeProtection.self, forKey: .protection)
    }
}

/// `HomeProtectionDto`: the family's worst level and the children that are not
/// healthy. Only these two fields come with Home.
public struct HomeProtection: Decodable, Equatable, Sendable {
    public let level: ProtectionLevel
    public let childrenNeedingAttention: [UUID]

    public init(level: ProtectionLevel, childrenNeedingAttention: [UUID] = []) {
        self.level = level
        self.childrenNeedingAttention = childrenNeedingAttention
    }

    enum CodingKeys: String, CodingKey {
        case level, childrenNeedingAttention
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // No level, no block: the row is dropped by the caller's `try?`.
        let rawLevel = try container.decode(String.self, forKey: .level)
        childrenNeedingAttention = try container.decodeIfPresent([UUID].self, forKey: .childrenNeedingAttention) ?? []
        level = ProtectionLevel.resolving(rawLevel, hasFault: !childrenNeedingAttention.isEmpty)
    }
}

/// `SummaryPeriod` on the wire. Only P16a reads it, to know which screen a
/// link opens.
public enum SummaryPeriod: String, Sendable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
}

/// `InsightSummaryResponse`, daily or weekly.
public struct InsightSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    /// nil when absent or a value this app does not know (a monthly report
    /// one day): the summary still reads, a link to it is "gone".
    public let period: SummaryPeriod?
    public let periodStart: LocalDate
    public let periodEnd: LocalDate
    public let paragraphs: [String]
    public let recommendation: String?
    public let conversationQuestion: String?
    public let riskLevel: StatusLevel

    public init(
        id: UUID,
        childId: UUID,
        period: SummaryPeriod? = nil,
        periodStart: LocalDate,
        periodEnd: LocalDate,
        paragraphs: [String],
        recommendation: String? = nil,
        conversationQuestion: String? = nil,
        riskLevel: StatusLevel = .good
    ) {
        self.id = id
        self.childId = childId
        self.period = period
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.paragraphs = paragraphs
        self.recommendation = recommendation
        self.conversationQuestion = conversationQuestion
        self.riskLevel = riskLevel
    }

    enum CodingKeys: String, CodingKey {
        case id = "summaryId"
        case childId, period, periodStart, periodEnd, paragraphs, recommendation, conversationQuestion, riskLevel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        // Read as text: a period this app does not know never fails the summary.
        period = (try? container.decodeIfPresent(String.self, forKey: .period)).flatMap(SummaryPeriod.init(rawValue:))
        periodStart = try container.decode(LocalDate.self, forKey: .periodStart)
        periodEnd = try container.decode(LocalDate.self, forKey: .periodEnd)
        paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        conversationQuestion = try container.decodeIfPresent(String.self, forKey: .conversationQuestion)
        riskLevel = try container.decodeIfPresent(StatusLevel.self, forKey: .riskLevel) ?? .good
    }
}

/// `DailyTotalDto`: one day of one child's screen time.
public struct DailyUsage: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let usedMinutes: Int
    public let limitMinutes: Int

    public init(date: LocalDate, usedMinutes: Int, limitMinutes: Int) {
        self.date = date
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
    }
}

/// `UsageRange` on P08. A value this app does not know reads as today.
public enum UsageRange: String, CaseIterable, Sendable, Decodable {
    case today = "TODAY"
    case lastSevenDays = "LAST_7_DAYS"
    case lastThirtyDays = "LAST_30_DAYS"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UsageRange(rawValue: raw) ?? .today
    }
}

/// `AppUsageEntryDto`. The server folds everything past the top four into one
/// entry with the reserved id `nozir.other_apps`.
public struct AppUsageEntry: Decodable, Hashable, Sendable {
    public static let otherAppsPackageId = "nozir.other_apps"

    public let packageId: String
    public let displayName: String
    public let minutes: Int

    public init(packageId: String, displayName: String, minutes: Int) {
        self.packageId = packageId
        self.displayName = displayName
        self.minutes = minutes
    }

    public var isOtherApps: Bool {
        packageId == Self.otherAppsPackageId
    }

    enum CodingKeys: String, CodingKey {
        case packageId, displayName, minutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try container.decode(String.self, forKey: .packageId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        minutes = try container.decode(Int.self, forKey: .minutes)
    }
}

/// `AppBreakdownResponse`.
public struct AppBreakdown: Decodable, Equatable, Sendable {
    public let range: UsageRange
    public let totalMinutes: Int
    public let entries: [AppUsageEntry]

    public init(range: UsageRange, totalMinutes: Int, entries: [AppUsageEntry]) {
        self.range = range
        self.totalMinutes = totalMinutes
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case range, totalMinutes, entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(UsageRange.self, forKey: .range) ?? .today
        totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 0
        entries = try container.decodeIfPresent([AppUsageEntry].self, forKey: .entries) ?? []
    }
}
