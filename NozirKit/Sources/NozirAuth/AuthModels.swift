import Foundation

/// `TelegramLoginStartResponse`: where to send the parent and how long the
/// code they come back with lasts.
public struct TelegramLoginStart: Decodable, Equatable, Sendable {
    public let botUsername: String
    public let deepLink: URL
    public let codeLength: Int
    public let codeTtlSeconds: Int
}

/// `ParentAccountResponse`. `role` stays a string: the app does not branch on it yet.
public struct ParentAccount: Decodable, Equatable, Sendable {
    public let parentId: UUID
    public let familyId: UUID
    public let phoneE164: String?
    public let displayName: String?
    public let locale: String
    public let timeZone: String
    public let role: String
    public let createdAt: Date
}

/// `ParentAuthResponse`: a flattened token pair plus the parent.
struct ParentAuthResult: Decodable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let parent: ParentAccount
    let isNewAccount: Bool

    var tokens: TokenPair {
        TokenPair(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }
}
