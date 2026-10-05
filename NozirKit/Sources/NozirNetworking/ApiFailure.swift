/// Everything that can go wrong with a call, in the one shape callers handle.
public enum ApiFailure: Error, Equatable, Sendable {
    /// The server answered with the error body.
    case server(status: Int, error: ApiError)
    /// No answer at all. `code` is `URLError.Code.rawValue`.
    case network(code: Int)
    /// A 2xx whose body did not match the expected shape.
    case decoding(String)
    /// A non-2xx without the error body (a proxy's HTML page, for example).
    case unexpectedStatus(Int)
    /// There is no session, or the server has ended it. Tokens are gone.
    case sessionEnded

    public var code: ApiErrorCode? {
        guard case .server(_, let error) = self else { return nil }
        return error.code
    }

    /// True when the server refused the session's credentials with a 401.
    /// `TokenRefresher` reads it on the refresh endpoint's answer; `ApiClient`
    /// decides on ordinary calls itself. A network failure never ends a session.
    public var endsSession: Bool {
        guard case .server(let status, let error) = self, status == 401 else { return false }
        return [.tokenExpired, .tokenRevoked, .invalidToken, .unauthenticated].contains(error.code)
    }

    /// A 404, with or without the error body. For the pairing code it is an
    /// answer ("no live code"), not a fault.
    public var isNotFound: Bool {
        switch self {
        case .server(let status, _): status == 404
        case .unexpectedStatus(let status): status == 404
        default: false
        }
    }
}
