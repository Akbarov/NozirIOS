import Foundation
import Testing
@testable import NozirNetworking

@Suite struct ApiErrorTests {
    @Test func decodesTheSingleErrorShape() {
        // Shape: Nozir-Backend platform/api/ApiError.kt
        let body = Data(#"""
        {"error":{"code":"RATE_LIMITED","message":"slow down","retryAfterSeconds":42,"traceId":"t-1","timestamp":"2026-10-03T11:31:09.5Z"}}
        """#.utf8)
        let failure = ResponseMapping.failure(status: 429, body: body)
        let expected = ApiError(code: .rateLimited, message: "slow down", retryAfterSeconds: 42, traceId: "t-1")
        #expect(failure == .server(status: 429, error: expected))
    }

    @Test func readsFieldViolations() {
        let body = Data(#"""
        {"error":{"code":"VALIDATION_FAILED","message":"bad","field":"code","violations":[{"field":"code","code":"VALIDATION_FAILED","message":"must be the digits the bot sent"}]}}
        """#.utf8)
        guard case .server(_, let error) = ResponseMapping.failure(status: 400, body: body) else {
            Issue.record("expected a server failure")
            return
        }
        #expect(error.field == "code")
        #expect(error.violations == [
            FieldViolation(field: "code", code: ApiErrorCode(rawValue: "VALIDATION_FAILED"), message: "must be the digits the bot sent"),
        ])
    }

    @Test func keepsACodeThisAppDoesNotKnowYet() {
        let body = Data(#"{"error":{"code":"BRAND_NEW_CODE","message":"x"}}"#.utf8)
        #expect(ResponseMapping.failure(status: 409, body: body).code?.rawValue == "BRAND_NEW_CODE")
    }

    @Test func aBodyThatIsNotTheErrorShapeIsAnUnexpectedStatus() {
        let body = Data("<html>Bad gateway</html>".utf8)
        #expect(ResponseMapping.failure(status: 502, body: body) == .unexpectedStatus(502))
    }

    @Test(arguments: [ApiErrorCode.tokenExpired, .tokenRevoked, .invalidToken, .unauthenticated])
    func a401WithASessionCodeEndsTheSession(code: ApiErrorCode) {
        #expect(ApiFailure.server(status: 401, error: ApiError(code: code)).endsSession)
    }

    @Test func otherFailuresDoNotEndTheSession() {
        #expect(!ApiFailure.server(status: 403, error: ApiError(code: ApiErrorCode(rawValue: "FORBIDDEN"))).endsSession)
        #expect(!ApiFailure.server(status: 400, error: ApiError(code: .otpCodeInvalid)).endsSession)
        #expect(!ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue).endsSession)
        #expect(!ApiFailure.unexpectedStatus(401).endsSession)
    }
}
