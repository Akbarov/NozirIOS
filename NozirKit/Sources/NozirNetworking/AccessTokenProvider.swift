/// Where an authorised call gets its bearer. Implemented by `TokenRefresher`
/// in NozirAuth; declared here so the client does not depend on that module.
public protocol AccessTokenProvider: Sendable {
    /// A token that is not about to expire, refreshing first if it is.
    func validAccessToken() async throws -> String
    /// The server refused `token` with a 401: a newer one, refreshing only if
    /// nobody has refreshed since `token` was handed out.
    func refreshAfterRejection(of token: String) async throws -> String
}
