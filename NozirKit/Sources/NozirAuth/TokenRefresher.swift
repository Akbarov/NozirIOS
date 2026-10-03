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

    /// The server no longer accepts this session (see `ApiClient`): forget it
    /// and tell the app, exactly as a refused refresh does.
    public func endSession() {
        store.clear()
        sessionEndedContinuation.yield()
    }

    private func rotate(using refreshToken: String) async throws -> TokenPair {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [store, refresh, sessionEndedContinuation] () async throws -> TokenPair in
            do {
                let renewed = try await refresh(refreshToken)
                // A failed save is not a failed refresh: the new pair is valid
                // for this run. The next launch will find the old pair, present
                // a spent token and be signed out, which is the safe outcome.
                try? store.save(renewed)
                return renewed
            } catch let failure as ApiFailure where failure.endsSession {
                store.clear()
                sessionEndedContinuation.yield()
                throw ApiFailure.sessionEnded
            }
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
