# Nozir iOS — P19: Subscription (Nozir PRO) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parent sees the family's plan on P19 (trial, grace, expired, or "Nozir PRO faol"), and the family owner picks the yearly or monthly plan, taps "Click orqali toʻlash", pays on Click's page in Safari, and P19 turns into "Nozir PRO faol" once the server has been told by Click — reached from the Profile row "Obuna · Nozir PRO" and from every plan-lock card with one tap.

**Architecture:** `NozirNetworking` learns to send an `Idempotency-Key`. `NozirFamily` reads the plan's state out of the subscription answer it already fetches (`Subscription.state`, Android `SubscriptionMapper`), and gains the plan and checkout types plus a `BillingService` / `BillingApi` for `GET …/plans` and `POST …/checkout`. In `NozirAppFeature`, `SubscriptionMath` / `SubscriptionTexts` hold the pure Android arithmetic and words, `SubscriptionModel` (`@MainActor @Observable`) loads plans then state, starts one checkout at a time, and watches for the payment (5 s × 60, injected sleep), and `SubscriptionView` draws it and opens the page with `openURL`. `NozirDesignSystem` gains the `selected` / `good` / `info` card tones and a badge. `SignedInView` gets the steps, `ProfileView` the row, `LocationLockCard` / `FrozenChildCard` the "PRO rejaga oʻtish" button.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; no third-party libraries; no StoreKit.

**Spec:** `docs/superpowers/specs/2026-10-08-nozir-ios-subscription-design.md` (commit `0370737`). Supporting fact sheet (outside git): `.superpowers/p19-analysis.md`. The backend contract (spec §3) is live and unchanged.

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries. **No StoreKit / IAP** (spec §1, D5).
- `GET /v1/parent/subscription` → `{familyId, tier: FREE|PRO, status: ACTIVE|GRACE|EXPIRED|CANCELLED, state: FREE|TRIAL|PRO|GRACE, planCode?, channel?, currentPeriodEnd?, trialEndsAt?, graceUntil?, autoRenew, entitlements, quotas, activeChildId?}` — any parent. Stays on `FamilyService.subscription()`; it is not duplicated.
- `GET /v1/parent/subscription/plans` → `[{code, tier, periodMonths, priceMinorUnits (tiyin), currency, features: [{key, text}], availableChannels, plannedChannels}]`; channels `PAYME, CLICK, UZUM, CARD, GOOGLE_PLAY`.
- `POST /v1/parent/subscription/checkout` body `{planCode, channel}` + header `Idempotency-Key: <UUID>` (required; without it `400 MISSING_IDEMPOTENCY_KEY`) → `201 {orderId, checkoutUrl, channel, expiresAt}`. OWNER only (`403 FORBIDDEN`); channel off → `503 UPSTREAM_UNAVAILABLE`. **A fresh key per tap; never retried automatically** (a 401 token refresh repeats the same request, key included — the server replays).
- State (spec §4, Android mapper): `state == TRIAL` → trial(`trialEndsAt`); `state == GRACE` (or legacy `tier == PRO && status == GRACE`) → grace(`planCode`, `currentPeriodEnd`, `graceUntil`); `state == PRO` (or legacy `tier == PRO && status ∈ {ACTIVE, GRACE}`) → active; else `planCode != nil` → expired; else free. A missing or unknown `state` uses the legacy rules. An optional field that cannot be read is absent.
- Plans: `tier != PRO`, `currency != UZS`, `periodMonths ∉ {1, 12}` → dropped. Price = `priceMinorUnits / 100` soʻm (integer division). Unknown channel → dropped. Features and planned channels from the yearly plan, else the monthly one.
- Arithmetic exactly as Android: saving % = `(saved * 100 + twelveMonths / 2) / twelveMonths` (nil when `twelveMonths <= 0` or `saved <= 0`); monthly equivalent = `((yearly + 6) / 12 + 50) / 100 * 100`; grouping = digits in threes joined by U+00A0 (no-break space), never the locale's separator.
- Pay channel: `CLICK` if the selected plan's `availableChannels` has it, else the first available, else none (button disabled + "not ready" + planned channel labels).
- A blank `checkoutUrl`, or one that is not `http`/`https` with a host → "unreadable answer"; nothing is opened.
- The page opens in Safari via `openURL` with the `accepted` callback; not opened → `subscriptionCheckoutNotOpened`. No deep link, no `return_url`, no order-status endpoint.
- Watch: 60 × {wait 5 s → read the state → stop when `active`}; a trial does not stop it; after 60 it stops silently and "kutilmoqda" stays. Also: "Toʻlovni tekshirish", every entry (`.task`), and the app coming to the foreground (`scenePhase == .active`) each read once. Leaving the screen (`onDisappear`) cancels the watch.
- Guardian (`me().role != "OWNER"`): no pay button; the note `iosSubscriptionOwnerOnly` instead. A role that cannot be read counts as owner (the server still refuses).
- User-facing text only from `L10n`, errors only through `UserMessage`; the server's `message` is never shown. **Exactly one new l10n key**: `ios_subscription_owner_only` (uz/ru/en, spec §7). Never edit `L10n.generated.swift` by hand.
- Tests and previews never hard-code a price: prices come from the fakes' plan fixtures.
- Out of scope: StoreKit, App Store review, deep link / `return_url`, order status, backend changes, Payme/Uzum/card checkout.
- Tests: Swift Testing; scripted actor fakes (`FakeBilling`, `FakeFamily`), `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`.
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| S1 | `SubscriptionState.none` | `.free` (doc: Android `None`) | The model holds `SubscriptionState?`; a case named `none` collides with `Optional.none` in every `== .none` / `case .none` |
| S2 | `HomeStep.subscription` "(child page and daily limit on the Home stack)" | `HomeStep`, `ProfileStep`, `LocationStep` **and** `RuleScreen.subscription` | `ChildDetailsView` is also on the Profile stack (`ProfileStep.child`); the daily limit lives in `RulesHubView`, which is on both Home (`.rules`) and Profile (`.rules`, `.childRules`); `LocationTrackingView` is also opened from the rules hub (`RuleScreen.locationTracking`). `RuleScreen.subscription` lets P09 and its tracking screen push onto whichever stack they are in |
| S3 | Load: plans, then state | `me()` runs in parallel with the plans; then the state | The role must be known before the footer draws, or a guardian sees the pay button flash. The plans-then-state order is kept |
| S4 | Plans fail, state succeeds | The plans' error stays (error state + retry) | Android's `applyState` success clears the message and shows "Rejalar hozir koʻrsatilmadi" for a failed request; spec §6 says "Rejalar yo'q: xabar → xato holati + qayta urinish" |
| S5 | `isOwner`: `role == "OWNER"`, unreadable → true | `me()` failed → keep (starts `true`); `role == nil` → `true`; `"OWNER"` → `true`; anything else → `false` | "Unreadable" read as both a failed call and an absent field |
| S6 | Tones `selected`, `good`, `info` | Also: `LocationLockCard` uses `.info` (Android `PlanLockCard` is INFO); `FrozenChildCard` keeps `.attention` and its badge | The frozen card already carries the attention dot and badge on iOS |
| S7 | §8 "Navigation: Profile row and lock cards add the `subscription` step" (test) | Covered by the `SignedInModel` factory test, the app build and E2E | Views have no unit tests in this repo (previous plans verify navigation the same way) |

## Review Focus

1. **A guardian opens P19** (or the role is GUARDIAN but plans and state load fine) — the plans are shown, no pay button, "Obunani faqat oila egasi sotib oladi." in its place, and `pay()` sends nothing → Task 6 `aGuardianIsNotOfferedThePayment`.
2. **"Click orqali toʻlash" tapped twice quickly** — one `POST /checkout`, one page → Task 6 `twoTapsStartOneCheckout`; and each real tap is its own key → Task 3 `aCheckoutCarriesAFreshIdempotencyKeyEveryTime`.
3. **The parent pays in Safari and switches back** (iOS suspends the watch in the background) — P19 reads at once on `scenePhase == .active` and turns "Nozir PRO faol"; a second check while one is in flight is dropped → Task 6 `comingBackToTheAppChecksAtOnce`.
4. **The page cannot be opened, or the server gives a page that is not a web page** (blank, `javascript:`, no scheme) — nothing opens, the parent is told, "kutilmoqda" is not claimed, the watch stops → Task 3 `aCheckoutWithoutAPageToOpenIsUnreadable`, Task 6 `anUnreadableCheckoutOpensNothing`, `aPageThatDidNotOpenSaysSoAndStopsWatching`.
5. **A newer server** (an unknown `state` word, a channel or period this app does not know, a field of the wrong type) — legacy rules decide the state, the unknown plan/channel is left out, the rest of the screen stands → Task 2 `aStateThisAppDoesNotKnowFallsBackToTierAndStatus`, `unreadableOptionalFieldsAreAbsent`; Task 3 `plansAreReadAsSomAndOnlyThoseTheAppCanPrice`, `aPlanTheAppCannotReadIsLeftOut`.

---

## File map

**New:**
- `NozirKit/Sources/NozirFamily/SubscriptionState.swift` — `SubscriptionState` and its reading rule.
- `NozirKit/Sources/NozirFamily/BillingModels.swift` — `BillingPeriod`, `PaymentChannel`, `SubscriptionPlan`, `SubscriptionCheckout`, `RawPlan`.
- `NozirKit/Sources/NozirFamily/BillingService.swift`, `BillingApi.swift`.
- `NozirKit/Tests/NozirFamilyTests/SubscriptionStateTests.swift`, `BillingApiTests.swift`.
- `NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionTexts.swift` (`SubscriptionMath`, `SubscriptionTexts`), `SubscriptionModel.swift`.
- `NozirKit/Sources/NozirAppFeature/Screens/SubscriptionView.swift`.
- `NozirKit/Sources/NozirDesignSystem/Components/NozirBadge.swift`.
- `NozirKit/Tests/NozirAppFeatureTests/FakeBilling.swift`, `SubscriptionTextsTests.swift`, `SubscriptionModelTests.swift`.
- `NozirKit/Tests/NozirDesignSystemTests/CardToneTests.swift`.

**Modified:** `NozirNetworking/{ApiRequest,ApiClient}.swift`; `NozirFamily/AccountModels.swift` (`Subscription`); `NozirDesignSystem/{NozirColor.swift,Components/NozirCard.swift,Components/DesignSystemGallery.swift}`; `NozirAppFeature/{SignedInModel,AppEnvironment}.swift`; `NozirAppFeature/Screens/{SignedInView,ProfileView,ChildDetailsView,FrozenChildCard,LocationLockCard,DailyLimitSection,RulesHubView,LocationView,SafeZoneView,LocationTrackingView}.swift`; `NozirKit/l10n/ios/values{,-ru,-en}/strings.xml` and the generated `NozirL10n/L10n.generated.swift`; tests `NozirNetworkingTests/{ApiRequestTests,ApiClientTests}.swift`, `NozirFamilyTests/FamilyFixtures.swift`, `NozirAppFeatureTests/SignedInModelTests.swift`.

No `Package.swift` change: everything lives in existing targets (`Subscription/` is a new folder inside the `NozirAppFeature` target, picked up automatically). `FakeFamily` needs no change: `Subscription(activeChildId:)` keeps compiling (the new `state` parameter is defaulted) and its `subscription` / `me` queues and `subscriptionGate` already exist.

## Getting started

Branch `subscription` (spec commit `0370737`) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirNetworkingTests`, `NozirFamilyTests`, `NozirDesignSystemTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

Line numbers are as on the branch at spec commit `0370737`. Once an earlier task or step has edited the same file (Tasks 7 and 8 both edit `SignedInView.swift`), find the place by the code quoted next to the number.

---
### Task 1: `Idempotency-Key` on `ApiRequest`

**Files:**
- Modify: `NozirKit/Sources/NozirNetworking/ApiRequest.swift:21-41` (field and init)
- Modify: `NozirKit/Sources/NozirNetworking/ApiClient.swift:142-144` (header, after `If-Match`)
- Modify: `NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift` (new tests before the suite's closing `}` at line 53)
- Modify: `NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift` (new test after `theRetryRepeatsTheSameMethodAndBody()`, lines 177-187)

**Interfaces:**
- Consumes: `ApiRequest.post(_:json:)`, `ApiClient.makeURLRequest(_:bearer:)` (internal, `ApiClient.swift:114`), `FakeTransport`, `.error(_:code:)`, `.ok(_:)`, `FakeTokens`, `Echo`, `base`, `identity` (private to `ApiClientTests.swift`), `client()` (private to `ApiRequestTests.swift`).
- Produces: `ApiRequest.idempotencyKey: UUID?` (public var, default nil) and `ApiRequest.init(method:path:query:body:requiresAuth:timeout:ifMatch:idempotencyKey:)`; `makeURLRequest` writes `Idempotency-Key: <uuid, lower case>` when set.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift` — add inside `ApiRequestTests`, before its closing `}`:

```swift
    // P19: the checkout is refused without a key (400 MISSING_IDEMPOTENCY_KEY).
    @Test func aKeyedRequestCarriesItsIdempotencyKey() throws {
        let key = try #require(UUID(uuidString: "6F1B2A0C-1D01-4D8B-9A55-0B0E2A526A2F"))
        var request = try ApiRequest.post("/v1/parent/subscription/checkout", json: ["planCode": "pro_yearly"])
        request.idempotencyKey = key

        let urlRequest = client().makeURLRequest(request, bearer: "acc")

        #expect(urlRequest.value(forHTTPHeaderField: "Idempotency-Key") == "6f1b2a0c-1d01-4d8b-9a55-0b0e2a526a2f")
        #expect(urlRequest.jsonBody == ["planCode": "pro_yearly"])
    }

    @Test func anOrdinaryRequestHasNoIdempotencyKey() {
        let request = ApiRequest(method: .get, path: "/v1/parent/subscription")

        let urlRequest = client().makeURLRequest(request, bearer: "acc")

        #expect(request.idempotencyKey == nil)
        #expect(urlRequest.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }
```

`NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift` — add inside `ApiClientTests`, after `theRetryRepeatsTheSameMethodAndBody()`:

```swift
    // P19: a refreshed retry is the same tap, so it carries the same key and
    // the server answers it with the order it already made.
    @Test func theRetryAfterARefreshRepeatsTheSameIdempotencyKey() async throws {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .ok(#"{"value":"after"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))
        var request = try ApiRequest.post("/v1/parent/subscription/checkout", json: ["planCode": "pro_yearly"])
        request.idempotencyKey = UUID()

        _ = try await client.send(request, as: Echo.self)

        let requests = await transport.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first?.value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == first)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirNetworkingTests 170`
Expected: FAIL — `value of type 'ApiRequest' has no member 'idempotencyKey'`.

- [ ] **Step 3: The field**

In `NozirKit/Sources/NozirNetworking/ApiRequest.swift`, replace lines 21-41 (the `ifMatch` field through the end of `init`) with:

```swift
    /// The entity tag a write was made against, e.g. `"7"` with the quotes
    /// (`IfMatchVersion.kt`). Every rules write needs one.
    public var ifMatch: String?
    /// `Idempotency-Key`: the server answers a repeat of this key with the
    /// answer it gave the first time. The caller makes one per tap; nil sends none.
    public var idempotencyKey: UUID?

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil,
        ifMatch: String? = nil,
        idempotencyKey: UUID? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.timeout = timeout
        self.ifMatch = ifMatch
        self.idempotencyKey = idempotencyKey
    }
```

- [ ] **Step 4: The header**

In `NozirKit/Sources/NozirNetworking/ApiClient.swift`, after the `If-Match` block (lines 142-144):

```swift
        if let ifMatch = request.ifMatch {
            urlRequest.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        }
```

add:

```swift
        // Lower case, as Android's `UUID.toString()` writes it.
        if let key = request.idempotencyKey {
            urlRequest.setValue(key.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key")
        }
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirNetworkingTests 170`
Expected: `** TEST SUCCEEDED **`, the 3 new tests among them.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirNetworking/ApiRequest.swift NozirKit/Sources/NozirNetworking/ApiClient.swift NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: a request can carry an Idempotency-Key

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: The plan's state, read from the subscription answer

**Files:**
- Create: `NozirKit/Sources/NozirFamily/SubscriptionState.swift`
- Modify: `NozirKit/Sources/NozirFamily/AccountModels.swift:61-74` (`Subscription`)
- Modify: `NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift` (append after line 39)
- Create: `NozirKit/Tests/NozirFamilyTests/SubscriptionStateTests.swift`

**Interfaces:**
- Consumes: `familyApi(_:)`, `FakeTransport.Reply.ok(_:)` (`FamilyFixtures.swift`, `HTTP.swift`), `FamilyApi.subscription()` / `chooseActiveChild(_:)` (`FamilyApi.swift:131-140`, unchanged), `NozirJSON.decoder()` (RFC 3339 dates, via `ApiClient`).
- Produces:
  - `public enum SubscriptionState: Equatable, Sendable { case free; case trial(endsAt: Date?); case active(planCode: String?, endsAt: Date?, autoRenew: Bool); case grace(planCode: String?, endedAt: Date?, until: Date?); case expired(planCode: String, endedAt: Date?); var isActive: Bool }`.
  - `Subscription.state: SubscriptionState`; `Subscription.init(activeChildId: UUID?, state: SubscriptionState = .free)`; `isChildActive(_:)` unchanged.
  - Test fixtures (NozirFamilyTests only): `moment(_:) -> Date`, `subscriptionJSON(tier:status:state:planCode:currentPeriodEnd:trialEndsAt:graceUntil:autoRenew:)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift` — append at the end of the file:

```swift
/// An instant written the way the backend writes it, whole seconds.
func moment(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// `SubscriptionResponse` as the backend writes it; a nil writes `null`.
/// `state` and `autoRenew` are raw JSON so a test can send what a newer or
/// broken server might.
func subscriptionJSON(
    tier: String = "FREE",
    status: String = "ACTIVE",
    state: String = #""FREE""#,
    planCode: String? = nil,
    currentPeriodEnd: String? = nil,
    trialEndsAt: String? = nil,
    graceUntil: String? = nil,
    autoRenew: String = "false"
) -> String {
    func field(_ value: String?) -> String {
        value.map { "\"\($0)\"" } ?? "null"
    }
    return #"{"familyId":"7d1e2a52-6a2f-4d8b-9a55-6f1b2a0c1d09","tier":"\#(tier)","status":"\#(status)","state":\#(state),"planCode":\#(field(planCode)),"channel":null,"currentPeriodEnd":\#(field(currentPeriodEnd)),"trialEndsAt":\#(field(trialEndsAt)),"graceUntil":\#(field(graceUntil)),"autoRenew":\#(autoRenew),"entitlements":[],"quotas":{"CHILDREN":1},"activeChildId":null}"#
}
```

`NozirKit/Tests/NozirFamilyTests/SubscriptionStateTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

/// One subscription answer, read the way every screen reads it.
private func state(_ body: String) async throws -> SubscriptionState {
    let (api, _) = familyApi([.ok(body)])
    return try await api.subscription().state
}

@Suite struct SubscriptionStateTests {
    // Spec §4: the server's own word decides.
    @Test func eachStateTheServerNamesIsRead() async throws {
        #expect(try await state(subscriptionJSON(state: #""TRIAL""#, trialEndsAt: "2026-10-15T00:00:00Z"))
            == .trial(endsAt: moment("2026-10-15T00:00:00Z")))
        #expect(try await state(subscriptionJSON(state: #""TRIAL""#)) == .trial(endsAt: nil))
        #expect(try await state(subscriptionJSON(
            tier: "PRO", status: "GRACE", state: #""GRACE""#, planCode: "pro_monthly",
            currentPeriodEnd: "2026-10-07T00:00:00Z", graceUntil: "2026-10-10T00:00:00Z"
        )) == .grace(planCode: "pro_monthly", endedAt: moment("2026-10-07T00:00:00Z"), until: moment("2026-10-10T00:00:00Z")))
        #expect(try await state(subscriptionJSON(
            tier: "PRO", state: #""PRO""#, planCode: "pro_yearly", currentPeriodEnd: "2027-10-08T00:00:00Z"
        )) == .active(planCode: "pro_yearly", endsAt: moment("2027-10-08T00:00:00Z"), autoRenew: false))
        #expect(try await state(subscriptionJSON()) == .free)
        // The server never says EXPIRED as a state: FREE with a plan code is a lapsed plan.
        #expect(try await state(subscriptionJSON(status: "EXPIRED", planCode: "pro_monthly", currentPeriodEnd: "2026-09-01T00:00:00Z"))
            == .expired(planCode: "pro_monthly", endedAt: moment("2026-09-01T00:00:00Z")))
    }

    // Spec §4: a server without `state` is read from tier and status (Android's legacy rule).
    @Test func anOlderServerWithoutStateIsReadFromTierAndStatus() async throws {
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "GRACE", state: "null", planCode: "pro_yearly"))
            == .grace(planCode: "pro_yearly", endedAt: nil, until: nil))
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: "null", planCode: "pro_yearly", autoRenew: "true"))
            == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: true))
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "EXPIRED", state: "null", planCode: "pro_yearly"))
            == .expired(planCode: "pro_yearly", endedAt: nil))
        #expect(try await state(subscriptionJSON(state: "null")) == .free)
    }

    // Review Focus 5: a word this app does not know is no word at all.
    @Test func aStateThisAppDoesNotKnowFallsBackToTierAndStatus() async throws {
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: #""FAMILY""#, planCode: "pro_yearly"))
            == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: false))
        #expect(try await state(subscriptionJSON(state: #""FAMILY""#)) == .free)
        #expect(try await state(subscriptionJSON(tier: "PRO", status: "ACTIVE", state: "42", planCode: "pro_yearly")).isActive)
    }

    // Review Focus 5: an optional field of the wrong type is absent, never a failed screen.
    @Test func unreadableOptionalFieldsAreAbsent() async throws {
        let body = #"{"tier":"PRO","status":"ACTIVE","state":"PRO","planCode":"pro_yearly","currentPeriodEnd":"soon","autoRenew":"yes","activeChildId":"not-a-uuid"}"#
        let (api, _) = familyApi([.ok(body)])

        let subscription = try await api.subscription()

        #expect(subscription.state == .active(planCode: "pro_yearly", endsAt: nil, autoRenew: false))
        #expect(subscription.activeChildId == nil)
        #expect(subscription.isChildActive(aliId))
    }

    // 2a callers are untouched: the active child, and a body with nothing else in it.
    @Test func theActiveChildIsStillReadAndABareBodyIsFree() async throws {
        let (api, _) = familyApi([
            .ok(subscriptionJSON().replacingOccurrences(of: #""activeChildId":null"#, with: #""activeChildId":"\#(aliId.uuidString.lowercased())""#)),
            .ok(#"{"activeChildId":null}"#),
        ])

        let free = try await api.subscription()
        #expect(free.activeChildId == aliId)
        #expect(!free.isChildActive(UUID()))

        let bare = try await api.chooseActiveChild(aliId)
        #expect(bare.state == .free)
        #expect(bare.activeChildId == nil)
        #expect(Subscription(activeChildId: nil).state == .free)
    }

    @Test func onlyAPaidPeriodIsActive() {
        #expect(SubscriptionState.active(planCode: nil, endsAt: nil, autoRenew: false).isActive)
        #expect(!SubscriptionState.free.isActive)
        #expect(!SubscriptionState.trial(endsAt: nil).isActive)
        #expect(!SubscriptionState.grace(planCode: "pro_yearly", endedAt: nil, until: nil).isActive)
        #expect(!SubscriptionState.expired(planCode: "pro_yearly", endedAt: nil).isActive)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`
Expected: FAIL — `cannot find 'SubscriptionState' in scope`, `value of type 'Subscription' has no member 'state'`.

- [ ] **Step 3: `SubscriptionState`**

`NozirKit/Sources/NozirFamily/SubscriptionState.swift`:

```swift
import Foundation

/// What P19 draws about the family's plan (Android `SubscriptionState`).
public enum SubscriptionState: Equatable, Sendable {
    /// Never paid, no trial running (Android `None`).
    case free
    case trial(endsAt: Date?)
    /// Paid and running. `autoRenew` is always false with Click today.
    case active(planCode: String?, endsAt: Date?, autoRenew: Bool)
    /// The paid period ended; paying before `until` continues it from that day.
    case grace(planCode: String?, endedAt: Date?, until: Date?)
    /// A plan was held and lapsed: the server says FREE with a plan code.
    case expired(planCode: String, endedAt: Date?)

    /// Only money counts: a trial is not a payment landing.
    public var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    /// Android `SubscriptionMapper.toSubscriptionState`. `state` is the server's
    /// own word and wins; a missing or unknown word falls back to the older
    /// `tier`/`status` pair, so a server this build has not met still reads.
    static func read(
        tier: String?,
        status: String?,
        state: String?,
        planCode: String?,
        currentPeriodEnd: Date?,
        trialEndsAt: Date?,
        graceUntil: Date?,
        autoRenew: Bool
    ) -> SubscriptionState {
        let word = state.flatMap { knownStates.contains($0) ? $0 : nil }
        let isLegacyPaid = word == nil && tier == "PRO"
        if word == "TRIAL" {
            return .trial(endsAt: trialEndsAt)
        }
        if word == "GRACE" || (isLegacyPaid && status == "GRACE") {
            return .grace(planCode: planCode, endedAt: currentPeriodEnd, until: graceUntil)
        }
        if word == "PRO" || (isLegacyPaid && (status == "ACTIVE" || status == "GRACE")) {
            return .active(planCode: planCode, endsAt: currentPeriodEnd, autoRenew: autoRenew)
        }
        if let planCode {
            return .expired(planCode: planCode, endedAt: currentPeriodEnd)
        }
        return .free
    }

    /// Backend `SubscriptionState`.
    private static let knownStates: Set<String> = ["FREE", "TRIAL", "PRO", "GRACE"]
}
```

- [ ] **Step 4: `Subscription`**

In `NozirKit/Sources/NozirFamily/AccountModels.swift`, replace `struct Subscription` (lines 61-74) with:

```swift
/// `SubscriptionResponse`: the child a free family keeps active (2a) and the
/// plan's state (P19). Every field is read defensively: one this app cannot
/// read is absent, never a failed screen.
public struct Subscription: Decodable, Equatable, Sendable {
    /// The child a free family keeps fully active; nil while every child is.
    public let activeChildId: UUID?
    public let state: SubscriptionState

    public init(activeChildId: UUID?, state: SubscriptionState = .free) {
        self.activeChildId = activeChildId
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case activeChildId, tier, status, state, planCode, currentPeriodEnd, trialEndsAt, graceUntil, autoRenew
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        activeChildId = try? container.decodeIfPresent(UUID.self, forKey: .activeChildId)
        state = SubscriptionState.read(
            tier: try? container.decodeIfPresent(String.self, forKey: .tier),
            status: try? container.decodeIfPresent(String.self, forKey: .status),
            state: try? container.decodeIfPresent(String.self, forKey: .state),
            planCode: try? container.decodeIfPresent(String.self, forKey: .planCode),
            currentPeriodEnd: try? container.decodeIfPresent(Date.self, forKey: .currentPeriodEnd),
            trialEndsAt: try? container.decodeIfPresent(Date.self, forKey: .trialEndsAt),
            graceUntil: try? container.decodeIfPresent(Date.self, forKey: .graceUntil),
            autoRenew: (try? container.decodeIfPresent(Bool.self, forKey: .autoRenew)) ?? false
        )
    }

    /// False means frozen: the phone keeps its last rules, but they cannot change.
    public func isChildActive(_ id: UUID) -> Bool {
        activeChildId == nil || activeChildId == id
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run, one at a time: `bash .superpowers/run.sh NozirFamilyTests 170`, then `bash .superpowers/run.sh NozirAppFeatureTests 170` (every `Subscription(activeChildId:)` in `FakeFamily` callers still compiles).
Expected: `** TEST SUCCEEDED **` both times; the existing `theSubscriptionSaysWhichChildIsActive` still passes.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirFamily/SubscriptionState.swift NozirKit/Sources/NozirFamily/AccountModels.swift NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift NozirKit/Tests/NozirFamilyTests/SubscriptionStateTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: the family's plan state, read from the subscription answer

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: Plans and checkout — `BillingService` and `BillingApi`

**Files:**
- Create: `NozirKit/Sources/NozirFamily/BillingModels.swift`
- Create: `NozirKit/Sources/NozirFamily/BillingService.swift`
- Create: `NozirKit/Sources/NozirFamily/BillingApi.swift`
- Modify: `NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift` (append after Task 2's `subscriptionJSON`)
- Create: `NozirKit/Tests/NozirFamilyTests/BillingApiTests.swift`

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiRequest(method:path:)`, `ApiRequest.post(_:json:)`, `ApiRequest.idempotencyKey` (Task 1), `ApiFailure` (`.decoding`, `.code`), `ApiErrorCode.forbidden` / `.upstreamUnavailable` (`ApiErrorCode.swift:26,29`), `FixedToken`, `FakeTransport`, `URLRequest.jsonBody` (`HTTP.swift`).
- Produces:
  - `public enum BillingPeriod: Int, CaseIterable, Sendable { case monthly = 1, yearly = 12; var months: Int }`.
  - `public enum PaymentChannel: String, CaseIterable, Sendable, Encodable { case payme = "PAYME", click = "CLICK", uzum = "UZUM", card = "CARD", googlePlay = "GOOGLE_PLAY" }`.
  - `public struct SubscriptionPlan: Equatable, Sendable { code: String; period: BillingPeriod; priceSom: Int64; features: [String]; availableChannels: [PaymentChannel]; plannedChannels: [PaymentChannel]; init(code:period:priceSom:features:availableChannels:plannedChannels:) }`.
  - `public struct SubscriptionCheckout: Decodable, Equatable, Sendable { orderId: String; checkoutUrl: URL; init(orderId:checkoutUrl:) }` — decoding throws when there is no `http`/`https` page with a host.
  - `public protocol BillingService: Sendable { func plans() async throws -> [SubscriptionPlan]; func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout }`.
  - `public struct BillingApi: BillingService { public init(client: ApiClient) }`.
  - Test fixtures (NozirFamilyTests only): `billingApi(_:)`, `planJSON(code:tier:periodMonths:priceMinorUnits:currency:features:available:planned:)`, `checkoutJSON(_:)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift` — append at the end of the file:

```swift
func billingApi(_ replies: [FakeTransport.Reply]) -> (BillingApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (BillingApi(client: client), transport)
}

/// `PlanResponse` as the backend writes it. `periodMonths` and
/// `priceMinorUnits` are raw JSON so a test can send a wrong type.
func planJSON(
    code: String = "pro_yearly",
    tier: String = "PRO",
    periodMonths: String = "12",
    priceMinorUnits: String = "750000",
    currency: String = "UZS",
    features: [String] = ["Bolaning joylashuvi"],
    available: [String] = ["CLICK"],
    planned: [String] = ["PAYME", "CLICK", "UZUM", "CARD"]
) -> String {
    let featureList = features.map { #"{"key":"feature","text":"\#($0)"}"# }.joined(separator: ",")
    func quoted(_ values: [String]) -> String {
        values.map { "\"\($0)\"" }.joined(separator: ",")
    }
    return #"{"code":"\#(code)","tier":"\#(tier)","periodMonths":\#(periodMonths),"priceMinorUnits":\#(priceMinorUnits),"currency":"\#(currency)","features":[\#(featureList)],"availableChannels":[\#(quoted(available))],"plannedChannels":[\#(quoted(planned))]}"#
}

/// `CheckoutResponse` with the given page.
func checkoutJSON(_ url: String) -> String {
    #"{"orderId":"5f2c1a0e-0000-4000-8000-000000000001","checkoutUrl":"\#(url)","channel":"CLICK","expiresAt":"2026-10-08T12:00:00Z"}"#
}
```

`NozirKit/Tests/NozirFamilyTests/BillingApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

private let clickPage = "https://my.click.uz/services/pay?service_id=1&amount=7500"

@Suite struct BillingApiTests {
    // Spec §4 and Review Focus 5: only a plan the app can price honestly is offered.
    @Test func plansAreReadAsSomAndOnlyThoseTheAppCanPrice() async throws {
        let body = "[" + [
            planJSON(),
            planJSON(
                code: "pro_monthly", periodMonths: "1", priceMinorUnits: "100099",
                features: ["Bolaning joylashuvi", "Xavfsiz hududlar"],
                available: ["CLICK", "APPLE_PAY"], planned: ["PAYME", "SOMETHING_NEW"]
            ),
            planJSON(code: "free", tier: "FREE", priceMinorUnits: "0"),
            planJSON(code: "usd", currency: "USD"),
            planJSON(code: "half_year", periodMonths: "6"),
        ].joined(separator: ",") + "]"
        let (api, transport) = billingApi([.ok(body)])

        let plans = try await api.plans()

        #expect(plans == [
            SubscriptionPlan(
                code: "pro_yearly", period: .yearly, priceSom: 7_500,
                features: ["Bolaning joylashuvi"],
                availableChannels: [.click], plannedChannels: [.payme, .click, .uzum, .card]
            ),
            // Tiyin are cut, never rounded (Android `minorUnits / 100`).
            SubscriptionPlan(
                code: "pro_monthly", period: .monthly, priceSom: 1_000,
                features: ["Bolaning joylashuvi", "Xavfsiz hududlar"],
                availableChannels: [.click], plannedChannels: [.payme]
            ),
        ])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/subscription/plans")
    }

    // Review Focus 5: one plan the app cannot read never blanks the others.
    @Test func aPlanTheAppCannotReadIsLeftOut() async throws {
        let body = "[" + [
            planJSON(code: "broken", periodMonths: #""12""#),
            planJSON(code: "no_price", priceMinorUnits: "null"),
            planJSON(features: ["", "Bolaning joylashuvi"]),
        ].joined(separator: ",") + "]"
        let (api, _) = billingApi([.ok(body)])

        let plans = try await api.plans()

        #expect(plans.map(\.code) == ["pro_yearly"])
        #expect(plans.first?.features == ["Bolaning joylashuvi"])
    }

    // Global Constraints and Review Focus 2: one key per tap, never reused.
    @Test func aCheckoutCarriesAFreshIdempotencyKeyEveryTime() async throws {
        let (api, transport) = billingApi([
            .init(status: 201, body: checkoutJSON(clickPage)),
            .init(status: 201, body: checkoutJSON(clickPage)),
        ])

        let checkout = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
        _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)

        #expect(checkout == SubscriptionCheckout(orderId: "5f2c1a0e-0000-4000-8000-000000000001", checkoutUrl: URL(string: clickPage)!))
        let requests = await transport.requests
        #expect(requests.count == 2)
        let first = try #require(requests.first)
        #expect(first.httpMethod == "POST")
        #expect(first.url?.path == "/v1/parent/subscription/checkout")
        #expect(first.jsonBody == ["planCode": "pro_yearly", "channel": "CLICK"])
        let keys = requests.compactMap { $0.value(forHTTPHeaderField: "Idempotency-Key") }
        #expect(keys.count == 2)
        #expect(keys.allSatisfy { UUID(uuidString: $0) != nil && $0 == $0.lowercased() })
        #expect(keys[0] != keys[1])
    }

    // Spec §4 and Review Focus 4: no web page, nothing to open.
    @Test(arguments: ["", "   ", "my.click.uz/services/pay", "javascript:alert(1)", "ftp://my.click.uz/pay", "https://"])
    func aCheckoutWithoutAPageToOpenIsUnreadable(url: String) async {
        let (api, _) = billingApi([.init(status: 201, body: checkoutJSON(url))])

        do {
            _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
            Issue.record("expected an unreadable answer")
        } catch let failure as ApiFailure {
            guard case .decoding = failure else {
                Issue.record("unexpected \(failure)")
                return
            }
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func anUpperCaseSchemeIsStillAWebPage() async throws {
        let (api, _) = billingApi([.init(status: 201, body: checkoutJSON("HTTPS://my.click.uz/services/pay?service_id=1"))])

        let checkout = try await api.startCheckout(planCode: "pro_monthly", channel: .click)

        #expect(checkout.checkoutUrl.host() == "my.click.uz")
    }

    // Spec §3: a guardian is refused (403), a channel that is off is 503; one POST either way.
    @Test(arguments: [(403, "FORBIDDEN"), (503, "UPSTREAM_UNAVAILABLE")])
    func aRefusedCheckoutIsThrownAndNotRetried(status: Int, code: String) async {
        let (api, transport) = billingApi([.error(status, code: code), .init(status: 201, body: checkoutJSON(clickPage))])

        do {
            _ = try await api.startCheckout(planCode: "pro_yearly", channel: .click)
            Issue.record("expected a refusal")
        } catch let failure as ApiFailure {
            #expect(failure.code == ApiErrorCode(rawValue: code))
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(await transport.requests.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`
Expected: FAIL — `cannot find 'BillingApi' in scope` (and the other new names).

- [ ] **Step 3: The models**

`NozirKit/Sources/NozirFamily/BillingModels.swift`:

```swift
import Foundation

/// Android `BillingPeriod`: the two cadences the app can price.
public enum BillingPeriod: Int, CaseIterable, Sendable {
    case monthly = 1
    case yearly = 12

    public var months: Int {
        rawValue
    }
}

/// Backend `PaymentChannel`. A channel this app does not know is left out.
public enum PaymentChannel: String, CaseIterable, Sendable, Encodable {
    case payme = "PAYME"
    case click = "CLICK"
    case uzum = "UZUM"
    case card = "CARD"
    case googlePlay = "GOOGLE_PLAY"
}

/// `PlanResponse`, only ever built for a PRO plan in UZS of one or twelve months.
public struct SubscriptionPlan: Equatable, Sendable {
    public let code: String
    public let period: BillingPeriod
    /// Whole soʻm, converted from tiyin once, here (Android `moneyFromMinorUnits`).
    public let priceSom: Int64
    /// The server's own sentences, in its order.
    public let features: [String]
    /// The channels that can take money now.
    public let availableChannels: [PaymentChannel]
    /// The channels being prepared, shown as labels while none is live.
    public let plannedChannels: [PaymentChannel]

    public init(
        code: String,
        period: BillingPeriod,
        priceSom: Int64,
        features: [String],
        availableChannels: [PaymentChannel],
        plannedChannels: [PaymentChannel]
    ) {
        self.code = code
        self.period = period
        self.priceSom = priceSom
        self.features = features
        self.availableChannels = availableChannels
        self.plannedChannels = plannedChannels
    }
}

/// `CheckoutResponse`: the payment order and the page that pays it. An answer
/// without an `http`/`https` page cannot be decoded, so it reaches the parent
/// as "unreadable answer" and nothing is opened.
public struct SubscriptionCheckout: Decodable, Equatable, Sendable {
    public let orderId: String
    public let checkoutUrl: URL

    public init(orderId: String, checkoutUrl: URL) {
        self.orderId = orderId
        self.checkoutUrl = checkoutUrl
    }

    private enum CodingKeys: String, CodingKey {
        case orderId, checkoutUrl
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderId = (try? container.decodeIfPresent(String.self, forKey: .orderId)) ?? ""
        let raw = (try? container.decodeIfPresent(String.self, forKey: .checkoutUrl))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else {
            throw DecodingError.dataCorruptedError(forKey: .checkoutUrl, in: container, debugDescription: "No web page to open")
        }
        checkoutUrl = url
    }
}

/// One `PlanResponse` before the app decides whether it can price it. Every
/// field is read on its own, so one plan of the wrong shape is left out
/// instead of failing the list.
struct RawPlan: Decodable {
    let code: String?
    let tier: String?
    let periodMonths: Int?
    let priceMinorUnits: Int64?
    let currency: String?
    let features: [String]
    let availableChannels: [PaymentChannel]
    let plannedChannels: [PaymentChannel]

    private enum CodingKeys: String, CodingKey {
        case code, tier, periodMonths, priceMinorUnits, currency, features, availableChannels, plannedChannels
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
        tier = try? container.decodeIfPresent(String.self, forKey: .tier)
        periodMonths = try? container.decodeIfPresent(Int.self, forKey: .periodMonths)
        priceMinorUnits = try? container.decodeIfPresent(Int64.self, forKey: .priceMinorUnits)
        currency = try? container.decodeIfPresent(String.self, forKey: .currency)
        let rawFeatures = (try? container.decodeIfPresent([RawFeature].self, forKey: .features)) ?? []
        features = rawFeatures.compactMap(\.text).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        availableChannels = Self.channels(try? container.decodeIfPresent([String].self, forKey: .availableChannels))
        plannedChannels = Self.channels(try? container.decodeIfPresent([String].self, forKey: .plannedChannels))
    }

    /// Android `toSubscriptionPlanOrNull`: the free tier is a state, not an
    /// offer; another currency would be divided wrongly; another cadence has
    /// no name on screen.
    var plan: SubscriptionPlan? {
        guard tier == "PRO", currency == "UZS",
              let code, let priceMinorUnits,
              let months = periodMonths, let period = BillingPeriod(rawValue: months)
        else { return nil }
        return SubscriptionPlan(
            code: code,
            period: period,
            priceSom: priceMinorUnits / 100,
            features: features,
            availableChannels: availableChannels,
            plannedChannels: plannedChannels
        )
    }

    private static func channels(_ raw: [String]?) -> [PaymentChannel] {
        (raw ?? []).compactMap(PaymentChannel.init(rawValue:))
    }
}

/// `PlanFeatureDto`; only the text is shown.
private struct RawFeature: Decodable {
    let text: String?

    private enum CodingKeys: String, CodingKey {
        case text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try? container.decodeIfPresent(String.self, forKey: .text)
    }
}
```

- [ ] **Step 4: The service and the API**

`NozirKit/Sources/NozirFamily/BillingService.swift`:

```swift
import Foundation

/// What P19 asks beyond the subscription itself (which stays on
/// `FamilyService.subscription()`). `BillingApi` is the real one; screen-model
/// tests use a scripted fake.
public protocol BillingService: Sendable {
    /// The plans the app can price honestly, in the server's order.
    func plans() async throws -> [SubscriptionPlan]
    /// Opens one payment order and returns its page. Every call is a new
    /// order with a fresh `Idempotency-Key`, sent once and never retried here.
    /// OWNER only: a guardian gets 403 `FORBIDDEN`; a channel that is off, 503.
    func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout
}
```

`NozirKit/Sources/NozirFamily/BillingApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/subscription/plans` and `/checkout` (backend `BillingController`).
public struct BillingApi: BillingService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func plans() async throws -> [SubscriptionPlan] {
        let raw = try await client.send(ApiRequest(method: .get, path: "/v1/parent/subscription/plans"), as: [RawPlan].self)
        return raw.compactMap(\.plan)
    }

    public func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout {
        struct Body: Encodable {
            let planCode: String
            let channel: PaymentChannel
        }
        var request = try ApiRequest.post("/v1/parent/subscription/checkout", json: Body(planCode: planCode, channel: channel))
        // One per tap (Android `UUID.randomUUID()` in the repository).
        request.idempotencyKey = UUID()
        return try await client.send(request, as: SubscriptionCheckout.self)
    }
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`
Expected: `** TEST SUCCEEDED **`, the new `BillingApiTests` among them.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirFamily/BillingModels.swift NozirKit/Sources/NozirFamily/BillingService.swift NozirKit/Sources/NozirFamily/BillingApi.swift NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift NozirKit/Tests/NozirFamilyTests/BillingApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: plans in soʻm and a keyed checkout — BillingApi

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: The arithmetic and the words — `SubscriptionMath`, `SubscriptionTexts`, the iOS key, the fake

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/FakeBilling.swift` (the fake and the fixtures; the fake is used from Task 6)
- Create: `NozirKit/Tests/NozirAppFeatureTests/SubscriptionTextsTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionTexts.swift`
- Modify: `NozirKit/l10n/ios/values/strings.xml`, `NozirKit/l10n/ios/values-ru/strings.xml`, `NozirKit/l10n/ios/values-en/strings.xml` (before `</resources>`)
- Regenerate: `NozirKit/Sources/NozirL10n/L10n.generated.swift` (by `scripts/gen_l10n.py` only)

**Interfaces:**
- Consumes: `BillingPeriod`, `PaymentChannel`, `SubscriptionPlan`, `SubscriptionCheckout`, `BillingService` (Task 3); `SubscriptionState`, `Subscription(activeChildId:state:)` (Task 2); `DateTexts.dayMonthAndYear(_:_:)` (`Insights/InsightTexts.swift:60`); `LocalDate(_:in:)` (`NozirInsights/LocalDate.swift:36`); `day(_:)` (`FakeInsights.swift:7`); `PauseGate` (`FakeLocation.swift:114`); `offline` (`FakeFamily.swift:5`); L10n `paymentChannel{Payme,Click,Uzum,Card,GooglePlay}`, `subscriptionPlan{Yearly,Monthly}`, `subscriptionPriceUnit{Year,Month}`, `subscriptionActive{Yearly,Monthly}`, `subscriptionTrialTitle`, `subscriptionTrialUntil(_:)`, `subscriptionGraceTitle`, `subscriptionGraceUntil(_:)`, `subscriptionActiveUntil(_:)`, `subscriptionActiveNoEndDate`, `subscriptionActiveAutoRenew{On,Off}`, `subscriptionActionPayWith(_:_:)`, `subscriptionMonthlyEquivalent(_:)` (all in `L10n.generated.swift:3329-3370, 5480-5766`).
- Produces (internal to `NozirAppFeature`):
  - `SubscriptionMath.yearlySavingPercent(yearlySom: Int64, monthlySom: Int64) -> Int?`, `monthlyEquivalent(yearlySom: Int64) -> Int64`, `payChannel(_ plan: SubscriptionPlan?) -> PaymentChannel?`.
  - `SubscriptionTexts.grouped(_ amount: Int64) -> String`, `channelName(_:_:)`, `planName(_:_:)`, `priceUnit(_:_:)`, `activePeriod(_:_:)`, `trialLine(endsAt:calendar:_:)`, `graceLine(until:calendar:_:)`, `activeUntil(endsAt:calendar:_:)`, `autoRenew(_:_:)`, `payTitle(channel:priceSom:_:)`, `monthlyEquivalent(yearlySom:_:)` — all `-> String`.
  - `L10n.iosSubscriptionOwnerOnly` (generated).
  - Test support: `actor FakeBilling: BillingService` (`Script { plans, checkout, plansGate, checkoutGate }`, `calls: [String]`, `checkouts: [CheckoutCall]`, `add(_:)`), `struct CheckoutCall: Equatable, Sendable { planCode, channel }`, `planFixture(_:priceSom:available:planned:features:)`, `proYearly`, `proMonthly`, `clickCheckout`, `familySubscription(_:)`.

- [ ] **Step 1: The fake and the fixtures**

`NozirKit/Tests/NozirAppFeatureTests/FakeBilling.swift`:

```swift
import Foundation
import NozirFamily
import NozirNetworking

/// What one checkout asked for.
struct CheckoutCall: Equatable, Sendable {
    let planCode: String
    let channel: PaymentChannel
}

/// Answers the plans and each checkout from their own queue, in order (an
/// empty queue is a phone with no connection), and records what was asked.
actor FakeBilling: BillingService {
    struct Script: Sendable {
        var plans: [Result<[SubscriptionPlan], ApiFailure>] = []
        var checkout: [Result<SubscriptionCheckout, ApiFailure>] = []
        /// Held once by the next `plans` / `startCheckout` call, after its answer is taken.
        var plansGate: PauseGate?
        var checkoutGate: PauseGate?
    }

    private var script: Script
    /// "plans", "checkout".
    private(set) var calls: [String] = []
    private(set) var checkouts: [CheckoutCall] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func plans() async throws -> [SubscriptionPlan] {
        calls.append("plans")
        let answer: Result<[SubscriptionPlan], ApiFailure> = script.plans.isEmpty ? .failure(offline) : script.plans.removeFirst()
        let gate = script.plansGate
        script.plansGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func startCheckout(planCode: String, channel: PaymentChannel) async throws -> SubscriptionCheckout {
        calls.append("checkout")
        checkouts.append(CheckoutCall(planCode: planCode, channel: channel))
        let answer: Result<SubscriptionCheckout, ApiFailure> = script.checkout.isEmpty ? .failure(offline) : script.checkout.removeFirst()
        let gate = script.checkoutGate
        script.checkoutGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// A PRO plan as the server lists it; the code follows the period
/// (`V18__plan_catalogue.sql`).
func planFixture(
    _ period: BillingPeriod,
    priceSom: Int64,
    available: [PaymentChannel] = [.click],
    planned: [PaymentChannel] = [.payme, .click, .uzum, .card],
    features: [String] = ["Bolaning joylashuvi", "Har kungi AI xulosa"]
) -> SubscriptionPlan {
    SubscriptionPlan(
        code: period == .yearly ? "pro_yearly" : "pro_monthly",
        period: period,
        priceSom: priceSom,
        features: features,
        availableChannels: available,
        plannedChannels: planned
    )
}

/// The two plans as the test server sells them. Tests read every price from
/// here, never from a literal (spec §3).
let proYearly = planFixture(.yearly, priceSom: 7_500)
let proMonthly = planFixture(.monthly, priceSom: 1_000, features: ["Bolaning joylashuvi"])

let clickCheckout = SubscriptionCheckout(
    orderId: "5f2c1a0e-0000-4000-8000-000000000001",
    checkoutUrl: URL(string: "https://my.click.uz/services/pay?service_id=1&amount=7500")!
)

func familySubscription(_ state: SubscriptionState) -> Subscription {
    Subscription(activeChildId: nil, state: state)
}
```

- [ ] **Step 2: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/SubscriptionTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

/// 2026-10-14T20:00:00Z: already the 15th in Tashkent (UTC+5).
private let lateOnTheFourteenth = Date(timeIntervalSince1970: 1_792_008_000)

private let tashkent: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}()

@Suite struct SubscriptionTextsTests {
    private let l10n = L10n(.uz)

    // Android `groupedByThousands`: a no-break space every three digits, never the locale's.
    @Test func pricesAreGroupedByThousandsWithANoBreakSpace() {
        #expect(SubscriptionTexts.grouped(0) == "0")
        #expect(SubscriptionTexts.grouped(999) == "999")
        #expect(SubscriptionTexts.grouped(1_000) == "1\u{00A0}000")
        #expect(SubscriptionTexts.grouped(149_000) == "149\u{00A0}000")
        #expect(SubscriptionTexts.grouped(1_234_567) == "1\u{00A0}234\u{00A0}567")
        #expect(SubscriptionTexts.grouped(-1_500) == "-1\u{00A0}500")
    }

    // Android `yearlySavingPercent`: a whole percent, half rounds up; nothing to claim is nil.
    @Test func theYearlySavingIsAWholePercent() {
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 149_000, monthlySom: 19_900) == 38)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: proYearly.priceSom, monthlySom: proMonthly.priceSom) == 38)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 597, monthlySom: 50) == 1)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 598, monthlySom: 50) == 0)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 12_000, monthlySom: 1_000) == nil)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 13_000, monthlySom: 1_000) == nil)
        #expect(SubscriptionMath.yearlySavingPercent(yearlySom: 7_500, monthlySom: 0) == nil)
    }

    // Android `monthlyEquivalent`: a year over twelve, to the nearest 100 soʻm (50 rounds up).
    @Test func theMonthlyEquivalentIsRoundedToAHundred() {
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 149_000) == 12_400)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_500) == 600)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_794) == 700)
        #expect(SubscriptionMath.monthlyEquivalent(yearlySom: 7_793) == 600)
        #expect(SubscriptionTexts.monthlyEquivalent(yearlySom: 149_000, l10n) == l10n.subscriptionMonthlyEquivalent("12\u{00A0}400"))
    }

    // Spec §4: Click when it is live, else the first live channel, else none.
    @Test func clickIsPreferredThenTheFirstLiveChannel() {
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [.payme, .click])) == .click)
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [.uzum, .payme])) == .uzum)
        #expect(SubscriptionMath.payChannel(planFixture(.yearly, priceSom: 1, available: [])) == nil)
        #expect(SubscriptionMath.payChannel(nil) == nil)
    }

    @Test func everyChannelAndPeriodHasItsWord() {
        #expect(SubscriptionTexts.channelName(.payme, l10n) == l10n.paymentChannelPayme)
        #expect(SubscriptionTexts.channelName(.click, l10n) == l10n.paymentChannelClick)
        #expect(SubscriptionTexts.channelName(.uzum, l10n) == l10n.paymentChannelUzum)
        #expect(SubscriptionTexts.channelName(.card, l10n) == l10n.paymentChannelCard)
        #expect(SubscriptionTexts.channelName(.googlePlay, l10n) == l10n.paymentChannelGooglePlay)
        #expect(SubscriptionTexts.planName(.yearly, l10n) == l10n.subscriptionPlanYearly)
        #expect(SubscriptionTexts.planName(.monthly, l10n) == l10n.subscriptionPlanMonthly)
        #expect(SubscriptionTexts.priceUnit(.yearly, l10n) == l10n.subscriptionPriceUnitYear)
        #expect(SubscriptionTexts.priceUnit(.monthly, l10n) == l10n.subscriptionPriceUnitMonth)
        #expect(SubscriptionTexts.activePeriod(.yearly, l10n) == l10n.subscriptionActiveYearly)
        #expect(SubscriptionTexts.activePeriod(.monthly, l10n) == l10n.subscriptionActiveMonthly)
    }

    // Spec §6: a date when the server gave one, in the phone's calendar; the title otherwise.
    @Test func theStateLinesNameTheDayOrSayTheTitle() {
        let fifteenth = DateTexts.dayMonthAndYear(day("2026-10-15"), l10n)

        #expect(SubscriptionTexts.trialLine(endsAt: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionTrialUntil(fifteenth))
        #expect(SubscriptionTexts.trialLine(endsAt: nil, calendar: tashkent, l10n) == l10n.subscriptionTrialTitle)
        #expect(SubscriptionTexts.graceLine(until: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionGraceUntil(fifteenth))
        #expect(SubscriptionTexts.graceLine(until: nil, calendar: tashkent, l10n) == l10n.subscriptionGraceTitle)
        #expect(SubscriptionTexts.activeUntil(endsAt: lateOnTheFourteenth, calendar: tashkent, l10n) == l10n.subscriptionActiveUntil(fifteenth))
        #expect(SubscriptionTexts.activeUntil(endsAt: nil, calendar: tashkent, l10n) == l10n.subscriptionActiveNoEndDate)
        #expect(SubscriptionTexts.autoRenew(true, l10n) == l10n.subscriptionActiveAutoRenewOn)
        #expect(SubscriptionTexts.autoRenew(false, l10n) == l10n.subscriptionActiveAutoRenewOff)
    }

    @Test func thePayButtonNamesTheChannelAndTheGroupedPrice() {
        #expect(SubscriptionTexts.payTitle(channel: .click, priceSom: proYearly.priceSom, l10n)
            == l10n.subscriptionActionPayWith(l10n.paymentChannelClick, SubscriptionTexts.grouped(proYearly.priceSom)))
    }

    // Spec §7: the one new iOS key, in three languages.
    @Test func theOwnerOnlyNoteIsInEveryLanguage() {
        #expect(L10n(.uz).iosSubscriptionOwnerOnly == "Obunani faqat oila egasi sotib oladi.")
        #expect(L10n(.ru).iosSubscriptionOwnerOnly == "Подписку покупает только владелец семьи.")
        #expect(L10n(.en).iosSubscriptionOwnerOnly == "Only the family owner can buy the subscription.")
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'SubscriptionTexts' in scope`, `cannot find 'SubscriptionMath' in scope`, `value of type 'L10n' has no member 'iosSubscriptionOwnerOnly'`.

- [ ] **Step 4: The iOS key**

`NozirKit/l10n/ios/values/strings.xml` — before `</resources>`:

```xml
    <!-- P19: a guardian sees why there is no pay button (the server refuses them, 403). Android has no such note. -->
    <string name="ios_subscription_owner_only">Obunani faqat oila egasi sotib oladi.</string>
```

`NozirKit/l10n/ios/values-ru/strings.xml` — before `</resources>`:

```xml
    <string name="ios_subscription_owner_only">Подписку покупает только владелец семьи.</string>
```

`NozirKit/l10n/ios/values-en/strings.xml` — before `</resources>`:

```xml
    <string name="ios_subscription_owner_only">Only the family owner can buy the subscription.</string>
```

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 scripts/gen_l10n.py && python3 scripts/gen_l10n.py --check && git diff --stat NozirKit/Sources/NozirL10n/L10n.generated.swift`
Expected: `gen_l10n: up to date (… keys)`; the diff adds only `iosSubscriptionOwnerOnly` (one `/// \`ios_subscription_owner_only\`` block of three languages).

- [ ] **Step 5: `SubscriptionMath` and `SubscriptionTexts`**

`NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionTexts.swift`:

```swift
import Foundation
import NozirFamily
import NozirInsights
import NozirL10n

/// Android `YearlySavingPercent.kt`, `MonthlyEquivalent.kt` and
/// `SubscriptionUiState.payChannel`, figure for figure. The saving and the
/// per-month line are derived from the two prices, so they can never
/// contradict the prices printed beside them.
enum SubscriptionMath {
    /// How much less a year costs than twelve months, as a whole percent (half
    /// rounds up). Nil when there is nothing to claim: no monthly price, or a
    /// year that costs at least twelve months. The badge is then not drawn.
    static func yearlySavingPercent(yearlySom: Int64, monthlySom: Int64) -> Int? {
        let twelveMonths = monthlySom * Int64(BillingPeriod.yearly.months)
        guard twelveMonths > 0 else { return nil }
        let saved = twelveMonths - yearlySom
        guard saved > 0 else { return nil }
        return Int((saved * 100 + twelveMonths / 2) / twelveMonths)
    }

    /// A year over twelve, rounded to the nearest 100 soʻm: a way of comparing
    /// two prices, not a figure anyone is charged.
    static func monthlyEquivalent(yearlySom: Int64) -> Int64 {
        let months = Int64(BillingPeriod.yearly.months)
        let perMonth = (yearlySom + months / 2) / months
        return ((perMonth + 50) / 100) * 100
    }

    /// Click when it is live, otherwise the first channel that can take money;
    /// nil when none can, and the button then says payment is not ready.
    static func payChannel(_ plan: SubscriptionPlan?) -> PaymentChannel? {
        let live = plan?.availableChannels ?? []
        return live.first { $0 == .click } ?? live.first
    }
}

/// P19 in words (Android `SubscriptionContent`, `SubscriptionActiveCard`,
/// `BillingPeriodLabels`, `PaymentChannelLabel`, `GroupedThousands`). Dates
/// are the day in `calendar` (the phone's), written in the parent's language.
enum SubscriptionTexts {
    /// 149000 as "149 000" with a no-break space, so a price never wraps
    /// inside itself; the locale's separator is never used.
    static func grouped(_ amount: Int64) -> String {
        let digits = String(amount.magnitude)
        var groups: [Substring] = []
        var end = digits.endIndex
        while end > digits.startIndex {
            let start = digits.index(end, offsetBy: -3, limitedBy: digits.startIndex) ?? digits.startIndex
            groups.insert(digits[start..<end], at: 0)
            end = start
        }
        let joined = groups.joined(separator: "\u{00A0}")
        return amount < 0 ? "-" + joined : joined
    }

    /// Brand names, the same word in every language.
    static func channelName(_ channel: PaymentChannel, _ l10n: L10n) -> String {
        switch channel {
        case .payme: l10n.paymentChannelPayme
        case .click: l10n.paymentChannelClick
        case .uzum: l10n.paymentChannelUzum
        case .card: l10n.paymentChannelCard
        case .googlePlay: l10n.paymentChannelGooglePlay
        }
    }

    static func planName(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionPlanYearly
        case .monthly: l10n.subscriptionPlanMonthly
        }
    }

    static func priceUnit(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionPriceUnitYear
        case .monthly: l10n.subscriptionPriceUnitMonth
        }
    }

    /// "Yillik obuna": what a family that pays is told it holds.
    static func activePeriod(_ period: BillingPeriod, _ l10n: L10n) -> String {
        switch period {
        case .yearly: l10n.subscriptionActiveYearly
        case .monthly: l10n.subscriptionActiveMonthly
        }
    }

    static func trialLine(endsAt: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let endsAt else { return l10n.subscriptionTrialTitle }
        return l10n.subscriptionTrialUntil(date(endsAt, calendar, l10n))
    }

    static func graceLine(until: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let until else { return l10n.subscriptionGraceTitle }
        return l10n.subscriptionGraceUntil(date(until, calendar, l10n))
    }

    static func activeUntil(endsAt: Date?, calendar: Calendar, _ l10n: L10n) -> String {
        guard let endsAt else { return l10n.subscriptionActiveNoEndDate }
        return l10n.subscriptionActiveUntil(date(endsAt, calendar, l10n))
    }

    static func autoRenew(_ isOn: Bool, _ l10n: L10n) -> String {
        isOn ? l10n.subscriptionActiveAutoRenewOn : l10n.subscriptionActiveAutoRenewOff
    }

    /// "Click orqali toʻlash · 7 500 soʻm".
    static func payTitle(channel: PaymentChannel, priceSom: Int64, _ l10n: L10n) -> String {
        l10n.subscriptionActionPayWith(channelName(channel, l10n), grouped(priceSom))
    }

    /// "12 400 soʻm/oy hisobida", under the yearly price.
    static func monthlyEquivalent(yearlySom: Int64, _ l10n: L10n) -> String {
        l10n.subscriptionMonthlyEquivalent(grouped(SubscriptionMath.monthlyEquivalent(yearlySom: yearlySom)))
    }

    private static func date(_ instant: Date, _ calendar: Calendar, _ l10n: L10n) -> String {
        DateTexts.dayMonthAndYear(LocalDate(instant, in: calendar), l10n)
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/FakeBilling.swift NozirKit/Tests/NozirAppFeatureTests/SubscriptionTextsTests.swift NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionTexts.swift NozirKit/l10n/ios/values/strings.xml NozirKit/l10n/ios/values-ru/strings.xml NozirKit/l10n/ios/values-en/strings.xml NozirKit/Sources/NozirL10n/L10n.generated.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: prices, saving and plan words as Android counts them

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: Design system — `selected`, `good`, `info` tones and the saving badge

**Files:**
- Modify: `NozirKit/Sources/NozirDesignSystem/NozirColor.swift` (after `criticalContainer`, line 48)
- Modify: `NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift` (whole file, 48 lines)
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirBadge.swift`
- Modify: `NozirKit/Sources/NozirDesignSystem/Components/DesignSystemGallery.swift` (after `NozirInlineMessage("Inline message")`)
- Create: `NozirKit/Tests/NozirDesignSystemTests/CardToneTests.swift`

**Interfaces:**
- Consumes: `NozirColor.color(light:dark:darkAlpha:)` (private, same enum), `RGB(hex:)` (`NozirColor.swift:4`, internal), `NozirColor.card/border/attentionContainer/attentionBorder/criticalContainer/criticalBorder/goodContainer/skyContainer`, `NozirSpacing`, `.nozirText(_:color:)`.
- Produces:
  - `NozirColor.tealContainer`, `.tealBorder`, `.goodBorder`, `.skyBorder`, `.accentSolid`, `.onAccentSolid` (public `Color`).
  - `NozirCardTone` cases `.selected`, `.good`, `.info`; internal `NozirCardTone.fill: Color`, `NozirCardTone.border: Color`.
  - `public struct NozirBadge: View { public init(_ text: String) }`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirDesignSystemTests/CardToneTests.swift`:

```swift
import SwiftUI
import Testing
import UIKit
@testable import NozirDesignSystem

private func components(_ color: Color, _ style: UIUserInterfaceStyle) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color)
        .resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

/// The colour is `light` opaque in light mode and `dark` at `darkAlpha` in dark mode.
private func isTonal(_ color: Color, light: UInt32, dark: UInt32, darkAlpha: CGFloat) -> Bool {
    let day = components(color, .light)
    let night = components(color, .dark)
    let lightRGB = RGB(hex: light)
    let darkRGB = RGB(hex: dark)
    return abs(day.red - CGFloat(lightRGB.red)) < 0.002
        && abs(day.green - CGFloat(lightRGB.green)) < 0.002
        && abs(day.blue - CGFloat(lightRGB.blue)) < 0.002
        && abs(day.alpha - 1) < 0.002
        && abs(night.red - CGFloat(darkRGB.red)) < 0.002
        && abs(night.green - CGFloat(darkRGB.green)) < 0.002
        && abs(night.blue - CGFloat(darkRGB.blue)) < 0.002
        && abs(night.alpha - darkAlpha) < 0.002
}

@MainActor
@Suite struct CardToneTests {
    // Android `NozirLightColors` / `NozirDarkColors`: teal, statusGood, info, accentSolid.
    @Test func theP19ColoursAreAndroidsTonalColours() {
        #expect(isTonal(NozirColor.tealContainer, light: 0xEEFAF8, dark: 0x0FA799, darkAlpha: 0.12))
        #expect(isTonal(NozirColor.tealBorder, light: 0xB5E8E1, dark: 0x0FA799, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.goodBorder, light: 0xBFE6DD, dark: 0x0FA799, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.skyBorder, light: 0xC3DFFD, dark: 0x3987E5, darkAlpha: 0.30))
        #expect(isTonal(NozirColor.accentSolid, light: 0xFF8A3D, dark: 0xD95926, darkAlpha: 1))
        #expect(isTonal(NozirColor.onAccentSolid, light: 0x3A1C06, dark: 0xFFFFFF, darkAlpha: 1))
    }

    // Android `NozirCard`: each tone is its tonal colour's container and border.
    @Test func eachToneDrawsItsOwnFillAndBorder() {
        #expect(NozirCardTone.plain.fill == NozirColor.card)
        #expect(NozirCardTone.plain.border == NozirColor.border)
        #expect(NozirCardTone.attention.fill == NozirColor.attentionContainer)
        #expect(NozirCardTone.attention.border == NozirColor.attentionBorder)
        #expect(NozirCardTone.critical.fill == NozirColor.criticalContainer)
        #expect(NozirCardTone.critical.border == NozirColor.criticalBorder)
        #expect(NozirCardTone.selected.fill == NozirColor.tealContainer)
        #expect(NozirCardTone.selected.border == NozirColor.tealBorder)
        #expect(NozirCardTone.good.fill == NozirColor.goodContainer)
        #expect(NozirCardTone.good.border == NozirColor.goodBorder)
        #expect(NozirCardTone.info.fill == NozirColor.skyContainer)
        #expect(NozirCardTone.info.border == NozirColor.skyBorder)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirDesignSystemTests 170`
Expected: FAIL — `type 'NozirColor' has no member 'tealContainer'`, `type 'NozirCardTone' has no member 'selected'`.

- [ ] **Step 3: The colours**

In `NozirKit/Sources/NozirDesignSystem/NozirColor.swift`, after `public static let criticalContainer = …` (line 48) add:

```swift
    /// Android `teal`: a chosen option (the selected plan card).
    public static let tealContainer = color(light: 0xEEFAF8, dark: 0x0FA799, darkAlpha: 0.12)
    public static let tealBorder = color(light: 0xB5E8E1, dark: 0x0FA799, darkAlpha: 0.30)
    /// Android `statusGood.containerBorder` (`goodContainer` is its container).
    public static let goodBorder = color(light: 0xBFE6DD, dark: 0x0FA799, darkAlpha: 0.30)
    /// Android `info.containerBorder` (`skyContainer` is its container).
    public static let skyBorder = color(light: 0xC3DFFD, dark: 0x3987E5, darkAlpha: 0.30)
    /// Android `accentSolid` / `onAccentSolid`: the saving badge.
    public static let accentSolid = color(light: 0xFF8A3D, dark: 0xD95926)
    public static let onAccentSolid = color(light: 0x3A1C06, dark: 0xFFFFFF)
```

- [ ] **Step 4: The tones**

Replace `NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift` with:

```swift
import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention, critical
    /// Android `TEAL`: a chosen option, e.g. the selected plan.
    case selected
    /// Android `GOOD`: something that works, e.g. "Nozir PRO faol".
    case good
    /// Android `INFO`: a calm note, e.g. a plan lock.
    case info

    var fill: Color {
        switch self {
        case .plain: NozirColor.card
        case .attention: NozirColor.attentionContainer
        case .critical: NozirColor.criticalContainer
        case .selected: NozirColor.tealContainer
        case .good: NozirColor.goodContainer
        case .info: NozirColor.skyContainer
        }
    }

    var border: Color {
        switch self {
        case .plain: NozirColor.border
        case .attention: NozirColor.attentionBorder
        case .critical: NozirColor.criticalBorder
        case .selected: NozirColor.tealBorder
        case .good: NozirColor.goodBorder
        case .info: NozirColor.skyBorder
        }
    }
}

/// Android `NozirCard`: a rounded surface with a hairline border.
public struct NozirCard<Content: View>: View {
    private let tone: NozirCardTone
    private let content: Content

    public init(tone: NozirCardTone = .plain, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.compact) {
            content
        }
        .padding(NozirSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .fill(tone.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(tone.border, lineWidth: NozirSize.borderResting)
        )
    }
}
```

- [ ] **Step 5: The badge**

`NozirKit/Sources/NozirDesignSystem/Components/NozirBadge.swift`:

```swift
import SwiftUI

/// Android `SavingBadge`: a small solid pill that sits on a card's top edge
/// ("38% tejaysiz"). Decoration that also says something, so it is read.
public struct NozirBadge: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.label, color: NozirColor.onAccentSolid)
            .padding(.horizontal, 11)
            .padding(.vertical, NozirSpacing.extraSmall)
            .background(Capsule().fill(NozirColor.accentSolid))
    }
}
```

In `NozirKit/Sources/NozirDesignSystem/Components/DesignSystemGallery.swift`, after `NozirInlineMessage("Inline message")` add:

```swift
            NozirCard(tone: .selected) { Text("Selected card").nozirText(.body) }
            NozirCard(tone: .good) { Text("Good card").nozirText(.body) }
            NozirCard(tone: .info) { Text("Info card").nozirText(.body) }
            NozirBadge("38% tejaysiz")
```

- [ ] **Step 6: Run the tests to see them pass**

Run, one at a time: `bash .superpowers/run.sh NozirDesignSystemTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (every existing `switch` over a tone is in `NozirCard.swift`; `ProtectionTexts.cardTone` and `NotificationTexts.cardTone` only return tones).

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirDesignSystem/NozirColor.swift NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift NozirKit/Sources/NozirDesignSystem/Components/NozirBadge.swift NozirKit/Sources/NozirDesignSystem/Components/DesignSystemGallery.swift NozirKit/Tests/NozirDesignSystemTests/CardToneTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: selected, good and info card tones and the saving badge

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 6: `SubscriptionModel` — load, choose, pay once, watch for the payment

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/SubscriptionModelTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionModel.swift`

**Interfaces:**
- Consumes: `BillingService`, `SubscriptionPlan`, `BillingPeriod`, `PaymentChannel`, `SubscriptionCheckout` (Task 3); `SubscriptionState`, `Subscription.state` (Task 2); `SubscriptionMath` (Task 4); `FakeBilling`, `CheckoutCall`, `proYearly`, `proMonthly`, `planFixture`, `clickCheckout`, `familySubscription` (Task 4); `FamilyService.subscription()` / `me()`, `ParentProfile(displayName:phoneE164:locale:role:)` (`AccountModels.swift:76-91`); `FakeFamily` (`subscription`, `me` queues, `subscriptionGate`, `calls`, `add(_:)`), `offline`, `PauseGate`; `UserMessage(_:)` and its cases; `PrivacyModel.phoneCalendar` (`PrivacyModel.swift:58`); `L10n.subscriptionCheckoutNotOpened`.
- Produces: `@MainActor @Observable final class SubscriptionModel` with
  - `enum Phase: Equatable { case loading, ready, failed(UserMessage) }`, `enum Note: Equatable { case failure(UserMessage), checkoutNotOpened; func text(_ l10n: L10n) -> String }`;
  - `static let watchInterval: Duration` (5 s), `static let watchAttempts: Int` (60);
  - `init(billing: any BillingService, family: any FamilyService, calendar: Calendar = PrivacyModel.phoneCalendar, sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })`;
  - read-only state: `phase`, `plans: [SubscriptionPlan]`, `state: SubscriptionState?`, `selectedPeriod: BillingPeriod?`, `isOwner: Bool`, `isOffline: Bool`, `message: Note?`, `isStartingCheckout: Bool`, `isAwaitingPayment: Bool`, `checkoutURLToOpen: URL?`, `watch: Task<Void, Never>?`, `let calendar: Calendar`;
  - derived: `yearly`, `monthly`, `selectedPlan: SubscriptionPlan?`, `features: [String]`, `plannedChannels: [PaymentChannel]`, `payChannel: PaymentChannel?`, `savingPercent: Int?`, `isActive: Bool`, `offersPlans: Bool`, `canPay: Bool`, `activePeriod: BillingPeriod?`, `period(of: String?) -> BillingPeriod?`;
  - actions: `load() async`, `select(_ period: BillingPeriod)`, `pay() async`, `checkoutOpened(_ accepted: Bool)`, `checkPayment() async`, `sceneBecameActive() async`, `stopWatching()`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/SubscriptionModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

/// Records every wait and returns at once: five minutes of watching in no time.
private actor Naps {
    private(set) var asked: [Duration] = []

    func take(_ duration: Duration) {
        asked.append(duration)
    }
}

private let owner = ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER")
private let guardian = ParentProfile(displayName: "Nodira", phoneE164: nil, locale: "uz", role: "GUARDIAN")
private let forbidden = ApiFailure.server(status: 403, error: ApiError(code: .forbidden))
private let upstream = ApiFailure.server(status: 503, error: ApiError(code: .upstreamUnavailable))
private let paidYearly = SubscriptionState.active(planCode: proYearly.code, endsAt: nil, autoRenew: false)

/// Both plans, and the family answering `states` in order.
private func offered(_ states: [SubscriptionState] = [.free]) -> (FakeBilling.Script, FakeFamily.Script) {
    var billing = FakeBilling.Script()
    billing.plans = [.success([proYearly, proMonthly])]
    var family = FakeFamily.Script()
    family.subscription = states.map { .success(familySubscription($0)) }
    return (billing, family)
}

/// By default the watch waits an hour: a test that does not look at it never
/// sees it run, and `stopWatching()` ends it.
@MainActor
private func setup(
    _ billing: FakeBilling.Script,
    _ family: FakeFamily.Script,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in try await Task.sleep(for: .seconds(3_600)) }
) -> (SubscriptionModel, FakeBilling, FakeFamily) {
    let billingFake = FakeBilling(billing)
    let familyFake = FakeFamily(family)
    let model = SubscriptionModel(billing: billingFake, family: familyFake, sleep: sleep)
    return (model, billingFake, familyFake)
}

private func reads(_ family: FakeFamily) async -> Int {
    await family.calls.filter { $0 == "subscription" }.count
}

@MainActor
@Suite struct SubscriptionModelTests {
    // Spec §5.3: plans first, then the state (the role alongside the plans).
    @Test func theOfferIsLoadedPlansFirst() async {
        let (billing, base) = offered([.trial(endsAt: nil)])
        var family = base
        family.me = [.success(owner)]
        let (model, billingFake, familyFake) = setup(billing, family)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.state == .trial(endsAt: nil))
        #expect(model.selectedPeriod == .yearly)
        #expect(model.selectedPlan == proYearly)
        #expect(model.payChannel == .click)
        #expect(model.isOwner)
        #expect(model.offersPlans)
        #expect(model.canPay)
        #expect(model.features == proYearly.features)
        #expect(model.plannedChannels == proYearly.plannedChannels)
        #expect(model.savingPercent == SubscriptionMath.yearlySavingPercent(yearlySom: proYearly.priceSom, monthlySom: proMonthly.priceSom))
        #expect(!model.isOffline)
        #expect(model.message == nil)
        #expect(await billingFake.calls == ["plans"])
        #expect(await familyFake.calls == ["me", "subscription"])
    }

    // Android `withPlans`: the parent's pick survives a refresh while it is still sold.
    @Test func thePickSurvivesARefreshWhileItIsStillSold() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .success([proYearly, proMonthly]), .success([proYearly])]
        var family = FakeFamily.Script()
        family.subscription = Array(repeating: .success(familySubscription(.free)), count: 3)
        let (model, _, _) = setup(billing, family)

        await model.load()
        model.select(.monthly)
        #expect(model.selectedPlan == proMonthly)

        await model.load()
        #expect(model.selectedPeriod == .monthly)

        await model.load()
        #expect(model.selectedPeriod == .yearly)
        model.select(.monthly)
        #expect(model.selectedPeriod == .yearly)
    }

    @Test func aMonthlyOnlyOfferIsMonthlyWithoutASaving() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, _, _) = setup(billing, family)

        await model.load()

        #expect(model.yearly == nil)
        #expect(model.selectedPlan == proMonthly)
        #expect(model.savingPercent == nil)
        #expect(model.features == proMonthly.features)
    }

    // Android `withFailure`: prices on screen survive a lost connection, with a note.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func losingTheConnectionKeepsThePrices(failure: ApiFailure) async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .failure(failure), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = Array(repeating: .success(familySubscription(.free)), count: 3)
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.load()
        #expect(model.isOffline)
        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.message == nil)

        await model.load()
        #expect(!model.isOffline)
    }

    // Plan deviation S4: no plans and an error is the error, with a retry, even when the state read.
    @Test func aFirstLoadWithoutPlansIsAnErrorThatCanBeRetried() async {
        var billing = FakeBilling.Script()
        billing.plans = [.failure(offline), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free)), .success(familySubscription(.free))]
        let (model, _, _) = setup(billing, family)

        await model.load()
        #expect(model.phase == .failed(.noConnection))
        #expect(model.state == .free)
        #expect(!model.isOffline)

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.plans == [proYearly, proMonthly])
    }

    // A server fault over shown prices is said above them, not called offline.
    @Test func aServerFaultOverShownPricesIsSaidAboveThem() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([proYearly, proMonthly]), .failure(.unexpectedStatus(500)), .success([proYearly, proMonthly])]
        var family = FakeFamily.Script()
        family.subscription = [
            .success(familySubscription(.free)),
            .success(familySubscription(.free)),
            .failure(.unexpectedStatus(500)),
        ]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.load()
        #expect(model.message == .failure(.serverProblem))
        #expect(!model.isOffline)
        #expect(model.plans == [proYearly, proMonthly])

        await model.load()
        #expect(model.message == .failure(.serverProblem))
        #expect(model.state == .free)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var billing = FakeBilling.Script()
        billing.plans = [.success([proMonthly]), .success([proYearly, proMonthly])]
        billing.plansGate = gate
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, _, familyFake) = setup(billing, family)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.state == .free)
        #expect(await reads(familyFake) == 1)
    }

    // Review Focus 1 (spec D3): a guardian sees the plans, never the pay button.
    @Test func aGuardianIsNotOfferedThePayment() async {
        let (billing, base) = offered()
        var family = base
        family.me = [.success(guardian)]
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(!model.isOwner)
        #expect(model.offersPlans)
        #expect(!model.canPay)
        #expect(await billingFake.calls == ["plans"])
    }

    // Plan deviation S5: a role that cannot be read still offers it; the server decides.
    @Test func aRoleThatCannotBeReadStillOffersThePayment() async {
        let (billing, base) = offered([.free, .free])
        var family = base
        family.me = [.success(ParentProfile(displayName: nil, phoneE164: nil, locale: "uz"))]
        let (model, _, _) = setup(billing, family)
        await model.load()
        #expect(model.isOwner)

        await model.load()
        #expect(model.isOwner)
    }

    // Spec §6: a family that pays sees its plan, not an offer.
    @Test func aPayingFamilyIsOfferedNothing() async {
        let (billing, family) = offered([paidYearly])
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(model.isActive)
        #expect(!model.offersPlans)
        #expect(!model.canPay)
        #expect(model.activePeriod == .yearly)
        #expect(model.period(of: proMonthly.code) == .monthly)
        #expect(model.period(of: "retired_plan") == nil)
        #expect(await billingFake.calls == ["plans"])
    }

    @Test func noLiveChannelMeansNoPayment() async {
        var billing = FakeBilling.Script()
        billing.plans = [.success([planFixture(.yearly, priceSom: proYearly.priceSom, available: [])])]
        var family = FakeFamily.Script()
        family.subscription = [.success(familySubscription(.free))]
        let (model, billingFake, _) = setup(billing, family)

        await model.load()
        await model.pay()

        #expect(model.payChannel == nil)
        #expect(!model.canPay)
        #expect(await billingFake.calls == ["plans"])
    }

    // Spec D1/D2: the page goes to Safari and the watch starts.
    @Test func payingOpensThePageAndStartsWatching() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, billingFake, _) = setup(billing, family)
        await model.load()
        model.select(.monthly)

        await model.pay()

        #expect(await billingFake.checkouts == [CheckoutCall(planCode: proMonthly.code, channel: .click)])
        #expect(model.checkoutURLToOpen == clickCheckout.checkoutUrl)
        #expect(model.isAwaitingPayment)
        #expect(!model.isStartingCheckout)
        #expect(model.message == nil)
        #expect(model.watch != nil)

        model.checkoutOpened(true)
        #expect(model.checkoutURLToOpen == nil)
        #expect(model.isAwaitingPayment)
        model.stopWatching()
    }

    // Review Focus 2: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsStartOneCheckout() async {
        let gate = PauseGate()
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout), .success(clickCheckout)]
        billing.checkoutGate = gate
        family.me = [.success(owner)]
        let (model, billingFake, _) = setup(billing, family)
        await model.load()

        let first = Task { await model.pay() }
        await gate.untilPaused()
        #expect(model.isStartingCheckout)
        #expect(!model.canPay)
        await model.pay()
        await gate.release()
        await first.value

        #expect(await billingFake.checkouts.count == 1)
        #expect(!model.isStartingCheckout)
        model.stopWatching()
    }

    // Spec §3: 403 (not the owner) and 503 (channel off) are said; the prices stay; nothing opens.
    @Test(arguments: [(forbidden, UserMessage.permissionDenied), (upstream, .serviceUnavailable)])
    func aRefusedCheckoutIsSaidAndThePricesStay(failure: ApiFailure, expected: UserMessage) async {
        var (billing, family) = offered()
        billing.checkout = [.failure(failure)]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.pay()

        #expect(model.message == .failure(expected))
        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
        #expect(model.watch == nil)
        #expect(model.plans == [proYearly, proMonthly])
        #expect(model.canPay)

        model.select(.monthly)
        #expect(model.message == nil)
    }

    // Review Focus 4: a page that is not a web page is never opened.
    @Test func anUnreadableCheckoutOpensNothing() async {
        var (billing, family) = offered()
        billing.checkout = [.failure(.decoding("No web page to open"))]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()

        await model.pay()

        #expect(model.message == .failure(.unreadableAnswer))
        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
    }

    // Review Focus 4 (spec D1): nothing took the page — said, not awaited, not watched.
    @Test func aPageThatDidNotOpenSaysSoAndStopsWatching() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()

        model.checkoutOpened(false)
        await model.watch?.value

        #expect(model.checkoutURLToOpen == nil)
        #expect(!model.isAwaitingPayment)
        #expect(model.message == .checkoutNotOpened)
        #expect(model.message?.text(L10n(.uz)) == L10n(.uz).subscriptionCheckoutNotOpened)
        #expect(await reads(familyFake) == 1)
    }

    // Spec D2: every 5 s; a trial is not money, so only an active plan stops it.
    @Test func theWatchStopsWhenThePaymentLands() async {
        let naps = Naps()
        var (billing, family) = offered([.free, .trial(endsAt: nil), paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { await naps.take($0) })
        await model.load()

        await model.pay()
        await model.watch?.value

        #expect(await naps.asked == [SubscriptionModel.watchInterval, SubscriptionModel.watchInterval])
        #expect(SubscriptionModel.watchInterval == .seconds(5))
        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
        #expect(!model.offersPlans)
        #expect(await reads(familyFake) == 3)
    }

    // Spec D2: five minutes, then silence; "kutilmoqda" and the check button stay.
    @Test func theWatchGivesUpQuietlyAfterFiveMinutes() async {
        let naps = Naps()
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { await naps.take($0) })
        await model.load()

        await model.pay()
        await model.watch?.value

        #expect(SubscriptionModel.watchAttempts == 60)
        #expect(await naps.asked.count == 60)
        #expect(await reads(familyFake) == 61)
        #expect(model.isAwaitingPayment)
        #expect(model.message == nil)
        #expect(model.state == .free)
    }

    // Spec §5.3: leaving the screen cancels the watch.
    @Test(.timeLimit(.minutes(5)))
    func leavingTheScreenStopsTheWatch() async {
        let gate = PauseGate()
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family, sleep: { _ in await gate.pause() })
        await model.load()
        await model.pay()

        await gate.untilPaused()
        model.stopWatching()
        await gate.release()
        await model.watch?.value

        #expect(await reads(familyFake) == 1)
        #expect(model.isAwaitingPayment)
    }

    // Spec D2: "Toʻlovni tekshirish" reads once; an active plan ends the wait and the watch.
    @Test func checkingByHandReadsOnceAndEndsTheWatch() async {
        var (billing, family) = offered([.free, paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()

        await model.checkPayment()
        await model.watch?.value

        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
        #expect(await reads(familyFake) == 2)
    }

    // Review Focus 3 (spec D2): back from Safari, one read at once; a second while it runs is dropped.
    @Test(.timeLimit(.minutes(5)))
    func comingBackToTheAppChecksAtOnce() async {
        let gate = PauseGate()
        var (billing, family) = offered([.free, paidYearly])
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, familyFake) = setup(billing, family)
        await model.load()
        await model.pay()
        await familyFake.add { $0.subscriptionGate = gate }

        let first = Task { await model.sceneBecameActive() }
        await gate.untilPaused()
        await model.checkPayment()
        await gate.release()
        await first.value
        await model.watch?.value

        #expect(await reads(familyFake) == 2)
        #expect(model.state == paidYearly)
        #expect(!model.isAwaitingPayment)
    }

    @Test func aFailedCheckSaysNothingAndKeepsWaiting() async {
        var (billing, family) = offered()
        billing.checkout = [.success(clickCheckout)]
        family.me = [.success(owner)]
        let (model, _, _) = setup(billing, family)
        await model.load()
        await model.pay()

        await model.checkPayment()

        #expect(model.isAwaitingPayment)
        #expect(model.message == nil)
        #expect(model.state == .free)
        model.stopWatching()
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'SubscriptionModel' in scope`.

- [ ] **Step 3: `SubscriptionModel`**

`NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirL10n

/// P19 (Android `SubscriptionViewModel`): what the family has and what it
/// could have. Plans are read before the state (a paying family still needs
/// them to name its cadence); the parent's role alongside the plans, so a
/// guardian never sees the pay button flash. A payment is opened here and
/// made on Click's page; nothing here grants anything: after the page opens,
/// the state is read every 5 s (60 times) until the server says PRO, and once
/// more on "Toʻlovni tekshirish" and whenever the app comes back.
@MainActor
@Observable
final class SubscriptionModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// No plans on screen and the last load failed: the offer area is the error.
        case failed(UserMessage)
    }

    /// One sentence above the offer; the prices stay.
    enum Note: Equatable {
        case failure(UserMessage)
        case checkoutNotOpened

        func text(_ l10n: L10n) -> String {
            switch self {
            case .failure(let problem): problem.text(l10n)
            case .checkoutNotOpened: l10n.subscriptionCheckoutNotOpened
            }
        }
    }

    /// Android `PaymentWatchIntervalMillis` × `PaymentWatchAttempts`: five minutes.
    static let watchInterval: Duration = .seconds(5)
    static let watchAttempts = 60

    private(set) var phase: Phase = .loading
    private(set) var plans: [SubscriptionPlan] = []
    /// Nil until the server has said.
    private(set) var state: SubscriptionState?
    /// Yearly until the parent picks otherwise.
    private(set) var selectedPeriod: BillingPeriod?
    /// Only the owner may pay (a guardian gets 403); an unread role counts as owner.
    private(set) var isOwner = true
    /// Prices are on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var message: Note?
    private(set) var isStartingCheckout = false
    /// A page was opened and the plan has not turned PRO yet.
    private(set) var isAwaitingPayment = false
    /// A page waiting to be opened; the view opens it and calls `checkoutOpened`.
    private(set) var checkoutURLToOpen: URL?
    /// The payment watch, kept so a test can wait for it to end.
    @ObservationIgnored private(set) var watch: Task<Void, Never>?

    /// The phone's calendar, for the dates on screen.
    let calendar: Calendar
    private let billing: any BillingService
    private let family: any FamilyService
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Bumped by every load: an older load's answers are dropped.
    @ObservationIgnored private var generation = 0
    /// Bumped by every state read: an older read never overwrites a newer one.
    @ObservationIgnored private var stateReads = 0
    @ObservationIgnored private var isChecking = false

    init(
        billing: any BillingService,
        family: any FamilyService,
        calendar: Calendar = PrivacyModel.phoneCalendar,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.billing = billing
        self.family = family
        self.calendar = calendar
        self.sleep = sleep
    }

    // MARK: What the screen draws

    var yearly: SubscriptionPlan? {
        plans.first { $0.period == .yearly }
    }

    var monthly: SubscriptionPlan? {
        plans.first { $0.period == .monthly }
    }

    var selectedPlan: SubscriptionPlan? {
        switch selectedPeriod {
        case .yearly: yearly
        case .monthly: monthly
        case nil: nil
        }
    }

    /// From the yearly plan, else the monthly one.
    var features: [String] {
        (yearly ?? monthly)?.features ?? []
    }

    var plannedChannels: [PaymentChannel] {
        (yearly ?? monthly)?.plannedChannels ?? []
    }

    var payChannel: PaymentChannel? {
        SubscriptionMath.payChannel(selectedPlan)
    }

    /// Nil without two plans to compare: no badge.
    var savingPercent: Int? {
        guard let yearly, let monthly else { return nil }
        return SubscriptionMath.yearlySavingPercent(yearlySom: yearly.priceSom, monthlySom: monthly.priceSom)
    }

    var isActive: Bool {
        state?.isActive == true
    }

    /// The plans and, for the owner, the pay action. Trial and grace still
    /// get the offer; only a paying family does not.
    var offersPlans: Bool {
        !isActive && !plans.isEmpty
    }

    var canPay: Bool {
        offersPlans && isOwner && payChannel != nil && !isStartingCheckout
    }

    /// Which cadence a plan code is, read off the listed plans; nil for a plan no longer sold.
    func period(of planCode: String?) -> BillingPeriod? {
        guard let planCode else { return nil }
        if planCode == yearly?.code { return .yearly }
        if planCode == monthly?.code { return .monthly }
        return nil
    }

    var activePeriod: BillingPeriod? {
        guard case .active(let planCode, _, _)? = state else { return nil }
        return period(of: planCode)
    }

    // MARK: Actions

    func load() async {
        generation += 1
        let mine = generation
        message = nil
        if plans.isEmpty { phase = .loading }
        let billing = self.billing
        let family = self.family
        async let parent = Self.attempt { try await family.me() }
        let listed = await Self.attempt { try await billing.plans() }
        let role = await parent
        guard mine == generation else { return }
        if case .success(let me) = role {
            isOwner = (me.role ?? "OWNER") == "OWNER"
        }
        var failure: (any Error)?
        switch listed {
        case .success(let fresh):
            apply(plans: fresh)
        case .failure(let error):
            failure = error
        }
        let read = await readState()
        guard mine == generation else { return }
        if failure == nil, case .failure(let error)? = read {
            failure = error
        }
        settle(after: failure)
    }

    /// Only a cadence that is on sale can be picked.
    func select(_ period: BillingPeriod) {
        guard plans.contains(where: { $0.period == period }) else { return }
        selectedPeriod = period
        message = nil
    }

    /// One checkout at a time; a second tap while one is in flight does nothing.
    func pay() async {
        guard canPay, let plan = selectedPlan, let channel = payChannel else { return }
        isStartingCheckout = true
        message = nil
        defer { isStartingCheckout = false }
        do {
            let checkout = try await billing.startCheckout(planCode: plan.code, channel: channel)
            checkoutURLToOpen = checkout.checkoutUrl
            isAwaitingPayment = true
            startWatching()
        } catch is CancellationError {
            return
        } catch {
            message = .failure(UserMessage(error))
        }
    }

    /// The view tried to open the page; `accepted` false means nothing took it.
    func checkoutOpened(_ accepted: Bool) {
        checkoutURLToOpen = nil
        guard !accepted else { return }
        isAwaitingPayment = false
        stopWatching()
        message = .checkoutNotOpened
    }

    /// "Toʻlovni tekshirish".
    func checkPayment() async {
        await checkOnce()
    }

    /// Back from Safari (or any other app): iOS paused the watch meanwhile.
    func sceneBecameActive() async {
        await checkOnce()
    }

    /// The screen went away.
    func stopWatching() {
        watch?.cancel()
    }

    // MARK: Inside

    private func apply(plans fresh: [SubscriptionPlan]) {
        plans = fresh
        if let picked = selectedPeriod, fresh.contains(where: { $0.period == picked }) { return }
        selectedPeriod = (yearly ?? monthly)?.period
    }

    private func apply(state fresh: SubscriptionState) {
        state = fresh
        guard fresh.isActive else { return }
        isAwaitingPayment = false
        stopWatching()
    }

    /// Android `withFailure`: prices on screen survive a lost connection with a
    /// note; any other fault over them is said above them; with no prices the
    /// fault is the screen.
    private func settle(after failure: (any Error)?) {
        guard let failure else {
            isOffline = false
            phase = .ready
            return
        }
        if failure is CancellationError { return }
        let problem = UserMessage(failure)
        if plans.isEmpty {
            isOffline = false
            phase = .failed(problem)
        } else if problem == .noConnection || problem == .timeout {
            isOffline = true
            phase = .ready
        } else {
            isOffline = false
            phase = .ready
            message = .failure(problem)
        }
    }

    /// Reads and applies the state. Nil when a newer read started meanwhile.
    @discardableResult
    private func readState() async -> Result<SubscriptionState, any Error>? {
        stateReads += 1
        let mine = stateReads
        do {
            let fresh = try await family.subscription().state
            guard mine == stateReads else { return nil }
            apply(state: fresh)
            return .success(fresh)
        } catch {
            guard mine == stateReads else { return nil }
            return .failure(error)
        }
    }

    /// One read; dropped while another check is running. A failure is silent (Android).
    private func checkOnce() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        await readState()
    }

    private func startWatching() {
        watch?.cancel()
        watch = Task { await self.watchForPayment() }
    }

    private func watchForPayment() async {
        for _ in 0..<Self.watchAttempts {
            do {
                try await sleep(Self.watchInterval)
                try Task.checkCancellation()
            } catch {
                return
            }
            if case .success(let fresh)? = await readState(), fresh.isActive { return }
            if Task.isCancelled { return }
        }
    }

    private nonisolated static func attempt<Value: Sendable>(
        _ work: @Sendable () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return .success(try await work())
        } catch {
            return .failure(error)
        }
    }
}
```

- [ ] **Step 4: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`, no `Sendable` / isolation warnings in the filtered output.

- [ ] **Step 5: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/SubscriptionModelTests.swift NozirKit/Sources/NozirAppFeature/Subscription/SubscriptionModel.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: the subscription model — plans, one checkout, watching for the payment

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 7: P19 screen, the Profile row and the wiring

**Files:**
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift:19-52` (`setup`) and a new test before the suite's closing `}` (after `theNotificationsScreenUsesTheSessionsService`)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift` (line 32 service, line 50 init parameter, line 66 assignment, after `makeNotificationsModel` lines 199-201 factory)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:84`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SubscriptionView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift:6-35, 197-202`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`ProfileStep` lines 42-54, `ProfileView(…)` lines 130-138, `profileDestination` lines 255-258)

**Interfaces:**
- Consumes: `BillingApi`, `BillingService`, `SubscriptionPlan`, `PaymentChannel` (Task 3); `SubscriptionState` (Task 2); `SubscriptionTexts`, `L10n.iosSubscriptionOwnerOnly` (Task 4); `NozirCardTone.selected/.good`, `NozirBadge` (Task 5); `SubscriptionModel` and everything it produces (Task 6); `FakeBilling`, `proYearly`, `proMonthly`, `familySubscription` (Task 4); `FamilyStore.service` (`FamilyStore.swift:12`); design system `NozirCard`, `NozirButton(_:variant:size:isLoading:action:)`, `NozirInlineMessage`, `NozirBulletRow`, `NozirSectionTitle`, `NozirErrorState(title:message:retryTitle:onRetry:)`, `NozirEmptyState(title:message:)`, `NozirOfflineNotice`, `NozirSettingsRow(_:value:action:)`, `NozirColor.*`, `NozirSpacing.*`, `NozirRadius.cardCompact`; L10n `subscriptionTopBar`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`, `contentDescriptionLoading`, `subscriptionTrialBody`, `subscriptionExpiredTitle`, `subscriptionActiveTitle`, `subscriptionFeaturesLabel`, `subscriptionSavingBadge(_: Int)`, `subscriptionPlansEmptyTitle`, `subscriptionPlansEmptyBody`, `subscriptionActionPay`, `subscriptionPaymentNotReady`, `subscriptionAwaitingPayment`, `subscriptionCheckPayment`, `subscriptionSosFree`, `subscriptionSosFreeBody`, `glyphCheck`, `profileRowSubscription`.
- Produces: `SignedInModel.init(…, notifications:, billing: any BillingService, location:, …)`; `SignedInModel.makeSubscriptionModel() -> SubscriptionModel`; `SubscriptionView(model:)`; `ProfileView.init(model:onAddChild:onOpenChild:onPair:onOpenRules:onOpenSubscription:onOpenNotifications:onOpenPrivacy:)`; `SignedInView.ProfileStep.subscription`.

- [ ] **Step 1: Write the failing test**

In `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`, in `setup` add the parameter after `notifications: FakeNotifications = FakeNotifications(),` (line 28):

```swift
    billing: FakeBilling = FakeBilling(),
```

and in the `SignedInModel(` call after `notifications: notifications,` (line 40):

```swift
        billing: billing,
```

Add inside `SignedInModelTests`, after `theNotificationsScreenUsesTheSessionsService()`:

```swift
    // P19: the screen reads the session's billing and the family's subscription and role.
    @Test func theSubscriptionScreenUsesTheSessionsServices() async {
        var familyScript = FakeFamily.Script()
        familyScript.subscription = [.success(familySubscription(.trial(endsAt: nil)))]
        familyScript.me = [.success(ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER"))]
        var billingScript = FakeBilling.Script()
        billingScript.plans = [.success([proYearly, proMonthly])]
        let billing = FakeBilling(billingScript)
        let (model, family) = setup(familyScript, billing: billing)

        let screen = model.makeSubscriptionModel()
        await screen.load()

        #expect(screen.phase == .ready)
        #expect(screen.plans == [proYearly, proMonthly])
        #expect(screen.state == .trial(endsAt: nil))
        #expect(screen.isOwner)
        #expect(await billing.calls == ["plans"])
        #expect(await family.calls == ["me", "subscription"])
    }
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra argument 'billing' in call`, `value of type 'SignedInModel' has no member 'makeSubscriptionModel'`.

- [ ] **Step 3: `SignedInModel` and `AppEnvironment`**

In `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:

After `private let notifications: any NotificationsService` (line 32) add:

```swift
    private let billing: any BillingService
```

In `init`, after the parameter `notifications: any NotificationsService,` (line 50) add:

```swift
        billing: any BillingService,
```

and after `self.notifications = notifications` (line 66) add:

```swift
        self.billing = billing
```

After `makeNotificationsModel()` (lines 199-201) add:

```swift

    /// P19, one per visit: plans from billing, the state and the role from the family.
    func makeSubscriptionModel() -> SubscriptionModel {
        SubscriptionModel(billing: billing, family: family.service)
    }
```

In `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`, after `notifications: NotificationsApi(client: authorised),` (line 84) add:

```swift
            billing: BillingApi(client: authorised),
```

- [ ] **Step 4: Run the test to see it pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: `SubscriptionView`**

`NozirKit/Sources/NozirAppFeature/Screens/SubscriptionView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P19 as Android `SubscriptionContent`: the offline notice, what the family
/// has, then the "Nozir PRO faol" card or the two plans; the pay action and
/// the SOS note pinned below the scroll (inside it at accessibility text
/// sizes, as P20 does, so nothing is squeezed). The page opens in Safari;
/// nothing here grants anything — the server does when Click says the money moved.
struct SubscriptionView: View {
    @State private var model: SubscriptionModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: SubscriptionModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
          VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                stateNotes
                if case .active(_, let endsAt, let autoRenew)? = model.state {
                    activeCard(endsAt: endsAt, autoRenew: autoRenew)
                    features
                } else {
                    offer
                }
            }
            .padding(NozirSpacing.medium)
            if dynamicTypeSize.isAccessibilitySize {
                footer
            }
          }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !dynamicTypeSize.isAccessibilitySize {
                footer
            }
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.subscriptionTopBar)
        .navigationBarTitleDisplayMode(.inline)
        // Every entry reads again (spec D2).
        .task { await model.load() }
        .refreshable { await model.load() }
        // Back from Safari: iOS paused the watch while the parent paid.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.sceneBecameActive() }
            }
        }
        .onChange(of: model.checkoutURLToOpen) { _, url in
            if let url { open(url) }
        }
        // The flip to PRO is otherwise silent for VoiceOver.
        .onChange(of: model.isActive) { _, active in
            if active {
                AccessibilityNotification.Announcement(l10n.subscriptionActiveTitle).post()
            }
        }
        .onDisappear { model.stopWatching() }
    }

    /// Safari, or the Click app if it claims the link (Android `ACTION_VIEW`).
    private func open(_ url: URL) {
        openURL(url) { accepted in
            Task { @MainActor in model.checkoutOpened(accepted) }
        }
    }

    // MARK: What the family has

    @ViewBuilder
    private var stateNotes: some View {
        switch model.state {
        case .trial(let endsAt)?:
            NozirInlineMessage(SubscriptionTexts.trialLine(endsAt: endsAt, calendar: model.calendar, l10n))
            NozirInlineMessage(l10n.subscriptionTrialBody)
        case .grace(_, _, let until)?:
            NozirInlineMessage(SubscriptionTexts.graceLine(until: until, calendar: model.calendar, l10n))
        case .expired?:
            NozirInlineMessage(l10n.subscriptionExpiredTitle)
        case .free?, .active?, nil:
            EmptyView()
        }
    }

    /// "Nozir PRO faol", the cadence when the plan is still listed, the end
    /// date (the point: it answers "am I about to be charged?"), and renewal.
    private func activeCard(endsAt: Date?, autoRenew: Bool) -> some View {
        NozirCard(tone: .good) {
            HStack(spacing: NozirSpacing.compact) {
                Text(l10n.glyphCheck)
                    .nozirText(.titleSmall, color: NozirColor.goodContent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.card))
                    .accessibilityHidden(true)
                Text(l10n.subscriptionActiveTitle)
                    .nozirText(.titleSmall)
                    .accessibilityAddTraits(.isHeader)
            }
            if let period = model.activePeriod {
                Text(SubscriptionTexts.activePeriod(period, l10n)).nozirText(.body)
            }
            Text(SubscriptionTexts.activeUntil(endsAt: endsAt, calendar: model.calendar, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(SubscriptionTexts.autoRenew(autoRenew, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }

    @ViewBuilder
    private var features: some View {
        if !model.features.isEmpty {
            NozirSectionTitle(l10n.subscriptionFeaturesLabel)
            ForEach(Array(model.features.enumerated()), id: \.offset) { _, feature in
                NozirBulletRow(feature)
            }
        }
    }

    // MARK: The offer

    @ViewBuilder
    private var offer: some View {
        if !model.plans.isEmpty {
            // A refused checkout is said above the offer, which stays.
            if let note = model.message {
                NozirInlineMessage(note.text(l10n))
            }
            if let yearly = model.yearly {
                planCard(
                    yearly,
                    caption: SubscriptionTexts.monthlyEquivalent(yearlySom: yearly.priceSom, l10n),
                    badge: model.savingPercent.map { l10n.subscriptionSavingBadge($0) }
                )
            }
            if let monthly = model.monthly {
                planCard(monthly, caption: nil, badge: nil)
            }
            features
        } else if case .failed(let problem) = model.phase {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: problem.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else if model.phase == .loading {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
                .accessibilityLabel(l10n.contentDescriptionLoading)
        } else {
            NozirEmptyState(title: l10n.subscriptionPlansEmptyTitle, message: l10n.subscriptionPlansEmptyBody)
        }
    }

    /// A radio choice (Android `SubscriptionPlanCard`): teal when chosen, the
    /// badge overhanging the top edge.
    private func planCard(_ plan: SubscriptionPlan, caption: String?, badge: String?) -> some View {
        let isSelected = model.selectedPeriod == plan.period
        return Button {
            model.select(plan.period)
        } label: {
            NozirCard(tone: isSelected ? .selected : .plain) {
                planRow(plan, caption: caption, isSelected: isSelected)
            }
            .overlay(alignment: .topTrailing) {
                if let badge {
                    NozirBadge(badge)
                        .padding(.trailing, 14)
                        .offset(y: -11)
                }
            }
            .padding(.top, badge == nil ? 0 : 11)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Name and caption beside the price; stacked at accessibility text sizes.
    private func planRow(_ plan: SubscriptionPlan, caption: String?, isSelected: Bool) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: NozirSpacing.extraSmall))
            : AnyLayout(HStackLayout(alignment: .top, spacing: NozirSpacing.compact))
        return layout {
            VStack(alignment: .leading, spacing: 2) {
                Text(SubscriptionTexts.planName(plan.period, l10n)).nozirText(.titleSmall)
                if let caption {
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            if !stacked {
                Spacer(minLength: 0)
            }
            VStack(alignment: stacked ? .leading : .trailing, spacing: 2) {
                Text(SubscriptionTexts.grouped(plan.priceSom))
                    .nozirText(.titleLarge, color: isSelected ? NozirColor.primaryAccent : NozirColor.textPrimary)
                Text(SubscriptionTexts.priceUnit(plan.period, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: NozirSpacing.compact) {
            if model.offersPlans {
                if model.isOwner {
                    payAction
                } else {
                    // Spec D3: a guardian is told why, instead of a button the server refuses.
                    Text(l10n.iosSubscriptionOwnerOnly)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            Text(l10n.subscriptionSosFree)
                .nozirText(.bodySmall, color: NozirColor.goodContent)
                .multilineTextAlignment(.center)
            Text(l10n.subscriptionSosFreeBody)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, NozirSpacing.medium)
        .padding(.vertical, NozirSpacing.compact)
        .frame(maxWidth: .infinity)
        .background(NozirColor.background)
    }

    /// Android `PayAction`: ready → "Click orqali toʻlash · 7 500 soʻm" (and,
    /// once a page was opened, the wait and the check); no live channel → a
    /// disabled button, why, and the channels being prepared.
    @ViewBuilder
    private var payAction: some View {
        if let channel = model.payChannel, let plan = model.selectedPlan {
            NozirButton(
                SubscriptionTexts.payTitle(channel: channel, priceSom: plan.priceSom, l10n),
                size: .callToAction,
                isLoading: model.isStartingCheckout
            ) {
                Task { await model.pay() }
            }
            if model.isAwaitingPayment {
                Text(l10n.subscriptionAwaitingPayment)
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    .multilineTextAlignment(.center)
                NozirButton(l10n.subscriptionCheckPayment, variant: .secondary) {
                    Task { await model.checkPayment() }
                }
            }
        } else {
            NozirButton(l10n.subscriptionActionPay, size: .callToAction) {}
                .disabled(true)
            Text(l10n.subscriptionPaymentNotReady)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if !model.plannedChannels.isEmpty {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: NozirSpacing.extraSmall) { channelChips }
                    VStack(spacing: NozirSpacing.extraSmall) { channelChips }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// Labels, not buttons: nothing here starts anything.
    private var channelChips: some View {
        ForEach(model.plannedChannels, id: \.self) { channel in
            Text(SubscriptionTexts.channelName(channel, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.horizontal, NozirSpacing.small)
                .padding(.vertical, NozirSpacing.extraSmall)
                .background(Capsule().fill(NozirColor.card))
                .overlay(Capsule().strokeBorder(NozirColor.border, lineWidth: 1))
        }
    }
}
```

- [ ] **Step 6: The Profile row**

In `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`, replace lines 6-35 (the doc comment through the end of `init`) with:

```swift
/// P21 as Android `ProfileScreen`, with only the rows whose screens exist.
struct ProfileView: View {
    @State private var model: ProfileModel
    private let onAddChild: () -> Void
    private let onOpenChild: (Child) -> Void
    private let onPair: (Child) -> Void
    private let onOpenRules: () -> Void
    private let onOpenSubscription: () -> Void
    private let onOpenNotifications: () -> Void
    private let onOpenPrivacy: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var showsTheme = false
    @State private var showsLanguage = false

    init(
        model: ProfileModel,
        onAddChild: @escaping () -> Void,
        onOpenChild: @escaping (Child) -> Void,
        onPair: @escaping (Child) -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenSubscription: @escaping () -> Void,
        onOpenNotifications: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onAddChild = onAddChild
        self.onOpenChild = onOpenChild
        self.onPair = onPair
        self.onOpenRules = onOpenRules
        self.onOpenSubscription = onOpenSubscription
        self.onOpenNotifications = onOpenNotifications
        self.onOpenPrivacy = onOpenPrivacy
    }
```

and in the settings card (lines 198-201) replace:

```swift
                NozirCard {
                    NozirSettingsRow(l10n.profileRowNotifications, action: onOpenNotifications)
```

with:

```swift
                NozirCard {
                    // Android order: Rules, Subscription, Notifications. No value: Android shows none.
                    NozirSettingsRow(l10n.profileRowSubscription, action: onOpenSubscription)
                    Divider()
                    NozirSettingsRow(l10n.profileRowNotifications, action: onOpenNotifications)
```

- [ ] **Step 7: The Profile step**

In `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

In `enum ProfileStep`, after `case protection(UUID)` (line 53) add:

```swift
        /// P19 from the Profile row or a lock card opened in this tab.
        case subscription
```

In the `ProfileView(` call, after `onOpenRules: { profilePath.append(.rules(nil)) },` (line 135) add:

```swift
                    onOpenSubscription: { profilePath.append(.subscription) },
```

In `profileDestination(_:)`, after the `.protection` branch (lines 257-258) add:

```swift
        case .subscription:
            SubscriptionView(model: model.makeSubscriptionModel())
```

- [ ] **Step 8: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 9: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Sources/NozirAppFeature/Screens/SubscriptionView.swift NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: the Nozir PRO screen and its Profile row

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 8: "PRO rejaga oʻtish" on every plan lock

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/LocationLockCard.swift` (whole file, 17 lines)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift` (whole file, 29 lines)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift:6-38`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift:25-27`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift:7-15` (`RuleScreen`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift:9-29, 77`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift:9-18, 105`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift:8-14, 82`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`HomeStep` lines 10-30, `LocationStep` lines 36-40, the Location stack lines 107-124, `homeDestination` lines 197-203 and 218-219, `profileDestination` lines 234-240, `ruleDestination` lines 267-281)

**Interfaces:**
- Consumes: `SignedInModel.makeSubscriptionModel()`, `SubscriptionView(model:)`, `SignedInView.ProfileStep.subscription` (Task 7); `NozirCardTone.info` (Task 5); `NozirButton(_:variant:isLoading:action:)`; L10n `planLockActionUpgrade`, `planLockLocationTitle`, `planLockLocationBody`, `planLockSosNote`, `planLockFrozenBadge`, `planLockFrozenChildTitle`, `planLockFrozenChildBody`, `planLockChooseActive`.
- Produces: `LocationLockCard(onUpgrade:)`; `FrozenChildCard(isMakingActive:onMakeActive:onUpgrade:)`; `ChildDetailsView.init(model:onRemoved:onOpenRules:onOpenProtection:onOpenSubscription:)`; `LocationView.init(model:onOpenZone:onOpenTracking:onOpenSubscription:onAddChild:)`; `SafeZoneView.init(model:onFinished:onOpenSubscription:)`; `LocationTrackingView.init(model:onOpenSubscription:)`; `RuleScreen.subscription`; `SignedInView.HomeStep.subscription`, `SignedInView.LocationStep.subscription`.

This task is views and navigation only; the screens it opens are the model and factory tested in Tasks 6-7 (plan deviation S7). Its check is the whole `NozirAppFeatureTests` run plus the app build, and E2E lines 8-10 in Task 9.

- [ ] **Step 1: The cards**

Replace `NozirKit/Sources/NozirAppFeature/Screens/LocationLockCard.swift` with:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// "Location is on the PRO plan" (Android `PlanLockCard`, tone INFO): the
/// plan-lock card of P13, P14 and P12b. The note says SOS stays free; the
/// button opens P19.
struct LocationLockCard: View {
    private let onUpgrade: () -> Void
    @Environment(\.l10n) private var l10n

    init(onUpgrade: @escaping () -> Void) {
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        NozirCard(tone: .info) {
            Text(l10n.planLockLocationTitle).nozirText(.titleSmall)
            Text(l10n.planLockLocationBody).nozirText(.body)
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
            NozirButton(l10n.planLockActionUpgrade, action: onUpgrade)
        }
    }
}
```

Replace `NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift` with:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The free-plan lock of a frozen child (P03, P09): the rules stay as they
/// are on the phone; this child can be made the active one for free, or the
/// family can go PRO. With the free way out beside it, the upgrade is a
/// secondary button (Android `PlanLockCard` with a secondary action).
struct FrozenChildCard: View {
    private let isMakingActive: Bool
    private let onMakeActive: () -> Void
    private let onUpgrade: () -> Void
    @Environment(\.l10n) private var l10n

    init(isMakingActive: Bool, onMakeActive: @escaping () -> Void, onUpgrade: @escaping () -> Void) {
        self.isMakingActive = isMakingActive
        self.onMakeActive = onMakeActive
        self.onUpgrade = onUpgrade
    }

    var body: some View {
        NozirCard(tone: .attention) {
            HStack(spacing: NozirSpacing.small) {
                NozirStatusDot(.attention)
                Text(l10n.planLockFrozenBadge).nozirText(.label, color: NozirColor.attentionContent)
            }
            Text(l10n.planLockFrozenChildTitle).nozirText(.titleSmall)
            Text(l10n.planLockFrozenChildBody).nozirText(.bodySmall)
            NozirButton(l10n.planLockChooseActive, variant: .secondary, isLoading: isMakingActive, action: onMakeActive)
            NozirButton(l10n.planLockActionUpgrade, variant: .secondary, action: onUpgrade)
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
```

- [ ] **Step 2: The child's page and the daily limit**

In `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`, replace lines 6-38 (the doc comment through the `FrozenChildCard` block) with:

```swift
/// Android `ChildDetailsScreen`: edit, the frozen lock, remove; the rules and
/// protection rows open P09 and P18 for this child, the lock opens P19.
struct ChildDetailsView: View {
    @State private var model: ChildDetailsModel
    private let onRemoved: () -> Void
    private let onOpenRules: () -> Void
    private let onOpenProtection: () -> Void
    private let onOpenSubscription: () -> Void
    @Environment(\.l10n) private var l10n

    init(
        model: ChildDetailsModel,
        onRemoved: @escaping () -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenProtection: @escaping () -> Void,
        onOpenSubscription: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onRemoved = onRemoved
        self.onOpenRules = onOpenRules
        self.onOpenProtection = onOpenProtection
        self.onOpenSubscription = onOpenSubscription
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                HStack(spacing: NozirSpacing.compact) {
                    NozirAvatar(name: model.name, tone: model.avatar, fallbackInitial: l10n.previewAvatarInitial, size: 56)
                    Text(model.child.displayName).nozirText(.titleLarge)
                }
                if model.isFrozen {
                    FrozenChildCard(
                        isMakingActive: model.isMakingActive,
                        onMakeActive: { Task { await model.makeActive() } },
                        onUpgrade: onOpenSubscription
                    )
                }
```

In `NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift`, replace lines 25-27:

```swift
                    FrozenChildCard(isMakingActive: model.session.isMakingActive) {
                        Task { await model.session.makeActive() }
                    }
```

with:

```swift
                    FrozenChildCard(
                        isMakingActive: model.session.isMakingActive,
                        onMakeActive: { Task { await model.session.makeActive() } },
                        onUpgrade: { onOpen(.subscription) }
                    )
```

In `NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift`, in `enum RuleScreen`, after `case locationTracking(ChildRulesSession)` (line 14) add:

```swift
    /// P19 from a plan lock on P09 or P12b, on whichever stack the hub is in (plan deviation S2).
    case subscription
```

- [ ] **Step 3: The location screens**

In `NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift`, replace lines 9-29 (from `struct LocationView: View {` through the end of `init`) with:

```swift
struct LocationView: View {
    @State private var model: LocationModel
    private let onOpenZone: (UUID, SafeZone?) -> Void
    private let onOpenTracking: (UUID) -> Void
    private let onOpenSubscription: () -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: MapCameraPosition

    init(
        model: LocationModel,
        onOpenZone: @escaping (UUID, SafeZone?) -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onOpenSubscription: @escaping () -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        _position = State(initialValue: MapCamera.region(model.cameraTarget ?? LocationModel.fallbackCentre, metres: model.snapshot?.coordinate == nil ? 2500 : 1200))
        self.onOpenZone = onOpenZone
        self.onOpenTracking = onOpenTracking
        self.onOpenSubscription = onOpenSubscription
        self.onAddChild = onAddChild
    }
```

and replace `LocationLockCard()` (line 77) with:

```swift
            LocationLockCard(onUpgrade: onOpenSubscription)
```

In `NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift`, replace lines 9-18:

```swift
struct SafeZoneView: View {
    @State private var model: SafeZoneModel
    private let onFinished: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var position: MapCameraPosition = MapCamera.region(LocationModel.fallbackCentre, metres: 4000)

    init(model: SafeZoneModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }
```

with:

```swift
struct SafeZoneView: View {
    @State private var model: SafeZoneModel
    private let onFinished: () -> Void
    private let onOpenSubscription: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var position: MapCameraPosition = MapCamera.region(LocationModel.fallbackCentre, metres: 4000)

    init(model: SafeZoneModel, onFinished: @escaping () -> Void, onOpenSubscription: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
        self.onOpenSubscription = onOpenSubscription
    }
```

and replace `LocationLockCard()` (line 105) with:

```swift
            LocationLockCard(onUpgrade: onOpenSubscription)
```

In `NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift`, replace lines 8-14:

```swift
struct LocationTrackingView: View {
    @State private var model: LocationTrackingModel
    @Environment(\.l10n) private var l10n

    init(model: LocationTrackingModel) {
        _model = State(initialValue: model)
    }
```

with:

```swift
struct LocationTrackingView: View {
    @State private var model: LocationTrackingModel
    private let onOpenSubscription: () -> Void
    @Environment(\.l10n) private var l10n

    init(model: LocationTrackingModel, onOpenSubscription: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onOpenSubscription = onOpenSubscription
    }
```

and replace `LocationLockCard()` (line 82) with:

```swift
            LocationLockCard(onUpgrade: onOpenSubscription)
```

- [ ] **Step 4: The steps**

In `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

In `enum HomeStep`, after `case summaryLink(UUID)` (line 29) add:

```swift
        /// P19 from the frozen-child lock on P03 or P09 opened in this tab.
        case subscription
```

Replace `enum LocationStep` (lines 36-40) with:

```swift
    enum LocationStep: Hashable {
        /// A child's zone to edit, or nil for a new one.
        case zone(UUID, UUID?)
        case tracking(UUID)
        /// P19 from the location lock on P13, P14 or P12b.
        case subscription
    }
```

Replace the Location stack's `LocationView(…)` and its `.navigationDestination` (lines 108-124) with:

```swift
                LocationView(
                    model: model.locationTab,
                    onOpenZone: { childId, zone in locationPath.append(.zone(childId, zone?.id)) },
                    onOpenTracking: { locationPath.append(.tracking($0)) },
                    onOpenSubscription: { locationPath.append(.subscription) },
                    onAddChild: { model.presentAddChild() }
                )
                .navigationDestination(for: LocationStep.self) { step in
                    switch step {
                    case .zone(let childId, let zoneId):
                        SafeZoneView(
                            model: model.makeSafeZoneModel(childId: childId, zoneId: zoneId),
                            onFinished: { locationPath.removeAll() },
                            onOpenSubscription: { locationPath.append(.subscription) }
                        )
                    case .tracking(let childId):
                        LocationTrackingView(
                            model: model.makeLocationTrackingModel(childId: childId),
                            onOpenSubscription: { locationPath.append(.subscription) }
                        )
                    case .subscription:
                        SubscriptionView(model: model.makeSubscriptionModel())
                    }
                }
```

In `homeDestination(_:)`, replace the `.details` branch (lines 197-203) with:

```swift
        case .details(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { homePath.append(.rules(child.id)) },
                onOpenProtection: { homePath.append(.protection(child.id)) },
                onOpenSubscription: { homePath.append(.subscription) }
            )
```

and after the `.protection` branch (lines 218-219) add:

```swift
        case .subscription:
            SubscriptionView(model: model.makeSubscriptionModel())
```

In `profileDestination(_:)`, replace the `.child` branch (lines 234-240) with:

```swift
        case .child(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { profilePath.append(.childRules(child.id)) },
                onOpenProtection: { profilePath.append(.protection(child.id)) },
                onOpenSubscription: { profilePath.append(.subscription) }
            )
```

In `ruleDestination(_:onOpen:)`, replace the `.locationTracking` branch (lines 279-280) with:

```swift
        case .locationTracking(let session):
            LocationTrackingView(
                model: model.makeLocationTrackingModel(session: session),
                onOpenSubscription: { onOpen(.subscription) }
            )
        case .subscription:
            SubscriptionView(model: model.makeSubscriptionModel())
```

- [ ] **Step 5: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **`; `grep -rn "LocationLockCard()\|FrozenChildCard(isMakingActive: [^,]*) {" NozirKit/Sources` prints nothing.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Screens/LocationLockCard.swift NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p19: every plan lock opens Nozir PRO

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 9: Final check — whole suite, l10n, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, `gen_l10n: up to date`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `git diff 0370737 -- NozirKit/l10n` adds only `ios_subscription_owner_only` (three files), and `git diff --stat 0370737 -- NozirKit/Package.swift NozirKit/l10n/android` is empty.

- [ ] **Step 2: E2E (the user; simulator or a real iPhone + the real backend with test prices, an owner account and a guardian account on the same family, and the Android parent app on that family)**

Write "yes" or what was seen against each line:

1. Owner, family on the free plan: Profile → "Obuna · Nozir PRO" (between Qoidalar and Bildirishnomalar, no value) → P19 titled "Nozir PRO": "Yillik" card selected (teal) with the price grouped ("7 500"), "soʻm/yil", "… soʻm/oy hisobida" and the "…% tejaysiz" badge on its edge; "Oylik" card below; "Nimalar kiradi" with the server's sentences; the footer "Click orqali toʻlash · 7 500 soʻm", "SOS doim bepul" and its line. The Android app shows the same figures.
2. Tap "Oylik": it turns teal, VoiceOver reads it as selected; the button says the monthly price. Pull to refresh: still monthly.
3. Tap the pay button → Safari (or the Click app) opens Click's page; back in Nozir: "Toʻlov tasdiqlanishini kutyapmiz…" and "Toʻlovni tekshirish". Backend log: one `POST /checkout` with an `Idempotency-Key`.
4. Pay on Click (test card), switch back to Nozir → within seconds (at once on return) the screen is "Nozir PRO faol", "Oylik obuna", "… gacha amal qiladi", "Avtomatik yangilanish yoqilmagan", the features; no plans, no pay button; VoiceOver announces "Nozir PRO faol".
5. Start a payment and close Click's page without paying; wait 5 minutes on P19 → it stays "kutilmoqda" with the check button, no error. Tap "Toʻlovni tekshirish" → still waiting, nothing said.
6. Double-tap the pay button quickly → one page, one `POST /checkout` in the backend log.
7. Guardian account → P19 shows the plans, no pay button, "Obunani faqat oila egasi sotib oladi." above "SOS doim bepul".
8. Free family with two children → the frozen child's page (Profile → child, and Home → summary → edit child): "Shu bolani faol qilish" and "PRO rejaga oʻtish" both secondary; the second opens P19 in the same tab. Same from P09 (Profile → Qoidalar → the frozen child).
9. Location tab, a free family after the trial: the lock card (blue) with "PRO rejaga oʻtish" → P19 on the Location tab; the same from a zone being saved (P14) and from the tracking screen (P12b) opened both from the Location tab and from Qoidalar.
10. A family in trial / in grace / expired: P19 shows "… gacha hamma imkoniyat ochiq" + the trial body / "… gacha toʻlasangiz…" / "Obuna muddati tugagan" above the offer, with the pay button.
11. Airplane mode on P19 after it loaded: pull to refresh → the offline notice, prices stay; open P19 fresh offline → the error with "Qayta urinish", which works once online.
12. Largest Dynamic Type: the plan cards stack name over price, the footer scrolls with the content, nothing is cut. Three languages and both themes: every P19 text correct, the teal / green / blue cards and the orange badge readable in dark mode; screenshots (Cmd+S).
13. Record whether `my.click.uz` opened in Safari or in the Click app on a real iPhone (spec §9 risk).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.

## Open questions (ruled while planning)

- **Q1 — a guardian whose role could not be read taps pay.** The server answers 403 `FORBIDDEN`, which `UserMessage` reads as `.permissionDenied` ("Bu maʼlumot sizning oilangizga tegishli emas."), the same as Android. Ruling: follow the spec (§8 "403/503 xabarlari"): the message is shown above the offer; the button is not turned into the owner-only note. A later copy decision can map this case.
- **Q2 — a failed "Toʻlovni tekshirish" or foreground check.** Android says nothing (`applyPaymentCheck` ignores a failure). Ruling: same; the wait text stays and the parent can tap again.
- **Q3 — the watch and the tab bar.** `onDisappear` also fires when the parent switches tabs, which stops the watch; returning to the tab re-runs `.task` (a fresh read). Ruling: accepted, it matches the spec's `onDisappear` rule and the foreground check covers the common path.
- **Q4 — `autoRenew`.** The server always writes `false` with Click; the "on" text is kept for parity and is tested, though it is not seen today.
