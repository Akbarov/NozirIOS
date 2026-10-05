# Nozir iOS — 2b: Home va hisobotlar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Home (P05) bolalarning bugungi holatini va faol SOS'ni ko'rsatadi; kunlik AI xulosa (P06), haftalik ekran vaqti grafigi (P07) va ilovalar bo'yicha vaqt (P08) ochiladi; Statistika tabida bola tanlagich bor.

**Architecture:** Yangi `NozirInsights` moduli — `/v1/parent/home`, `/summaries/{daily,weekly}`, `/usage/{daily,apps}` uchun `InsightsApi` va `InsightsService` protokoli, `LocalDate` turi. Grafik mantiqi (`ChartMath`) va matn/yig'ish yordamchilari toza funksiyalarda; grafiklar oddiy SwiftUI. Ekran modellari (`HomeModel`, `DailySummaryModel`, `WeeklyReportModel`, `AppUsageModel`, `StatisticsModel`) `@MainActor @Observable`, `FakeInsights` va 2a dagi `FakeFamily` bilan testlanadi.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), Observation, Swift Testing; uchinchi tomon kutubxonasi yo'q.

**Spec:** `docs/superpowers/specs/2026-10-05-nozir-ios-home-reports-design.md` (oldingi: 2a va poydevor spec'lari)

## Global Constraints

- iOS 17.0; `swift-tools-version: 6.0` (Swift 6, strict concurrency). Swift Charts va uchinchi tomon kutubxonasi ishlatilmaydi.
- Har bir `/v1/parent/*` chaqiruvi poydevordagi `ApiClient` orqali (`requiresAuth: true`); bola id'si yo'lda kichik harflar bilan (`uuidString.lowercased()`).
- Server `message` maydoni hech qachon ko'rsatilmaydi; foydalanuvchi matni faqat `L10n` (`@Environment(\.l10n)`), xatolar `UserMessage` orqali.
- Sana server bilan `YYYY-MM-DD` (`LocalDate`); hafta ISO-8601, Dushanbadan.
- Kesh faqat xotirada; diskka hech narsa yozilmaydi.
- Yangilash: har ekran ochilganda; Home ilova qayta faollashganda ham. P05 da bola filtri har ochilishda "Hammasi" ga qaytadi.
- P05: faol SOS banneri ko'rinadi va SOS oynasini ochadi; vaqt so'rovlari, himoya qatori, qo'ng'iroqcha yashirin.
- P07: 53 hafta (joriy + 52), joriy hafta oxirgi; grafik faqat `usedMinutes`; nol asosli balandlik, birinchi teng cho'qqi ajratiladi, hammasi 0 bo'lsa cho'qqi yo'q.
- P08: top-4 ilova + "Boshqalar" (`nozir.other_apps`), "Boshqalar" doim oxirida, foiz `daqiqa × 100 / jami` (butun; jami 0 → 0).
- Commit: `git add -A` taqiqlangan, faqat aniq yo'llar; push foydalanuvchida; commit muhiti va izoh qatorlari 2a dagidek.
- Swift kodi test ishlaguncha "yozilgan, tekshirilmagan".

## Spec'dan chetlanishlar (reja bosqichida)

| # | Spec | Reja | Sabab |
|---|---|---|---|
| E1 | `activeSos` yo'q bo'lsa eskirgan `activeSosId` ga qaytish | Faqat `activeSos` o'qiladi | `activeSosId` da bola ham, vaqt ham yo'q — banner chizib bo'lmaydi; backend ikkalasini birga yuboradi |
| E2 | P06: kunlik va haftalik parallel | Avval kunlik, keyin uning `periodEnd` Dushanbasi uchun haftalik | Sana berilmaganda haftani faqat kunlik javob biladi |
| E3 | P07: usage va haftalik xulosa parallel | Ketma-ket (avval usage) | Kod sodda, test deterministik; kechikish bir so'rov |
| E4 | — | iOS `weekly_chart_day_separator` = `", "` (qo'shtirnoqli) | 2a dagi `bedtime_days_separator` bilan bir xil sabab: Android oxirgi bo'shliqni kesadi |
| E5 | — | `HomePlaceholderView` o'chiriladi; `ios_home_placeholder_*` matnlari qoladi (ishlatilmaydi) | P05 uning o'rnini oladi; matnni o'chirish generatsiyani o'zgartiradi, foydasi yo'q |
| E6 | Holat komponentlarida skelet | Yuklanishda `ProgressView` | Skelet faqat bezak; mantiq va testga ta'siri yo'q, keyin qo'shish oson |
| E7 | `SosAlertModel`, `NozirSegmentedControl` | `SosAlert` qiymat turi; tizim `Picker(.segmented)` | Oynada holat yo'q (vaqt `TimelineView` bilan); spec'ning o'zi tizim tanlagichiga ruxsat bergan |

## Review Focus

1. **P08 da oraliq tez almashtirildi** ("Bugun" javobi kech keldi) — oxirgi tanlangan oraliq ma'lumoti qolishi kerak → Task 9 `aLateAnswerForAnOldRangeIsIgnored`.
2. **Bola telefoni oflayn, lekin `placeLabel` bor** — eski joy hozirgidek ko'rsatilmasligi kerak → Task 6 `anOfflinePhoneNeverShowsAPlace`.
3. **Yakshanba yoki yil boshida hafta chegarasi** — to'g'ri Dushanba → Task 1 `mondayOfAnyDay`.
4. **Statistika tabida tanlangan bola Profildan o'chirildi** — birinchi bolaga qaytish → Task 10 `aRemovedChildFallsBackToTheFirst`.
5. **SOS javobida ism yo'q va bolaning raqami yo'q** — ism `FamilyStore` dan, qo'ng'iroq tugmasi o'chiq va sababi yoziladi → Task 5 `aNamelessSosTakesTheNameFromTheFamily`, `aChildWithoutANumberCannotBeCalled`.

---

## Fayl xaritasi

**Yangi:** `NozirKit/Sources/NozirInsights/{LocalDate,InsightModels,InsightsService,InsightsApi}.swift`; `NozirKit/Sources/NozirDesignSystem/ChartMath.swift`; `NozirKit/Sources/NozirDesignSystem/Components/{NozirCharts,NozirStates,NozirChildSwitcher}.swift`; `NozirKit/Sources/NozirAppFeature/Insights/{AppUsageFolding,InsightTexts,SosAlert,InsightStyle}.swift`; `NozirKit/Sources/NozirAppFeature/Insights/{HomeModel,DailySummaryModel,WeeklyReportModel,AppUsageModel,StatisticsModel}.swift`; `NozirKit/Sources/NozirAppFeature/Screens/{SosViews,HomeView,DailySummaryView,WeeklyReportView,AppUsageView,StatisticsView}.swift`; testlar `NozirKit/Tests/NozirInsightsTests/{InsightsFixtures,LocalDateTests,InsightsApiTests}.swift`, `NozirKit/Tests/NozirDesignSystemTests/{ChartMathTests,ChildSwitcherTests}.swift`, `NozirKit/Tests/NozirAppFeatureTests/{FakeInsights,InsightTextsTests,SosAlertTests,HomeModelTests,DailySummaryModelTests,WeeklyReportModelTests,AppUsageModelTests,StatisticsModelTests}.swift`.

**O'zgaradi:** `NozirKit/Package.swift`, `NozirKit/l10n/ios/values/strings.xml` (+ generatsiya), `NozirDesignSystem/NozirColor.swift`, `Components/{NozirCard,NozirRows}.swift`, `NozirAppFeature/{AppModel,SignedInModel,AppEnvironment}.swift`, `Screens/SignedInView.swift`, `Tests/NozirAppFeatureTests/{AppModelTests,SignedInModelTests}.swift`. **O'chiriladi:** `Screens/HomePlaceholderView.swift`.

## Ishni boshlash

Branch `home-reports` (spec commit fedd002) allaqachon ochilgan. Swift testlari: `bash .superpowers/run.sh <Target> 170` (watcher), `all`, `app`. Raqamli target nomlari (`NozirL10nTests`) uchun `all`.

---
### Task 1: `NozirInsights` moduli va `LocalDate`

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirInsights/LocalDate.swift`
- Test: `NozirKit/Tests/NozirInsightsTests/LocalDateTests.swift`

**Interfaces:**
- Consumes: poydevor `NozirNetworking` (faqat Package bog'liqligi).
- Produces:
  - Package: `.target(name: "NozirInsights", dependencies: ["NozirNetworking"])`; `.testTarget(name: "NozirInsightsTests", dependencies: ["NozirInsights", "NozirNetworking", "NozirTestSupport"])`; `NozirAppFeature` va `NozirAppFeatureTests` bog'liqliklarida `"NozirInsights"`.
  - `public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible { year: Int; month: Int; day: Int; init?(year:month:day:); init?(_ text: String); init(_ date: Date, in calendar: Calendar); text: String; adding(days: Int) -> LocalDate; isoWeekday: Int /* 1 = Dushanba … 7 = Yakshanba */; monday: LocalDate }`

- [ ] **Step 1: Package**

`NozirKit/Package.swift` — `targets` ro'yxatini quyidagicha o'zgartiring (yangi qatorlar: `NozirInsights`, `NozirInsightsTests`, va ikki joyda `"NozirInsights"`):

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirL10n"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirFamily", dependencies: ["NozirNetworking"]),
        .target(name: "NozirInsights", dependencies: ["NozirNetworking"]),
        .target(name: "NozirDesignSystem"),
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n", "NozirFamily", "NozirInsights"]
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
        .testTarget(name: "NozirDesignSystemTests", dependencies: ["NozirDesignSystem"]),
        .testTarget(name: "NozirL10nTests", dependencies: ["NozirL10n"]),
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n", "NozirFamily", "NozirDesignSystem", "NozirInsights"]
        ),
    ]
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirInsightsTests/LocalDateTests.swift`:

```swift
import Foundation
import Testing
@testable import NozirInsights

private func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

@Suite struct LocalDateTests {
    @Test func theServersTextReadsAndWritesBack() throws {
        let date = try #require(LocalDate("2026-10-05"))

        #expect(date.year == 2026)
        #expect(date.month == 10)
        #expect(date.day == 5)
        #expect(date.text == "2026-10-05")
        #expect(LocalDate(year: 2026, month: 1, day: 9)?.text == "2026-01-09")
    }

    @Test(arguments: ["2026-02-30", "2026-1-5", "20261005", "2026-13-01", "", "2026-10-05T00:00", "２０２６-10-05"])
    func anythingElseIsNotADate(text: String) {
        #expect(LocalDate(text) == nil)
    }

    @Test func daysCrossMonthsAndYears() {
        #expect(day("2026-12-30").adding(days: 3) == day("2027-01-02"))
        #expect(day("2026-03-01").adding(days: -1) == day("2026-02-28"))
        #expect(day("2028-03-01").adding(days: -1) == day("2028-02-29"))
    }

    @Test func weekdaysAreCountedFromMonday() {
        #expect(day("2026-10-05").isoWeekday == 1)
        #expect(day("2026-10-08").isoWeekday == 4)
        #expect(day("2026-10-11").isoWeekday == 7)
    }

    // Review Focus 3.
    @Test func mondayOfAnyDay() {
        #expect(day("2026-10-05").monday == day("2026-10-05"))
        #expect(day("2026-10-11").monday == day("2026-10-05"))
        #expect(day("2026-01-01").monday == day("2025-12-29"))
        #expect(day("2026-03-01").monday == day("2026-02-23"))
    }

    @Test func theDayDependsOnThePhonesZone() throws {
        let moment = try #require(ISO8601DateFormatter().date(from: "2026-10-04T20:00:00Z"))

        #expect(LocalDate(moment, in: calendar("Asia/Tashkent")) == day("2026-10-05"))
        #expect(LocalDate(moment, in: calendar("UTC")) == day("2026-10-04"))
    }

    @Test func daysCompareInCalendarOrder() {
        #expect(day("2026-09-30") < day("2026-10-01"))
        #expect(day("2025-12-31") < day("2026-01-01"))
        #expect(!(day("2026-10-05") < day("2026-10-05")))
    }

    @Test func jsonCarriesTheText() throws {
        struct Box: Codable, Equatable {
            let date: LocalDate
        }

        let box = try JSONDecoder().decode(Box.self, from: Data(#"{"date":"2026-10-05"}"#.utf8))
        #expect(box.date == day("2026-10-05"))
        let written = try String(decoding: JSONEncoder().encode(box), as: UTF8.self)
        #expect(written == #"{"date":"2026-10-05"}"#)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Box.self, from: Data(#"{"date":"5.10.2026"}"#.utf8))
        }
    }
}
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirInsightsTests` (Mac'dagi watcher: `bash .superpowers/run.sh NozirInsightsTests 170`)
Expected: FAIL — `NozirInsights` manbasi yo'q / `cannot find 'LocalDate' in scope`.

- [ ] **Step 4: `LocalDate`**

`NozirKit/Sources/NozirInsights/LocalDate.swift`:

```swift
import Foundation

/// A day with no time and no zone, as the server writes it: `YYYY-MM-DD`
/// (`java.time.LocalDate`). Arithmetic runs on a fixed UTC Gregorian calendar,
/// so adding days never meets a daylight-saving gap; only `init(_:in:)` reads
/// the phone's calendar.
public struct LocalDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public init?(year: Int, month: Int, day: Int) {
        let parts = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), parts.isValidDate(in: Self.utc) else { return nil }
        self.init(checked: year, month, day)
    }

    /// Exactly `YYYY-MM-DD` with ASCII digits; anything else is nil.
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { ("0"..."9").contains($0) } }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The day `date` falls on in `calendar` (the phone's, for "today").
    public init(_ date: Date, in calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(checked: parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    private init(checked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public var text: String {
        Self.padded(year, 4) + "-" + Self.padded(month, 2) + "-" + Self.padded(day, 2)
    }

    public var description: String { text }

    public func adding(days: Int) -> LocalDate {
        let moved = Self.utc.date(byAdding: .day, value: days, to: midnight) ?? midnight
        return LocalDate(moved, in: Self.utc)
    }

    /// ISO-8601: Monday is 1, Sunday is 7.
    public var isoWeekday: Int {
        let weekday = Self.utc.component(.weekday, from: midnight) // 1 = Sunday
        return (weekday + 5) % 7 + 1
    }

    /// The Monday of this day's ISO week.
    public var monday: LocalDate {
        adding(days: 1 - isoWeekday)
    }

    public static func < (lhs: LocalDate, rhs: LocalDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = LocalDate(text) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a YYYY-MM-DD day: \(text)")
        }
        self = date
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }

    private var midnight: Date {
        Self.utc.date(from: DateComponents(year: year, month: month, day: day)) ?? Date(timeIntervalSince1970: 0)
    }

    private static func padded(_ value: Int, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirInsightsTests`
Expected: `** TEST SUCCEEDED **`; `LocalDateTests` ning barcha testlari o'tadi.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirInsights/LocalDate.swift NozirKit/Tests/NozirInsightsTests/LocalDateTests.swift
```

Xabar: `insights: a day as the server writes it, and its Monday`

---
### Task 2: `InsightsApi` — home, xulosalar, foydalanish

**Files:**
- Create: `NozirKit/Sources/NozirInsights/InsightModels.swift`
- Create: `NozirKit/Sources/NozirInsights/InsightsService.swift`
- Create: `NozirKit/Sources/NozirInsights/InsightsApi.swift`
- Test: `NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift`
- Test: `NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocalDate`); poydevor `ApiClient`, `ApiRequest`, `ApiFailure` (`isNotFound`), `NozirTestSupport` (`FakeTransport`, `.ok`, `.error`).
- Produces (hammasi `public`):
  - `enum StatusLevel: String, Sendable, Decodable { good, attention, action, critical }` — noma'lum qiymat → `.good`.
  - `struct ChildHomeCard: Decodable, Equatable, Sendable, Identifiable { id (childId), displayName, avatarKey: String?, usedMinutes, limitMinutes, statusLevel, needsAttention, summarySentence: String?, placeLabel: String?, placeSince: Date?, deviceOnline, lastSeenAt: Date? }` va hamma maydonli `init(id:displayName:avatarKey:usedMinutes:limitMinutes:statusLevel:needsAttention:summarySentence:placeLabel:placeSince:deviceOnline:lastSeenAt:)` (id va displayName'dan boshqasi sukutli).
  - `struct ActiveSos: Decodable, Equatable, Sendable { sosId, childId, childName: String?, triggeredAt: Date }` + `init(sosId:childId:childName:triggeredAt:)`.
  - `struct ParentHome: Decodable, Equatable, Sendable { date: LocalDate; children: [ChildHomeCard]; familySummary: String?; activeSos: ActiveSos? }` + `init(date:children:familySummary:activeSos:)`.
  - `struct InsightSummary: Decodable, Equatable, Sendable, Identifiable { id (summaryId), childId, periodStart, periodEnd: LocalDate, paragraphs: [String], recommendation: String?, conversationQuestion: String?, riskLevel: StatusLevel }` + `init(id:childId:periodStart:periodEnd:paragraphs:recommendation:conversationQuestion:riskLevel:)`.
  - `struct DailyUsage: Decodable, Equatable, Sendable { date: LocalDate; usedMinutes: Int; limitMinutes: Int }` + init.
  - `enum UsageRange: String, CaseIterable, Sendable, Decodable { today = "TODAY", lastSevenDays = "LAST_7_DAYS", lastThirtyDays = "LAST_30_DAYS" }` — noma'lum → `.today`.
  - `struct AppUsageEntry: Decodable, Hashable, Sendable { packageId; displayName (yo'q bo'lsa ""); minutes; static let otherAppsPackageId = "nozir.other_apps"; isOtherApps: Bool }` + `init(packageId:displayName:minutes:)`.
  - `struct AppBreakdown: Decodable, Equatable, Sendable { range: UsageRange; totalMinutes: Int; entries: [AppUsageEntry] }` + init.
  - `protocol InsightsService: Sendable { home(); dailySummary(of:on:); weeklySummary(of:weekStart:); dailyUsage(of:from:to:); appUsage(of:range:) }` (imzolar quyida).
  - `struct InsightsApi: InsightsService { init(client: ApiClient) }`.

- [ ] **Step 1: Test yordamchilari**

`NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift`:

```swift
import Foundation
import NozirInsights
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the insight calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func insightsApi(_ replies: [FakeTransport.Reply]) -> (InsightsApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (InsightsApi(client: client), transport)
}

let aliId = UUID(uuidString: "0B0E2A52-6A2F-4D8B-9A55-6F1B2A0C1D01")!
let sosId = UUID(uuidString: "5D0C7E11-2B44-4C1A-8F0E-3A9B6C2D7E10")!
let summaryId = UUID(uuidString: "9A1B2C3D-4E5F-4A6B-8C7D-0E1F2A3B4C5D")!

func instant(_ text: String) -> Date {
    ISO8601DateFormatter().date(from: text)!
}

extension URLRequest {
    /// The query string as a dictionary, for asserting what was asked.
    var queryParameters: [String: String] {
        let items = url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }
}

/// `ParentHomeResponse` as the backend writes it (`non_null`: absent, not null).
let fullHomeJSON = """
{"date":"2026-10-05","children":[{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","displayName":"Ali",\
"ageGroup":"STAR","avatarKey":"teal","usedMinutes":95,"limitMinutes":120,"statusLevel":"ATTENTION",\
"needsAttention":true,"summarySentence":"Bugun tinch kun.","placeLabel":"Maktab",\
"placeSince":"2026-10-05T03:10:00Z","deviceOnline":true,"lastSeenAt":"2026-10-05T07:02:11Z"}],\
"familySummary":"Hammasi joyida.","pendingExtraTimeRequests":[],"pendingChallengeApprovals":0,\
"protection":{"level":"HEALTHY","childrenNeedingAttention":[]},\
"activeSosId":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10",\
"activeSos":{"sosId":"5d0c7e11-2b44-4c1a-8f0e-3a9b6c2d7e10","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
"childName":"Ali","triggeredAt":"2026-10-05T07:00:00Z"}}
"""

/// The least the backend can send: no optional field, a status this app does not know.
let bareHomeJSON = """
{"date":"2026-10-05","children":[{"childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01","displayName":"Ali",\
"ageGroup":"STAR","usedMinutes":0,"limitMinutes":120,"statusLevel":"SOMETHING_NEW","needsAttention":false,\
"deviceOnline":false}],"pendingExtraTimeRequests":[],"pendingChallengeApprovals":0,\
"protection":{"level":"HEALTHY","childrenNeedingAttention":[]}}
"""

/// `InsightSummaryResponse`.
func summaryJSON(period: String = "DAILY", start: String = "2026-10-04", end: String = "2026-10-04", risk: String = "GOOD") -> String {
    """
    {"summaryId":"9a1b2c3d-4e5f-4a6b-8c7d-0e1f2a3b4c5d","childId":"0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01",\
    "period":"\(period)","periodStart":"\(start)","periodEnd":"\(end)",\
    "paragraphs":["Ali kuni tinch otdi.","Kechqurun video koproq."],"recommendation":"Birga sayr qiling.",\
    "conversationQuestion":"Bu hafta nima yoqdi?","riskLevel":"\(risk)","source":"AI",\
    "generatedAt":"2026-10-05T01:00:00Z","contentNotice":"insight.notice.no_messages_read"}
    """
}
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirInsights

private let childPath = "/v1/parent/children/0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01"

@Suite struct InsightsApiTests {
    @Test func homeReadsTheServersShape() async throws {
        let (api, transport) = insightsApi([.ok(fullHomeJSON)])

        let home = try await api.home()

        #expect(home.date == LocalDate("2026-10-05"))
        #expect(home.familySummary == "Hammasi joyida.")
        #expect(home.children == [ChildHomeCard(
            id: aliId,
            displayName: "Ali",
            avatarKey: "teal",
            usedMinutes: 95,
            limitMinutes: 120,
            statusLevel: .attention,
            needsAttention: true,
            summarySentence: "Bugun tinch kun.",
            placeLabel: "Maktab",
            placeSince: instant("2026-10-05T03:10:00Z"),
            deviceOnline: true,
            lastSeenAt: instant("2026-10-05T07:02:11Z")
        )])
        #expect(home.activeSos == ActiveSos(sosId: sosId, childId: aliId, childName: "Ali", triggeredAt: instant("2026-10-05T07:00:00Z")))
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/home")
        #expect(request.queryParameters.isEmpty)
    }

    @Test func aHomeWithNothingOptionalStillLoads() async throws {
        let (api, _) = insightsApi([.ok(bareHomeJSON)])

        let home = try await api.home()

        let card = try #require(home.children.first)
        #expect(card.statusLevel == .good)
        #expect(card.avatarKey == nil)
        #expect(card.summarySentence == nil)
        #expect(card.placeLabel == nil)
        #expect(card.placeSince == nil)
        #expect(!card.deviceOnline)
        #expect(home.familySummary == nil)
        #expect(home.activeSos == nil)
    }

    @Test func theDailySummaryWithoutADayIsTheLatest() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON())])

        let summary = try await api.dailySummary(of: aliId, on: nil)

        #expect(summary == InsightSummary(
            id: summaryId,
            childId: aliId,
            periodStart: LocalDate("2026-10-04")!,
            periodEnd: LocalDate("2026-10-04")!,
            paragraphs: ["Ali kuni tinch otdi.", "Kechqurun video koproq."],
            recommendation: "Birga sayr qiling.",
            conversationQuestion: "Bu hafta nima yoqdi?",
            riskLevel: .good
        ))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/summaries/daily")
        #expect(request.queryParameters.isEmpty)
    }

    @Test func aDayIsSentAsTheServerWritesIt() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON())])

        _ = try await api.dailySummary(of: aliId, on: LocalDate("2026-10-04"))

        let request = try #require(await transport.requests.first)
        #expect(request.queryParameters == ["date": "2026-10-04"])
    }

    @Test func aSummaryThatDoesNotExistIsNotFound() async {
        let (api, _) = insightsApi([.error(404, code: "NOT_FOUND")])

        do {
            _ = try await api.dailySummary(of: aliId, on: nil)
            Issue.record("expected not found")
        } catch let failure as ApiFailure {
            #expect(failure.isNotFound)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func theWeeklySummaryIsAskedForByItsMonday() async throws {
        let (api, transport) = insightsApi([.ok(summaryJSON(period: "WEEKLY", start: "2026-09-28", end: "2026-10-04", risk: "ACTION"))])

        let summary = try await api.weeklySummary(of: aliId, weekStart: LocalDate("2026-09-28")!)

        #expect(summary.riskLevel == .action)
        #expect(summary.periodEnd == LocalDate("2026-10-04"))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/summaries/weekly")
        #expect(request.queryParameters == ["weekStart": "2026-09-28"])
    }

    @Test func dailyUsageSendsBothEnds() async throws {
        let body = #"[{"date":"2026-09-28","usedMinutes":130,"limitMinutes":120},{"date":"2026-09-29","usedMinutes":0,"limitMinutes":120}]"#
        let (api, transport) = insightsApi([.ok(body)])

        let days = try await api.dailyUsage(of: aliId, from: LocalDate("2026-09-28")!, to: LocalDate("2026-10-04")!)

        #expect(days == [
            DailyUsage(date: LocalDate("2026-09-28")!, usedMinutes: 130, limitMinutes: 120),
            DailyUsage(date: LocalDate("2026-09-29")!, usedMinutes: 0, limitMinutes: 120),
        ])
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/usage/daily")
        #expect(request.queryParameters == ["from": "2026-09-28", "to": "2026-10-04"])
    }

    @Test(arguments: [(UsageRange.today, "TODAY"), (.lastSevenDays, "LAST_7_DAYS"), (.lastThirtyDays, "LAST_30_DAYS")])
    func appUsageSendsTheRange(range: UsageRange, raw: String) async throws {
        let body = #"{"range":"\#(raw)","totalMinutes":0,"entries":[]}"#
        let (api, transport) = insightsApi([.ok(body)])

        let breakdown = try await api.appUsage(of: aliId, range: range)

        #expect(breakdown == AppBreakdown(range: range, totalMinutes: 0, entries: []))
        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == childPath + "/usage/apps")
        #expect(request.queryParameters == ["range": raw])
    }

    @Test func appEntriesAreReadAsSentAndUnknownRangesAreToday() async throws {
        let body = """
        {"range":"LAST_YEAR","totalMinutes":75,"entries":[\
        {"packageId":"com.google.android.youtube","displayName":"YouTube","minutes":50},\
        {"packageId":"nozir.other_apps","minutes":25}]}
        """
        let (api, _) = insightsApi([.ok(body)])

        let breakdown = try await api.appUsage(of: aliId, range: .today)

        #expect(breakdown.range == .today)
        #expect(breakdown.totalMinutes == 75)
        #expect(breakdown.entries == [
            AppUsageEntry(packageId: "com.google.android.youtube", displayName: "YouTube", minutes: 50),
            AppUsageEntry(packageId: "nozir.other_apps", displayName: "", minutes: 25),
        ])
        #expect(!breakdown.entries[0].isOtherApps)
        #expect(breakdown.entries[1].isOtherApps)
    }
}
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirInsightsTests`
Expected: FAIL — `cannot find 'InsightsApi' in scope`.

- [ ] **Step 4: Modellar**

`NozirKit/Sources/NozirInsights/InsightModels.swift`:

```swift
import Foundation

/// `RiskLevel` on the wire (the home card calls it `statusLevel`). A value this
/// app does not know reads as good rather than breaking the list.
public enum StatusLevel: String, Sendable, Decodable {
    case good = "GOOD"
    case attention = "ATTENTION"
    case action = "ACTION"
    case critical = "CRITICAL"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StatusLevel(rawValue: raw) ?? .good
    }
}

/// `ChildHomeCardDto`. `ageGroup` is not read: the age comes from the family list.
public struct ChildHomeCard: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let avatarKey: String?
    public let usedMinutes: Int
    public let limitMinutes: Int
    public let statusLevel: StatusLevel
    /// The only thing that lifts a card to the top; a quiet card is "no news".
    public let needsAttention: Bool
    public let summarySentence: String?
    public let placeLabel: String?
    public let placeSince: Date?
    public let deviceOnline: Bool
    public let lastSeenAt: Date?

    public init(
        id: UUID,
        displayName: String,
        avatarKey: String? = nil,
        usedMinutes: Int = 0,
        limitMinutes: Int = 0,
        statusLevel: StatusLevel = .good,
        needsAttention: Bool = false,
        summarySentence: String? = nil,
        placeLabel: String? = nil,
        placeSince: Date? = nil,
        deviceOnline: Bool = true,
        lastSeenAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarKey = avatarKey
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
        self.statusLevel = statusLevel
        self.needsAttention = needsAttention
        self.summarySentence = summarySentence
        self.placeLabel = placeLabel
        self.placeSince = placeSince
        self.deviceOnline = deviceOnline
        self.lastSeenAt = lastSeenAt
    }

    enum CodingKeys: String, CodingKey {
        case id = "childId"
        case displayName, avatarKey, usedMinutes, limitMinutes, statusLevel, needsAttention
        case summarySentence, placeLabel, placeSince, deviceOnline, lastSeenAt
    }
}

/// `ActiveSosDto`: the unanswered alarm. `childName` is nil when the child was removed.
public struct ActiveSos: Decodable, Equatable, Sendable {
    public let sosId: UUID
    public let childId: UUID
    public let childName: String?
    public let triggeredAt: Date

    public init(sosId: UUID, childId: UUID, childName: String?, triggeredAt: Date) {
        self.sosId = sosId
        self.childId = childId
        self.childName = childName
        self.triggeredAt = triggeredAt
    }
}

/// `ParentHomeResponse`, the parts P05 draws in this slice. The legacy
/// `activeSosId` is not read (plan deviation E1).
public struct ParentHome: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let children: [ChildHomeCard]
    public let familySummary: String?
    public let activeSos: ActiveSos?

    public init(date: LocalDate, children: [ChildHomeCard], familySummary: String? = nil, activeSos: ActiveSos? = nil) {
        self.date = date
        self.children = children
        self.familySummary = familySummary
        self.activeSos = activeSos
    }

    enum CodingKeys: String, CodingKey {
        case date, children, familySummary, activeSos
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(LocalDate.self, forKey: .date)
        children = try container.decodeIfPresent([ChildHomeCard].self, forKey: .children) ?? []
        familySummary = try container.decodeIfPresent(String.self, forKey: .familySummary)
        activeSos = try container.decodeIfPresent(ActiveSos.self, forKey: .activeSos)
    }
}

/// `InsightSummaryResponse`, daily or weekly.
public struct InsightSummary: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let childId: UUID
    public let periodStart: LocalDate
    public let periodEnd: LocalDate
    public let paragraphs: [String]
    public let recommendation: String?
    public let conversationQuestion: String?
    public let riskLevel: StatusLevel

    public init(
        id: UUID,
        childId: UUID,
        periodStart: LocalDate,
        periodEnd: LocalDate,
        paragraphs: [String],
        recommendation: String? = nil,
        conversationQuestion: String? = nil,
        riskLevel: StatusLevel = .good
    ) {
        self.id = id
        self.childId = childId
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.paragraphs = paragraphs
        self.recommendation = recommendation
        self.conversationQuestion = conversationQuestion
        self.riskLevel = riskLevel
    }

    enum CodingKeys: String, CodingKey {
        case id = "summaryId"
        case childId, periodStart, periodEnd, paragraphs, recommendation, conversationQuestion, riskLevel
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        childId = try container.decode(UUID.self, forKey: .childId)
        periodStart = try container.decode(LocalDate.self, forKey: .periodStart)
        periodEnd = try container.decode(LocalDate.self, forKey: .periodEnd)
        paragraphs = try container.decodeIfPresent([String].self, forKey: .paragraphs) ?? []
        recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        conversationQuestion = try container.decodeIfPresent(String.self, forKey: .conversationQuestion)
        riskLevel = try container.decodeIfPresent(StatusLevel.self, forKey: .riskLevel) ?? .good
    }
}

/// `DailyTotalDto`: one day of one child's screen time.
public struct DailyUsage: Decodable, Equatable, Sendable {
    public let date: LocalDate
    public let usedMinutes: Int
    public let limitMinutes: Int

    public init(date: LocalDate, usedMinutes: Int, limitMinutes: Int) {
        self.date = date
        self.usedMinutes = usedMinutes
        self.limitMinutes = limitMinutes
    }
}

/// `UsageRange` on P08. A value this app does not know reads as today.
public enum UsageRange: String, CaseIterable, Sendable, Decodable {
    case today = "TODAY"
    case lastSevenDays = "LAST_7_DAYS"
    case lastThirtyDays = "LAST_30_DAYS"

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UsageRange(rawValue: raw) ?? .today
    }
}

/// `AppUsageEntryDto`. The server folds everything past the top four into one
/// entry with the reserved id `nozir.other_apps`.
public struct AppUsageEntry: Decodable, Hashable, Sendable {
    public static let otherAppsPackageId = "nozir.other_apps"

    public let packageId: String
    public let displayName: String
    public let minutes: Int

    public init(packageId: String, displayName: String, minutes: Int) {
        self.packageId = packageId
        self.displayName = displayName
        self.minutes = minutes
    }

    public var isOtherApps: Bool {
        packageId == Self.otherAppsPackageId
    }

    enum CodingKeys: String, CodingKey {
        case packageId, displayName, minutes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        packageId = try container.decode(String.self, forKey: .packageId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        minutes = try container.decode(Int.self, forKey: .minutes)
    }
}

/// `AppBreakdownResponse`.
public struct AppBreakdown: Decodable, Equatable, Sendable {
    public let range: UsageRange
    public let totalMinutes: Int
    public let entries: [AppUsageEntry]

    public init(range: UsageRange, totalMinutes: Int, entries: [AppUsageEntry]) {
        self.range = range
        self.totalMinutes = totalMinutes
        self.entries = entries
    }

    enum CodingKeys: String, CodingKey {
        case range, totalMinutes, entries
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        range = try container.decodeIfPresent(UsageRange.self, forKey: .range) ?? .today
        totalMinutes = try container.decodeIfPresent(Int.self, forKey: .totalMinutes) ?? 0
        entries = try container.decodeIfPresent([AppUsageEntry].self, forKey: .entries) ?? []
    }
}
```

- [ ] **Step 5: Protokol va API**

`NozirKit/Sources/NozirInsights/InsightsService.swift`:

```swift
import Foundation

/// Everything the home and report screens ask the server. `InsightsApi` is the
/// real one; screen-model tests use a scripted fake.
public protocol InsightsService: Sendable {
    func home() async throws -> ParentHome
    /// nil: the latest finished day. A missing summary is a 404 (`ApiFailure.isNotFound`).
    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary
    /// Both ends included; the server fills days without data with zero.
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage]
    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown
}
```

`NozirKit/Sources/NozirInsights/InsightsApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/home`, `/summaries/{daily,weekly}` and `/usage/{daily,apps}`
/// (backend `InsightsController`, `UsageController`).
public struct InsightsApi: InsightsService {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    public func home() async throws -> ParentHome {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/home"), as: ParentHome.self)
    }

    public func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary {
        var query: [String: String] = [:]
        if let date {
            query["date"] = date.text
        }
        let request = ApiRequest(method: .get, path: Self.childPath(childId) + "/summaries/daily", query: query)
        return try await client.send(request, as: InsightSummary.self)
    }

    public func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/summaries/weekly",
            query: ["weekStart": weekStart.text]
        )
        return try await client.send(request, as: InsightSummary.self)
    }

    public func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/usage/daily",
            query: ["from": from.text, "to": to.text]
        )
        return try await client.send(request, as: [DailyUsage].self)
    }

    public func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        let request = ApiRequest(
            method: .get,
            path: Self.childPath(childId) + "/usage/apps",
            query: ["range": range.rawValue]
        )
        return try await client.send(request, as: AppBreakdown.self)
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirInsightsTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirInsights/InsightModels.swift NozirKit/Sources/NozirInsights/InsightsService.swift NozirKit/Sources/NozirInsights/InsightsApi.swift NozirKit/Tests/NozirInsightsTests/InsightsFixtures.swift NozirKit/Tests/NozirInsightsTests/InsightsApiTests.swift
```

Xabar: `insights: home, summaries and usage, read as the backend writes them`

---
### Task 3: Grafik hisobi, ilovalarni yig'ish va sana/vaqt matnlari

**Files:**
- Create: `NozirKit/Sources/NozirDesignSystem/ChartMath.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Insights/AppUsageFolding.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift`
- Modify: `NozirKit/l10n/ios/values/strings.xml` (+ `NozirKit/Sources/NozirL10n/L10n.generated.swift` qayta generatsiya)
- Test: `NozirKit/Tests/NozirDesignSystemTests/ChartMathTests.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocalDate`: `day`, `month`, `isoWeekday`, `adding(days:)`), Task 2 (`AppUsageEntry`), `Durations` (2a), `L10n` (`monthNames`, `weekdayNames`, `weekdayNamesShort`, `dateDayMonth`, `dateWeekdayAndDay`, `dateRangeSameMonth`, `dateRangeAcrossMonths`, `elapsed*`).
- Produces:
  - `public enum ChartMath { static func fractions(_ values: [Int]) -> [Double]; static func peakIndex(_ values: [Int]) -> Int?; static func shares(_ values: [Int]) -> [Double] }` (`NozirDesignSystem`).
  - `enum AppUsageFolding { static let keptApps = 4; static func folded(_ entries: [AppUsageEntry]) -> [AppUsageEntry]; static func sharePercent(_ minutes: Int, of total: Int) -> Int; static func friendlyName(packageId: String, reported: String) -> String }` (`NozirAppFeature`, internal).
  - `enum ElapsedTime: Equatable { justNow, minutes(Int), hours(Int), stale(hours: Int); init(from moment: Date, to now: Date); func text(_ l10n: L10n) -> String }`.
  - `enum DateTexts { static func dayAndMonth(_:_:) -> String; static func weekdayAndDate(_:_:) -> String; static func weekRange(_ start: LocalDate, _ end: LocalDate, _ l10n: L10n) -> String; static func shortWeekday(_:_:) -> String; static func weekday(_:_:) -> String; static func timeOfDay(_ date: Date, calendar: Calendar) -> String }`.
  - L10n: `weeklyChartDaySeparator` uch tilda `", "` (chetlanish E4).

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirDesignSystemTests/ChartMathTests.swift`:

```swift
import Testing
@testable import NozirDesignSystem

@Suite struct ChartMathTests {
    @Test func heightsAreAShareOfThePeakFromZero() {
        #expect(ChartMath.fractions([30, 60, 0, 15]) == [0.5, 1, 0, 0.25])
    }

    @Test func aWeekOfZerosHasNoHeightAndNoPeak() {
        #expect(ChartMath.fractions([0, 0, 0]) == [0, 0, 0])
        #expect(ChartMath.peakIndex([0, 0, 0]) == nil)
        #expect(ChartMath.fractions([]) == [])
        #expect(ChartMath.peakIndex([]) == nil)
    }

    @Test func theFirstOfEqualPeaksIsMarked() {
        #expect(ChartMath.peakIndex([10, 40, 5, 40]) == 1)
    }

    @Test func aNegativeValueDrawsNothing() {
        #expect(ChartMath.fractions([-5, 10]) == [0, 1])
    }

    @Test func sharesAddUpToTheWhole() {
        let shares = ChartMath.shares([50, 25, 25])
        #expect(shares == [0.5, 0.25, 0.25])
        #expect(ChartMath.shares([0, 0]) == [0, 0])
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private func entry(_ packageId: String, _ minutes: Int, name: String = "") -> AppUsageEntry {
    AppUsageEntry(packageId: packageId, displayName: name, minutes: minutes)
}

private func ymd(_ text: String) -> LocalDate {
    LocalDate(text)!
}

@Suite struct AppUsageFoldingTests {
    @Test func theFourLongestStayAndTheRestBecomeOthersLast() {
        let entries = [
            entry("a", 10), entry("b", 50), entry("c", 30), entry("d", 40), entry("e", 20), entry("f", 5),
        ]

        let folded = AppUsageFolding.folded(entries)

        #expect(folded.map(\.packageId) == ["b", "d", "c", "e", AppUsageEntry.otherAppsPackageId])
        #expect(folded.last?.minutes == 15)
    }

    @Test func theServersOwnOthersIsAddedToAndStaysLastHoweverLarge() {
        let entries = [entry(AppUsageEntry.otherAppsPackageId, 500, name: "Other"), entry("a", 10), entry("b", 20)]

        let folded = AppUsageFolding.folded(entries)

        #expect(folded == [entry("b", 20), entry("a", 10), entry(AppUsageEntry.otherAppsPackageId, 500, name: "Other")])
    }

    @Test func equalAppsKeepTheServersOrder() {
        let folded = AppUsageFolding.folded([entry("x", 10), entry("y", 10), entry("z", 10)])
        #expect(folded.map(\.packageId) == ["x", "y", "z"])
    }

    @Test func emptyOthersAreDropped() {
        let folded = AppUsageFolding.folded([entry("a", 10), entry(AppUsageEntry.otherAppsPackageId, 0)])
        #expect(folded == [entry("a", 10)])
    }

    @Test func aShareIsAWholePercentOfTheTotal() {
        #expect(AppUsageFolding.sharePercent(50, of: 75) == 66)
        #expect(AppUsageFolding.sharePercent(25, of: 75) == 33)
        #expect(AppUsageFolding.sharePercent(10, of: 0) == 0)
    }

    @Test func theChildsOwnLabelWinsUnlessItIsTheId() {
        #expect(AppUsageFolding.friendlyName(packageId: "uz.payme", reported: " Payme ") == "Payme")
        #expect(AppUsageFolding.friendlyName(packageId: "com.google.android.youtube", reported: "com.google.android.youtube") == "YouTube")
        #expect(AppUsageFolding.friendlyName(packageId: "org.telegram.messenger", reported: "") == "Telegram")
    }

    @Test func anUnknownIdIsTidied() {
        #expect(AppUsageFolding.friendlyName(packageId: "com.acme.some_game", reported: "") == "Some Game")
        #expect(AppUsageFolding.friendlyName(packageId: "com.acme.android.app", reported: "") == "Acme")
        #expect(AppUsageFolding.friendlyName(packageId: "com.app", reported: "") == "App")
        #expect(AppUsageFolding.friendlyName(packageId: "...", reported: "") == "...")
    }
}

@Suite struct InsightTextsTests {
    private let l10n = L10n(.uz)
    private let now = Date(timeIntervalSince1970: 1_791_200_000)

    @Test func elapsedTimeReadsInBands() {
        #expect(ElapsedTime(from: now.addingTimeInterval(-59), to: now) == .justNow)
        #expect(ElapsedTime(from: now.addingTimeInterval(30), to: now) == .justNow)
        #expect(ElapsedTime(from: now.addingTimeInterval(-60), to: now) == .minutes(1))
        #expect(ElapsedTime(from: now.addingTimeInterval(-3_599), to: now) == .minutes(59))
        #expect(ElapsedTime(from: now.addingTimeInterval(-3_600), to: now) == .hours(1))
        #expect(ElapsedTime(from: now.addingTimeInterval(-4 * 3_600 + 1), to: now) == .hours(3))
        #expect(ElapsedTime(from: now.addingTimeInterval(-4 * 3_600), to: now) == .stale(hours: 4))
    }

    @Test func elapsedTimeIsSaid() {
        #expect(ElapsedTime.justNow.text(l10n) == l10n.elapsedJustNow)
        #expect(ElapsedTime.minutes(5).text(l10n) == "5 daqiqa oldin")
        #expect(ElapsedTime.hours(2).text(l10n) == "2 soat oldin")
        #expect(ElapsedTime.stale(hours: 6).text(l10n) == l10n.elapsedStaleHours(6))
    }

    @Test func daysAreWrittenInTheParentsLanguage() {
        #expect(DateTexts.dayAndMonth(ymd("2026-10-05"), l10n) == "5-oktabr")
        #expect(DateTexts.dayAndMonth(ymd("2026-10-05"), L10n(.en)) == "October 5")
        #expect(DateTexts.weekdayAndDate(ymd("2026-10-05"), l10n) == "Dushanba, 5-oktabr")
        #expect(DateTexts.weekday(ymd("2026-10-11"), l10n) == "Yakshanba")
        #expect(DateTexts.shortWeekday(ymd("2026-10-11"), l10n) == "Ya")
    }

    @Test func aWeekNamesItsMonthOnceOrTwice() {
        #expect(DateTexts.weekRange(ymd("2026-10-05"), ymd("2026-10-11"), l10n) == l10n.dateRangeSameMonth(5, 11, "oktabr"))
        #expect(DateTexts.weekRange(ymd("2026-09-28"), ymd("2026-10-04"), l10n) == l10n.dateRangeAcrossMonths("28-sentabr", "4-oktabr"))
    }

    @Test func aTimeOfDayIsTheClockInThePhonesZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tashkent"))
        let moment = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:05:00Z"))

        #expect(DateTexts.timeOfDay(moment, calendar: calendar) == "08:05")
    }

    @Test func theDaySeparatorKeepsItsSpace() {
        #expect(L10n(.uz).weeklyChartDaySeparator == ", ")
        #expect(L10n(.ru).weeklyChartDaySeparator == ", ")
        #expect(L10n(.en).weeklyChartDaySeparator == ", ")
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests` va `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'ChartMath' in scope`, `cannot find 'AppUsageFolding' in scope`.

- [ ] **Step 3: `ChartMath`**

`NozirKit/Sources/NozirDesignSystem/ChartMath.swift`:

```swift
/// Android `ChartFractions.kt`: the arithmetic behind every chart, kept apart
/// from drawing so it can be tested.
public enum ChartMath {
    /// Each value over the largest, from a zero baseline, clamped to 0...1. A
    /// list of zeros (or an empty one) draws nothing rather than dividing by zero.
    public static func fractions(_ values: [Int]) -> [Double] {
        guard let peak = values.max(), peak > 0 else { return values.map { _ in 0 } }
        return values.map { min(max(Double($0) / Double(peak), 0), 1) }
    }

    /// The first index holding the largest value; nil when nothing is above zero.
    public static func peakIndex(_ values: [Int]) -> Int? {
        guard let peak = values.max(), peak > 0 else { return nil }
        return values.firstIndex(of: peak)
    }

    /// Each value's part of the sum (negatives count as zero).
    public static func shares(_ values: [Int]) -> [Double] {
        let total = values.reduce(0) { $0 + max($1, 0) }
        guard total > 0 else { return values.map { _ in 0 } }
        return values.map { Double(max($0, 0)) / Double(total) }
    }
}
```

- [ ] **Step 4: `AppUsageFolding`**

`NozirKit/Sources/NozirAppFeature/Insights/AppUsageFolding.swift`:

```swift
import Foundation
import NozirInsights

/// Android `FoldedToTopApps.kt` and `FriendlyAppName.kt`.
enum AppUsageFolding {
    /// There are four series colours; everything past them is one grey bucket.
    static let keptApps = 4

    /// The four longest-used apps (ties keep the server's order), then one
    /// "others" entry holding the rest and any bucket the server already made.
    /// The bucket is always last: it is not an app and is not compared with one.
    static func folded(_ entries: [AppUsageEntry]) -> [AppUsageEntry] {
        let apps = entries.enumerated()
            .filter { !$0.element.isOtherApps }
            .sorted { lhs, rhs in
                lhs.element.minutes != rhs.element.minutes
                    ? lhs.element.minutes > rhs.element.minutes
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
        let kept = Array(apps.prefix(keptApps))
        let buckets = entries.filter(\.isOtherApps)
        let foldedMinutes = apps.dropFirst(keptApps).reduce(0) { $0 + $1.minutes }
            + buckets.reduce(0) { $0 + $1.minutes }
        guard foldedMinutes > 0 else { return kept }
        let others = AppUsageEntry(
            packageId: AppUsageEntry.otherAppsPackageId,
            displayName: buckets.first?.displayName ?? "",
            minutes: foldedMinutes
        )
        return kept + [others]
    }

    /// `minutes × 100 / total`, whole percent; a zero total is 0%.
    static func sharePercent(_ minutes: Int, of total: Int) -> Int {
        total > 0 ? minutes * 100 / total : 0
    }

    /// The label the child's phone reported, unless it is just the id; then a
    /// short list of well-known apps; then the id tidied into words.
    static func friendlyName(packageId: String, reported: String) -> String {
        let trimmed = reported.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != packageId { return trimmed }
        if let known = wellKnown[packageId] { return known }
        return tidied(packageId)
    }

    private static func tidied(_ packageId: String) -> String {
        let segments = packageId.split(separator: ".").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let chosen = segments.last(where: { !uninformative.contains($0.lowercased()) }) ?? segments.last else {
            return packageId
        }
        let words = chosen.split(whereSeparator: { $0 == "_" || $0 == "-" }).filter { !$0.isEmpty }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return name.isEmpty ? packageId : name
    }

    private static let uninformative: Set<String> = [
        "com", "org", "net", "io", "co", "me", "app", "apps", "android",
        "mobile", "client", "free", "lite", "pro", "plus", "main", "release",
    ]

    private static let wellKnown: [String: String] = [
        "com.google.android.youtube": "YouTube",
        "com.google.android.apps.youtube.kids": "YouTube Kids",
        "com.google.android.apps.youtube.music": "YouTube Music",
        "com.google.android.gm": "Gmail",
        "com.google.android.apps.photos": "Google Photos",
        "com.google.android.googlequicksearchbox": "Google",
        "com.android.vending": "Play Store",
        "com.android.chrome": "Chrome",
        "com.whatsapp": "WhatsApp",
        "org.telegram.messenger": "Telegram",
        "com.instagram.android": "Instagram",
        "com.facebook.katana": "Facebook",
        "com.facebook.orca": "Messenger",
        "com.zhiliaoapp.musically": "TikTok",
        "com.snapchat.android": "Snapchat",
        "com.twitter.android": "X",
        "com.viber.voip": "Viber",
        "com.imo.android.imoim": "imo",
        "com.vkontakte.android": "VK",
        "ru.ok.android": "Odnoklassniki",
        "com.discord": "Discord",
        "com.spotify.music": "Spotify",
        "com.netflix.mediaclient": "Netflix",
        "com.pinterest": "Pinterest",
        "com.linkedin.android": "LinkedIn",
        "com.duolingo": "Duolingo",
        "com.yandex.browser": "Yandex Browser",
        "com.opera.mini.native": "Opera Mini",
        "com.UCMobile.intl": "UC Browser",
        "com.roblox.client": "Roblox",
        "com.mojang.minecraftpe": "Minecraft",
        "com.supercell.brawlstars": "Brawl Stars",
        "com.supercell.clashofclans": "Clash of Clans",
        "com.dts.freefireth": "Free Fire",
        "com.tencent.ig": "PUBG Mobile",
        "com.activision.callofduty.shooter": "Call of Duty Mobile",
    ]
}
```

(`"com.acme.android.app"` → "acme": oxiridan boshlab birinchi ma'noli bo'lak; `"com.app"` → hamma bo'lak ma'nosiz, oxirgisi "app" → "App"; `"..."` → bo'lak yo'q → id o'zi. Android `tidiedPackageId` bilan bir xil.)

- [ ] **Step 5: `InsightTexts`**

`NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift`:

```swift
import Foundation
import NozirInsights
import NozirL10n

/// Android `ElapsedTimeOf.kt`: the age of a moment in the band a parent reads it in.
enum ElapsedTime: Equatable {
    case justNow
    case minutes(Int)
    case hours(Int)
    /// Four hours and more: a guess, not an answer.
    case stale(hours: Int)

    /// A moment in the future is a disagreeing clock, read as "just now".
    init(from moment: Date, to now: Date) {
        let seconds = Int(now.timeIntervalSince(moment))
        guard seconds >= 60 else {
            self = .justNow
            return
        }
        let minutes = seconds / 60
        guard minutes >= 60 else {
            self = .minutes(minutes)
            return
        }
        let hours = minutes / 60
        self = hours < 4 ? .hours(hours) : .stale(hours: hours)
    }

    func text(_ l10n: L10n) -> String {
        switch self {
        case .justNow: l10n.elapsedJustNow
        case .minutes(let minutes): l10n.elapsedMinutes(minutes)
        case .hours(let hours): l10n.elapsedHours(hours)
        case .stale(let hours): l10n.elapsedStaleHours(hours)
        }
    }
}

/// Android `UzbekDateText.kt`: days in the parent's language, not the phone's.
enum DateTexts {
    /// "5-oktabr", "October 5".
    static func dayAndMonth(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateDayMonth(date.day, monthName(date, l10n))
    }

    /// "Dushanba, 5-oktabr".
    static func weekdayAndDate(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.dateWeekdayAndDay(weekday(date, l10n), dayAndMonth(date, l10n))
    }

    /// "5–11 oktabr" or "28-sentabr – 4-oktabr".
    static func weekRange(_ start: LocalDate, _ end: LocalDate, _ l10n: L10n) -> String {
        if start.year == end.year, start.month == end.month {
            return l10n.dateRangeSameMonth(start.day, end.day, monthName(end, l10n))
        }
        return l10n.dateRangeAcrossMonths(dayAndMonth(start, l10n), dayAndMonth(end, l10n))
    }

    static func weekday(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.weekdayNames[date.isoWeekday - 1]
    }

    static func shortWeekday(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.weekdayNamesShort[date.isoWeekday - 1]
    }

    /// "08:05" on the phone's clock.
    static func timeOfDay(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return twoDigits(parts.hour ?? 0) + ":" + twoDigits(parts.minute ?? 0)
    }

    private static func monthName(_ date: LocalDate, _ l10n: L10n) -> String {
        l10n.monthNames[date.month - 1]
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
```

- [ ] **Step 6: Kunlar ajratgichi (chetlanish E4)**

`NozirKit/l10n/ios/values/strings.xml` — `bedtime_days_separator` dan keyin, `</resources>` dan oldin qo'shing:

```xml
    <!-- Same reason: P07/P08 chart descriptions read "Du 2s 10d,Se 1s" without it. -->
    <string name="weekly_chart_day_separator">", "</string>
```

Run: `python3 scripts/gen_l10n.py && python3 scripts/gen_l10n.py --check`
Expected: generator xatosiz; `--check` "up to date". `git diff NozirKit/Sources/NozirL10n/L10n.generated.swift` faqat `weeklyChartDaySeparator` ning uch qatorini `","` → `", "` ga o'zgartiradi.

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`, `./scripts/test.sh NozirAppFeatureTests`, `python3 -m unittest discover -s scripts/tests`
Expected: `** TEST SUCCEEDED **` ikkalasida; Python testlari OK.

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirDesignSystem/ChartMath.swift NozirKit/Sources/NozirAppFeature/Insights/AppUsageFolding.swift NozirKit/Sources/NozirAppFeature/Insights/InsightTexts.swift NozirKit/l10n/ios/values/strings.xml NozirKit/Sources/NozirL10n/L10n.generated.swift NozirKit/Tests/NozirDesignSystemTests/ChartMathTests.swift NozirKit/Tests/NozirAppFeatureTests/InsightTextsTests.swift
```

Xabar: `insights: chart arithmetic, app folding, and days in the parent's words`

---
### Task 4: Dizayn komponentlari — ranglar, grafiklar, holatlar, bola tanlagich

**Files:**
- Modify: `NozirKit/Sources/NozirDesignSystem/NozirColor.swift`
- Modify: `NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift`
- Modify: `NozirKit/Sources/NozirDesignSystem/Components/NozirRows.swift:3-28`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirCharts.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirStates.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirChildSwitcher.swift`
- Test: `NozirKit/Tests/NozirDesignSystemTests/ChildSwitcherTests.swift`

**Interfaces:**
- Consumes: Task 3 (`ChartMath` — faqat ekranlar ishlatadi), mavjud `NozirColor`, `NozirText`, `NozirSpacing`, `NozirAvatar`, `AvatarTone`, `NozirButton`.
- Produces (hammasi `public`):
  - `NozirColor.actionContainer`, `.criticalContainer`, `.chartSeries: [Color]` (4 ta), `.chartOther`.
  - `NozirCardTone.critical`; `NozirStatusLevel.critical` (`NozirStatusDot` uni `criticalContent` bilan chizadi).
  - `struct NozirChartColumn: Identifiable, Equatable, Sendable { id: Int; label; valueLabel; fraction: Double; isPeak: Bool }` + init.
  - `struct NozirColumnChart: View { init(columns: [NozirChartColumn], accessibilityLabel: String, height: CGFloat = 140) }`.
  - `struct NozirChartSegment: Identifiable { id: Int; fraction: Double; color: Color }` + init; `struct NozirStackedBar: View { init(segments: [NozirChartSegment], height: CGFloat = 14) }`.
  - `struct NozirLegendItem: Identifiable { id: Int; color: Color; label: String; valueLabel: String }` + init; `struct NozirLegend: View { init(items: [NozirLegendItem]) }`.
  - `struct NozirProgressBar: View { init(fraction: Double, color: Color) }`.
  - `struct NozirErrorState: View { init(title: String, message: String, retryTitle: String, onRetry: @escaping () -> Void) }`; `struct NozirEmptyState: View { init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) }`; `struct NozirOfflineNotice: View { init(_ text: String) }`.
  - `struct NozirSwitcherChild: Identifiable, Equatable, Sendable { id: UUID; name: String; tone: AvatarTone; needsAttention: Bool }` + init.
  - `struct NozirChildSwitcher: View { init(children: [NozirSwitcherChild], selection: Binding<UUID?>, allTitle: String? = nil, allAccessibilityLabel: String? = nil, addTitle: String? = nil, onAdd: (() -> Void)? = nil, fallbackInitial: String); nonisolated static func selection(afterTapping: UUID?, current: UUID?, allowsAll: Bool) -> UUID? }`.

- [ ] **Step 1: Failing test (tanlagich mantiqi)**

`NozirKit/Tests/NozirDesignSystemTests/ChildSwitcherTests.swift`:

```swift
import Foundation
import Testing
@testable import NozirDesignSystem

@Suite struct ChildSwitcherTests {
    private let ali = UUID()
    private let vali = UUID()

    @Test func tappingAChildSelectsIt() {
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: nil, allowsAll: true) == ali)
        #expect(NozirChildSwitcher.selection(afterTapping: vali, current: ali, allowsAll: true) == vali)
    }

    @Test func tappingTheChosenChildAgainGoesBackToEveryoneWhereThereIsAnEveryone() {
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: ali, allowsAll: true) == nil)
        #expect(NozirChildSwitcher.selection(afterTapping: ali, current: ali, allowsAll: false) == ali)
    }

    @Test func tappingEveryoneClearsTheChoice() {
        #expect(NozirChildSwitcher.selection(afterTapping: nil, current: ali, allowsAll: true) == nil)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Expected: FAIL — `cannot find 'NozirChildSwitcher' in scope`.

- [ ] **Step 3: Ranglar, karta, holat darajasi**

`NozirKit/Sources/NozirDesignSystem/NozirColor.swift` — `attentionBorder` qatoridan keyin qo'shing:

```swift
    public static let actionContainer = color(light: 0xFDEEE6, dark: 0xF0803F, darkAlpha: 0.12)
    public static let criticalContainer = color(light: 0xFDECEC, dark: 0xE66767, darkAlpha: 0.12)
    /// Android `chartSeries`: four app colours, in order; there is never a fifth.
    public static let chartSeries: [Color] = [
        color(light: 0x0E9F8F, dark: 0x0FA799),
        color(light: 0xEB6834, dark: 0xD95926),
        color(light: 0x2A78D6, dark: 0x3987E5),
        color(light: 0xEDA100, dark: 0xC98500),
    ]
    /// The grey of "Boshqalar".
    public static let chartOther = color(light: 0xB8C4C1, dark: 0x5B6B68)
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift` — butun fayl:

```swift
import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention, critical
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
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(border, lineWidth: NozirSize.borderResting)
        )
    }

    private var fill: Color {
        switch tone {
        case .plain: NozirColor.card
        case .attention: NozirColor.attentionContainer
        case .critical: NozirColor.criticalContainer
        }
    }

    private var border: Color {
        switch tone {
        case .plain: NozirColor.border
        case .attention: NozirColor.attentionBorder
        case .critical: NozirColor.criticalBorder
        }
    }
}
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirRows.swift` — 3–28-qatorlar (enum va `NozirStatusDot.color`):

```swift
public enum NozirStatusLevel: Sendable {
    case good, attention, action, critical
}
```

```swift
    private var color: Color {
        switch level {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }
```

Bu ikki enum ustida boshqa to'liq `switch` yo'q (reja yozilganda tekshirilgan: `ProfileModel`, `PairingView`, `ChildDetailsView` faqat qiymat beradi), shuning uchun boshqa fayl o'zgarmaydi.

- [ ] **Step 4: Grafiklar**

`NozirKit/Sources/NozirDesignSystem/Components/NozirCharts.swift`:

```swift
import SwiftUI

/// One column of `NozirColumnChart`. `fraction` comes from `ChartMath.fractions`.
public struct NozirChartColumn: Identifiable, Equatable, Sendable {
    public let id: Int
    public let label: String
    /// Empty for a day still to come: "0d" over Friday on a Tuesday would be a lie.
    public let valueLabel: String
    public let fraction: Double
    public let isPeak: Bool

    public init(id: Int, label: String, valueLabel: String, fraction: Double, isPeak: Bool) {
        self.id = id
        self.label = label
        self.valueLabel = valueLabel
        self.fraction = fraction
        self.isPeak = isPeak
    }
}

/// Android `NozirColumnChart`: columns from a zero baseline, the peak in full
/// colour. VoiceOver reads `accessibilityLabel` (every figure as text) instead
/// of the bars.
public struct NozirColumnChart: View {
    private let columns: [NozirChartColumn]
    private let label: String
    private let height: CGFloat

    public init(columns: [NozirChartColumn], accessibilityLabel: String, height: CGFloat = 140) {
        self.columns = columns
        label = accessibilityLabel
        self.height = height
    }

    public var body: some View {
        HStack(alignment: .bottom, spacing: NozirSpacing.small) {
            ForEach(columns) { column in
                VStack(spacing: NozirSpacing.extraSmall) {
                    Text(column.valueLabel.isEmpty ? " " : column.valueLabel)
                        .nozirText(.label, color: column.isPeak ? NozirColor.primaryAccent : NozirColor.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(NozirColor.track)
                        RoundedRectangle(cornerRadius: 6)
                            .fill(column.isPeak ? NozirColor.primary : NozirColor.primary.opacity(0.45))
                            .frame(height: barHeight(column.fraction))
                    }
                    .frame(height: height)
                    Text(column.label)
                        .nozirText(.label, color: NozirColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    /// A day with any use stays visible as a sliver.
    private func barHeight(_ fraction: Double) -> CGFloat {
        guard fraction > 0 else { return 0 }
        return max(height * fraction, 4)
    }
}

public struct NozirChartSegment: Identifiable {
    public let id: Int
    public let fraction: Double
    public let color: Color

    public init(id: Int, fraction: Double, color: Color) {
        self.id = id
        self.fraction = fraction
        self.color = color
    }
}

/// Android `NozirStackedBar`: one bar split into each app's share. Decorative;
/// the screen gives the same figures as text.
public struct NozirStackedBar: View {
    private let segments: [NozirChartSegment]
    private let height: CGFloat
    private let gap: CGFloat = 2

    public init(segments: [NozirChartSegment], height: CGFloat = 14) {
        self.segments = segments
        self.height = height
    }

    public var body: some View {
        GeometryReader { proxy in
            let visible = segments.filter { $0.fraction > 0 }
            let usable = max(0, proxy.size.width - gap * CGFloat(max(visible.count - 1, 0)))
            HStack(spacing: gap) {
                ForEach(visible) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: usable * segment.fraction)
                }
            }
        }
        .frame(height: height)
        .background(NozirColor.track)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

public struct NozirLegendItem: Identifiable {
    public let id: Int
    public let color: Color
    public let label: String
    public let valueLabel: String

    public init(id: Int, color: Color, label: String, valueLabel: String) {
        self.id = id
        self.color = color
        self.label = label
        self.valueLabel = valueLabel
    }
}

/// A colour dot, a name and a figure per line.
public struct NozirLegend: View {
    private let items: [NozirLegendItem]

    public init(items: [NozirLegendItem]) {
        self.items = items
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            ForEach(items) { item in
                HStack(spacing: NozirSpacing.small) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(item.label).nozirText(.bodySmall)
                    Spacer(minLength: NozirSpacing.small)
                    Text(item.valueLabel).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// A thin track filled to `fraction` (0...1).
public struct NozirProgressBar: View {
    private let fraction: Double
    private let color: Color

    public init(fraction: Double, color: Color) {
        self.fraction = min(max(fraction, 0), 1)
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(NozirColor.track)
                Capsule()
                    .fill(color)
                    .frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 5: Holatlar**

`NozirKit/Sources/NozirDesignSystem/Components/NozirStates.swift`:

```swift
import SwiftUI

/// Android `NozirErrorState`: what went wrong, and one way to try again.
public struct NozirErrorState: View {
    private let title: String
    private let message: String
    private let retryTitle: String
    private let onRetry: () -> Void

    public init(title: String, message: String, retryTitle: String, onRetry: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.retryTitle = retryTitle
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(spacing: NozirSpacing.compact) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 32))
                .foregroundStyle(NozirColor.actionContent)
                .accessibilityHidden(true)
            Text(title)
                .nozirText(.titleSmall)
                .multilineTextAlignment(.center)
            Text(message)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            NozirButton(retryTitle, variant: .secondary, action: onRetry)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NozirSpacing.extraLarge)
    }
}

/// Android `NozirEmptyState`: nothing yet is an answer, not an error.
public struct NozirEmptyState: View {
    private let title: String
    private let message: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(title: String, message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: NozirSpacing.compact) {
            Text(title)
                .nozirText(.titleSmall)
                .multilineTextAlignment(.center)
            Text(message)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                NozirButton(actionTitle, action: action)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, NozirSpacing.extraLarge)
    }
}

/// Android `NozirOfflineNotice`: the screen shows the last known state.
public struct NozirOfflineNotice: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.small) {
            Image(systemName: "wifi.slash")
                .accessibilityHidden(true)
            Text(text)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .foregroundStyle(NozirColor.textSecondary)
        .padding(.horizontal, NozirSpacing.compact)
        .padding(.vertical, NozirSpacing.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.track))
    }
}
```

- [ ] **Step 6: Bola tanlagich**

`NozirKit/Sources/NozirDesignSystem/Components/NozirChildSwitcher.swift`:

```swift
import SwiftUI

public struct NozirSwitcherChild: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tone: AvatarTone
    public let needsAttention: Bool

    public init(id: UUID, name: String, tone: AvatarTone, needsAttention: Bool = false) {
        self.id = id
        self.name = name
        self.tone = tone
        self.needsAttention = needsAttention
    }
}

/// Android `ChildAvatarSwitcher`: the children's faces in a row. With
/// `allTitle` there is an "everyone" chip first (P05); without it one child is
/// always chosen (Statistics). `addTitle` + `onAdd` end the row with "+".
public struct NozirChildSwitcher: View {
    private let children: [NozirSwitcherChild]
    @Binding private var selection: UUID?
    private let allTitle: String?
    private let allAccessibilityLabel: String?
    private let addTitle: String?
    private let onAdd: (() -> Void)?
    private let fallbackInitial: String

    public init(
        children: [NozirSwitcherChild],
        selection: Binding<UUID?>,
        allTitle: String? = nil,
        allAccessibilityLabel: String? = nil,
        addTitle: String? = nil,
        onAdd: (() -> Void)? = nil,
        fallbackInitial: String
    ) {
        self.children = children
        _selection = selection
        self.allTitle = allTitle
        self.allAccessibilityLabel = allAccessibilityLabel
        self.addTitle = addTitle
        self.onAdd = onAdd
        self.fallbackInitial = fallbackInitial
    }

    /// The choice after a tap. `nil` tapped is the "everyone" chip.
    nonisolated static func selection(afterTapping tapped: UUID?, current: UUID?, allowsAll: Bool) -> UUID? {
        guard let tapped else { return nil }
        if allowsAll, tapped == current { return nil }
        return tapped
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: NozirSpacing.compact) {
                if let allTitle {
                    chip(isSelected: selection == nil, label: allTitle, accessibility: allAccessibilityLabel ?? allTitle) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NozirColor.onPrimaryContainer)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(NozirColor.primaryContainer))
                    } action: {
                        selection = Self.selection(afterTapping: nil, current: selection, allowsAll: true)
                    }
                }
                ForEach(children) { child in
                    chip(isSelected: selection == child.id, label: child.name, accessibility: child.name) {
                        NozirAvatar(name: child.name, tone: child.tone, fallbackInitial: fallbackInitial, size: 44)
                            .overlay(alignment: .topTrailing) {
                                if child.needsAttention {
                                    Circle()
                                        .fill(NozirColor.actionContent)
                                        .frame(width: 10, height: 10)
                                        .accessibilityHidden(true)
                                }
                            }
                    } action: {
                        selection = Self.selection(afterTapping: child.id, current: selection, allowsAll: allTitle != nil)
                    }
                }
                if let addTitle, let onAdd {
                    chip(isSelected: false, label: addTitle, accessibility: addTitle) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(NozirColor.primaryAccent)
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(NozirColor.border, lineWidth: NozirSize.borderResting))
                    } action: {
                        onAdd()
                    }
                }
            }
            .padding(.vertical, NozirSpacing.extraSmall)
        }
    }

    private func chip<Face: View>(
        isSelected: Bool,
        label: String,
        accessibility: String,
        @ViewBuilder face: () -> Face,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: NozirSpacing.extraSmall) {
                face()
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(isSelected ? NozirColor.primary : .clear, lineWidth: NozirSize.borderEmphasis)
                    )
                Text(label)
                    .nozirText(.label, color: isSelected ? NozirColor.textPrimary : NozirColor.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
```

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`, so'ng watcher `app` (ilova build'i: `NozirCardTone`/`NozirStatusLevel` dagi yangi holat ilovada `switch` ni buzmasligi kerak).
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirDesignSystem/NozirColor.swift NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift NozirKit/Sources/NozirDesignSystem/Components/NozirRows.swift NozirKit/Sources/NozirDesignSystem/Components/NozirCharts.swift NozirKit/Sources/NozirDesignSystem/Components/NozirStates.swift NozirKit/Sources/NozirDesignSystem/Components/NozirChildSwitcher.swift NozirKit/Tests/NozirDesignSystemTests/ChildSwitcherTests.swift
```


Xabar: `design: charts, empty and error states, and a row of children`

---
### Task 5: SOS — banner, oyna va favqulodda raqam

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`ActiveSos`), Task 3 (`ElapsedTime`), Task 4 (`NozirCardTone.critical`), 2a (`Child`, `makeChild` test yordamchisi), poydevor (`ServerConfig.emergencyContacts.emergencyNumber`).
- Produces:
  - `struct SosAlert: Equatable { sos: ActiveSos; childName: String?; childPhone: String?; emergencyNumber: String?; init(_ sos: ActiveSos, child: Child?, emergencyNumber: String?); func title(_:) -> String; func when(now: Date, _ l10n: L10n) -> String; func callChildTitle(_:) -> String; childCallURL: URL?; func emergencyTitle(_:) -> String?; emergencyCallURL: URL? }`
  - `struct SosBanner: View { init(alert: SosAlert, onOpen: @escaping () -> Void) }`; `struct SosSheet: View { init(alert: SosAlert) }`.
  - `AppModel.emergencyNumber: String?` (`public private(set)`), har `evaluate()` da yangilanadi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let childId = UUID()
private let now = Date(timeIntervalSince1970: 1_791_200_000)

private func sos(name: String?, minutesAgo: Double = 5) -> ActiveSos {
    ActiveSos(sosId: UUID(), childId: childId, childName: name, triggeredAt: now.addingTimeInterval(-minutesAgo * 60))
}

@Suite struct SosAlertTests {
    private let l10n = L10n(.uz)

    @Test func theAlarmSaysWhoAndWhen() {
        let alert = SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil)

        #expect(alert.title(l10n) == l10n.homeSosBannerTitleNamed("Ali"))
        #expect(alert.when(now: now, l10n) == l10n.homeSosBannerBodyWhen("5 daqiqa oldin"))
    }

    // Review Focus 5.
    @Test func aNamelessSosTakesTheNameFromTheFamily() {
        let child = makeChild("Vali", id: childId, phone: "+998901234567")

        let alert = SosAlert(sos(name: nil), child: child, emergencyNumber: nil)

        #expect(alert.childName == "Vali")
        #expect(alert.title(l10n) == l10n.homeSosBannerTitleNamed("Vali"))
        #expect(alert.callChildTitle(l10n) == l10n.sosActionCallChild("Vali"))
    }

    @Test func aBlankNameIsNoName() {
        let alert = SosAlert(sos(name: "  "), child: nil, emergencyNumber: nil)

        #expect(alert.childName == nil)
        #expect(alert.title(l10n) == l10n.homeSosBannerTitle)
        #expect(alert.callChildTitle(l10n) == l10n.sosActionCallChildUnnamed)
    }

    @Test func aChildWithANumberIsCalledOnIt() {
        let alert = SosAlert(sos(name: "Ali"), child: makeChild("Ali", id: childId, phone: "+998901234567"), emergencyNumber: nil)

        #expect(alert.childCallURL == URL(string: "tel:+998901234567"))
    }

    // Review Focus 5.
    @Test func aChildWithoutANumberCannotBeCalled() {
        #expect(SosAlert(sos(name: "Ali"), child: makeChild("Ali", id: childId, phone: nil), emergencyNumber: nil).childCallURL == nil)
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil).childCallURL == nil)
    }

    @Test func theEmergencyNumberComesFromTheConfig() {
        let alert = SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: "112")

        #expect(alert.emergencyTitle(l10n) == l10n.sosActionCallEmergency("112"))
        #expect(alert.emergencyCallURL == URL(string: "tel:112"))
    }

    @Test func noEmergencyNumberNoButton() {
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: nil).emergencyTitle(l10n) == nil)
        #expect(SosAlert(sos(name: "Ali"), child: nil, emergencyNumber: "").emergencyCallURL == nil)
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift` — `AppModelTests` suite oxiriga qo'shing:

```swift
    @Test func theEmergencyNumberIsKeptForSos() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false)), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.phase == .signedIn)
        #expect(model.emergencyNumber == "112")
    }

    @Test func noConfigNoEmergencyNumber() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))

        await model.start()

        #expect(model.emergencyNumber == nil)
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'SosAlert' in scope`, `value of type 'AppModel' has no member 'emergencyNumber'`.

- [ ] **Step 3: `SosAlert`**

`NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift`:

```swift
import Foundation
import NozirFamily
import NozirInsights
import NozirL10n

/// What the SOS banner and sheet say and dial. The name is the alarm's own,
/// else the family list's (a removed child has neither); the child's number
/// is only ever the family list's.
struct SosAlert: Equatable {
    let sos: ActiveSos
    let childName: String?
    let childPhone: String?
    let emergencyNumber: String?

    init(_ sos: ActiveSos, child: Child?, emergencyNumber: String?) {
        self.sos = sos
        childName = Self.present(sos.childName) ?? Self.present(child?.displayName)
        childPhone = Self.present(child?.phoneE164)
        self.emergencyNumber = Self.present(emergencyNumber)
    }

    func title(_ l10n: L10n) -> String {
        childName.map(l10n.homeSosBannerTitleNamed) ?? l10n.homeSosBannerTitle
    }

    /// "5 daqiqa oldin · hali javob berilmadi".
    func when(now: Date, _ l10n: L10n) -> String {
        l10n.homeSosBannerBodyWhen(ElapsedTime(from: sos.triggeredAt, to: now).text(l10n))
    }

    func callChildTitle(_ l10n: L10n) -> String {
        childName.map(l10n.sosActionCallChild) ?? l10n.sosActionCallChildUnnamed
    }

    var childCallURL: URL? {
        childPhone.flatMap { URL(string: "tel:\($0)") }
    }

    func emergencyTitle(_ l10n: L10n) -> String? {
        emergencyNumber.map(l10n.sosActionCallEmergency)
    }

    var emergencyCallURL: URL? {
        emergencyNumber.flatMap { URL(string: "tel:\($0)") }
    }

    private static func present(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
```

- [ ] **Step 4: `AppModel` favqulodda raqamni saqlaydi**

`NozirKit/Sources/NozirAppFeature/AppModel.swift` — `phase` dan keyin:

```swift
    /// From the server config; the SOS sheet offers to dial it. Nil until a
    /// config (fresh or cached) has been read.
    public private(set) var emergencyNumber: String?
```

va `evaluate()`:

```swift
    private func evaluate() async {
        let loaded = await config.load()
        emergencyNumber = loaded?.emergencyContacts.emergencyNumber
        if UpdateGate.blocks(loaded) {
            phase = .updateRequired(emergencyNumber: emergencyNumber)
            return
        }
        phase = tokens.load() == nil ? .signedOut : .signedIn
    }
```

- [ ] **Step 5: Banner va oyna**

`NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Android `SosBanner`: the first thing on P05 while an alarm is unanswered.
/// "N daqiqa oldin" moves on by itself every 30 s.
struct SosBanner: View {
    let alert: SosAlert
    let onOpen: () -> Void
    @Environment(\.l10n) private var l10n

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            NozirCard(tone: .critical) {
                HStack(alignment: .top, spacing: NozirSpacing.compact) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(NozirColor.criticalContent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.title(l10n)).nozirText(.titleSmall, color: NozirColor.criticalContent)
                        Text(alert.when(now: context.date, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                NozirButton(l10n.homeSosBannerAction, variant: .criticalOutline, action: onOpen)
            }
        }
    }
}

/// The SOS sheet of this slice: who, when, and two numbers to dial. P15 (map,
/// "I have seen it") comes with its own slice.
struct SosSheet: View {
    let alert: SosAlert
    @Environment(\.l10n) private var l10n
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @State private var dialerMissing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NozirSpacing.large) {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                            Text(alert.title(l10n)).nozirText(.titleLarge, color: NozirColor.criticalContent)
                            Text(alert.when(now: context.date, l10n)).nozirText(.body, color: NozirColor.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    VStack(alignment: .leading, spacing: NozirSpacing.small) {
                        NozirButton(alert.callChildTitle(l10n), size: .callToAction) {
                            call(alert.childCallURL)
                        }
                        .disabled(alert.childCallURL == nil)
                        if alert.childCallURL == nil {
                            Text(l10n.sosCallChildUnavailable).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    if let emergencyTitle = alert.emergencyTitle(l10n) {
                        NozirButton(emergencyTitle, variant: .criticalOutline, size: .callToAction) {
                            call(alert.emergencyCallURL)
                        }
                    }
                    if dialerMissing {
                        NozirInlineMessage(l10n.updateRequiredDiallerMissing)
                    }
                }
                .padding(NozirSpacing.medium)
            }
            .background(NozirColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel(l10n.contentDescriptionBack)
                }
            }
        }
    }

    private func call(_ url: URL?) {
        guard let url else {
            dialerMissing = true
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in dialerMissing = true }
            }
        }
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/SosAlert.swift NozirKit/Sources/NozirAppFeature/Screens/SosViews.swift NozirKit/Sources/NozirAppFeature/AppModel.swift NozirKit/Tests/NozirAppFeatureTests/SosAlertTests.swift NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift
```

Xabar: `sos: an unanswered alarm says whose, how long ago, and whom to call`

---
### Task 6: P05 Home — `HomeModel`, `HomeView` va insights soxtasi

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/InsightStyle.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`InsightsService`, `ParentHome`, `ChildHomeCard`, `StatusLevel`), Task 3 (`DateTexts`), Task 4 (`NozirChildSwitcher`, `NozirErrorState`, `NozirEmptyState`, `NozirOfflineNotice`, `NozirColor.*Container`), Task 5 (`SosAlert`, `SosBanner`, `SosSheet`), 2a (`FamilyStore`, `FakeFamily`, `makeChild`, `offline`, `Durations`, `UserMessage`).
- Produces:
  - `extension StatusLevel { var designLevel: NozirStatusLevel; func label(_:) -> String; func glyph(_:) -> String; var content: Color; var container: Color }`.
  - `@MainActor @Observable final class HomeModel { enum Notice: Equatable { offline, message(UserMessage) }; enum CardStyle: Equatable { attention, quiet, plain }; home: ParentHome?; failure: UserMessage?; notice: Notice?; var filter: UUID?; family: FamilyStore; init(insights:family:currentYear:); appear() async; load() async; cards; ordered; visible; showsAttentionNote: Bool; style(of:) -> CardStyle; age(of:) -> Int?; nameAndAge(of:_:) -> String; tone(of:) -> AvatarTone; switcherChildren: [NozirSwitcherChild]; sosAlert(emergencyNumber:) -> SosAlert?; static usageAndPlace(_:_:), usageAndRules(_:_:), placeTitle(_:_:), placeCaption(_:_:calendar:) }`
  - `struct HomeView: View { init(model: HomeModel, reloadToken: Int, emergencyNumber: @escaping () -> String?, onOpenSummary: @escaping (UUID, String) -> Void, onAddChild: @escaping () -> Void) }`
  - Test yordamchilari (`FakeInsights.swift`): `actor FakeInsights: InsightsService` (`Script`: `home`, `daily` navbatlari; `weekly`, `usage`, `apps` yopilmalari; `calls: [String]`, `childIds: [UUID]`, `add(_:)`), `notFound`, `homeCard(…)`, `parentHome(…)`, `insight(…)`, `day(_:)`.

- [ ] **Step 1: Insights soxtasi (keyingi task'lar ham ishlatadi)**

`NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift`:

```swift
import Foundation
import NozirInsights
import NozirNetworking

let notFound = ApiFailure.server(status: 404, error: ApiError(code: .notFound))

func day(_ text: String) -> LocalDate {
    LocalDate(text)!
}

/// Answers home and daily from queues (an empty queue is a phone with no
/// connection); weekly, usage and apps from functions of their arguments, so a
/// test can answer per week or per range. Records every call in order.
actor FakeInsights: InsightsService {
    struct Script: Sendable {
        var home: [Result<ParentHome, ApiFailure>] = []
        var daily: [Result<InsightSummary, ApiFailure>] = []
        var weekly: @Sendable (UUID, LocalDate) throws -> InsightSummary = { _, _ in throw notFound }
        var usage: @Sendable (UUID, LocalDate, LocalDate) throws -> [DailyUsage] = { _, _, _ in throw offline }
        var apps: @Sendable (UUID, UsageRange) throws -> AppBreakdown = { _, _ in throw offline }
    }

    private var script: Script
    /// "home", "daily latest", "daily 2026-10-04", "weekly 2026-09-28",
    /// "usage 2026-09-28…2026-10-04", "apps TODAY".
    private(set) var calls: [String] = []
    /// The child each child call was about, in call order.
    private(set) var childIds: [UUID] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    func home() async throws -> ParentHome {
        calls.append("home")
        guard !script.home.isEmpty else { throw offline }
        return try script.home.removeFirst().get()
    }

    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary {
        calls.append("daily \(date?.text ?? "latest")")
        childIds.append(childId)
        guard !script.daily.isEmpty else { throw offline }
        return try script.daily.removeFirst().get()
    }

    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary {
        calls.append("weekly \(weekStart.text)")
        childIds.append(childId)
        return try script.weekly(childId, weekStart)
    }

    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] {
        calls.append("usage \(from.text)…\(to.text)")
        childIds.append(childId)
        return try script.usage(childId, from, to)
    }

    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        calls.append("apps \(range.rawValue)")
        childIds.append(childId)
        return try script.apps(childId, range)
    }
}

func homeCard(
    _ name: String = "Ali",
    id: UUID = UUID(),
    attention: Bool = false,
    online: Bool = true,
    place: String? = nil,
    since: Date? = nil,
    used: Int = 95,
    limit: Int = 120,
    summary: String? = nil,
    avatar: String? = "teal",
    level: StatusLevel = .good
) -> ChildHomeCard {
    ChildHomeCard(
        id: id,
        displayName: name,
        avatarKey: avatar,
        usedMinutes: used,
        limitMinutes: limit,
        statusLevel: level,
        needsAttention: attention,
        summarySentence: summary,
        placeLabel: place,
        placeSince: since,
        deviceOnline: online
    )
}

func parentHome(
    _ children: [ChildHomeCard],
    date: LocalDate = day("2026-10-05"),
    familySummary: String? = nil,
    sos: ActiveSos? = nil
) -> ParentHome {
    ParentHome(date: date, children: children, familySummary: familySummary, activeSos: sos)
}

func insight(
    childId: UUID,
    start: String,
    end: String,
    paragraphs: [String] = ["Tinch kun."],
    question: String? = nil,
    risk: StatusLevel = .good
) -> InsightSummary {
    InsightSummary(
        id: UUID(),
        childId: childId,
        periodStart: day(start),
        periodEnd: day(end),
        paragraphs: paragraphs,
        recommendation: "Birga sayr qiling.",
        conversationQuestion: question,
        riskLevel: risk
    )
}
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

@MainActor
private func setup(
    _ homes: [Result<ParentHome, ApiFailure>],
    family children: [Child] = []
) -> (HomeModel, FakeInsights, FakeFamily) {
    var script = FakeInsights.Script()
    script.home = homes
    let insights = FakeInsights(script)
    var familyScript = FakeFamily.Script()
    familyScript.children = Array(repeating: .success(children), count: homes.count)
    let family = FakeFamily(familyScript)
    let model = HomeModel(insights: insights, family: FamilyStore(service: family), currentYear: 2026)
    return (model, insights, family)
}

@MainActor
@Suite struct HomeModelTests {
    private let l10n = L10n(.uz)

    @Test func appearingAsksForHomeAndTheFamily() async {
        let (model, insights, family) = setup([.success(parentHome([homeCard()]))])

        await model.appear()

        #expect(await insights.calls == ["home"])
        #expect(await family.calls == ["children"])
        #expect(model.cards.count == 1)
        #expect(model.failure == nil)
        #expect(model.notice == nil)
    }

    @Test func anEmptyFamilyHasNoCards() async {
        let (model, _, _) = setup([.success(parentHome([]))])

        await model.appear()

        #expect(model.home != nil)
        #expect(model.cards.isEmpty)
    }

    @Test func aFirstLoadThatFailsIsAFullError() async {
        let (model, _, _) = setup([.failure(offline)])

        await model.appear()

        #expect(model.home == nil)
        #expect(model.failure == .noConnection)
    }

    @Test func aLaterOfflineLoadKeepsTheLastHomeAndSaysSo() async {
        let first = parentHome([homeCard("Ali")])
        let (model, _, _) = setup([.success(first), .failure(offline)])
        await model.appear()

        await model.load()

        #expect(model.home == first)
        #expect(model.failure == nil)
        #expect(model.notice == .offline)
    }

    @Test func aLaterServerFailureKeepsTheLastHomeWithAMessage() async {
        let first = parentHome([homeCard("Ali")])
        let (model, _, _) = setup([.success(first), .failure(.unexpectedStatus(500))])
        await model.appear()

        await model.load()

        #expect(model.home == first)
        #expect(model.notice == .message(.serverProblem))
    }

    @Test func aGoodLoadClearsTheNotice() async {
        let (model, _, _) = setup([.success(parentHome([])), .failure(offline), .success(parentHome([]))])
        await model.appear()
        await model.load()

        await model.load()

        #expect(model.notice == nil)
    }

    @Test func attentionComesFirstAndTheRestKeepTheServersOrder() async {
        let a = homeCard("A"), b = homeCard("B", attention: true), c = homeCard("C"), d = homeCard("D", attention: true)
        let (model, _, _) = setup([.success(parentHome([a, b, c, d]))])

        await model.appear()

        #expect(model.ordered.map(\.displayName) == ["B", "D", "A", "C"])
    }

    @Test func quietRowsOnlyBesideSomeoneWhoNeedsAttention() async {
        let calm = homeCard("A"), worried = homeCard("B", attention: true)
        let (model, _, _) = setup([.success(parentHome([calm, worried])), .success(parentHome([calm]))])
        await model.appear()

        #expect(model.style(of: worried) == .attention)
        #expect(model.style(of: calm) == .quiet)
        #expect(model.showsAttentionNote)

        await model.load()

        #expect(model.style(of: calm) == .plain)
        #expect(!model.showsAttentionNote)
    }

    @Test func theFilterShowsOneChildAndAppearingAgainShowsEveryone() async {
        let ali = homeCard("Ali"), vali = homeCard("Vali", attention: true)
        let home = parentHome([ali, vali])
        let (model, _, _) = setup([.success(home), .success(home)])
        await model.appear()

        model.filter = ali.id

        #expect(model.visible.map(\.displayName) == ["Ali"])
        #expect(model.style(of: ali) == .plain)
        #expect(!model.showsAttentionNote)

        await model.appear()

        #expect(model.filter == nil)
        #expect(model.visible.count == 2)
    }

    @Test func aFilterForAChildNoLongerThereShowsEveryone() async {
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali"), homeCard("Vali")]))])
        await model.appear()

        model.filter = UUID()

        #expect(model.visible.count == 2)
    }

    @Test func theAgeComesFromTheFamilyList() async {
        let id = UUID()
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali", id: id), homeCard("Vali")]))], family: [makeChild("Ali", id: id, birthYear: 2015)])
        await model.appear()

        #expect(model.age(of: model.cards[0]) == 11)
        #expect(model.nameAndAge(of: model.cards[0], l10n) == l10n.homeChildNameAndAge("Ali", 11))
        #expect(model.age(of: model.cards[1]) == nil)
        #expect(model.nameAndAge(of: model.cards[1], l10n) == "Vali")
    }

    @Test func theUsageLineCarriesThePlaceWhenThereIsOne() {
        #expect(HomeModel.usageAndPlace(homeCard(place: "Maktab", used: 95), l10n) == l10n.homeChildUsageAndPlace(Durations.short(95, l10n), "Maktab"))
        #expect(HomeModel.usageAndPlace(homeCard(place: nil, used: 45), l10n) == Durations.short(45, l10n))
        #expect(HomeModel.usageAndRules(homeCard(used: 45), l10n) == l10n.homeChildUsageAndPlace(Durations.short(45, l10n), l10n.homeChildRulesFollowed))
    }

    // Review Focus 2.
    @Test func anOfflinePhoneNeverShowsAPlace() throws {
        let since = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:10:00Z"))
        let card = homeCard(online: false, place: "Maktab", since: since, used: 95)

        #expect(HomeModel.usageAndPlace(card, l10n) == l10n.homeChildUsageAndPlace(Durations.short(95, l10n), l10n.homeChildOffline))
        #expect(HomeModel.placeTitle(card, l10n) == l10n.homeChildOffline)
        #expect(HomeModel.placeCaption(card, l10n) == nil)
    }

    @Test func aPlaceTileSaysSinceWhen() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Tashkent"))
        let since = try #require(ISO8601DateFormatter().date(from: "2026-10-05T03:10:00Z"))

        #expect(HomeModel.placeTitle(homeCard(place: "Maktab", since: since), l10n) == "Maktab")
        #expect(HomeModel.placeCaption(homeCard(place: "Maktab", since: since), l10n, calendar: calendar) == l10n.homePlaceSince("08:10"))
        #expect(HomeModel.placeTitle(homeCard(place: nil), l10n) == l10n.homePlaceUnknown)
        #expect(HomeModel.placeCaption(homeCard(place: nil), l10n) == nil)
    }

    @Test func theSosIsBuiltFromTheAlarmAndTheFamily() async {
        let id = UUID()
        let sos = ActiveSos(sosId: UUID(), childId: id, childName: nil, triggeredAt: Date())
        let (model, _, _) = setup([.success(parentHome([homeCard("Ali", id: id)], sos: sos))], family: [makeChild("Ali", id: id, phone: "+998901234567")])
        await model.appear()

        let alert = model.sosAlert(emergencyNumber: "112")

        #expect(alert?.childName == "Ali")
        #expect(alert?.childCallURL == URL(string: "tel:+998901234567"))
        #expect(alert?.emergencyNumber == "112")
    }

    @Test func noAlarmNoBanner() async {
        let (model, _, _) = setup([.success(parentHome([homeCard()]))])
        await model.appear()

        #expect(model.sosAlert(emergencyNumber: "112") == nil)
    }

    @Test func statusLevelsMapToTheDesignSystem() {
        #expect(StatusLevel.good.designLevel == .good)
        #expect(StatusLevel.critical.designLevel == .critical)
        #expect(StatusLevel.action.label(l10n) == l10n.statusLabelAction)
    }
}
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'HomeModel' in scope`.

- [ ] **Step 4: Holat uslubi**

`NozirKit/Sources/NozirAppFeature/Insights/InsightStyle.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// How a server status level looks and reads.
extension StatusLevel {
    var designLevel: NozirStatusLevel {
        switch self {
        case .good: .good
        case .attention: .attention
        case .action: .action
        case .critical: .critical
        }
    }

    func label(_ l10n: L10n) -> String {
        switch self {
        case .good: l10n.statusLabelGood
        case .attention: l10n.statusLabelAttention
        case .action: l10n.statusLabelAction
        case .critical: l10n.statusLabelCritical
        }
    }

    func glyph(_ l10n: L10n) -> String {
        switch self {
        case .good: l10n.statusGlyphGood
        case .attention: l10n.statusGlyphAttention
        case .action: l10n.statusGlyphAction
        case .critical: l10n.statusGlyphCritical
        }
    }

    var content: Color {
        switch self {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        case .critical: NozirColor.criticalContent
        }
    }

    var container: Color {
        switch self {
        case .good: NozirColor.goodContainer
        case .attention: NozirColor.attentionContainer
        case .action: NozirColor.actionContainer
        case .critical: NozirColor.criticalContainer
        }
    }
}
```

- [ ] **Step 5: `HomeModel`**

`NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirInsights
import NozirL10n

/// P05. Asks for home and the family list each time it appears (the age and
/// the phone number live in the family list, not in home). Keeps the last home
/// it had: a later failure becomes a notice above it, never an empty screen.
@MainActor
@Observable
final class HomeModel {
    enum Notice: Equatable {
        case offline
        case message(UserMessage)
    }

    /// Android `MultiChildHome`: the card that needs attention rises; beside it
    /// the others become quiet rows; with no one needing it, every child gets the
    /// same plain card.
    enum CardStyle: Equatable {
        case attention, quiet, plain
    }

    private(set) var home: ParentHome?
    /// Only while there is no home to show.
    private(set) var failure: UserMessage?
    private(set) var notice: Notice?
    /// The P05 avatar filter; nil is "Hammasi".
    var filter: UUID?
    let family: FamilyStore

    private let insights: any InsightsService
    private let currentYear: Int

    init(
        insights: any InsightsService,
        family: FamilyStore,
        currentYear: Int = Calendar.current.component(.year, from: Date())
    ) {
        self.insights = insights
        self.family = family
        self.currentYear = currentYear
    }

    /// Every time P05 is shown: the filter goes back to everyone.
    func appear() async {
        filter = nil
        await load()
    }

    func load() async {
        do {
            let fresh = try await insights.home()
            home = fresh
            failure = nil
            notice = nil
        } catch is CancellationError {
            return
        } catch {
            let message = UserMessage(error)
            if home == nil {
                failure = message
            } else {
                notice = (message == .noConnection || message == .timeout) ? .offline : .message(message)
            }
        }
        // Ages and phone numbers; a failure here keeps the list there was.
        try? await family.refresh()
    }

    var cards: [ChildHomeCard] {
        home?.children ?? []
    }

    /// Those needing attention first, the rest in the server's order: a stable
    /// partition, never a ranking.
    var ordered: [ChildHomeCard] {
        cards.filter(\.needsAttention) + cards.filter { !$0.needsAttention }
    }

    /// The filtered child, or everyone when the filter names no child on screen.
    var visible: [ChildHomeCard] {
        guard let filter, ordered.contains(where: { $0.id == filter }) else { return ordered }
        return ordered.filter { $0.id == filter }
    }

    /// Under the cards: the "not compared" note when someone needs attention,
    /// otherwise the family sentence.
    var showsAttentionNote: Bool {
        visible.contains(where: \.needsAttention)
    }

    func style(of card: ChildHomeCard) -> CardStyle {
        if card.needsAttention { return .attention }
        return showsAttentionNote ? .quiet : .plain
    }

    func age(of card: ChildHomeCard) -> Int? {
        family.child(card.id).map { currentYear - $0.birthYear }
    }

    func nameAndAge(of card: ChildHomeCard, _ l10n: L10n) -> String {
        age(of: card).map { l10n.homeChildNameAndAge(card.displayName, $0) } ?? card.displayName
    }

    func tone(of card: ChildHomeCard) -> AvatarTone {
        .forKey(card.avatarKey, position: cards.firstIndex { $0.id == card.id } ?? 0)
    }

    var switcherChildren: [NozirSwitcherChild] {
        cards.map { NozirSwitcherChild(id: $0.id, name: $0.displayName, tone: tone(of: $0), needsAttention: $0.needsAttention) }
    }

    func sosAlert(emergencyNumber: String?) -> SosAlert? {
        guard let sos = home?.activeSos else { return nil }
        return SosAlert(sos, child: family.child(sos.childId), emergencyNumber: emergencyNumber)
    }

    /// "1s 35d · Maktab". A phone that stopped reporting says so in place of the
    /// place: a stale place is never shown as the current one.
    nonisolated static func usageAndPlace(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        let usage = Durations.short(card.usedMinutes, l10n)
        let place = card.deviceOnline ? card.placeLabel : l10n.homeChildOffline
        return place.map { l10n.homeChildUsageAndPlace(usage, $0) } ?? usage
    }

    /// A quiet row: no news reads as good news.
    nonisolated static func usageAndRules(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        l10n.homeChildUsageAndPlace(Durations.short(card.usedMinutes, l10n), l10n.homeChildRulesFollowed)
    }

    /// The one-child place tile.
    nonisolated static func placeTitle(_ card: ChildHomeCard, _ l10n: L10n) -> String {
        guard card.deviceOnline else { return l10n.homeChildOffline }
        return card.placeLabel ?? l10n.homePlaceUnknown
    }

    nonisolated static func placeCaption(_ card: ChildHomeCard, _ l10n: L10n, calendar: Calendar = .current) -> String? {
        guard card.deviceOnline, card.placeLabel != nil, let since = card.placeSince else { return nil }
        return l10n.homePlaceSince(DateTexts.timeOfDay(since, calendar: calendar))
    }
}
```

- [ ] **Step 6: `HomeView`**

`NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P05 as Android `HomeContent`: the SOS banner, the offline notice, then the
/// family (empty, one child, or many). P15–P18 links are not in this slice.
struct HomeView: View {
    @State private var model: HomeModel
    private let reloadToken: Int
    private let emergencyNumber: () -> String?
    private let onOpenSummary: (UUID, String) -> Void
    private let onAddChild: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var showsSos = false

    init(
        model: HomeModel,
        reloadToken: Int,
        emergencyNumber: @escaping () -> String?,
        onOpenSummary: @escaping (UUID, String) -> Void,
        onAddChild: @escaping () -> Void
    ) {
        _model = State(initialValue: model)
        self.reloadToken = reloadToken
        self.emergencyNumber = emergencyNumber
        self.onOpenSummary = onOpenSummary
        self.onAddChild = onAddChild
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                if let alert = model.sosAlert(emergencyNumber: emergencyNumber()) {
                    SosBanner(alert: alert) { showsSos = true }
                }
                if model.notice == .offline {
                    NozirOfflineNotice(l10n.stateOfflineNotice)
                }
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenHomeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await model.appear() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await model.load() }
            }
        }
        .refreshable { await model.load() }
        .sheet(isPresented: $showsSos) {
            if let alert = model.sosAlert(emergencyNumber: emergencyNumber()) {
                SosSheet(alert: alert)
                    .environment(\.l10n, l10n)
                    .environment(\.locale, locale)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let home = model.home {
            if case .message(let message) = model.notice {
                NozirInlineMessage(message.text(l10n))
            }
            switch home.children.count {
            case 0:
                NozirEmptyState(
                    title: l10n.homeEmptyTitle,
                    message: l10n.homeEmptyBody,
                    actionTitle: l10n.homeEmptyAction,
                    action: onAddChild
                )
            case 1:
                singleChild(home, home.children[0])
            default:
                family(home)
            }
        } else if let failure = model.failure {
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: failure.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    // MARK: One child (P05a)

    @ViewBuilder
    private func singleChild(_ home: ParentHome, _ card: ChildHomeCard) -> some View {
        HStack(spacing: NozirSpacing.compact) {
            NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nameAndAge(of: card, l10n)).nozirText(.titleSmall)
                Text(l10n.homeTodayAndDate(DateTexts.dayAndMonth(home.date, l10n)))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            Spacer(minLength: 0)
            statusChip(card.statusLevel)
        }
        .accessibilityElement(children: .combine)
        if let sentence = card.summarySentence {
            NozirCard {
                Text(l10n.homeSummaryLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(sentence).nozirText(.body)
                Button(l10n.homeSummaryAction) { onOpenSummary(card.id, card.displayName) }
                    .font(.system(size: 15, weight: .semibold))
                    .tint(NozirColor.primaryAccent)
            }
        }
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            statTile(
                label: l10n.homeStatScreenTime,
                value: Durations.short(card.usedMinutes, l10n),
                caption: l10n.homeStatOfLimit(Durations.short(card.limitMinutes, l10n))
            )
            statTile(
                label: l10n.homeStatPlace,
                value: HomeModel.placeTitle(card, l10n),
                caption: HomeModel.placeCaption(card, l10n)
            )
        }
    }

    private func statTile(label: String, value: String, caption: String?) -> some View {
        NozirCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).nozirText(.label, color: NozirColor.textSecondary)
                Text(value).nozirText(.titleSmall)
                if let caption {
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func statusChip(_ level: StatusLevel) -> some View {
        HStack(spacing: NozirSpacing.extraSmall) {
            NozirStatusDot(level.designLevel)
            Text(level.label(l10n)).nozirText(.bodySmall, color: level.content)
        }
        .padding(.horizontal, NozirSpacing.small)
        .padding(.vertical, NozirSpacing.extraSmall)
        .background(Capsule().fill(level.container))
    }

    // MARK: Many children (P05b, P05c)

    @ViewBuilder
    private func family(_ home: ParentHome) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(l10n.homeFamilyTitle).nozirText(.titleLarge)
            Spacer()
            Text(DateTexts.dayAndMonth(home.date, l10n)).nozirText(.bodySmall, color: NozirColor.textTertiary)
        }
        NozirChildSwitcher(
            children: model.switcherChildren,
            selection: $model.filter,
            allTitle: l10n.homeShowAllChildren,
            allAccessibilityLabel: l10n.homeShowAllChildrenDescription,
            addTitle: l10n.homeAddChild,
            onAdd: onAddChild,
            fallbackInitial: l10n.previewAvatarInitial
        )
        ForEach(model.visible) { card in
            Button {
                onOpenSummary(card.id, card.displayName)
            } label: {
                childCard(card)
            }
            .buttonStyle(.plain)
            .accessibilityHint(l10n.homeSummaryAction)
        }
        if model.showsAttentionNote {
            Text(l10n.homeNotComparedNote)
                .nozirText(.bodySmall, color: NozirColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        } else if let sentence = home.familySummary {
            NozirCard {
                Text(l10n.homeFamilySummaryLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(sentence).nozirText(.body)
            }
        }
    }

    @ViewBuilder
    private func childCard(_ card: ChildHomeCard) -> some View {
        switch model.style(of: card) {
        case .attention:
            NozirCard(tone: .attention) {
                HStack(spacing: NozirSpacing.small) {
                    statusMark(.action)
                    NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.nameAndAge(of: card, l10n)).nozirText(.body)
                        Text(HomeModel.usageAndPlace(card, l10n)).nozirText(.bodySmall, color: NozirColor.attentionContent)
                    }
                    Spacer(minLength: 0)
                }
                if let sentence = card.summarySentence {
                    Text(sentence).nozirText(.bodySmall)
                }
                Text(l10n.homeAttentionAction).nozirText(.bodySmall, color: NozirColor.actionContent)
            }
        case .quiet:
            NozirCard {
                row(card, subtitle: HomeModel.usageAndRules(card, l10n), avatarSize: 36)
            }
        case .plain:
            NozirCard {
                row(card, subtitle: HomeModel.usageAndPlace(card, l10n), avatarSize: 40)
                if let sentence = card.summarySentence {
                    Divider()
                    Text(sentence).nozirText(.bodySmall)
                }
            }
        }
    }

    private func row(_ card: ChildHomeCard, subtitle: String, avatarSize: CGFloat) -> some View {
        HStack(spacing: NozirSpacing.compact) {
            NozirAvatar(name: card.displayName, tone: model.tone(of: card), fallbackInitial: l10n.previewAvatarInitial, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.nameAndAge(of: card, l10n)).nozirText(.body)
                Text(subtitle).nozirText(.bodySmall, color: NozirColor.textSecondary)
            }
            Spacer(minLength: 0)
            statusMark(card.statusLevel)
        }
    }

    /// Android `ChildStatusMark`: the level's glyph in its colours; the label is
    /// what VoiceOver reads.
    private func statusMark(_ level: StatusLevel) -> some View {
        Text(level.glyph(l10n))
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(level.content)
            .frame(width: 22, height: 22)
            .background(Circle().fill(level.container))
            .accessibilityLabel(level.label(l10n))
    }
}
```

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`. (`HomeView` hali hech qayerda ishlatilmaydi — Task 10 ulaydi; build uni baribir kompilyatsiya qiladi.)

- [ ] **Step 8: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/InsightStyle.swift NozirKit/Sources/NozirAppFeature/Insights/HomeModel.swift NozirKit/Sources/NozirAppFeature/Screens/HomeView.swift NozirKit/Tests/NozirAppFeatureTests/FakeInsights.swift NozirKit/Tests/NozirAppFeatureTests/HomeModelTests.swift
```

Xabar: `p05: today for every child, the one who needs attention first`

---
### Task 7: P06 Kunlik xulosa — `DailySummaryModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`InsightsService`, `InsightSummary`, `ApiFailure.isNotFound`), Task 1 (`LocalDate.monday`), Task 3 (`DateTexts`), Task 4 (`NozirEmptyState`, `NozirErrorState`), Task 6 (`FakeInsights`, `insight(…)`, `notFound`), 2a (`UserMessage`, `offline`).
- Produces:
  - `@MainActor @Observable final class DailySummaryModel { enum State: Equatable { loading, loaded(InsightSummary), notReady, failed(UserMessage) }; childId: UUID; childName: String; state: State; question: String?; init(childId:childName:date:insights:); load() async; retry() async; func title(_:) -> String; func subtitle(_:) -> String? }`
  - `struct DailySummaryView: View { init(model: DailySummaryModel, onEditChild: @escaping () -> Void, onOpenWeekly: @escaping () -> Void) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()

@MainActor
private func setup(_ script: FakeInsights.Script, date: LocalDate? = nil) -> (DailySummaryModel, FakeInsights) {
    let insights = FakeInsights(script)
    return (DailySummaryModel(childId: aliId, childName: "Ali", date: date, insights: insights), insights)
}

@MainActor
@Suite struct DailySummaryModelTests {
    private let l10n = L10n(.uz)

    @Test func theLatestSummaryAndItsWeeksQuestion() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.success(daily)]
        script.weekly = { _, _ in insight(childId: aliId, start: "2026-09-28", end: "2026-10-04", question: "Nima yoqdi?") }
        let (model, insights) = setup(script)

        await model.load()

        #expect(model.state == .loaded(daily))
        #expect(model.question == "Nima yoqdi?")
        // 2026-10-04 is a Sunday: its week starts on Monday 2026-09-28.
        #expect(await insights.calls == ["daily latest", "weekly 2026-09-28"])
        #expect(await insights.childIds == [aliId, aliId])
    }

    @Test func aDayGivenIsTheDayAsked() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-01", end: "2026-10-01"))]
        let (model, insights) = setup(script, date: day("2026-10-01"))

        await model.load()

        #expect(await insights.calls.first == "daily 2026-10-01")
    }

    @Test func aSummaryNotWrittenYetIsNotAnError() async {
        var script = FakeInsights.Script()
        script.daily = [.failure(notFound)]
        let (model, insights) = setup(script)

        await model.load()

        #expect(model.state == .notReady)
        #expect(await insights.calls == ["daily latest"])
    }

    @Test func theFreePlanIsTold() async {
        var script = FakeInsights.Script()
        script.daily = [.failure(.server(status: 403, error: ApiError(code: .subscriptionRequired)))]
        let (model, _) = setup(script)

        await model.load()

        #expect(model.state == .failed(.subscriptionRequired))
    }

    @Test func aWeeklyFailureIsSilent() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.success(daily)]
        script.weekly = { _, _ in throw offline }
        let (model, _) = setup(script)

        await model.load()

        #expect(model.state == .loaded(daily))
        #expect(model.question == nil)
    }

    @Test func aFailureCanBeRetried() async {
        let daily = insight(childId: aliId, start: "2026-10-04", end: "2026-10-04")
        var script = FakeInsights.Script()
        script.daily = [.failure(offline), .success(daily)]
        let (model, _) = setup(script)
        await model.load()
        #expect(model.state == .failed(.noConnection))

        await model.retry()

        #expect(model.state == .loaded(daily))
    }

    @Test func comingBackDoesNotAskAgain() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-04", end: "2026-10-04"))]
        let (model, insights) = setup(script)
        await model.load()

        await model.load()

        #expect(await insights.calls.filter { $0.hasPrefix("daily") }.count == 1)
    }

    @Test func theHeaderNamesTheChildAndTheDay() async {
        var script = FakeInsights.Script()
        script.daily = [.success(insight(childId: aliId, start: "2026-10-04", end: "2026-10-04"))]
        let (model, _) = setup(script)
        #expect(model.subtitle(l10n) == nil)

        await model.load()

        #expect(model.title(l10n) == l10n.dailySummaryChildToday("Ali"))
        #expect(model.subtitle(l10n) == DateTexts.weekdayAndDate(day("2026-10-04"), l10n))
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'DailySummaryModel' in scope`.

- [ ] **Step 3: `DailySummaryModel`**

`NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift`:

```swift
import Foundation
import Observation
import NozirInsights
import NozirL10n
import NozirNetworking

/// P06. The daily summary first; then, for the "ask this week" line only, the
/// weekly summary of the week the day belongs to (plan deviation E2: only the
/// daily answer knows which day it is). A weekly failure is silent.
@MainActor
@Observable
final class DailySummaryModel {
    enum State: Equatable {
        case loading
        case loaded(InsightSummary)
        /// 404: the server writes a summary only for a finished day. An answer, not a fault.
        case notReady
        case failed(UserMessage)
    }

    let childId: UUID
    let childName: String
    private(set) var state: State = .loading
    private(set) var question: String?

    private let date: LocalDate?
    private let insights: any InsightsService

    init(childId: UUID, childName: String, date: LocalDate? = nil, insights: any InsightsService) {
        self.childId = childId
        self.childName = childName
        self.date = date
        self.insights = insights
    }

    /// On appear. A summary already read is not asked for again.
    func load() async {
        if case .loaded = state { return }
        await fetch()
    }

    func retry() async {
        state = .loading
        await fetch()
    }

    private func fetch() async {
        do {
            let summary = try await insights.dailySummary(of: childId, on: date)
            state = .loaded(summary)
            let weekly = try? await insights.weeklySummary(of: childId, weekStart: summary.periodEnd.monday)
            question = weekly?.conversationQuestion
        } catch is CancellationError {
            return
        } catch let failure as ApiFailure where failure.isNotFound {
            state = .notReady
        } catch {
            state = .failed(UserMessage(error))
        }
    }

    /// "Ali bugun" — Android's label; the summary is about the last finished day.
    func title(_ l10n: L10n) -> String {
        l10n.dailySummaryChildToday(childName)
    }

    /// "Yakshanba, 4-oktabr" once the summary has said which day it is.
    func subtitle(_ l10n: L10n) -> String? {
        guard case .loaded(let summary) = state else { return nil }
        return DateTexts.weekdayAndDate(summary.periodEnd, l10n)
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P06 as Android `DailySummaryScreen`: paragraphs, a recommendation, a
/// question for the week, the "no messages were read" promise, and the way on
/// to the weekly report.
struct DailySummaryView: View {
    @State private var model: DailySummaryModel
    private let onEditChild: () -> Void
    private let onOpenWeekly: () -> Void
    @Environment(\.l10n) private var l10n

    init(model: DailySummaryModel, onEditChild: @escaping () -> Void, onOpenWeekly: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onEditChild = onEditChild
        self.onOpenWeekly = onOpenWeekly
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                header
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenDailySummaryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onEditChild) { Image(systemName: "pencil") }
                    .accessibilityLabel(l10n.contentDescriptionChildDetails)
            }
        }
        .task { await model.load() }
        .refreshable { await model.retry() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.title(l10n)).nozirText(.titleLarge)
            if let subtitle = model.subtitle(l10n) {
                Text(subtitle).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        case .notReady:
            NozirEmptyState(title: l10n.dailySummaryEmptyTitle, message: l10n.dailySummaryEmptyBody)
            weeklyButton
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.retry() }
            }
        case .loaded(let summary):
            loaded(summary)
        }
    }

    @ViewBuilder
    private func loaded(_ summary: InsightSummary) -> some View {
        NozirCard {
            ForEach(Array(summary.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                Text(paragraph).nozirText(.body)
            }
        }
        if let recommendation = summary.recommendation {
            NozirCard {
                Text(l10n.dailySummaryRecommendationLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(recommendation).nozirText(.body)
            }
        }
        if let question = model.question {
            NozirCard {
                Text(l10n.dailySummaryQuestionLabel).nozirText(.label, color: NozirColor.textSecondary)
                Text(question).nozirText(.body)
            }
        }
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            Image(systemName: "lock.fill")
                .foregroundStyle(NozirColor.textTertiary)
                .accessibilityHidden(true)
            Text(l10n.dailySummaryNotice + " " + l10n.dailySummaryNoticePromise)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        weeklyButton
    }

    private var weeklyButton: some View {
        NozirButton(l10n.dailySummaryActionWeekly, variant: .secondary, action: onOpenWeekly)
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/DailySummaryModel.swift NozirKit/Sources/NozirAppFeature/Screens/DailySummaryView.swift NozirKit/Tests/NozirAppFeatureTests/DailySummaryModelTests.swift
```

Xabar: `p06: the day in a few paragraphs, and a question for the week`

---
### Task 8: P07 Haftalik hisobot — `WeeklyReportModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/WeeklyReportView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift`

**Interfaces:**
- Consumes: Task 1 (`LocalDate`), Task 2 (`InsightsService`, `DailyUsage`, `StatusLevel`), Task 3 (`ChartMath`, `DateTexts`, `Durations`), Task 4 (`NozirColumnChart`, `NozirChartColumn`, `NozirChildSwitcher`, `NozirSwitcherChild`, holatlar), Task 6 (`FakeInsights`, `insight`, `day`, `StatusLevel.content`).
- Produces:
  - `@MainActor @Observable final class WeeklyReportModel { struct Day: Equatable { date; usedMinutes; isFuture }; struct Page: Equatable { days: [Day]; observations: [String]; risk: StatusLevel }; enum PageState: Equatable { loading, loaded(Page), failed(UserMessage) }; static let weekCount = 53; childId: UUID; weeks: [LocalDate]; var selectedWeek: LocalDate; currentWeek: LocalDate; pages: [LocalDate: PageState]; init(childId:insights:today:); appear() async; show(_:) async; retry(_:) async; setChild(_:) async; week(before:) -> LocalDate?; week(after:) -> LocalDate?; title(of:_:) -> String; static range(of:_:), columns(_:_:), chartDescription(_:_:), peakLine(_:_:), isEmpty(_:) }`
  - `struct WeeklySwitcher { children: [NozirSwitcherChild]; selection: Binding<UUID?> }`
  - `struct WeeklyReportView: View { init(model: WeeklyReportModel, switcher: WeeklySwitcher?, onOpenApps: @escaping (UUID) -> Void) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirInsights
import NozirL10n
@testable import NozirAppFeature

private let aliId = UUID()
private let valiId = UUID()

/// "Today" that a test can move.
@MainActor
private final class Today {
    var value: LocalDate

    init(_ text: String) {
        value = day(text)
    }
}

private func usage(_ minutes: [Int], from monday: LocalDate) -> [DailyUsage] {
    minutes.enumerated().map { DailyUsage(date: monday.adding(days: $0.offset), usedMinutes: $0.element, limitMinutes: 120) }
}

@MainActor
private func setup(_ script: FakeInsights.Script, today: Today? = nil) -> (WeeklyReportModel, FakeInsights) {
    let clock = today ?? Today("2026-10-07")
    let insights = FakeInsights(script)
    let model = WeeklyReportModel(childId: aliId, insights: insights, today: { clock.value })
    return (model, insights)
}

@MainActor
@Suite struct WeeklyReportModelTests {
    private let l10n = L10n(.uz)

    @Test func fiftyThreeWeeksEndingWithThisOne() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.weeks.count == 53)
        #expect(model.weeks.last == day("2026-10-05"))
        #expect(model.weeks.first == day("2025-10-06"))
        #expect(model.currentWeek == day("2026-10-05"))
        #expect(model.selectedWeek == day("2026-10-05"))
        #expect(zip(model.weeks, model.weeks.dropFirst()).allSatisfy { $0.adding(days: 7) == $1 })
    }

    @Test func aWeekIsItsUsageAndItsObservations() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([30, 60, 0], from: from) }
        script.weekly = { _, monday in
            insight(childId: aliId, start: monday.text, end: monday.adding(days: 6).text, paragraphs: ["Bir.", "Ikki."], risk: .attention)
        }
        let (model, insights) = setup(script)

        await model.appear()

        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.days.map(\.usedMinutes) == [30, 60, 0, 0, 0, 0, 0])
        #expect(page.days.map(\.isFuture) == [false, false, false, true, true, true, true])
        #expect(page.observations == ["Bir.", "Ikki."])
        #expect(page.risk == .attention)
        let calls = await insights.calls
        #expect(calls.prefix(2) == ["usage 2026-10-05…2026-10-11", "weekly 2026-10-05"])
    }

    @Test func thePreviousWeekIsFetchedAhead() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let (model, insights) = setup(script)

        await model.appear()

        #expect(await insights.calls == [
            "usage 2026-10-05…2026-10-11", "weekly 2026-10-05",
            "usage 2026-09-28…2026-10-04", "weekly 2026-09-28",
        ])
        #expect(model.pages[day("2026-09-28")] != nil)
    }

    @Test func aWeekSeenIsNotAskedForAgain() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let (model, insights) = setup(script)
        await model.appear()
        let before = await insights.calls.count

        await model.show(day("2026-10-05"))
        await model.appear()

        #expect(await insights.calls.count == before)
    }

    @Test func aWeeklySummaryFailureLeavesTheChart() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10, 20], from: from) }
        script.weekly = { _, _ in throw offline }
        let (model, _) = setup(script)

        await model.appear()

        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.observations.isEmpty)
        #expect(page.days[1].usedMinutes == 20)
    }

    @Test func aUsageFailureIsAnErrorAndCanBeRetried() async {
        var script = FakeInsights.Script()
        script.usage = { _, _, _ in throw offline }
        let (model, insights) = setup(script)
        await model.appear()
        #expect(model.pages[day("2026-10-05")] == .failed(.noConnection))

        await insights.add { $0.usage = { _, from, _ in usage([5], from: from) } }
        await model.retry(day("2026-10-05"))

        guard case .loaded = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
    }

    @Test func anotherChildStartsFromNothing() async {
        var script = FakeInsights.Script()
        script.usage = { child, from, _ in usage([child == aliId ? 10 : 90], from: from) }
        let (model, insights) = setup(script)
        await model.appear()

        await model.setChild(valiId)

        #expect(model.childId == valiId)
        guard case .loaded(let page) = model.pages[day("2026-10-05")] else {
            Issue.record("expected a loaded page")
            return
        }
        #expect(page.days[0].usedMinutes == 90)
        #expect(await insights.childIds.suffix(4) == [valiId, valiId, valiId, valiId])
    }

    @Test func aNewWeekMovesTheReportOn() async {
        var script = FakeInsights.Script()
        script.usage = { _, from, _ in usage([10], from: from) }
        let today = Today("2026-10-11")
        let (model, _) = setup(script, today: today)
        await model.appear()

        today.value = day("2026-10-12")
        await model.appear()

        #expect(model.currentWeek == day("2026-10-12"))
        #expect(model.selectedWeek == day("2026-10-12"))
        #expect(model.weeks.count == 53)
    }

    @Test func weeksStepWithinTheRange() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.week(before: day("2026-10-05")) == day("2026-09-28"))
        #expect(model.week(after: day("2026-10-05")) == nil)
        #expect(model.week(before: day("2025-10-06")) == nil)
    }

    @Test func titlesSayThisWeekAndLastWeek() {
        let (model, _) = setup(FakeInsights.Script())

        #expect(model.title(of: day("2026-10-05"), l10n) == l10n.weeklyReportTitle)
        #expect(model.title(of: day("2026-09-28"), l10n) == l10n.weeklyReportTitleLastWeek)
        #expect(model.title(of: day("2026-09-21"), l10n) == l10n.screenWeeklyReportTitle)
        #expect(WeeklyReportModel.range(of: day("2026-09-28"), l10n) == DateTexts.weekRange(day("2026-09-28"), day("2026-10-04"), l10n))
    }

    @Test func theChartMarksThePeakAndLeavesTheFutureBlank() {
        let monday = day("2026-10-05")
        let page = WeeklyReportModel.Page(
            days: [30, 60, 60, 0, 0, 0, 0].enumerated().map {
                WeeklyReportModel.Day(date: monday.adding(days: $0.offset), usedMinutes: $0.element, isFuture: $0.offset >= 3)
            },
            observations: [],
            risk: .good
        )

        let columns = WeeklyReportModel.columns(page, l10n)

        #expect(columns.map(\.label) == l10n.weekdayNamesShort)
        #expect(columns.map(\.fraction) == [0.5, 1, 1, 0, 0, 0, 0])
        #expect(columns.map(\.isPeak) == [false, true, false, false, false, false, false])
        #expect(columns[0].valueLabel == Durations.short(30, l10n))
        #expect(columns[3].valueLabel == "")
        #expect(WeeklyReportModel.peakLine(page, l10n) == l10n.weeklyPeakLine(l10n.weekdayNames[1].lowercased(), Durations.long(60, l10n)))
        let spoken = [
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[0], Durations.short(30, l10n)),
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[1], Durations.short(60, l10n)),
            l10n.weeklyChartDayValue(l10n.weekdayNamesShort[2], Durations.short(60, l10n)),
        ]
        #expect(WeeklyReportModel.chartDescription(columns, l10n) == l10n.weeklyChartDescription(spoken.joined(separator: ", ")))
    }

    @Test func aQuietWeekHasNoPeakAndWithoutObservationsIsEmpty() {
        let monday = day("2026-10-05")
        let zeros = (0..<7).map { WeeklyReportModel.Day(date: monday.adding(days: $0), usedMinutes: 0, isFuture: false) }

        #expect(WeeklyReportModel.peakLine(WeeklyReportModel.Page(days: zeros, observations: [], risk: .good), l10n) == nil)
        #expect(WeeklyReportModel.isEmpty(WeeklyReportModel.Page(days: zeros, observations: [], risk: .good)))
        #expect(!WeeklyReportModel.isEmpty(WeeklyReportModel.Page(days: zeros, observations: ["Bir."], risk: .good)))
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'WeeklyReportModel' in scope`.

- [ ] **Step 3: `WeeklyReportModel`**

`NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P07. Fifty-three ISO weeks (this one last) for one child; each page is the
/// week's daily usage and the weekly summary's paragraphs. Pages stay in memory
/// by Monday; the week before the one shown is fetched ahead; one request per
/// (child, week) at a time. Usage then summary, one after the other (plan
/// deviation E3); a summary failure, 403/404 included, only hides observations.
@MainActor
@Observable
final class WeeklyReportModel {
    struct Day: Equatable {
        let date: LocalDate
        let usedMinutes: Int
        /// A day still to come: no figure over it.
        let isFuture: Bool
    }

    struct Page: Equatable {
        let days: [Day]
        let observations: [String]
        let risk: StatusLevel
    }

    enum PageState: Equatable {
        case loading
        case loaded(Page)
        case failed(UserMessage)
    }

    private struct Key: Hashable {
        let child: UUID
        let week: LocalDate
    }

    static let weekCount = 53

    private(set) var childId: UUID
    /// Mondays, oldest first; the last is this week.
    private(set) var weeks: [LocalDate]
    /// The page on screen; the view's pager writes it.
    var selectedWeek: LocalDate
    private(set) var pages: [LocalDate: PageState] = [:]

    private let insights: any InsightsService
    private let today: @MainActor () -> LocalDate
    @ObservationIgnored private var inFlight: Set<Key> = []

    init(childId: UUID, insights: any InsightsService, today: @escaping @MainActor () -> LocalDate) {
        self.childId = childId
        self.insights = insights
        self.today = today
        let current = today().monday
        weeks = Self.weeks(endingAt: current)
        selectedWeek = current
    }

    static func weeks(endingAt current: LocalDate) -> [LocalDate] {
        (0..<weekCount).map { current.adding(days: -7 * (weekCount - 1 - $0)) }
    }

    var currentWeek: LocalDate {
        weeks[weeks.count - 1]
    }

    /// Whenever the screen or the shown page appears. A Monday that has come
    /// since the screen was built moves the report on to the new week.
    func appear() async {
        let current = today().monday
        if current != currentWeek {
            weeks = Self.weeks(endingAt: current)
            selectedWeek = current
            pages = [:]
        }
        await show(selectedWeek)
    }

    /// Loads `week` (if not already there) and then the week before it.
    func show(_ week: LocalDate) async {
        await loadIfNeeded(week)
        if let previous = self.week(before: week) {
            await loadIfNeeded(previous)
        }
    }

    func retry(_ week: LocalDate) async {
        pages[week] = nil
        await loadIfNeeded(week)
    }

    /// Statistics' child switcher: the same week, a different child, nothing cached.
    func setChild(_ id: UUID) async {
        guard id != childId else { return }
        childId = id
        pages = [:]
        await show(selectedWeek)
    }

    func week(before week: LocalDate) -> LocalDate? {
        guard let index = weeks.firstIndex(of: week), index > 0 else { return nil }
        return weeks[index - 1]
    }

    func week(after week: LocalDate) -> LocalDate? {
        guard let index = weeks.firstIndex(of: week), index < weeks.count - 1 else { return nil }
        return weeks[index + 1]
    }

    private func loadIfNeeded(_ week: LocalDate) async {
        let child = childId
        let key = Key(child: child, week: week)
        guard !inFlight.contains(key) else { return }
        switch pages[week] {
        case .loaded?, .failed?: return
        case .loading?, nil: break
        }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        pages[week] = .loading
        do {
            let usage = try await insights.dailyUsage(of: child, from: week, to: week.adding(days: 6))
            let summary = try? await insights.weeklySummary(of: child, weekStart: week)
            guard child == childId else { return }
            guard !Task.isCancelled else {
                pages[week] = nil
                return
            }
            let page = Page(
                days: Self.days(of: week, from: usage, today: today()),
                observations: summary?.paragraphs ?? [],
                risk: summary?.riskLevel ?? .good
            )
            pages[week] = .loaded(page)
        } catch is CancellationError {
            if child == childId { pages[week] = nil }
        } catch {
            guard child == childId else { return }
            pages[week] = .failed(UserMessage(error))
        }
    }

    /// Monday to Sunday; a day the server left out counts as zero.
    static func days(of week: LocalDate, from usage: [DailyUsage], today: LocalDate) -> [Day] {
        let minutes = Dictionary(usage.map { ($0.date, $0.usedMinutes) }, uniquingKeysWith: { first, _ in first })
        return (0..<7).map { offset in
            let date = week.adding(days: offset)
            return Day(date: date, usedMinutes: minutes[date] ?? 0, isFuture: date > today)
        }
    }

    /// "Bu hafta", "Oʻtgan hafta", then the report's own name.
    func title(of week: LocalDate, _ l10n: L10n) -> String {
        if week == currentWeek { return l10n.weeklyReportTitle }
        if week == currentWeek.adding(days: -7) { return l10n.weeklyReportTitleLastWeek }
        return l10n.screenWeeklyReportTitle
    }

    nonisolated static func range(of week: LocalDate, _ l10n: L10n) -> String {
        DateTexts.weekRange(week, week.adding(days: 6), l10n)
    }

    /// Android `weeklyChartColumns`: short weekday, short duration (blank for
    /// days to come), height from zero, the first equal peak marked.
    nonisolated static func columns(_ page: Page, _ l10n: L10n) -> [NozirChartColumn] {
        let minutes = page.days.map(\.usedMinutes)
        let fractions = ChartMath.fractions(minutes)
        let peak = ChartMath.peakIndex(minutes)
        return page.days.enumerated().map { index, day in
            NozirChartColumn(
                id: index,
                label: DateTexts.shortWeekday(day.date, l10n),
                valueLabel: day.isFuture ? "" : Durations.short(day.usedMinutes, l10n),
                fraction: fractions[index],
                isPeak: index == peak
            )
        }
    }

    /// The chart as VoiceOver reads it: every day that has a figure.
    nonisolated static func chartDescription(_ columns: [NozirChartColumn], _ l10n: L10n) -> String {
        let spoken = columns
            .filter { !$0.valueLabel.isEmpty }
            .map { l10n.weeklyChartDayValue($0.label, $0.valueLabel) }
        return l10n.weeklyChartDescription(spoken.joined(separator: l10n.weeklyChartDaySeparator))
    }

    /// "Eng koʻp: seshanba — 1 soat 0 daqiqa"; nil for a week of zeros.
    nonisolated static func peakLine(_ page: Page, _ l10n: L10n) -> String? {
        guard let peak = ChartMath.peakIndex(page.days.map(\.usedMinutes)) else { return nil }
        let day = page.days[peak]
        return l10n.weeklyPeakLine(DateTexts.weekday(day.date, l10n).lowercased(), Durations.long(day.usedMinutes, l10n))
    }

    /// No use at all and nothing observed.
    nonisolated static func isEmpty(_ page: Page) -> Bool {
        page.days.allSatisfy { $0.usedMinutes == 0 } && page.observations.isEmpty
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/WeeklyReportView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// The Statistics tab's child switcher, when there is more than one child.
struct WeeklySwitcher {
    let children: [NozirSwitcherChild]
    let selection: Binding<UUID?>
}

/// P07 as Android `WeeklyReportScreen`: one page per week, swiped or stepped
/// with ‹ ›, this week last.
struct WeeklyReportView: View {
    @State private var model: WeeklyReportModel
    private let switcher: WeeklySwitcher?
    private let onOpenApps: (UUID) -> Void
    @Environment(\.l10n) private var l10n

    init(model: WeeklyReportModel, switcher: WeeklySwitcher?, onOpenApps: @escaping (UUID) -> Void) {
        _model = State(initialValue: model)
        self.switcher = switcher
        self.onOpenApps = onOpenApps
    }

    var body: some View {
        VStack(spacing: NozirSpacing.small) {
            if let switcher {
                NozirChildSwitcher(
                    children: switcher.children,
                    selection: switcher.selection,
                    fallbackInitial: l10n.previewAvatarInitial
                )
                .padding(.horizontal, NozirSpacing.medium)
            }
            weekHeader
                .padding(.horizontal, NozirSpacing.medium)
            TabView(selection: $model.selectedWeek) {
                ForEach(model.weeks, id: \.self) { week in
                    ScrollView {
                        page(week)
                            .padding(NozirSpacing.medium)
                    }
                    .tag(week)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenWeeklyReportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.selectedWeek) { await model.appear() }
    }

    private var weekHeader: some View {
        HStack {
            Button {
                if let previous = model.week(before: model.selectedWeek) { model.selectedWeek = previous }
            } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .disabled(model.week(before: model.selectedWeek) == nil)
            .accessibilityLabel(l10n.contentDescriptionPreviousWeek)
            Spacer()
            VStack(spacing: 2) {
                Text(model.title(of: model.selectedWeek, l10n)).nozirText(.titleSmall)
                Text(WeeklyReportModel.range(of: model.selectedWeek, l10n))
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button {
                if let next = model.week(after: model.selectedWeek) { model.selectedWeek = next }
            } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .disabled(model.week(after: model.selectedWeek) == nil)
            .accessibilityLabel(l10n.contentDescriptionNextWeek)
        }
        .tint(NozirColor.primaryAccent)
    }

    @ViewBuilder
    private func page(_ week: LocalDate) -> some View {
        switch model.pages[week] {
        case .loaded(let page)?:
            loaded(page)
        case .failed(let message)?:
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.retry(week) }
            }
        case .loading?, nil:
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
        }
    }

    @ViewBuilder
    private func loaded(_ page: WeeklyReportModel.Page) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            if WeeklyReportModel.isEmpty(page) {
                NozirEmptyState(title: l10n.weeklyEmptyTitle, message: l10n.weeklyEmptyBody)
            } else {
                let columns = WeeklyReportModel.columns(page, l10n)
                NozirCard {
                    Text(l10n.weeklyChartLabel).nozirText(.label, color: NozirColor.textSecondary)
                    NozirColumnChart(
                        columns: columns,
                        accessibilityLabel: WeeklyReportModel.chartDescription(columns, l10n)
                    )
                    if let peakLine = WeeklyReportModel.peakLine(page, l10n) {
                        Text(peakLine).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                if !page.observations.isEmpty {
                    NozirCard {
                        Text(l10n.weeklyObservationsLabel).nozirText(.label, color: NozirColor.textSecondary)
                        ForEach(Array(page.observations.enumerated()), id: \.offset) { _, observation in
                            HStack(alignment: .firstTextBaseline, spacing: NozirSpacing.small) {
                                Circle()
                                    .fill(page.risk.content)
                                    .frame(width: 8, height: 8)
                                    .accessibilityHidden(true)
                                Text(observation).nozirText(.body)
                            }
                        }
                    }
                }
            }
            NozirButton(l10n.weeklyActionApps, variant: .secondary) {
                onOpenApps(model.childId)
            }
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
git add NozirKit/Sources/NozirAppFeature/Insights/WeeklyReportModel.swift NozirKit/Sources/NozirAppFeature/Screens/WeeklyReportView.swift NozirKit/Tests/NozirAppFeatureTests/WeeklyReportModelTests.swift
```

Xabar: `p07: a year of weeks, a column a day, what the week was like`

---
### Task 9: P08 Ilovalar — `AppUsageModel` va ekran

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/AppUsageModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/AppUsageView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppUsageModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`InsightsService`, `UsageRange`, `AppBreakdown`, `AppUsageEntry`), Task 3 (`AppUsageFolding`, `ChartMath`, `Durations`), Task 4 (`NozirStackedBar`, `NozirChartSegment`, `NozirLegend`, `NozirLegendItem`, `NozirProgressBar`, `NozirColor.chartSeries/chartOther`, holatlar), Task 6 (`FakeInsights`), 2a (`offline`).
- Produces:
  - `@MainActor @Observable final class AppUsageModel { enum State: Equatable { loading, loaded(AppBreakdown), failed(UserMessage) }; childId: UUID; var range: UsageRange; state: State; var showsTable: Bool; init(childId:insights:); load() async; entries: [AppUsageEntry]; total: Int; isEmpty: Bool; static name(of:_:) -> String; static colorIndex(of:at:) -> Int?; static chartDescription(_:_:) -> String; static rangeTitle(_:_:) -> String }`
  - `struct AppUsageView: View { init(model: AppUsageModel) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/AppUsageModelTests.swift`:

```swift
import Foundation
import Testing
import NozirInsights
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let aliId = UUID()

private func app(_ packageId: String, _ minutes: Int, name: String = "") -> AppUsageEntry {
    AppUsageEntry(packageId: packageId, displayName: name, minutes: minutes)
}

private func breakdown(_ range: UsageRange, _ entries: [AppUsageEntry]) -> AppBreakdown {
    AppBreakdown(range: range, totalMinutes: entries.reduce(0) { $0 + $1.minutes }, entries: entries)
}

/// Holds the "today" answer until the test lets it go; every other range answers at once.
private actor GatedInsights: InsightsService {
    private var todayAsked = false
    private var askedWaiter: CheckedContinuation<Void, Never>?
    private var release: CheckedContinuation<Void, Never>?

    func appUsage(of childId: UUID, range: UsageRange) async throws -> AppBreakdown {
        guard range == .today else { return breakdown(range, [app("b", 70)]) }
        todayAsked = true
        askedWaiter?.resume()
        askedWaiter = nil
        await withCheckedContinuation { release = $0 }
        return breakdown(.today, [app("a", 10)])
    }

    func waitUntilTodayIsAsked() async {
        if todayAsked { return }
        await withCheckedContinuation { askedWaiter = $0 }
    }

    func answerToday() {
        release?.resume()
        release = nil
    }

    func home() async throws -> ParentHome { throw offline }
    func dailySummary(of childId: UUID, on date: LocalDate?) async throws -> InsightSummary { throw offline }
    func weeklySummary(of childId: UUID, weekStart: LocalDate) async throws -> InsightSummary { throw offline }
    func dailyUsage(of childId: UUID, from: LocalDate, to: LocalDate) async throws -> [DailyUsage] { throw offline }
}

@MainActor
@Suite struct AppUsageModelTests {
    private let l10n = L10n(.uz)

    @Test func todayIsAskedFirst() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, [app("a", 10)]) }
        let insights = FakeInsights(script)
        let model = AppUsageModel(childId: aliId, insights: insights)

        await model.load()

        #expect(model.range == .today)
        #expect(model.state == .loaded(breakdown(.today, [app("a", 10)])))
        #expect(await insights.calls == ["apps TODAY"])
        #expect(await insights.childIds == [aliId])
    }

    @Test func anotherRangeIsAskedAgain() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, [app("a", range == .lastThirtyDays ? 900 : 10)]) }
        let insights = FakeInsights(script)
        let model = AppUsageModel(childId: aliId, insights: insights)
        await model.load()

        model.range = .lastThirtyDays
        await model.load()

        #expect(model.total == 900)
        #expect(await insights.calls == ["apps TODAY", "apps LAST_30_DAYS"])
    }

    // Review Focus 1.
    @Test func aLateAnswerForAnOldRangeIsIgnored() async {
        let gated = GatedInsights()
        let model = AppUsageModel(childId: aliId, insights: gated)
        let first = Task { await model.load() }
        await gated.waitUntilTodayIsAsked()

        model.range = .lastSevenDays
        await model.load()
        await gated.answerToday()
        await first.value

        #expect(model.range == .lastSevenDays)
        #expect(model.state == .loaded(breakdown(.lastSevenDays, [app("b", 70)])))
    }

    @Test func aFailureIsAnErrorAndCanBeRetried() async {
        let insights = FakeInsights()
        let model = AppUsageModel(childId: aliId, insights: insights)
        await model.load()
        #expect(model.state == .failed(.noConnection))

        await insights.add { $0.apps = { _, range in breakdown(range, [app("a", 10)]) } }
        await model.load()

        #expect(model.state == .loaded(breakdown(.today, [app("a", 10)])))
    }

    @Test func noAppsIsEmpty() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in breakdown(range, []) }
        let model = AppUsageModel(childId: aliId, insights: FakeInsights(script))

        await model.load()

        #expect(model.isEmpty)
        #expect(model.entries.isEmpty)
    }

    @Test func entriesAreFoldedWithOthersLast() async {
        var script = FakeInsights.Script()
        script.apps = { _, range in
            breakdown(range, [app("nozir.other_apps", 5), app("a", 10), app("b", 40), app("c", 30), app("d", 20), app("e", 15)])
        }
        let model = AppUsageModel(childId: aliId, insights: FakeInsights(script))

        await model.load()

        #expect(model.entries.map(\.packageId) == ["b", "c", "d", "e", "nozir.other_apps"])
        #expect(model.entries.last?.minutes == 15)
        #expect(model.total == 120)
        #expect(!model.isEmpty)
    }

    @Test func namesAndColoursFollowTheChartRule() {
        #expect(AppUsageModel.name(of: app("nozir.other_apps", 5, name: "Other"), l10n) == l10n.appUsageOther)
        #expect(AppUsageModel.name(of: app("com.google.android.youtube", 5, name: "com.google.android.youtube"), l10n) == "YouTube")
        #expect(AppUsageModel.colorIndex(of: app("a", 1), at: 0) == 0)
        #expect(AppUsageModel.colorIndex(of: app("d", 1), at: 3) == 3)
        #expect(AppUsageModel.colorIndex(of: app("nozir.other_apps", 1), at: 1) == nil)
        #expect(AppUsageModel.colorIndex(of: app("z", 1), at: 4) == nil)
    }

    @Test func theBarIsSaidAloud() {
        let entries = [app("org.telegram.messenger", 30), app("nozir.other_apps", 15)]

        let expected = l10n.appUsageChartDescription([
            l10n.appUsageChartEntry("Telegram", Durations.short(30, l10n)),
            l10n.appUsageChartEntry(l10n.appUsageOther, Durations.short(15, l10n)),
        ].joined(separator: ", "))

        #expect(AppUsageModel.chartDescription(entries, l10n) == expected)
    }

    @Test func rangesHaveTheirNames() {
        #expect(AppUsageModel.rangeTitle(.today, l10n) == l10n.rangeToday)
        #expect(AppUsageModel.rangeTitle(.lastSevenDays, l10n) == l10n.rangeSevenDays)
        #expect(AppUsageModel.rangeTitle(.lastThirtyDays, l10n) == l10n.rangeThirtyDays)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'AppUsageModel' in scope`.

- [ ] **Step 3: `AppUsageModel`**

`NozirKit/Sources/NozirAppFeature/Insights/AppUsageModel.swift`:

```swift
import Foundation
import Observation
import NozirInsights
import NozirL10n

/// P08 for one child. The view binds `range` and calls `load()` whenever it
/// changes; an answer for a range that is no longer chosen is dropped, so a
/// slow "Bugun" can never overwrite "7 kun".
@MainActor
@Observable
final class AppUsageModel {
    enum State: Equatable {
        case loading
        case loaded(AppBreakdown)
        case failed(UserMessage)
    }

    let childId: UUID
    var range: UsageRange = .today
    private(set) var state: State = .loading
    var showsTable = false

    private let insights: any InsightsService
    @ObservationIgnored private var generation = 0

    init(childId: UUID, insights: any InsightsService) {
        self.childId = childId
        self.insights = insights
    }

    func load() async {
        generation += 1
        let mine = generation
        let asked = range
        state = .loading
        do {
            let breakdown = try await insights.appUsage(of: childId, range: asked)
            guard mine == generation else { return }
            state = .loaded(breakdown)
        } catch is CancellationError {
            return
        } catch {
            guard mine == generation else { return }
            state = .failed(UserMessage(error))
        }
    }

    /// Top four, then "Boshqalar" last.
    var entries: [AppUsageEntry] {
        guard case .loaded(let breakdown) = state else { return [] }
        return AppUsageFolding.folded(breakdown.entries)
    }

    var total: Int {
        guard case .loaded(let breakdown) = state else { return 0 }
        return breakdown.totalMinutes
    }

    var isEmpty: Bool {
        guard case .loaded = state else { return false }
        return entries.isEmpty
    }

    nonisolated static func name(of entry: AppUsageEntry, _ l10n: L10n) -> String {
        entry.isOtherApps ? l10n.appUsageOther : AppUsageFolding.friendlyName(packageId: entry.packageId, reported: entry.displayName)
    }

    /// Which of the four series colours; nil is the grey of "Boshqalar".
    nonisolated static func colorIndex(of entry: AppUsageEntry, at index: Int) -> Int? {
        guard !entry.isOtherApps, index < AppUsageFolding.keptApps else { return nil }
        return index
    }

    /// The stacked bar as VoiceOver reads it.
    nonisolated static func chartDescription(_ entries: [AppUsageEntry], _ l10n: L10n) -> String {
        let spoken = entries.map { l10n.appUsageChartEntry(name(of: $0, l10n), Durations.short($0.minutes, l10n)) }
        return l10n.appUsageChartDescription(spoken.joined(separator: l10n.weeklyChartDaySeparator))
    }

    nonisolated static func rangeTitle(_ range: UsageRange, _ l10n: L10n) -> String {
        switch range {
        case .today: l10n.rangeToday
        case .lastSevenDays: l10n.rangeSevenDays
        case .lastThirtyDays: l10n.rangeThirtyDays
        }
    }
}
```

- [ ] **Step 4: Ekran**

`NozirKit/Sources/NozirAppFeature/Screens/AppUsageView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirInsights
import NozirL10n

/// P08 as Android `AppUsageScreen`: a range, the total, a bar of shares with
/// its legend and per-app rows; or the same figures as a table.
struct AppUsageView: View {
    @State private var model: AppUsageModel
    @Environment(\.l10n) private var l10n

    init(model: AppUsageModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Picker(l10n.appUsageTitle, selection: $model.range) {
                    ForEach(UsageRange.allCases, id: \.self) { range in
                        Text(AppUsageModel.rangeTitle(range, l10n)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                content
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenAppUsageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: model.range) { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        case .failed(let message):
            NozirErrorState(
                title: l10n.stateErrorTitle,
                message: message.text(l10n),
                retryTitle: l10n.stateActionRetry
            ) {
                Task { await model.load() }
            }
        case .loaded:
            if model.isEmpty {
                NozirEmptyState(title: l10n.appUsageEmptyTitle, message: l10n.appUsageEmptyBody)
            } else {
                Text(l10n.appUsageTotal(Durations.short(model.total, l10n))).nozirText(.titleLarge)
                if model.showsTable {
                    table
                } else {
                    chart
                }
                NozirButton(model.showsTable ? l10n.appUsageActionChart : l10n.appUsageActionTable, variant: .ghost) {
                    model.showsTable.toggle()
                }
            }
        }
    }

    private func color(_ entry: AppUsageEntry, at index: Int) -> Color {
        AppUsageModel.colorIndex(of: entry, at: index).map { NozirColor.chartSeries[$0] } ?? NozirColor.chartOther
    }

    private var chart: some View {
        let entries = model.entries
        let shares = ChartMath.shares(entries.map(\.minutes))
        let fractions = ChartMath.fractions(entries.map(\.minutes))
        return VStack(alignment: .leading, spacing: NozirSpacing.large) {
            NozirCard {
                NozirStackedBar(segments: entries.enumerated().map { index, entry in
                    NozirChartSegment(id: index, fraction: shares[index], color: color(entry, at: index))
                })
                .accessibilityElement()
                .accessibilityLabel(AppUsageModel.chartDescription(entries, l10n))
                NozirLegend(items: entries.enumerated().map { index, entry in
                    NozirLegendItem(
                        id: index,
                        color: color(entry, at: index),
                        label: AppUsageModel.name(of: entry, l10n),
                        valueLabel: l10n.appUsageSharePercent(AppUsageFolding.sharePercent(entry.minutes, of: model.total))
                    )
                })
            }
            NozirCard {
                ForEach(Array(entries.enumerated()), id: \.element) { index, entry in
                    VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
                        HStack {
                            Text(AppUsageModel.name(of: entry, l10n)).nozirText(.body)
                            Spacer()
                            Text(Durations.short(entry.minutes, l10n)).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                        NozirProgressBar(fraction: fractions[index], color: color(entry, at: index))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var table: some View {
        NozirCard {
            Grid(alignment: .leading, horizontalSpacing: NozirSpacing.medium, verticalSpacing: NozirSpacing.small) {
                GridRow {
                    Text(l10n.appUsageTableApp).nozirText(.label, color: NozirColor.textSecondary)
                    Text(l10n.appUsageTableTime).nozirText(.label, color: NozirColor.textSecondary)
                        .gridColumnAlignment(.trailing)
                    Text(l10n.appUsageTableShare).nozirText(.label, color: NozirColor.textSecondary)
                        .gridColumnAlignment(.trailing)
                }
                Divider()
                ForEach(model.entries, id: \.self) { entry in
                    GridRow {
                        Text(AppUsageModel.name(of: entry, l10n)).nozirText(.body)
                        Text(Durations.short(entry.minutes, l10n)).nozirText(.body)
                        Text(l10n.appUsageSharePercent(AppUsageFolding.sharePercent(entry.minutes, of: model.total))).nozirText(.body)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`; `aLateAnswerForAnOldRangeIsIgnored` osilib qolmaydi (osilsa — `GatedInsights` continuation'lari tartibini tekshiring, testni o'chirmang).

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/AppUsageModel.swift NozirKit/Sources/NozirAppFeature/Screens/AppUsageView.swift NozirKit/Tests/NozirAppFeatureTests/AppUsageModelTests.swift
```

Xabar: `p08: where the time went, four apps and the rest`

---
### Task 10: Statistika tabi va ulash — `StatisticsModel`, uch tab, navigatsiya

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Insights/StatisticsModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/StatisticsView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift:74-87`
- Delete: `NozirKit/Sources/NozirAppFeature/Screens/HomePlaceholderView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/StatisticsModelTests.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`InsightsApi`, `InsightsService`), Task 5 (`AppModel.emergencyNumber`), Task 6 (`HomeModel`, `HomeView`, `FakeInsights`), Task 7 (`DailySummaryModel`, `DailySummaryView`), Task 8 (`WeeklyReportModel`, `WeeklyReportView`, `WeeklySwitcher`), Task 9 (`AppUsageModel`, `AppUsageView`), 2a (`SignedInModel`, `ChildDetailsView`, `FamilyStore`).
- Produces:
  - `@MainActor @Observable final class StatisticsModel { var selectedChildId: UUID?; family: FamilyStore; init(family:); childId: UUID?; showsSwitcher: Bool; switcherChildren: [NozirSwitcherChild] }`
  - `SignedInModel.Tab`: `home, statistics, profile`; `SignedInModel.init(family:insights:language:appearance:localeSync:emergencyNumber:signOut:)`; `statistics: StatisticsModel`; `homeRefresh: Int` (bola qo'shish oqimi yopilganda oshadi); `currentEmergencyNumber: String?`; `makeHomeModel()`, `makeDailySummaryModel(childId:childName:)`, `makeWeeklyModel(childId:)`, `makeAppUsageModel(childId:)`.
  - `struct StatisticsView: View { init(statistics: StatisticsModel, makeWeekly: @escaping (UUID) -> WeeklyReportModel, onAddChild: @escaping () -> Void, onOpenApps: @escaping (UUID) -> Void) }`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/StatisticsModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
@testable import NozirAppFeature

@MainActor
private func family(_ children: [Child]) async -> FamilyStore {
    var script = FakeFamily.Script()
    script.children = [.success(children)]
    let store = FamilyStore(service: FakeFamily(script))
    try? await store.refresh()
    return store
}

@MainActor
@Suite struct StatisticsModelTests {
    @Test func theFirstChildByDefault() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let model = StatisticsModel(family: await family([ali, vali]))

        #expect(model.childId == ali.id)
        #expect(model.showsSwitcher)
        #expect(model.switcherChildren.map(\.name) == ["Ali", "Vali"])
    }

    @Test func aChoiceIsKept() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let model = StatisticsModel(family: await family([ali, vali]))

        model.selectedChildId = vali.id

        #expect(model.childId == vali.id)
    }

    // Review Focus 4.
    @Test func aRemovedChildFallsBackToTheFirst() async {
        let ali = makeChild("Ali"), vali = makeChild("Vali")
        let store = await family([ali, vali])
        let model = StatisticsModel(family: store)
        model.selectedChildId = vali.id

        store.remove(vali.id)

        #expect(model.childId == ali.id)
        #expect(!model.showsSwitcher)
    }

    @Test func noChildrenNoChild() async {
        let model = StatisticsModel(family: await family([]))

        #expect(model.childId == nil)
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift` — `setup` ni yangi `init` ga moslang (`insights` va `emergencyNumber` qo'shiladi):

```swift
@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales()
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        insights: FakeInsights(),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        emergencyNumber: { "112" },
        signOut: {}
    )
    return (model, fake)
}
```

va suite oxiriga:

```swift
    @Test func closingTheAddFlowReloadsHome() {
        let (model, _) = setup(FakeFamily.Script())
        let before = model.homeRefresh

        model.presentAddChild()
        model.finishAddChild()

        #expect(model.homeRefresh == before + 1)
    }

    @Test func screensShareTheFamilyAndTheEmergencyNumber() {
        let (model, _) = setup(FakeFamily.Script())

        #expect(model.statistics.family === model.family)
        #expect(model.makeHomeModel().family === model.family)
        #expect(model.currentEmergencyNumber == "112")
    }
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'StatisticsModel' in scope`, `extra arguments at positions … in call`.

- [ ] **Step 3: `StatisticsModel`**

`NozirKit/Sources/NozirAppFeature/Insights/StatisticsModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily

/// Which child the Statistics tab shows (spec decision: a switcher above P07,
/// the choice carried on to P08). A child removed in Profile falls back to the
/// first; with no children there is nothing to show.
@MainActor
@Observable
final class StatisticsModel {
    var selectedChildId: UUID?
    let family: FamilyStore

    init(family: FamilyStore) {
        self.family = family
    }

    var childId: UUID? {
        if let selectedChildId, family.child(selectedChildId) != nil { return selectedChildId }
        return family.children.first?.id
    }

    var showsSwitcher: Bool {
        family.children.count > 1
    }

    var switcherChildren: [NozirSwitcherChild] {
        family.children.enumerated().map { position, child in
            NozirSwitcherChild(id: child.id, name: child.displayName, tone: .forKey(child.avatarKey, position: position))
        }
    }
}
```

- [ ] **Step 4: `SignedInModel`**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift` — o'zgarishlar:

1. Importlarga `import NozirInsights`.
2. `Tab`:

```swift
    public enum Tab: Hashable, Sendable {
        case home, statistics, profile
    }
```

3. `family` dan keyin yangi xossalar va `init`:

```swift
    public let family: FamilyStore
    let statistics: StatisticsModel
    /// Goes up when the add-a-child flow closes, so Home asks again.
    private(set) var homeRefresh = 0

    private let insights: any InsightsService
    private let language: LanguageStore
    private let appearance: AppearanceStore
    private let localeSync: LocaleSync
    private let emergencyNumber: @MainActor () -> String?
    private let signOutAction: @MainActor () async -> Void
    @ObservationIgnored private var hasStarted = false

    init(
        family: FamilyStore,
        insights: any InsightsService,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        emergencyNumber: @escaping @MainActor () -> String?,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.insights = insights
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        self.emergencyNumber = emergencyNumber
        signOutAction = signOut
        statistics = StatisticsModel(family: family)
    }
```

4. `finishAddChild`:

```swift
    public func finishAddChild() {
        isAddingChild = false
        tab = .home
        homeRefresh += 1
    }
```

5. Fabrikalar (`makeDetailsModel` dan keyin):

```swift
    var currentEmergencyNumber: String? {
        emergencyNumber()
    }

    func makeHomeModel() -> HomeModel {
        HomeModel(insights: insights, family: family)
    }

    func makeDailySummaryModel(childId: UUID, childName: String) -> DailySummaryModel {
        DailySummaryModel(childId: childId, childName: childName, insights: insights)
    }

    func makeWeeklyModel(childId: UUID) -> WeeklyReportModel {
        WeeklyReportModel(childId: childId, insights: insights, today: { LocalDate(Date(), in: .current) })
    }

    func makeAppUsageModel(childId: UUID) -> AppUsageModel {
        AppUsageModel(childId: childId, insights: insights)
    }
```

- [ ] **Step 5: `StatisticsView`**

`NozirKit/Sources/NozirAppFeature/Screens/StatisticsView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// The Statistics tab's root: P07 for the chosen child, with the switcher when
/// there is more than one. One weekly model lives for the tab; choosing another
/// child tells it rather than building a new one.
struct StatisticsView: View {
    private let statistics: StatisticsModel
    private let makeWeekly: (UUID) -> WeeklyReportModel
    private let onAddChild: () -> Void
    private let onOpenApps: (UUID) -> Void
    @State private var weekly: WeeklyReportModel?
    @Environment(\.l10n) private var l10n

    init(
        statistics: StatisticsModel,
        makeWeekly: @escaping (UUID) -> WeeklyReportModel,
        onAddChild: @escaping () -> Void,
        onOpenApps: @escaping (UUID) -> Void
    ) {
        self.statistics = statistics
        self.makeWeekly = makeWeekly
        self.onAddChild = onAddChild
        self.onOpenApps = onOpenApps
    }

    var body: some View {
        Group {
            if statistics.childId != nil, let weekly {
                WeeklyReportView(model: weekly, switcher: switcher, onOpenApps: onOpenApps)
            } else if statistics.family.hasLoaded, statistics.childId == nil {
                ScrollView {
                    NozirEmptyState(
                        title: l10n.homeEmptyTitle,
                        message: l10n.homeEmptyBody,
                        actionTitle: l10n.homeEmptyAction,
                        action: onAddChild
                    )
                    .padding(NozirSpacing.medium)
                }
                .background(NozirColor.background.ignoresSafeArea())
                .navigationTitle(l10n.tabStatistics)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(NozirColor.background.ignoresSafeArea())
            }
        }
        .task(id: statistics.childId) {
            guard let id = statistics.childId else { return }
            if let weekly {
                await weekly.setChild(id)
            } else {
                weekly = makeWeekly(id)
            }
        }
    }

    private var switcher: WeeklySwitcher? {
        guard statistics.showsSwitcher else { return nil }
        return WeeklySwitcher(
            children: statistics.switcherChildren,
            selection: Binding(
                get: { statistics.childId },
                set: { statistics.selectedChildId = $0 }
            )
        )
    }
}
```

- [ ] **Step 6: `SignedInView` — uch tab**

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift` — butun fayl:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// The signed-in app: Home, Statistics and Profile. Location arrives with its
/// slice.
struct SignedInView: View {
    enum HomeStep: Hashable {
        case summary(UUID, String)
        case weekly(UUID)
        case apps(UUID)
        case details(Child)
    }

    enum StatisticsStep: Hashable {
        case apps(UUID)
    }

    enum ProfileStep: Hashable {
        case child(Child)
        case pairing(Child)
    }

    @State private var model: SignedInModel
    @State private var homePath: [HomeStep] = []
    @State private var statisticsPath: [StatisticsStep] = []
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

            NavigationStack(path: $profilePath) {
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0)) },
                    onPair: { profilePath.append(.pairing($0)) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    switch step {
                    case .child(let child):
                        ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { profilePath.removeAll() })
                    case .pairing(let child):
                        PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
                    }
                }
            }
            .tabItem { Label(l10n.tabProfile, systemImage: "person.crop.circle") }
            .tag(SignedInModel.Tab.profile)
        }
        .tint(NozirColor.primary)
        .fullScreenCover(isPresented: $model.isAddingChild) {
            AddChildFlow(model: model, onClose: {
                homePath.removeAll()
                statisticsPath.removeAll()
                profilePath.removeAll()
                model.finishAddChild()
            })
                // Said again for the cover, so it cannot fall back to the defaults.
                .environment(\.l10n, l10n)
                .environment(\.locale, locale)
        }
        .task(id: scenePhase == .active) { if scenePhase == .active { await model.start() } }
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
            ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { homePath.removeAll() })
        }
    }
}
```

Keyin eski joy egasini o'chiring:

```bash
git rm NozirKit/Sources/NozirAppFeature/Screens/HomePlaceholderView.swift
```

(`ios_home_placeholder_*` matnlari `strings.xml` da qoladi — chetlanish E5.)

- [ ] **Step 7: `AppEnvironment`**

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — importlarga `import NozirInsights`, va `makeSignedInModel()`:

```swift
    func makeSignedInModel() -> SignedInModel {
        let api = FamilyApi(client: authorised)
        return SignedInModel(
            family: FamilyStore(service: api),
            insights: InsightsApi(client: authorised),
            language: language,
            appearance: appearance,
            localeSync: LocaleSync(store: language, send: { _ = try await api.updateLocale($0) }),
            emergencyNumber: { [appModel] in appModel.emergencyNumber },
            signOut: { [appModel] in
                UserDefaults.standard.removeObject(forKey: LocaleSync.unsentKey)
                await appModel.signOut()
            }
        )
    }
```

- [ ] **Step 8: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`, so'ng watcher `app` (ilova build).
Expected: `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`; `grep -rn "HomePlaceholderView" NozirKit Nozir` — hech narsa.

- [ ] **Step 9: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Insights/StatisticsModel.swift NozirKit/Sources/NozirAppFeature/Screens/StatisticsView.swift NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Tests/NozirAppFeatureTests/StatisticsModelTests.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
```

(`HomePlaceholderView.swift` o'chirilishi `git rm` bilan allaqachon indeksda.)

Xabar: `app: home, statistics and profile, each screen reachable`

---
### Task 11: Oxirgi tekshiruv — butun to'plam, CI va simulyatorda E2E

**Files:** (kod o'zgarmaydi; topilgan xatolar alohida TDD sikli bilan tuzatiladi)

- [ ] **Step 1: Butun to'plam**

Run: `python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check && ./scripts/test.sh`, keyin watcher `all` va `app`.
Expected: Python testlari OK, `up to date`, `** TEST SUCCEEDED **` (yangi `NozirInsightsTests` ham ichida), `** BUILD SUCCEEDED **`.

- [ ] **Step 2: E2E (foydalanuvchi, simulyator + haqiqiy bola telefoni, haqiqiy backend)**

Har bir bandga "ha" yoki kuzatilgan holat yoziladi:

1. Bitta bolali oila: Home — avatar, "{Ism}, {yosh} yosh", "Bugun · {kun oy}", holat belgisi; xulosa jumlasi bo'lsa karta va "Batafsil oʻqish"; "Ekran vaqti" va "{limit} limitdan"; "Joylashuv" (joy yoki "Nomaʼlum", "{HH:mm} dan beri").
2. Bola telefonida internet o'chiriladi (yoki `deviceOnline=false` bo'lguncha kutiladi) → Home'da joy o'rnida "Telefon oflayn".
3. Ikkinchi bola qo'shiladi (Home'dagi "+ Qoʻshish" orqali) → yopilgach Home o'zi yangilanadi; "Oilam", "Hammasi" + avatarlar; avatar bosilsa faqat o'sha bola, yana bosilsa hammasi; boshqa tabga o'tib qaytilganda filtr "Hammasi".
4. E'tibor talab qiladigan bola bo'lsa (backend `needsAttention`) — u birinchi, sariq karta; qolganlari sokin qator; pastda "Bolalar bir-biri bilan taqqoslanmaydi" matni. Bo'lmasa — oddiy kartalar va "Oila boʻyicha" jumlasi (bo'lsa).
5. Karta → P06: "{Ism} bugun", hafta kuni va sana, paragraflar, "Tavsiya", (bo'lsa) "Bu hafta soʻrab koʻring", 🔒 eslatma. Xulosa yo'q bola uchun "Bugungi xulosa hali tayyor emas". ✎ → bola tafsilotlari (2a).
6. P06 → "Haftalik hisobot" → P07: "Bu hafta", sanalar oralig'i, 7 ustun (kelajak kunlar raqamsiz), cho'qqi ajratilgan, "Eng koʻp: …"; chapga surish/‹ → "Oʻtgan hafta", keyin "Haftalik hisobot"; eng eski hafta 52 hafta oldin, › joriy haftada o'chiq.
7. P07 → "Ilovalar boʻyicha vaqt" → P08: "Bugun/7 kun/30 kun" almashadi va qayta so'raladi; "Jami …", ulushlar chizig'i, legend (foizlar), qatorlar; "Boshqalar" oxirida; "Jadval koʻrinishi" ↔ "Grafik koʻrinishi"; tez-tez oraliq almashtirilganda oxirgi tanlangan oraliq ma'lumoti qoladi.
8. Statistika tabi: 2+ bolada tepada tanlagich, sukut — birinchi bola; ikkinchi bola tanlansa grafik shu bolaniki; P08 ga o'tilsa ham shu bola. Profil'da tanlangan bola o'chirilsa Statistika birinchi bolaga qaytadi. Bolasiz oilada Statistika bo'sh holat va "Bola qoʻshish".
9. SOS: bola telefonidan SOS yuboriladi → Home'ga qaytilganda (yoki ilova faollashganda) qizil banner "{Ism} SOS yubordi", "N daqiqa oldin · hali javob berilmadi" (ekranda 30 s+ turib vaqt o'zgarishi kuzatiladi) → "Ochish" → oyna: "{Ism}ga qoʻngʻiroq qilish" (raqam bor bo'lsa faol, yo'q bo'lsa o'chiq va "Bola telefon raqami hali maʼlum emas."), "112 ga qoʻngʻiroq". Simulyatorda `tel:` ochilmasa "qo'ng'iroq ilovasi ochilmadi" matni chiqadi.
10. Internet o'chiq holda ilova ochilsa: Home oldin yuklangan bo'lsa "Oflayn — oxirgi maʼlum holat koʻrsatilmoqda", yuklanmagan bo'lsa xato va "Qayta urinish".
11. Til (uz → ru → en) va tema (yorug'/tungi): P05, P06, P07, P08, SOS oynasi matnlari va ranglari to'g'ri; sana va oy nomlari tanlangan tilda.
12. Uch tilda va ikki temada P05 (1 va 2+ bola), P06, P07, P08, SOS oynasi skrinshotlari (Cmd+S).

- [ ] **Step 3: Natijani yozish**

Ledger'ga (`.superpowers/sdd/<plan>/progress.md`) E2E natijalari va kechiktirilgan kichik masalalar yoziladi. Push foydalanuvchida; keyin `superpowers:finishing-a-development-branch`.
