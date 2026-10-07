import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let decisionPath = "/v1/parent/extra-time-requests/7c3e1a20-1b2c-4d3e-8f4a-5b6c7d8e9f01/decision"

@Suite struct ExtraTimeApiTests {
    @Test func thePendingListIsAskedForByStatus() async throws {
        let (api, transport) = extraTimeApi([.ok(page(extraTimeJSON()))])

        let requests = try await api.pending()

        #expect(requests == [ExtraTimeRequest(
            id: requestId,
            childId: aliId,
            childName: "Ali",
            kind: .extraMinutes,
            requestedMinutes: 30,
            reason: "Uy vazifasi tugadi",
            status: .pending,
            createdAt: instant("2026-10-07T14:05:00Z"),
            requestsInLastSevenDays: 2
        )])
        #expect(requests.first?.isAnswerable == true)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/extra-time-requests")
        #expect(request.queryParameters == ["status": "PENDING"])
    }

    @Test func aPageWithACursorOrNoItemsStillReads() async throws {
        let (api, _) = extraTimeApi([.ok(#"{"items":[],"nextCursor":"abc"}"#), .ok("{}")])

        #expect(try await api.pending().isEmpty)
        #expect(try await api.pending().isEmpty)
    }

    @Test func anAbsentKindIsExtraMinutesAndABedtimeDelayKeepsItsNight() async throws {
        let night = #","nightOf":"2026-10-07""#
        let body = page(extraTimeJSON(kind: nil), extraTimeJSON(kind: "BEDTIME_DELAY", extra: night))
        let (api, _) = extraTimeApi([.ok(body)])

        let requests = try await api.pending()

        #expect(requests.map(\.kind) == [.extraMinutes, .bedtimeDelay])
        #expect(requests.map(\.nightOf) == [nil, LocalDate("2026-10-07")])
        #expect(requests[0].grantedMinutes == nil)
        #expect(requests[0].decisionNote == nil)
        #expect(requests[0].decidedAt == nil)
    }

    // Spec §6: a kind or status from a newer server is kept, and not offered for an answer.
    @Test func aKindOrStatusThisAppDoesNotKnowIsKeptAndNotAnswerable() async throws {
        let (api, _) = extraTimeApi([.ok(page(extraTimeJSON(kind: "SCHOOL_TRIP"), extraTimeJSON(status: "WITHDRAWN")))])

        let requests = try await api.pending()

        #expect(requests.map(\.kind) == [.unknown("SCHOOL_TRIP"), .extraMinutes])
        #expect(requests.map(\.status) == [.pending, .unknown("WITHDRAWN")])
        #expect(requests.map(\.isAnswerable) == [false, false])
    }

    @Test func approvingSendsOnlyTheOutcome() async throws {
        let answered = extraTimeJSON(status: "APPROVED", extra: #","grantedMinutes":30,"decidedAt":"2026-10-07T14:10:00Z""#)
        let (api, transport) = extraTimeApi([.ok(answered)])

        let request = try await api.decide(requestId, outcome: .approve, grantedMinutes: nil, note: nil)

        #expect(request.status == .approved)
        #expect(request.grantedMinutes == 30)
        #expect(request.decidedAt == instant("2026-10-07T14:10:00Z"))
        let sent = try #require(await transport.requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.url?.path == decisionPath)
        #expect(sent.jsonBody == ["outcome": "APPROVE"])
    }

    @Test func aPartialAnswerSendsItsMinutes() async throws {
        let (api, transport) = extraTimeApi([.ok(extraTimeJSON(status: "APPROVED", extra: #","grantedMinutes":15"#))])

        _ = try await api.decide(requestId, outcome: .partial, grantedMinutes: 15, note: nil)

        let body = try #require(await transport.requests.first?.jsonObject)
        #expect(body.count == 2)
        #expect(body["outcome"] as? String == "PARTIAL")
        #expect(body["grantedMinutes"] as? Int == 15)
    }

    @Test func aRefusalSendsItsNote() async throws {
        let (api, transport) = extraTimeApi([.ok(extraTimeJSON(status: "DECLINED", extra: #","decisionNote":"Ertaga gaplashamiz""#))])

        let request = try await api.decide(requestId, outcome: .decline, grantedMinutes: nil, note: "Ertaga gaplashamiz")

        #expect(request.status == .declined)
        #expect(request.decisionNote == "Ertaga gaplashamiz")
        #expect(await transport.requests.first?.jsonBody == ["outcome": "DECLINE", "note": "Ertaga gaplashamiz"])
    }

    @Test func anAnswerGivenElsewhereIsAlreadyDecided() async {
        let (api, _) = extraTimeApi([.error(409, code: "ALREADY_DECIDED")])

        await #expect(throws: ApiFailure.server(
            status: 409,
            error: ApiError(code: .alreadyDecided, message: "server text")
        )) {
            try await api.decide(requestId, outcome: .decline, grantedMinutes: nil, note: nil)
        }
    }

    // Global constraint: one tap, one POST — a lost connection is not retried.
    @Test func aDecisionThatFindsNoConnectionIsSentOnce() async {
        let (api, transport) = extraTimeApi([])

        await #expect(throws: ApiFailure.self) {
            try await api.decide(requestId, outcome: .approve, grantedMinutes: nil, note: nil)
        }
        #expect(await transport.requests.count == 1)
    }
}
