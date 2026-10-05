# Nozir iOS — 3: Joylashuv va SOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Joylashuv tabi (P13 xarita, "hozir so'rash", hudud chiplari), P14 xavfsiz hudud, P12b kuzatuv qoidasi va to'liq P15 SOS ekrani — push'siz.

**Architecture:** Yangi `NozirLocation` moduli — `/location`, `/location/request`, `/safe-zones`, `/sos-alerts/{id}` (+ acknowledge) uchun `LocationApi` va `LocationService` protokoli. P12b qoidasi `NozirFamily` ga (`RuleSnapshot.locationTracking`, If-Match bilan yozish). Ekran modellari (`LocationModel`, `SafeZoneModel`, `LocationTrackingModel`, `SosDetailModel`) `@MainActor @Observable`, `FakeLocation` va `FakeFamily` bilan testlanadi; matn mantiqi toza funksiyalarda (`LocationTexts`). Xarita — SwiftUI MapKit (`Map`, `Annotation`, `MapCircle`), kalitsiz.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), MapKit, Observation, Swift Testing; uchinchi tomon kutubxonasi yo'q.

**Spec:** `docs/superpowers/specs/2026-10-06-nozir-ios-location-design.md` (oldingi: poydevor, 2a, 2b spec'lari)

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). Uchinchi tomon kutubxonasi va Google Maps yo'q; xarita — Apple MapKit.
- Har bir `/v1/parent/*` chaqiruvi poydevordagi `ApiClient` orqali; bola id'si yo'lda kichik harflar bilan (`uuidString.lowercased()`).
- Server `message` hech qachon ko'rsatilmaydi; foydalanuvchi matni faqat `L10n`, xatolar `UserMessage` orqali.
- Joylashuv keshlanmaydi va diskka hech narsa yozilmaydi; P13 har ochilishda, tabga qaytganda va ilova faollashganda qayta so'raydi.
- Ota-onaning o'z joylashuvi so'ralmaydi (CoreLocation ishlatilmaydi, Info.plist'ga joylashuv kaliti qo'shilmaydi).
- Push yo'q: APNs, P16a, bildirishnomalar — bu sub-loyihada emas.
- Obuna: oldindan tekshirilmaydi; 403 `SUBSCRIPTION_REQUIRED` → "Joylashuv PRO rejada" (`plan_lock_location_*` + `plan_lock_sos_note`), upgrade tugmasi yo'q; o'chirish hech qachon cheklanmaydi; P15 ga hech qanday tekshiruv yo'q.
- "Hozir so'rash" kutishi: 12 urinish × 2,5 s; kutish va soat testda in'ektsiya qilinadi (testlarda real kutish yo'q).
- P14: nom 1–60 belgi (bo'sh emas), radius 50–5000 m (sukut 200), "Kirganda" sukut yoqiq, "Chiqqanda" sukut o'chiq; Toshkent markazi 41.311081, 69.240562.
- P12b: oraliq {5,10,15,30} daqiqa (sukut 10), hudud yonida {1,3,5} (sukut 3), siljish {50,100,200} m (sukut 100); yozish `If-Match` bilan; to'qnashuvda qayta o'qish, avtomatik qayta yuborish yo'q.
- P15: favqulodda raqam — `AppModel.emergencyNumber`, yo'q bo'lsa `l10n.sosEmergencyNumber` ("112"); fix yoshi 4 soatdan eski → eskirgan (`ElapsedTime.stale`).
- Commit: `git add -A` taqiqlangan, faqat aniq yo'llar; push foydalanuvchida; commit muhiti va izoh qatorlari avvalgidek.
- Swift kodi test ishlaguncha "yozilgan, tekshirilmagan".

## Spec'dan chetlanishlar (reja bosqichida)

| # | Spec | Reja | Sabab |
|---|---|---|---|
| E1 | "Ko'rdim" `Idempotency-Key: <sosId>` bilan | Kalit yuborilmaydi | `ApiRequest` da ixtiyoriy sarlavha yo'q; backend `acknowledge` da `@Idempotent` yo'q va amal o'z-o'zidan bir martalik (ikkinchi chaqiruv o'sha alertni qaytaradi); ikki bosishdan model himoyalaydi |
| E2 | P13 sarlavhasi: `placeLabel` → `zoneName` | `zoneName` → `placeLabel` → "Manzil aniqlanmadi" | Android `LocationFix.headline` tartibi: bola turgan hudud eng tushunarli javob |
| E3 | P12b: muzlatilgan bola — 2a dagi kabi oldindan qulf | Oldindan tekshiruv yo'q; saqlashda `CHILD_NOT_ACTIVE` → `data_error_child_not_active` matni | Obuna holati iOS'da faqat P03 tafsilotlarida o'qiladi; bitta so'rov va bitta holat kamroq, sababi baribir aytiladi |
| E4 | `SosAlertModel` | `SosDetailModel` / `SosDetailView`; NozirLocation turi `SosAlertDetail` | 2b'dagi `SosAlert` (banner qiymati) bilan nom to'qnashmasin |
| E5 | — | `ActiveSos` `Hashable` bo'ladi (NozirInsights) | Home navigatsiya yo'lida `.sos(ActiveSos)` qadami uchun |

## Review Focus

1. **"Hozir so'rash" kutayotganda bola almashtirildi** — eski bolaning javobi yangi bola ekraniga tushmasligi, kutish to'xtashi → Task 4 `aWaitForAnotherChildNeverLandsOnScreen`.
2. **Telefon eski "mavjud emas" sababini qayta yubordi** — kutish faqat yangiroq sabab yoki yangiroq fix bilan tugashi → Task 4 `anOldReasonDoesNotEndTheWait`, `aNewerReasonEndsTheWait`.
3. **Tahrirlanayotgan hudud boshqa telefonda o'chirilgan** — bo'sh forma emas, "topilmadi" → Task 5 `aZoneGoneElsewhereIsNotFound`.
4. **P12b versiya to'qnashuvi** — qayta o'qish va xabar, avtomatik qayta yubormaslik → Task 6 `aConflictReloadsAndDoesNotResend`.
5. **"Ko'rdim" ikki marta tez bosildi yoki tarmoq xatosi** — bitta so'rov; xato bo'lsa qayta urinish mumkin → Task 8 `twoTapsAcknowledgeOnce`, `aFailedAcknowledgeCanBeRetried`.

---

## Fayl xaritasi

**Yangi:** `NozirKit/Sources/NozirLocation/{LocationModels,LocationService,LocationApi}.swift`; `NozirKit/Sources/NozirAppFeature/Location/{LocationTexts,LocationModel,SafeZoneModel,LocationTrackingModel,SosDetailModel}.swift`; `NozirKit/Sources/NozirAppFeature/Screens/{LocationView,LocationMapView,SafeZoneView,LocationTrackingView,SosDetailView}.swift`; testlar `NozirKit/Tests/NozirLocationTests/{LocationFixtures,LocationApiTests}.swift`, `NozirKit/Tests/NozirAppFeatureTests/{FakeLocation,LocationTextsTests,LocationModelTests,SafeZoneModelTests,LocationTrackingModelTests,SosDetailModelTests}.swift`.

**O'zgaradi:** `NozirKit/Package.swift`; `NozirNetworking/ApiErrorCode.swift`; `NozirInsights/InsightModels.swift` (`ActiveSos: Hashable`); `NozirFamily/{RuleModels,FamilyService,FamilyApi}.swift`; `NozirAppFeature/{UserMessage,SignedInModel,AppEnvironment}.swift`; `Screens/{HomeView,SignedInView,SosViews}.swift`; `NozirKit/l10n/ios/values{,-en,-ru}/strings.xml` (+ generatsiya); testlar `NozirFamilyTests/RulesAndPairingApiTests.swift`, `NozirAppFeatureTests/{FakeFamily,UserMessageTests,SignedInModelTests,SosAlertTests}.swift`.

## Ishni boshlash

Branch `location` (spec commit 57c204d) ochilgan. Swift testlari: `bash .superpowers/run.sh <Target> 170` (watcher), `all`, `app`.

---

### Task 1: `NozirLocation` moduli — joylashuv, hududlar, SOS API

**Files:**
- Modify: `NozirKit/Package.swift`
- Modify: `NozirKit/Sources/NozirNetworking/ApiErrorCode.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/UserMessage.swift`
- Modify: `NozirKit/Sources/NozirInsights/InsightModels.swift` (`ActiveSos`)
- Create: `NozirKit/Sources/NozirLocation/LocationModels.swift`
- Create: `NozirKit/Sources/NozirLocation/LocationService.swift`
- Create: `NozirKit/Sources/NozirLocation/LocationApi.swift`
- Test: `NozirKit/Tests/NozirLocationTests/LocationFixtures.swift`
- Test: `NozirKit/Tests/NozirLocationTests/LocationApiTests.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift`

**Interfaces:**
- Consumes: poydevor `ApiClient`, `ApiRequest` (`.post(_:json:)`, `.put(_:json:ifMatch:)`), `ApiFailure.isNotFound`, `NozirTestSupport`.
- Produces:
  - Package: `.target(name: "NozirLocation", dependencies: ["NozirNetworking"])`, `.testTarget(name: "NozirLocationTests", dependencies: ["NozirLocation", "NozirNetworking", "NozirTestSupport"])`; `NozirAppFeature` va `NozirAppFeatureTests` bog'liqliklarida `"NozirLocation"`.
  - `ApiErrorCode.safeZoneLimitReached` (`"SAFE_ZONE_LIMIT_REACHED"`); `UserMessage.safeZoneLimitReached` (matn `l10n.dataErrorSafeZoneLimitReached`).
  - `ActiveSos: Hashable`.
  - `public struct Coordinate: Hashable, Sendable { latitude: Double; longitude: Double }`
  - `public enum LocationUnavailableReason: String, Sendable, Decodable { locationOff, permissionDenied, noFix }` (noma'lum → `.noFix`)
  - `public struct LocationSnapshot: Decodable, Equatable, Sendable { occurredAt: Date?; latitude: Double?; longitude: Double?; accuracyMeters: Double?; zoneId: UUID?; zoneName: String?; placeLabel: String?; batteryPercent: Int?; isStale: Bool; unavailableReason: LocationUnavailableReason?; unavailableAt: Date?; coordinate: Coordinate? }` + hamma maydonli `init` (sukutlar bilan).
  - `public struct SafeZone: Decodable, Equatable, Sendable, Identifiable { id (zoneId); childId; name; latitude; longitude; radiusMeters: Int; notifyOnEnter; notifyOnExit; iconKey: String?; isActive: Bool (yo'q bo'lsa true); coordinate: Coordinate; draft: SafeZoneDraft }` + `init`.
  - `public struct SafeZoneDraft: Encodable, Equatable, Sendable { var name; var latitude; var longitude; var radiusMeters: Int; var notifyOnEnter; var notifyOnExit; var iconKey: String? }` + `init`.
  - `public enum SosStatus: String, Sendable, Decodable { active, acknowledged, cancelledByChild, resolved, unknown }` (noma'lum → `.unknown`)
  - `public struct SosAlertDetail: Decodable, Equatable, Sendable, Identifiable { id; childId; childName: String?; childPhoneE164: String?; triggeredAt: Date; status: SosStatus; batteryPercent: Int?; deviceOnline: Bool; latitude: Double?; longitude: Double?; accuracyMeters: Double?; locationFixAt: Date?; placeLabel: String?; acknowledgedAt: Date?; cancelledAt: Date?; coordinate: Coordinate? }` + `init`.
  - `public protocol LocationService: Sendable` — `location(of:)`, `requestLocation(of:) -> Bool`, `safeZones(of:)`, `createSafeZone(_:for:)`, `updateSafeZone(_:_:)`, `deleteSafeZone(_:)`, `sosAlert(_:)`, `acknowledgeSos(_:)` (imzolar quyida).
  - `public struct LocationApi: LocationService { init(client: ApiClient) }`

- [ ] **Step 1: Package**

`NozirKit/Package.swift` — `NozirInsights` qatoridan keyin target, `NozirInsightsTests` dan keyin test target qo'shing va ikki bog'liqlik ro'yxatini kengaytiring:

```swift
        .target(name: "NozirLocation", dependencies: ["NozirNetworking"]),
```

```swift
        .testTarget(name: "NozirLocationTests", dependencies: ["NozirLocation", "NozirNetworking", "NozirTestSupport"]),
```

```swift
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n", "NozirFamily", "NozirInsights", "NozirLocation"]
        ),
```

```swift
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n", "NozirFamily", "NozirDesignSystem", "NozirInsights", "NozirLocation"]
        ),
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirLocationTests/LocationFixtures.swift`:

```swift
import Foundation
import NozirLocation
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the location calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func locationApi(_ replies: [FakeTransport.Reply]) -> (LocationApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (LocationApi(client: client), transport)
}

let aliId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!
let zoneId = UUID(uuidString: "7C1D2E3F-4A5B-4C6D-8E7F-9A0B1C2D3E4F")!
let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
let childPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"

func instant(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

/// `LocationSnapshotDto` with a fix (`non_null`: absent, not null).
let fixJSON = """
{"occurredAt":"2026-10-06T07:10:00Z","latitude":41.3111,"longitude":69.2797,"accuracyMeters":24.6,\
"zoneId":"7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f","zoneName":"Maktab","batteryPercent":64,"isStale":false}
"""

/// Only a reason: the phone answered, but had no position to give.
let reasonOnlyJSON = """
{"isStale":true,"unavailableReason":"LOCATION_OFF","unavailableAt":"2026-10-06T07:12:00Z"}
"""

func zoneJSON(active: String = #","isActive":false"#) -> String {
    """
    {"zoneId":"7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "name":"Maktab","latitude":41.3111,"longitude":69.2797,"radiusMeters":200,"notifyOnEnter":true,\
    "notifyOnExit":false,"createdAt":"2026-10-01T09:00:00Z"\(active)}
    """
}

func sosJSON(status: String = "ACTIVE", acknowledged: String = "") -> String {
    """
    {"id":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "childName":"Ali","childPhoneE164":"+998901234567","triggeredAt":"2026-10-06T07:00:00Z",\
    "trigger":"BUTTON_HOLD","status":"\(status)","batteryPercent":31,"deviceOnline":true,\
    "latitude":41.3111,"longitude":69.2797,"accuracyMeters":12.0,"locationFixAt":"2026-10-06T06:59:30Z"\(acknowledged)}
    """
}

extension URLRequest {
    /// The body as a JSON object with any value types.
    var bodyObject: [String: Any]? {
        guard let httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any]
    }
}
```

`NozirKit/Tests/NozirLocationTests/LocationApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirLocation

@Suite struct LocationApiTests {
    @Test func aFixReadsTheServersShape() async throws {
        let (api, transport) = locationApi([.ok(fixJSON)])

        let snapshot = try await api.location(of: aliId)

        #expect(snapshot == LocationSnapshot(
            occurredAt: instant("2026-10-06T07:10:00Z"),
            latitude: 41.3111,
            longitude: 69.2797,
            accuracyMeters: 24.6,
            zoneId: zoneId,
            zoneName: "Maktab",
            batteryPercent: 64,
            isStale: false
        ))
        #expect(snapshot.coordinate == Coordinate(latitude: 41.3111, longitude: 69.2797))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == childPath + "/location")
    }

    @Test func aReasonWithoutAPositionHasNoCoordinate() async throws {
        let (api, _) = locationApi([.ok(reasonOnlyJSON)])

        let snapshot = try await api.location(of: aliId)

        #expect(snapshot.coordinate == nil)
        #expect(snapshot.occurredAt == nil)
        #expect(snapshot.isStale)
        #expect(snapshot.unavailableReason == .locationOff)
        #expect(snapshot.unavailableAt == instant("2026-10-06T07:12:00Z"))
    }

    @Test func anUnknownReasonReadsAsNoFix() async throws {
        let (api, _) = locationApi([.ok(#"{"isStale":true,"unavailableReason":"AIRPLANE","unavailableAt":"2026-10-06T07:12:00Z"}"#)])

        #expect(try await api.location(of: aliId).unavailableReason == .noFix)
    }

    @Test func aPhoneThatNeverReportedIsNotFound() async {
        let (api, _) = locationApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.location(of: aliId)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func askingForAFixPostsAndReadsTheAnswer() async throws {
        let (api, transport) = locationApi([.ok(#"{"asked":false}"#)])

        let asked = try await api.requestLocation(of: aliId)

        #expect(!asked)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == childPath + "/location/request")
    }

    @Test func zonesAreReadWithTheirActiveFlag() async throws {
        let (api, transport) = locationApi([.ok("[\(zoneJSON()),\(zoneJSON(active: ""))]")])

        let zones = try await api.safeZones(of: aliId)

        #expect(zones.count == 2)
        #expect(zones[0] == SafeZone(
            id: zoneId,
            childId: aliId,
            name: "Maktab",
            latitude: 41.3111,
            longitude: 69.2797,
            radiusMeters: 200,
            notifyOnEnter: true,
            notifyOnExit: false,
            iconKey: nil,
            isActive: false
        ))
        #expect(zones[1].isActive)
        #expect(await transport.requests.first?.url?.path == childPath + "/safe-zones")
    }

    @Test func aNewZoneIsPostedForTheChild() async throws {
        let (api, transport) = locationApi([.init(status: 201, body: zoneJSON(active: ""))])
        let draft = SafeZoneDraft(name: "Maktab", latitude: 41.3111, longitude: 69.2797, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)

        let zone = try await api.createSafeZone(draft, for: aliId)

        #expect(zone.id == zoneId)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == childPath + "/safe-zones")
        let body = try #require(request.bodyObject)
        #expect(Set(body.keys) == ["name", "latitude", "longitude", "radiusMeters", "notifyOnEnter", "notifyOnExit"])
        #expect(body["radiusMeters"] as? Int == 200)
    }

    @Test func anEditIsPutOnTheZone() async throws {
        let (api, transport) = locationApi([.ok(zoneJSON(active: ""))])
        let draft = SafeZoneDraft(name: "Uy", latitude: 41.3, longitude: 69.2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "home")

        _ = try await api.updateSafeZone(zoneId, draft)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/parent/safe-zones/7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f")
        #expect(request.bodyObject?["iconKey"] as? String == "home")
        #expect(request.bodyObject?["notifyOnExit"] as? Bool == true)
    }

    @Test func deletingAZoneSendsNoBody() async throws {
        let (api, transport) = locationApi([.init(status: 204)])

        try await api.deleteSafeZone(zoneId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/parent/safe-zones/7c1d2e3f-4a5b-4c6d-8e7f-9a0b1c2d3e4f")
        #expect(request.httpBody == nil)
    }

    @Test func anSosAlertReadsTheServersShape() async throws {
        let (api, transport) = locationApi([.ok(sosJSON())])

        let alert = try await api.sosAlert(sosId)

        #expect(alert.id == sosId)
        #expect(alert.childName == "Ali")
        #expect(alert.childPhoneE164 == "+998901234567")
        #expect(alert.status == .active)
        #expect(alert.batteryPercent == 31)
        #expect(alert.deviceOnline)
        #expect(alert.coordinate == Coordinate(latitude: 41.3111, longitude: 69.2797))
        #expect(alert.accuracyMeters == 12)
        #expect(alert.locationFixAt == instant("2026-10-06T06:59:30Z"))
        #expect(alert.placeLabel == nil)
        #expect(alert.acknowledgedAt == nil)
        #expect(await transport.requests.first?.url?.path == "/v1/parent/sos-alerts/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10")
    }

    @Test func acknowledgingPostsAndReturnsTheSettledAlert() async throws {
        let (api, transport) = locationApi([.ok(sosJSON(status: "ACKNOWLEDGED", acknowledged: #","acknowledgedAt":"2026-10-06T07:03:00Z""#))])

        let alert = try await api.acknowledgeSos(sosId)

        #expect(alert.status == .acknowledged)
        #expect(alert.acknowledgedAt == instant("2026-10-06T07:03:00Z"))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/parent/sos-alerts/5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10/acknowledge")
    }

    @Test func anUnknownStatusIsNotActive() async throws {
        let (api, _) = locationApi([.ok(sosJSON(status: "ESCALATED"))])

        #expect(try await api.sosAlert(sosId).status == .unknown)
    }

    @Test func aZoneBecomesItsOwnDraft() {
        let zone = SafeZone(id: zoneId, childId: aliId, name: "Maktab", latitude: 1, longitude: 2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "school", isActive: true)

        #expect(zone.draft == SafeZoneDraft(name: "Maktab", latitude: 1, longitude: 2, radiusMeters: 300, notifyOnEnter: false, notifyOnExit: true, iconKey: "school"))
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift` — `CodeCase` argumentlar ro'yxatiga qo'shing:

```swift
        CodeCase(status: 403, code: .safeZoneLimitReached, expected: .safeZoneLimitReached),
```

va suite ichiga:

```swift
    @Test func theZoneLimitHasItsOwnSentence() {
        #expect(UserMessage.safeZoneLimitReached.text(L10n(.uz)) == L10n(.uz).dataErrorSafeZoneLimitReached)
    }
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirLocationTests`, so'ng `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `NozirLocation` manbasi yo'q; `type 'ApiErrorCode' has no member 'safeZoneLimitReached'`.

- [ ] **Step 4: Xato kodi, `UserMessage`, `ActiveSos`**

`NozirKit/Sources/NozirNetworking/ApiErrorCode.swift` — `subscriptionRequired` qatoridan keyin:

```swift
    public static let safeZoneLimitReached = ApiErrorCode(rawValue: "SAFE_ZONE_LIMIT_REACHED")
```

`NozirKit/Sources/NozirAppFeature/UserMessage.swift`:
- `case childLimitReached, subscriptionRequired, childNotActive` qatorini `case childLimitReached, subscriptionRequired, childNotActive, safeZoneLimitReached` ga almashtiring;
- `meaning(of:)` ichida `case .childNotActive: return .childNotActive` dan keyin `case .safeZoneLimitReached: return .safeZoneLimitReached`;
- `text(_:)` ichida `case .childNotActive: l10n.dataErrorChildNotActive` dan keyin `case .safeZoneLimitReached: l10n.dataErrorSafeZoneLimitReached`.

`NozirKit/Sources/NozirInsights/InsightModels.swift` — `public struct ActiveSos: Decodable, Equatable, Sendable {` ni `public struct ActiveSos: Decodable, Hashable, Sendable {` ga almashtiring (chetlanish E5).

- [ ] **Step 5: Modellar**

`NozirKit/Sources/NozirLocation/LocationModels.swift`:

```swift
import Foundation

/// A point on the map. Not CoreLocation's type: that one is not Hashable and
/// this module has no reason to import a framework for two numbers.
public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Why the phone gave no position. A reason this app does not know reads as "no fix".
public enum LocationUnavailableReason: String, Sendable, Decodable {
    case locationOff = "LOCATION_OFF"
    case permissionDenied = "PERMISSION_DENIED"
    case noFix = "NO_FIX"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = LocationUnavailableReason(rawValue: raw) ?? .noFix
    }
}

/// `LocationSnapshotDto`: the last fix, or only the reason there is none.
/// `isStale` is the server's verdict (older than ~35 minutes); the app never
/// decides it.
public struct LocationSnapshot: Decodable, Equatable, Sendable {
    public let occurredAt: Date?
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyMeters: Double?
    public let zoneId: UUID?
    public let zoneName: String?
    public let placeLabel: String?
    public let batteryPercent: Int?
    public let isStale: Bool
    public let unavailableReason: LocationUnavailableReason?
    public let unavailableAt: Date?

    public init(
        occurredAt: Date? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        zoneId: UUID? = nil,
        zoneName: String? = nil,
        placeLabel: String? = nil,
        batteryPercent: Int? = nil,
        isStale: Bool = false,
        unavailableReason: LocationUnavailableReason? = nil,
        unavailableAt: Date? = nil
    ) {
        self.occurredAt = occurredAt
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.zoneId = zoneId
        self.zoneName = zoneName
        self.placeLabel = placeLabel
        self.batteryPercent = batteryPercent
        self.isStale = isStale
        self.unavailableReason = unavailableReason
        self.unavailableAt = unavailableAt
    }

    /// Only when the server gave both halves.
    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}

/// What a parent sends for a zone (`SafeZoneBody`). `iconKey` is carried, not edited.
public struct SafeZoneDraft: Encodable, Equatable, Sendable {
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var radiusMeters: Int
    public var notifyOnEnter: Bool
    public var notifyOnExit: Bool
    public var iconKey: String?

    public init(
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        notifyOnEnter: Bool,
        notifyOnExit: Bool,
        iconKey: String? = nil
    ) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
        self.iconKey = iconKey
    }
}

/// `SafeZoneDto`. `isActive` is false when the plan no longer includes zones:
/// the zone is kept, but nothing alerts on it.
public struct SafeZone: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let radiusMeters: Int
    public let notifyOnEnter: Bool
    public let notifyOnExit: Bool
    public let iconKey: String?
    public let isActive: Bool

    public init(
        id: UUID,
        childId: UUID,
        name: String,
        latitude: Double,
        longitude: Double,
        radiusMeters: Int,
        notifyOnEnter: Bool,
        notifyOnExit: Bool,
        iconKey: String? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.childId = childId
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.radiusMeters = radiusMeters
        self.notifyOnEnter = notifyOnEnter
        self.notifyOnExit = notifyOnExit
        self.iconKey = iconKey
        self.isActive = isActive
    }

    enum CodingKeys: String, CodingKey {
        case id = "zoneId"
        case childId, name, latitude, longitude, radiusMeters, notifyOnEnter, notifyOnExit, iconKey, isActive
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        name = try container.decode(String.self, forKey: .name)
        latitude = try container.decode(Double.self, forKey: .latitude)
        longitude = try container.decode(Double.self, forKey: .longitude)
        radiusMeters = try container.decode(Int.self, forKey: .radiusMeters)
        notifyOnEnter = try container.decodeIfPresent(Bool.self, forKey: .notifyOnEnter) ?? true
        notifyOnExit = try container.decodeIfPresent(Bool.self, forKey: .notifyOnExit) ?? false
        iconKey = try container.decodeIfPresent(String.self, forKey: .iconKey)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
    }

    public var coordinate: Coordinate {
        Coordinate(latitude: latitude, longitude: longitude)
    }

    /// The zone as an editable form, exactly as stored.
    public var draft: SafeZoneDraft {
        SafeZoneDraft(
            name: name,
            latitude: latitude,
            longitude: longitude,
            radiusMeters: radiusMeters,
            notifyOnEnter: notifyOnEnter,
            notifyOnExit: notifyOnExit,
            iconKey: iconKey
        )
    }
}

/// `SosStatus`; a value this app does not know is `unknown` — never `active`,
/// so no "I have seen it" is offered for a state nobody understood.
public enum SosStatus: String, Sendable, Decodable {
    case active = "ACTIVE"
    case acknowledged = "ACKNOWLEDGED"
    case cancelledByChild = "CANCELLED_BY_CHILD"
    case resolved = "RESOLVED"
    case unknown

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SosStatus(rawValue: raw) ?? .unknown
    }
}

/// `SosAlertResponse`, the parts P15 shows. The position's time is its own
/// (`locationFixAt`), not the alarm's: "from 11 minutes ago" is honest.
public struct SosAlertDetail: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    public let childName: String?
    public let childPhoneE164: String?
    public let triggeredAt: Date
    public let status: SosStatus
    public let batteryPercent: Int?
    public let deviceOnline: Bool
    public let latitude: Double?
    public let longitude: Double?
    public let accuracyMeters: Double?
    public let locationFixAt: Date?
    public let placeLabel: String?
    public let acknowledgedAt: Date?
    public let cancelledAt: Date?

    public init(
        id: UUID,
        childId: UUID,
        childName: String? = nil,
        childPhoneE164: String? = nil,
        triggeredAt: Date,
        status: SosStatus = .active,
        batteryPercent: Int? = nil,
        deviceOnline: Bool = true,
        latitude: Double? = nil,
        longitude: Double? = nil,
        accuracyMeters: Double? = nil,
        locationFixAt: Date? = nil,
        placeLabel: String? = nil,
        acknowledgedAt: Date? = nil,
        cancelledAt: Date? = nil
    ) {
        self.id = id
        self.childId = childId
        self.childName = childName
        self.childPhoneE164 = childPhoneE164
        self.triggeredAt = triggeredAt
        self.status = status
        self.batteryPercent = batteryPercent
        self.deviceOnline = deviceOnline
        self.latitude = latitude
        self.longitude = longitude
        self.accuracyMeters = accuracyMeters
        self.locationFixAt = locationFixAt
        self.placeLabel = placeLabel
        self.acknowledgedAt = acknowledgedAt
        self.cancelledAt = cancelledAt
    }

    enum CodingKeys: String, CodingKey {
        case id, childId, childName, childPhoneE164, triggeredAt, status, batteryPercent, deviceOnline
        case latitude, longitude, accuracyMeters, locationFixAt, placeLabel, acknowledgedAt, cancelledAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        childName = try container.decodeIfPresent(String.self, forKey: .childName)
        childPhoneE164 = try container.decodeIfPresent(String.self, forKey: .childPhoneE164)
        triggeredAt = try container.decode(Date.self, forKey: .triggeredAt)
        status = try container.decodeIfPresent(SosStatus.self, forKey: .status) ?? .unknown
        batteryPercent = try container.decodeIfPresent(Int.self, forKey: .batteryPercent)
        deviceOnline = try container.decodeIfPresent(Bool.self, forKey: .deviceOnline) ?? false
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        accuracyMeters = try container.decodeIfPresent(Double.self, forKey: .accuracyMeters)
        locationFixAt = try container.decodeIfPresent(Date.self, forKey: .locationFixAt)
        placeLabel = try container.decodeIfPresent(String.self, forKey: .placeLabel)
        acknowledgedAt = try container.decodeIfPresent(Date.self, forKey: .acknowledgedAt)
        cancelledAt = try container.decodeIfPresent(Date.self, forKey: .cancelledAt)
    }

    public var coordinate: Coordinate? {
        guard let latitude, let longitude else { return nil }
        return Coordinate(latitude: latitude, longitude: longitude)
    }
}
```

(`LocationSnapshot` sintez qilingan `Decodable` dan foydalanadi: ixtiyoriy maydonlar `decodeIfPresent`, `isStale` majburiy — backend uni doim yuboradi.)

- [ ] **Step 6: Protokol va API**

`NozirKit/Sources/NozirLocation/LocationService.swift`:

```swift
import Foundation

/// Everything the location and SOS screens ask the server. `LocationApi` is
/// the real one; screen-model tests use a scripted fake.
public protocol LocationService: Sendable {
    /// A 404 (`ApiFailure.isNotFound`) means the phone has never reported.
    func location(of childId: UUID) async throws -> LocationSnapshot
    /// False: no paired phone or no way to wake it.
    func requestLocation(of childId: UUID) async throws -> Bool
    func safeZones(of childId: UUID) async throws -> [SafeZone]
    func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone
    func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone
    func deleteSafeZone(_ zoneId: UUID) async throws
    func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail
    /// Settles the alarm on the server: stops the SMS escalation, tells the child's phone.
    func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail
}
```

`NozirKit/Sources/NozirLocation/LocationApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/children/{id}/location`, `/safe-zones` and `/v1/parent/sos-alerts`
/// (backend `LocationController`, `SafeZoneController`, `SosController`).
public struct LocationApi: LocationService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    static func zonePath(_ id: UUID) -> String {
        "/v1/parent/safe-zones/\(id.uuidString.lowercased())"
    }

    static func sosPath(_ id: UUID) -> String {
        "/v1/parent/sos-alerts/\(id.uuidString.lowercased())"
    }

    public func location(of childId: UUID) async throws -> LocationSnapshot {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/location"), as: LocationSnapshot.self)
    }

    public func requestLocation(of childId: UUID) async throws -> Bool {
        struct Answer: Decodable {
            let asked: Bool
        }
        let request = ApiRequest(method: .post, path: Self.childPath(childId) + "/location/request")
        return try await client.send(request, as: Answer.self).asked
    }

    public func safeZones(of childId: UUID) async throws -> [SafeZone] {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/safe-zones"), as: [SafeZone].self)
    }

    public func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone {
        try await client.send(try .post(Self.childPath(childId) + "/safe-zones", json: draft), as: SafeZone.self)
    }

    public func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone {
        try await client.send(try .put(Self.zonePath(zoneId), json: draft), as: SafeZone.self)
    }

    /// Never plan-gated on the server: a lapsed plan cannot keep a zone alive.
    public func deleteSafeZone(_ zoneId: UUID) async throws {
        try await client.send(ApiRequest(method: .delete, path: Self.zonePath(zoneId)))
    }

    public func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail {
        try await client.send(ApiRequest(method: .get, path: Self.sosPath(sosId)), as: SosAlertDetail.self)
    }

    /// No Idempotency-Key (plan deviation E1): the endpoint is settle-once on
    /// the server, and the screen model guards double taps.
    public func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail {
        try await client.send(ApiRequest(method: .post, path: Self.sosPath(sosId) + "/acknowledge"), as: SosAlertDetail.self)
    }
}
```

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirLocationTests`, so'ng `./scripts/test.sh NozirAppFeatureTests`
Expected: ikkalasida `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirNetworking/ApiErrorCode.swift NozirKit/Sources/NozirAppFeature/UserMessage.swift NozirKit/Sources/NozirInsights/InsightModels.swift NozirKit/Sources/NozirLocation/LocationModels.swift NozirKit/Sources/NozirLocation/LocationService.swift NozirKit/Sources/NozirLocation/LocationApi.swift NozirKit/Tests/NozirLocationTests/LocationFixtures.swift NozirKit/Tests/NozirLocationTests/LocationApiTests.swift NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift
```

Xabar: `location: where the phone last was, its zones, and an alarm's detail`

---
### Task 2: P12b qoidasi `NozirFamily` da — `LocationTracking` va versiyali yozish

**Files:**
- Modify: `NozirKit/Sources/NozirFamily/RuleModels.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyService.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyApi.swift`
- Modify: `NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift`

**Interfaces:**
- Consumes: 2a `RuleSnapshot`, `FamilyApi.entityTag`, `ApiRequest.put(_:json:ifMatch:)`.
- Produces:
  - `public struct LocationTracking: Codable, Equatable, Sendable { var isEnabled: Bool; var intervalMinutes: Int; var zoneIntervalMinutes: Int; var moveMetres: Int; static let standard = LocationTracking(isEnabled: true, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100); static let intervalChoices = [5, 10, 15, 30]; static let zoneIntervalChoices = [1, 3, 5]; static let moveChoices = [50, 100, 200] }` — yetishmagan maydon `standard` dagi qiymatni oladi.
  - `RuleSnapshot.locationTracking: LocationTracking` (javobda yo'q bo'lsa `.standard`); `init(version:screenTime:bedtime:locationTracking: = .standard)`.
  - `FamilyService.setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot`.
  - `FakeFamily.Script.locationTracking: [Result<RuleSnapshot, ApiFailure>]`, `FakeFamily.locationTrackingWrites: [RuleWrite<LocationTracking>]` (chaqiruv nomi `"locationTracking"`); `snapshot(version:limit:bedtime:tracking:)`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift` — `snapshotJSON` ni kuzatuv qismini almashtiradigan qilib o'zgartiring (sukut — avvalgi qisman shakl):

```swift
/// `RuleSnapshotResponse` with the parts 2a does not read left in, as the server sends them.
private func snapshotJSON(version: Int = 7, start: String = "22:00", tracking: String = #"{"isEnabled":false}"#) -> String {
    """
    {"childId":"\(aliId.uuidString.lowercased())","version":\(version),\
    "screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
    "maxTrustBonusMinutes":30,"locationTracking":\(tracking),\
    "bedtime":{"startTime":"\(start)","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]},\
    "appPolicies":[],"familyRules":[],"neverBlockedPackages":["com.android.dialer"]}
    """
}
```

va suite oxiriga:

```swift
    @Test func theTrackingRuleIsReadWhole() async throws {
        let tracking = #"{"isEnabled":true,"intervalMinutes":15,"zoneIntervalMinutes":1,"moveMetres":200}"#
        let (api, _) = familyApi([.ok(snapshotJSON(tracking: tracking))])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.locationTracking == LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 1, moveMetres: 200))
    }

    @Test func aTrackingRuleMissingFieldsTakesTheStandardOnes() async throws {
        let (api, _) = familyApi([.ok(snapshotJSON())])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.locationTracking == LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100))
    }

    @Test func aServerWithoutTheTrackingRuleReadsAsStandard() async throws {
        let body = """
        {"version":3,"screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
        "bedtime":{"startTime":"22:00","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]}}
        """
        let (api, _) = familyApi([.ok(body)])

        #expect(try await api.rules(of: aliId).locationTracking == .standard)
    }

    @Test func aTrackingWriteNamesTheVersionAndSendsAllFour() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 12))])

        let after = try await api.setLocationTracking(
            LocationTracking(isEnabled: false, intervalMinutes: 30, zoneIntervalMinutes: 5, moveMetres: 50),
            of: aliId,
            version: 11
        )

        #expect(after.version == 12)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/location-tracking")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"11\"")
        let body = try #require(request.jsonObject)
        #expect(Set(body.keys) == ["isEnabled", "intervalMinutes", "zoneIntervalMinutes", "moveMetres"])
        #expect(body["isEnabled"] as? Bool == false)
        #expect(body["intervalMinutes"] as? Int == 30)
        #expect(body["moveMetres"] as? Int == 50)
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`
Expected: FAIL — `cannot find 'LocationTracking' in scope`.

- [ ] **Step 3: Model**

`NozirKit/Sources/NozirFamily/RuleModels.swift` — `RuleSnapshot` dan oldin qo'shing:

```swift
/// How often the child's phone reports unasked (`LocationTrackingDto`). Off
/// stops only the automatic reports: "where are they now" and SOS still take a
/// position. Values outside the choices are kept but select nothing on P12b.
public struct LocationTracking: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var intervalMinutes: Int
    public var zoneIntervalMinutes: Int
    public var moveMetres: Int

    public static let standard = LocationTracking(isEnabled: true, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
    public static let intervalChoices = [5, 10, 15, 30]
    public static let zoneIntervalChoices = [1, 3, 5]
    public static let moveChoices = [50, 100, 200]

    public init(isEnabled: Bool, intervalMinutes: Int, zoneIntervalMinutes: Int, moveMetres: Int) {
        self.isEnabled = isEnabled
        self.intervalMinutes = intervalMinutes
        self.zoneIntervalMinutes = zoneIntervalMinutes
        self.moveMetres = moveMetres
    }

    private enum CodingKeys: String, CodingKey {
        case isEnabled, intervalMinutes, zoneIntervalMinutes, moveMetres
    }

    /// A server older than the tracking columns sends some or none of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = Self.standard
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? standard.isEnabled
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? standard.intervalMinutes
        zoneIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .zoneIntervalMinutes) ?? standard.zoneIntervalMinutes
        moveMetres = try container.decodeIfPresent(Int.self, forKey: .moveMetres) ?? standard.moveMetres
    }
}
```

`RuleSnapshot` ni butunlay almashtiring:

```swift
/// `RuleSnapshotResponse`, the parts the app reads. `version` goes back as `If-Match`.
public struct RuleSnapshot: Decodable, Equatable, Sendable {
    public let version: Int64
    public let screenTime: ScreenTimeLimit
    public let bedtime: BedtimeSchedule
    public let locationTracking: LocationTracking

    public init(version: Int64, screenTime: ScreenTimeLimit, bedtime: BedtimeSchedule, locationTracking: LocationTracking = .standard) {
        self.version = version
        self.screenTime = screenTime
        self.bedtime = bedtime
        self.locationTracking = locationTracking
    }

    private enum CodingKeys: String, CodingKey {
        case version, screenTime, bedtime, locationTracking
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int64.self, forKey: .version)
        screenTime = try container.decode(ScreenTimeLimit.self, forKey: .screenTime)
        bedtime = try container.decode(BedtimeSchedule.self, forKey: .bedtime)
        locationTracking = try container.decodeIfPresent(LocationTracking.self, forKey: .locationTracking) ?? .standard
    }
}
```

- [ ] **Step 4: Protokol va API**

`NozirKit/Sources/NozirFamily/FamilyService.swift` — `setBedtime` qatoridan keyin:

```swift
    func setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot
```

`NozirKit/Sources/NozirFamily/FamilyApi.swift` — `setBedtime` funksiyasidan keyin:

```swift
    public func setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(
            Self.childPath(childId) + "/rules/location-tracking",
            json: tracking,
            ifMatch: Self.entityTag(version)
        )
        return try await client.send(request, as: RuleSnapshot.self)
    }
```

- [ ] **Step 5: Oila soxtasi**

`NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift`:
- `Script` ga `var bedtime: ...` qatoridan keyin: `var locationTracking: [Result<RuleSnapshot, ApiFailure>] = []`
- `private(set) var bedtimeWrites` qatoridan keyin: `private(set) var locationTrackingWrites: [RuleWrite<LocationTracking>] = []`
- `setBedtime` funksiyasidan keyin:

```swift
    func setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        locationTrackingWrites.append(RuleWrite(value: tracking, version: version))
        return try next("locationTracking", \.locationTracking)
    }
```

- `snapshot` yordamchisini almashtiring:

```swift
func snapshot(
    version: Int64,
    limit: ScreenTimeLimit = defaultLimit,
    bedtime: BedtimeSchedule = defaultBedtime,
    tracking: LocationTracking = .standard
) -> RuleSnapshot {
    RuleSnapshot(version: version, screenTime: limit, bedtime: bedtime, locationTracking: tracking)
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`, so'ng `./scripts/test.sh NozirAppFeatureTests`
Expected: ikkalasida `** TEST SUCCEEDED **` (2a testlari o'zgarishsiz o'tadi).

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirFamily/RuleModels.swift NozirKit/Sources/NozirFamily/FamilyService.swift NozirKit/Sources/NozirFamily/FamilyApi.swift NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift
```

Xabar: `family: how often the phone reports, read and written by version`

---
### Task 3: Joylashuv va SOS matnlari (`LocationTexts`) va iOS kaliti

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Location/LocationTexts.swift`
- Modify: `NozirKit/l10n/ios/values/strings.xml`, `NozirKit/l10n/ios/values-en/strings.xml`, `NozirKit/l10n/ios/values-ru/strings.xml` (+ `NozirKit/Sources/NozirL10n/L10n.generated.swift` qayta generatsiya)
- Test: `NozirKit/Tests/NozirAppFeatureTests/LocationTextsTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocationSnapshot`, `LocationUnavailableReason`, `SosAlertDetail`, `SafeZone`), Task 2 (`LocationTracking`), 2b (`ElapsedTime`, `DateTexts.timeOfDay`), `L10n`.
- Produces (`enum LocationTexts`, hammasi `static`):
  - `headline(_ snapshot: LocationSnapshot, childName: String?, _ l10n: L10n) -> String` — joy = `zoneName` → `placeLabel` → `locationPlaceUnknown` (chetlanish E2); ism bo'lsa `locationChildAtPlace(ism, joy)`.
  - `updated(_ snapshot:, now: Date, _ l10n:, calendar: Calendar = .current) -> String?` — `occurredAt` bo'lsa `locationUpdatedAt(yosh, soat)`.
  - `accuracy(_ meters: Double?, _ l10n:) -> String?` (`locationAccuracy`, yaxlitlangan), `battery(_ percent: Int?, _ l10n:) -> String?` (`locationBattery`).
  - `unavailable(_ reason:, _ l10n:) -> String`, `unavailableWhen(_ at: Date?, now:, _ l10n:) -> String?`.
  - `tracking(_ tracking: LocationTracking?, _ l10n:) -> String?` — yoqiq: `rulesLinkLocationEvery(interval)`, o'chiq: `locationTrackingOff`, nil: nil.
  - `radius(_ meters: Int, _ l10n:) -> String` (`safeZoneRadiusValue`).
  - `zoneChip(_ zone: SafeZone, _ l10n:) -> String` — faol emas bo'lsa `"{nom} · {iosSafeZoneInactive}"` (`homeChildUsageAndPlace` formati bilan), aks holda nom.
  - SOS: `sosTitle(childName: String?, _ l10n:)`, `sosMeta(triggeredAt: Date, now:, _ l10n:, calendar:)`, `sosPlace(_ alert:, _ l10n:) -> String?` (joy nomi, bo'lmasa koordinatalar `sosLocationCoordinates`; joylashuv yo'q → nil), `sosAccuracy(_ meters: Double?, _ l10n:)`, `sosFixAge(_ alert:, now:, _ l10n:, calendar:) -> (text: String, isStale: Bool)?` (fix vaqti yo'q, lekin joylashuv bor → `sosLocationFixTimeUnknown`, eskirgan emas; 4 soat+ → eskirgan), `sosBattery(_ percent: Int?, _ l10n:)` (`sosFactBatteryValue` yoki `sosFactUnknown`), `sosConnection(online: Bool, _ l10n:)`, `sosSettled(_ alert:, _ l10n:, calendar:) -> String?` (acknowledged/cancelled/resolved izohlari; active/unknown → nil).
  - L10n: `iosSafeZoneInactive` (uz "Faol emas", en "Inactive", ru "Неактивна").

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/LocationTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirLocation
@testable import NozirAppFeature

private let now = Date(timeIntervalSince1970: 1_791_300_000)

private var tashkent: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
    return calendar
}

private func fix(zone: String? = nil, place: String? = nil, minutesAgo: Double = 5, accuracy: Double? = 24.6, battery: Int? = 64) -> LocationSnapshot {
    LocationSnapshot(
        occurredAt: now.addingTimeInterval(-minutesAgo * 60),
        latitude: 41.3111,
        longitude: 69.2797,
        accuracyMeters: accuracy,
        zoneName: zone,
        placeLabel: place,
        batteryPercent: battery
    )
}

private func alert(
    name: String? = "Ali",
    status: SosStatus = .active,
    place: String? = nil,
    hasLocation: Bool = true,
    fixMinutesAgo: Double? = 11,
    acknowledgedAt: Date? = nil
) -> SosAlertDetail {
    SosAlertDetail(
        id: UUID(),
        childId: UUID(),
        childName: name,
        triggeredAt: now.addingTimeInterval(-3 * 60),
        status: status,
        latitude: hasLocation ? 41.3111 : nil,
        longitude: hasLocation ? 69.2797 : nil,
        accuracyMeters: 12,
        locationFixAt: fixMinutesAgo.map { now.addingTimeInterval(-$0 * 60) },
        placeLabel: place,
        acknowledgedAt: acknowledgedAt
    )
}

@Suite struct LocationTextsTests {
    private let l10n = L10n(.uz)

    @Test func theHeadlineNamesTheZoneBeforeTheStreet() {
        #expect(LocationTexts.headline(fix(zone: "Maktab", place: "Amir Temur 1"), childName: "Ali", l10n) == l10n.locationChildAtPlace("Ali", "Maktab"))
        #expect(LocationTexts.headline(fix(place: "Amir Temur 1"), childName: "Ali", l10n) == l10n.locationChildAtPlace("Ali", "Amir Temur 1"))
        #expect(LocationTexts.headline(fix(), childName: nil, l10n) == l10n.locationPlaceUnknown)
        #expect(LocationTexts.headline(fix(zone: "  "), childName: nil, l10n) == l10n.locationPlaceUnknown)
    }

    @Test func theFixSaysHowOldAndWhen() {
        let line = LocationTexts.updated(fix(minutesAgo: 5), now: now, l10n, calendar: tashkent)
        let expectedTime = DateTexts.timeOfDay(now.addingTimeInterval(-300), calendar: tashkent)

        #expect(line == l10n.locationUpdatedAt("5 daqiqa oldin", expectedTime))
        #expect(LocationTexts.updated(LocationSnapshot(isStale: true), now: now, l10n) == nil)
    }

    @Test func accuracyAndBatteryAreWholeNumbers() {
        #expect(LocationTexts.accuracy(24.6, l10n) == l10n.locationAccuracy(25))
        #expect(LocationTexts.accuracy(nil, l10n) == nil)
        #expect(LocationTexts.battery(64, l10n) == l10n.locationBattery(64))
        #expect(LocationTexts.battery(nil, l10n) == nil)
    }

    @Test func eachReasonHasItsSentence() {
        #expect(LocationTexts.unavailable(.locationOff, l10n) == l10n.locationUnavailableOff)
        #expect(LocationTexts.unavailable(.permissionDenied, l10n) == l10n.locationUnavailablePermission)
        #expect(LocationTexts.unavailable(.noFix, l10n) == l10n.locationUnavailableNoFix)
        #expect(LocationTexts.unavailableWhen(now.addingTimeInterval(-120), now: now, l10n) == l10n.locationUnavailableWhen("2 daqiqa oldin"))
        #expect(LocationTexts.unavailableWhen(nil, now: now, l10n) == nil)
    }

    @Test func theTrackingRowSaysEveryOrOff() {
        #expect(LocationTexts.tracking(LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.rulesLinkLocationEvery(15))
        #expect(LocationTexts.tracking(LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.locationTrackingOff)
        #expect(LocationTexts.tracking(nil, l10n) == nil)
    }

    @Test func anInactiveZoneSaysSo() {
        let active = SafeZone(id: UUID(), childId: UUID(), name: "Maktab", latitude: 0, longitude: 0, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)
        let inactive = SafeZone(id: UUID(), childId: UUID(), name: "Uy", latitude: 0, longitude: 0, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false, isActive: false)

        #expect(LocationTexts.zoneChip(active, l10n) == "Maktab")
        #expect(LocationTexts.zoneChip(inactive, l10n) == l10n.homeChildUsageAndPlace("Uy", l10n.iosSafeZoneInactive))
        #expect(L10n(.uz).iosSafeZoneInactive == "Faol emas")
        #expect(L10n(.en).iosSafeZoneInactive == "Inactive")
    }

    @Test func anSosHeaderNamesTheChildOrNot() {
        #expect(LocationTexts.sosTitle(childName: "Ali", l10n) == l10n.sosHeaderTitle("Ali"))
        #expect(LocationTexts.sosTitle(childName: nil, l10n) == l10n.sosHeaderTitleUnnamed)
        let expectedTime = DateTexts.timeOfDay(now.addingTimeInterval(-180), calendar: tashkent)
        #expect(LocationTexts.sosMeta(triggeredAt: alert().triggeredAt, now: now, l10n, calendar: tashkent) == l10n.sosHeaderMeta(expectedTime, "3 daqiqa oldin"))
    }

    @Test func anSosPlaceIsItsNameOrItsCoordinates() {
        #expect(LocationTexts.sosPlace(alert(place: "Maktab"), l10n) == "Maktab")
        #expect(LocationTexts.sosPlace(alert(), l10n) == l10n.sosLocationCoordinates("41.3111", "69.2797"))
        #expect(LocationTexts.sosPlace(alert(hasLocation: false), l10n) == nil)
    }

    @Test func anSosFixIsAgedAndCalledStaleAfterFourHours() {
        let fresh = LocationTexts.sosFixAge(alert(fixMinutesAgo: 11), now: now, l10n, calendar: tashkent)
        let freshTime = DateTexts.timeOfDay(now.addingTimeInterval(-660), calendar: tashkent)
        #expect(fresh?.text == l10n.sosLocationFixTaken(freshTime, "11 daqiqa oldin"))
        #expect(fresh?.isStale == false)

        #expect(LocationTexts.sosFixAge(alert(fixMinutesAgo: 5 * 60), now: now, l10n, calendar: tashkent)?.isStale == true)

        let unknown = LocationTexts.sosFixAge(alert(fixMinutesAgo: nil), now: now, l10n)
        #expect(unknown?.text == l10n.sosLocationFixTimeUnknown)
        #expect(unknown?.isStale == false)

        #expect(LocationTexts.sosFixAge(alert(hasLocation: false, fixMinutesAgo: nil), now: now, l10n) == nil)
    }

    @Test func factsHaveAWordForUnknown() {
        #expect(LocationTexts.sosBattery(31, l10n) == l10n.sosFactBatteryValue(31))
        #expect(LocationTexts.sosBattery(nil, l10n) == l10n.sosFactUnknown)
        #expect(LocationTexts.sosConnection(online: true, l10n) == l10n.sosConnectionOnline)
        #expect(LocationTexts.sosConnection(online: false, l10n) == l10n.sosConnectionOffline)
        #expect(LocationTexts.sosAccuracy(12.4, l10n) == l10n.sosLocationAccuracy(12))
    }

    @Test func aSettledAlarmSaysHow() {
        let seenAt = now.addingTimeInterval(-60)
        let seenTime = DateTexts.timeOfDay(seenAt, calendar: tashkent)

        #expect(LocationTexts.sosSettled(alert(status: .active), l10n, calendar: tashkent) == nil)
        #expect(LocationTexts.sosSettled(alert(status: .unknown), l10n, calendar: tashkent) == nil)
        #expect(LocationTexts.sosSettled(alert(status: .acknowledged, acknowledgedAt: seenAt), l10n, calendar: tashkent) == l10n.sosAcknowledgedNote(seenTime))
        #expect(LocationTexts.sosSettled(alert(status: .acknowledged), l10n, calendar: tashkent) == l10n.sosAcknowledgedNoteNoTime)
        #expect(LocationTexts.sosSettled(alert(status: .cancelledByChild), l10n, calendar: tashkent) == l10n.sosCancelledNote("Ali"))
        #expect(LocationTexts.sosSettled(alert(name: nil, status: .cancelledByChild), l10n, calendar: tashkent) == l10n.sosCancelledNoteUnnamed)
        #expect(LocationTexts.sosSettled(alert(status: .resolved), l10n, calendar: tashkent) == l10n.sosResolvedNote)
    }

    @Test func aRadiusIsWrittenInMetres() {
        #expect(LocationTexts.radius(200, l10n) == l10n.safeZoneRadiusValue(200))
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'LocationTexts' in scope`.

- [ ] **Step 3: iOS kaliti**

`NozirKit/l10n/ios/values/strings.xml` — `</resources>` dan oldin:

```xml
    <!-- iOS shows that a zone is kept but no longer alerts (the plan lapsed); Android does not. -->
    <string name="ios_safe_zone_inactive">Faol emas</string>
```

`NozirKit/l10n/ios/values-en/strings.xml` — `</resources>` dan oldin:

```xml
    <string name="ios_safe_zone_inactive">Inactive</string>
```

`NozirKit/l10n/ios/values-ru/strings.xml` — `</resources>` dan oldin:

```xml
    <string name="ios_safe_zone_inactive">Неактивна</string>
```

Run: `python3 scripts/gen_l10n.py && python3 scripts/gen_l10n.py --check`
Expected: xatosiz, `up to date`; `git diff --stat NozirKit/Sources/NozirL10n/L10n.generated.swift` faqat `iosSafeZoneInactive` qo'shilganini ko'rsatadi.

- [ ] **Step 4: `LocationTexts`**

`NozirKit/Sources/NozirAppFeature/Location/LocationTexts.swift`:

```swift
import Foundation
import NozirFamily
import NozirL10n
import NozirLocation

/// Every sentence the location and SOS screens build from data, in the parent's
/// language. The place name is the server's or nothing: the app never invents one.
enum LocationTexts {
    // MARK: P13

    /// "Ali · Maktab". The zone the child stands in, else the street the server
    /// resolved, else "address unknown" (Android `LocationFix.headline`).
    static func headline(_ snapshot: LocationSnapshot, childName: String?, _ l10n: L10n) -> String {
        let place = present(snapshot.zoneName) ?? present(snapshot.placeLabel) ?? l10n.locationPlaceUnknown
        guard let childName = present(childName) else { return place }
        return l10n.locationChildAtPlace(childName, place)
    }

    /// "5 daqiqa oldin yangilandi · soat 12:05 da olingan".
    static func updated(_ snapshot: LocationSnapshot, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        guard let at = snapshot.occurredAt else { return nil }
        return l10n.locationUpdatedAt(ElapsedTime(from: at, to: now).text(l10n), DateTexts.timeOfDay(at, calendar: calendar))
    }

    static func accuracy(_ meters: Double?, _ l10n: L10n) -> String? {
        meters.map { l10n.locationAccuracy(Int($0.rounded())) }
    }

    static func battery(_ percent: Int?, _ l10n: L10n) -> String? {
        percent.map { l10n.locationBattery($0) }
    }

    static func unavailable(_ reason: LocationUnavailableReason, _ l10n: L10n) -> String {
        switch reason {
        case .locationOff: l10n.locationUnavailableOff
        case .permissionDenied: l10n.locationUnavailablePermission
        case .noFix: l10n.locationUnavailableNoFix
        }
    }

    /// "Telefon javobi: 2 daqiqa oldin".
    static func unavailableWhen(_ at: Date?, now: Date, _ l10n: L10n) -> String? {
        at.map { l10n.locationUnavailableWhen(ElapsedTime(from: $0, to: now).text(l10n)) }
    }

    /// The P12b row's value: "Har 10 daqiqada" or the "off" sentence.
    static func tracking(_ tracking: LocationTracking?, _ l10n: L10n) -> String? {
        guard let tracking else { return nil }
        return tracking.isEnabled ? l10n.rulesLinkLocationEvery(tracking.intervalMinutes) : l10n.locationTrackingOff
    }

    static func radius(_ meters: Int, _ l10n: L10n) -> String {
        l10n.safeZoneRadiusValue(meters)
    }

    /// A zone kept after the plan lapsed says it no longer alerts.
    static func zoneChip(_ zone: SafeZone, _ l10n: L10n) -> String {
        zone.isActive ? zone.name : l10n.homeChildUsageAndPlace(zone.name, l10n.iosSafeZoneInactive)
    }

    // MARK: P15

    static func sosTitle(childName: String?, _ l10n: L10n) -> String {
        present(childName).map(l10n.sosHeaderTitle) ?? l10n.sosHeaderTitleUnnamed
    }

    /// "12:02 · 3 daqiqa oldin".
    static func sosMeta(triggeredAt: Date, now: Date, _ l10n: L10n, calendar: Calendar = .current) -> String {
        l10n.sosHeaderMeta(
            DateTexts.timeOfDay(triggeredAt, calendar: calendar),
            ElapsedTime(from: triggeredAt, to: now).text(l10n)
        )
    }

    /// The place name, else the raw coordinates; nil when there is no position at all.
    static func sosPlace(_ alert: SosAlertDetail, _ l10n: L10n) -> String? {
        guard let coordinate = alert.coordinate else { return nil }
        return present(alert.placeLabel)
            ?? l10n.sosLocationCoordinates(String(coordinate.latitude), String(coordinate.longitude))
    }

    static func sosAccuracy(_ meters: Double?, _ l10n: L10n) -> String? {
        meters.map { l10n.sosLocationAccuracy(Int($0.rounded())) }
    }

    /// "12:01 da olingan · 11 daqiqa oldin". Four hours and more is stale and
    /// says so (colour alone never carries the meaning). A position without a
    /// time says that instead; no position, nothing.
    static func sosFixAge(
        _ alert: SosAlertDetail,
        now: Date,
        _ l10n: L10n,
        calendar: Calendar = .current
    ) -> (text: String, isStale: Bool)? {
        guard alert.coordinate != nil else { return nil }
        guard let fixAt = alert.locationFixAt else { return (l10n.sosLocationFixTimeUnknown, false) }
        let age = ElapsedTime(from: fixAt, to: now)
        let isStale: Bool
        if case .stale = age { isStale = true } else { isStale = false }
        return (l10n.sosLocationFixTaken(DateTexts.timeOfDay(fixAt, calendar: calendar), age.text(l10n)), isStale)
    }

    static func sosBattery(_ percent: Int?, _ l10n: L10n) -> String {
        percent.map { l10n.sosFactBatteryValue($0) } ?? l10n.sosFactUnknown
    }

    static func sosConnection(online: Bool, _ l10n: L10n) -> String {
        online ? l10n.sosConnectionOnline : l10n.sosConnectionOffline
    }

    /// Why there is no "I have seen it" button: the alarm is settled.
    static func sosSettled(_ alert: SosAlertDetail, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        switch alert.status {
        case .active, .unknown:
            return nil
        case .acknowledged:
            return alert.acknowledgedAt.map { l10n.sosAcknowledgedNote(DateTexts.timeOfDay($0, calendar: calendar)) }
                ?? l10n.sosAcknowledgedNoteNoTime
        case .cancelledByChild:
            return present(alert.childName).map(l10n.sosCancelledNote) ?? l10n.sosCancelledNoteUnnamed
        case .resolved:
            return l10n.sosResolvedNote
        }
    }

    static func present(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`, `python3 -m unittest discover -s scripts/tests`
Expected: `** TEST SUCCEEDED **`; Python OK.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Location/LocationTexts.swift NozirKit/l10n/ios/values/strings.xml NozirKit/l10n/ios/values-en/strings.xml NozirKit/l10n/ios/values-ru/strings.xml NozirKit/Sources/NozirL10n/L10n.generated.swift NozirKit/Tests/NozirAppFeatureTests/LocationTextsTests.swift
```

Xabar: `location: places, ages and alarms in the parent's words`

---
### Task 4: P13 Joylashuv — `LocationModel`, xarita va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Location/LocationModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/LocationMapView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/FakeLocation.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/LocationModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocationService`, `LocationSnapshot`, `SafeZone`, `Coordinate`), Task 2 (`LocationTracking`, `FamilyService.rules`), Task 3 (`LocationTexts`), 2a/2b (`FamilyStore`, `FakeFamily`, `makeChild`, `offline`, `notFound`, `snapshot(version:…)`, `UserMessage`, `NozirChildSwitcher`, `NozirSwitcherChild`, `NozirEmptyState`, `NozirErrorState`, `NozirOfflineNotice`, `NozirSettingsRow`, `NozirCard`, `NozirButton`, `AvatarTone`).
- Produces:
  - `@MainActor @Observable final class LocationModel { enum Phase: Equatable { loading, ready, neverReported, locked, noChild, failed(UserMessage) }; enum Request: Equatable { idle, waiting, unreachable, failed(UserMessage) }; static let pollAttempts = 12; static let pollInterval: Duration = .milliseconds(2500); static let fallbackCentre = Coordinate(latitude: 41.311081, longitude: 69.240562); var selectedChildId: UUID?; family: FamilyStore; phase; snapshot: LocationSnapshot?; isOffline: Bool; inlineMessage: UserMessage?; zones: [SafeZone]; tracking: LocationTracking?; request: Request; init(family:location:pause:); childId: UUID?; child: Child?; showsSwitcher: Bool; func switcherChildren(_:) -> [NozirSwitcherChild]; load() async; reloadZones() async; requestFix() async; cameraCentre: Coordinate; nonisolated static func isNewer(_:than:) -> Bool }`
  - `struct LocationMapView: View { init(pin: Coordinate?, pinTitle: String, isStale: Bool, zones: [SafeZone], currentZoneId: UUID?, position: Binding<MapCameraPosition>, interactive: Bool = true) }` va `extension CLLocationCoordinate2D { init(_ coordinate: Coordinate) }`; `enum MapCamera { static func region(_ centre: Coordinate, metres: Double) -> MapCameraPosition }`.
  - `struct LocationView: View { init(model: LocationModel, onOpenZone: @escaping (UUID, SafeZone?) -> Void, onOpenTracking: @escaping (UUID) -> Void, onAddChild: @escaping () -> Void) }`
  - Test yordamchilari (`FakeLocation.swift`): `actor FakeLocation: LocationService` (`Script`; `calls`, `childIds`, `add(_:)`), `actor PauseGate` (`pause()`, `untilPaused()`, `release()`), `fixAt(_:minutesAfter:…)`, `zone(_:for:…)`, `baseTime`.

- [ ] **Step 1: Joylashuv soxtasi (keyingi task'lar ham ishlatadi)**

`NozirKit/Tests/NozirAppFeatureTests/FakeLocation.swift`:

```swift
import Foundation
import NozirLocation
import NozirNetworking

/// Answers each call from its own script and records what was asked.
/// Locations are a queue per child whose last answer repeats (a phone that has
/// nothing newer keeps giving the same fix); a child with no queue has never
/// reported (404). Other queues answer like a phone with no connection when empty.
actor FakeLocation: LocationService {
    struct Script: Sendable {
        var locations: [UUID: [Result<LocationSnapshot, ApiFailure>]] = [:]
        var requests: [Result<Bool, ApiFailure>] = []
        var zones: [UUID: Result<[SafeZone], ApiFailure>] = [:]
        var create: [Result<SafeZone, ApiFailure>] = []
        var update: [Result<SafeZone, ApiFailure>] = []
        var delete: [Result<Void, ApiFailure>] = []
        var sos: [Result<SosAlertDetail, ApiFailure>] = []
        var acknowledge: [Result<SosAlertDetail, ApiFailure>] = []
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var childIds: [UUID] = []
    private(set) var drafts: [SafeZoneDraft] = []
    private(set) var zoneIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func location(of childId: UUID) async throws -> LocationSnapshot {
        calls.append("location")
        childIds.append(childId)
        guard var queue = script.locations[childId], let first = queue.first else { throw notFound }
        if queue.count > 1 {
            queue.removeFirst()
            script.locations[childId] = queue
        }
        return try first.get()
    }

    func requestLocation(of childId: UUID) async throws -> Bool {
        calls.append("request")
        childIds.append(childId)
        guard !script.requests.isEmpty else { return true }
        return try script.requests.removeFirst().get()
    }

    func safeZones(of childId: UUID) async throws -> [SafeZone] {
        calls.append("zones")
        childIds.append(childId)
        return try (script.zones[childId] ?? .success([])).get()
    }

    func createSafeZone(_ draft: SafeZoneDraft, for childId: UUID) async throws -> SafeZone {
        calls.append("create")
        childIds.append(childId)
        drafts.append(draft)
        guard !script.create.isEmpty else { throw offline }
        return try script.create.removeFirst().get()
    }

    func updateSafeZone(_ zoneId: UUID, _ draft: SafeZoneDraft) async throws -> SafeZone {
        calls.append("update")
        zoneIds.append(zoneId)
        drafts.append(draft)
        guard !script.update.isEmpty else { throw offline }
        return try script.update.removeFirst().get()
    }

    func deleteSafeZone(_ zoneId: UUID) async throws {
        calls.append("delete")
        zoneIds.append(zoneId)
        guard !script.delete.isEmpty else { throw offline }
        try script.delete.removeFirst().get()
    }

    func sosAlert(_ sosId: UUID) async throws -> SosAlertDetail {
        calls.append("sos")
        guard !script.sos.isEmpty else { throw offline }
        return try script.sos.removeFirst().get()
    }

    func acknowledgeSos(_ sosId: UUID) async throws -> SosAlertDetail {
        calls.append("acknowledge")
        guard !script.acknowledge.isEmpty else { throw offline }
        return try script.acknowledge.removeFirst().get()
    }
}

/// Holds the poll's pause until the test lets it go.
actor PauseGate {
    private var paused = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var held: [CheckedContinuation<Void, Never>] = []

    func pause() async {
        paused += 1
        let ready = waiters
        waiters = []
        ready.forEach { $0.resume() }
        await withCheckedContinuation { held.append($0) }
    }

    /// Returns once some pause is being held.
    func untilPaused() async {
        if !held.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        let waiting = held
        held = []
        waiting.forEach { $0.resume() }
    }
}

let baseTime = Date(timeIntervalSince1970: 1_791_300_000)

func fixAt(
    minutesAfter minutes: Double = 0,
    latitude: Double = 41.3111,
    longitude: Double = 69.2797,
    zoneId: UUID? = nil,
    zoneName: String? = nil,
    isStale: Bool = false
) -> LocationSnapshot {
    LocationSnapshot(
        occurredAt: baseTime.addingTimeInterval(minutes * 60),
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: 20,
        zoneId: zoneId,
        zoneName: zoneName,
        batteryPercent: 60,
        isStale: isStale
    )
}

func reasonAt(minutesAfter minutes: Double, _ reason: LocationUnavailableReason = .locationOff) -> LocationSnapshot {
    LocationSnapshot(isStale: true, unavailableReason: reason, unavailableAt: baseTime.addingTimeInterval(minutes * 60))
}

func zone(
    _ name: String = "Maktab",
    for childId: UUID,
    id: UUID = UUID(),
    radius: Int = 200,
    isActive: Bool = true
) -> SafeZone {
    SafeZone(
        id: id,
        childId: childId,
        name: name,
        latitude: 41.30,
        longitude: 69.25,
        radiusMeters: radius,
        notifyOnEnter: true,
        notifyOnExit: false,
        isActive: isActive
    )
}
```

(`PauseGate.untilPaused` — pauza allaqachon ushlab turilgan bo'lsa darhol qaytadi, aks holda keyingi `pause()` ni kutadi.)

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/LocationModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let vali = makeChild("Vali")

@MainActor
private func setup(
    _ script: FakeLocation.Script,
    children: [Child] = [ali],
    rules: [Result<RuleSnapshot, ApiFailure>] = [],
    pause: @escaping @Sendable (Duration) async throws -> Void = { _ in }
) async -> (LocationModel, FakeLocation, FakeFamily) {
    var familyScript = FakeFamily.Script()
    familyScript.children = [.success(children)]
    familyScript.rules = rules
    let familyFake = FakeFamily(familyScript)
    let store = FamilyStore(service: familyFake)
    try? await store.refresh()
    let fake = FakeLocation(script)
    return (LocationModel(family: store, location: fake, pause: pause), fake, familyFake)
}

@MainActor
@Suite struct LocationModelTests {
    @Test func noChildrenIsNoChild() async {
        let (model, fake, _) = await setup(FakeLocation.Script(), children: [])

        await model.load()

        #expect(model.phase == .noChild)
        #expect(await fake.calls.isEmpty)
    }

    @Test func aFixIsShownWithZonesAndTheTrackingRule() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .success([zone(for: ali.id)])
        let tracking = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)
        let (model, fake, _) = await setup(script, rules: [.success(snapshot(version: 1, tracking: tracking))])

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
        #expect(model.zones.map(\.name) == ["Maktab"])
        #expect(model.tracking == tracking)
        #expect(await fake.calls == ["location", "zones"])
    }

    @Test func aPhoneThatNeverReportedIsNotAnError() async {
        let (model, _, _) = await setup(FakeLocation.Script())

        await model.load()

        #expect(model.phase == .neverReported)
        #expect(model.snapshot == nil)
    }

    @Test func aFreePlanSeesTheLock() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .locked)
    }

    @Test func aFirstFailureIsAFullError() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.failure(offline)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .failed(.noConnection))
    }

    @Test func aLaterOfflineLoadKeepsThePinAndSaysSo() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .failure(offline)]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
        #expect(model.isOffline)
    }

    @Test func aLaterServerFailureKeepsThePinWithAMessage() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .failure(.unexpectedStatus(500))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.load()

        #expect(model.snapshot == fixAt())
        #expect(!model.isOffline)
        #expect(model.inlineMessage == .serverProblem)
    }

    @Test func zonesThatCannotBeReadAreQuietlyLeftOut() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .failure(offline)
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.zones.isEmpty)
        #expect(model.inlineMessage == nil)
    }

    @Test func theFirstChildByDefaultAndAnotherChildStartsFresh() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.zones[ali.id] = .success([zone(for: ali.id)])
        let (model, fake, _) = await setup(script, children: [ali, vali])
        await model.load()
        #expect(model.childId == ali.id)
        #expect(model.showsSwitcher)

        model.selectedChildId = vali.id
        await model.load()

        #expect(model.childId == vali.id)
        #expect(model.phase == .neverReported)
        #expect(model.snapshot == nil)
        #expect(model.zones.isEmpty)
        #expect(await fake.childIds.suffix(2) == [vali.id, vali.id])
    }

    @Test func theCameraOpensOnThePinThenAZoneThenTashkent() async {
        var zoneOnly = FakeLocation.Script()
        zoneOnly.zones[ali.id] = .success([zone(for: ali.id)])
        let (model, _, _) = await setup(zoneOnly)
        #expect(model.cameraCentre == LocationModel.fallbackCentre)
        await model.load()
        #expect(model.cameraCentre == Coordinate(latitude: 41.30, longitude: 69.25))

        var withFix = zoneOnly
        withFix.locations[ali.id] = [.success(fixAt())]
        let (fixed, _, _) = await setup(withFix)
        await fixed.load()
        #expect(fixed.cameraCentre == Coordinate(latitude: 41.3111, longitude: 69.2797))
    }

    // MARK: "Where are they now"

    @Test func anUnreachablePhoneIsSaidAtOnce() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.success(false)]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .unreachable)
        #expect(await fake.calls.filter { $0 == "location" }.count == 1)
    }

    @Test func aNewerFixEndsTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(fixAt()), .success(fixAt(minutesAfter: 1, latitude: 41.32))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .idle)
        #expect(model.snapshot == fixAt(minutesAfter: 1, latitude: 41.32))
        #expect(await fake.calls.filter { $0 == "location" }.count == 3)
    }

    // Review Focus 2.
    @Test func anOldReasonDoesNotEndTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(reasonAt(minutesAfter: 0))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .idle)
        #expect(model.snapshot == reasonAt(minutesAfter: 0))
        #expect(await fake.calls.filter { $0 == "location" }.count == 1 + LocationModel.pollAttempts)
    }

    // Review Focus 2.
    @Test func aNewerReasonEndsTheWait() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(reasonAt(minutesAfter: 2, .noFix))]
        let (model, fake, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.snapshot == reasonAt(minutesAfter: 2, .noFix))
        #expect(await fake.calls.filter { $0 == "location" }.count == 2)
    }

    @Test func aPhoneThatNeverReportedCanStillBeAsked() async {
        var script = FakeLocation.Script()
        script.requests = [.success(true)]
        let (model, fake, _) = await setup(script)
        await model.load()
        #expect(model.phase == .neverReported)
        await fake.add { $0.locations[ali.id] = [.success(fixAt())] }

        await model.requestFix()

        #expect(model.phase == .ready)
        #expect(model.snapshot == fixAt())
    }

    @Test func aRateLimitSaysWhenToTryAgain() async {
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        script.requests = [.failure(.server(status: 429, error: ApiError(code: .rateLimited, retryAfterSeconds: 30)))]
        let (model, _, _) = await setup(script)
        await model.load()

        await model.requestFix()

        #expect(model.request == .failed(.rateLimited(seconds: 30)))
    }

    @Test(.timeLimit(.minutes(1)))
    func twoTapsAskOnce() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt())]
        let (model, fake, _) = await setup(script, pause: { _ in await gate.pause() })
        await model.load()

        let first = Task { await model.requestFix() }
        await gate.untilPaused()
        await model.requestFix()
        #expect(model.request == .waiting)
        await fake.add { $0.locations[ali.id] = [.success(fixAt(minutesAfter: 1))] }
        await gate.release()
        await first.value

        #expect(await fake.calls.filter { $0 == "request" }.count == 1)
        #expect(model.snapshot == fixAt(minutesAfter: 1))
    }

    // Review Focus 1.
    @Test(.timeLimit(.minutes(1)))
    func aWaitForAnotherChildNeverLandsOnScreen() async {
        let gate = PauseGate()
        var script = FakeLocation.Script()
        script.locations[ali.id] = [.success(fixAt()), .success(fixAt(minutesAfter: 5, latitude: 40.0))]
        script.locations[vali.id] = [.success(fixAt(latitude: 39.6, longitude: 66.9))]
        let (model, fake, _) = await setup(script, children: [ali, vali], pause: { _ in await gate.pause() })
        await model.load()

        let wait = Task { await model.requestFix() }
        await gate.untilPaused()
        model.selectedChildId = vali.id
        await model.load()
        await gate.release()
        await wait.value

        #expect(model.childId == vali.id)
        #expect(model.snapshot == fixAt(latitude: 39.6, longitude: 66.9))
        #expect(model.request == .idle)
        let aliLocations = zip(await fake.calls, await fake.childIds).filter { $0.0 == "location" && $0.1 == ali.id }.count
        #expect(aliLocations == 1)
    }

    @Test func newerMeansALaterFixOrALaterReason() {
        #expect(LocationModel.isNewer(fixAt(), than: nil))
        #expect(!LocationModel.isNewer(LocationSnapshot(isStale: true), than: nil))
        #expect(LocationModel.isNewer(fixAt(minutesAfter: 1), than: fixAt()))
        #expect(!LocationModel.isNewer(fixAt(), than: fixAt(minutesAfter: 1)))
        #expect(LocationModel.isNewer(reasonAt(minutesAfter: 1), than: reasonAt(minutesAfter: 0)))
        #expect(!LocationModel.isNewer(reasonAt(minutesAfter: 0), than: reasonAt(minutesAfter: 0)))
        #expect(LocationModel.isNewer(reasonAt(minutesAfter: -5), than: fixAt()))
    }
}

```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'LocationModel' in scope`.

- [ ] **Step 4: `LocationModel`**

`NozirKit/Sources/NozirAppFeature/Location/LocationModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n
import NozirLocation
import NozirNetworking

/// P13. Where the chosen child's phone last was, the child's zones and the
/// tracking rule — asked again every time the tab is shown, never cached: the
/// one thing this app must never be confidently wrong about is where a child is.
/// "Where are they now" wakes the phone and then looks again every 2.5 s, up to
/// twelve times (Android's numbers, not measured).
@MainActor
@Observable
final class LocationModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// 404: the phone has never said anything. An answer, not a fault.
        case neverReported
        /// 403 `SUBSCRIPTION_REQUIRED`.
        case locked
        case noChild
        case failed(UserMessage)
    }

    enum Request: Equatable {
        case idle
        case waiting
        /// The server had no way to wake the phone.
        case unreachable
        case failed(UserMessage)
    }

    static let pollAttempts = 12
    static let pollInterval: Duration = .milliseconds(2500)
    /// Tashkent, when there is neither a pin nor a zone.
    static let fallbackCentre = Coordinate(latitude: 41.311081, longitude: 69.240562)

    var selectedChildId: UUID?
    let family: FamilyStore
    private(set) var phase: Phase = .loading
    private(set) var snapshot: LocationSnapshot?
    private(set) var isOffline = false
    /// A failure other than the connection, shown above a pin that stays.
    private(set) var inlineMessage: UserMessage?
    private(set) var zones: [SafeZone] = []
    private(set) var tracking: LocationTracking?
    private(set) var request: Request = .idle

    private let location: any LocationService
    private let pause: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var shownChildId: UUID?
    /// Bumped when the child changes: an answer for the previous child is dropped.
    @ObservationIgnored private var generation = 0

    init(
        family: FamilyStore,
        location: any LocationService,
        pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.family = family
        self.location = location
        self.pause = pause
    }

    var childId: UUID? {
        if let selectedChildId, family.child(selectedChildId) != nil { return selectedChildId }
        return family.children.first?.id
    }

    var child: Child? {
        childId.flatMap(family.child)
    }

    var showsSwitcher: Bool {
        family.children.count > 1
    }

    func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] {
        family.children.enumerated().map { position, child in
            NozirSwitcherChild(
                id: child.id,
                name: child.displayName,
                tone: .forKey(child.avatarKey, position: position),
                accessibilityLabel: l10n.contentDescriptionChildAvatar(child.displayName)
            )
        }
    }

    /// The pin, else the first zone, else Tashkent.
    var cameraCentre: Coordinate {
        snapshot?.coordinate ?? zones.first?.coordinate ?? Self.fallbackCentre
    }

    /// Every time the tab (or the chosen child) is shown.
    func load() async {
        if !family.hasLoaded {
            do {
                try await family.refresh()
            } catch is CancellationError {
                return
            } catch {
                phase = .failed(UserMessage(error))
                return
            }
        }
        guard let id = childId else {
            startFresh(for: nil)
            phase = .noChild
            return
        }
        if id != shownChildId {
            startFresh(for: id)
        }
        let mine = generation
        do {
            let fresh = try await location.location(of: id)
            guard mine == generation else { return }
            show(fresh)
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            guard mine == generation else { return }
            snapshot = nil
            phase = .neverReported
            isOffline = false
            inlineMessage = nil
        } catch let failure as ApiFailure where failure.code == .subscriptionRequired {
            guard mine == generation else { return }
            snapshot = nil
            phase = .locked
        } catch {
            guard mine == generation else { return }
            let message = UserMessage(error)
            if snapshot == nil {
                phase = .failed(message)
            } else if message == .noConnection || message == .timeout {
                isOffline = true
            } else {
                inlineMessage = message
            }
        }
        await reloadZones()
    }

    /// Zones and the tracking rule. Either failing is quiet: they keep what they had.
    func reloadZones() async {
        guard let id = childId, phase != .locked else { return }
        let mine = generation
        if let fresh = try? await location.safeZones(of: id), mine == generation {
            zones = fresh
        }
        if let rules = try? await family.service.rules(of: id), mine == generation {
            tracking = rules.locationTracking
        }
    }

    /// "Where are they now": wake the phone, then look again until something
    /// newer arrives or twelve looks have passed. Nothing newer is not an error.
    func requestFix() async {
        guard request != .waiting, phase != .locked, let id = childId else { return }
        let mine = generation
        let before = snapshot
        request = .waiting
        do {
            let asked = try await location.requestLocation(of: id)
            guard mine == generation else { return }
            guard asked else {
                request = .unreachable
                return
            }
            for _ in 0..<Self.pollAttempts {
                try await pause(Self.pollInterval)
                guard mine == generation else { return }
                guard let fresh = try? await location.location(of: id) else { continue }
                guard mine == generation else { return }
                if Self.isNewer(fresh, than: before) {
                    show(fresh)
                    request = .idle
                    return
                }
            }
            request = .idle
        } catch is CancellationError {
            if mine == generation { request = .idle }
        } catch {
            if mine == generation { request = .failed(UserMessage(error)) }
        }
    }

    /// A later fix, or a later "no position" reason. Each is compared with its
    /// own kind: the two times come from different clocks.
    nonisolated static func isNewer(_ fresh: LocationSnapshot, than old: LocationSnapshot?) -> Bool {
        if let at = fresh.occurredAt, at > (old?.occurredAt ?? .distantPast) { return true }
        if let at = fresh.unavailableAt, at > (old?.unavailableAt ?? .distantPast) { return true }
        return false
    }

    private func show(_ fresh: LocationSnapshot) {
        snapshot = fresh
        phase = .ready
        isOffline = false
        inlineMessage = nil
    }

    private func startFresh(for id: UUID?) {
        generation += 1
        shownChildId = id
        snapshot = nil
        zones = []
        tracking = nil
        isOffline = false
        inlineMessage = nil
        request = .idle
        phase = .loading
    }
}
```

- [ ] **Step 5: Xarita**

`NozirKit/Sources/NozirAppFeature/Screens/LocationMapView.swift`:

```swift
import MapKit
import SwiftUI
import NozirDesignSystem
import NozirLocation

extension CLLocationCoordinate2D {
    init(_ coordinate: Coordinate) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

enum MapCamera {
    static func region(_ centre: Coordinate, metres: Double) -> MapCameraPosition {
        .region(MKCoordinateRegion(center: CLLocationCoordinate2D(centre), latitudinalMeters: metres, longitudinalMeters: metres))
    }
}

/// The child's pin and the family's zones on Apple Maps. The zone the child is
/// in is drawn in the "good" colour, the rest in the brand colour; a stale pin
/// is faded. No user location, no key.
struct LocationMapView: View {
    let pin: Coordinate?
    let pinTitle: String
    let isStale: Bool
    let zones: [SafeZone]
    let currentZoneId: UUID?
    @Binding var position: MapCameraPosition
    var interactive = true

    var body: some View {
        Map(position: $position, interactionModes: interactive ? [.pan, .zoom] : []) {
            ForEach(zones) { zone in
                let colour = zone.id == currentZoneId ? NozirColor.goodContent : NozirColor.primary
                MapCircle(center: CLLocationCoordinate2D(zone.coordinate), radius: CLLocationDistance(zone.radiusMeters))
                    .foregroundStyle(colour.opacity(0.12))
                    .stroke(colour.opacity(0.55), lineWidth: 3)
            }
            if let pin {
                Annotation(pinTitle, coordinate: CLLocationCoordinate2D(pin)) {
                    Circle()
                        .fill(NozirColor.primary)
                        .frame(width: 18, height: 18)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                        .shadow(radius: 2)
                        .opacity(isStale ? 0.45 : 1)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift`:

```swift
import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P13 as Android `LocationContent`: the switcher, the map, what is known about
/// where the child is, "where are they now", the zones and the tracking rule.
struct LocationView: View {
    @State private var model: LocationModel
    private let onOpenZone: (UUID, SafeZone?) -> Void
    private let onOpenTracking: (UUID) -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase
    @State private var position: MapCameraPosition = MapCamera.region(LocationModel.fallbackCentre, metres: 4000)

    init(
        model: LocationModel,
        onOpenZone: @escaping (UUID, SafeZone?) -> Void,
        onOpenTracking: @escaping (UUID) -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onOpenZone = onOpenZone
        self.onOpenTracking = onOpenTracking
        self.onAddChild = onAddChild
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.medium) {
                if model.showsSwitcher {
                    NozirChildSwitcher(
                        children: model.switcherChildren(l10n),
                        selection: Binding(get: { model.childId }, set: { model.selectedChildId = $0 }),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenMapTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.childId) { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .onChange(of: model.cameraCentre) { _, centre in
            position = MapCamera.region(centre, metres: model.snapshot?.coordinate == nil ? 2500 : 1200)
        }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        case .noChild:
            NozirEmptyState(
                title: l10n.locationNoChildTitle,
                message: l10n.locationNoChildBody,
                actionTitle: l10n.homeEmptyAction,
                action: onAddChild
            )
        case .locked:
            NozirCard {
                Text(l10n.planLockLocationTitle).nozirText(.titleSmall)
                Text(l10n.planLockLocationBody).nozirText(.body)
                Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .ready, .neverReported:
            located
        }
    }

    @ViewBuilder
    private var located: some View {
        if model.isOffline {
            NozirOfflineNotice(l10n.stateOfflineNotice)
        }
        if let message = model.inlineMessage {
            NozirInlineMessage(message.text(l10n))
        }
        LocationMapView(
            pin: model.snapshot?.coordinate,
            pinTitle: model.child?.displayName ?? "",
            isStale: model.snapshot?.isStale ?? false,
            zones: model.zones,
            currentZoneId: model.snapshot?.zoneId,
            position: $position
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
        .accessibilityLabel(l10n.locationMapDescription)
        statusCard
        requestSection
        zoneChips
        if let childId = model.childId {
            NozirCard {
                NozirSettingsRow(l10n.locationTrackingToggleTitle, value: LocationTexts.tracking(model.tracking, l10n)) {
                    onOpenTracking(childId)
                }
            }
        }
    }

    @ViewBuilder
    private var statusCard: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if let snapshot = model.snapshot {
                NozirCard(tone: snapshot.isStale ? .attention : .plain) {
                    if snapshot.coordinate != nil {
                        Text(LocationTexts.headline(snapshot, childName: model.child?.displayName, l10n)).nozirText(.titleSmall)
                        if let updated = LocationTexts.updated(snapshot, now: context.date, l10n) {
                            Text(updated).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                        HStack(spacing: NozirSpacing.medium) {
                            if let accuracy = LocationTexts.accuracy(snapshot.accuracyMeters, l10n) {
                                Text(accuracy).nozirText(.bodySmall, color: NozirColor.textSecondary)
                            }
                            if let battery = LocationTexts.battery(snapshot.batteryPercent, l10n) {
                                Text(battery).nozirText(.bodySmall, color: NozirColor.textSecondary)
                            }
                        }
                    } else {
                        Text(l10n.locationUnknownTitle).nozirText(.titleSmall)
                    }
                    if let reason = snapshot.unavailableReason {
                        Text(LocationTexts.unavailable(reason, l10n)).nozirText(.body)
                        if let when = LocationTexts.unavailableWhen(snapshot.unavailableAt, now: context.date, l10n) {
                            Text(when).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    if snapshot.isStale, snapshot.coordinate != nil {
                        Text(l10n.locationStaleNote).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                }
                .accessibilityElement(children: .combine)
            } else {
                NozirEmptyState(title: l10n.locationNeverReportedTitle, message: l10n.locationNeverReportedBody)
            }
        }
    }

    @ViewBuilder
    private var requestSection: some View {
        NozirButton(l10n.locationRequestFix, variant: .secondary, isLoading: model.request == .waiting) {
            Task { await model.requestFix() }
        }
        .disabled(model.request == .waiting)
        switch model.request {
        case .idle:
            EmptyView()
        case .waiting:
            Text(l10n.locationRequestWaiting).nozirText(.bodySmall, color: NozirColor.textSecondary)
        case .unreachable:
            NozirInlineMessage(l10n.locationRequestUnreachable)
        case .failed(let message):
            NozirInlineMessage(message.text(l10n))
        }
    }

    private var zoneChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: NozirSpacing.small) {
                ForEach(model.zones) { zone in
                    chip(LocationTexts.zoneChip(zone, l10n), highlighted: zone.id == model.snapshot?.zoneId) {
                        if let childId = model.childId { onOpenZone(childId, zone) }
                    }
                }
                chip(l10n.locationAddZone, highlighted: false) {
                    if let childId = model.childId { onOpenZone(childId, nil) }
                }
            }
        }
    }

    private func chip(_ title: String, highlighted: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .nozirText(.bodySmall, color: highlighted ? NozirColor.goodContent : NozirColor.primaryAccent)
                .padding(.horizontal, NozirSpacing.compact)
                .padding(.vertical, NozirSpacing.small)
                .background(Capsule().fill(highlighted ? NozirColor.goodContainer : NozirColor.primaryContainer))
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests` (ikki marta — gated testlar barqarorligini ko'rish uchun)
Expected: ikkalasida `** TEST SUCCEEDED **`; hech bir test osilmaydi.

Gated testlar haqiqatan nimanidir tutishini tekshiring: `requestFix` dagi pauzadan keyingi `guard mine == generation else { return }` ni vaqtincha olib tashlang → `aWaitForAnotherChildNeverLandsOnScreen` FAIL bo'lishi kerak; qayta tiklang va hisobotda yozing.

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Location/LocationModel.swift NozirKit/Sources/NozirAppFeature/Screens/LocationMapView.swift NozirKit/Sources/NozirAppFeature/Screens/LocationView.swift NozirKit/Tests/NozirAppFeatureTests/FakeLocation.swift NozirKit/Tests/NozirAppFeatureTests/LocationModelTests.swift
```

Xabar: `p13: where the child is, and asking the phone to say again`

---
### Task 5: P14 Xavfsiz hudud — `SafeZoneModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Location/SafeZoneModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SafeZoneModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocationService`, `SafeZone`, `SafeZoneDraft`, `Coordinate`, `ApiFailure.isNotFound`), Task 3 (`LocationTexts.radius`), Task 4 (`LocationMapView`, `MapCamera`, `CLLocationCoordinate2D(_:)`, `LocationModel.fallbackCentre`, `FakeLocation`, `fixAt`, `zone(…)`), 2a (`UserMessage`, `NozirTextField`, `NozirButton`, `NozirCard`, `NozirInlineMessage`).
- Produces:
  - `@MainActor @Observable final class SafeZoneModel { enum Hint: Equatable { needsPlace, needsName, centredOnLastFix }; enum Deletion: Equatable { idle, confirming, deleting }; static let radiusRange = 50...5000; static let defaultRadius = 200; static let nameLimit = 60; childId: UUID; zoneId: UUID?; isEditing: Bool; name: String; radius: Int; var notifyOnEnter: Bool; var notifyOnExit: Bool; centre: Coordinate?; isLoading: Bool; isMissing: Bool; message: UserMessage?; isSaving: Bool; wasSaved: Bool; deletion: Deletion; wasDeleted: Bool; init(childId:zoneId:location:); load() async; updateName(_:); updateRadius(_:); place(at:); draft: SafeZoneDraft?; canSave: Bool; hint: Hint?; save() async; askToDelete(); cancelDelete(); confirmDelete() async }`
  - `struct SafeZoneView: View { init(model: SafeZoneModel, onFinished: @escaping () -> Void) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SafeZoneModelTests.swift`:

```swift
import Foundation
import Testing
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let schoolId = UUID()

@MainActor
private func setup(_ script: FakeLocation.Script, zoneId: UUID? = nil) -> (SafeZoneModel, FakeLocation) {
    let fake = FakeLocation(script)
    return (SafeZoneModel(childId: childId, zoneId: zoneId, location: fake), fake)
}

private func scriptWithSchool() -> FakeLocation.Script {
    var script = FakeLocation.Script()
    script.zones[childId] = .success([zone("Maktab", for: childId, id: schoolId, radius: 300)])
    return script
}

@MainActor
@Suite struct SafeZoneModelTests {
    @Test func aNewZoneStartsOnTheChildsLastFix() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        let (model, _) = setup(script)

        await model.load()

        #expect(!model.isEditing)
        #expect(model.centre == Coordinate(latitude: 41.3111, longitude: 69.2797))
        #expect(model.radius == 200)
        #expect(model.notifyOnEnter)
        #expect(!model.notifyOnExit)
        #expect(model.hint == .needsName)
        model.updateName("Maktab")
        #expect(model.hint == .centredOnLastFix)
        #expect(model.canSave)
    }

    @Test func withoutAFixThePlaceMustBeChosen() async {
        let (model, _) = setup(FakeLocation.Script())

        await model.load()
        model.updateName("Uy")

        #expect(model.centre == nil)
        #expect(model.hint == .needsPlace)
        #expect(!model.canSave)

        model.place(at: Coordinate(latitude: 41.2, longitude: 69.1))

        #expect(model.hint == nil)
        #expect(model.canSave)
    }

    @Test func aBlankNameCannotBeSavedAndANameStopsAtSixty() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        let (model, _) = setup(script)
        await model.load()

        model.updateName("   ")
        #expect(!model.canSave)

        model.updateName(String(repeating: "a", count: 70))
        #expect(model.name.count == 60)
    }

    @Test func theRadiusStaysWithinItsRange() async {
        let (model, _) = setup(FakeLocation.Script())

        model.updateRadius(10)
        #expect(model.radius == 50)
        model.updateRadius(9000)
        #expect(model.radius == 5000)
    }

    @Test func savingANewZonePostsItForTheChild() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.success(zone("Maktab", for: childId))]
        let (model, fake) = setup(script)
        await model.load()
        model.updateName(" Maktab ")

        await model.save()

        #expect(model.wasSaved)
        #expect(await fake.calls.last == "create")
        #expect(await fake.drafts == [SafeZoneDraft(name: "Maktab", latitude: 41.3111, longitude: 69.2797, radiusMeters: 200, notifyOnEnter: true, notifyOnExit: false)])
    }

    @Test func anExistingZoneOpensAsStoredAndSavesOnlyWhenChanged() async {
        var script = scriptWithSchool()
        script.update = [.success(zone("Maktab 2", for: childId, id: schoolId))]
        let (model, fake) = setup(script, zoneId: schoolId)

        await model.load()

        #expect(model.isEditing)
        #expect(model.name == "Maktab")
        #expect(model.radius == 300)
        #expect(model.centre == Coordinate(latitude: 41.30, longitude: 69.25))
        #expect(model.hint == nil)
        #expect(!model.canSave)

        model.updateName("Maktab 2")
        await model.save()

        #expect(model.wasSaved)
        #expect(await fake.zoneIds == [schoolId])
        #expect(await fake.drafts.first?.name == "Maktab 2")
    }

    // Review Focus 3.
    @Test func aZoneGoneElsewhereIsNotFound() async {
        var script = FakeLocation.Script()
        script.zones[childId] = .success([])
        let (model, _) = setup(script, zoneId: schoolId)

        await model.load()

        #expect(model.isMissing)
        #expect(model.message == .notFound)
        #expect(!model.canSave)
    }

    @Test func theZoneLimitIsSaid() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.failure(.server(status: 409, error: ApiError(code: .safeZoneLimitReached)))]
        let (model, _) = setup(script)
        await model.load()
        model.updateName("Maktab")

        await model.save()

        #expect(!model.wasSaved)
        #expect(model.message == .safeZoneLimitReached)
        #expect(!model.isSaving)
    }

    @Test func aFreePlanCannotAddAZone() async {
        var script = FakeLocation.Script()
        script.locations[childId] = [.success(fixAt())]
        script.create = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _) = setup(script)
        await model.load()
        model.updateName("Maktab")

        await model.save()

        #expect(model.message == .subscriptionRequired)
    }

    @Test func deletingAsksFirst() async {
        var script = scriptWithSchool()
        script.delete = [.success(())]
        let (model, fake) = setup(script, zoneId: schoolId)
        await model.load()

        model.askToDelete()
        #expect(model.deletion == .confirming)
        model.cancelDelete()
        #expect(model.deletion == .idle)
        #expect(await fake.calls.contains("delete") == false)

        model.askToDelete()
        await model.confirmDelete()

        #expect(model.wasDeleted)
        #expect(await fake.zoneIds == [schoolId])
    }

    @Test func aFailedDeleteGoesBackToTheQuestion() async {
        var script = scriptWithSchool()
        script.delete = [.failure(offline)]
        let (model, _) = setup(script, zoneId: schoolId)
        await model.load()
        model.askToDelete()

        await model.confirmDelete()

        #expect(!model.wasDeleted)
        #expect(model.deletion == .confirming)
        #expect(model.message == .noConnection)
    }

    @Test func aNewZoneCannotBeDeleted() async {
        let (model, _) = setup(FakeLocation.Script())
        await model.load()

        model.askToDelete()

        #expect(model.deletion == .idle)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'SafeZoneModel' in scope`.

- [ ] **Step 3: `SafeZoneModel`**

`NozirKit/Sources/NozirAppFeature/Location/SafeZoneModel.swift`:

```swift
import Foundation
import Observation
import NozirLocation
import NozirNetworking

/// P14: one screen for a new zone and an existing one. The centre is placed by
/// tapping the map (no search: that needs a places service). A new zone opens
/// on the child's last fix and says the pin was placed for the parent.
@MainActor
@Observable
final class SafeZoneModel {
    enum Hint: Equatable {
        case needsPlace, needsName, centredOnLastFix
    }

    enum Deletion: Equatable {
        case idle, confirming, deleting
    }

    static let radiusRange = 50...5000
    static let defaultRadius = 200
    static let nameLimit = 60

    let childId: UUID
    let zoneId: UUID?
    private(set) var name = ""
    private(set) var radius = SafeZoneModel.defaultRadius
    var notifyOnEnter = true
    var notifyOnExit = false
    private(set) var centre: Coordinate?
    private(set) var isLoading = true
    /// The zone was deleted on another phone: say so rather than open a blank form.
    private(set) var isMissing = false
    private(set) var message: UserMessage?
    private(set) var isSaving = false
    private(set) var wasSaved = false
    private(set) var deletion: Deletion = .idle
    private(set) var wasDeleted = false

    private let location: any LocationService
    @ObservationIgnored private var stored: SafeZoneDraft?
    @ObservationIgnored private var centredOnFix = false

    init(childId: UUID, zoneId: UUID?, location: any LocationService) {
        self.childId = childId
        self.zoneId = zoneId
        self.location = location
    }

    var isEditing: Bool {
        zoneId != nil
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        message = nil
        if let zoneId {
            do {
                let zones = try await location.safeZones(of: childId)
                guard let zone = zones.first(where: { $0.id == zoneId }) else {
                    isMissing = true
                    message = .notFound
                    return
                }
                stored = zone.draft
                name = zone.name
                radius = zone.radiusMeters
                notifyOnEnter = zone.notifyOnEnter
                notifyOnExit = zone.notifyOnExit
                centre = zone.coordinate
            } catch is CancellationError {
                return
            } catch {
                message = UserMessage(error)
            }
        } else if centre == nil, let fix = try? await location.location(of: childId).coordinate {
            centre = fix
            centredOnFix = true
        }
    }

    func updateName(_ text: String) {
        name = String(text.prefix(Self.nameLimit))
    }

    func updateRadius(_ metres: Int) {
        radius = min(max(metres, Self.radiusRange.lowerBound), Self.radiusRange.upperBound)
    }

    func place(at coordinate: Coordinate) {
        centre = coordinate
        centredOnFix = false
    }

    /// What would be sent; nil until there is a place and a name.
    var draft: SafeZoneDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let centre, !trimmed.isEmpty, !isMissing else { return nil }
        return SafeZoneDraft(
            name: trimmed,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radiusMeters: radius,
            notifyOnEnter: notifyOnEnter,
            notifyOnExit: notifyOnExit,
            iconKey: stored?.iconKey
        )
    }

    var canSave: Bool {
        guard !isSaving, deletion == .idle, let draft else { return false }
        return draft != stored
    }

    var hint: Hint? {
        if centre == nil { return .needsPlace }
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .needsName }
        if centredOnFix { return .centredOnLastFix }
        return nil
    }

    func save() async {
        guard canSave, let draft else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            if let zoneId {
                _ = try await location.updateSafeZone(zoneId, draft)
            } else {
                _ = try await location.createSafeZone(draft, for: childId)
            }
            wasSaved = true
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
        }
    }

    func askToDelete() {
        guard isEditing, !isMissing, deletion == .idle else { return }
        deletion = .confirming
    }

    func cancelDelete() {
        guard deletion == .confirming else { return }
        deletion = .idle
    }

    func confirmDelete() async {
        guard deletion == .confirming, let zoneId else { return }
        deletion = .deleting
        message = nil
        do {
            try await location.deleteSafeZone(zoneId)
            wasDeleted = true
        } catch {
            deletion = .confirming
            message = UserMessage(error)
        }
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift`:

```swift
import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P14 as Android `SafeZoneContent`: tap the map for the centre, name it, size
/// it, choose the alerts; delete with a second question.
struct SafeZoneView: View {
    @State private var model: SafeZoneModel
    private let onFinished: () -> Void
    @Environment(\.l10n) private var l10n
    @State private var position: MapCameraPosition = MapCamera.region(LocationModel.fallbackCentre, metres: 4000)

    init(model: SafeZoneModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                } else if model.isMissing {
                    NozirInlineMessage(UserMessage.notFound.text(l10n))
                } else {
                    form
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(model.isEditing ? l10n.safeZoneEditTitle : l10n.screenSafeZoneTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .onChange(of: model.wasSaved || model.wasDeleted) { _, done in
            if done { onFinished() }
        }
        .onChange(of: model.isLoading) { _, loading in
            if !loading, let centre = model.centre {
                position = MapCamera.region(centre, metres: 1200)
            }
        }
    }

    @ViewBuilder
    private var form: some View {
        MapReader { proxy in
            LocationMapView(
                pin: model.centre,
                pinTitle: model.name,
                isStale: false,
                zones: previewZone.map { [$0] } ?? [],
                currentZoneId: nil,
                position: $position
            )
            .onTapGesture { point in
                if let tapped = proxy.convert(point, from: .local) {
                    model.place(at: Coordinate(latitude: tapped.latitude, longitude: tapped.longitude))
                }
            }
        }
        .frame(height: 280)
        .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
        .accessibilityLabel(l10n.safeZoneMapDescription)
        if let hint = model.hint {
            Text(hintText(hint)).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        NozirTextField(
            l10n.safeZoneNameLabel,
            text: Binding(get: { model.name }, set: { model.updateName($0) }),
            placeholder: l10n.safeZoneNamePlaceholder
        )
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            HStack {
                Text(l10n.safeZoneRadiusLabel).nozirText(.body)
                Spacer()
                Text(LocationTexts.radius(model.radius, l10n)).nozirText(.body, color: NozirColor.textSecondary)
            }
            Slider(
                value: Binding(get: { Double(model.radius) }, set: { model.updateRadius(Int($0.rounded())) }),
                in: Double(SafeZoneModel.radiusRange.lowerBound)...Double(SafeZoneModel.radiusRange.upperBound),
                step: 50
            )
            .tint(NozirColor.primary)
            .accessibilityValue(LocationTexts.radius(model.radius, l10n))
        }
        NozirCard {
            Toggle(l10n.safeZoneNotifyEnter, isOn: $model.notifyOnEnter)
            Divider()
            Toggle(l10n.safeZoneNotifyExit, isOn: $model.notifyOnExit)
            Text(l10n.safeZoneNotifyExitHint).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .tint(NozirColor.primary)
        if let message = model.message {
            NozirInlineMessage(message.text(l10n))
        }
        NozirButton(l10n.safeZoneSave, size: .callToAction, isLoading: model.isSaving) {
            Task { await model.save() }
        }
        .disabled(!model.canSave)
        if model.isEditing {
            deletion
        }
    }

    @ViewBuilder
    private var deletion: some View {
        switch model.deletion {
        case .idle:
            NozirButton(l10n.safeZoneDelete, variant: .criticalOutline) { model.askToDelete() }
        case .confirming, .deleting:
            NozirCard(tone: .attention) {
                Text(l10n.safeZoneDeleteTitle(model.name)).nozirText(.titleSmall)
                Text(l10n.safeZoneDeleteBody).nozirText(.bodySmall)
                HStack(spacing: NozirSpacing.small) {
                    NozirButton(l10n.safeZoneDeleteCancel, variant: .secondary) { model.cancelDelete() }
                        .disabled(model.deletion == .deleting)
                    NozirButton(l10n.safeZoneDeleteConfirm, variant: .criticalOutline, isLoading: model.deletion == .deleting) {
                        Task { await model.confirmDelete() }
                    }
                }
            }
        }
    }

    /// The circle as it would be saved, drawn live while the radius moves.
    private var previewZone: SafeZone? {
        guard let centre = model.centre else { return nil }
        return SafeZone(
            id: model.zoneId ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            childId: model.childId,
            name: model.name,
            latitude: centre.latitude,
            longitude: centre.longitude,
            radiusMeters: model.radius,
            notifyOnEnter: model.notifyOnEnter,
            notifyOnExit: model.notifyOnExit
        )
    }

    private func hintText(_ hint: SafeZoneModel.Hint) -> String {
        switch hint {
        case .needsPlace: l10n.safeZonePlaceHint
        case .needsName: l10n.safeZoneNameHint
        case .centredOnLastFix: l10n.safeZoneCentredHint
        }
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Location/SafeZoneModel.swift NozirKit/Sources/NozirAppFeature/Screens/SafeZoneView.swift NozirKit/Tests/NozirAppFeatureTests/SafeZoneModelTests.swift
```

Xabar: `p14: a circle on the map, named, and the alerts it gives`

---
### Task 6: P12b Joylashuvni kuzatish — `LocationTrackingModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/LocationTrackingModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`LocationTracking`, `FamilyService.rules`, `setLocationTracking`, `FakeFamily.Script.locationTracking`, `locationTrackingWrites`, `snapshot(version:…:tracking:)`), 2a (`FamilyStore`, `UserMessage`, `NozirCard`, `NozirButton`, `NozirErrorState`, `NozirInlineMessage`).
- Produces:
  - `@MainActor @Observable final class LocationTrackingModel { enum Notice: Equatable { saved, conflict }; childId: UUID; childName: String?; tracking: LocationTracking?; isLoading: Bool; loadFailure: UserMessage?; message: UserMessage?; notice: Notice?; isSaving: Bool; canSave: Bool; init(childId:childName:family:); load() async; setEnabled(_:); setInterval(_:); setZoneInterval(_:); setMove(_:); save() async }`
  - `struct LocationTrackingView: View { init(model: LocationTrackingModel) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/LocationTrackingModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let childId = UUID()
private let every15 = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)

@MainActor
private func setup(_ script: FakeFamily.Script) -> (LocationTrackingModel, FakeFamily) {
    let fake = FakeFamily(script)
    return (LocationTrackingModel(childId: childId, childName: "Ali", family: FamilyStore(service: fake)), fake)
}

@MainActor
@Suite struct LocationTrackingModelTests {
    @Test func theRuleIsReadAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.tracking == every15)
        #expect(!model.canSave)

        model.setInterval(30)

        #expect(model.tracking?.intervalMinutes == 30)
        #expect(model.canSave)
    }

    @Test func turningOffKeepsTheNumbers() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)
        await model.load()

        model.setEnabled(false)

        #expect(model.tracking == LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100))
    }

    @Test func savingNamesTheVersionItWasReadAt() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let changed = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 1, moveMetres: 50)
        script.locationTracking = [.success(snapshot(version: 5, tracking: changed))]
        let (model, fake) = setup(script)
        await model.load()
        model.setZoneInterval(1)
        model.setMove(50)

        await model.save()

        #expect(await fake.locationTrackingWrites == [RuleWrite(value: changed, version: 4)])
        #expect(model.notice == .saved)
        #expect(!model.canSave)
    }

    @Test func aSecondSaveUsesTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        let first = LocationTracking(isEnabled: true, intervalMinutes: 30, zoneIntervalMinutes: 3, moveMetres: 100)
        let second = LocationTracking(isEnabled: true, intervalMinutes: 5, zoneIntervalMinutes: 3, moveMetres: 100)
        script.locationTracking = [.success(snapshot(version: 5, tracking: first)), .success(snapshot(version: 6, tracking: second))]
        let (model, fake) = setup(script)
        await model.load()
        model.setInterval(30)
        await model.save()

        model.setInterval(5)
        await model.save()

        #expect(await fake.locationTrackingWrites.map(\.version) == [4, 5])
    }

    // Review Focus 4.
    @Test func aConflictReloadsAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 7, tracking: elsewhere))]
        script.locationTracking = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, fake) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(model.tracking == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.count == 1)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 2)
    }

    @Test func aFrozenChildSaysWhy() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, _) = setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.message == .childNotActive)
        #expect(model.canSave)
    }

    @Test func aRuleThatCannotBeReadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4, tracking: every15))]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.loadFailure == .noConnection)
        #expect(model.tracking == nil)

        await model.load()
        #expect(model.loadFailure == nil)
        #expect(model.tracking == every15)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'LocationTrackingModel' in scope`.

- [ ] **Step 3: `LocationTrackingModel`**

`NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirNetworking

/// P12b: how often the child's phone reports unasked. Written with the
/// version it was read at; a version that moved meanwhile is re-read and the
/// parent is told — the change is never resent on their behalf.
@MainActor
@Observable
final class LocationTrackingModel {
    enum Notice: Equatable {
        case saved
        /// Changed elsewhere since it was read: the latest is shown.
        case conflict
    }

    let childId: UUID
    let childName: String?
    private(set) var tracking: LocationTracking?
    private(set) var isLoading = false
    private(set) var loadFailure: UserMessage?
    private(set) var message: UserMessage?
    private(set) var notice: Notice?
    private(set) var isSaving = false

    private let family: FamilyStore
    @ObservationIgnored private var saved: LocationTracking?
    @ObservationIgnored private var version: Int64?

    init(childId: UUID, childName: String?, family: FamilyStore) {
        self.childId = childId
        self.childName = childName
        self.family = family
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let snapshot = try await family.service.rules(of: childId)
            accept(snapshot)
            loadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            loadFailure = UserMessage(error)
        }
    }

    func setEnabled(_ enabled: Bool) {
        edit { $0.isEnabled = enabled }
    }

    func setInterval(_ minutes: Int) {
        edit { $0.intervalMinutes = minutes }
    }

    func setZoneInterval(_ minutes: Int) {
        edit { $0.zoneIntervalMinutes = minutes }
    }

    func setMove(_ metres: Int) {
        edit { $0.moveMetres = metres }
    }

    var canSave: Bool {
        guard !isSaving, let tracking, version != nil else { return false }
        return tracking != saved
    }

    func save() async {
        guard canSave, let tracking, let version else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        do {
            let snapshot = try await family.service.setLocationTracking(tracking, of: childId, version: version)
            accept(snapshot)
            notice = .saved
        } catch is CancellationError {
            return
        } catch {
            let failure = UserMessage(error)
            if failure == .conflict, let fresh = try? await family.service.rules(of: childId) {
                accept(fresh)
                notice = .conflict
            } else {
                message = failure
            }
        }
    }

    private func edit(_ change: (inout LocationTracking) -> Void) {
        guard var copy = tracking else { return }
        change(&copy)
        tracking = copy
        notice = nil
        message = nil
    }

    private func accept(_ snapshot: RuleSnapshot) {
        version = snapshot.version
        saved = snapshot.locationTracking
        tracking = snapshot.locationTracking
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P12b as Android `LocationTrackingContent`: on/off and three segmented
/// choices; the numbers stay while it is off.
struct LocationTrackingView: View {
    @State private var model: LocationTrackingModel
    @Environment(\.l10n) private var l10n

    init(model: LocationTrackingModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let tracking = model.tracking {
                    form(tracking)
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
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenLocationTrackingTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    @ViewBuilder
    private func form(_ tracking: LocationTracking) -> some View {
        NozirCard {
            Toggle(l10n.locationTrackingToggleTitle, isOn: Binding(get: { tracking.isEnabled }, set: { model.setEnabled($0) }))
                .tint(NozirColor.primary)
            Text(tracking.isEnabled ? l10n.locationTrackingOn : l10n.locationTrackingOff)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        if tracking.isEnabled {
            choice(
                title: l10n.locationTrackingIntervalTitle,
                body: l10n.locationTrackingIntervalBody,
                values: LocationTracking.intervalChoices,
                selection: Binding(get: { tracking.intervalMinutes }, set: { model.setInterval($0) }),
                label: l10n.locationTrackingMinutes
            )
            choice(
                title: l10n.locationTrackingZoneIntervalTitle,
                body: l10n.locationTrackingZoneIntervalBody,
                values: LocationTracking.zoneIntervalChoices,
                selection: Binding(get: { tracking.zoneIntervalMinutes }, set: { model.setZoneInterval($0) }),
                label: l10n.locationTrackingMinutes
            )
            choice(
                title: l10n.locationTrackingMoveTitle,
                body: l10n.locationTrackingMoveBody,
                values: LocationTracking.moveChoices,
                selection: Binding(get: { tracking.moveMetres }, set: { model.setMove($0) }),
                label: l10n.locationTrackingMetres
            )
        }
        switch model.notice {
        case .saved?:
            Text(model.childName.map(l10n.rulesSavedNamed) ?? l10n.rulesSaved)
                .nozirText(.bodySmall, color: NozirColor.goodContent)
        case .conflict?:
            NozirInlineMessage(l10n.rulesConflictNotice)
        case nil:
            EmptyView()
        }
        if let message = model.message {
            NozirInlineMessage(message.text(l10n))
        }
        NozirButton(l10n.safeZoneSave, size: .callToAction, isLoading: model.isSaving) {
            Task { await model.save() }
        }
        .disabled(!model.canSave)
    }

    private func choice(
        title: String,
        body: String,
        values: [Int],
        selection: Binding<Int>,
        label: @escaping (Int) -> String
    ) -> some View {
        NozirCard {
            Text(title).nozirText(.titleSmall)
            Text(body).nozirText(.bodySmall, color: NozirColor.textSecondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { value in
                    Text(label(value)).tag(value)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
```

(Saqlash tugmasi matni sifatida `safe_zone_save` — "Saqlash" — ishlatiladi; Android P12b ham umumiy "Saqlash" ni ko'rsatadi, alohida kalit yo'q.)

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift NozirKit/Sources/NozirAppFeature/Screens/LocationTrackingView.swift NozirKit/Tests/NozirAppFeatureTests/LocationTrackingModelTests.swift
```

Xabar: `p12b: how often the phone reports, saved against the version read`

---
### Task 7: Joylashuv tabi va ulash — to'rt tab, P13 → P14 / P12b

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocationApi`, `LocationService`), Task 4 (`LocationModel`, `LocationView`, `FakeLocation`), Task 5 (`SafeZoneModel`, `SafeZoneView`), Task 6 (`LocationTrackingModel`, `LocationTrackingView`), 2b (`SignedInModel`, `SignedInView`).
- Produces:
  - `SignedInModel.Tab`: `home, statistics, location, profile`; `SignedInModel.init(family:insights:location:language:appearance:localeSync:emergencyNumber:signOut:)`; `locationTab: LocationModel`; `makeSafeZoneModel(childId:zoneId:) -> SafeZoneModel`; `makeLocationTrackingModel(childId:) -> LocationTrackingModel`; `locationService: any LocationService` (internal, Task 8 ishlatadi).
  - `SignedInView.LocationStep: Hashable { zone(UUID, UUID?), tracking(UUID) }`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`:
- importlarga `import NozirLocation`;
- `setup` dagi `SignedInModel(` chaqiruviga `insights: FakeInsights(),` dan keyin `location: FakeLocation(),` qo'shing;
- suite oxiriga:

```swift
    @Test func theLocationTabSharesTheFamily() {
        let (model, _) = setup(FakeFamily.Script())

        #expect(model.locationTab.family === model.family)
    }

    @Test func zoneAndTrackingScreensAreForTheChildAsked() {
        let (model, _) = setup(FakeFamily.Script())
        let child = makeChild("Ali")
        let zoneId = UUID()

        let zone = model.makeSafeZoneModel(childId: child.id, zoneId: zoneId)
        #expect(zone.childId == child.id)
        #expect(zone.zoneId == zoneId)
        #expect(zone.isEditing)
        #expect(!model.makeSafeZoneModel(childId: child.id, zoneId: nil).isEditing)
        #expect(model.makeLocationTrackingModel(childId: child.id).childId == child.id)
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `extra argument 'location' in call`, `value of type 'SignedInModel' has no member 'locationTab'`.

- [ ] **Step 3: `SignedInModel`**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:
1. Importlarga `import NozirLocation`.
2. `Tab`:

```swift
    public enum Tab: Hashable, Sendable {
        case home, statistics, location, profile
    }
```

3. `let statistics: StatisticsModel` dan keyin:

```swift
    /// One for the session, like Statistics: the tab keeps its chosen child.
    let locationTab: LocationModel
```

4. `private let insights: any InsightsService` dan keyin: `let locationService: any LocationService`
5. `init` — `insights:` parametridan keyin `location: any LocationService,` qo'shing; tanasida `self.insights = insights` dan keyin `locationService = location`, va oxirida `statistics = …` dan keyin:

```swift
        locationTab = LocationModel(family: family, location: location)
```

6. `makeAppUsageModel` dan keyin:

```swift
    func makeSafeZoneModel(childId: UUID, zoneId: UUID?) -> SafeZoneModel {
        SafeZoneModel(childId: childId, zoneId: zoneId, location: locationService)
    }

    func makeLocationTrackingModel(childId: UUID) -> LocationTrackingModel {
        LocationTrackingModel(childId: childId, childName: family.child(childId)?.displayName, family: family)
    }
```

- [ ] **Step 4: `AppEnvironment`**

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — importlarga `import NozirLocation`; `makeSignedInModel()` dagi `insights: InsightsApi(client: authorised),` dan keyin:

```swift
            location: LocationApi(client: authorised),
```

- [ ] **Step 5: `SignedInView` — Joylashuv tabi**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:
1. Importlarga `import NozirLocation`; tepadagi izohni `/// The signed-in app: Home, Statistics, Location and Profile.` ga almashtiring.
2. `StatisticsStep` dan keyin:

```swift
    enum LocationStep: Hashable {
        /// A child's zone to edit, or nil for a new one.
        case zone(UUID, UUID?)
        case tracking(UUID)
    }
```

3. `@State private var statisticsPath` dan keyin: `@State private var locationPath: [LocationStep] = []`
4. Statistika tabidan (`.tag(SignedInModel.Tab.statistics)`) keyin, Profil tabidan oldin:

```swift
            NavigationStack(path: $locationPath) {
                LocationView(
                    model: model.locationTab,
                    onOpenZone: { childId, zone in locationPath.append(.zone(childId, zone?.id)) },
                    onOpenTracking: { locationPath.append(.tracking($0)) },
                    onAddChild: { model.presentAddChild() }
                )
                .navigationDestination(for: LocationStep.self) { step in
                    switch step {
                    case .zone(let childId, let zoneId):
                        SafeZoneView(
                            model: model.makeSafeZoneModel(childId: childId, zoneId: zoneId),
                            onFinished: { locationPath.removeAll() }
                        )
                    case .tracking(let childId):
                        LocationTrackingView(model: model.makeLocationTrackingModel(childId: childId))
                    }
                }
            }
            .tabItem { Label(l10n.tabLocation, systemImage: "location") }
            .tag(SignedInModel.Tab.location)
```

5. `clearPaths()` ga `locationPath.removeAll()` qo'shing.

(P13 P14/P12b dan qaytganda `LocationView` dagi `.task(id: model.childId)` qayta ishga tushadi va joylashuv, hududlar, qoida qayta o'qiladi.)

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`, so'ng watcher `app`.
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `grep -n "NSLocation" Nozir.xcodeproj/project.pbxproj` — hech narsa (Info.plist build sozlamalaridan generatsiya qilinadi; joylashuv ruxsati kerak emas).

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
```

Xabar: `app: a location tab, its zones and its rule`

---
### Task 8: P15 SOS ekrani — `SosDetailModel`, ekran, Home'dan push

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Location/SosDetailModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SosDetailView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift` (`SosSheet` o'chiriladi)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SosDetailModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocationService.sosAlert`, `acknowledgeSos`, `SosAlertDetail`, `SosStatus`, `ActiveSos: Hashable`), Task 3 (`LocationTexts.sos*`), Task 4 (`FakeLocation`, `CLLocationCoordinate2D(_:)`, `MapCamera`), Task 7 (`SignedInModel.locationService`), 2b (`SosAlert`, `SosBanner`, `HomeView`, `ElapsedTime`).
- Produces:
  - `SosAlert.init(_ sos: ActiveSos, child: Child?, emergencyNumber: String?, phone: String? = nil)` — `phone` bo'lsa u, aks holda oila ro'yxatidagi raqam.
  - `@MainActor @Observable final class SosDetailModel { enum Phase: Equatable { loading, ready, missing, failed(UserMessage) }; seed: ActiveSos; detail: SosAlertDetail?; phase; isOffline; isAcknowledging; acknowledgeFailed; init(seed:child:emergencyNumber:location:); load() async; acknowledge() async; childName: String?; triggeredAt: Date; call: SosAlert; canAcknowledge: Bool; directionsURL: URL? }`
  - `struct SosDetailView: View { init(model: SosDetailModel) }`
  - `HomeView.init(model:reloadToken:emergencyNumber:onOpenSummary:onOpenSos:onAddChild:)` — `onOpenSos: (ActiveSos) -> Void`; banner endi P15 ni ochadi.
  - `SignedInModel.makeSosDetailModel(seed: ActiveSos, emergencyNumber: String) -> SosDetailModel`; `SignedInView.HomeStep.sos(ActiveSos)`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift` — suite ichiga:

```swift
    @Test func theAlarmsOwnNumberWinsOverTheFamilyList() {
        let child = makeChild("Ali", id: childId, phone: "+998901111111")

        let alert = SosAlert(sos(name: "Ali"), child: child, emergencyNumber: nil, phone: "+998902222222")

        #expect(alert.childCallURL == URL(string: "tel:+998902222222"))
        #expect(SosAlert(sos(name: "Ali"), child: child, emergencyNumber: nil, phone: " ").childCallURL == URL(string: "tel:+998901111111"))
    }
```

`NozirKit/Tests/NozirAppFeatureTests/SosDetailModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation
import NozirNetworking
@testable import NozirAppFeature

private let sosId = UUID()
private let childId = UUID()
private let triggered = Date(timeIntervalSince1970: 1_791_300_000)

private let seed = ActiveSos(sosId: sosId, childId: childId, childName: "Ali", triggeredAt: triggered)

private func detail(
    status: SosStatus = .active,
    name: String? = "Ali",
    phone: String? = "+998901234567",
    hasLocation: Bool = true,
    acknowledgedAt: Date? = nil
) -> SosAlertDetail {
    SosAlertDetail(
        id: sosId,
        childId: childId,
        childName: name,
        childPhoneE164: phone,
        triggeredAt: triggered,
        status: status,
        batteryPercent: 31,
        deviceOnline: true,
        latitude: hasLocation ? 41.3111 : nil,
        longitude: hasLocation ? 69.2797 : nil,
        accuracyMeters: 12,
        locationFixAt: hasLocation ? triggered : nil,
        acknowledgedAt: acknowledgedAt
    )
}

@MainActor
private func setup(_ script: FakeLocation.Script, child: Child? = nil) -> (SosDetailModel, FakeLocation) {
    let fake = FakeLocation(script)
    return (SosDetailModel(seed: seed, child: child, emergencyNumber: "112", location: fake), fake)
}

@MainActor
@Suite struct SosDetailModelTests {
    private let l10n = L10n(.uz)

    @Test func theBannersWordsShowBeforeTheDetailArrives() {
        let (model, _) = setup(FakeLocation.Script())

        #expect(model.phase == .loading)
        #expect(model.childName == "Ali")
        #expect(model.triggeredAt == triggered)
        #expect(!model.canAcknowledge)
    }

    @Test func theDetailFillsTheScreen() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.detail == detail())
        #expect(model.canAcknowledge)
        #expect(model.call.childCallURL == URL(string: "tel:+998901234567"))
        #expect(model.call.emergencyCallURL == URL(string: "tel:112"))
        #expect(model.directionsURL == URL(string: "https://maps.apple.com/?daddr=41.3111,69.2797"))
    }

    @Test func anAlarmThatIsGoneIsNotAnError() async {
        var script = FakeLocation.Script()
        script.sos = [.failure(notFound)]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.phase == .missing)
    }

    @Test func aFailureWithNothingShownCanBeRetried() async {
        var script = FakeLocation.Script()
        script.sos = [.failure(.unexpectedStatus(500)), .success(detail())]
        let (model, _) = setup(script)

        await model.load()
        #expect(model.phase == .failed(.serverProblem))

        await model.load()
        #expect(model.phase == .ready)
    }

    @Test func goingOfflineKeepsTheAlarmOnScreen() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail()), .failure(offline)]
        let (model, _) = setup(script)
        await model.load()

        await model.load()

        #expect(model.phase == .ready)
        #expect(model.detail == detail())
        #expect(model.isOffline)
    }

    @Test func acknowledgingSettlesTheAlarm() async {
        var script = FakeLocation.Script()
        let seenAt = triggered.addingTimeInterval(120)
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged, acknowledgedAt: seenAt))]
        let (model, fake) = setup(script)
        await model.load()

        await model.acknowledge()

        #expect(model.detail?.status == .acknowledged)
        #expect(!model.canAcknowledge)
        #expect(await fake.calls == ["sos", "acknowledge"])
    }

    // Review Focus 5.
    @Test func twoTapsAcknowledgeOnce() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.success(detail(status: .acknowledged))]
        let (model, fake) = setup(script)
        await model.load()

        async let first: Void = model.acknowledge()
        async let second: Void = model.acknowledge()
        _ = await (first, second)

        #expect(await fake.calls.filter { $0 == "acknowledge" }.count == 1)
    }

    // Review Focus 5.
    @Test func aFailedAcknowledgeCanBeRetried() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail())]
        script.acknowledge = [.failure(offline), .success(detail(status: .acknowledged))]
        let (model, _) = setup(script)
        await model.load()

        await model.acknowledge()
        #expect(model.acknowledgeFailed)
        #expect(model.canAcknowledge)

        await model.acknowledge()
        #expect(!model.acknowledgeFailed)
        #expect(model.detail?.status == .acknowledged)
    }

    @Test(arguments: [SosStatus.acknowledged, .cancelledByChild, .resolved, .unknown])
    func aSettledOrUnknownAlarmOffersNoAcknowledge(status: SosStatus) async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(status: status))]
        let (model, fake) = setup(script)
        await model.load()

        await model.acknowledge()

        #expect(!model.canAcknowledge)
        #expect(await fake.calls.contains("acknowledge") == false)
    }

    @Test func withoutTheAlarmsNumberTheFamilyListIsUsed() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(phone: nil))]
        let (model, _) = setup(script, child: makeChild("Ali", id: childId, phone: "+998907654321"))

        await model.load()

        #expect(model.call.childCallURL == URL(string: "tel:+998907654321"))
    }

    @Test func noNumberAnywhereCannotBeCalled() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(phone: nil))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.call.childCallURL == nil)
        #expect(model.call.callChildTitle(l10n) == l10n.sosActionCallChild("Ali"))
    }

    @Test func noPositionNoDirections() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(hasLocation: false))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.directionsURL == nil)
    }

    @Test func theAlarmsNameWinsOverTheBanners() async {
        var script = FakeLocation.Script()
        script.sos = [.success(detail(name: "Alijon"))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.childName == "Alijon")
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `extra argument 'phone' in call`, `cannot find 'SosDetailModel' in scope`.

- [ ] **Step 3: `SosAlert` raqami**

`NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift` — `init` ni almashtiring va hujjat izohini yangilang:

```swift
/// What the SOS banner and P15 say and dial. The name is the alarm's own,
/// else the family list's (a removed child has neither); the child's number is
/// the alarm's own when P15 has it, else the family list's.
struct SosAlert: Equatable {
    let sos: ActiveSos
    let childName: String?
    let childPhone: String?
    let emergencyNumber: String?

    init(_ sos: ActiveSos, child: Child?, emergencyNumber: String?, phone: String? = nil) {
        self.sos = sos
        childName = Self.present(sos.childName) ?? Self.present(child?.displayName)
        childPhone = Self.present(phone) ?? Self.present(child?.phoneE164)
        self.emergencyNumber = Self.present(emergencyNumber)
    }
```

(qolgan a'zolar o'zgarmaydi).

- [ ] **Step 4: `SosDetailModel`**

`NozirKit/Sources/NozirAppFeature/Location/SosDetailModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirInsights
import NozirLocation
import NozirNetworking

/// P15. Paints at once from the banner's copy (who, when), then fills in from
/// the server. No plan, rate or preference check anywhere on this screen.
/// "I have seen it" settles the alarm once: a second tap while the first is in
/// flight does nothing.
@MainActor
@Observable
final class SosDetailModel {
    enum Phase: Equatable {
        case loading
        case ready
        /// 404: cancelled or expired. An answer, not a fault.
        case missing
        case failed(UserMessage)
    }

    let seed: ActiveSos
    private(set) var detail: SosAlertDetail?
    private(set) var phase: Phase = .loading
    private(set) var isOffline = false
    private(set) var isAcknowledging = false
    private(set) var acknowledgeFailed = false

    private let child: Child?
    private let emergencyNumber: String
    private let location: any LocationService

    /// `emergencyNumber` is the config's, or the compiled-in "112": the dial
    /// button must work with no network and no session.
    init(seed: ActiveSos, child: Child?, emergencyNumber: String, location: any LocationService) {
        self.seed = seed
        self.child = child
        self.emergencyNumber = emergencyNumber
        self.location = location
    }

    func load() async {
        do {
            detail = try await location.sosAlert(seed.sosId)
            phase = .ready
            isOffline = false
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            phase = detail == nil ? .missing : phase
        } catch {
            if detail == nil {
                phase = .failed(UserMessage(error))
            } else {
                isOffline = true
            }
        }
    }

    func acknowledge() async {
        guard canAcknowledge else { return }
        isAcknowledging = true
        acknowledgeFailed = false
        defer { isAcknowledging = false }
        do {
            detail = try await location.acknowledgeSos(seed.sosId)
        } catch {
            acknowledgeFailed = true
        }
    }

    var childName: String? {
        LocationTexts.present(detail?.childName) ?? LocationTexts.present(seed.childName) ?? LocationTexts.present(child?.displayName)
    }

    var triggeredAt: Date {
        detail?.triggeredAt ?? seed.triggeredAt
    }

    /// Who and what to dial, through the banner's own rules.
    var call: SosAlert {
        let named = ActiveSos(sosId: seed.sosId, childId: seed.childId, childName: childName, triggeredAt: triggeredAt)
        return SosAlert(named, child: child, emergencyNumber: emergencyNumber, phone: detail?.childPhoneE164)
    }

    var canAcknowledge: Bool {
        detail?.status == .active && !isAcknowledging
    }

    /// Apple Maps with the alarm's position as the destination.
    var directionsURL: URL? {
        guard let coordinate = detail?.coordinate else { return nil }
        return URL(string: "https://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")
    }
}
```

- [ ] **Step 5: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/SosDetailView.swift`:

```swift
import MapKit
import SwiftUI
import NozirDesignSystem
import NozirL10n
import NozirLocation

/// P15 as Android `SosAlertContent`: who and when, battery and connection,
/// where (a still map), the calls, and "I have seen it".
struct SosDetailView: View {
    @State private var model: SosDetailModel
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @State private var actionUnavailable = false

    init(model: SosDetailModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: NozirSpacing.large) {
                    header(now: context.date)
                    switch model.phase {
                    case .missing:
                        NozirEmptyState(title: l10n.sosNotFoundTitle, message: l10n.sosNotFoundBody)
                    case .failed(let message):
                        NozirErrorState(
                            title: l10n.stateErrorTitle,
                            message: message.text(l10n),
                            retryTitle: l10n.stateActionRetry
                        ) {
                            Task { await model.load() }
                        }
                    case .loading, .ready:
                        if model.isOffline {
                            NozirOfflineNotice(l10n.stateOfflineNotice)
                        }
                        if let detail = model.detail {
                            facts(detail)
                            locationCard(detail, now: context.date)
                        }
                    }
                    actions
                    acknowledgeRow
                }
                .padding(NozirSpacing.medium)
            }
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenSosAlertTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    private func header(now: Date) -> some View {
        NozirCard(tone: .critical) {
            Text(LocationTexts.sosTitle(childName: model.childName, l10n)).nozirText(.titleLarge, color: NozirColor.criticalContent)
            Text(LocationTexts.sosMeta(triggeredAt: model.triggeredAt, now: now, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func facts(_ detail: SosAlertDetail) -> some View {
        HStack(spacing: NozirSpacing.small) {
            fact(l10n.sosFactBattery, LocationTexts.sosBattery(detail.batteryPercent, l10n))
            fact(l10n.sosFactConnection, LocationTexts.sosConnection(online: detail.deviceOnline, l10n))
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        NozirCard {
            Text(label).nozirText(.label, color: NozirColor.textSecondary)
            Text(value).nozirText(.titleSmall)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func locationCard(_ detail: SosAlertDetail, now: Date) -> some View {
        NozirCard {
            Text(l10n.sosLocationLabel).nozirText(.label, color: NozirColor.textSecondary)
            if let coordinate = detail.coordinate {
                Map(initialPosition: MapCamera.region(coordinate, metres: 600), interactionModes: []) {
                    if let accuracy = detail.accuracyMeters {
                        MapCircle(center: CLLocationCoordinate2D(coordinate), radius: accuracy)
                            .foregroundStyle(NozirColor.criticalContent.opacity(0.14))
                            .stroke(NozirColor.criticalContent.opacity(0.55), lineWidth: 3)
                    }
                    Marker("", coordinate: CLLocationCoordinate2D(coordinate))
                        .tint(NozirColor.criticalContent)
                }
                .frame(height: 190)
                .clipShape(RoundedRectangle(cornerRadius: NozirRadius.cardCompact))
                .accessibilityLabel(l10n.contentDescriptionSosLocation)
                if let place = LocationTexts.sosPlace(detail, l10n) {
                    Text(place).nozirText(.body)
                }
                if let accuracy = LocationTexts.sosAccuracy(detail.accuracyMeters, l10n) {
                    Text(accuracy).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                if let age = LocationTexts.sosFixAge(detail, now: now, l10n) {
                    Text(age.text).nozirText(.bodySmall, color: age.isStale ? NozirColor.attentionContent : NozirColor.textSecondary)
                    if age.isStale {
                        Text(l10n.sosLocationStaleNote).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                }
            } else {
                Text(l10n.sosLocationUnknownTitle).nozirText(.titleSmall)
                Text(l10n.sosLocationUnknownBody).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        let call = model.call
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            NozirButton(call.callChildTitle(l10n), size: .callToAction) { open(call.childCallURL) }
                .disabled(call.childCallURL == nil)
            if call.childCallURL == nil {
                Text(l10n.sosCallChildUnavailable).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
        if let directions = model.directionsURL {
            NozirButton(l10n.sosActionDirections, variant: .secondary) { open(directions) }
        }
        if let emergencyTitle = call.emergencyTitle(l10n) {
            NozirButton(emergencyTitle, variant: .criticalOutline, size: .callToAction) { open(call.emergencyCallURL) }
        }
        if actionUnavailable {
            NozirInlineMessage(l10n.sosActionUnavailable)
        }
    }

    @ViewBuilder
    private var acknowledgeRow: some View {
        if let detail = model.detail {
            if let settled = LocationTexts.sosSettled(detail, l10n) {
                Text(settled).nozirText(.body, color: NozirColor.goodContent)
            } else if detail.status == .active {
                NozirButton(l10n.sosAcknowledgeAction, variant: .secondary, isLoading: model.isAcknowledging) {
                    Task { await model.acknowledge() }
                }
                .disabled(!model.canAcknowledge)
                if model.acknowledgeFailed {
                    NozirInlineMessage(l10n.sosAcknowledgeFailed)
                }
            }
        }
    }

    private func open(_ url: URL?) {
        guard let url else {
            actionUnavailable = true
            return
        }
        actionUnavailable = false
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in actionUnavailable = true }
            }
        }
    }
}
```

- [ ] **Step 6: Home banneri P15 ni ochadi; eski oyna olib tashlanadi**

`NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift` — `struct SosSheet: View { … }` blokini (izohi bilan) butunlay o'chiring; fayl tepasidagi `SosBanner` izohi o'zgarmaydi.

`NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`:
1. `@State private var showsSos = false` qatorini va `@Environment(\.locale) private var locale` qatorini (boshqa joyda ishlatilmasa) o'chiring.
2. `private let onOpenSummary: (UUID, String) -> Void` dan keyin `private let onOpenSos: (ActiveSos) -> Void` qo'shing.
3. `init` — `onOpenSummary:` parametridan keyin `onOpenSos: @escaping (ActiveSos) -> Void,`; tanasiga `self.onOpenSos = onOpenSos`.
4. Bannerni: `SosBanner(alert: alert) { onOpenSos(alert.sos) }`.
5. `// The alarm ended while its sheet was open…` izohi, `.onChange(of: model.home?.activeSos == nil) { … }` va `.sheet(isPresented: $showsSos) { … }` modifikatorlarini o'chiring.
6. Tepadagi izohda `P15–P18 links are not in this slice.` ni `The banner opens P15; P16–P18 are not in this slice.` ga almashtiring.

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — `makeLocationTrackingModel` dan keyin:

```swift
    func makeSosDetailModel(seed: ActiveSos, emergencyNumber: String) -> SosDetailModel {
        SosDetailModel(seed: seed, child: family.child(seed.childId), emergencyNumber: emergencyNumber, location: locationService)
    }
```

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:
1. Importlarga `import NozirInsights`.
2. `HomeStep` ga `case sos(ActiveSos)`.
3. `HomeView(` chaqiruvida `onOpenSummary:` dan keyin: `onOpenSos: { homePath.append(.sos($0)) },`
4. `homeDestination` ga:

```swift
        case .sos(let seed):
            SosDetailView(model: model.makeSosDetailModel(
                seed: seed,
                emergencyNumber: model.currentEmergencyNumber ?? l10n.sosEmergencyNumber
            ))
```

(P15 dan qaytganda `HomeView` qayta paydo bo'ladi va `.task(id: reloadToken)` home'ni qayta so'raydi — hal qilingan SOS banneri yo'qoladi.)

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`, so'ng watcher `app`.
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `grep -rn "SosSheet\|showsSos" NozirKit/Sources` — hech narsa.

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift NozirKit/Sources/NozirAppFeature/Location/SosDetailModel.swift NozirKit/Sources/NozirAppFeature/Screens/SosDetailView.swift NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift NozirKit/Tests/NozirAppFeatureTests/SosDetailModelTests.swift
```

Xabar: `p15: the whole alarm — where, whom to call, and "I have seen it"`

---
### Task 9: Oxirgi tekshiruv — butun to'plam, CI va E2E

**Files:** (kod o'zgarmaydi; topilgan xatolar alohida TDD sikli bilan tuzatiladi)

- [ ] **Step 1: Butun to'plam**

Run: `python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check && ./scripts/test.sh`, keyin watcher `all` va `app`.
Expected: Python OK, `up to date`, `** TEST SUCCEEDED **` (yangi `NozirLocationTests` ham ichida), `** BUILD SUCCEEDED **`.

- [ ] **Step 2: E2E (foydalanuvchi; simulyator + haqiqiy bola telefoni + haqiqiy backend)**

Har bir bandga "ha" yoki kuzatilgan holat yoziladi:

1. Tablar: Home, Statistika, Joylashuv, Profil. Joylashuv tabida 1 bolada tanlagich yo'q, 2+ bolada bor; bola almashtirilganda xarita va karta shu bolaga o'tadi.
2. Joylashuv yuborgan bola: xaritada pin, karta — "{Ism} · {hudud yoki manzil}", "N daqiqa oldin yangilandi · soat HH:mm da olingan", "Aniqlik ±N m", batareya.
3. Hech qachon yubormagan bola: "Hali birorta joylashuv kelmadi"; xarita Toshkentda (yoki hududda).
4. "Hozir qayerdaligini soʻrash": "javob kutilmoqda…" chiqadi; bola telefoni javob bersa ~30 s ichida pin yangilanadi; telefon joylashuvi o'chiq bo'lsa "joylashuv xizmati oʻchirilgan" matni chiqadi; javob bo'lmasa jim to'xtaydi.
5. Bola telefoni uzoq vaqt jim bo'lsa: sariq karta va "Bu joylashuv eskirgan" izohi, pin xira.
6. "+ Zona" → xaritada markaz bolaning oxirgi joyida va "Markaz … boʻyicha qoʻyildi" izohi; nom bo'sh — "Saqlash" o'chiq; nom kiritiladi, radius surilganda doira o'zgaradi → "Saqlash" → P13 da yangi doira va chip.
7. Chip bosilsa tahrirlash: qiymatlar saqlanganicha; o'zgartirmasdan "Saqlash" o'chiq; nomni o'zgartirib saqlash → chip yangilanadi. "Zonani oʻchirish" → tasdiq → "Bekor qilish" hech narsa qilmaydi → "Ha, oʻchirilsin" → P13 da doira yo'q.
8. Joylashuvni kuzatish qatori → P12b: o'chirish-yoqish, oraliqlar; "Saqlash" → "Saqlandi…" matni; P13 qatori yangi qiymatni ko'rsatadi. (Ixtiyoriy: Android ota-ona ilovasida shu qoidani o'zgartirib, iOS'da eski versiya bilan saqlash → "qoidalar oʻzgargan" xabari va oxirgi holat.)
9. Bola telefonidan SOS → Home banneri → P15: ism, vaqt, batareya, aloqa, kichik xarita va aniqlik doirasi, joy yoki koordinatalar, fix yoshi; "Koʻrdim" → "Koʻrganingiz HH:mm da bildirildi"; orqaga → Home'da banner yo'q. Bola SMS eskalatsiyasi to'xtaganini tasdiqlash (ixtiyoriy).
10. P15 tugmalari (haqiqiy iPhone'da): bolaga qo'ng'iroq (raqam bo'lsa), "Yoʻnalishni ochish" Apple Maps'ni ochadi, "112 ga qoʻngʻiroq". Simulyatorda `tel:` → "Bu amalni bajaradigan ilova topilmadi."
11. Oflayn: Joylashuv tabi oldin ochilgan bo'lsa pin qoladi va "Oflayn" belgisi; ochilmagan bo'lsa xato va "Qayta urinish".
12. Uch til va ikki tema: P13, P14, P12b, P15 matnlari va xarita ranglari to'g'ri; skrinshotlar (Cmd+S).

- [ ] **Step 3: Natijani yozish**

Ledger'ga (`.superpowers/sdd/<plan>/progress.md`) E2E natijalari va kechiktirilgan kichik masalalar yoziladi. Push foydalanuvchida; keyin `superpowers:finishing-a-development-branch`.
