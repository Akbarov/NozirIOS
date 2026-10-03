# Nozir iOS (ota-ona ilovasi) — 1-sub-loyiha: Poydevor

- **Sana:** 2026-10-03
- **Holat:** dizayn, foydalanuvchi ko'rib chiqishini kutmoqda
- **Manba:** `Nozir_iOS_Parent_Handover.md`, `Nozir-Backend` (`docs/api/openapi.yaml`,
  `docs/architecture/AUTH_AND_TOKENS.md`, `identity/*`, `serverconfig/*`, `platform/api/*`),
  `NozirParent` (`core/network`, `core/designsystem`)

---

## 1. Maqsad

iOS ota-ona ilovasi uchun keyingi barcha ekranlar quriladigan poydevor: Xcode loyiha,
CI, tarmoq qatlami, Telegram orqali kirish, token rotatsiyasi va majburiy yangilanish
darvozasi. Muvaffaqiyat mezoni:

1. Ota-ona iPhone'da Telegram orqali kirib, bo'sh Home o'rinbosarini ko'radi.
2. Ilova qayta ochilganda qayta kirish so'ramaydi (refresh token Keychain'da).
3. Backend `updateRequired = true` qaytarsa, "Yangilang" devori chiqadi.
4. Barcha mantiq testlar bilan qoplangan va CI (macOS runner) yashil.

## 2. Qabul qilingan qarorlar

| Mavzu | Qaror | Izoh |
|---|---|---|
| Texnologiya | Native SwiftUI | KMP/Compose MP rad etildi (handover 4.3) |
| Minimal iOS | 17 | `@Observable` (Observation) ishlatiladi |
| Kirish | Faqat Telegram | Android bilan bir xil akkaunt. Telefon OTP — faqat review test raqami uchun, iOS UI'da yo'q |
| Obuna | StoreKit 2 IAP, v1'da | Alohida sub-loyiha (4-band); bu spec qamrovidan tashqari |
| Loyiha tuzilmasi | Yupqa Xcode ilova + lokal Swift Package `NozirKit` | `.pbxproj` ni qo'lda tahrirlash yo'q |
| Tarmoq | Qo'lda URLSession + Codable | Generator yo'q; JSON fixture testlari bilan |
| Testlar | Swift Testing (Xcode 16+) | Eski Xcode bo'lsa XCTest |
| Tekshiruv | GitHub Actions macOS runner + foydalanuvchining lokal Xcode'i | Claude Swift kompilyatsiya qila olmaydi |
| Joylashuv | `~/XCodeProjects/NozirIOS`, alohida git repo | Android repolariga tegilmaydi |

## 3. Butun iOS loyihasining bo'linishi

Har bir sub-loyiha o'z spec → reja → implementatsiya tsikliga ega.

1. **Poydevor** — *ushbu spec*.
2. **Asosiy ekranlar:** P03/P03b/P04 (bola qo'shish, juftlash), P05–P12, P16–P18, P20–P21.
3. **Xavfsizlik va joylashuv:** P12b, P13, P14, P15 (SOS), P16a + APNs (backend
   `ApnsPushSender` haqiqiy transportga aylanadi, `.p8` kalit).
4. **Obuna:** P19 + StoreKit 2 + backendda `APPLE` to'lov kanali (yangi Flyway
   migration, raqami o'sha paytda `origin/main` dan tekshiriladi) + App Store Server
   Notifications V2 + tranzaksiya tekshiruvi.

## 4. Qamrov

**Kiradi:** Xcode ilova target'i, `NozirKit` paketi (5 target), CI, P01 Welcome,
P02 Sign in (Telegram), "Yangilang" devori, Home o'rinbosari, chiqish (logout).

**Kirmaydi:** 3-bo'limdagi boshqa barcha ekranlar, push, IAP, xarita, lokalizatsiya
uchun o'zbekchadan boshqa tillar, UI testlar.

## 5. Arxitektura

### 5.1 Repo tuzilmasi

```
NozirIOS/
├── NozirIOS.xcodeproj           # foydalanuvchi Xcode'da bir marta yaratadi
├── NozirIOS/                    # ilova target'i: faqat @main va kompozitsiya ildizi
│   ├── NozirIOSApp.swift
│   ├── Config/Debug.xcconfig
│   ├── Config/Release.xcconfig
│   └── Assets.xcassets
├── NozirKit/                    # lokal Swift Package
│   ├── Package.swift
│   ├── Sources/<Target>/...
│   └── Tests/<Target>Tests/...  (+ Fixtures/*.json)
├── .github/workflows/verify.yml
└── docs/superpowers/{specs,plans}/
```

Xcode loyihasini mavjud papka ichida yaratishning aniq tartibi reja bosqichida
yoziladi (Xcode yangi loyiha uchun o'z papkasini yaratadi — ziddiyat bo'lmasligi
kerak).

### 5.2 `NozirKit` targetlari

| Target | Vazifasi | Bog'liqligi |
|---|---|---|
| `NozirNetworking` | `ApiClient` (URLSession), `ApiRequest`, `ApiResult`, `ApiFailure`, `ErrorResponse` dekoderi, `X-Nozir-Client` sarlavhasi, ISO-8601 sanalar | — |
| `NozirAuth` | `TokenStore` protokoli (+ Keychain va xotiradagi implementatsiya), `TokenRefresher` (actor), autentifikatsiyali transport, `SignInProvider` protokoli va uning yagona implementatsiyasi `TelegramSignIn` | Networking |
| `NozirConfig` | `ServerConfigService` (`/v1/config`), kesh, `UpdateGate` | Networking |
| `NozirDesignSystem` | Ranglar, tipografiya, oraliqlar, tugmalar — Android `core/designsystem` (`NozirLightColors`, `NozirDarkColors`, `NozirTypography`, `NozirSpacing`, `NozirShapes`) qiymatlaridan ko'chiriladi | — |
| `NozirAppFeature` | `AppState` holat mashinasi, P01/P02/devor/Home view'lari va ViewModel'lari | hammasi |

Nomlar Android tushunchalariga mos (`ApiRequest`, `ApiResult`, `ApiFailure`), lekin
kod Swift idiomlarida yoziladi.

### 5.3 Muhit

- Base URL `Info.plist` ← `.xcconfig` orqali. Release: `https://nozir.syncoder.uz`
  (Android `productionApiBaseUrl` bilan bir xil). Debug: sukut bo'yicha xuddi shu,
  lokal backend uchun `Debug.xcconfig` da qayta belgilanadi.
- Sirlar va API kalitlari kodga yozilmaydi.

## 6. Ma'lumot oqimi

### 6.1 Ishga tushish

1. `GET /v1/config?clientKind=PARENT_IOS`, sarlavha
   `X-Nozir-Client: nozir-parent/<CFBundleShortVersionString> (ios; <iOS versiyasi>)`.
   Autentifikatsiyasiz (openapi: `security: []`).
2. `updateRequired == true` → `AppState.updateRequired` (App Store havolasi bilan devor).
3. Config olinmasa: keshdagi oxirgi qiymat; kesh ham bo'lmasa — ilova **ochiq qoladi**
   (backend `ClientVersions`: "noto'g'ri sarlavha qulflamasin" tamoyili).
4. Keychain'da refresh token bor → `signedIn`, yo'q → `signedOut` (P01).
5. Fonda 1 soatdan ortiq turib qaytganda config qayta olinadi (openapi tavsifi).
   Kesh muddati `Cache-Control: max-age` dan olinadi.

`UNSUPPORTED_CLIENT_VERSION` backendda e'lon qilingan, lekin hech qayerda
qaytarilmaydi — darvoza faqat `/v1/config` orqali.

### 6.2 Telegram orqali kirish (P02)

1. `POST /v1/auth/telegram/start` → `{ botUsername, deepLink, codeLength, codeTtlSeconds }`.
   503 (`UPSTREAM_UNAVAILABLE`) → tugma o'chiriladi, "vaqtincha mavjud emas" matni.
2. `deepLink` `UIApplication.open` bilan ochiladi (Telegram o'rnatilmagan bo'lsa
   brauzerda t.me).
3. Ota-ona botga raqamini ulashadi, bot kod yuboradi.
4. Ilovada `codeLength` xonali maydon va `codeTtlSeconds` bo'yicha amal qilish muddati.
5. `POST /v1/auth/telegram/verify { code, deviceLabel }`. `deviceLabel = UIDevice.current.model`
   (qurilma nomi shaxsiy ma'lumot, yuborilmaydi).
6. `ParentAuthResponse` → tokenlar Keychain'ga, `parent` xotiraga → `signedIn`.
7. Noto'g'ri kod: `OTP_CODE_INVALID` (backend noto'g'ri/eskirgan/mavjud emasni
   ajratmaydi — ilova ham ajratmaydi). `RATE_LIMITED` → `retryAfterSeconds` ko'rsatiladi.

### 6.3 Autentifikatsiyali so'rov va refresh

- Har so'rovga `Authorization: Bearer <access>`.
- Access tokenning `accessTokenExpiresAt` gacha 30 soniyadan kam qolsa — so'rovdan
  **oldin** refresh.
- 401 (`TOKEN_EXPIRED`) → bitta refresh → so'rov bir marta qayta yuboriladi.
  Ikkinchi 401 qayta urinilmaydi.
- `TokenRefresher` — `actor`. Bir vaqtda kelgan barcha refresh talablari **bitta**
  ichki `Task` ni kutadi; backendga bitta `POST /v1/auth/token/refresh` boradi.
  Sabab: rotatsiya qilingan refresh token qayta yuborilsa backend butun lineage'ni
  bekor qiladi (`RefreshTokenServiceImpl.onReuseDetected`).
- Refresh `TOKEN_REVOKED` / `INVALID_TOKEN` / `TOKEN_EXPIRED` bilan rad etilsa —
  Keychain tozalanadi, `signedOut`.
- Tarmoq xatosida tokenlar **o'chirilmaydi**.

### 6.4 Chiqish

`POST /v1/auth/logout` (204). Javobdan qat'i nazar Keychain tozalanadi va `signedOut`.

## 7. Xatolar

- `ApiFailure`:
  - `.server(code: ApiErrorCode, message, field, violations, retryAfterSeconds, traceId, status)`
  - `.network(URLError)`
  - `.decoding`
  - `.unexpectedStatus(Int)` — tanasi `ErrorResponse` bo'lmagan non-2xx
- `ApiErrorCode` — backend `ErrorCode` enum'ining nusxasi, noma'lum qiymat uchun
  `.unknown(String)` (yangi kod qo'shilsa dekod sinmasligi kerak).
- Server `message` foydalanuvchiga **hech qachon** ko'rsatilmaydi (backend `ApiError`
  izohi). Foydalanuvchi matnlari o'zbekcha, ilova resurslarida.
- `traceId` support uchun saqlanadi (ko'rsatilishi xavfsiz — backend izohi).

## 8. Qattiq qoidalar

- **SOS (P15) hech qachon to'silmaydi** — na obuna, na majburiy yangilanish devori.
  Poydevorda SOS yo'q, lekin `UpdateGate` "darvozadan ozod" belgisini qo'llab-quvvatlaydi
  va buning testi bor.
- Refresh faqat `TokenRefresher` orqali, boshqa joyda emas.
- Tokenlar faqat Keychain'da (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`);
  UserDefaults'da emas, logga yozilmaydi.

## 9. Testlash

Swift Testing. Ilova target'ida test yo'q; hamma test `NozirKit` ichida.

| Qatlam | Nima tekshiriladi |
|---|---|
| Networking | `URLProtocol` stub bilan: sarlavhalar, sana formati, `ErrorResponse` → `ApiFailure`, noma'lum `ErrorCode` |
| Kontrakt fixture'lari | `Tests/Fixtures/*.json` — `AuthDtos.kt`, `ServerConfigApi.kt` maydonlari bo'yicha; har DTO dekod qilinadi |
| `TokenRefresher` | 5 parallel so'rov → 1 refresh; revoked → `signedOut`; tarmoq xatosi → tokenlar saqlanadi; 401 → refresh → retry, ikkinchi 401 → to'xtash; muddat yaqin → oldindan refresh |
| `TelegramSignIn` | 503 → o'chirilgan holat; muvaffaqiyat → tokenlar saqlanadi; `OTP_CODE_INVALID`, `RATE_LIMITED` |
| `UpdateGate` / `AppState` | config xato + kesh yo'q → ochiq; `updateRequired` → devor; ozod ekran → devor yo'q; token bor/yo'q → to'g'ri boshlang'ich holat |
| Keychain | Simulyatorda bitta integratsiya testi (yozish/o'qish/o'chirish) |
| UI | Hozircha yo'q (YAGNI); view'lar faqat ViewModel holatini chizadi |

TDD: test yoziladi → CI yoki lokal Xcode'da **qizil** ekani ko'riladi → implementatsiya
→ **yashil**. Har bir qadamning dalili — CI logi yoki foydalanuvchi yuborgan natija.

## 10. CI

`.github/workflows/verify.yml` (Android repolaridagi nom bilan bir xil):

- `push` va `pull_request` da, macOS runner.
- Xcode versiyasi `xcode-select` bilan aniq belgilanadi.
- `xcodebuild test -scheme NozirKit -destination 'platform=iOS Simulator,…'`.
- `xcodebuild build` — ilova target'i.

Runner image'dagi aniq Xcode va simulyator nomlari reja bosqichida GitHub
hujjatlaridan tekshiriladi (o'zgarib turadi).

## 11. Ma'lum xavflar

1. **App Review 4.8 (Login Services).** Apple qoidasiga ko'ra uchinchi tomon ijtimoiy
   login ishlatilsa, unga teng muqobil (faqat ism/email, emailni yashirish, reklama
   kuzatuvisiz) taklif qilinishi kerak. Telegram shu toifaga tushadi deb hisoblayman
   (talqin, Apple tasdig'i emas). Foydalanuvchi hozircha faqat Telegram'ni tanladi.
   Rad etilsa: Sign in with Apple alohida qo'shiladi (backend: `parent_account` ga
   Apple identifikatori, yangi migration, yangi endpoint). Kirish qatlami
   (`SignInProvider` chegarasi) buni mavjud kodni buzmasdan qo'shishga imkon beradi.
2. **App Review 3.1.1 / 3.1.3(b).** Android/Click/Payme orqali olingan PRO iOS'da
   ochilishi uchun o'sha obuna iOS'da IAP sifatida ham sotilishi shart. 4-sub-loyiha
   tugamaguncha iOS ilova App Store'ga yuborilmaydi.
3. **Tekshirib bo'lmaydigan kod.** Claude muhitida Swift/Xcode yo'q (swift.org proxy
   tomonidan bloklangan). CI yoki lokal Xcode tasdiqlamaguncha kod "yozildi,
   tekshirilmagan" hisoblanadi.
4. **Handover'dagi tekshirilmagan tasdiq.** Apple qoidalari 2026-10-03 da
   developer.apple.com'dan o'qildi; sahifada yangilanish sanasi ko'rsatilmagan.

## 12. Foydalanuvchi bilan hal qilingan savollar (2026-10-03)

| Savol | Javob | Oqibati |
|---|---|---|
| Lokal Xcode | 26.6 (17F113) | Swift Testing mavjud. CI'dagi Xcode versiyasi ham shunga yaqin tanlanadi |
| Bundle ID | `tut.mobile.nozirparent` | Android `applicationId` bilan bir xil |
| Apple Developer Program | Hozircha yo'q, keyin olinadi | Poydevor faqat simulyatorda tekshiriladi; CI'da imzolash o'chiriladi (`CODE_SIGNING_ALLOWED=NO`). Haqiqiy qurilma, TestFlight, APNs va IAP a'zolikdan keyin |
| GitHub repo | `NozirIOS`, foydalanuvchi o'zi yaratadi va push qiladi | CI repo push qilingandan keyin ishlaydi; ungacha dalil — lokal Xcode |
| P01/P02 dizayni | Android bilan bir xil | Ranglar, tipografiya, oraliqlar va ekran tarkibi `NozirParent` dagi Compose kodidan (`core/designsystem`, `feature/welcome`, `feature/signin`) ko'chiriladi. To'liq iOS uslubiga o'tish — keyinroq, alohida qaror |

## 13. Reja bosqichidagi aniqlashtirishlar

Implementatsiya rejasi (`docs/superpowers/plans/2026-10-03-nozir-ios-foundation.md`,
"Spec'dan aniqlashtirishlar" jadvali) quyidagilarni aniqlashtirdi; ular shu spec'ning
tegishli bandlari o'rnini bosadi:

- Base URL: `.xcconfig` o'rniga ilova target'idagi `ApiHost` (Release — doimiy host,
  Debug — `NOZIR_API_BASE_URL` muhit o'zgaruvchisi).
- Config keshi `Cache-Control` bo'yicha emas, **ilova versiyasi bo'yicha** kalitlanadi.
- Tarmoq testlari `URLProtocol` o'rniga `HTTPTransport` fake'i bilan.
- `ApiErrorCode` — `RawRepresentable` struct.
- `SignInProvider` o'rniga `TelegramSignInService`; yangi provayder `TokenStore.save` orqali qo'shiladi.
- Fixture'lar test fayllari ichida.
- App Store havolasi App Store ID paydo bo'lguncha yo'q.

