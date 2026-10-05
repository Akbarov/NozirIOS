# Nozir iOS — 2b: Home va hisobotlar

- **Sana:** 2026-10-05
- **Holat:** dizayn, foydalanuvchi ko'rib chiqishini kutmoqda
- **Oldingi spec'lar:** `2026-10-03-nozir-ios-foundation-design.md`, `2026-10-03-nozir-ios-family-onboarding-design.md` (2a)
- **Manba:** Android `NozirParent` (`feature/home`, `feature/summary`, `feature/weekly`, `feature/apps`,
  `core/ui/*Duration*`, `core/domain/usage/FoldedToTopApps.kt`, `ChartFractions.kt`), backend
  `insights/internal/web/InsightDtos.kt`, `usage/internal/web/UsageDtos.kt`, `SummaryQueryService.kt`
  (backend Kotlin — haqiqat manbai; openapi bilan farqlar 8-bo'limda).

---

## 1. Maqsad

Ota-ona ilovani ochganda bir qarashda bolalari bugun qanday ekanini ko'radi (P05), bolaning kunlik AI
xulosasini o'qiydi (P06), haftalik ekran vaqtini grafikda ko'radi (P07) va vaqt qaysi ilovalarga
ketganini biladi (P08). Faol SOS bo'lsa, u har doim ko'rinadi va bir bosishda bolaga qo'ng'iroq qilish
mumkin.

Muvaffaqiyat mezonlari:

1. Kirgandan keyin Home haqiqiy backend ma'lumoti bilan 1 va 2+ bolali oilada to'g'ri ko'rinadi.
2. Bola kartasidan P06 → P07 → P08 zanjiri o'sha bola uchun ishlaydi; Statistika tabida bola tanlagich
   2+ bolada boshqa bolaning statistikasini ko'rsatadi.
3. Faol SOS bannerini bosish oynani ochadi va bolaga (raqami bo'lsa) yoki favqulodda raqamga qo'ng'iroq
   qilish mumkin.
4. Uch tilda va ikki temada barcha ekranlar to'g'ri; barcha mantiq unit testlar bilan qoplangan; CI yashil.

## 2. Qabul qilingan qarorlar

| Mavzu | Qaror |
|---|---|
| P05 dagi qurilmagan havolalar | Faol SOS banneri ko'rinadi va SOS oynasini ochadi; vaqt so'rovlari (P17), himoya qatori (P18), qo'ng'iroqcha (P16) o'z bo'laklarigacha yashirin |
| Statistika uchun bola tanlash | P07 tepasida bola tanlagich (2+ bola bo'lsa); tanlangan bola P08 ga ham o'tadi (Android'dan farq — u yerda tab doim birinchi bolani ko'rsatadi) |
| Tarmoq kodi | Yangi `NozirInsights` moduli (A) |
| Grafiklar | Oddiy SwiftUI, mantiq toza funksiyalarda (A); Swift Charts ishlatilmaydi |
| Kesh | Faqat xotirada; Home oxirgi javobni saqlaydi, P07 ko'rilgan haftalarni saqlaydi |
| Yangilash | Har ekran ochilganda (Android kabi); Home ilova qayta faollashganda ham |

## 3. Qamrov

**Kiradi:** `NozirInsights` (home, daily/weekly summary, usage daily/apps), tab paneliga Statistika tabi,
P05 (1 bola va 2+ bola ko'rinishlari, bo'sh holat, oflayn holat), SOS oynasi, P06, P07 (53 hafta
varaqlash, ustunli grafik, kuzatuvlar), P08 (oraliqlar, ulushlar chizig'i, jadval), bola tanlagich.

**Kirmaydi:** P15 to'liq SOS ekrani va SOS'ni "ko'rdim" deb belgilash, P16–P18, push va deep link'lar
(P16a), disk kesh, App Store baho so'rovi, `pendingChallengeApprovals`, `GET /summaries` ro'yxati.

## 4. Arxitektura

### 4.1 Modullar

| Modul | Vazifasi | Bog'liqligi |
|---|---|---|
| `NozirInsights` (yangi) | `InsightsApi` (5 endpoint), DTO'lar, `InsightsService` protokoli, `LocalDate` (yil-oy-kun, `YYYY-MM-DD`) | Networking |
| `NozirDesignSystem` (kengayadi) | `NozirColumnChart`, `NozirStackedBar` + legend, `NozirProgressBar`, `NozirSegmentedControl` (yoki tizim `Picker(.segmented)`), holat komponentlari (skelet, bo'sh, xato + qayta urinish, oflayn belgi) | — |
| `NozirAppFeature` (kengayadi) | `HomeModel`, `SosAlertModel`, `DailySummaryModel`, `WeeklyReportModel`, `AppUsageModel`, `StatisticsModel` (tanlangan bola), `ChartMath`, `AppUsageFolding`, ekranlar | hammasi |

### 4.2 Navigatsiya

- Tablar: **Home**, **Statistika**, **Profil** (Joylashuv 3-sub-loyihada).
- Home stack: P05 → P06 (bola tanlangan) → P07 → P08. P06 dagi ✎ → bola tafsilotlari (2a).
- Statistika stack: P07 (ildiz) → P08.
- P05 dagi "Qo'shish" / bo'sh holatdagi "Bola qo'shish" → 2a dagi bola qo'shish oqimi.
- SOS banneri → SOS oynasi (sheet).

### 4.3 Sana va vaqt

- `LocalDate` — server bilan almashinuv uchun `YYYY-MM-DD`, Calendar'siz taqqoslanadigan qiymat.
- Hafta — ISO-8601, Dushanbadan; chegaralar telefon kalendarida hisoblanadi (Android kabi).
- "N daqiqa oldin" — Android `elapsed_*` qoidalari; SOS oynasi va banneri har 30 s yangilanadi.

## 5. Ekranlar va ma'lumot oqimi

### 5.1 P05 Home

- Ochilganda va ilova faollashganda: `GET /v1/parent/home` va `FamilyStore.refresh()` (bola yoshi va
  telefoni shu yerdan; home javobida yo'q).
- **0 bola:** bo'sh holat (`home_empty_*`) va "Bola qo'shish".
- **1 bola:** sarlavha (avatar, "{Ism}, {yosh} yosh", "Bugun · {kun oy}", holat belgisi); AI xulosa kartasi
  (`summarySentence` bo'lsa) → P06; "Ekran vaqti" (`usedMinutes`, "{limit} limitdan"); "Joylashuv"
  (`placeLabel` yoki "Noma'lum", "{HH:mm} dan beri"; telefon oflayn bo'lsa "Telefon oflayn").
- **2+ bola:** "Oilam" sarlavhasi; avatar filtri ("Hammasi" doim ko'rinadi, "+ Qo'shish");
  kartalar `needsAttention` bo'yicha barqaror saralanadi (e'tibor talab qiladiganlar oldinda, qolgani
  server tartibida); e'tibor talab qiladigan karta, sokin qator yoki oddiy karta — Android
  `MultiChildHome` qoidalari; har karta → shu bola uchun P06. Pastda e'tibor bo'lsa
  `home_not_compared_note`, bo'lmasa `familySummary` kartasi. Filtr har ochilishda "Hammasi" ga qaytadi.
- **Joy matni:** "{qisqa vaqt} · {joy}", joy = oflayn bo'lsa "Telefon oflayn", aks holda `placeLabel`;
  ikkalasi bo'lmasa faqat vaqt. Eski joy hech qachon hozirgidek ko'rsatilmaydi.
- **SOS banneri** (`activeSos`, yo'q bo'lsa eskirgan `activeSosId`): "{ism} SOS yubordi" /
  "SOS signali", "{n daqiqa oldin} · hali javob berilmadi", "Ochish" → SOS oynasi.

### 5.2 SOS oynasi

- Sarlavha va vaqt banner bilan bir xil.
- "{ism}ga qo'ng'iroq qilish" (`sos_action_call_child`) — `tel:` bola raqami bilan (`FamilyStore`);
  raqam yo'q bo'lsa tugma o'chiq va `sos_call_child_unavailable`.
- "{raqam} ga qo'ng'iroq" (`sos_action_call_emergency`) — server konfiguratsiyasidagi
  `emergencyNumber` bor bo'lsa.
- `tel:` ochilmasa — poydevordagi "qo'ng'iroq ilovasi ochilmadi" matni.

### 5.3 P06 Kunlik xulosa

- `GET .../summaries/daily` (sana berilmasa eng so'nggisi; Home'dan sanasiz) va parallel
  `GET .../summaries/weekly?weekStart=<o'sha kunning Dushanbasi>` — faqat `conversationQuestion` uchun;
  uning xatosi jim yutiladi.
- Sarlavha "{Ism} bugun", ostida `periodEnd` hafta kuni va sanasi; ✎ → bola tafsilotlari.
- Paragraflar, "Tavsiya", "Bu hafta so'rab ko'ring", 🔒 "Bu xulosa foydalanish statistikasidan
  tuzilgan. Yozishmalar o'qilmagan." eslatmasi, pastda "Haftalik hisobot" → P07 (shu bola).
- 404 → "Bugungi xulosa hali tayyor emas" (bo'sh holat, kechirimsiz); 403 `SUBSCRIPTION_REQUIRED` →
  `data_error_subscription_required`; boshqa xato → xato va "Qayta urinish".

### 5.4 P07 Haftalik hisobot

- Statistika tabining ildizi; P06 dan ham ochiladi (o'sha bola uchun, bola tanlagichsiz).
- Tab'da: 2+ bola bo'lsa tepada bola tanlagich (avatarlar); sukut — birinchi bola; tanlov P08 ga o'tadi.
- 53 hafta (joriy + 52 oldingi), joriy hafta oxirgi sahifa; ‹ › tugmalari va surish.
- Sarlavha: "Bu hafta" / "O'tgan hafta" / "Haftalik hisobot" va sanalar oralig'i.
- Har sahifa: `GET .../usage/daily?from=Du&to=Ya` va `GET .../summaries/weekly?weekStart=Du`;
  oldingi hafta oldindan yuklanadi; sahifalar xotirada (Dushanba bo'yicha), bir vaqtda bitta so'rov.
- Grafik: 7 ustun (Du–Ya), qiymat yorlig'i (qisqa vaqt; kelajak kunlar bo'sh), nol asosli balandlik
  `qiymat / hafta cho'qqisi`, birinchi teng cho'qqi ajratiladi, hammasi 0 bo'lsa cho'qqi yo'q;
  "Eng ko'p: {kun} — {uzun vaqt}" (cho'qqi 0 bo'lsa yashirin). Faqat `usedMinutes` chiziladi.
- "Kuzatuvlar": haftalik xulosaning har paragrafi — bitta qator, nuqta rangi xulosaning `riskLevel`idan.
  Haftalik xulosa xatosi (403/404 ham) jim: grafik bor, kuzatuv yo'q.
- "Ilovalar bo'yicha vaqt" → P08.
- Usage xatosi → xato va "Qayta urinish"; ma'lumot ham, kuzatuv ham yo'q → `weekly_empty_*`.

### 5.5 P08 Ilovalar

- "Bugun / 7 kun / 30 kun" (`TODAY`, `LAST_7_DAYS`, `LAST_30_DAYS`), sukut — Bugun.
- `GET .../usage/apps?range=…`; oraliq almashganda qayta so'raladi.
- Grafik ko'rinish: "Jami {vaqt}", ulushlar chizig'i (har ilova jami ichidagi ulushi) va legend; ilovalar
  qatorlari (nom, `daqiqa / eng katta` progress, qisqa vaqt).
- Jadval ko'rinish: Ilova / Vaqt / Ulushi (`daqiqa × 100 / jami`, butun foiz, jami 0 bo'lsa 0%).
- Top-4 va "Boshqalar": `nozir.other_apps` qatori(lar)i birlashtiriladi, doim oxirida, nomi
  `app_usage_other`; ranglar — 4 ta seriya rangi va kulrang "boshqa".
- Ilova nomi: server nomi package id ga teng bo'lmasa o'shasi; aks holda package id dan tozalangan nom
  (Android `FriendlyAppName` qoidasi).
- Bo'sh → `app_usage_empty_*`; xato → xato va "Qayta urinish".

## 6. Xatolar va holatlar

- P05: kesh yo'q + xato → to'liq xato holati va "Qayta urinish"; kesh bor + tarmoq yo'q/vaqt tugadi →
  `state_offline_notice` belgisi; kesh bor + boshqa xato → ro'yxat ustida inline matn.
- Barcha matnlar `L10n` dan; server `message` ko'rsatilmaydi (poydevor qoidasi).
- Noma'lum enum qiymatlari ro'yxatni buzmaydi: `statusLevel` → GOOD, `riskLevel` → GOOD,
  `ageGroup` → nil, noma'lum `range` → TODAY.

## 7. Testlash

Swift Testing, `FakeTransport`, soxta `InsightsService`, soat in'ektsiya qilinadi.

| Qism | Testlar |
|---|---|
| `InsightsApi` | Har endpoint: yo'l, so'rov parametrlari (`date`, `weekStart`, `from`/`to`, `range`), backend Kotlin DTO fixture'larini dekodlash, noma'lum enum'lar, `activeSosId` zaxirasi |
| `LocalDate` / hafta | `YYYY-MM-DD` ↔ qiymat, Dushanba hisoblash (yakshanba, oy/yil chegarasi), 53 hafta ro'yxati |
| `ChartMath` | Nol asosli ulushlar, birinchi teng cho'qqi, hammasi 0, ulushlar yig'indisi |
| `AppUsageFolding` | Top-4 + "Boshqalar", mavjud `nozir.other_apps` birlashtirish, foiz yaxlitlash, nom tozalash |
| `HomeModel` | 0/1/2+ bola, saralash barqarorligi, filtr, joy matni qoidasi, oflayn/inline/to'liq xato, SOS |
| `SosAlertModel` | Vaqt matni (hozirgina/daqiqa/soat), raqamli/raqamsiz bola, favqulodda raqam |
| `DailySummaryModel` | Muvaffaqiyat, 404, 403, haftalik xatosi yutilishi |
| `WeeklyReportModel` | Hafta chegaralari, kesh, oldindan yuklash, takroriy so'rov yo'qligi, bola almashganda tozalanish, haftalik xulosa xatosi jim |
| `AppUsageModel` | Oraliq almashuvi, jadval/grafik almashuvi, bo'sh holat |
| `StatisticsModel` | Sukut birinchi bola, tanlov saqlanishi, bola o'chirilganda birinchiga qaytish |

View'lar — simulyatorda qo'lda (uch til, ikki tema, 1 va 2+ bola).

## 8. Ma'lum xavflar

1. **Hafta chegarasi** telefon kalendarida hisoblanadi, server esa oila vaqt zonasida — telefon boshqa
   zonada bo'lsa yakshanba/dushanba kechasi bir kunlik siljish mumkin (Android ham shunday).
2. **Bugungi kunlik xulosa hech qachon yo'q** (server tugagan kunlarni yozadi); "{Ism} bugun" sarlavhasi
   Android'dan olingan yorliq, xulosa esa so'nggi tugagan kun haqida.
3. **openapi va backend farqlari:** `ActiveSos.childName` openapi'da majburiy, Kotlin'da ixtiyoriy;
   `usage/daily` da `from`/`to` openapi'da majburiy, Kotlin'da ixtiyoriy — iOS doim yuboradi;
   holat sxemasi nomi `StatusLevel` / `RiskLevel` (qiymatlar bir xil). iOS Kotlin'ga moslanadi.
4. **Obuna cheklovlari hozir o'chiq** (`nozir.billing.enforce-entitlements = false`); 403 yo'llari
   faqat testlarda tekshiriladi.
5. **SOS'ni "ko'rdim" deb belgilash yo'q** — banner P15 qurilmaguncha SOS hal bo'lmaguncha turadi.
