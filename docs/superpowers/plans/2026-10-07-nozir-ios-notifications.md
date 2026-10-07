# Nozir iOS — P16: Notifications list Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parent opens P16 from a bell on Home or from a "Bildirishnomalar" row in Profile, reads the family's whole notification history (newest first, "Hammasi" / "Muhim"), pages through it with "Yana koʻrsatish", taps a row to mark it read and — when the row leads somewhere that exists on iOS — lands on that screen (SOS, P17, P18, daily summary, weekly report, rules), and sets how long the child's phone may stay silent before the parent is told.

**Architecture:** `NozirInsights` gains the wire models (`NotificationType`, `NotificationTier`, `ParentNotification`, `NotificationPage`, `NotificationFilter`, `NotificationPreferences`), a `NotificationsService` protocol and its `NotificationsApi`. In `NozirAppFeature`, `NotificationTexts` holds every pure word-and-tone rule (Android `NotificationHeadline`, `ZoneCrossingHeadline`, `NotificationMoment`, `NotificationRow`, `NotificationCardTone`, `DeviceOfflineSetting`), `NotificationLink` reads a `nozir://` link (Android `pushDeepLinkOf`) and turns a row into a `SignedInView.HomeStep`, and `NotificationsModel` (`@MainActor @Observable`, built like `ProtectionModel` / `TimeRequestModel`) pages, filters, marks read and saves the offline threshold. `NotificationsView` and `NotificationRow` draw it; `SignedInView` gets `HomeStep.notifications`, Home a bell, Profile a row, `SignedInModel` the service and a factory.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; no third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-ios-notifications-design.md` (commit `cb91f49`). The backend contract (§3) is live and unchanged (`Nozir-Backend` `notifications/internal/web/NotificationController.kt`, `NotificationDtos.kt`).

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries. No `Package.swift` change.
- Every `/v1/parent/*` call goes through `ApiClient`. **Nothing is retried automatically** — not a page, not a read, not a preferences write.
- `GET /v1/parent/notifications?filter=ALL|IMPORTANT&cursor=` → `{items: [NotificationResponse], nextCursor?}`; newest first; the app sends no `limit` (server default 20); `IMPORTANT` = tier `ACTION|CRITICAL`; `nextCursor` is opaque (base64url of epoch millis) and absent on the last page; **a page may be empty and a full page carries a cursor even when nothing older exists**.
- `NotificationResponse` (backend global `non_null`: a null field is **absent**, never `null`): `id` UUID, `type` (enum name), `tier` (`GOOD|ATTENTION|ACTION|CRITICAL`), `localisationKey` String, `localisationArgs` `{String: String}` (always present, may be `{}`), `childId?`, `childName?`, `deepLink?` (`nozir://…`), `occurredAt` instant, `readAt?` instant.
- A row whose `id`, `tier` or `occurredAt` cannot be read is dropped **alone**; a `type` this app does not know keeps its row as `.unknown(raw)` ("Yangi bildirishnoma"). The backend already sends `TRIAL_ENDING`, `TRIAL_ENDED`, `SUBSCRIPTION_EXPIRED`, `SUBSCRIPTION_LAPSED`, which Android also does not know.
- `POST /v1/parent/notifications/{id}/read` → 204, no body; already read is not an error. The row is marked read on screen at once; the call's failure is **silent**.
- `GET /v1/parent/notification-preferences` → `{dailyPushCap, quietHoursStart?, quietHoursEnd?, mutedTypes: [String], smsForCriticalEnabled, deviceOfflineAfterMinutes}`; `PUT` the same body is a **full replace**: every field the app did not change is sent back exactly as read (`mutedTypes` as raw strings, so a type this app does not know stays muted). `deviceOfflineAfterMinutes` 60…2880, default 360; quiet hours are `"HH:mm"`.
- User-facing text only from `L10n`, errors only through `UserMessage`; the server's `message` is never shown. **No new l10n key** (`gen_l10n.py --check` stays clean). No `notificationsPushNote` (iOS has no push yet).
- Out of scope (spec §1): push / APNs, an unread badge, "mark all read", every other preference (daily cap, quiet hours, SMS, muted types — no UI, values kept), map / challenges / subscription links.
- Tests: Swift Testing; scripted fakes (`FakeNotifications`, `FakeFamily`), `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`.
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| N1 | §5.2 "presetlar 6/12/24/48 soat"; D3 "Android presetlari" | Android's presets: **1, 2, 4, 6, 12, 24 hours** (`[60, 120, 240, 360, 720, 1440]`) | The two lines of the spec disagree; D3 is the user's decision and the spec's goal is "Android P16 bilan bir xil natija". Android `DeviceOfflineSetting.kt` `PresetMinutes = listOf(60, 120, 240, 360, 720, 1440)`. One constant (`NotificationTexts.offlinePresets`) — see Open question Q1 |
| N2 | "daraja → karta tusi" | GOOD → `.plain`, ATTENTION → `.attention`, **ACTION → `.attention`**, CRITICAL → `.critical`; the dot keeps all four colours (`NozirStatusLevel`) | iOS `NozirCardTone` has only `plain, attention, critical` (`NozirCard.swift:3`); Android has an ACTION card. Red stays for CRITICAL (SOS) |
| N3 | §5.2 accessibility: "'oʻqilmagan' holati matn bilan" | Unread is bold only; VoiceOver reads headline, "bola · vaqt" and "Ilova ichida qoldi" | There is no "unread" key in `L10n.generated.swift` and the spec forbids new keys; Android also marks unread only by weight. See Q2 |
| N4 | summary link: `childId` yoʻq → hech narsa | Also nothing for `DAILY_SUMMARY_READY` without a `childName` | `DailySummaryModel` needs the name for its title ("Ali bugun"); `HomeStep.summary(UUID, String)` takes a non-optional name |
| N5 | §4.2 `setFilter` (behaviour while the new page loads not said) | The list is cleared and the spinner shows until the new filter's first page arrives | Android narrows already-fetched rows client-side; clearing is simpler and the generation counter (spec) still drops the older answer |
| N6 | §4.2 `inlineMessage`, `phase .failed`, toast | First page fails with nothing on screen → `.failed` (error state + retry); a refresh with a list on screen and no connection/timeout → offline notice; any other refresh fault or a "Yana" failure → `inlineMessage` under the list; a preferences write failure → toast | Mirrors `ProtectionModel` and Android `withFailure` / `applyNextPage` / `applyPreferences` |
| N7 | §4.1 preferences "barcha maydonlar" | Decoded strictly: a missing required field is a failure and the card is not drawn | The write is a full replace; filling a missing field with a default and writing it back would silently change a setting the parent never touched |
| N8 | §4.2 "fon `markRead`" | A detached `Task` kept in `lastRead` (internal, read only by tests) | Lets tests await the background call without making `open(_:)` async (navigation must not wait for it) |
| N9 | D1 Profile row → Home tab + push | Not pushed again when P16 is already on top of Home's stack | Two taps (or Profile after Home's bell) must not stack two P16s |
| N10 | §5.2 "oldingi planga qaytganda yangilanadi" | Coming back re-reads the **first page** (pages loaded with "Yana" are dropped) | Android `start()` does the same; keeps one code path |
| N11 | §4.2 summary link | The link's id (`nozir://summary/{summaryId}`, backend `InsightSubscriptions`) is not used; the row's `childId` and `type` decide | iOS has no "summary by id" call; spec §7 accepts "o'sha bolaning oxirgi xulosasi" |

## Review Focus

1. **The filter is switched while a page is still loading** (slow network, parent taps "Muhim" right after opening) — only "Muhim" rows end up on screen; the older "Hammasi" answer never lands → Task 3 `aFilterSwitchDropsTheOlderAnswer`; a refresh during "Yana" likewise → `aRefreshDropsALoadMoreInFlight`.
2. **The last page is empty but the page before carried a cursor** (exactly 20, 40… notifications), or a page whose rows were all unreadable — the list stays, "Yana koʻrsatish" disappears only when there is no cursor, and "Hali bildirishnoma yoʻq" is never shown over rows → Task 3 `anEmptyLastPageEndsTheListWithoutSayingEmpty`, `aPageWithNothingReadableStillOffersMore`.
3. **"Yana koʻrsatish" tapped twice** — one request, the rows appended once → Task 3 `twoTapsOnMoreAskOnce`.
4. **Marking read fails** (no connection) — the row stays read on screen, no toast, no inline error → Task 3 `aFailedReadStaysSilent`.
5. **Changing the offline threshold** — every other preference (quiet hours, muted types including ones this app does not know, cap, SMS) goes back unchanged; a refusal is a toast and the old value stays → Task 1 `savingSendsEveryFieldBack`, Task 3 `theOfflineSettingKeepsEveryOtherField`, `aRefusedSettingIsSaidAndTheOldValueStays`.
6. **A notification type this app does not know** (`TRIAL_ENDING`…) — its row is still shown as "Yangi bildirishnoma"; one broken row never empties the page → Task 1 `anUnknownTypeKeepsItsRowAndABrokenRowIsDroppedAlone`, Task 2 `anUnknownTypeReadsAsANewNotification`.
7. **A link whose row has no `childId`** (the child was removed, or a family-wide digest) — tapping marks it read and goes nowhere, never crashes → Task 2 `aLinkThatNeedsAChildGoesNowhereWithoutOne`.

---

## File map

**New:**
- `NozirKit/Sources/NozirInsights/NotificationModels.swift` — `NotificationType`, `NotificationTier`, `NotificationFilter`, `ParentNotification`, `NotificationPage`, `NotificationPreferences`.
- `NozirKit/Sources/NozirInsights/NotificationsService.swift` — `NotificationsService`.
- `NozirKit/Sources/NozirInsights/NotificationsApi.swift` — `NotificationsApi`.
- `NozirKit/Tests/NozirInsightsTests/NotificationsApiTests.swift`.
- `NozirKit/Sources/NozirAppFeature/Notifications/NotificationTexts.swift`, `NotificationLink.swift`, `NotificationsModel.swift`.
- `NozirKit/Sources/NozirAppFeature/Screens/NotificationsView.swift`, `NotificationRow.swift`.
- `NozirKit/Tests/NozirAppFeatureTests/FakeNotifications.swift`, `NotificationTextsTests.swift`, `NotificationLinkTests.swift`, `NotificationsModelTests.swift`.

**Modified:** `NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` (append); `NozirAppFeature/{SignedInModel,AppEnvironment}.swift`; `NozirAppFeature/Screens/{HomeView,ProfileView,SignedInView}.swift`; `NozirAppFeatureTests/SignedInModelTests.swift`.

`Notifications/` is a new folder inside the `NozirAppFeature` target, picked up automatically. P18 code is not touched beyond the shared wiring lines named in Task 5.

## Getting started

Branch `protection` (spec commit `cb91f49`, on top of the P18 work) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirInsightsTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

---
### Task 1: The history and the settings, as the server writes them — models and `NotificationsApi`

**Files:**
- Create: `NozirKit/Sources/NozirInsights/NotificationModels.swift`
- Create: `NozirKit/Sources/NozirInsights/NotificationsService.swift`
- Create: `NozirKit/Sources/NozirInsights/NotificationsApi.swift`
- Modify: `NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` (append at the end, after `protectionJSON(…)`, line 131)
- Create: `NozirKit/Tests/NozirInsightsTests/NotificationsApiTests.swift`

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiClient.send(_:)` (no body read; `ApiClient.swift:45`), `ApiRequest(method:path:query:)`, `ApiRequest.put(_:json:ifMatch:)` (`ApiRequest.swift:51`), `ApiFailure` (`.decoding`, `ApiFailure.swift:8`), `FakeTransport`, `FakeTransport.Reply(status:body:)`, `.ok`, `.error`, `URLRequest.jsonObject` (`NozirTestSupport/HTTP.swift`), `URLRequest.queryParameters`, `FixedToken`, `aliId`, `instant(_:)` (`InsightsFixtures.swift`).
- Produces:
  - `public enum NotificationType: Hashable, Sendable` — `sosTriggered, safeZoneEntered, safeZoneLeft, protectionBroken, protectionRestored, deviceOffline, extraTimeRequested, challengeNeedsApproval, dailySummaryReady, weeklyReportReady, limitReached, bedtimeViolation, usageAnomaly, rulesChanged, subscriptionExpiring, childAppOutdated, appInstalled, unknown(String)`; `init(rawValue: String)`.
  - `public enum NotificationTier: String, Sendable { case good = "GOOD", attention = "ATTENTION", action = "ACTION", critical = "CRITICAL"; var isImportant: Bool }`.
  - `public enum NotificationFilter: String, CaseIterable, Sendable { case all = "ALL", important = "IMPORTANT" }`.
  - `public struct ParentNotification: Decodable, Hashable, Sendable, Identifiable { id: UUID, type, tier, localisationKey: String, localisationArgs: [String: String], childId: UUID?, childName: String?, deepLink: String?, occurredAt: Date, readAt: Date?; init(id:type:tier:localisationKey: = "", localisationArgs: = [:], childId: = nil, childName: = nil, deepLink: = nil, occurredAt:readAt: = nil); var isRead: Bool; func markedRead(at: Date) -> ParentNotification }`.
  - `public struct NotificationPage: Decodable, Equatable, Sendable { items: [ParentNotification], nextCursor: String?; init(items:nextCursor: = nil) }`.
  - `public struct NotificationPreferences: Codable, Equatable, Sendable { dailyPushCap: Int, quietHoursStart: String?, quietHoursEnd: String?, mutedTypes: [String], smsForCriticalEnabled: Bool, deviceOfflineAfterMinutes: Int; init(…all six…); func withDeviceOfflineAfter(minutes: Int) -> NotificationPreferences }`.
  - `public protocol NotificationsService: Sendable { func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage; func markRead(_ id: UUID) async throws; func preferences() async throws -> NotificationPreferences; func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences }`.
  - `public struct NotificationsApi: NotificationsService { public init(client: ApiClient) }`.
  - Test fixtures (NozirInsightsTests only): `notificationsApi(_:)`, `notificationId`, `digestId`, `notificationJSON(id:type:tier:key:args:child:deepLink:occurredAt:extra:)`, `notificationPageJSON(_:nextCursor:)`, `preferencesJSON`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` — append at the end of the file:

```swift
func notificationsApi(_ replies: [FakeTransport.Reply]) -> (NotificationsApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (NotificationsApi(client: client), transport)
}

let notificationId = UUID(uuidString: "3F2A1B0C-9D8E-4F7A-8B6C-5D4E3F2A1B0C")!
let digestId = UUID(uuidString: "4A5B6C7D-8E9F-4A0B-9C1D-2E3F4A5B6C7D")!

/// `NotificationResponse` as the backend writes it (`non_null`: `childId`,
/// `childName`, `deepLink` and `readAt` are absent when null;
/// `localisationArgs` is always there). By default Ali's SOS. `args: nil` and
/// `occurredAt: nil` leave those fields out (a broken row); `extra` is spliced
/// in before the closing brace and must start with a comma.
func notificationJSON(
    id: String = "3f2a1b0c-9d8e-4f7a-8b6c-5d4e3f2a1b0c",
    type: String = "SOS_TRIGGERED",
    tier: String = "CRITICAL",
    key: String = "notification.sos.triggered",
    args: String? = "{}",
    child: Bool = true,
    deepLink: String? = "nozir://sos/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10",
    occurredAt: String? = "2026-10-07T08:00:00Z",
    extra: String = ""
) -> String {
    let argsField = args.map { #","localisationArgs":\#($0)"# } ?? ""
    let childFields = child ? #","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","childName":"Ali""# : ""
    let linkField = deepLink.map { #","deepLink":"\#($0)""# } ?? ""
    let timeField = occurredAt.map { #","occurredAt":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","type":"\#(type)","tier":"\#(tier)","localisationKey":"\#(key)""#
        + argsField + childFields + linkField + timeField + extra + "}"
}

/// `NotificationPage`: `nextCursor` is absent on the last page.
func notificationPageJSON(_ items: [String], nextCursor: String? = nil) -> String {
    let cursorField = nextCursor.map { #","nextCursor":"\#($0)""# } ?? ""
    return #"{"items":["# + items.joined(separator: ",") + "]" + cursorField + "}"
}

/// `NotificationPreferencesResponse` with quiet hours set (`LocalTime.toString()`: "22:00").
let preferencesJSON = #"{"dailyPushCap":1,"quietHoursStart":"22:00","quietHoursEnd":"07:00","mutedTypes":["LIMIT_REACHED"],"smsForCriticalEnabled":true,"deviceOfflineAfterMinutes":360}"#
```

`NozirKit/Tests/NozirInsightsTests/NotificationsApiTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: FAIL — `cannot find 'NotificationsApi' in scope` (and the other new names).

- [ ] **Step 3: The models**

`NozirKit/Sources/NozirInsights/NotificationModels.swift`:

```swift
import Foundation

/// `NotificationType`, as far as this app has words for it. Anything else —
/// `TRIAL_ENDING`, `TRIAL_ENDED`, `SUBSCRIPTION_EXPIRED`, `SUBSCRIPTION_LAPSED`
/// or a type added later — is kept as it came: the record is complete, so the
/// row stays ("Yangi bildirishnoma").
public enum NotificationType: Hashable, Sendable {
    case sosTriggered
    case safeZoneEntered
    case safeZoneLeft
    case protectionBroken
    case protectionRestored
    case deviceOffline
    case extraTimeRequested
    case challengeNeedsApproval
    case dailySummaryReady
    case weeklyReportReady
    case limitReached
    case bedtimeViolation
    case usageAnomaly
    case rulesChanged
    case subscriptionExpiring
    case childAppOutdated
    case appInstalled
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "SOS_TRIGGERED": self = .sosTriggered
        case "SAFE_ZONE_ENTERED": self = .safeZoneEntered
        case "SAFE_ZONE_LEFT": self = .safeZoneLeft
        case "PROTECTION_BROKEN": self = .protectionBroken
        case "PROTECTION_RESTORED": self = .protectionRestored
        case "DEVICE_OFFLINE": self = .deviceOffline
        case "EXTRA_TIME_REQUESTED": self = .extraTimeRequested
        case "CHALLENGE_NEEDS_APPROVAL": self = .challengeNeedsApproval
        case "DAILY_SUMMARY_READY": self = .dailySummaryReady
        case "WEEKLY_REPORT_READY": self = .weeklyReportReady
        case "LIMIT_REACHED": self = .limitReached
        case "BEDTIME_VIOLATION": self = .bedtimeViolation
        case "USAGE_ANOMALY": self = .usageAnomaly
        case "RULES_CHANGED": self = .rulesChanged
        case "SUBSCRIPTION_EXPIRING": self = .subscriptionExpiring
        case "CHILD_APP_OUTDATED": self = .childAppOutdated
        case "APP_INSTALLED": self = .appInstalled
        default: self = .unknown(rawValue)
        }
    }
}

/// `NotificationTier`. The tier is what a row's colour means, so a row whose
/// tier this app cannot read is the one row that is dropped.
public enum NotificationTier: String, Sendable {
    case good = "GOOD"
    case attention = "ATTENTION"
    case action = "ACTION"
    case critical = "CRITICAL"

    /// What "Muhim" keeps; GOOD and ATTENTION never ring the phone.
    public var isImportant: Bool {
        self == .action || self == .critical
    }
}

/// `NotificationFilter`: the "Hammasi" / "Muhim" control.
public enum NotificationFilter: String, CaseIterable, Sendable {
    case all = "ALL"
    case important = "IMPORTANT"
}

/// `NotificationResponse`. The server sends no text: a key, its arguments and
/// a type; every word is the app's.
public struct ParentNotification: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let type: NotificationType
    public let tier: NotificationTier
    public let localisationKey: String
    public let localisationArgs: [String: String]
    /// Nil for a family-wide row (the digest).
    public let childId: UUID?
    public let childName: String?
    /// `nozir://…`; read by `NotificationLink` in the app.
    public let deepLink: String?
    public let occurredAt: Date
    public let readAt: Date?

    public init(
        id: UUID,
        type: NotificationType,
        tier: NotificationTier,
        localisationKey: String = "",
        localisationArgs: [String: String] = [:],
        childId: UUID? = nil,
        childName: String? = nil,
        deepLink: String? = nil,
        occurredAt: Date,
        readAt: Date? = nil
    ) {
        self.id = id
        self.type = type
        self.tier = tier
        self.localisationKey = localisationKey
        self.localisationArgs = localisationArgs
        self.childId = childId
        self.childName = childName
        self.deepLink = deepLink
        self.occurredAt = occurredAt
        self.readAt = readAt
    }

    public var isRead: Bool {
        readAt != nil
    }

    /// The same row, read at `moment` (the list marks it before the server hears).
    public func markedRead(at moment: Date) -> ParentNotification {
        ParentNotification(
            id: id, type: type, tier: tier, localisationKey: localisationKey,
            localisationArgs: localisationArgs, childId: childId, childName: childName,
            deepLink: deepLink, occurredAt: occurredAt, readAt: moment
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, type, tier, localisationKey, localisationArgs, childId, childName, deepLink, occurredAt, readAt
    }

    /// `id`, `tier` and `occurredAt` are required; everything else is read defensively.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        let rawTier = try container.decode(String.self, forKey: .tier)
        guard let tier = NotificationTier(rawValue: rawTier) else {
            throw DecodingError.dataCorruptedError(forKey: .tier, in: container, debugDescription: "Unknown tier \(rawTier)")
        }
        self.tier = tier
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        type = NotificationType(rawValue: (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "")
        localisationKey = (try? container.decodeIfPresent(String.self, forKey: .localisationKey)) ?? ""
        localisationArgs = (try? container.decodeIfPresent([String: String].self, forKey: .localisationArgs)) ?? [:]
        childId = try? container.decodeIfPresent(UUID.self, forKey: .childId)
        childName = try? container.decodeIfPresent(String.self, forKey: .childName)
        deepLink = try? container.decodeIfPresent(String.self, forKey: .deepLink)
        readAt = try? container.decodeIfPresent(Date.self, forKey: .readAt)
    }
}

/// `NotificationPage`. `nextCursor` is opaque and absent on the last page; a
/// page may be empty, and rows this app cannot read are dropped one by one.
public struct NotificationPage: Decodable, Equatable, Sendable {
    public let items: [ParentNotification]
    public let nextCursor: String?

    public init(items: [ParentNotification], nextCursor: String? = nil) {
        self.items = items
        self.nextCursor = nextCursor
    }

    enum CodingKeys: String, CodingKey {
        case items, nextCursor
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rows = try container.decodeIfPresent([LossyNotification].self, forKey: .items) ?? []
        items = rows.compactMap(\.value)
        nextCursor = try? container.decodeIfPresent(String.self, forKey: .nextCursor)
    }
}

/// One element of `items`, or nil when it cannot be read: one broken row never
/// empties the page.
private struct LossyNotification: Decodable {
    let value: ParentNotification?

    init(from decoder: any Decoder) throws {
        value = try? ParentNotification(from: decoder)
    }
}

/// `NotificationPreferencesResponse` / `NotificationPreferencesBody`. The write
/// is a full replace, so every field is carried and decoded strictly: a value
/// filled in by guesswork would be written back as the parent's.
/// `mutedTypes` stays raw — a type this app does not know must stay muted.
public struct NotificationPreferences: Codable, Equatable, Sendable {
    /// `NotificationDefaults` on the server; the server still clamps.
    public static let minDeviceOfflineMinutes = 60
    public static let maxDeviceOfflineMinutes = 2880

    public let dailyPushCap: Int
    /// "HH:mm"; absent when not set.
    public let quietHoursStart: String?
    public let quietHoursEnd: String?
    public let mutedTypes: [String]
    public let smsForCriticalEnabled: Bool
    public let deviceOfflineAfterMinutes: Int

    public init(
        dailyPushCap: Int,
        quietHoursStart: String?,
        quietHoursEnd: String?,
        mutedTypes: [String],
        smsForCriticalEnabled: Bool,
        deviceOfflineAfterMinutes: Int
    ) {
        self.dailyPushCap = dailyPushCap
        self.quietHoursStart = quietHoursStart
        self.quietHoursEnd = quietHoursEnd
        self.mutedTypes = mutedTypes
        self.smsForCriticalEnabled = smsForCriticalEnabled
        self.deviceOfflineAfterMinutes = deviceOfflineAfterMinutes
    }

    /// Everything else exactly as it was.
    public func withDeviceOfflineAfter(minutes: Int) -> NotificationPreferences {
        NotificationPreferences(
            dailyPushCap: dailyPushCap,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd,
            mutedTypes: mutedTypes,
            smsForCriticalEnabled: smsForCriticalEnabled,
            deviceOfflineAfterMinutes: minutes
        )
    }
}
```

- [ ] **Step 4: The service and the API**

`NozirKit/Sources/NozirInsights/NotificationsService.swift`:

```swift
import Foundation

/// The family's notification history and its settings (P16). `NotificationsApi`
/// is the real one; screen-model tests use a scripted fake. Nothing here is
/// retried.
public protocol NotificationsService: Sendable {
    /// Newest first; `cursor` nil for the first page.
    func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage
    /// 204; a row already read is not an error.
    func markRead(_ id: UUID) async throws
    func preferences() async throws -> NotificationPreferences
    /// A full replace; answers what the server stored (it clamps).
    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences
}
```

`NozirKit/Sources/NozirInsights/NotificationsApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/notifications` and `/v1/parent/notification-preferences`
/// (backend `NotificationController`).
public struct NotificationsApi: NotificationsService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static let path = "/v1/parent/notifications"
    static let preferencesPath = "/v1/parent/notification-preferences"

    /// No `limit`: the server's default (20) is the page Android reads too.
    public func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage {
        var query = ["filter": filter.rawValue]
        if let cursor {
            query["cursor"] = cursor
        }
        return try await client.send(ApiRequest(method: .get, path: Self.path, query: query), as: NotificationPage.self)
    }

    public func markRead(_ id: UUID) async throws {
        try await client.send(ApiRequest(method: .post, path: Self.path + "/\(id.uuidString.lowercased())/read"))
    }

    public func preferences() async throws -> NotificationPreferences {
        try await client.send(ApiRequest(method: .get, path: Self.preferencesPath), as: NotificationPreferences.self)
    }

    public func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        try await client.send(try ApiRequest.put(Self.preferencesPath, json: preferences), as: NotificationPreferences.self)
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: `** TEST SUCCEEDED **`, the 9 new tests among them.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirInsights/NotificationModels.swift NozirKit/Sources/NozirInsights/NotificationsService.swift NozirKit/Sources/NozirInsights/NotificationsApi.swift NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift NozirKit/Tests/NozirInsightsTests/NotificationsApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16: the notification history and its settings, as the server writes them

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: The words, tones and links — `NotificationTexts`, `NotificationLink` and the test fixtures

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/FakeNotifications.swift` (the fake and the fixtures; the fake is used from Task 3)
- Create: `NozirKit/Tests/NozirAppFeatureTests/NotificationTextsTests.swift`
- Create: `NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Notifications/NotificationTexts.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift`

**Interfaces:**
- Consumes: `NotificationType`, `NotificationTier`, `NotificationFilter`, `ParentNotification`, `NotificationPage`, `NotificationPreferences`, `NotificationsService` (Task 1); `ActiveSos(sosId:childId:childName:triggeredAt:)` (`InsightModels.swift:69-81`); `SignedInView.HomeStep` cases `.sos(ActiveSos)`, `.timeRequest(UUID, usedMinutesToday: Int?)`, `.protection(UUID)`, `.summary(UUID, String)`, `.weekly(UUID)`, `.rules(UUID)` (`SignedInView.swift:10-24`); `LocalDate(_:in:)`, `LocalDate.adding(days:)` (`LocalDate.swift:36, 53`); `DateTexts.timeOfDay(_:calendar:)`, `DateTexts.dayAndMonth(_:_:)` (`Insights/InsightTexts.swift:42, 73`); `LocationTexts.present(_:)` (`Location/LocationTexts.swift:126`); `NozirCardTone` (`NozirCard.swift:3`), `NozirStatusLevel` (`NozirRows.swift:3`); `PauseGate` (`FakeLocation.swift:114`), `offline` (`FakeFamily.swift:5`); the L10n names below.
- Produces (all `static`, internal to `NozirAppFeature`):
  - `NotificationTexts.headline(_ notification: ParentNotification, _ l10n: L10n) -> String`.
  - `NotificationTexts.moment(_ date: Date, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String`, `caption(_ notification: ParentNotification, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String`, `inAppNote(_ tier: NotificationTier, _ l10n: L10n) -> String?`.
  - `NotificationTexts.dotLevel(_ tier: NotificationTier) -> NozirStatusLevel`, `cardTone(_ tier: NotificationTier) -> NozirCardTone`.
  - `NotificationTexts.emptyTitle(_ filter: NotificationFilter, _ l10n: L10n) -> String`, `emptyBody(_:_:) -> String`.
  - `NotificationTexts.offlinePresets: [Int]`, `presetLabel(_ minutes: Int, _ l10n: L10n) -> String`, `presetAccessibilityLabel(_ minutes: Int, _ l10n: L10n) -> String`, `offlineCurrent(_ minutes: Int, _ l10n: L10n) -> String`.
  - `enum NotificationLink: Equatable { case sos(UUID), extraTime(UUID), protection(UUID), summary(UUID), appRules(UUID), other }`; `static func parse(_ deepLink: String?) -> NotificationLink`; `static func step(for notification: ParentNotification) -> SignedInView.HomeStep?`.
  - Test support: `actor FakeNotifications: NotificationsService` (`PageAsk { filter, cursor }`, `Script { pages, read, preferences, save, pageGate, saveGate }`, `calls: [String]` — "page", "read", "preferences", "save" — `pageAsks: [PageAsk]`, `readIds: [UUID]`, `saved: [NotificationPreferences]`, `add(_:)`), `notifiedAt` (2026-10-07T08:00:00Z), `parentNotification(id:type:tier:key:args:childId:childName:deepLink:occurredAt:readAt:)`, `notificationPage(_:cursor:)`, `notificationPreferences(offlineAfter:)`.

The L10n names used (verified in `NozirL10n/L10n.generated.swift`): `notificationSosTriggered`, `notificationSafeZoneEntered`, `notificationSafeZoneLeft`, `notificationSafeZoneEnteredNamed(_: String, _: String)` (child, zone), `notificationSafeZoneLeftNamed(_: String, _: String)`, `notificationProtectionBroken`, `notificationProtectionRestored`, `notificationDeviceOffline`, `notificationExtraTimeRequested`, `notificationBedtimeDelayRequested`, `notificationChallengeNeedsApproval`, `notificationDailySummaryReady`, `notificationWeeklyReportReady`, `notificationLimitReached`, `notificationBedtimeViolation`, `notificationUsageAnomaly`, `notificationRulesChanged`, `notificationSubscriptionExpiring`, `notificationChildAppOutdated`, `notificationAppInstalled`, `notificationAppInstalledCount(_: String)`, `notificationDigestSuppressed(_: String)`, `notificationUnknown`, `notificationMomentToday(_: String)`, `notificationMomentYesterday(_: String)`, `notificationMomentDate(_: String, _: String)` (day, clock), `notificationChildAndMoment(_: String, _: String)`, `notificationsInAppOnly`, `notificationsEmptyTitle`, `notificationsEmptyBody`, `notificationsEmptyImportantTitle`, `notificationsEmptyImportantBody`, `notificationsOfflinePreset(_: Int)` ("6 s"), `notificationsOfflineValue(_: Int)` ("6 soat"), `notificationsOfflineCurrent(_: String)` ("Hozir: …"), `durationLongHoursMinutes(_: Int, _: Int)`.

- [ ] **Step 1: The fake and the fixtures**

`NozirKit/Tests/NozirAppFeatureTests/FakeNotifications.swift`:

```swift
import Foundation
import NozirInsights
import NozirNetworking

/// Answers each call from its own queue, in order (an empty queue is a phone
/// with no connection), and records what was asked.
actor FakeNotifications: NotificationsService {
    struct PageAsk: Equatable, Sendable {
        let filter: NotificationFilter
        let cursor: String?
    }

    struct Script: Sendable {
        var pages: [Result<NotificationPage, ApiFailure>] = []
        var read: [Result<Void, ApiFailure>] = []
        var preferences: [Result<NotificationPreferences, ApiFailure>] = []
        var save: [Result<NotificationPreferences, ApiFailure>] = []
        /// Held once by the next `page` / `savePreferences` call, after its answer is taken.
        var pageGate: PauseGate?
        var saveGate: PauseGate?
    }

    private var script: Script
    /// "page", "read", "preferences", "save".
    private(set) var calls: [String] = []
    private(set) var pageAsks: [PageAsk] = []
    private(set) var readIds: [UUID] = []
    private(set) var saved: [NotificationPreferences] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func page(filter: NotificationFilter, cursor: String?) async throws -> NotificationPage {
        calls.append("page")
        pageAsks.append(PageAsk(filter: filter, cursor: cursor))
        let answer: Result<NotificationPage, ApiFailure> = script.pages.isEmpty ? .failure(offline) : script.pages.removeFirst()
        let gate = script.pageGate
        script.pageGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func markRead(_ id: UUID) async throws {
        calls.append("read")
        readIds.append(id)
        let answer: Result<Void, ApiFailure> = script.read.isEmpty ? .failure(offline) : script.read.removeFirst()
        try answer.get()
    }

    func preferences() async throws -> NotificationPreferences {
        calls.append("preferences")
        let answer: Result<NotificationPreferences, ApiFailure> = script.preferences.isEmpty ? .failure(offline) : script.preferences.removeFirst()
        return try answer.get()
    }

    func savePreferences(_ preferences: NotificationPreferences) async throws -> NotificationPreferences {
        calls.append("save")
        saved.append(preferences)
        let answer: Result<NotificationPreferences, ApiFailure> = script.save.isEmpty ? .failure(offline) : script.save.removeFirst()
        let gate = script.saveGate
        script.saveGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// 2026-10-07T08:00:00Z (13:00 in Tashkent).
let notifiedAt = Date(timeIntervalSince1970: 1_791_360_000)

/// Ali's unread SOS by default, with no link.
func parentNotification(
    id: UUID = UUID(),
    type: NotificationType = .sosTriggered,
    tier: NotificationTier = .critical,
    key: String = "notification.sos.triggered",
    args: [String: String] = [:],
    childId: UUID? = UUID(),
    childName: String? = "Ali",
    deepLink: String? = nil,
    occurredAt: Date = notifiedAt,
    readAt: Date? = nil
) -> ParentNotification {
    ParentNotification(
        id: id,
        type: type,
        tier: tier,
        localisationKey: key,
        localisationArgs: args,
        childId: childId,
        childName: childName,
        deepLink: deepLink,
        occurredAt: occurredAt,
        readAt: readAt
    )
}

func notificationPage(_ items: [ParentNotification], cursor: String? = nil) -> NotificationPage {
    NotificationPage(items: items, nextCursor: cursor)
}

/// Every field set to something other than the defaults, a muted type this
/// app does not know among them, so a write that drops one shows.
func notificationPreferences(offlineAfter: Int = 360) -> NotificationPreferences {
    NotificationPreferences(
        dailyPushCap: 2,
        quietHoursStart: "22:00",
        quietHoursEnd: "07:00",
        mutedTypes: ["LIMIT_REACHED", "SOMETHING_NEW"],
        smsForCriticalEnabled: false,
        deviceOfflineAfterMinutes: offlineAfter
    )
}
```

- [ ] **Step 2: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/NotificationTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private var tashkent: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}

private func at(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// 15:00 in Tashkent on 7 October.
private let now = at("2026-10-07T10:00:00Z")

@Suite struct NotificationTextsTests {
    private let l10n = L10n(.uz)

    private func headline(_ type: NotificationType, key: String = "x", args: [String: String] = [:], childName: String? = "Ali") -> String {
        NotificationTexts.headline(parentNotification(type: type, key: key, args: args, childName: childName), l10n)
    }

    // Spec §4.2: otherwise by type (Android `headlineRes`).
    @Test func everyKnownTypeHasItsSentence() {
        let table: [(NotificationType, String)] = [
            (.sosTriggered, l10n.notificationSosTriggered),
            (.safeZoneEntered, l10n.notificationSafeZoneEntered),
            (.safeZoneLeft, l10n.notificationSafeZoneLeft),
            (.protectionBroken, l10n.notificationProtectionBroken),
            (.protectionRestored, l10n.notificationProtectionRestored),
            (.deviceOffline, l10n.notificationDeviceOffline),
            (.extraTimeRequested, l10n.notificationExtraTimeRequested),
            (.challengeNeedsApproval, l10n.notificationChallengeNeedsApproval),
            (.dailySummaryReady, l10n.notificationDailySummaryReady),
            (.weeklyReportReady, l10n.notificationWeeklyReportReady),
            (.limitReached, l10n.notificationLimitReached),
            (.bedtimeViolation, l10n.notificationBedtimeViolation),
            (.usageAnomaly, l10n.notificationUsageAnomaly),
            (.rulesChanged, l10n.notificationRulesChanged),
            (.subscriptionExpiring, l10n.notificationSubscriptionExpiring),
            (.childAppOutdated, l10n.notificationChildAppOutdated),
            (.appInstalled, l10n.notificationAppInstalled),
        ]
        for (type, expected) in table {
            #expect(headline(type) == expected)
        }
        #expect(headline(.sosTriggered) == "SOS yuborildi")
    }

    // Review Focus 6 and spec §7: the four new backend types read as "Yangi bildirishnoma".
    @Test func anUnknownTypeReadsAsANewNotification() {
        #expect(headline(.unknown("TRIAL_ENDING")) == l10n.notificationUnknown)
        #expect(headline(.unknown("")) == "Yangi bildirishnoma")
    }

    // Android `NotificationHeadline`: the digest and the app count carry their number;
    // without it the type's own sentence (the digest is DAILY_SUMMARY_READY on the wire).
    @Test func theDigestAndTheAppCountCarryTheirNumber() {
        #expect(headline(.dailySummaryReady, key: "notification.digest.suppressed", args: ["count": "3"]) == l10n.notificationDigestSuppressed("3"))
        #expect(headline(.dailySummaryReady, key: "notification.digest.suppressed") == l10n.notificationDailySummaryReady)
        #expect(headline(.appInstalled, key: "notification.app.installed", args: ["count": "2"]) == l10n.notificationAppInstalledCount("2"))
        #expect(headline(.appInstalled, key: "notification.app.installed") == l10n.notificationAppInstalled)
    }

    // Android `zoneCrossingHeadline`: both names, the arg's child name before the row's.
    @Test func aZoneCrossingNamesTheChildAndTheZone() {
        let key = "notification.safeZone.entered"
        #expect(headline(.safeZoneEntered, key: key, args: ["childName": "Umar", "zoneName": "Uy"]) == l10n.notificationSafeZoneEnteredNamed("Umar", "Uy"))
        #expect(headline(.safeZoneEntered, key: key, args: ["zoneName": " Maktab №5 "]) == l10n.notificationSafeZoneEnteredNamed("Ali", "Maktab №5"))
        #expect(headline(.safeZoneLeft, key: "notification.safeZone.left", args: ["zoneName": "Uy"]) == l10n.notificationSafeZoneLeftNamed("Ali", "Uy"))
        #expect(headline(.safeZoneLeft, key: "notification.safeZone.left", args: ["zoneName": "Uy"], childName: nil) == l10n.notificationSafeZoneLeft)
        #expect(headline(.safeZoneEntered, key: key, args: ["zoneName": "  "]) == l10n.notificationSafeZoneEntered)
        #expect(headline(.safeZoneEntered, key: key) == l10n.notificationSafeZoneEntered)
        #expect(headline(.limitReached, args: ["zoneName": "Uy"]) == l10n.notificationLimitReached)
    }

    // Android `headlineResForKey`: a bedtime ask shares the extra-time type.
    @Test func aBedtimeAskIsNotCalledExtraTime() {
        #expect(headline(.extraTimeRequested, key: "notification.bedtimeDelay.requested") == l10n.notificationBedtimeDelayRequested)
        #expect(headline(.extraTimeRequested, key: "notification.extraTime.requested") == l10n.notificationExtraTimeRequested)
    }

    // Android `asNotificationMoment`, on the phone's clock.
    @Test func theMomentIsTodayYesterdayOrADate() {
        #expect(NotificationTexts.moment(at("2026-10-07T03:15:00Z"), now: now, l10n, calendar: tashkent) == "Bugun 08:15")
        #expect(NotificationTexts.moment(at("2026-10-06T19:30:00Z"), now: now, l10n, calendar: tashkent) == "Bugun 00:30")
        #expect(NotificationTexts.moment(at("2026-10-06T18:59:00Z"), now: now, l10n, calendar: tashkent) == "Kecha 23:59")
        #expect(NotificationTexts.moment(at("2026-10-05T18:59:00Z"), now: now, l10n, calendar: tashkent) == "5-oktabr 23:59")
        #expect(NotificationTexts.moment(at("2026-08-15T03:12:00Z"), now: now, l10n, calendar: tashkent) == "15-avgust 08:12")
    }

    @Test func theCaptionNamesTheChildWhenThereIsOne() {
        let row = parentNotification(occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(row, now: now, l10n, calendar: tashkent) == l10n.notificationChildAndMoment("Ali", "Bugun 08:15"))
        let digest = parentNotification(childId: nil, childName: nil, occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(digest, now: now, l10n, calendar: tashkent) == "Bugun 08:15")
        let blank = parentNotification(childName: " ", occurredAt: at("2026-10-07T03:15:00Z"))
        #expect(NotificationTexts.caption(blank, now: now, l10n, calendar: tashkent) == "Bugun 08:15")
    }

    // A tier that never rings the phone says so; the dot and card follow the tier (plan deviation N2).
    @Test func theTierDecidesTheNoteTheDotAndTheCard() {
        #expect(NotificationTexts.inAppNote(.good, l10n) == l10n.notificationsInAppOnly)
        #expect(NotificationTexts.inAppNote(.attention, l10n) == "Ilova ichida qoldi")
        #expect(NotificationTexts.inAppNote(.action, l10n) == nil)
        #expect(NotificationTexts.inAppNote(.critical, l10n) == nil)
        #expect(NotificationTexts.dotLevel(.good) == .good)
        #expect(NotificationTexts.dotLevel(.attention) == .attention)
        #expect(NotificationTexts.dotLevel(.action) == .action)
        #expect(NotificationTexts.dotLevel(.critical) == .critical)
        #expect(NotificationTexts.cardTone(.good) == .plain)
        #expect(NotificationTexts.cardTone(.attention) == .attention)
        #expect(NotificationTexts.cardTone(.action) == .attention)
        #expect(NotificationTexts.cardTone(.critical) == .critical)
    }

    @Test func theEmptyStateFollowsTheFilter() {
        #expect(NotificationTexts.emptyTitle(.all, l10n) == l10n.notificationsEmptyTitle)
        #expect(NotificationTexts.emptyBody(.all, l10n) == l10n.notificationsEmptyBody)
        #expect(NotificationTexts.emptyTitle(.important, l10n) == l10n.notificationsEmptyImportantTitle)
        #expect(NotificationTexts.emptyBody(.important, l10n) == l10n.notificationsEmptyImportantBody)
    }

    // Plan deviation N1 (Android `DeviceOfflineSetting`): whole hours read as hours, anything else keeps its minutes.
    @Test func theOfflineSettingIsInHours() {
        #expect(NotificationTexts.offlinePresets == [60, 120, 240, 360, 720, 1440])
        #expect(NotificationTexts.offlinePresets.allSatisfy {
            (NotificationPreferences.minDeviceOfflineMinutes...NotificationPreferences.maxDeviceOfflineMinutes).contains($0)
        })
        #expect(NotificationTexts.presetLabel(360, l10n) == "6 s")
        #expect(NotificationTexts.presetAccessibilityLabel(360, l10n) == "6 soat")
        #expect(NotificationTexts.offlineCurrent(360, l10n) == "Hozir: 6 soat")
        #expect(NotificationTexts.offlineCurrent(2880, l10n) == "Hozir: 48 soat")
        #expect(NotificationTexts.offlineCurrent(90, l10n) == l10n.notificationsOfflineCurrent(l10n.durationLongHoursMinutes(1, 30)))
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
@testable import NozirAppFeature

private let linkId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
private let linkText = "5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10"
private let aliChildId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!

private func row(_ type: NotificationType, link: String?, childId: UUID? = aliChildId, childName: String? = "Ali") -> ParentNotification {
    parentNotification(type: type, childId: childId, childName: childName, deepLink: link)
}

@Suite struct NotificationLinkTests {
    // Spec §4.2 (Android `pushDeepLinkOf`): the backend's five links this app can open.
    @Test func everyLinkThisAppCanOpenIsRead() {
        #expect(NotificationLink.parse("nozir://sos/\(linkText)") == .sos(linkId))
        #expect(NotificationLink.parse("nozir://extra-time/\(linkText)") == .extraTime(linkId))
        #expect(NotificationLink.parse("nozir://protection/\(linkText)") == .protection(linkId))
        #expect(NotificationLink.parse("nozir://summary/\(linkText)") == .summary(linkId))
        #expect(NotificationLink.parse("nozir://app-rules/\(linkText)") == .appRules(linkId))
        #expect(NotificationLink.parse("  nozir://sos/\(linkText.uppercased())/?from=push#top ") == .sos(linkId))
    }

    // Anything unrecognised is `other`: never a guess and never a crash.
    @Test func anythingElseIsOther() {
        let links: [String?] = [
            nil, "", "nozir://", "nozir://notifications", "nozir://map/\(linkText)",
            "nozir://challenges/\(linkText)", "nozir://subscription", "nozir://sos",
            "nozir://sos/not-a-uuid", "nozir://sos/\(linkText)/more", "https://nozir.uz/sos/\(linkText)",
            "nozir://something-new/\(linkText)",
        ]
        for link in links {
            #expect(NotificationLink.parse(link) == .other)
        }
    }

    @Test func aRowOpensTheScreenItsLinkNames() {
        let sos = row(.sosTriggered, link: "nozir://sos/\(linkText)")
        #expect(NotificationLink.step(for: sos) == .sos(ActiveSos(sosId: linkId, childId: aliChildId, childName: "Ali", triggeredAt: notifiedAt)))
        #expect(NotificationLink.step(for: row(.extraTimeRequested, link: "nozir://extra-time/\(linkText)")) == .timeRequest(linkId, usedMinutesToday: nil))
        #expect(NotificationLink.step(for: row(.protectionBroken, link: "nozir://protection/\(linkText)")) == .protection(linkId))
        #expect(NotificationLink.step(for: row(.limitReached, link: "nozir://app-rules/\(linkText)")) == .rules(linkId))
    }

    // D2: DAILY → the child's latest daily summary, WEEKLY → the weekly report.
    @Test func aSummaryLinkOpensByItsType() {
        let link = "nozir://summary/\(linkText)"
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link)) == .summary(aliChildId, "Ali"))
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: link)) == .weekly(aliChildId))
        #expect(NotificationLink.step(for: row(.usageAnomaly, link: link)) == nil)
        // Plan deviation N4: P06 needs the child's name.
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link, childName: nil)) == nil)
    }

    // Review Focus 7: a removed child or a family-wide row goes nowhere, and never crashes.
    @Test func aLinkThatNeedsAChildGoesNowhereWithoutOne() {
        #expect(NotificationLink.step(for: row(.sosTriggered, link: "nozir://sos/\(linkText)", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: "nozir://summary/\(linkText)", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: "nozir://summary/\(linkText)", childId: nil)) == nil)
        // The ask's own id is enough for P17.
        #expect(NotificationLink.step(for: row(.extraTimeRequested, link: "nozir://extra-time/\(linkText)", childId: nil)) == .timeRequest(linkId, usedMinutesToday: nil))
    }

    @Test func aRowWithoutALinkOrWithAnotherOneGoesNowhere() {
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: "nozir://notifications", childId: nil)) == nil)
        #expect(NotificationLink.step(for: row(.unknown("TRIAL_ENDING"), link: "nozir://subscription")) == nil)
        #expect(NotificationLink.step(for: row(.safeZoneLeft, link: "nozir://map/\(linkText)")) == nil)
        #expect(NotificationLink.step(for: row(.rulesChanged, link: nil)) == nil)
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'NotificationTexts' in scope`, `cannot find 'NotificationLink' in scope`.

- [ ] **Step 4: The words and tones**

`NozirKit/Sources/NozirAppFeature/Notifications/NotificationTexts.swift`:

```swift
import Foundation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P16 in words and tones (Android `NotificationHeadline`, `NotificationHeadlineRes`,
/// `ZoneCrossingHeadline`, `NotificationMoment`, `NotificationRow`,
/// `NotificationCardTone`, `NotificationsContent`, `DeviceOfflineSetting`).
/// The server sends a key and its arguments, never text.
enum NotificationTexts {
    private static let digestKey = "notification.digest.suppressed"
    private static let appInstalledKey = "notification.app.installed"
    private static let bedtimeDelayKey = "notification.bedtimeDelay.requested"
    private static let countArg = "count"
    private static let childNameArg = "childName"
    private static let zoneNameArg = "zoneName"

    // MARK: Headline

    /// Android's order: the digest's count, the new-apps count, a named zone
    /// crossing, a bedtime ask, then the type's own sentence.
    static func headline(_ notification: ParentNotification, _ l10n: L10n) -> String {
        let count = notification.localisationArgs[countArg]
        if notification.localisationKey == digestKey, let count {
            return l10n.notificationDigestSuppressed(count)
        }
        if notification.localisationKey == appInstalledKey, let count {
            return l10n.notificationAppInstalledCount(count)
        }
        if let named = zoneCrossing(notification, l10n) {
            return named
        }
        if notification.localisationKey == bedtimeDelayKey {
            return l10n.notificationBedtimeDelayRequested
        }
        return typeHeadline(notification.type, l10n)
    }

    /// "Umar «Uy»ga yetib keldi"; nil unless both names are there.
    private static func zoneCrossing(_ notification: ParentNotification, _ l10n: L10n) -> String? {
        guard let child = LocationTexts.present(notification.localisationArgs[childNameArg] ?? notification.childName),
              let zone = LocationTexts.present(notification.localisationArgs[zoneNameArg]) else { return nil }
        switch notification.type {
        case .safeZoneEntered: return l10n.notificationSafeZoneEnteredNamed(child, zone)
        case .safeZoneLeft: return l10n.notificationSafeZoneLeftNamed(child, zone)
        default: return nil
        }
    }

    private static func typeHeadline(_ type: NotificationType, _ l10n: L10n) -> String {
        switch type {
        case .sosTriggered: l10n.notificationSosTriggered
        case .safeZoneEntered: l10n.notificationSafeZoneEntered
        case .safeZoneLeft: l10n.notificationSafeZoneLeft
        case .protectionBroken: l10n.notificationProtectionBroken
        case .protectionRestored: l10n.notificationProtectionRestored
        case .deviceOffline: l10n.notificationDeviceOffline
        case .extraTimeRequested: l10n.notificationExtraTimeRequested
        case .challengeNeedsApproval: l10n.notificationChallengeNeedsApproval
        case .dailySummaryReady: l10n.notificationDailySummaryReady
        case .weeklyReportReady: l10n.notificationWeeklyReportReady
        case .limitReached: l10n.notificationLimitReached
        case .bedtimeViolation: l10n.notificationBedtimeViolation
        case .usageAnomaly: l10n.notificationUsageAnomaly
        case .rulesChanged: l10n.notificationRulesChanged
        case .subscriptionExpiring: l10n.notificationSubscriptionExpiring
        case .childAppOutdated: l10n.notificationChildAppOutdated
        case .appInstalled: l10n.notificationAppInstalled
        case .unknown: l10n.notificationUnknown
        }
    }

    // MARK: When, and for whom

    /// "Bugun 17:45", "Kecha 08:00", "15-avgust 08:12" on the phone's clock.
    static func moment(_ date: Date, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        let day = LocalDate(date, in: calendar)
        let today = LocalDate(now, in: calendar)
        let clock = DateTexts.timeOfDay(date, calendar: calendar)
        if day == today {
            return l10n.notificationMomentToday(clock)
        }
        if day == today.adding(days: -1) {
            return l10n.notificationMomentYesterday(clock)
        }
        return l10n.notificationMomentDate(DateTexts.dayAndMonth(day, l10n), clock)
    }

    /// "Ali · Bugun 17:45", or just the moment for a family-wide row.
    static func caption(_ notification: ParentNotification, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        let when = moment(notification.occurredAt, now: now, l10n, calendar: calendar)
        guard let name = LocationTexts.present(notification.childName) else { return when }
        return l10n.notificationChildAndMoment(name, when)
    }

    /// "Ilova ichida qoldi" for the tiers that never ring the phone.
    static func inAppNote(_ tier: NotificationTier, _ l10n: L10n) -> String? {
        tier.isImportant ? nil : l10n.notificationsInAppOnly
    }

    // MARK: Tones

    static func dotLevel(_ tier: NotificationTier) -> NozirStatusLevel {
        switch tier {
        case .good: .good
        case .attention: .attention
        case .action: .action
        case .critical: .critical
        }
    }

    /// GOOD is plain so the rows that matter stand out; iOS has no ACTION card
    /// (plan deviation N2), so ACTION shares the attention card.
    static func cardTone(_ tier: NotificationTier) -> NozirCardTone {
        switch tier {
        case .good: .plain
        case .attention, .action: .attention
        case .critical: .critical
        }
    }

    // MARK: Empty list

    static func emptyTitle(_ filter: NotificationFilter, _ l10n: L10n) -> String {
        filter == .important ? l10n.notificationsEmptyImportantTitle : l10n.notificationsEmptyTitle
    }

    static func emptyBody(_ filter: NotificationFilter, _ l10n: L10n) -> String {
        filter == .important ? l10n.notificationsEmptyImportantBody : l10n.notificationsEmptyBody
    }

    // MARK: "Telefon jim qolsa"

    /// Android's presets, in minutes (plan deviation N1); all inside 60…2880.
    static let offlinePresets = [60, 120, 240, 360, 720, 1440]

    /// "6 s" on the segment.
    static func presetLabel(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.notificationsOfflinePreset(minutes / 60)
    }

    /// "6 soat" for VoiceOver, so the short segment label is never read alone.
    static func presetAccessibilityLabel(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.notificationsOfflineValue(minutes / 60)
    }

    /// "Hozir: 6 soat"; a value that is not whole hours keeps its minutes.
    static func offlineCurrent(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let value = rest == 0 ? l10n.notificationsOfflineValue(hours) : l10n.durationLongHoursMinutes(hours, rest)
        return l10n.notificationsOfflineCurrent(value)
    }
}
```

- [ ] **Step 5: The links**

`NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift`:

```swift
import Foundation
import NozirInsights

/// A `nozir://` link read by hand (Android `pushDeepLinkOf`). Anything
/// unrecognised — map, challenges, subscription, notifications, a bad id, a
/// link from a newer server — is `other`: never a guess and never a crash.
enum NotificationLink: Equatable {
    case sos(UUID)
    case extraTime(UUID)
    /// The id is the child's.
    case protection(UUID)
    /// The id is the summary's; iOS opens by the row's child and type (plan deviation N11).
    case summary(UUID)
    /// The id is the child's.
    case appRules(UUID)
    case other

    private static let scheme = "nozir://"

    static func parse(_ deepLink: String?) -> NotificationLink {
        let trimmed = deepLink?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.hasPrefix(scheme) else { return .other }
        var rest = trimmed.dropFirst(scheme.count)
        if let cut = rest.firstIndex(where: { $0 == "?" || $0 == "#" }) {
            rest = rest[..<cut]
        }
        let segments = rest.split(separator: "/").map(String.init)
        guard segments.count == 2, let id = UUID(uuidString: segments[1]) else { return .other }
        switch segments[0] {
        case "sos": return .sos(id)
        case "extra-time": return .extraTime(id)
        case "protection": return .protection(id)
        case "summary": return .summary(id)
        case "app-rules": return .appRules(id)
        default: return .other
        }
    }

    /// Where a tapped row goes on Home's stack (spec D2), or nil: the row is
    /// still marked read, it just leads nowhere.
    static func step(for notification: ParentNotification) -> SignedInView.HomeStep? {
        switch parse(notification.deepLink) {
        case .sos(let sosId):
            guard let childId = notification.childId else { return nil }
            return .sos(ActiveSos(
                sosId: sosId,
                childId: childId,
                childName: notification.childName,
                triggeredAt: notification.occurredAt
            ))
        case .extraTime(let requestId):
            return .timeRequest(requestId, usedMinutesToday: nil)
        case .protection(let childId):
            return .protection(childId)
        case .summary:
            guard let childId = notification.childId else { return nil }
            switch notification.type {
            case .dailySummaryReady:
                guard let name = LocationTexts.present(notification.childName) else { return nil }
                return .summary(childId, name)
            case .weeklyReportReady:
                return .weekly(childId)
            default:
                return nil
            }
        case .appRules(let childId):
            return .rules(childId)
        case .other:
            return nil
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`, the 16 new tests among them.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/FakeNotifications.swift NozirKit/Tests/NozirAppFeatureTests/NotificationTextsTests.swift NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift NozirKit/Sources/NozirAppFeature/Notifications/NotificationTexts.swift NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16: notifications in words, tones and links

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: `NotificationsModel` — pages, filter, read, and the offline setting

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/NotificationsModelTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Notifications/NotificationsModel.swift`

**Interfaces:**
- Consumes: `NotificationsService`, `NotificationFilter`, `ParentNotification` (`isRead`, `markedRead(at:)`), `NotificationPage`, `NotificationPreferences` (`withDeviceOfflineAfter(minutes:)`) (Task 1); `NotificationLink.step(for:)` (Task 2); `FakeNotifications`, `notificationPage(_:cursor:)`, `notificationPreferences(offlineAfter:)`, `parentNotification(…)`, `notifiedAt` (Task 2); `UserMessage(_:)`, `.noConnection`, `.timeout`, `.serverProblem` (`UserMessage.swift`); `PauseGate` (`FakeLocation.swift:114`), `offline` (`FakeFamily.swift:5`); `ActiveSos`; `SignedInView.HomeStep`.
- Produces: `@MainActor @Observable final class NotificationsModel` with
  - `enum Phase: Equatable { case loading, ready, failed(UserMessage) }`;
  - `init(service: any NotificationsService)`;
  - read-only state `filter: NotificationFilter` (starts `.all`), `items: [ParentNotification]`, `nextCursor: String?`, `phase: Phase` (starts `.loading`), `isOffline`, `isLoadingMore`, `inlineMessage: UserMessage?`, `preferences: NotificationPreferences?`, `pendingOfflineMinutes: Int?`; settable `toast: UserMessage?`; computed `hasMore: Bool`, `isEmpty: Bool`, `offlineAfterMinutes: Int?`; test hook `lastRead: Task<Void, Never>?`;
  - `func appear() async` (first page, then the preferences once), `func load() async` (first page of the current filter), `func setFilter(_ filter: NotificationFilter) async`, `func loadMore() async`, `func open(_ notification: ParentNotification) -> SignedInView.HomeStep?`, `func loadPreferencesIfNeeded() async`, `func setOfflineAfter(minutes: Int) async`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/NotificationsModelTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
private let first = parentNotification(type: .sosTriggered, tier: .critical)
private let second = parentNotification(type: .limitReached, tier: .action, key: "notification.limit.reached")
private let third = parentNotification(type: .weeklyReportReady, tier: .good, key: "notification.insight.weeklyReady")
private let alreadyRead = parentNotification(type: .rulesChanged, tier: .good, key: "child.rules.changed", readAt: notifiedAt)
/// base64url("1791360000000").
private let cursor = "MTc5MTM2MDAwMDAwMA"

@MainActor
private func setup(_ script: FakeNotifications.Script) -> (NotificationsModel, FakeNotifications) {
    let fake = FakeNotifications(script)
    return (NotificationsModel(service: fake), fake)
}

@MainActor
@Suite struct NotificationsModelTests {
    @Test func theFirstPageAndTheSettingsAreLoaded() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second], cursor: cursor))]
        script.preferences = [.success(notificationPreferences())]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)
        #expect(model.filter == .all)

        await model.appear()

        #expect(model.phase == .ready)
        #expect(model.items == [first, second])
        #expect(model.hasMore)
        #expect(!model.isEmpty)
        #expect(model.preferences == notificationPreferences())
        #expect(model.offlineAfterMinutes == 360)
        #expect(await fake.calls == ["page", "preferences"])
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil)])
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeNotifications.Script()
        script.pages = [.failure(.unexpectedStatus(500)), .success(notificationPage([first]))]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))
        #expect(model.items.isEmpty)
        #expect(!model.isEmpty)

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.items == [first])
    }

    // Plan deviation N6: offline over a shown list keeps it and says so.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func goingOfflineKeepsTheList(failure: ApiFailure) async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .failure(failure), .success(notificationPage([second, first]))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.isOffline)
        #expect(model.items == [first])
        #expect(model.phase == .ready)
        #expect(model.inlineMessage == nil)

        await model.load()
        #expect(!model.isOffline)
        #expect(model.items == [second, first])
    }

    @Test func aServerFaultOverAShownListIsSaidUnderIt() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(model.inlineMessage == .serverProblem)
        #expect(!model.isOffline)
        #expect(model.items == [first])
    }

    @Test func noRowsAndNoCursorIsEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([]))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.isEmpty)
        #expect(!model.hasMore)
    }

    // Review Focus 2: a page whose rows were all unreadable still has a cursor.
    @Test func aPageWithNothingReadableStillOffersMore() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([], cursor: cursor))]
        let (model, _) = setup(script)

        await model.load()

        #expect(!model.isEmpty)
        #expect(model.hasMore)
    }

    @Test func moreRowsAreAppendedWithTheCursor() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second], cursor: cursor)), .success(notificationPage([second, third]))]
        let (model, fake) = setup(script)
        await model.load()

        await model.loadMore()

        #expect(model.items == [first, second, third])
        #expect(!model.hasMore)
        #expect(!model.isLoadingMore)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .all, cursor: cursor)])
    }

    // Review Focus 2: exactly a full page, then an empty one.
    @Test func anEmptyLastPageEndsTheListWithoutSayingEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .success(notificationPage([]))]
        let (model, _) = setup(script)
        await model.load()

        await model.loadMore()

        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(!model.isEmpty)
        #expect(model.inlineMessage == nil)
    }

    // Review Focus 3.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsOnMoreAskOnce() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .success(notificationPage([second]))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add { $0.pageGate = gate }

        let tap = Task { await model.loadMore() }
        await gate.untilPaused()
        #expect(model.isLoadingMore)
        await model.loadMore()
        await gate.release()
        await tap.value

        #expect(await fake.pageAsks.count == 2)
        #expect(model.items == [first, second])
        #expect(!model.isLoadingMore)
    }

    @Test func aFailedMoreIsSaidAndCanBeTriedAgain() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first], cursor: cursor)), .failure(offline), .success(notificationPage([second]))]
        let (model, _) = setup(script)
        await model.load()

        await model.loadMore()
        #expect(model.inlineMessage == .noConnection)
        #expect(model.items == [first])
        #expect(model.hasMore)
        #expect(!model.isLoadingMore)

        await model.loadMore()
        #expect(model.inlineMessage == nil)
        #expect(model.items == [first, second])
    }

    @Test func nothingMoreIsAskedWithoutACursorOrBeforeTheFirstPage() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first]))]
        let (model, fake) = setup(script)

        await model.loadMore()
        await model.load()
        await model.loadMore()

        #expect(await fake.calls == ["page"])
    }

    @Test func aFilterAsksForItsOwnFirstPage() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, third], cursor: cursor)), .success(notificationPage([first]))]
        let (model, fake) = setup(script)
        await model.load()

        await model.setFilter(.important)

        #expect(model.filter == .important)
        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .important, cursor: nil)])

        await model.setFilter(.important)
        #expect(await fake.pageAsks.count == 2)
    }

    @Test func anEmptyImportantListIsEmpty() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([third])), .success(notificationPage([]))]
        let (model, _) = setup(script)
        await model.load()

        await model.setFilter(.important)

        #expect(model.isEmpty)
        #expect(model.filter == .important)
    }

    // Review Focus 1 (spec §4.2): the older answer never lands over the newer filter.
    @Test(.timeLimit(.minutes(5)))
    func aFilterSwitchDropsTheOlderAnswer() async {
        let gate = PauseGate()
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([third, first], cursor: cursor)), .success(notificationPage([first]))]
        script.pageGate = gate
        let (model, fake) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.setFilter(.important)
        await gate.release()
        await older.value

        #expect(model.filter == .important)
        #expect(model.items == [first])
        #expect(!model.hasMore)
        #expect(model.phase == .ready)
        #expect(await fake.pageAsks == [.init(filter: .all, cursor: nil), .init(filter: .important, cursor: nil)])
    }

    // Review Focus 1: a refresh during "Yana" wins; the older rows are not appended.
    @Test(.timeLimit(.minutes(5)))
    func aRefreshDropsALoadMoreInFlight() async {
        var script = FakeNotifications.Script()
        script.pages = [
            .success(notificationPage([first], cursor: cursor)),
            .success(notificationPage([second], cursor: "older")),
            .success(notificationPage([third, first])),
        ]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add { $0.pageGate = gate }

        let more = Task { await model.loadMore() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await more.value

        #expect(model.items == [third, first])
        #expect(!model.hasMore)
        #expect(!model.isLoadingMore)
    }

    @Test func openingARowMarksItReadAtOnceAndTellsTheServer() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first, second]))]
        script.read = [.success(())]
        let (model, fake) = setup(script)
        await model.load()

        let step = model.open(first)

        #expect(step == nil)
        #expect(model.items[0].isRead)
        #expect(!model.items[1].isRead)
        _ = await model.lastRead?.value
        #expect(await fake.readIds == [first.id])
    }

    // Review Focus 4: a lost connection never un-reads the row or says anything.
    @Test func aFailedReadStaysSilent() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first]))]
        let (model, fake) = setup(script)
        await model.load()

        _ = model.open(first)
        _ = await model.lastRead?.value

        #expect(model.items[0].isRead)
        #expect(model.toast == nil)
        #expect(model.inlineMessage == nil)
        #expect(!model.isOffline)
        #expect(await fake.readIds == [first.id])
    }

    @Test func aRowAlreadyReadIsNotSentAgain() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([alreadyRead]))]
        let (model, fake) = setup(script)
        await model.load()

        _ = model.open(alreadyRead)

        #expect(model.lastRead == nil)
        #expect(await fake.calls == ["page"])
    }

    @Test func openingARowWithALinkGoesThere() async {
        let childId = UUID()
        let sos = parentNotification(childId: childId, deepLink: "nozir://sos/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10")
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([sos]))]
        script.read = [.success(())]
        let (model, _) = setup(script)
        await model.load()

        let step = model.open(sos)

        #expect(step == .sos(ActiveSos(sosId: sosId, childId: childId, childName: "Ali", triggeredAt: notifiedAt)))
        #expect(model.items[0].isRead)
    }

    // Spec §4.2: no settings, no card — and nothing said; the next visit asks again.
    @Test func settingsThatCannotBeReadHideTheCardQuietly() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([first])), .success(notificationPage([first]))]
        script.preferences = [.failure(offline), .success(notificationPreferences())]
        let (model, fake) = setup(script)

        await model.appear()
        #expect(model.preferences == nil)
        #expect(model.offlineAfterMinutes == nil)
        #expect(model.toast == nil)
        #expect(model.phase == .ready)

        await model.appear()
        #expect(model.preferences == notificationPreferences())
        await model.appear()
        #expect(await fake.calls.filter { $0 == "preferences" }.count == 2)
    }

    // Review Focus 5: a full replace with only the threshold changed.
    @Test func theOfflineSettingKeepsEveryOtherField() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.success(notificationPreferences(offlineAfter: 720))]
        let (model, fake) = setup(script)
        await model.loadPreferencesIfNeeded()

        await model.setOfflineAfter(minutes: 720)

        let saved = await fake.saved
        #expect(saved == [notificationPreferences(offlineAfter: 720)])
        #expect(saved.first?.quietHoursStart == "22:00")
        #expect(saved.first?.mutedTypes == ["LIMIT_REACHED", "SOMETHING_NEW"])
        #expect(saved.first?.dailyPushCap == 2)
        #expect(saved.first?.smsForCriticalEnabled == false)
        #expect(model.offlineAfterMinutes == 720)
        #expect(model.pendingOfflineMinutes == nil)
        #expect(model.toast == nil)
    }

    // Review Focus 5: said once; the card shows what is really stored.
    @Test func aRefusedSettingIsSaidAndTheOldValueStays() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.failure(offline)]
        let (model, _) = setup(script)
        await model.loadPreferencesIfNeeded()

        await model.setOfflineAfter(minutes: 1440)

        #expect(model.toast == .noConnection)
        #expect(model.offlineAfterMinutes == 360)
        #expect(model.preferences == notificationPreferences())
        #expect(model.pendingOfflineMinutes == nil)
    }

    @Test func theSameValueOrNoSettingsSendsNothing() async {
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        let (model, fake) = setup(script)

        await model.setOfflineAfter(minutes: 720)
        await model.loadPreferencesIfNeeded()
        await model.setOfflineAfter(minutes: 360)

        #expect(await fake.calls == ["preferences"])
    }

    @Test(.timeLimit(.minutes(5)))
    func aSecondChoiceWhileSavingIsIgnored() async {
        let gate = PauseGate()
        var script = FakeNotifications.Script()
        script.preferences = [.success(notificationPreferences())]
        script.save = [.success(notificationPreferences(offlineAfter: 720))]
        script.saveGate = gate
        let (model, fake) = setup(script)
        await model.loadPreferencesIfNeeded()

        let choice = Task { await model.setOfflineAfter(minutes: 720) }
        await gate.untilPaused()
        #expect(model.offlineAfterMinutes == 720)
        await model.setOfflineAfter(minutes: 1440)
        await gate.release()
        await choice.value

        #expect(await fake.saved.count == 1)
        #expect(model.offlineAfterMinutes == 720)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'NotificationsModel' in scope`.

- [ ] **Step 3: The model**

`NozirKit/Sources/NozirAppFeature/Notifications/NotificationsModel.swift`:

```swift
import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P16 (Android `NotificationsViewModel`): the family's whole history, a page
/// at a time, "Hammasi" or "Muhim"; a tapped row is read at once and the
/// server told behind it; and the "telefon jim qolsa" threshold. Nothing is
/// retried. Every load bumps a generation: a filter switch or a refresh drops
/// any older answer, including a "Yana" in flight.
@MainActor
@Observable
final class NotificationsModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// The first page failed with nothing on screen.
        case failed(UserMessage)
    }

    private(set) var filter: NotificationFilter = .all
    private(set) var items: [ParentNotification] = []
    private(set) var nextCursor: String?
    private(set) var phase: Phase = .loading
    /// A list is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var isLoadingMore = false
    /// Under the list: a "Yana" that failed, or a refresh fault that is not "offline".
    private(set) var inlineMessage: UserMessage?
    /// Nil until read; the card is not drawn without it.
    private(set) var preferences: NotificationPreferences?
    /// The preset just chosen, while its write is in flight.
    private(set) var pendingOfflineMinutes: Int?
    /// A failed settings write, said once; the view sets it back to nil.
    var toast: UserMessage?
    /// The latest background "read" call; only tests wait for it (plan deviation N8).
    @ObservationIgnored private(set) var lastRead: Task<Void, Never>?

    private let service: any NotificationsService
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isLoadingPreferences = false

    init(service: any NotificationsService) {
        self.service = service
    }

    var hasMore: Bool {
        nextCursor != nil
    }

    /// Nothing left to show — not "this page was empty" (Android `isEmpty`).
    var isEmpty: Bool {
        phase == .ready && items.isEmpty && nextCursor == nil
    }

    /// What the card shows: the choice in flight, else what the server stored.
    var offlineAfterMinutes: Int? {
        pendingOfflineMinutes ?? preferences?.deviceOfflineAfterMinutes
    }

    /// Every time the screen shows: the first page again, the settings until read once.
    func appear() async {
        await load()
        await loadPreferencesIfNeeded()
    }

    /// The first page of the current filter; a list on screen stays while it asks.
    func load() async {
        generation += 1
        let mine = generation
        if phase != .ready { phase = .loading }
        isLoadingMore = false
        do {
            let page = try await service.page(filter: filter, cursor: nil)
            guard mine == generation else { return }
            items = page.items
            nextCursor = page.nextCursor
            phase = .ready
            isOffline = false
            inlineMessage = nil
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if phase != .ready {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                inlineMessage = message
            }
        }
    }

    /// The other filter from its first page; the old rows go at once (plan deviation N5).
    func setFilter(_ newFilter: NotificationFilter) async {
        guard newFilter != filter else { return }
        filter = newFilter
        items = []
        nextCursor = nil
        phase = .loading
        isOffline = false
        inlineMessage = nil
        await load()
    }

    /// One "Yana" at a time; a row already shown is not added twice.
    func loadMore() async {
        guard let cursor = nextCursor, phase == .ready, !isLoadingMore else { return }
        isLoadingMore = true
        inlineMessage = nil
        let mine = generation
        do {
            let page = try await service.page(filter: filter, cursor: cursor)
            guard mine == generation else { return }
            let shown = Set(items.map(\.id))
            items += page.items.filter { !shown.contains($0.id) }
            nextCursor = page.nextCursor
            isOffline = false
        } catch is CancellationError {
            guard mine == generation else { return }
        } catch {
            guard mine == generation else { return }
            inlineMessage = UserMessage(error)
        }
        isLoadingMore = false
    }

    /// Read here, whether or not the row leads anywhere; the server is told
    /// behind it and its failure is silent (the row is unread again on the
    /// next fetch, which is the right way round for something this small).
    func open(_ notification: ParentNotification) -> SignedInView.HomeStep? {
        if !notification.isRead {
            let readAt = Date()
            items = items.map { $0.id == notification.id ? $0.markedRead(at: readAt) : $0 }
            let service = service
            let id = notification.id
            lastRead = Task {
                _ = try? await service.markRead(id)
            }
        }
        return NotificationLink.step(for: notification)
    }

    /// Read once; a failure is silent and asked again on the next visit.
    func loadPreferencesIfNeeded() async {
        guard preferences == nil, !isLoadingPreferences else { return }
        isLoadingPreferences = true
        defer { isLoadingPreferences = false }
        guard let fresh = try? await service.preferences() else { return }
        if preferences == nil {
            preferences = fresh
        }
    }

    /// Everything else sent back as read (a full replace). A refusal is a toast
    /// and the card goes back to the stored value.
    func setOfflineAfter(minutes: Int) async {
        guard let current = preferences, pendingOfflineMinutes == nil,
              current.deviceOfflineAfterMinutes != minutes else { return }
        pendingOfflineMinutes = minutes
        defer { pendingOfflineMinutes = nil }
        do {
            preferences = try await service.savePreferences(current.withDeviceOfflineAfter(minutes: minutes))
        } catch is CancellationError {
            return
        } catch {
            toast = UserMessage(error)
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`, the 24 new tests (one with two arguments) among them.

- [ ] **Step 5: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/NotificationsModelTests.swift NozirKit/Sources/NozirAppFeature/Notifications/NotificationsModel.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16: the notifications model — pages, filter, read, offline setting

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: P16 screen and its rows (with accessibility)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Screens/NotificationRow.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/NotificationsView.swift`

**Interfaces:**
- Consumes: `ParentNotification`, `NotificationFilter` (Task 1); `NotificationTexts.*` (Task 2); `NotificationsModel` (Task 3); `SignedInView.HomeStep`; design system `NozirCard(tone:)`, `NozirStatusDot(_:)`, `NozirButton(_:variant:size:isLoading:action:)` (variant `.ghost`), `NozirEmptyState(title:message:)`, `NozirErrorState(title:message:retryTitle:onRetry:)`, `NozirOfflineNotice(_:)`, `NozirInlineMessage(_:)`, `.nozirToast(_:)`, `.nozirText(_:color:)`, `NozirColor.{background,textSecondary,textTertiary}`, `NozirSpacing.*`; `Picker` + `.pickerStyle(.segmented)` as in `AppUsageView.swift:19-24` and `LocationTrackingView.swift:101-107` (the design system has no segmented control); L10n `screenNotificationsTitle`, `notificationsFilterAll`, `notificationsFilterImportant`, `notificationsLoadMore`, `notificationsOfflineTitle`, `notificationsOfflineBody`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`.
- Produces: `NotificationRow(notification: ParentNotification, now: Date, action: () -> Void)`; `NotificationsView(model: NotificationsModel, onOpen: @escaping (SignedInView.HomeStep) -> Void)`.

This task has no unit test of its own: every rule the screen shows is pinned by Tasks 2 and 3; the views are checked by the build here, wired and tested through `SignedInModel` in Task 5, and walked through in Task 6's E2E.

- [ ] **Step 1: The row**

`NozirKit/Sources/NozirAppFeature/Screens/NotificationRow.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// One line of the record (Android `NotificationRow`): the tier's dot, what
/// happened (bold while unread — the only unread mark, plan deviation N3),
/// "bola · vaqt", and "Ilova ichida qoldi" for a tier that never rang the
/// phone. One button for VoiceOver; the dot is decoration. Nothing is cut at
/// large text sizes.
struct NotificationRow: View {
    let notification: ParentNotification
    /// The moment the list draws, for "Bugun" / "Kecha".
    let now: Date
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard(tone: NotificationTexts.cardTone(notification.tier)) {
                HStack(alignment: .top, spacing: NozirSpacing.small) {
                    NozirStatusDot(NotificationTexts.dotLevel(notification.tier))
                        .padding(.top, NozirSpacing.small)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(NotificationTexts.headline(notification, l10n))
                            .bold(!notification.isRead)
                            .nozirText(.body)
                        Text(NotificationTexts.caption(notification, now: now, l10n))
                            .nozirText(.bodySmall, color: NozirColor.textTertiary)
                        if let note = NotificationTexts.inAppNote(notification.tier, l10n) {
                            Text(note).nozirText(.bodySmall, color: NozirColor.textTertiary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
```

- [ ] **Step 2: The screen**

`NozirKit/Sources/NozirAppFeature/Screens/NotificationsView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P16 as Android `NotificationsContent`: the filter, the offline notice, the
/// record (or its spinner, error or empty state), "Yana koʻrsatish", then the
/// "Telefon jim qolsa" card once the settings are read. No push note: iOS has
/// no push yet (spec §1). A tapped row is read at once; one that leads
/// somewhere pushes onto Home's stack.
struct NotificationsView: View {
    @State private var model: NotificationsModel
    private let onOpen: (SignedInView.HomeStep) -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: NotificationsModel, onOpen: @escaping (SignedInView.HomeStep) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                Picker(l10n.screenNotificationsTitle, selection: Binding(
                    get: { model.filter },
                    set: { filter in Task { await model.setFilter(filter) } }
                )) {
                    Text(l10n.notificationsFilterAll).tag(NotificationFilter.all)
                    Text(l10n.notificationsFilterImportant).tag(NotificationFilter.important)
                }
                .pickerStyle(.segmented)
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
                if let minutes = model.offlineAfterMinutes {
                    offlineCard(minutes)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenNotificationsTitle)
        .navigationBarTitleDisplayMode(.inline)
        // On open and on coming back from a screen a row opened (spec §5.2).
        .task { await model.appear() }
        .refreshable { await model.load() }
        // Back from another app: there is no push yet, so this is how news arrives.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .nozirToast(Binding(
            get: { model.toast?.text(l10n) },
            set: { if $0 == nil { model.toast = nil } }
        ))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if model.isEmpty {
                NozirEmptyState(
                    title: NotificationTexts.emptyTitle(model.filter, l10n),
                    message: NotificationTexts.emptyBody(model.filter, l10n)
                )
            } else {
                list
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        let now = Date()
        ForEach(model.items) { notification in
            NotificationRow(notification: notification, now: now) {
                if let step = model.open(notification) {
                    onOpen(step)
                }
            }
        }
        if let message = model.inlineMessage {
            NozirInlineMessage(message.text(l10n))
        }
        if model.hasMore {
            NozirButton(l10n.notificationsLoadMore, variant: .ghost, isLoading: model.isLoadingMore) {
                Task { await model.loadMore() }
            }
            .disabled(model.isLoadingMore)
        }
    }

    /// Android `DeviceOfflineSetting`: a value that is not a preset still reads
    /// right on the line below; the control then shows nothing selected.
    private func offlineCard(_ minutes: Int) -> some View {
        NozirCard {
            Text(l10n.notificationsOfflineTitle)
                .nozirText(.titleSmall)
                .accessibilityAddTraits(.isHeader)
            Text(l10n.notificationsOfflineBody)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Picker(l10n.notificationsOfflineTitle, selection: Binding(
                get: { minutes },
                set: { chosen in Task { await model.setOfflineAfter(minutes: chosen) } }
            )) {
                ForEach(NotificationTexts.offlinePresets, id: \.self) { preset in
                    Text(NotificationTexts.presetLabel(preset, l10n))
                        .accessibilityLabel(NotificationTexts.presetAccessibilityLabel(preset, l10n))
                        .tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .disabled(model.pendingOfflineMinutes != nil)
            Text(NotificationTexts.offlineCurrent(minutes, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
```

- [ ] **Step 3: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 4: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Screens/NotificationRow.swift NozirKit/Sources/NozirAppFeature/Screens/NotificationsView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16: the notifications screen and its rows

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: The way in — Home's bell, Profile's row, `HomeStep.notifications` and the wiring

**Files:**
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift:19-48` (`setup`) and a new test before the suite's closing `}` (after `theProtectionScreenIsForTheChildTapped`, line 330)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift` (property after line 31, init parameter after line 47, assignment after line 61, factory after `makeProtectionModel`, line 190)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:83`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift` (doc comment line 6-7, properties and init lines 8-38, toolbar after line 55)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift` (properties and init lines 13-32, settings card line 62)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`HomeStep` after line 23, `HomeView(…)` lines 65-74, `ProfileView(…)` lines 122-129, `clearPaths()` neighbour, `homeDestination` after the `.protection` branch)

**Interfaces:**
- Consumes: `NotificationsApi`, `NotificationsService` (Task 1); `FakeNotifications`, `notificationPage`, `notificationPreferences`, `parentNotification` (Task 2); `NotificationsModel` (Task 3); `NotificationsView(model:onOpen:)` (Task 4); `NozirSettingsRow(_:value:action:)`; `SignedInModel.tab` / `.home`; L10n `glyphBell`, `contentDescriptionNotifications`, `profileRowNotifications`.
- Produces: `SignedInModel.init(…, protection:, notifications: any NotificationsService, location:, …)`; `SignedInModel.makeNotificationsModel() -> NotificationsModel`; `SignedInView.HomeStep.notifications`; `HomeView.init(…, onOpenProtection:, onOpenNotifications: @escaping () -> Void, onAddChild:)`; `ProfileView.init(…, onOpenRules:, onOpenNotifications: @escaping () -> Void, onOpenPrivacy:)`.

- [ ] **Step 1: Write the failing test**

In `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`, replace `setup` (lines 19-48) with:

```swift
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales(),
    extraTime: FakeExtraTime = FakeExtraTime(),
    protection: FakeProtection = FakeProtection(),
    notifications: FakeNotifications = FakeNotifications(),
    privacy: FakePrivacy = FakePrivacy(),
    privacyConfig: PrivacyConfig = .absent,
    signOutLocally: @escaping @MainActor () -> Void = {}
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        insights: FakeInsights(),
        extraTime: extraTime,
        protection: protection,
        notifications: notifications,
        location: FakeLocation(),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        emergencyNumber: { "112" },
        privacy: privacy,
        privacyConfig: { privacyConfig },
        signOutLocally: signOutLocally,
        signOut: {}
    )
    return (model, fake)
}
```

and add inside `SignedInModelTests`, after `theProtectionScreenIsForTheChildTapped()`:

```swift
    // P16 (spec §4.2): the screen reads the session's service.
    @Test func theNotificationsScreenUsesTheSessionsService() async {
        var script = FakeNotifications.Script()
        script.pages = [.success(notificationPage([parentNotification()]))]
        script.preferences = [.success(notificationPreferences())]
        let notifications = FakeNotifications(script)
        let (model, _) = setup(FakeFamily.Script(), notifications: notifications)

        let screen = model.makeNotificationsModel()
        await screen.appear()

        #expect(screen.phase == .ready)
        #expect(screen.items.count == 1)
        #expect(screen.offlineAfterMinutes == 360)
        #expect(await notifications.calls == ["page", "preferences"])
    }
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra argument 'notifications' in call` and `value of type 'SignedInModel' has no member 'makeNotificationsModel'`.

- [ ] **Step 3: The session's service and the factory**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — after `private let protection: any ProtectionService` (line 31) add:

```swift
    private let notifications: any NotificationsService
```

in `init`, after the parameter `protection: any ProtectionService,` (line 47) add:

```swift
        notifications: any NotificationsService,
```

after `self.protection = protection` (line 61) add:

```swift
        self.notifications = notifications
```

and after `makeProtectionModel(childId:)` (ends line 190) add:

```swift

    /// P16 for this family; one per visit, like every pushed screen.
    func makeNotificationsModel() -> NotificationsModel {
        NotificationsModel(service: notifications)
    }
```

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — after `protection: ProtectionApi(client: authorised),` (line 83) add:

```swift
            notifications: NotificationsApi(client: authorised),
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Home's bell**

`NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift` — replace the doc comment (lines 6-7) with:

```swift
/// P05 as Android `HomeContent`: the SOS banner, the offline notice, then the
/// family (empty, one child, or many). The banner opens P15; the bell in the
/// navigation bar opens P16.
```

replace `private let onOpenProtection: (UUID) -> Void` (line 15) with:

```swift
    private let onOpenProtection: (UUID) -> Void
    private let onOpenNotifications: () -> Void
```

replace the init's parameter line `onOpenProtection: @escaping (UUID) -> Void,` (line 27) with:

```swift
        onOpenProtection: @escaping (UUID) -> Void,
        onOpenNotifications: @escaping () -> Void,
```

replace `self.onOpenProtection = onOpenProtection` (line 36) with:

```swift
        self.onOpenProtection = onOpenProtection
        self.onOpenNotifications = onOpenNotifications
```

and after `.navigationBarTitleDisplayMode(.inline)` (line 55) add:

```swift
        // Spec §5.1: the way to P16 from Home; VoiceOver reads the words, not the glyph.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onOpenNotifications) {
                    Text(l10n.glyphBell)
                }
                .accessibilityLabel(l10n.contentDescriptionNotifications)
            }
        }
```

- [ ] **Step 6: Profile's row**

`NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift` — replace `private let onOpenRules: () -> Void` (line 12) with:

```swift
    private let onOpenRules: () -> Void
    private let onOpenNotifications: () -> Void
```

replace the init's `onOpenRules: @escaping () -> Void,` (line 23) with:

```swift
        onOpenRules: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void,
```

replace `self.onOpenRules = onOpenRules` (line 30) with:

```swift
        self.onOpenRules = onOpenRules
        self.onOpenNotifications = onOpenNotifications
```

and replace the settings card's first row `NozirSettingsRow(l10n.profileRowPrivacy, action: onOpenPrivacy)` (line 62) with (Android `ProfileSettingsCard` order: notifications before privacy):

```swift
                    NozirSettingsRow(l10n.profileRowNotifications, action: onOpenNotifications)
                    Divider()
                    NozirSettingsRow(l10n.profileRowPrivacy, action: onOpenPrivacy)
```

- [ ] **Step 7: The route**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — in `enum HomeStep`, after `case protection(UUID)` (line 23) add:

```swift
        /// P16, from Home's bell or Profile's row (spec D1: its links push onto Home's stack).
        case notifications
```

replace the `HomeView(…)` call (lines 65-74) with:

```swift
                HomeView(
                    model: model.makeHomeModel(),
                    reloadToken: model.homeRefresh,
                    emergencyNumber: { model.currentEmergencyNumber },
                    onOpenSummary: { homePath.append(.summary($0, $1)) },
                    onOpenSos: { homePath.append(.sos($0)) },
                    onOpenTimeRequest: { homePath.append(.timeRequest($0, usedMinutesToday: $1)) },
                    onOpenProtection: { homePath.append(.protection($0)) },
                    onOpenNotifications: { openNotifications() },
                    onAddChild: { model.presentAddChild() }
                )
```

replace the `ProfileView(…)` call (lines 122-129) with:

```swift
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) },
                    onOpenRules: { profilePath.append(.rules(nil)) },
                    onOpenNotifications: { openNotifications() },
                    onOpenPrivacy: { profilePath.append(.privacy) }
                )
```

after `clearPaths()` (the private function before `homeDestination`) add:

```swift

    /// P16 always lives on Home's stack, so a row's link pushes where that
    /// screen belongs; from Profile the tab switches first (spec D1). Never
    /// stacked twice (plan deviation N9).
    private func openNotifications() {
        model.tab = .home
        if homePath.last != .notifications {
            homePath.append(.notifications)
        }
    }
```

and in `homeDestination(_:)`, after the `.protection` branch (`ProtectionView(model: model.makeProtectionModel(childId: childId))`) add:

```swift
        case .notifications:
            NotificationsView(model: model.makeNotificationsModel()) { step in
                homePath.append(step)
            }
```

- [ ] **Step 8: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 9: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16: Home's bell, Profile's row, and the route to the notifications list

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 6: Final check — whole suite, l10n, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, l10n up to date (no new key), `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `git diff --stat cb91f49 -- NozirKit/l10n NozirKit/Sources/NozirL10n NozirKit/Package.swift` is empty, and `git diff --stat cb91f49 -- NozirKit/Sources/NozirAppFeature/Protection NozirKit/Sources/NozirInsights/Protection*` is empty (P18 untouched).

- [ ] **Step 2: E2E (the user; simulator + the real backend + an Android child phone paired to the family, and the Android parent app on the same family)**

Write "yes" or what was seen against each line:

1. Home shows 🔔 at the right of the navigation bar (one child, many children, no children, and while Home is loading or failed); tap → "Bildirishnomalar" with "Hammasi" selected, newest first, the same rows and order the Android parent app's P16 shows.
2. Each row: the dot's colour follows the tier; SOS rows sit on the red card, ACTION rows (limit reached, extra-time ask, protection) on the yellow card, GOOD rows plain; "Ali · Bugun 17:45" / "Kecha …" / "15-avgust …"; "Ilova ichida qoldi" only under GOOD and ATTENTION rows; the digest reads "N ta bildirishnoma ilova ichida qoldi" with no child name.
3. Unread rows are bold; tap one → it turns regular at once; leave and come back → still regular (backend log: one `POST …/read`, 204). With airplane mode on, tap an unread row → it turns regular, no message appears.
4. Tap an SOS row → P15 for that alarm; an extra-time row → P17 for that ask; a protection row → P18 for that child; a daily-summary row → P06 for that child; a weekly-report row → the weekly report; a limit-reached / new-apps row → that child's rules hub. Back returns to P16, refreshed.
5. Tap a digest row, a zone-crossing row and a subscription/trial row → the row turns regular and nothing opens; no crash. A trial or lapsed-subscription row reads "Yangi bildirishnoma".
6. "Muhim" → only red and yellow rows; switch back and forth quickly on a slow connection (Network Link Conditioner "3G") → the list always matches the selected segment. A family with no important rows → "Muhim bildirishnoma yoʻq · Bu yaxshi xabar — hammasi joyida."
7. More than 20 notifications → "Yana koʻrsatish" under the list; tap → the next rows follow, no duplicates; double-tap quickly → one request in the backend log; at the end the button disappears and no "Hali bildirishnoma yoʻq" appears. A family with exactly 20 → one extra tap shows nothing new and the button goes.
8. Pull to refresh → a new event (trigger one on the child phone, e.g. a safe-zone crossing) appears on top; background → foreground the app on P16 → it refreshes by itself.
9. Airplane mode, pull to refresh → offline notice, the list stays; "Yana koʻrsatish" → "Internet aloqasi yoʻq…" under the list, the button works again once online. Open P16 for the first time with airplane mode on → the error state with "Qayta urinish", which loads the list once online.
10. "Telefon jim qolsa" card at the bottom: "1 s · 2 s · 4 s · 6 s · 12 s · 24 s" with the stored value selected and "Hozir: 6 soat"; choose "12 s" → "Hozir: 12 soat"; the Android parent app's P16 shows 12 hours; the backend `notification_preference` row keeps its quiet hours, muted types, cap and SMS switch unchanged. Set it to 2880 minutes outside the app (a `PUT /v1/parent/notification-preferences` with the same body and `"deviceOfflineAfterMinutes":2880`) → iOS shows no segment selected and "Hozir: 48 soat".
11. Airplane mode, choose another preset → toast "Internet aloqasi yoʻq…", the card goes back to the stored value. Settings unreadable (stop the backend after the list loads, reopen) → the card is simply absent, no message.
12. Profile → settings card: "Bildirishnomalar" above "Maxfiylik"; tap → the app switches to the Home tab with P16 open; tap a row there → its screen opens on Home's stack; go to Profile and tap "Bildirishnomalar" again → back on Home with one P16 (not two) on top.
13. VoiceOver: the bell reads "Bildirishnomalar tarixi", button; each row reads as one button — headline, "Ali · Bugun …", "Ilova ichida qoldi" when shown; the dot is silent; the offline presets read "6 soat"; "Telefon jim qolsa" is a heading. Largest Dynamic Type: rows and the card wrap, nothing cut.
14. Three languages and both themes: every P16 text correct, the red and yellow cards readable in dark mode; screenshots (Cmd+S).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.

## Open questions (ruled while planning)

- **Q1 — the offline presets.** Spec §5.2 lists 6/12/24/48 hours, spec D3 says "Android presetlari", and Android ships 1/2/4/6/12/24 hours (`DeviceOfflineSetting.kt`). Ruling: Android's (plan deviation N1), because D3 is the user's decision and the spec's stated goal is the same result as Android. If the user wants 6/12/24/48, change `NotificationTexts.offlinePresets` to `[360, 720, 1440, 2880]` and its test in `theOfflineSettingIsInHours` — nothing else depends on the list.
- **Q2 — "unread" for VoiceOver.** Spec §5.2 asks for the unread state in words, but no l10n key says "unread" and the spec forbids new keys. Ruling: bold only, as Android (plan deviation N3); a key can be added later through the Android strings (`sync-android-strings.sh`) and read out in `NotificationRow`.
- **Q3 — a removed child's rows.** The backend joins the child's name with `LEFT JOIN child`, so a removed child's rows may still carry `childId`. An SOS or summary row for a removed child then opens P15 / P06, which answer "not found" in their own words; this is Android's behaviour too and needs no special case here.
