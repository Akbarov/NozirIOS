import Foundation
import Testing
import NozirTestSupport
@testable import NozirNetworking

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
private let base = URL(string: "https://api.test")!

private actor FakeTokens: AccessTokenProvider {
    private var current: String
    private let renewed: String
    private(set) var rejected: [String] = []
    private(set) var endedFor: [String] = []

    init(current: String, renewed: String = "renewed") {
        self.current = current
        self.renewed = renewed
    }

    func validAccessToken() async throws -> String { current }

    func refreshAfterRejection(of token: String) async throws -> String {
        rejected.append(token)
        current = renewed
        return renewed
    }

    func endSession(rejecting token: String) async {
        endedFor.append(token)
    }
}

/// A transport that fails the way URLSession does when its task is cancelled.
private struct CancelledTransport: HTTPTransport {
    let error: any Error

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw error
    }
}

private struct Echo: Decodable, Equatable {
    let value: String
}

@Suite struct ApiClientTests {
    @Test func anonymousRequestCarriesTheClientHeaderAndNoBearer() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        _ = try await client.send(
            ApiRequest(method: .get, path: "/v1/config", query: ["clientKind": "PARENT_IOS"], requiresAuth: false),
            as: Echo.self
        )

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(sent.url?.absoluteString == "https://api.test/v1/config?clientKind=PARENT_IOS")
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "X-Nozir-Client") == "nozir-parent/1.0.0 (ios; 17.5)")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    // Final review: /v1/config is served with Cache-Control max-age=900 and no
    // Vary on X-Nozir-Client, so a cached "update required" would outlive the update.
    @Test func everyRequestBypassesTheHTTPCache() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        _ = try await client.send(ApiRequest(method: .get, path: "/v1/config", requiresAuth: false), as: Echo.self)

        let requests = await transport.requests
        #expect(requests.first?.cachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test func aTrailingSlashOnTheBaseURLDoesNotDoubleTheSlash() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: URL(string: "https://api.test/")!, transport: transport, identity: identity)

        _ = try await client.send(ApiRequest(method: .get, path: "/v1/config", requiresAuth: false), as: Echo.self)

        let requests = await transport.requests
        #expect(requests.first?.url?.absoluteString == "https://api.test/v1/config")
    }

    @Test func aJSONPostCarriesItsBodyAndContentType() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        _ = try await client.send(
            try .post("/v1/auth/telegram/verify", json: ["code": "123456"], requiresAuth: false),
            as: Echo.self
        )

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.jsonBody == ["code": "123456"])
    }

    @Test func anAuthorisedRequestCarriesTheBearer() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        let echo = try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        let requests = await transport.requests
        #expect(echo == Echo(value: "x"))
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer acc-1")
    }

    @Test func aServerErrorIsThrownInTheOneShape() async {
        let transport = FakeTransport([.error(400, code: "VALIDATION_FAILED")])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        await #expect(throws: ApiFailure.server(
            status: 400,
            error: ApiError(code: ApiErrorCode(rawValue: "VALIDATION_FAILED"), message: "server text")
        )) {
            try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }

    @Test func a401IsRefreshedOnceAndRetriedWithTheNewToken() async throws {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .ok(#"{"value":"after"}"#)])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        let echo = try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        let requests = await transport.requests
        let rejected = await tokens.rejected
        #expect(echo == Echo(value: "after"))
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
        #expect(rejected == ["acc-1"])
    }

    // AUTH_AND_TOKENS.md: refresh once and retry once. A 401 after that is a
    // session the server no longer accepts.
    @Test func aSecond401IsNotRetriedAndEndsTheSession() async {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .error(401, code: "TOKEN_EXPIRED")])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        let rejected = await tokens.rejected
        let ended = await tokens.endedFor
        #expect(requests.count == 2)
        #expect(rejected.count == 1)
        #expect(ended == ["renewed"])
    }

    // AUTH_AND_TOKENS.md: on TOKEN_REVOKED or INVALID_TOKEN, sign out — do not retry.
    @Test(arguments: ["TOKEN_REVOKED", "INVALID_TOKEN"])
    func aRevokedOrInvalidTokenEndsTheSessionWithoutARefresh(code: String) async {
        let transport = FakeTransport([.error(401, code: code), .ok(#"{"value":"never"}"#)])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        let rejected = await tokens.rejected
        let ended = await tokens.endedFor
        #expect(requests.count == 1)
        #expect(rejected.isEmpty)
        #expect(ended == ["acc-1"])
    }

    @Test func theRetryRepeatsTheSameMethodAndBody() async throws {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .ok(#"{"value":"after"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        _ = try await client.send(try .post("/v1/parent/x", json: ["name": "Ali"]), as: Echo.self)

        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.last?.httpMethod == "POST")
        #expect(requests.last?.jsonBody == ["name": "Ali"])
    }

    // A SwiftUI .task that goes away cancels its request; that is not "no connection".
    @Test(arguments: [URLError(.cancelled) as any Error, CancellationError() as any Error])
    func cancellationIsNotANetworkFailure(error: any Error) async {
        let client = ApiClient(baseURL: base, transport: CancelledTransport(error: error), identity: identity)

        await #expect(throws: CancellationError.self) {
            try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }

    @Test func noConnectionIsANetworkFailure() async {
        let client = ApiClient(baseURL: base, transport: FakeTransport([]), identity: identity)

        await #expect(throws: ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)) {
            try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }

    @Test func aNoContentAnswerIsASuccess() async throws {
        let transport = FakeTransport([.init(status: 204)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        try await client.send(ApiRequest(method: .post, path: "/v1/auth/logout"))

        let requests = await transport.requests
        #expect(requests.count == 1)
    }

    @Test func anAuthorisedRequestWithoutASessionIsNotSent() async {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        #expect(requests.isEmpty)
    }

    @Test func aSuccessWithTheWrongShapeIsADecodingFailure() async {
        let client = ApiClient(baseURL: base, transport: FakeTransport([.ok("{}")]), identity: identity)

        do {
            _ = try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
            Issue.record("expected a decoding failure")
        } catch let failure as ApiFailure {
            guard case .decoding = failure else {
                Issue.record("expected .decoding, got \(failure)")
                return
            }
        } catch {
            Issue.record("expected ApiFailure, got \(error)")
        }
    }
}
