# Nozir — P20: Maxfiylik va akkauntni o'chirish (iOS + backend) (dizayn)

Sana: 2026-10-07 · Holat: foydalanuvchi tasdiqladi (bo'limlar 1–3) · Repolar: `NozirIOS` (shu spec), `Nozir-Backend`

## 1. Maqsad va qamrov

Ota-ona maxfiylik ekranida nima ko'rilishi va nima ko'rilmasligini o'qiy oladi va oilaning barcha ma'lumotlarini o'chirishni so'ray oladi; so'rov 7 kundan keyin backend'da **haqiqatan** bajariladi. App Store'ning "ilova ichidan akkauntni o'chirish" talabini qoplaydi.

**Kiradi:**
- iOS: P20 ekrani (Android `feature/privacy` bilan bir xil tarkib), Profil'dan kirish, o'chirish so'rovi, so'rov holatini serverdan o'qish, so'rovdan keyin tizimdan chiqish.
- Backend: so'rovni faqat OWNER yuborishi, takror so'rovning oldini olish, so'rov yuborilganda oiladagi barcha ota-onalar sessiyalarini bekor qilish, `GET …/current`, V42 migratsiyasi, muddati o'tgan so'rovlarni bajaruvchi job.

**Kirmaydi:** so'rovni bekor qilish (Android kabi — yo'q); bola so'rovini tasdiqlash oqimi (bola so'rovi bajarilmaydi); bitta bolani o'chirish (`subject_child_id` — ota-ona yo'lida ishlatilmaydi); yakuniy xabar (Telegram/push); qayta ro'yxatdan o'tishni bloklash; hujjatlardagi umumiy saqlash (retention) joblari.

**Muvaffaqiyat mezoni:** OWNER so'rov yuborgach, oiladagi barcha ota-onalar tizimdan chiqadi; 7 kun ichida qayta kirilsa ekran "so'rov qabul qilindi, sana" ni ko'rsatadi va takror so'rov yuborib bo'lmaydi; muddat o'tgach oila, ota-onalar, bolalar, qurilmalar va ularga bog'liq barcha ma'lumotlar o'chadi, tokenlar rad etiladi, to'lov yozuvlari esa oiladan uzilgan holda qoladi; aynan shu Telegram akkaunt qayta kirsa — yangi bo'sh akkaunt.

## 2. Qarorlar (foydalanuvchi tanlagan)

| # | Savol | Qaror |
|---|---|---|
| D1 | To'lov yozuvlari | Saqlanadi, oiladan uziladi (V42: `payment_order.family_id` → nullable, `ON DELETE SET NULL`) |
| D2 | Bola so'rovi | Faqat `requested_by='PARENT'` so'rovlar bajariladi |
| D3 | Bekor qilish | Yo'q |
| D4 | Kim yubora oladi | Faqat OWNER (GUARDIAN → 403) |
| D5 | Ko'lam | Butun oila |
| D6 | So'rovdan keyin | Oiladagi **barcha** ota-onalar darhol tizimdan chiqariladi; bola qurilmalari 7 kun ishlayveradi |
| D7 | Yakuniy xabar | Yo'q, faqat `ERASURE_EXECUTED` audit |
| D8 | Qayta kirish | Yangi bo'sh akkaunt (hozirgi xatti-harakat) |
| D9 | Executor | B+A: modul eraserlari (FK'siz jadvallar) → `DELETE FROM family` (cascade) |
| D10 | Audit | Qatorlar o'chirilmaydi (1095 kun), anonimlashtiriladi |

## 3. Backend

### 3.1 V42 — `V42__erasure_execution.sql`
- `payment_order.family_id`: `DROP NOT NULL`; mavjud FK o'chirilib, `REFERENCES family(id) ON DELETE SET NULL` bilan qayta qo'shiladi (constraint nomi migratsiya yozilishida `pg_constraint`/V12 dan aniqlanadi).
- Mavjud dublikatlar: bir oilada bir nechta `PENDING`+`PARENT` so'rov bo'lsa, eng oxirgisidan boshqalari `CANCELLED` qilinadi (index'dan oldin).
- `CREATE UNIQUE INDEX uq_erasure_parent_pending ON erasure_request (family_id) WHERE status='PENDING' AND requested_by='PARENT'`.
- `CREATE INDEX idx_erasure_family_time ON erasure_request (family_id, requested_at DESC)`.
- Mavjud migratsiyalarga tegilmaydi. V41 izohidagi "V42+ close PHONE_OTP_SIGN_IN" — keyingi raqamni oladi (V43+).

### 3.2 Billing
- `PaymentOrderEntity.familyId: UUID?`. `SubscriptionActivator` `familyId == null` bo'lgan order uchun obunani faollashtirmaydi (log yozadi, xato tashlamaydi). Boshqa o'quvchilar plan bosqichida grep bilan tekshiriladi.
- `click_transaction` (order'ga cascade) va `payment_event` (payload o'zgarmaydi) saqlanadi.

### 3.3 So'rov yuborish — `POST /v1/parent/data-deletion-requests`
- OWNER tekshiruvi: `parent.role != OWNER` → 403 `FORBIDDEN` (mavjud `ForbiddenException`).
- Oilada `PENDING`+`PARENT` so'rov bo'lsa — yangisi yaratilmaydi, mavjud so'rov 202 bilan qaytadi (audit/outbox takrorlanmaydi, sessiyalar baribir bekor qilinadi). Parallel ikki so'rov: unique index buzilishi ushlanib, mavjud qator qaytariladi.
- Yangi so'rov yozilgach: oiladagi har bir faol ota-ona uchun refresh tokenlar bekor qilinadi va `token_version` oshiriladi (mavjud `RefreshTokenServiceImpl.revokeAllFor` mexanizmi; sabab uchun `ACCOUNT_DELETED` ishlatilishi mumkinmi — plan tekshiradi). Bola qurilmalariga tegilmaydi.
- Body'da `childId` berilsa 400 (D5 — ota-ona yo'li faqat butun oila). Android va iOS `{}` yuboradi.

### 3.4 `GET /v1/parent/data-deletion-requests/current`
- Har qanday ota-ona (GUARDIAN ham). Oilaning eng oxirgi `PENDING` + `PARENT` so'rovi → 200 `{requestId, status, requestedAt, executableAt}`; yo'q → 204.
- `openapi.yaml` yangilanadi.

### 3.5 Executor
- Joy: `identity` moduli (`erasure_request` va `family` uning jadvallari). Port: `platform/privacy/FamilyDataEraser { fun erase(familyId: UUID, childIds: List<UUID>) }` — `List<FamilyDataEraser>` sifatida yig'iladi; ArchUnit chegaralari saqlanadi.
- Eraserlar (FK'siz jadvallar):
  - `usage`: `DELETE FROM usage_bucket WHERE child_id = ANY(?)`.
  - `platform`: `DELETE FROM feature_flag_override WHERE family_id = ?`; `DELETE FROM outbox_message WHERE payload->>'familyId' = ? AND status <> 'PROCESSING'`; `UPDATE audit_log SET actor_id = NULL, subject_child_id = NULL, detail = '{}' WHERE family_id = ? AND action <> 'ERASURE_EXECUTED'`.
- Bitta oila — bitta tranzaksiya, tartib:
  1. `SELECT … FROM erasure_request WHERE status='PENDING' AND requested_by='PARENT' AND executable_at <= now() ORDER BY executable_at LIMIT 1 FOR UPDATE SKIP LOCKED`.
  2. Oilaning bolalari id'lari o'qiladi (o'chirilganlari ham).
  3. `ERASURE_EXECUTED` audit (familyId, requestId, requestedAt; shaxsiy ma'lumotsiz).
  4. Barcha eraserlar.
  5. `DELETE FROM family WHERE id = ?` (cascade; `erasure_request` qatori ham o'chadi — `EXECUTED` holati saqlanmaydi, isbot — audit yozuvi).
- Ishga tushirish: `@Scheduled` (interval `nozir.privacy.executor-interval`, sukut 15 daqiqa), bir yugurishda ko'pi bilan N oila (sukut 20); bitta oila xatosi — log, tranzaksiya qaytariladi, yugurishning qolgan qismi davom etadi (`SubscriptionLifecycleScanner` naqshi). Scheduled metod — test qilinadigan `runOnce(now)` ustidagi yupqa o'ram.
- App Store reviewer oilasi (V41, `f0f0f0f0-…`): executor uni o'chirmaydi — so'rov `PENDING` qoladi, WARN log. *(Reviewer akkauntining doimiyligi uchun.)*
- Tokenlar: oila o'chgach ota-ona (`ParentTokenVersionsAdapter` → null → `TOKEN_REVOKED`) va qurilma (`DeviceTokenVersions` → null → `DEVICE_UNPAIRED`) tokenlari mavjud kod bilan rad etiladi (tekshirilgan).

### 3.6 To'liqlik testi
- Unit test migratsiya fayllaridagi barcha `CREATE TABLE` nomlarini o'qiydi va har biri aynan bitta ro'yxatda ekanini tekshiradi: `CASCADES` / `ERASED_EXPLICITLY` / `GLOBAL` / `RETAINED` (`payment_order`, `payment_event`, `click_transaction`, `audit_log`). Yangi jadval ro'yxatsiz qo'shilsa test yiqiladi.

### 3.7 Testlar (repo normasi: JUnit 5 + MockK + Kotest, `Clock.fixed`, Spring kontekstsiz)
OWNER/GUARDIAN; takror so'rov; parallel so'rov (unique buzilishi); sessiyalar bekor qilinishi; GET 200/204; executor: muddati o'tmagan, CHILD so'rovi, reviewer oilasi o'tkazib yuboriladi; tartib (audit → eraserlar → family delete); bitta oila xatosi qolganlarini to'xtatmaydi; `SubscriptionActivator` null familyId; to'liqlik testi. SQL-darajadagi cascade testi yo'q (Postgres test infratuzilmasi yo'q) — bu risk sifatida qayd etiladi.

## 4. iOS

### 4.1 Tarmoq
- `GET /v1/parent/privacy/disclosure` → `PrivacyDisclosure{documentVersion, locale, seen:[{key,text}], notSeen:[{key,text}]}`.
- `POST /v1/parent/data-deletion-requests` body `{}` → 202 `ErasureRequest{requestId, executableAt, requestedAt?}`.
- `GET …/current` → 200 `ErasureRequestStatus{requestId, status, requestedAt, executableAt}` yoki 204 → `nil`.
- `ServerConfig.dataDeletionDelayDays: Int?` (yo'q bo'lsa `nil`).
- Modul joyi plan'da mavjud tuzilishga qarab aniqlanadi.

### 4.2 `PrivacyModel` (`@MainActor @Observable`)
- `load()`: disclosure va current parallel; disclosure xatosi → `loadFailure` (xato holati + "Qayta urinish"); current xatosi → `deletion = .unknown` (o'chirish bo'limi ko'rinmaydi).
- `deletion`: `.unknown`, `.idle`, `.confirming`, `.submitting`, `.requested(executableAt: Date)`.
- `isOwner` (`ParentAccount.role == "OWNER"`); GUARDIAN uchun `.idle` da tugma ko'rinmaydi, `.requested` kartasi ko'rinadi.
- `startDelete()` → `.confirming`; `cancelDelete()` → `.idle`; `confirmDelete()`: faqat `.confirming` dan (ikki marta bosish e'tiborsiz), `.submitting`; muvaffaqiyat → `onSignedOut()` (lokal tokenlar tozalanadi, server `logout` chaqirilmaydi — tokenlar allaqachon bekor); 403 / tarmoq xatosi → toast, `.idle`.
- `CancellationError` → holat tiklanadi, toast yo'q.

### 4.3 Ekran
Profil sozlamalar kartasi: "Maxfiylik" (`profileRowPrivacy`) mavzu qatoridan oldin → `ProfileStep.privacy`.
Tarkib (Android kabi): oflayn belgisi; izoh (`privacyCaptionChild(nom)` / `privacyCaptionChildren`); "Ko'riladi" kartasi (`glyphCheck`, `contentDescriptionPrivacySeen`); "Ko'rilmaydi" kartasi (`glyphCross`); `privacyPromise`; `privacyDocumentVersion(v)`; `privacyPolicyRow` (URL bo'sh bo'lmasa, Safari'da); bo'sh disclosure → `privacyDisclosureEmptyTitle/Body`.
Pastga mahkamlangan o'chirish bo'limi: `.idle` → `privacyActionDelete`; `.confirming` → kritik karta (`privacyDeleteTitle`, `privacyDeleteBodyWithDays(n)` yoki `privacyDeleteBody`, chapda `privacyDeleteCancel`, o'ngda `privacyDeleteConfirm`); `.submitting` → tugmalar o'chiq; `.requested` → diqqat kartasi (`privacyDeleteRequestedTitle`, `privacyDeleteRequestedBody(sana)`), tugmasiz.

### 4.4 Testlar
Swift Testing, soxta servis: holat o'tishlari; ikki marta bosish; current xatosi → bo'lim yashirin; current 204 → `.idle`; current PENDING → `.requested`; GUARDIAN; muvaffaqiyat → sign-out; 403 → toast + `.idle`; config kunlari yo'q → kunsiz matn.

## 5. Ochiq risklar
1. To'lov va audit yozuvlarini saqlash muddati — buxgalter/yurist bilan tasdiqlanmagan; `payment_event.payload` ichida shaxsiy ma'lumot bor-yo'qligi noma'lum.
2. Cascade'ning haqiqiy Postgres'dagi to'liqligi faqat to'liqlik testi va qo'lda sinov bilan tekshiriladi.
3. `outbox_message.payload` da `familyId` kalitisiz shaxsiy ma'lumot bo'lishi mumkin (masalan faqat `parentId`) — plan topic'larni ko'rib chiqadi.
4. Ko'p instance: executor `SKIP LOCKED` bilan xavfsiz, ShedLock kerak emas.

## 6. Plan bosqichidagi aniqliklar (kod bilan tekshirilgan, ushbu bo'limlar yuqoridagidan ustun)
- `family`/`child` jadvallari `family` moduliga tegishli: executor ularga `FamilyRegistry` porti (`childIdsOf`, `deleteFamily`) orqali murojaat qiladi.
- Takror so'rov: unique buzilishini ushlash Postgres tranzaksiyasini buzadi — `INSERT … ON CONFLICT … DO NOTHING`, keyin mavjud PENDING qator o'qiladi.
- `revokeAllFor` sababni `LOGOUT` deb qattiq yozadi — POST `ACCOUNT_DELETED` sababi bilan alohida chaqiruv + `token_version` oshirish ishlatadi. OWNER tekshiruvi saqlangan `parent_account.role` bo'yicha.
- Executor: yugurish boshida N ta muddati o'tgan id o'qiladi, har biri o'z tranzaksiyasida qulflanadi (xato beradigan oila qolganlarini to'sib qo'ymaydi). So'rovlar `subject_child_id IS NULL` shartini ham talab qiladi; V42 eski bola-ko'lamli PENDING ota-ona so'rovlarini `CANCELLED` qiladi.
- Reviewer himoyasi: `f0f0f0f0-0000-4000-8000-000000000001` oilasi YOKI telefoni `DevProperties.isFixedOtpPhone` ga mos ota-onasi bor oila (V41 mavjud oilani qayta ishlatishi mumkin).
- Outbox: qatorlar `familyId` bo'yicha va har bir bolaning `childId` si bo'yicha o'chiriladi (`PROCESSING` dan tashqari).
- To'liqlik testi beshinchi ro'yxatga ega: `EXPIRES_ON_ITS_OWN` (`idempotency_record`).
- iOS: `ParentAccount` saqlanmaydi — rol `GET /v1/parent/me` dan olinadi (`load()` uchta parallel so'rov); 204 uchun `ApiClient.sendUnlessNoContent` qo'shiladi; yangi `NozirPrivacy` moduli.
