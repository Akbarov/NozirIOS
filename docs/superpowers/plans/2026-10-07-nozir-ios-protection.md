# Nozir iOS — P18: Protection status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parent sees on Home (one child or many) whether the child's phone still holds the permissions Nozir needs — a plain, yellow or red "Himoya" row — opens P18 from that row or from the child's page, reads which permission is off and why, when the phone last reported, the steps for that phone's make, and sends those steps to the child's phone with one tap.

**Architecture:** `NozirInsights` gains the protection models (`ProtectionLevel`, `PermissionKind`, `PermissionStatus`, `ProtectionPermission`, `ProtectionStatus`), a `ProtectionService` protocol with its `ProtectionApi`, and `ParentHome.protection: HomeProtection?`. In `NozirAppFeature`, `HomeModel` exposes the row's level and the child it opens, `ProtectionTexts` holds every pure word-and-tone rule (Android's `PermissionStateLabel`, `PermissionDisplayLevel`, `OemInstructionTextRes`, …), and `ProtectionModel` (`@MainActor @Observable`, built like `TimeRequestModel`) loads one child's status and sends the instructions once. `ProtectionView` and `ProtectionRow` draw it; `ChildDetailsView` gets a row; `SignedInView` gets `HomeStep.protection` / `ProfileStep.protection`, `SignedInModel` a factory and the service.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; no third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-ios-protection-design.md` (commit `83e765d`). The backend contract (§3) is live and unchanged.

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries.
- Every `/v1/parent/*` call goes through `ApiClient`. Sending instructions is **never retried automatically**: one tap, one POST; a second tap while the first is in flight does nothing.
- `GET /v1/parent/children/{childId}/protection` → `{childId, level: HEALTHY|DEGRADED|BROKEN, permissions: [{kind, status, wasRevoked, instructionKey?}], lastReportAt?, isStale, manufacturer, instructionKey?}`. The id goes in the path lowercased (`InsightsApi.childPath`). Absent optional fields are absent, never `null` (backend `non_null`).
- `kind`: `USAGE_ACCESS, OVERLAY, NOTIFICATIONS, LOCATION, BATTERY, OEM_AUTOSTART`; `status`: `GRANTED, DENIED, SKIPPED`. A permission whose kind or status this app does not know is **left out**, never shown as broken. A level this app does not know reads as `healthy` (Android `UnknownLevelFallback`).
- A phone that never reported: `BROKEN`, every kind `DENIED`, `isStale = true`, no `lastReportAt`. Stale after 36 hours (the server decides; the app reads `isStale`).
- `POST /v1/parent/children/{childId}/protection/send-instructions` body `{kinds: [kind…]}` → 202, no body. `kinds` = every permission whose status is not `GRANTED`, in the server's order.
- Home: `ParentHome.protection` = `{level, childrenNeedingAttention: [UUID]}` — exactly those two fields (backend `HomeProtectionDto`, `InsightDtos.kt:76-79`). Absent or unreadable → `nil` → no row; Home still loads.
- Tones (spec D2), only the summary card and the Home row: healthy → `NozirCard(tone: .plain)`, degraded → `.attention`, broken → `.critical`. Permission dots follow Android `PermissionDisplayLevel` (granted → good, revoked → action, otherwise attention; never critical).
- Instruction key = `permission.instructionKey ?? status.instructionKey` of the **first** permission that is not granted; 11 known keys (`oem.{xiaomi,oppo,vivo,realme,infinix,generic}.autostart`, `oem.{xiaomi,samsung,generic}.battery`, `oem.generic.usage`, `oem.generic.overlay`), anything else → `protectionInstructionUnknown`. The phone in the line is `manufacturer` with its first letter upper-cased.
- Refresh: pull to refresh and the app coming back to the foreground (spec D5).
- User-facing text only from `L10n`, errors only through `UserMessage`; the server's `message` is never shown. **No new l10n key** (`gen_l10n.py --check` stays clean).
- Out of scope: push / deep link `nozir://protection/{childId}`, per-permission instructions, the notifications list (P16), the backend.
- Tests: Swift Testing; scripted fakes (`FakeProtection`, `FakeInsights`, `FakeFamily`), `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`.
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| P1 | 404 → `.missing` (`protectionNoChild…`) | 404 **or** 403 `NOT_YOUR_CHILD` → `.missing` | Every `{childId}` route passes `ChildScopeInterceptor` (backend `platform/web/ChildScopeInterceptor.kt`), which answers a removed or foreign child with 403 `NOT_YOUR_CHILD`, not 404; without this a removed child would read "permission denied" |
| P2 | `protectionChildId`: filter → first of `childrenNeedingAttention` → first card | Same order, but the first of `childrenNeedingAttention` **that has a card on screen**; and with a filter on a child the server did not name, the row's level reads `healthy` | Home carries only the family's worst level; a red row that opens a healthy child's "Himoya faol" is a contradiction. A child the server named is "not healthy", but its exact level is unknown, so the family level is shown |
| P3 | `HomeModel.protection` (type not said) | `var protection: ProtectionLevel?` (the row's level; nil hides the row) and `var protectionChildId: UUID?` | The view needs only those two |
| P4 | `ProtectionModel` (child name not said) | `ProtectionModel(childId:childName:service:)`; `makeProtectionModel(childId:)` reads the name from `FamilyStore.child(_:)` | Android loads it from the children repository; `LocationTrackingModel` does the same here |
| P5 | Permissions card (no title) | The card carries the existing `protectionPermissionsLabel` ("Ruxsatlar") as its heading | Spec §5.3 accessibility: card titles are headings; the key exists |
| P6 | Stale note "o'tgan vaqt" | `ElapsedTime(from:to:)` (`Insights/InsightTexts.swift:6`), `now` = the moment the view draws | The app's one elapsed-time formatter (Android `elapsedTimeOf`); 36 h and more reads "N soatdan koʻproq oldin" |

## Review Focus

1. **A child phone that never reported** (just paired, or Nozir never opened) — P18 says "Bola telefonidan hali xabar kelmagan…", lists all six as "Yoqilmagan · Bu ruxsat hali berilmagan", shows the generic usage steps, and "Yuborish" sends all six kinds → Task 1 `aPhoneThatNeverReportedIsBrokenAndStale`, Task 3 `theStaleNoteSaysHowLongOrNever`, Task 4 `sendingSendsEveryKindNotGranted`.
2. **A newer child app reporting a kind or status this app does not know** (or a new level) — that permission is left out, never shown as broken; an unknown level reads healthy → Task 1 `anUnknownLevelIsHealthyAndAnUnknownKindOrStatusIsLeftOut`.
3. **The child was removed (on this phone or the other parent's)** while P18 is open or about to open — "Bola tanlanmagan", no error, no retry button → Task 4 `aChildNoLongerInTheFamilyIsMissing` (404 and 403 `NOT_YOUR_CHILD`).
4. **"Yuborish" tapped twice, or with no connection** — one POST with only the broken kinds; a failure is a toast, the button works again, and "Yoʻriqnoma yuborildi" is never claimed for a send that failed → Task 4 `twoTapsSendOnce`, `aFailedSendIsSaidOnceAndCanBeTriedAgain`.
5. **A Home answer without `protection`, or with one the app cannot read; and the avatar filter on a healthy child** — Home loads with no row; a filtered healthy child gets a plain row that opens that child → Task 2 `protectionThatCannotBeReadLeavesHomeStanding`, `theProtectionRowOpensTheRightChild`.

---

## File map

**New:**
- `NozirKit/Sources/NozirInsights/ProtectionModels.swift` — `ProtectionLevel`, `PermissionKind`, `PermissionStatus`, `ProtectionPermission`, `ProtectionStatus`.
- `NozirKit/Sources/NozirInsights/ProtectionService.swift` — `ProtectionService`.
- `NozirKit/Sources/NozirInsights/ProtectionApi.swift` — `ProtectionApi`.
- `NozirKit/Tests/NozirInsightsTests/ProtectionApiTests.swift`.
- `NozirKit/Sources/NozirAppFeature/Protection/ProtectionTexts.swift`, `ProtectionModel.swift`.
- `NozirKit/Sources/NozirAppFeature/Screens/ProtectionView.swift`, `ProtectionRow.swift`.
- `NozirKit/Tests/NozirAppFeatureTests/FakeProtection.swift`, `ProtectionTextsTests.swift`, `ProtectionModelTests.swift`.

**Modified:** `NozirInsights/InsightModels.swift` (`ParentHome`, new `HomeProtection`); `NozirAppFeature/Insights/HomeModel.swift`; `NozirAppFeature/{SignedInModel,AppEnvironment}.swift`; `NozirAppFeature/Screens/{HomeView,ChildDetailsView,SignedInView}.swift`; tests `NozirInsightsTests/{InsightsFixtures,InsightsApiTests}.swift`, `NozirAppFeatureTests/{FakeInsights,HomeModelTests,SignedInModelTests}.swift`.

No `Package.swift` change: everything lives in existing targets (`Protection/` is a new folder inside the `NozirAppFeature` target, picked up automatically).

## Getting started

Branch `protection` (spec commit `83e765d`) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirInsightsTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

---
### Task 1: The status, as the server writes it — models and `ProtectionApi`

**Files:**
- Create: `NozirKit/Sources/NozirInsights/ProtectionModels.swift`
- Create: `NozirKit/Sources/NozirInsights/ProtectionService.swift`
- Create: `NozirKit/Sources/NozirInsights/ProtectionApi.swift`
- Modify: `NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` (append at the end, after `page(_:)` at line 99-101)
- Create: `NozirKit/Tests/NozirInsightsTests/ProtectionApiTests.swift`

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiClient.send(_:)` (no body read; `ApiClient.swift:45`), `ApiRequest(method:path:)`, `ApiRequest.post(_:json:)`, `InsightsApi.childPath(_:)` (`InsightsApi.swift:13`, internal to `NozirInsights`), `ApiFailure.isNotFound`, `FakeTransport`, `FakeTransport.Reply(status:body:)`, `.ok`, `.error`, `URLRequest.jsonObject` / `queryParameters`, `FixedToken`, `aliId`, `instant(_:)` (`InsightsFixtures.swift`).
- Produces:
  - `public enum ProtectionLevel: String, Sendable, Decodable { case healthy = "HEALTHY", degraded = "DEGRADED", broken = "BROKEN" }` (unknown → `.healthy`).
  - `public enum PermissionKind: String, CaseIterable, Sendable, Encodable { case usageAccess = "USAGE_ACCESS", overlay = "OVERLAY", notifications = "NOTIFICATIONS", location = "LOCATION", battery = "BATTERY", oemAutostart = "OEM_AUTOSTART" }`.
  - `public enum PermissionStatus: String, Sendable { case granted = "GRANTED", denied = "DENIED", skipped = "SKIPPED" }`.
  - `public struct ProtectionPermission: Hashable, Sendable { kind, status, wasRevoked: Bool, instructionKey: String?; init(kind:status:wasRevoked: = false, instructionKey: = nil); var needsFixing: Bool }`.
  - `public struct ProtectionStatus: Decodable, Equatable, Sendable { childId: UUID, level, permissions: [ProtectionPermission], lastReportAt: Date?, isStale: Bool, manufacturer: String, instructionKey: String?; init(childId:level:permissions:lastReportAt:isStale:manufacturer:instructionKey:) (all but childId defaulted); var kindsToFix: [PermissionKind] }`.
  - `public protocol ProtectionService: Sendable { func status(childId: UUID) async throws -> ProtectionStatus; func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws }`.
  - `public struct ProtectionApi: ProtectionService { public init(client: ApiClient) }`.
  - Test fixtures (NozirInsightsTests only): `protectionApi(_:)`, `permissionJSON(_:_:revoked:key:)`, `protectionJSON(level:permissions:isStale:manufacturer:extra:)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift` — append at the end of the file:

```swift
func protectionApi(_ replies: [FakeTransport.Reply]) -> (ProtectionApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (ProtectionApi(client: client), transport)
}

/// `PermissionStateDto` as the backend writes it: `instructionKey` is absent when null.
func permissionJSON(_ kind: String, _ status: String, revoked: Bool = false, key: String? = nil) -> String {
    let keyField = key.map { #","instructionKey":"\#($0)""# } ?? ""
    return #"{"kind":"\#(kind)","status":"\#(status)","wasRevoked":\#(revoked)\#(keyField)}"#
}

/// `ProtectionStatusResponse` for Ali (`non_null`: `lastReportAt` and
/// `instructionKey` are absent unless `extra` adds them; it must start with a comma).
func protectionJSON(
    level: String = "DEGRADED",
    permissions: [String] = [],
    isStale: Bool = false,
    manufacturer: String = "xiaomi",
    extra: String = ""
) -> String {
    let list = permissions.joined(separator: ",")
    return #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","level":"\#(level)","permissions":[\#(list)],"isStale":\#(isStale),"manufacturer":"\#(manufacturer)"\#(extra)}"#
}
```

`NozirKit/Tests/NozirInsightsTests/ProtectionApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let protectionPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01/protection"

@Suite struct ProtectionApiTests {
    @Test func aStatusIsReadAsTheServerWritesIt() async throws {
        let body = protectionJSON(
            permissions: [
                permissionJSON("USAGE_ACCESS", "GRANTED"),
                permissionJSON("OEM_AUTOSTART", "DENIED", revoked: true, key: "oem.xiaomi.autostart"),
            ],
            extra: #","lastReportAt":"2026-10-07T08:00:00Z","instructionKey":"oem.xiaomi.battery""#
        )
        let (api, transport) = protectionApi([.ok(body)])

        let status = try await api.status(childId: aliId)

        #expect(status == ProtectionStatus(
            childId: aliId,
            level: .degraded,
            permissions: [
                ProtectionPermission(kind: .usageAccess, status: .granted),
                ProtectionPermission(kind: .oemAutostart, status: .denied, wasRevoked: true, instructionKey: "oem.xiaomi.autostart"),
            ],
            lastReportAt: instant("2026-10-07T08:00:00Z"),
            isStale: false,
            manufacturer: "xiaomi",
            instructionKey: "oem.xiaomi.battery"
        ))
        #expect(status.kindsToFix == [.oemAutostart])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == protectionPath)
        #expect(request.queryParameters.isEmpty)
    }

    // Review Focus 1 (spec §3): nothing ever heard from the phone.
    @Test func aPhoneThatNeverReportedIsBrokenAndStale() async throws {
        let all = PermissionKind.allCases.map { permissionJSON($0.rawValue, "DENIED") }
        let (api, _) = protectionApi([.ok(protectionJSON(level: "BROKEN", permissions: all, isStale: true, manufacturer: "*"))])

        let status = try await api.status(childId: aliId)

        #expect(status.level == .broken)
        #expect(status.isStale)
        #expect(status.lastReportAt == nil)
        #expect(status.instructionKey == nil)
        #expect(status.manufacturer == "*")
        #expect(status.kindsToFix == PermissionKind.allCases)
        #expect(status.permissions.allSatisfy { !$0.wasRevoked && $0.instructionKey == nil })
    }

    // Review Focus 2: a newer child app or server never invents a fault here.
    @Test func anUnknownLevelIsHealthyAndAnUnknownKindOrStatusIsLeftOut() async throws {
        let permissions = [
            permissionJSON("CAMERA", "DENIED"),
            permissionJSON("USAGE_ACCESS", "PAUSED"),
            permissionJSON("OVERLAY", "SKIPPED"),
        ]
        let (api, _) = protectionApi([.ok(protectionJSON(level: "SOMETHING_NEW", permissions: permissions))])

        let status = try await api.status(childId: aliId)

        #expect(status.level == .healthy)
        #expect(status.permissions == [ProtectionPermission(kind: .overlay, status: .skipped)])
    }

    // Spec §4.1: optional fields are read defensively.
    @Test func absentOrUnreadableFieldsHaveSafeDefaults() async throws {
        let body = #"{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","lastReportAt":"yesterday","permissions":[{"kind":"BATTERY","status":"GRANTED"}]}"#
        let (api, _) = protectionApi([.ok(body)])

        let status = try await api.status(childId: aliId)

        #expect(status.level == .healthy)
        #expect(status.permissions == [ProtectionPermission(kind: .battery, status: .granted)])
        #expect(status.lastReportAt == nil)
        #expect(!status.isStale)
        #expect(status.manufacturer == "")
        #expect(status.instructionKey == nil)
        #expect(status.kindsToFix.isEmpty)
    }

    @Test func aChildThatIsGoneIsNotFound() async {
        let (api, _) = protectionApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.status(childId: aliId)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func instructionsAreSentForTheKindsAsked() async throws {
        let (api, transport) = protectionApi([.init(status: 202)])

        try await api.sendInstructions(childId: aliId, kinds: [.oemAutostart, .battery])

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == protectionPath + "/send-instructions")
        let body = try #require(request.jsonObject)
        #expect(body["kinds"] as? [String] == ["OEM_AUTOSTART", "BATTERY"])
        #expect(body.count == 1)
    }

    // Global Constraints: one tap, one POST.
    @Test func aRefusedSendIsThrownAndNotRetried() async {
        let (api, transport) = protectionApi([.error(500, code: "INTERNAL_ERROR"), .init(status: 202)])

        do {
            try await api.sendInstructions(childId: aliId, kinds: [.overlay])
            Issue.record("expected a failure")
        } catch {
            #expect(error is ApiFailure)
        }
        #expect(await transport.requests.count == 1)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: FAIL — `cannot find 'ProtectionApi' in scope` (and the other new names).

- [ ] **Step 3: The models**

`NozirKit/Sources/NozirInsights/ProtectionModels.swift`:

```swift
import Foundation

/// `ProtectionLevel`: how much of the protection still works. A level this app
/// does not know reads as healthy (Android `UnknownLevelFallback`): an invented
/// fault would send a parent into the child's settings for nothing.
public enum ProtectionLevel: String, Sendable, Decodable {
    case healthy = "HEALTHY"
    case degraded = "DEGRADED"
    case broken = "BROKEN"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProtectionLevel(rawValue: raw) ?? .healthy
    }
}

/// `PermissionKind`, in the order the child app asks for them.
public enum PermissionKind: String, CaseIterable, Sendable, Encodable {
    case usageAccess = "USAGE_ACCESS"
    case overlay = "OVERLAY"
    case notifications = "NOTIFICATIONS"
    case location = "LOCATION"
    case battery = "BATTERY"
    case oemAutostart = "OEM_AUTOSTART"
}

/// `PermissionStatus`.
public enum PermissionStatus: String, Sendable {
    case granted = "GRANTED"
    case denied = "DENIED"
    case skipped = "SKIPPED"
}

/// `PermissionStateDto`, only ever built from a kind and a status this app
/// knows: one it cannot read is left out, never shown as broken.
public struct ProtectionPermission: Hashable, Sendable {
    public let kind: PermissionKind
    public let status: PermissionStatus
    /// Granted before and not now — the post-update case.
    public let wasRevoked: Bool
    public let instructionKey: String?

    public init(kind: PermissionKind, status: PermissionStatus, wasRevoked: Bool = false, instructionKey: String? = nil) {
        self.kind = kind
        self.status = status
        self.wasRevoked = wasRevoked
        self.instructionKey = instructionKey
    }

    /// Something a parent still has to do about (Android `needsFixing`).
    public var needsFixing: Bool {
        status != .granted
    }
}

/// `ProtectionStatusResponse`. Only `childId` is required; everything else is
/// read defensively, so a newer server never blanks the screen.
public struct ProtectionStatus: Decodable, Equatable, Sendable {
    public let childId: UUID
    public let level: ProtectionLevel
    /// In the order the child app asked for them.
    public let permissions: [ProtectionPermission]
    /// Nil when the phone never reported.
    public let lastReportAt: Date?
    public let isStale: Bool
    /// Lower case as the server stores it ("xiaomi"); "*" when no phone is paired.
    public let manufacturer: String
    public let instructionKey: String?

    public init(
        childId: UUID,
        level: ProtectionLevel = .healthy,
        permissions: [ProtectionPermission] = [],
        lastReportAt: Date? = nil,
        isStale: Bool = false,
        manufacturer: String = "",
        instructionKey: String? = nil
    ) {
        self.childId = childId
        self.level = level
        self.permissions = permissions
        self.lastReportAt = lastReportAt
        self.isStale = isStale
        self.manufacturer = manufacturer
        self.instructionKey = instructionKey
    }

    enum CodingKeys: String, CodingKey {
        case childId, level, permissions, lastReportAt, isStale, manufacturer, instructionKey
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        childId = try container.decode(UUID.self, forKey: .childId)
        level = try container.decodeIfPresent(ProtectionLevel.self, forKey: .level) ?? .healthy
        let raw = (try? container.decodeIfPresent([RawPermission].self, forKey: .permissions)) ?? []
        permissions = raw.compactMap(\.permission)
        lastReportAt = try? container.decodeIfPresent(Date.self, forKey: .lastReportAt)
        isStale = (try? container.decodeIfPresent(Bool.self, forKey: .isStale)) ?? false
        manufacturer = (try? container.decodeIfPresent(String.self, forKey: .manufacturer)) ?? ""
        instructionKey = try? container.decodeIfPresent(String.self, forKey: .instructionKey)
    }

    /// What "Yuborish" sends: every permission not granted, in the server's order.
    public var kindsToFix: [PermissionKind] {
        permissions.filter(\.needsFixing).map(\.kind)
    }
}

/// One `PermissionStateDto` before the app decides whether it can read it.
private struct RawPermission: Decodable {
    let kind: String?
    let status: String?
    let wasRevoked: Bool?
    let instructionKey: String?

    var permission: ProtectionPermission? {
        guard let kind = kind.flatMap(PermissionKind.init(rawValue:)),
              let status = status.flatMap(PermissionStatus.init(rawValue:)) else { return nil }
        return ProtectionPermission(kind: kind, status: status, wasRevoked: wasRevoked ?? false, instructionKey: instructionKey)
    }
}
```

- [ ] **Step 4: The service and the API**

`NozirKit/Sources/NozirInsights/ProtectionService.swift`:

```swift
import Foundation

/// One child's protection and the "send the steps to the phone" action (P18).
/// `ProtectionApi` is the real one; screen-model tests use a scripted fake.
public protocol ProtectionService: Sendable {
    /// A child no longer in this family: 403 `NOT_YOUR_CHILD` (the backend's
    /// child-scope guard) or 404.
    func status(childId: UUID) async throws -> ProtectionStatus
    /// Pushes the fix steps for `kinds` to the child's phone (202, no body).
    /// Sent once and never retried here.
    func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws
}
```

`NozirKit/Sources/NozirInsights/ProtectionApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/children/{childId}/protection` (backend `ProtectionController`).
public struct ProtectionApi: ProtectionService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func path(_ childId: UUID) -> String {
        InsightsApi.childPath(childId) + "/protection"
    }

    public func status(childId: UUID) async throws -> ProtectionStatus {
        try await client.send(ApiRequest(method: .get, path: Self.path(childId)), as: ProtectionStatus.self)
    }

    public func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws {
        let request = try ApiRequest.post(Self.path(childId) + "/send-instructions", json: SendInstructionsBody(kinds: kinds))
        try await client.send(request)
    }
}

/// `SendInstructionsBody`.
private struct SendInstructionsBody: Encodable {
    let kinds: [PermissionKind]
}
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirInsightsTests 170`
Expected: `** TEST SUCCEEDED **`, the 7 new tests among them.

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirInsights/ProtectionModels.swift NozirKit/Sources/NozirInsights/ProtectionService.swift NozirKit/Sources/NozirInsights/ProtectionApi.swift NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift NozirKit/Tests/NozirInsightsTests/ProtectionApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p18: a child's protection status, as the server writes it

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: Home carries the family's protection — `ParentHome.protection` and the row's level and child

**Files:**
- Modify: `NozirKit/Sources/NozirInsights/InsightModels.swift:85-120` (`ParentHome`; new `HomeProtection` after it)
- Modify: `NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift` (new tests before the suite's closing `}` at line 193)
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift` (after `usedMinutesToday(of:)`, line 160)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift:97-105` (`parentHome`)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift` (new tests after `noHomeNoRows`, before the suite's closing `}` at line 327)

**Interfaces:**
- Consumes: `ProtectionLevel` (Task 1); `insightsApi(_:)`, `bareHomeJSON`, `fullHomeJSON`, `aliId` (`InsightsFixtures.swift` — both Home fixtures already carry `"protection":{"level":"HEALTHY","childrenNeedingAttention":[]}`, exactly what `HomeProtectionDto` sends); `homeCard`, `parentHome`, `setup` (HomeModelTests).
- Produces:
  - `public struct HomeProtection: Decodable, Equatable, Sendable { level: ProtectionLevel; childrenNeedingAttention: [UUID]; init(level:childrenNeedingAttention: = []) }`.
  - `ParentHome.protection: HomeProtection?`; `ParentHome.init(…, pendingExtraTimeRequests: = [], protection: HomeProtection? = nil)`.
  - `HomeModel.protectionChildId: UUID?` and `HomeModel.protection: ProtectionLevel?` (plan deviations P2, P3).
  - Test helper: `parentHome(_:date:familySummary:sos:requests:protection:)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift` — add inside `InsightsApiTests`, before its closing `}`:

```swift
    // P18: the family's worst level and who is behind it come with home.
    @Test func homeCarriesTheFamilysProtection() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #""protection":{"level":"HEALTHY","childrenNeedingAttention":[]}"#,
            with: #""protection":{"level":"BROKEN","childrenNeedingAttention":["0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"]}"#
        )
        let (api, _) = insightsApi([.ok(body), .ok(fullHomeJSON)])

        #expect(try await api.home().protection == HomeProtection(level: .broken, childrenNeedingAttention: [aliId]))
        #expect(try await api.home().protection == HomeProtection(level: .healthy, childrenNeedingAttention: []))
    }

    @Test func aHomeWithoutProtectionHasNoRow() async throws {
        let body = bareHomeJSON.replacingOccurrences(
            of: #","protection":{"level":"HEALTHY","childrenNeedingAttention":[]}"#,
            with: ""
        )
        let (api, _) = insightsApi([.ok(body)])

        let home = try await api.home()

        #expect(home.protection == nil)
        #expect(home.children.count == 1)
    }

    // Review Focus 5: an unreadable block is no block; a new level is healthy.
    @Test func protectionThatCannotBeReadLeavesHomeStanding() async throws {
        let unreadable = bareHomeJSON.replacingOccurrences(
            of: #""childrenNeedingAttention":[]"#,
            with: #""childrenNeedingAttention":["not-a-uuid"]"#
        )
        let newLevel = bareHomeJSON.replacingOccurrences(of: #""level":"HEALTHY""#, with: #""level":"SOMETHING_NEW""#)
        let (api, _) = insightsApi([.ok(unreadable), .ok(newLevel)])

        let home = try await api.home()
        #expect(home.protection == nil)
        #expect(home.children.count == 1)

        #expect(try await api.home().protection?.level == .healthy)
    }
```

`NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift` — replace `parentHome` (lines 97-105) with:

```swift
func parentHome(
    _ children: [ChildHomeCard],
    date: LocalDate = day("2026-10-05"),
    familySummary: String? = nil,
    sos: ActiveSos? = nil,
    requests: [ExtraTimeRequest] = [],
    protection: HomeProtection? = nil
) -> ParentHome {
    ParentHome(
        date: date,
        children: children,
        familySummary: familySummary,
        activeSos: sos,
        pendingExtraTimeRequests: requests,
        protection: protection
    )
}
```

`NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift` — add inside `HomeModelTests`, after `noHomeNoRows()`:

```swift
    // Spec §4.2 + P2 and Review Focus 5: the row opens the filtered child, else
    // the first child the server named that is on screen, else the first card;
    // a filtered child the server did not name is healthy.
    @Test func theProtectionRowOpensTheRightChild() async {
        let ali = homeCard("Ali")
        let vali = homeCard("Vali")
        let protection = HomeProtection(level: .broken, childrenNeedingAttention: [UUID(), vali.id])
        let (model, _, _) = setup([.success(parentHome([ali, vali], protection: protection))])

        await model.appear()
        #expect(model.protectionChildId == vali.id)
        #expect(model.protection == .broken)

        model.filter = ali.id
        #expect(model.protectionChildId == ali.id)
        #expect(model.protection == .healthy)

        model.filter = vali.id
        #expect(model.protectionChildId == vali.id)
        #expect(model.protection == .broken)
    }

    @Test func aHealthyFamilyOpensTheFirstChild() async {
        let ali = homeCard("Ali")
        let (model, _, _) = setup([.success(parentHome([ali, homeCard("Vali")], protection: HomeProtection(level: .healthy)))])

        await model.appear()

        #expect(model.protectionChildId == ali.id)
        #expect(model.protection == .healthy)
    }

    @Test func noProtectionOrNoChildNoRow() async {
        let (model, _, _) = setup([
            .success(parentHome([homeCard()])),
            .success(parentHome([], protection: HomeProtection(level: .broken))),
        ])
        #expect(model.protection == nil)

        await model.appear()
        #expect(model.protection == nil)
        #expect(model.protectionChildId == nil)

        await model.load()
        #expect(model.protection == nil)
        #expect(model.protectionChildId == nil)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run, one at a time: `bash .superpowers/run.sh NozirInsightsTests 170`, then `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'HomeProtection' in scope`, `value of type 'ParentHome' has no member 'protection'`, `extra argument 'protection' in call`.

- [ ] **Step 3: `ParentHome` and `HomeProtection`**

In `NozirKit/Sources/NozirInsights/InsightModels.swift`, replace `struct ParentHome` (lines 85-120) with:

```swift
public struct ParentHome: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let children: [ChildHomeCard]
    public let familySummary: String?
    public let activeSos: ActiveSos?
    /// P17 rows, newest first. A list that cannot be read is no list: Home
    /// still loads (plan deviation T6).
    public let pendingExtraTimeRequests: [ExtraTimeRequest]
    /// P18 row. Absent or unreadable is nil: no row, and Home still loads.
    public let protection: HomeProtection?

    public init(
        date: LocalDate,
        children: [ChildHomeCard],
        familySummary: String? = nil,
        activeSos: ActiveSos? = nil,
        pendingExtraTimeRequests: [ExtraTimeRequest] = [],
        protection: HomeProtection? = nil
    ) {
        self.date = date
        self.children = children
        self.familySummary = familySummary
        self.activeSos = activeSos
        self.pendingExtraTimeRequests = pendingExtraTimeRequests
        self.protection = protection
    }

    enum CodingKeys: String, CodingKey {
        case date, children, familySummary, activeSos, pendingExtraTimeRequests, protection
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(LocalDate.self, forKey: .date)
        children = try container.decodeIfPresent([ChildHomeCard].self, forKey: .children) ?? []
        familySummary = try container.decodeIfPresent(String.self, forKey: .familySummary)
        activeSos = try container.decodeIfPresent(ActiveSos.self, forKey: .activeSos)
        pendingExtraTimeRequests = (try? container.decodeIfPresent([ExtraTimeRequest].self, forKey: .pendingExtraTimeRequests)) ?? []
        protection = try? container.decodeIfPresent(HomeProtection.self, forKey: .protection)
    }
}

/// `HomeProtectionDto`: the family's worst level and the children that are not
/// healthy. Only these two fields come with Home.
public struct HomeProtection: Decodable, Equatable, Sendable {
    public let level: ProtectionLevel
    public let childrenNeedingAttention: [UUID]

    public init(level: ProtectionLevel, childrenNeedingAttention: [UUID] = []) {
        self.level = level
        self.childrenNeedingAttention = childrenNeedingAttention
    }

    enum CodingKeys: String, CodingKey {
        case level, childrenNeedingAttention
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decodeIfPresent(ProtectionLevel.self, forKey: .level) ?? .healthy
        childrenNeedingAttention = try container.decodeIfPresent([UUID].self, forKey: .childrenNeedingAttention) ?? []
    }
}
```

- [ ] **Step 4: `HomeModel`**

In `NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift`, after `usedMinutesToday(of:)` (ends line 160) add:

```swift
    /// The child the P18 row opens (spec §4.2): the one the filter shows, else
    /// the first child the server named that has a card here, else the first
    /// card. Nil without protection or without children: no row.
    var protectionChildId: UUID? {
        guard let summary = home?.protection else { return nil }
        if let filter, cards.contains(where: { $0.id == filter }) { return filter }
        let named = summary.childrenNeedingAttention.first { id in cards.contains { $0.id == id } }
        return named ?? cards.first?.id
    }

    /// The P18 row's level; nil hides the row. With the filter on a child the
    /// server did not name, that child is healthy: a red row must not open a
    /// "Himoya faol" screen (plan deviation P2).
    var protection: ProtectionLevel? {
        guard let summary = home?.protection, let childId = protectionChildId else { return nil }
        guard childId == filter else { return summary.level }
        return summary.childrenNeedingAttention.contains(childId) ? summary.level : .healthy
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
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p18: Home carries the family's protection and picks the child it opens

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: The words and tones — `ProtectionTexts` and the test fixtures

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/FakeProtection.swift` (the fake and the fixtures; the fake is used from Task 4)
- Create: `NozirKit/Tests/NozirAppFeatureTests/ProtectionTextsTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Protection/ProtectionTexts.swift`

**Interfaces:**
- Consumes: `ProtectionLevel`, `PermissionKind`, `PermissionStatus`, `ProtectionPermission`, `ProtectionStatus`, `ProtectionService` (Task 1); `ElapsedTime(from:to:)` / `.text(_:)` (`Insights/InsightTexts.swift:6-36`); `LocationTexts.present(_:)` (`Location/LocationTexts.swift:126`); `NozirCardTone` (`NozirCard.swift:3`), `NozirStatusLevel` (`NozirRows.swift:3`); `PauseGate` (`FakeLocation.swift:114`), `offline` (`FakeFamily.swift:5`); the L10n names below (all in `NozirL10n/L10n.generated.swift`).
- Produces (all `static`, internal to `NozirAppFeature`):
  - `ProtectionTexts.homeTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String`, `homeBody(_:_:) -> String`, `cardTone(_ level: ProtectionLevel) -> NozirCardTone`.
  - `levelTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String`, `summaryBody(_ status: ProtectionStatus, _ l10n: L10n) -> String`.
  - `name(_ kind: PermissionKind, _ l10n: L10n) -> String`, `stateLabel(_ permission: ProtectionPermission, _ l10n: L10n) -> String`, `stateNote(_:_:) -> String?`, `stateLine(_:_:) -> String`, `dotLevel(_ permission: ProtectionPermission) -> NozirStatusLevel`.
  - `staleNote(_ status: ProtectionStatus, now: Date, _ l10n: L10n) -> String?`.
  - `steps(_ key: String?, _ l10n: L10n) -> String`, `phone(_ manufacturer: String) -> String`, `instruction(_ status: ProtectionStatus, childName: String?, _ l10n: L10n) -> String?`, `sendTitle(childName: String?, _ l10n: L10n) -> String`.
  - Test support: `actor FakeProtection: ProtectionService` (`Script { status, send, statusGate, sendGate }`, `calls: [String]`, `sent: [[PermissionKind]]`, `add(_:)`), `protectionPermission(_:_:revoked:key:)`, `lastReport` (2026-10-07T08:00:00Z), `protectionStatus(childId:level:permissions:lastReportAt:isStale:manufacturer:instructionKey:)`.

The L10n names used (verified in `L10n.generated.swift`): `homeProtection{Healthy,Degraded,Broken}{Title,Body}`, `protectionLevel{Healthy,Degraded,Broken}Title`, `protectionBodyAllWorking`, `protectionBodyNeedsFixing(_: Int)`, `protectionPermission{UsageAccess,Overlay,Notifications,Location,Battery,Autostart}`, `protectionState{Granted,Revoked,Skipped,Denied}`, `protectionNote{Revoked,Skipped,Denied}`, `protectionStateWithNote(_: String, _: String)`, `protectionStaleNote(_: String)`, `protectionStaleNoteNever`, `oemXiaomiAutostart`, `oemXiaomiBattery`, `oemOppoAutostart`, `oemVivoAutostart`, `oemSamsungBattery`, `oemRealmeAutostart`, `oemInfinixAutostart`, `oemGenericAutostart`, `oemGenericUsage`, `oemGenericOverlay`, `oemGenericBattery`, `protectionInstructionUnknown`, `protectionInstructionLine(_: String, _: String, _: String)` (child, phone, steps), `protectionInstructionLineUnnamed(_: String, _: String)` (phone, steps), `protectionActionSend(_: String)`, `protectionActionSendUnnamed`.

- [ ] **Step 1: The fake and the fixtures**

`NozirKit/Tests/NozirAppFeatureTests/FakeProtection.swift`:

```swift
import Foundation
import NozirInsights
import NozirNetworking

/// Answers the status and each send from its own queue, in order (an empty
/// queue is a phone with no connection), and records what was asked.
actor FakeProtection: ProtectionService {
    struct Script: Sendable {
        var status: [Result<ProtectionStatus, ApiFailure>] = []
        var send: [Result<Void, ApiFailure>] = []
        /// Held once by the next `status` / `sendInstructions` call, after its answer is taken.
        var statusGate: PauseGate?
        var sendGate: PauseGate?
    }

    private var script: Script
    /// "status", "send".
    private(set) var calls: [String] = []
    /// The kinds of each send, in call order.
    private(set) var sent: [[PermissionKind]] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func status(childId: UUID) async throws -> ProtectionStatus {
        calls.append("status")
        let answer: Result<ProtectionStatus, ApiFailure> = script.status.isEmpty ? .failure(offline) : script.status.removeFirst()
        let gate = script.statusGate
        script.statusGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func sendInstructions(childId: UUID, kinds: [PermissionKind]) async throws {
        calls.append("send")
        sent.append(kinds)
        let answer: Result<Void, ApiFailure> = script.send.isEmpty ? .failure(offline) : script.send.removeFirst()
        let gate = script.sendGate
        script.sendGate = nil
        if let gate { await gate.pause() }
        try answer.get()
    }
}

func protectionPermission(
    _ kind: PermissionKind,
    _ status: PermissionStatus = .denied,
    revoked: Bool = false,
    key: String? = nil
) -> ProtectionPermission {
    ProtectionPermission(kind: kind, status: status, wasRevoked: revoked, instructionKey: key)
}

/// 2026-10-07T08:00:00Z.
let lastReport = Date(timeIntervalSince1970: 1_791_360_000)

/// A degraded Xiaomi by default: usage access works, autostart switched itself off.
func protectionStatus(
    childId: UUID = UUID(),
    level: ProtectionLevel = .degraded,
    permissions: [ProtectionPermission] = [
        protectionPermission(.usageAccess, .granted),
        protectionPermission(.oemAutostart, revoked: true, key: "oem.xiaomi.autostart"),
    ],
    lastReportAt: Date? = lastReport,
    isStale: Bool = false,
    manufacturer: String = "xiaomi",
    instructionKey: String? = nil
) -> ProtectionStatus {
    ProtectionStatus(
        childId: childId,
        level: level,
        permissions: permissions,
        lastReportAt: lastReportAt,
        isStale: isStale,
        manufacturer: manufacturer,
        instructionKey: instructionKey
    )
}
```

- [ ] **Step 2: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/ProtectionTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

@Suite struct ProtectionTextsTests {
    private let l10n = L10n(.uz)

    // Spec §5.1 and D2: the Home row's words and card follow the level.
    @Test func theHomeRowFollowsTheLevel() {
        #expect(ProtectionTexts.homeTitle(.healthy, l10n) == l10n.homeProtectionHealthyTitle)
        #expect(ProtectionTexts.homeBody(.healthy, l10n) == l10n.homeProtectionHealthyBody)
        #expect(ProtectionTexts.homeTitle(.degraded, l10n) == l10n.homeProtectionDegradedTitle)
        #expect(ProtectionTexts.homeBody(.degraded, l10n) == l10n.homeProtectionDegradedBody)
        #expect(ProtectionTexts.homeTitle(.broken, l10n) == l10n.homeProtectionBrokenTitle)
        #expect(ProtectionTexts.homeBody(.broken, l10n) == l10n.homeProtectionBrokenBody)
        #expect(ProtectionTexts.cardTone(.healthy) == .plain)
        #expect(ProtectionTexts.cardTone(.degraded) == .attention)
        #expect(ProtectionTexts.cardTone(.broken) == .critical)
    }

    @Test func theSummaryCountsEveryPermissionNotGranted() {
        let mixed = protectionStatus(permissions: [
            protectionPermission(.usageAccess, .granted),
            protectionPermission(.overlay, .denied),
            protectionPermission(.battery, .skipped),
            protectionPermission(.oemAutostart, revoked: true),
        ])

        #expect(ProtectionTexts.levelTitle(.healthy, l10n) == l10n.protectionLevelHealthyTitle)
        #expect(ProtectionTexts.levelTitle(.degraded, l10n) == l10n.protectionLevelDegradedTitle)
        #expect(ProtectionTexts.levelTitle(.broken, l10n) == l10n.protectionLevelBrokenTitle)
        #expect(ProtectionTexts.summaryBody(mixed, l10n) == l10n.protectionBodyNeedsFixing(3))
        #expect(ProtectionTexts.summaryBody(protectionStatus(permissions: [protectionPermission(.overlay, .granted)]), l10n) == l10n.protectionBodyAllWorking)
        #expect(ProtectionTexts.summaryBody(protectionStatus(permissions: []), l10n) == l10n.protectionBodyAllWorking)
    }

    @Test func everyKindHasItsName() {
        #expect(ProtectionTexts.name(.usageAccess, l10n) == l10n.protectionPermissionUsageAccess)
        #expect(ProtectionTexts.name(.overlay, l10n) == l10n.protectionPermissionOverlay)
        #expect(ProtectionTexts.name(.notifications, l10n) == l10n.protectionPermissionNotifications)
        #expect(ProtectionTexts.name(.location, l10n) == l10n.protectionPermissionLocation)
        #expect(ProtectionTexts.name(.battery, l10n) == l10n.protectionPermissionBattery)
        #expect(ProtectionTexts.name(.oemAutostart, l10n) == l10n.protectionPermissionAutostart)
        #expect(Set(PermissionKind.allCases.map { ProtectionTexts.name($0, l10n) }).count == 6)
    }

    // Spec §4.2 (Android PermissionStateLabel / PermissionDisplayLevel): granted
    // works; a revoked one switched itself off (it wins over skipped); skipped
    // was passed over; anything else was never turned on. Never critical.
    @Test func theStateWordAndDotFollowAndroid() {
        let granted = protectionPermission(.overlay, .granted)
        let revoked = protectionPermission(.overlay, .denied, revoked: true)
        let revokedSkipped = protectionPermission(.overlay, .skipped, revoked: true)
        let skipped = protectionPermission(.overlay, .skipped)
        let denied = protectionPermission(.overlay, .denied)

        #expect(ProtectionTexts.stateLabel(granted, l10n) == l10n.protectionStateGranted)
        #expect(ProtectionTexts.stateNote(granted, l10n) == nil)
        #expect(ProtectionTexts.stateLine(granted, l10n) == l10n.protectionStateGranted)
        #expect(ProtectionTexts.dotLevel(granted) == .good)

        #expect(ProtectionTexts.stateLine(revoked, l10n) == l10n.protectionStateWithNote(l10n.protectionStateRevoked, l10n.protectionNoteRevoked))
        #expect(ProtectionTexts.stateLine(revokedSkipped, l10n) == ProtectionTexts.stateLine(revoked, l10n))
        #expect(ProtectionTexts.dotLevel(revoked) == .action)

        #expect(ProtectionTexts.stateLine(skipped, l10n) == l10n.protectionStateWithNote(l10n.protectionStateSkipped, l10n.protectionNoteSkipped))
        #expect(ProtectionTexts.dotLevel(skipped) == .attention)

        #expect(ProtectionTexts.stateLine(denied, l10n) == l10n.protectionStateWithNote(l10n.protectionStateDenied, l10n.protectionNoteDenied))
        #expect(ProtectionTexts.dotLevel(denied) == .attention)
    }

    // Review Focus 1 and P6: how long the phone has been quiet, or that it never spoke.
    @Test func theStaleNoteSaysHowLongOrNever() {
        let now = lastReport.addingTimeInterval(40 * 3_600)

        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: false), now: now, l10n) == nil)
        #expect(ProtectionTexts.staleNote(protectionStatus(lastReportAt: nil, isStale: true), now: now, l10n) == l10n.protectionStaleNoteNever)
        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: true), now: now, l10n) == l10n.protectionStaleNote(l10n.elapsedStaleHours(40)))
        #expect(ProtectionTexts.staleNote(protectionStatus(isStale: true), now: lastReport.addingTimeInterval(2 * 3_600), l10n) == l10n.protectionStaleNote(l10n.elapsedHours(2)))
    }

    // Spec §4.2: the 11 served keys, and the generic steps for anything else.
    @Test func everyServedKeyHasItsSteps() {
        let served: [(String, String)] = [
            ("oem.xiaomi.autostart", l10n.oemXiaomiAutostart),
            ("oem.oppo.autostart", l10n.oemOppoAutostart),
            ("oem.vivo.autostart", l10n.oemVivoAutostart),
            ("oem.realme.autostart", l10n.oemRealmeAutostart),
            ("oem.infinix.autostart", l10n.oemInfinixAutostart),
            ("oem.generic.autostart", l10n.oemGenericAutostart),
            ("oem.xiaomi.battery", l10n.oemXiaomiBattery),
            ("oem.samsung.battery", l10n.oemSamsungBattery),
            ("oem.generic.battery", l10n.oemGenericBattery),
            ("oem.generic.usage", l10n.oemGenericUsage),
            ("oem.generic.overlay", l10n.oemGenericOverlay),
        ]
        for (key, steps) in served {
            #expect(ProtectionTexts.steps(key, l10n) == steps)
        }
        #expect(Set(served.map(\.1)).count == 11)
        #expect(ProtectionTexts.steps("oem.huawei.autostart", l10n) == l10n.protectionInstructionUnknown)
        #expect(ProtectionTexts.steps(nil, l10n) == l10n.protectionInstructionUnknown)
    }

    // D3: one card, for the first permission not granted; its own key wins over the status's.
    @Test func theInstructionIsForTheFirstBrokenPermission() {
        let status = protectionStatus(
            permissions: [
                protectionPermission(.usageAccess, .granted, key: "oem.generic.usage"),
                protectionPermission(.battery, key: "oem.xiaomi.battery"),
                protectionPermission(.oemAutostart, key: "oem.xiaomi.autostart"),
            ],
            instructionKey: "oem.generic.overlay"
        )
        let noOwnKey = protectionStatus(permissions: [protectionPermission(.overlay)], manufacturer: "samsung", instructionKey: "oem.generic.overlay")

        #expect(ProtectionTexts.instruction(status, childName: "Ali", l10n) == l10n.protectionInstructionLine("Ali", "Xiaomi", l10n.oemXiaomiBattery))
        #expect(ProtectionTexts.instruction(noOwnKey, childName: nil, l10n) == l10n.protectionInstructionLineUnnamed("Samsung", l10n.oemGenericOverlay))
        #expect(ProtectionTexts.instruction(noOwnKey, childName: "  ", l10n) == l10n.protectionInstructionLineUnnamed("Samsung", l10n.oemGenericOverlay))
        #expect(ProtectionTexts.instruction(protectionStatus(permissions: [protectionPermission(.overlay, .granted)]), childName: "Ali", l10n) == nil)
    }

    @Test func thePhoneIsTheMakeWithACapital() {
        #expect(ProtectionTexts.phone("xiaomi") == "Xiaomi")
        #expect(ProtectionTexts.phone("Samsung") == "Samsung")
        #expect(ProtectionTexts.phone("") == "")
    }

    @Test func theSendButtonNamesTheChild() {
        #expect(ProtectionTexts.sendTitle(childName: "Ali", l10n) == l10n.protectionActionSend("Ali"))
        #expect(ProtectionTexts.sendTitle(childName: nil, l10n) == l10n.protectionActionSendUnnamed)
        #expect(ProtectionTexts.sendTitle(childName: " ", l10n) == l10n.protectionActionSendUnnamed)
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'ProtectionTexts' in scope`.

- [ ] **Step 4: `ProtectionTexts`**

`NozirKit/Sources/NozirAppFeature/Protection/ProtectionTexts.swift`:

```swift
import Foundation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P18 and its Home row in words and tones (Android `ProtectionRow`,
/// `ProtectionSummaryCard`, `PermissionKindLabel`, `PermissionStateLabel`,
/// `PermissionDisplayLevel`, `ProtectionStaleNotice`, `OemInstructionTextRes`,
/// `OemInstructionCard`, `ProtectionFix`). A blank child name reads as "the child".
enum ProtectionTexts {
    // MARK: Home row and summary card

    static func homeTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.homeProtectionHealthyTitle
        case .degraded: l10n.homeProtectionDegradedTitle
        case .broken: l10n.homeProtectionBrokenTitle
        }
    }

    static func homeBody(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.homeProtectionHealthyBody
        case .degraded: l10n.homeProtectionDegradedBody
        case .broken: l10n.homeProtectionBrokenBody
        }
    }

    /// Spec D2, for the Home row and the summary card only.
    static func cardTone(_ level: ProtectionLevel) -> NozirCardTone {
        switch level {
        case .healthy: .plain
        case .degraded: .attention
        case .broken: .critical
        }
    }

    static func levelTitle(_ level: ProtectionLevel, _ l10n: L10n) -> String {
        switch level {
        case .healthy: l10n.protectionLevelHealthyTitle
        case .degraded: l10n.protectionLevelDegradedTitle
        case .broken: l10n.protectionLevelBrokenTitle
        }
    }

    /// "Barcha ruxsatlar ishlayapti" or "N ta sozlama tuzatilishi kerak"; N counts every permission not granted.
    static func summaryBody(_ status: ProtectionStatus, _ l10n: L10n) -> String {
        let count = status.kindsToFix.count
        return count == 0 ? l10n.protectionBodyAllWorking : l10n.protectionBodyNeedsFixing(count)
    }

    // MARK: Permission rows

    static func name(_ kind: PermissionKind, _ l10n: L10n) -> String {
        switch kind {
        case .usageAccess: l10n.protectionPermissionUsageAccess
        case .overlay: l10n.protectionPermissionOverlay
        case .notifications: l10n.protectionPermissionNotifications
        case .location: l10n.protectionPermissionLocation
        case .battery: l10n.protectionPermissionBattery
        case .oemAutostart: l10n.protectionPermissionAutostart
        }
    }

    /// The word that travels with the colour, so the colour is never alone.
    static func stateLabel(_ permission: ProtectionPermission, _ l10n: L10n) -> String {
        if permission.status == .granted { return l10n.protectionStateGranted }
        if permission.wasRevoked { return l10n.protectionStateRevoked }
        return permission.status == .skipped ? l10n.protectionStateSkipped : l10n.protectionStateDenied
    }

    /// Why it is in that state; nil when it works.
    static func stateNote(_ permission: ProtectionPermission, _ l10n: L10n) -> String? {
        if permission.status == .granted { return nil }
        if permission.wasRevoked { return l10n.protectionNoteRevoked }
        return permission.status == .skipped ? l10n.protectionNoteSkipped : l10n.protectionNoteDenied
    }

    /// "Oʻchib qolgan · Telefon yangilangandan keyin oʻchib qolgan", or just "Ishlayapti".
    static func stateLine(_ permission: ProtectionPermission, _ l10n: L10n) -> String {
        let label = stateLabel(permission, l10n)
        return stateNote(permission, l10n).map { l10n.protectionStateWithNote(label, $0) } ?? label
    }

    /// One that broke by itself outranks one never granted; red is kept for SOS.
    static func dotLevel(_ permission: ProtectionPermission) -> NozirStatusLevel {
        if permission.status == .granted { return .good }
        return permission.wasRevoked ? .action : .attention
    }

    // MARK: Stale note

    /// Nil while the phone reports; otherwise how long it has been quiet, or that it never spoke.
    static func staleNote(_ status: ProtectionStatus, now: Date, _ l10n: L10n) -> String? {
        guard status.isStale else { return nil }
        guard let at = status.lastReportAt else { return l10n.protectionStaleNoteNever }
        return l10n.protectionStaleNote(ElapsedTime(from: at, to: now).text(l10n))
    }

    // MARK: The fix

    /// The steps a served key stands for; a key this release has never heard of gets the generic steps.
    static func steps(_ key: String?, _ l10n: L10n) -> String {
        switch key ?? "" {
        case "oem.xiaomi.autostart": l10n.oemXiaomiAutostart
        case "oem.xiaomi.battery": l10n.oemXiaomiBattery
        case "oem.oppo.autostart": l10n.oemOppoAutostart
        case "oem.vivo.autostart": l10n.oemVivoAutostart
        case "oem.samsung.battery": l10n.oemSamsungBattery
        case "oem.realme.autostart": l10n.oemRealmeAutostart
        case "oem.infinix.autostart": l10n.oemInfinixAutostart
        case "oem.generic.autostart": l10n.oemGenericAutostart
        case "oem.generic.usage": l10n.oemGenericUsage
        case "oem.generic.overlay": l10n.oemGenericOverlay
        case "oem.generic.battery": l10n.oemGenericBattery
        default: l10n.protectionInstructionUnknown
        }
    }

    /// "xiaomi" → "Xiaomi" (Android `replaceFirstChar { it.uppercase() }`).
    static func phone(_ manufacturer: String) -> String {
        manufacturer.prefix(1).uppercased() + String(manufacturer.dropFirst())
    }

    /// "Ali telefonida (Xiaomi): …" for the first permission not granted; nil when all work.
    static func instruction(_ status: ProtectionStatus, childName: String?, _ l10n: L10n) -> String? {
        guard let first = status.permissions.first(where: \.needsFixing) else { return nil }
        let text = steps(first.instructionKey ?? status.instructionKey, l10n)
        let device = phone(status.manufacturer)
        return LocationTexts.present(childName).map { l10n.protectionInstructionLine($0, device, text) }
            ?? l10n.protectionInstructionLineUnnamed(device, text)
    }

    static func sendTitle(childName: String?, _ l10n: L10n) -> String {
        LocationTexts.present(childName).map { l10n.protectionActionSend($0) } ?? l10n.protectionActionSendUnnamed
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
git add NozirKit/Tests/NozirAppFeatureTests/FakeProtection.swift NozirKit/Tests/NozirAppFeatureTests/ProtectionTextsTests.swift NozirKit/Sources/NozirAppFeature/Protection/ProtectionTexts.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p18: protection in words — states, stale note, per-phone steps

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: `ProtectionModel` — load one child's status, send the steps once

**Files:**
- Create: `NozirKit/Tests/NozirAppFeatureTests/ProtectionModelTests.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Protection/ProtectionModel.swift`

**Interfaces:**
- Consumes: `ProtectionService`, `ProtectionStatus.kindsToFix`, `PermissionKind` (Task 1); `FakeProtection`, `protectionStatus`, `protectionPermission` (Task 3); `UserMessage(_:)`, `UserMessage.noConnection/.timeout/.serverProblem` (`UserMessage.swift`); `ApiFailure.isNotFound`, `ApiFailure.code`, `ApiErrorCode.notYourChild` (`ApiErrorCode.swift:30`); `notFound` (`FakeInsights.swift:5`), `offline`, `PauseGate`.
- Produces: `@MainActor @Observable final class ProtectionModel` with `enum Phase: Equatable { case loading, ready, missing, failed(UserMessage) }`, `init(childId: UUID, childName: String?, service: any ProtectionService)`, `let childId: UUID`, `let childName: String?`, `private(set) var status: ProtectionStatus?`, `private(set) var phase: Phase`, `private(set) var isOffline: Bool`, `private(set) var isSending: Bool`, `private(set) var wereInstructionsSent: Bool`, `var toast: UserMessage?`, `var kindsToFix: [PermissionKind]`, `func load() async`, `func sendInstructions() async`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/ProtectionModelTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let notYourChild = ApiFailure.server(status: 403, error: ApiError(code: .notYourChild))

/// Overlay never turned on, battery skipped, autostart switched itself off; usage access works.
private let fourKinds = protectionStatus(childId: childId, level: .broken, permissions: [
    protectionPermission(.usageAccess, .granted),
    protectionPermission(.overlay),
    protectionPermission(.battery, .skipped),
    protectionPermission(.oemAutostart, revoked: true, key: "oem.xiaomi.autostart"),
])

private let allWorking = protectionStatus(childId: childId, level: .healthy, permissions: [
    protectionPermission(.usageAccess, .granted),
    protectionPermission(.oemAutostart, .granted),
])

@MainActor
private func setup(_ script: FakeProtection.Script, name: String? = "Ali") -> (ProtectionModel, FakeProtection) {
    let fake = FakeProtection(script)
    return (ProtectionModel(childId: childId, childName: name, service: fake), fake)
}

@MainActor
@Suite struct ProtectionModelTests {
    @Test func theStatusIsLoaded() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        let (model, fake) = setup(script)
        #expect(model.phase == .loading)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.status == fourKinds)
        #expect(model.kindsToFix == [.overlay, .battery, .oemAutostart])
        #expect(model.childName == "Ali")
        #expect(await fake.calls == ["status"])
    }

    // Review Focus 3 (P1): a removed child is an answer, not a fault.
    @Test(arguments: [notFound, notYourChild])
    func aChildNoLongerInTheFamilyIsMissing(failure: ApiFailure) async {
        var script = FakeProtection.Script()
        script.status = [.failure(failure)]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
        #expect(model.status == nil)
        #expect(model.toast == nil)
        #expect(model.kindsToFix.isEmpty)
    }

    @Test func aFirstFailureCanBeRetried() async {
        var script = FakeProtection.Script()
        script.status = [.failure(.unexpectedStatus(500)), .success(fourKinds)]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    // Spec §4.2: offline (no connection or a timeout) keeps what is on screen.
    @Test(arguments: [offline, ApiFailure.network(code: URLError.Code.timedOut.rawValue)])
    func goingOfflineKeepsTheStatusOnScreen(failure: ApiFailure) async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .failure(failure), .success(allWorking)]
        let (model, _) = setup(script)
        await model.load()

        await model.load()
        #expect(model.phase == .ready)
        #expect(model.status == fourKinds)
        #expect(model.isOffline)
        #expect(model.toast == nil)

        await model.load()
        #expect(!model.isOffline)
        #expect(model.status == allWorking)
        #expect(model.kindsToFix.isEmpty)
    }

    // A server fault over a shown status is not "offline".
    @Test func aServerFaultOverAShownStatusIsSaidNotCalledOffline() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .failure(.unexpectedStatus(500))]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(!model.isOffline)
        #expect(model.toast == .serverProblem)
        #expect(model.status == fourKinds)
        #expect(model.phase == .ready)
    }

    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        var script = FakeProtection.Script()
        script.status = [.success(allWorking), .success(fourKinds)]
        script.statusGate = gate
        let (model, _) = setup(script)

        let older = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        await gate.release()
        await older.value

        #expect(model.status == fourKinds)
    }

    // Review Focus 1 and 4 (D3): every kind not granted, in the server's order, once.
    @Test func sendingSendsEveryKindNotGranted() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.success(())]
        let (model, fake) = setup(script)
        await model.load()

        await model.sendInstructions()

        #expect(await fake.sent == [[.overlay, .battery, .oemAutostart]])
        #expect(model.wereInstructionsSent)
        #expect(!model.isSending)
        #expect(model.toast == nil)
    }

    // Review Focus 4: a second tap while the first is in flight does nothing.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSendOnce() async {
        let gate = PauseGate()
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.success(())]
        script.sendGate = gate
        let (model, fake) = setup(script)
        await model.load()

        let first = Task { await model.sendInstructions() }
        await gate.untilPaused()
        #expect(model.isSending)
        await model.sendInstructions()

        await gate.release()
        await first.value
        #expect(await fake.sent.count == 1)
        #expect(model.wereInstructionsSent)
        #expect(!model.isSending)
    }

    // Review Focus 4: said once, nothing claimed, and the button works again.
    @Test func aFailedSendIsSaidOnceAndCanBeTriedAgain() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds)]
        script.send = [.failure(offline), .success(())]
        let (model, fake) = setup(script)
        await model.load()

        await model.sendInstructions()
        #expect(model.toast == .noConnection)
        #expect(!model.wereInstructionsSent)
        #expect(!model.isSending)
        #expect(await fake.sent.count == 1)

        model.toast = nil
        await model.sendInstructions()
        #expect(await fake.sent.count == 2)
        #expect(model.wereInstructionsSent)
        #expect(model.toast == nil)
    }

    @Test func nothingToFixOrNothingLoadedSendsNothing() async {
        var script = FakeProtection.Script()
        script.status = [.success(allWorking)]
        let (model, fake) = setup(script)

        await model.sendInstructions()
        await model.load()
        await model.sendInstructions()

        #expect(await fake.calls == ["status"])
        #expect(!model.wereInstructionsSent)
    }

    // Spec §4.2: "sent" lasts the screen's life, through a refresh.
    @Test func aRefreshKeepsTheSentNote() async {
        var script = FakeProtection.Script()
        script.status = [.success(fourKinds), .success(fourKinds)]
        script.send = [.success(())]
        let (model, _) = setup(script)
        await model.load()
        await model.sendInstructions()

        await model.load()

        #expect(model.wereInstructionsSent)
    }
}
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'ProtectionModel' in scope`.

- [ ] **Step 3: `ProtectionModel`**

`NozirKit/Sources/NozirAppFeature/Protection/ProtectionModel.swift`:

```swift
import Foundation
import Observation
import NozirInsights
import NozirNetworking

/// P18 (Android `ProtectionViewModel`): one child's protection, and the offer to
/// send the fix steps to the child's phone. A send is one POST: a second tap
/// while it is in flight does nothing, and nothing is retried. A child no
/// longer in the family (404, or 403 `NOT_YOUR_CHILD` from the backend's
/// child-scope guard) is `.missing`, not an error (plan deviation P1).
@MainActor
@Observable
final class ProtectionModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// The child was removed: an answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    let childId: UUID
    /// From the family list; nil reads as "the child".
    let childName: String?
    private(set) var status: ProtectionStatus?
    private(set) var phase: Phase = .loading
    /// A status is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var isSending = false
    /// For the rest of this screen's life: a parent who sees nothing change
    /// presses again, and the child's phone gets the same steps twice.
    private(set) var wereInstructionsSent = false
    /// A failure said once; the view sets it back to nil.
    var toast: UserMessage?

    private let service: any ProtectionService
    /// Bumped by every load: an older answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(childId: UUID, childName: String?, service: any ProtectionService) {
        self.childId = childId
        self.childName = childName
        self.service = service
    }

    /// What "Yuborish" sends; empty hides the fix section.
    var kindsToFix: [PermissionKind] {
        status?.kindsToFix ?? []
    }

    func load() async {
        generation += 1
        let mine = generation
        // A retry from the full error shows the spinner while it asks.
        if status == nil { phase = .loading }
        do {
            let fresh = try await service.status(childId: childId)
            guard mine == generation else { return }
            status = fresh
            phase = .ready
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound || failure.code == ApiErrorCode.notYourChild {
            guard mine == generation else { return }
            status = nil
            phase = .missing
            isOffline = false
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if status == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                toast = message
            }
        }
    }

    /// Every permission not granted, once; a failure is a toast and the button works again.
    func sendInstructions() async {
        let kinds = kindsToFix
        guard !kinds.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }
        do {
            try await service.sendInstructions(childId: childId, kinds: kinds)
            wereInstructionsSent = true
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
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/ProtectionModelTests.swift NozirKit/Sources/NozirAppFeature/Protection/ProtectionModel.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p18: the protection screen's model — load, offline, send once

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: P18 screen, the Home row, the child's page row, and the wiring (with accessibility)

**Files:**
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift:19-45` (`setup`) and a new test before the suite's closing `}` (after `theTimeRequestScreenIsForTheAskTapped`)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift:29-70` (service), after `makeTimeRequestModel` (line 182) (factory)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:82`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/ProtectionRow.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/ProtectionView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift` (lines 6-35 init, 119 and 175 rows, new `protectionRow` after `timeRequestRows`, line 206)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift:6-17, 30-32`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`HomeStep` line 20, `ProfileStep` line 42, `HomeView(…)` lines 61-69, `homeDestination` lines 173-178 and 191-192, `profileDestination` lines 199-204 and 219-220)

**Interfaces:**
- Consumes: `ProtectionApi`, `ProtectionService`, `ProtectionLevel`, `ProtectionStatus`, `ProtectionPermission` (Task 1); `HomeModel.protection`, `HomeModel.protectionChildId` (Task 2); `ProtectionTexts.*` (Task 3); `ProtectionModel` (Task 4); `FakeProtection`, `protectionStatus` (Task 3); `makeChild` (`FakeFamily.swift:236`); `FamilyStore.child(_:)`; design system `NozirCard(tone:)`, `NozirStatusDot(_:)`, `NozirSettingsRow(_:value:action:)`, `NozirButton(_:variant:size:isLoading:action:)`, `NozirEmptyState(title:message:)`, `NozirErrorState(title:message:retryTitle:onRetry:)`, `NozirOfflineNotice(_:)`, `.nozirToast(_:)`, `.nozirText(_:color:)`, `NozirColor.*`, `NozirSpacing.*`, `NozirRadius.cardCompact`; L10n `screenProtectionTitle`, `glyphShield`, `glyphChevron`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`, `protectionNoChildTitle`, `protectionNoChildBody`, `protectionEmptyTitle`, `protectionEmptyBody`, `protectionPermissionsLabel`, `protectionInstructionLabel`, `protectionSendSent`.
- Produces: `SignedInModel.init(…, extraTime:, protection: any ProtectionService, location:, …)`; `SignedInModel.makeProtectionModel(childId: UUID) -> ProtectionModel`; `SignedInView.HomeStep.protection(UUID)`, `SignedInView.ProfileStep.protection(UUID)`; `HomeView.init(…, onOpenProtection: @escaping (UUID) -> Void, onAddChild:)`; `ChildDetailsView.init(model:onRemoved:onOpenRules:onOpenProtection:)`; `ProtectionRow(level:action:)`, `ProtectionShield(level:)`, `ProtectionView(model:)`.

- [ ] **Step 1: Write the failing test**

In `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`, replace `setup` (lines 19-45) with:

```swift
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales(),
    extraTime: FakeExtraTime = FakeExtraTime(),
    protection: FakeProtection = FakeProtection(),
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

Add inside `SignedInModelTests`, after `theTimeRequestScreenIsForTheAskTapped()`:

```swift
    // P18 (P4): the screen is for the child tapped, named from the family list.
    @Test func theProtectionScreenIsForTheChildTapped() async {
        let ali = makeChild("Ali")
        var family = FakeFamily.Script()
        family.children = [.success([ali])]
        var script = FakeProtection.Script()
        script.status = [.success(protectionStatus(childId: ali.id))]
        let (model, _) = setup(family, protection: FakeProtection(script))
        try? await model.family.refresh()

        let screen = model.makeProtectionModel(childId: ali.id)
        await screen.load()

        #expect(screen.childId == ali.id)
        #expect(screen.childName == "Ali")
        #expect(screen.phase == .ready)
        #expect(model.makeProtectionModel(childId: UUID()).childName == nil)
    }
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra argument 'protection' in call`, `value of type 'SignedInModel' has no member 'makeProtectionModel'`.

- [ ] **Step 3: `SignedInModel`**

In `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:

After `private let extraTime: any ExtraTimeService` (line 30) add:

```swift
    private let protection: any ProtectionService
```

In `init`, after the parameter `extraTime: any ExtraTimeService,` (line 45) add:

```swift
        protection: any ProtectionService,
```

and after `self.extraTime = extraTime` (line 58) add:

```swift
        self.protection = protection
```

After `makeTimeRequestModel(id:usedMinutesToday:)` (ends line 182) add:

```swift

    /// P18 for one child, named from the family list (nil: "the child").
    func makeProtectionModel(childId: UUID) -> ProtectionModel {
        ProtectionModel(childId: childId, childName: family.child(childId)?.displayName, service: protection)
    }
```

- [ ] **Step 4: `AppEnvironment`**

In `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`, after `extraTime: ExtraTimeApi(client: authorised),` (line 82) add:

```swift
            protection: ProtectionApi(client: authorised),
```

- [ ] **Step 5: Run the test to see it pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: `ProtectionRow`**

`NozirKit/Sources/NozirAppFeature/Screens/ProtectionRow.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// The Home "Himoya" row (Android `ProtectionRow`), in the card tone of spec
/// D2. One button for VoiceOver: the title and body say the level; the
/// shield and the chevron are decoration.
struct ProtectionRow: View {
    let level: ProtectionLevel
    let action: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        Button(action: action) {
            NozirCard(tone: ProtectionTexts.cardTone(level)) {
                HStack(spacing: NozirSpacing.compact) {
                    ProtectionShield(level: level)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ProtectionTexts.homeTitle(level, l10n)).nozirText(.body)
                        Text(ProtectionTexts.homeBody(level, l10n))
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Text(l10n.glyphChevron)
                        .nozirText(.titleSmall, color: NozirColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The shield tile; decoration only. Healthy sits on the good colour; on a
/// tinted card the tile is the plain card colour, so it stays visible.
struct ProtectionShield: View {
    let level: ProtectionLevel
    @Environment(\.l10n) private var l10n

    var body: some View {
        Text(l10n.glyphShield)
            .font(.system(size: 18))
            .frame(width: 40, height: 40)
            .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(tile))
            .accessibilityHidden(true)
    }

    private var tile: Color {
        level == .healthy ? NozirColor.goodContainer : NozirColor.card
    }
}
```

- [ ] **Step 7: `ProtectionView`**

`NozirKit/Sources/NozirAppFeature/Screens/ProtectionView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P18 as Android `ProtectionContent`: the offline notice, the summary card,
/// the stale note, the permissions, then — only when something is not granted —
/// the steps for this phone and the button that sends them to it.
struct ProtectionView: View {
    @State private var model: ProtectionModel
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: ProtectionModel) {
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
        .navigationTitle(l10n.screenProtectionTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // Back from another app (spec D5): the child may have fixed it meanwhile.
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
            NozirEmptyState(title: l10n.protectionNoChildTitle, message: l10n.protectionNoChildBody)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready:
            if let status = model.status {
                summaryCard(status)
                if let note = ProtectionTexts.staleNote(status, now: Date(), l10n) {
                    NozirOfflineNotice(note)
                }
                permissionsCard(status)
                fix(status)
            }
        }
    }

    /// Where protection stands, in one line, before any list of toggles.
    private func summaryCard(_ status: ProtectionStatus) -> some View {
        NozirCard(tone: ProtectionTexts.cardTone(status.level)) {
            HStack(spacing: NozirSpacing.compact) {
                ProtectionShield(level: status.level)
                VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                    Text(ProtectionTexts.levelTitle(status.level, l10n))
                        .nozirText(.titleSmall)
                        .accessibilityAddTraits(.isHeader)
                    Text(ProtectionTexts.summaryBody(status, l10n))
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    /// In the order the child app asked for them (plan deviation P5: the card's heading).
    @ViewBuilder
    private func permissionsCard(_ status: ProtectionStatus) -> some View {
        if status.permissions.isEmpty {
            NozirEmptyState(title: l10n.protectionEmptyTitle, message: l10n.protectionEmptyBody)
        } else {
            NozirCard {
                Text(l10n.protectionPermissionsLabel)
                    .nozirText(.label, color: NozirColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(Array(status.permissions.enumerated()), id: \.offset) { entry in
                    if entry.offset > 0 {
                        Divider()
                    }
                    permissionRow(entry.element)
                }
            }
        }
    }

    /// The dot, the word and its colour say the same thing; VoiceOver reads the words.
    private func permissionRow(_ permission: ProtectionPermission) -> some View {
        let level = ProtectionTexts.dotLevel(permission)
        return HStack(spacing: NozirSpacing.compact) {
            NozirStatusDot(level)
            VStack(alignment: .leading, spacing: 2) {
                Text(ProtectionTexts.name(permission.kind, l10n)).nozirText(.body)
                Text(ProtectionTexts.stateLine(permission, l10n)).nozirText(.bodySmall, color: color(level))
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ level: NozirStatusLevel) -> Color {
        switch level {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }

    /// Nothing when everything works: an "all fine" evening ends at the list.
    @ViewBuilder
    private func fix(_ status: ProtectionStatus) -> some View {
        if let instruction = ProtectionTexts.instruction(status, childName: model.childName, l10n) {
            NozirCard {
                Text(l10n.protectionInstructionLabel)
                    .nozirText(.label, color: NozirColor.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Text(instruction).nozirText(.body)
            }
            NozirButton(
                ProtectionTexts.sendTitle(childName: model.childName, l10n),
                size: .callToAction,
                isLoading: model.isSending
            ) {
                Task { await model.sendInstructions() }
            }
            .disabled(model.isSending)
            if model.wereInstructionsSent {
                Text(l10n.protectionSendSent).nozirText(.bodySmall, color: NozirColor.goodContent)
            }
        }
    }
}
```

- [ ] **Step 8: The Home row**

In `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`:

Replace the doc comment on line 7 (`/// family (empty, one child, or many). The banner opens P15; P16–P18 are not in this slice.`) with:

```swift
/// family (empty, one child, or many). The banner opens P15; P16 is not in this slice.
```

After `private let onOpenTimeRequest: (UUID, Int?) -> Void` (line 14) add:

```swift
    private let onOpenProtection: (UUID) -> Void
```

In `init`, after the parameter `onOpenTimeRequest: @escaping (UUID, Int?) -> Void,` (line 25) add:

```swift
        onOpenProtection: @escaping (UUID) -> Void,
```

and after `self.onOpenTimeRequest = onOpenTimeRequest` (line 33) add:

```swift
        self.onOpenProtection = onOpenProtection
```

In `singleChild`, after `timeRequestRows` (line 119) add a line:

```swift
        protectionRow
```

In `family`, after `timeRequestRows` (line 175) add a line:

```swift
        protectionRow
```

After the `timeRequestRows` property (ends line 206) add:

```swift

    /// P18: after the P17 rows, before the stat cards or the child cards (spec §5.1).
    @ViewBuilder
    private var protectionRow: some View {
        if let level = model.protection, let childId = model.protectionChildId {
            ProtectionRow(level: level) { onOpenProtection(childId) }
        }
    }
```

- [ ] **Step 9: The child's page row**

In `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`, replace lines 6-17 (doc comment through `init`) with:

```swift
/// Android `ChildDetailsScreen`: edit, the frozen lock, remove; the rules and
/// protection rows open P09 and P18 for this child.
struct ChildDetailsView: View {
    @State private var model: ChildDetailsModel
    private let onRemoved: () -> Void
    private let onOpenRules: () -> Void
    private let onOpenProtection: () -> Void
    @Environment(\.l10n) private var l10n

    init(
        model: ChildDetailsModel,
        onRemoved: @escaping () -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenProtection: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onRemoved = onRemoved
        self.onOpenRules = onOpenRules
        self.onOpenProtection = onOpenProtection
    }
```

Replace the rules card (lines 30-32):

```swift
                NozirCard {
                    NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                }
```

with:

```swift
                NozirCard {
                    NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                    Divider()
                    NozirSettingsRow(l10n.screenProtectionTitle, action: onOpenProtection)
                }
```

- [ ] **Step 10: The navigation**

In `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

In `enum HomeStep`, after `case timeRequest(UUID, usedMinutesToday: Int?)` (line 20) add:

```swift
        /// P18 for that child, from the Home row or the child's page.
        case protection(UUID)
```

In `enum ProfileStep`, after `case privacy` (line 42) add:

```swift
        /// P18 from the child's page opened in this tab.
        case protection(UUID)
```

Replace the `HomeView(…)` call (lines 61-69) with:

```swift
                HomeView(
                    model: model.makeHomeModel(),
                    reloadToken: model.homeRefresh,
                    emergencyNumber: { model.currentEmergencyNumber },
                    onOpenSummary: { homePath.append(.summary($0, $1)) },
                    onOpenSos: { homePath.append(.sos($0)) },
                    onOpenTimeRequest: { homePath.append(.timeRequest($0, usedMinutesToday: $1)) },
                    onOpenProtection: { homePath.append(.protection($0)) },
                    onAddChild: { model.presentAddChild() }
                )
```

In `homeDestination(_:)`, replace the `.details` branch (lines 173-178) with:

```swift
        case .details(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { homePath.append(.rules(child.id)) },
                onOpenProtection: { homePath.append(.protection(child.id)) }
            )
```

and after the `.timeRequest` branch (lines 191-192) add:

```swift
        case .protection(let childId):
            ProtectionView(model: model.makeProtectionModel(childId: childId))
```

In `profileDestination(_:)`, replace the `.child` branch (lines 199-204) with:

```swift
        case .child(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { profilePath.append(.childRules(child.id)) },
                onOpenProtection: { profilePath.append(.protection(child.id)) }
            )
```

and after the `.privacy` branch (lines 219-220) add:

```swift
        case .protection(let childId):
            ProtectionView(model: model.makeProtectionModel(childId: childId))
```

- [ ] **Step 11: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 12: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Sources/NozirAppFeature/Screens/ProtectionRow.swift NozirKit/Sources/NozirAppFeature/Screens/ProtectionView.swift NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p18: the protection row on Home and the child's page, and its screen

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 6: Final check — whole suite, l10n, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, l10n up to date (no new key), `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `git diff --stat 83e765d -- NozirKit/l10n NozirKit/Sources/NozirL10n NozirKit/Package.swift` is empty.

- [ ] **Step 2: E2E (the user; simulator + the real backend + an Android child phone paired to the family, and the Android parent app on the same family)**

Write "yes" or what was seen against each line:

1. Every permission granted on the child phone → iOS Home (pull to refresh) shows a plain "Himoya faol" row (🛡 on a green tile, ›) after the summary card and the P17 rows, above the two stat tiles.
2. Turn off "Avtoishga tushish" (or usage access) on the child phone, wait for its next report → pull to refresh on Home: the row turns yellow ("Himoya toʻliq emas") or red ("Himoya ishlamayapti") as the server's level says; the Android parent app shows the same level.
3. Tap the row → P18 titled "Himoya holati": the summary card in the same tone, "N ta sozlama tuzatilishi kerak"; the "Ruxsatlar" card lists the permissions in the child app's order, each with a dot and "Oʻchib qolgan · Telefon yangilangandan keyin oʻchib qolgan" / "Yoqilmagan · Bu ruxsat hali berilmagan" / "Ishlayapti".
4. "Nima qilish kerak" shows "Ali telefonida (Xiaomi): …" (the make with a capital) with that phone's steps; "Aliga yoʻriqnoma yuborish" → spinner, then "Yoʻriqnoma yuborildi. Bola telefonida koʻrinadi."; the child phone gets the push. Backend log: one POST with only the kinds not granted.
5. Double-tap the send button quickly → one POST in the backend log.
6. Airplane mode on P18: pull to refresh → offline notice, the list stays; tap send → toast "Internet aloqasi yoʻq…", "yuborildi" not shown, the button works again once online.
7. Fix the permission on the child phone, come back to the iOS app (background → foreground) on P18 → it refreshes by itself to "Himoya faol", the fix section is gone.
8. A child whose phone never reported (a freshly added child, unpaired or paired without opening Nozir) → P18 red, "Bola telefonidan hali xabar kelmagan — bu holat taxminiy.", six "Yoqilmagan" rows; record the phone text in the instruction line (open question Q1).
9. A phone silent for more than 36 hours (or the server's clock moved) → "Bola telefonidan N soat… oldin xabar kelgan — bu holat taxminiy."
10. Two children, one broken: the family Home row is red and opens the broken child; tap the healthy child's avatar → the row turns plain and opens that child ("Himoya faol"); "Hammasi" → red again.
11. Profile → a child → "Himoya holati" row under "Qoidalar" opens P18 for that child; the same from Home → the child's summary → edit child.
12. Remove the child on the Android parent app while iOS P18 for that child is open, pull to refresh → "Bola tanlanmagan", no error text, no retry button.
13. VoiceOver: the summary title, "Ruxsatlar" and "Nima qilish kerak" are headings; 🛡, › and the dots are silent; each permission reads name + state; the Home row reads as one button. Largest Dynamic Type: nothing cut, the send button's label wraps.
14. Three languages and both themes: every P18 text correct, the red and yellow cards readable in dark mode; screenshots (Cmd+S).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.

## Open questions (ruled while planning)

- **Q1 — a child with no paired phone.** The backend falls back to `manufacturer = "*"` (`ProtectionServiceImpl.FALLBACK_MANUFACTURER`) when the child has no paired device, so the instruction line would read "Ali telefonida (*): …" — Android shows the same. The spec forbids new keys and names no fallback. Ruling: follow Android (no special case); E2E line 8 records what the parent reads, for a later copy decision.
- **Q2 — the stale note's clock.** Android stamps `now` when the status arrives; this plan reads `Date()` when the view draws (plan deviation P6), so the note never lags behind a screen left open. The difference is at most the time since the last load.
