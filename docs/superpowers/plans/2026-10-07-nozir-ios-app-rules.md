# Nozir iOS — 2c-2: Ilova qoidalari (P11) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ota-ona bolaning har bir ilovasi uchun qoida qo'ya oladi — P09 hub'dagi "Ilovalar" qatori, P11 ro'yxati (shu sahifada qo'shish va qidiruv) va har bir ilova uchun alohida tahrirlovchi — Android `feature/rules/apps` bilan bir xil natija, boshqa telefonda o'zgargan qoida ustidan hech qachon yozmasdan.

**Architecture:** `NozirFamily` ga `AppPolicyMode`/`BlockWindow`/`AppPolicy`/`InstalledApp`, snapshot'ga `appPolicies` va `neverBlockedPackages`, servisga `setAppPolicy` va `installedApps` qo'shiladi. `NozirAppFeature/Rules/` da ikki model: `AppRulesModel` (ro'yxat sessiya snapshot'idan, telefon ilovalari, qo'shsa bo'ladigan filtr, qidiruv) va `AppRuleModel` (bitta paket; 2c-1 dagi R6 `editBase` naqshi shu paketga qo'llanadi). Ikkalasi P09 hub'ining `ChildRulesSession` idan foydalanadi — umumiy versiya, `isWriting`, muzlatilganlik. Nomlar, qidiruv kaliti va qator matnlari sof yordamchilarda (`AppRuleTexts`, `AppSearch`).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 17), Observation, Swift Testing; uchinchi tomon kutubxonasi yo'q.

**Spec:** `docs/superpowers/specs/2026-10-07-nozir-ios-app-rules-design.md` (oldingi: `2026-10-06-nozir-ios-rules-design.md` va uning rejasi `docs/superpowers/plans/2026-10-06-nozir-ios-rules.md`)

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). Uchinchi tomon kutubxonasi yo'q.
- Har bir `/v1/parent/*` chaqiruvi `ApiClient` orqali; bola id'si yo'lda kichik harflar bilan (`FamilyApi.childPath`).
- `PUT /v1/parent/children/{id}/rules/apps/{packageId}` — `If-Match: "<sessiya versiyasi>"` majburiy; tana `AppPolicyDto{packageId, displayName?, mode, dailyLimitMinutes?, blockWindows:[{startTime:"HH:mm", endTime:"HH:mm", days:[1..7]}]}`; javob — to'liq `RuleSnapshot`, `session.accept` ga.
- `GET /v1/parent/children/{id}/apps` → `[{packageId, displayName?}]`, server saralaydi; bo'sh paketlar tashlanadi; bo'sh ro'yxat xato emas (telefon hali yubormagan).
- Rejimlar: `UNRESTRICTED`, `DAILY_LIMIT`, `SCHEDULE_BLOCK`, `ALWAYS_BLOCKED`; noma'lum nom o'zgarmasdan saqlanadi va hech qachon yuborilmaydi. `UNRESTRICTED` saqlansa qator o'chmaydi (DELETE yo'q). `displayName` har PUT'da yuboriladi (o'rnatilgan ilovadan, bo'lmasa saqlangan qoidadan).
- Kunlik vaqt slayderi 15–240, qadam 15, sukut 30. Jadval sukuti 08:00–13:00, kunlar 1–5; oxirgi kun o'chmaydi; faqat birinchi oyna tahrirlanadi, qolganlari o'zgarmasdan yuboriladi.
- Segmentlar: "Cheklov yo'q", "Kunlik vaqt", "Jadval"; "Doim yopiq" 4-segment faqat saqlangan rejim `ALWAYS_BLOCKED` bo'lsa. Noma'lum rejim — hech bir segment tanlanmagan, boshqa rejim tanlanmaguncha saqlash o'chiq.
- "Saqlash" faqat o'zgarish bo'lsa; yangi ilova (sessiyada qoidasi yo'q) uchun "Cheklov yo'q" holatida ham yoqiq. Muvaffaqiyat → ekranda qoladi, `rules_saved_named`/`rules_saved`, tahrirlovchi yangi asosga o'tadi.
- R6 shu paket bo'yicha: saqlashdan oldin sessiyadagi shu paketning qoidasi `editBase` ga teng bo'lmasa — yuborilmaydi, `rules_conflict_notice`, qoralama tashlanadi. Boshqa paket yoki boshqa qoida (P09/P10/P12/P12b) o'zgarishi to'qnashuv emas.
- 409 → sessiya qayta o'qiladi, `rules_conflict_notice`, qayta yuborilmaydi. 403 `CHILD_NOT_ACTIVE` → `data_error_child_not_active`; 400 → `data_error_invalid_request`; tarmoq/5xx → `UserMessage`; qoralama qoladi.
- Ikki marta tez "Saqlash" → bitta so'rov; bekor qilingan saqlash → xabarsiz; hub'da boshqa yozuv davom etsa (`session.isWriting`) yoki muzlatilgan → saqlash o'chiq.
- Tab almashtirib qaytish → qoralama yo'qolmaydi (`@State` model, sessiya bir marta yuklanadi, ilovalar bir marta o'qiladi).
- Hub "Boshqa qoidalar" tartibi: Uyqu vaqti → Ilovalar → Bonus → Joylashuv. Ilovalar qatori: `rules_link_apps_none` yoki `rules_link_apps_count(N)`, N — rejimi `UNRESTRICTED` bo'lmagan qoidalar soni; muzlatilganda o'chiq.
- Server `message` hech qachon ko'rsatilmaydi; matn faqat `L10n`, xatolar `UserMessage`. **Yangi l10n kaliti yo'q** (`gen_l10n --check` o'zgarishsiz o'tadi).
- Kirmaydi: push deep link `app-rules/{childId}`, ilova ikonkalari, qoidani o'chirish.
- P10 (`BedtimeView`) va P03b (`NewChildRulesView`) xatti-harakati o'zgarmaydi; mavjud testlar o'zgarishsiz o'tadi.
- Testlar: Swift Testing, `FakeFamily`, `PauseGate`; gate'li test `@Test(.timeLimit(.minutes(5)))`.
- Commit: `git add -A` taqiqlangan, faqat aniq yo'llar; push foydalanuvchida; commit muhiti va izoh qatorlari avvalgidek.
- Swift kodi test ishlaguncha "yozilgan, tekshirilmagan".

## Spec'dan chetlanishlar (reja bosqichida)

| # | Spec | Reja | Sabab |
|---|---|---|---|
| R1 | §3.2 `AppRulesModel` tahrirlovchini ochadi | Model `AppRuleTarget{packageId, displayName}` qaytaradi; view uni `RuleScreen.appRule` ga aylantiradi | Model navigatsiyaga bog'lanmaydi; `RuleScreen` ning yangi holatlari Task 6 da bitta joyda (`ruleDestination` switch'i) qo'shiladi va har bir task alohida kompilyatsiya bo'ladi |
| R2 | §4.1 hub soni | `AppRuleTexts.hubRow(_:_:)` — sof yordamchi (Task 2) | Hub qatori `AppRulesModel` yaratmasdan snapshot'dan o'qiydi |
| R3 | §3.2 `RuleDaysSection` sarlavhasi parametrlanadi | Yana `describesNights: false` — P11 da "Faol tunlar: …" xulosasi va "kamida bitta tun" izohi chiqmaydi | Bu matnlar tun haqida; Android P11 kun tanlagichida faqat chiplar; yangi kalit qo'shilmaydi |
| R4 | §4.3 `withMode` | Saqlangan rejimga qaytish saqlangan qoidani tiklaydi (o'zgarish yo'q) | Aks holda 45 daqiqalik qoida "Jadval"ga o'tib qaytganda 30 bo'lib qoladi va ota-ona o'zgartirmagan qoida "Saqlash"ni yoqadi (Review Focus 1) |
| R5 | §4.2 qator xulosasi | Noma'lum rejimli qatorda xulosa yo'q (nom va `›`); hub soni uni sanaydi | Noma'lum rejim uchun kalit yo'q; "Cheklov yo'q" yozish yolg'on bo'lardi |
| R6 | §4.2 | P11 da pull-to-refresh: `session.reload()` va ilovalarni qayta o'qish (ro'yxat bor bo'lsa ilovalar xatosi jim) | `state_offline_notice` keyingi o'qishdan keladi; Android `refresh()` |
| R7 | §3.2 `installedApps` | Ilovalar sessiyada snapshot bo'lgandan keyin, bir marta o'qiladi; xatodan keyin faqat "Qayta urinish" yoki qayta ochilish o'qiydi | Tab almashtirish so'rovni takrorlamasin; birinchi o'qish xatosi ko'rinadi (D3) |
| R8 | §6 `ruleDestination` | `ruleDestination(_:onOpen:)` — `onOpen` o'sha tab stack'iga qo'shadi | P11 tahrirlovchini o'zi ochilgan tabga surishi kerak; avvalgi funksiyada bunday yo'l yo'q edi |
| R9 | §2 yo'l | `packageId` yo'lga percent-encoding'siz qo'yiladi | Android paket nomlari faqat `[A-Za-z0-9._]` |
| R10 | §4.2/§4.3 muzlatilgan | "Ilova qo'shish" va tahrirlovchi boshqaruvlari muzlatilganda o'chiq | 2c-1 R13 bilan bir xil: qatorlar o'chiq bo'lsa ham model saqlamaydi |
| R11 | §4.3 rejimlar | `setMode` `modes` da yo'q rejimni e'tiborsiz qoldiradi; daqiqa/oyna setter'lari boshqa rejimda ishlamaydi | Yangi ilovaga "Doim yopiq"ni bir bosishda qo'yib bo'lmasin (Android `AppRuleMode`) |
| R12 | §7 fake'lar | `FakeFamily`: `appPolicy`, `installedApps` navbatlari, `installedAppsGate`, `cancelNextInstalledApps`; `cancelNextWrite` ilova yozuvini ham qamraydi | Testlar uchun |
| R13 | §4.3 R6 solishtirish | Qoidalar `displayName` siz, kunlar to'plam sifatida solishtiriladi | Nom qoidaning qismi emas; server kunlarni o'z tartibida yozadi |
| R14 | §4.2 tanlagich | Qo'shsa bo'ladigan ilova qolmasa — `app_rules_empty_title/body` (qidiruv maydonisiz) | Android `AppRulesAddList` |

## Review Focus

1. **Mavjud "Doim yopiq" qoidasi ochilib, rejimga tegmasdan "Saqlash"** — qoida `ALWAYS_BLOCKED` bo'lib qoladi yoki yozuv umuman ketmaydi; boshqa rejimga o'tib qaytish ham o'zgarish emas → Task 4 `anAlwaysClosedRuleOpenedAndSavedUntouchedStaysAlwaysClosed`.
2. **Tahrirlovchi ochiq paytda boshqa telefon shu ilovaning qoidasini o'zgartirdi** (pull-to-refresh olib keldi) — ustidan yozilmaydi, to'qnashuv xabari, yangi qiymat ko'rinadi → Task 4 `aRuleChangedOnAnotherPhoneIsNeverWrittenOver` (va yangi ilova uchun `aNewAppGivenARuleOnAnotherPhoneIsNeverWrittenOver`).
3. **Bu telefon P10 ni yoki boshqa ilova qoidasini saqlaydi, bu tahrirlovchida qoralama bor** — keyingi saqlash yangi versiya bilan ketadi, soxta to'qnashuv yo'q → Task 4 `anotherAppsRuleSavedMeanwhileIsNoConflict`, `aBedtimeSavedMeanwhileIsNoConflict`.
4. **Qoidada ikki oyna; birinchisi tahrirlanadi** — ikkinchisi o'zgarmasdan yuboriladi → Task 4 `editingTheFirstWindowKeepsTheSecond`.
5. **Telefon ilovalarini o'qish xato bilan tugadi** — ota-ona xato matni va "Qayta urinish"ni ko'radi, jim bo'sh tanlagichni emas; qayta urinish ro'yxatni olib keladi → Task 3 `aFailedAppsLoadSaysSoAndRetries`.

---

## Fayl xaritasi

**Yangi:**
- `NozirKit/Sources/NozirFamily/AppPolicyModels.swift` — `AppPolicyMode`, `BlockWindow`, `AppPolicy`, `InstalledApp`.
- `NozirKit/Sources/NozirAppFeature/Rules/AppRuleTexts.swift` — `AppRuleTexts`, `AppSearch`.
- `NozirKit/Sources/NozirAppFeature/Rules/AppRulesModel.swift` — `AppRuleTarget`, `AppRulesModel`.
- `NozirKit/Sources/NozirAppFeature/Rules/AppRuleModel.swift` — `AppRuleModel`.
- `NozirKit/Sources/NozirAppFeature/Screens/{AppRulesView,AppRuleView}.swift`.
- Testlar: `NozirKit/Tests/NozirAppFeatureTests/{AppRuleTextsTests,AppRulesModelTests,AppRuleModelTests}.swift`.

**O'zgaradi:** `NozirFamily/{RuleModels,FamilyService,FamilyApi}.swift`; `NozirAppFeature/Rules/{ChildRulesSession,RuleBounds}.swift`; `NozirAppFeature/SignedInModel.swift`; `Screens/{RuleControls,RulesHubView,DailyLimitSection,SignedInView}.swift`; testlar `NozirFamilyTests/RulesAndPairingApiTests.swift`, `NozirAppFeatureTests/{FakeFamily,ChildRulesSessionTests,SignedInModelTests}.swift`.

## Ishni boshlash

Branch `app-rules` (spec commit 10061dc) ochilgan. Swift testlari Mac'dagi watcher orqali: `bash .superpowers/run.sh <Target> 170` (`<Target>` — `NozirFamilyTests`, `NozirAppFeatureTests`, `all` yoki `app`). Natija `TIMEOUT waiting …` bo'lsa so'rov bekor bo'lmagan: so'rovni qayta yubormang, `.superpowers/test-result.log` da `### done` chiqquncha kuting va o'qing.

---
### Task 1: `NozirFamily` — ilova qoidalari va telefon ilovalari

**Files:**
- Create: `NozirKit/Sources/NozirFamily/AppPolicyModels.swift`
- Modify: `NozirKit/Sources/NozirFamily/RuleModels.swift` (`RuleSnapshot`)
- Modify: `NozirKit/Sources/NozirFamily/FamilyService.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyApi.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift` (`acceptBonus`)
- Modify: `NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift`
- Modify: `NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift`

**Interfaces:**
- Consumes: `ClockTime` (`init?(_ text:)`, `.text`), `FamilyApi.childPath(_:)`, `FamilyApi.entityTag(_:)` (private), `ApiRequest.put(_:json:ifMatch:)`, `ApiClient.send(_:as:)`, `NozirTestSupport` (`familyApi`, `.ok`, `URLRequest.jsonObject`), `PauseGate`.
- Produces:
  - `public enum AppPolicyMode: Hashable, Sendable { case unrestricted, dailyLimit, scheduleBlock, alwaysBlocked, unknown(String); init(wireName: String); var wireName: String }`
  - `public struct BlockWindow: Codable, Equatable, Sendable { var start: ClockTime; var end: ClockTime; var days: [Int]; init(start:end:days:) }`
  - `public struct AppPolicy: Codable, Equatable, Sendable { let packageId: String; var displayName: String?; var mode: AppPolicyMode; var dailyLimitMinutes: Int?; var blockWindows: [BlockWindow]; init(packageId:displayName: = nil, mode:, dailyLimitMinutes: = nil, blockWindows: = []) }` — `displayName` har doim kodlanadi (nil → `null`), `dailyLimitMinutes` nil bo'lsa yozilmaydi.
  - `public struct InstalledApp: Decodable, Equatable, Sendable { let packageId: String; let displayName: String?; init(packageId:displayName:) }`
  - `RuleSnapshot.appPolicies: [AppPolicy]`, `RuleSnapshot.neverBlockedPackages: [String]` (javobda yo'q bo'lsa `[]`); `RuleSnapshot.init(version:screenTime:bedtime:locationTracking: = .standard, maxTrustBonusMinutes: = 0, appPolicies: = [], neverBlockedPackages: = [])`.
  - `FamilyService.setAppPolicy(_ policy: AppPolicy, of childId: UUID, version: Int64) async throws -> RuleSnapshot`
  - `FamilyService.installedApps(of childId: UUID) async throws -> [InstalledApp]`
  - `FakeFamily.Script`: `appPolicy: [Result<RuleSnapshot, ApiFailure>]`, `installedApps: [Result<[InstalledApp], ApiFailure>]`, `cancelNextInstalledApps: Bool`, `installedAppsGate: PauseGate?`; ilova yozuvi `writeGate` va `cancelNextWrite` ga bo'ysunadi. Yozuvlar `appPolicyWrites: [RuleWrite<AppPolicy>]`; chaqiruv nomlari `"appPolicy"`, `"installedApps"`.
  - Test yordamchilari: `snapshot(version:limit:bedtime:tracking:trust:apps: [AppPolicy] = [], neverBlocked: [String] = [])`, `schoolHours: BlockWindow`, `appPolicy(_ packageId:name:mode:minutes:windows:) -> AppPolicy`, `robloxApp`, `telegramApp`, `dialerApp: InstalledApp`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift` — `snapshotJSON` ni butunlay almashtiring:

```swift
/// `RuleSnapshotResponse` with the parts 2a does not read left in, as the server sends them.
private func snapshotJSON(
    version: Int = 7,
    start: String = "22:00",
    tracking: String = #"{"isEnabled":false}"#,
    apps: String = "[]"
) -> String {
    """
    {"childId":"\(aliId.uuidString.lowercased())","version":\(version),\
    "screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
    "maxTrustBonusMinutes":30,"locationTracking":\(tracking),\
    "bedtime":{"startTime":"\(start)","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]},\
    "appPolicies":\(apps),"familyRules":[],"neverBlockedPackages":["com.android.dialer"]}
    """
}
```

va suite oxiriga (`theCeilingBindsWhenTheTasksPayMore` dan keyin, yopuvchi `}` dan oldin):

```swift
    @Test func theAppRulesAndTheNeverBlockedListAreRead() async throws {
        let apps = """
            [{"packageId":"com.roblox.client","displayName":"Roblox","mode":"SCHEDULE_BLOCK","dailyLimitMinutes":null,\
            "blockWindows":[{"startTime":"08:00","endTime":"13:00","days":[1,2,3,4,5]},\
            {"startTime":"15:00","endTime":"16:30","days":[6]}]},\
            {"packageId":"com.whatsapp","displayName":null,"mode":"DAILY_LIMIT","dailyLimitMinutes":45,"blockWindows":[]},\
            {"packageId":"com.example.new","mode":"FOCUS_ONLY"}]
            """
        let (api, _) = familyApi([.ok(snapshotJSON(apps: apps))])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.neverBlockedPackages == ["com.android.dialer"])
        #expect(snapshot.appPolicies.map(\.packageId) == ["com.roblox.client", "com.whatsapp", "com.example.new"])
        let roblox = snapshot.appPolicies[0]
        #expect(roblox.displayName == "Roblox")
        #expect(roblox.mode == .scheduleBlock)
        #expect(roblox.dailyLimitMinutes == nil)
        #expect(roblox.blockWindows == [
            BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 13, minute: 0), days: [1, 2, 3, 4, 5]),
            BlockWindow(start: ClockTime(hour: 15, minute: 0), end: ClockTime(hour: 16, minute: 30), days: [6]),
        ])
        #expect(snapshot.appPolicies[1].mode == .dailyLimit)
        #expect(snapshot.appPolicies[1].dailyLimitMinutes == 45)
        #expect(snapshot.appPolicies[1].displayName == nil)
        #expect(snapshot.appPolicies[2].mode == .unknown("FOCUS_ONLY"))
        #expect(snapshot.appPolicies[2].blockWindows.isEmpty)
    }

    @Test func aServerWithoutAppRulesReadsAsNone() async throws {
        let body = """
        {"version":3,"screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
        "bedtime":{"startTime":"22:00","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]}}
        """
        let (api, _) = familyApi([.ok(body)])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.appPolicies.isEmpty)
        #expect(snapshot.neverBlockedPackages.isEmpty)
    }

    @Test func anAppRuleWriteGoesToItsPackageAgainstTheVersion() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 8))])
        let policy = AppPolicy(
            packageId: "com.roblox.client",
            displayName: "Roblox",
            mode: .scheduleBlock,
            blockWindows: [BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 13, minute: 5), days: [1, 2, 3, 4, 5])]
        )

        let after = try await api.setAppPolicy(policy, of: aliId, version: 7)

        #expect(after.version == 8)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/apps/com.roblox.client")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        let body = try #require(request.jsonObject)
        #expect(body["packageId"] as? String == "com.roblox.client")
        #expect(body["displayName"] as? String == "Roblox")
        #expect(body["mode"] as? String == "SCHEDULE_BLOCK")
        #expect(body["dailyLimitMinutes"] == nil)
        let windows = try #require(body["blockWindows"] as? [[String: Any]])
        #expect(windows.count == 1)
        #expect(windows[0]["startTime"] as? String == "08:00")
        #expect(windows[0]["endTime"] as? String == "13:05")
        #expect(windows[0]["days"] as? [Int] == [1, 2, 3, 4, 5])
    }

    @Test func aDailyLimitWriteCarriesTheMinutesAndAnUnknownModeKeepsItsName() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 8)), .ok(snapshotJSON(version: 9))])

        _ = try await api.setAppPolicy(AppPolicy(packageId: "com.whatsapp", mode: .dailyLimit, dailyLimitMinutes: 45), of: aliId, version: 7)
        _ = try await api.setAppPolicy(AppPolicy(packageId: "com.example.new", mode: .unknown("FOCUS_ONLY")), of: aliId, version: 8)

        let requests = await transport.requests
        let daily = try #require(requests.first?.jsonObject)
        #expect(daily["mode"] as? String == "DAILY_LIMIT")
        #expect(daily["dailyLimitMinutes"] as? Int == 45)
        #expect(daily["displayName"] is NSNull)
        #expect((daily["blockWindows"] as? [Any])?.isEmpty == true)
        #expect(requests.last?.jsonObject?["mode"] as? String == "FOCUS_ONLY")
        #expect(AppPolicyMode(wireName: "ALWAYS_BLOCKED") == .alwaysBlocked)
        #expect(AppPolicyMode(wireName: "UNRESTRICTED").wireName == "UNRESTRICTED")
    }

    @Test func thePhonesAppsAreListedAndABlankPackageIsDropped() async throws {
        let (api, transport) = familyApi([.ok("""
            [{"packageId":"com.roblox.client","displayName":"Roblox"},{"packageId":"  ","displayName":"Ghost"},\
            {"packageId":"org.telegram.messenger","displayName":null},{"packageId":"com.duolingo"}]
            """)])

        let apps = try await api.installedApps(of: aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == FamilyApi.childPath(aliId) + "/apps")
        #expect(apps == [
            InstalledApp(packageId: "com.roblox.client", displayName: "Roblox"),
            InstalledApp(packageId: "org.telegram.messenger", displayName: nil),
            InstalledApp(packageId: "com.duolingo", displayName: nil),
        ])
    }
```

`NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift` — `aBonusAnswerMovesTheVersionAndTheCeilingOnly` testidan keyin qo'shing:

```swift
    @Test func aBonusAnswerKeepsTheAppRules() async {
        var script = FakeFamily.Script()
        let roblox = appPolicy("com.roblox.client", mode: .dailyLimit, minutes: 45)
        script.rules = [.success(snapshot(version: 4, apps: [roblox], neverBlocked: ["com.android.dialer"]))]
        let (session, _) = setup(script)
        await session.load()

        session.acceptBonus(version: 5, ceiling: 30)

        #expect(session.version == 5)
        #expect(session.snapshot?.appPolicies == [roblox])
        #expect(session.snapshot?.neverBlockedPackages == ["com.android.dialer"])
    }
```

`NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift` — quyidagi tahrirlar.

`Script` ichida `var setBonus: [Result<BonusConfig, ApiFailure>] = []` qatoridan keyin:

```swift
        var appPolicy: [Result<RuleSnapshot, ApiFailure>] = []
        var installedApps: [Result<[InstalledApp], ApiFailure>] = []
```

`/// When true the next screen-time, bedtime, location-tracking, trust-ladder or bonus write throws `CancellationError` once.` izohini almashtiring:

```swift
        /// When true the next screen-time, bedtime, location-tracking, trust-ladder, bonus or app-rule write throws `CancellationError` once.
```

`var writeGate: PauseGate?` qatoridan keyin (`Script` yopilishidan oldin):

```swift
        /// When true the next `installedApps` call throws `CancellationError` once.
        var cancelNextInstalledApps = false
        /// Held once by the next `installedApps` call, after its answer is taken.
        var installedAppsGate: PauseGate?
```

`private(set) var bonusWrites: [RuleWrite<BonusConfig>] = []` qatoridan keyin:

```swift
    private(set) var appPolicyWrites: [RuleWrite<AppPolicy>] = []
```

`setBonus` funksiyasidan keyin (uning yopuvchi `}` idan keyin):

```swift
    func setAppPolicy(_ policy: AppPolicy, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        childIds.append(childId)
        appPolicyWrites.append(RuleWrite(value: policy, version: version))
        try cancelIfAsked("appPolicy")
        return try await held("appPolicy", \.appPolicy, \.writeGate)
    }

    func installedApps(of childId: UUID) async throws -> [InstalledApp] {
        childIds.append(childId)
        if script.cancelNextInstalledApps {
            script.cancelNextInstalledApps = false
            calls.append("installedApps")
            throw CancellationError()
        }
        return try await held("installedApps", \.installedApps, \.installedAppsGate)
    }
```

`func snapshot(...)` yordamchisini butunlay almashtiring:

```swift
func snapshot(
    version: Int64,
    limit: ScreenTimeLimit = defaultLimit,
    bedtime: BedtimeSchedule = defaultBedtime,
    tracking: LocationTracking = .standard,
    trust: Int = 0,
    apps: [AppPolicy] = [],
    neverBlocked: [String] = []
) -> RuleSnapshot {
    RuleSnapshot(
        version: version,
        screenTime: limit,
        bedtime: bedtime,
        locationTracking: tracking,
        maxTrustBonusMinutes: trust,
        appPolicies: apps,
        neverBlockedPackages: neverBlocked
    )
}
```

`func pairingCode(...)` dan oldin qo'shing:

```swift
/// 08:00–13:00 on school days: the default schedule, and a common saved one.
let schoolHours = BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 13, minute: 0), days: [1, 2, 3, 4, 5])

func appPolicy(
    _ packageId: String,
    name: String? = nil,
    mode: AppPolicyMode,
    minutes: Int? = nil,
    windows: [BlockWindow] = []
) -> AppPolicy {
    AppPolicy(packageId: packageId, displayName: name, mode: mode, dailyLimitMinutes: minutes, blockWindows: windows)
}

let robloxApp = InstalledApp(packageId: "com.roblox.client", displayName: "Roblox")
let telegramApp = InstalledApp(packageId: "org.telegram.messenger", displayName: "Telegram")
let dialerApp = InstalledApp(packageId: "com.android.dialer", displayName: "Phone")
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`
Expected: FAIL — `cannot find 'AppPolicy' in scope`, `value of type 'FamilyApi' has no member 'setAppPolicy'`.

- [ ] **Step 3: Model turlari**

`NozirKit/Sources/NozirFamily/AppPolicyModels.swift` yarating:

```swift
import Foundation

/// How an app's rule restricts it (`AppPolicyMode`). A mode the server adds
/// later keeps its name: the editor offers no segment for it and never sends it.
public enum AppPolicyMode: Hashable, Sendable {
    case unrestricted, dailyLimit, scheduleBlock, alwaysBlocked
    case unknown(String)

    public init(wireName: String) {
        switch wireName {
        case "UNRESTRICTED": self = .unrestricted
        case "DAILY_LIMIT": self = .dailyLimit
        case "SCHEDULE_BLOCK": self = .scheduleBlock
        case "ALWAYS_BLOCKED": self = .alwaysBlocked
        default: self = .unknown(wireName)
        }
    }

    public var wireName: String {
        switch self {
        case .unrestricted: "UNRESTRICTED"
        case .dailyLimit: "DAILY_LIMIT"
        case .scheduleBlock: "SCHEDULE_BLOCK"
        case .alwaysBlocked: "ALWAYS_BLOCKED"
        case .unknown(let name): name
        }
    }
}

/// `BlockWindowDto`: the app is closed from `start` to `end` on `days`
/// (ISO-8601, 1 = Monday). The server does not compare start with end.
public struct BlockWindow: Codable, Equatable, Sendable {
    public var start: ClockTime
    public var end: ClockTime
    public var days: [Int]

    public init(start: ClockTime, end: ClockTime, days: [Int]) {
        self.start = start
        self.end = end
        self.days = days
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, days
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try Self.time(container, .startTime)
        end = try Self.time(container, .endTime)
        days = try container.decode([Int].self, forKey: .days)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start.text, forKey: .startTime)
        try container.encode(end.text, forKey: .endTime)
        try container.encode(days, forKey: .days)
    }

    private static func time(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> ClockTime {
        let text = try container.decode(String.self, forKey: key)
        guard let time = ClockTime(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not HH:mm: \(text)")
        }
        return time
    }
}

/// `AppPolicyDto`: one app's rule. `packageId` is its identity on the wire and
/// in the path; the name is only shown, and rewritten by every write.
public struct AppPolicy: Codable, Equatable, Sendable {
    public let packageId: String
    public var displayName: String?
    public var mode: AppPolicyMode
    public var dailyLimitMinutes: Int?
    public var blockWindows: [BlockWindow]

    public init(
        packageId: String,
        displayName: String? = nil,
        mode: AppPolicyMode,
        dailyLimitMinutes: Int? = nil,
        blockWindows: [BlockWindow] = []
    ) {
        self.packageId = packageId
        self.displayName = displayName
        self.mode = mode
        self.dailyLimitMinutes = dailyLimitMinutes
        self.blockWindows = blockWindows
    }

    private enum CodingKeys: String, CodingKey {
        case packageId, displayName, mode, dailyLimitMinutes, blockWindows
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try container.decode(String.self, forKey: .packageId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        mode = AppPolicyMode(wireName: try container.decode(String.self, forKey: .mode))
        dailyLimitMinutes = try container.decodeIfPresent(Int.self, forKey: .dailyLimitMinutes)
        blockWindows = try container.decodeIfPresent([BlockWindow].self, forKey: .blockWindows) ?? []
    }

    /// The name goes out even when unknown (`null`): the server stores what each write says.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageId, forKey: .packageId)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(mode.wireName, forKey: .mode)
        try container.encodeIfPresent(dailyLimitMinutes, forKey: .dailyLimitMinutes)
        try container.encode(blockWindows, forKey: .blockWindows)
    }
}

/// `InstalledAppDto`: one app on the child's phone, for P11's picker.
public struct InstalledApp: Decodable, Equatable, Sendable {
    public let packageId: String
    public let displayName: String?

    public init(packageId: String, displayName: String?) {
        self.packageId = packageId
        self.displayName = displayName
    }
}
```

- [ ] **Step 4: `RuleSnapshot`**

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
    /// P11's rules, in the server's order. A "no limit" row stays: there is no delete.
    public let appPolicies: [AppPolicy]
    /// Packages no rule may restrict (the dialler, SMS, the clock, Nozir).
    public let neverBlockedPackages: [String]

    public init(
        version: Int64,
        screenTime: ScreenTimeLimit,
        bedtime: BedtimeSchedule,
        locationTracking: LocationTracking = .standard,
        maxTrustBonusMinutes: Int = 0,
        appPolicies: [AppPolicy] = [],
        neverBlockedPackages: [String] = []
    ) {
        self.version = version
        self.screenTime = screenTime
        self.bedtime = bedtime
        self.locationTracking = locationTracking
        self.maxTrustBonusMinutes = maxTrustBonusMinutes
        self.appPolicies = appPolicies
        self.neverBlockedPackages = neverBlockedPackages
    }

    private enum CodingKeys: String, CodingKey {
        case version, screenTime, bedtime, locationTracking, maxTrustBonusMinutes, appPolicies, neverBlockedPackages
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int64.self, forKey: .version)
        screenTime = try container.decode(ScreenTimeLimit.self, forKey: .screenTime)
        bedtime = try container.decode(BedtimeSchedule.self, forKey: .bedtime)
        locationTracking = try container.decodeIfPresent(LocationTracking.self, forKey: .locationTracking) ?? .standard
        maxTrustBonusMinutes = try container.decodeIfPresent(Int.self, forKey: .maxTrustBonusMinutes) ?? 0
        appPolicies = try container.decodeIfPresent([AppPolicy].self, forKey: .appPolicies) ?? []
        neverBlockedPackages = try container.decodeIfPresent([String].self, forKey: .neverBlockedPackages) ?? []
    }
}
```

- [ ] **Step 5: Protokol, API va `acceptBonus`**

`NozirKit/Sources/NozirFamily/FamilyService.swift` — `func setBonus(...)` qatoridan keyin:

```swift
    func setAppPolicy(_ policy: AppPolicy, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    /// The apps on the child's phone as it last reported them; a blank package is dropped.
    func installedApps(of childId: UUID) async throws -> [InstalledApp]
```

`NozirKit/Sources/NozirFamily/FamilyApi.swift` — `setBonus` funksiyasidan keyin:

```swift
    /// The path names the package and wins over the body's (the server says so).
    /// Package ids are `[A-Za-z0-9._]`, so the path needs no escaping.
    public func setAppPolicy(_ policy: AppPolicy, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(
            Self.childPath(childId) + "/rules/apps/" + policy.packageId,
            json: policy,
            ifMatch: Self.entityTag(version)
        )
        return try await client.send(request, as: RuleSnapshot.self)
    }

    /// Not limited by the plan. Empty means the phone has not sent its list yet.
    public func installedApps(of childId: UUID) async throws -> [InstalledApp] {
        let apps = try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/apps"), as: [InstalledApp].self)
        return apps.filter { !$0.packageId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
```

`NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift` — `acceptBonus` ni butunlay almashtiring:

```swift
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
            maxTrustBonusMinutes: snapshot.maxTrustBonusMinutes,
            appPolicies: snapshot.appPolicies,
            neverBlockedPackages: snapshot.neverBlockedPackages
        ))
    }
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirFamilyTests 170`, so'ng `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: ikkalasida `** TEST SUCCEEDED **` (mavjud testlar o'zgarishsiz o'tadi; `FakeFamily` yangi protokolga mos; `aBonusAnswerKeepsTheAppRules` o'tadi).

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirFamily/AppPolicyModels.swift NozirKit/Sources/NozirFamily/RuleModels.swift NozirKit/Sources/NozirFamily/FamilyService.swift NozirKit/Sources/NozirFamily/FamilyApi.swift NozirKit/Sources/NozirAppFeature/Rules/ChildRulesSession.swift NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift NozirKit/Tests/NozirAppFeatureTests/ChildRulesSessionTests.swift
```

Xabar: `family: app rules and the phone's apps, read and written by version`

---
### Task 2: Umumiy qismlar — chegara, kun tanlagich sarlavhasi, nomlar, qidiruv, qator matnlari

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift` (`RuleMinuteRange`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift` (`RuleDaysSection`)
- Create: `NozirKit/Sources/NozirAppFeature/Rules/AppRuleTexts.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppRuleTextsTests.swift`

**Interfaces:**
- Consumes: `AppUsageFolding.friendlyName(packageId:reported:)`, `Durations.short(_:_:)`, `AppPolicy`, `AppPolicyMode`, `InstalledApp` (Task 1), L10n: `appRuleNone`, `appRuleAlways`, `appRuleDailyLimit(_: String)`, `appRuleSchedule(_: String, _: String)`, `appRuleModeNone`, `appRuleModeDailyLimit`, `appRuleModeSchedule`, `rulesLinkAppsNone`, `rulesLinkAppsCount(_: Int)`, `bedtimeDaysLabel`.
- Produces:
  - `RuleMinuteRange.appDailyLimit = 15...240`
  - `RuleDaysSection(title: String? = nil, describesNights: Bool = true, activeDays: Set<Int>, onToggle: @escaping (Int) -> Void)` — mavjud chaqiruvlar o'zgarishsiz.
  - `enum AppRuleTexts { static func name(packageId: String, displayName: String?) -> String; static func name(_ app: InstalledApp) -> String; static func summary(_ policy: AppPolicy, _ l10n: L10n) -> String?; static func closesTheApp(_ policy: AppPolicy) -> Bool; static func hubRow(_ policies: [AppPolicy], _ l10n: L10n) -> String; static func modeLabel(_ mode: AppPolicyMode, _ l10n: L10n) -> String }`
  - `enum AppSearch { static func key(_ text: String) -> String; static func matching(_ apps: [InstalledApp], _ query: String) -> [InstalledApp] }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/AppRuleTextsTests.swift` yarating:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private let l10n = L10n(.uz)

@MainActor
@Suite struct AppRuleTextsTests {
    @Test func anAppIsCalledByItsLabelOrABetterNameThanItsId() {
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: "Roblox Beta") == "Roblox Beta")
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: nil) == "Roblox")
        #expect(AppRuleTexts.name(packageId: "com.roblox.client", displayName: "com.roblox.client") == "Roblox")
        #expect(AppRuleTexts.name(packageId: "uz.payme.app", displayName: "  ") == "Payme")
        #expect(AppRuleTexts.name(telegramApp) == "Telegram")
    }

    @Test func eachModeHasItsLine() {
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .unrestricted), l10n) == l10n.appRuleNone)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .alwaysBlocked), l10n) == l10n.appRuleAlways)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .dailyLimit, minutes: 45), l10n) == l10n.appRuleDailyLimit(Durations.short(45, l10n)))
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .scheduleBlock, windows: [schoolHours]), l10n) == l10n.appRuleSchedule("08:00", "13:00"))
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .scheduleBlock), l10n) == l10n.appRuleNone)
        #expect(AppRuleTexts.summary(appPolicy("a", mode: .unknown("FOCUS_ONLY")), l10n) == nil)
    }

    @Test func onlyRulesThatCloseTheAppAreAccented() {
        #expect(AppRuleTexts.closesTheApp(appPolicy("a", mode: .scheduleBlock, windows: [schoolHours])))
        #expect(AppRuleTexts.closesTheApp(appPolicy("a", mode: .alwaysBlocked)))
        #expect(!AppRuleTexts.closesTheApp(appPolicy("a", mode: .dailyLimit, minutes: 30)))
        #expect(!AppRuleTexts.closesTheApp(appPolicy("a", mode: .unrestricted)))
    }

    @Test func theHubCountsRulesButNotNoLimit() {
        let free = [appPolicy("a", mode: .unrestricted)]
        let some = free + [
            appPolicy("b", mode: .dailyLimit, minutes: 30),
            appPolicy("c", mode: .alwaysBlocked),
            appPolicy("d", mode: .unknown("FOCUS_ONLY")),
        ]

        #expect(AppRuleTexts.hubRow([], l10n) == l10n.rulesLinkAppsNone)
        #expect(AppRuleTexts.hubRow(free, l10n) == l10n.rulesLinkAppsNone)
        #expect(AppRuleTexts.hubRow(some, l10n) == l10n.rulesLinkAppsCount(3))
    }

    @Test func theModesHaveTheirLabels() {
        #expect(AppRuleTexts.modeLabel(.unrestricted, l10n) == l10n.appRuleModeNone)
        #expect(AppRuleTexts.modeLabel(.dailyLimit, l10n) == l10n.appRuleModeDailyLimit)
        #expect(AppRuleTexts.modeLabel(.scheduleBlock, l10n) == l10n.appRuleModeSchedule)
        #expect(AppRuleTexts.modeLabel(.alwaysBlocked, l10n) == l10n.appRuleAlways)
    }

    @Test func searchFoldsCaseSpacesAndUzbekApostrophes() {
        #expect(AppSearch.key("  O\u{02BB}QUV ") == "o'quv")
        #expect(AppSearch.key("O\u{2019}quv") == "o'quv")
        #expect(AppSearch.key("o`quv") == "o'quv")
        #expect(AppSearch.key("o\u{02BC}quv") == "o'quv")
        let oquv = InstalledApp(packageId: "uz.oquv.app", displayName: "O\u{02BB}quv markazi")

        #expect(AppSearch.matching([oquv, robloxApp], "o'QUV") == [oquv])
    }

    @Test func searchFindsTheMiddleOfANameItsFriendlyNameAndThePackage() {
        let brawl = InstalledApp(packageId: "com.supercell.brawlstars", displayName: nil)
        let apps = [robloxApp, telegramApp, brawl]

        #expect(AppSearch.matching(apps, "gram") == [telegramApp])
        #expect(AppSearch.matching(apps, "Brawl S") == [brawl])
        #expect(AppSearch.matching(apps, "org.telegram") == [telegramApp])
        #expect(AppSearch.matching(apps, "   ") == apps)
        #expect(AppSearch.matching(apps, "zzz").isEmpty)
    }

    @Test func anAppsDailyTimeMovesInQuarterHoursUpToFourHours() {
        #expect(RuleMinuteRange.appDailyLimit == 15...240)
        #expect(RuleMinuteRange.step == 15)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'AppRuleTexts' in scope`, `type 'RuleMinuteRange' has no member 'appDailyLimit'`.

- [ ] **Step 3: Chegara**

`NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift` — `static let windDown = 15...60` qatoridan keyin:

```swift
    /// One app's daily time on P11 (Android `APP_DAILY_LIMIT`).
    static let appDailyLimit = 15...240
```

- [ ] **Step 4: Nomlar, qidiruv va matnlar**

`NozirKit/Sources/NozirAppFeature/Rules/AppRuleTexts.swift` yarating:

```swift
import Foundation
import NozirFamily
import NozirL10n

/// P11's words (Android `AppRuleName.kt`, `AppPolicySummary.kt`, `AppRuleMode.kt`).
enum AppRuleTexts {
    /// The phone's label unless it is empty or just the id; then a well-known
    /// name; then the id tidied into words. The package stays the identity.
    static func name(packageId: String, displayName: String?) -> String {
        AppUsageFolding.friendlyName(packageId: packageId, reported: displayName ?? "")
    }

    static func name(_ app: InstalledApp) -> String {
        name(packageId: app.packageId, displayName: app.displayName)
    }

    /// The line under an app's name. A schedule says its hours ("08:00–13:00
    /// yopiq") — a fact a parent can check against a school day. nil for a
    /// mode this app has no words for: "no limit" would be untrue.
    static func summary(_ policy: AppPolicy, _ l10n: L10n) -> String? {
        switch policy.mode {
        case .unrestricted:
            return l10n.appRuleNone
        case .alwaysBlocked:
            return l10n.appRuleAlways
        case .dailyLimit:
            return l10n.appRuleDailyLimit(Durations.short(policy.dailyLimitMinutes ?? 0, l10n))
        case .scheduleBlock:
            guard let window = policy.blockWindows.first else { return l10n.appRuleNone }
            return l10n.appRuleSchedule(window.start.text, window.end.text)
        case .unknown:
            return nil
        }
    }

    /// A rule that shuts the app at some hour is drawn in the accent colour.
    static func closesTheApp(_ policy: AppPolicy) -> Bool {
        policy.mode == .scheduleBlock || policy.mode == .alwaysBlocked
    }

    /// P09's "Ilovalar" row. A saved "no limit" is a row, not a rule.
    static func hubRow(_ policies: [AppPolicy], _ l10n: L10n) -> String {
        let count = policies.filter { $0.mode != .unrestricted }.count
        return count == 0 ? l10n.rulesLinkAppsNone : l10n.rulesLinkAppsCount(count)
    }

    static func modeLabel(_ mode: AppPolicyMode, _ l10n: L10n) -> String {
        switch mode {
        case .unrestricted: return l10n.appRuleModeNone
        case .dailyLimit: return l10n.appRuleModeDailyLimit
        case .scheduleBlock: return l10n.appRuleModeSchedule
        case .alwaysBlocked: return l10n.appRuleAlways
        case .unknown(let name): return name
        }
    }
}

/// Finding one app among fifty by part of its name (Android `AppSearch.kt`):
/// substring, on the name shown, the name the phone gave and the package id.
enum AppSearch {
    /// Straight, curly, both Uzbek modifier letters and the backtick: almost
    /// nobody types the one the label uses.
    private static let apostrophes: Set<Unicode.Scalar> = ["'", "\u{2018}", "\u{2019}", "\u{02BB}", "\u{02BC}", "`"]

    /// Trimmed, lower-cased (`lowercased()` is locale-independent, so a
    /// Turkish phone still finds "Instagram"), apostrophes folded to `'`.
    static func key(_ text: String) -> String {
        var folded = String.UnicodeScalarView()
        for scalar in text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().unicodeScalars {
            folded.append(apostrophes.contains(scalar) ? "'" : scalar)
        }
        return String(folded)
    }

    /// Nothing typed is everything, in the server's order.
    static func matching(_ apps: [InstalledApp], _ query: String) -> [InstalledApp] {
        let needle = key(query)
        guard !needle.isEmpty else { return apps }
        return apps.filter { app in
            key(AppRuleTexts.name(app)).contains(needle)
                || key(app.displayName ?? "").contains(needle)
                || key(app.packageId).contains(needle)
        }
    }
}
```

- [ ] **Step 5: Kun tanlagich sarlavhasi**

`NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift` — `RuleDaysSection` ni butunlay almashtiring (`chip(_:)` o'zgarmaydi, to'liq keltirilgan):

```swift
/// The seven days as chips, what they add up to, and the hint when one is left.
/// P11's daytime window passes its own title and `describesNights: false`:
/// the summary and the hint speak of nights.
struct RuleDaysSection: View {
    private let title: String?
    private let describesNights: Bool
    private let activeDays: Set<Int>
    private let onToggle: (Int) -> Void
    @Environment(\.l10n) private var l10n

    init(title: String? = nil, describesNights: Bool = true, activeDays: Set<Int>, onToggle: @escaping (Int) -> Void) {
        self.title = title
        self.describesNights = describesNights
        self.activeDays = activeDays
        self.onToggle = onToggle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(title ?? l10n.bedtimeDaysLabel).nozirText(.body)
            HStack(spacing: NozirSpacing.extraSmall) {
                ForEach(1...7, id: \.self) { day in chip(day) }
            }
            if describesNights {
                Text(RuleDays.summary(activeDays, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
                if activeDays.count == 1 {
                    Text(l10n.bedtimeDaysHint).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
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
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`, so'ng `bash .superpowers/run.sh app 170`
Expected: `** TEST SUCCEEDED **` (`RuleBoundsTests`, `NewChildRulesModelTests`, `BedtimeModelTests` o'zgarishsiz o'tadi), `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/RuleBounds.swift NozirKit/Sources/NozirAppFeature/Rules/AppRuleTexts.swift NozirKit/Sources/NozirAppFeature/Screens/RuleControls.swift NozirKit/Tests/NozirAppFeatureTests/AppRuleTextsTests.swift
```

Xabar: `rules: app names, search and rule lines for P11`

---
### Task 3: `AppRulesModel` — P11 ro'yxati, telefon ilovalari, qo'shish va qidiruv

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/AppRulesModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppRulesModelTests.swift`

**Interfaces:**
- Consumes: `ChildRulesSession` (`snapshot`, `load()`, `reload()`, `isWriting`, `family.service`, `childId`), `FamilyService.installedApps(of:)` (Task 1), `AppRuleTexts.name`, `AppSearch.matching` (Task 2), `AppUsageEntry.otherAppsPackageId` (`NozirInsights`), `UserMessage`.
- Produces:
  - `struct AppRuleTarget: Hashable, Sendable { let packageId: String; let displayName: String? }`
  - `@MainActor @Observable final class AppRulesModel { init(session: ChildRulesSession); let session; private(set) var installedApps: [InstalledApp]?; private(set) var isLoadingApps: Bool; private(set) var appsLoadFailure: UserMessage?; private(set) var isChoosingApp: Bool; private(set) var query: String; var policies: [AppPolicy]; var addableApps: [InstalledApp]; var shownApps: [InstalledApp]; func isAddable(_ app: InstalledApp) -> Bool; func name(of policy: AppPolicy) -> String; func load() async; func retryApps() async; func refresh() async; func toggleChoosing(); func setQuery(_ text: String); func choose(_ app: InstalledApp) -> AppRuleTarget?; func open(_ policy: AppPolicy) -> AppRuleTarget }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/AppRulesModelTests.swift` yarating:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let robloxRule = appPolicy("com.roblox.client", name: "Roblox", mode: .scheduleBlock, windows: [schoolHours])
private let telegramFree = appPolicy("org.telegram.messenger", name: "Telegram", mode: .unrestricted)

@MainActor
private func makeModel(_ script: FakeFamily.Script) -> (AppRulesModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    return (AppRulesModel(session: session), session, fake)
}

/// P11 as it opens: the session read, then the phone's apps.
@MainActor
private func setup(_ script: FakeFamily.Script) async -> (AppRulesModel, ChildRulesSession, FakeFamily) {
    let (model, session, fake) = makeModel(script)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct AppRulesModelTests {
    @Test func theRulesAreTheSessionsInTheServersOrder() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [telegramFree, robloxRule]))]
        script.installedApps = [.success([])]
        let (model, _, _) = await setup(script)

        #expect(model.policies == [telegramFree, robloxRule])
    }

    @Test func onlyAppsWithoutAnyRuleAreOfferedAndNeverAProtectedOne() async {
        let duolingo = InstalledApp(packageId: "com.duolingo", displayName: "Duolingo")
        let bucket = InstalledApp(packageId: "nozir.other_apps", displayName: "Others")
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [telegramFree, robloxRule], neverBlocked: [dialerApp.packageId]))]
        script.installedApps = [.success([robloxApp, dialerApp, telegramApp, bucket, duolingo])]
        let (model, _, _) = await setup(script)

        #expect(model.addableApps == [duolingo])
        #expect(model.choose(dialerApp) == nil)
        #expect(model.choose(bucket) == nil)
        #expect(model.choose(robloxApp) == nil)
    }

    @Test func aRuleSavedElsewhereInTheHubTakesTheAppOffTheList() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, session, _) = await setup(script)
        #expect(model.addableApps == [robloxApp, telegramApp])

        session.accept(snapshot(version: 5, apps: [robloxRule]))

        #expect(model.policies == [robloxRule])
        #expect(model.addableApps == [telegramApp])
    }

    // Review Focus 5.
    @Test func aFailedAppsLoadSaysSoAndRetries() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.failure(offline), .success([robloxApp])]
        let (model, _, fake) = await setup(script)
        model.toggleChoosing()

        #expect(model.installedApps == nil)
        #expect(model.appsLoadFailure == .noConnection)
        #expect(!model.isLoadingApps)
        #expect(model.addableApps.isEmpty)

        await model.retryApps()

        #expect(model.appsLoadFailure == nil)
        #expect(model.addableApps == [robloxApp])
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 2)
    }

    @Test func aPhoneThatSentNoAppsYetIsNotAnError() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([])]
        let (model, _, _) = await setup(script)

        #expect(model.installedApps == [])
        #expect(model.appsLoadFailure == nil)
        #expect(model.addableApps.isEmpty)
    }

    @Test func theAppsAreAskedForOnlyOnceTheRulesArrive() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp])]
        let (model, session, fake) = await setup(script)

        #expect(session.loadFailure == .noConnection)
        #expect(await fake.calls.filter { $0 == "installedApps" }.isEmpty)

        await model.load()

        #expect(model.addableApps == [robloxApp])
    }

    @Test func loadingAgainReadsNothingTwiceAndKeepsTheSearch() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp]), .success([])]
        let (model, _, fake) = await setup(script)
        model.toggleChoosing()
        model.setQuery("rob")

        await model.load()

        #expect(model.isChoosingApp)
        #expect(model.query == "rob")
        #expect(model.shownApps == [robloxApp])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
    }

    @Test func openingAndClosingThePickerStartsFromNothingTyped() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)

        model.toggleChoosing()
        #expect(model.isChoosingApp)
        model.setQuery("tel")
        model.toggleChoosing()

        #expect(!model.isChoosingApp)
        #expect(model.query == "")
        model.toggleChoosing()
        #expect(model.query == "")
        #expect(model.shownApps == [robloxApp, telegramApp])
    }

    @Test func theSearchNarrowsTheOfferedApps() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)
        model.toggleChoosing()

        model.setQuery("GRAM ")
        #expect(model.shownApps == [telegramApp])

        model.setQuery("zzz")
        #expect(model.shownApps.isEmpty)
        #expect(model.addableApps.count == 2)
    }

    @Test func choosingAnAppOpensItsEditorWithItsNameAndClosesThePicker() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, _, _) = await setup(script)
        model.toggleChoosing()
        model.setQuery("rob")

        let target = model.choose(robloxApp)

        #expect(target == AppRuleTarget(packageId: "com.roblox.client", displayName: "Roblox"))
        #expect(!model.isChoosingApp)
        #expect(model.query == "")
    }

    @Test func aRuleOpensWithThePhonesNameWhenThereIsOne() async {
        let unnamed = appPolicy("com.roblox.client", mode: .dailyLimit, minutes: 30)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [unnamed, telegramFree]))]
        script.installedApps = [.success([robloxApp])]
        let (model, _, _) = await setup(script)

        #expect(model.open(unnamed) == AppRuleTarget(packageId: "com.roblox.client", displayName: "Roblox"))
        #expect(model.open(telegramFree) == AppRuleTarget(packageId: "org.telegram.messenger", displayName: "Telegram"))
        #expect(model.name(of: unnamed) == "Roblox")
    }

    @Test func pullToRefreshReadsTheRulesAndTheAppsAgain() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [robloxRule]))]
        script.installedApps = [.success([robloxApp]), .success([robloxApp, telegramApp])]
        let (model, session, _) = await setup(script)

        await model.refresh()

        #expect(session.version == 6)
        #expect(model.addableApps == [telegramApp])
    }

    @Test func aFailedRefreshOfTheAppsKeepsTheListShown() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp]), .failure(offline)]
        let (model, _, _) = await setup(script)

        await model.refresh()

        #expect(model.addableApps == [robloxApp])
        #expect(model.appsLoadFailure == nil)
    }

    @Test(.timeLimit(.minutes(5)))
    func aRetryWhileTheAppsAreOnTheirWayAsksOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.installedApps = [.success([robloxApp])]
        script.installedAppsGate = gate
        let (model, _, fake) = makeModel(script)

        let first = Task { await model.load() }
        await gate.untilPaused()
        #expect(model.isLoadingApps)
        await model.retryApps()
        await gate.release()
        await first.value

        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
        #expect(model.addableApps == [robloxApp])
    }

    @Test func aCancelledAppsLoadSaysNothing() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.cancelNextInstalledApps = true
        let (model, _, _) = await setup(script)

        #expect(model.appsLoadFailure == nil)
        #expect(!model.isLoadingApps)
        #expect(model.installedApps == nil)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'AppRulesModel' in scope`, `cannot find 'AppRuleTarget' in scope`.

- [ ] **Step 3: `AppRulesModel`**

`NozirKit/Sources/NozirAppFeature/Rules/AppRulesModel.swift` yarating:

```swift
import Foundation
import Observation
import NozirFamily
import NozirInsights

/// The app P11 opens the editor on, and the phone's name for it (sent with the save).
struct AppRuleTarget: Hashable, Sendable {
    let packageId: String
    let displayName: String?
}

/// P11 (Android `AppRulesViewModel`): the rules the session holds, and the
/// apps on the child's phone a rule could still be written for. One app's
/// edit is `AppRuleModel`'s, on a screen of its own (spec D1).
@MainActor
@Observable
final class AppRulesModel {
    let session: ChildRulesSession
    /// The phone's list; nil until it has been read.
    private(set) var installedApps: [InstalledApp]?
    private(set) var isLoadingApps = false
    /// The first read of the phone's list failed. Said, with Retry (spec D3):
    /// a silent empty picker reads as "the child has no apps".
    private(set) var appsLoadFailure: UserMessage?
    private(set) var isChoosingApp = false
    private(set) var query = ""

    init(session: ChildRulesSession) {
        self.session = session
    }

    /// In the server's order. A saved "no limit" stays a row: there is no delete.
    var policies: [AppPolicy] {
        session.snapshot?.appPolicies ?? []
    }

    /// The phone's apps a rule could be written for, in the server's order.
    var addableApps: [InstalledApp] {
        (installedApps ?? []).filter { isAddable($0) }
    }

    var shownApps: [InstalledApp] {
        AppSearch.matching(addableApps, query)
    }

    /// Not one with a rule (a "no limit" one included), not one the server
    /// never lets a rule touch, and not the usage screens' "others" bucket.
    func isAddable(_ app: InstalledApp) -> Bool {
        guard let snapshot = session.snapshot else { return false }
        return app.packageId != AppUsageEntry.otherAppsPackageId
            && !snapshot.neverBlockedPackages.contains(app.packageId)
            && !snapshot.appPolicies.contains { $0.packageId == app.packageId }
    }

    func name(of policy: AppPolicy) -> String {
        AppRuleTexts.name(packageId: policy.packageId, displayName: displayName(of: policy))
    }

    /// The session once, then the phone's list once: a tab switch keeps both
    /// and the picker as it was.
    func load() async {
        await session.load()
        guard session.snapshot != nil, installedApps == nil else { return }
        await loadApps()
    }

    func retryApps() async {
        await loadApps()
    }

    /// Pull to refresh. Nothing while a save of the hub is on its way: a newer
    /// version read mid-save would be the one that save is checked against.
    func refresh() async {
        guard !session.isWriting else { return }
        await session.reload()
        await loadApps()
    }

    /// Opening and closing both start from nothing typed: a query kept across
    /// a close greets the next opening with a list that looks empty.
    func toggleChoosing() {
        isChoosingApp.toggle()
        query = ""
    }

    func setQuery(_ text: String) {
        query = text
    }

    /// nil for an app no rule may be written for (the server would refuse it).
    func choose(_ app: InstalledApp) -> AppRuleTarget? {
        guard isAddable(app) else { return nil }
        isChoosingApp = false
        query = ""
        return AppRuleTarget(packageId: app.packageId, displayName: app.displayName)
    }

    func open(_ policy: AppPolicy) -> AppRuleTarget {
        AppRuleTarget(packageId: policy.packageId, displayName: displayName(of: policy))
    }

    /// The phone's current name first, then the one saved with the rule.
    private func displayName(of policy: AppPolicy) -> String? {
        installedApps?.first { $0.packageId == policy.packageId }?.displayName ?? policy.displayName
    }

    /// A later read that fails leaves a shown list alone (Android does the same).
    private func loadApps() async {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        if installedApps == nil { appsLoadFailure = nil }
        defer { isLoadingApps = false }
        do {
            installedApps = try await session.family.service.installedApps(of: session.childId)
            appsLoadFailure = nil
        } catch is CancellationError {
            return
        } catch {
            if installedApps == nil { appsLoadFailure = UserMessage(error) }
        }
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/AppRulesModel.swift NozirKit/Tests/NozirAppFeatureTests/AppRulesModelTests.swift
```

Xabar: `rules: P11 lists the app rules and the apps a rule can be added for`

---
### Task 4: `AppRuleModel` — bitta ilova qoidasini tahrirlash va saqlash

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Rules/AppRuleModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppRuleModelTests.swift`

**Interfaces:**
- Consumes: `ChildRulesSession` (`snapshot`, `version`, `isWriting`, `isFrozen`, `load()`, `write(_:)`, `family.service`, `childId`), `RuleSaveOutcome` (`.saved`, `.conflict`, `.failed`, `.cancelled`), `RuleNotice`, `RuleDays.toggled(_:_:)`, `FamilyService.setAppPolicy(_:of:version:)` (Task 1), `AppRuleTexts.name(packageId:displayName:)` (Task 2), `BedtimeModel` (testda).
- Produces:
  - `@MainActor @Observable final class AppRuleModel`:
    - `static let defaultDailyLimitMinutes = 30`, `static let defaultWindow: BlockWindow` (08:00–13:00, `[1, 2, 3, 4, 5]`)
    - `init(session: ChildRulesSession, packageId: String, displayName: String?)`; `let session`, `let packageId`, `let displayName`
    - `private(set) var edited: AppPolicy?`, `editBase: AppPolicy?`, `isSaving: Bool`, `message: UserMessage?`, `notice: RuleNotice?`
    - `var saved: AppPolicy?`, `var policy: AppPolicy?`, `var sentName: String?`, `var name: String`, `var modes: [AppPolicyMode]`, `var selectedMode: AppPolicyMode?`, `var window: BlockWindow?`, `var hasChange: Bool`, `var canSave: Bool`
    - `func load() async`, `func setMode(_ mode: AppPolicyMode)`, `func setDailyLimitMinutes(_ minutes: Int)`, `func setWindowStart(_ time: ClockTime)`, `func setWindowEnd(_ time: ClockTime)`, `func toggleDay(_ day: Int)`, `func save() async`
    - `static func withMode(_ policy: AppPolicy, _ mode: AppPolicyMode) -> AppPolicy`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/AppRuleModelTests.swift` yarating:

```swift
import Foundation
import Testing
import NozirFamily
import NozirNetworking
@testable import NozirAppFeature

private let ali = makeChild("Ali")
private let conflict = ApiFailure.server(status: 409, error: ApiError(code: .conflict))
private let roblox = "com.roblox.client"
private let mine = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 30)
private let anHour = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 60)

@MainActor
private func makeModel(
    _ script: FakeFamily.Script,
    packageId: String = roblox,
    displayName: String? = "Roblox"
) -> (AppRuleModel, ChildRulesSession, FakeFamily) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(ali)
    let session = ChildRulesSession(childId: ali.id, family: family)
    return (AppRuleModel(session: session, packageId: packageId, displayName: displayName), session, fake)
}

/// The editor over a loaded session, as P11 opens it.
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    packageId: String = roblox,
    displayName: String? = "Roblox"
) async -> (AppRuleModel, ChildRulesSession, FakeFamily) {
    let (model, session, fake) = makeModel(script, packageId: packageId, displayName: displayName)
    await model.load()
    return (model, session, fake)
}

@MainActor
@Suite struct AppRuleModelTests {
    @Test func aNewAppStartsWithNoLimitAndThatCanBeSaved() async {
        let saved = appPolicy(roblox, name: "Roblox", mode: .unrestricted)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [saved]))]
        let (model, session, fake) = await setup(script)

        #expect(model.policy == saved)
        #expect(model.name == "Roblox")
        #expect(model.selectedMode == .unrestricted)
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock])
        #expect(model.canSave)

        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: saved, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.policy == saved)
        #expect(!model.canSave)
    }

    @Test func anUnchangedRuleHasNothingToSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 45)]))]
        let (model, _, _) = await setup(script)

        #expect(model.selectedMode == .dailyLimit)
        #expect(!model.canSave)

        model.setDailyLimitMinutes(60)
        #expect(model.canSave)

        model.setDailyLimitMinutes(45)
        #expect(!model.hasChange)
        #expect(!model.canSave)
    }

    @Test func dailyTimeStartsAtThirtyAndAScheduleAtSchoolHours() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        let (model, _, _) = await setup(script)

        model.setMode(.dailyLimit)
        #expect(model.policy?.dailyLimitMinutes == AppRuleModel.defaultDailyLimitMinutes)
        #expect(model.policy?.blockWindows == [])
        #expect(model.window == nil)

        model.setMode(.scheduleBlock)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.policy?.blockWindows == [schoolHours])
        #expect(model.window == AppRuleModel.defaultWindow)

        model.setMode(.unrestricted)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.policy?.blockWindows == [])
        #expect(model.canSave)
    }

    @Test func goingBackToTheSavedModeIsNoChange() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 45)]))]
        let (model, _, _) = await setup(script)

        model.setMode(.scheduleBlock)
        #expect(model.window == AppRuleModel.defaultWindow)
        #expect(model.canSave)

        model.setMode(.dailyLimit)
        #expect(model.policy?.dailyLimitMinutes == 45)
        #expect(!model.canSave)
    }

    @Test func minutesAndHoursAreOnlyEditedInTheirOwnMode() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        let (model, _, _) = await setup(script)

        model.setWindowStart(ClockTime(hour: 9, minute: 0))
        model.toggleDay(6)
        #expect(model.edited == nil)

        model.setMode(.alwaysBlocked)
        #expect(model.policy == mine)
        #expect(!model.canSave)
    }

    // Review Focus 1.
    @Test func anAlwaysClosedRuleOpenedAndSavedUntouchedStaysAlwaysClosed() async {
        let always = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        let daily = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 30)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [always]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [daily]))]
        let (model, _, fake) = await setup(script)

        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock, .alwaysBlocked])
        #expect(model.selectedMode == .alwaysBlocked)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        model.setMode(.dailyLimit)
        model.setMode(.alwaysBlocked)
        #expect(model.policy == always)
        #expect(!model.canSave)

        model.setMode(.dailyLimit)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: daily, version: 4)])
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock])
        #expect(model.selectedMode == .dailyLimit)
    }

    @Test func anUnknownModeIsKeptUntilAnotherIsChosen() async {
        let future = appPolicy(roblox, name: "Roblox", mode: .unknown("FOCUS_ONLY"), minutes: 20)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [future]))]
        let (model, _, fake) = await setup(script)

        #expect(model.selectedMode == nil)
        #expect(model.modes == [.unrestricted, .dailyLimit, .scheduleBlock])
        #expect(!model.canSave)

        model.setDailyLimitMinutes(60)
        #expect(model.policy == future)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        model.setMode(.unrestricted)
        #expect(model.selectedMode == .unrestricted)
        #expect(model.policy?.dailyLimitMinutes == nil)
        #expect(model.canSave)
    }

    @Test func theLastDayOfAWindowStaysOn() async {
        let oneDay = BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 13, minute: 0), days: [3])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, mode: .scheduleBlock, windows: [oneDay])]))]
        let (model, _, _) = await setup(script)

        model.toggleDay(3)
        #expect(model.window?.days == [3])
        #expect(!model.canSave)

        model.toggleDay(1)
        #expect(model.window?.days == [1, 3])
        #expect(model.canSave)
    }

    @Test func aDayToggledOffAndOnAgainIsNoChange() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, mode: .scheduleBlock, windows: [schoolHours])]))]
        let (model, _, _) = await setup(script)

        model.toggleDay(2)
        #expect(model.canSave)
        model.toggleDay(2)

        #expect(model.window?.days == [1, 2, 3, 4, 5])
        #expect(!model.canSave)
    }

    // Review Focus 4.
    @Test func editingTheFirstWindowKeepsTheSecond() async {
        let evening = BlockWindow(start: ClockTime(hour: 19, minute: 0), end: ClockTime(hour: 21, minute: 0), days: [6, 7])
        let later = BlockWindow(start: ClockTime(hour: 9, minute: 0), end: schoolHours.end, days: schoolHours.days)
        let sent = appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [later, evening])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy(roblox, name: "Roblox", mode: .scheduleBlock, windows: [schoolHours, evening])]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [sent]))]
        let (model, _, fake) = await setup(script)

        model.setWindowStart(ClockTime(hour: 9, minute: 0))
        #expect(model.window == later)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: sent, version: 4)])
        #expect(model.policy?.blockWindows == [later, evening])
    }

    @Test func aScheduleIsSentWithItsHoursDaysAndName() async {
        let sent = appPolicy(
            roblox,
            name: "Roblox",
            mode: .scheduleBlock,
            windows: [BlockWindow(start: ClockTime(hour: 8, minute: 0), end: ClockTime(hour: 14, minute: 30), days: [1, 2, 3, 4])]
        )
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [sent]))]
        let (model, session, fake) = await setup(script)

        model.setMode(.scheduleBlock)
        model.setWindowEnd(ClockTime(hour: 14, minute: 30))
        model.toggleDay(5)
        await model.save()

        #expect(await fake.appPolicyWrites == [RuleWrite(value: sent, version: 4)])
        #expect(session.version == 5)
        #expect(model.notice == .saved)
        #expect(model.edited == nil)
    }

    @Test func theNameComesFromTheSavedRuleWhenThePhoneGaveNone() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [anHour]))]
        let (model, _, fake) = await setup(script, displayName: nil)

        #expect(model.name == "Roblox")
        model.setDailyLimitMinutes(60)
        await model.save()

        #expect(await fake.appPolicyWrites.first?.value.displayName == "Roblox")
    }

    @Test func aConflictShowsTheLatestAndDoesNotResend() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 8, apps: [elsewhere]))]
        script.appPolicy = [.failure(conflict)]
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(model.notice == .conflict)
        #expect(session.version == 8)
        #expect(model.policy == elsewhere)
        #expect(!model.canSave)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    // Review Focus 2.
    @Test func aRuleChangedOnAnotherPhoneIsNeverWrittenOver() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .dailyLimit, minutes: 90)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await session.reload()
        #expect(model.policy?.dailyLimitMinutes == 60)
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.policy == elsewhere)
        #expect(!model.canSave)
    }

    // Review Focus 2.
    @Test func aNewAppGivenARuleOnAnotherPhoneIsNeverWrittenOver() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        model.setMode(.dailyLimit)

        await session.reload()
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.notice == .conflict)
        #expect(model.policy == elsewhere)
        #expect(model.modes.contains(.alwaysBlocked))
    }

    @Test func aNewAppUntouchedThatGotARuleElsewhereHasNothingToSave() async {
        let elsewhere = appPolicy(roblox, name: "Roblox", mode: .alwaysBlocked)
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4)), .success(snapshot(version: 6, apps: [elsewhere]))]
        let (model, session, fake) = await setup(script)
        #expect(model.canSave)

        await session.reload()
        #expect(!model.canSave)
        await model.save()

        #expect(await fake.appPolicyWrites.isEmpty)
        #expect(model.policy == elsewhere)
    }

    // Review Focus 3.
    @Test func anotherAppsRuleSavedMeanwhileIsNoConflict() async {
        let telegram = appPolicy("org.telegram.messenger", name: "Telegram", mode: .scheduleBlock, windows: [schoolHours])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [
            .success(snapshot(version: 5, apps: [mine, telegram])),
            .success(snapshot(version: 6, apps: [anHour, telegram])),
        ]
        let (model, session, fake) = await setup(script)
        let other = AppRuleModel(session: session, packageId: "org.telegram.messenger", displayName: "Telegram")
        model.setDailyLimitMinutes(60)
        other.setMode(.scheduleBlock)

        await other.save()
        await model.save()

        #expect(other.notice == .saved)
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites.map(\.version) == [4, 5])
        #expect(await fake.appPolicyWrites.last?.value == anHour)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(session.version == 6)
    }

    // Review Focus 3.
    @Test func aBedtimeSavedMeanwhileIsNoConflict() async {
        let later = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.bedtime = [.success(snapshot(version: 5, bedtime: later, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 6, bedtime: later, apps: [anHour]))]
        let (model, session, fake) = await setup(script)
        let bedtime = BedtimeModel(session: session)
        model.setDailyLimitMinutes(60)
        bedtime.setStart(ClockTime(hour: 21, minute: 0))

        await bedtime.save()
        await model.save()

        #expect(bedtime.notice == .saved)
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites == [RuleWrite(value: anHour, version: 5)])
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func aFailedSaveKeepsTheEditForAnotherTry() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [
            .failure(.server(status: 500, error: ApiError(code: .internalError))),
            .failure(.server(status: 403, error: ApiError(code: .childNotActive))),
            .failure(.server(status: 400, error: ApiError(code: .validationFailed))),
        ]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()
        #expect(model.message == .serverProblem)
        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)

        await model.save()
        #expect(model.message == .childNotActive)

        await model.save()
        #expect(model.message == .invalidRequest)
        #expect(model.notice == nil)
        #expect(model.canSave)
        #expect(await fake.appPolicyWrites.count == 3)
    }

    @Test func aCancelledSaveSaysNothingAndKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.cancelNextWrite = true
        let (model, session, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(model.notice == nil)
        #expect(model.message == nil)
        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)
        #expect(session.version == 4)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    @Test(.timeLimit(.minutes(5)))
    func twoTapsSaveOnce() async {
        let gate = PauseGate()
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 5, apps: [anHour]))]
        script.writeGate = gate
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        let first = Task { await model.save() }
        await gate.untilPaused()
        #expect(model.isSaving)
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.count == 1)

        await gate.release()
        await first.value
        #expect(model.notice == .saved)
        #expect(await fake.appPolicyWrites.count == 1)
    }

    @Test(.timeLimit(.minutes(5)))
    func anotherScreensSaveInFlightHoldsThisOneBack() async {
        let gate = PauseGate()
        let later = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 30, activeDays: [1, 2, 3, 4, 5, 6, 7])
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.bedtime = [.success(snapshot(version: 5, bedtime: later, apps: [mine]))]
        script.appPolicy = [.success(snapshot(version: 6, bedtime: later, apps: [anHour]))]
        script.writeGate = gate
        let (model, session, fake) = await setup(script)
        let bedtime = BedtimeModel(session: session)
        bedtime.setStart(ClockTime(hour: 21, minute: 0))
        model.setDailyLimitMinutes(60)
        #expect(model.canSave)

        let bedtimeSave = Task { await bedtime.save() }
        await gate.untilPaused()
        #expect(!model.canSave)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)

        await gate.release()
        await bedtimeSave.value
        #expect(model.canSave)

        await model.save()
        #expect(await fake.appPolicyWrites.map(\.version) == [5])
        #expect(model.notice == .saved)
    }

    @Test func aFrozenChildCannotSave() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine]))]
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.save()

        #expect(!model.canSave)
        #expect(await fake.appPolicyWrites.isEmpty)
    }

    @Test func loadingAgainKeepsTheEdit() async {
        var script = FakeFamily.Script()
        script.rules = [.success(snapshot(version: 4, apps: [mine])), .success(snapshot(version: 4, apps: [mine]))]
        let (model, _, fake) = await setup(script)
        model.setDailyLimitMinutes(60)

        await model.load()

        #expect(model.policy?.dailyLimitMinutes == 60)
        #expect(model.canSave)
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
    }

    @Test func nothingIsShownOrSavedBeforeTheRulesArrive() async {
        var script = FakeFamily.Script()
        script.rules = [.failure(offline)]
        let (model, session, fake) = await setup(script)

        #expect(session.loadFailure == .noConnection)
        #expect(model.policy == nil)
        #expect(!model.canSave)
        model.setMode(.dailyLimit)
        await model.save()
        #expect(await fake.appPolicyWrites.isEmpty)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `cannot find 'AppRuleModel' in scope`.

- [ ] **Step 3: `AppRuleModel`**

`NozirKit/Sources/NozirAppFeature/Rules/AppRuleModel.swift` yarating:

```swift
import Foundation
import Observation
import NozirFamily

/// One app's rule (Android `AppRuleEditor`, on a screen of its own: spec D1).
///
/// Only the edit lives here; the saved rule is the session's, found by
/// package. A save is checked against what the edit started from for this
/// package only: another app's rule, or P09/P10/P12 saved meanwhile, moves
/// the version this one writes against and is no conflict.
@MainActor
@Observable
final class AppRuleModel {
    static let defaultDailyLimitMinutes = 30
    /// A school morning (Android `AppRuleDraft.DEFAULT_WINDOW`).
    static let defaultWindow = BlockWindow(
        start: ClockTime(hour: 8, minute: 0),
        end: ClockTime(hour: 13, minute: 0),
        days: [1, 2, 3, 4, 5]
    )

    let session: ChildRulesSession
    let packageId: String
    /// The phone's name for the app when P11 knew one.
    let displayName: String?
    /// The edit; nil while nothing has been touched.
    private(set) var edited: AppPolicy?
    /// What the edit started from: this app's rule as the session held it,
    /// nil for an app that had none. Read only while `edited` is set.
    private(set) var editBase: AppPolicy?
    private(set) var isSaving = false
    private(set) var message: UserMessage?
    private(set) var notice: RuleNotice?

    init(session: ChildRulesSession, packageId: String, displayName: String?) {
        self.session = session
        self.packageId = packageId
        self.displayName = displayName
    }

    /// This app's rule as the session holds it; nil while it has none.
    var saved: AppPolicy? {
        session.snapshot?.appPolicies.first { $0.packageId == packageId }
    }

    /// What the editor shows: the edit, else the saved rule, else "no limit"
    /// for an app without one. nil until the rules have been read.
    var policy: AppPolicy? {
        guard session.snapshot != nil else { return nil }
        return edited ?? saved ?? AppPolicy(packageId: packageId, displayName: sentName, mode: .unrestricted)
    }

    /// Goes with every save: the server rewrites the name each time.
    var sentName: String? {
        displayName ?? saved?.displayName ?? editBase?.displayName
    }

    var name: String {
        AppRuleTexts.name(packageId: packageId, displayName: sentName)
    }

    /// "Doim yopiq" is offered only to a rule saved that way (spec D2): kept,
    /// never one tap away for a rule that is not.
    var modes: [AppPolicyMode] {
        let offered: [AppPolicyMode] = [.unrestricted, .dailyLimit, .scheduleBlock]
        return saved?.mode == .alwaysBlocked ? offered + [.alwaysBlocked] : offered
    }

    /// nil for a mode this app has no segment for: none is lit.
    var selectedMode: AppPolicyMode? {
        guard let mode = policy?.mode, modes.contains(mode) else { return nil }
        return mode
    }

    /// The window the editor shows: a schedule's first. Any others go back as they came.
    var window: BlockWindow? {
        guard let policy, policy.mode == .scheduleBlock else { return nil }
        return policy.blockWindows.first ?? Self.defaultWindow
    }

    /// An app with no rule has one to save as it stands: "no limit" is a row.
    var hasChange: Bool {
        guard let edited else { return session.snapshot != nil && saved == nil }
        guard let editBase else { return true }
        return !Self.same(edited, editBase)
    }

    /// A mode this app does not know is never sent: the server would refuse it.
    var canSave: Bool {
        guard !isSaving, !session.isWriting, !session.isFrozen, session.version != nil, let policy else { return false }
        if case .unknown = policy.mode { return false }
        return hasChange
    }

    func load() async {
        await session.load()
    }

    /// The saved mode again is the saved rule again: tapping away and back is no change.
    func setMode(_ mode: AppPolicyMode) {
        guard modes.contains(mode) else { return }
        let base = edited == nil ? saved : editBase
        edit { policy in
            if let base, base.mode == mode {
                policy = base
            } else {
                policy = Self.withMode(policy, mode)
            }
        }
    }

    func setDailyLimitMinutes(_ minutes: Int) {
        guard policy?.mode == .dailyLimit else { return }
        edit { $0.dailyLimitMinutes = minutes }
    }

    func setWindowStart(_ time: ClockTime) {
        editWindow { $0.start = time }
    }

    func setWindowEnd(_ time: ClockTime) {
        editWindow { $0.end = time }
    }

    /// The last day stays on: the server refuses a window with none.
    func toggleDay(_ day: Int) {
        editWindow { $0.days = RuleDays.toggled(Set($0.days), day).sorted() }
    }

    /// What each mode needs to be a rule the server accepts (Android `AppRuleDraft.withMode`).
    static func withMode(_ policy: AppPolicy, _ mode: AppPolicyMode) -> AppPolicy {
        var changed = policy
        changed.mode = mode
        switch mode {
        case .unrestricted, .alwaysBlocked:
            changed.dailyLimitMinutes = nil
            changed.blockWindows = []
        case .dailyLimit:
            changed.dailyLimitMinutes = policy.dailyLimitMinutes ?? defaultDailyLimitMinutes
            changed.blockWindows = []
        case .scheduleBlock:
            changed.dailyLimitMinutes = nil
            changed.blockWindows = policy.blockWindows.isEmpty ? [defaultWindow] : policy.blockWindows
        case .unknown:
            break
        }
        return changed
    }

    func save() async {
        guard canSave, let policy, let held = session.snapshot else { return }
        isSaving = true
        message = nil
        notice = nil
        defer { isSaving = false }
        // Untouched, only an app with no rule gets here (`hasChange`): its base is none.
        let base = edited == nil ? nil : editBase
        // Changed on another phone under the edit (a refresh brought it): never written over.
        let current = held.appPolicies.first { $0.packageId == packageId }
        guard Self.same(current, base) else {
            discardEdit()
            notice = .conflict
            return
        }
        var named = policy
        named.displayName = sentName
        let body = named
        let service = session.family.service
        let childId = session.childId
        let version = held.version
        let outcome = await session.write { try await service.setAppPolicy(body, of: childId, version: version) }
        switch outcome {
        case .saved:
            discardEdit()
            notice = .saved
        case .conflict:
            discardEdit()
            notice = .conflict
        case .failed(let failure):
            message = failure
        case .cancelled:
            break
        }
    }

    private func edit(_ change: (inout AppPolicy) -> Void) {
        guard var copy = policy else { return }
        if edited == nil {
            editBase = saved
        }
        change(&copy)
        edited = copy
        notice = nil
        message = nil
    }

    private func editWindow(_ change: (inout BlockWindow) -> Void) {
        guard let window else { return }
        edit { policy in
            var changed = window
            change(&changed)
            policy.blockWindows = [changed] + policy.blockWindows.dropFirst()
        }
    }

    /// The name is not part of the rule; the days are a set.
    private static func same(_ lhs: AppPolicy?, _ rhs: AppPolicy?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        guard lhs.mode == rhs.mode,
              lhs.dailyLimitMinutes == rhs.dailyLimitMinutes,
              lhs.blockWindows.count == rhs.blockWindows.count else { return false }
        return zip(lhs.blockWindows, rhs.blockWindows).allSatisfy { left, right in
            left.start == right.start && left.end == right.end && Set(left.days) == Set(right.days)
        }
    }

    private func discardEdit() {
        edited = nil
        editBase = nil
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Rules/AppRuleModel.swift NozirKit/Tests/NozirAppFeatureTests/AppRuleModelTests.swift
```

Xabar: `rules: one app's rule, edited without writing over another phone`

---
### Task 5: Ekranlar — `AppRulesView` (P11) va `AppRuleView` (tahrirlovchi)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Screens/AppRulesView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/AppRuleView.swift`

**Interfaces:**
- Consumes: `AppRulesModel`, `AppRuleTarget` (Task 3), `AppRuleModel` (Task 4), `AppRuleTexts` (Task 2), `RuleMinuteSlider`, `RuleTimePicker`, `RuleDaysSection(title:describesNights:activeDays:onToggle:)`, `RuleSaveFooter`, design system: `NozirCard(tone:)`, `NozirButton(_:variant:size:isLoading:action:)`, `NozirEmptyState`, `NozirErrorState`, `NozirOfflineNotice`, `NozirInlineMessage`, `NozirColor`, `NozirSpacing`, `NozirRadius.field`, `NozirSize.control`, `NozirSize.borderResting`. Design system'da segmentli boshqaruv va qidiruv maydoni yo'q: SwiftUI `Picker(.segmented)` va token'lar bilan bezatilgan oddiy `TextField` ishlatiladi (`NozirTextField` yorliq talab qiladi va `fieldFrame` design system'dan tashqarida ko'rinmaydi).
- L10n (tekshirilgan, `L10n.generated.swift`): `appRulesTitle`, `appRulesSubtitle`, `appRulesNeverBlocked`, `appRulesAdd`, `appRulesAddLabel`, `appRulesEmptyTitle`, `appRulesEmptyBody`, `appRulesSearchPlaceholder`, `appRulesSearchNoMatch(_: String)`, `appRulesEdit(_: String)`, `appRuleDailyLimitSlider`, `appRuleWindowStart`, `appRuleWindowEnd`, `appRuleWindowDays`, `screenAppRulesTitle`, `stateOfflineNotice`, `stateErrorTitle`, `stateActionRetry`, `glyphSearch`, `glyphChevron`.
- Produces: `AppRulesView(model: AppRulesModel, onOpen: @escaping (AppRuleTarget) -> Void)`, `AppRuleView(model: AppRuleModel)`.

- [ ] **Step 1: P11 ro'yxati**

`NozirKit/Sources/NozirAppFeature/Screens/AppRulesView.swift` yarating:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P11 (Android `AppRulesContent`): the app rules, the never-blocked promise,
/// and "Ilova qo'shish" opening the phone's apps, with a search, on this page.
/// A row opens that app's editor on a screen of its own (spec D1).
struct AppRulesView: View {
    @State private var model: AppRulesModel
    private let onOpen: (AppRuleTarget) -> Void
    @Environment(\.l10n) private var l10n

    init(model: AppRulesModel, onOpen: @escaping (AppRuleTarget) -> Void) {
        _model = State(initialValue: model)
        self.onOpen = onOpen
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.appRulesTitle).nozirText(.titleLarge)
                    Text(l10n.appRulesSubtitle).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
                if model.session.snapshot != nil {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    rules
                    NozirCard(tone: .attention) {
                        Text(l10n.appRulesNeverBlocked).nozirText(.bodySmall)
                    }
                    NozirButton(l10n.appRulesAdd, variant: .ghost) { model.toggleChoosing() }
                        .disabled(model.session.isFrozen)
                    if model.isChoosingApp {
                        picker
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
        .navigationTitle(l10n.screenAppRulesTitle)
        .navigationBarTitleDisplayMode(.inline)
        // Once: a tab switch finds the session, the apps and the search as they were.
        .task { await model.load() }
        .refreshable { await model.refresh() }
    }

    @ViewBuilder
    private var rules: some View {
        if model.policies.isEmpty {
            NozirEmptyState(title: l10n.appRulesEmptyTitle, message: l10n.appRulesEmptyBody)
        } else {
            NozirCard {
                ForEach(Array(model.policies.enumerated()), id: \.element.packageId) { index, policy in
                    if index > 0 { Divider() }
                    policyRow(policy)
                }
            }
        }
    }

    /// Name, the rule in one line (accented when it closes the app), and `›`.
    private func policyRow(_ policy: AppPolicy) -> some View {
        let name = model.name(of: policy)
        return Button {
            onOpen(model.open(policy))
        } label: {
            HStack(spacing: NozirSpacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name).nozirText(.body)
                    if let summary = AppRuleTexts.summary(policy, l10n) {
                        Text(summary).nozirText(
                            .bodySmall,
                            color: AppRuleTexts.closesTheApp(policy) ? NozirColor.actionContent : NozirColor.textTertiary
                        )
                    }
                }
                Spacer(minLength: NozirSpacing.small)
                Text(l10n.glyphChevron)
                    .nozirText(.body, color: NozirColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(l10n.appRulesEdit(name))
    }

    /// The phone's apps a rule could be written for. A failed read says so
    /// with Retry (spec D3); nothing left to add is not a search.
    @ViewBuilder
    private var picker: some View {
        if let failure = model.appsLoadFailure, model.installedApps == nil {
            NozirInlineMessage(failure.text(l10n))
            NozirButton(l10n.stateActionRetry, variant: .secondary) {
                Task { await model.retryApps() }
            }
        } else if model.installedApps == nil {
            ProgressView().frame(maxWidth: .infinity)
        } else if model.addableApps.isEmpty {
            NozirEmptyState(title: l10n.appRulesEmptyTitle, message: l10n.appRulesEmptyBody)
        } else {
            searchField
            if model.shownApps.isEmpty {
                Text(l10n.appRulesSearchNoMatch(model.query.trimmingCharacters(in: .whitespacesAndNewlines)))
                    .nozirText(.bodySmall, color: NozirColor.textSecondary)
            } else {
                NozirCard {
                    ForEach(Array(model.shownApps.enumerated()), id: \.element.packageId) { index, app in
                        if index > 0 { Divider() }
                        appRow(app)
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: NozirSpacing.small) {
            Text(l10n.glyphSearch)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .accessibilityHidden(true)
            TextField(
                "",
                text: Binding(get: { model.query }, set: { model.setQuery($0) }),
                prompt: Text(l10n.appRulesSearchPlaceholder).foregroundColor(NozirColor.textTertiary)
            )
            .nozirText(.body)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .accessibilityLabel(l10n.appRulesSearchPlaceholder)
        }
        .padding(.horizontal, NozirSpacing.medium)
        .frame(minHeight: NozirSize.control)
        .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.field)
                .strokeBorder(NozirColor.border, lineWidth: NozirSize.borderResting)
        )
    }

    private func appRow(_ app: InstalledApp) -> some View {
        Button {
            if let target = model.choose(app) {
                onOpen(target)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(AppRuleTexts.name(app)).nozirText(.body)
                Text(l10n.appRulesAddLabel).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: NozirSize.control, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Tahrirlovchi**

`NozirKit/Sources/NozirAppFeature/Screens/AppRuleView.swift` yarating:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// One app's rule (Android `AppRuleEditor`): the mode, then what the mode
/// needs — the daily time, or the hours and the days — and "Saqlash".
struct AppRuleView: View {
    @State private var model: AppRuleModel
    @Environment(\.l10n) private var l10n

    init(model: AppRuleModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                if let policy = model.policy {
                    if model.session.isOffline {
                        NozirOfflineNotice(l10n.stateOfflineNotice)
                    }
                    NozirCard {
                        modePicker
                        if policy.mode == .dailyLimit {
                            RuleMinuteSlider(
                                title: l10n.appRuleDailyLimitSlider,
                                value: Binding(
                                    get: { policy.dailyLimitMinutes ?? AppRuleModel.defaultDailyLimitMinutes },
                                    set: { model.setDailyLimitMinutes($0) }
                                ),
                                range: RuleMinuteRange.appDailyLimit,
                                accessibilityLabel: l10n.appRuleDailyLimitSlider
                            )
                        }
                        if let window = model.window {
                            HStack(spacing: NozirSpacing.medium) {
                                RuleTimePicker(l10n.appRuleWindowStart, time: Binding(get: { window.start }, set: { model.setWindowStart($0) }))
                                RuleTimePicker(l10n.appRuleWindowEnd, time: Binding(get: { window.end }, set: { model.setWindowEnd($0) }))
                            }
                        }
                    }
                    .disabled(model.session.isFrozen)
                    if let window = model.window {
                        NozirCard {
                            RuleDaysSection(title: l10n.appRuleWindowDays, describesNights: false, activeDays: Set(window.days)) {
                                model.toggleDay($0)
                            }
                        }
                        .disabled(model.session.isFrozen)
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
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }

    /// Three segments, a fourth only for a rule saved as "Doim yopiq". A mode
    /// this app does not know lights none until the parent picks one.
    private var modePicker: some View {
        Picker(
            l10n.appRulesEdit(model.name),
            selection: Binding(
                get: { model.selectedMode },
                set: { mode in
                    if let mode { model.setMode(mode) }
                }
            )
        ) {
            ForEach(model.modes, id: \.self) { mode in
                Text(AppRuleTexts.modeLabel(mode, l10n)).tag(mode as AppPolicyMode?)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
```

- [ ] **Step 3: Build**

Run: `bash .superpowers/run.sh app 170`, so'ng `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: `** BUILD SUCCEEDED **` (Swift 6 izolyatsiya ogohlantirishlarisiz), `** TEST SUCCEEDED **`. Ekranlar Task 6 da ulanadi; hozircha ular faqat kompilyatsiya qilinadi.

- [ ] **Step 4: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Screens/AppRulesView.swift NozirKit/Sources/NozirAppFeature/Screens/AppRuleView.swift
```

Xabar: `rules: the P11 list and the app rule editor`

---
### Task 6: Ulash — hub qatori, `RuleScreen`, fabrikalar, ikki tabda navigatsiya

**Files:**
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift` (`RuleScreen`)
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift` (`otherRules`)
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` (`ruleDestination` va ikki chaqiruv)
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`

**Interfaces:**
- Consumes: `AppRulesModel(session:)`, `AppRuleModel(session:packageId:displayName:)`, `AppRuleTarget`, `AppRulesView`, `AppRuleView`, `AppRuleTexts.hubRow(_:_:)`, `l10n.rulesLinkApps`.
- Produces:
  - `RuleScreen.apps(ChildRulesSession)`, `RuleScreen.appRule(ChildRulesSession, packageId: String, displayName: String?)`
  - `SignedInModel.makeAppRulesModel(session: ChildRulesSession) -> AppRulesModel`
  - `SignedInModel.makeAppRuleModel(session: ChildRulesSession, packageId: String, displayName: String?) -> AppRuleModel`
  - `SignedInView.ruleDestination(_ screen: RuleScreen, onOpen: @escaping (RuleScreen) -> Void)` (private)

- [ ] **Step 1: Failing testni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — `theRulesScreensShareTheHubsSession` testidan keyin qo'shing:

```swift
    @Test func theAppRuleScreensShareTheHubsSession() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.children = [.success([ali])]
        script.rules = [.success(snapshot(version: 4, apps: [appPolicy("com.roblox.client", name: "Roblox", mode: .dailyLimit, minutes: 30)]))]
        script.installedApps = [.success([robloxApp, telegramApp])]
        let (model, fake) = setup(script)
        try? await model.family.refresh()
        let session = model.makeRulesSession(childId: ali.id)

        let list = model.makeAppRulesModel(session: session)
        let editor = model.makeAppRuleModel(session: session, packageId: "org.telegram.messenger", displayName: "Telegram")

        #expect(list.session === session)
        #expect(editor.session === session)
        #expect(editor.packageId == "org.telegram.messenger")
        #expect(editor.displayName == "Telegram")

        // Behaviour, not identity: once the session has loaded, neither reads "rules" again,
        // and the phone's apps are read once however often P11 appears.
        await session.load()
        await list.load()
        await editor.load()
        await list.load()
        #expect(await fake.calls.filter { $0 == "rules" }.count == 1)
        #expect(await fake.calls.filter { $0 == "installedApps" }.count == 1)
        #expect(list.addableApps == [telegramApp])
        #expect(editor.name == "Telegram")
        #expect(editor.canSave)
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `bash .superpowers/run.sh NozirAppFeatureTests 170`
Expected: FAIL — `value of type 'SignedInModel' has no member 'makeAppRulesModel'`.

- [ ] **Step 3: `RuleScreen` va fabrikalar**

`NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift` — `RuleScreen` ni butunlay almashtiring:

```swift
/// A screen opened from P09, carrying P09's session so every save there moves
/// the one version all of the child's rules share.
enum RuleScreen: Hashable {
    case bedtime(ChildRulesSession)
    /// P11, the list of app rules.
    case apps(ChildRulesSession)
    /// One app's editor, opened from P11; `displayName` is the phone's name for it when known.
    case appRule(ChildRulesSession, packageId: String, displayName: String?)
    case bonus(ChildRulesSession)
    case locationTracking(ChildRulesSession)
}
```

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — `makeBonusModel(session:)` funksiyasidan keyin:

```swift
    func makeAppRulesModel(session: ChildRulesSession) -> AppRulesModel {
        AppRulesModel(session: session)
    }

    func makeAppRuleModel(session: ChildRulesSession, packageId: String, displayName: String?) -> AppRuleModel {
        AppRuleModel(session: session, packageId: packageId, displayName: displayName)
    }
```

- [ ] **Step 4: Hub qatori**

`NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift` — `otherRules(_:isEnabled:)` ni butunlay almashtiring:

```swift
    /// The way to P10, P11, P12 and P12b, in Android's order.
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
                RuleLinkRow(title: l10n.rulesLinkApps, lines: [AppRuleTexts.hubRow(snapshot.appPolicies, l10n)], isEnabled: isEnabled) {
                    onOpen(.apps(session))
                }
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
```

- [ ] **Step 5: `SignedInView`**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — Home'dagi chaqiruv (`homeDestination` ichida, `case .rules(let childId):` blokidan keyin):

```swift
        case .ruleScreen(let screen):
            ruleDestination(screen)
        }
    }

    @ViewBuilder
    private func profileDestination(_ step: ProfileStep) -> some View {
```

ni quyidagiga almashtiring:

```swift
        case .ruleScreen(let screen):
            ruleDestination(screen) { homePath.append(.ruleScreen($0)) }
        }
    }

    @ViewBuilder
    private func profileDestination(_ step: ProfileStep) -> some View {
```

Profil'dagi chaqiruv va `ruleDestination` ning o'zi — fayl oxiridagi:

```swift
        case .ruleScreen(let screen):
            ruleDestination(screen)
        }
    }

    /// P10, P12 and P12b on the session of the hub that opened them. Each view
    /// keeps the first model it is given (`@State(initialValue:)`), like SafeZoneView.
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

ni quyidagiga almashtiring:

```swift
        case .ruleScreen(let screen):
            ruleDestination(screen) { profilePath.append(.ruleScreen($0)) }
        }
    }

    /// P10, P11, P12 and P12b on the session of the hub that opened them, and
    /// P11's editor on the same one. Each view keeps the first model it is
    /// given (`@State(initialValue:)`), like SafeZoneView. `onOpen` pushes onto
    /// the tab this screen is in.
    @ViewBuilder
    private func ruleDestination(_ screen: RuleScreen, onOpen: @escaping (RuleScreen) -> Void) -> some View {
        switch screen {
        case .bedtime(let session):
            BedtimeView(model: model.makeBedtimeModel(session: session))
        case .apps(let session):
            AppRulesView(model: model.makeAppRulesModel(session: session)) { target in
                onOpen(.appRule(session, packageId: target.packageId, displayName: target.displayName))
            }
        case .appRule(let session, let packageId, let displayName):
            AppRuleView(model: model.makeAppRuleModel(session: session, packageId: packageId, displayName: displayName))
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
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `grep -n "apps row waits" NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift` — hech narsa.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Screens/RulesHubView.swift NozirKit/Sources/NozirAppFeature/Screens/DailyLimitSection.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
```

Xabar: `rules: the apps row on P09 opens P11 and its editor in both tabs`

---
### Task 7: Oxirgi tekshiruv — butun to'plam, l10n va E2E

**Files:** (kod o'zgarmaydi; topilgan xatolar alohida TDD sikli bilan tuzatiladi)

- [ ] **Step 1: Butun to'plam**

Run: `python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check`, keyin `bash .superpowers/run.sh all 170` va `bash .superpowers/run.sh app 170`.
Expected: Python OK, `up to date` (yangi kalit qo'shilmagan), `** TEST SUCCEEDED **` (`NozirFamilyTests` va `NozirAppFeatureTests` ichida yangi testlar bilan), `** BUILD SUCCEEDED **`; `git diff --stat 10061dc -- NozirKit/l10n` — bo'sh.

- [ ] **Step 2: E2E (foydalanuvchi; simulyator + haqiqiy bola telefoni + Android ota-ona ilovasi + haqiqiy backend)**

Har bir bandga "ha" yoki kuzatilgan holat yoziladi:

1. Hub qatori: P09 "Boshqa qoidalar"da tartib Uyqu vaqti → Ilovalar → Bonus → Joylashuv. Qoida yo'q bolada "Hech bir ilovada qoida yoʻq"; qoidalar bor bolada "N ta ilovada qoida bor", "Cheklov yo'q" saqlangan qatorlar sanalmaydi. Muzlatilgan bolada qator o'chiq. Profil va Home (P03 → Qoidalar) tablarida ham.
2. P11: sarlavha va izoh; qoida yo'q → "Hali qoida yoʻq" bo'sh holati; "Telefon, SMS, budilnik va Nozir hech qachon bloklanmaydi" kartasi; qatorlarda nom, xulosa ("Kuniga 45d", "08:00–13:00 yopiq" urg'u rangida, "Doim yopiq" urg'u rangida, "Cheklov yoʻq") va `›`.
3. Ilova qo'shish: "Ilova qoʻshish" → qidiruv maydoni va telefon ilovalari ("Qoida qoʻshish mumkin"); qoidasi borlar (shu jumladan "Cheklov yo'q") va telefon/SMS/Nozir ro'yxatda yo'q. Qidiruv: "gram" → Telegram/Instagram; o'zbekcha nomni `'` yoki `’` bilan yozib topish; mos kelmasa "«…» boʻyicha ilova topilmadi…". Yopib ochish — maydon bo'sh.
4. Ilovalar yuklanmasa: tarmoqni o'chirib P11 ni birinchi marta ochish va "Ilova qoʻshish" → xato matni va "Qayta urinish"; tarmoq qaytgach "Qayta urinish" → ro'yxat.
5. Uch rejimni saqlash: yangi ilovani "Kunlik vaqt" (15d–4s, qadam 15, sukut 30d), "Jadval" (sukut 08:00–13:00, Du–Ju; oxirgi kun o'chmaydi) va "Cheklov yo'q" bilan saqlash → "Saqlandi. {Ism} telefoni…"; ekran ochiq qoladi; bola telefoni keyingi aloqada yangi qoidani qo'llaydi; Android ota-ona ilovasidagi P11 da ham shu qoidalar va nomlar.
6. "Cheklov yo'q" saqlangan ilova P11 ro'yxatida "Cheklov yoʻq" bo'lib qoladi va qo'shish ro'yxatida yo'q.
7. Doim yopiq: Android'da ilovaga "Doim yopiq" qo'yish; iOS'da ochish → 4-segment "Doim yopiq" tanlangan, "Saqlash" o'chiq; boshqa rejimga o'tib qaytish → yana o'chiq; boshqa rejimni saqlash → 4-segment yo'qoladi, Android'da yangi rejim.
8. To'qnashuv: iOS'da tahrirlovchi ochiq; Android'da shu ilova qoidasini o'zgartirish; iOS'da boshqa qiymat bilan saqlash → "qoidalar oʻzgargan…" xabari, Android qiymati ko'rinadi, iOS qiymati yuborilmagan. Keyin P11 da pull-to-refresh va qayta tahrirlash → to'qnashuvsiz saqlanadi.
9. Soxta to'qnashuv yo'q: tahrirlovchida qoralama qoldirib orqaga, P10 ni saqlash, boshqa ilova qoidasini saqlash, qaytib birinchi ilovani saqlash → hammasi saqlanadi, to'qnashuv xabari yo'q.
10. Muzlatilgan bola (bepul reja, ikkinchi bola): hub'da Ilovalar qatori o'chiq; P11 ochiq paytda muzlasa — "Ilova qoʻshish" va tahrirlovchi boshqaruvlari o'chiq, "Saqlash" o'chiq.
11. Tahrirlovchida qoralama qoldirib boshqa tabga o'tish va qaytish → qoralama joyida; P11 da qidiruv matni joyida.
12. Uch til va ikki tema: P09 qatori, P11, qo'shish ro'yxati, tahrirlovchi (4 segmentli holat ham) matnlari va ranglari to'g'ri; skrinshotlar (Cmd+S).

- [ ] **Step 3: Natijani yozish**

Ledger'ga (`.superpowers/sdd/<plan>/progress.md`) E2E natijalari va kechiktirilgan kichik masalalar yoziladi. Push foydalanuvchida; keyin `superpowers:finishing-a-development-branch`.
