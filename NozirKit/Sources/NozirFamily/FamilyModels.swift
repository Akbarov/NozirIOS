import Foundation

/// Backend `AgeGroup`: STAR 7–10, EXPLORER 11–13, INDEPENDENT 14–17.
public enum AgeGroup: String, Sendable, Decodable {
    case star = "STAR"
    case explorer = "EXPLORER"
    case independent = "INDEPENDENT"
}

/// Backend `PairingState`: how far the child's phone has got.
public enum PairingState: String, Sendable, Decodable {
    case notPaired = "NOT_PAIRED"
    case codeIssued = "CODE_ISSUED"
    case appInstalled = "APP_INSTALLED"
    case paired = "PAIRED"
}

/// `ChildResponse`. Decoding is lenient where the server may grow: a band or a
/// state this app does not know yet must not empty the parent's child list.
public struct Child: Decodable, Equatable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let birthYear: Int
    /// The effective band (the parent's override or the birth year's); never
    /// re-derived here. Nil for a band this app does not know.
    public let ageGroup: AgeGroup?
    public let avatarKey: String?
    /// A minor's number: shown to the parent only, never logged.
    public let phoneE164: String?
    public let pairingState: PairingState

    public init(
        id: UUID,
        displayName: String,
        birthYear: Int,
        ageGroup: AgeGroup? = nil,
        avatarKey: String? = nil,
        phoneE164: String? = nil,
        pairingState: PairingState = .notPaired
    ) {
        self.id = id
        self.displayName = displayName
        self.birthYear = birthYear
        self.ageGroup = ageGroup
        self.avatarKey = avatarKey
        self.phoneE164 = phoneE164
        self.pairingState = pairingState
    }

    private enum CodingKeys: String, CodingKey {
        case id = "childId"
        case displayName, birthYear, ageGroup, avatarKey, phoneE164, pairingState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        birthYear = try container.decode(Int.self, forKey: .birthYear)
        ageGroup = try? container.decodeIfPresent(AgeGroup.self, forKey: .ageGroup)
        avatarKey = try container.decodeIfPresent(String.self, forKey: .avatarKey)
        phoneE164 = try container.decodeIfPresent(String.self, forKey: .phoneE164)
        pairingState = (try? container.decode(PairingState.self, forKey: .pairingState)) ?? .notPaired
    }
}

/// `CreateChildBody`. Nil fields are left out of the JSON.
public struct ChildCreate: Encodable, Equatable, Sendable {
    public let displayName: String
    public let birthYear: Int
    public let avatarKey: String?
    public let phoneE164: String?

    public init(displayName: String, birthYear: Int, avatarKey: String?, phoneE164: String?) {
        self.displayName = displayName
        self.birthYear = birthYear
        self.avatarKey = avatarKey
        self.phoneE164 = phoneE164
    }
}

/// `UpdateChildBody`: only what changed is sent. The phone has three
/// instructions, because "leave it" and "remove it" are different requests.
public struct ChildUpdate: Encodable, Equatable, Sendable {
    public enum Phone: Equatable, Sendable {
        case unchanged
        case cleared
        case set(String)
    }

    public var displayName: String?
    public var birthYear: Int?
    public var avatarKey: String?
    public var phone: Phone

    public init(displayName: String? = nil, birthYear: Int? = nil, avatarKey: String? = nil, phone: Phone = .unchanged) {
        self.displayName = displayName
        self.birthYear = birthYear
        self.avatarKey = avatarKey
        self.phone = phone
    }

    public var isEmpty: Bool {
        displayName == nil && birthYear == nil && avatarKey == nil && phone == .unchanged
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, birthYear, avatarKey, phoneE164
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(birthYear, forKey: .birthYear)
        try container.encodeIfPresent(avatarKey, forKey: .avatarKey)
        switch phone {
        case .unchanged:
            break
        case .cleared:
            try container.encodeNil(forKey: .phoneE164)
        case .set(let number):
            try container.encode(number, forKey: .phoneE164)
        }
    }
}
