import Foundation
import NozirNetworking

/// The one sentence a parent sees for a failure. Branches on the code and the
/// status only; the server's own `message` is for logs and never reaches here.
enum UserMessage {
    static func text(for error: any Error) -> String {
        guard let failure = error as? ApiFailure else { return Copy.Errors.serverProblem }
        switch failure {
        case .network(let code):
            return code == URLError.Code.timedOut.rawValue ? Copy.Errors.timeout : Copy.Errors.noConnection
        case .server(let status, let apiError):
            if apiError.code == .rateLimited {
                return Copy.Errors.rateLimited(seconds: apiError.retryAfterSeconds)
            }
            if status == 503 || apiError.code == .upstreamUnavailable {
                return Copy.Errors.serviceUnavailable
            }
            return Copy.Errors.serverProblem
        case .sessionEnded:
            return Copy.Errors.sessionEnded
        case .decoding, .unexpectedStatus:
            return Copy.Errors.serverProblem
        }
    }
}
