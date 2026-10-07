import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirPrivacy

/// A bearer that never expires: these tests are about the privacy calls, not tokens.
private struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

private func privacyApi(_ replies: [FakeTransport.Reply]) -> (PrivacyApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (PrivacyApi(client: client), transport)
}

/// `TransparencyDisclosureResponse` as the backend writes it.
private let disclosureJSON = """
    {"documentVersion":"2026-10-01","locale":"uz",\
    "seen":[{"key":"screen_time","text":"Ekran vaqti"},{"key":"location","text":"Joylashuv"}],\
    "notSeen":[{"key":"messages","text":"Xabarlar"}]}
    """

/// `DataDeletionRequestResponse` (the 202, and the body of GET …/current).
private let requestJSON = """
    {"requestId":"5d1c8a52-6a2f-4d8b-9a55-6f1b2a0c1d09","subjectChildId":null,\
    "requestedAt":"2026-10-07T10:00:00.123456Z","executableAt":"2026-10-14T10:00:00Z"}
    """

private let executableAt = Date(timeIntervalSince1970: 1_791_972_000) // 2026-10-14T10:00:00Z

@Suite struct PrivacyApiTests {
    @Test func theDisclosureIsReadAsTheServerWroteIt() async throws {
        let (api, transport) = privacyApi([.ok(disclosureJSON)])

        let disclosure = try await api.disclosure()

        #expect(disclosure.documentVersion == "2026-10-01")
        #expect(disclosure.seen.map(\.text) == ["Ekran vaqti", "Joylashuv"])
        #expect(disclosure.notSeen == [DisclosureItem(key: "messages", text: "Xabarlar")])
        #expect(!disclosure.isEmpty)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/privacy/disclosure")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer acc")
    }

    // Android `PrivacyDisclosureDto` defaults: missing lists are empty, not a failure.
    @Test func aDisclosureWithoutListsIsEmpty() async throws {
        let (api, _) = privacyApi([.ok(#"{"documentVersion":"2026-10-01"}"#)])

        let disclosure = try await api.disclosure()

        #expect(disclosure.isEmpty)
        #expect(disclosure.locale == "")
    }

    @Test func theDeletionRequestAsksForTheWholeFamily() async throws {
        let (api, transport) = privacyApi([.init(status: 202, body: requestJSON)])

        let recorded = try await api.requestDeletion()

        #expect(recorded.executableAt == executableAt)
        #expect(recorded.requestId == "5d1c8a52-6a2f-4d8b-9a55-6f1b2a0c1d09")
        #expect(recorded.requestedAt != nil)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/parent/data-deletion-requests")
        #expect(request.jsonObject?.isEmpty == true)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func aRequestAnswerWithoutRequestedAtStillReads() async throws {
        let body = #"{"requestId":"r-1","executableAt":"2026-10-14T10:00:00Z"}"#
        let (api, _) = privacyApi([.init(status: 202, body: body)])

        let recorded = try await api.requestDeletion()

        #expect(recorded == ErasureRequest(requestId: "r-1", requestedAt: nil, executableAt: executableAt))
    }

    @Test func aGuardiansRequestIsRefused() async {
        let (api, _) = privacyApi([.error(403, code: "FORBIDDEN")])

        await #expect(throws: ApiFailure.server(status: 403, error: ApiError(code: .forbidden, message: "server text"))) {
            try await api.requestDeletion()
        }
    }

    @Test func aPendingRequestIsRead() async throws {
        let body = """
            {"requestId":"5d1c8a52-6a2f-4d8b-9a55-6f1b2a0c1d09","status":"PENDING",\
            "requestedAt":"2026-10-07T10:00:00Z","executableAt":"2026-10-14T10:00:00Z"}
            """
        let (api, transport) = privacyApi([.ok(body)])

        let current = try await api.currentDeletion()

        #expect(current?.status == "PENDING")
        #expect(current?.executableAt == executableAt)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/data-deletion-requests/current")
    }

    @Test func noPendingRequestIsNil() async throws {
        let (api, _) = privacyApi([.init(status: 204)])

        #expect(try await api.currentDeletion() == nil)
    }
}
