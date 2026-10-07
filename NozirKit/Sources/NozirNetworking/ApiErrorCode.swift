/// The server's machine-readable error code (`ErrorCode.kt`). A struct rather
/// than an enum so that a code added on the server later still decodes.
public struct ApiErrorCode: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let unauthenticated = ApiErrorCode(rawValue: "UNAUTHENTICATED")
    public static let tokenExpired = ApiErrorCode(rawValue: "TOKEN_EXPIRED")
    public static let tokenRevoked = ApiErrorCode(rawValue: "TOKEN_REVOKED")
    public static let invalidToken = ApiErrorCode(rawValue: "INVALID_TOKEN")
    public static let otpCodeInvalid = ApiErrorCode(rawValue: "OTP_CODE_INVALID")
    public static let otpCodeExpired = ApiErrorCode(rawValue: "OTP_CODE_EXPIRED")
    public static let rateLimited = ApiErrorCode(rawValue: "RATE_LIMITED")
    public static let upstreamUnavailable = ApiErrorCode(rawValue: "UPSTREAM_UNAVAILABLE")
    public static let signInMethodDisabled = ApiErrorCode(rawValue: "SIGN_IN_METHOD_DISABLED")
    public static let internalError = ApiErrorCode(rawValue: "INTERNAL_ERROR")
    public static let forbidden = ApiErrorCode(rawValue: "FORBIDDEN")
    public static let notYourChild = ApiErrorCode(rawValue: "NOT_YOUR_CHILD")
    public static let notFound = ApiErrorCode(rawValue: "NOT_FOUND")
    public static let conflict = ApiErrorCode(rawValue: "CONFLICT")
    public static let validationFailed = ApiErrorCode(rawValue: "VALIDATION_FAILED")
    public static let missingIfMatch = ApiErrorCode(rawValue: "MISSING_IF_MATCH")
    public static let phoneNumberInvalid = ApiErrorCode(rawValue: "PHONE_NUMBER_INVALID")
    public static let childLimitReached = ApiErrorCode(rawValue: "CHILD_LIMIT_REACHED")
    public static let childNotActive = ApiErrorCode(rawValue: "CHILD_NOT_ACTIVE")
    public static let subscriptionRequired = ApiErrorCode(rawValue: "SUBSCRIPTION_REQUIRED")
    public static let safeZoneLimitReached = ApiErrorCode(rawValue: "SAFE_ZONE_LIMIT_REACHED")
    /// A decision on something already decided: an extra-time ask the other
    /// parent answered, or one that expired (P17).
    public static let alreadyDecided = ApiErrorCode(rawValue: "ALREADY_DECIDED")
}
