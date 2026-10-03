# Nozir iOS — 2a: Oila va ulanish (+ tillar va tema)

- **Sana:** 2026-10-03
- **Holat:** dizayn, foydalanuvchi ko'rib chiqishini kutmoqda
- **Oldingi spec:** `2026-10-03-nozir-ios-foundation-design.md` (poydevor)
- **Manba:** Android `NozirParent` (`feature/children`, `feature/pairing`, `feature/profile`,
  `navigation/*`, `core/domain/children`, `res/values*/strings.xml`), backend
  `docs/api/openapi.yaml` (`/v1/parent/children*`, `/rules*`, `/subscription*`, `/me`)

---

## 1. Maqsad

Ota-ona iOS ilovasida bolasini qo'shadi, unga boshlang'ich qoidalar beradi va bolaning
Android telefonini juftlaydi; profilda bolalarini, temani va tilni boshqaradi. Ilova uch
tilda (uz/en/ru) ishlaydi va tilni ilova ichida almashtirish mumkin.

Muvaffaqiyat mezonlari:

1. Yangi ota-ona Telegram orqali kirgach, bolasi yo'q bo'lsa to'g'ridan-to'g'ri P03 ga tushadi.
2. P03 → P03b → P04 oqimi haqiqiy backend va haqiqiy bola telefoni bilan oxirigacha o'tadi
   (P04 "Ulandi" holatiga yetadi).
3. P21 da til uz/en/ru va tema tizim/yorug'/qorong'i almashtirilganda barcha ekranlar
   darhol yangilanadi; tanlov qayta ishga tushirishdan keyin saqlanadi.
4. Barcha mantiq unit testlar bilan qoplangan; CI yashil.

## 2. 2-sub-loyihaning bo'linishi (kelishilgan)

| # | Bo'lak | Ekranlar |
|---|---|---|
| **2a** | **Oila va ulanish** (ushbu spec) | P03, P03b, P04, P21, bola tafsilotlari |
| 2b | Home va hisobotlar | P05, P06, P07, P08 |
| 2c | Qoidalar | P09, P10, P11, P12 |
| 2d | Ogohlantirishlar va hisob | P16, P17, P18, P20 |

## 3. Qabul qilingan qarorlar

| Mavzu | Qaror |
|---|---|
| Tillar | uz, en, ru — hozirdan |
| Til tanlovi | Ilova ichida (P21), Android kabi. iOS tizim oynalari tizim tilida qoladi — qabul qilingan cheklov |
| Tarjima tizimi | Android `strings.xml` (uz/en/ru) dan skript bilan generatsiya qilingan `L10n.swift` |
| Tema | P21 da: tizim / yorug' / qorong'i |
| Kirishdan keyingi yo'nalish | Bolalar ro'yxati bo'sh → P03, aks holda Home (`isNewAccount` Telegram'da doim `false`) |
| Kesh | Faqat xotirada; ekran ochilganda yangilanadi |
| Push | Yo'q; P04 4 soniyalik so'rov bilan ishlaydi |

## 4. Qamrov

**Kiradi:** `NozirL10n` moduli va generator, poydevor matnlarini L10n'ga ko'chirish,
`AppearanceStore`, tab paneli (Home o'rinbosari + Profile), `NozirFamily` moduli
(children, rules-qismi, subscription, pairing, profile API'lari va `FamilyStore`), P03,
P03b, P04, bola tafsilotlari (tahrirlash/o'chirish/faol qilish), P21.

**Kirmaydi:** diskdagi kesh, push va APNs, P05 Home mazmuni (2b), qoidalar ekranlari
P09–P12 (2c), P16/P19/P20 (P21 dagi ularga havolalar o'sha bo'laklargacha yashirin),
joylashuv (3-sub-loyiha).

## 5. Arxitektura

### 5.1 Yangi va o'zgaradigan modullar

| Modul | Vazifasi | Bog'liqligi |
|---|---|---|
| `NozirL10n` (yangi) | `AppLanguage` (uz/en/ru), generatsiya qilingan `L10n` (tipli kalitlar va formatlovchi funksiyalar), `LanguageStore` (`@Observable`, UserDefaults) | — |
| `NozirNetworking` (kengayadi) | `ApiRequest.ifMatch`, `ApiRequest.idempotencyKey`; yangi `ApiErrorCode` konstantalari | — |
| `NozirFamily` (yangi) | `ChildrenApi`, `RulesApi` (snapshot, screen-time, bedtime), `SubscriptionApi`, `PairingApi`, `ProfileApi`, DTO'lar, `FamilyStore` | Networking |
| `NozirDesignSystem` (kengayadi) | `AppearanceStore` (tema), yangi komponentlar: forma maydoni, avatar tanlovi, QR ko'rinishi, ro'yxat qatori, qulf kartasi | L10n (faqat qulf kartasi matnlari uchun emas — matnlar chaqiruvchidan keladi) |
| `NozirAppFeature` (kengayadi) | Tab paneli, P03/P03b/P04/bola tafsilotlari/P21 ekranlari va modellari; `Copy.swift` o'rniga `L10n` | hammasi |

### 5.2 Tarjima generatori

- `scripts/gen-l10n.py` kiradi: `NozirParent/app/src/main/res/values{,-en,-ru}/strings.xml`
  va `NozirKit/l10n/ios-strings{,-en,-ru}.xml` (faqat iOS'ga xos matnlar — "App Store",
  "Telegram orqali qaytadan kiring" kabilar; bir xil kalit bo'lsa iOS fayli ustun).
- Chiqadi: `NozirKit/Sources/NozirL10n/L10n.generated.swift` — repo'ga commit qilinadi
  (build vaqtida generatsiya yo'q, Xcode plugin yo'q).
- Kalit nomi: Android `snake_case` → Swift `lowerCamelCase` (`welcome_title` → `welcomeTitle`).
- `%1$s`/`%1$d` bo'lgan matnlar funksiyaga aylanadi: `L10n.signInTelegramCodeSubtitle(_ arg1: Int)`.
  Argument turlari `s` → `String`, `d` → `Int`; bir kalitning uch tildagi argumentlari
  mos kelmasa generator xato bilan to'xtaydi.
- XML maxsus belgilari (`\'`, `\"`, `\n`, `&amp;`, `<![CDATA[`) to'g'ri ochiladi.
- Faqat ishlatiladigan kalitlar emas, **barcha** kalitlar generatsiya qilinadi (708 ta);
  ishlatilmaganlari kompilyatsiyaga zarar qilmaydi va keyingi bo'laklarda kerak bo'ladi.
- `string-array` lar (3 ta) bu bo'lakda generatsiya qilinmaydi.
- Tarjimasi yo'q kalit uchun uz matni ishlatiladi (Android xatti-harakati bilan bir xil).
- `L10n` qiymatlari `LanguageStore.current` ga qarab olinadi; view'lar `LanguageStore` ni
  kuzatgani uchun til almashganda qayta chiziladi.

### 5.3 Tema

`AppearanceStore` (`@Observable`): `system | light | dark`, UserDefaults'da saqlanadi.
Ildiz view'ga `.preferredColorScheme(nil | .light | .dark)` qo'llanadi. Ranglar poydevorda
allaqachon ikki rejimga tayyor.

### 5.4 Navigatsiya

- `signedIn` holatida `TabView`: **Home** (o'rinbosar, 2b da to'ldiriladi) va **Profile**.
  Statistika va Joylashuv tablari o'z bo'laklarida qo'shiladi.
- Har bir tab o'z `NavigationStack` iga ega.
- Kirgandan keyin `FamilyStore.refresh()`; ro'yxat bo'sh bo'lsa P03 Home tab ustida
  modal (full-screen) oqim sifatida ochiladi: P03 → P03b → P04 → yopiladi.
- Profile'dan "Bola qo'shish" ham xuddi shu oqimni ochadi; "Juftlash" esa to'g'ridan-to'g'ri P04.

## 6. Ma'lumot oqimi

### 6.1 Bola qo'shish

1. **P03** forma → `ChildDraft` (serverga hech narsa yuborilmaydi). Tekshiruvlar:
   ism 1–40 belgi (bo'shliqlar kesiladi); tug'ilgan yil 1990…joriy yil; avatar kaliti
   Android ro'yxatidan; telefon ixtiyoriy, `^\+998[0-9]{9}$`; yosh rejimi (Android
   `AgeModeCard`) — backendga `ageGroup` override sifatida, agar Android shunday yuborsa
   (reja bosqichida Android `ChildCreateDto` dan aniqlanadi).
2. **P03b** "Saqlash":
   1. `POST /v1/parent/children` → `Child`. `403 CHILD_LIMIT_REACHED` → limit matni,
      oqim to'xtaydi.
   2. `GET /v1/parent/children/{id}/rules` → `version`.
   3. `PUT .../rules/screen-time` (`If-Match: "<version>"`) → yangi snapshot, yangi `version`.
   4. `PUT .../rules/bedtime` (`If-Match: "<yangi version>"`).
   5. 2–4 qadamdan biri muvaffaqiyatsiz bo'lsa (tarmoq yoki `409 CONFLICT`): `CONFLICT`
      da snapshot qayta o'qiladi va **bir marta** qayta uriniladi; baribir bo'lmasa bola
      **o'chirilmaydi**, "Qoidalarni keyinroq sozlash mumkin" xabari bilan P04 ga o'tiladi.
3. **P04** (6.2).

### 6.2 Juftlash (P04)

- Ochilganda `GET .../pairing-code`; `404` → `POST` (yangi kod; eskisini backend bekor qiladi).
- Ko'rsatiladi: 6 xonali kod, `qrPayload` dan QR (`CoreImage CIQRCodeGenerator`), muddatgacha
  qolgan vaqt (`expiresAt`, soat qiymatlari testda boshqariladi), holat ro'yxati.
- So'rov har 4 soniyada `GET .../pairing-code`; ekran ko'rinmay qolsa yoki ilova fonga
  o'tsa to'xtaydi, qaytganda davom etadi.
- `state`: `CODE_ISSUED` → "Kod kutilmoqda"; `APP_INSTALLED` → "Ilova o'rnatildi";
  `PAIRED` → "Ulandi", so'rov to'xtaydi, 1.5 s dan keyin oqim yopiladi;
  `EXPIRED`/`REVOKED` yoki muddat tugashi → so'rov to'xtaydi, "Yangi kod" tugmasi (`POST`).
- Tarmoq xatosi so'rovni to'xtatmaydi (keyingi 4 s da qayta), lekin holat ostida
  "Internet aloqasi yo'q" ko'rsatiladi.

### 6.3 Bola tafsilotlari

- `PATCH /v1/parent/children/{id}` (ism, yil, avatar, telefon), `DELETE` (tasdiqlash
  dialogi bilan; muvaffaqiyatdan keyin Profile'ga qaytiladi).
- `GET /v1/parent/subscription`: `activeChildId` bor va bu bola emas → bola muzlatilgan:
  qulf kartasi va "Faol qilish" (`PUT /v1/parent/subscription/active-child`).
  Obuna noma'lum bo'lsa (javob kelmagan) — cheklov qo'yilmaydi (Android `FamilyPlan.Unknown`).

### 6.4 P21 Profil

- `GET /v1/parent/me` (ism, telefon), `FamilyStore` dan bolalar (juftlash holati bilan),
  tema tanlovi, til tanlovi, chiqish (poydevordagi `AppModel.signOut`).
- Ism tahrirlash: `PATCH /v1/parent/me {displayName}`.

### 6.5 Til

- Boshlang'ich til: saqlangan tanlov → yo'q bo'lsa telefonning birinchi afzal tili
  (uz/ru/en dan biri bo'lsa) → bo'lmasa `uz`.
- Tanlanganda: `LanguageStore.set(_:)` darhol (UI yangilanadi) → fonda
  `PATCH /v1/parent/me {locale}`. Muvaffaqiyatsiz bo'lsa "yuborilmagan" belgisi saqlanadi
  va keyingi ishga tushishda (sessiya bo'lsa) qayta yuboriladi.
- Kirishdan keyin backenddagi `parent.locale` lokal tanlovni **almashtirmaydi** (lokal tanlov
  ustun; Android bilan bir xil emas bo'lsa — reja bosqichida tekshiriladi).

## 7. Xatolar

`UserMessage` kengayadi (Android `data_error_*` matnlari, endi `L10n` orqali):
`CHILD_LIMIT_REACHED`, `CHILD_NOT_ACTIVE`, `SUBSCRIPTION_REQUIRED`, `CONFLICT`,
`NOT_FOUND`, `VALIDATION_FAILED`, `PHONE_NUMBER_INVALID` (maydon ostida),
`PAIRING_CODE_*` (P04 da). Server `message` hech qachon ko'rsatilmaydi (poydevor qoidasi).

## 8. Testlash

Swift Testing, `FakeTransport`, soat va taymer in'ektsiya qilinadi.

| Qism | Testlar |
|---|---|
| L10n generator | Python unit testlari: kalit nomlash, argumentli matnlar, XML belgilari, argument nomuvofiqligi xatosi, iOS ustunligi, uz'ga qaytish |
| `L10n` / `LanguageStore` | Til almashganda qiymat o'zgaradi; tarjima yo'q kalit uz qaytaradi; boshlang'ich til zanjiri; saqlash |
| `AppearanceStore` | saqlash va `ColorScheme?` xaritasi |
| `ApiRequest` | `If-Match` va `Idempotency-Key` sarlavhalari |
| Family API'lari | Har bir endpoint: yo'l, metod, tana, javob dekodlash (backend DTO fixture'lari) |
| P03 modeli | Barcha tekshiruvlar, telefon formatlash |
| P03b modeli | Muvaffaqiyatli zanjir (`v`, `v+1`); `CHILD_LIMIT_REACHED`; `CONFLICT` → qayta o'qib bitta urinish; qoida xatosida bola o'chirilmaydi va P04 ga o'tiladi |
| P04 modeli | 404 → POST; holatlar bo'yicha UI holati; `PAIRED` da so'rov to'xtaydi; `EXPIRED` → yangi kod; to'xtatish/davom ettirish; tarmoq xatosida davom etish |
| Bola tafsilotlari modeli | Tahrirlash, o'chirish, muzlatilgan holat va faol qilish, obuna noma'lum |
| P21 modeli | Til/tema tanlovi, til backendga yuborilishi va qayta urinish |
| Yo'naltirish | Bolalar bo'sh → P03 oqimi; bor → Home |

View'lar — simulyatorda qo'lda (uch tilda va ikki temada skrinshot).

## 9. Ma'lum xavflar

1. **iOS tizim oynalari ilova tilini olmaydi** (Telegram/Safari ochilishi, ruxsat dialoglari,
   `UIDatePicker` ichki matnlari) — qabul qilingan.
2. **Android tarjimalari to'liq emas** (en 648, ru 653 / uz 708) — yetishmaganlari uz'da
   ko'rinadi; to'ldirish Android tomonida.
3. **openapi'da yo'q endpointlar** (`GET /children/{id}/apps`, `PUT /rules/trust-ladder`) —
   2a da ishlatilmaydi; 2c da backend kodidan tekshiriladi.
4. **Juftlash push'siz** — 4 s kechikish bilan; push 3-sub-loyihada.
5. **Poydevor hali tekshirilmagan** — 2a implementatsiyasi poydevor testlari yashil bo'lib,
   commit qilingandan keyin boshlanadi.
