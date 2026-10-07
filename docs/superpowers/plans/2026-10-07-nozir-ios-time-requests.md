# Nozir iOS — P17: Extra-time requests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a child asks for extra minutes or to push tonight's bedtime back, the parent sees a row on Home (one child or many), opens P17, reads who asked, when, why and how often, and answers once — all of it, a computed smaller amount, or no with an optional reason — and then sees the answer on the screen; an ask that was already answered elsewhere or has expired sends the screen to "no pending requests", never to an error about rules.

**Architecture:** `NozirInsights` gains the request models (`ExtraTimeRequest`, `ExtraTimeKind`, `ExtraTimeStatus`, `ExtraTimeOutcome`), an `ExtraTimeService` protocol with its `ExtraTimeApi`, and `ParentHome.pendingExtraTimeRequests`; `NozirNetworking.ApiErrorCode` gains `alreadyDecided`. In `NozirAppFeature`, `HomeModel` exposes the rows, `PartialMinutes` and `TimeRequestTexts` hold the pure rules and words, and `TimeRequestModel` (`@MainActor @Observable`, built like `SosDetailModel`) finds the ask in the pending list and sends exactly one decision. `TimeRequestView` and `TimeRequestRow` draw it; `SignedInView` gets `HomeStep.timeRequest`, `SignedInModel` a factory and the service.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; no third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-ios-time-requests-design.md` (commit `04c5d4c`). The backend contract (§3) is live and unchanged.

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries.
- Every `/v1/parent/*` call goes through `ApiClient`. A decision is **never retried automatically**: one tap, one POST; a second tap while the first is in flight does nothing.
- `GET /v1/parent/extra-time-requests?status=PENDING` → `{items: [ExtraTimeRequest], nextCursor}`; the cursor is not used.
- `POST /v1/parent/extra-time-requests/{id}/decision` body `{outcome: APPROVE|PARTIAL|DECLINE, grantedMinutes?: Int, note?: String}` → 200 `ExtraTimeRequest`. Absent fields are omitted, never sent as `null`. The id goes in the path lowercased (like `InsightsApi.childPath`).
- `ExtraTimeRequest`: `id`, `childId`, `childName?`, `kind` (absent → `EXTRA_MINUTES`), `nightOf?`, `requestedMinutes`, `reason`, `status` (`PENDING|APPROVED|DECLINED|EXPIRED`), `grantedMinutes?`, `decisionNote?`, `createdAt`, `decidedAt?`, `requestsInLastSevenDays?`. A kind or status this app does not know decodes as `.unknown(raw)`, never as a failure.
- 409 `ALREADY_DECIDED` or 404 on a decision → the pending list is read again (usually `.missing`); any other failure → toast through `UserMessage`, the ask and the buttons stay.
- `PartialMinutes.of`: `EXTRA_MINUTES` → `requested / 2` rounded down to a multiple of 5; `< 5` or `>= requested` → nil. `BEDTIME_DELAY` → 15 when `requested > 15`, otherwise nil.
- Decline note: at most 280 characters kept; trimmed; blank → `note` omitted.
- Home: `ParentHome.pendingExtraTimeRequests` (absent key → `[]`); a row per waiting ask, in both the one-child and the family layout, above the stat cards.
- User-facing text only from `L10n`, errors only through `UserMessage`; the server's `message` is never shown. **No new l10n key** (`gen_l10n.py --check` stays clean).
- Out of scope: push / deep link `nozir://extra-time/{id}`, the notifications list (P16), an amount picker, a history list, the backend.
- Tests: Swift Testing; scripted fakes (`FakeExtraTime`, `FakeInsights`, `FakeFamily`), `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`.
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| T1 | `HomeStep.timeRequest(UUID)`, `makeTimeRequestModel(id:)` | `HomeStep.timeRequest(UUID, usedMinutesToday: Int?)`, `makeTimeRequestModel(id:usedMinutesToday:)` | `SignedInModel` holds no `HomeModel` (`HomeView` keeps the one `makeHomeModel()` gave it); the row already knows the child's card, so it passes the minutes (Android reads the same number from the home answer) |
| T2 | Home row is an "urg'u kartasi" (accent card) | A plain `NozirCard` with an accent tile (`primaryContainer`) and accent sub-line (`primaryAccent`) | iOS `NozirCardTone` has only `plain/attention/critical`; attention would read as a warning about the child (Android's own comment). No design-system change in this plan |
| T3 | `unknown(String)` kind | An ask of an unknown kind is **not answerable**: no Home row, P17 says `.missing` | The app cannot say what a yes would do; a parent must never approve minutes and find a bedtime moved |
| T4 | — | Once an answer is on screen, `load()` does nothing | The pending list no longer has the ask; a refresh would otherwise replace "15 daqiqa berildi" with "Kutilayotgan soʻrov yoʻq" |
| T5 | Network error with data → `isOffline` | Only `noConnection` / `timeout` set `isOffline`; any other refresh failure with the ask shown is a toast | Android `withFailure`; "offline" over a 500 is false |
| T6 | `ParentHome.pendingExtraTimeRequests` (absent → `[]`) | Also `[]` when the list cannot be decoded | Home is the app's front door; one unreadable ask must not blank it |
| T7 | `isDeciding` | `deciding: ExtraTimeOutcome?` with `isDeciding` computed from it | The spinner goes on the button that was tapped |
| T8 | `declineNote` (280-character bound) | `private(set) var declineNote` + `updateDeclineNote(_:)` that cuts at 280 | The `AddChildModel.updateName` pattern: the field shows what is kept |
| T9 | Family view: "har bir so'rov — ism bilan qator" | Rows follow the avatar filter (one child picked → that child's asks only) | The filter already narrows the cards below |
| T10 | Row position "stat kartalaridan oldin" | One child: after the summary card, before the two stat tiles. Family: after the switcher, before the child cards | Android puts it after the tiles; the spec moves it up — followed |

## Review Focus

1. **Pull-to-refresh (or coming back to the app) after answering** — the answer card stays; it never turns into "no pending requests" → Task 4 `aRefreshAfterTheAnswerKeepsTheAnswer`.
2. **A refusal from the server that is not "already decided"** (bedtime night over → 409 `CONFLICT`, a 400, no connection) — toast once, the ask stays pending, an open decline card keeps its note, and the parent can try again → Task 4 `aFailedDecisionIsSaidOnceAndCanBeTriedAgain`, `aDecisionWithNoConnectionIsNotRetried`.
3. **A Home answer whose pending list the app cannot read** (a new field shape, a bad id) — Home still loads with no rows → Task 2 `aListThatCannotBeReadLeavesHomeStanding`.
4. **A decline note that is only spaces, or longer than 280** — no quotes around nothing reach the child; the field never holds more than the server takes → Task 4 `aBlankNoteIsNoNoteAndALongOneIsCut`.
5. **An ask of a kind this app does not know** (a newer backend) — no Home row, no buttons, P17 says there is nothing waiting → Task 2 `timeRequestRowsFollowTheFilterAndSkipWhatCannotBeAnswered`, Task 4 `anAskOfAnUnknownKindIsMissing`.

---

## File map

**New:**
- `NozirKit/Sources/NozirInsights/ExtraTimeModels.swift` — `ExtraTimeKind`, `ExtraTimeStatus`, `ExtraTimeOutcome`, `ExtraTimeRequest`.
- `NozirKit/Sources/NozirInsights/ExtraTimeService.swift` — `ExtraTimeService`.
- `NozirKit/Sources/NozirInsights/ExtraTimeApi.swift` — `ExtraTimeApi`.
- `NozirKit/Tests/NozirInsightsTests/ExtraTimeApiTests.swift`.
- `NozirKit/Sources/NozirAppFeature/TimeRequests/PartialMinutes.swift`, `TimeRequestTexts.swift`, `TimeRequestModel.swift`.
- `NozirKit/Sources/NozirAppFeature/Screens/TimeRequestView.swift`, `TimeRequestRow.swift`.
- `NozirKit/Tests/NozirAppFeatureTests/FakeExtraTime.swift`, `TimeRequestTextsTests.swift`, `TimeRequestModelTests.swift`.

**Modified:** `NozirNetworking/ApiErrorCode.swift`; `NozirInsights/InsightModels.swift` (`ParentHome`); `NozirAppFeature/Insights/HomeModel.swift`; `NozirAppFeature/{SignedInModel,AppEnvironment}.swift`; `NozirAppFeature/Screens/{HomeView,SignedInView}.swift`; tests `NozirNetworkingTests/ApiErrorTests.swift`, `NozirInsightsTests/{InsightsFixtures,InsightsApiTests}.swift`, `NozirAppFeatureTests/{FakeInsights,HomeModelTests,SignedInModelTests}.swift`.

No `Package.swift` change: everything lives in existing targets.

## Getting started

Branch `time-requests` (spec commit `04c5d4c`) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirNetworkingTests`, `NozirInsightsTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

---
### Task 1: The request, as the server writes it — models, `ExtraTimeApi`, `ALREADY_DECIDED`

**Files:**
- Modify: `NozirKit/Sources/NozirNetworking/ApiErrorCode.swift:39` (after `safeZoneLimitReached`)
- Modify: `NozirKit/Tests/NozirNetworkingTests/ApiErrorTests.swift` (new test before the suite's closing `}` at line 51)
- Create: `NozirKit/Sources/NozirInsights/ExtraTimeModels.swift`
- Create: `NozirKit/Sources/NozirInsights/ExtraTimeService.swift`
- Create: `NozirKit/Sources/NozirInsights/ExtraTimeApi.swift`
- Modify: `NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` (append at the end)
- Create: `NozirKit/Tests/NozirInsightsTests/ExtraTimeApiTests.swift`

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiRequest(method:path:query:)`, `ApiRequest.post(_:json:)`, `LocalDate` (Codable), `FakeTransport`, `.ok`, `.error`, `URLRequest.jsonBody` / `jsonObject` / `queryParameters`, `FixedToken`, `aliId`, `instant(_:)` (`InsightsFixtures.swift`).
- Produces:
  - `ApiErrorCode.alreadyDecided` (`"ALREADY_DECIDED"`).
  - `public enum ExtraTimeKind: Hashable, Sendable, Decodable { case extraMinutes, bedtimeDelay, unknown(String); init(rawValue: String); var isKnown: Bool }`.
  - `public enum ExtraTimeStatus: Hashable, Sendable, Decodable { case pending, approved, declined, expired, unknown(String); init(rawValue: String) }`.
  - `public enum ExtraTimeOutcome: String, Sendable, Encodable { case approve = "APPROVE", partial = "PARTIAL", decline = "DECLINE" }`.
  - `public struct ExtraTimeRequest: Decodable, Hashable, Sendable, Identifiable` with the fields of Global Constraints (`id: UUID`, `childId: UUID`, `childName: String?`, `kind`, `nightOf: LocalDate?`, `requestedMinutes: Int`, `reason: String`, `status`, `grantedMinutes: Int?`, `decisionNote: String?`, `createdAt: Date`, `decidedAt: Date?`, `requestsInLastSevenDays: Int?`), `init(id:childId:childName:kind:nightOf:requestedMinutes:reason:status:grantedMinutes:decisionNote:createdAt:decidedAt:requestsInLastSevenDays:)` (optionals default `nil`, `kind` defaults `.extraMinutes`), and `var isAnswerable: Bool` (pending and a known kind).
  - `public protocol ExtraTimeService: Sendable { func pending() async throws -> [ExtraTimeRequest]; func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest }`.
  - `public struct ExtraTimeApi: ExtraTimeService { public init(client: ApiClient) }`.
  - Test fixtures (NozirInsightsTests only): `requestId`, `extraTimeApi(_:)`, `extraTimeJSON(kind:status:requested:extra:)`, `page(_:)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirNetworkingTests/ApiErrorTests.swift` — add inside `ApiErrorTests`, before its closing `}`:

```swift
    // P17: a decision on an ask the other parent answered, or one that expired.
    @Test func anAnsweredRequestIsAlreadyDecided() {
        let body = Data(#"{"error":{"code":"ALREADY_DECIDED","message":"x"}}"#.utf8)

        #expect(ResponseMapping.failure(status: 409, body: body).code == ApiErrorCode.alreadyDecided)
    }
```

`NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` — append at the end of the file:

```swift
let requestId = UUID(uuidString: "7C3E1A20-1B2C-4D3E-8F4A-5B6C7D8E9F01")!

func extraTimeApi(_ replies: [FakeTransport.Reply]) -> (ExtraTimeApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (ExtraTimeApi(client: client), transport)
}

/// `ExtraTimeRequestDto` as the backend writes it (`non_null`: absent, not
/// null). `kind: nil` leaves the field out; `extra` is spliced in before the
/// closing brace and must start with a comma.
func extraTimeJSON(kind: String? = "EXTRA_MINUTES", status: String = "PENDING", requested: Int = 30, extra: String = "") -> String {
    let kindField = kind.map { #""kind":"\#($0)","# } ?? ""
    return """
    {"id":"7c3e1a20-1b2c-4d3e-8f4a-5b6c7d8e9f01","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "childName":"Ali",\(kindField)"requestedMinutes":\(requested),"reason":"Uy vazifasi tugadi",\
    "status":"\(status)","createdAt":"2026-10-07T14:05:00Z","requestsInLastSevenDays":2\(extra)}
    """
}

/// `ExtraTimeRequestPage` around the given items.
func page(_ items: String...) -> String {
    "{\"items\":[" + items.joined(separator: ",") + "]}"
}
```

Create `NozirKit/Tests/NozirInsightsTests/ExtraTimeApiTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the tests to see them fail**

Run, one at a time: `bash .superpowers/run.sh NozirNetworkingTests 170`, then `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: build errors — `type 'ApiErrorCode' has no member 'alreadyDecided'`, `cannot find 'ExtraTimeApi' in scope`.

- [ ] **Step 3: `ApiErrorCode.alreadyDecided`**

In `NozirKit/Sources/NozirNetworking/ApiErrorCode.swift`, after `public static let safeZoneLimitReached = …` (line 39) add:

```swift
    /// A decision on something already decided: an extra-time ask the other
    /// parent answered, or one that expired (P17).
    public static let alreadyDecided = ApiErrorCode(rawValue: "ALREADY_DECIDED")
```

- [ ] **Step 4: The models**

Create `NozirKit/Sources/NozirInsights/ExtraTimeModels.swift`:

```swift
import Foundation

/// `ExtraTimeKind`: what a yes does — minutes into today, or one night's
/// bedtime moved. A kind this app does not know is kept as it came.
public enum ExtraTimeKind: Hashable, Sendable, Decodable {
    case extraMinutes
    case bedtimeDelay
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "EXTRA_MINUTES": self = .extraMinutes
        case "BEDTIME_DELAY": self = .bedtimeDelay
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Only a kind the app can put into words may be answered: a parent must
    /// never approve minutes and find they moved a bedtime.
    public var isKnown: Bool {
        if case .unknown = self { return false }
        return true
    }
}

/// `ExtraTimeStatus`. A status this app does not know is kept as it came.
public enum ExtraTimeStatus: Hashable, Sendable, Decodable {
    case pending
    case approved
    case declined
    case expired
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "PENDING": self = .pending
        case "APPROVED": self = .approved
        case "DECLINED": self = .declined
        case "EXPIRED": self = .expired
        default: self = .unknown(rawValue)
        }
    }

    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// The parent's answer (`ExtraTimeOutcome`).
public enum ExtraTimeOutcome: String, Sendable, Encodable {
    case approve = "APPROVE"
    case partial = "PARTIAL"
    case decline = "DECLINE"
}

/// `ExtraTimeRequestDto`. The backend leaves out what is null (`non_null`);
/// an absent `kind` is the backend's default, extra minutes.
public struct ExtraTimeRequest: Decodable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    /// Nil when the child was removed.
    public let childName: String?
    public let kind: ExtraTimeKind
    /// The evening the moved night opens on; only for `bedtimeDelay`.
    public let nightOf: LocalDate?
    public let requestedMinutes: Int
    /// The child's own words, shown as written.
    public let reason: String
    public let status: ExtraTimeStatus
    public let grantedMinutes: Int?
    public let decisionNote: String?
    public let createdAt: Date
    public let decidedAt: Date?
    public let requestsInLastSevenDays: Int?

    public init(
        id: UUID,
        childId: UUID,
        childName: String? = nil,
        kind: ExtraTimeKind = .extraMinutes,
        nightOf: LocalDate? = nil,
        requestedMinutes: Int,
        reason: String,
        status: ExtraTimeStatus,
        grantedMinutes: Int? = nil,
        decisionNote: String? = nil,
        createdAt: Date,
        decidedAt: Date? = nil,
        requestsInLastSevenDays: Int? = nil
    ) {
        self.id = id
        self.childId = childId
        self.childName = childName
        self.kind = kind
        self.nightOf = nightOf
        self.requestedMinutes = requestedMinutes
        self.reason = reason
        self.status = status
        self.grantedMinutes = grantedMinutes
        self.decisionNote = decisionNote
        self.createdAt = createdAt
        self.decidedAt = decidedAt
        self.requestsInLastSevenDays = requestsInLastSevenDays
    }

    enum CodingKeys: String, CodingKey {
        case id, childId, childName, kind, nightOf, requestedMinutes, reason, status
        case grantedMinutes, decisionNote, createdAt, decidedAt, requestsInLastSevenDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        childName = try container.decodeIfPresent(String.self, forKey: .childName)
        kind = try container.decodeIfPresent(ExtraTimeKind.self, forKey: .kind) ?? .extraMinutes
        nightOf = try container.decodeIfPresent(LocalDate.self, forKey: .nightOf)
        requestedMinutes = try container.decode(Int.self, forKey: .requestedMinutes)
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? ""
        status = try container.decode(ExtraTimeStatus.self, forKey: .status)
        grantedMinutes = try container.decodeIfPresent(Int.self, forKey: .grantedMinutes)
        decisionNote = try container.decodeIfPresent(String.self, forKey: .decisionNote)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        decidedAt = try container.decodeIfPresent(Date.self, forKey: .decidedAt)
        requestsInLastSevenDays = try container.decodeIfPresent(Int.self, forKey: .requestsInLastSevenDays)
    }

    /// Waiting for an answer, and of a kind the app can describe.
    public var isAnswerable: Bool {
        status == .pending && kind.isKnown
    }
}
```

- [ ] **Step 5: The service and the API**

Create `NozirKit/Sources/NozirInsights/ExtraTimeService.swift`:

```swift
import Foundation

/// The child's asks for more time and the parent's answers (P17). `ExtraTimeApi`
/// is the real one; screen-model tests use a scripted fake.
public protocol ExtraTimeService: Sendable {
    /// Waiting asks, newest first (the server's order). There is no call for one ask.
    func pending() async throws -> [ExtraTimeRequest]
    /// One answer, sent once and never retried here. 409 `ALREADY_DECIDED` when
    /// it was answered elsewhere or expired; 404 when it is not this family's.
    func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest
}
```

Create `NozirKit/Sources/NozirInsights/ExtraTimeApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/extra-time-requests` (backend `ChallengeController`).
public struct ExtraTimeApi: ExtraTimeService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static let path = "/v1/parent/extra-time-requests"

    public func pending() async throws -> [ExtraTimeRequest] {
        let request = ApiRequest(method: .get, path: Self.path, query: ["status": "PENDING"])
        return try await client.send(request, as: ExtraTimePage.self).items
    }

    public func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest {
        let body = DecisionBody(outcome: outcome, grantedMinutes: grantedMinutes, note: note)
        let request = try ApiRequest.post(Self.path + "/\(id.uuidString.lowercased())/decision", json: body)
        return try await client.send(request, as: ExtraTimeRequest.self)
    }
}

/// `ExtraTimeRequestPage`. `nextCursor` is not read: the pending list is short.
private struct ExtraTimePage: Decodable {
    let items: [ExtraTimeRequest]

    enum CodingKeys: String, CodingKey {
        case items
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([ExtraTimeRequest].self, forKey: .items) ?? []
    }
}

/// `ExtraTimeDecisionBody`. The synthesised encoding leaves nil fields out.
private struct DecisionBody: Encodable {
    let outcome: ExtraTimeOutcome
    let grantedMinutes: Int?
    let note: String?
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run, one at a time: `bash .superpowers/run.sh NozirNetworkingTests 170`, then `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: `** TEST SUCCEEDED **` both times.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirNetworking/ApiErrorCode.swift NozirKit/Tests/NozirNetworkingTests/ApiErrorTests.swift NozirKit/Sources/NozirInsights/ExtraTimeModels.swift NozirKit/Sources/NozirInsights/ExtraTimeService.swift NozirKit/Sources/NozirInsights/ExtraTimeApi.swift NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift NozirKit/Tests/NozirInsightsTests/ExtraTimeApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p17: a child's ask for more time, read and answered as the server writes it

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: Home carries the waiting asks — `ParentHome.pendingExtraTimeRequests` and `HomeModel.timeRequests`

**Files:**
- Modify: `NozirKit/Sources/NozirInsights/InsightModels.swift:83-109` (`ParentHome`)
- Modify: `NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift` (new tests before the suite's closing `}` at line 155)
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift` (after `sosAlert(emergencyNumber:)`, lines 138-141)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift:98-105` (`parentHome`) and append at the end
- Modify: `NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift` (new test before the suite's closing `}` at line 289)

**Interfaces:**
- Consumes: `ExtraTimeRequest`, `ExtraTimeKind`, `ExtraTimeStatus`, `isAnswerable` (Task 1); `extraTimeJSON(…)`, `requestId`, `bareHomeJSON`, `insightsApi(_:)` (NozirInsightsTests fixtures); `homeCard(…)`, `day(_:)` (`FakeInsights.swift`).
- Produces:
  - `ParentHome.pendingExtraTimeRequests: [ExtraTimeRequest]`; `ParentHome.init(date:children:familySummary:activeSos:pendingExtraTimeRequests: [ExtraTimeRequest] = [])`.
  - `HomeModel.timeRequests: [ExtraTimeRequest]` (answerable asks, narrowed by `filter`), `HomeModel.usedMinutesToday(of: ExtraTimeRequest) -> Int?`.
  - Test helpers (NozirAppFeatureTests): `parentHome(_:date:familySummary:sos:requests:)`, `askedAt: Date` (2026-10-07T14:05:00Z), `extraTimeAsk(id:childId:name:kind:requested:reason:status:granted:note:week:) -> ExtraTimeRequest`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift` — add inside `InsightsApiTests`, before its closing `}`:

```swift
    // P17: the waiting asks come with home.
    @Test func homeCarriesTheWaitingAsks() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #""pendingExtraTimeRequests":[]"#,
            with: #""pendingExtraTimeRequests":["# + extraTimeJSON() + "]"
        )
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.map(\.id) == [requestId])
        #expect(home.pendingExtraTimeRequests.first?.requestedMinutes == 30)
    }

    @Test func aHomeWithoutTheListHasNoAsks() async throws {
        let body = bareHomeJSON.replacingOccurrences(of: #""pendingExtraTimeRequests":[],"#, with: "")
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.isEmpty)
        #expect(home.children.count == 1)
    }

    // Review Focus 3: one unreadable ask must not blank the front door.
    @Test func aListThatCannotBeReadLeavesHomeStanding() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #""pendingExtraTimeRequests":[]"#,
            with: #""pendingExtraTimeRequests":[{"id":"not-a-uuid"}]"#
        )
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.pendingExtraTimeRequests.isEmpty)
        #expect(home.children.count == 1)
    }
```

`NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift` — replace `parentHome(…)` (lines 98-105) with:

```swift
func parentHome(
    _ children: [ChildHomeCard],
    date: LocalDate = day("2026-10-05"),
    familySummary: String? = nil,
    sos: ActiveSos? = nil,
    requests: [ExtraTimeRequest] = []
) -> ParentHome {
    ParentHome(date: date, children: children, familySummary: familySummary, activeSos: sos, pendingExtraTimeRequests: requests)
}
```

and append at the end of the file:

```swift
/// 2026-10-07T14:05:00Z.
let askedAt = Date(timeIntervalSince1970: 1_791_381_900)

/// A child's ask as the pending list carries it.
func extraTimeAsk(
    id: UUID = UUID(),
    childId: UUID = UUID(),
    name: String? = "Ali",
    kind: ExtraTimeKind = .extraMinutes,
    requested: Int = 30,
    reason: String = "Uy vazifasi tugadi",
    status: ExtraTimeStatus = .pending,
    granted: Int? = nil,
    note: String? = nil,
    week: Int? = 2
) -> ExtraTimeRequest {
    ExtraTimeRequest(
        id: id,
        childId: childId,
        childName: name,
        kind: kind,
        nightOf: kind == .bedtimeDelay ? day("2026-10-07") : nil,
        requestedMinutes: requested,
        reason: reason,
        status: status,
        grantedMinutes: granted,
        decisionNote: note,
        createdAt: askedAt,
        requestsInLastSevenDays: week
    )
}
```

`NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift` — add inside `HomeModelTests`, before its closing `}`:

```swift
    // P17 rows (D1, T9) and Review Focus 5: one row per answerable ask, for the
    // children the filter shows; an ask of an unknown kind has no row.
    @Test func timeRequestRowsFollowTheFilterAndSkipWhatCannotBeAnswered() async {
        let ali = homeCard("Ali", used: 95)
        let vali = homeCard("Vali", used: 40)
        let forAli = extraTimeAsk(childId: ali.id)
        let unknown = extraTimeAsk(childId: ali.id, kind: .unknown("SCHOOL_TRIP"))
        let forVali = extraTimeAsk(childId: vali.id, name: "Vali", kind: .bedtimeDelay)
        let (model, _, _) = setup([.success(parentHome([ali, vali], requests: [forAli, unknown, forVali]))])

        await model.appear()
        #expect(model.timeRequests == [forAli, forVali])
        #expect(model.usedMinutesToday(of: forAli) == 95)

        model.filter = vali.id
        #expect(model.timeRequests == [forVali])
        #expect(model.usedMinutesToday(of: forVali) == 40)
        #expect(model.usedMinutesToday(of: extraTimeAsk()) == nil)
    }

    @Test func noHomeNoRows() {
        let (model, _, _) = setup([])

        #expect(model.timeRequests.isEmpty)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run, one at a time: `bash .superpowers/run.sh NozirInsightsTests 170`, then `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: build errors — `value of type 'ParentHome' has no member 'pendingExtraTimeRequests'`, `extra argument 'pendingExtraTimeRequests' in call`, `value of type 'HomeModel' has no member 'timeRequests'`.

- [ ] **Step 3: `ParentHome`**

In `NozirKit/Sources/NozirInsights/InsightModels.swift`, replace `ParentHome` (lines 83-109) with:

```swift
/// `ParentHomeResponse`, the parts P05 draws in this slice. The legacy
/// `activeSosId` is not read (plan deviation E1).
public struct ParentHome: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let children: [ChildHomeCard]
    public let familySummary: String?
    public let activeSos: ActiveSos?
    /// P17 rows, newest first. A list that cannot be read is no list: Home
    /// still loads (plan deviation T6).
    public let pendingExtraTimeRequests: [ExtraTimeRequest]

    public init(
        date: LocalDate,
        children: [ChildHomeCard],
        familySummary: String? = nil,
        activeSos: ActiveSos? = nil,
        pendingExtraTimeRequests: [ExtraTimeRequest] = []
    ) {
        self.date = date
        self.children = children
        self.familySummary = familySummary
        self.activeSos = activeSos
        self.pendingExtraTimeRequests = pendingExtraTimeRequests
    }

    enum CodingKeys: String, CodingKey {
        case date, children, familySummary, activeSos, pendingExtraTimeRequests
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(LocalDate.self, forKey: .date)
        children = try container.decodeIfPresent([ChildHomeCard].self, forKey: .children) ?? []
        familySummary = try container.decodeIfPresent(String.self, forKey: .familySummary)
        activeSos = try container.decodeIfPresent(ActiveSos.self, forKey: .activeSos)
        pendingExtraTimeRequests = (try? container.decodeIfPresent([ExtraTimeRequest].self, forKey: .pendingExtraTimeRequests)) ?? []
    }
}
```

- [ ] **Step 4: `HomeModel`**

In `NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift`, after `sosAlert(emergencyNumber:)` (ends line 141) add:

```swift
    /// P17 rows: the asks the app can answer, in the server's order, for the
    /// child the filter shows (everyone when it names no child on screen).
    var timeRequests: [ExtraTimeRequest] {
        let waiting = (home?.pendingExtraTimeRequests ?? []).filter(\.isAnswerable)
        guard let filter, cards.contains(where: { $0.id == filter }) else { return waiting }
        return waiting.filter { $0.childId == filter }
    }

    /// Today's minutes from the child's own card, for P17's context line; nil
    /// when that child has no card.
    func usedMinutesToday(of request: ExtraTimeRequest) -> Int? {
        cards.first { $0.id == request.childId }?.usedMinutes
    }
```

- [ ] **Step 5: Run the tests to see them pass**

Run, one at a time: `bash .superpowers/run.sh NozirInsightsTests 170`, then `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **` both times.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirInsights/InsightModels.swift NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p17: home carries the asks waiting for an answer

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: The smaller amount and the words — `PartialMinutes`, `TimeRequestTexts`

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/TimeRequests/PartialMinutes.swift`
- Create: `NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestTexts.swift`
- Create: `NozirKit/Tests/NozirAppFeatureTests/TimeRequestTextsTests.swift`

**Interfaces:**
- Consumes: `ExtraTimeRequest`, `ExtraTimeKind`, `ExtraTimeStatus` (Task 1); `extraTimeAsk(…)` (Task 2); `LocationTexts.present(_:)` (`Location/LocationTexts.swift:126`), `DateTexts.timeOfDay(_:calendar:)` (`Insights/InsightTexts.swift:73`), `Durations.short(_:_:)` (`Durations.swift:8`); L10n keys `homeExtraTimeTitle`, `homeExtraTimeBody(_:_:)`, `homeExtraTimeBodyUnnamed(_:)`, `homeBedtimeDelayTitle`, `homeBedtimeDelayBody(_:_:)`, `homeBedtimeDelayBodyUnnamed(_:)`, `timeRequestHeader(_:_:)`, `timeRequestHeaderUnnamed(_:)`, `timeRequestHeaderDelay(_:_:)`, `timeRequestHeaderDelayUnnamed(_:)`, `timeRequestHeaderMeta(_:)`, `timeRequestReasonQuoted(_:)`, `timeRequestReasonEmpty`, `timeRequestContextUsed(_:)`, `timeRequestContextWeek(_:)`, `timeRequestContextWeekFirst`, `timeRequestActionApprove(_:)`, `timeRequestActionApproveDelay(_:)`, `timeRequestActionPartial(_:)`, `timeRequestActionPartialDelay(_:)`, `timeRequestNote(_:)`, `timeRequestNoteUnnamed`, `timeRequestDelayNote`, `timeRequestDoneApproved(_:)`, `timeRequestDoneDeclined`, `timeRequestDoneExpired` (all in `NozirL10n/L10n.generated.swift`, `String` / `Int` arguments as written).
- Produces:
  - `enum PartialMinutes { static func of(_ request: ExtraTimeRequest) -> Int? }`.
  - `enum TimeRequestTexts` with `static` functions: `rowTitle(_:_:) -> String`, `rowBody(_:_:) -> String`, `header(_:_:) -> String`, `headerMeta(_:_:calendar:) -> String`, `reason(_:_:) -> String`, `context(usedMinutesToday:requestsInLastSevenDays:_:) -> String?`, `approveTitle(_:_:) -> String`, `partialTitle(_:of:_:) -> String`, `note(_:_:) -> String`, `outcome(_:_:) -> String?`, `decisionNote(_:_:) -> String?` (each takes the `ExtraTimeRequest` first and the `L10n` last).

- [ ] **Step 1: Write the failing tests**

Create `NozirKit/Tests/NozirAppFeatureTests/TimeRequestTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

@Suite struct PartialMinutesTests {
    // Spec §4.2: half, down to a multiple of five; nothing below five or at the whole ask.
    @Test(arguments: [(5, nil), (9, nil), (10, 5), (15, 5), (19, 5), (20, 10), (30, 15), (45, 20), (60, 30), (0, nil)] as [(Int, Int?)])
    func extraMinutesOfferRoughlyHalfInFives(requested: Int, offer: Int?) {
        #expect(PartialMinutes.of(extraTimeAsk(requested: requested)) == offer)
    }

    // A bedtime moves in the steps it was asked in: 30 halves to 15, 15 has no half.
    @Test(arguments: [(30, 15), (20, 15), (15, nil), (10, nil)] as [(Int, Int?)])
    func aBedtimeDelayOffersAQuarterOfAnHour(requested: Int, offer: Int?) {
        #expect(PartialMinutes.of(extraTimeAsk(kind: .bedtimeDelay, requested: requested)) == offer)
    }

    @Test func anUnknownKindOffersNothing() {
        #expect(PartialMinutes.of(extraTimeAsk(kind: .unknown("SCHOOL_TRIP"), requested: 60)) == nil)
    }
}

@Suite struct TimeRequestTextsTests {
    private let l10n = L10n(.uz)

    @Test func theRowSaysWhoAskedAndForWhat() {
        let minutes = extraTimeAsk(requested: 30)
        let delay = extraTimeAsk(kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.rowTitle(minutes, l10n) == l10n.homeExtraTimeTitle)
        #expect(TimeRequestTexts.rowBody(minutes, l10n) == l10n.homeExtraTimeBody("Ali", 30))
        #expect(TimeRequestTexts.rowTitle(delay, l10n) == l10n.homeBedtimeDelayTitle)
        #expect(TimeRequestTexts.rowBody(delay, l10n) == l10n.homeBedtimeDelayBody("Ali", 30))
    }

    @Test(arguments: [nil, "", "  \n"] as [String?])
    func aMissingOrBlankNameReadsAsTheChild(name: String?) {
        let minutes = extraTimeAsk(name: name, requested: 30)
        let delay = extraTimeAsk(name: name, kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.rowBody(minutes, l10n) == l10n.homeExtraTimeBodyUnnamed(30))
        #expect(TimeRequestTexts.rowBody(delay, l10n) == l10n.homeBedtimeDelayBodyUnnamed(30))
        #expect(TimeRequestTexts.header(minutes, l10n) == l10n.timeRequestHeaderUnnamed(30))
        #expect(TimeRequestTexts.header(delay, l10n) == l10n.timeRequestHeaderDelayUnnamed(30))
        #expect(TimeRequestTexts.note(minutes, l10n) == l10n.timeRequestNoteUnnamed)
    }

    // A parent who reads "30 minutes" and taps yes must not have moved a bedtime.
    @Test func theHeaderAndTheButtonsNeverMixTheTwoAsks() {
        let minutes = extraTimeAsk(requested: 30)
        let delay = extraTimeAsk(kind: .bedtimeDelay, requested: 30)

        #expect(TimeRequestTexts.header(minutes, l10n) == l10n.timeRequestHeader("Ali", 30))
        #expect(TimeRequestTexts.header(delay, l10n) == l10n.timeRequestHeaderDelay("Ali", 30))
        #expect(TimeRequestTexts.approveTitle(minutes, l10n) == l10n.timeRequestActionApprove(30))
        #expect(TimeRequestTexts.approveTitle(delay, l10n) == l10n.timeRequestActionApproveDelay(30))
        #expect(TimeRequestTexts.partialTitle(15, of: minutes, l10n) == l10n.timeRequestActionPartial(15))
        #expect(TimeRequestTexts.partialTitle(15, of: delay, l10n) == l10n.timeRequestActionPartialDelay(15))
        #expect(TimeRequestTexts.note(minutes, l10n) == l10n.timeRequestNote("Ali"))
        #expect(TimeRequestTexts.note(delay, l10n) == l10n.timeRequestDelayNote)
    }

    @Test func theTimeIsThePhonesClock() {
        #expect(TimeRequestTexts.headerMeta(extraTimeAsk(), l10n, calendar: utc) == l10n.timeRequestHeaderMeta("14:05"))
    }

    @Test func theChildsWordsAreQuotedAsWritten() {
        #expect(TimeRequestTexts.reason(extraTimeAsk(reason: "  Uy vazifasi tugadi \n"), l10n) == l10n.timeRequestReasonQuoted("Uy vazifasi tugadi"))
        #expect(TimeRequestTexts.reason(extraTimeAsk(reason: " "), l10n) == l10n.timeRequestReasonEmpty)
    }

    @Test func theContextIsTwoPlainFacts() {
        let used = l10n.timeRequestContextUsed(Durations.short(95, l10n))

        #expect(TimeRequestTexts.context(usedMinutesToday: 95, requestsInLastSevenDays: 3, l10n) == used + " " + l10n.timeRequestContextWeek(3))
        #expect(TimeRequestTexts.context(usedMinutesToday: 95, requestsInLastSevenDays: nil, l10n) == used)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: 1, l10n) == l10n.timeRequestContextWeekFirst)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: 0, l10n) == l10n.timeRequestContextWeekFirst)
        #expect(TimeRequestTexts.context(usedMinutesToday: nil, requestsInLastSevenDays: nil, l10n) == nil)
    }

    @Test func theAnswerSaysWhatWasGiven() {
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .approved, granted: 15), l10n) == l10n.timeRequestDoneApproved(15))
        #expect(TimeRequestTexts.outcome(extraTimeAsk(requested: 30, status: .approved), l10n) == l10n.timeRequestDoneApproved(30))
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .declined), l10n) == l10n.timeRequestDoneDeclined)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .expired), l10n) == l10n.timeRequestDoneExpired)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .pending), l10n) == nil)
        #expect(TimeRequestTexts.outcome(extraTimeAsk(status: .unknown("WITHDRAWN")), l10n) == nil)
    }

    @Test func aRefusalShowsItsReasonBackAndABlankOneNotAtAll() {
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined, note: " Ertaga "), l10n) == l10n.timeRequestReasonQuoted("Ertaga"))
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined, note: "  "), l10n) == nil)
        #expect(TimeRequestTexts.decisionNote(extraTimeAsk(status: .declined), l10n) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: build errors — `cannot find 'PartialMinutes' in scope`, `cannot find 'TimeRequestTexts' in scope`.

- [ ] **Step 3: `PartialMinutes`**

Create `NozirKit/Sources/NozirAppFeature/TimeRequests/PartialMinutes.swift`:

```swift
import Foundation
import NozirInsights

/// Android `partialMinutesOf`: the smaller amount a parent can offer instead
/// of the whole ask, or nil when there is none worth a button.
///
/// Minutes: roughly half, rounded down to a figure a person would say ("15",
/// not "17"); nothing below five, and never the whole ask again. A bedtime
/// moves in the steps the child chose from (15 or 30): half an hour halves to
/// a quarter, a quarter has no half.
enum PartialMinutes {
    static func of(_ request: ExtraTimeRequest) -> Int? {
        switch request.kind {
        case .bedtimeDelay:
            return request.requestedMinutes > 15 ? 15 : nil
        case .extraMinutes:
            let rounded = request.requestedMinutes / 2 / 5 * 5
            guard rounded >= 5, rounded < request.requestedMinutes else { return nil }
            return rounded
        case .unknown:
            return nil
        }
    }
}
```

- [ ] **Step 4: `TimeRequestTexts`**

Create `NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestTexts.swift`:

```swift
import Foundation
import NozirInsights
import NozirL10n

/// P17 and its Home row in words (Android `ExtraTimeRequestRow`,
/// `TimeRequestHeaderCard`, `TimeRequestContextCard`, `TimeRequestActions`,
/// `TimeRequestNoteCard`, `TimeRequestAnsweredCard`). A blank name reads as
/// "the child"; a bedtime ask never borrows the minutes' sentence, so every
/// button says what a yes does.
enum TimeRequestTexts {
    private static func name(_ request: ExtraTimeRequest) -> String? {
        LocationTexts.present(request.childName)
    }

    private static func isDelay(_ request: ExtraTimeRequest) -> Bool {
        request.kind == .bedtimeDelay
    }

    static func rowTitle(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request) ? l10n.homeBedtimeDelayTitle : l10n.homeExtraTimeTitle
    }

    static func rowBody(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        let minutes = request.requestedMinutes
        if isDelay(request) {
            return name(request).map { l10n.homeBedtimeDelayBody($0, minutes) } ?? l10n.homeBedtimeDelayBodyUnnamed(minutes)
        }
        return name(request).map { l10n.homeExtraTimeBody($0, minutes) } ?? l10n.homeExtraTimeBodyUnnamed(minutes)
    }

    static func header(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        let minutes = request.requestedMinutes
        if isDelay(request) {
            return name(request).map { l10n.timeRequestHeaderDelay($0, minutes) } ?? l10n.timeRequestHeaderDelayUnnamed(minutes)
        }
        return name(request).map { l10n.timeRequestHeader($0, minutes) } ?? l10n.timeRequestHeaderUnnamed(minutes)
    }

    /// "14:05 · bugun" on the phone's clock.
    static func headerMeta(_ request: ExtraTimeRequest, _ l10n: L10n, calendar: Calendar = .current) -> String {
        l10n.timeRequestHeaderMeta(DateTexts.timeOfDay(request.createdAt, calendar: calendar))
    }

    /// The child's words, quoted and otherwise untouched.
    static func reason(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        LocationTexts.present(request.reason).map { l10n.timeRequestReasonQuoted($0) } ?? l10n.timeRequestReasonEmpty
    }

    /// Two plain facts and no verdict; nil when neither is known.
    static func context(usedMinutesToday: Int?, requestsInLastSevenDays: Int?, _ l10n: L10n) -> String? {
        var sentences: [String] = []
        if let used = usedMinutesToday {
            sentences.append(l10n.timeRequestContextUsed(Durations.short(used, l10n)))
        }
        if let week = requestsInLastSevenDays {
            sentences.append(week <= 1 ? l10n.timeRequestContextWeekFirst : l10n.timeRequestContextWeek(week))
        }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    static func approveTitle(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request)
            ? l10n.timeRequestActionApproveDelay(request.requestedMinutes)
            : l10n.timeRequestActionApprove(request.requestedMinutes)
    }

    static func partialTitle(_ minutes: Int, of request: ExtraTimeRequest, _ l10n: L10n) -> String {
        isDelay(request) ? l10n.timeRequestActionPartialDelay(minutes) : l10n.timeRequestActionPartial(minutes)
    }

    /// Why the reason field is worth using — and for a bedtime, that a yes is for tonight only.
    static func note(_ request: ExtraTimeRequest, _ l10n: L10n) -> String {
        if isDelay(request) { return l10n.timeRequestDelayNote }
        return name(request).map { l10n.timeRequestNote($0) } ?? l10n.timeRequestNoteUnnamed
    }

    /// The answer once there is one; nil while waiting or for a status this app does not know.
    static func outcome(_ request: ExtraTimeRequest, _ l10n: L10n) -> String? {
        switch request.status {
        case .approved:
            return l10n.timeRequestDoneApproved(request.grantedMinutes ?? request.requestedMinutes)
        case .declined:
            return l10n.timeRequestDoneDeclined
        case .expired:
            return l10n.timeRequestDoneExpired
        case .pending, .unknown:
            return nil
        }
    }

    /// A refusal's reason shown back to the parent, as the child reads it.
    static func decisionNote(_ request: ExtraTimeRequest, _ l10n: L10n) -> String? {
        LocationTexts.present(request.decisionNote).map { l10n.timeRequestReasonQuoted($0) }
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/TimeRequests/PartialMinutes.swift NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestTexts.swift NozirKit/Tests/NozirAppFeatureTests/TimeRequestTextsTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p17: the smaller amount a parent can offer, and every sentence the screen says

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: `TimeRequestModel` — find the ask, answer it once

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/FakeExtraTime.swift`
- Create: `NozirKit/Tests/NozirAppFeatureTests/TimeRequestModelTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestModel.swift`

**Interfaces:**
- Consumes: `ExtraTimeService`, `ExtraTimeRequest`, `ExtraTimeOutcome`, `isAnswerable` (Task 1); `ApiErrorCode.alreadyDecided` (Task 1); `PartialMinutes.of(_:)` (Task 3); `extraTimeAsk(…)` (Task 2); `UserMessage` (`UserMessage.swift`), `ApiFailure.code`, `ApiFailure.isNotFound`; test support `PauseGate` (`FakeLocation.swift:114`), `offline` (`FakeFamily.swift:5`), `notFound` (`FakeInsights.swift:5`).
- Produces:
  - `@MainActor @Observable final class TimeRequestModel` with `init(requestId: UUID, usedMinutesToday: Int?, service: any ExtraTimeService)`; `enum Phase: Equatable { case loading, ready, missing, failed(UserMessage) }`; `static let noteLimit = 280`; `let requestId: UUID`; `let usedMinutesToday: Int?`; `private(set) var request: ExtraTimeRequest?`, `phase: Phase`, `isOffline: Bool`, `deciding: ExtraTimeOutcome?`, `isWritingDecline: Bool`, `declineNote: String`; `var toast: UserMessage?`; computed `isDeciding: Bool`, `canDecide: Bool`, `partialMinutes: Int?`; `func load() async`, `func approve() async`, `func approvePartial() async`, `func startDecline()`, `func cancelDecline()`, `func updateDeclineNote(_ text: String)`, `func confirmDecline() async`.
  - Test fake `actor FakeExtraTime: ExtraTimeService` with `Script { pending, decide, pendingGate, decideGate }`, `calls: [String]` (`"pending"`, `"decide"`), `decisions: [FakeExtraTime.Decision]`, `add(_:)`.

- [ ] **Step 1: The fake**

Create `NozirKit/Tests/NozirAppFeatureTests/FakeExtraTime.swift`:

```swift
import Foundation
import NozirInsights
import NozirNetworking

/// Answers the pending list and each decision from its own queue, in order (an
/// empty queue is a phone with no connection), and records what was asked.
actor FakeExtraTime: ExtraTimeService {
    struct Decision: Equatable, Sendable {
        let id: UUID
        let outcome: ExtraTimeOutcome
        let grantedMinutes: Int?
        let note: String?
    }

    struct Script: Sendable {
        var pending: [Result<[ExtraTimeRequest], ApiFailure>] = []
        var decide: [Result<ExtraTimeRequest, ApiFailure>] = []
        /// Held once by the next `pending` / `decide` call, after its answer is taken.
        var pendingGate: PauseGate?
        var decideGate: PauseGate?
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var decisions: [Decision] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func pending() async throws -> [ExtraTimeRequest] {
        calls.append("pending")
        let answer: Result<[ExtraTimeRequest], ApiFailure> = script.pending.isEmpty ? .failure(offline) : script.pending.removeFirst()
        let gate = script.pendingGate
        script.pendingGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest {
        calls.append("decide")
        decisions.append(Decision(id: id, outcome: outcome, grantedMinutes: grantedMinutes, note: note))
        let answer: Result<ExtraTimeRequest, ApiFailure> = script.decide.isEmpty ? .failure(offline) : script.decide.removeFirst()
        let gate = script.decideGate
        script.decideGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}
```

- [ ] **Step 2: Write the failing tests**

Create `NozirKit/Tests/NozirAppFeatureTests/TimeRequestModelTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let askId = UUID()
private let childId = UUID()
private let answeredElsewhere = ApiFailure.server(status: 409, error: ApiError(code: .alreadyDecided))

private func ask(
    kind: ExtraTimeKind = .extraMinutes,
    requested: Int = 30,
    status: ExtraTimeStatus = .pending,
    granted: Int? = nil,
    note: String? = nil
) -> ExtraTimeRequest {
    extraTimeAsk(id: askId, childId: childId, kind: kind, requested: requested, status: status, granted: granted, note: note)
}

@MainActor
private func setup(_ script: FakeExtraTime.Script, used: Int? = 95) -> (TimeRequestModel, FakeExtraTime) {
    let fake = FakeExtraTime(script)
    return (TimeRequestModel(requestId: askId, usedMinutesToday: used, service: fake), fake)
}

@MainActor
@Suite struct TimeRequestModelTests {
    @Test func theAskIsFoundInThePendingList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk(), ask()])]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.request == ask())
        #expect(model.canDecide)
        #expect(model.partialMinutes == 15)
        #expect(model.usedMinutesToday == 95)
        #expect(await fake.calls == ["pending"])
    }

    @Test func anAskNoLongerWaitingIsMissingNotAnError() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk()])]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(model.request == nil)
        #expect(!model.canDecide)
    }

    // Review Focus 5 (T3): an ask the app cannot put into words gets no buttons.
    @Test func anAskOfAnUnknownKindIsMissing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .unknown("SCHOOL_TRIP"))])]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(!model.canDecide)
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeExtraTime.Script()
        script.pending = [.failure(.unexpectedStatus(500)), .success([ask()])]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    // Spec §6: offline with the ask on screen keeps it, and its buttons.
    @Test func goingOfflineKeepsTheAskOnScreen() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .failure(offline), .success([ask()])]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.request == ask())
        #expect(model.isOffline)
        #expect(model.canDecide)

        await model.load()
        #expect(!model.isOffline)
    }

    // T5: a server fault over a shown ask is not "offline".
    @Test func aServerFaultOverAShownAskIsSaidNotCalledOffline() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(!model.isOffline)
        #expect(model.toast == .serverProblem)
        #expect(model.request == ask())
    }

    @Test func approvingSendsTheWholeAskAndShowsTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .approve, grantedMinutes: nil, note: nil)])
        #expect(model.request?.status == .approved)
        #expect(model.phase == .ready)
        #expect(!model.canDecide)
        #expect(!model.isDeciding)
    }

    @Test(arguments: [(ExtraTimeKind.extraMinutes, 30, 15), (.extraMinutes, 45, 20), (.bedtimeDelay, 30, 15)])
    func thePartialAnswerSendsTheComputedMinutes(kind: ExtraTimeKind, requested: Int, partial: Int) async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: kind, requested: requested)])]
        script.decide = [.success(ask(kind: kind, requested: requested, status: .approved, granted: partial))]
        let (model, fake) = setup(script)
        await model.load()
        #expect(model.partialMinutes == partial)

        await model.approvePartial()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .partial, grantedMinutes: partial, note: nil)])
        #expect(model.request?.grantedMinutes == partial)
    }

    @Test func withoutASmallerAmountThePartialAnswerSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .bedtimeDelay, requested: 15)])]
        let (model, fake) = setup(script)
        await model.load()

        await model.approvePartial()

        #expect(model.partialMinutes == nil)
        #expect(await fake.calls == ["pending"])
    }

    @Test func decliningSendsTheTrimmedNote() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .declined, note: "Ertaga gaplashamiz"))]
        let (model, fake) = setup(script)
        await model.load()

        model.startDecline()
        #expect(model.isWritingDecline)
        model.updateDeclineNote("  Ertaga gaplashamiz \n")
        await model.confirmDecline()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .decline, grantedMinutes: nil, note: "Ertaga gaplashamiz")])
        #expect(!model.isWritingDecline)
        #expect(model.request?.status == .declined)
    }

    // Review Focus 4.
    @Test func aBlankNoteIsNoNoteAndALongOneIsCut() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .declined))]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()

        model.updateDeclineNote(String(repeating: "a", count: 300))
        #expect(model.declineNote.count == TimeRequestModel.noteLimit)

        model.updateDeclineNote(" \n ")
        await model.confirmDecline()

        #expect(await fake.decisions == [FakeExtraTime.Decision(id: askId, outcome: .decline, grantedMinutes: nil, note: nil)])
    }

    @Test func goingBackFromTheNoteKeepsWhatWasWrittenAndSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()
        model.updateDeclineNote("Ertaga")

        model.cancelDecline()

        #expect(!model.isWritingDecline)
        #expect(model.declineNote == "Ertaga")
        #expect(await fake.calls == ["pending"])
    }

    @Test func confirmingWithoutTheNoteOpenSendsNothing() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()

        await model.confirmDecline()

        #expect(await fake.calls == ["pending"])
    }

    // Spec §6: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSendOneDecision() async {
        let gate = PauseGate()
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        script.decideGate = gate
        let (model, fake) = setup(script)
        await model.load()

        let first = Task { await model.approve() }
        await gate.untilPaused()
        #expect(model.isDeciding)
        #expect(model.deciding == .approve)
        await model.approve()
        await model.approvePartial()
        model.startDecline()
        #expect(!model.isWritingDecline)

        await gate.release()
        await first.value
        #expect(await fake.decisions.count == 1)
        #expect(model.request?.status == .approved)
        #expect(!model.isDeciding)
    }

    // D6: answered by the other parent, or expired.
    @Test func anAskAnsweredElsewhereSendsTheScreenBackToTheList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.failure(answeredElsewhere)]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(model.phase == .missing)
        #expect(model.request == nil)
        #expect(model.toast == nil)
        #expect(await fake.calls == ["pending", "decide", "pending"])
    }

    @Test func anAskThatIsGoneSendsTheScreenBackToTheList() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.failure(notFound)]
        let (model, _) = setup(script)
        await model.load()
        model.startDecline()

        await model.confirmDecline()

        #expect(model.phase == .missing)
        #expect(!model.isWritingDecline)
        #expect(model.toast == nil)
    }

    // Review Focus 2: the night is over (409 CONFLICT) — said once, the ask,
    // the open note and the buttons stay, and a second try goes out.
    @Test func aFailedDecisionIsSaidOnceAndCanBeTriedAgain() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask(kind: .bedtimeDelay)])]
        script.decide = [
            .failure(.server(status: 409, error: ApiError(code: .conflict))),
            .success(ask(kind: .bedtimeDelay, status: .declined)),
        ]
        let (model, fake) = setup(script)
        await model.load()
        model.startDecline()
        model.updateDeclineNote("Ertaga")

        await model.confirmDecline()
        #expect(model.toast == .conflict)
        #expect(model.isWritingDecline)
        #expect(model.declineNote == "Ertaga")
        #expect(model.request?.status == .pending)
        #expect(model.canDecide)

        await model.confirmDecline()
        #expect(model.request?.status == .declined)
        #expect(await fake.decisions.count == 2)
    }

    // Review Focus 2 / global constraint: no connection is said, not retried.
    @Test func aDecisionWithNoConnectionIsNotRetried() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        let (model, fake) = setup(script)
        await model.load()

        await model.approve()

        #expect(model.toast == .noConnection)
        #expect(await fake.decisions.count == 1)
        #expect(model.canDecide)
    }

    // Review Focus 1 (T4): the answer stays; the list no longer has it.
    @Test func aRefreshAfterTheAnswerKeepsTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()]), .success([])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()
        await model.approve()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.request?.status == .approved)
        #expect(await fake.calls == ["pending", "decide"])
    }

    // Spec §6: an older answer never overwrites a newer state.
    @Test(.timeLimit(.minutes(5)))
    func aLateRefreshDoesNotUndoTheAnswer() async {
        var script = FakeExtraTime.Script()
        script.pending = [.success([ask()])]
        script.decide = [.success(ask(status: .approved, granted: 30))]
        let (model, fake) = setup(script)
        await model.load()
        let gate = PauseGate()
        await fake.add {
            $0.pending = [.success([ask()])]
            $0.pendingGate = gate
        }

        let late = Task { await model.load() }
        await gate.untilPaused()
        await model.approve()
        await gate.release()
        await late.value

        #expect(model.request?.status == .approved)
        #expect(!model.canDecide)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var script = FakeExtraTime.Script()
        script.pending = [.success([]), .success([ask()])]
        script.pendingGate = gate
        let (model, _) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.phase == .ready)
        #expect(model.request == ask())
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: build error — `cannot find 'TimeRequestModel' in scope`.

- [ ] **Step 4: `TimeRequestModel`**

Create `NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestModel.swift`:

```swift
import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P17 (Android `TimeRequestViewModel`): one child's ask, found in the pending
/// list (there is no call for one ask), and the parent's one answer. A second
/// tap while the first is in flight does nothing, and nothing is retried. An
/// ask answered elsewhere (409 `ALREADY_DECIDED`) or gone (404) sends the
/// screen back to the list, which then usually says nothing is waiting.
@MainActor
@Observable
final class TimeRequestModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// Not waiting any more (answered by the other parent, expired) or of
        /// a kind this app cannot describe. An answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    /// The most of a decline note that is kept.
    static let noteLimit = 280

    let requestId: UUID
    /// From the child's Home card; nil leaves the "already used" sentence out.
    let usedMinutesToday: Int?
    private(set) var request: ExtraTimeRequest?
    private(set) var phase: Phase = .loading
    /// An ask is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    /// The answer in flight, for the spinner on the button that sent it.
    private(set) var deciding: ExtraTimeOutcome?
    /// A state rather than a sheet: a mis-tap must not turn a refusal into a bare no.
    private(set) var isWritingDecline = false
    private(set) var declineNote = ""
    /// A failure said once; the view sets it back to nil.
    var toast: UserMessage?

    private let service: any ExtraTimeService
    /// Bumped by every load and every answer: an older answer never overwrites a newer state.
    @ObservationIgnored private var generation = 0

    init(requestId: UUID, usedMinutesToday: Int?, service: any ExtraTimeService) {
        self.requestId = requestId
        self.usedMinutesToday = usedMinutesToday
        self.service = service
    }

    var isDeciding: Bool {
        deciding != nil
    }

    /// Waiting, of a kind the app can describe, and no answer in flight.
    var canDecide: Bool {
        guard let request else { return false }
        return request.isAnswerable && deciding == nil
    }

    /// The smaller amount, when there is one worth a button.
    var partialMinutes: Int? {
        request.flatMap { PartialMinutes.of($0) }
    }

    func load() async {
        // An answer on screen is final: the pending list no longer has it, and
        // "nothing waiting" must not replace "15 minutes given" (plan deviation T4).
        if let request, request.status != .pending { return }
        generation += 1
        let mine = generation
        do {
            let waiting = try await service.pending()
            guard mine == generation else { return }
            if let found = waiting.first(where: { $0.id == requestId && $0.isAnswerable }) {
                request = found
                phase = .ready
            } else {
                request = nil
                phase = .missing
                isWritingDecline = false
            }
            isOffline = false
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if request == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                toast = message
            }
        }
    }

    func approve() async {
        await decide(.approve, grantedMinutes: nil, note: nil)
    }

    func approvePartial() async {
        guard let minutes = partialMinutes else { return }
        await decide(.partial, grantedMinutes: minutes, note: nil)
    }

    func startDecline() {
        guard canDecide else { return }
        isWritingDecline = true
    }

    /// Back to the three answers; what was written stays for a second try.
    func cancelDecline() {
        guard !isDeciding else { return }
        isWritingDecline = false
    }

    func updateDeclineNote(_ text: String) {
        declineNote = String(text.prefix(Self.noteLimit))
    }

    /// A blank note is no note: the child reads a plain "no", not quotes around nothing.
    func confirmDecline() async {
        guard isWritingDecline else { return }
        let note = declineNote.trimmingCharacters(in: .whitespacesAndNewlines)
        await decide(.decline, grantedMinutes: nil, note: note.isEmpty ? nil : note)
    }

    private func decide(_ outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async {
        guard canDecide, let request else { return }
        deciding = outcome
        defer { deciding = nil }
        do {
            let answered = try await service.decide(request.id, outcome: outcome, grantedMinutes: grantedMinutes, note: note)
            generation += 1
            self.request = answered
            phase = .ready
            isWritingDecline = false
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.code == ApiErrorCode.alreadyDecided || failure.isNotFound {
            // Answered by the other parent, or expired: ask again what is waiting.
            await load()
        } catch {
            toast = UserMessage(error)
        }
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/FakeExtraTime.swift NozirKit/Tests/NozirAppFeatureTests/TimeRequestModelTests.swift NozirKit/Sources/NozirAppFeature/TimeRequests/TimeRequestModel.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p17: one ask, one answer — found in the pending list, sent once

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: P17 screen, the Home rows, and the wiring (with accessibility)

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift:29` (stored service), `:41-67` (`init`), after `makeSosDetailModel` (`:171-173`) (factory)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:81` (`makeSignedInModel`)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift:18-43` (`setup`) and a new test before the suite's closing `}` (line 292)
- Create: `NozirKit/Sources/NozirAppFeature/Screens/TimeRequestRow.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/TimeRequestView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift:9-32` (properties and `init`), `:116` (one child), `:170` (family)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift:10-19` (`HomeStep`), `:59-66` (`HomeView(…)`), `:186-187` (`homeDestination`)

**Interfaces:**
- Consumes: `ExtraTimeService`, `ExtraTimeApi(client:)`, `ExtraTimeRequest` (Task 1); `HomeModel.timeRequests`, `HomeModel.usedMinutesToday(of:)` (Task 2); `TimeRequestTexts.*` (Task 3); `TimeRequestModel` and its members (Task 4); `FakeExtraTime`, `extraTimeAsk(…)` (tests); design system `NozirCard`, `NozirButton(_:variant:size:isLoading:action:)` (`.primary`, `.secondary`, `.ghost`; `.callToAction`), `NozirTextField(_:text:placeholder:)`, `NozirAvatar(name:tone:fallbackInitial:size:)`, `AvatarTone.forKey(_:position:)`, `NozirEmptyState(title:message:)`, `NozirErrorState(title:message:retryTitle:onRetry:)`, `NozirOfflineNotice(_:)`, `.nozirToast(_:)`, `.nozirText(_:color:)`, `NozirColor.{background,card,primaryContainer,primaryAccent,goodContent,textPrimary,textSecondary}`, `NozirSpacing.{extraSmall,small,compact,medium}`, `NozirSize.icon`, `NozirRadius.cardCompact`; L10n `screenTimeRequestTitle`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`, `timeRequestEmptyTitle`, `timeRequestEmptyBody`, `timeRequestReasonLabel`, `timeRequestActionDecline`, `timeRequestDeclineLabel`, `timeRequestDeclinePlaceholder`, `timeRequestDeclineHint`, `timeRequestDeclineBack`, `timeRequestDeclineConfirm`, `glyphChat`, `glyphInfo`, `glyphChevron`, `previewAvatarInitial`.
- Produces:
  - `SignedInModel.init(family:insights:extraTime:location:language:appearance:localeSync:emergencyNumber:privacy:privacyConfig:signOutLocally:signOut:)`; `SignedInModel.makeTimeRequestModel(id: UUID, usedMinutesToday: Int?) -> TimeRequestModel`.
  - `SignedInView.HomeStep.timeRequest(UUID, usedMinutesToday: Int?)`.
  - `HomeView.init(model:reloadToken:emergencyNumber:onOpenSummary:onOpenSos:onOpenTimeRequest:onAddChild:)` with `onOpenTimeRequest: (UUID, Int?) -> Void`.
  - `TimeRequestRow(request:action:)`, `TimeRequestView(model:)`.

- [ ] **Step 1: Write the failing test**

In `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`, add `import NozirInsights` after `import NozirFamily` (line 4), and replace `setup(…)` (lines 18-43) with:

```swift
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales(),
    extraTime: FakeExtraTime = FakeExtraTime(),
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

and add inside `SignedInModelTests`, before its closing `}`:

```swift
    // P17 (T1): the screen is for the ask tapped, with that child's minutes from Home.
    @Test func theTimeRequestScreenIsForTheAskTapped() async {
        let id = UUID()
        var script = FakeExtraTime.Script()
        script.pending = [.success([extraTimeAsk(id: id)])]
        let (model, _) = setup(FakeFamily.Script(), extraTime: FakeExtraTime(script))

        let screen = model.makeTimeRequestModel(id: id, usedMinutesToday: 95)
        await screen.load()

        #expect(screen.requestId == id)
        #expect(screen.usedMinutesToday == 95)
        #expect(screen.phase == .ready)
    }
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: build errors — `extra argument 'extraTime' in call`, `value of type 'SignedInModel' has no member 'makeTimeRequestModel'`.

- [ ] **Step 3: `SignedInModel`**

In `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:

After `private let insights: any InsightsService` (line 29) add:

```swift
    private let extraTime: any ExtraTimeService
```

Replace the `init(…)` signature and its first two assignments (lines 41-55, from `init(` through `self.insights = insights`) with:

```swift
    init(
        family: FamilyStore,
        insights: any InsightsService,
        extraTime: any ExtraTimeService,
        location: any LocationService,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        emergencyNumber: @escaping @MainActor () -> String?,
        privacy: any PrivacyService,
        privacyConfig: @escaping @MainActor () -> PrivacyConfig,
        signOutLocally: @escaping @MainActor () -> Void,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.insights = insights
        self.extraTime = extraTime
```

(the rest of the body, from `locationService = location` on, is unchanged).

After `makeSosDetailModel(seed:emergencyNumber:)` (lines 171-173) add:

```swift
    /// P17 for one ask; today's minutes come from the Home card that opened it
    /// (plan deviation T1).
    func makeTimeRequestModel(id: UUID, usedMinutesToday: Int?) -> TimeRequestModel {
        TimeRequestModel(requestId: id, usedMinutesToday: usedMinutesToday, service: extraTime)
    }
```

- [ ] **Step 4: `AppEnvironment`**

In `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`, in `makeSignedInModel()`, after `insights: InsightsApi(client: authorised),` (line 81) add:

```swift
            extraTime: ExtraTimeApi(client: authorised),
```

- [ ] **Step 5: Run the test to see it pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: `TimeRequestRow`**

Create `NozirKit/Sources/NozirAppFeature/Screens/TimeRequestRow.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// One waiting ask on Home (Android `ExtraTimeRequestRow`). The accent is in
/// the tile and the sub-line, not a status colour: something to answer, not
/// something to worry about (plan deviation T2).
struct TimeRequestRow: View {
    let request: ExtraTimeRequest
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard {
                HStack(spacing: NozirSpacing.compact) {
                    Text(l10n.glyphChat)
                        .font(.system(size: 18))
                        .frame(width: 40, height: 40)
                        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.primaryContainer))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeRequestTexts.rowTitle(request, l10n)).nozirText(.body)
                        Text(TimeRequestTexts.rowBody(request, l10n))
                            .nozirText(.bodySmall, color: NozirColor.primaryAccent)
                    }
                    Spacer(minLength: 0)
                    Text(l10n.glyphChevron)
                        .nozirText(.titleSmall, color: NozirColor.primaryAccent)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 7: `TimeRequestView`**

Create `NozirKit/Sources/NozirAppFeature/Screens/TimeRequestView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P17 as Android `TimeRequestContent`: who asked and when, their words, two
/// plain facts, then the answer — the buttons, the reason field a refusal
/// opens, or the answer once given (including one the other parent gave).
struct TimeRequestView: View {
    @State private var model: TimeRequestModel
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: TimeRequestModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenTimeRequestTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // Back from another app: the other parent may have answered meanwhile.
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
        case .missing:
            NozirEmptyState(title: l10n.timeRequestEmptyTitle, message: l10n.timeRequestEmptyBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if let request = model.request {
                header(request)
                reasonCard(request)
                if let context = TimeRequestTexts.context(
                    usedMinutesToday: model.usedMinutesToday,
                    requestsInLastSevenDays: request.requestsInLastSevenDays,
                    l10n
                ) {
                    NozirCard {
                        Text(context).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                decision(request)
            }
        }
    }

    /// Who, how much and when.
    private func header(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            HStack(spacing: NozirSpacing.compact) {
                NozirAvatar(
                    name: request.childName ?? "",
                    tone: .forKey(nil, position: 0),
                    fallbackInitial: l10n.previewAvatarInitial,
                    size: 44
                )
                VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                    Text(TimeRequestTexts.header(request, l10n)).nozirText(.titleSmall)
                    Text(TimeRequestTexts.headerMeta(request, l10n))
                        .nozirText(.bodySmall, color: NozirColor.primaryAccent)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
    }

    /// The child's own words, quoted and otherwise untouched.
    private func reasonCard(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            Text(l10n.timeRequestReasonLabel)
                .nozirText(.label, color: NozirColor.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Text(TimeRequestTexts.reason(request, l10n)).nozirText(.body)
        }
    }

    @ViewBuilder
    private func decision(_ request: ExtraTimeRequest) -> some View {
        if request.status != .pending {
            answeredCard(request)
        } else if model.isWritingDecline {
            declineCard
        } else {
            actions(request)
            noteCard(request)
        }
    }

    /// Yes, a smaller amount, or no — one above the other, so large text never cuts a label.
    private func actions(_ request: ExtraTimeRequest) -> some View {
        VStack(spacing: NozirSpacing.small) {
            NozirButton(
                TimeRequestTexts.approveTitle(request, l10n),
                size: .callToAction,
                isLoading: model.deciding == .approve
            ) {
                Task { await model.approve() }
            }
            if let partial = model.partialMinutes {
                NozirButton(
                    TimeRequestTexts.partialTitle(partial, of: request, l10n),
                    variant: .secondary,
                    isLoading: model.deciding == .partial
                ) {
                    Task { await model.approvePartial() }
                }
            }
            NozirButton(l10n.timeRequestActionDecline, variant: .ghost) { model.startDecline() }
        }
        .disabled(model.isDeciding)
    }

    /// Said once, before it is needed; for a bedtime, that a yes is for tonight only.
    private func noteCard(_ request: ExtraTimeRequest) -> some View {
        NozirCard {
            HStack(alignment: .top, spacing: NozirSpacing.small) {
                Text(l10n.glyphInfo)
                    .nozirText(.label, color: NozirColor.card)
                    .frame(width: NozirSize.icon, height: NozirSize.icon)
                    .background(Circle().fill(NozirColor.primaryAccent))
                    .accessibilityHidden(true)
                Text(TimeRequestTexts.note(request, l10n)).nozirText(.bodySmall)
            }
        }
    }

    private var declineCard: some View {
        NozirCard {
            NozirTextField(
                l10n.timeRequestDeclineLabel,
                text: Binding(get: { model.declineNote }, set: { model.updateDeclineNote($0) }),
                placeholder: l10n.timeRequestDeclinePlaceholder
            )
            Text(l10n.timeRequestDeclineHint).nozirText(.bodySmall, color: NozirColor.textSecondary)
            // Side by side when both fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NozirSpacing.small) { declineButtons }
                VStack(spacing: NozirSpacing.small) { declineButtons }
            }
        }
    }

    @ViewBuilder
    private var declineButtons: some View {
        NozirButton(l10n.timeRequestDeclineBack, variant: .secondary) { model.cancelDecline() }
            .disabled(model.isDeciding)
        NozirButton(l10n.timeRequestDeclineConfirm, isLoading: model.deciding == .decline) {
            Task { await model.confirmDecline() }
        }
    }

    /// The answer, and a refusal's reason shown back as the child reads it.
    @ViewBuilder
    private func answeredCard(_ request: ExtraTimeRequest) -> some View {
        if let outcome = TimeRequestTexts.outcome(request, l10n) {
            NozirCard {
                Text(outcome)
                    .nozirText(.titleSmall, color: request.status == .approved ? NozirColor.goodContent : NozirColor.textPrimary)
                if let note = TimeRequestTexts.decisionNote(request, l10n) {
                    Text(note).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
```

- [ ] **Step 8: The Home rows**

In `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`:

Replace the stored closures and `init(…)` (lines 11-32, from `private let emergencyNumber` through the end of `init`) with:

```swift
    private let emergencyNumber: () -> String?
    private let onOpenSummary: (UUID, String) -> Void
    private let onOpenSos: (ActiveSos) -> Void
    private let onOpenTimeRequest: (UUID, Int?) -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(
        model: HomeModel,
        reloadToken: Int,
        emergencyNumber: @escaping () -> String?,
        onOpenSummary: @escaping (UUID, String) -> Void,
        onOpenSos: @escaping (ActiveSos) -> Void,
        onOpenTimeRequest: @escaping (UUID, Int?) -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.reloadToken = reloadToken
        self.emergencyNumber = emergencyNumber
        self.onOpenSummary = onOpenSummary
        self.onOpenSos = onOpenSos
        self.onOpenTimeRequest = onOpenTimeRequest
        self.onAddChild = onAddChild
    }
```

In `singleChild(_:_:)`, immediately before the stat tiles' `HStack(alignment: .top, spacing: NozirSpacing.small) {` (line 116) add:

```swift
        timeRequestRows
```

In `family(_:)`, immediately after the `NozirChildSwitcher(…)` call (ends line 170) and before `ForEach(model.visible) { card in` add:

```swift
        timeRequestRows
```

After `family(_:)` (before `@ViewBuilder private func childCard`) add:

```swift
    /// P17 rows, one per waiting ask, above the stat cards (plan deviation T10).
    @ViewBuilder
    private var timeRequestRows: some View {
        ForEach(model.timeRequests) { request in
            TimeRequestRow(request: request) {
                onOpenTimeRequest(request.id, model.usedMinutesToday(of: request))
            }
        }
    }
```

- [ ] **Step 9: The navigation**

In `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

In `enum HomeStep`, after `case ruleScreen(RuleScreen)` (line 18) add:

```swift
        /// P17 from a Home row, with that child's minutes today (plan deviation T1).
        case timeRequest(UUID, usedMinutesToday: Int?)
```

Replace the `HomeView(…)` call (lines 59-66) with:

```swift
                HomeView(
                    model: model.makeHomeModel(),
                    reloadToken: model.homeRefresh,
                    emergencyNumber: { model.currentEmergencyNumber },
                    onOpenSummary: { homePath.append(.summary($0, $1)) },
                    onOpenSos: { homePath.append(.sos($0)) },
                    onOpenTimeRequest: { homePath.append(.timeRequest($0, usedMinutesToday: $1)) },
                    onAddChild: { model.presentAddChild() }
                )
```

In `homeDestination(_:)`, after the `case .ruleScreen(let screen):` branch (`ruleDestination(screen) { homePath.append(.ruleScreen($0)) }`, lines 186-187) add:

```swift
        case .timeRequest(let id, let usedMinutesToday):
            TimeRequestView(model: model.makeTimeRequestModel(id: id, usedMinutesToday: usedMinutesToday))
```

- [ ] **Step 10: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 11: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift NozirKit/Sources/NozirAppFeature/Screens/TimeRequestRow.swift NozirKit/Sources/NozirAppFeature/Screens/TimeRequestView.swift NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p17: a child's ask on Home, and the screen that answers it

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 6: Final check — whole suite, l10n, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, l10n up to date (no new key), `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `git diff --stat 04c5d4c -- NozirKit/l10n NozirKit/Sources/NozirL10n NozirKit/Package.swift` is empty.

- [ ] **Step 2: E2E (the user; simulator + the real backend + the Android child app able to send requests, and the Android parent app on the same family)**

Write "yes" or what was seen against each line:

1. One child asks +30 min on the child phone → iOS Home (pull to refresh) shows a "Vaqt soʻrovi" row ("Ali +30 daqiqa soʻradi", 💬 tile, ›) after the summary card and above the two stat tiles.
2. Two children, each with an ask → both rows on the family Home, above the child cards; tapping one child's avatar leaves only that child's row; "Hammasi" brings both back.
3. Tap the row → P17 titled "Vaqt soʻroviga javob": avatar, "Ali +30 daqiqa soʻradi", "HH:mm · bugun" (the phone's clock), "Sababi" with the child's words in «», "Bugun allaqachon … ishlatgan. Bu hafta … marta…" (or "birinchi marta").
4. "✓ 30 daqiqa berish" → spinner on that button, then "30 daqiqa berildi"; the child phone shows +30 bonus; back on Home the row is gone.
5. Ask 30 → "15 daqiqa berish" sends 15 ("15 daqiqa berildi"); ask 5 → no smaller-amount button.
6. "✕ Rad etish" → reason card; "Orqaga qaytish" returns with the text kept; "Rad etishni yuborish" with "  Ertaga  " → "Soʻrov rad etildi" and «Ertaga»; the child phone shows the same reason. With an empty field → no quotes on either side.
7. Bedtime ask (30) → "Uyqu vaqti soʻrovi" row; P17 says "…uyquni 30 daqiqa kechiktirishni soʻradi", buttons "✓ 30 daqiqa kechiktirish" / "15 daqiqa kechiktirish", note "Faqat bugungi tun uchun…"; a 15-minute ask shows no smaller button. Approve → tonight's bedtime moves on the child phone.
8. Answer an ask on the Android parent app, then tap "✓" on the iOS P17 still showing it → "Kutilayotgan soʻrov yoʻq", no error text, no "qoidalar oʻzgargan".
9. Airplane mode with P17 showing an ask: pull to refresh → offline notice, ask and buttons stay; tap "✓" → toast "Internet aloqasi yoʻq…", backend log shows no decision, buttons work again once online.
10. Double-tap "✓" quickly → one decision in the backend log.
11. After answering, pull to refresh / leave the app and come back → the answer card stays.
12. A bedtime ask answered with "✓" after that night has ended (or its 30 minutes are spent) → record the toast text seen (open question Q1).
13. VoiceOver: the header and "Sababi" are announced as headings; 💬, ›, i and the avatar are silent; the Home row reads as one button. Largest Dynamic Type: the three answers stack, the decline buttons stack, nothing is cut.
14. Three languages and both themes: every P17 text correct; screenshots (Cmd+S).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.

## Open questions (ruled while planning)

- **Q1 — a bedtime approve that the server refuses with 409 `CONFLICT`** (night over, or its 30-minute ceiling already spent). The spec sends every failure other than `ALREADY_DECIDED`/404 to a toast through `UserMessage`, which for `CONFLICT` is `dataErrorConflict` ("Bu qoidalar siz oʻqiganingizdan keyin oʻzgargan…"); no existing key says "that night is over", and the spec forbids new keys. Ruling: follow the spec (toast, ask stays, decline still possible — Task 4 `aFailedDecisionIsSaidOnceAndCanBeTriedAgain`); E2E line 12 records what the parent reads, for a later copy decision.
