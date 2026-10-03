import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirAuth

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")

// TelegramLoginStartResponse, AuthDtos.kt
private let startBody = #"{"botUsername":"nozir_bot","deepLink":"https://t.me/nozir_bot","codeLength":6,"codeTtlSeconds":180}"#

// ParentAuthResponse, AuthDtos.kt. phoneE164 is absent: a Telegram parent who added no number.
private let signedInBody = #"""
{"accessToken":"acc-1","accessTokenExpiresAt":"2026-10-03T11:46:09Z","refreshToken":"ref-1","refreshTokenExpiresAt":"2026-11-02T11:31:09Z","parent":{"parentId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","familyId":"2c5ea4c0-4067-11e9-8bad-9b1deb4d3b7d","displayName":"Zohid","locale":"uz","timeZone":"Asia/Tashkent","role":"OWNER","createdAt":"2026-09-01T08:00:00Z"},"isNewAccount":false}
"""#

// TokenPairResponse, AuthDtos.kt
private let refreshedBody = #"{"accessToken":"acc-2","accessTokenExpiresAt":"2026-10-03T11:46:09Z","refreshToken":"ref-2","refreshTokenExpiresAt":"2026-11-02T11:31:09Z"}"#

private let expectedTokens = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

private func makeAuth(_ replies: [FakeTransport.Reply]) -> (AuthApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(baseURL: URL(string: "https://api.test")!, transport: transport, identity: identity)
    return (AuthApi(client: client), transport)
}

@Suite struct TelegramSignInTests {
    @Test func startAsksTheServerWhereToSendTheParent() async throws {
        let (api, transport) = makeAuth([.ok(startBody)])
        let signIn = TelegramSignIn(api: api, store: InMemoryTokenStore(), deviceLabel: "iPhone")

        let start = try await signIn.start()

        let requests = await transport.requests
        #expect(start == TelegramLoginStart(
            botUsername: "nozir_bot",
            deepLink: URL(string: "https://t.me/nozir_bot")!,
            codeLength: 6,
            codeTtlSeconds: 180
        ))
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url?.path == "/v1/auth/telegram/start")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aServerWithoutABotAnswers503() async {
        let (api, _) = makeAuth([.error(503, code: "UPSTREAM_UNAVAILABLE")])
        let signIn = TelegramSignIn(api: api, store: InMemoryTokenStore(), deviceLabel: "iPhone")

        await #expect(throws: ApiFailure.server(status: 503, error: ApiError(code: .upstreamUnavailable, message: "server text"))) {
            try await signIn.start()
        }
    }

    @Test func aGoodCodeSavesTheSession() async throws {
        let (api, transport) = makeAuth([.ok(signedInBody)])
        let store = InMemoryTokenStore()
        let signIn = TelegramSignIn(api: api, store: store, deviceLabel: "iPhone")

        try await signIn.verify(code: "123456")

        let requests = await transport.requests
        #expect(requests.first?.url?.path == "/v1/auth/telegram/verify")
        #expect(requests.first?.jsonBody == ["code": "123456", "deviceLabel": "iPhone"])
        #expect(store.load() == expectedTokens)
    }

    @Test func aRejectedCodeSavesNothing() async {
        let (api, _) = makeAuth([.error(400, code: "OTP_CODE_INVALID")])
        let store = InMemoryTokenStore()
        let signIn = TelegramSignIn(api: api, store: store, deviceLabel: "iPhone")

        await #expect(throws: ApiFailure.server(status: 400, error: ApiError(code: .otpCodeInvalid, message: "server text"))) {
            try await signIn.verify(code: "000000")
        }
        #expect(store.load() == nil)
    }

    @Test func refreshPresentsTheRefreshTokenAnonymously() async throws {
        let (api, transport) = makeAuth([.ok(refreshedBody)])

        let renewed = try await api.refresh("ref-1")

        let requests = await transport.requests
        #expect(renewed.accessToken == "acc-2")
        #expect(renewed.refreshToken == "ref-2")
        #expect(requests.first?.url?.path == "/v1/auth/token/refresh")
        #expect(requests.first?.jsonBody == ["refreshToken": "ref-1"])
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func theParentAccountDecodesWithAnAbsentOrNullPhone() throws {
        let withNull = Data(#"""
        {"parentId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","familyId":"2c5ea4c0-4067-11e9-8bad-9b1deb4d3b7d","phoneE164":null,"displayName":null,"locale":"uz","timeZone":"Asia/Tashkent","role":"GUARDIAN","createdAt":"2026-09-01T08:00:00Z"}
        """#.utf8)
        let account = try NozirJSON.decoder().decode(ParentAccount.self, from: withNull)
        #expect(account.phoneE164 == nil)
        #expect(account.role == "GUARDIAN")
        #expect(account.createdAt == Date(timeIntervalSince1970: 1_788_249_600))
    }
}
