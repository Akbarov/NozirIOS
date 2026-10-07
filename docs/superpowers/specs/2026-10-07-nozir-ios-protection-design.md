# Nozir iOS — P18: Himoya holati (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi (bo'limlar 1–2) · Manba: Android `feature/protection`, backend `protection` moduli

## 1. Maqsad va qamrov

Ota-ona bola telefonidagi himoya to'liq ishlayaptimi — qaysi ruxsat o'chgan, telefon qachon oxirgi marta xabar bergan — iOS'da ko'radi va telefon modeliga mos tuzatish ko'rsatmasini bolaga yubora oladi. Android P18 bilan bir xil natija.

**Kiradi:** Home'dagi "Himoya" qatori (bitta bola va oila ko'rinishida), bola sahifasidagi "Himoya holati" qatori, P18 ekrani, ko'rsatma yuborish.

**Kirmaydi:** push/deep link (`nozir://protection/{childId}` — APNs sub-loyihasida, xuddi shu marshrutga ulanadi), har bir ruxsat uchun alohida ko'rsatma, bildirishnomalar ro'yxati (P16).

**Muvaffaqiyat mezoni:** bola telefonida ruxsat o'chsa, iOS Home'da qator rangi o'zgaradi; P18 qaysi ruxsat buzilganini va to'g'ri ko'rsatmani ko'rsatadi; "Yuborish" bola telefoniga ko'rsatma push qiladi.

## 2. Qarorlar (foydalanuvchi)

| # | Savol | Qaror |
|---|---|---|
| D1 | Kirish | Home qatori (ikkala ko'rinish) + bola sahifasidagi qator |
| D2 | Rang | Sog'lom → oddiy karta; qisman → diqqat (sariq); buzilgan → kritik (qizil). Faqat umumiy karta va Home qatori uchun |
| D3 | Ko'rsatma | Android kabi: birinchi buzilgan ruxsat uchun bitta karta + "Yuborish" barcha buzilganlarni yuboradi |
| D4 | Kod joyi | `NozirInsights` (Home modeli bilan birga) |
| D5 | Yangilash | Pastga tortish + oldingi planga qaytganda (Android'da yo'q) |

## 3. Backend shartnomasi (tekshirilgan, o'zgarmaydi)

- `GET /v1/parent/children/{childId}/protection` → `{childId, level: HEALTHY|DEGRADED|BROKEN, permissions: [{kind, status, wasRevoked, instructionKey?}], lastReportAt?, isStale, manufacturer, instructionKey?}`. `kind`: `USAGE_ACCESS, OVERLAY, NOTIFICATIONS, LOCATION, BATTERY, OEM_AUTOSTART`; `status`: `GRANTED, DENIED, SKIPPED`. Hech qachon xabar bermagan telefon → `BROKEN`, hammasi `DENIED`, `isStale=true`, `lastReportAt=null`. Eskirish: 36 soat.
- `POST /v1/parent/children/{childId}/protection/send-instructions` body `{kinds: [kind…]}` → 202, tanasiz. Bola telefoniga push.
- Home: `protection: {level, childrenNeedingAttention: [UUID]}` — oila bo'yicha eng yomon daraja va HEALTHY bo'lmagan bolalar.
- Obuna cheklovi yo'q. Ko'rsatma matnlari klientda (server faqat kalit beradi).

## 4. Arxitektura

### 4.1 NozirInsights
- `ProtectionLevel` (`healthy, degraded, broken`; noma'lum → `healthy`, Android kabi), `PermissionKind`, `PermissionStatus`, `ProtectionPermission{kind, status, wasRevoked, instructionKey?}` (noma'lum kind/status → tashlab yuboriladi), `ProtectionStatus{childId, level, permissions, lastReportAt?, isStale, manufacturer, instructionKey?}` — ixtiyoriy maydonlar mudofaaviy dekodlanadi.
- `ProtectionService`: `status(childId:) async throws -> ProtectionStatus`; `sendInstructions(childId:kinds:) async throws`. `ProtectionApi` — `ApiClient` orqali; avtomatik qayta yuborilmaydi.
- `ParentHome.protection: HomeProtection?` (`level`, `childrenNeedingAttention`); yo'q yoki o'qilmasa → `nil` (qator ko'rinmaydi).

### 4.2 NozirAppFeature
- `ProtectionTexts`: daraja sarlavhasi, umumiy matn (`protectionBodyAllWorking` / `protectionBodyNeedsFixing(N)`, N = `GRANTED` bo'lmaganlar), ruxsat nomi, holat so'zi + izoh (Android qoidasi: `GRANTED` → ishlayapti; `wasRevoked` → o'chib qolgan + izoh; `SKIPPED` → o'tkazib yuborilgan + izoh; aks holda yoqilmagan + izoh), eskirish izohi (`protectionStaleNote(o'tgan vaqt)` / `…Never`), ko'rsatma matni (11 ta kalit: `oem.{xiaomi,oppo,vivo,realme,infinix,generic}.autostart`, `oem.{xiaomi,samsung,generic}.battery`, `oem.generic.usage`, `oem.generic.overlay` → mos l10n; boshqasi → `protectionInstructionUnknown`; kalit = `permission.instructionKey ?? status.instructionKey`), Home qatori matnlari.
- `ProtectionModel` (`@MainActor @Observable`, `TimeRequestModel` naqshi): `phase` = `.loading | .ready | .failed(UserMessage) | .missing` (404 → `protectionNoChild…`); `status`; `isOffline` (faqat no-connection/timeout; boshqa yangilash xatosi → toast); generation hisoblagichi; `isSending`; `wereInstructionsSent` (model hayoti davomida); `sendInstructions()` — barcha `GRANTED` bo'lmagan kind'lar, bir vaqtda bitta, xato → toast.
- Home: `HomeModel.protection` + `protectionChildId` (filtr tanlangan bola bo'lsa — u; aks holda `childrenNeedingAttention` dagi birinchi; yo'q bo'lsa birinchi bola kartasi).
- Marshrutlar: `HomeStep.protection(UUID)`, `ProfileStep.protection(UUID)` (+ Home tab'dagi bola sahifasidan ham); `SignedInModel.makeProtectionModel(childId:)`.

## 5. Ekranlar

### 5.1 Home qatori
Umumiy kartadan keyin, P17 so'rov qatorlaridan keyin, stat kartalaridan oldin (ikkala ko'rinish). Karta tusi D2 bo'yicha, `glyphShield`, sarlavha/matn `homeProtection{Healthy,Degraded,Broken}{Title,Body}`, `glyphChevron`. Bosilsa P18.

### 5.2 Bola sahifasi
`ChildDetailsView`ga "Himoya holati" qatori (mavjud qator komponenti bilan; matn — `screenProtectionTitle`) → P18.

### 5.3 P18 (`screenProtectionTitle`)
Oflayn belgisi → umumiy karta (D2 tusi, daraja sarlavhasi, umumiy matn) → eskirish izohi (agar `isStale`) → ruxsatlar kartasi (har qator: rangli holat nuqtasi — `NozirStatusLevel`, nom, holat so'zi/izoh; bo'sh → `protectionEmpty…`) → tuzatish qismi (faqat buzilgan ruxsat bo'lsa): `protectionInstructionLabel`, ko'rsatma qatori (`protectionInstructionLine(bola, telefon, qadamlar)` / `…Unnamed`; telefon = `manufacturer` bosh harf bilan), "Yuborish" (`protectionActionSend(bola)` / `…Unnamed`, yuborilayotganda yuklanish), yuborilgach `protectionSendSent`. Yuklanmoqda → spinner; birinchi xato → `NozirErrorState` + qayta urinish. Aniq kalit nomlari plan'da `L10n.generated.swift`dan tekshiriladi; yangi kalit yo'q.

Accessibility: karta sarlavhalari heading; rangli nuqtalar holat matni bilan birga o'qiladi; glyph'lar yashirin; katta matnda hech narsa kesilmaydi.

## 6. Testlar
Swift Testing, soxta servis: dekodlash (noma'lum daraja → healthy, noma'lum kind/status tashlanadi, maydonlar yo'q, Home `protection` bor/yo'q/buzuq); API yo'l/metod/tana; model holatlari, oflayn, 404, eski javob yangisini bosmaydi; yuborish faqat buzilganlarni, ikki marta bosish → bitta so'rov, xato → toast va qayta faol; matn qoidalari (har bir holat, izohlar, 11 ko'rsatma kaliti + noma'lum); `protectionChildId` tanlovi.

## 7. Ochiq risklar
- Push yo'q: ota-ona buzilgan himoyani faqat Home ochilganda ko'radi.
- Qizil karta SOS bilan bir xil rangda (D2 — foydalanuvchi tanlovi).
