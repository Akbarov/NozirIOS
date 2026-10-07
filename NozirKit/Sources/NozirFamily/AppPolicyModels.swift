import Foundation

/// How an app's rule restricts it (`AppPolicyMode`). A mode the server adds
/// later keeps its name: the editor offers no segment for it and never sends it.
public enum AppPolicyMode: Hashable, Sendable {
    case unrestricted, dailyLimit, scheduleBlock, alwaysBlocked
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "UNRESTRICTED": self = .unrestricted
        case "DAILY_LIMIT": self = .dailyLimit
        case "SCHEDULE_BLOCK": self = .scheduleBlock
        case "ALWAYS_BLOCKED": self = .alwaysBlocked
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .unrestricted: "UNRESTRICTED"
        case .dailyLimit: "DAILY_LIMIT"
        case .scheduleBlock: "SCHEDULE_BLOCK"
        case .alwaysBlocked: "ALWAYS_BLOCKED"
        case .unknown(let name): name
        }
    }
}

/// `BlockWindowDto`: the app is closed from `start` to `end` on `days`
/// (ISO-8601, 1 = Monday). The server does not compare start with end.
public struct BlockWindow: Codable, Equatable, Sendable {
    public var start: ClockTime
    public var end: ClockTime
    public var days: [Int]

    public init(start: ClockTime, end: ClockTime, days: [Int]) {
        self.start = start
        self.end = end
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, days
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try ClockTime.decode(container, .startTime)
        end = try ClockTime.decode(container, .endTime)
        days = try container.decode([Int].self, forKey: .days)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start.text, forKey: .startTime)
        try container.encode(end.text, forKey: .endTime)
        try container.encode(days, forKey: .days)
    }
}

/// `AppPolicyDto`: one app's rule. `packageId` is its identity on the wire and
/// in the path; the name is only shown, and rewritten by every write.
public struct AppPolicy: Codable, Equatable, Sendable {
    public let packageId: String
    public var displayName: String?
    public var mode: AppPolicyMode
    public var dailyLimitMinutes: Int?
    public var blockWindows: [BlockWindow]

    public init(
        packageId: String,
        displayName: String? = nil,
        mode: AppPolicyMode,
        dailyLimitMinutes: Int? = nil,
        blockWindows: [BlockWindow] = []
    ) {
        self.packageId = packageId
        self.displayName = displayName
        self.mode = mode
        self.dailyLimitMinutes = dailyLimitMinutes
        self.blockWindows = blockWindows
    }

    private enum CodingKeys: String, CodingKey {
        case packageId, displayName, mode, dailyLimitMinutes, blockWindows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try container.decode(String.self, forKey: .packageId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        mode = AppPolicyMode(wireName: try container.decode(String.self, forKey: .mode))
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        blockWindows = try container.decodeIfPresent([BlockWindow].self, forKey: .blockWindows) ?? []
    }

    /// The name goes out even when unknown (`null`): the server stores what each write says.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(mode.wireName, forKey: .mode)
        try container.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try container.encode(blockWindows, forKey: .blockWindows)
    }
}

/// `InstalledAppDto`: one app on the child's phone, for P11's picker.
public struct InstalledApp: Decodable, Equatable, Sendable {
    public let packageId: String
    public let displayName: String?

    public init(packageId: String, displayName: String?) {
        self.packageId = packageId
        self.displayName = displayName
    }
}
