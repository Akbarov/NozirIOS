import Foundation
import NozirNetworking

/// The only place a refresh token is spent.
///
/// The server revokes the whole session when a rotated refresh token is shown
/// again (`RefreshTokenServiceImpl.onReuseDetected`), so two refreshes must
/// never race: every caller that needs one while another is in flight waits
/// for that one instead of starting its own.
public actor TokenRefresher: AccessTokenProvider {
    public typealias RefreshCall = @Sendable (String) async throws -> TokenPair

    /// Refresh this long before the access token expires, not after.
    private let leeway: TimeInterval = 30
    private let store: any TokenStore
    private let now: @Sendable () -> Date
    private let refresh: RefreshCall
    private var inFlight: Task<TokenPair, any Error>?

    /// Emits once each time the server ends the session. Single consumer: AppModel.
    public nonisolated let sessionEnded: AsyncStream<Void>
    private let sessionEndedContinuation: AsyncStream<Void>.Continuation

    public init(
        store: any TokenStore,
        now: @escaping @Sendable () -> Date = { Date() },
        refresh: @escaping RefreshCall
    ) {
        self.store = store
        self.now = now
        self.refresh = refresh
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.sessionEnded = stream
        self.sessionEndedContinuation = continuation
    }

    public func validAccessToken() async throws -> String {
        guard let tokens = store.load() else { throw ApiFailure.sessionEnded }
        if tokens.accessTokenExpiresAt.timeIntervalSince(now()) > leeway {
            return tokens.accessToken
        }
        return try await rotate(using: tokens.refreshToken).accessToken
    }

    public func refreshAfterRejection(of token: String) async throws -> String {
        guard let tokens = store.load() else { throw ApiFailure.sessionEnded }
        if tokens.accessToken != token {
            // Somebody refreshed after `token` was handed out; use theirs.
            return tokens.accessToken
        }
        return try await rotate(using: tokens.refreshToken).accessToken
    }

    /// The server refused `token` for good (see `ApiClient`). Ends the session
    /// only if `token` is still the stored one: a late answer to an old request
    /// must not sign out a parent who has since signed in again.
    public func endSession(rejecting token: String) {
        guard store.load()?.accessToken == token else { return }
        store.clear()
        sessionEndedContinuation.yield()
    }

    private func rotate(using refreshToken: String) async throws -> TokenPair {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [store, refresh, sessionEndedContinuation] () async throws -> TokenPair in
            // Every write below is conditional on the store still holding the
            // session this refresh started from: while it was in flight the
            // session may have been ended, or replaced by a new sign-in.
            do {
                let renewed = try await refresh(refreshToken)
                guard store.load()?.refreshToken == refreshToken else {
                    throw ApiFailure.sessionEnded
                }
                do {
                    try store.save(renewed)
                } catch {
                    // The old pair is spent and the new one cannot be kept, so
                    // nothing usable remains: end the session now, visibly.
                    store.clear()
                    sessionEndedContinuation.yield()
                    throw ApiFailure.sessionEnded
                }
                return renewed
            } catch let failure as ApiFailure where failure.endsSession {
                if store.load()?.refreshToken == refreshToken {
                    store.clear()
                    sessionEndedContinuation.yield()
                }
                throw ApiFailure.sessionEnded
            }
        }
        inFlight = task
        defer { if inFlight == task { inFlight = nil } }
        return try await task.value
    }
}
