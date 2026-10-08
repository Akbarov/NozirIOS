# Nozir iOS — P19: Obuna (Nozir PRO) (dizayn)

Sana: 2026-10-08 · Holat: foydalanuvchi tasdiqladi · Manba: Android `feature/subscription`, `core/ui/PlanLockCard.kt`, backend `billing` moduli · Tahlil: `.superpowers/p19-analysis.md` (git'dan tashqarida)

## 1. Maqsad va qamrov

Ota-ona iOS'da obuna holatini ko'radi va Nozir PRO'ni Android kabi sotib oladi: server Click to'lov sahifasini (`checkoutUrl`) beradi, ilova uni Safari'da ochadi, PRO'ni server Click tasdiqlaganda beradi, ilova holatni qayta o'qib bilib oladi. StoreKit ishlatilmaydi.

**Kiradi:** P19 ekrani, Profil qatori "Obuna · Nozir PRO", qulf kartalaridagi "PRO rejaga oʻtish" tugmasi, `Idempotency-Key` qo'llovi, vasiy uchun izoh.

**Kirmaydi:** StoreKit/IAP va App Store ko'rib chiqish talablari (keyinroq alohida), deep link / `return_url` orqali qaytish, buyurtma holati endpointi (backendda yo'q), backend o'zgarishlari, Payme/Uzum/karta kanallari (server ruxsat bermaguncha).

**Muvaffaqiyat mezoni:** oila egasi yillik yoki oylik rejani tanlab "Click orqali toʻlash"ni bosadi → Safari'da Click ochiladi → to'lovdan keyin ilovaga qaytganda (yoki 5 daqiqa ichida) ekran "Nozir PRO faol" kartasiga o'tadi; qulf kartalaridan bir bosishda P19'ga borish mumkin.

## 2. Qarorlar (foydalanuvchi)

| # | Savol | Qaror |
|---|---|---|
| D1 | To'lov sahifasi | Safari'da (`openURL`), Android `ACTION_VIEW` kabi; ochilmasa `subscriptionCheckoutNotOpened` |
| D2 | Natijani bilish | Android: 5 s × 60 (5 daqiqa) tekshirish + "Toʻlovni tekshirish" + har kirishda yangilash; **qo'shimcha**: ilova oldinga chiqqanda (`scenePhase == .active`) darhol tekshirish |
| D3 | Vasiy (GUARDIAN) | To'lov tugmasi yashiriladi, o'rniga izoh: "Obunani faqat oila egasi sotib oladi." (yangi iOS kaliti) |
| D4 | Kirish | Android'dagi hamma joy: Profil qatori + `LocationLockCard` (xarita, xavfsiz hudud, kuzatuv) + `FrozenChildCard` (bola sahifasi, kunlik limit) |
| D5 | App Store qoidalari | Hozir e'tiborsiz; keyin ko'riladi |

## 3. Backend shartnomasi (tekshirilgan, o'zgarmaydi)

- `GET /v1/parent/subscription` → `{familyId, tier: FREE|PRO, status: ACTIVE|GRACE|EXPIRED|CANCELLED, state: FREE|TRIAL|PRO|GRACE, planCode?, channel?, currentPeriodEnd?, trialEndsAt?, graceUntil?, autoRenew, entitlements: [..], quotas: {..}, activeChildId?}`. Har qanday ota-ona.
- `GET /v1/parent/subscription/plans` → `[{code, tier, periodMonths, priceMinorUnits (tiyin), currency, features: [{key, text}], availableChannels: [..], plannedChannels: [..]}]`. Kanallar: `PAYME, CLICK, UZUM, CARD, GOOGLE_PLAY`.
- `POST /v1/parent/subscription/checkout` body `{planCode, channel}`, sarlavha `Idempotency-Key: <UUID>` (majburiy; yo'q bo'lsa `400 MISSING_IDEMPOTENCY_KEY`) → `201 {orderId, checkoutUrl, channel, expiresAt}`. Faqat OWNER (aks holda `403 FORBIDDEN`). Kanal o'chiq → `503 UPSTREAM_UNAVAILABLE`. Har bosish yangi buyurtma; bir xil kalit → saqlangan javob.
- PRO faqat Click `complete` callbackida beriladi (`autoRenew` doim `false`). Buyurtma holati ilovaga ochilmaydi.
- Hozirgi narxlar test narxlari (1 000 / 7 500 soʻm) — testlar va previewlar narxni qattiq yozmaydi, faqat fake ma'lumotdan oladi.

## 4. Holatni o'qish (Android mapper bilan bir xil)

`SubscriptionState`: `none`, `trial(endsAt?)`, `active(planCode?, endsAt?, autoRenew)`, `grace(planCode?, endedAt?, until?)`, `expired(planCode, endedAt?)`.
- `state == TRIAL` → trial(`trialEndsAt`)
- `state == GRACE` (yoki eski: `tier == PRO && status == GRACE`) → grace(`planCode`, `currentPeriodEnd`, `graceUntil`)
- `state == PRO` (yoki eski: `tier == PRO && status ∈ {ACTIVE, GRACE}`) → active
- aks holda `planCode != nil` → expired; aks holda → none.
- Noma'lum/yo'q `state` → yuqoridagi eski qoidalar; mudofaaviy dekodlash (o'qib bo'lmaydigan ixtiyoriy maydon → `nil`).

Reja: `tier != PRO`, `currency != UZS`, `periodMonths ∉ {1, 12}` → tashlanadi. Narx = `priceMinorUnits / 100` soʻm. Noma'lum kanal → tashlanadi. Yillik tejash foizi = Android `yearlySavingPercent` (butun foiz, yaxlitlash Android bilan bir xil); oylik ekvivalent = yillik/12, eng yaqin 100 soʻmgacha yaxlitlab. Imkoniyatlar va rejalashtirilgan kanallar yillik rejadan (yo'q bo'lsa oylikdan). To'lov kanali: tanlangan rejaning `availableChannels`ida `CLICK` bo'lsa CLICK, aks holda birinchisi, aks holda yo'q.

Bo'sh `checkoutUrl` yoki `http/https` bo'lmagan URL → "o'qib bo'lmaydigan javob" xatosi.

## 5. Arxitektura

### 5.1 NozirNetworking
- `ApiRequest`ga `idempotencyKey: UUID?` (standart `nil`); `makeURLRequest` uni `Idempotency-Key` sarlavhasiga yozadi. Avtomatik qayta yuborish yo'q.

### 5.2 NozirFamily
- `Subscription` kengaytiriladi: mavjud `activeChildId` + `isChildActive(_:)` o'zgarmaydi; qo'shiladi `state: SubscriptionState` (§4). Mavjud chaqiruvchilar buzilmaydi.
- Yangi turlar: `SubscriptionPlan{code, period: BillingPeriod(.monthly/.yearly), priceSom: Int64, features: [String], availableChannels, plannedChannels}`, `PaymentChannel`, `SubscriptionCheckout{orderId, checkoutUrl: URL}`.
- Yangi `BillingService: Sendable` — `plans() async throws -> [SubscriptionPlan]`, `startCheckout(planCode:channel:) async throws -> SubscriptionCheckout` (har chaqiruvda yangi UUID kalit). `BillingApi` — `ApiClient` orqali. Joriy obuna GET'i `FamilyService.subscription()`da qoladi (takrorlanmaydi).

### 5.3 NozirAppFeature
- `SubscriptionModel` (`@MainActor @Observable`): faza `loading / ready / failed(UserMessage)`; `plans`, `state`, `selectedPeriod`, `isOwner` (`FamilyService.me().role == "OWNER"`, PrivacyModel kabi; o'qib bo'lmasa → `true`, server baribir himoyalaydi), `isOffline`, `message`, `isStartingCheckout`, `isAwaitingPayment`, `checkoutURLToOpen`.
  - `load()`: avval rejalar, keyin holat (Android tartibi); generation counter eski javoblarni tashlaydi. Rejalar ekranda bo'lib noConnection/timeout → `isOffline`, aks holda xabar.
  - `pay()`: bitta in-flight guard (birinchi `await`dan oldin); muvaffaqiyat → `checkoutURLToOpen` + `isAwaitingPayment = true` + kuzatuv `Task` boshlanadi (oldingisi bekor); xato → xabar (rejalar qoladi). Vasiyga taklif qilinmaydi.
  - `checkoutOpened(_ accepted: Bool)`: URL tozalanadi; `false` → `isAwaitingPayment = false`, kuzatuv bekor, xabar `subscriptionCheckoutNotOpened`.
  - Kuzatuv: 60 marta {5 s kutish → holatni o'qish → `active` bo'lsa to'xtash va `isAwaitingPayment = false`}. Kutish vaqti test uchun injektsiya qilinadi (`sleep` closure). Ekrandan chiqilganda (`onDisappear`) bekor qilinadi.
  - `checkPayment()` va `sceneBecameActive()`: bitta darhol holat o'qish (in-flight bo'lsa tashlanadi); `active` → kuzatuv to'xtaydi.
- `SubscriptionView`: `@State(initialValue:)`, `.task { load }`, `.refreshable`, `scenePhase` → `sceneBecameActive`, `openURL(url) { accepted in model.checkoutOpened(accepted) }`. AX o'lchamlarda pastki qism siqilmaydi (katta matnda footer scroll ichiga tushadi — mavjud P20 yechimi kabi).
- `SubscriptionTexts`: holat matnlari, narx (minglik guruhlash, Android bilan bir xil ajratgich), kanal nomi, davr nomi, sanalar `DateTexts` orqali.
- Navigatsiya: `ProfileStep.subscription`, `HomeStep.subscription` (bola sahifasi va kunlik limit Home stekida), `LocationStep.subscription`; `SignedInModel.makeSubscriptionModel()`; `AppEnvironment` `BillingApi`ni ulaydi.
- `LocationLockCard` va `FrozenChildCard`ga `onUpgrade` tugmasi (`planLockActionUpgrade`); FrozenChildCard'da u ikkilamchi tugma yonida turadi (Android: ikkilamchi bor bo'lsa upgrade SECONDARY).
- `ProfileView`: "Obuna · Nozir PRO" qatori Qoidalar va Bildirishnomalar orasida (`profileRowSubscription`), qiymat yo'q (Android kabi).

### 5.4 NozirDesignSystem
- `NozirCardTone`ga `selected` (teal chegara/fon), `good` (yashil), `info` tonlari; reja kartasi uchun "tejash" belgisi (pill). Yuklanish — mavjud loading uslubi (alohida skeleton yo'q).

## 6. Ekran (P19, sarlavha `subscriptionTopBar`)

Yuqoridan pastga: oflayn izoh → holat bloki → taklif yoki faol karta → pastki qism.
- **trial:** `subscriptionTrialUntil(sana)` yoki `subscriptionTrialTitle` + `subscriptionTrialBody`.
- **grace:** `subscriptionGraceUntil(sana)` yoki `subscriptionGraceTitle`.
- **expired:** `subscriptionExpiredTitle`.
- **active:** "Nozir PRO faol" kartasi (`good`): davr (`subscriptionActiveYearly/Monthly`, reja topilsa), `subscriptionActiveUntil(sana)` yoki `subscriptionActiveNoEndDate`, `subscriptionActiveAutoRenewOn/Off` + imkoniyatlar. Taklif va to'lov tugmasi yo'q.
- **taklif** (active bo'lmaganda): rejalar bor va xabar bor → xabar taklif ustida; rejalar bor → yillik karta (nom, narx, `subscriptionPriceUnitYear`, `subscriptionMonthlyEquivalent`, `subscriptionSavingBadge(%)`) + oylik karta, ikkalasi radio; `subscriptionFeaturesLabel` + ro'yxat. Rejalar yo'q: xabar → xato holati + qayta urinish; yuklanmoqda → loading; aks holda `subscriptionPlansEmptyTitle/Body`.
- **pastki qism:** taklif bor va egasi → to'lov: kanal yo'q/narx yo'q → o'chiq `subscriptionActionPay` + `subscriptionPaymentNotReady` + kanal yorliqlari; tayyor → `subscriptionActionPayWith(kanal, narx)` (yuklanish holati bilan); kutilmoqda → `subscriptionAwaitingPayment` + ikkilamchi `subscriptionCheckPayment`. Taklif bor va vasiy → `iosSubscriptionOwnerOnly` izohi. Har doim `subscriptionSosFree` + `subscriptionSosFreeBody`.

## 7. Yangi l10n kaliti (iOS-only, `NozirKit/l10n/ios`)

`ios_subscription_owner_only`: uz "Obunani faqat oila egasi sotib oladi." · ru "Подписку покупает только владелец семьи." · en "Only the family owner can buy the subscription."
Boshqa yangi kalit yo'q.

## 8. Testlar (Swift Testing)

- Dekodlash/mapper: har bir `state`, eski PRO+GRACE/ACTIVE, FREE+planCode → expired, noma'lum qiymatlar; reja filtrlari; tiyin→soʻm; bo'sh/noto'g'ri `checkoutUrl`.
- Hisob: tejash foizi, oylik ekvivalent yaxlitlash, kanal tanlash, minglik formatlash.
- `ApiRequest`: `Idempotency-Key` sarlavhasi; har `startCheckout` yangi kalit.
- `SubscriptionModel`: yuklash tartibi va xatolar (oflayn vs xabar), tanlov saqlanishi, `pay` in-flight guard, 403/503 xabarlari, `checkoutOpened(false)`, kuzatuv `active`da to'xtaydi va 60 urinishdan keyin jim to'xtaydi, `checkPayment` / `sceneBecameActive`, eski generation javobi tashlanadi, vasiy → to'lov taklif qilinmaydi.
- Navigatsiya: Profil qatori va qulf kartalari `subscription` qadamini qo'shadi; `SignedInModel` fabrikasi.

## 9. Ochiq risklar

- `my.click.uz` havolasi Click iOS ilovasini ochadimi — noma'lum; real qurilmada tekshirish.
- App Store 3.1.1 (raqamli xizmat uchun IAP) bo'yicha rad etilish xavfi — D5 bo'yicha keyin.
- Bekor qilingan to'lovni ilova bilmaydi (endpoint yo'q) — 5 daqiqadan keyin "kutilmoqda" qoladi (Android bilan bir xil).
- Har bosish yangi buyurtma — bir nechta ochiq Click sahifasi bo'lishi mumkin (Android bilan bir xil).
- iOS fonda kuzatuvni to'xtatadi — D2 dagi oldinga chiqishda tekshirish buni qoplaydi.
