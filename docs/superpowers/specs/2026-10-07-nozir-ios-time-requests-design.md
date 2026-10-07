# Nozir iOS — P17: Qo'shimcha vaqt so'rovlari (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi (bo'limlar 1–2) · Manba: Android `feature/timerequest`, backend `challenges` moduli

## 1. Maqsad va qamrov

Bola qo'shimcha daqiqa yoki bugungi uxlash vaqtini surishni so'raganda, ota-ona iOS'da so'rovni ko'rib, to'liq/qisman berishi yoki rad etishi mumkin — Android P17 bilan bir xil natija.

**Kiradi:** Home'da kutilayotgan so'rov qatorlari (bitta bola VA oila ko'rinishida — Android'dan yaxshiroq), P17 ekrani (ikkala tur: `EXTRA_MINUTES`, `BEDTIME_DELAY`), qaror POST'i, natija kartasi.

**Kirmaydi:** push/deep link (`nozir://extra-time/{id}` — APNs sub-loyihasida, xuddi shu marshrutga ulanadi), bildirishnomalar ro'yxati (P16), miqdor tanlagich, so'rovlar tarixi ro'yxati.

**Muvaffaqiyat mezoni:** bola so'rovi iOS Home'da ko'rinadi; ota-ona bergan daqiqalar bola telefonida bonus sifatida paydo bo'ladi; javob berilgan yoki muddati o'tgan so'rov qayta javob talab qilmaydi va "qoidalar o'zgargan" kabi noto'g'ri matn chiqmaydi.

## 2. Qarorlar (foydalanuvchi)

| # | Savol | Qaror |
|---|---|---|
| D1 | Ko'p bolali Home | Har bir kutilayotgan so'rov — ism bilan qator |
| D2 | Qisman berish | Android kabi bitta hisoblangan tugma |
| D3 | Javobdan keyin | Ekranda natija kartasi (toast/avto-orqaga yo'q) |
| D4 | Kod joyi | `NozirInsights` (Home modeli bilan birga) |
| D5 | Turlar | Ikkalasi (`EXTRA_MINUTES`, `BEDTIME_DELAY`) |
| D6 | 409 `ALREADY_DECIDED` / 404 | Ro'yxat qayta o'qiladi → odatda `.missing` (`timeRequestEmpty*`) |

## 3. Backend shartnomasi (tekshirilgan, o'zgarmaydi)

- `GET /v1/parent/extra-time-requests?status=PENDING` → `{items: [ExtraTimeRequest], nextCursor}` (cursor ishlatilmaydi; `createdAt desc`).
- `POST /v1/parent/extra-time-requests/{id}/decision` body `{outcome: APPROVE|PARTIAL|DECLINE, grantedMinutes?: Int, note?: String}` → 200 `ExtraTimeRequest`. Idempotency kaliti yo'q; takror → 409 `ALREADY_DECIDED`.
- `ExtraTimeRequest`: `id`, `childId`, `childName?`, `kind` (sukut `EXTRA_MINUTES`), `nightOf?` (faqat `BEDTIME_DELAY`), `requestedMinutes`, `reason`, `status` (`PENDING|APPROVED|DECLINED|EXPIRED`), `grantedMinutes?`, `decisionNote?`, `createdAt`, `decidedAt?`, `requestsInLastSevenDays?`.
- Xatolar: begona/noma'lum id → 404; javob berilgan/muddati o'tgan → 409 `ALREADY_DECIDED`; `PARTIAL` 1..requested emas → 400; `BEDTIME_DELAY`: grant 15/30 ga pastga yaxlitlanadi, 15 dan kichik qisman → 400, kecha tugagan yoki 30 daqiqa chegarasi tugagan → 409 `CONFLICT` (rad etish doim mumkin).
- Muddat: `EXTRA_MINUTES` 20 soat, `BEDTIME_DELAY` 12 soat (soatlik job).
- Qaror bonus jadvaliga yoziladi — qoidalar versiyasi o'zgarmaydi (`ChildRulesSession` kerak emas).
- Home: `GET /v1/parent/home` javobida `pendingExtraTimeRequests` (xuddi shu shakl).

## 4. Arxitektura

### 4.1 NozirInsights
- `ExtraTimeRequest` (+ `ExtraTimeKind`: `extraMinutes`, `bedtimeDelay`, `unknown(String)`; `ExtraTimeStatus`: `pending`, `approved`, `declined`, `expired`, `unknown(String)`).
- `ExtraTimeService` protokoli: `pending() async throws -> [ExtraTimeRequest]`; `decide(_ id: UUID, outcome: ExtraTimeOutcome, grantedMinutes: Int?, note: String?) async throws -> ExtraTimeRequest`. `ExtraTimeApi` — `ApiClient` orqali; qaror hech qachon avtomatik qayta yuborilmaydi.
- `ParentHome.pendingExtraTimeRequests: [ExtraTimeRequest]` (kalit yo'q → `[]`).
- `NozirNetworking.ApiErrorCode.alreadyDecided` (`ALREADY_DECIDED`).

### 4.2 NozirAppFeature
- `PartialMinutes.of(_ request) -> Int?`: `EXTRA_MINUTES` → `floor(requested/2)` 5 ga pastga; `<5` yoki `>= requested` → nil. `BEDTIME_DELAY` → `requested > 15` bo'lsa 15, aks holda nil.
- `TimeRequestModel` (`@MainActor @Observable`, `SosDetailModel` naqshi): `phase` = `.loading | .ready | .missing | .failed(UserMessage)`; `request`; `isOffline`; `isDeciding`; `isWritingDecline`; `declineNote` (280 belgi bilan cheklangan); `toast`; `usedMinutesToday: Int?` (Home kartasidan, yo'q bo'lsa qator yashiriladi); generation hisoblagichi; amallar `load`, `approve`, `approvePartial`, `startDecline`, `cancelDecline`, `confirmDecline`. Bir vaqtda bitta POST. Muvaffaqiyat → `request` = server javobi (natija kartasi). 409 `ALREADY_DECIDED` yoki 404 → `load()`. Boshqa xato → toast, tugmalar qayta faol.
- `HomeStep.timeRequest(UUID)`; `SignedInModel.makeTimeRequestModel(id:)`.

## 5. Ekranlar

### 5.1 Home qatori
Stat kartalaridan oldin, har bir kutilayotgan so'rov uchun (`HomeView` bitta bola va oila ko'rinishi): urg'u kartasi, `glyphChat`, sarlavha (`homeExtraTimeTitle` / `homeBedtimeDelayTitle`), matn (`homeExtraTimeBody(nom, N)` / `…Unnamed`, `homeBedtimeDelayBody…`), `glyphChevron`. Bosilsa P17.

### 5.2 P17 (`screenTimeRequestTitle`)
Oflayn belgisi → sarlavha kartasi (`timeRequestHeader…`, `timeRequestHeaderMeta(HH:mm)`) → sabab kartasi (`timeRequestReasonLabel`, `timeRequestReasonQuoted` / `timeRequestReasonEmpty`) → kontekst kartasi (`timeRequestContextUsed(X)` agar ma'lum, `timeRequestContextWeek(N)` / `…WeekFirst`) → qaror qismi:
- `pending`, izoh yozilmayapti: `timeRequestActionApprove(N)` / `…ApproveDelay`, qisman (`timeRequestActionPartial(M)` / `…PartialDelay`, faqat `PartialMinutes` bo'lsa), `timeRequestActionDecline`, izoh `timeRequestNote…` / `timeRequestDelayNote`.
- rad etish kartasi: `timeRequestDeclineLabel`, matn maydoni (`…DeclinePlaceholder`, `…DeclineHint`), `…DeclineBack`, `…DeclineConfirm`.
- natija kartasi: `timeRequestDoneApproved(N)` / `…DoneDeclined` / `…DoneExpired` + izoh.
Yuklanmoqda → spinner; birinchi xato → `NozirErrorState` + qayta urinish; `.missing` → `timeRequestEmptyTitle/Body`. Pastga tortib yangilash; oldingi planga qaytganda yangilanadi. Aniq kalit nomlari va imzolari plan'da `L10n.generated.swift` dan tekshiriladi; yangi kalit yo'q.

Accessibility: karta sarlavhalari heading; glyph'lar yashirin; katta matnda tugmalar ustma-ust.

## 6. Testlar
Swift Testing, soxta servis: id bo'yicha topish / `.missing`; `PartialMinutes` chegaralari (ikkala tur); har bir qaror tanasi (outcome, grantedMinutes, note trim/nil); ikki marta bosish → bitta POST; 409 → qayta yuklash → `.missing`; tarmoq xatosi ma'lumot bor paytda → `isOffline`, so'rov qoladi; eski javob yangisini bosmaydi; `ParentHome` maydonli/maydonsiz dekodlash; `ExtraTimeApi` yo'l/metod/tana; noma'lum `kind`/`status`.

## 7. Ochiq risklar
- Android ko'p bolali Home'da qator ko'rsatmaydi — iOS ko'rsatadi (D1); bu ataylab farq.
- Push yo'qligi sababli ota-ona so'rovni faqat Home ochilganda/yangilanganda ko'radi.
