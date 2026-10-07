# Nozir iOS — P16: Bildirishnomalar ro'yxati (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi · Manba: Android `feature/notifications`, backend `notifications` moduli · Branch: `protection` (P18 bilan birga, foydalanuvchi so'rovi)

## 1. Maqsad va qamrov

Ota-ona iOS'da barcha bildirishnomalar tarixini ko'radi (push hali yo'q — ro'yxat ochilganda yangilanadi), muhimlarini filtrlaydi, bosib tegishli ekranga o'tadi va "telefon N soat aloqaga chiqmasa xabar berish" sozlamasini o'zgartiradi. Android P16 bilan bir xil natija.

**Kiradi:** Home'dagi qo'ng'iroqcha tugmasi, Profil'dagi "Bildirishnomalar" qatori, P16 ekrani (filtr, ro'yxat, "Yana ko'rsatish", o'qildi deb belgilash, havolalar), qurilma oflayn sozlamasi kartasi.

**Kirmaydi:** push/APNs, o'qilmaganlar belgisi (badge — backend son bermaydi), "hammasini o'qildi" (backend'da yo'q), boshqa sozlamalar (kunlik push chegarasi, tinch soatlar, SMS, o'chirilgan turlar — UI yo'q, qiymatlari o'zgarmay saqlanadi), `notificationsPushNote` eslatmasi (iOS'da push yo'q — ko'rsatilmaydi), xarita/challenges/subscription havolalari.

## 2. Qarorlar (foydalanuvchi)

| # | Savol | Qaror |
|---|---|---|
| D1 | Kirish | Home qo'ng'iroqchasi + Profil qatori (Profil qatori Home tab'iga o'tib P16 ni ochadi — havolalar Home stack'ida ishlaydi) |
| D2 | Havolalar | Hozir bor ekranlar: sos, extra-time (P17), protection (P18), summary (DAILY → kunlik xulosa, o'sha bolaning oxirgi kuni; WEEKLY → haftalik), app-rules (qoidalar sahifasi). Boshqasi → faqat o'qildi |
| D3 | Sozlama | "Telefon N soat aloqaga chiqmasa" kartasi hozir qo'shiladi (Android presetlari) |
| D4 | Kod joyi | `NozirInsights` (P17/P18 kabi) |

## 3. Backend shartnomasi (tekshirilgan, o'zgarmaydi)

- `GET /v1/parent/notifications?filter=ALL|IMPORTANT&cursor=&limit=` → `{items, nextCursor}`; eng yangisi birinchi; limit sukut 20; IMPORTANT = `ACTION|CRITICAL`; `nextCursor` shaffof, oxirgi sahifa bo'sh bo'lishi mumkin.
- `Notification`: `id` UUID, `type` (enum string; noma'lumlari ham keladi: TRIAL_*, SUBSCRIPTION_*), `tier` (GOOD|ATTENTION|ACTION|CRITICAL), `localisationKey`, `localisationArgs` (map; yo'q → `[:]`), `childId?`, `childName?`, `deepLink?` (`nozir://…`), `occurredAt`, `readAt?`.
- `POST /v1/parent/notifications/{id}/read` → 204 (allaqachon o'qilgan — xato emas).
- `GET/PUT /v1/parent/notification-preferences` — to'liq almashtirish: `dailyPushCap, quietHoursStart?, quietHoursEnd?, mutedTypes[String], smsForCriticalEnabled, deviceOfflineAfterMinutes` (60..2880, sukut 360).
- Saqlash muddati 180 kun. O'qilmaganlar soni va "hammasini o'qildi" endpointi yo'q.

## 4. Arxitektura

### 4.1 NozirInsights
- `ParentNotification` + `NotificationType` (ma'lum turlar + `unknown(String)`), `NotificationTier`; qator `id`/`tier`/`occurredAt` o'qilmasa tashlab yuboriladi (sahifa bitta element uchun buzilmaydi); `NotificationPage{items, nextCursor}`; `NotificationFilter{all, important}`.
- `NotificationPreferences` (barcha maydonlar, `mutedTypes` xom string sifatida).
- `NotificationsService` / `NotificationsApi`: `page(filter:cursor:)`, `markRead(_:)`, `preferences()`, `savePreferences(_:)`. Hech biri avtomatik qayta yuborilmaydi.

### 4.2 NozirAppFeature
- `NotificationTexts`: sarlavha (Android tartibi: `notification.digest.suppressed`+count → digest; `notification.app.installed`+count → son bilan; SAFE_ZONE_* + `childName`/`zoneName` → `…Named`; `notification.bedtimeDelay.requested` → uyqu so'rovi; aks holda tur bo'yicha; noma'lum → `notificationUnknown`), vaqt ("Bugun HH:mm" / "Kecha HH:mm" / "kun oy HH:mm"), "bola · vaqt", "Ilova ichida qoldi" (GOOD/ATTENTION), daraja → nuqta/karta tusi, oflayn sozlama matnlari.
- `NotificationLink.parse(_ deepLink:)` → `sos(UUID)`, `extraTime(UUID)`, `protection(UUID)`, `summary(UUID)`, `appRules(UUID)`, `other` (map, notifications, challenges, subscription, noto'g'ri). Qatorni `HomeStep`ga aylantirish: sos → `.sos(ActiveSos(sosId, childId, childName, occurredAt))` (childId yo'q bo'lsa hech narsa); extraTime → `.timeRequest(id, usedMinutesToday: nil)`; protection → `.protection(childId)`; summary → tur DAILY_SUMMARY_READY bo'lsa `.summary(childId, childName)`, WEEKLY_REPORT_READY bo'lsa `.weekly(childId)` (childId yo'q → hech narsa); appRules → `.rules(childId)`.
- `NotificationsModel` (`@MainActor @Observable`): `filter`, `items`, `nextCursor`, `phase` (`.loading | .ready | .failed(UserMessage)`), `isOffline`, `isLoadingMore`, `inlineMessage`, generation hisoblagichi (filtr almashishi va yangilash eski javoblarni bekor qiladi); `load()` (1-sahifa), `loadMore()` (bittadan ortiq emas), `setFilter(_:)`, `open(_:) -> HomeStep?` (darhol `readAt = now`, fon `markRead`, xatosi e'tiborsiz); oflayn sozlama: `preferences?` (yuklab bo'lmasa karta yo'q), `setOfflineAfter(minutes:)` — to'liq almashtirish, boshqa maydonlar o'zgarishsiz, xato → toast va eski qiymat.
- Marshrut: `HomeStep.notifications`; Profil qatori `model.tab = .home` + `homePath.append(.notifications)`; `SignedInModel.makeNotificationsModel()`.

## 5. Ekran

### 5.1 Kirish
Home: sarlavha qismida qo'ng'iroqcha tugmasi (`glyphBell`, accessibility `contentDescriptionNotifications`). Profil sozlamalar kartasida "Bildirishnomalar" qatori (`profileRowNotifications`).

### 5.2 P16 (`screenNotificationsTitle`)
Segment filtr (`notificationsFilterAll` / `notificationsFilterImportant`) → oflayn belgisi → ro'yxat (karta: daraja nuqtasi + sarlavha, o'qilmagan qalin; ostida "bola · vaqt"; GOOD/ATTENTION uchun `notificationsInAppOnly`) → `notificationsLoadMore` (faqat `nextCursor` bo'lsa; yuklanayotganda o'chiq) → oflayn sozlama kartasi (`notificationsOffline*`; presetlar 6/12/24/48 soat; joriy qiymat). Yuklanmoqda → spinner; birinchi xato → `NozirErrorState` + qayta urinish; bo'sh → `notificationsEmpty*` / `notificationsEmptyImportant*`. Pastga tortib yangilash; ochilganda va oldingi planga qaytganda yangilanadi. Aniq kalit nomlari plan'da `L10n.generated.swift`dan tekshiriladi; yangi kalit yo'q.

Accessibility: har qator bitta element (sarlavha, bola, vaqt, "o'qilmagan" holati matn bilan), glyph'lar yashirin, katta matnda hech narsa kesilmaydi.

## 6. Testlar
Dekodlash (noma'lum tur, noma'lum daraja → qator tashlanadi, args yo'q, buzuq element faqat o'zi tashlanadi), API yo'l/so'rov/tana, sarlavha qoidalari (har bir maxsus kalit + tur), vaqt formati (bugun/kecha/sana), havola tahlili va `HomeStep` xaritasi, model: sahifalash, bo'sh oxirgi sahifa, filtr almashishi eski javobni bekor qiladi, ikki marta "Yana" → bitta so'rov, o'qildi optimistik + xatosi jim, oflayn, sozlama to'liq almashtirish va xatoda qaytarish.

## 7. Ochiq risklar
- Push yo'q: yangi bildirishnoma faqat ekran ochilganda ko'rinadi.
- Kunlik xulosa havolasi aniq kunni emas, o'sha bolaning oxirgi xulosasini ochadi.
- 4 ta yangi backend turi "Yangi bildirishnoma" bo'lib ko'rinadi (Android kabi).
