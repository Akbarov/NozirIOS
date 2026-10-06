# Nozir iOS — 3: Joylashuv va SOS

- **Sana:** 2026-10-06
- **Holat:** dizayn bo'limlari foydalanuvchi tomonidan tasdiqlangan; yozma spec ko'rib chiqishni kutmoqda
- **Oldingi spec'lar:** `2026-10-03-nozir-ios-foundation-design.md`, `2026-10-03-nozir-ios-family-onboarding-design.md` (2a),
  `2026-10-05-nozir-ios-home-reports-design.md` (2b)
- **Manba:** Android `NozirParent` (`feature/location`, `feature/safezone`, `feature/sos`, `feature/rules/location`),
  backend Kotlin (`LocationController`, `SafeZone*`, `SosController`, `ParentRulesController`, `RulesDtos.kt`) — wire
  shakllari uchun haqiqat manbai backend.

---

## 1. Maqsad

Ota-ona bolasi hozir qayerdaligini xaritada ko'radi va kerak bo'lsa bola telefonidan yangi joylashuv so'raydi (P13),
xavfsiz hududlar chizadi (P14), bola telefoni qanchalik tez-tez joylashuv yuborishini sozlaydi (P12b) va faol SOS'ni
to'liq ekranda ko'rib, bolaga yoki 112 ga qo'ng'iroq qiladi va "ko'rdim" deb belgilaydi (P15).

Muvaffaqiyat mezonlari:

1. Joylashuv tabida 1 va 2+ bolali oilada haqiqiy backend ma'lumoti bilan pin, hududlar va holat kartasi to'g'ri.
2. "Hozir so'rash" bola telefoniga yetadi va ~30 s ichida yangi pin (yoki "mavjud emas" sababi) ko'rinadi.
3. Hudud qo'shish, tahrirlash, o'chirish ishlaydi; P12b qoidasi saqlanadi va bola telefoniga yetadi.
4. Home'dagi SOS banneri P15 ni ochadi; "Ko'rdim" SMS eskalatsiyasini to'xtatadi.
5. Uch tilda va ikki temada ekranlar to'g'ri; mantiq unit testlar bilan qoplangan; CI yashil.

## 2. Qabul qilingan qarorlar

| Mavzu | Qaror |
|---|---|
| Qamrov | Push'siz: P13, P14, P15, P12b. APNs (backend `ApnsPushSender` hozir stub) va P16a — Apple Developer hisobi bo'lganda alohida sub-loyiha |
| Obuna | Oldindan reja tekshirilmaydi; 403 `SUBSCRIPTION_REQUIRED` kelsa "Joylashuv PRO rejada" qulf kartasi (SOS izohi bilan), upgrade tugmasi P19 qurilguncha yashirin. O'chirish hech qachon cheklanmaydi |
| P12b ga kirish | Joylashuv tabidagi "Joylashuvni kuzatish" qatori (Android'dagi P09 yo'li P09 qurilganda qo'shiladi) |
| Modullar | Yangi `NozirLocation` moduli (A); P12b qoidasi `NozirFamily` da |
| Xarita | Apple MapKit (SwiftUI `Map`), kalitsiz; Google Maps ishlatilmaydi |
| Bola tanlash | P13 tepasida `NozirChildSwitcher` ("Hammasi"siz, 2+ bolada); sukut birinchi bola; Statistika tanlovidan alohida |
| SOS kirishi | Home banneri endi to'liq P15 ni push qiladi; 2b'dagi `SosSheet` olib tashlanadi, `SosAlert` qiymati kengaytiriladi |

## 3. Qamrov

**Kiradi:** Joylashuv tabi (P13 xarita, holat kartasi, "hozir so'rash" + kutish, hudud chiplari, P12b qatori), P14
(qo'shish/tahrirlash/o'chirish), P12b, P15 (tafsilot, xarita, qo'ng'iroqlar, Apple Maps yo'nalishi, "ko'rdim").

**Kirmaydi:** APNs va har qanday push, P16a, P16 bildirishnomalar tarixi, joylashuv tarixi (`location/events` — Android
ham ishlatmaydi), manzil qidirish/geocoding (joy nomini faqat backend beradi), P19 obuna, P09–P12, ota-onaning o'z
joylashuvi (CoreLocation ruxsati so'ralmaydi).

## 4. Arxitektura

### 4.1 Modullar

| Modul | Vazifasi | Bog'liqligi |
|---|---|---|
| `NozirLocation` (yangi) | `LocationApi` va `LocationService` protokoli: joriy fix, so'rov, hududlar CRUD, SOS alert olish va "ko'rdim"; modellar `LocationSnapshot`, `SafeZone`, `SafeZoneDraft`, `SosAlertDetail` | Networking |
| `NozirFamily` (kengayadi) | `RuleSnapshot.locationTracking` (yo'q bo'lsa sukut 10/3/100, yoqiq), `setLocationTracking(_:of:version:)` (If-Match) | Networking |
| `NozirDesignSystem` | Xaritasiz qoladi (MapKit faqat AppFeature'da); kerak bo'lsa segment tanlovi va qulf kartasi komponentlari | — |
| `NozirAppFeature` (kengayadi) | `LocationModel` (P13), `SafeZoneModel` (P14), `LocationTrackingModel` (P12b), `SosAlertModel` (P15), ekranlar, Joylashuv tabi | hammasi |

### 4.2 Navigatsiya

- Tablar: **Home, Statistika, Joylashuv, Profil** (Android tartibi).
- Joylashuv stack: P13 (ildiz) → P14 (yangi yoki hudud) ; P13 → P12b.
- Home stack: SOS banneri → P15.
- P14 va P12b dan qaytganda P13 hududlarni/qoida qatorini qayta o'qiydi (pin saqlanadi).

### 4.3 Vaqt va yangilash

- P13: har ochilishda, tabga qaytganda va ilova faollashganda `location` + `safe-zones` qayta so'raladi; joylashuv
  keshlanmaydi.
- P15: ochilganda alert so'raladi; vaqt matnlari har 30 s yangilanadi; alertni qayta so'rash — qo'lda.
- Kutish oralig'i (2,5 s) va soat testlarda in'ektsiya qilinadi.

## 5. Ekranlar va ma'lumot oqimi

### 5.1 P13 Joylashuv

- So'rovlar: `GET /v1/parent/children/{id}/location`, `GET .../safe-zones`, P12b qatori uchun `GET .../rules`.
- **Xarita:** bola pini (`isStale` bo'lsa xira); har hudud doira (bola turgan hudud — yashil, qolgani — asosiy rang);
  kamera pinda, bo'lmasa birinchi hududda, bo'lmasa Toshkent markazi (41.311081, 69.240562); kamera faqat pin
  koordinatasi o'zgarganda ko'chadi.
- **Holat kartasi:**
  - fix bor: joy nomi yoki hudud nomi (`placeLabel` → `zoneName`, ikkalasi yo'q bo'lsa "joy noma'lum"), "N daqiqa oldin
    yangilangan", "Aniqlik ±N m", batareya %; `isStale` → sariq ton va izoh (eskirish chegarasi serverda, ~35 daqiqa);
  - fix yo'q, sabab bor (`LOCATION_OFF` / `PERMISSION_DENIED` / `NO_FIX`): sabab matni va `unavailableAt` vaqti; sabab
    fix bilan birga kelsa ham ko'rsatiladi;
  - 404: "Hali joylashuv yuborilmagan" bo'sh holati (xato emas);
  - 403 `SUBSCRIPTION_REQUIRED`: qulf kartasi (`plan_lock_location_*` + `plan_lock_sos_note`), xarita chizilmaydi;
  - boshqa xato: pin yo'q bo'lsa to'liq xato + "Qayta urinish"; pin bor bo'lsa pin qoladi + oflayn belgisi.
- **Hududlar** yuklanmasa jim (chiplar bo'sh). `isActive=false` hudud chipida "faol emas" belgisi (iOS qo'shimchasi).
- **"Hozir so'rash":** `POST .../location/request` → `asked=false`: "bola telefoniga ulanib bo'lmadi"; `asked=true`:
  "kutilmoqda", so'ng 2,5 s oraliqda 12 martagacha `GET .../location`. To'xtash: yangi fix (`occurredAt` oldingisidan
  keyin) yoki yangiroq sabab (`unavailableAt` oldingi sababnikidan keyin — turli telefon soatlari solishtirilmaydi).
  12 urinishda hech narsa kelmasa jim to'xtaydi, eski pin qoladi. 429 → `retryAfterSeconds` bilan matn. Ikki marta
  bosish himoyalangan; ekran yopilsa yoki bola almashsa kutish bekor qilinadi. Tugma har holatda (hatto 404 da) ko'rinadi,
  qulf holatida — yo'q.
- **Pastda:** hudud chiplari (bosilsa P14 tahrirlash), "+ Hudud", "Joylashuvni kuzatish: har N daqiqada / O'chiq"
  qatori → P12b. Qoidalar o'qilmasa qator qiymatsiz ko'rinadi.

### 5.2 P14 Xavfsiz hudud

- Bitta ekran: `zoneId` bo'lsa tahrirlash (`GET .../safe-zones` dan topiladi; topilmasa "topilmadi" xabari, bo'sh forma
  ochilmaydi), aks holda yangi.
- Maydonlar: nom (1–60 belgi, bo'sh emas), markaz (xaritaga bosib; qidiruv yo'q), radius slayder 50–5000 m (sukut 200),
  "Kirganda xabar" (sukut yoqiq), "Chiqqanda xabar" (sukut o'chiq, "ko'p xabar" izohi). `iconKey` saqlanadi, tahrirlanmaydi.
- Yangi hudud bolaning oxirgi fixida ochiladi ("Markaz siz uchun qo'yildi" izohi); fix bo'lmasa xarita Toshkentda va
  "Xaritaga bosing" izohi; markaz tanlanmaguncha saqlab bo'lmaydi.
- Saqlash faqat to'g'ri va o'zgargan holatda: yangi → `POST .../children/{id}/safe-zones` (201), mavjud →
  `PUT /v1/parent/safe-zones/{zoneId}`; muvaffaqiyatda P13 ga qaytish. Idempotency-Key yuborilmaydi.
- O'chirish (faqat tahrirlashda): ikki bosqichli tasdiq → `DELETE /v1/parent/safe-zones/{zoneId}` (204); xato bo'lsa
  tasdiq holatiga qaytadi va xabar.
- Xatolar: `SAFE_ZONE_LIMIT_REACHED` → chegara matni; 403 → `plan_lock_location_title`; 404 → "topilmadi"; tarmoq →
  oflayn matni.

### 5.3 P12b Joylashuvni kuzatish

- O'qish: `GET .../rules` (`locationTracking` + `version`). Yozish: `PUT .../rules/location-tracking` `If-Match` bilan,
  tana `{isEnabled, intervalMinutes, zoneIntervalMinutes, moveMetres}` (hammasi majburiy).
- Tugma va uchta segment: oraliq {5, 10, 15, 30} daqiqa, hudud yonida {1, 3, 5} daqiqa, siljish {50, 100, 200} m.
  O'chirilganda qiymatlar saqlanadi; tanlovdan tashqari qiymat hech narsani tanlamaydi.
- Izoh: kuzatuv o'chiq bo'lsa ham "hozir so'rash" va SOS joylashuvni baribir oladi.
- Saqlash faqat o'zgarganda; to'qnashuv (412/409) → qayta o'qish + `rules_conflict_notice`, avtomatik qayta yuborish yo'q;
  muzlatilgan bola (`CHILD_NOT_ACTIVE`) → 2a dagi kabi o'zgartirib bo'lmaydi va sababi.

### 5.4 P15 SOS

- `GET /v1/parent/sos-alerts/{sosId}`; banner ma'lumoti (ism, vaqt) bilan darhol chiziladi, keyin to'ldiriladi; faqat
  xotirada. Obuna, cheklov yoki sozlama tekshiruvi yo'q.
- Sarlavha "{Ism} SOS yubordi" / nomsiz variant va vaqt (30 s da yangilanadi); faktlar — batareya %, onlayn/oflayn.
- Joylashuv kartasi: qimirlamaydigan xarita (pin + aniqlik doirasi, kritik rang), joy nomi yoki koordinatalar, "±N m",
  fix yoshi (`locationFixAt`; 4 soatdan eski → sariq + izoh; vaqt yo'q → "vaqt noma'lum"); joylashuv yo'q → "noma'lum"
  kartasi.
- Harakatlar: bolaga qo'ng'iroq (`childPhoneE164`, bo'lmasa oila ro'yxatidan; yo'q bo'lsa o'chiq + sabab); "Yo'nalish"
  (Apple Maps, joylashuv bo'lsa); favqulodda raqam — doim, konfiguratsiyadan, yo'q bo'lsa ilovadagi "112"; `tel:`
  ochilmasa `sos_action_unavailable`.
- "Ko'rdim": status `ACTIVE` bo'lsa; `POST .../acknowledge` (`Idempotency-Key: <sosId>`), ikki bosishdan himoya;
  muvaffaqiyat → "Siz {vaqt}da ko'rdingiz"; xato → `sos_acknowledge_failed` + qayta urinish. Boshqa holatlar:
  `ACKNOWLEDGED`, `CANCELLED_BY_CHILD`, `RESOLVED` izohlari.
- 404 → `sos_not_found_*` (bekor qilingan/muddati o'tgan); tarmoq xatosi va alert bor → oflayn belgisi.
- Qaytganda Home qayta yuklanadi.

## 6. Xatolar va holatlar

- Server `message` ko'rsatilmaydi; `UserMessage` ga `SAFE_ZONE_LIMIT_REACHED` qo'shiladi; 429 `retryAfterSeconds`
  bilan; 403 `SUBSCRIPTION_REQUIRED` P13/P14 da qulf matni.
- Noma'lum enum: `status`/`trigger` → noma'lum (ACTIVE emas, "ko'rdim" tugmasi chiqmaydi), `unavailableReason` → `NO_FIX`.
- Matnlar Android'dan (`location_*`, `location_tracking_*`, `safe_zone_*`, `sos_*`, `plan_lock_*`, `rules_*`); iOS
  qo'shimcha kalitlari: "faol emas" hudud belgisi va kerak bo'lsa Apple Maps yo'nalishi (iOS override sifatida).

## 7. Testlash

Swift Testing, `FakeTransport`, soxta `LocationService`, soat va kutish oralig'i in'ektsiya qilinadi (real kutish yo'q).

| Qism | Testlar |
|---|---|
| `LocationApi` | Har endpoint yo'li, metodi, tanasi; fixning 3 shakli; `isActive`; `Idempotency-Key`; 429 |
| `RuleSnapshot.locationTracking` | Bor/yo'q dekodlash; If-Match bilan yozish |
| `LocationModel` (P13) | 404/403/xato; pin + oflayn; kutish sikli (yangi fix, yangi sabab, tugash, bekor qilish, bola almashishi); `asked=false`; 429; hududlar xatosi jim |
| `SafeZoneModel` (P14) | Validatsiya, o'zgarganmi; oxirgi fixda markaz; POST/PUT; ikki bosqichli o'chirish; chegara/404 |
| `LocationTrackingModel` (P12b) | O'qish, yozish, to'qnashuv, muzlatilgan bola |
| `SosAlertModel` (P15) | Bannerdan darhol; 404; "ko'rdim" (idempotent, ikki bosish, xato); holatlar; fix yoshi; raqam yo'qligi |

Ekranlar va xarita — simulyatorda qo'lda (uch til, ikki tema, 1 va 2+ bola); qo'ng'iroq va Apple Maps — haqiqiy iPhone'da.

## 8. Ma'lum xavflar

1. **iOS ota-onaga push yo'q**: SOS faqat Home banneri va SMS eskalatsiyasi orqali bilinadi; hudud kirish-chiqish
   xabarlari iOS'da kelmaydi.
2. **Backend `placeLabel` ko'pincha bo'sh bo'lishi mumkin** (tekshirilmagan) — koordinata yoki "joy noma'lum" chiqadi.
3. **Kutish konstantalari o'lchanmagan**: 12 × 2,5 s va so'rovlar chegarasi (soatiga 20) Android'dan.
4. **Simulyatorda `tel:` ishlamaydi**; qo'ng'iroq va yo'nalish haqiqiy qurilmada tekshiriladi.
5. **Obuna cheklovlari hozir o'chiq** (`enforce-entitlements = false`); 403 yo'llari faqat testlarda tekshiriladi.
6. **Ikki xil eskirish qoidasi**: P13 — serverning `isStale` (~35 daqiqa), P15 — mijozdagi 4 soatlik chegara (Android kabi).
