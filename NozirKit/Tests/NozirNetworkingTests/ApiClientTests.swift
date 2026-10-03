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

    @Test func aSecond401IsNotRetriedAgain() async {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .error(401, code: "TOKEN_REVOKED")])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        await #expect(throws: ApiFailure.server(status: 401, error: ApiError(code: .tokenRevoked, message: "server text"))) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        let rejected = await tokens.rejected
        #expect(requests.count == 2)
        #expect(rejected.count == 1)
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
