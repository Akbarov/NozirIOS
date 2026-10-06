# Nozir iOS — 2c-1: Mavjud bola qoidalarini o'zgartirish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ota-ona ulangan bolaning qoidalarini iOS'da o'zgartira oladi — P09 hub (kunlik limit + ishonch zinapoyasi + "Boshqa qoidalar"), P10 uyqu vaqti, P12 bonus vaqt va hub'dan ochiladigan P12b — Android `feature/rules` bilan bir xil xatti-harakat.

**Architecture:** `NozirFamily` ga ishonch zinapoyasi va bonus konfiguratsiyasi qo'shiladi (`setTrustLadder`, `bonus(of:)`, `setBonus`). `NozirAppFeature/Rules/` da har bir hub uchun bitta `ChildRulesSession` (qoidalar snapshot'i, umumiy versiya, muzlatilganlik, generation token) va undan foydalanuvchi ekran modellari (`DailyLimitModel`, `BedtimeModel`, `BonusModel`, sessiyali `LocationTrackingModel`) — har biri faqat o'z qoralamasini ushlaydi va yozishda sessiya versiyasini ishlatadi. Bola almashtirish `RulesHubModel` da: boshqa bola → yangi sessiya. P03b dagi slayder, vaqt tanlagich, kun chiplari va kun xulosasi umumiy view'larga ajratiladi.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; uchinchi tomon kutubxonasi yo'q.

**Spec:** `docs/superpowers/specs/2026-10-06-nozir-ios-rules-design.md` (oldingi: poydevor, 2a, 2b, 3 — joylashuv spec'lari)

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). Uchinchi tomon kutubxonasi yo'q.
- Har bir `/v1/parent/*` chaqiruvi `ApiClient` orqali; bola id'si yo'lda kichik harflar bilan (`FamilyApi.childPath`).
- Har bir qoida `PUT` i `If-Match: "<versiya>"` bilan (`FamilyApi.entityTag`). Bola qoidalari uchun **bitta umumiy versiya**: istalgan yozuv uni oshiradi; bonus ham shu versiyani ishlatadi; `PUT rules/bonus` da `If-Match` = sessiya versiyasi (tanadagi `ruleVersion` emas).
- Slayderlar (Android `RuleMinuteRange`): kunlik limit 30–360, ishonch zinapoyasi 0–120 (0 = "O'chiq"), bonus maksimumi 0–120, uyquga tayyorgarlik 15–60; hammasi 15 qadam. Uyquga tayyorgarlik o'chiq = 0; qayta yoqilganda oldingi qiymat, birinchi marta 30.
- Server chegaralari: school/weekend 0..1440, bonus 0..480, zinapoya 0..120, wind-down 0..120, `activeDays` bo'sh emas, 1..7. Oxirgi kunni o'chirib bo'lmaydi.
- "Har kuni bir xil" saqlanmaydi: `school == weekend` dan aniqlanadi; yoqilganda dam olish kuni o'qish kuni qiymatini oladi; yoqiq paytda o'qish kuni o'zgarsa ikkalasi o'zgaradi.
- P09 saqlash: zinapoya o'zgargan bo'lsa avval `PUT trust-ladder`; muvaffaqiyatli bo'lsa va limit ham o'zgargan bo'lsa, javobdagi **yangi versiya** bilan `PUT screen-time`. Birinchisi xato bo'lsa ikkinchisi yuborilmaydi. `maxDailyBonusMinutes` o'zgartirilmasdan (sessiyadagi qiymat) qaytariladi. Har bir muvaffaqiyatli javob `session.accept` ga.
- To'qnashuv (409 `CONFLICT`) → sessiya qayta o'qiladi, `rules_conflict_notice`, qoralama tashlanadi, **avtomatik qayta yuborish yo'q**. 403 `CHILD_NOT_ACTIVE` → `data_error_child_not_active`, qoralama qoladi. Tarmoq/5xx → `UserMessage`, qoralama qoladi.
- Ikki marta tez "Saqlash" → bitta so'rov (sinxron `isSaving` qo'riqchisi). Kechikkan javob (boshqa bola, yangiroq yuklash) → tashlanadi. Tab almashtirib qaytish → saqlanmagan qoralama yo'qolmaydi.
- Muzlatilganlik `subscription()` dan; reja noma'lum (o'qilmadi) → hech kim muzlatilmaydi. Muzlatilganda "Saqlash" yo'q, "Boshqa qoidalar" qatorlari o'chiq.
- Server `message` hech qachon ko'rsatilmaydi; foydalanuvchi matni faqat `L10n`, xatolar `UserMessage`. **Yangi l10n kaliti yo'q** (`gen_l10n --check` o'zgarishsiz o'tadi).
- Kirmaydi: P11 ilova qoidalari va hub'dagi "Ilovalar" qatori (2c-2), `rules/family/{kind}`, push/APNs.
- P12b sessiyasiz (Joylashuv tabi) o'zgarishsiz; mavjud `LocationTrackingModelTests` o'zgarishsiz o'tadi. P03b xatti-harakati o'zgarishsiz; mavjud `NewChildRulesModelTests` o'zgarishsiz o'tadi.
- Testlar: Swift Testing, `FakeFamily`, `PauseGate`; gate'li test `@Test(.timeLimit(.minutes(5)))`.
- Commit: `git add -A` taqiqlangan, faqat aniq yo'llar; push foydalanuvchida; commit muhiti va izoh qatorlari avvalgidek.
- Swift kodi test ishlaguncha "yozilgan, tekshirilmagan".

## Spec'dan chetlanishlar (reja bosqichida)

| # | Spec | Reja | Sabab |
|---|---|---|---|
| R1 | `ChallengeKind`, `ChallengeDifficulty` — `unknown` bilan | `case unknown(String)` — server nomi saqlanadi; `wireName` bilan qaytariladi | `PUT rules/bonus` to'liq `BonusConfigDto` ni kutadi va Kotlin enum'i noma'lum nomni rad etadi: noma'lum vazifani o'zgartirmasdan aynan qaytarish kerak |
| R2 | `BonusConfig{ruleVersion, maxDailyBonusMinutes, challenges}` | `PUT` tanasiga `childId` (kichik harf) ham qo'shiladi | Backend `BonusConfigDto.childId` nullable emas — tanada bo'lmasa 400 |
| R3 | Vazifalar ro'yxati | Noma'lum `kind` li vazifa ro'yxatda ko'rsatilmaydi, lekin saqlashda o'zgarishsiz qaytariladi; `earnableMinutes` barcha yoqilganlarni sanaydi | Android noma'lum turni umuman tashlaydi; iOS uni buzmaydi va nomsiz qator chizmaydi |
| R4 | `SignedInModel` fabrikalari ro'yxati | `makeRulesHubModel(childId:picksChild:)` qo'shiladi; `RulesHubModel` bola tanlagichni boshqaradi | "Boshqa bola → yangi sessiya" testlanadigan joyda bo'lsin (Review Focus 3) |
| R5 | `ProfileStep.rules(UUID?)`, `HomeStep.rules(UUID)`, ichki qadamlar | Qo'shimcha `ProfileStep.childRules(UUID)` (Profil tabidagi P03 dan, tanlagichsiz) va umumiy `RuleScreen` (`bedtime`/`bonus`/`locationTracking`, sessiya bilan) | P03 Profil tabida ham ochiladi va spec bo'yicha u yerda tanlagich yo'q |
| R6 | — | Qoralama boshlangan qiymat (`editBase`) saqlanadi; saqlashda sessiyadagi qiymat undan farq qilsa (pull-to-refresh boshqa telefon o'zgarishini olib kelgan) — yuborilmaydi, `notice = .conflict` | Muvaffaqiyat mezoni: "boshqa telefonda o'zgargan qoida ustidan hech qachon yozilmaydi" — sessiya versiyasi yangilangani bilan bu kafolatlanmaydi |
| R7 | `load()` | `load()` faqat snapshot yo'q bo'lsa o'qiydi; `reload()` majburiy (to'qnashuv, pull-to-refresh). `reload()` xatosi ma'lumot bor paytda: tarmoq → `isOffline`; boshqa xato → ko'rsatilgan holat qoladi | Tab almashtirish yuklashni takrorlamasin; `state_offline_notice` faqat tarmoq uchun |
| R8 | — | `session.accept` eskiroq versiyani e'tiborsiz qoldiradi | Ikki ekran yozuvi javoblari teskari tartibda kelsa ham versiya orqaga qaytmaydi |
| R9 | Uyqu vaqti qatori: `rules_time_range` + kun xulosasi | Ikki qator: vaqt oralig'i, ostida `bedtime_days_*` xulosasi | Ajratuvchi uchun yangi kalit kerak bo'lmasin |
| R10 | Joylashuv qatori: "yoki o'chiq" | O'chiq → `location_tracking_off` | Android `OtherRulesCard` shu kalitni ishlatadi |
| R11 | P03 "Qoidalar" qatori | Matn `profile_row_rules` | Alohida kalit yo'q; yangi kalit qo'shilmaydi |
| R12 | Android: zinapoya saqlanib limit xato bo'lsa, ekran eski versiyada qoladi | iOS birinchi javobni `session.accept` qiladi; qayta urinish faqat limitni yangi versiya bilan yuboradi | Androiddagi holat qayta urinishni soxta to'qnashuvga olib keladi (Review Focus 1) |
| R13 | Ekran modellari muzlatilganlikni hub orqali biladi | Har bir model `canSave` da `session.isFrozen` ni ham tekshiradi | Himoya qatlami: qator o'chiq bo'lsa ham model saqlamaydi |
| R14 | Profil qatori "bola bo'lmasa ko'rsatilmaydi" | `ProfileModel.showsRules` | View shartini testlash uchun |

## Review Focus

1. **P09 da zinapoya saqlandi, limit saqlanmadi (tarmoq)** — zinapoya saqlangan deb ko'rsatiladi va sessiyada yangi versiya; qayta "Saqlash" faqat limitni yangi versiya bilan yuboradi, zinapoyani qayta yubormaydi, soxta to'qnashuv yo'q → Task 4 `aLimitFailureAfterTheLadderKeepsTheLadderAndRetriesOnTheNewVersion`.
2. **P09 da saqlanmagan qoralama turganda P10 saqlandi** — keyin P09 saqlash sessiyaning yangi versiyasi bilan ketadi va to'qnashuv bermaydi → Task 6 `aBedtimeSaveDoesNotMakeTheOpenLimitEditConflict`.
3. **Sessiya yuklanayotganda bola almashtirildi** — eski bolaning javobi yangi bola ekraniga tushmaydi → Task 5 `aLateAnswerForTheFormerChildNeverReachesTheNewOne`.
4. **Boshqa tabga o'tib qaytish** (`.task` qayta ishlaydi) — har bir qoidalar ekranidagi qoralama saqlanib qoladi → Task 4 `loadingAgainKeepsTheEdit`, Task 6 `loadingAgainKeepsTheEdit`, Task 7 `loadingAgainKeepsTheEdit`.
5. **"Saqlash" ikki marta tez bosildi** — aynan bitta so'rov → Task 4 `twoTapsSaveOnce`.

---

## Fayl xaritasi

**Yangi:**
- `NozirKit/Sources/NozirFamily/BonusModels.swift` — `ChallengeKind`, `ChallengeDifficulty`, `BonusChallenge`, `BonusConfig`.
- `NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift` — `RuleMinuteRange`, `RuleDays` (P03b dan ko'chiriladi).
- `NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift` — `RuleNotice`, `RuleSaveOutcome`, `ChildRulesSession`.
- `NozirKit/Sources/NozirAppFeature/Rules/DailyLimitModel.swift` — `DailyLimitValues`, `DailyLimitModel`.
- `NozirKit/Sources/NozirAppFeature/Rules/RulesHubModel.swift`, `Rules/RuleTexts.swift`.
- `NozirKit/Sources/NozirAppFeature/Rules/BedtimeModel.swift`, `Rules/BonusModel.swift`, `Rules/BonusTexts.swift`.
- `NozirKit/Sources/NozirAppFeature/Screens/{RuleControls,FrozenChildCard,RuleSaveFooter,RulesHubView,DailyLimitSection,BedtimeView,BonusView}.swift`.
- Testlar: `NozirKit/Tests/NozirAppFeatureTests/{RuleBoundsTests,ChildRulesSessionTests,DailyLimitModelTests,RulesHubModelTests,BedtimeModelTests,BonusModelTests,LocationTrackingSessionTests}.swift`.

**O'zgaradi:** `NozirFamily/{RuleModels,FamilyService,FamilyApi}.swift`; `NozirAppFeature/{SignedInModel}.swift`; `Family/{NewChildRulesModel,ProfileModel}.swift`; `Location/LocationTrackingModel.swift`; `Screens/{NewChildRulesView,ChildDetailsView,ProfileView,SignedInView}.swift`; testlar `NozirFamilyTests/RulesAndPairingApiTests.swift`, `NozirAppFeatureTests/{FakeFamily,SignedInModelTests}.swift`.

## Ishni boshlash

Branch `rules` (spec commit 7792de6) ochilgan. Swift testlari Mac'dagi watcher orqali: `bash .superpowers/run.sh <Target> 170` (`<Target>` — `NozirFamilyTests`, `NozirAppFeatureTests`, `all` yoki `app`). Natija `TIMEOUT waiting …` bo'lsa so'rov bekor bo'lmagan: so'rovni qayta yubormang, `.superpowers/test-result.log` da `### done` chiqquncha kuting va o'qing.

---
### Task 1: `NozirFamily` — ishonch zinapoyasi va bonus konfiguratsiyasi

**Files:**
- Modify: `NozirKit/Sources/NozirFamily/RuleModels.swift` (`RuleSnapshot`)
- Create: `NozirKit/Sources/NozirFamily/BonusModels.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyService.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyApi.swift`
- Modify: `NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift` (butunlay almashtiriladi)

**Interfaces:**
- Consumes: `FamilyApi.childPath(_:)`, `FamilyApi.entityTag(_:)` (private), `ApiRequest.put(_:json:ifMatch:)`, `NozirTestSupport` (`FakeTransport`, `.ok`, `.error`, `URLRequest.jsonObject`), `PauseGate` (`FakeLocation.swift`).
- Produces:
  - `RuleSnapshot.maxTrustBonusMinutes: Int` (javobda yo'q bo'lsa 0); `RuleSnapshot.init(version:screenTime:bedtime:locationTracking: = .standard, maxTrustBonusMinutes: Int = 0)`.
  - `public enum ChallengeKind: Hashable, Sendable { case math, reading, english, exercise, unknown(String); init(wireName: String); var wireName: String }`
  - `public enum ChallengeDifficulty: Hashable, Sendable { case easy, medium, hard, unknown(String); init(wireName: String); var wireName: String }`
  - `public struct BonusChallenge: Codable, Equatable, Sendable, Identifiable { let id: UUID; let kind; let difficulty; let bonusMinutes: Int; let requiresParentApproval: Bool; var enabled: Bool }` + `init(id:kind:difficulty:bonusMinutes:requiresParentApproval:enabled:)`.
  - `public struct BonusConfig: Decodable, Equatable, Sendable { let ruleVersion: Int64; var maxDailyBonusMinutes: Int; var challenges: [BonusChallenge]; var earnableMinutes: Int; var isCeilingBinding: Bool; func withChallenge(_ id: UUID, enabled: Bool) -> BonusConfig }` + `init(ruleVersion:maxDailyBonusMinutes:challenges:)`.
  - `FamilyService.setTrustLadder(_ minutes: Int, of childId: UUID, version: Int64) async throws -> RuleSnapshot`
  - `FamilyService.bonus(of childId: UUID) async throws -> BonusConfig`
  - `FamilyService.setBonus(_ config: BonusConfig, of childId: UUID, version: Int64) async throws -> BonusConfig`
  - `FakeFamily.Script`: `trustLadder`, `bonus`, `setBonus` navbatlari; `rulesGate: PauseGate?` (keyingi `rules` javobni olgach to'xtaydi), `writeGate: PauseGate?` (keyingi istalgan qoida yozuvi javobni olgach to'xtaydi). Yozuvlar: `trustLadderWrites: [RuleWrite<Int>]`, `bonusWrites: [RuleWrite<BonusConfig>]`; chaqiruv nomlari `"trustLadder"`, `"bonus"`, `"setBonus"`.
  - Test yordamchilari: `snapshot(version:limit:bedtime:tracking:trust: Int = 0)`, `mathTask`, `readingTask`, `exerciseTask`, `bonusConfig(version:ceiling:challenges:)`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift` — `rulesPath` qatoridan keyin qo'shing:

```swift
/// `BonusConfigDto` as the backend writes it: one task it knows, one it does not.
private let bonusJSON = """
    {"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","ruleVersion":9,"maxDailyBonusMinutes":60,"challenges":[\
    {"id":"1a2b3c4d-0000-4000-8000-000000000001","kind":"MATH","difficulty":"MEDIUM","bonusMinutes":15,\
    "requiresParentApproval":false,"enabled":true},\
    {"id":"1a2b3c4d-0000-4000-8000-000000000002","kind":"CHESS","difficulty":"LEGENDARY","bonusMinutes":20,\
    "requiresParentApproval":true,"enabled":false}]}
    """

private let mathId = UUID(uuidString: "1a2b3c4d-0000-4000-8000-000000000001")!
private let chessId = UUID(uuidString: "1a2b3c4d-0000-4000-8000-000000000002")!
```

va suite oxiriga (yopuvchi `}` dan oldin):

```swift
    @Test func theTrustLadderCeilingIsRead() async throws {
        let (api, _) = familyApi([.ok(snapshotJSON())])

        #expect(try await api.rules(of: aliId).maxTrustBonusMinutes == 30)
    }

    @Test func aServerWithoutTheTrustLadderReadsAsOff() async throws {
        let body = """
        {"version":3,"screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
        "bedtime":{"startTime":"22:00","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]}}
        """
        let (api, _) = familyApi([.ok(body)])

        #expect(try await api.rules(of: aliId).maxTrustBonusMinutes == 0)
    }

    @Test func aTrustLadderWriteSendsOnlyTheCeilingAgainstTheVersion() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 8))])

        let after = try await api.setTrustLadder(45, of: aliId, version: 7)

        #expect(after.version == 8)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/trust-ladder")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        let body = try #require(request.jsonObject)
        #expect(Set(body.keys) == ["maxTrustBonusMinutes"])
        #expect(body["maxTrustBonusMinutes"] as? Int == 45)
    }

    @Test func theBonusConfigIsReadAndAnUnknownTaskStillDecodes() async throws {
        let (api, transport) = familyApi([.ok(bonusJSON)])

        let config = try await api.bonus(of: aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == rulesPath + "/bonus")
        #expect(config.ruleVersion == 9)
        #expect(config.maxDailyBonusMinutes == 60)
        #expect(config.challenges.map(\.id) == [mathId, chessId])
        #expect(config.challenges[0].kind == .math)
        #expect(config.challenges[0].difficulty == .medium)
        #expect(config.challenges[1].kind == .unknown("CHESS"))
        #expect(config.challenges[1].difficulty == .unknown("LEGENDARY"))
        #expect(config.challenges[1].requiresParentApproval)
        #expect(config.earnableMinutes == 15)
        #expect(!config.isCeilingBinding)
    }

    @Test func aBonusWriteSendsTheWholeConfigAndTheVersionInTheHeader() async throws {
        let (api, transport) = familyApi([.ok(bonusJSON), .ok(bonusJSON)])
        var config = try await api.bonus(of: aliId).withChallenge(chessId, enabled: true)
        config.maxDailyBonusMinutes = 30

        let after = try await api.setBonus(config, of: aliId, version: 11)

        #expect(after.ruleVersion == 9)
        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/bonus")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"11\"")
        let body = try #require(request.jsonObject)
        #expect(Set(body.keys) == ["childId", "ruleVersion", "maxDailyBonusMinutes", "challenges"])
        #expect(body["childId"] as? String == aliId.uuidString.lowercased())
        #expect(body["ruleVersion"] as? Int == 11)
        #expect(body["maxDailyBonusMinutes"] as? Int == 30)
        let challenges = try #require(body["challenges"] as? [[String: Any]])
        #expect(challenges.count == 2)
        #expect(challenges[1]["id"] as? String == chessId.uuidString.lowercased())
        #expect(challenges[1]["kind"] as? String == "CHESS")
        #expect(challenges[1]["difficulty"] as? String == "LEGENDARY")
        #expect(challenges[1]["bonusMinutes"] as? Int == 20)
        #expect(challenges[1]["requiresParentApproval"] as? Bool == true)
        #expect(challenges[1]["enabled"] as? Bool == true)
    }

    @Test func theCeilingBindsWhenTheTasksPayMore() {
        let task = BonusChallenge(id: mathId, kind: .math, difficulty: .easy, bonusMinutes: 40, requiresParentApproval: false, enabled: true)
        let config = BonusConfig(ruleVersion: 1, maxDailyBonusMinutes: 30, challenges: [task])

        #expect(config.earnableMinutes == 40)
        #expect(config.isCeilingBinding)
        #expect(!config.withChallenge(mathId, enabled: false).isCeilingBinding)
        #expect(ChallengeKind(wireName: "EXERCISE") == .exercise)
        #expect(ChallengeDifficulty(wireName: "HARD").wireName == "HARD")
    }
```

`NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift` — faylni butunlay almashtiring:

```swift
import Foundation
import NozirFamily
import NozirNetworking

let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)

struct RuleWrite<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let version: Int64
}

/// Answers each family call from its own queue, in order, and records what was
/// asked. An empty queue answers like a phone with no connection.
actor FakeFamily: FamilyService {
    struct Script: Sendable {
        var children: [Result<[Child], ApiFailure>] = []
        var child: [Result<Child, ApiFailure>] = []
        var create: [Result<Child, ApiFailure>] = []
        var update: [Result<Child, ApiFailure>] = []
        var remove: [Result<Void, ApiFailure>] = []
        var rules: [Result<RuleSnapshot, ApiFailure>] = []
        var screenTime: [Result<RuleSnapshot, ApiFailure>] = []
        var bedtime: [Result<RuleSnapshot, ApiFailure>] = []
        var locationTracking: [Result<RuleSnapshot, ApiFailure>] = []
        var trustLadder: [Result<RuleSnapshot, ApiFailure>] = []
        var bonus: [Result<BonusConfig, ApiFailure>] = []
        var setBonus: [Result<BonusConfig, ApiFailure>] = []
        var currentCode: [Result<PairingCode?, ApiFailure>] = []
        var issueCode: [Result<PairingCode, ApiFailure>] = []
        var devices: [Result<[ChildDevice], ApiFailure>] = []
        var subscription: [Result<Subscription, ApiFailure>] = []
        var activeChild: [Result<Subscription, ApiFailure>] = []
        var me: [Result<ParentProfile, ApiFailure>] = []
        var locale: [Result<ParentProfile, ApiFailure>] = []
        /// When true the next `currentPairingCode` throws `CancellationError` once.
        var cancelNextCurrentCode = false
        /// Held once by the next `rules` call, after its answer is taken.
        var rulesGate: PauseGate?
        /// Held once by the next rule write of any kind, after its answer is taken.
        var writeGate: PauseGate?
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var created: [ChildCreate] = []
    private(set) var updates: [ChildUpdate] = []
    private(set) var screenTimeWrites: [RuleWrite<ScreenTimeLimit>] = []
    private(set) var bedtimeWrites: [RuleWrite<BedtimeSchedule>] = []
    private(set) var locationTrackingWrites: [RuleWrite<LocationTracking>] = []
    private(set) var trustLadderWrites: [RuleWrite<Int>] = []
    private(set) var bonusWrites: [RuleWrite<BonusConfig>] = []
    private(set) var locales: [String] = []
    /// The child each call was about, in call order.
    private(set) var childIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    private func next<T>(_ name: String, _ queue: WritableKeyPath<Script, [Result<T, ApiFailure>]>) throws -> T {
        calls.append(name)
        guard !script[keyPath: queue].isEmpty else { throw offline }
        return try script[keyPath: queue].removeFirst().get()
    }

    /// `next`, then the gate if one is set: the answer is fixed before the pause,
    /// so a later call gets the answer after it.
    private func held<T>(
        _ name: String,
        _ queue: WritableKeyPath<Script, [Result<T, ApiFailure>]>,
        _ gate: WritableKeyPath<Script, PauseGate?>
    ) async throws -> T {
        calls.append(name)
        let answer: Result<T, ApiFailure> = script[keyPath: queue].isEmpty ? .failure(offline) : script[keyPath: queue].removeFirst()
        if let pause = script[keyPath: gate] {
            script[keyPath: gate] = nil
            await pause.pause()
        }
        return try answer.get()
    }

    func children() async throws -> [Child] { try next("children", \.children) }
    func child(_ id: UUID) async throws -> Child {
        childIds.append(id)
        return try next("child", \.child)
    }

    func createChild(_ child: ChildCreate) async throws -> Child {
        created.append(child)
        return try next("create", \.create)
    }

    func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child {
        childIds.append(id)
        updates.append(update)
        return try next("update", \.update)
    }

    func removeChild(_ id: UUID) async throws {
        childIds.append(id)
        try next("remove", \.remove)
    }

    func rules(of childId: UUID) async throws -> RuleSnapshot {
        childIds.append(childId)
        return try await held("rules", \.rules, \.rulesGate)
    }

    func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        screenTimeWrites.append(RuleWrite(value: limit, version: version))
        return try await held("screenTime", \.screenTime, \.writeGate)
    }

    func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        bedtimeWrites.append(RuleWrite(value: bedtime, version: version))
        return try await held("bedtime", \.bedtime, \.writeGate)
    }

    func setLocationTracking(_ tracking: LocationTracking, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        locationTrackingWrites.append(RuleWrite(value: tracking, version: version))
        return try await held("locationTracking", \.locationTracking, \.writeGate)
    }

    func setTrustLadder(_ minutes: Int, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        trustLadderWrites.append(RuleWrite(value: minutes, version: version))
        return try await held("trustLadder", \.trustLadder, \.writeGate)
    }

    func bonus(of childId: UUID) async throws -> BonusConfig {
        childIds.append(childId)
        return try next("bonus", \.bonus)
    }

    func setBonus(_ config: BonusConfig, of childId: UUID, version: Int64) async throws -> BonusConfig {
        childIds.append(childId)
        bonusWrites.append(RuleWrite(value: config, version: version))
        return try await held("setBonus", \.setBonus, \.writeGate)
    }

    func currentPairingCode(for childId: UUID) async throws -> PairingCode? {
        childIds.append(childId)
        if script.cancelNextCurrentCode {
            script.cancelNextCurrentCode = false
            calls.append("currentCode")
            throw CancellationError()
        }
        return try next("currentCode", \.currentCode)
    }
    func issuePairingCode(for childId: UUID) async throws -> PairingCode {
        childIds.append(childId)
        return try next("issueCode", \.issueCode)
    }
    func devices(of childId: UUID) async throws -> [ChildDevice] {
        childIds.append(childId)
        return try next("devices", \.devices)
    }
    func subscription() async throws -> Subscription { try next("subscription", \.subscription) }
    func chooseActiveChild(_ childId: UUID) async throws -> Subscription {
        childIds.append(childId)
        return try next("activeChild", \.activeChild)
    }
    func me() async throws -> ParentProfile { try next("me", \.me) }

    func updateLocale(_ locale: String) async throws -> ParentProfile {
        locales.append(locale)
        return try next("locale", \.locale)
    }
}

func makeChild(
    _ name: String = "Ali",
    id: UUID = UUID(),
    birthYear: Int = 2015,
    phone: String? = nil,
    avatar: String? = "teal",
    state: PairingState = .notPaired
) -> Child {
    Child(id: id, displayName: name, birthYear: birthYear, ageGroup: .explorer, avatarKey: avatar, phoneE164: phone, pairingState: state)
}

let defaultLimit = ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60)
let defaultBedtime = BedtimeSchedule(
    start: ClockTime(hour: 22, minute: 0),
    end: ClockTime(hour: 7, minute: 0),
    windDownMinutes: 30,
    activeDays: [1, 2, 3, 4, 5, 6, 7]
)

func snapshot(
    version: Int64,
    limit: ScreenTimeLimit = defaultLimit,
    bedtime: BedtimeSchedule = defaultBedtime,
    tracking: LocationTracking = .standard,
    trust: Int = 0
) -> RuleSnapshot {
    RuleSnapshot(version: version, screenTime: limit, bedtime: bedtime, locationTracking: tracking, maxTrustBonusMinutes: trust)
}

let mathTask = BonusChallenge(
    id: UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000001")!,
    kind: .math, difficulty: .medium, bonusMinutes: 20, requiresParentApproval: false, enabled: true
)
let readingTask = BonusChallenge(
    id: UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000002")!,
    kind: .reading, difficulty: .easy, bonusMinutes: 15, requiresParentApproval: false, enabled: false
)
let exerciseTask = BonusChallenge(
    id: UUID(uuidString: "1A2B3C4D-0000-4000-8000-000000000003")!,
    kind: .exercise, difficulty: .hard, bonusMinutes: 30, requiresParentApproval: true, enabled: true
)

func bonusConfig(version: Int64, ceiling: Int = 60, challenges: [BonusChallenge] = [mathTask, readingTask, exerciseTask]) -> BonusConfig {
    BonusConfig(ruleVersion: version, maxDailyBonusMinutes: ceiling, challenges: challenges)
}

func pairingCode(_ code: String = "472918", state: PairingState = .codeIssued) -> PairingCode {
    PairingCode(code: code, expiresAt: Date(timeIntervalSince1970: 1_791_200_000), qrPayload: "nozir://pair?code=\(code)", state: state)
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`
Expected: FAIL — `value of type 'RuleSnapshot' has no member 'maxTrustBonusMinutes'`, `cannot find 'BonusChallenge' in scope`.

- [ ] **Step 3: `RuleSnapshot`**

`NozirKit/Sources/NozirFamily/RuleModels.swift` — `RuleSnapshot` ni butunlay almashtiring:

```swift
/// `RuleSnapshotResponse`, the parts the app reads. `version` goes back as `If-Match`.
public struct RuleSnapshot: Decodable, Equatable, Sendable {
    public let version: Int64
    public let screenTime: ScreenTimeLimit
    public let bedtime: BedtimeSchedule
    public let locationTracking: LocationTracking
    /// The trust ladder's ceiling (P09). 0 is off, which is where every child starts.
    public let maxTrustBonusMinutes: Int

    public init(
        version: Int64,
        screenTime: ScreenTimeLimit,
        bedtime: BedtimeSchedule,
        locationTracking: LocationTracking = .standard,
        maxTrustBonusMinutes: Int = 0
    ) {
        self.version = version
        self.screenTime = screenTime
        self.bedtime = bedtime
        self.locationTracking = locationTracking
        self.maxTrustBonusMinutes = maxTrustBonusMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case version, screenTime, bedtime, locationTracking, maxTrustBonusMinutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int64.self, forKey: .version)
        screenTime = try container.decode(ScreenTimeLimit.self, forKey: .screenTime)
        bedtime = try container.decode(BedtimeSchedule.self, forKey: .bedtime)
        locationTracking = try container.decodeIfPresent(LocationTracking.self, forKey: .locationTracking) ?? .standard
        maxTrustBonusMinutes = try container.decodeIfPresent(Int.self, forKey: .maxTrustBonusMinutes) ?? 0
    }
}
```

- [ ] **Step 4: Bonus turlari**

`NozirKit/Sources/NozirFamily/BonusModels.swift`:

```swift
import Foundation

/// A task's subject (`ChallengeKind`). A kind the server adds later keeps its
/// name, so a save sends the task back exactly as it came.
public enum ChallengeKind: Hashable, Sendable {
    case math, reading, english, exercise
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "MATH": self = .math
        case "READING": self = .reading
        case "ENGLISH": self = .english
        case "EXERCISE": self = .exercise
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .math: "MATH"
        case .reading: "READING"
        case .english: "ENGLISH"
        case .exercise: "EXERCISE"
        case .unknown(let name): name
        }
    }
}

/// How hard a task is (`ChallengeDifficulty`); the server scales the minutes by it.
public enum ChallengeDifficulty: Hashable, Sendable {
    case easy, medium, hard
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "EASY": self = .easy
        case "MEDIUM": self = .medium
        case "HARD": self = .hard
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .easy: "EASY"
        case .medium: "MEDIUM"
        case .hard: "HARD"
        case .unknown(let name): name
        }
    }
}

/// `BonusConfigItemDto`. P12 edits only `enabled`; the rest goes back as read.
public struct BonusChallenge: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let kind: ChallengeKind
    public let difficulty: ChallengeDifficulty
    public let bonusMinutes: Int
    public let requiresParentApproval: Bool
    public var enabled: Bool

    public init(
        id: UUID,
        kind: ChallengeKind,
        difficulty: ChallengeDifficulty,
        bonusMinutes: Int,
        requiresParentApproval: Bool,
        enabled: Bool
    ) {
        self.id = id
        self.kind = kind
        self.difficulty = difficulty
        self.bonusMinutes = bonusMinutes
        self.requiresParentApproval = requiresParentApproval
        self.enabled = enabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, difficulty, bonusMinutes, requiresParentApproval, enabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = ChallengeKind(wireName: try container.decode(String.self, forKey: .kind))
        difficulty = ChallengeDifficulty(wireName: try container.decode(String.self, forKey: .difficulty))
        bonusMinutes = try container.decode(Int.self, forKey: .bonusMinutes)
        requiresParentApproval = try container.decode(Bool.self, forKey: .requiresParentApproval)
        enabled = try container.decode(Bool.self, forKey: .enabled)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString.lowercased(), forKey: .id)
        try container.encode(kind.wireName, forKey: .kind)
        try container.encode(difficulty.wireName, forKey: .difficulty)
        try container.encode(bonusMinutes, forKey: .bonusMinutes)
        try container.encode(requiresParentApproval, forKey: .requiresParentApproval)
        try container.encode(enabled, forKey: .enabled)
    }
}

/// `BonusConfigDto` (P12): the daily ceiling and the tasks under it.
/// `ruleVersion` is the rule set's version — the same one every rules write names.
public struct BonusConfig: Decodable, Equatable, Sendable {
    public let ruleVersion: Int64
    public var maxDailyBonusMinutes: Int
    public var challenges: [BonusChallenge]

    public init(ruleVersion: Int64, maxDailyBonusMinutes: Int, challenges: [BonusChallenge]) {
        self.ruleVersion = ruleVersion
        self.maxDailyBonusMinutes = maxDailyBonusMinutes
        self.challenges = challenges
    }

    /// What every enabled task would pay together in one day.
    public var earnableMinutes: Int {
        challenges.filter(\.enabled).reduce(0) { $0 + $1.bonusMinutes }
    }

    /// The ceiling stops the tasks short of what they would pay.
    public var isCeilingBinding: Bool {
        earnableMinutes > maxDailyBonusMinutes
    }

    public func withChallenge(_ id: UUID, enabled: Bool) -> BonusConfig {
        var copy = self
        copy.challenges = challenges.map { challenge in
            guard challenge.id == id else { return challenge }
            var changed = challenge
            changed.enabled = enabled
            return changed
        }
        return copy
    }
}
```

- [ ] **Step 5: Protokol va API**

`NozirKit/Sources/NozirFamily/FamilyService.swift` — `setLocationTracking` qatoridan keyin:

```swift
    func setTrustLadder(_ minutes: Int, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func bonus(of childId: UUID) async throws -> BonusConfig
    func setBonus(_ config: BonusConfig, of childId: UUID, version: Int64) async throws -> BonusConfig
```

`NozirKit/Sources/NozirFamily/FamilyApi.swift` — `setLocationTracking` funksiyasidan keyin:

```swift
    /// The ladder's ceiling has a write of its own: the screen-time body does not carry it.
    public func setTrustLadder(_ minutes: Int, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        struct Body: Encodable {
            let maxTrustBonusMinutes: Int
        }
        let request = try ApiRequest.put(
            Self.childPath(childId) + "/rules/trust-ladder",
            json: Body(maxTrustBonusMinutes: minutes),
            ifMatch: Self.entityTag(version)
        )
        return try await client.send(request, as: RuleSnapshot.self)
    }

    public func bonus(of childId: UUID) async throws -> BonusConfig {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/rules/bonus"), as: BonusConfig.self)
    }

    /// The whole configuration goes back. The server decides on `If-Match`,
    /// never on the body's `ruleVersion`; the body states the same number anyway.
    public func setBonus(_ config: BonusConfig, of childId: UUID, version: Int64) async throws -> BonusConfig {
        struct Body: Encodable {
            let childId: String
            let ruleVersion: Int64
            let maxDailyBonusMinutes: Int
            let challenges: [BonusChallenge]
        }
        let body = Body(
            childId: childId.uuidString.lowercased(),
            ruleVersion: version,
            maxDailyBonusMinutes: config.maxDailyBonusMinutes,
            challenges: config.challenges
        )
        let request = try ApiRequest.put(Self.childPath(childId) + "/rules/bonus", json: body, ifMatch: Self.entityTag(version))
        return try await client.send(request, as: BonusConfig.self)
    }
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`, so'ng `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: ikkalasida `** TEST SUCCEEDED **` (mavjud testlar o'zgarishsiz o'tadi; `FakeFamily` yangi protokolga mos).

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirFamily/RuleModels.swift NozirKit/Sources/NozirFamily/BonusModels.swift NozirKit/Sources/NozirFamily/FamilyService.swift NozirKit/Sources/NozirFamily/FamilyApi.swift NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift
```

Xabar: `family: the trust ladder and the bonus tasks, read and written by version`

---
### Task 2: P03b boshqaruvlari umumiy view'larga ajratiladi

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift` (`toggleDay`, `daysSummary`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift` (butunlay almashtiriladi)
- Test: `NozirKit/Tests/NozirAppFeatureTests/RuleBoundsTests.swift`

**Interfaces:**
- Consumes: `Durations.short/long/range`, `ClockTime.date()`, `ClockTime(date:)`, `L10n.weekdayNames/weekdayNamesShort`.
- Produces:
  - `enum RuleMinuteRange { static let step = 15; static let dailyLimit = 30...360; static let bonusCeiling = 0...120; static let trustLadder = 0...120; static let windDown = 15...60 }`
  - `enum RuleDays { static func toggled(_ days: Set<Int>, _ day: Int) -> Set<Int>; static func summary(_ days: Set<Int>, _ l10n: L10n) -> String }`
  - Views: `RuleMinuteSlider(title:caption:value:range:accessibilityLabel:valueText:)`, `RuleRangeLabels()`, `RuleTimePicker(_ title: String, time: Binding<ClockTime>)`, `RuleDaysSection(activeDays: Set<Int>, onToggle: (Int) -> Void)`, `RuleWindDownSection(minutes: Int, onToggle: (Bool) -> Void, onMinutes: (Int) -> Void)`.
  - `NewChildRulesModel.daysSummary` qoladi (mavjud test uni chaqiradi) va `RuleDays.summary` ga o'tkazadi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/RuleBoundsTests.swift`:

```swift
import Foundation
import Testing
import NozirL10n
@testable import NozirAppFeature

@MainActor
@Suite struct RuleBoundsTests {
    @Test func theLastNightStaysOn() {
        #expect(RuleDays.toggled([3], 3) == [3])
        #expect(RuleDays.toggled([1, 3], 3) == [1])
        #expect(RuleDays.toggled([1], 5) == [1, 5])
        #expect(RuleDays.toggled([1], 8) == [1])
        #expect(RuleDays.toggled([1], 0) == [1])
    }

    @Test func theNightsAreNamedAsOnP03b() {
        let l10n = L10n(.uz)
        let mondayAndFriday = [l10n.weekdayNames[0], l10n.weekdayNames[4]].joined(separator: l10n.bedtimeDaysSeparator)

        #expect(RuleDays.summary(Set(1...7), l10n) == l10n.bedtimeDaysEveryNight)
        #expect(RuleDays.summary([5, 1], l10n) == l10n.bedtimeDaysSummary(mondayAndFriday))
        #expect(NewChildRulesModel.daysSummary([5, 1], l10n) == RuleDays.summary([5, 1], l10n))
    }

    @Test func theSlidersMoveInQuarterHoursWithinAndroidsBounds() {
        #expect(RuleMinuteRange.step == 15)
        #expect(RuleMinuteRange.dailyLimit == 30...360)
        #expect(RuleMinuteRange.trustLadder == 0...120)
        #expect(RuleMinuteRange.bonusCeiling == 0...120)
        #expect(RuleMinuteRange.windDown == 15...60)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'RuleDays' in scope`.

- [ ] **Step 3: Chegaralar va kunlar**

`NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift`:

```swift
import Foundation
import NozirL10n

/// The bounds every rule slider moves in (Android `RuleMinuteRange`). Narrower
/// than the server allows on purpose: no slider offers taking the phone away
/// by accident, and a family talks about time in quarter hours.
enum RuleMinuteRange {
    static let step = 15
    static let dailyLimit = 30...360
    static let bonusCeiling = 0...120
    /// The same numbers as the bonus ceiling, and a separate rule. 0 means off.
    static let trustLadder = 0...120
    static let windDown = 15...60
}

/// The nights a bedtime runs on, as ISO day numbers (1 = Monday).
enum RuleDays {
    /// The day flipped. The last night stays on: the server refuses an empty week,
    /// and a stray tap must not turn into a refused save.
    static func toggled(_ days: Set<Int>, _ day: Int) -> Set<Int> {
        guard (1...7).contains(day) else { return days }
        if days.contains(day) {
            return days.count > 1 ? days.subtracting([day]) : days
        }
        return days.union([day])
    }

    /// "Har kuni", or "Faol tunlar: Dushanba, Chorshanba".
    static func summary(_ days: Set<Int>, _ l10n: L10n) -> String {
        if days.count == 7 { return l10n.bedtimeDaysEveryNight }
        let names = days.sorted().compactMap { day in
            l10n.weekdayNames.indices.contains(day - 1) ? l10n.weekdayNames[day - 1] : nil
        }
        return l10n.bedtimeDaysSummary(names.joined(separator: l10n.bedtimeDaysSeparator))
    }
}
```

`NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift` — `toggleDay` va `daysSummary` ni almashtiring:

```swift
    /// At least one night stays on.
    public func toggleDay(_ day: Int) {
        activeDays = RuleDays.toggled(activeDays, day)
    }
```

```swift
    /// "Har kuni", or "Faol tunlar: Dushanba, Chorshanba".
    static func daysSummary(_ days: Set<Int>, _ l10n: L10n) -> String {
        RuleDays.summary(days, l10n)
    }
```

- [ ] **Step 4: Umumiy boshqaruvlar**

`NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// A quarter-hour slider under its title, the value on the right (P03b, P09, P12).
struct RuleMinuteSlider: View {
    private let title: String
    private let caption: String?
    @Binding private var value: Int
    private let range: ClosedRange<Int>
    private let accessibilityLabel: String
    /// The value as shown; nil writes it as "2s 30d".
    private let valueText: ((Int) -> String)?
    @Environment(\.l10n) private var l10n

    init(
        title: String,
        caption: String? = nil,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        accessibilityLabel: String,
        valueText: ((Int) -> String)? = nil
    ) {
        self.title = title
        self.caption = caption
        _value = value
        self.range = range
        self.accessibilityLabel = accessibilityLabel
        self.valueText = valueText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    if let caption {
                        Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                    }
                }
                Spacer()
                Text(valueText?(value) ?? Durations.short(value, l10n)).nozirText(.titleSmall, color: NozirColor.primaryAccent)
            }
            // A value from elsewhere stretches the range rather than being moved by it.
            Slider(
                value: Binding(get: { Double(value) }, set: { value = Int($0.rounded()) }),
                in: Durations.range(range, including: value),
                step: Double(RuleMinuteRange.step)
            )
            .tint(NozirColor.primary)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityValue(valueText?(value) ?? Durations.long(value, l10n))
        }
    }
}

/// "30d … 6s" under the daily-limit sliders.
struct RuleRangeLabels: View {
    @Environment(\.l10n) private var l10n

    var body: some View {
        HStack {
            Text(l10n.dailyLimitRangeMin)
            Spacer()
            Text(l10n.dailyLimitRangeMax)
        }
        .nozirText(.label, color: NozirColor.textTertiary)
    }
}

/// A wall-clock time with its label above (bedtime start or end).
struct RuleTimePicker: View {
    private let title: String
    @Binding private var time: ClockTime

    init(_ title: String, time: Binding<ClockTime>) {
        self.title = title
        _time = time
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            Text(title).nozirText(.bodySmall, color: NozirColor.textSecondary)
            DatePicker(
                title,
                selection: Binding(get: { time.date() }, set: { time = ClockTime(date: $0) }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The seven nights as chips, what they add up to, and the hint when one is left.
struct RuleDaysSection: View {
    private let activeDays: Set<Int>
    private let onToggle: (Int) -> Void
    @Environment(\.l10n) private var l10n

    init(activeDays: Set<Int>, onToggle: @escaping (Int) -> Void) {
        self.activeDays = activeDays
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.bedtimeDaysLabel).nozirText(.body)
            HStack(spacing: NozirSpacing.extraSmall) {
                ForEach(1...7, id: \.self) { day in chip(day) }
            }
            Text(RuleDays.summary(activeDays, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
            if activeDays.count == 1 {
                Text(l10n.bedtimeDaysHint).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
        }
    }

    private func chip(_ day: Int) -> some View {
        let isOn = activeDays.contains(day)
        return Button {
            onToggle(day)
        } label: {
            Text(l10n.weekdayNamesShort[day - 1])
                .nozirText(.bodySmall, color: isOn ? NozirColor.onPrimary : NozirColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: NozirRadius.button).fill(isOn ? NozirColor.primary : NozirColor.track))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.weekdayNames[day - 1])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// The warning before bedtime: a switch, and while it is on, its length.
/// Off is 0 — the only shape the child's phone understands.
struct RuleWindDownSection: View {
    private let minutes: Int
    private let onToggle: (Bool) -> Void
    private let onMinutes: (Int) -> Void
    @Environment(\.l10n) private var l10n

    init(minutes: Int, onToggle: @escaping (Bool) -> Void, onMinutes: @escaping (Int) -> Void) {
        self.minutes = minutes
        self.onToggle = onToggle
        self.onMinutes = onMinutes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Toggle(isOn: Binding(get: { minutes > 0 }, set: { onToggle($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.bedtimeWindDownTitle).nozirText(.body)
                    Text(minutes > 0 ? l10n.bedtimeWindDownSubtitle(minutes) : l10n.bedtimeWindDownOff)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .tint(NozirColor.primary)
            if minutes > 0 {
                Slider(
                    value: Binding(get: { Double(minutes) }, set: { onMinutes(Int($0.rounded())) }),
                    in: Durations.range(RuleMinuteRange.windDown, including: minutes),
                    step: Double(RuleMinuteRange.step)
                )
                .tint(NozirColor.primary)
                .accessibilityLabel(l10n.bedtimeWindDownSlider)
            }
        }
    }
}
```

- [ ] **Step 5: P03b umumiy boshqaruvlarda**

`NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift` — faylni butunlay almashtiring (xatti-harakat va tartib avvalgidek):

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03b as Android `NewChildRulesScreen`: two limits, the night window, the nights.
struct NewChildRulesView: View {
    @State private var model: NewChildRulesModel
    private let onSaved: (Child) -> Void
    @Environment(\.l10n) private var l10n

    init(model: NewChildRulesModel, onSaved: @escaping (Child) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.newChildRulesTitle(model.draft.displayName)).nozirText(.titleLarge)
                Text(model.isPrefilledFromSibling ? l10n.newChildRulesCopied : l10n.newChildRulesIntro)
                    .nozirText(.body, color: NozirColor.textSecondary)
                NozirCard { limitSection }
                NozirCard { bedtimeSection }
                Text(l10n.newChildRulesAppsLater).nozirText(.bodySmall, color: NozirColor.textTertiary)
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                NozirButton(l10n.newChildRulesActionContinue, size: .callToAction, isLoading: model.isSaving) {
                    Task {
                        if let child = await model.save() { onSaved(child) }
                    }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenNewChildRulesTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once the child exists, going back and saving again would be a second child.
        .navigationBarBackButtonHidden(model.hasCreatedChild)
        .task { await model.prefill() }
    }

    private var limitSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesLimitLabel).nozirText(.titleSmall)
            RuleMinuteSlider(
                title: l10n.dailyLimitSchoolDays,
                caption: l10n.dailyLimitSchoolDaysRange,
                value: $model.schoolDayMinutes,
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderSchool
            )
            RuleMinuteSlider(
                title: l10n.dailyLimitWeekend,
                caption: l10n.dailyLimitWeekendRange,
                value: $model.weekendMinutes,
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderWeekend
            )
            RuleRangeLabels()
        }
    }

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesBedtimeLabel).nozirText(.titleSmall)
            HStack(spacing: NozirSpacing.medium) {
                RuleTimePicker(l10n.bedtimeStartLabel, time: $model.bedtimeStart)
                RuleTimePicker(l10n.bedtimeEndLabel, time: $model.bedtimeEnd)
            }
            Text(l10n.bedtimeLength(Durations.long(model.bedtime.lengthMinutes, l10n)))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            RuleDaysSection(activeDays: model.activeDays) { model.toggleDay($0) }
            RuleWindDownSection(
                minutes: model.windDownMinutes,
                onToggle: { model.setWindDown(on: $0) },
                onMinutes: { model.setWindDownMinutes($0) }
            )
        }
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`, so'ng `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (`NewChildRulesModelTests` o'zgarishsiz o'tadi), `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift NozirKit/Tests/NozirAppFeatureTests/RuleBoundsTests.swift
```

Xabar: `rules: the sliders, clocks and nights of P03b, shared`

---
### Task 3: `ChildRulesSession` — bitta bola qoidalarining umumiy holati

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift`

**Interfaces:**
- Consumes: `FamilyStore` (`service`, `child(_:)`), `FamilyService.rules/subscription/chooseActiveChild`, `Subscription.isChildActive`, `UserMessage(_:)`, Task 1 `RuleSnapshot.maxTrustBonusMinutes`, `FakeFamily.Script.rulesGate`, `PauseGate`.
- Produces:
  - `enum RuleNotice: Equatable, Sendable { case saved, conflict }`
  - `enum RuleSaveOutcome: Equatable, Sendable { case saved, conflict, failed(UserMessage) }`
  - `@MainActor @Observable final class ChildRulesSession: Hashable` (tenglik — obyekt identifikatori):
    - `init(childId: UUID, family: FamilyStore)`; `let childId: UUID`, `let childName: String?`, `let family: FamilyStore`
    - `private(set) var snapshot: RuleSnapshot?`, `isLoading`, `loadFailure: UserMessage?`, `isOffline`, `isFrozen`, `isMakingActive`, `message: UserMessage?`; `var version: Int64?`
    - `func load() async` (faqat snapshot yo'q bo'lsa), `func reload() async` (majburiy), `func accept(_ fresh: RuleSnapshot)`, `func acceptBonus(version: Int64, ceiling: Int)`, `func write(_ send: () async throws -> RuleSnapshot) async -> RuleSaveOutcome`, `func makeActive() async`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))

@MainActor
private func setup(_ script: FakeFamily.Script) -> (ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    return (ChildRulesSession(childId: ali.id, family: family), fake)
}

@MainActor
@Suite struct ChildRulesSessionTests {
    @Test func aFirstLoadReadsTheRulesAndThePlan() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 30))]
        script.subscription = [.success(Subscription(activeChildId: nil))]
        let (session, fake) = setup(script)

        await session.load()

        #expect(session.childName == "Ali")
        #expect(session.version == 4)
        #expect(session.snapshot?.maxTrustBonusMinutes == 30)
        #expect(!session.isFrozen)
        #expect(!session.isLoading)
        #expect(await fake.calls == ["rules", "subscription"])
    }

    @Test func loadingAgainDoesNotAskAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 5))]
        let (session, fake) = setup(script)

        await session.load()
        await session.load()

        #expect(session.version == 4)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aFirstLoadThatFailsCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4))]
        let (session, _) = setup(script)

        await session.load()
        #expect(session.snapshot == nil)
        #expect(session.loadFailure == .noConnection)
        #expect(!session.isOffline)

        await session.load()
        #expect(session.version == 4)
        #expect(session.loadFailure == nil)
    }

    @Test func aReloadWithoutAConnectionKeepsWhatIsShown() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .failure(offline), .success(snapshot(version: 6))]
        let (session, _) = setup(script)
        await session.load()

        await session.reload()
        #expect(session.isOffline)
        #expect(session.version == 4)
        #expect(session.loadFailure == nil)

        await session.reload()
        #expect(!session.isOffline)
        #expect(session.version == 6)
    }

    @Test func anotherActiveChildFreezesThisOne() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (session, _) = setup(script)

        await session.load()

        #expect(session.isFrozen)
    }

    @Test func anUnknownPlanFreezesNobody() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, fake) = setup(script)

        await session.load()

        #expect(!session.isFrozen)
        #expect(await fake.calls.contains("subscription"))
    }

    @Test func makingThisChildActiveUnfreezesIt() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.activeChild = [.success(Subscription(activeChildId: ali.id))]
        let (session, fake) = setup(script)
        await session.load()
        #expect(session.isFrozen)

        await session.makeActive()

        #expect(!session.isFrozen)
        #expect(session.message == nil)
        #expect(await fake.childIds.last == ali.id)
    }

    @Test func aRefusedMakeActiveSaysWhyAndStaysFrozen() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (session, _) = setup(script)
        await session.load()

        await session.makeActive()

        #expect(session.isFrozen)
        #expect(session.message == .noConnection)
        #expect(!session.isMakingActive)
    }

    @Test func anAnswerOlderThanWhatIsHeldIsIgnored() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, _) = setup(script)
        await session.load()

        session.accept(snapshot(version: 6))
        session.accept(snapshot(version: 5))

        #expect(session.version == 6)
    }

    @Test func aBonusAnswerMovesTheVersionAndTheCeilingOnly() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 45))]
        let (session, _) = setup(script)
        await session.load()

        session.acceptBonus(version: 5, ceiling: 30)

        #expect(session.version == 5)
        #expect(session.snapshot?.screenTime == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 30))
        #expect(session.snapshot?.bedtime == defaultBedtime)
        #expect(session.snapshot?.maxTrustBonusMinutes == 45)
    }

    @Test(.timeLimit(.minutes(5)))
    func aReadAskedBeforeAWriteLandedIsDropped() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (session, fake) = setup(script)
        await session.load()
        await fake.add {
            $0.rules = [.success(snapshot(version: 4))]
            $0.rulesGate = gate
        }

        let late = Task { await session.reload() }
        await gate.untilPaused()
        session.accept(snapshot(version: 5, trust: 15))
        await gate.release()
        await late.value

        #expect(session.version == 5)
        #expect(session.snapshot?.maxTrustBonusMinutes == 15)
        #expect(!session.isLoading)
    }

    @Test func aWriteHandsItsAnswerToTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.success(snapshot(version: 5))]
        let (session, fake) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .saved)
        #expect(session.version == 5)
        #expect(await fake.bedtimeWrites.map(\.version) == [4])
    }

    @Test func aConflictReadsAgainAndIsNotResent() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7))]
        script.bedtime = [.failure(conflict)]
        let (session, fake) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .conflict)
        #expect(session.version == 7)
        #expect(await fake.bedtimeWrites.count == 1)
    }

    @Test func aRefusedWriteKeepsTheVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (session, _) = setup(script)
        await session.load()

        let outcome = await session.write { try await session.family.service.setBedtime(defaultBedtime, of: ali.id, version: 4) }

        #expect(outcome == .failed(.childNotActive))
        #expect(session.version == 4)
    }

    @Test func aSessionIsItsOwnIdentity() {
        let (first, _) = setup(FakeFamily.Script())
        let (second, _) = setup(FakeFamily.Script())

        #expect(first == first)
        #expect(first != second)
        #expect(Set([first, first, second]).count == 2)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'ChildRulesSession' in scope`.

- [ ] **Step 3: Sessiya**

`NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift`:

```swift
import Foundation
import Observation
import NozirFamily

/// What a rules screen says after a save.
enum RuleNotice: Equatable, Sendable {
    case saved
    /// Changed elsewhere since it was read: the latest is shown, the edit is dropped.
    case conflict
}

/// How one rule write ended.
enum RuleSaveOutcome: Equatable, Sendable {
    case saved
    /// Refused as stale. The session has read the rules again; nothing was resent.
    case conflict
    case failed(UserMessage)
}

/// One child's rule set, shared by P09 and every screen opened from it.
///
/// The server keeps one version for all of a child's rules, and every write
/// moves it. The screens therefore write against this session's version and
/// hand every answer back here: a save on P10 then never makes P09's next save
/// look stale. Each screen keeps only its own edit.
@MainActor
@Observable
final class ChildRulesSession {
    let childId: UUID
    let childName: String?
    let family: FamilyStore
    private(set) var snapshot: RuleSnapshot?
    private(set) var isLoading = false
    /// The first read failed: there is nothing to show yet.
    private(set) var loadFailure: UserMessage?
    /// A later read found no connection; what is shown is the last known state.
    private(set) var isOffline = false
    /// A free family keeps another child active: these rules cannot change.
    private(set) var isFrozen = false
    private(set) var isMakingActive = false
    /// Why "make this child active" did not work.
    private(set) var message: UserMessage?
    /// Goes up with every read and every accepted answer; an older read is dropped.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var planGeneration = 0

    init(childId: UUID, family: FamilyStore) {
        self.childId = childId
        self.family = family
        childName = family.child(childId)?.displayName
    }

    var version: Int64? {
        snapshot?.version
    }

    /// Reads once. A tab switch or a screen opened again leaves what is held alone.
    func load() async {
        guard snapshot == nil else { return }
        await read()
    }

    /// Reads whatever is held again: after a conflict, or a pull to refresh.
    func reload() async {
        await read()
    }

    /// A write's answer. One older than what is held is ignored (two screens'
    /// answers can land out of order), and a read still in flight is dropped:
    /// it was asked before this write landed.
    func accept(_ fresh: RuleSnapshot) {
        if let snapshot, fresh.version < snapshot.version { return }
        generation += 1
        isLoading = false
        snapshot = fresh
        loadFailure = nil
        isOffline = false
    }

    /// P12's answer carries only the version and the ceiling; the rest is as held.
    func acceptBonus(version: Int64, ceiling: Int) {
        guard let snapshot else { return }
        accept(RuleSnapshot(
            version: version,
            screenTime: ScreenTimeLimit(
                schoolDayMinutes: snapshot.screenTime.schoolDayMinutes,
                weekendMinutes: snapshot.screenTime.weekendMinutes,
                maxDailyBonusMinutes: ceiling
            ),
            bedtime: snapshot.bedtime,
            locationTracking: snapshot.locationTracking,
            maxTrustBonusMinutes: snapshot.maxTrustBonusMinutes
        ))
    }

    /// Sends one write and keeps its answer. A conflict reads the rules again
    /// and is never resent on the parent's behalf (openapi `RuleVersionConflict`).
    func write(_ send: () async throws -> RuleSnapshot) async -> RuleSaveOutcome {
        do {
            accept(try await send())
            return .saved
        } catch {
            let failure = UserMessage(error)
            guard failure == .conflict else { return .failed(failure) }
            await reload()
            return .conflict
        }
    }

    func makeActive() async {
        guard !isMakingActive else { return }
        isMakingActive = true
        message = nil
        defer { isMakingActive = false }
        planGeneration += 1
        do {
            let subscription = try await family.service.chooseActiveChild(childId)
            isFrozen = !subscription.isChildActive(childId)
        } catch {
            message = UserMessage(error)
        }
    }

    private func read() async {
        generation += 1
        let mine = generation
        isLoading = true
        do {
            let fresh = try await family.service.rules(of: childId)
            guard mine == generation else { return }
            snapshot = fresh
            loadFailure = nil
            isOffline = false
        } catch is CancellationError {
            if mine == generation { isLoading = false }
            return
        } catch {
            guard mine == generation else { return }
            let failure = UserMessage(error)
            if snapshot == nil {
                loadFailure = failure
            } else if failure == .noConnection || failure == .timeout {
                isOffline = true
            }
        }
        isLoading = false
        await readPlan()
    }

    /// An unknown plan freezes nobody (Android `FamilyPlan.Unknown`): a lock
    /// drawn because an answer had not arrived would tell a paying family they
    /// had lost a child.
    private func readPlan() async {
        planGeneration += 1
        let mine = planGeneration
        guard let subscription = try? await family.service.subscription(), mine == planGeneration else { return }
        isFrozen = !subscription.isChildActive(childId)
    }
}

/// A session is one hub's: two sessions for the same child are still two.
extension ChildRulesSession: Hashable {
    nonisolated static func == (lhs: ChildRulesSession, rhs: ChildRulesSession) -> Bool {
        lhs === rhs
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift
```

Xabar: `rules: one session per child — one version, the plan, late answers dropped`

---
### Task 4: `DailyLimitModel` — P09 mantiqi (limit + ishonch zinapoyasi)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/DailyLimitModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/DailyLimitModelTests.swift`

**Interfaces:**
- Consumes: Task 3 `ChildRulesSession` (`snapshot`, `version`, `isFrozen`, `childId`, `family`, `load()`, `reload()`, `write(_:)`, `acceptBonus`), `RuleNotice`, `RuleSaveOutcome`; Task 1 `FamilyService.setTrustLadder`, `FakeFamily.Script.writeGate`, `snapshot(…trust:)`.
- Produces:
  - `struct DailyLimitValues: Equatable, Sendable { var schoolDayMinutes: Int; var weekendMinutes: Int; var trustBonusMinutes: Int; init(schoolDayMinutes:weekendMinutes:trustBonusMinutes:); init(_ snapshot: RuleSnapshot) }`
  - `@MainActor @Observable final class DailyLimitModel`:
    - `init(session: ChildRulesSession)`; `let session`
    - `private(set) var edited: DailyLimitValues?`, `editBase: DailyLimitValues?`, `sameEveryDayChoice: Bool?`, `isSaving`, `message: UserMessage?`, `notice: RuleNotice?`
    - `var values: DailyLimitValues?`, `var isSameEveryDay: Bool`, `var hasLimitChange: Bool`, `var hasTrustLadderChange: Bool`, `var canSave: Bool`
    - `func load() async`, `setSchoolDayMinutes(_:)`, `setWeekendMinutes(_:)`, `setTrustBonusMinutes(_:)`, `setSameEveryDay(_:)`, `func save() async`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/DailyLimitModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let sameDays = ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 120, maxDailyBonusMinutes: 60)

/// The model over a loaded session, as P09 shows it.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (DailyLimitModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = DailyLimitModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct DailyLimitModelTests {
    @Test func theRuleIsShownAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, trust: 30))]
        let (model, _, _) = await setup(script)

        #expect(model.values == DailyLimitValues(schoolDayMinutes: 120, weekendMinutes: 180, trustBonusMinutes: 30))
        #expect(!model.isSameEveryDay)
        #expect(!model.canSave)

        model.setWeekendMinutes(150)

        #expect(model.hasLimitChange)
        #expect(!model.hasTrustLadderChange)
        #expect(model.canSave)
    }

    @Test func sameEveryDayMovesBothDaysTogether() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: sameDays))]
        let (model, _, _) = await setup(script)
        #expect(model.isSameEveryDay)

        model.setSchoolDayMinutes(90)
        #expect(model.values?.weekendMinutes == 90)

        model.setSameEveryDay(false)
        model.setSchoolDayMinutes(60)
        #expect(model.values?.schoolDayMinutes == 60)
        #expect(model.values?.weekendMinutes == 90)
    }

    @Test func turningSameEveryDayOnGivesTheWeekendTheSchoolDay() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        model.setSameEveryDay(true)

        #expect(model.isSameEveryDay)
        #expect(model.values?.weekendMinutes == 120)
        #expect(model.hasLimitChange)
    }

    @Test func aLimitOnlySaveCarriesTheBonusCeilingAndSkipsTheLadder() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let saved = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 5, limit: saved))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.screenTimeWrites == [RuleWrite(value: saved, version: 4)])
        #expect(await fake.trustLadderWrites.isEmpty)
        #expect(model.notice == .saved)
        #expect(session.version == 5)
        #expect(model.edited == nil)
        #expect(!model.canSave)
    }

    @Test func aLadderOnlySaveSkipsTheLimit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 45))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(45)

        await model.save()

        #expect(await fake.trustLadderWrites == [RuleWrite(value: 45, version: 4)])
        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.notice == .saved)
        #expect(session.snapshot?.maxTrustBonusMinutes == 45)
    }

    @Test func bothChangesGoLadderFirstThenTheLimitOnTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 30))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 6, limit: limit, trust: 30))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.calls.filter { $0 == "trustLadder" || $0 == "screenTime" } == ["trustLadder", "screenTime"])
        #expect(await fake.trustLadderWrites.map(\.version) == [4])
        #expect(await fake.screenTimeWrites.map(\.version) == [5])
        #expect(session.version == 6)
        #expect(model.notice == .saved)
    }

    // Review Focus 1.
    @Test func aLimitFailureAfterTheLadderKeepsTheLadderAndRetriesOnTheNewVersion() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.success(snapshot(version: 5, trust: 30))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.failure(offline), .success(snapshot(version: 6, limit: limit, trust: 30))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(model.message == .noConnection)
        #expect(model.notice == nil)
        #expect(session.version == 5)
        #expect(session.snapshot?.maxTrustBonusMinutes == 30)
        #expect(model.values == DailyLimitValues(schoolDayMinutes: 90, weekendMinutes: 180, trustBonusMinutes: 30))
        #expect(!model.hasTrustLadderChange)
        #expect(model.hasLimitChange)
        #expect(model.canSave)

        await model.save()

        #expect(await fake.trustLadderWrites.count == 1)
        #expect(await fake.screenTimeWrites.map(\.version) == [5, 5])
        #expect(model.notice == .saved)
        #expect(model.message == nil)
        #expect(session.version == 6)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aRefusedLadderStopsBeforeTheLimit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.trustLadder = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, session, fake) = await setup(script)
        model.setTrustBonusMinutes(30)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.message == .childNotActive)
        #expect(session.version == 4)
        #expect(model.canSave)
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = ScreenTimeLimit(schoolDayMinutes: 150, weekendMinutes: 150, maxDailyBonusMinutes: 60)
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7, limit: elsewhere))]
        script.screenTime = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 7)
        #expect(model.values == DailyLimitValues(schoolDayMinutes: 150, weekendMinutes: 150, trustBonusMinutes: 0))
        #expect(model.isSameEveryDay)
        #expect(!model.canSave)
        #expect(await fake.screenTimeWrites.count == 1)
    }

    @Test func aRuleChangedElsewhereUnderTheEditIsNotWrittenOver() async {
        var script = FakeFamily.Script()
        let elsewhere = ScreenTimeLimit(schoolDayMinutes: 60, weekendMinutes: 60, maxDailyBonusMinutes: 60)
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 5, limit: elsewhere))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        await session.reload()

        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.values?.schoolDayMinutes == 60)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        model.setTrustBonusMinutes(15)

        await model.load()

        #expect(model.values == DailyLimitValues(schoolDayMinutes: 90, weekendMinutes: 180, trustBonusMinutes: 15))
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aSaveOnAnotherScreenLeavesTheEditInPlace() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, session, _) = await setup(script)
        model.setSchoolDayMinutes(90)

        session.accept(snapshot(version: 5, bedtime: BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])))

        #expect(model.values?.schoolDayMinutes == 90)
        #expect(model.canSave)
    }

    @Test func theLimitSaveCarriesACeilingP12JustSaved() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.screenTime = [.success(snapshot(version: 6))]
        let (model, session, fake) = await setup(script)
        model.setSchoolDayMinutes(90)
        session.acceptBonus(version: 5, ceiling: 30)

        await model.save()

        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 30), version: 5)])
    }

    // Review Focus 5.
    @Test(.timeLimit(.minutes(5)))
    func twoTapsSaveOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.screenTime = [.success(snapshot(version: 5))]
        script.writeGate = gate
        let (model, _, fake) = await setup(script)
        model.setSchoolDayMinutes(90)

        let first = Task { await model.save() }
        await gate.untilPaused()
        #expect(model.isSaving)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.screenTimeWrites.count == 1)

        await gate.release()
        await first.value
        #expect(model.notice == .saved)
        #expect(await fake.screenTimeWrites.count == 1)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, session, fake) = await setup(script)
        #expect(session.isFrozen)
        model.setSchoolDayMinutes(90)

        #expect(!model.canSave)
        await model.save()

        #expect(await fake.screenTimeWrites.isEmpty)
        #expect(await fake.trustLadderWrites.isEmpty)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'DailyLimitModel' in scope`.

- [ ] **Step 3: `DailyLimitModel`**

`NozirKit/Sources/NozirAppFeature/Rules/DailyLimitModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily

/// P09's three numbers: the two day limits and the trust ladder's ceiling.
struct DailyLimitValues: Equatable, Sendable {
    var schoolDayMinutes: Int
    var weekendMinutes: Int
    var trustBonusMinutes: Int

    init(schoolDayMinutes: Int, weekendMinutes: Int, trustBonusMinutes: Int) {
        self.schoolDayMinutes = schoolDayMinutes
        self.weekendMinutes = weekendMinutes
        self.trustBonusMinutes = trustBonusMinutes
    }

    init(_ snapshot: RuleSnapshot) {
        self.init(
            schoolDayMinutes: snapshot.screenTime.schoolDayMinutes,
            weekendMinutes: snapshot.screenTime.weekendMinutes,
            trustBonusMinutes: snapshot.maxTrustBonusMinutes
        )
    }
}

/// P09 (Android `DailyLimitViewModel`): the daily limit and the trust ladder.
///
/// Only the parent's edit lives here; the rule as saved is the session's. A
/// load therefore never touches the edit, and a save made on another screen of
/// the same hub moves the version this one writes against.
@MainActor
@Observable
final class DailyLimitModel {
    let session: ChildRulesSession
    /// The edit; nil while nothing has been touched.
    private(set) var edited: DailyLimitValues?
    /// What the edit started from. A save checks it is still what the session holds.
    private(set) var editBase: DailyLimitValues?
    /// "Same every day" as the parent set it; nil reads it from the numbers.
    private(set) var sameEveryDayChoice: Bool?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var values: DailyLimitValues? {
        edited ?? session.snapshot.map(DailyLimitValues.init)
    }

    /// Not stored: the server and Android read it as school == weekend.
    var isSameEveryDay: Bool {
        if let sameEveryDayChoice { return sameEveryDayChoice }
        guard let values else { return true }
        return values.schoolDayMinutes == values.weekendMinutes
    }

    var hasLimitChange: Bool {
        guard let edited, let editBase else { return false }
        return edited.schoolDayMinutes != editBase.schoolDayMinutes || edited.weekendMinutes != editBase.weekendMinutes
    }

    var hasTrustLadderChange: Bool {
        guard let edited, let editBase else { return false }
        return edited.trustBonusMinutes != editBase.trustBonusMinutes
    }

    var canSave: Bool {
        !isSaving && !session.isFrozen && session.version != nil && (hasLimitChange || hasTrustLadderChange)
    }

    func load() async {
        await session.load()
    }

    func setSchoolDayMinutes(_ minutes: Int) {
        let same = isSameEveryDay
        edit { values in
            values.schoolDayMinutes = minutes
            if same { values.weekendMinutes = minutes }
        }
    }

    func setWeekendMinutes(_ minutes: Int) {
        edit { $0.weekendMinutes = minutes }
    }

    func setTrustBonusMinutes(_ minutes: Int) {
        edit { $0.trustBonusMinutes = minutes }
    }

    /// On gives the weekend the school-day figure, the one the parent was just
    /// looking at. Off changes nothing until a slider moves.
    func setSameEveryDay(_ isSame: Bool) {
        sameEveryDayChoice = isSame
        if isSame {
            edit { $0.weekendMinutes = $0.schoolDayMinutes }
        }
    }

    /// One button, up to two writes, in order: the ladder has an endpoint of its
    /// own. The limit then names the version the ladder came back with. A
    /// failure stops there: what was saved stays saved, and what was not waits
    /// for another tap against the new version.
    func save() async {
        guard canSave, let edited, let editBase, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Read again under this edit and changed elsewhere: never written over.
        guard DailyLimitValues(held) == editBase else {
            finish(.conflict)
            return
        }
        let service = session.family.service
        let childId = session.childId
        if edited.trustBonusMinutes != editBase.trustBonusMinutes {
            let minutes = edited.trustBonusMinutes
            let version = session.version ?? held.version
            let outcome = await session.write { try await service.setTrustLadder(minutes, of: childId, version: version) }
            guard outcome == .saved else {
                finish(outcome)
                return
            }
            self.editBase?.trustBonusMinutes = minutes
        }
        if edited.schoolDayMinutes != editBase.schoolDayMinutes || edited.weekendMinutes != editBase.weekendMinutes {
            let current = session.snapshot ?? held
            let limit = ScreenTimeLimit(
                schoolDayMinutes: edited.schoolDayMinutes,
                weekendMinutes: edited.weekendMinutes,
                maxDailyBonusMinutes: current.screenTime.maxDailyBonusMinutes
            )
            let version = current.version
            let outcome = await session.write { try await service.setScreenTime(limit, of: childId, version: version) }
            guard outcome == .saved else {
                finish(outcome)
                return
            }
        }
        finish(.saved)
    }

    private func finish(_ outcome: RuleSaveOutcome) {
        switch outcome {
        case .saved:
            discardEdit()
            notice = .saved
        case .conflict:
            discardEdit()
            notice = .conflict
        case .failed(let failure):
            message = failure
        }
    }

    private func edit(_ change: (inout DailyLimitValues) -> Void) {
        guard var copy = values else { return }
        if edited == nil {
            editBase = session.snapshot.map(DailyLimitValues.init)
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
        sameEveryDayChoice = nil
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/DailyLimitModel.swift NozirKit/Tests/NozirAppFeatureTests/DailyLimitModelTests.swift
```

Xabar: `p09: the daily limit and the trust ladder, saved in order on one version`

---
### Task 5: P09 hub — bola tanlagich, kartalar, "Boshqa qoidalar", holatlar

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/RulesHubModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Rules/RuleTexts.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/RuleSaveFooter.swift` (`RuleSaveFooter`, `RuleLinkRow`)
- Create: `NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift` (`RuleScreen`, `RulesHubView`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift` (muzlatilgan karta umumiy view'ga)
- Test: `NozirKit/Tests/NozirAppFeatureTests/RulesHubModelTests.swift`

**Interfaces:**
- Consumes: Task 2 `RuleMinuteSlider`, `RuleRangeLabels`, `RuleMinuteRange`, `RuleDays.summary`; Task 3 `ChildRulesSession`, `RuleNotice`; Task 4 `DailyLimitModel`, `DailyLimitValues`; `NozirChildSwitcher`, `NozirSwitcherChild`, `AvatarTone.forKey(_:position:)`, `NozirEmptyState`, `NozirErrorState`, `NozirOfflineNotice`, `NozirInlineMessage`, `NozirSectionTitle`, `NozirCard`, `NozirButton`, `NozirStatusDot`.
- Produces:
  - `@MainActor @Observable final class RulesHubModel { init(childId: UUID?, picksChild: Bool, family: FamilyStore, makeSession: @escaping @MainActor (UUID) -> ChildRulesSession, makeDailyLimit: @escaping @MainActor (ChildRulesSession) -> DailyLimitModel); let picksChild; let family; private(set) var session: ChildRulesSession?; private(set) var dailyLimit: DailyLimitModel?; var selectedChildId: UUID?; var showsSwitcher: Bool; func select(_ childId: UUID?); func load() async; func switcherChildren(_ l10n: L10n) -> [NozirSwitcherChild] }`
  - `enum RuleTexts { static func saved(childName:_:) ; static func limitNotice(childName:_:); static func trustValue(_:_:); static func trustNote(_:_:); static func bedtimeRange(_:_:); static func bonusRow(_:_:); static func locationRow(_:_:) }` (hammasi `String`).
  - `enum RuleScreen: Hashable { case bedtime(ChildRulesSession), bonus(ChildRulesSession), locationTracking(ChildRulesSession) }`
  - Views: `RulesHubView(model: RulesHubModel, onOpen: (RuleScreen) -> Void)`, `DailyLimitSection(model: DailyLimitModel, onOpen: (RuleScreen) -> Void)`, `FrozenChildCard(isMakingActive: Bool, onMakeActive: () -> Void)`, `RuleSaveFooter(notice:message:childName:isSaving:canSave:onSave:)`, `RuleLinkRow(title:lines:isEnabled:action:)`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/RulesHubModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let vali = makeChild("Vali")
private let aliLimit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 120, maxDailyBonusMinutes: 60)
private let valiLimit = ScreenTimeLimit(schoolDayMinutes: 240, weekendMinutes: 300, maxDailyBonusMinutes: 60)

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    children: [Child] = [ali, vali],
    childId: UUID? = nil,
    picksChild: Bool = true
) -> (RulesHubModel, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    children.forEach(family.replace)
    let hub = RulesHubModel(
        childId: childId,
        picksChild: picksChild,
        family: family,
        makeSession: { ChildRulesSession(childId: $0, family: family) },
        makeDailyLimit: { DailyLimitModel(session: $0) }
    )
    return (hub, fake)
}

@MainActor
@Suite struct RulesHubModelTests {
    @Test func fromProfileItOpensOnTheFirstChildWithTheSwitcher() {
        let (hub, _) = setup(FakeFamily.Script())

        #expect(hub.selectedChildId == ali.id)
        #expect(hub.dailyLimit?.session === hub.session)
        #expect(hub.showsSwitcher)
        #expect(hub.switcherChildren(L10n(.uz)).map(\.name) == ["Ali", "Vali"])
    }

    @Test func fromAChildsDetailsItIsThatChildOnly() {
        let (hub, _) = setup(FakeFamily.Script(), childId: vali.id, picksChild: false)

        #expect(hub.selectedChildId == vali.id)
        #expect(!hub.showsSwitcher)
    }

    @Test func oneChildNeedsNoSwitcher() {
        let (hub, _) = setup(FakeFamily.Script(), children: [ali])

        #expect(!hub.showsSwitcher)
    }

    @Test func noChildrenIsNoChild() {
        let (hub, _) = setup(FakeFamily.Script(), children: [])

        #expect(hub.session == nil)
        #expect(hub.dailyLimit == nil)
    }

    @Test func anotherChildIsAnotherSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit)), .success(snapshot(version: 9, limit: valiLimit))]
        let (hub, _) = setup(script)
        await hub.load()
        let aliSession = hub.session
        hub.dailyLimit?.setSchoolDayMinutes(60)

        hub.select(vali.id)
        await hub.load()

        #expect(hub.session !== aliSession)
        #expect(hub.session?.childId == vali.id)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 240)
        #expect(hub.dailyLimit?.canSave == false)
    }

    @Test func choosingTheSameChildAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit))]
        let (hub, _) = setup(script)
        await hub.load()
        hub.dailyLimit?.setSchoolDayMinutes(60)
        let session = hub.session

        hub.select(ali.id)
        hub.select(nil)

        #expect(hub.session === session)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 60)
    }

    // Review Focus 3.
    @Test(.timeLimit(.minutes(5)))
    func aLateAnswerForTheFormerChildNeverReachesTheNewOne() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, limit: aliLimit)), .success(snapshot(version: 9, limit: valiLimit))]
        script.rulesGate = gate
        let (hub, fake) = setup(script)

        let aliLoad = Task { await hub.load() }
        await gate.untilPaused()
        hub.select(vali.id)
        await hub.load()
        await gate.release()
        await aliLoad.value

        #expect(hub.session?.childId == vali.id)
        #expect(hub.session?.version == 9)
        #expect(hub.dailyLimit?.values?.schoolDayMinutes == 240)
        #expect(await fake.childIds == [ali.id, vali.id])
    }
}

@Suite struct RuleTextsTests {
    private let l10n = L10n(.uz)

    @Test func theLadderAtZeroIsOff() {
        #expect(RuleTexts.trustValue(0, l10n) == l10n.trustLadderOffValue)
        #expect(RuleTexts.trustNote(0, l10n) == l10n.trustLadderNoteOff)
        #expect(RuleTexts.trustValue(45, l10n) == l10n.trustLadderValue(Durations.short(45, l10n)))
        #expect(RuleTexts.trustNote(60, l10n) == l10n.trustLadderNoteRungs(Durations.short(60, l10n)))
    }

    @Test func theNoticeAndTheSavedLineNameTheChildWhenKnown() {
        #expect(RuleTexts.limitNotice(childName: "Ali", l10n) == l10n.dailyLimitNoticeNamed("Ali"))
        #expect(RuleTexts.limitNotice(childName: nil, l10n) == l10n.dailyLimitNotice)
        #expect(RuleTexts.saved(childName: "Ali", l10n) == l10n.rulesSavedNamed("Ali"))
        #expect(RuleTexts.saved(childName: nil, l10n) == l10n.rulesSaved)
    }

    @Test func theOtherRulesStateEachRuleAsItStands() {
        let rules = snapshot(version: 1, tracking: LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100))

        #expect(RuleTexts.bedtimeRange(rules.bedtime, l10n) == l10n.rulesTimeRange("22:00", "07:00"))
        #expect(RuleTexts.bonusRow(rules, l10n) == l10n.rulesLinkBonusCeiling(Durations.short(60, l10n)))
        #expect(RuleTexts.locationRow(rules.locationTracking, l10n) == l10n.rulesLinkLocationEvery(15))
        #expect(RuleTexts.locationRow(LocationTracking(isEnabled: false, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100), l10n) == l10n.locationTrackingOff)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'RulesHubModel' in scope`, `cannot find 'RuleTexts' in scope`.

- [ ] **Step 3: Hub modeli va matnlar**

`NozirKit/Sources/NozirAppFeature/Rules/RulesHubModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P09's frame: which child, and that child's session and limit model.
/// From Profile the parent may move between children (2+); from P03 it is
/// that child only.
@MainActor
@Observable
final class RulesHubModel {
    let picksChild: Bool
    let family: FamilyStore
    private(set) var session: ChildRulesSession?
    private(set) var dailyLimit: DailyLimitModel?
    private let makeSession: @MainActor (UUID) -> ChildRulesSession
    private let makeDailyLimit: @MainActor (ChildRulesSession) -> DailyLimitModel

    /// `childId` nil opens on the first child.
    init(
        childId: UUID?,
        picksChild: Bool,
        family: FamilyStore,
        makeSession: @escaping @MainActor (UUID) -> ChildRulesSession,
        makeDailyLimit: @escaping @MainActor (ChildRulesSession) -> DailyLimitModel
    ) {
        self.picksChild = picksChild
        self.family = family
        self.makeSession = makeSession
        self.makeDailyLimit = makeDailyLimit
        select(childId ?? family.children.first?.id)
    }

    var selectedChildId: UUID? {
        session?.childId
    }

    var showsSwitcher: Bool {
        picksChild && family.children.count > 1
    }

    /// Another child is another rule set: a new session, so nothing of the
    /// previous child's — its rules, an edit, an answer still on its way — can
    /// reach this one. The same child again keeps everything.
    func select(_ childId: UUID?) {
        guard let childId, childId != session?.childId else { return }
        let fresh = makeSession(childId)
        session = fresh
        dailyLimit = makeDailyLimit(fresh)
    }

    func load() async {
        await dailyLimit?.load()
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
}
```

`NozirKit/Sources/NozirAppFeature/Rules/RuleTexts.swift`:

```swift
import Foundation
import NozirFamily
import NozirL10n

/// The sentences of P09 and its rows, as Android writes them.
enum RuleTexts {
    /// After a save: the child's phone takes it at the next connection.
    static func saved(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.rulesSavedNamed) ?? l10n.rulesSaved
    }

    static func limitNotice(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.dailyLimitNoticeNamed) ?? l10n.dailyLimitNotice
    }

    /// "O'chiq" at zero, "+45d" otherwise.
    static func trustValue(_ minutes: Int, _ l10n: L10n) -> String {
        minutes == 0 ? l10n.trustLadderOffValue : l10n.trustLadderValue(Durations.short(minutes, l10n))
    }

    static func trustNote(_ minutes: Int, _ l10n: L10n) -> String {
        minutes == 0 ? l10n.trustLadderNoteOff : l10n.trustLadderNoteRungs(Durations.short(minutes, l10n))
    }

    static func bedtimeRange(_ bedtime: BedtimeSchedule, _ l10n: L10n) -> String {
        l10n.rulesTimeRange(bedtime.start.text, bedtime.end.text)
    }

    static func bonusRow(_ snapshot: RuleSnapshot, _ l10n: L10n) -> String {
        l10n.rulesLinkBonusCeiling(Durations.short(snapshot.screenTime.maxDailyBonusMinutes, l10n))
    }

    static func locationRow(_ tracking: LocationTracking, _ l10n: L10n) -> String {
        tracking.isEnabled ? l10n.rulesLinkLocationEvery(tracking.intervalMinutes) : l10n.locationTrackingOff
    }
}
```

- [ ] **Step 4: Umumiy kartalar va qatorlar**

`NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The free-plan lock of a frozen child (P03, P09): the rules stay as they
/// are on the phone, and this child can be made the active one.
struct FrozenChildCard: View {
    private let isMakingActive: Bool
    private let onMakeActive: () -> Void
    @Environment(\.l10n) private var l10n

    init(isMakingActive: Bool, onMakeActive: @escaping () -> Void) {
        self.isMakingActive = isMakingActive
        self.onMakeActive = onMakeActive
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
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift` — `if model.isFrozen { frozenCard }` qatorini almashtiring:

```swift
                if model.isFrozen {
                    FrozenChildCard(isMakingActive: model.isMakingActive) {
                        Task { await model.makeActive() }
                    }
                }
```

va `private var frozenCard: some View { … }` xususiyatini butunlay o'chiring.

`NozirKit/Sources/NozirAppFeature/Screens/RuleSaveFooter.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The end of every rules screen: what the last save did, and "Saqlash",
/// enabled only when there is something to save.
struct RuleSaveFooter: View {
    private let notice: RuleNotice?
    private let message: UserMessage?
    private let childName: String?
    private let isSaving: Bool
    private let canSave: Bool
    private let onSave: () -> Void
    @Environment(\.l10n) private var l10n

    init(notice: RuleNotice?, message: UserMessage?, childName: String?, isSaving: Bool, canSave: Bool, onSave: @escaping () -> Void) {
        self.notice = notice
        self.message = message
        self.childName = childName
        self.isSaving = isSaving
        self.canSave = canSave
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            switch notice {
            case .saved?:
                Text(RuleTexts.saved(childName: childName, l10n)).nozirText(.bodySmall, color: NozirColor.goodContent)
            case .conflict?:
                NozirInlineMessage(l10n.rulesConflictNotice)
            case nil:
                EmptyView()
            }
            if let message {
                NozirInlineMessage(message.text(l10n))
            }
            NozirButton(l10n.rulesActionSave, size: .callToAction, isLoading: isSaving, action: onSave)
                .disabled(!canSave && !isSaving)
        }
    }
}

/// A row that leads to another rules screen and states the rule as it stands.
/// Disabled (a frozen child) it still says what the rule is.
struct RuleLinkRow: View {
    private let title: String
    private let lines: [String]
    private let isEnabled: Bool
    private let action: () -> Void

    init(title: String, lines: [String], isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.lines = lines
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: NozirSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                Spacer(minLength: NozirSpacing.small)
                if isEnabled {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(NozirColor.textTertiary)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
```

- [ ] **Step 5: P09 bo'limi va hub ekrani**

`NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P09 for one child (Android `DailyLimitContent`): the limit, the trust
/// ladder, the notice, the other rules and "Saqlash"; or the state instead.
struct DailyLimitSection: View {
    private let model: DailyLimitModel
    private let onOpen: (RuleScreen) -> Void
    @Environment(\.l10n) private var l10n

    init(model: DailyLimitModel, onOpen: @escaping (RuleScreen) -> Void) {
        self.model = model
        self.onOpen = onOpen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            if let snapshot = model.session.snapshot, let values = model.values {
                if model.session.isOffline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                if model.session.isFrozen {
                    FrozenChildCard(isMakingActive: model.session.isMakingActive) {
                        Task { await model.session.makeActive() }
                    }
                    if let message = model.session.message {
                        NozirInlineMessage(message.text(l10n))
                    }
                }
                limitCard(values).disabled(model.session.isFrozen)
                trustCard(values).disabled(model.session.isFrozen)
                Text(RuleTexts.limitNotice(childName: model.session.childName, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
                otherRules(snapshot, isEnabled: !model.session.isFrozen)
                if !model.session.isFrozen {
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
                    }
                }
            } else if let failure = model.session.loadFailure {
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
    }

    private func limitCard(_ values: DailyLimitValues) -> some View {
        NozirCard {
            Text(l10n.dailyLimitTitle).nozirText(.titleSmall)
            RuleMinuteSlider(
                title: model.isSameEveryDay ? l10n.dailyLimitEveryDay : l10n.dailyLimitSchoolDays,
                caption: model.isSameEveryDay ? nil : l10n.dailyLimitSchoolDaysRange,
                value: Binding(get: { values.schoolDayMinutes }, set: { model.setSchoolDayMinutes($0) }),
                range: RuleMinuteRange.dailyLimit,
                accessibilityLabel: l10n.dailyLimitSliderSchool
            )
            Toggle(l10n.dailyLimitEveryDaySame, isOn: Binding(get: { model.isSameEveryDay }, set: { model.setSameEveryDay($0) }))
                .tint(NozirColor.primary)
            if !model.isSameEveryDay {
                RuleMinuteSlider(
                    title: l10n.dailyLimitWeekend,
                    caption: l10n.dailyLimitWeekendRange,
                    value: Binding(get: { values.weekendMinutes }, set: { model.setWeekendMinutes($0) }),
                    range: RuleMinuteRange.dailyLimit,
                    accessibilityLabel: l10n.dailyLimitSliderWeekend
                )
            }
            RuleRangeLabels()
        }
    }

    private func trustCard(_ values: DailyLimitValues) -> some View {
        NozirCard {
            RuleMinuteSlider(
                title: l10n.trustLadderTitle,
                caption: l10n.trustLadderSubtitle,
                value: Binding(get: { values.trustBonusMinutes }, set: { model.setTrustBonusMinutes($0) }),
                range: RuleMinuteRange.trustLadder,
                accessibilityLabel: l10n.trustLadderSlider,
                valueText: { RuleTexts.trustValue($0, l10n) }
            )
            Text(RuleTexts.trustNote(values.trustBonusMinutes, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }

    /// The way to P10, P12 and P12b. The apps row waits for 2c-2.
    private func otherRules(_ snapshot: RuleSnapshot, isEnabled: Bool) -> some View {
        let session = model.session
        return VStack(alignment: .leading, spacing: NozirSpacing.small) {
            NozirSectionTitle(l10n.rulesOtherLabel)
            NozirCard {
                RuleLinkRow(
                    title: l10n.rulesLinkBedtime,
                    lines: [
                        RuleTexts.bedtimeRange(snapshot.bedtime, l10n),
                        RuleDays.summary(Set(snapshot.bedtime.activeDays), l10n)
                    ],
                    isEnabled: isEnabled
                ) { onOpen(.bedtime(session)) }
                Divider()
                RuleLinkRow(title: l10n.rulesLinkBonus, lines: [RuleTexts.bonusRow(snapshot, l10n)], isEnabled: isEnabled) {
                    onOpen(.bonus(session))
                }
                Divider()
                RuleLinkRow(
                    title: l10n.rulesLinkLocation,
                    lines: [RuleTexts.locationRow(snapshot.locationTracking, l10n)],
                    isEnabled: isEnabled
                ) { onOpen(.locationTracking(session)) }
            }
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// A screen opened from P09, carrying P09's session so every save there moves
/// the one version all of the child's rules share.
enum RuleScreen: Hashable {
    case bedtime(ChildRulesSession)
    case bonus(ChildRulesSession)
    case locationTracking(ChildRulesSession)
}

/// P09 — the rules hub: the switcher (from Profile, 2+ children) and the
/// chosen child's daily limit.
struct RulesHubView: View {
    @State private var model: RulesHubModel
    private let onOpen: (RuleScreen) -> Void
    @Environment(\.l10n) private var l10n

    init(model: RulesHubModel, onOpen: @escaping (RuleScreen) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if model.showsSwitcher {
                    NozirChildSwitcher(
                        children: model.switcherChildren(l10n),
                        selection: Binding(get: { model.selectedChildId }, set: { model.select($0) }),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                }
                if let dailyLimit = model.dailyLimit {
                    DailyLimitSection(model: dailyLimit, onOpen: onOpen)
                } else {
                    NozirEmptyState(title: l10n.rulesNoChildTitle, message: l10n.rulesNoChildBody)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenDailyLimitTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once per child: a tab switch finds the session loaded and the edit untouched.
        .task(id: model.selectedChildId) { await model.load() }
        .refreshable { await model.session?.reload() }
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`, so'ng `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (`ChildDetailsModelTests` o'zgarishsiz), `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/RulesHubModel.swift NozirKit/Sources/NozirAppFeature/Rules/RuleTexts.swift NozirKit/Sources/NozirAppFeature/Screens/FrozenChildCard.swift NozirKit/Sources/NozirAppFeature/Screens/RuleSaveFooter.swift NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift NozirKit/Tests/NozirAppFeatureTests/RulesHubModelTests.swift
```

Xabar: `p09: the rules hub — one child at a time, the other rules one tap away`

---
### Task 6: P10 Uyqu vaqti — `BedtimeModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/BedtimeModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/BedtimeView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/BedtimeModelTests.swift`

**Interfaces:**
- Consumes: Task 2 `RuleDays.toggled`, `RuleTimePicker`, `RuleDaysSection`, `RuleWindDownSection`; Task 3 `ChildRulesSession`, `RuleNotice`, `RuleSaveOutcome`; Task 4 `DailyLimitModel` (Review Focus 2 testi); Task 5 `RuleSaveFooter`; `NozirBulletRow`.
- Produces:
  - `@MainActor @Observable final class BedtimeModel { static let defaultWindDownMinutes = 30; init(session: ChildRulesSession); let session; private(set) var edited: BedtimeSchedule?; editBase: BedtimeSchedule?; isSaving; message: UserMessage?; notice: RuleNotice?; var bedtime: BedtimeSchedule?; var isWindDownOn: Bool; var hasChange: Bool; var canSave: Bool; func load() async; setStart(_:), setEnd(_:), toggleDay(_:), setWindDown(on:), setWindDownMinutes(_:); func save() async }`
  - `BedtimeView(model: BedtimeModel)`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/BedtimeModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))

private func night(start: ClockTime = ClockTime(hour: 22, minute: 0), windDown: Int = 30, days: [Int] = [1, 2, 3, 4, 5, 6, 7]) -> BedtimeSchedule {
    BedtimeSchedule(start: start, end: ClockTime(hour: 7, minute: 0), windDownMinutes: windDown, activeDays: days)
}

@MainActor
private func setup(_ script: FakeFamily.Script) async -> (BedtimeModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = BedtimeModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct BedtimeModelTests {
    @Test func theWindowIsShownAndNothingIsSavedUntilItChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        #expect(model.bedtime == defaultBedtime)
        #expect(!model.canSave)

        model.setStart(ClockTime(hour: 21, minute: 30))

        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 30))
        #expect(model.canSave)
    }

    @Test func theLastNightCannotBeTurnedOff() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(days: [3])))]
        let (model, _, _) = await setup(script)

        model.toggleDay(3)
        #expect(model.bedtime?.activeDays == [3])
        #expect(!model.canSave)

        model.toggleDay(1)
        #expect(model.bedtime?.activeDays == [1, 3])
    }

    @Test func windDownComesBackAtItsOwnLength() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(windDown: 45)))]
        let (model, _, _) = await setup(script)

        model.setWindDown(on: false)
        #expect(model.bedtime?.windDownMinutes == 0)
        #expect(!model.isWindDownOn)

        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == 45)
    }

    @Test func windDownFirstTurnedOnIsThirty() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, bedtime: night(windDown: 0)))]
        let (model, _, _) = await setup(script)

        model.setWindDownMinutes(60)
        #expect(model.bedtime?.windDownMinutes == 0)

        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == BedtimeModel.defaultWindDownMinutes)

        model.setWindDownMinutes(15)
        model.setWindDown(on: false)
        model.setWindDown(on: true)
        #expect(model.bedtime?.windDownMinutes == 15)
    }

    @Test func savingNamesTheSessionVersionAndHandsTheAnswerBack() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let changed = night(start: ClockTime(hour: 21, minute: 0), days: [1, 2, 3, 4, 5])
        script.bedtime = [.success(snapshot(version: 5, bedtime: changed))]
        let (model, session, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))
        model.toggleDay(6)
        model.toggleDay(7)

        await model.save()

        #expect(await fake.bedtimeWrites == [RuleWrite(value: changed, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.bedtime == changed)
        #expect(!model.canSave)
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = night(start: ClockTime(hour: 20, minute: 30))
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 8, bedtime: elsewhere))]
        script.bedtime = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 8)
        #expect(model.bedtime == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.bedtimeWrites.count == 1)
    }

    @Test func aFailedSaveKeepsTheEditForAnotherTry() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bedtime = [.failure(.server(status: 500, error: ApiError(code: .internalError)))]
        let (model, _, _) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(model.message == .serverProblem)
        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 0))
        #expect(model.canSave)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.load()

        #expect(model.bedtime?.start == ClockTime(hour: 21, minute: 0))
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    // Review Focus 2.
    @Test func aBedtimeSaveDoesNotMakeTheOpenLimitEditConflict() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let later = night(start: ClockTime(hour: 21, minute: 30))
        script.bedtime = [.success(snapshot(version: 5, bedtime: later))]
        let limit = ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60)
        script.screenTime = [.success(snapshot(version: 6, limit: limit, bedtime: later))]
        let (bedtime, session, fake) = await setup(script)
        let dailyLimit = DailyLimitModel(session: session)
        dailyLimit.setSchoolDayMinutes(90)

        bedtime.setStart(ClockTime(hour: 21, minute: 30))
        await bedtime.save()
        await dailyLimit.save()

        #expect(bedtime.notice == .saved)
        #expect(dailyLimit.notice == .saved)
        #expect(await fake.bedtimeWrites.map(\.version) == [4])
        #expect(await fake.screenTimeWrites == [RuleWrite(value: limit, version: 5)])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(session.version == 6)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, _, fake) = await setup(script)
        model.setStart(ClockTime(hour: 21, minute: 0))

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.bedtimeWrites.isEmpty)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'BedtimeModel' in scope`.

- [ ] **Step 3: `BedtimeModel`**

`NozirKit/Sources/NozirAppFeature/Rules/BedtimeModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily

/// P10 (Android `BedtimeViewModel`): the night window, its nights, and the
/// warning before it. Only the edit lives here; the saved rule is the session's.
@MainActor
@Observable
final class BedtimeModel {
    /// The warning's length the first time it is switched on.
    static let defaultWindDownMinutes = 30

    let session: ChildRulesSession
    private(set) var edited: BedtimeSchedule?
    /// What the edit started from. A save checks it is still what the session holds.
    private(set) var editBase: BedtimeSchedule?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?
    /// The warning's length before it was switched off: on again gives the
    /// parent's own number back rather than a default they never chose.
    @ObservationIgnored private var lastWindDownMinutes: Int?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var bedtime: BedtimeSchedule? {
        edited ?? session.snapshot?.bedtime
    }

    var isWindDownOn: Bool {
        (bedtime?.windDownMinutes ?? 0) > 0
    }

    var hasChange: Bool {
        guard let edited, let editBase else { return false }
        return edited != editBase
    }

    var canSave: Bool {
        !isSaving && !session.isFrozen && session.version != nil && hasChange
    }

    func load() async {
        await session.load()
    }

    func setStart(_ time: ClockTime) {
        edit { $0.start = time }
    }

    func setEnd(_ time: ClockTime) {
        edit { $0.end = time }
    }

    /// The last night stays on.
    func toggleDay(_ day: Int) {
        edit { $0.activeDays = RuleDays.toggled(Set($0.activeDays), day).sorted() }
    }

    /// Off is 0, the only shape the child's phone understands.
    func setWindDown(on: Bool) {
        if on {
            let minutes = lastWindDownMinutes ?? Self.defaultWindDownMinutes
            edit { $0.windDownMinutes = minutes }
        } else {
            if let current = bedtime?.windDownMinutes, current > 0 {
                lastWindDownMinutes = current
            }
            edit { $0.windDownMinutes = 0 }
        }
    }

    func setWindDownMinutes(_ minutes: Int) {
        guard isWindDownOn else { return }
        lastWindDownMinutes = minutes
        edit { $0.windDownMinutes = minutes }
    }

    func save() async {
        guard canSave, let edited, let editBase, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Read again under this edit and changed elsewhere: never written over.
        guard held.bedtime == editBase else {
            discardEdit()
            notice = .conflict
            return
        }
        let service = session.family.service
        let childId = session.childId
        let version = held.version
        let outcome = await session.write { try await service.setBedtime(edited, of: childId, version: version) }
        switch outcome {
        case .saved:
            discardEdit()
            notice = .saved
        case .conflict:
            discardEdit()
            notice = .conflict
        case .failed(let failure):
            message = failure
        }
    }

    private func edit(_ change: (inout BedtimeSchedule) -> Void) {
        guard var copy = bedtime else { return }
        if edited == nil {
            editBase = session.snapshot?.bedtime
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/BedtimeView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P10 as Android `BedtimeContent`: the window, the nights, the warning, and
/// what keeps working at night (read only).
struct BedtimeView: View {
    @State private var model: BedtimeModel
    @Environment(\.l10n) private var l10n

    init(model: BedtimeModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let bedtime = model.bedtime {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    NozirCard {
                        HStack(spacing: NozirSpacing.medium) {
                            RuleTimePicker(l10n.bedtimeStartLabel, time: Binding(get: { bedtime.start }, set: { model.setStart($0) }))
                            RuleTimePicker(l10n.bedtimeEndLabel, time: Binding(get: { bedtime.end }, set: { model.setEnd($0) }))
                        }
                        Text(l10n.bedtimeLength(Durations.long(bedtime.lengthMinutes, l10n)))
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    NozirCard {
                        RuleDaysSection(activeDays: Set(bedtime.activeDays)) { model.toggleDay($0) }
                    }
                    NozirCard {
                        RuleWindDownSection(
                            minutes: bedtime.windDownMinutes,
                            onToggle: { model.setWindDown(on: $0) },
                            onMinutes: { model.setWindDownMinutes($0) }
                        )
                    }
                    allowlistCard
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
                    }
                } else if let failure = model.session.loadFailure {
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
        .navigationTitle(l10n.screenSleepTimeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    /// Android `BedtimeAllowlistCard`: fixed on the phone, nothing to edit.
    private var allowlistCard: some View {
        NozirCard {
            Text(l10n.bedtimeAllowlistLabel).nozirText(.titleSmall)
            NozirBulletRow(l10n.bedtimeAllowlistCalls)
            NozirBulletRow(l10n.bedtimeAllowlistSos)
            NozirBulletRow(l10n.bedtimeAllowlistParent)
            NozirBulletRow(l10n.bedtimeAllowlistAlarm)
        }
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/BedtimeModel.swift NozirKit/Sources/NozirAppFeature/Screens/BedtimeView.swift NozirKit/Tests/NozirAppFeatureTests/BedtimeModelTests.swift
```

Xabar: `p10: bedtime — the window, the nights, a warning that remembers its length`

---
### Task 7: P12 Bonus vaqt — `BonusModel`, matnlar va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/BonusTexts.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Rules/BonusModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/BonusView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/BonusModelTests.swift`

**Interfaces:**
- Consumes: Task 1 `BonusConfig`, `BonusChallenge`, `ChallengeKind`, `ChallengeDifficulty`, `FamilyService.bonus/setBonus`, `FakeFamily` (`bonus`, `setBonus`, `bonusWrites`, `mathTask`, `readingTask`, `exerciseTask`, `bonusConfig(version:ceiling:challenges:)`); Task 2 `RuleMinuteSlider`, `RuleMinuteRange.bonusCeiling`; Task 3 `ChildRulesSession` (`acceptBonus`, `reload`, `version`, `isFrozen`), `RuleNotice`; Task 4 `DailyLimitModel` (versiya zanjiri testi); Task 5 `RuleSaveFooter`.
- Produces:
  - `enum BonusTexts { static func ceilingValue(_ minutes: Int, _ l10n: L10n) -> String; static func ceilingNote(_ config: BonusConfig, _ l10n: L10n) -> String?; static func name(_ kind: ChallengeKind, _ l10n: L10n) -> String?; static func subtitle(_ challenge: BonusChallenge, _ l10n: L10n) -> String?; static func minutes(_ challenge: BonusChallenge, _ l10n: L10n) -> String; static func caption(childName: String?, _ l10n: L10n) -> String }`
  - `@MainActor @Observable final class BonusModel { init(session: ChildRulesSession); let session; private(set) var saved: BonusConfig?; edited: BonusConfig?; isLoading; loadFailure: UserMessage?; isSaving; message: UserMessage?; notice: RuleNotice?; var config: BonusConfig?; var visibleChallenges: [BonusChallenge]; var canSave: Bool; func load() async; func setCeiling(_:); func setEnabled(_ id: UUID, _ enabled: Bool); func save() async }`
  - `BonusView(model: BonusModel)`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/BonusModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let chess = BonusChallenge(id: UUID(), kind: .unknown("CHESS"), difficulty: .easy, bonusMinutes: 10, requiresParentApproval: false, enabled: true)

@MainActor
private func setup(_ script: FakeFamily.Script) async -> (BonusModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    let model = BonusModel(session: session)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct BonusModelTests {
    @Test func theTasksAreReadAndNothingIsSavedUntilSomethingChanges() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        let (model, _, _) = await setup(script)

        #expect(model.config?.maxDailyBonusMinutes == 60)
        #expect(model.visibleChallenges.map(\.id) == [mathTask.id, readingTask.id, exerciseTask.id])
        #expect(!model.canSave)
    }

    @Test func aToggleChangesOnlyThatTasksSwitch() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        let (model, _, _) = await setup(script)

        model.setEnabled(readingTask.id, true)

        #expect(model.config?.challenges.map(\.enabled) == [true, true, true])
        #expect(model.config?.challenges[1].bonusMinutes == readingTask.bonusMinutes)
        #expect(model.canSave)

        model.setEnabled(readingTask.id, false)
        #expect(!model.canSave)
    }

    @Test func savingSendsTheWholeConfigOnTheSessionVersionAndMovesTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        script.setBonus = [.success(bonusConfig(version: 5, ceiling: 30, challenges: [mathTask, readingTask, exerciseTask, chess]))]
        let (model, session, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(await fake.bonusWrites == [RuleWrite(value: bonusConfig(version: 4, ceiling: 30, challenges: [mathTask, readingTask, exerciseTask, chess]), version: 4)])
        #expect(session.version == 5)
        #expect(session.snapshot?.screenTime.maxDailyBonusMinutes == 30)
        #expect(model.notice == .saved)
        #expect(model.config?.maxDailyBonusMinutes == 30)
        #expect(!model.canSave)
    }

    @Test func theLimitSavedAfterwardsNamesTheVersionTheBonusLeft() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        script.setBonus = [.success(bonusConfig(version: 5, ceiling: 30))]
        script.screenTime = [.success(snapshot(version: 6))]
        let (bonus, session, fake) = await setup(script)
        let dailyLimit = DailyLimitModel(session: session)
        dailyLimit.setSchoolDayMinutes(90)
        bonus.setCeiling(30)

        await bonus.save()
        await dailyLimit.save()

        #expect(dailyLimit.notice == .saved)
        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 30), version: 5)])
    }

    @Test func aConflictReadsBothAgainAndDoesNotResend() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 7, limit: ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 90)))]
        script.bonus = [.success(bonusConfig(version: 4)), .success(bonusConfig(version: 7, ceiling: 90))]
        script.setBonus = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 7)
        #expect(model.config?.maxDailyBonusMinutes == 90)
        #expect(!model.canSave)
        #expect(await fake.bonusWrites.count == 1)
        #expect(await fake.calls.filter { $0 == "bonus" }.count == 2)
    }

    @Test func aRefusedSaveKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4))]
        script.setBonus = [.failure(.server(status: 403, error: ApiError(code: .childNotActive)))]
        let (model, session, _) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(model.message == .childNotActive)
        #expect(model.config?.maxDailyBonusMinutes == 30)
        #expect(model.canSave)
        #expect(session.version == 4)
    }

    // Review Focus 4.
    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.success(bonusConfig(version: 4)), .success(bonusConfig(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setCeiling(90)

        await model.load()

        #expect(model.config?.maxDailyBonusMinutes == 90)
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "bonus" }.count == 1)
    }

    @Test func aConfigThatCannotBeReadCanBeRetried() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.bonus = [.failure(offline), .success(bonusConfig(version: 4))]
        let (model, _, _) = await setup(script)
        #expect(model.config == nil)
        #expect(model.loadFailure == .noConnection)

        await model.load()

        #expect(model.config != nil)
        #expect(model.loadFailure == nil)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.bonus = [.success(bonusConfig(version: 4))]
        let (model, _, fake) = await setup(script)
        model.setCeiling(30)

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.bonusWrites.isEmpty)
    }
}

@Suite struct BonusTextsTests {
    private let l10n = L10n(.uz)

    @Test func zeroSaysTasksPayNothing() {
        #expect(BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 0), l10n) == l10n.bonusCeilingZero)
    }

    @Test func aCeilingBelowTheTasksSaysWhereItStopsThem() {
        // Enabled: math 20 + exercise 30 = 50.
        let note = BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 45), l10n)

        #expect(note == l10n.bonusCeilingBinding(Durations.short(50, l10n), Durations.short(45, l10n)))
        #expect(BonusTexts.ceilingNote(bonusConfig(version: 1, ceiling: 60), l10n) == nil)
    }

    @Test func aTaskIsNamedWithItsDifficultyAndWhoApprovesIt() {
        #expect(BonusTexts.name(.math, l10n) == l10n.bonusChallengeMath)
        #expect(BonusTexts.name(.unknown("CHESS"), l10n) == nil)
        #expect(BonusTexts.subtitle(mathTask, l10n) == l10n.bonusChallengeMedium)
        #expect(BonusTexts.subtitle(exerciseTask, l10n) == l10n.bonusChallengeSubtitle(l10n.bonusChallengeHard))
        #expect(BonusTexts.minutes(exerciseTask, l10n) == l10n.bonusChallengeMinutes(Durations.short(30, l10n)))
        #expect(BonusTexts.ceilingValue(60, l10n) == l10n.bonusCeilingValue(Durations.short(60, l10n)))
        #expect(BonusTexts.caption(childName: "Ali", l10n) == l10n.bonusCaptionNamed("Ali"))
        #expect(BonusTexts.caption(childName: nil, l10n) == l10n.bonusCaption)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'BonusModel' in scope`, `cannot find 'BonusTexts' in scope`.

- [ ] **Step 3: Matnlar**

`NozirKit/Sources/NozirAppFeature/Rules/BonusTexts.swift`:

```swift
import Foundation
import NozirFamily
import NozirL10n

/// P12's words (Android `BonusCeilingCard`, `BonusChallengeRow`, `ChallengeLabel`).
/// The names are the app's, not the server's: a kind added later has none.
enum BonusTexts {
    static func ceilingValue(_ minutes: Int, _ l10n: L10n) -> String {
        l10n.bonusCeilingValue(Durations.short(minutes, l10n))
    }

    /// Under the slider: zero turns task time off; a ceiling below what the
    /// enabled tasks pay says where it stops them. Otherwise nothing.
    static func ceilingNote(_ config: BonusConfig, _ l10n: L10n) -> String? {
        if config.maxDailyBonusMinutes == 0 { return l10n.bonusCeilingZero }
        guard config.isCeilingBinding else { return nil }
        return l10n.bonusCeilingBinding(
            Durations.short(config.earnableMinutes, l10n),
            Durations.short(config.maxDailyBonusMinutes, l10n)
        )
    }

    static func name(_ kind: ChallengeKind, _ l10n: L10n) -> String? {
        switch kind {
        case .math: l10n.bonusChallengeMath
        case .reading: l10n.bonusChallengeReading
        case .english: l10n.bonusChallengeEnglish
        case .exercise: l10n.bonusChallengeExercise
        case .unknown: nil
        }
    }

    /// "O'rtacha", or "Qiyin · Siz tasdiqlaysiz" when nothing can measure it.
    static func subtitle(_ challenge: BonusChallenge, _ l10n: L10n) -> String? {
        let hardness: String?
        switch challenge.difficulty {
        case .easy: hardness = l10n.bonusChallengeEasy
        case .medium: hardness = l10n.bonusChallengeMedium
        case .hard: hardness = l10n.bonusChallengeHard
        case .unknown: hardness = nil
        }
        guard let hardness else { return nil }
        return challenge.requiresParentApproval ? l10n.bonusChallengeSubtitle(hardness) : hardness
    }

    static func minutes(_ challenge: BonusChallenge, _ l10n: L10n) -> String {
        l10n.bonusChallengeMinutes(Durations.short(challenge.bonusMinutes, l10n))
    }

    static func caption(childName: String?, _ l10n: L10n) -> String {
        childName.map(l10n.bonusCaptionNamed) ?? l10n.bonusCaption
    }
}
```

- [ ] **Step 4: `BonusModel`**

`NozirKit/Sources/NozirAppFeature/Rules/BonusModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily

/// P12 (Android `BonusViewModel`): the daily ceiling and which tasks are on.
/// The ceiling lives in the rule set, so the whole configuration is written
/// against the session's version and the answer moves the session.
@MainActor
@Observable
final class BonusModel {
    let session: ChildRulesSession
    /// The configuration as the server last stated it.
    private(set) var saved: BonusConfig?
    /// The parent's edit on top; nil while nothing has been touched.
    private(set) var edited: BonusConfig?
    private(set) var isLoading = false
    private(set) var loadFailure: UserMessage?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession) {
        self.session = session
    }

    var config: BonusConfig? {
        edited ?? saved
    }

    /// A kind this app has no name for is kept and sent back, but not drawn.
    var visibleChallenges: [BonusChallenge] {
        (config?.challenges ?? []).filter { challenge in
            if case .unknown = challenge.kind { return false }
            return true
        }
    }

    var canSave: Bool {
        guard !isSaving, !session.isFrozen, session.version != nil, let edited else { return false }
        return edited != saved
    }

    /// Reads once: a tab switch must not throw an edit away.
    func load() async {
        await session.load()
        guard saved == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            saved = try await session.family.service.bonus(of: session.childId)
            loadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            loadFailure = UserMessage(error)
        }
    }

    func setCeiling(_ minutes: Int) {
        edit { $0.maxDailyBonusMinutes = minutes }
    }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        edit { $0 = $0.withChallenge(id, enabled: enabled) }
    }

    /// One call for the ceiling and the tasks: sent apart, the child's phone
    /// would see a moment where a task pays above a ceiling just lowered.
    func save() async {
        guard canSave, let edited, let version = session.version else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        let service = session.family.service
        let childId = session.childId
        do {
            let answer = try await service.setBonus(edited, of: childId, version: version)
            session.acceptBonus(version: answer.ruleVersion, ceiling: answer.maxDailyBonusMinutes)
            saved = answer
            self.edited = nil
            notice = .saved
        } catch {
            let failure = UserMessage(error)
            guard failure == .conflict else {
                message = failure
                return
            }
            // The rules moved under this screen: drop the edit, read both again, never resend.
            self.edited = nil
            await session.reload()
            if let fresh = try? await service.bonus(of: childId) {
                saved = fresh
            }
            notice = .conflict
        }
    }

    private func edit(_ change: (inout BonusConfig) -> Void) {
        guard var copy = config else { return }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }
}
```

- [ ] **Step 5: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/BonusView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P12 as Android `BonusContent`: the ceiling at the top, then the tasks with
/// a switch each.
struct BonusView: View {
    @State private var model: BonusModel
    @Environment(\.l10n) private var l10n

    init(model: BonusModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(BonusTexts.caption(childName: model.session.childName, l10n))
                    .nozirText(.body, color: NozirColor.textSecondary)
                if let config = model.config {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    ceilingCard(config)
                    NozirSectionTitle(l10n.bonusChallengesLabel)
                    if model.visibleChallenges.isEmpty {
                        NozirEmptyState(title: l10n.bonusEmptyTitle, message: l10n.bonusEmptyBody)
                    } else {
                        NozirCard {
                            ForEach(Array(model.visibleChallenges.enumerated()), id: \.element.id) { position, challenge in
                                if position > 0 { Divider() }
                                challengeRow(challenge)
                            }
                        }
                    }
                    RuleSaveFooter(
                        notice: model.notice,
                        message: model.message,
                        childName: model.session.childName,
                        isSaving: model.isSaving,
                        canSave: model.canSave
                    ) {
                        Task { await model.save() }
                    }
                } else if let failure = model.loadFailure ?? model.session.loadFailure {
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
        .navigationTitle(l10n.screenBonusTimeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    private func ceilingCard(_ config: BonusConfig) -> some View {
        NozirCard {
            RuleMinuteSlider(
                title: l10n.bonusCeilingTitle,
                caption: l10n.bonusCeilingSubtitle,
                value: Binding(get: { config.maxDailyBonusMinutes }, set: { model.setCeiling($0) }),
                range: RuleMinuteRange.bonusCeiling,
                accessibilityLabel: l10n.bonusCeilingSlider,
                valueText: { BonusTexts.ceilingValue($0, l10n) }
            )
            if let note = BonusTexts.ceilingNote(config, l10n) {
                Text(note).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
        }
    }

    private func challengeRow(_ challenge: BonusChallenge) -> some View {
        let name = BonusTexts.name(challenge.kind, l10n) ?? ""
        return HStack(spacing: NozirSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).nozirText(.body)
                if let subtitle = BonusTexts.subtitle(challenge, l10n) {
                    Text(subtitle).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            Spacer(minLength: NozirSpacing.small)
            Text(BonusTexts.minutes(challenge, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
            Toggle(l10n.bonusChallengeToggle(name), isOn: Binding(get: { challenge.enabled }, set: { model.setEnabled(challenge.id, $0) }))
                .labelsHidden()
                .tint(NozirColor.primary)
        }
        .frame(minHeight: NozirSize.control)
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/BonusTexts.swift NozirKit/Sources/NozirAppFeature/Rules/BonusModel.swift NozirKit/Sources/NozirAppFeature/Screens/BonusView.swift NozirKit/Tests/NozirAppFeatureTests/BonusModelTests.swift
```

Xabar: `p12: bonus time — the ceiling and the tasks, saved whole on the shared version`

---
### Task 8: P12b hub'dan — sessiyali `LocationTrackingModel`

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift` (butunlay almashtiriladi)
- Test: `NozirKit/Tests/NozirAppFeatureTests/LocationTrackingSessionTests.swift` (yangi; `LocationTrackingModelTests.swift` ga tegilmaydi)

**Interfaces:**
- Consumes: Task 3 `ChildRulesSession` (`load`, `snapshot`, `version`, `loadFailure`, `write`), `RuleSaveOutcome`; mavjud `LocationTrackingModel.Notice`.
- Produces: `LocationTrackingModel.init(childId: UUID, childName: String?, family: FamilyStore, session: ChildRulesSession? = nil)`. Sessiyasiz yo'l avvalgidek; sessiya bilan — qoida sessiyadan o'qiladi, yozuv `session.version` bilan, javob `session.accept` ga (`session.write` orqali), to'qnashuvda sessiya qayta o'qiladi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/LocationTrackingSessionTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let every15 = LocationTracking(isEnabled: true, intervalMinutes: 15, zoneIntervalMinutes: 3, moveMetres: 100)
private let every30 = LocationTracking(isEnabled: true, intervalMinutes: 30, zoneIntervalMinutes: 3, moveMetres: 100)

/// P12b opened from the hub: the session is already loaded, as P09 leaves it.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (LocationTrackingModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    await session.load()
    let model = LocationTrackingModel(childId: ali.id, childName: "Ali", family: family, session: session)
    return (model, session, fake)
}

@MainActor
@Suite struct LocationTrackingSessionTests {
    @Test func theRuleComesFromTheSessionWithoutAskingAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 4, tracking: every15))]
        let (model, _, fake) = await setup(script)

        await model.load()

        #expect(model.tracking == every15)
        #expect(!model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aSessionThatCouldNotReadShowsWhy() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .failure(offline)]
        let (model, _, _) = await setup(script)

        await model.load()

        #expect(model.tracking == nil)
        #expect(model.loadFailure == .noConnection)
    }

    @Test func aSaveGoesBackToTheSession() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.success(snapshot(version: 5, tracking: every30))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(await fake.locationTrackingWrites == [RuleWrite(value: every30, version: 4)])
        #expect(session.version == 5)
        #expect(session.snapshot?.locationTracking == every30)
        #expect(model.notice == .saved)
        #expect(!model.canSave)
    }

    @Test func itWritesOnTheVersionAnotherScreenLeft() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, tracking: every15))]
        script.locationTracking = [.success(snapshot(version: 6, tracking: every30))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)
        session.accept(snapshot(version: 5, limit: ScreenTimeLimit(schoolDayMinutes: 60, weekendMinutes: 60, maxDailyBonusMinutes: 60), tracking: every15))

        await model.save()

        #expect(await fake.locationTrackingWrites.map(\.version) == [5])
        #expect(model.notice == .saved)
    }

    @Test func aConflictReloadsTheSessionAndDoesNotResend() async {
        var script = FakeFamily.Script()
        let elsewhere = LocationTracking(isEnabled: false, intervalMinutes: 10, zoneIntervalMinutes: 3, moveMetres: 100)
        script.rules = [.success(snapshot(version: 4, tracking: every15)), .success(snapshot(version: 7, tracking: elsewhere))]
        script.locationTracking = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, session, fake) = await setup(script)
        await model.load()
        model.setInterval(30)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(model.tracking == elsewhere)
        #expect(session.version == 7)
        #expect(!model.canSave)
        #expect(await fake.locationTrackingWrites.count == 1)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `extra argument 'session' in call`.

- [ ] **Step 3: `LocationTrackingModel`**

`NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift` — faylni butunlay almashtiring (sessiyasiz yo'l satrma-satr avvalgidek):

```swift
import Foundation
import Observation
import NozirFamily
import NozirNetworking

/// P12b: how often the child's phone reports unasked. Written with the
/// version it was read at; a version that moved meanwhile is re-read and the
/// parent is told — the change is never resent on their behalf.
///
/// Opened from the rules hub it works on the hub's session: the rule is read
/// from it, written against its version, and the answer goes back to it.
/// From the Location tab (no session) it reads and writes on its own.
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
    private let session: ChildRulesSession?
    @ObservationIgnored private var saved: LocationTracking?
    @ObservationIgnored private var version: Int64?

    init(childId: UUID, childName: String?, family: FamilyStore, session: ChildRulesSession? = nil) {
        self.childId = childId
        self.childName = childName
        self.family = family
        self.session = session
    }

    /// A repeated `.task` (a tab switch) must not overwrite edits in progress:
    /// only a load that has not produced a rule yet may run again (the retry).
    func load() async {
        guard tracking == nil else { return }
        isLoading = true
        defer { isLoading = false }
        if let session {
            await session.load()
            if let snapshot = session.snapshot {
                accept(snapshot)
                loadFailure = nil
            } else {
                loadFailure = session.loadFailure
            }
            return
        }
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
        if let session {
            await save(tracking, through: session)
            return
        }
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

    /// The session's version, which another screen of the hub may have moved.
    /// A tracking rule changed under the edit is shown, not written over.
    private func save(_ tracking: LocationTracking, through session: ChildRulesSession) async {
        guard let held = session.snapshot else { return }
        guard held.locationTracking == saved else {
            accept(held)
            notice = .conflict
            return
        }
        let service = family.service
        let childId = self.childId
        let version = held.version
        let outcome = await session.write { try await service.setLocationTracking(tracking, of: childId, version: version) }
        switch outcome {
        case .saved:
            if let snapshot = session.snapshot { accept(snapshot) }
            notice = .saved
        case .conflict:
            if let snapshot = session.snapshot { accept(snapshot) }
            notice = .conflict
        case .failed(let failure):
            message = failure
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

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **` — `LocationTrackingModelTests` o'zgarishsiz, `LocationTrackingSessionTests` yangi.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Location/LocationTrackingModel.swift NozirKit/Tests/NozirAppFeatureTests/LocationTrackingSessionTests.swift
```

Xabar: `p12b: from the hub it writes on the hub's session`

---
### Task 9: Ulash — fabrikalar, Profil va P03 qatorlari, navigatsiya

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift` (`showsRules`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (butunlay almashtiriladi)
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`

**Interfaces:**
- Consumes: Task 3–8 turlari: `ChildRulesSession(childId:family:)`, `DailyLimitModel(session:)`, `BedtimeModel(session:)`, `BonusModel(session:)`, `LocationTrackingModel(childId:childName:family:session:)`, `RulesHubModel(childId:picksChild:family:makeSession:makeDailyLimit:)`, `RuleScreen`, `RulesHubView`, `BedtimeView`, `BonusView`.
- Produces:
  - `SignedInModel`: `makeRulesSession(childId: UUID) -> ChildRulesSession`, `makeDailyLimitModel(session:) -> DailyLimitModel`, `makeBedtimeModel(session:) -> BedtimeModel`, `makeBonusModel(session:) -> BonusModel`, `makeLocationTrackingModel(session:) -> LocationTrackingModel`, `makeRulesHubModel(childId: UUID?, picksChild: Bool) -> RulesHubModel`.
  - `ProfileModel.showsRules: Bool`.
  - `ProfileView(model:onAddChild:onOpenChild:onPair:onOpenRules:)`, `ChildDetailsView(model:onRemoved:onOpenRules:)`.
  - `SignedInView.HomeStep.rules(UUID)`, `.ruleScreen(RuleScreen)`; `ProfileStep.rules(UUID?)`, `.childRules(UUID)`, `.ruleScreen(RuleScreen)`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — suite oxiriga (yopuvchi `}` dan oldin):

```swift
    @Test func theRulesScreensShareTheHubsSession() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.children = [.success([ali, makeChild("Vali")])]
        let (model, _) = setup(script)
        try? await model.family.refresh()

        let session = model.makeRulesSession(childId: ali.id)

        #expect(session.childId == ali.id)
        #expect(session.childName == "Ali")
        #expect(model.makeDailyLimitModel(session: session).session === session)
        #expect(model.makeBedtimeModel(session: session).session === session)
        #expect(model.makeBonusModel(session: session).session === session)
        let tracking = model.makeLocationTrackingModel(session: session)
        #expect(tracking.childId == ali.id)
        #expect(tracking.childName == "Ali")
    }

    @Test func theProfileHubOpensOnTheFirstChildAndCanSwitch() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.children = [.success([ali, makeChild("Vali")])]
        let (model, _) = setup(script)
        try? await model.family.refresh()

        let hub = model.makeRulesHubModel(childId: nil, picksChild: true)

        #expect(hub.selectedChildId == ali.id)
        #expect(hub.showsSwitcher)
        #expect(hub.dailyLimit?.session === hub.session)
    }

    @Test func aChildsDetailsHubIsForThatChildOnly() async {
        let vali = makeChild("Vali")
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali"), vali])]
        let (model, _) = setup(script)
        try? await model.family.refresh()

        let hub = model.makeRulesHubModel(childId: vali.id, picksChild: false)

        #expect(hub.selectedChildId == vali.id)
        #expect(!hub.showsSwitcher)
    }

    @Test func theProfileShowsRulesOnlyWithAChild() async {
        var script = FakeFamily.Script()
        script.children = [.success([]), .success([makeChild("Ali")])]
        let (model, _) = setup(script)
        let profile = model.makeProfileModel()

        try? await model.family.refresh()
        #expect(!profile.showsRules)

        try? await model.family.refresh()
        #expect(profile.showsRules)
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `value of type 'SignedInModel' has no member 'makeRulesSession'`.

- [ ] **Step 3: Fabrikalar va `showsRules`**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — `makeLocationTrackingModel(childId:)` funksiyasidan keyin:

```swift
    /// One per hub: P09 and every screen opened from it write on its version.
    func makeRulesSession(childId: UUID) -> ChildRulesSession {
        ChildRulesSession(childId: childId, family: family)
    }

    func makeDailyLimitModel(session: ChildRulesSession) -> DailyLimitModel {
        DailyLimitModel(session: session)
    }

    func makeBedtimeModel(session: ChildRulesSession) -> BedtimeModel {
        BedtimeModel(session: session)
    }

    func makeBonusModel(session: ChildRulesSession) -> BonusModel {
        BonusModel(session: session)
    }

    func makeLocationTrackingModel(session: ChildRulesSession) -> LocationTrackingModel {
        LocationTrackingModel(childId: session.childId, childName: session.childName, family: family, session: session)
    }

    /// From Profile: `childId` nil (the first child) and the switcher. From P03: that child, no switcher.
    func makeRulesHubModel(childId: UUID?, picksChild: Bool) -> RulesHubModel {
        let store = self.family
        return RulesHubModel(
            childId: childId,
            picksChild: picksChild,
            family: store,
            makeSession: { ChildRulesSession(childId: $0, family: store) },
            makeDailyLimit: { DailyLimitModel(session: $0) }
        )
    }
```

`NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift` — `init` dan keyin:

```swift
    /// The rules row is for a family with a child to set rules for.
    var showsRules: Bool {
        !family.children.isEmpty
    }
```

- [ ] **Step 4: Profil va P03 qatorlari**

`NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`:
- `private let onPair: (Child) -> Void` dan keyin: `private let onOpenRules: () -> Void`
- `init` ni almashtiring:

```swift
    init(
        model: ProfileModel,
        onAddChild: @escaping () -> Void,
        onOpenChild: @escaping (Child) -> Void,
        onPair: @escaping (Child) -> Void,
        onOpenRules: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.onAddChild = onAddChild
        self.onOpenChild = onOpenChild
        self.onPair = onPair
        self.onOpenRules = onOpenRules
    }
```

- "Mening oilam" kartasi (`Button(action: onAddChild)` bilan tugaydigan `NozirCard`) dan keyin, `NozirSectionTitle(l10n.profileSectionSettings)` dan oldin:

```swift
                if model.showsRules {
                    NozirCard {
                        NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                    }
                }
```

`NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`:
- `private let onRemoved: () -> Void` dan keyin: `private let onOpenRules: () -> Void`
- `init` ni almashtiring:

```swift
    init(model: ChildDetailsModel, onRemoved: @escaping () -> Void, onOpenRules: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onRemoved = onRemoved
        self.onOpenRules = onOpenRules
    }
```

- `body` dagi `form` qatoridan keyin (xabar va "Saqlash" dan oldin) — muzlatilgan bolada ham ochiladi:

```swift
                NozirCard {
                    NozirSettingsRow(l10n.profileRowRules, action: onOpenRules)
                }
```

- [ ] **Step 5: `SignedInView`**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — faylni butunlay almashtiring:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirLocation

/// The signed-in app: Home, Statistics, Location and Profile.
struct SignedInView: View {
    enum HomeStep: Hashable {
        case summary(UUID, String)
        case weekly(UUID)
        case apps(UUID)
        case details(Child)
        case sos(ActiveSos)
        /// P09 from P03: that child, no switcher.
        case rules(UUID)
        case ruleScreen(RuleScreen)
    }

    enum StatisticsStep: Hashable {
        case apps(UUID)
    }

    enum LocationStep: Hashable {
        /// A child's zone to edit, or nil for a new one.
        case zone(UUID, UUID?)
        case tracking(UUID)
    }

    enum ProfileStep: Hashable {
        case child(Child)
        case pairing(Child)
        /// P09 from the Profile row: nil opens on the first child, with the switcher.
        case rules(UUID?)
        /// P09 from P03 opened in this tab: that child, no switcher.
        case childRules(UUID)
        case ruleScreen(RuleScreen)
    }

    @State private var model: SignedInModel
    @State private var homePath: [HomeStep] = []
    @State private var statisticsPath: [StatisticsStep] = []
    @State private var locationPath: [LocationStep] = []
    @State private var profilePath: [ProfileStep] = []
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase

    init(model: SignedInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack(path: $homePath) {
                HomeView(
                    model: model.makeHomeModel(),
                    reloadToken: model.homeRefresh,
                    emergencyNumber: { model.currentEmergencyNumber },
                    onOpenSummary: { homePath.append(.summary($0, $1)) },
                    onOpenSos: { homePath.append(.sos($0)) },
                    onAddChild: { model.presentAddChild() }
                )
                .navigationDestination(for: HomeStep.self) { step in
                    homeDestination(step)
                }
            }
            .tabItem { Label(l10n.tabHome, systemImage: "house") }
            .tag(SignedInModel.Tab.home)

            NavigationStack(path: $statisticsPath) {
                StatisticsView(
                    statistics: model.statistics,
                    makeWeekly: { model.makeWeeklyModel(childId: $0) },
                    onAddChild: { model.presentAddChild() },
                    onOpenApps: { statisticsPath.append(.apps($0)) }
                )
                .navigationDestination(for: StatisticsStep.self) { step in
                    switch step {
                    case .apps(let childId):
                        AppUsageView(model: model.makeAppUsageModel(childId: childId))
                    }
                }
            }
            .tabItem { Label(l10n.tabStatistics, systemImage: "chart.bar") }
            .tag(SignedInModel.Tab.statistics)

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

            NavigationStack(path: $profilePath) {
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) },
                    onOpenRules: { profilePath.append(.rules(nil)) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    profileDestination(step)
                }
            }
            .tabItem { Label(l10n.tabProfile, systemImage: "person.crop.circle") }
            .tag(SignedInModel.Tab.profile)
        }
        .tint(NozirColor.primary)
        .fullScreenCover(isPresented: $model.isAddingChild) {
            AddChildFlow(model: model, onClose: {
                clearPaths()
                model.finishAddChild()
            })
                // Said again for the cover, so it cannot fall back to the defaults.
                .environment(\.l10n, l10n)
                .environment(\.locale, locale)
        }
        .task(id: scenePhase == .active) { if scenePhase == .active { await model.start() } }
    }

    private func clearPaths() {
        homePath.removeAll()
        statisticsPath.removeAll()
        locationPath.removeAll()
        profilePath.removeAll()
    }

    @ViewBuilder
    private func homeDestination(_ step: HomeStep) -> some View {
        switch step {
        case .summary(let childId, let childName):
            DailySummaryView(
                model: model.makeDailySummaryModel(childId: childId, childName: childName),
                onEditChild: {
                    if let child = model.family.child(childId) {
                        homePath.append(.details(child))
                    }
                },
                onOpenWeekly: { homePath.append(.weekly(childId)) }
            )
        case .weekly(let childId):
            WeeklyReportView(
                model: model.makeWeeklyModel(childId: childId),
                switcher: nil,
                onOpenApps: { homePath.append(.apps($0)) }
            )
        case .apps(let childId):
            AppUsageView(model: model.makeAppUsageModel(childId: childId))
        case .details(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { homePath.append(.rules(child.id)) }
            )
        case .sos(let seed):
            SosDetailView(model: model.makeSosDetailModel(
                seed: seed,
                emergencyNumber: SosDetailModel.dialNumber(configured: model.currentEmergencyNumber, fallback: l10n.sosEmergencyNumber)
            ))
        case .rules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: false),
                onOpen: { homePath.append(.ruleScreen($0)) }
            )
        case .ruleScreen(let screen):
            ruleDestination(screen)
        }
    }

    @ViewBuilder
    private func profileDestination(_ step: ProfileStep) -> some View {
        switch step {
        case .child(let child):
            ChildDetailsView(
                model: model.makeDetailsModel(child),
                onRemoved: { clearPaths() },
                onOpenRules: { profilePath.append(.childRules(child.id)) }
            )
        case .pairing(let child):
            PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
        case .rules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: true),
                onOpen: { profilePath.append(.ruleScreen($0)) }
            )
        case .childRules(let childId):
            RulesHubView(
                model: model.makeRulesHubModel(childId: childId, picksChild: false),
                onOpen: { profilePath.append(.ruleScreen($0)) }
            )
        case .ruleScreen(let screen):
            ruleDestination(screen)
        }
    }

    /// P10, P12 and P12b on the session of the hub that opened them.
    @ViewBuilder
    private func ruleDestination(_ screen: RuleScreen) -> some View {
        switch screen {
        case .bedtime(let session):
            BedtimeView(model: model.makeBedtimeModel(session: session))
        case .bonus(let session):
            BonusView(model: model.makeBonusModel(session: session))
        case .locationTracking(let session):
            LocationTrackingView(model: model.makeLocationTrackingModel(session: session))
        }
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`, so'ng `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `grep -rn "frozenCard" NozirKit/Sources` — hech narsa.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
```

Xabar: `rules: reached from Profile and from a child's details`

---
### Task 10: Oxirgi tekshiruv — butun to'plam, l10n va E2E

**Files:** (kod o'zgarmaydi; topilgan xatolar alohida TDD sikli bilan tuzatiladi)

- [ ] **Step 1: Butun to'plam**

Run: `python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, keyin `bash .superpowers/run.sh all 170` va `bash .superpowers/run.sh app 170`.
Expected: Python OK, `up to date` (yangi kalit qo'shilmagan), `** TEST SUCCEEDED **` (`NozirFamilyTests` va `NozirAppFeatureTests` ichida yangi testlar bilan), `** BUILD SUCCEEDED **`; `git diff --stat 7792de6 -- NozirKit/l10n` — bo'sh.

- [ ] **Step 2: E2E (foydalanuvchi; simulyator + haqiqiy bola telefoni + Android ota-ona ilovasi + haqiqiy backend)**

Har bir bandga "ha" yoki kuzatilgan holat yoziladi:

1. Profil: bola bo'lsa "Mening oilam" kartasidan keyin "Qoidalar" qatori bor; bolasiz akkauntda yo'q. Qator → P09 birinchi bola bilan; 2+ bolada tepada tanlagich, 1 bolada yo'q.
2. P03 (Home → kunlik xulosa → tahrirlash, va Profil → bola): forma va "Saqlash" orasida "Qoidalar" qatori → P09 shu bola uchun, tanlagichsiz.
3. P09: o'qish kuni slayderi 30d–6s, qadam 15; "Har kuni bir xil" yoqilganda dam olish kuni slayderi yo'qoladi va o'qish kuni qiymatini oladi; o'chirilganda alohida slayder qaytadi. Zinapoya 0 da "Oʻchiq" va o'chiq izohi; 15+ da "+N" va pog'onalar izohi. Eslatma matni bola ismi bilan. O'zgarishsiz "Saqlash" o'chiq.
4. P09 da faqat limitni, faqat zinapoyani, ikkalasini o'zgartirib saqlash → "Saqlandi. {Ism} telefoni…"; bola telefoni keyingi aloqada yangi limitni oladi; Android ota-ona ilovasidagi P09 da ham shu qiymatlar.
5. "Boshqa qoidalar": Uyqu vaqti (vaqt oralig'i + kunlar), Bonus vaqt ("Kuniga … gacha"), Joylashuv ("Har N daqiqada" yoki o'chiq matni); Ilovalar qatori yo'q.
6. P10: vaqtlar, uzunlik matni; kunlarni o'chirib oxirgisida to'xtash va izoh; Wind Down o'chirib-yoqish oldingi uzunlikni qaytaradi; saqlash → P09 qatori yangilanadi; bola telefonida yangi uyqu oynasi.
7. P12: maksimum 0 da "nol" izohi; vazifalar yig'indisidan past maksimumda "to'xtatadi" izohi; vazifa kaliti; saqlash → P09 dagi Bonus qatori yangi maksimumni ko'rsatadi; bola ilovasida vazifalar ro'yxati o'zgaradi.
8. P12b hub'dan: o'zgartirib saqlash → P09 Joylashuv qatori yangilanadi; keyin P09 da limitni saqlash to'qnashuvsiz o'tadi (umumiy versiya).
9. P09 da limitni o'zgartirib (saqlamay) P10 ga o'tish, P10 ni saqlash, P09 ga qaytib saqlash → ikkalasi ham saqlanadi, to'qnashuv xabari yo'q.
10. To'qnashuv: iOS da P09 ochiq; Android ota-ona ilovasida limitni o'zgartirish; iOS da boshqa qiymat bilan saqlash → "qoidalar oʻzgargan…" xabari, Android qiymati ko'rinadi, iOS qiymati yuborilmagan (Android'da o'zgarmagan). P10 va P12 da ham bir marta.
11. Bepul reja, ikkinchi (muzlatilgan) bola: P09 da qulf kartasi, "Saqlash" yo'q, slayderlar va "Boshqa qoidalar" qatorlari o'chiq; "Shu bolani faol qilish" → karta yo'qoladi, "Saqlash" va qatorlar yoqiladi.
12. P09 da qoralama qoldirib boshqa tabga o'tish va qaytish → qoralama joyida; P10 va P12 da ham.
13. Oflayn: P09 ochiq paytda tarmoqni o'chirib pull-to-refresh → "Oflayn — oxirgi maʼlum holat…" belgisi, qiymatlar qoladi; birinchi ochilishda tarmoq yo'q → xato va "Qayta urinish".
14. Uch til va ikki tema: P09, P10, P12, P12b va qulf kartasi matnlari to'g'ri; skrinshotlar (Cmd+S).

- [ ] **Step 3: Natijani yozish**

Ledger'ga (`.superpowers/sdd/<plan>/progress.md`) E2E natijalari va kechiktirilgan kichik masalalar yoziladi. Push foydalanuvchida; keyin `superpowers:finishing-a-development-branch`.
