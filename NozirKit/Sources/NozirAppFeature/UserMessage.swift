import Foundation
import NozirL10n
import NozirNetworking

/// What a parent is told, kept as a meaning rather than a sentence: the view
/// renders it in the current language, so switching language also translates a
/// message already on screen. Branches on the code and the status only; the
/// server's own `message` never reaches here.
public enum UserMessage: Equatable, Sendable {
    case noConnection, timeout, serviceUnavailable, serverProblem, unreadableAnswer
    case sessionEnded, permissionDenied, notFound, invalidRequest, conflict
    case childLimitReached, subscriptionRequired, childNotActive
    case rateLimited(seconds: Int?)
    case codeRejected, telegramNotOpened

    /// Android `DataErrorFromApiFailure` and `ApiFailureFromStatus`: the code
    /// first, then the status, and "check what you entered" for the rest.
    public init(_ error: any Error) {
        guard let failure = error as? ApiFailure else {
            self = .serverProblem
            return
        }
        switch failure {
        case .network(let code):
            self = code == URLError.Code.timedOut.rawValue ? .timeout : .noConnection
        case .sessionEnded:
            self = .sessionEnded
        case .decoding:
            self = .unreadableAnswer
        case .unexpectedStatus(let status):
            self = Self.meaning(ofStatus: status, retryAfter: nil) ?? .invalidRequest
        case .server(let status, let error):
            self = Self.meaning(of: error)
                ?? Self.meaning(ofStatus: status, retryAfter: error.retryAfterSeconds)
                ?? .invalidRequest
        }
    }

    private static func meaning(of error: ApiError) -> UserMessage? {
        switch error.code {
        case .rateLimited: return .rateLimited(seconds: error.retryAfterSeconds)
        case .upstreamUnavailable: return .serviceUnavailable
        case .childLimitReached: return .childLimitReached
        case .subscriptionRequired: return .subscriptionRequired
        case .childNotActive: return .childNotActive
        case .conflict: return .conflict
        case .forbidden, .notYourChild: return .permissionDenied
        case .notFound: return .notFound
        default: return nil
        }
    }

    private static func meaning(ofStatus status: Int, retryAfter: Int?) -> UserMessage? {
        switch status {
        case 401: return .sessionEnded
        case 404: return .notFound
        case 408: return .timeout
        case 429: return .rateLimited(seconds: retryAfter)
        case 503: return .serviceUnavailable
        case 500...: return .serverProblem
        default: return nil
        }
    }

    public func text(_ l10n: L10n) -> String {
        switch self {
        case .noConnection: l10n.dataErrorNoConnection
        case .timeout: l10n.dataErrorTimeout
        case .serviceUnavailable: l10n.signInErrorServiceUnavailable
        case .serverProblem: l10n.dataErrorServerProblem
        case .unreadableAnswer: l10n.dataErrorUnreadableAnswer
        case .sessionEnded: l10n.dataErrorNotAuthenticated
        case .permissionDenied: l10n.dataErrorPermissionDenied
        case .notFound: l10n.dataErrorNotFound
        case .invalidRequest: l10n.dataErrorInvalidRequest
        case .conflict: l10n.dataErrorConflict
        case .childLimitReached: l10n.dataErrorChildLimitReached
        case .subscriptionRequired: l10n.dataErrorSubscriptionRequired
        case .childNotActive: l10n.dataErrorChildNotActive
        case .rateLimited(let seconds):
            if let seconds { l10n.dataErrorRateLimitedSeconds(seconds) } else { l10n.dataErrorRateLimited }
        case .codeRejected: l10n.signInTelegramCodeRejected
        case .telegramNotOpened: l10n.signInTelegramNotOpenedOnlyDoor
        }
    }
}
