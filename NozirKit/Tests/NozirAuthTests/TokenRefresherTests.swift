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

        var events = refresher.sessionEnded.makeAsyncIterator()
        let event: Void? = await events.next()
        #expect(store.load() == nil)
        #expect(event != nil)
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

        await refresher.endSession()

        var events = refresher.sessionEnded.makeAsyncIterator()
        let event: Void? = await events.next()
        #expect(store.load() == nil)
        #expect(event != nil)
    }
}
