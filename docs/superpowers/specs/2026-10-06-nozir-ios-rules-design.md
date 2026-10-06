# Nozir iOS — 2c-1: Mavjud bola qoidalarini o'zgartirish (dizayn)

Sana: 2026-10-06 · Holat: foydalanuvchi tasdiqladi (bo'limlar 1–5) · Oldingi: poydevor, 2a, 2b, 3 (joylashuv) spec'lari

## 1. Maqsad va qamrov

Ota-ona allaqachon ulangan bolaning qoidalarini iOS'da o'zgartira olishi — Android ota-ona ilovasidagi `feature/rules` bilan bir xil xatti-harakat.

**Kiradi (2c-1):**
- Kirish: Profil'da "Qoidalar" qatori va P03 bola tafsilotlarida "Qoidalar" qatori.
- P09 hub — kunlik limit (o'qish kuni / dam olish kuni, "Har kuni bir xil") + ishonch zinapoyasi + "Boshqa qoidalar" qatorlari.
- P10 uyqu vaqti.
- P12 bonus vaqt (maksimum + vazifalarni yoqish/o'chirish).
- P12b (3-sub-loyihada qurilgan) hub'dan ham ochiladi va umumiy sessiyadan foydalanadi.

**Kirmaydi:** P11 ilova qoidalari (2c-2: `rules/apps/{packageId}`, `GET …/apps`, muharrir), `rules/family/{kind}` (Android ishlatmaydi), push/APNs.

**Muvaffaqiyat mezoni:** iOS'da o'zgartirilgan qoida Android ota-ona ilovasida va bola telefonida (keyingi aloqada) ko'rinadi; boshqa telefonda o'zgargan qoida ustidan hech qachon yozilmaydi; muzlatilgan bolada ota-ona behuda o'zgartirmaydi.

## 2. Backend shartnomasi (tekshirilgan, `Nozir-Backend`)

| So'rov | Tana / javob | Cheklov |
|---|---|---|
| `GET /v1/parent/children/{id}/rules` | `RuleSnapshotResponse`: `version`, `screenTime{schoolDayMinutes, weekendMinutes, maxDailyBonusMinutes}`, `maxTrustBonusMinutes`, `locationTracking`, `bedtime{startTime, endTime, windDownMinutes, activeDays}`, (`appPolicies`, `familyRules`, `neverBlockedPackages` — 2c-1 da o'qilmaydi) | ETag = versiya |
| `PUT …/rules/screen-time` | `ScreenTimeLimitDto` (3 butun son) → snapshot | school/weekend 0..1440, bonus 0..480 |
| `PUT …/rules/trust-ladder` | `{maxTrustBonusMinutes}` → snapshot | 0..120 |
| `PUT …/rules/bedtime` | `BedtimeScheduleDto` → snapshot | `HH:mm`, wind-down 0..120, `activeDays` bo'sh emas, 1..7 |
| `PUT …/rules/location-tracking` | `LocationTrackingDto` → snapshot | 3-sub-loyihadagidek |
| `GET …/rules/bonus` | `BonusConfigDto{childId, ruleVersion, maxDailyBonusMinutes, challenges[{id, kind, difficulty, bonusMinutes, requiresParentApproval, enabled}]}` | ETag = `ruleVersion` |
| `PUT …/rules/bonus` | to'liq `BonusConfigDto` → `BonusConfigDto` | `If-Match` hal qiluvchi (tanadagi `ruleVersion` emas); maksimum 0..480 |

- Har bir `PUT` `If-Match: "<versiya>"` talab qiladi (yo'q bo'lsa 428 `MISSING_IF_MATCH`; eskirgan bo'lsa `CONFLICT`). Hech biri `@Idempotent` emas.
- Barcha qoidalar uchun **bitta umumiy versiya**: istalgan yozuv uni oshiradi; bonus ham shu versiyani ishlatadi.
- Har bir yozuv `requireActive` — muzlatilgan bola → 403 `CHILD_NOT_ACTIVE`.
- **Ma'lum holat (o'zgartirilmaydi):** joylashuv qoidasini **yozish** obuna bilan cheklanmagan; obunasiz bolada **o'qish** `locationTracking.isEnabled = false` qaytaradi (saqlangan qiymat o'zgarmaydi). Demak obunasiz oilada P12b "O'chiq" ko'rinadi; P12b dagi `SUBSCRIPTION_REQUIRED` qulf yo'li bu endpoint uchun amalda ishlamaydi. 2c-1 bu xatti-harakatni o'zgartirmaydi.
- `kind`: `MATH`, `READING`, `ENGLISH`, `EXERCISE`; `difficulty`: `EASY`, `MEDIUM`, `HARD`. Noma'lum qiymat dekodlashni buzmasligi kerak (`unknown`).

## 3. Arxitektura (yondashuv B — umumiy sessiya)

### 3.1 NozirFamily
- `RuleSnapshot` ga `maxTrustBonusMinutes: Int` (yo'q bo'lsa 0).
- `FamilyService`: `setTrustLadder(_ minutes: Int, of: UUID, version: Int64) -> RuleSnapshot`; `bonus(of:) -> BonusConfig`; `setBonus(_ config: BonusConfig, of: UUID, version: Int64) -> BonusConfig`.
- Yangi turlar: `BonusConfig{ruleVersion, maxDailyBonusMinutes, challenges}`, `BonusChallenge{id, kind, difficulty, bonusMinutes, requiresParentApproval, enabled}`, `ChallengeKind`, `ChallengeDifficulty` (har biri `unknown` bilan).
- Hammasi mavjud `FamilyApi` orqali, `ApiRequest.put(json:ifMatch:)`; bola id yo'lda kichik harflar bilan.

### 3.2 NozirAppFeature/Rules/
- **`ChildRulesSession`** (`@MainActor @Observable`, har bir hub uchun bitta): `childId`, `childName`, `snapshot: RuleSnapshot?`, `version`, `isFrozen`, `loadFailure`, `isOffline`; `load()` (qoidalar + reja; generation token), `accept(_ snapshot:)`, `acceptBonus(version:ceiling:)`, `reload()` (to'qnashuvdan keyin). Reja noma'lum bo'lsa hech kim muzlatilmaydi (2a dagidek).
- Ekran modellari — har biri faqat o'z qoralamasini ushlaydi va yozishda `session.version` ni ishlatadi:
  - `DailyLimitModel` (P09: limit + zinapoya)
  - `BedtimeModel` (P10)
  - `BonusModel` (P12; o'z `BonusConfig` ini o'qiydi)
  - `LocationTrackingModel` (P12b) — ixtiyoriy `session:` parametri qo'shiladi.
- Umumiy natija turi: `saved` / `conflict` / `failed(UserMessage)`; to'qnashuvda `session.reload()` + `notice = .conflict`, **avtomatik qayta yuborish yo'q**.
- Onboarding (P03b, `NewChildRulesView`) dagi slayder, vaqt tanlagich, kun chiplari va kun xulosasi umumiy view'larga ajratiladi; P03b xatti-harakati o'zgarmaydi.

## 4. Ekranlar

### 4.1 P09 — Kunlik limit (hub)
Tartib: (1) bola tanlagich — faqat Profil'dan ochilganda va 2+ bolada; (2) kunlik limit kartasi: o'qish kuni slayderi 30–360 qadam 15, "Har kuni bir xil" kaliti (saqlanmaydi; `school == weekend` dan aniqlanadi; yoqilganda dam olish kuni o'qish kuni qiymatini oladi; yoqiq paytda o'qish kuni o'zgarsa ikkalasi o'zgaradi), dam olish kuni slayderi; (3) ishonch zinapoyasi: 0–120 qadam 15, 0 = "O'chiq" (`trust_ladder_off_value`, `trust_ladder_note_off`), aks holda `trust_ladder_note_rungs`; (4) `daily_limit_notice_named` / `daily_limit_notice`; (5) "Boshqa qoidalar": Uyqu vaqti (`rules_time_range` + kun xulosasi), Bonus vaqt (`rules_link_bonus_ceiling`), Joylashuv (`rules_link_location_every` yoki o'chiq); Ilovalar qatori 2c-2 gacha yo'q; (6) "Saqlash" (`rules_action_save`) — faqat o'zgarish bo'lsa yoqiq.

**Saqlash:** zinapoya o'zgargan bo'lsa avval `PUT trust-ladder`; muvaffaqiyatli bo'lsa va limit ham o'zgargan bo'lsa, javobdagi **yangi versiya** bilan `PUT screen-time`. Birinchisi xato bo'lsa — ikkinchisi yuborilmaydi. Har bir muvaffaqiyatli javob `session.accept` ga beriladi. Muvaffaqiyat: `rules_saved_named`/`rules_saved`. `maxDailyBonusMinutes` o'zgartirilmasdan qaytariladi.

**Muzlatilgan:** qulf kartasi (`plan_lock_frozen_child_title/body`, "Shu bolani faol qilish" → `chooseActiveChild`, `plan_lock_sos_note`); "Saqlash" yashirin; "Boshqa qoidalar" qatorlari o'chiq.

**Holatlar:** yuklanmoqda (spinner), birinchi yuklash xatosi (`NozirErrorState` + "Qayta urinish"), ekranda ma'lumot bor paytda tarmoq yo'q → `state_offline_notice`, bola yo'q → `rules_no_child_title/body`.

### 4.2 P10 — Uyqu vaqti
Boshlanish/tugash vaqti (odatda yarim tundan o'tadi; uzunlik `bedtime_length`), kun chiplari (oxirgi kunni o'chirib bo'lmaydi; xulosa `bedtime_days_*`), uyquga tayyorgarlik kaliti + 15–60 slayder qadam 15 (o'chiq = 0; qayta yoqilganda oldingi qiymat, birinchi marta 30), "Uyqu vaqtida ham ishlaydi" kartasi (faqat ko'rish: `bedtime_allowlist_*`). Saqlash `PUT bedtime`.

### 4.3 P12 — Bonus vaqt
`GET rules/bonus`. Kunlik maksimum 0–120 qadam 15 (`bonus_ceiling_*`); 0 → `bonus_ceiling_zero`; yoqilgan vazifalar yig'indisi maksimumdan katta → `bonus_ceiling_binding`. Vazifalar ro'yxati: nom (`bonus_challenge_<kind>`), `+N`, qiyinlik, "Siz tasdiqlaysiz" (`requiresParentApproval` bo'lsa), yoqish/o'chirish kaliti — faqat `enabled` tahrirlanadi. Bo'sh → `bonus_empty_*`. Saqlash: to'liq konfiguratsiya `PUT rules/bonus` (`If-Match` = sessiya versiyasi); javob → `session.acceptBonus`. To'qnashuvda bonus ham, sessiya ham qayta o'qiladi.

### 4.4 P12b
Mavjud ekran. Sessiya bilan: qoida sessiyadan, saqlangach `session.accept`. Sessiyasiz (Joylashuv tabi): o'zgarishsiz. Mavjud testlar o'zgarishsiz o'tadi.

## 5. Kirish va navigatsiya
- **Profil:** "Mening oilam" bo'limidan keyin "Qoidalar" qatori (`profile_row_rules`); bola bo'lmasa ko'rsatilmaydi; hub tanlagich bilan, sukut — birinchi bola.
- **P03:** forma va "Saqlash" orasida "Qoidalar" qatori; hub shu bola uchun, tanlagichsiz; muzlatilgan bo'lsa ham ochiladi.
- `SignedInView`: `ProfileStep.rules(UUID?)`, `HomeStep.rules(UUID)` va ichki qadamlar `bedtime`, `bonus`, `locationTracking` — hammasi hub'ning sessiyasi bilan. Bola tanlagichda boshqa bola → yangi sessiya. Chiqishda `clearPaths`.
- `SignedInModel`: `makeRulesSession(childId:)`, `makeDailyLimitModel(session:)`, `makeBedtimeModel(session:)`, `makeBonusModel(session:)`, `makeLocationTrackingModel(session:)`.

## 6. Xatolar va chekka holatlar
- To'qnashuv → sessiya qayta o'qiladi, `rules_conflict_notice`, qoralama tashlanadi (Android kabi), qayta yuborilmaydi.
- 403 `CHILD_NOT_ACTIVE` → `data_error_child_not_active`, qoralama qoladi.
- Tarmoq/5xx → `UserMessage`, qoralama qoladi, qayta saqlash mumkin.
- Ikki marta tez "Saqlash" → bitta so'rov (sinxron `isSaving` qo'riqchisi).
- Kechikkan javob (boshqa bola, yangiroq yuklash) → generation token bilan tashlanadi.
- Boshqa tabga o'tib qaytish → saqlanmagan qoralama yo'qolmaydi (yuklash faqat qoralama yo'q bo'lsa).
- Server `message` hech qachon ko'rsatilmaydi; yangi l10n kaliti yo'q (Android'dagi barcha kalitlar iOS'da bor).

## 7. Testlash
Swift Testing, fake service'lar, `PauseGate` (`.timeLimit(.minutes(5))`).
- API: trust-ladder/bonus yo'llari, `If-Match`, tana, dekodlash; `maxTrustBonusMinutes` yo'q bo'lsa 0; noma'lum `kind`/`difficulty`.
- Sessiya: load, accept, muzlatilganlik (noma'lum reja = muzlatilmagan), eski generation.
- P09: ikki bosqichli saqlash va versiya zanjiri, birinchisi xato → to'xtash, "har kuni bir xil", to'qnashuvda qayta yubormaslik, qoralama himoyasi, muzlatilganda saqlash yo'q.
- P10: oxirgi kun, wind-down eslab qolish, saqlash, to'qnashuv.
- P12: maksimum xabarlari, toggle, `acceptBonus`, to'qnashuv.
- P12b: sessiya bilan; eski testlar o'zgarishsiz.
- Navigatsiya fabrikalari.

## 8. E2E (qo'lda)
Profil va P03 dan kirish; P09/P10/P12/P12b ni o'zgartirib bola telefonida va Android ota-ona ilovasida ko'rish; Android'da o'zgartirib iOS'da eski versiya bilan saqlash → to'qnashuv xabari; bepul rejada ikkinchi (muzlatilgan) bola — qulf kartasi va "faol qilish"; uch til, ikki tema.

## 9. Chetlanishlar (Android'ga nisbatan)
| # | Android | iOS 2c-1 | Sabab |
|---|---|---|---|
| D1 | Hub faqat Profil'dan, avval tanlangan bola uchun | Profil (tanlagich bilan) + P03 | Foydalanuvchi tanlovi |
| D2 | Har ekran o'z snapshot'ini o'qiydi | Umumiy `ChildRulesSession` | Bitta umumiy versiya: o'z saqlashlaringiz bir-biriga to'qnashmasin |
| D3 | Ilovalar qatori hub'da | 2c-2 gacha yo'q | P11 keyingi sub-loyiha |
