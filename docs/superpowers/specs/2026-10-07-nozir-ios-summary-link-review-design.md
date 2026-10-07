# Nozir iOS — P16a: Xulosa havolasi va baholash taklifi (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi · Manba: Android `feature/summarylink` (SUMMARY_LINK, "P16a"), `core/platform/play` (InAppReview, ReviewTiming, ReviewGate) · Branch: `protection` (P18 + P16 bilan birga)

## 1. Maqsad va qamrov

1. Bildirishnomadagi xulosa havolasi (`nozir://summary/{summaryId}`) aynan o'sha kunning yoki haftaning xulosasini ochadi (hozir P16 bolaning oxirgi xulosasini ochadi — N11).
2. Ota-ona ilovadan qoniqqan paytda (kunlik xulosa ko'rinib turganda) tizimning baholash oynasi bir marta taklif qilinadi.

**Kiradi:** `summary(id:)` API, `InsightSummary.period`, oraliq ekran (`HomeStep.summaryLink`), kunlik/haftalik ekranlarni aniq sana bilan ochish, P16 xulosa qatorlarini shu ekranga yo'naltirish, baholash taklifi.

**Kirmaydi (foydalanuvchi qarori):** `nozir` URL sxemasini ro'yxatdan o'tkazish va tashqi havolalarni ochish (push bilan birga keyinroq), universal links.

## 2. Qarorlar (foydalanuvchi)

| # | Savol | Qaror |
|---|---|---|
| D1 | Tashqi havolalar | Yo'q — faqat ilova ichidan (P16 qatorlari) |
| D2 | Xulosa havolasi | Aynan o'sha kun/hafta, oraliq ekran orqali (Android kabi); P16 xulosa qatorlari ham shu yo'ldan |
| D3 | Baholash | Android kabi: P06 da xulosa yuklanganda, birinchi ko'rishdan ≥3 kun o'tgach, o'rnatish uchun bir marta |

## 3. Backend shartnomasi (tekshirilgan, o'zgarmaydi)

- `GET /v1/parent/summaries/{summaryId}` → `InsightSummaryResponse`: `summaryId`, `childId`, `period` (`DAILY|WEEKLY`), `periodStart`, `periodEnd` (LocalDate), `paragraphs`, `recommendation?`, `conversationQuestion?`, `riskLevel`, `source`, `generatedAt`, `contentNotice`. Oila doirasida; topilmasa yoki boshqa oilaniki → 404. O'qildi deb belgilaydi. Bepul tarifda eski xulosa uchun tarif xatosi bo'lishi mumkin (aniq kod plan'da tekshiriladi).
- Baholash uchun server ishtiroki yo'q.

## 4. Arxitektura

### 4.1 NozirInsights
- `InsightSummary.period: SummaryPeriod?` (`daily`, `weekly`; noma'lum/yo'q → `nil`) — mavjud dekodlash buzilmaydi.
- `InsightsService.summary(id: UUID) async throws -> InsightSummary` (+ `InsightsApi`, test fake'lar).

### 4.2 NozirAppFeature
- `SummaryLinkModel` (`@MainActor @Observable`): `phase` = `.loading | .resolved(HomeStep) | .gone | .failed(UserMessage)`; `load()` — `summary(id:)` → `period == .daily` → `.summary(childId, name, date: periodStart)`; `.weekly` → `.weekly(childId, weekStart: periodStart)`; `period` yo'q yoki bola oilada yo'q (ism topilmasa) → `.gone`; 404 → `.gone`; boshqa xato → `.failed`. Generation hisoblagichi.
- `HomeStep.summaryLink(UUID)`; mavjud `.summary` va `.weekly` qadamlari ixtiyoriy sana oladi (`date: LocalDate?` / `weekStart: LocalDate?`, sukut `nil` — eski chaqiruvlar o'zgarmaydi); `makeDailySummaryModel(childId:childName:date:)`, `makeWeeklyModel(childId:weekStart:)`.
- `NotificationLink.step(for:)`: `.summary(id)` → `.summaryLink(id)` (child/type tekshiruvi endi kerak emas).
- Oraliq ekran `.resolved(step)` bo'lganda o'zini almashtiradi: `homePath` oxiridagi `.summaryLink` olib tashlanib, `step` qo'shiladi ("Orqaga" → kelgan joy).
- `ReviewPrompt`: `ReviewGate` (`UserDefaults`, kalitlar `review.firstSeenAt`, `review.askedAt`): birinchi chaqiruvda `firstSeenAt` yoziladi; `now - firstSeenAt >= 3 kun` va `askedAt` yo'q va soat orqaga ketmagan → `askedAt` yoziladi (so'rashdan OLDIN) va `true`. `DailySummaryView` xulosa yuklanganda (`summary != nil`) chaqiradi; `true` bo'lsa SwiftUI `@Environment(\.requestReview)` chaqiriladi. Natija noma'lum, qayta urinish yo'q.

## 5. Ekran — P16a (`screenSummaryLinkTitle`)
Yuklanmoqda → spinner; `.gone` → `NozirEmptyState(summaryLinkGoneTitle, summaryLinkGoneBody)`; `.failed` → `NozirErrorState` + "Qayta urinish"; `.resolved` → darhol almashtirish. Yangi l10n kaliti yo'q.

## 6. Testlar
`period` dekodlash (daily/weekly/yo'q/noma'lum); `summary(id:)` yo'l; `SummaryLinkModel`: daily → aniq sana, weekly → aniq hafta, 404 → gone, period yo'q → gone, bola oilada yo'q → gone, boshqa xato → failed, qayta urinish, eski javob tashlanadi; `NotificationLink` summary → summaryLink; mavjud summary/weekly chaqiruvlari o'zgarmaydi; `ReviewGate`: birinchi chaqiruv → yo'q, 3 kundan kam → yo'q, 3 kun → ha (bir marta), ikkinchi marta → yo'q, soat orqaga → yo'q.

## 7. Ochiq risklar
- `requestReview` dev/TestFlight'da ko'rinmasligi mumkin — Apple qaror qiladi; sinov faqat mantiq darajasida.
- Kunlik/haftalik ekran sana bilan ochilganda o'z ichki sana tanlagichi bilan to'qnashmasligi plan'da tekshiriladi.
