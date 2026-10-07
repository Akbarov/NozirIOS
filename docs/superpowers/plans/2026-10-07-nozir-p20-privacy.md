# Nozir iOS — P20: Privacy and account deletion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A parent opens "Maxfiylik" from Profile, reads what Nozir sees and does not see (the server's own list, the same one the child's phone shows), and an OWNER can request deletion of the whole family; after the request the app signs out locally, and on the next sign-in within the wait the screen shows "request received, date" with no button.

**Architecture:** A new small module `NozirPrivacy` (models + `PrivacyService` protocol + `PrivacyApi`), built the way `NozirInsights` and `NozirLocation` are, with a scripted `FakePrivacy` in `NozirAppFeatureTests`. `ApiClient` gains `sendUnlessNoContent` so `GET …/current` can answer `nil` on 204. `NozirAppFeature/Privacy/PrivacyModel` (`@MainActor @Observable`) loads the disclosure, the current request and the parent's role in parallel and walks the deletion stages; `PrivacyView` draws it with the deletion section pinned to the bottom. `AppModel` keeps a `PrivacyConfig` (wait in days, policy URL) from the server config and gains `signOutLocally()` (tokens cleared, no `/v1/auth/logout`), which `SignedInModel` hands to the privacy model.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; no third-party libraries.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-p20-privacy-design.md` §4 (iOS). The backend half (§3) is planned separately; this plan assumes its endpoints behave as §3 says: `POST /v1/parent/data-deletion-requests` → 202, `GET …/current` → 200 / 204, GUARDIAN → 403, every parent's session revoked on POST.

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). No third-party libraries.
- Every `/v1/parent/*` call goes through `ApiClient`; the deletion request is **never retried automatically** (one tap, one POST).
- `GET /v1/parent/privacy/disclosure` → `PrivacyDisclosure{documentVersion, locale, seen:[{key,text}], notSeen:[{key,text}]}`. No disclosure text is ever written in the app: no fallback list, no cache.
- `POST /v1/parent/data-deletion-requests` body `{}` → 202 `ErasureRequest{requestId, executableAt, requestedAt?}`.
- `GET /v1/parent/data-deletion-requests/current` → 200 `ErasureRequestStatus{requestId, status, requestedAt, executableAt}` or 204 → `nil`. Only the 204 status means "nothing"; an empty 200 is a decoding failure.
- `ServerConfig.dataDeletionDelayDays: Int?` (absent → `nil`); on screen only a positive value is named.
- `PrivacyModel.deletion`: `.unknown`, `.idle`, `.confirming`, `.submitting`, `.requested(executableAt: Date)`. A failed `current` read → `.unknown` (section hidden). Owner = `role == "OWNER"`; a GUARDIAN sees no button in `.idle` but does see the `.requested` card.
- `confirmDelete()` only from `.confirming` (a second tap is ignored); success → local sign-out (tokens cleared, server `logout` **not** called); 403 / network / any other failure → toast + `.idle`; `CancellationError` → back to `.confirming`, no toast.
- User-facing text only from `L10n`, errors only through `UserMessage`; the server's `message` is never shown. **No new l10n key**: every key the screen needs already exists in uz/en/ru (`gen_l10n.py --check` stays clean).
- Out of scope: cancelling a request, deleting one child, any final message, the backend.
- Tests: Swift Testing; `FakePrivacy`, `FakeFamily`, `PauseGate`; a test that uses a gate is `@Test(.timeLimit(.minutes(5)))`.
- Commits: never `git add -A`, explicit paths only; push is the user's.
- Swift code is "written, not verified" until its test run says `** TEST SUCCEEDED **`.

## Spec deviations (decided while planning)

| # | Spec | Plan | Why |
|---|---|---|---|
| R1 | `isOwner` from `ParentAccount.role` | `ParentProfile` (the `GET /v1/parent/me` answer) gains `role: String?`; `PrivacyModel.load()` reads it with `me()` alongside the other two calls | `ParentAccount` is only decoded inside `TelegramSignIn` and is not kept after sign-in; `/v1/parent/me` returns the same `ParentAccountResponse` with `role` |
| R2 | 204 → `nil` | New `ApiClient.sendUnlessNoContent(_:as:)` | `send(_:as:)` decodes the empty 204 body and fails with `.decoding`; there was no 204 path for a value |
| R3 | — | A role that could not be read counts as "not owner": no button, the server is not asked | Fail closed: the button must never appear for a guardian; an owner pulls to refresh |
| R4 | `CancellationError` → "holat tiklanadi" | Back to `.confirming` (the stage it left) | The card the parent was reading stays in place |
| R5 | Success → `onSignedOut()` | The model first sets `.requested(executableAt:)`, then calls `onSignedOut` | The screen never flashes back to the button while the session is torn down |
| R6 | `requestId` | Decoded as `String` | The app never uses it; a String cannot fail on the id's format |
| R7 | `privacyPolicyRow` "URL bo'sh bo'lmasa" | Shown only for an `http`/`https` URL with a host (`PrivacyConfig.policyURL`) | A link that opens nothing is worse than none (Android `PrivacyPolicyRow`) |
| R8 | Caption `privacyCaptionChild(nom)` / `privacyCaptionChildren` | The name is used only when the family has exactly one child whose name is not blank | Android `loadChildName`: never name one of several |
| R9 | `privacyDocumentVersion(v)` | Not drawn when the server sent an empty version | "Hujjat versiyasi: " with nothing after it reads as a fault |

## Review Focus

1. **A 200 with an empty body on `GET …/current`** (a proxy, a broken server) must not read as "no request" and offer a second deletion — only the 204 status means nothing → Task 1 `onlyTheNoContentStatusMeansNothing`.
2. **Pull-to-refresh while the confirmation card is open, or while the POST is in flight** — the card (or the spinner) stays; a `current` answer never pulls it back to the button → Task 4 `aRefreshKeepsTheConfirmationOpen`, `aRefreshDuringTheRequestKeepsItSubmitting`.
3. **Two loads racing** (`.task` and `.refreshable`, or a retry) — an older answer never overwrites a newer one → Task 4 `anOlderLoadNeverOverwritesANewerOne`.
4. **The parent's role cannot be read** (`/v1/parent/me` fails) — no delete button, but a pending request's card still shows → Task 4 `anUnreadableRoleOffersNoButtonButShowsTheRequest`.
5. **Server config with a wait of 0 or less, or a blank / non-web policy URL** — the confirmation names no number and the policy row is not drawn → Task 3 `PrivacyConfigTests`.

---

## File map

**New:**
- `NozirKit/Sources/NozirPrivacy/PrivacyModels.swift` — `DisclosureItem`, `PrivacyDisclosure`, `ErasureRequest`, `ErasureRequestStatus`.
- `NozirKit/Sources/NozirPrivacy/PrivacyService.swift` — `PrivacyService`.
- `NozirKit/Sources/NozirPrivacy/PrivacyApi.swift` — `PrivacyApi`.
- `NozirKit/Tests/NozirPrivacyTests/PrivacyApiTests.swift`.
- `NozirKit/Sources/NozirAppFeature/PrivacyConfig.swift` — `PrivacyConfig`.
- `NozirKit/Sources/NozirAppFeature/Privacy/PrivacyModel.swift` — `PrivacyModel`.
- `NozirKit/Sources/NozirAppFeature/Screens/PrivacyView.swift` — `PrivacyView`.
- `NozirKit/Tests/NozirAppFeatureTests/FakePrivacy.swift`, `NozirKit/Tests/NozirAppFeatureTests/PrivacyModelTests.swift`, `NozirKit/Tests/NozirAppFeatureTests/PrivacyConfigTests.swift`.

**Modified:** `NozirKit/Package.swift`; `NozirNetworking/ApiClient.swift`; `NozirConfig/ServerConfig.swift`; `NozirFamily/AccountModels.swift`; `NozirAppFeature/{AppModel,AppEnvironment,SignedInModel}.swift`; `NozirAppFeature/Insights/InsightTexts.swift`; `NozirAppFeature/Screens/{ProfileView,SignedInView}.swift`; tests `NozirNetworkingTests/ApiClientTests.swift`, `NozirConfigTests/ConfigTests.swift`, `NozirFamilyTests/RulesAndPairingApiTests.swift`, `NozirAppFeatureTests/{AppModelTests,SignedInModelTests,InsightTextsTests}.swift`.

## Getting started

Branch `privacy` (spec commit `f7ee8d3`) is checked out. The Mac's files are reached through `device_bash` (`cd $HOME/mnt/XCodeProjects/NozirIOS && …`). Swift tests run through the watcher on the Mac, one request at a time, each as its own `device_bash` call with `timeout_ms: 180000`:

`cd $HOME/mnt/XCodeProjects/NozirIOS && bash .superpowers/run.sh <Target> 170`

`<Target>` is a test target (`NozirNetworkingTests`, `NozirConfigTests`, `NozirFamilyTests`, `NozirPrivacyTests`, `NozirAppFeatureTests`), `all` (whole suite) or `app` (build the app). If the answer is `TIMEOUT waiting …`, the request is still running: do not send it again; wait and read `.superpowers/test-result.log` until its `### done` line appears.

After every commit: `rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete`.

---
### Task 1: Foundations — 204 as "nothing", the deletion wait, the parent's role

**Files:**
- Modify: `NozirKit/Sources/NozirNetworking/ApiClient.swift:32-100` (`send`, `perform`, `endSession`, `checked`)
- Modify: `NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift` (new tests before the suite's closing `}` at line 243)
- Modify: `NozirKit/Sources/NozirConfig/ServerConfig.swift:1-32`
- Modify: `NozirKit/Tests/NozirConfigTests/ConfigTests.swift` (helper `config(updateRequired:)` lines 16-34, new suite at the end)
- Modify: `NozirKit/Sources/NozirFamily/AccountModels.swift:76-87` (`ParentProfile`)
- Modify: `NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift` (new tests after `theParentsRecordAndLanguage`, ~line 185)

**Interfaces:**
- Consumes: `ApiClient.perform` (private), `ResponseMapping.failure(status:body:)`, `NozirJSON.decoder()`, `FakeTransport`, `.ok`, `.error`, `familyApi(_:)` (`FamilyFixtures.swift`).
- Produces:
  - `ApiClient.sendUnlessNoContent<Response: Decodable>(_ request: ApiRequest, as type: Response.Type) async throws -> Response?` — `nil` exactly when the status is 204.
  - `ServerConfig.dataDeletionDelayDays: Int?`; `ServerConfig.init(minSupportedVersion:latestVersion:updateRequired:featureFlags:emergencyContacts:privacyPolicyUrl:termsUrl:supportUrl:dataDeletionDelayDays: Int? = nil)`.
  - `ParentProfile.role: String?` (`"OWNER"` / `"GUARDIAN"`, nil when absent); `ParentProfile.init(displayName:phoneE164:locale:role: String? = nil)`.

- [ ] **Step 1: Write the failing tests**

`NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift` — add inside `ApiClientTests`, before its closing `}`:

```swift
    // P20: GET …/data-deletion-requests/current answers 204 when nothing is pending.
    @Test func aNoContentAnswerReadsAsNothing() async throws {
        let transport = FakeTransport([.init(status: 204)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        let echo = try await client.sendUnlessNoContent(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        #expect(echo == nil)
    }

    @Test func aBodyIsDecodedWhenThereIsOne() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        let echo = try await client.sendUnlessNoContent(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        #expect(echo == Echo(value: "x"))
    }

    // Review Focus 1: only the status says "nothing"; an empty 200 is a fault.
    @Test func onlyTheNoContentStatusMeansNothing() async {
        let client = ApiClient(baseURL: base, transport: FakeTransport([.init(status: 200)]), identity: identity)

        do {
            _ = try await client.sendUnlessNoContent(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
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

    @Test func aRefusalIsStillThrownWhenNothingIsAllowed() async {
        let transport = FakeTransport([.error(403, code: "FORBIDDEN")])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        await #expect(throws: ApiFailure.server(
            status: 403,
            error: ApiError(code: .forbidden, message: "server text")
        )) {
            try await client.sendUnlessNoContent(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }
```

`NozirKit/Tests/NozirConfigTests/ConfigTests.swift` — in the helper `config(updateRequired:)` (lines 16-34) the fixture body already carries `"dataDeletionDelayDays":30`, so the expected value must too. Replace the helper with:

```swift
private func config(updateRequired: Bool) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: ["PHONE_OTP_SIGN_IN": false],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: "https://nozir.syncoder.uz/privacy",
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support",
        dataDeletionDelayDays: 30
    )
}
```

and append at the end of the file:

```swift
@Suite struct ServerConfigDecodingTests {
    @Test func theDeletionWaitIsRead() throws {
        let decoded = try NozirJSON.decoder().decode(ServerConfig.self, from: Data(configBody(updateRequired: false).utf8))

        #expect(decoded.dataDeletionDelayDays == 30)
    }

    // An older server, or a config cached before this field existed.
    @Test func aConfigWithoutTheDeletionWaitHasNone() throws {
        let body = configBody(updateRequired: false).replacingOccurrences(of: #""dataDeletionDelayDays":30,"#, with: "")

        let decoded = try NozirJSON.decoder().decode(ServerConfig.self, from: Data(body.utf8))

        #expect(decoded.dataDeletionDelayDays == nil)
    }
}
```

`NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift` — add after `theParentsRecordAndLanguage` (inside the suite):

```swift
    // P20: only an owner may ask for the family's data to be deleted.
    @Test func theParentsRoleIsRead() async throws {
        let parent = #"{"parentId":"\#(UUID().uuidString)","familyId":"\#(UUID().uuidString)","phoneE164":null,"displayName":"Zohid","locale":"uz","timeZone":"Asia/Tashkent","role":"GUARDIAN","createdAt":"2026-10-01T08:00:00Z"}"#
        let (api, _) = familyApi([.ok(parent)])

        #expect(try await api.me().role == "GUARDIAN")
    }

    @Test func aParentRecordWithoutARoleStillReads() async throws {
        let parent = #"{"displayName":"Zohid","phoneE164":null,"locale":"uz"}"#
        let (api, _) = familyApi([.ok(parent)])

        let me = try await api.me()

        #expect(me.displayName == "Zohid")
        #expect(me.role == nil)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirNetworkingTests 170`
Expected: FAIL — `value of type 'ApiClient' has no member 'sendUnlessNoContent'`.

- [ ] **Step 3: `ApiClient.sendUnlessNoContent`**

In `NozirKit/Sources/NozirNetworking/ApiClient.swift` replace everything from `public func send<Response: Decodable>(` (line 32) through the end of `endSession(_:rejecting:)` (line 73) with:

```swift
    public func send<Response: Decodable>(_ request: ApiRequest, as type: Response.Type) async throws -> Response {
        try Self.decode(Response.self, from: try await perform(request).data)
    }

    /// For a read whose "nothing" is a 204 (no pending deletion request): nil
    /// then, the decoded body on any other success. Only the status says
    /// "nothing" — an empty 200 is still a decoding failure.
    public func sendUnlessNoContent<Response: Decodable>(_ request: ApiRequest, as type: Response.Type) async throws -> Response? {
        let answer = try await perform(request)
        guard answer.status != 204 else { return nil }
        return try Self.decode(Response.self, from: answer.data)
    }

    public func send(_ request: ApiRequest) async throws {
        _ = try await perform(request)
    }

    private static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do {
            return try NozirJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw ApiFailure.decoding(String(describing: error))
        }
    }

    private func perform(_ request: ApiRequest) async throws -> (data: Data, status: Int) {
        guard request.requiresAuth else {
            let answer = try await transmit(request, bearer: nil)
            return try checked(answer)
        }
        guard let tokens else { throw ApiFailure.sessionEnded }
        let token = try await tokens.validAccessToken()
        let first = try await transmit(request, bearer: token)
        guard first.response.statusCode == 401 else { return try checked(first) }
        guard Self.isExpiry(first.data) else { return try await endSession(tokens, rejecting: token) }
        let renewed = try await tokens.refreshAfterRejection(of: token)
        let second = try await transmit(request, bearer: renewed)
        guard second.response.statusCode == 401 else { return try checked(second) }
        return try await endSession(tokens, rejecting: renewed)
    }

    /// Only an expired access token is worth a refresh. A 401 without the error
    /// body (a proxy's page) is given the benefit of the doubt: one refresh decides.
    private static func isExpiry(_ body: Data) -> Bool {
        guard case .server(_, let error) = ResponseMapping.failure(status: 401, body: body) else {
            return true
        }
        return error.code == .tokenExpired
    }

    private func endSession(_ tokens: any AccessTokenProvider, rejecting token: String) async throws -> (data: Data, status: Int) {
        await tokens.endSession(rejecting: token)
        throw ApiFailure.sessionEnded
    }
```

and replace `checked(_:)` (lines 94-100) with:

```swift
    private func checked(_ answer: (data: Data, response: HTTPURLResponse)) throws -> (data: Data, status: Int) {
        let status = answer.response.statusCode
        guard (200..<300).contains(status) else {
            throw ResponseMapping.failure(status: status, body: answer.data)
        }
        return (answer.data, status)
    }
```

`transmit` and `makeURLRequest` are unchanged.

- [ ] **Step 4: `ServerConfig.dataDeletionDelayDays`**

Replace lines 1-32 of `NozirKit/Sources/NozirConfig/ServerConfig.swift` (the `ServerConfig` struct; `EmergencyContacts` below it is unchanged) with:

```swift
/// `ServerConfigResponse`, reduced to what the app reads.
public struct ServerConfig: Codable, Equatable, Sendable {
    public let minSupportedVersion: String
    public let latestVersion: String
    /// Computed by the server from `X-Nozir-Client` (`ClientVersions.isBelow`).
    public let updateRequired: Bool
    public let featureFlags: [String: Bool]
    public let emergencyContacts: EmergencyContacts
    public let privacyPolicyUrl: String
    public let termsUrl: String
    public let supportUrl: String
    /// How long a deletion request waits before it runs (P20). Nil from an
    /// older server or a config cached before the field existed.
    public let dataDeletionDelayDays: Int?

    public init(
        minSupportedVersion: String,
        latestVersion: String,
        updateRequired: Bool,
        featureFlags: [String: Bool],
        emergencyContacts: EmergencyContacts,
        privacyPolicyUrl: String,
        termsUrl: String,
        supportUrl: String,
        dataDeletionDelayDays: Int? = nil
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.latestVersion = latestVersion
        self.updateRequired = updateRequired
        self.featureFlags = featureFlags
        self.emergencyContacts = emergencyContacts
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.supportUrl = supportUrl
        self.dataDeletionDelayDays = dataDeletionDelayDays
    }
}
```

(The synthesized `Decodable` reads an optional with `decodeIfPresent`, so an absent key is `nil`; `UserDefaultsConfigCache` round-trips through the same `Codable`.)

- [ ] **Step 5: `ParentProfile.role`**

Replace lines 76-87 of `NozirKit/Sources/NozirFamily/AccountModels.swift` with:

```swift
/// `ParentAccountResponse`, the parts P21 and P20 use.
public struct ParentProfile: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let phoneE164: String?
    public let locale: String
    /// `ParentRole`: "OWNER" or "GUARDIAN". Kept a string, like `ParentAccount.role`;
    /// nil when the server did not say, which P20 reads as "not the owner".
    public let role: String?

    public init(displayName: String?, phoneE164: String?, locale: String, role: String? = nil) {
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.locale = locale
        self.role = role
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run, one at a time: `bash .superpowers/run.sh NozirNetworkingTests 170`, then `bash .superpowers/run.sh NozirConfigTests 170`, then `bash .superpowers/run.sh NozirFamilyTests 170`.
Expected: `** TEST SUCCEEDED **` three times (existing tests, including `aNoContentAnswerIsASuccess` and `asksAsTheIOSParentAppWithoutABearer`, pass unchanged).

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirNetworking/ApiClient.swift NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift NozirKit/Sources/NozirConfig/ServerConfig.swift NozirKit/Tests/NozirConfigTests/ConfigTests.swift NozirKit/Sources/NozirFamily/AccountModels.swift NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p20: a 204 reads as nothing; the deletion wait and the parent's role are read

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 2: `NozirPrivacy` — the disclosure and the deletion request, as the server writes them

**Files:**
- Modify: `NozirKit/Package.swift` (whole file shown)
- Create: `NozirKit/Sources/NozirPrivacy/PrivacyModels.swift`
- Create: `NozirKit/Sources/NozirPrivacy/PrivacyService.swift`
- Create: `NozirKit/Sources/NozirPrivacy/PrivacyApi.swift`
- Create: `NozirKit/Tests/NozirPrivacyTests/PrivacyApiTests.swift`

**Interfaces:**
- Consumes: `ApiClient.send(_:as:)`, `ApiClient.sendUnlessNoContent(_:as:)` (Task 1), `ApiRequest.post(_:json:)`, `NozirTestSupport` (`FakeTransport`, `.ok`, `.error`, `URLRequest.jsonObject`).
- Produces (all `public`, module `NozirPrivacy`):
  - `struct DisclosureItem: Decodable, Equatable, Sendable { let key: String; let text: String; init(key:text:) }`
  - `struct PrivacyDisclosure: Decodable, Equatable, Sendable { let documentVersion: String; let locale: String; let seen: [DisclosureItem]; let notSeen: [DisclosureItem]; var isEmpty: Bool; init(documentVersion:locale:seen:notSeen:) }` — absent fields decode as `""` / `[]`.
  - `struct ErasureRequest: Decodable, Equatable, Sendable { let requestId: String; let requestedAt: Date?; let executableAt: Date; init(requestId:requestedAt:executableAt:) }`
  - `struct ErasureRequestStatus: Decodable, Equatable, Sendable { let requestId: String; let status: String; let requestedAt: Date; let executableAt: Date; init(requestId:status:requestedAt:executableAt:) }`
  - `protocol PrivacyService: Sendable { func disclosure() async throws -> PrivacyDisclosure; func requestDeletion() async throws -> ErasureRequest; func currentDeletion() async throws -> ErasureRequestStatus? }`
  - `struct PrivacyApi: PrivacyService { init(client: ApiClient) }`
  - Package: library target `NozirPrivacy` (depends on `NozirNetworking`); test target `NozirPrivacyTests`; `NozirAppFeature` and `NozirAppFeatureTests` depend on `NozirPrivacy`.

- [ ] **Step 1: Add the targets**

Replace `NozirKit/Package.swift` with:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NozirKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NozirAppFeature", targets: ["NozirAppFeature"]),
    ],
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirL10n"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirFamily", dependencies: ["NozirNetworking"]),
        .target(name: "NozirInsights", dependencies: ["NozirNetworking"]),
        .target(name: "NozirLocation", dependencies: ["NozirNetworking"]),
        .target(name: "NozirPrivacy", dependencies: ["NozirNetworking"]),
        .target(name: "NozirDesignSystem"),
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n", "NozirFamily", "NozirInsights", "NozirLocation", "NozirPrivacy"]
        ),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirConfigTests", dependencies: ["NozirConfig", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirFamilyTests", dependencies: ["NozirFamily", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirInsightsTests", dependencies: ["NozirInsights", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirLocationTests", dependencies: ["NozirLocation", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirPrivacyTests", dependencies: ["NozirPrivacy", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirDesignSystemTests", dependencies: ["NozirDesignSystem"]),
        .testTarget(name: "NozirL10nTests", dependencies: ["NozirL10n"]),
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n", "NozirFamily", "NozirDesignSystem", "NozirInsights", "NozirLocation", "NozirPrivacy"]
        ),
    ]
)
```

(The NozirKit scheme is generated by Xcode, as it was when `NozirLocationTests` was added in `fce2fca`; nothing else lists test targets.)

- [ ] **Step 2: Write the failing tests**

Create `NozirKit/Tests/NozirPrivacyTests/PrivacyApiTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirPrivacyTests 170`
Expected: FAIL — a build error: the `NozirPrivacy` target has no sources yet (`no such module 'NozirPrivacy'` or SwiftPM's "no source files" for that target).

- [ ] **Step 4: The models**

Create `NozirKit/Sources/NozirPrivacy/PrivacyModels.swift`:

```swift
import Foundation

/// One line of the disclosure (`DisclosureItemDto`). The text is the server's;
/// the app never writes a line of its own.
public struct DisclosureItem: Decodable, Equatable, Sendable {
    public let key: String
    public let text: String

    public init(key: String, text: String) {
        self.key = key
        self.text = text
    }
}

/// `TransparencyDisclosureResponse`: the same document the child's phone reads,
/// so the two screens cannot drift apart. Missing fields read as empty, like
/// Android `PrivacyDisclosureDto`.
public struct PrivacyDisclosure: Decodable, Equatable, Sendable {
    public let documentVersion: String
    public let locale: String
    public let seen: [DisclosureItem]
    /// The more important half.
    public let notSeen: [DisclosureItem]

    public init(documentVersion: String, locale: String, seen: [DisclosureItem], notSeen: [DisclosureItem]) {
        self.documentVersion = documentVersion
        self.locale = locale
        self.seen = seen
        self.notSeen = notSeen
    }

    private enum CodingKeys: String, CodingKey {
        case documentVersion, locale, seen, notSeen
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentVersion = try container.decodeIfPresent(String.self, forKey: .documentVersion) ?? ""
        locale = try container.decodeIfPresent(String.self, forKey: .locale) ?? ""
        seen = try container.decodeIfPresent([DisclosureItem].self, forKey: .seen) ?? []
        notSeen = try container.decodeIfPresent([DisclosureItem].self, forKey: .notSeen) ?? []
    }

    /// Nothing on either side: the screen says the list could not be had.
    public var isEmpty: Bool {
        seen.isEmpty && notSeen.isEmpty
    }
}

/// The 202 from `POST /v1/parent/data-deletion-requests`
/// (`DataDeletionRequestResponse`). Nothing has been deleted; `executableAt`
/// is when it will be.
public struct ErasureRequest: Decodable, Equatable, Sendable {
    public let requestId: String
    public let requestedAt: Date?
    public let executableAt: Date

    public init(requestId: String, requestedAt: Date?, executableAt: Date) {
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.executableAt = executableAt
    }
}

/// `GET /v1/parent/data-deletion-requests/current`: the family's pending
/// request, the only date the screen quotes.
public struct ErasureRequestStatus: Decodable, Equatable, Sendable {
    public let requestId: String
    public let status: String
    public let requestedAt: Date
    public let executableAt: Date

    public init(requestId: String, status: String, requestedAt: Date, executableAt: Date) {
        self.requestId = requestId
        self.status = status
        self.requestedAt = requestedAt
        self.executableAt = executableAt
    }
}
```

- [ ] **Step 5: The service and the API**

Create `NozirKit/Sources/NozirPrivacy/PrivacyService.swift`:

```swift
import Foundation

/// Everything P20 asks the server. `PrivacyApi` is the real one; screen-model
/// tests use a scripted fake.
public protocol PrivacyService: Sendable {
    func disclosure() async throws -> PrivacyDisclosure
    /// The whole family (body `{}`). An owner only: a guardian gets 403. The
    /// server revokes every parent's session when it records the request.
    func requestDeletion() async throws -> ErasureRequest
    /// nil: no pending request (204).
    func currentDeletion() async throws -> ErasureRequestStatus?
}
```

Create `NozirKit/Sources/NozirPrivacy/PrivacyApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/privacy/disclosure` and `/v1/parent/data-deletion-requests`.
/// The deletion request is never retried here: two taps on purpose are two
/// requests, a replay by the app is not.
public struct PrivacyApi: PrivacyService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func disclosure() async throws -> PrivacyDisclosure {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/privacy/disclosure"), as: PrivacyDisclosure.self)
    }

    public func requestDeletion() async throws -> ErasureRequest {
        // `{}`: no childId — P20 is not a per-child control (spec D5).
        try await client.send(try .post("/v1/parent/data-deletion-requests", json: [String: String]()), as: ErasureRequest.self)
    }

    public func currentDeletion() async throws -> ErasureRequestStatus? {
        try await client.sendUnlessNoContent(
            ApiRequest(method: .get, path: "/v1/parent/data-deletion-requests/current"),
            as: ErasureRequestStatus.self
        )
    }
}
```

- [ ] **Step 6: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirPrivacyTests 170`, then `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **` both times (the second proves the new dependency did not break the feature target).

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirPrivacy/PrivacyModels.swift NozirKit/Sources/NozirPrivacy/PrivacyService.swift NozirKit/Sources/NozirPrivacy/PrivacyApi.swift NozirKit/Tests/NozirPrivacyTests/PrivacyApiTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "privacy: the server's disclosure, and a deletion request for the whole family

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 3: `AppModel` — the privacy config, and a sign-out that does not call the server

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/PrivacyConfig.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppModel.swift` (properties ~17-21, `signOut` ~62-68, `evaluate` ~89-97)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift` (helper `config(updateRequired:)` lines 7-25; new tests before the suite's closing `}`)
- Create: `NozirKit/Tests/NozirAppFeatureTests/PrivacyConfigTests.swift`

**Interfaces:**
- Consumes: `ServerConfig.dataDeletionDelayDays`, `ServerConfig.privacyPolicyUrl` (Task 1), `TokenStore.clear()`.
- Produces:
  - `struct PrivacyConfig: Equatable, Sendable { let deletionDelayDays: Int?; let policyURL: URL?; static let absent: PrivacyConfig; init(deletionDelayDays: Int?, policyURL: URL?); init(_ config: ServerConfig?) }` (internal, module `NozirAppFeature`) — days only when positive; URL only `http`/`https` with a host.
  - `AppModel.privacyConfig: PrivacyConfig` (internal getter, `private(set)`), refreshed whenever the config is (re)read.
  - `AppModel.signOutLocally()` (public): clears the tokens and moves to `.signedOut`; never calls `logout`.

- [ ] **Step 1: Write the failing tests**

Create `NozirKit/Tests/NozirAppFeatureTests/PrivacyConfigTests.swift`:

```swift
import Foundation
import Testing
import NozirConfig
@testable import NozirAppFeature

private func serverConfig(days: Int?, policy: String) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: false,
        featureFlags: [:],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: policy,
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support",
        dataDeletionDelayDays: days
    )
}

@Suite struct PrivacyConfigTests {
    @Test func theWaitAndThePolicyAreTheServers() {
        let config = PrivacyConfig(serverConfig(days: 7, policy: "https://nozir.syncoder.uz/privacy"))

        #expect(config == PrivacyConfig(deletionDelayDays: 7, policyURL: URL(string: "https://nozir.syncoder.uz/privacy")))
    }

    @Test func noConfigNamesNothing() {
        #expect(PrivacyConfig(nil) == .absent)
    }

    // Review Focus 5: a wait that is not a wait is not stated.
    @Test(arguments: [0, -3])
    func aWaitOfNoDaysIsNotNamed(days: Int) {
        #expect(PrivacyConfig(serverConfig(days: days, policy: "https://nozir.syncoder.uz/privacy")).deletionDelayDays == nil)
    }

    @Test func anOlderServerWithoutTheWaitNamesNoNumber() {
        #expect(PrivacyConfig(serverConfig(days: nil, policy: "https://nozir.syncoder.uz/privacy")).deletionDelayDays == nil)
    }

    // Review Focus 5: a link that opens nothing is worse than no link.
    @Test(arguments: ["", "   ", "nozir.syncoder.uz/privacy", "mailto:privacy@nozir.uz", "https://"])
    func aPolicyThatIsNotAWebPageHasNoRow(policy: String) {
        #expect(PrivacyConfig(serverConfig(days: 7, policy: policy)).policyURL == nil)
    }

    @Test func aPolicyWithSpacesAroundItIsStillALink() {
        let config = PrivacyConfig(serverConfig(days: 7, policy: "  https://nozir.syncoder.uz/privacy \n"))

        #expect(config.policyURL == URL(string: "https://nozir.syncoder.uz/privacy"))
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift` — replace the helper `config(updateRequired:)` (lines 7-25) with:

```swift
private func config(updateRequired: Bool, deletionDays: Int? = nil) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: [:],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: "https://nozir.syncoder.uz/privacy",
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support",
        dataDeletionDelayDays: deletionDays
    )
}
```

and add inside `AppModelTests`, before its closing `}`:

```swift
    // P20: the server has already revoked every session; asking it to log out
    // again would only fail.
    @Test func signingOutLocallyForgetsTheSessionWithoutTheServer() async {
        let tokens = InMemoryTokenStore(someTokens)
        let logout = LogoutEndpoint()
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: logout)
        await model.start()

        model.signOutLocally()

        #expect(await logout.calls == 0)
        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func thePrivacyConfigComesWithTheServerConfig() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false, deletionDays: 7)), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.privacyConfig == PrivacyConfig(
            deletionDelayDays: 7,
            policyURL: URL(string: "https://nozir.syncoder.uz/privacy")
        ))
    }

    @Test func noConfigNoPrivacyConfig() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.privacyConfig == .absent)
    }
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'PrivacyConfig' in scope`, `value of type 'AppModel' has no member 'signOutLocally'`.

- [ ] **Step 3: `PrivacyConfig`**

Create `NozirKit/Sources/NozirAppFeature/PrivacyConfig.swift`:

```swift
import Foundation
import NozirConfig

/// What P20 takes from the server config. Both are the server's to state and
/// neither is the app's to invent: without a config there is no number of
/// days and no link (Android `PrivacyViewModel.loadServerConfig`).
struct PrivacyConfig: Equatable, Sendable {
    /// Positive, or nil: the confirmation then names no number.
    let deletionDelayDays: Int?
    /// A web page, or nil: the policy row is not drawn.
    let policyURL: URL?

    static let absent = PrivacyConfig(deletionDelayDays: nil, policyURL: nil)

    init(deletionDelayDays: Int?, policyURL: URL?) {
        self.deletionDelayDays = deletionDelayDays
        self.policyURL = policyURL
    }

    init(_ config: ServerConfig?) {
        guard let config else {
            self = .absent
            return
        }
        let days = config.dataDeletionDelayDays.flatMap { $0 > 0 ? $0 : nil }
        self.init(deletionDelayDays: days, policyURL: Self.webPage(config.privacyPolicyUrl))
    }

    private static func webPage(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}
```

- [ ] **Step 4: `AppModel`**

In `NozirKit/Sources/NozirAppFeature/AppModel.swift`:

After `public private(set) var emergencyNumber: String?` (line 21) add:

```swift

    /// From the server config, for P20: the deletion wait and the policy link.
    private(set) var privacyConfig = PrivacyConfig.absent
```

After `signOut()` (ends line 68) add:

```swift

    /// P20: a deletion request has been recorded and the server has already
    /// revoked every parent's session, so it is not asked again — the session
    /// is only forgotten here.
    public func signOutLocally() {
        tokens.clear()
        phase = .signedOut
    }
```

In `evaluate()`, after `emergencyNumber = loaded?.emergencyContacts.emergencyNumber` add:

```swift
        privacyConfig = PrivacyConfig(loaded)
```

- [ ] **Step 5: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **` (existing `AppModelTests` pass unchanged: the helper's new argument has a default).

- [ ] **Step 6: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/PrivacyConfig.swift NozirKit/Sources/NozirAppFeature/AppModel.swift NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift NozirKit/Tests/NozirAppFeatureTests/PrivacyConfigTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "app: the deletion wait and the policy link, and a sign-out the server already did

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 4: `PrivacyModel` — the lists, the role, and ask → confirm → done

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Privacy/PrivacyModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift` (`DateTexts`, after `weekRange` ~line 57)
- Create: `NozirKit/Tests/NozirAppFeatureTests/FakePrivacy.swift`
- Create: `NozirKit/Tests/NozirAppFeatureTests/PrivacyModelTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift` (new test inside `InsightTextsTests`, before its closing `}` at line 112)

**Interfaces:**
- Consumes: `PrivacyService`, `PrivacyDisclosure`, `DisclosureItem`, `ErasureRequest`, `ErasureRequestStatus` (Task 2); `ParentProfile.role` (Task 1); `PrivacyConfig` (Task 3); `FamilyStore` (`children`, `service`, `refresh()`), `FamilyService.me()`; `UserMessage(_:)`; `LocalDate(_:in:)`; `L10n.dateDayMonthYear`, `privacyCaptionChild`, `privacyCaptionChildren`, `privacyDeleteBody`, `privacyDeleteBodyWithDays`, `privacyDeleteRequestedBody`; test side `FakeFamily`, `offline`, `makeChild`, `PauseGate`.
- Produces:
  - `DateTexts.dayMonthAndYear(_ date: LocalDate, _ l10n: L10n) -> String` ("14-oktabr 2026", "October 14, 2026").
  - `@MainActor @Observable final class PrivacyModel` (internal):
    - `enum Deletion: Equatable { case unknown, idle, confirming, submitting, requested(executableAt: Date) }`
    - `private(set) var disclosure: PrivacyDisclosure?`, `loadFailure: UserMessage?`, `isOffline: Bool`, `deletion: Deletion` (starts `.unknown`), `isOwner: Bool`; `var toast: UserMessage?` (the view clears it); `let config: PrivacyConfig`
    - `init(privacy: any PrivacyService, family: FamilyStore, config: PrivacyConfig, calendar: Calendar = PrivacyModel.phoneCalendar, onSignedOut: @escaping @MainActor () -> Void)`
    - `nonisolated static var phoneCalendar: Calendar`
    - `func load() async`; `var canRequestDeletion: Bool`; `func startDelete()`; `func cancelDelete()`; `func confirmDelete() async`
    - `func caption(_ l10n: L10n) -> String`; `func deleteBody(_ l10n: L10n) -> String`; `func requestedBody(_ executableAt: Date, _ l10n: L10n) -> String`
  - Test side: `actor FakePrivacy: PrivacyService` with `Script { disclosure, current, request: [Result<…, ApiFailure>]; cancelNextRequest: Bool; disclosureGate: PauseGate?; requestGate: PauseGate? }`, `calls: [String]` (`"disclosure"`, `"current"`, `"request"`); fixtures `deletionDate`, `sampleDisclosure`, `pendingRequest`, `recordedRequest`.

- [ ] **Step 1: The fake**

Create `NozirKit/Tests/NozirAppFeatureTests/FakePrivacy.swift`:

```swift
import Foundation
import NozirNetworking
import NozirPrivacy

/// Answers each privacy call from its own queue, in order, and records what
/// was asked. An empty queue answers like a phone with no connection.
actor FakePrivacy: PrivacyService {
    struct Script: Sendable {
        var disclosure: [Result<PrivacyDisclosure, ApiFailure>] = []
        var current: [Result<ErasureRequestStatus?, ApiFailure>] = []
        var request: [Result<ErasureRequest, ApiFailure>] = []
        /// When true the next `requestDeletion` throws `CancellationError` once.
        var cancelNextRequest = false
        /// Held once by the next `disclosure` call, after its answer is taken.
        var disclosureGate: PauseGate?
        /// Held once by the next `requestDeletion` call, after its answer is taken.
        var requestGate: PauseGate?
    }

    private var script: Script
    private(set) var calls: [String] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func disclosure() async throws -> PrivacyDisclosure {
        calls.append("disclosure")
        let answer: Result<PrivacyDisclosure, ApiFailure> = script.disclosure.isEmpty ? .failure(offline) : script.disclosure.removeFirst()
        let gate = script.disclosureGate
        script.disclosureGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }

    func currentDeletion() async throws -> ErasureRequestStatus? {
        calls.append("current")
        let answer: Result<ErasureRequestStatus?, ApiFailure> = script.current.isEmpty ? .failure(offline) : script.current.removeFirst()
        return try answer.get()
    }

    func requestDeletion() async throws -> ErasureRequest {
        calls.append("request")
        if script.cancelNextRequest {
            script.cancelNextRequest = false
            throw CancellationError()
        }
        let answer: Result<ErasureRequest, ApiFailure> = script.request.isEmpty ? .failure(offline) : script.request.removeFirst()
        let gate = script.requestGate
        script.requestGate = nil
        if let gate { await gate.pause() }
        return try answer.get()
    }
}

/// 2026-10-14T10:00:00Z.
let deletionDate = Date(timeIntervalSince1970: 1_791_972_000)

let sampleDisclosure = PrivacyDisclosure(
    documentVersion: "2026-10-01",
    locale: "uz",
    seen: [DisclosureItem(key: "screen_time", text: "Ekran vaqti"), DisclosureItem(key: "location", text: "Joylashuv")],
    notSeen: [DisclosureItem(key: "messages", text: "Xabarlar")]
)

let pendingRequest = ErasureRequestStatus(
    requestId: "r-1",
    status: "PENDING",
    requestedAt: deletionDate.addingTimeInterval(-7 * 86_400),
    executableAt: deletionDate
)

let recordedRequest = ErasureRequest(
    requestId: "r-1",
    requestedAt: deletionDate.addingTimeInterval(-7 * 86_400),
    executableAt: deletionDate
)
```

- [ ] **Step 2: Write the failing tests**

`NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift` — add inside `InsightTextsTests`:

```swift
    @Test func aDayWithItsYear() {
        #expect(DateTexts.dayMonthAndYear(ymd("2026-10-14"), l10n) == "14-oktabr 2026")
        #expect(DateTexts.dayMonthAndYear(ymd("2026-10-14"), L10n(.en)) == "October 14, 2026")
    }
```

Create `NozirKit/Tests/NozirAppFeatureTests/PrivacyModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
import NozirPrivacy
@testable import NozirAppFeature

@MainActor
private final class SignOutSpy {
    private(set) var count = 0

    func signOut() {
        count += 1
    }
}

private let owner = ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER")
private let guardian = ParentProfile(displayName: "Malika", phoneE164: nil, locale: "uz", role: "GUARDIAN")
private let forbidden = ApiFailure.server(status: 403, error: ApiError(code: .forbidden))

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// `times` loads' worth of answers: the list, and the current request.
private func loaded(current: Result<ErasureRequestStatus?, ApiFailure> = .success(nil), times: Int = 1) -> FakePrivacy.Script {
    var script = FakePrivacy.Script()
    script.disclosure = Array(repeating: .success(sampleDisclosure), count: times)
    script.current = Array(repeating: current, count: times)
    return script
}

@MainActor
private func setup(
    _ script: FakePrivacy.Script,
    parents: [Result<ParentProfile, ApiFailure>] = [.success(owner)],
    children: [Child] = [],
    config: PrivacyConfig = PrivacyConfig(deletionDelayDays: 7, policyURL: nil)
) async -> (PrivacyModel, FakePrivacy, SignOutSpy) {
    var familyScript = FakeFamily.Script()
    familyScript.me = parents
    familyScript.children = [.success(children)]
    let family = FamilyStore(service: FakeFamily(familyScript))
    try? await family.refresh()
    let fake = FakePrivacy(script)
    let spy = SignOutSpy()
    let model = PrivacyModel(privacy: fake, family: family, config: config, calendar: utc, onSignedOut: { spy.signOut() })
    return (model, fake, spy)
}

@MainActor
@Suite struct PrivacyModelTests {
    private let l10n = L10n(.uz)

    @Test func anOwnerSeesTheServersListAndTheButton() async {
        let (model, fake, _) = await setup(loaded())

        await model.load()

        #expect(model.disclosure == sampleDisclosure)
        #expect(model.loadFailure == nil)
        #expect(!model.isOffline)
        #expect(model.deletion == .idle)
        #expect(model.isOwner)
        #expect(model.canRequestDeletion)
        #expect(await fake.calls.sorted() == ["current", "disclosure"])
    }

    @Test func aPendingRequestShowsItsDateAndNoButton() async {
        let (model, _, _) = await setup(loaded(current: .success(pendingRequest)))

        await model.load()

        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(!model.canRequestDeletion)
        #expect(model.requestedBody(deletionDate, l10n) == l10n.privacyDeleteRequestedBody("14-oktabr 2026"))
        #expect(model.requestedBody(deletionDate, L10n(.en)) == L10n(.en).privacyDeleteRequestedBody("October 14, 2026"))
    }

    @Test func aRequestThatCannotBeReadHidesTheSection() async {
        let (model, _, _) = await setup(loaded(current: .failure(offline)))

        await model.load()

        #expect(model.disclosure == sampleDisclosure)
        #expect(model.deletion == .unknown)
        #expect(!model.canRequestDeletion)
    }

    @Test func aListThatCannotBeLoadedCanBeRetried() async {
        var script = FakePrivacy.Script()
        script.disclosure = [.failure(offline), .success(sampleDisclosure)]
        script.current = [.success(nil), .success(nil)]
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner)])

        await model.load()
        #expect(model.disclosure == nil)
        #expect(model.loadFailure == .noConnection)

        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(model.loadFailure == nil)
        #expect(!model.isOffline)
    }

    @Test func aLostConnectionKeepsTheListWithANote() async {
        var script = FakePrivacy.Script()
        script.disclosure = [
            .success(sampleDisclosure),
            .failure(offline),
            .failure(.server(status: 500, error: ApiError(code: .internalError))),
        ]
        script.current = [.success(nil), .success(nil), .success(nil)]
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner), .success(owner)])
        await model.load()

        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(model.isOffline)
        #expect(model.loadFailure == nil)

        // Only a lost connection earns the offline note.
        await model.load()
        #expect(model.disclosure == sampleDisclosure)
        #expect(!model.isOffline)
    }

    @Test func anEmptyListIsAnAnswerNotAFault() async {
        var script = FakePrivacy.Script()
        script.disclosure = [.success(PrivacyDisclosure(documentVersion: "", locale: "uz", seen: [], notSeen: []))]
        script.current = [.success(nil)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.disclosure?.isEmpty == true)
        #expect(model.loadFailure == nil)
    }

    @Test func aGuardianSeesNoButtonButSeesTheRequest() async {
        let (model, fake, _) = await setup(loaded(), parents: [.success(guardian)])
        await model.load()

        #expect(!model.isOwner)
        #expect(model.deletion == .idle)
        #expect(!model.canRequestDeletion)
        model.startDelete()
        await model.confirmDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)

        let (pending, _, _) = await setup(loaded(current: .success(pendingRequest)), parents: [.success(guardian)])
        await pending.load()
        #expect(pending.deletion == .requested(executableAt: deletionDate))
    }

    // Review Focus 4: an unread role is not an owner.
    @Test func anUnreadableRoleOffersNoButtonButShowsTheRequest() async {
        let (model, _, _) = await setup(loaded(), parents: [.failure(offline)])
        await model.load()

        #expect(!model.isOwner)
        #expect(model.deletion == .idle)
        #expect(!model.canRequestDeletion)

        let (pending, _, _) = await setup(loaded(current: .success(pendingRequest)), parents: [.failure(offline)])
        await pending.load()
        #expect(pending.deletion == .requested(executableAt: deletionDate))
    }

    @Test func askConfirmDoneEndsTheSession() async {
        var script = loaded()
        script.request = [.success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()

        model.startDelete()
        #expect(model.deletion == .confirming)
        model.cancelDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)

        model.startDelete()
        await model.confirmDelete()

        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(model.toast == nil)
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
    }

    @Test func nothingIsSentWithoutTheConfirmation() async {
        var script = loaded()
        script.request = [.success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()

        await model.confirmDelete()

        #expect(model.deletion == .idle)
        #expect(spy.count == 0)
        #expect(await fake.calls.filter { $0 == "request" }.isEmpty)
    }

    @Test(.timeLimit(.minutes(5)))
    func twoTapsRequestOnce() async {
        let gate = PauseGate()
        var script = loaded()
        script.request = [.success(recordedRequest)]
        script.requestGate = gate
        let (model, fake, spy) = await setup(script)
        await model.load()
        model.startDelete()

        let first = Task { await model.confirmDelete() }
        await gate.untilPaused()
        #expect(model.deletion == .submitting)
        await model.confirmDelete()
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)

        await gate.release()
        await first.value
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
    }

    @Test func aRefusalSaysSoAndGoesBackToTheButton() async {
        var script = loaded()
        script.request = [.failure(forbidden)]
        let (model, _, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()

        #expect(model.toast == .permissionDenied)
        #expect(model.deletion == .idle)
        #expect(spy.count == 0)
    }

    @Test func aRequestThatDidNotArriveSaysSoAndCanBeAskedAgain() async {
        var script = loaded()
        script.request = [.failure(offline), .success(recordedRequest)]
        let (model, fake, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()
        #expect(model.toast == .noConnection)
        #expect(model.deletion == .idle)
        #expect(spy.count == 0)

        model.startDelete()
        await model.confirmDelete()
        #expect(spy.count == 1)
        #expect(await fake.calls.filter { $0 == "request" }.count == 2)
    }

    @Test func aCancelledRequestGoesBackToTheConfirmationQuietly() async {
        var script = loaded()
        script.cancelNextRequest = true
        let (model, _, spy) = await setup(script)
        await model.load()
        model.startDelete()

        await model.confirmDelete()

        #expect(model.deletion == .confirming)
        #expect(model.toast == nil)
        #expect(spy.count == 0)
    }

    // Review Focus 2.
    @Test func aRefreshKeepsTheConfirmationOpen() async {
        let (model, _, _) = await setup(loaded(times: 2), parents: [.success(owner), .success(owner)])
        await model.load()
        model.startDelete()

        await model.load()

        #expect(model.deletion == .confirming)
    }

    // Review Focus 2.
    @Test(.timeLimit(.minutes(5)))
    func aRefreshDuringTheRequestKeepsItSubmitting() async {
        let gate = PauseGate()
        var script = loaded(times: 2)
        script.request = [.success(recordedRequest)]
        script.requestGate = gate
        let (model, _, spy) = await setup(script, parents: [.success(owner), .success(owner)])
        await model.load()
        model.startDelete()

        let first = Task { await model.confirmDelete() }
        await gate.untilPaused()
        await model.load()
        #expect(model.deletion == .submitting)

        await gate.release()
        await first.value
        #expect(model.deletion == .requested(executableAt: deletionDate))
        #expect(spy.count == 1)
    }

    // Review Focus 3.
    @Test(.timeLimit(.minutes(5)))
    func anOlderLoadNeverOverwritesANewerOne() async {
        let gate = PauseGate()
        let newer = PrivacyDisclosure(
            documentVersion: "2026-10-07",
            locale: "uz",
            seen: sampleDisclosure.seen,
            notSeen: sampleDisclosure.notSeen
        )
        var script = FakePrivacy.Script()
        script.disclosure = [.success(sampleDisclosure), .success(newer)]
        script.current = [.success(nil), .success(nil)]
        script.disclosureGate = gate
        let (model, _, _) = await setup(script, parents: [.success(owner), .success(owner)])

        let first = Task { await model.load() }
        await gate.untilPaused()
        await model.load()
        #expect(model.disclosure == newer)

        await gate.release()
        await first.value
        #expect(model.disclosure == newer)
    }

    @Test func theConfirmationNamesTheWaitOnlyWhenTheServerGaveIt() async {
        let (withDays, _, _) = await setup(FakePrivacy.Script(), config: PrivacyConfig(deletionDelayDays: 7, policyURL: nil))
        let (withoutDays, _, _) = await setup(FakePrivacy.Script(), config: .absent)

        #expect(withDays.deleteBody(l10n) == l10n.privacyDeleteBodyWithDays(7))
        #expect(withoutDays.deleteBody(l10n) == l10n.privacyDeleteBody)
    }

    @Test func theCaptionNamesTheOnlyChildAndNoOneElse() async {
        let (one, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("Ali")])
        let (two, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("Ali"), makeChild("Vali")])
        let (none, _, _) = await setup(FakePrivacy.Script())
        let (blank, _, _) = await setup(FakePrivacy.Script(), children: [makeChild("  ")])

        #expect(one.caption(l10n) == l10n.privacyCaptionChild("Ali"))
        #expect(two.caption(l10n) == l10n.privacyCaptionChildren)
        #expect(none.caption(l10n) == l10n.privacyCaptionChildren)
        #expect(blank.caption(l10n) == l10n.privacyCaptionChildren)
    }
}
```

- [ ] **Step 3: Run the tests to see them fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'PrivacyModel' in scope`, `type 'DateTexts' has no member 'dayMonthAndYear'`.

- [ ] **Step 4: `DateTexts.dayMonthAndYear`**

In `NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift`, inside `enum DateTexts`, after `weekRange(_:_:_:)` add:

```swift

    /// "14-oktabr 2026", "October 14, 2026".
    static func dayMonthAndYear(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateDayMonthYear(date.day, monthName(date, l10n), date.year)
    }
```

- [ ] **Step 5: `PrivacyModel`**

Create `NozirKit/Sources/NozirAppFeature/Privacy/PrivacyModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirL10n
import NozirPrivacy

/// P20 (Android `PrivacyViewModel`): what the parent sees and what they do not,
/// read from the server and never from a copy in the app, and the request to
/// erase the family. Nothing is deleted here: the server records a request and
/// revokes every parent's session, so a recorded request ends this one locally.
@MainActor
@Observable
final class PrivacyModel {
    enum Deletion: Equatable {
        /// The current request could not be read: the section is not drawn.
        case unknown
        case idle
        case confirming
        case submitting
        case requested(executableAt: Date)
    }

    private(set) var disclosure: PrivacyDisclosure?
    /// The list could not be had and there is none on screen.
    private(set) var loadFailure: UserMessage?
    /// A list is on screen but the last refresh found no connection.
    private(set) var isOffline = false
    private(set) var deletion: Deletion = .unknown
    /// Only an owner may ask (a guardian gets 403); an unread role is not an owner.
    private(set) var isOwner = false
    /// A request that failed, said once; the view sets it back to nil.
    var toast: UserMessage?

    let config: PrivacyConfig
    private let privacy: any PrivacyService
    private let family: FamilyStore
    private let calendar: Calendar
    private let onSignedOut: @MainActor () -> Void
    /// Bumped by every load: an older answer never overwrites a newer one.
    @ObservationIgnored private var generation = 0

    init(
        privacy: any PrivacyService,
        family: FamilyStore,
        config: PrivacyConfig,
        calendar: Calendar = PrivacyModel.phoneCalendar,
        onSignedOut: @escaping @MainActor () -> Void
    ) {
        self.privacy = privacy
        self.family = family
        self.config = config
        self.calendar = calendar
        self.onSignedOut = onSignedOut
    }

    /// The date a parent reads: Gregorian, in the phone's time zone.
    nonisolated static var phoneCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// The list, the current request and the parent's role, asked together.
    func load() async {
        generation += 1
        let mine = generation
        if disclosure == nil {
            loadFailure = nil
        }
        let service = privacy
        let familyService = family.service
        async let shown = Self.attempt { try await service.disclosure() }
        async let current = Self.attempt { try await service.currentDeletion() }
        async let parent = Self.attempt { try await familyService.me() }
        let answers = await (shown, current, parent)
        guard mine == generation else { return }
        apply(disclosure: answers.0)
        apply(current: answers.1)
        if case .success(let me) = answers.2 {
            isOwner = me.role == "OWNER"
        }
    }

    var canRequestDeletion: Bool {
        deletion == .idle && isOwner
    }

    /// Opens the confirmation. Nothing has been sent.
    func startDelete() {
        guard canRequestDeletion else { return }
        deletion = .confirming
    }

    func cancelDelete() {
        guard deletion == .confirming else { return }
        deletion = .idle
    }

    /// Reachable from the confirmation only, so a second tap while the first
    /// is in flight does nothing. Never retried by itself.
    func confirmDelete() async {
        guard deletion == .confirming else { return }
        deletion = .submitting
        do {
            let recorded = try await privacy.requestDeletion()
            deletion = .requested(executableAt: recorded.executableAt)
            onSignedOut()
        } catch is CancellationError {
            deletion = .confirming
        } catch {
            deletion = .idle
            toast = UserMessage(error)
        }
    }

    /// Names the child only when there is exactly one to name (Android `loadChildName`).
    func caption(_ l10n: L10n) -> String {
        guard family.children.count == 1, let only = family.children.first else {
            return l10n.privacyCaptionChildren
        }
        let name = only.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? l10n.privacyCaptionChildren : l10n.privacyCaptionChild(name)
    }

    /// States the wait only when the server gave one.
    func deleteBody(_ l10n: L10n) -> String {
        guard let days = config.deletionDelayDays else { return l10n.privacyDeleteBody }
        return l10n.privacyDeleteBodyWithDays(days)
    }

    /// The server's date, the only one this screen quotes.
    func requestedBody(_ executableAt: Date, _ l10n: L10n) -> String {
        l10n.privacyDeleteRequestedBody(DateTexts.dayMonthAndYear(LocalDate(executableAt, in: calendar), l10n))
    }

    private func apply(disclosure answer: Result<PrivacyDisclosure, any Error>) {
        switch answer {
        case .success(let fresh):
            disclosure = fresh
            loadFailure = nil
            isOffline = false
        case .failure(let error):
            if error is CancellationError { return }
            let message = UserMessage(error)
            if disclosure == nil {
                loadFailure = message
            } else {
                isOffline = message == .noConnection || message == .timeout
            }
        }
    }

    /// A failure leaves `.unknown` unknown and a known stage as it was; an
    /// answer never pulls an open confirmation or a request in flight back.
    private func apply(current answer: Result<ErasureRequestStatus?, any Error>) {
        guard case .success(let status) = answer else { return }
        switch deletion {
        case .confirming, .submitting:
            return
        case .unknown, .idle, .requested:
            deletion = status.map { .requested(executableAt: $0.executableAt) } ?? .idle
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

- [ ] **Step 6: Run the tests to see them pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`, with no `Sendable` / isolation warnings in the filtered output.

- [ ] **Step 7: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Privacy/PrivacyModel.swift NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift NozirKit/Tests/NozirAppFeatureTests/FakePrivacy.swift NozirKit/Tests/NozirAppFeatureTests/PrivacyModelTests.swift NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p20: ask, confirm, done — and a guardian is never offered the button

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 5: P20 screen, the Profile row, and the wiring (with accessibility)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Screens/PrivacyView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift` (imports 1-7, properties 28-35, `init` 37-57, factory after `makeProfileModel` line 88)
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` (imports 1-9, `makeSignedInModel` 76-91)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift` (properties 9-12, `init` 17-29, settings card 57-62)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`ProfileStep` 31-39, `ProfileView(…)` 112-118, `profileDestination` 189-212)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` (imports 1-7, `setup` 17-35, new test inside the suite)

**Interfaces:**
- Consumes: `PrivacyModel` (all of Task 4's surface), `PrivacyConfig`, `AppModel.privacyConfig`, `AppModel.signOutLocally()` (Task 3), `PrivacyApi(client:)` (Task 2), `LocaleSync.unsentKey`, design system (`NozirCard(tone:)`, `NozirButton(_:variant:isLoading:action:)`, `NozirSettingsRow`, `NozirErrorState`, `NozirEmptyState`, `NozirOfflineNotice`, `.nozirToast(_:)`, `NozirColor`, `NozirSpacing`, `NozirSize.icon`), l10n keys `profileRowPrivacy`, `screenPrivacyTitle`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`, `privacySeenLabel`, `privacyNotSeenLabel`, `contentDescriptionPrivacySeen`, `contentDescriptionPrivacyNotSeen`, `glyphCheck`, `glyphCross`, `glyphBullet`, `privacyPromise`, `privacyDocumentVersion(_:)`, `privacyPolicyRow`, `privacyDisclosureEmptyTitle`, `privacyDisclosureEmptyBody`, `privacyActionDelete`, `privacyDeleteTitle`, `privacyDeleteCancel`, `privacyDeleteConfirm`, `privacyDeleteRequestedTitle`.
- Produces:
  - `SignedInModel.init(family:insights:location:language:appearance:localeSync:emergencyNumber:privacy: any PrivacyService, privacyConfig: @escaping @MainActor () -> PrivacyConfig, signOutLocally: @escaping @MainActor () -> Void, signOut:)`
  - `SignedInModel.makePrivacyModel() -> PrivacyModel`
  - `SignedInView.ProfileStep.privacy`; `ProfileView.init(model:onAddChild:onOpenChild:onPair:onOpenRules:onOpenPrivacy:)`
  - `PrivacyView(model: PrivacyModel)`

- [ ] **Step 1: Write the failing test**

In `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` add `import NozirPrivacy` after `import NozirLocation` (line 6), and replace `setup` (lines 17-35) with:

```swift
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales(),
    privacy: FakePrivacy = FakePrivacy(),
    privacyConfig: PrivacyConfig = .absent,
    signOutLocally: @escaping @MainActor () -> Void = {}
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        insights: FakeInsights(),
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

and add inside `SignedInModelTests`:

```swift
    // P20: the screen gets the config of the moment it opens, and a recorded
    // request ends the session here without the server's logout.
    @Test func thePrivacyScreenReadsTheConfigAndEndsTheSessionLocally() async {
        var familyScript = FakeFamily.Script()
        familyScript.me = [.success(ParentProfile(displayName: "Zohid", phoneE164: nil, locale: "uz", role: "OWNER"))]
        var privacyScript = FakePrivacy.Script()
        privacyScript.disclosure = [.success(sampleDisclosure)]
        privacyScript.current = [.success(nil)]
        privacyScript.request = [.success(recordedRequest)]
        var endedLocally = 0
        let (model, _) = setup(
            familyScript,
            privacy: FakePrivacy(privacyScript),
            privacyConfig: PrivacyConfig(deletionDelayDays: 7, policyURL: nil),
            signOutLocally: { endedLocally += 1 }
        )
        let privacy = model.makePrivacyModel()

        await privacy.load()
        privacy.startDelete()
        await privacy.confirmDelete()

        #expect(privacy.deleteBody(L10n(.uz)) == L10n(.uz).privacyDeleteBodyWithDays(7))
        #expect(endedLocally == 1)
    }
```

- [ ] **Step 2: Run the test to see it fail**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra arguments at positions … in call` (`privacy:`, `privacyConfig:`, `signOutLocally:`) and `value of type 'SignedInModel' has no member 'makePrivacyModel'`.

- [ ] **Step 3: `SignedInModel`**

In `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:

Add `import NozirPrivacy` after `import NozirLocation` (line 7).

Replace the stored properties from `private let emergencyNumber: @MainActor () -> String?` through `private let signOutAction: @MainActor () async -> Void` (lines 33-34) with:

```swift
    private let emergencyNumber: @MainActor () -> String?
    private let privacy: any PrivacyService
    private let privacyConfig: @MainActor () -> PrivacyConfig
    private let signOutLocallyAction: @MainActor () -> Void
    private let signOutAction: @MainActor () async -> Void
```

Replace `init(…)` (lines 37-57) with:

```swift
    init(
        family: FamilyStore,
        insights: any InsightsService,
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
        locationService = location
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        self.emergencyNumber = emergencyNumber
        self.privacy = privacy
        self.privacyConfig = privacyConfig
        signOutLocallyAction = signOutLocally
        signOutAction = signOut
        statistics = StatisticsModel(family: family)
        locationTab = LocationModel(family: family, location: location)
    }
```

After `makeProfileModel()` add:

```swift

    /// P20 with the config of the moment it opens. A recorded request ends the
    /// session here only: the server has already revoked it.
    func makePrivacyModel() -> PrivacyModel {
        PrivacyModel(privacy: privacy, family: family, config: privacyConfig(), onSignedOut: signOutLocallyAction)
    }
```

- [ ] **Step 4: `AppEnvironment`**

In `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` add `import NozirPrivacy` after `import NozirNetworking` (line 9), and replace `makeSignedInModel()` (lines 76-91) with:

```swift
    func makeSignedInModel() -> SignedInModel {
        let api = FamilyApi(client: authorised)
        return SignedInModel(
            family: FamilyStore(service: api),
            insights: InsightsApi(client: authorised),
            location: LocationApi(client: authorised),
            language: language,
            appearance: appearance,
            localeSync: LocaleSync(store: language, send: { _ = try await api.updateLocale($0) }),
            emergencyNumber: { [appModel] in appModel.emergencyNumber },
            privacy: PrivacyApi(client: authorised),
            privacyConfig: { [appModel] in appModel.privacyConfig },
            signOutLocally: { [appModel] in
                UserDefaults.standard.removeObject(forKey: LocaleSync.unsentKey)
                appModel.signOutLocally()
            },
            signOut: { [appModel] in
                UserDefaults.standard.removeObject(forKey: LocaleSync.unsentKey)
                await appModel.signOut()
            }
        )
    }
```

- [ ] **Step 5: Run the test to see it pass**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: `PrivacyView`**

Create `NozirKit/Sources/NozirAppFeature/Screens/PrivacyView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirPrivacy

/// P20 as Android `PrivacyContent`: who else reads this list, what the parent
/// sees and does not see (the server's words only), the promise, the policy
/// link, and the deletion section pinned below the scroll. The button, the
/// confirmation and the receipt take the same place, one at a time.
struct PrivacyView: View {
    @State private var model: PrivacyModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @AccessibilityFocusState private var confirmationFocused: Bool

    init(model: PrivacyModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                if model.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                Text(model.caption(l10n))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                disclosureContent
                if let policy = model.config.policyURL {
                    NozirCard {
                        NozirSettingsRow(l10n.privacyPolicyRow) { openURL(policy) }
                            .accessibilityAddTraits(.isLink)
                    }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            deletionSection
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenPrivacyTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        // VoiceOver lands on the question, not on the button that is gone.
        .onChange(of: model.deletion) { _, stage in
            if stage == .confirming {
                confirmationFocused = true
            }
        }
        .nozirToast(Binding(
            get: { model.toast?.text(l10n) },
            set: { if $0 == nil { model.toast = nil } }
        ))
    }

    @ViewBuilder
    private var disclosureContent: some View {
        if let disclosure = model.disclosure {
            if disclosure.isEmpty {
                NozirEmptyState(title: l10n.privacyDisclosureEmptyTitle, message: l10n.privacyDisclosureEmptyBody)
            } else {
                if !disclosure.seen.isEmpty {
                    disclosureCard(seen: true, items: disclosure.seen)
                }
                if !disclosure.notSeen.isEmpty {
                    disclosureCard(seen: false, items: disclosure.notSeen)
                }
                Text(l10n.privacyPromise)
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if !disclosure.documentVersion.isEmpty {
                    Text(l10n.privacyDocumentVersion(disclosure.documentVersion))
                        .nozirText(.bodySmall, color: NozirColor.textTertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        } else if let failure = model.loadFailure {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: failure.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    /// One half of the promise. The tick or the cross and the label carry the
    /// meaning; the colour only agrees with them.
    private func disclosureCard(seen: Bool, items: [DisclosureItem]) -> some View {
        let accent = seen ? NozirColor.primaryAccent : NozirColor.criticalContent
        return NozirCard(tone: seen ? .plain : .critical) {
            HStack(spacing: NozirSpacing.small) {
                Text(seen ? l10n.glyphCheck : l10n.glyphCross)
                    .nozirText(.label, color: seen ? NozirColor.onPrimary : NozirColor.card)
                    .frame(width: NozirSize.icon, height: NozirSize.icon)
                    .background(Circle().fill(seen ? NozirColor.primary : NozirColor.criticalContent))
                Text(seen ? l10n.privacySeenLabel : l10n.privacyNotSeenLabel)
                    .nozirText(.titleSmall, color: accent)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(seen ? l10n.contentDescriptionPrivacySeen : l10n.contentDescriptionPrivacyNotSeen)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: NozirSpacing.small) {
                    Text(l10n.glyphBullet)
                        .nozirText(.body, color: accent)
                        .accessibilityHidden(true)
                    Text(item.text).nozirText(.body)
                }
            }
        }
    }

    @ViewBuilder
    private var deletionSection: some View {
        switch model.deletion {
        case .unknown:
            EmptyView()
        case .idle:
            if model.canRequestDeletion {
                pinned {
                    NozirButton(l10n.privacyActionDelete, variant: .secondary) { model.startDelete() }
                }
            }
        case .confirming, .submitting:
            pinned { confirmationCard(isSubmitting: model.deletion == .submitting) }
        case .requested(let executableAt):
            pinned {
                NozirCard(tone: .attention) {
                    Text(l10n.privacyDeleteRequestedTitle).nozirText(.titleSmall)
                    Text(model.requestedBody(executableAt, l10n))
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private func pinned<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.vertical, NozirSpacing.compact)
            .frame(maxWidth: .infinity)
            .background(NozirColor.background)
    }

    /// A card where the button was, not an alert: full sentences about what
    /// goes and when, and the refusal first.
    private func confirmationCard(isSubmitting: Bool) -> some View {
        NozirCard(tone: .critical) {
            Text(l10n.privacyDeleteTitle)
                .nozirText(.titleSmall)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($confirmationFocused)
            Text(model.deleteBody(l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            // Side by side when both fit; stacked at large text sizes.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: NozirSpacing.small) { confirmationButtons(isSubmitting: isSubmitting) }
                VStack(spacing: NozirSpacing.small) { confirmationButtons(isSubmitting: isSubmitting) }
            }
        }
    }

    @ViewBuilder
    private func confirmationButtons(isSubmitting: Bool) -> some View {
        NozirButton(l10n.privacyDeleteCancel, variant: .secondary) { model.cancelDelete() }
            .disabled(isSubmitting)
        NozirButton(l10n.privacyDeleteConfirm, variant: .criticalOutline, isLoading: isSubmitting) {
            Task { await model.confirmDelete() }
        }
    }
}
```

- [ ] **Step 7: The Profile row and the navigation**

In `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`:

After `private let onOpenRules: () -> Void` (line 12) add:

```swift
    private let onOpenPrivacy: () -> Void
```

Replace `init(…)` (lines 17-29) with:

```swift
    init(
        model: ProfileModel,
        onAddChild: @escaping () -> Void,
        onOpenChild: @escaping (Child) -> Void,
        onPair: @escaping (Child) -> Void,
        onOpenRules: @escaping () -> Void,
        onOpenPrivacy: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onAddChild = onAddChild
        self.onOpenChild = onOpenChild
        self.onPair = onPair
        self.onOpenRules = onOpenRules
        self.onOpenPrivacy = onOpenPrivacy
    }
```

Replace the settings card (lines 58-62) with:

```swift
                NozirCard {
                    NozirSettingsRow(l10n.profileRowPrivacy, action: onOpenPrivacy)
                    Divider()
                    NozirSettingsRow(l10n.profileRowTheme, value: themeLabel(model.appearance.mode)) { showsTheme = true }
                    Divider()
                    NozirSettingsRow(l10n.profileRowLanguage, value: languageLabel(model.language.current)) { showsLanguage = true }
                }
```

In `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

In `enum ProfileStep`, after `case ruleScreen(RuleScreen)` (line 38) add:

```swift
        /// P20 from the Profile settings card.
        case privacy
```

Replace the `ProfileView(…)` call (lines 112-118) with:

```swift
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) },
                    onOpenRules: { profilePath.append(.rules(nil)) },
                    onOpenPrivacy: { profilePath.append(.privacy) }
                )
```

In `profileDestination(_:)`, after the `case .ruleScreen(let screen):` branch (`ruleDestination(screen)`, line 210) add:

```swift
        case .privacy:
            PrivacyView(model: model.makePrivacyModel())
```

- [ ] **Step 8: Run the tests and build the app**

Run, one at a time: `bash .superpowers/run.sh NozirAppFeatureTests 170`, then `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, then `** BUILD SUCCEEDED **` (no `Sendable` / isolation warnings in the filtered output).

- [ ] **Step 9: Commit**

```bash
cd $HOME/mnt/XCodeProjects/NozirIOS
git status --short
git add NozirKit/Sources/NozirAppFeature/Screens/PrivacyView.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com git commit -m "p20: what we see and what we do not, reached from Profile, and the way out

Co-Authored-By: <implementer's own model attribution line>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp"
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

---
### Task 6: Final check — whole suite, l10n, and E2E

**Files:** none change (a fault found here gets its own red-green cycle in the task that owns the code).

- [ ] **Step 1: Whole suite**

Run: `cd $HOME/mnt/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, then `bash .superpowers/run.sh all 170`, then `bash .superpowers/run.sh app 170`.
Expected: Python `OK`, l10n up to date (no new key), `** TEST SUCCEEDED **` (with the new `NozirPrivacyTests` target among them), `** BUILD SUCCEEDED **`; `git diff --stat f7ee8d3 -- NozirKit/l10n NozirKit/Sources/NozirL10n` is empty.

- [ ] **Step 2: E2E (the user; simulator + the real backend with the P20 backend half deployed + the Android parent app on the same family)**

Write "yes" or what was seen against each line:

1. Profile → settings card: "Maxfiylik" is the first row, above Mavzu and Til; it opens P20 titled "Maxfiylik".
2. P20 with one child: the caption names the child; with two children it says "Farzandingiz…". The "Siz koʻrasiz" card (tick) and "Siz koʻrmaysiz" card (cross, red) list exactly what Android P20 lists; the promise and "Hujjat versiyasi: …" follow.
3. "Maxfiylik siyosati" row opens the policy in Safari; with the config's URL blanked on the server the row is gone.
4. Offline on first open → error with "Qayta urinish", which brings the list once online; offline on pull-to-refresh with the list shown → offline note, list stays.
5. OWNER: "Maʼlumotlarimni oʻchirish" → red card with the number of days from the config, "Bekor qilish" on the left returns to the button; nothing reaches the server (backend log).
6. OWNER confirms → spinner on the confirm button, then the app is on the sign-in screen; on the Android parent app (same family, other parent) the session ends at its next call; the child's phone keeps working.
7. Sign in again as the same OWNER within the wait: P20 shows "Soʻrov qabul qilindi" with the server's date (day, month, year in the chosen language) and no button.
8. GUARDIAN account: P20 shows the lists but no delete button; with a pending request (from the OWNER) the "Soʻrov qabul qilindi" card shows.
9. Server answers 403 (GUARDIAN forced through, e.g. role changed on the server while the screen was open) → toast, button back; no sign-out.
10. VoiceOver: each card is announced as a heading ("Siz koʻradigan maʼlumotlar"); glyphs and bullets are silent; opening the confirmation moves focus to its question; the requested card reads as one element. Largest Dynamic Type: the two confirmation buttons stack and nothing is cut.
11. Three languages and both themes: every P20 text correct; screenshots (Cmd+S).

- [ ] **Step 3: Record the result**

Write the E2E results and any deferred small issues to the ledger (`.superpowers/sdd/<plan>/progress.md`). Push is the user's; then `superpowers:finishing-a-development-branch`.
