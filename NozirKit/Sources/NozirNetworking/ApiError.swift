import Foundation

/// The body of every non-2xx response (`ApiError.kt`). `message` is for logs
/// only and is never shown to a parent.
public struct ApiError: Decodable, Equatable, Sendable {
    public let code: ApiErrorCode
    public let message: String
    public let field: String?
    public let violations: [FieldViolation]
    public let retryAfterSeconds: Int?
    /// Safe to show on a support screen.
    public let traceId: String?

    public init(
        code: ApiErrorCode,
        message: String = "",
        field: String? = nil,
        violations: [FieldViolation] = [],
        retryAfterSeconds: Int? = nil,
        traceId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.field = field
        self.violations = violations
        self.retryAfterSeconds = retryAfterSeconds
        self.traceId = traceId
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, field, violations, retryAfterSeconds, traceId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(ApiErrorCode.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        field = try container.decodeIfPresent(String.self, forKey: .field)
        violations = try container.decodeIfPresent([FieldViolation].self, forKey: .violations) ?? []
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
    }
}

public struct FieldViolation: Decodable, Equatable, Sendable {
    public let field: String
    public let code: ApiErrorCode
    public let message: String
}

private struct ErrorResponse: Decodable {
    let error: ApiError
}

enum ResponseMapping {
    static func failure(status: Int, body: Data) -> ApiFailure {
        guard let envelope = try? NozirJSON.decoder().decode(ErrorResponse.self, from: body) else {
            return .unexpectedStatus(status)
        }
        return .server(status: status, error: envelope.error)
    }
}
