import Foundation

/// `ExtraTimeKind`: what a yes does — minutes into today, or one night's
/// bedtime moved. A kind this app does not know is kept as it came.
public enum ExtraTimeKind: Hashable, Sendable, Decodable {
    case extraMinutes
    case bedtimeDelay
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "EXTRA_MINUTES": self = .extraMinutes
        case "BEDTIME_DELAY": self = .bedtimeDelay
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Only a kind the app can put into words may be answered: a parent must
    /// never approve minutes and find they moved a bedtime.
    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

/// `ExtraTimeStatus`. A status this app does not know is kept as it came.
public enum ExtraTimeStatus: Hashable, Sendable, Decodable {
    case pending
    case approved
    case declined
    case expired
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "PENDING": self = .pending
        case "APPROVED": self = .approved
        case "DECLINED": self = .declined
        case "EXPIRED": self = .expired
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// The parent's answer (`ExtraTimeOutcome`).
public enum ExtraTimeOutcome: String, Sendable, Encodable {
    case approve = "APPROVE"
    case partial = "PARTIAL"
    case decline = "DECLINE"
}

/// `ExtraTimeRequestDto`. The backend leaves out what is null (`non_null`);
/// an absent `kind` is the backend's default, extra minutes.
public struct ExtraTimeRequest: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    /// Nil when the child was removed.
    public let childName: String?
    public let kind: ExtraTimeKind
    /// The evening the moved night opens on; only for `bedtimeDelay`.
    public let nightOf: LocalDate?
    public let requestedMinutes: Int
    /// The child's own words, shown as written.
    public let reason: String
    public let status: ExtraTimeStatus
    public let grantedMinutes: Int?
    public let decisionNote: String?
    public let createdAt: Date
    public let decidedAt: Date?
    public let requestsInLastSevenDays: Int?

    public init(
        id: UUID,
        childId: UUID,
        childName: String? = nil,
        kind: ExtraTimeKind = .extraMinutes,
        nightOf: LocalDate? = nil,
        requestedMinutes: Int,
        reason: String,
        status: ExtraTimeStatus,
        grantedMinutes: Int? = nil,
        decisionNote: String? = nil,
        createdAt: Date,
        decidedAt: Date? = nil,
        requestsInLastSevenDays: Int? = nil
    ) {
        self.id = id
        self.childId = childId
        self.childName = childName
        self.kind = kind
        self.nightOf = nightOf
        self.requestedMinutes = requestedMinutes
        self.reason = reason
        self.status = status
        self.grantedMinutes = grantedMinutes
        self.decisionNote = decisionNote
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.requestsInLastSevenDays = requestsInLastSevenDays
    }

    /// The same ask under another child name (Home's answer carries none).
    public func named(_ name: String?) -> ExtraTimeRequest {
        ExtraTimeRequest(
            id: id, childId: childId, childName: name, kind: kind, nightOf: nightOf,
            requestedMinutes: requestedMinutes, reason: reason, status: status,
            grantedMinutes: grantedMinutes, decisionNote: decisionNote, createdAt: createdAt,
            decidedAt: decidedAt, requestsInLastSevenDays: requestsInLastSevenDays
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, childId, childName, kind, nightOf, requestedMinutes, reason, status
        case grantedMinutes, decisionNote, createdAt, decidedAt, requestsInLastSevenDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        childName = try container.decodeIfPresent(String.self, forKey: .childName)
        kind = try container.decodeIfPresent(ExtraTimeKind.self, forKey: .kind) ?? .extraMinutes
        nightOf = try container.decodeIfPresent(LocalDate.self, forKey: .nightOf)
        requestedMinutes = try container.decode(Int.self, forKey: .requestedMinutes)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        status = try container.decode(ExtraTimeStatus.self, forKey: .status)
        grantedMinutes = try container.decodeIfPresent(Int.self, forKey: .grantedMinutes)
        decisionNote = try container.decodeIfPresent(String.self, forKey: .decisionNote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
        requestsInLastSevenDays = try container.decodeIfPresent(Int.self, forKey: .requestsInLastSevenDays)
    }

    /// Waiting for an answer, and of a kind the app can describe.
    public var isAnswerable: Bool {
        status == .pending && kind.isKnown
    }
}
