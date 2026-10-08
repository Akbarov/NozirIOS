# Nozir iOS — P16a: Summary link and review prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parent who taps a summary notification on P16 lands on exactly that day's P06 or that week's P07 (through a short "Xulosa" screen that asks the server which summary the link names and then hands its place in the stack to the summary), and a parent looking at a loaded daily summary three or more days after the first one is offered the system review sheet once per install.

**Architecture:** `NozirInsights` gains `SummaryPeriod`, `InsightSummary.period` and `InsightsService.summary(id:)` (`GET /v1/parent/summaries/{id}`). In `NozirAppFeature`, `SignedInView.HomeStep.summary` / `.weekly` gain an optional day / week (default `nil`, so every existing call stays as it is), `WeeklyReportModel` gains an initial week, and a new `HomeStep.summaryLink(UUID)` shows `SummaryLinkView` over `SummaryLinkModel` (`@MainActor @Observable`, generation counter), which resolves to a dated step; `SignedInView` then swaps the link for that step with the pure `SummaryLinkModel.path(_:replacing:with:)`. `NotificationLink.step(for:)` sends every summary link there. `ReviewGate` (UserDefaults + injectable clock, Android `ReviewGate` + `ReviewTiming`) is held by `SignedInModel`, handed to every `DailySummaryModel`, and `DailySummaryView` calls SwiftUI's `requestReview` when `DailySummaryModel.reviewIsDue()` says yes.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, StoreKit (`@Environment(\.requestReview)`), Swift Testing; no third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-ios-summary-link-review-design.md` (commit `e764c4c`). Backend contract checked against `Nozir-Backend` `insights/internal/web/InsightsController.kt:63-78`, `InsightDtos.kt:102-120`, `insights/internal/service/SummaryQueryService.kt:62-155`.

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries. **No `Package.swift` change** (StoreKit is a system framework, imported in one view).
- `GET /v1/parent/summaries/{summaryId}` (id lower-case, like `InsightsApi.childPath`) → `InsightSummaryResponse`: `summaryId`, `childId`, `period` (`DAILY|WEEKLY`), `periodStart`, `periodEnd` (`YYYY-MM-DD`), `paragraphs`, `recommendation?`, `conversationQuestion?`, `riskLevel`, `source`, `generatedAt`, `contentNotice`. Family-scoped: not found **or another family's** → 404. The call marks the summary read on the server.
- `period` absent, `null` or a value this app does not know → `nil`; existing daily/weekly decoding never breaks over it.
- Summary link outcomes (spec §4.2): `.daily` → `HomeStep.summary(childId, name, date: periodStart)`; `.weekly` → `HomeStep.weekly(childId, weekStart: periodStart)`; `period == nil` or the child not in the family → `.gone`; 404 → `.gone`; any other failure → `.failed(UserMessage)` with "Qayta urinish". **Nothing is retried automatically.**
- The link screen **replaces itself**: the last `.summaryLink(id)` in `homePath` is removed and the resolved step appended, so Back returns to where the parent tapped (P16).
- `HomeStep.summary(UUID, String)` and `.weekly(UUID)` keep working unchanged at every existing call site (Home, P06's weekly button); the Statistics tab's `makeWeeklyModel(childId:)` call keeps working unchanged.
- Review: `UserDefaults` keys exactly `review.firstSeenAt`, `review.askedAt`; the first call writes `firstSeenAt`; `now - firstSeenAt >= 3 days`, no `askedAt`, and the clock not behind `firstSeenAt` → write `askedAt` **before** answering `true`. Asked only while P06 shows a loaded summary. The outcome is unknown and there is **no second attempt**.
- User-facing text only from `L10n` (`screenSummaryLinkTitle`, `summaryLinkGoneTitle`, `summaryLinkGoneBody`, `stateErrorTitle`, `stateActionRetry` exist); errors only through `UserMessage`. **No new l10n key** (`gen_l10n.py --check` stays clean).
- Out of scope (spec §1): registering the `nozir` URL scheme, opening external links, universal links, push.
- Tests: Swift Testing; scripted fakes (`FakeInsights`, `FakeFamily`), `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`. UserDefaults in tests are always a fresh suite (`UserDefaults(suiteName: "<Suite>.\(UUID().uuidString)")!`).
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| L1 | §4.2 "bola oilada yoʻq (ism topilmasa) → `.gone`" | When the child is not in `FamilyStore`, the family list is asked for **once** (`family.refresh()`); still missing → `.gone`; that refresh failing → `.failed(UserMessage)` | The store is empty when `SignedInModel.start()` failed, and a child added on another phone is not in it yet; calling those "gone" would be a false "this summary no longer exists" |
| L2 | §4.2 child check named for the name only | Applied to both periods (weekly does not need the name) | Spec lists "bola oilada yoʻq → gone" as one rule; a removed child's weekly report would open on a child no screen knows |
| L3 | §3 "tarif xatosi boʻlishi mumkin (aniq kod plan'da)" | No special case: a 403 `SUBSCRIPTION_REQUIRED` is `.failed(.subscriptionRequired)` (error state with retry, the server's reason in our words) | `SummaryQueryService.byId` finds the stored row first and `daily`/`weekly` serve a stored row without the plan check (`weekly` only throws `ForbiddenException(SUBSCRIPTION_REQUIRED)` when it would have to *write* a week); the path is practically unreachable and `UserMessage` already words it |
| L4 | §4.2 phase `.resolved(HomeStep)` → "oʻzini almashtiradi" | The swap is the pure `SummaryLinkModel.path(_:replacing:with:)`; when the link is no longer on top (the parent already went back, or tapped elsewhere) **nothing** is pushed | Testable without a view; never pushes a screen behind the parent's back |
| L5 | §7 "kunlik/haftalik ekran sana bilan ochilganda ichki sana tanlagichi bilan toʻqnashmasligi" | `WeeklyReportModel(…, initialWeek:)` selects `initialWeek.monday` when the 53-week pager holds it; a week older than that or in the future opens on this week. A Monday that comes while the screen is open still moves it to the new week (`appear()`), as today | P07's pager is the only date picker; P06 has none (its `date` is fixed per screen) |
| L6 | (spec silent) P06 title for an earlier day | Stays "Ali bugun" (`dailySummaryChildToday`); the subtitle already shows the real day ("Dushanba, 5-oktabr") | Android `DailySummaryContent` uses the same `daily_summary_child_today` for a dated summary; a different title needs a new key, which the spec forbids |
| L7 | (spec silent) P06's "Haftalik hisobot" button on a dated P06 | Unchanged: `.weekly(childId)` (this week) | Spec scope is the link; keeps Home's flow byte-for-byte |
| L8 | §4.2 "`DailySummaryView` … chaqiradi" | The view asks `DailySummaryModel.reviewIsDue()` (the model holds the session's `ReviewGate`) when `hasSummary` becomes true, and calls `requestReview()` on `true` | The decision is then a model test, not a view test; the view keeps only the StoreKit call |
| L9 | §4.2 `ReviewGate` timestamps | Stored as `Double` seconds since 1970 (`timeIntervalSince1970`) | `UserDefaults` has no instant type; Android stores millis |
| L10 | §4.2 cancelled lookup (spec silent) | A cancelled request while the screen still waits → `.failed(.noConnection)` (retry offered), as `DailySummaryModel.fetch()` does | Never a spinner nobody drives |

## Review Focus

1. **A stale answer after a retry** (slow network, "Qayta urinish" tapped, then the first answer arrives late) — only the newest request's answer decides where the parent goes; the screen never navigates twice → Task 3 `aStaleAnswerNeverLands`.
2. **A weekly link opens that exact week** (Monday's notification read on Thursday of the next week) — P07 opens on the linked week, not this one; a week outside the pager's year opens on this week instead of crashing or showing an empty pager → Task 2 `aWeekGivenOpensOnThatWeek`, `aWeekOutsideTheYearOpensOnThisWeek`; Task 3 `aWeeklyLinkOpensThatWeek`.
3. **Existing Home / Statistics summary opening unchanged** — Home's card still opens the latest day, Statistics and P06's button still open this week → Task 2 `theSummaryScreensOpenOnTheDayOrWeekAsked`, `anUndatedStepIsTheOldOne` (plus the untouched `WeeklyReportModelTests.fiftyThreeWeeksEndingWithThisOne`, `DailySummaryModelTests.theLatestSummaryAndItsWeeksQuestion`).
4. **The review is never asked twice** — not on a second P06, not after a relaunch (a new gate on the same defaults), not when two P06 screens ask in the same moment → Task 4 `neverAskedTwiceNotEvenAfterARelaunch`, `theReviewIsAskedOnlyOverALoadedSummary`.
5. **The clock moved back** (manual time change, travel) — "not yet", never "ask again"; `firstSeenAt` is not rewritten; once the real time passes three days it asks once → Task 4 `aClockMovedBackIsNotYet`, `aClockMovedBackAfterAskingNeverAsksAgain`.
6. **The parent goes back before the link resolves** — nothing is pushed behind them; a second link on top is left alone → Task 3 `theLinkHandsItsPlaceToTheSummaryOnlyWhileOnTop`.

---

## File map

**New:**
- `NozirKit/Sources/NozirAppFeature/Insights/SummaryLinkModel.swift` — `SummaryLinkModel` (lookup, phases, the path swap).
- `NozirKit/Sources/NozirAppFeature/Screens/SummaryLinkView.swift` — P16a.
- `NozirKit/Sources/NozirAppFeature/Insights/ReviewGate.swift` — `ReviewGate`.
- `NozirKit/Tests/NozirAppFeatureTests/SummaryLinkModelTests.swift`, `ReviewGateTests.swift`.

**Modified:**
- `NozirKit/Sources/NozirInsights/{InsightModels,InsightsService,InsightsApi}.swift`.
- `NozirKit/Sources/NozirAppFeature/Insights/{DailySummaryModel,WeeklyReportModel}.swift`, `Notifications/NotificationLink.swift`, `SignedInModel.swift`, `AppEnvironment.swift`, `Screens/{SignedInView,DailySummaryView}.swift`.
- Tests: `NozirInsightsTests/InsightsApiTests.swift`; `NozirAppFeatureTests/{FakeInsights,HangingInsights,HomeModelTests,WeeklyReportModelTests,AppUsageModelTests,DailySummaryModelTests,NotificationLinkTests,SignedInModelTests}.swift`.

Untouched: `NozirL10n`, `l10n/`, `Package.swift`, `HomeView`, `StatisticsView`, `NotificationsView`, `NotificationsModel`, everything P18 / P20.

## Getting started

Branch `protection` (spec commit `e764c4c`, on top of the finished P18 and P16 work) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirInsightsTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

Names this plan relies on that already exist: `FakeInsights` / `insight(…)` / `day(_:)` / `notFound` (`NozirAppFeatureTests/FakeInsights.swift`), `offline` and `makeChild(_:id:…)` (`FakeFamily.swift:5`, `:236`), `PauseGate` and `baseTime` (`FakeLocation.swift:114`, `:139`), `summaryJSON(period:start:end:risk:)`, `summaryId`, `aliId`, `insightsApi(_:)` (`NozirInsightsTests/InsightsFixtures.swift`), `FamilyStore.refresh()` / `.child(_:)` / `.hasLoaded` (`NozirFamily/FamilyStore.swift`), `LocationTexts.present(_:)` (`Location/LocationTexts.swift:126`), `UserMessage(_:)` and `.noConnection` / `.subscriptionRequired` (`UserMessage.swift`), `ApiFailure.isNotFound`.

---
### Task 1: One summary by its id — `SummaryPeriod`, `InsightSummary.period`, `summary(id:)`

**Files:**
- Modify: `NozirKit/Sources/NozirInsights/InsightModels.swift:151-195` (`InsightSummary`)
- Modify: `NozirKit/Sources/NozirInsights/InsightsService.swift`
- Modify: `NozirKit/Sources/NozirInsights/InsightsApi.swift`
- Test: `NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift`
- Modify (conformers gain the new requirement): `NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift`, `HangingInsights.swift`, `HomeModelTests.swift` (`GatedHome`, ~line 378), `WeeklyReportModelTests.swift` (`GatedInsights`, ~line 36), `AppUsageModelTests.swift` (`GatedInsights`, ~line 19)

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiRequest(method:path:)`, `LocalDate`, `StatusLevel`; fixtures `insightsApi(_:)`, `summaryJSON(period:start:end:risk:)`, `summaryId`, `aliId`, `FakeTransport.Reply` `.ok` / `.error(_:code:)`.
- Produces:
  - `public enum SummaryPeriod: String, Sendable { case daily = "DAILY", weekly = "WEEKLY" }`.
  - `InsightSummary.period: SummaryPeriod?`; `InsightSummary.init(id:childId:period: SummaryPeriod? = nil, periodStart:periodEnd:paragraphs:recommendation:conversationQuestion:riskLevel:)` (every existing call compiles unchanged).
  - `InsightsService.summary(id: UUID) async throws -> InsightSummary` (404 → `ApiFailure.isNotFound`).
  - Test support (NozirAppFeatureTests): `FakeInsights.Script.byId: [Result<InsightSummary, ApiFailure>]` (empty queue = offline), `FakeInsights.Script.byIdGate: PauseGate?` (held once by the next `summary(id:)` call, after its answer is taken); call recorded as `"summary <id lower-case>"`; `insight(childId:start:end:paragraphs:question:risk:period:)` (new last parameter `period: SummaryPeriod? = nil`).

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift` — in `theDailySummaryWithoutADayIsTheLatest`, the expected value now carries the period (the fixture sends `"period":"DAILY"`). Replace:

```swift
        #expect(summary == InsightSummary(
            id: summaryId,
            childId: aliId,
            periodStart: LocalDate("2026-10-04")!,
```

with:

```swift
        #expect(summary == InsightSummary(
            id: summaryId,
            childId: aliId,
            period: .daily,
            periodStart: LocalDate("2026-10-04")!,
```

Then add these tests inside `InsightsApiTests`, right after `theWeeklySummaryIsAskedForByItsMonday`:

```swift
    // P16a (spec §3): a notification's summary, asked for by its id alone.
    @Test func aSummaryIsAskedForByItsId() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON(period: "WEEKLY", start: "2026-09-28", end: "2026-10-04"))])

        let summary = try await api.summary(id: summaryId)

        #expect(summary.id == summaryId)
        #expect(summary.childId == aliId)
        #expect(summary.period == .weekly)
        #expect(summary.periodStart == LocalDate("2026-09-28"))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/summaries/9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d")
        #expect(request.queryParameters.isEmpty)
    }

    // Not found, or another family's: the same 404.
    @Test func aSummaryByIdThatIsGoneIsNotFound() async {
        let (api, _) = insightsApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.summary(id: summaryId)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    // Spec §4.1: an unknown or missing period is nil, and never breaks the summary.
    @Test func thePeriodIsReadAndAnUnknownOrMissingOneIsNil() async throws {
        let daily = summaryJSON()
        let monthly = summaryJSON(period: "MONTHLY")
        let missing = summaryJSON().replacingOccurrences(of: #""period":"DAILY","#, with: "")
        let null = summaryJSON().replacingOccurrences(of: #""period":"DAILY""#, with: #""period":null"#)
        let (api, _) = insightsApi([.ok(daily), .ok(monthly), .ok(missing), .ok(null)])

        #expect(try await api.summary(id: summaryId).period == .daily)
        let unknown = try await api.summary(id: summaryId)
        #expect(unknown.period == nil)
        #expect(unknown.paragraphs.count == 2)
        #expect(try await api.summary(id: summaryId).period == nil)
        #expect(try await api.summary(id: summaryId).period == nil)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: FAIL — `value of type 'InsightsApi' has no member 'summary'` and `extra argument 'period' in call`.

- [ ] **Step 3: The period and the call**

`NozirKit/Sources/NozirInsights/InsightModels.swift` — replace the whole `InsightSummary` block (from `/// \`InsightSummaryResponse\`, daily or weekly.` to the closing brace of its `init(from:)`, lines 151-195) with:

```swift
/// `SummaryPeriod` on the wire. Only P16a reads it, to know which screen a
/// link opens.
public enum SummaryPeriod: String, Sendable {
    case daily = "DAILY"
    case weekly = "WEEKLY"
}

/// `InsightSummaryResponse`, daily or weekly.
public struct InsightSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    /// nil when absent or a value this app does not know (a monthly report
    /// one day): the summary still reads, a link to it is "gone".
    public let period: SummaryPeriod?
    public let periodStart: LocalDate
    public let periodEnd: LocalDate
    public let paragraphs: [String]
    public let recommendation: String?
    public let conversationQuestion: String?
    public let riskLevel: StatusLevel

    public init(
        id: UUID,
        childId: UUID,
        period: SummaryPeriod? = nil,
        periodStart: LocalDate,
        periodEnd: LocalDate,
        paragraphs: [String],
        recommendation: String? = nil,
        conversationQuestion: String? = nil,
        riskLevel: StatusLevel = .good
    ) {
        self.id = id
        self.childId = childId
        self.period = period
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.paragraphs = paragraphs
        self.recommendation = recommendation
        self.conversationQuestion = conversationQuestion
        self.riskLevel = riskLevel
    }

    enum CodingKeys: String, CodingKey {
        case id = "summaryId"
        case childId, period, periodStart, periodEnd, paragraphs, recommendation, conversationQuestion, riskLevel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        // Read as text: a period this app does not know never fails the summary.
        period = (try? container.decodeIfPresent(String.self, forKey: .period)).flatMap(SummaryPeriod.init(rawValue:))
        periodStart = try container.decode(LocalDate.self, forKey: .periodStart)
        periodEnd = try container.decode(LocalDate.self, forKey: .periodEnd)
        paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        conversationQuestion = try container.decodeIfPresent(String.self, forKey: .conversationQuestion)
        riskLevel = try container.decodeIfPresent(StatusLevel.self, forKey: .riskLevel) ?? .good
    }
}
```

(`try?` on an optional result flattens to `String?` in Swift 5+; a number or object in `period` reads as nil.)

`NozirKit/Sources/NozirInsights/InsightsService.swift` — add after `weeklySummary(of:weekStart:)`:

```swift
    /// The summary a notification names (P16a). Not found or another family's
    /// is a 404 (`ApiFailure.isNotFound`). The server marks it read.
    func summary(id: UUID) async throws -> InsightSummary
```

`NozirKit/Sources/NozirInsights/InsightsApi.swift` — replace the type's two-line doc comment with:

```swift
/// `/v1/parent/home`, `/summaries/{daily,weekly}`, `/v1/parent/summaries/{id}`
/// and `/usage/{daily,apps}` (backend `InsightsController`, `UsageController`).
```

and add after `weeklySummary(of:weekStart:)`:

```swift
    public func summary(id: UUID) async throws -> InsightSummary {
        let request = ApiRequest(method: .get, path: "/v1/parent/summaries/\(id.uuidString.lowercased())")
        return try await client.send(request, as: InsightSummary.self)
    }
```

- [ ] **Step 4: Run the Insights tests to see them pass**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: `** TEST SUCCEEDED **`, the 3 new tests among them.

- [ ] **Step 5: Every fake answers the new call**

`NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift`:

In `FakeInsights.Script`, after `var apps: …`:

```swift
        /// `summary(id:)` answers, in order; an empty queue is no connection.
        var byId: [Result<InsightSummary, ApiFailure>] = []
        /// Held once by the next `summary(id:)` call, after its answer is taken.
        var byIdGate: PauseGate?
```

Change the `calls` doc comment to:

```swift
    /// "home", "daily latest", "daily 2026-10-04", "weekly 2026-09-28",
    /// "usage 2026-09-28…2026-10-04", "apps TODAY", "summary <id lower-case>".
```

Add after `weeklySummary(of:weekStart:)`:

```swift
    func summary(id: UUID) async throws -> InsightSummary {
        calls.append("summary \(id.uuidString.lowercased())")
        let answer: Result<InsightSummary, ApiFailure> = script.byId.isEmpty ? .failure(offline) : script.byId.removeFirst()
        let gate = script.byIdGate
        script.byIdGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
```

Replace the `insight(…)` helper with (new last parameter, same defaults otherwise):

```swift
func insight(
    childId: UUID,
    start: String,
    end: String,
    paragraphs: [String] = ["Tinch kun."],
    question: String? = nil,
    risk: StatusLevel = .good,
    period: SummaryPeriod? = nil
) -> InsightSummary {
    InsightSummary(
        id: UUID(),
        childId: childId,
        period: period,
        periodStart: day(start),
        periodEnd: day(end),
        paragraphs: paragraphs,
        recommendation: "Birga sayr qiling.",
        conversationQuestion: question,
        riskLevel: risk
    )
}
```

`NozirKit/Tests/NozirAppFeatureTests/HangingInsights.swift` — add after its `weeklySummary` line:

```swift
    func summary(id: UUID) async throws -> InsightSummary { throw offline }
```

`NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift` (`GatedHome`), `WeeklyReportModelTests.swift` (`GatedInsights`) and `AppUsageModelTests.swift` (`GatedInsights`) — add the same line after each one's `weeklySummary` line:

```swift
    func summary(id: UUID) async throws -> InsightSummary { throw offline }
```

- [ ] **Step 6: Run the feature tests (they must still compile and pass)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **` (no new test yet; a `does not conform to protocol 'InsightsService'` error means a conformer was missed — `grep -rn ": InsightsService" NozirKit` lists all five).

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirInsights/InsightModels.swift NozirKit/Sources/NozirInsights/InsightsService.swift NozirKit/Sources/NozirInsights/InsightsApi.swift NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift NozirKit/Tests/NozirAppFeatureTests/HangingInsights.swift NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift NozirKit/Tests/NozirAppFeatureTests/AppUsageModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16a: one summary by its id, and which period it is

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: P06 on a given day, P07 on a given week — dated steps and factories

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift:57-63` (`init`)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift:208-221` (`makeDailySummaryModel`, `makeWeeklyModel`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift:11-12` (`HomeStep`), `:174-189` (`homeDestination`)
- Test: `NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift`, `SignedInModelTests.swift`

**Interfaces:**
- Consumes: `DailySummaryModel(childId:childName:date:insights:)` (exists, `DailySummaryModel.swift:29`), `LocalDate.monday`, `LocalDate.adding(days:)`, `FakeInsights` (Task 1).
- Produces:
  - `SignedInView.HomeStep.summary(UUID, String, date: LocalDate? = nil)` and `.weekly(UUID, weekStart: LocalDate? = nil)` — `.summary(id, name)` / `.weekly(id)` still build the undated step.
  - `WeeklyReportModel.init(childId: UUID, insights: any InsightsService, today: @escaping @MainActor () -> LocalDate, initialWeek: LocalDate? = nil)`.
  - `SignedInModel.makeDailySummaryModel(childId: UUID, childName: String, date: LocalDate? = nil) -> DailySummaryModel`.
  - `SignedInModel.makeWeeklyModel(childId: UUID, weekStart: LocalDate? = nil) -> WeeklyReportModel`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift` — replace the `setup` helper with:

```swift
@MainActor
private func setup(_ script: FakeInsights.Script, today: Today? = nil, initialWeek: LocalDate? = nil) -> (WeeklyReportModel, FakeInsights) {
    let clock = today ?? Today("2026-10-07")
    let insights = FakeInsights(script)
    let model = WeeklyReportModel(childId: aliId, insights: insights, today: { clock.value }, initialWeek: initialWeek)
    return (model, insights)
}
```

and add inside `WeeklyReportModelTests`, after `fiftyThreeWeeksEndingWithThisOne`:

```swift
    // P16a (spec §4.2, plan L5; Review Focus 2): a link's week opens on its
    // Monday, inside the same fifty-three weeks.
    @Test func aWeekGivenOpensOnThatWeek() async {
        let (model, insights) = setup(FakeInsights.Script(), initialWeek: day("2026-09-16"))

        #expect(model.selectedWeek == day("2026-09-14"))
        #expect(model.currentWeek == day("2026-10-05"))
        #expect(model.weeks.count == 53)

        await model.appear()

        #expect(await insights.calls.first == "usage 2026-09-14…2026-09-20")
        #expect(model.selectedWeek == day("2026-09-14"))
    }

    // Older than the pager's year, or still to come: this week, never an empty pager.
    @Test func aWeekOutsideTheYearOpensOnThisWeek() {
        #expect(setup(FakeInsights.Script(), initialWeek: day("2025-10-05")).0.selectedWeek == day("2026-10-05"))
        #expect(setup(FakeInsights.Script(), initialWeek: day("2026-10-12")).0.selectedWeek == day("2026-10-05"))
        #expect(setup(FakeInsights.Script(), initialWeek: day("2025-10-06")).0.selectedWeek == day("2025-10-06"))
    }
```

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — in `setup(…)`, add a parameter after `defaults:`:

```swift
    insights: FakeInsights = FakeInsights(),
```

and in the `SignedInModel(` call replace `insights: FakeInsights(),` with `insights: insights,`. Then add at the end of `SignedInModelTests`:

```swift
    // P16a (Review Focus 3): Home's and Statistics' calls open what they always
    // opened; a day or a week given is the one opened.
    @Test func theSummaryScreensOpenOnTheDayOrWeekAsked() async {
        let id = UUID()
        let insights = FakeInsights()
        let (model, _) = setup(FakeFamily.Script(), insights: insights)

        await model.makeDailySummaryModel(childId: id, childName: "Ali").load()
        await model.makeDailySummaryModel(childId: id, childName: "Ali", date: day("2026-10-01")).load()

        #expect(await insights.calls == ["daily latest", "daily 2026-10-01"])
        let thisWeek = model.makeWeeklyModel(childId: id)
        #expect(thisWeek.selectedWeek == thisWeek.currentWeek)
        let earlier = thisWeek.currentWeek.adding(days: -14)
        #expect(model.makeWeeklyModel(childId: id, weekStart: earlier.adding(days: 2)).selectedWeek == earlier)
    }

    @Test func anUndatedStepIsTheOldOne() {
        let id = UUID()
        #expect(SignedInView.HomeStep.summary(id, "Ali") == .summary(id, "Ali", date: nil))
        #expect(SignedInView.HomeStep.weekly(id) == .weekly(id, weekStart: nil))
        #expect(SignedInView.HomeStep.summary(id, "Ali") != .summary(id, "Ali", date: day("2026-10-01")))
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra argument 'initialWeek' in call`, `extra argument 'date' in call`, `extra argument 'weekStart' in call`.

- [ ] **Step 3: The initial week**

`NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift` — replace the `init`:

```swift
    /// `initialWeek` (P16a): the week a link names. Its Monday is shown when
    /// the fifty-three weeks hold it; otherwise this week (plan deviation L5).
    init(
        childId: UUID,
        insights: any InsightsService,
        today: @escaping @MainActor () -> LocalDate,
        initialWeek: LocalDate? = nil
    ) {
        self.childId = childId
        self.insights = insights
        self.today = today
        let current = today().monday
        let weeks = Self.weeks(endingAt: current)
        self.weeks = weeks
        if let asked = initialWeek?.monday, weeks.contains(asked) {
            selectedWeek = asked
        } else {
            selectedWeek = current
        }
    }
```

- [ ] **Step 4: The factories**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — replace `makeDailySummaryModel` and `makeWeeklyModel` with:

```swift
    /// P06: `date` nil is the latest finished day (Home); a link gives its day.
    func makeDailySummaryModel(childId: UUID, childName: String, date: LocalDate? = nil) -> DailySummaryModel {
        DailySummaryModel(childId: childId, childName: childName, date: date, insights: insights)
    }

    /// P07: `weekStart` nil is this week (Home, Statistics); a link gives its week.
    func makeWeeklyModel(childId: UUID, weekStart: LocalDate? = nil) -> WeeklyReportModel {
        WeeklyReportModel(
            childId: childId,
            insights: insights,
            today: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                return LocalDate(Date(), in: calendar)
            },
            initialWeek: weekStart
        )
    }
```

- [ ] **Step 5: The steps**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — in `HomeStep`, replace

```swift
        case summary(UUID, String)
        case weekly(UUID)
```

with

```swift
        /// P06 for a child; `date` nil is the latest finished day.
        case summary(UUID, String, date: LocalDate? = nil)
        /// P07 for a child; `weekStart` nil is this week.
        case weekly(UUID, weekStart: LocalDate? = nil)
```

and in `homeDestination(_:)` replace the `.summary` and `.weekly` cases with:

```swift
        case .summary(let childId, let childName, let date):
            DailySummaryView(
                model: model.makeDailySummaryModel(childId: childId, childName: childName, date: date),
                onEditChild: {
                    if let child = model.family.child(childId) {
                        homePath.append(.details(child))
                    }
                },
                onOpenWeekly: { homePath.append(.weekly(childId)) }
            )
        case .weekly(let childId, let weekStart):
            WeeklyReportView(
                model: model.makeWeeklyModel(childId: childId, weekStart: weekStart),
                switcher: nil,
                onOpenApps: { homePath.append(.apps($0)) }
            )
```

(`HomeView`'s `homePath.append(.summary($0, $1))`, P06's `.weekly(childId)` and `StatisticsView`'s `makeWeekly: { model.makeWeeklyModel(childId: $0) }` stay exactly as they are.)

- [ ] **Step 6: Run the tests to see them pass, and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (the 4 new tests among them, every older Weekly / Daily / SignedIn test unchanged), then `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16a: the daily summary on a given day, the weekly report on a given week

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: P16a — `SummaryLinkModel`, `SummaryLinkView`, and every summary link through it

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/SummaryLinkModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SummaryLinkView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift:12-13` (doc of `.summary`), `:57-66` (`step(for:)`'s `.summary` case)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift` (factory after `makeWeeklyModel`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`HomeStep.summaryLink`, its destination)
- Create: `NozirKit/Tests/NozirAppFeatureTests/SummaryLinkModelTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift:46-61`, `SignedInModelTests.swift`

**Interfaces:**
- Consumes: `InsightsService.summary(id:)`, `SummaryPeriod`, `FakeInsights.Script.byId` / `.byIdGate`, `insight(…, period:)` (Task 1); `HomeStep.summary(_:_:date:)`, `.weekly(_:weekStart:)` (Task 2); `FamilyStore.child(_:)` / `.refresh()`; `LocationTexts.present(_:)`; `UserMessage(_:)`; `ApiFailure.isNotFound`; `NozirEmptyState(title:message:)`, `NozirErrorState(title:message:retryTitle:action)`; `FakeFamily.Script.children`, `FakeFamily.calls`, `makeChild(_:id:)`, `PauseGate`.
- Produces:
  - `SignedInView.HomeStep.summaryLink(UUID)` (the id is the summary's).
  - `@MainActor @Observable final class SummaryLinkModel { enum Phase: Equatable { case loading, resolved(SignedInView.HomeStep), gone, failed(UserMessage) }; let summaryId: UUID; private(set) var phase: Phase; init(summaryId: UUID, insights: any InsightsService, family: FamilyStore); func load() async; static func path(_ path: [SignedInView.HomeStep], replacing summaryId: UUID, with step: SignedInView.HomeStep) -> [SignedInView.HomeStep] }`.
  - `SummaryLinkView(model: SummaryLinkModel, onResolved: (SignedInView.HomeStep) -> Void)`.
  - `SignedInModel.makeSummaryLinkModel(summaryId: UUID) -> SummaryLinkModel`.
  - `NotificationLink.step(for:)`: `nozir://summary/{id}` → `.summaryLink(id)` for any row.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/SummaryLinkModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()
private let linkId = UUID()
private let ali = makeChild("Ali", id: aliId)
private let vali = makeChild("Vali")

/// The family list is read before the screen opens (`preload`), as
/// `SignedInModel.start()` does; `children` answers every read in order.
@MainActor
private func setup(
    _ script: FakeInsights.Script,
    children: [Result<[Child], ApiFailure>] = [.success([ali])],
    preload: Bool = true
) async -> (SummaryLinkModel, FakeInsights, FakeFamily) {
    var familyScript = FakeFamily.Script()
    familyScript.children = children
    let familyService = FakeFamily(familyScript)
    let store = FamilyStore(service: familyService)
    if preload { try? await store.refresh() }
    let insights = FakeInsights(script)
    return (SummaryLinkModel(summaryId: linkId, insights: insights, family: store), insights, familyService)
}

private func linked(_ period: SummaryPeriod?, start: String, end: String) -> InsightSummary {
    insight(childId: aliId, start: start, end: end, period: period)
}

@MainActor
@Suite struct SummaryLinkModelTests {
    // Spec §4.2: DAILY → P06 on exactly that day, named from the family list.
    @Test func aDailyLinkOpensThatDay() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, insights, _) = await setup(script)

        #expect(model.phase == .loading)
        await model.load()

        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await insights.calls == ["summary \(linkId.uuidString.lowercased())"])
    }

    // Review Focus 2: WEEKLY → P07 on exactly that week, not this one.
    @Test func aWeeklyLinkOpensThatWeek() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.weekly, start: "2026-09-14", end: "2026-09-20"))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))
    }

    // 404: removed, or another family's — the same answer.
    @Test func aSummaryThatIsGoneSaysSo() async {
        var script = FakeInsights.Script()
        script.byId = [.failure(notFound)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .gone)
    }

    @Test func aSummaryOfNoKnownPeriodIsGone() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(nil, start: "2026-10-01", end: "2026-10-31"))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .gone)
    }

    // Plan deviations L1, L2: the list is asked for once before "gone", for either period.
    @Test func aChildNoLongerInTheFamilyIsGone() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.weekly, start: "2026-09-14", end: "2026-09-20"))]
        let (model, _, family) = await setup(script, children: [.success([vali]), .success([vali])])

        await model.load()

        #expect(model.phase == .gone)
        #expect(await family.calls == ["children", "children"])
    }

    // Plan deviation L1: a list not read yet (start() failed, or a child added
    // on another phone) is read first.
    @Test func aFamilyNotReadYetIsAskedFor() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _, family) = await setup(script, preload: false)

        await model.load()

        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await family.calls == ["children"])
    }

    @Test func aFamilyThatCannotBeReadIsAFailure() async {
        var script = FakeInsights.Script()
        script.byId = [.success(linked(.daily, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _, _) = await setup(script, children: [], preload: false)

        await model.load()

        #expect(model.phase == .failed(.noConnection))
    }

    // Spec §4.2 and plan deviation L3: any other failure is said in our words,
    // and "Qayta urinish" asks again.
    @Test func otherFailuresAreSaidAndCanBeRetried() async {
        var script = FakeInsights.Script()
        script.byId = [
            .failure(offline),
            .failure(.server(status: 403, error: ApiError(code: .subscriptionRequired))),
            .success(linked(.daily, start: "2026-10-04", end: "2026-10-04")),
        ]
        let (model, insights, _) = await setup(script)

        await model.load()
        #expect(model.phase == .failed(.noConnection))
        await model.load()
        #expect(model.phase == .failed(.subscriptionRequired))
        await model.load()
        #expect(model.phase == .resolved(.summary(aliId, "Ali", date: day("2026-10-04"))))
        #expect(await insights.calls.count == 3)
    }

    // Review Focus 1: an earlier answer arriving after a retry never lands.
    @Test(.timeLimit(.minutes(5))) func aStaleAnswerNeverLands() async {
        let gate = PauseGate()
        var script = FakeInsights.Script()
        script.byId = [
            .success(linked(.daily, start: "2026-10-04", end: "2026-10-04")),
            .success(linked(.weekly, start: "2026-09-14", end: "2026-09-20")),
        ]
        script.byIdGate = gate
        let (model, _, _) = await setup(script)

        let first = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))

        await gate.release()
        await first.value

        #expect(model.phase == .resolved(.weekly(aliId, weekStart: day("2026-09-14"))))
    }

    // Review Focus 6, plan deviation L4: the link hands its place to the
    // summary; when it is no longer on top nothing is pushed.
    @Test func theLinkHandsItsPlaceToTheSummaryOnlyWhileOnTop() {
        let link = SignedInView.HomeStep.summaryLink(linkId)
        let daily = SignedInView.HomeStep.summary(aliId, "Ali", date: day("2026-10-04"))

        #expect(SummaryLinkModel.path([.notifications, link], replacing: linkId, with: daily) == [.notifications, daily])
        #expect(SummaryLinkModel.path([.notifications], replacing: linkId, with: daily) == [.notifications])
        let other = SignedInView.HomeStep.summaryLink(UUID())
        #expect(SummaryLinkModel.path([.notifications, link, .notifications, other], replacing: linkId, with: daily)
            == [.notifications, link, .notifications, other])
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift` — replace the test `aSummaryLinkOpensByItsType` (with its comment) by:

```swift
    // P16a (spec D2, §4.2): a summary link opens that exact summary, whatever
    // the row's type, child or name; the server says which day or week it is.
    @Test func aSummaryLinkOpensThatSummary() {
        let link = "nozir://summary/\(linkText)"
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link)) == .summaryLink(linkId))
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: link)) == .summaryLink(linkId))
        #expect(NotificationLink.step(for: row(.usageAnomaly, link: link)) == .summaryLink(linkId))
        #expect(NotificationLink.step(for: row(.dailySummaryReady, link: link, childName: nil)) == .summaryLink(linkId))
        #expect(NotificationLink.step(for: row(.weeklyReportReady, link: link, childId: nil)) == .summaryLink(linkId))
    }
```

and in `aLinkThatNeedsAChildGoesNowhereWithoutOne` delete the two lines that expect `nil` for `.dailySummaryReady` / `.weeklyReportReady` with `nozir://summary/…` and `childId: nil` (a summary link no longer needs the row's child).

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — add at the end of `SignedInModelTests`:

```swift
    // P16a: the link screen asks the session's insights and names the child
    // from the session's family.
    @Test func theSummaryLinkScreenUsesTheSessionsServices() async {
        let ali = makeChild("Ali")
        var family = FakeFamily.Script()
        family.children = [.success([ali])]
        var script = FakeInsights.Script()
        script.byId = [.success(insight(childId: ali.id, start: "2026-10-04", end: "2026-10-04", period: .daily))]
        let id = UUID()
        let (model, _) = setup(family, insights: FakeInsights(script))
        try? await model.family.refresh()

        let screen = model.makeSummaryLinkModel(summaryId: id)
        await screen.load()

        #expect(screen.summaryId == id)
        #expect(screen.phase == .resolved(.summary(ali.id, "Ali", date: day("2026-10-04"))))
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'SummaryLinkModel' in scope`, `type 'SignedInView.HomeStep' has no member 'summaryLink'`.

- [ ] **Step 3: The model**

`NozirKit/Sources/NozirAppFeature/Insights/SummaryLinkModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirNetworking

/// P16a (Android `SummaryLinkViewModel`): a notification names a summary by
/// its id alone; this asks the server which child and which day or week it
/// is, and answers with the step that opens it. Nothing is cached: every
/// visit is a tap, and a cache could only answer a new tap with an old one.
@MainActor
@Observable
final class SummaryLinkModel {
    enum Phase: Equatable {
        case loading
        /// Where the summary lives; the screen hands its place to this step.
        case resolved(SignedInView.HomeStep)
        /// 404 (removed, or another family's), a period this app does not
        /// know, or a child no longer in the family.
        case gone
        case failed(UserMessage)
    }

    let summaryId: UUID
    private(set) var phase: Phase = .loading

    private let insights: any InsightsService
    private let family: FamilyStore
    /// Only the newest lookup writes (spec §4.2).
    @ObservationIgnored private var generation = 0

    init(summaryId: UUID, insights: any InsightsService, family: FamilyStore) {
        self.summaryId = summaryId
        self.insights = insights
        self.family = family
    }

    /// On appear and on "Qayta urinish". A later call wins: an earlier answer
    /// that arrives after it is dropped, so the screen never navigates twice.
    func load() async {
        generation += 1
        let mine = generation
        phase = .loading
        let next: Phase
        do {
            let summary = try await insights.summary(id: summaryId)
            guard mine == generation else { return }
            next = try await step(for: summary).map(Phase.resolved) ?? .gone
        } catch is CancellationError {
            // Nothing to fall back to: offer a retry rather than a spinner nobody drives (plan deviation L10).
            next = .failed(.noConnection)
        } catch let failure as ApiFailure where failure.isNotFound {
            next = .gone
        } catch {
            next = .failed(UserMessage(error))
        }
        guard mine == generation else { return }
        phase = next
    }

    /// nil: nothing this app can open (spec §4.2).
    private func step(for summary: InsightSummary) async throws -> SignedInView.HomeStep? {
        guard let period = summary.period, let name = try await childName(summary.childId) else { return nil }
        switch period {
        case .daily:
            return .summary(summary.childId, name, date: summary.periodStart)
        case .weekly:
            return .weekly(summary.childId, weekStart: summary.periodStart)
        }
    }

    /// From the family list; when the child is not in it, the list is asked
    /// for once (plan deviation L1). A failed read is thrown, not "gone".
    private func childName(_ childId: UUID) async throws -> String? {
        if let child = family.child(childId) {
            return LocationTexts.present(child.displayName)
        }
        try await family.refresh()
        return family.child(childId).flatMap { LocationTexts.present($0.displayName) }
    }

    /// The link hands its place in Home's stack to the summary (spec §4.2):
    /// Back from that summary returns to where the parent tapped. When the
    /// link is no longer on top — the parent went back, or something else was
    /// opened over it — the path stays as it is (plan deviation L4).
    static func path(
        _ path: [SignedInView.HomeStep],
        replacing summaryId: UUID,
        with step: SignedInView.HomeStep
    ) -> [SignedInView.HomeStep] {
        guard path.last == .summaryLink(summaryId) else { return path }
        return Array(path.dropLast()) + [step]
    }
}
```

- [ ] **Step 4: The link, the step and the factory**

`NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift` — change the `.summary` case's doc comment to:

```swift
    /// The id is the summary's; P16a asks the server which day or week it is.
```

and in `step(for:)` replace the whole `case .summary:` branch (from `case .summary:` to the `}` closing its inner `switch notification.type`) with:

```swift
        case .summary(let summaryId):
            return .summaryLink(summaryId)
```

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — in `HomeStep`, after `case notifications`:

```swift
        /// P16a: a summary notification, until the server says which day or
        /// week it is; then replaced by that step (the id is the summary's).
        case summaryLink(UUID)
```

and in `homeDestination(_:)`, after the `.notifications` case:

```swift
        case .summaryLink(let summaryId):
            SummaryLinkView(model: model.makeSummaryLinkModel(summaryId: summaryId)) { step in
                homePath = SummaryLinkModel.path(homePath, replacing: summaryId, with: step)
            }
```

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — after `makeWeeklyModel(childId:weekStart:)`:

```swift
    /// P16a for one notification; the session's family list names the child.
    func makeSummaryLinkModel(summaryId: UUID) -> SummaryLinkModel {
        SummaryLinkModel(summaryId: summaryId, insights: insights, family: family)
    }
```

- [ ] **Step 5: The screen**

`NozirKit/Sources/NozirAppFeature/Screens/SummaryLinkView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P16a as Android `SummaryLinkContent`: a spinner while the server says
/// which summary the link names, "Bu xulosa endi mavjud emas" when there is
/// none, the error state with "Qayta urinish" on a failure. Once resolved the
/// screen is replaced by the summary at once (spec §5).
struct SummaryLinkView: View {
    @State private var model: SummaryLinkModel
    private let onResolved: (SignedInView.HomeStep) -> Void
    @Environment(\.l10n) private var l10n

    init(model: SummaryLinkModel, onResolved: @escaping (SignedInView.HomeStep) -> Void) {
        _model = State(initialValue: model)
        self.onResolved = onResolved
    }

    var body: some View {
        ScrollView {
            content
                .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenSummaryLinkTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.phase, initial: true) { _, phase in
            if case .resolved(let step) = phase {
                onResolved(step)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading, .resolved:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .gone:
            NozirEmptyState(title: l10n.summaryLinkGoneTitle, message: l10n.summaryLinkGoneBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        }
    }
}
```

- [ ] **Step 6: Run the tests to see them pass, and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (12 new or rewritten tests, the changed `NotificationLinkTests` among them; `NotificationsModelTests` unchanged), then `** BUILD SUCCEEDED **` with no `Sendable` / isolation warnings.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/SummaryLinkModel.swift NozirKit/Sources/NozirAppFeature/Screens/SummaryLinkView.swift NozirKit/Sources/NozirAppFeature/Notifications/NotificationLink.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/SummaryLinkModelTests.swift NozirKit/Tests/NozirAppFeatureTests/NotificationLinkTests.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16a: a summary notification opens that exact day or week

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: The review prompt — `ReviewGate`, P06's moment, and the session's gate

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/ReviewGate.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift:23-34` (properties, `init`), plus two members
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift` (`import StoreKit`, `requestReview`, one modifier)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift` (property, `init` parameter, `makeDailySummaryModel`)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:77-104` (`makeSignedInModel`)
- Create: `NozirKit/Tests/NozirAppFeatureTests/ReviewGateTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift`, `SignedInModelTests.swift`

**Interfaces:**
- Consumes: `makeDailySummaryModel(childId:childName:date:)` (Task 2), `FakeInsights`, `insight(…)`, `notFound`, `offline`, `baseTime` (`FakeLocation.swift:139`).
- Produces:
  - `@MainActor final class ReviewGate { static let firstSeenKey = "review.firstSeenAt"; static let askedKey = "review.askedAt"; static let waitBeforeFirstAsk: TimeInterval /* 3 days */; init(defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Date = { Date() }); func consumeIfDue() -> Bool }`.
  - `DailySummaryModel.init(childId: UUID, childName: String, date: LocalDate? = nil, insights: any InsightsService, reviewGate: ReviewGate? = nil)`; `var hasSummary: Bool`; `func reviewIsDue() -> Bool`.
  - `SignedInModel.init(…, privacyConfig:, reviewGate: ReviewGate, signOutLocally:, signOut:)`.
  - Test support: `@MainActor final class MovableClock { var now: Date; init(_ now: Date = baseTime); func advance(days: Double) }` (in `ReviewGateTests.swift`, internal to the test target).

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/ReviewGateTests.swift`:

```swift
import Foundation
import Testing
@testable import NozirAppFeature

/// A wall clock a test moves by hand, forwards or back.
@MainActor
final class MovableClock {
    var now: Date

    init(_ now: Date = baseTime) {
        self.now = now
    }

    func advance(days: Double) {
        now = now.addingTimeInterval(days * 24 * 60 * 60)
    }
}

private let firstSeenKey = "review.firstSeenAt"
private let askedKey = "review.askedAt"
private let threeDays: TimeInterval = 3 * 24 * 60 * 60

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ReviewGateTests.\(UUID().uuidString)")!
}

/// Spec D3, §4.2 (Android `ReviewGate`, `ReviewTiming`).
@MainActor
@Suite struct ReviewGateTests {
    @Test func theKeysAreTheSpecs() {
        #expect(ReviewGate.firstSeenKey == firstSeenKey)
        #expect(ReviewGate.askedKey == askedKey)
        #expect(ReviewGate.waitBeforeFirstAsk == threeDays)
    }

    @Test func theFirstSightingOnlyStartsTheClock() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })

        #expect(!gate.consumeIfDue())
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
        #expect(defaults.object(forKey: askedKey) == nil)
    }

    @Test func lessThanThreeDaysIsNotYet() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.now = baseTime.addingTimeInterval(threeDays - 1)

        #expect(!gate.consumeIfDue())
        #expect(defaults.object(forKey: askedKey) == nil)
    }

    @Test func threeDaysAsksAndRecordsItBeforeAnswering() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.now = baseTime.addingTimeInterval(threeDays)

        #expect(gate.consumeIfDue())
        #expect(defaults.double(forKey: askedKey) == clock.now.timeIntervalSince1970)
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
    }

    // Review Focus 4: once per install — not again later, not after a relaunch.
    @Test func neverAskedTwiceNotEvenAfterARelaunch() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()
        clock.advance(days: 3)

        #expect(gate.consumeIfDue())
        #expect(!gate.consumeIfDue())
        clock.advance(days: 30)
        #expect(!gate.consumeIfDue())
        let relaunched = ReviewGate(defaults: defaults, now: { clock.now })
        #expect(!relaunched.consumeIfDue())
    }

    // Review Focus 5: a clock moved back is "not yet", never "ask again", and
    // never moves the first sighting.
    @Test func aClockMovedBackIsNotYet() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()

        clock.advance(days: -10)

        #expect(!gate.consumeIfDue())
        #expect(defaults.double(forKey: firstSeenKey) == baseTime.timeIntervalSince1970)
        #expect(defaults.object(forKey: askedKey) == nil)
        clock.now = baseTime.addingTimeInterval(threeDays)
        #expect(gate.consumeIfDue())
    }

    @Test func aClockMovedBackAfterAskingNeverAsksAgain() {
        let defaults = freshDefaults()
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        _ = gate.consumeIfDue()
        clock.advance(days: 3)
        #expect(gate.consumeIfDue())

        clock.now = baseTime.addingTimeInterval(-30 * 24 * 60 * 60)
        #expect(!gate.consumeIfDue())
        clock.now = baseTime.addingTimeInterval(60 * 24 * 60 * 60)
        #expect(!gate.consumeIfDue())
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift` — replace the `setup` helper with:

```swift
@MainActor
private func setup(_ script: FakeInsights.Script, date: LocalDate? = nil, reviewGate: ReviewGate? = nil) -> (DailySummaryModel, FakeInsights) {
    let insights = FakeInsights(script)
    return (DailySummaryModel(childId: aliId, childName: "Ali", date: date, insights: insights, reviewGate: reviewGate), insights)
}
```

and add at the end of `DailySummaryModelTests`:

```swift
    // Spec D3 (Android `ReviewPrompt(isGoodMoment = summary != null)`): asked
    // only over a loaded summary; "not ready" and errors never touch the gate.
    @Test func theReviewIsAskedOnlyOverALoadedSummary() async {
        let defaults = UserDefaults(suiteName: "DailySummaryModelTests.\(UUID().uuidString)")!
        let clock = MovableClock()
        let gate = ReviewGate(defaults: defaults, now: { clock.now })
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()

        script.daily = [.failure(notFound)]
        let (notReady, _) = setup(script, reviewGate: gate)
        await notReady.load()
        script.daily = [.failure(offline)]
        let (failed, _) = setup(script, reviewGate: gate)
        await failed.load()
        clock.advance(days: 5)

        #expect(!notReady.hasSummary)
        #expect(!notReady.reviewIsDue())
        #expect(!failed.reviewIsDue())
        #expect(defaults.object(forKey: ReviewGate.firstSeenKey) == nil)

        script.daily = [.success(daily)]
        let (first, _) = setup(script, reviewGate: gate)
        await first.load()
        #expect(first.hasSummary)
        #expect(!first.reviewIsDue())

        clock.advance(days: 3)
        let (later, _) = setup(script, reviewGate: gate)
        await later.load()
        #expect(later.reviewIsDue())
        #expect(!later.reviewIsDue())
        #expect(!first.reviewIsDue())

        let (withoutGate, _) = setup(script)
        await withoutGate.load()
        #expect(!withoutGate.reviewIsDue())
    }
```

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — in `setup(…)`, add a parameter right after `insights:`:

```swift
    reviewGate: ReviewGate? = nil,
```

and in the `SignedInModel(` call, after `privacyConfig: { privacyConfig },`:

```swift
        reviewGate: reviewGate ?? ReviewGate(defaults: defaults),
```

Then add at the end of `SignedInModelTests`:

```swift
    // Spec D3: every P06 of the session asks the one gate, so the second
    // summary cannot ask again.
    @Test func theDailySummariesShareTheSessionsReviewGate() async {
        let defaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!
        let clock = MovableClock()
        let daily = insight(childId: UUID(), start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.success(daily), .success(daily), .success(daily)]
        let (model, _) = setup(
            FakeFamily.Script(),
            defaults: defaults,
            insights: FakeInsights(script),
            reviewGate: ReviewGate(defaults: defaults, now: { clock.now })
        )

        let first = model.makeDailySummaryModel(childId: daily.childId, childName: "Ali")
        await first.load()
        #expect(!first.reviewIsDue())
        clock.advance(days: 3)
        let second = model.makeDailySummaryModel(childId: daily.childId, childName: "Ali")
        await second.load()
        let third = model.makeDailySummaryModel(childId: daily.childId, childName: "Ali", date: day("2026-10-04"))
        await third.load()

        #expect(second.reviewIsDue())
        #expect(!third.reviewIsDue())
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'ReviewGate' in scope`, `extra argument 'reviewGate' in call`, `value of type 'DailySummaryModel' has no member 'reviewIsDue'`.

- [ ] **Step 3: The gate**

`NozirKit/Sources/NozirAppFeature/Insights/ReviewGate.swift`:

```swift
import Foundation

/// Spec D3 (Android `ReviewGate` + `ReviewTiming`): the one chance to ask for
/// a store review, spent once per install and not in the first three days.
/// On disk because the question is about this install, not this launch: an
/// app that asked yesterday must not ask again because it was restarted.
/// Apple decides whether its sheet appears; nothing here learns what the
/// parent did, and there is no second attempt.
@MainActor
final class ReviewGate {
    static let firstSeenKey = "review.firstSeenAt"
    static let askedKey = "review.askedAt"
    static let waitBeforeFirstAsk: TimeInterval = 3 * 24 * 60 * 60

    private let defaults: UserDefaults
    private let now: @MainActor () -> Date

    init(defaults: UserDefaults = .standard, now: @escaping @MainActor () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    /// True at most once per install. The first call only starts the three
    /// days. Records the ask **before** answering yes, so two screens asking
    /// in the same moment cannot both be told yes. A clock behind the first
    /// sighting reads as "not yet", never as "ask again" (plan deviation L9:
    /// seconds since 1970).
    func consumeIfDue() -> Bool {
        let moment = now()
        let firstSeen = firstSeenAt(moment)
        guard defaults.object(forKey: Self.askedKey) == nil,
              moment >= firstSeen,
              moment.timeIntervalSince(firstSeen) >= Self.waitBeforeFirstAsk
        else { return false }
        defaults.set(moment.timeIntervalSince1970, forKey: Self.askedKey)
        return true
    }

    /// Written on the first call and never moved afterwards.
    private func firstSeenAt(_ moment: Date) -> Date {
        if let stored = defaults.object(forKey: Self.firstSeenKey) as? Double {
            return Date(timeIntervalSince1970: stored)
        }
        defaults.set(moment.timeIntervalSince1970, forKey: Self.firstSeenKey)
        return moment
    }
}
```

- [ ] **Step 4: P06's moment**

`NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift` — replace

```swift
    private let date: LocalDate?
    private let insights: any InsightsService

    init(childId: UUID, childName: String, date: LocalDate? = nil, insights: any InsightsService) {
        self.childId = childId
        self.childName = childName
        self.date = date
        self.insights = insights
    }
```

with

```swift
    private let date: LocalDate?
    private let insights: any InsightsService
    /// The session's; nil never asks (previews, tests that do not care).
    private let reviewGate: ReviewGate?

    init(
        childId: UUID,
        childName: String,
        date: LocalDate? = nil,
        insights: any InsightsService,
        reviewGate: ReviewGate? = nil
    ) {
        self.childId = childId
        self.childName = childName
        self.date = date
        self.insights = insights
        self.reviewGate = reviewGate
    }

    /// A summary is on screen: the moment worth asking at (spec D3).
    var hasSummary: Bool {
        if case .loaded = state { return true }
        return false
    }

    /// Asked by the screen when `hasSummary` turns true. Only then is the gate
    /// touched; it answers yes once per install (plan deviation L8).
    func reviewIsDue() -> Bool {
        guard hasSummary, let reviewGate else { return false }
        return reviewGate.consumeIfDue()
    }
```

`NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift` — add `import StoreKit` after `import NozirL10n`; add after `@Environment(\.l10n) private var l10n`:

```swift
    @Environment(\.requestReview) private var requestReview
```

and after `.refreshable { await model.retry() }`:

```swift
        // Spec D3: the parent has just been given what they opened the app
        // for. The gate allows this once per install; Apple decides the rest.
        .onChange(of: model.hasSummary, initial: true) { _, hasSummary in
            if hasSummary, model.reviewIsDue() {
                requestReview()
            }
        }
```

- [ ] **Step 5: The session's gate**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:
- after `private let privacyConfig: @MainActor () -> PrivacyConfig` add `private let reviewGate: ReviewGate`;
- in `init(…)`, after the `privacyConfig: @escaping @MainActor () -> PrivacyConfig,` parameter add `reviewGate: ReviewGate,`, and after `self.privacyConfig = privacyConfig` add `self.reviewGate = reviewGate`;
- replace `makeDailySummaryModel` with:

```swift
    /// P06: `date` nil is the latest finished day (Home); a link gives its day.
    /// Every P06 asks the session's one review gate.
    func makeDailySummaryModel(childId: UUID, childName: String, date: LocalDate? = nil) -> DailySummaryModel {
        DailySummaryModel(childId: childId, childName: childName, date: date, insights: insights, reviewGate: reviewGate)
    }
```

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — in `makeSignedInModel()`, after `privacyConfig: { [appModel] in appModel.privacyConfig },` add:

```swift
            reviewGate: ReviewGate(),
```

(The keys are per install and survive sign-out, as on Android.)

- [ ] **Step 6: Run the tests to see them pass, and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (9 new tests), then `** BUILD SUCCEEDED **` — `import StoreKit` with `@Environment(\.requestReview)` compiles for iOS 17 with no `Package.swift` change and no isolation warning. If the build says `cannot find 'requestReview' in scope`, the `import StoreKit` line is missing from `DailySummaryView.swift`.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/ReviewGate.swift NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Tests/NozirAppFeatureTests/ReviewGateTests.swift NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p16a: offer the review sheet once, over a loaded daily summary

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: Final check — whole suite, l10n, app build, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, l10n up to date (no new key), `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `git diff --stat e764c4c -- NozirKit/l10n NozirKit/Sources/NozirL10n NozirKit/Package.swift` is empty, and `git diff --stat e764c4c -- NozirKit/Sources/NozirAppFeature/Protection NozirKit/Sources/NozirAppFeature/Privacy NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Sources/NozirAppFeature/Screens/StatisticsView.swift NozirKit/Sources/NozirAppFeature/Screens/NotificationsView.swift` is empty.

- [ ] **Step 2: E2E (the user; simulator + the real backend + an Android child phone paired to the family)**

Write "yes" or what was seen against each line:

1. P16 → tap a "daily summary ready" row for a day **before yesterday** → "Xulosa" with a spinner for a moment, then P06 for that child with the subtitle naming **that** day (not the latest); Back → P16 (not "Xulosa"). Backend log: one `GET /v1/parent/summaries/{id}`, then `GET …/summaries/daily?date=<that day>`.
2. Tap a "weekly report ready" row from an earlier week → P07 opens on **that** week (header range matches), ‹ › and swipes still work, Back → P16. A row from more than a year ago (or set one up by hand) → P07 on this week.
3. A summary row whose summary was deleted (or whose child was removed: remove the child on Android, then tap its old row) → "Bu xulosa endi mavjud emas · Bola olib tashlangan boʻlishi mumkin…", no crash; Back → P16.
4. Airplane mode, tap a summary row → error state with "Qayta urinish"; back online, tap it → the summary opens. On "3G" (Network Link Conditioner) tap a row and Back at once → nothing is pushed onto P16 afterwards.
5. Home → a child's card → P06 still opens the **latest** day; "Haftalik hisobot" from it → this week. Statistics tab → this week, child switcher works. Home with a dated P06 open → its "Haftalik hisobot" → this week (plan deviation L7).
6. Review: fresh install (or delete the app), sign in, open P06 with a summary → no sheet. Set the Mac/simulator clock 3 days ahead (or put `review.firstSeenAt` back by 3 days with `xcrun simctl spawn booted defaults write <bundle id> review.firstSeenAt -float <seconds>`), open P06 again → the system "Enjoying Nozir?" sheet (on a simulator / debug build it shows every time Apple allows; on TestFlight it never shows — spec §7). Open P06 again, relaunch, open P06 → no second sheet. P06 showing "not ready" or an error → never a sheet.
7. Move the clock back a week after step 6's first P06 (before the three days) → no sheet; move it forward again past three days from the first P06 → the sheet once.
8. VoiceOver on "Xulosa": the title reads "Xulosa"; the gone state reads its title and body; the retry is a button. Three languages and both themes: P16a's texts correct ("Сводка" / "Summary"); screenshots (Cmd+S).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.

## Open questions (ruled while planning)

- **Q1 — the id key.** The task brief assumed the iOS model decodes `id`; it already maps `id` to the wire's `summaryId` (`InsightModels.swift:183`, `case id = "summaryId"`), and the daily, weekly and by-id responses all use the same `InsightSummaryResponse` (`InsightDtos.kt:102`). Ruling: no change; Task 1's by-id test pins `summaryId`.
- **Q2 — the plan error.** Spec §3 left the code open. `SummaryQueryService.byId` reads the stored row and serves it through `daily` / `weekly`, which only check the plan when they must *write* a summary, so a link to a stored summary never meets the plan gate. Ruling: no special case; a 403 `SUBSCRIPTION_REQUIRED` would read as `UserMessage.subscriptionRequired` in the error state (plan deviation L3).
- **Q3 — the family list not loaded.** Spec says "ism topilmasa → gone". Ruling: ask the list once first (plan deviation L1) — otherwise a failed `start()` or a child added on another phone would show "this summary no longer exists" for a summary that exists.
- **Q4 — superseded P16 rulings.** P16 plan deviations N4 (no name → nothing) and N11 (open by the row's child and type) no longer apply: every `nozir://summary/{id}` row goes to P16a, which names the child from the family list.
