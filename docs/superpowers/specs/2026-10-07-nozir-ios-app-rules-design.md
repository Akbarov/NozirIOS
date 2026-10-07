# Nozir iOS — 2c-2: Ilova qoidalari (P11) (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi (bo'limlar 1–4) · Oldingi: 2c-1 qoidalar spec'i (`2026-10-06-nozir-ios-rules-design.md`)

## 1. Maqsad va qamrov

Ota-ona mavjud bolaning har bir ilovasi uchun qoida qo'ya olishi — Android `feature/rules/apps` (P11) bilan bir xil natija, iOS navigatsiyasiga moslangan.

**Kiradi:** P09 hub'dagi "Ilovalar" qatori; P11 ro'yxati (qoidali ilovalar, "Ilova qo'shish" + qidiruv shu sahifada); har bir ilova uchun alohida tahrirlovchi ekran; mavjud "Doim yopiq" qoidasini saqlab qolish.

**Kirmaydi:** push deep link (`app-rules/{childId}` — APNs sub-loyihasida), ilova ikonkalari (backend bermaydi), qoidani o'chirish endpoint'i (backend'da yo'q — "Cheklov yo'q" saqlanadi).

**Muvaffaqiyat mezoni:** iOS'da qo'yilgan ilova qoidasi bola telefonida va Android ota-ona ilovasida ko'rinadi; boshqa telefonda o'zgargan qoida ustidan hech qachon yozilmaydi; mavjud "Doim yopiq" qoidasi ota-ona boshqa rejim tanlamaguncha o'zgarmaydi.

## 2. Backend shartnomasi (tekshirilgan)

| So'rov | Tana / javob | Cheklov |
|---|---|---|
| `GET /v1/parent/children/{id}/rules` | snapshot'da qo'shimcha: `appPolicies: [AppPolicyDto]`, `neverBlockedPackages: [String]` | — |
| `PUT …/rules/apps/{packageId}` | `AppPolicyDto{packageId, displayName?, mode, dailyLimitMinutes?, blockWindows:[{startTime:"HH:mm", endTime:"HH:mm", days:[1..7]}]}` → to'liq `RuleSnapshot` | `If-Match` majburiy; yo'ldagi `packageId` ustun; `requireActive` (403 `CHILD_NOT_ACTIVE`); bo'sh paket → 400; hech qachon bloklanmaydigan paket + UNRESTRICTED dan boshqa rejim → 400; `DAILY_LIMIT` daqiqasiz → 400; `SCHEDULE_BLOCK` oynasiz yoki kunsiz oyna → 400; boshlanish/tugash tekshirilmaydi |
| `GET /v1/parent/children/{id}/apps` | `[{packageId, displayName?}]`, server `(displayName ?: packageId).lowercase()` bo'yicha saralaydi | obuna bilan cheklanmagan; bo'sh ro'yxat — telefon hali yubormagan |

- Rejimlar: `UNRESTRICTED`, `DAILY_LIMIT`, `SCHEDULE_BLOCK`, `ALWAYS_BLOCKED`.
- `UNRESTRICTED` saqlansa qator **o'chmaydi** (upsert) — ro'yxatda "Cheklov yo'q" bo'lib qoladi. DELETE yo'q.
- `displayName` har PUT'da qayta yoziladi (null ham) — iOS doim o'zidagi nomni yuboradi.
- Versiya 2c-1 dagi umumiy qoidalar versiyasi.

## 3. Arxitektura

### 3.1 NozirFamily
- `AppPolicyMode` (`unrestricted, dailyLimit, scheduleBlock, alwaysBlocked, unknown(String)` — noma'lum nom o'zgarmasdan qaytariladi).
- `BlockWindow{start: ClockTime, end: ClockTime, days: [Int]}`, `AppPolicy{packageId, displayName?, mode, dailyLimitMinutes?, blockWindows}`, `InstalledApp{packageId, displayName?}`.
- `RuleSnapshot` ga `appPolicies: [AppPolicy]` va `neverBlockedPackages: [String]` (yo'q bo'lsa `[]`); memberwise init sukut bilan; `ChildRulesSession.acceptBonus` yangi maydonlarni saqlaydi.
- `FamilyService`: `setAppPolicy(_ policy: AppPolicy, of: UUID, version: Int64) -> RuleSnapshot`; `installedApps(of: UUID) -> [InstalledApp]` (bo'sh paketlar tashlanadi).

### 3.2 NozirAppFeature/Rules
- `AppRulesModel` (P11 ro'yxati): `session`; `policies` (sessiya snapshot'idan, server tartibida); `installedApps` + `appsLoadFailure`; `isChoosingApp`, `query`; `addableApps` (qoidasi borlar — `UNRESTRICTED` ham —, hech qachon bloklanmaydiganlar va `nozir.other_apps` chiqarib tashlanadi); qidiruv — nom (chiroyli va xom) va paket bo'yicha substring, invariant kichik harf, trim, apostroflar `' ‘ ’ ʻ ʼ \`` → `'`.
- `AppRuleModel` (bitta ilova): `session`, `packageId`, `displayName`; R6 — `editBase` (sessiyadagi shu ilovaning qoidasi yoki `nil` — yangi); `edited` qoralama; `canSave`; `save()` `session.write` orqali.
- Nomlar: mavjud `AppUsageFolding.friendlyName` (ixtiyoriy nom uchun kichik adapter).
- `RuleMinuteRange.appDailyLimit = 15...240`.
- Kun tanlagich: `RuleDaysSection` sarlavhasi parametrlanadi (P11 da `app_rule_window_days` "Kunlar"); P10 xatti-harakati o'zgarmaydi.

## 4. Ekranlar

### 4.1 Hub qatori
`DailyLimitSection` "Boshqa qoidalar": Uyqu vaqti → **Ilovalar** → Bonus → Joylashuv. Qiymat: `rules_link_apps_none` yoki `rules_link_apps_count(N)`, N — rejimi `UNRESTRICTED` bo'lmagan qoidalar soni. Muzlatilganda o'chiq.

### 4.2 P11 — ro'yxat
Tartib: sarlavha (`app_rules_title`, `app_rules_subtitle`); oflayn belgisi (`state_offline_notice`, ma'lumot bor bo'lsa); birinchi yuklash xatosi → xato + "Qayta urinish"; yuklanmoqda → spinner; qoidali ilovalar kartasi (qator: chiroyli nom, xulosa, `›`; xulosa: `app_rule_none` / `app_rule_daily_limit(qisqa davomiylik)` / `app_rule_schedule(boshlanish, tugash)` (oyna yo'q bo'lsa `app_rule_none`) / `app_rule_always`; jadval va doim yopiq urg'u rangida); qoida yo'q → `app_rules_empty_title/body`; `app_rules_never_blocked` izohi; "Ilova qo'shish" (`app_rules_add`) → shu sahifada qidiruv (`app_rules_search_placeholder`) va ro'yxat (qator: nom, `app_rules_add_label`); topilmasa `app_rules_search_no_match(so'rov)`; ilovalar yuklanmasa — xato matni + "Qayta urinish" (Android'dan farq: u jim). Qator/ilova bosilsa → tahrirlovchi.

### 4.3 Tahrirlovchi
- Sarlavha — ilovaning chiroyli nomi.
- Rejim (segmentli): `app_rule_mode_none`, `app_rule_mode_daily_limit`, `app_rule_mode_schedule`; **`app_rule_always`** to'rtinchi segment; hech qachon bloklanmaydigan paketdan tashqari har bir ilovada to'rttala segment ko'rinadi (bunday paketda faqat "Cheklov yo'q"). "Doim yopiq" tasdiq oynasisiz tanlanadi va saqlanadi; daqiqa va oynalar tozalanadi. Noma'lum rejim — "Cheklov yo'q" ko'rsatilmaydi; qoralama boshqa rejim tanlanmaguncha o'zgarmaydi (saqlash o'chiq).
- Kunlik vaqt: slayder `app_rule_daily_limit_slider`, 15–240 qadam 15, sukut 30.
- Jadval: `app_rule_window_start` ("Yopilishi"), `app_rule_window_end` ("Ochilishi"), sukut 08:00–13:00; kunlar sukut 1–5, oxirgi kun o'chmaydi. Faqat birinchi oyna tahrirlanadi; qolganlari o'zgarmasdan yuboriladi.
- Rejim almashganda (`withMode`): cheklovsiz/doim yopiq — daqiqa va oynalar tozalanadi; kunlik — mavjud daqiqa yoki 30, oyna yo'q; jadval — mavjud oynalar yoki sukut oyna, daqiqa yo'q.
- "Saqlash" (`rules_action_save`): o'zgarish bo'lsa; yangi ilova (`editBase == nil`) uchun "Cheklov yo'q" holatida ham yoqiq. Muvaffaqiyat → ekranda qoladi, `rules_saved_named`/`rules_saved`; tahrirlovchi yangi asosga o'tadi.
- R6: saqlashdan oldin sessiyadagi shu paketning qoidasi `editBase` ga teng bo'lmasa → yuborilmaydi, `rules_conflict_notice`, qoralama sessiya qiymatiga almashadi. Boshqa paketlar yoki boshqa qoidalar o'zgarishi to'qnashuv emas.
- So'rov tanasi `displayName` bilan (o'rnatilgan ilovadan, bo'lmasa saqlangan qoidadan).

## 5. Xatolar va chekka holatlar
- 409 → sessiya qayta o'qiladi, qoralama tashlanadi, `rules_conflict_notice`, qayta yuborilmaydi.
- 403 `CHILD_NOT_ACTIVE` → `data_error_child_not_active`; 400 → `data_error_invalid_request`; tarmoq → `UserMessage`; qoralama qoladi.
- Ikki marta bosish → bitta so'rov; bekor qilingan saqlash → xabarsiz; hub'da boshqa yozuv davom etsa (`session.isWriting`) yoki muzlatilgan → saqlash o'chiq.
- Tabga o'tib qaytish → qoralama yo'qolmaydi (`@State` model, sessiya yuklanishi faqat bir marta).
- Server `message` hech qachon ko'rsatilmaydi; yangi l10n kaliti yo'q.

## 6. Navigatsiya
`RuleScreen.apps(ChildRulesSession)` va `RuleScreen.appRule(ChildRulesSession, packageId: String, displayName: String?)`; `SignedInModel.makeAppRulesModel(session:)`, `makeAppRuleModel(session:packageId:displayName:)`; Home va Profil stack'larida `ruleDestination` orqali.

## 7. Testlash
Swift Testing, fake'lar, `PauseGate` (`.timeLimit(.minutes(5))`).
- API: `setAppPolicy` yo'li (kichik harfli bola id, paket), `If-Match`, tana (rejim nomi, `HH:mm`, kunlar, `displayName`, `unknown` rejim nomi saqlanadi); `installedApps` dekodlash va bo'sh paket filtri; snapshot'da maydonlar yo'q → `[]`; `acceptBonus` ilova qoidalarini saqlaydi.
- `AppRulesModel`: ro'yxat, qo'shsa bo'ladigan filtr, qidiruv (apostrof/registr), ilovalar xatosi + qayta urinish, hub soni `UNRESTRICTED` ni sanamaydi.
- `AppRuleModel`: rejim almashish va sukutlar, "Doim yopiq" saqlanadi, oxirgi kun, qo'shimcha oynalar saqlanadi, saqlash/to'qnashuv/R6, boshqa ilova yoki P10 saqlanganda yolg'on to'qnashuv yo'q, muzlatilgan, `isWriting`, ikki bosish, bekor, qoralama himoyasi.
- Navigatsiya: fabrikalar hub sessiyasini ulashadi (ikkinchi `rules` o'qishi yo'q).

## 8. E2E (qo'lda)
Hub "Ilovalar" qatori va soni; ilova qo'shish, qidiruv; uch rejimni saqlab bola telefonida tekshirish; Android'da qo'yilgan "Doim yopiq" iOS'da saqlanib qolishi; "Cheklov yo'q" saqlangan qator ro'yxatda qolishi; Android bilan to'qnashuv; muzlatilgan bola; uch til, ikki tema.

## 9. Chetlanishlar (Android'ga nisbatan)
| # | Android | iOS 2c-2 | Sabab |
|---|---|---|---|
| D1 | Tahrirlovchi qator ostida | Alohida ekran | Foydalanuvchi tanlovi, iOS odati |
| D2 | `ALWAYS_BLOCKED` umuman taklif qilinmaydi ("oxirgi chora" deb hisoblanadi) va saqlashda jim tashlab yuboriladi | Har bir ilova uchun 4-segment sifatida taklif qilinadi, tasdiqsiz (hech qachon bloklanmaydigan paket bundan mustasno) | Foydalanuvchi so'rovi (2026-10-07) |
| D3 | Ilovalar yuklanmasa jim | Xato + qayta urinish | Ota-ona sababini bilsin |
| D4 | Saqlangach xabar yo'q | `rules_saved*` xabari | iOS P09/P10/P12 bilan bir xil |
| D5 | O'zgarishsiz qoralamani ham saqlaydi | Faqat o'zgarish bo'lsa (yangi ilova bundan mustasno) | Keraksiz yozuv va versiya oshishi yo'q |
| D6 | R6 yo'q | Shu paket bo'yicha R6 | 2c-1 spec §1 |
