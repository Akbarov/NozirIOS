import Foundation
import Testing
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private func server(_ status: Int, _ code: ApiErrorCode, retryAfter: Int? = nil) -> ApiFailure {
    .server(status: status, error: ApiError(code: code, retryAfterSeconds: retryAfter))
}

struct CodeCase: Sendable {
    let status: Int
    let code: ApiErrorCode
    let expected: UserMessage
}

@Suite struct UserMessageTests {
    @Test func theServerMessageIsNeverShown() {
        let failure = ApiFailure.server(status: 500, error: ApiError(code: .internalError, message: "NullPointerException at line 42"))

        let message = UserMessage(failure)

        #expect(message == .serverProblem)
        #expect(message.text(L10n(.uz)) == L10n(.uz).dataErrorServerProblem)
    }

    @Test func aTimeoutIsNotCalledANoConnection() {
        #expect(UserMessage(ApiFailure.network(code: URLError.Code.timedOut.rawValue)) == .timeout)
        #expect(UserMessage(ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)) == .noConnection)
    }

    @Test(arguments: [
        CodeCase(status: 403, code: .childLimitReached, expected: .childLimitReached),
        CodeCase(status: 403, code: .childNotActive, expected: .childNotActive),
        CodeCase(status: 403, code: .subscriptionRequired, expected: .subscriptionRequired),
        CodeCase(status: 409, code: .conflict, expected: .conflict),
        CodeCase(status: 403, code: .forbidden, expected: .permissionDenied),
        CodeCase(status: 403, code: .notYourChild, expected: .permissionDenied),
        CodeCase(status: 400, code: .validationFailed, expected: .invalidRequest),
        CodeCase(status: 400, code: .phoneNumberInvalid, expected: .invalidRequest),
        CodeCase(status: 404, code: .notFound, expected: .notFound),
        CodeCase(status: 503, code: .upstreamUnavailable, expected: .serviceUnavailable),
        CodeCase(status: 502, code: .internalError, expected: .serverProblem),
    ])
    func aCodeBecomesItsMeaning(_ testCase: CodeCase) {
        #expect(UserMessage(server(testCase.status, testCase.code)) == testCase.expected)
    }

    @Test func aStatusWithoutTheErrorBodyStillMeansSomething() {
        #expect(UserMessage(ApiFailure.unexpectedStatus(404)) == .notFound)
        #expect(UserMessage(ApiFailure.unexpectedStatus(502)) == .serverProblem)
        #expect(UserMessage(ApiFailure.unexpectedStatus(418)) == .invalidRequest)
    }

    @Test func anAnswerThatCannotBeReadSaysSo() {
        #expect(UserMessage(ApiFailure.decoding("keyNotFound")) == .unreadableAnswer)
    }

    @Test func rateLimitedSaysHowLongWhenItKnows() {
        let l10n = L10n(.uz)
        #expect(UserMessage(server(429, .rateLimited, retryAfter: 42)).text(l10n) == l10n.dataErrorRateLimitedSeconds(42))
        #expect(UserMessage(server(429, .rateLimited)).text(l10n) == l10n.dataErrorRateLimited)
    }

    @Test func theSameMeaningReadsInEveryLanguage() {
        #expect(UserMessage.noConnection.text(L10n(.ru)) == L10n(.ru).dataErrorNoConnection)
        #expect(UserMessage.sessionEnded.text(L10n(.en)).contains("Telegram"))
    }

    @Test func anErrorThatIsNotAnApiFailureIsAServerProblem() {
        struct Odd: Error {}
        #expect(UserMessage(Odd()) == .serverProblem)
    }
}
