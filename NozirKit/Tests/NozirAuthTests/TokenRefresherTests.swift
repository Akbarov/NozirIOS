import Foundation
import Testing
import NozirNetworking
@testable import NozirAuth

private let now = Date(timeIntervalSince1970: 1_791_027_069)

private func pair(_ name: String, accessExpiresIn seconds: TimeInterval) -> TokenPair {
    TokenPair(
        accessToken: "acc-\(name)",
        accessTokenExpiresAt: now.addingTimeInterval(seconds),
        refreshToken: "ref-\(name)",
        refreshTokenExpiresAt: now.addingTimeInterval(30 * 24 * 3600)
    )
}

/// Stands in for POST /v1/auth/token/refresh and counts how often it was called.
private actor RefreshEndpoint {
    private let outcome: Result<TokenPair, ApiFailure>
    private(set) var presented: [String] = []

    init(_ outcome: Result<TokenPair, ApiFailure>) {
        self.outcome = outcome
    }

    func refresh(_ refreshToken: String) async throws -> TokenPair {
        presented.append(refreshToken)
        // Long enough for every concurrent caller to arrive while this is in flight.
        try await Task.sleep(for: .milliseconds(100))
        return try outcome.get()
    }
}

/// A refresh endpoint that holds every call at a gate until the test opens it,
/// so a test can act while a refresh is provably in flight.
private actor GatedRefreshEndpoint {
    private let renewed: TokenPair
    private var waiting: CheckedContinuation<Void, Never>?
    private(set) var presented: [String] = []

    init(_ renewed: TokenPair) {
        self.renewed = renewed
    }

    func refresh(_ refreshToken: String) async -> TokenPair {
        presented.append(refreshToken)
        await withCheckedContinuation { waiting = $0 }
        return renewed
    }

    /// Returns once a refresh is waiting at the gate.
    func untilWaiting() async {
        while waiting == nil { await Task.yield() }
    }

    func release() {
        waiting?.resume()
        waiting = nil
    }
}

/// A store whose save always fails, as a keychain can.
private final class FailingSaveStore: TokenStore, @unchecked Sendable {
    private let inner: InMemoryTokenStore

    init(_ tokens: TokenPair) {
        inner = InMemoryTokenStore(tokens)
    }

    func load() -> TokenPair? { inner.load() }
    func save(_ tokens: TokenPair) throws { throw KeychainError(status: -34018) }
    func clear() { inner.clear() }
}

/// True if the stream emits within `seconds`. Never waits forever: a test that
/// expects an event must fail, not hang, when the event does not come.
private func emits(_ stream: AsyncStream<Void>, within seconds: Double = 1) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            var events = stream.makeAsyncIterator()
            return await events.next() != nil
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
}

private func makeRefresher(store: InMemoryTokenStore, endpoint: RefreshEndpoint) -> TokenRefresher {
    TokenRefresher(store: store, now: { now }, refresh: { try await endpoint.refresh($0) })
}

@Suite struct TokenRefresherTests {
    @Test func aFreshTokenIsReturnedWithoutRefreshing() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 600))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.validAccessToken()

        let presented = await endpoint.presented
        #expect(token == "acc-1")
        #expect(presented.isEmpty)
    }

    @Test func aTokenAboutToExpireIsRefreshedFirstAndTheNewPairSaved() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 20))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.validAccessToken()

        let presented = await endpoint.presented
        #expect(token == "acc-2")
        #expect(presented == ["ref-1"])
        #expect(store.load() == pair("2", accessExpiresIn: 900))
    }

    @Test func fiveCallersAtOnceCauseOneRefresh() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.validAccessToken() }
            }
            var collected: [String] = []
            for try await token in group { collected.append(token) }
            return collected
        }

        let presented = await endpoint.presented
        #expect(tokens == Array(repeating: "acc-2", count: 5))
        #expect(presented == ["ref-1"])
    }

    @Test func aRejectionOfAnAlreadyReplacedTokenDoesNotRefreshAgain() async throws {
        let store = InMemoryTokenStore(pair("2", accessExpiresIn: 900))
        let endpoint = RefreshEndpoint(.success(pair("3", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.refreshAfterRejection(of: "acc-1")

        let presented = await endpoint.presented
        #expect(token == "acc-2")
        #expect(presented.isEmpty)
    }

    @Test func aRejectionOfTheCurrentTokenRefreshes() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 900))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.refreshAfterRejection(of: "acc-1")

        #expect(token == "acc-2")
    }

    @Test func aRevokedRefreshTokenEndsTheSession() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let revoked = ApiFailure.server(status: 401, error: ApiError(code: .tokenRevoked))
        let endpoint = RefreshEndpoint(.failure(revoked))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await refresher.validAccessToken()
        }

        let ended = await emits(refresher.sessionEnded)
        #expect(store.load() == nil)
        #expect(ended)
    }

    @Test func aNetworkFailureKeepsTheSession() async throws {
        let original = pair("1", accessExpiresIn: -5)
        let store = InMemoryTokenStore(original)
        let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)
        let refresher = makeRefresher(store: store, endpoint: RefreshEndpoint(.failure(offline)))

        await #expect(throws: offline) {
            try await refresher.validAccessToken()
        }
        #expect(store.load() == original)
    }

    @Test func noStoredSessionIsAnEndedSession() async {
        let refresher = makeRefresher(
            store: InMemoryTokenStore(),
            endpoint: RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        )

        await #expect(throws: ApiFailure.sessionEnded) {
            try await refresher.validAccessToken()
        }
    }

    // Review ruling: ApiClient calls endSession() on TOKEN_REVOKED / INVALID_TOKEN
    // and on a 401 after the retry.
    @Test func endingTheSessionForgetsItAndTellsTheApp() async {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 600))
        let refresher = makeRefresher(
            store: store,
            endpoint: RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        )

        await refresher.endSession(rejecting: "acc-1")

        let ended = await emits(refresher.sessionEnded)
        #expect(store.load() == nil)
        #expect(ended)
    }

    // Review (Auth) Important 1a: the app ended the session while a refresh was
    // in flight; the refresh's answer must not bring it back.
    @Test func aSessionEndedDuringARefreshStaysEnded() async {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let endpoint = GatedRefreshEndpoint(pair("2", accessExpiresIn: 900))
        let refresher = TokenRefresher(store: store, now: { now }, refresh: { await endpoint.refresh($0) })

        let caller = Task { try await refresher.validAccessToken() }
        await endpoint.untilWaiting()
        await refresher.endSession(rejecting: "acc-1")
        await endpoint.release()

        await #expect(throws: ApiFailure.sessionEnded) { try await caller.value }
        #expect(store.load() == nil)
    }

    // Review (Auth) Important 1b: a new sign-in during an old session's refresh is kept.
    @Test func aNewSignInDuringARefreshIsKept() async {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let endpoint = GatedRefreshEndpoint(pair("2", accessExpiresIn: 900))
        let refresher = TokenRefresher(store: store, now: { now }, refresh: { await endpoint.refresh($0) })

        let caller = Task { try await refresher.validAccessToken() }
        await endpoint.untilWaiting()
        try? store.save(pair("fresh", accessExpiresIn: 900))
        await endpoint.release()

        await #expect(throws: ApiFailure.sessionEnded) { try await caller.value }
        #expect(store.load() == pair("fresh", accessExpiresIn: 900))
    }

    // Review (Auth) Important 2: the old pair is spent and the new one cannot be
    // kept, so the session ends now instead of failing every request silently.
    @Test func aRefreshThatCannotBeSavedEndsTheSession() async {
        let store = FailingSaveStore(pair("1", accessExpiresIn: -5))
        let refresher = TokenRefresher(store: store, now: { now }, refresh: { _ in pair("2", accessExpiresIn: 900) })

        await #expect(throws: ApiFailure.sessionEnded) { try await refresher.validAccessToken() }

        let ended = await emits(refresher.sessionEnded)
        #expect(store.load() == nil)
        #expect(ended)
    }

    // Review Focus 5 for 401s: several requests rejected with the same token cause one refresh.
    @Test func concurrentRejectionsOfTheSameTokenCauseOneRefresh() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 600))
        let endpoint = GatedRefreshEndpoint(pair("2", accessExpiresIn: 900))
        let refresher = TokenRefresher(store: store, now: { now }, refresh: { await endpoint.refresh($0) })

        let callers = (0..<3).map { _ in Task { try await refresher.refreshAfterRejection(of: "acc-1") } }
        await endpoint.untilWaiting()
        for _ in 0..<50 { await Task.yield() }
        await endpoint.release()

        var tokens: [String] = []
        for caller in callers { tokens.append(try await caller.value) }
        let presented = await endpoint.presented
        #expect(tokens == ["acc-2", "acc-2", "acc-2"])
        #expect(presented == ["ref-1"])
    }

    // Review (Auth) Important 1b: a late 401 for an old token does not end a newer session.
    @Test func endingAnOlderSessionLeavesTheCurrentOneAlone() async {
        let store = InMemoryTokenStore(pair("2", accessExpiresIn: 900))
        let refresher = makeRefresher(store: store, endpoint: RefreshEndpoint(.success(pair("3", accessExpiresIn: 900))))

        await refresher.endSession(rejecting: "acc-1")

        #expect(store.load() == pair("2", accessExpiresIn: 900))
        #expect(await emits(refresher.sessionEnded, within: 0.2) == false)
    }
}
