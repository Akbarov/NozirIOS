import Foundation

/// One line of the disclosure (`DisclosureItemDto`). The text is the server's;
/// the app never writes a line of its own.
public struct DisclosureItem: Decodable, Equatable, Sendable {
    public let key: String
    public let text: String

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// `TransparencyDisclosureResponse`: the same document the child's phone reads,
/// so the two screens cannot drift apart. Missing fields read as empty, like
/// Android `PrivacyDisclosureDto`.
public struct PrivacyDisclosure: Decodable, Equatable, Sendable {
    public let documentVersion: String
    public let locale: String
    public let seen: [DisclosureItem]
    /// The more important half.
    public let notSeen: [DisclosureItem]

    public init(documentVersion: String, locale: String, seen: [DisclosureItem], notSeen: [DisclosureItem]) {
        self.documentVersion = documentVersion
        self.locale = locale
        self.seen = seen
        self.notSeen = notSeen
    }

    private enum CodingKeys: String, CodingKey {
        case documentVersion, locale, seen, notSeen
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentVersion = try container.decodeIfPresent(String.self, forKey: .documentVersion) ?? ""
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? ""
        seen = try container.decodeIfPresent([DisclosureItem].self, forKey: .seen) ?? []
        notSeen = try container.decodeIfPresent([DisclosureItem].self, forKey: .notSeen) ?? []
    }

    /// Nothing on either side: the screen says the list could not be had.
    public var isEmpty: Bool {
        seen.isEmpty && notSeen.isEmpty
    }
}

/// The 202 from `POST /v1/parent/data-deletion-requests`
/// (`DataDeletionRequestResponse`). Nothing has been deleted; `executableAt`
/// is when it will be.
public struct ErasureRequest: Decodable, Equatable, Sendable {
    public let requestId: String
    public let requestedAt: Date?
    public let executableAt: Date

    public init(requestId: String, requestedAt: Date?, executableAt: Date) {
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.executableAt = executableAt
    }
}

/// `GET /v1/parent/data-deletion-requests/current`: the family's pending
/// request, the only date the screen quotes.
public struct ErasureRequestStatus: Decodable, Equatable, Sendable {
    public let requestId: String
    public let status: String
    public let requestedAt: Date
    public let executableAt: Date

    public init(requestId: String, status: String, requestedAt: Date, executableAt: Date) {
        self.requestId = requestId
        self.status = status
        self.requestedAt = requestedAt
        self.executableAt = executableAt
    }
}
