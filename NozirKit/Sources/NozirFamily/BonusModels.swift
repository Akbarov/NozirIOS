import Foundation

/// A task's subject (`ChallengeKind`). A kind the server adds later keeps its
/// name, so a save sends the task back exactly as it came.
public enum ChallengeKind: Hashable, Sendable {
    case math, reading, english, exercise
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "MATH": self = .math
        case "READING": self = .reading
        case "ENGLISH": self = .english
        case "EXERCISE": self = .exercise
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .math: "MATH"
        case .reading: "READING"
        case .english: "ENGLISH"
        case .exercise: "EXERCISE"
        case .unknown(let name): name
        }
    }
}

/// How hard a task is (`ChallengeDifficulty`); the server scales the minutes by it.
public enum ChallengeDifficulty: Hashable, Sendable {
    case easy, medium, hard
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "EASY": self = .easy
        case "MEDIUM": self = .medium
        case "HARD": self = .hard
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .easy: "EASY"
        case .medium: "MEDIUM"
        case .hard: "HARD"
        case .unknown(let name): name
        }
    }
}

/// `BonusConfigItemDto`. P12 edits only `enabled`; the rest goes back as read.
public struct BonusChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ChallengeKind
    public let difficulty: ChallengeDifficulty
    public let bonusMinutes: Int
    public let requiresParentApproval: Bool
    public var enabled: Bool

    public init(
        id: UUID,
        kind: ChallengeKind,
        difficulty: ChallengeDifficulty,
        bonusMinutes: Int,
        requiresParentApproval: Bool,
        enabled: Bool
    ) {
        self.id = id
        self.kind = kind
        self.difficulty = difficulty
        self.bonusMinutes = bonusMinutes
        self.requiresParentApproval = requiresParentApproval
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, difficulty, bonusMinutes, requiresParentApproval, enabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = ChallengeKind(wireName: try container.decode(String.self, forKey: .kind))
        difficulty = ChallengeDifficulty(wireName: try container.decode(String.self, forKey: .difficulty))
        bonusMinutes = try container.decode(Int.self, forKey: .bonusMinutes)
        requiresParentApproval = try container.decode(Bool.self, forKey: .requiresParentApproval)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind.wireName, forKey: .kind)
        try container.encode(difficulty.wireName, forKey: .difficulty)
        try container.encode(bonusMinutes, forKey: .bonusMinutes)
        try container.encode(requiresParentApproval, forKey: .requiresParentApproval)
        try container.encode(enabled, forKey: .enabled)
    }
}

/// `BonusConfigDto` (P12): the daily ceiling and the tasks under it.
/// `ruleVersion` is the rule set's version — the same one every rules write names.
public struct BonusConfig: Decodable, Equatable, Sendable {
    public let ruleVersion: Int64
    public var maxDailyBonusMinutes: Int
    public var challenges: [BonusChallenge]

    public init(ruleVersion: Int64, maxDailyBonusMinutes: Int, challenges: [BonusChallenge]) {
        self.ruleVersion = ruleVersion
        self.maxDailyBonusMinutes = maxDailyBonusMinutes
        self.challenges = challenges
    }

    /// What every enabled task would pay together in one day.
    public var earnableMinutes: Int {
        challenges.filter(\.enabled).reduce(0) { $0 + $1.bonusMinutes }
    }

    /// The ceiling stops the tasks short of what they would pay.
    public var isCeilingBinding: Bool {
        earnableMinutes > maxDailyBonusMinutes
    }

    public func withChallenge(_ id: UUID, enabled: Bool) -> BonusConfig {
        var copy = self
        copy.challenges = challenges.map { challenge in
            guard challenge.id == id else { return challenge }
            var changed = challenge
            changed.enabled = enabled
            return changed
        }
        return copy
    }
}
