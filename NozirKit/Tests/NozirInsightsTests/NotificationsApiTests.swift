import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let listPath = "/v1/parent/notifications"
private let preferencesPath = "/v1/parent/notification-preferences"
/// base64url("1791360000000"), as `NotificationServiceImpl.encodeCursor` writes it.
private let cursor = "MTc5MTM2MDAwMDAwMA"

@Suite struct NotificationsApiTests {
    @Test func aPageIsReadAsTheServerWritesIt() async throws {
        let body = notificationPageJSON([
            notificationJSON(extra: #","readAt":"2026-10-07T08:05:00Z""#),
            notificationJSON(
                id: "4a5b6c7d-8e9f-4a0b-9c1d-2e3f4a5b6c7d",
                type: "DAILY_SUMMARY_READY",
                tier: "ATTENTION",
                key: "notification.digest.suppressed",
                args: #"{"count":"3"}"#,
                child: false,
                deepLink: "nozir://notifications",
                occurredAt: "2026-10-07T03:00:00.123Z"
            ),
        ], nextCursor: cursor)
        let (api, transport) = notificationsApi([.ok(body)])

        let page = try await api.page(filter: .all, cursor: nil)

        #expect(page.items == [
            ParentNotification(
                id: notificationId,
                type: .sosTriggered,
                tier: .critical,
                localisationKey: "notification.sos.triggered",
                childId: aliId,
                childName: "Ali",
                deepLink: "nozir://sos/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10",
                occurredAt: instant("2026-10-07T08:00:00Z"),
                readAt: instant("2026-10-07T08:05:00Z")
            ),
            ParentNotification(
                id: digestId,
                type: .dailySummaryReady,
                tier: .attention,
                localisationKey: "notification.digest.suppressed",
                localisationArgs: ["count": "3"],
                deepLink: "nozir://notifications",
                occurredAt: instant("2026-10-07T03:00:00Z").addingTimeInterval(0.123)
            ),
        ])
        #expect(page.nextCursor == cursor)
        #expect(page.items[0].isRead)
        #expect(!page.items[1].isRead)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == listPath)
        #expect(request.queryParameters == ["filter": "ALL"])
    }

    @Test func theNextPageAsksWithItsCursorAndFilter() async throws {
        let (api, transport) = notificationsApi([.ok(notificationPageJSON([]))])

        let page = try await api.page(filter: .important, cursor: cursor)

        #expect(page.items.isEmpty)
        #expect(page.nextCursor == nil)
        let request = try #require(await transport.requests.first)
        #expect(request.queryParameters == ["filter": "IMPORTANT", "cursor": cursor])
    }

    // Review Focus 6 (spec §4.1): an unknown type keeps its row; a row without
    // a readable id, tier or time is dropped alone, never the page.
    @Test func anUnknownTypeKeepsItsRowAndABrokenRowIsDroppedAlone() async throws {
        let body = notificationPageJSON([
            notificationJSON(
                id: "5b6c7d8e-9f0a-4b1c-8d2e-3f4a5b6c7d8e",
                type: "TRIAL_ENDING",
                tier: "GOOD",
                key: "notification.trial.ending",
                args: nil,
                child: false,
                deepLink: "nozir://subscription"
            ),
            notificationJSON(id: "6c7d8e9f-0a1b-4c2d-9e3f-4a5b6c7d8e9f", tier: "SOMETHING_NEW"),
            notificationJSON(id: "7d8e9f0a-1b2c-4d3e-8f4a-5b6c7d8e9f0a", occurredAt: nil),
            notificationJSON(id: "not-a-uuid"),
            notificationJSON(),
        ], nextCursor: cursor)
        let (api, _) = notificationsApi([.ok(body)])

        let page = try await api.page(filter: .all, cursor: nil)

        #expect(page.items.map(\.id) == [UUID(uuidString: "5B6C7D8E-9F0A-4B1C-8D2E-3F4A5B6C7D8E")!, notificationId])
        let trial = page.items[0]
        #expect(trial.type == .unknown("TRIAL_ENDING"))
        #expect(trial.tier == .good)
        #expect(trial.localisationArgs.isEmpty)
        #expect(trial.childId == nil)
        #expect(trial.childName == nil)
        #expect(page.nextCursor == cursor)
    }

    @Test func aReadIsOnePostWithNoBody() async throws {
        let (api, transport) = notificationsApi([.init(status: 204)])

        try await api.markRead(notificationId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == listPath + "/3f2a1b0c-9d8e-4f7a-8b6c-5d4e3f2a1b0c/read")
        #expect(request.httpBody == nil)
    }

    // Global Constraints: nothing is retried.
    @Test func aFailedReadIsThrownAndNotRetried() async {
        let (api, transport) = notificationsApi([.error(500, code: "INTERNAL_ERROR"), .init(status: 204)])

        do {
            try await api.markRead(notificationId)
            Issue.record("expected a failure")
        } catch {
            #expect(error is ApiFailure)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test func preferencesAreReadAsTheServerWritesThem() async throws {
        let withoutQuietHours = #"{"dailyPushCap":0,"mutedTypes":[],"smsForCriticalEnabled":false,"deviceOfflineAfterMinutes":1440}"#
        let (api, transport) = notificationsApi([.ok(preferencesJSON), .ok(withoutQuietHours)])

        #expect(try await api.preferences() == NotificationPreferences(
            dailyPushCap: 1,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00",
            mutedTypes: ["LIMIT_REACHED"],
            smsForCriticalEnabled: true,
            deviceOfflineAfterMinutes: 360
        ))
        #expect(try await api.preferences() == NotificationPreferences(
            dailyPushCap: 0,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            mutedTypes: [],
            smsForCriticalEnabled: false,
            deviceOfflineAfterMinutes: 1440
        ))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == preferencesPath)
    }

    // Plan deviation N7: a half-read setting is never written back.
    @Test func preferencesThatCannotBeReadAreAFailure() async {
        let (api, _) = notificationsApi([.ok(#"{"dailyPushCap":1,"mutedTypes":[],"smsForCriticalEnabled":true}"#)])

        do {
            _ = try await api.preferences()
            Issue.record("expected a failure")
        } catch let failure as ApiFailure {
            guard case .decoding = failure else {
                Issue.record("unexpected \(failure)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // Review Focus 5: a full replace — every field goes back, unknown muted types included.
    @Test func savingSendsEveryFieldBack() async throws {
        let saved = NotificationPreferences(
            dailyPushCap: 2,
            quietHoursStart: "22:00",
            quietHoursEnd: "07:00",
            mutedTypes: ["LIMIT_REACHED", "SOMETHING_NEW"],
            smsForCriticalEnabled: false,
            deviceOfflineAfterMinutes: 720
        )
        let answer = #"{"dailyPushCap":2,"quietHoursStart":"22:00","quietHoursEnd":"07:00","mutedTypes":["LIMIT_REACHED"],"smsForCriticalEnabled":false,"deviceOfflineAfterMinutes":720}"#
        let (api, transport) = notificationsApi([.ok(answer)])

        let stored = try await api.savePreferences(saved)

        #expect(stored.deviceOfflineAfterMinutes == 720)
        #expect(stored.mutedTypes == ["LIMIT_REACHED"])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == preferencesPath)
        let body = try #require(request.jsonObject)
        #expect(body.count == 6)
        #expect(body["dailyPushCap"] as? Int == 2)
        #expect(body["quietHoursStart"] as? String == "22:00")
        #expect(body["quietHoursEnd"] as? String == "07:00")
        #expect(body["mutedTypes"] as? [String] == ["LIMIT_REACHED", "SOMETHING_NEW"])
        #expect(body["smsForCriticalEnabled"] as? Bool == false)
        #expect(body["deviceOfflineAfterMinutes"] as? Int == 720)
    }

    @Test func noQuietHoursAreLeftOutOfTheWrite() async throws {
        let saved = NotificationPreferences(
            dailyPushCap: 1,
            quietHoursStart: nil,
            quietHoursEnd: nil,
            mutedTypes: [],
            smsForCriticalEnabled: true,
            deviceOfflineAfterMinutes: 360
        )
        let answer = #"{"dailyPushCap":1,"mutedTypes":[],"smsForCriticalEnabled":true,"deviceOfflineAfterMinutes":360}"#
        let (api, transport) = notificationsApi([.ok(answer)])

        _ = try await api.savePreferences(saved)

        let body = try #require(await transport.requests.first?.jsonObject)
        #expect(body.count == 4)
        #expect(body["quietHoursStart"] == nil)
        #expect(body["mutedTypes"] as? [String] == [])
    }
}
