# Nozir iOS — Poydevor: Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ota-ona iPhone'da Telegram orqali kirib, bo'sh Home o'rinbosarini ko'radigan, majburiy yangilanish darvozasi va token rotatsiyasi ishlaydigan, testlar bilan qoplangan iOS poydevorini qurish.

**Architecture:** Yupqa Xcode ilova target'i (`NozirIOS`) faqat `@main` va host tanlovini saqlaydi. Barcha mantiq lokal Swift Package `NozirKit` ichida: `NozirNetworking` (URLSession ustidagi yupqa klient), `NozirAuth` (Keychain, `TokenRefresher` actor, Telegram kirish), `NozirConfig` (`/v1/config`, kesh, `UpdateGate`), `NozirDesignSystem` (Android tokenlari), `NozirAppFeature` (holat mashinasi, ekranlar, kompozitsiya ildizi).

**Tech Stack:** Swift 6 (language mode 6), SwiftUI, Observation (`@Observable`), Swift Testing, iOS 17+, Xcode 26.6 (17F113), GitHub Actions `macos-26`. Tashqi bog'liqlik yo'q.

**Spec:** `docs/superpowers/specs/2026-10-03-nozir-ios-foundation-design.md`

## Global Constraints

- Minimal iOS: **17.0**. `Package.swift`: `// swift-tools-version: 6.0`, `platforms: [.iOS(.v17)]`.
- Bundle ID: **`tut.mobile.nozirparent`**.
- `X-Nozir-Client` qiymati aynan: `nozir-parent/<CFBundleShortVersionString> (ios; <UIDevice.systemVersion>)`.
- `/v1/config` so'rovida `clientKind=PARENT_IOS`.
- Release API host: **`https://nozir.syncoder.uz`** (Android `productionApiBaseUrl` bilan bir xil).
- Tokenlar faqat Keychain'da, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. UserDefaults'ga, logga yozilmaydi.
- Refresh faqat `TokenRefresher` orqali; bir vaqtda bitta refresh so'rovi.
- Server `message` matni foydalanuvchiga **hech qachon** ko'rsatilmaydi. Foydalanuvchi matnlari faqat `Copy.swift` da, o'zbekcha.
- Majburiy yangilanish devori SOS'ni (kelajakdagi P15) to'smaydi: `UpdateGate.blocks(_:isExempt:)`.
- Tashqi Swift paketlari qo'shilmaydi.
- Dizayn Android `NozirParent` bilan bir xil (ranglar, o'lchamlar, matnlar shu rejada ko'chirilgan).
- Tashqi bog'liqlik sifatida Apple Developer akkaunti yo'q: faqat simulyator, CI'da `CODE_SIGNING_ALLOWED=NO`.

### Tekshiruv protokoli (har bir "Run" qadami)

Claude muhitida Swift/Xcode yo'q. Har bir "Run" qadamini **foydalanuvchi** o'z Mac'ida bajaradi va chiqishni chatga yuboradi:

```bash
cd ~/XCodeProjects/NozirIOS && ./scripts/test.sh <TestTarget>
```

- "FAIL kutiladi" qadamida: `** TEST FAILED **` yoki kompilyatsiya xatosi (`error: cannot find '…' in scope`) — bu Swift'da "qizil" hisoblanadi.
- "PASS kutiladi" qadamida: `** TEST SUCCEEDED **`.
- Natija kutilganidan farq qilsa — **superpowers:systematic-debugging**, taxmin bilan tuzatish yo'q.
- Chiqish olinmaguncha qadam bajarilgan deb belgilanmaydi va "ishlaydi" deyilmaydi.

### Commit protokoli (har bir "Commit" qadami)

Claude `device_bash` orqali, `~/XCodeProjects/NozirIOS` ichida:

```bash
export GIT_AUTHOR_NAME=Zohidjon GIT_AUTHOR_EMAIL=zohidjonakbarov@gmail.com GIT_COMMITTER_NAME=Zohidjon GIT_COMMITTER_EMAIL=zohidjonakbarov@gmail.com
git status --short
git add <faqat qadamda sanalgan yo'llar>
git commit -F - <<'EOF'
<xabar>

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01U1bZYS4K1J2adZnrDTm3Pp
EOF
rm -f .git/index.lock .git/HEAD.lock; find .git/objects -name 'tmp_obj_*' -delete
```

`git add -A` ishlatilmaydi. Push'ni foydalanuvchi qiladi.

## Spec'dan aniqlashtirishlar (reja bosqichida qabul qilingan)

| Spec | Reja | Sabab |
|---|---|---|
| Base URL `.xcconfig` + `Info.plist` orqali (5.3) | `NozirIOS/ApiHost.swift`: Release'da doimiy host; Debug'da `NOZIR_API_BASE_URL` muhit o'zgaruvchisi (scheme'da) | `.xcconfig` da `//` izoh hisoblanadi va Info.plist'ni qo'lda sozlash kerak bo'ladi; Android ham bitta hostga ega |
| Config keshi `Cache-Control` bo'yicha (6.1) | Config faqat ishga tushishda va fonda >1 soatdan keyin olinadi; kesh **ilova versiyasi bo'yicha kalitlanadi** | `max-age` ishlatiladigan joy qolmaydi; eski versiyaning `updateRequired=true` keshi yangilangan ilovani qulflamasligi kerak |
| `URLProtocol` stub bilan haqiqiy URLSession (9) | `HTTPTransport` protokoli + `FakeTransport` actor; `URLSessionTransport` (8 qator) Task 13 dagi qo'lda E2E bilan tekshiriladi | Swift Testing testlari parallel ishlaydi; `URLProtocol` ning global holati poyga yaratadi |
| `ApiErrorCode` enum + `.unknown` (7) | `struct ApiErrorCode: RawRepresentable` + statik konstantalar | Noma'lum kod tabiiy ravishda saqlanadi, maxsus dekoder kerak emas |
| `SignInProvider` protokoli (5.2, 11) | `TelegramSignInService` protokoli; yangi provayder uchun kengayish nuqtasi — `TokenStore.save(_:)` | Telegram oqimi ikki bosqichli va o'ziga xos; umumiy protokol bitta implementatsiya uchun ortiqcha |
| `Tests/Fixtures/*.json` (9) | Fixture'lar test fayllari ichida raw string sifatida | Resurs bundle yo'llari bilan bog'liq xatolar yo'q; backend fayl/qatoriga havola izohda |
| App Store havolasi | `appStoreURL: URL?` = `nil` (App Store ID hali yo'q); bosilganda "qo'lda yangilang" matni | Apple Developer akkaunti yo'q |

## Review Focus

1. **Server sanalari 6–9 kasr xonali yoki `+05:00` bilan keladi** (Jackson `Instant`) — dekod sinmasligi kerak. Pin: Task 3.
2. **Base URL oxirida `/` bo'lsa** — `https://host//v1/config` hosil bo'lmasligi kerak. Pin: Task 5.
3. **Ilova yangilangandan keyin internetsiz ochilsa**, eski versiyaning keshidagi `updateRequired=true` yangi ilovani qulflamasligi kerak. Pin: Task 9.
4. **Kod joy tashlab, chiziqcha bilan yoki boshqa yozuvdagi raqamlar bilan qo'yilsa** (`"123 456"`, `"١٢٣"`), uzunlikdan oshsa — faqat ASCII raqamlar, `codeLength` gacha. Pin: Task 11.
5. **Bir vaqtda kelgan 401'lar va allaqachon rotatsiya qilingan token bilan 401** — backendga faqat bitta refresh boradi (aks holda reuse-detection butun sessiyani o'chiradi). Pin: Task 7.

## Fayl xaritasi

```
NozirIOS/                                   (repo ildizi)
├── .gitignore
├── .github/workflows/verify.yml            Task 2
├── scripts/test.sh                         Task 1
├── NozirIOS.xcodeproj                      Task 1 (Xcode yaratadi)
├── NozirIOS/
│   ├── NozirIOSApp.swift                   Task 1, Task 13
│   ├── ApiHost.swift                       Task 13
│   └── Assets.xcassets                     (Xcode yaratadi)
└── NozirKit/
    ├── Package.swift                       Task 1, 6, 9, 12 (targetlar qo'shiladi)
    ├── Sources/
    │   ├── NozirNetworking/
    │   │   ├── ClientIdentity.swift        Task 1
    │   │   ├── RFC3339.swift               Task 3
    │   │   ├── NozirJSON.swift             Task 3
    │   │   ├── ApiErrorCode.swift          Task 4
    │   │   ├── ApiError.swift              Task 4
    │   │   ├── ApiFailure.swift            Task 4
    │   │   ├── ApiRequest.swift            Task 5
    │   │   ├── HTTPTransport.swift         Task 5
    │   │   ├── AccessTokenProvider.swift   Task 5
    │   │   └── ApiClient.swift             Task 5
    │   ├── NozirAuth/
    │   │   ├── TokenPair.swift             Task 6
    │   │   ├── TokenStore.swift            Task 6
    │   │   ├── KeychainTokenStore.swift    Task 6
    │   │   ├── TokenRefresher.swift        Task 7
    │   │   ├── AuthModels.swift            Task 8
    │   │   ├── AuthApi.swift               Task 8
    │   │   └── TelegramSignIn.swift        Task 8
    │   ├── NozirConfig/
    │   │   ├── ServerConfig.swift          Task 9
    │   │   ├── ConfigApi.swift             Task 9
    │   │   ├── ConfigCache.swift           Task 9
    │   │   ├── ConfigLoader.swift          Task 9
    │   │   └── UpdateGate.swift            Task 9
    │   ├── NozirDesignSystem/
    │   │   ├── NozirColor.swift            Task 12
    │   │   ├── NozirMetrics.swift          Task 12
    │   │   ├── NozirText.swift             Task 12
    │   │   └── Components/*.swift          Task 12
    │   └── NozirAppFeature/
    │       ├── RootView.swift              Task 1, Task 13
    │       ├── AppModel.swift              Task 10
    │       ├── Copy.swift                  Task 11
    │       ├── UserMessage.swift           Task 11
    │       ├── SignInModel.swift           Task 11
    │       ├── AppEnvironment.swift        Task 13
    │       └── Screens/*.swift             Task 13
    └── Tests/
        ├── NozirTestSupport/               Task 5 (oddiy target, faqat testlar uchun)
        │   ├── FakeTransport.swift
        │   └── HTTP.swift
        ├── NozirNetworkingTests/           Task 1, 3, 4, 5
        ├── NozirAuthTests/                 Task 6, 7, 8
        ├── NozirConfigTests/               Task 9
        ├── NozirDesignSystemTests/         Task 12
        └── NozirAppFeatureTests/           Task 10, 11
```

---
### Task 1: Repo skeleti — `NozirKit` paketi, Xcode ilova, birinchi yashil test

**Files:**
- Create: `.gitignore`
- Create: `scripts/test.sh`
- Create: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirNetworking/ClientIdentity.swift`
- Create: `NozirKit/Sources/NozirAppFeature/RootView.swift` (o'rinbosar, Task 13 da almashtiriladi)
- Test: `NozirKit/Tests/NozirNetworkingTests/ClientIdentityTests.swift`
- Create (Xcode orqali, foydalanuvchi): `NozirIOS.xcodeproj`, `NozirIOS/NozirIOSApp.swift`, `NozirIOS/Assets.xcassets`
- Delete: `NozirIOS/ContentView.swift` (Xcode shabloni)

**Interfaces:**
- Produces: `public struct ClientIdentity: Sendable, Equatable { init(appVersion: String, osVersion: String); var headerValue: String }`; `public struct RootView: View { public init() }` (vaqtinchalik).

- [ ] **Step 1: `.gitignore` va test skriptini yozish**

`.gitignore`:

```gitignore
.DS_Store
xcuserdata/
*.xcuserstate
DerivedData/
.build/
NozirKit/.swiftpm/
```

`scripts/test.sh`:

```bash
#!/usr/bin/env bash
# Runs the NozirKit test suite on an iOS simulator and prints the tail of the log.
# Usage: ./scripts/test.sh [TestTarget]   e.g. ./scripts/test.sh NozirNetworkingTests
set -euo pipefail
cd "$(dirname "$0")/../NozirKit"
SCHEME="${NOZIR_SCHEME:-NozirKit-Package}"
DESTINATION="${NOZIR_DESTINATION:-platform=iOS Simulator,name=iPhone 17}"
ONLY=()
if [[ $# -gt 0 ]]; then ONLY=(-only-testing:"$1"); fi
# ${ONLY[@]+...}: macOS ships bash 3.2, where an empty array under `set -u` is an error.
xcodebuild test -scheme "$SCHEME" -destination "$DESTINATION" ${ONLY[@]+"${ONLY[@]}"} 2>&1 | tail -60
```

Keyin: `chmod +x scripts/test.sh`.

- [ ] **Step 2: `Package.swift` yozish**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NozirKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "NozirAppFeature", targets: ["NozirAppFeature"]),
    ],
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking"]),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking"]),
    ]
)
```

- [ ] **Step 3: Failing test yozish**

`NozirKit/Tests/NozirNetworkingTests/ClientIdentityTests.swift`:

```swift
import Testing
@testable import NozirNetworking

@Suite struct ClientIdentityTests {
    // Backend ClientVersions.parseVersion reads the text between "/" and the
    // first space, so the version must sit exactly there.
    @Test func headerNamesTheParentAppAndIOS() {
        let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
        #expect(identity.headerValue == "nozir-parent/1.0.0 (ios; 17.5)")
    }
}
```

`NozirKit/Sources/NozirAppFeature/RootView.swift` (paket kompilyatsiya bo'lishi uchun; mantiqsiz o'rinbosar):

```swift
import SwiftUI

/// Placeholder until Task 13 wires the real flow.
public struct RootView: View {
    public init() {}

    public var body: some View {
        Text("Nozir")
    }
}
```

`NozirNetworking` target'ida hali fayl yo'q — SPM bo'sh target'ni rad etadi, shuning uchun Step 5 gacha kompilyatsiya xatosi kutiladi (bu "qizil").

- [ ] **Step 4: Scheme nomini aniqlash va testni ishga tushirish (FAIL kutiladi)**

Foydalanuvchi:

```bash
cd ~/XCodeProjects/NozirIOS/NozirKit && xcodebuild -list
```

Kutilgan: schemes ro'yxatida `NozirKit-Package`. Agar boshqa nom bo'lsa (masalan faqat `NozirKit`), foydalanuvchi uni aytadi va Claude `scripts/test.sh` dagi `SCHEME` sukutini o'sha nomga almashtiradi. Bu nom Task 2 dagi CI'da ham ishlatiladi.

Keyin: `cd ~/XCodeProjects/NozirIOS && ./scripts/test.sh NozirNetworkingTests`
Kutilgan: FAIL — `NozirNetworking` target'ida manba yo'qligi yoki `cannot find 'ClientIdentity' in scope`.

Simulyator nomi topilmasa: `xcrun simctl list devices available | grep iPhone` chiqishini yuboring; Claude `NOZIR_DESTINATION` sukutini mavjud qurilmaga almashtiradi.

- [ ] **Step 5: Minimal implementatsiya**

`NozirKit/Sources/NozirNetworking/ClientIdentity.swift`:

```swift
/// What this app is and what it runs on, sent as `X-Nozir-Client`.
///
/// Drives the server's minimum-version gate. It carries no device identifier
/// and must never become one: the OS version is a coarse class, not a name.
public struct ClientIdentity: Sendable, Equatable {
    public let appVersion: String
    public let osVersion: String

    public init(appVersion: String, osVersion: String) {
        self.appVersion = appVersion
        self.osVersion = osVersion
    }

    public var headerValue: String {
        "nozir-parent/\(appVersion) (ios; \(osVersion))"
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `** TEST SUCCEEDED **`, `headerNamesTheParentAppAndIOS` passed.

- [ ] **Step 7: Xcode ilova loyihasini yaratish (foydalanuvchi)**

1. Xcode → File → New → Project… → iOS → **App** → Next.
2. Product Name: `NozirIOS`. Team: None. Organization Identifier: `tut.mobile`. Interface: **SwiftUI**. Language: **Swift**. Testing System (agar bo'lsa): **None**. Storage: **None**.
3. Saqlash joyi: `~/XCodeProjects/_xcode_new` (yangi papka yarating). **"Create Git repository" belgisini olib tashlang.**
4. Xcode'ni yoping.

- [ ] **Step 8: Xcode fayllarini repo ildiziga ko'chirish (Claude, `device_bash`)**

```bash
cd "$HOME/mnt/XCodeProjects"
ls _xcode_new/NozirIOS
mv -n _xcode_new/NozirIOS/NozirIOS.xcodeproj NozirIOS/
mv -n _xcode_new/NozirIOS/NozirIOS NozirIOS/
ls -A _xcode_new/NozirIOS   # bo'sh bo'lishi kerak
rmdir _xcode_new/NozirIOS _xcode_new
ls NozirIOS
```

Kutilgan oxirgi chiqish: `.git .gitignore NozirIOS NozirIOS.xcodeproj NozirKit docs scripts`. `mv -n` to'qnashuvda jim o'tkazib yuboradi — shuning uchun `ls` bilan tekshiriladi.

- [ ] **Step 9: Loyihani sozlash (foydalanuvchi)**

`~/XCodeProjects/NozirIOS/NozirIOS.xcodeproj` ni oching:

1. Target **NozirIOS** → General → Minimum Deployments: **iOS 17.0**. Identity → Bundle Identifier: **`tut.mobile.nozirparent`**.
2. File → Add Package Dependencies… → **Add Local…** → `~/XCodeProjects/NozirIOS/NozirKit` → Add Package → product **NozirAppFeature** → target **NozirIOS**.
3. Product → Scheme → Manage Schemes… → `NozirIOS` qatorida **Shared** belgisini qo'ying (CI scheme'ni ko'rishi uchun).
4. Xcode'ni yoping.

- [ ] **Step 10: Ilova kirish nuqtasini almashtirish (Claude)**

`NozirIOS/ContentView.swift` ni o'chirish (`rm`). `NozirIOS/NozirIOSApp.swift` ni to'liq almashtirish:

```swift
import SwiftUI
import NozirAppFeature

@main
struct NozirIOSApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
```

Agar Xcode boshqa nomli fayl yaratgan bo'lsa (`ls NozirIOS/` bilan tekshiriladi), `@main` bor faylning o'zi almashtiriladi.

- [ ] **Step 11: Ilovani ishga tushirish (foydalanuvchi)**

Xcode'da loyihani oching → iPhone 17 simulyatori → Cmd+R.
Kutilgan: ekranda "Nozir" yozuvi. Va terminalda:

```bash
cd ~/XCodeProjects/NozirIOS && xcodebuild build -project NozirIOS.xcodeproj -scheme NozirIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Kutilgan: `** BUILD SUCCEEDED **`.

- [ ] **Step 12: Commit**

Avval `git status --short` — `xcuserdata` ko'rinmasligi kerak. Keyin:

```bash
git add .gitignore scripts/test.sh NozirKit/Package.swift NozirKit/Sources NozirKit/Tests NozirIOS.xcodeproj NozirIOS
```

Xabar: `build: an empty iOS app that runs, and a package with one green test`

---

### Task 2: CI — GitHub Actions `macos-26`

**Files:**
- Create: `.github/workflows/verify.yml`

**Interfaces:**
- Consumes: Task 1 Step 4 da aniqlangan paket scheme nomi (kutilgan `NozirKit-Package`), Task 1 Step 9 dagi shared `NozirIOS` scheme.

GitHub `macos-26` image'ida Xcode 26.6 (17F113) sukut bo'yicha o'rnatilgan va iPhone 17 simulyatori bor (manba: actions/runner-images `macos-26-arm64-Readme.md`, image 20260831). Image yangilanganda o'zgarishi mumkin — "Toolchain" qadami buni logda ko'rsatadi.

- [ ] **Step 1: Workflow yozish**

```yaml
name: verify

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: macos-26
    timeout-minutes: 30
    env:
      DEVELOPER_DIR: /Applications/Xcode_26.6.app/Contents/Developer
      DESTINATION: platform=iOS Simulator,name=iPhone 17
    steps:
      - uses: actions/checkout@v4

      - name: Toolchain
        run: |
          xcodebuild -version
          xcrun simctl list devices available | grep iPhone | head -20

      - name: NozirKit tests
        working-directory: NozirKit
        run: xcodebuild test -scheme NozirKit-Package -destination "$DESTINATION"

      - name: App build
        run: >
          xcodebuild build
          -project NozirIOS.xcodeproj
          -scheme NozirIOS
          -destination 'generic/platform=iOS Simulator'
          CODE_SIGNING_ALLOWED=NO
```

Agar Task 1 Step 4 da scheme nomi boshqa chiqqan bo'lsa, `-scheme NozirKit-Package` o'sha nomga almashtiriladi.

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/verify.yml
```

Xabar: `ci: test the package and build the app on every push`

- [ ] **Step 3: GitHub repo va birinchi ishga tushirish (foydalanuvchi)**

1. GitHub'da `NozirIOS` repo yarating (bo'sh, README'siz).
2. `cd ~/XCodeProjects/NozirIOS && git remote add origin <repo URL> && git push -u origin main`
3. Actions → `verify` → natijani yuboring.

Kutilgan: ikkala qadam yashil. Qizil bo'lsa, log yuboriladi va **superpowers:systematic-debugging** bilan tahlil qilinadi.

---
### Task 3: Server sanalari — RFC 3339 va `NozirJSON`

Backend `JacksonConfig`: `Instant` RFC 3339 qatori sifatida, UTC, kasr qismi Jackson tomonidan 0–9 xonali (nanosoniyagacha) yoziladi. `JSONDecoder.DateDecodingStrategy.iso8601` kasr qismini qabul qilmaydi — shuning uchun o'z parser'imiz.

**Files:**
- Create: `NozirKit/Sources/NozirNetworking/RFC3339.swift`
- Create: `NozirKit/Sources/NozirNetworking/NozirJSON.swift`
- Test: `NozirKit/Tests/NozirNetworkingTests/RFC3339Tests.swift`

**Interfaces:**
- Produces: `enum RFC3339 { static func date(from: String) -> Date? }` (internal); `public enum NozirJSON { static func decoder() -> JSONDecoder; static func encoder() -> JSONEncoder }`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import NozirNetworking

/// 2026-10-03T11:31:09Z
private let wholeSecond = Date(timeIntervalSince1970: 1_791_027_069)

@Suite struct RFC3339Tests {
    @Test func parsesUTCWithoutFraction() {
        #expect(RFC3339.date(from: "2026-10-03T11:31:09Z") == wholeSecond)
    }

    // Jackson writes as many digits as the Instant has: 0, 3, 6 or 9.
    @Test(arguments: zip(
        [
            "2026-10-03T11:31:09.9Z",
            "2026-10-03T11:31:09.946Z",
            "2026-10-03T11:31:09.946123Z",
            "2026-10-03T11:31:09.946123456Z",
        ],
        [0.9, 0.946, 0.946123, 0.946123456]
    ))
    func parsesAnyNumberOfFractionalDigits(text: String, fraction: Double) throws {
        let date = try #require(RFC3339.date(from: text))
        #expect(abs(date.timeIntervalSince(wholeSecond) - fraction) < 0.000_001)
    }

    @Test func honoursAnOffset() {
        #expect(RFC3339.date(from: "2026-10-03T16:31:09+05:00") == wholeSecond)
    }

    @Test(arguments: ["", "yesterday", "2026-10-03", "2026-10-03T11:31:09.Z", "2026-10-03T11:31:09"])
    func rejectsWhatIsNotAnInstant(text: String) {
        #expect(RFC3339.date(from: text) == nil)
    }
}

@Suite struct NozirJSONTests {
    private struct Stamped: Decodable {
        let at: Date
    }

    @Test func decoderReadsServerInstants() throws {
        let json = Data(#"{"at":"2026-10-03T11:31:09.946123Z"}"#.utf8)
        let value = try NozirJSON.decoder().decode(Stamped.self, from: json)
        #expect(abs(value.at.timeIntervalSince1970 - 1_791_027_069.946123) < 0.000_001)
    }

    @Test func decoderRejectsSomethingThatIsNotAnInstant() {
        let json = Data(#"{"at":"soon"}"#.utf8)
        #expect(throws: DecodingError.self) {
            try NozirJSON.decoder().decode(Stamped.self, from: json)
        }
    }
}
```

- [ ] **Step 2: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `cannot find 'RFC3339' in scope`, `cannot find 'NozirJSON' in scope`.

- [ ] **Step 3: Implementatsiya**

`RFC3339.swift`:

```swift
import Foundation

/// The server's instants: `2026-10-03T11:31:09Z`, with any number of
/// fractional digits and either `Z` or a `±hh:mm` offset.
///
/// `ISO8601DateFormatter` is asked only for the whole-second part; the fraction
/// is cut out and added back, because how many digits the formatter accepts is
/// not something this code should depend on.
enum RFC3339 {
    static func date(from text: String) -> Date? {
        var wholeSecondText = text
        var fraction: Double = 0
        if let dot = text.firstIndex(of: ".") {
            let afterDot = text[text.index(after: dot)...]
            let digits = afterDot.prefix(while: { $0.isASCII && $0.isNumber })
            guard !digits.isEmpty, let value = Double("0." + digits) else { return nil }
            fraction = value
            wholeSecondText = String(text[..<dot]) + String(afterDot.dropFirst(digits.count))
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let whole = formatter.date(from: wholeSecondText) else { return nil }
        return whole.addingTimeInterval(fraction)
    }
}
```

`NozirJSON.swift`:

```swift
import Foundation

/// JSON conventions shared with the backend (`JacksonConfig`): instants are
/// RFC 3339 strings, unknown fields are ignored (JSONDecoder's default).
public enum NozirJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = RFC3339.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Not an RFC 3339 instant: \(text)"
                )
            }
            return date
        }
        return decoder
    }

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
```

- [ ] **Step 4: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NozirKit/Sources/NozirNetworking/RFC3339.swift NozirKit/Sources/NozirNetworking/NozirJSON.swift NozirKit/Tests/NozirNetworkingTests/RFC3339Tests.swift
```

Xabar: `networking: read the server's instants however many digits they carry`

---

### Task 4: Yagona xato shakli — `ApiError`, `ApiErrorCode`, `ApiFailure`

Manba: backend `platform/api/ApiError.kt` (`{ "error": { code, message, field, violations, retryAfterSeconds, traceId, timestamp } }`) va `ErrorCode.kt`.

**Files:**
- Create: `NozirKit/Sources/NozirNetworking/ApiErrorCode.swift`
- Create: `NozirKit/Sources/NozirNetworking/ApiError.swift`
- Create: `NozirKit/Sources/NozirNetworking/ApiFailure.swift`
- Test: `NozirKit/Tests/NozirNetworkingTests/ApiErrorTests.swift`

**Interfaces:**
- Consumes: `NozirJSON.decoder()` (Task 3).
- Produces:
  - `public struct ApiErrorCode: RawRepresentable, Hashable, Sendable, Codable` + `.unauthenticated .tokenExpired .tokenRevoked .invalidToken .otpCodeInvalid .otpCodeExpired .rateLimited .upstreamUnavailable .signInMethodDisabled .internalError`
  - `public struct ApiError: Decodable, Equatable, Sendable { code, message, field, violations, retryAfterSeconds, traceId; init(code:message:field:violations:retryAfterSeconds:traceId:) }`
  - `public struct FieldViolation: Decodable, Equatable, Sendable { field, code, message }`
  - `public enum ApiFailure: Error, Equatable, Sendable { case server(status: Int, error: ApiError); case network(code: Int); case decoding(String); case unexpectedStatus(Int); case sessionEnded }` + `var code: ApiErrorCode?`, `var endsSession: Bool`
  - `enum ResponseMapping { static func failure(status: Int, body: Data) -> ApiFailure }` (internal)

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import NozirNetworking

@Suite struct ApiErrorTests {
    @Test func decodesTheSingleErrorShape() {
        // Shape: Nozir-Backend platform/api/ApiError.kt
        let body = Data(#"""
        {"error":{"code":"RATE_LIMITED","message":"slow down","retryAfterSeconds":42,"traceId":"t-1","timestamp":"2026-10-03T11:31:09.5Z"}}
        """#.utf8)
        let failure = ResponseMapping.failure(status: 429, body: body)
        let expected = ApiError(code: .rateLimited, message: "slow down", retryAfterSeconds: 42, traceId: "t-1")
        #expect(failure == .server(status: 429, error: expected))
    }

    @Test func readsFieldViolations() {
        let body = Data(#"""
        {"error":{"code":"VALIDATION_FAILED","message":"bad","field":"code","violations":[{"field":"code","code":"VALIDATION_FAILED","message":"must be the digits the bot sent"}]}}
        """#.utf8)
        guard case .server(_, let error) = ResponseMapping.failure(status: 400, body: body) else {
            Issue.record("expected a server failure")
            return
        }
        #expect(error.field == "code")
        #expect(error.violations == [
            FieldViolation(field: "code", code: ApiErrorCode(rawValue: "VALIDATION_FAILED"), message: "must be the digits the bot sent"),
        ])
    }

    @Test func keepsACodeThisAppDoesNotKnowYet() {
        let body = Data(#"{"error":{"code":"BRAND_NEW_CODE","message":"x"}}"#.utf8)
        #expect(ResponseMapping.failure(status: 409, body: body).code?.rawValue == "BRAND_NEW_CODE")
    }

    @Test func aBodyThatIsNotTheErrorShapeIsAnUnexpectedStatus() {
        let body = Data("<html>Bad gateway</html>".utf8)
        #expect(ResponseMapping.failure(status: 502, body: body) == .unexpectedStatus(502))
    }

    @Test(arguments: [ApiErrorCode.tokenExpired, .tokenRevoked, .invalidToken, .unauthenticated])
    func a401WithASessionCodeEndsTheSession(code: ApiErrorCode) {
        #expect(ApiFailure.server(status: 401, error: ApiError(code: code)).endsSession)
    }

    @Test func otherFailuresDoNotEndTheSession() {
        #expect(!ApiFailure.server(status: 403, error: ApiError(code: ApiErrorCode(rawValue: "FORBIDDEN"))).endsSession)
        #expect(!ApiFailure.server(status: 400, error: ApiError(code: .otpCodeInvalid)).endsSession)
        #expect(!ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue).endsSession)
        #expect(!ApiFailure.unexpectedStatus(401).endsSession)
    }
}
```

- [ ] **Step 2: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `cannot find 'ResponseMapping' in scope` va boshqalar.

- [ ] **Step 3: Implementatsiya**

`ApiErrorCode.swift`:

```swift
/// The server's machine-readable error code (`ErrorCode.kt`). A struct rather
/// than an enum so that a code added on the server later still decodes.
public struct ApiErrorCode: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let unauthenticated = ApiErrorCode(rawValue: "UNAUTHENTICATED")
    public static let tokenExpired = ApiErrorCode(rawValue: "TOKEN_EXPIRED")
    public static let tokenRevoked = ApiErrorCode(rawValue: "TOKEN_REVOKED")
    public static let invalidToken = ApiErrorCode(rawValue: "INVALID_TOKEN")
    public static let otpCodeInvalid = ApiErrorCode(rawValue: "OTP_CODE_INVALID")
    public static let otpCodeExpired = ApiErrorCode(rawValue: "OTP_CODE_EXPIRED")
    public static let rateLimited = ApiErrorCode(rawValue: "RATE_LIMITED")
    public static let upstreamUnavailable = ApiErrorCode(rawValue: "UPSTREAM_UNAVAILABLE")
    public static let signInMethodDisabled = ApiErrorCode(rawValue: "SIGN_IN_METHOD_DISABLED")
    public static let internalError = ApiErrorCode(rawValue: "INTERNAL_ERROR")
}
```

`ApiError.swift`:

```swift
import Foundation

/// The body of every non-2xx response (`ApiError.kt`). `message` is for logs
/// only and is never shown to a parent.
public struct ApiError: Decodable, Equatable, Sendable {
    public let code: ApiErrorCode
    public let message: String
    public let field: String?
    public let violations: [FieldViolation]
    public let retryAfterSeconds: Int?
    /// Safe to show on a support screen.
    public let traceId: String?

    public init(
        code: ApiErrorCode,
        message: String = "",
        field: String? = nil,
        violations: [FieldViolation] = [],
        retryAfterSeconds: Int? = nil,
        traceId: String? = nil
    ) {
        self.code = code
        self.message = message
        self.field = field
        self.violations = violations
        self.retryAfterSeconds = retryAfterSeconds
        self.traceId = traceId
    }

    private enum CodingKeys: String, CodingKey {
        case code, message, field, violations, retryAfterSeconds, traceId
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(ApiErrorCode.self, forKey: .code)
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        field = try container.decodeIfPresent(String.self, forKey: .field)
        violations = try container.decodeIfPresent([FieldViolation].self, forKey: .violations) ?? []
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        traceId = try container.decodeIfPresent(String.self, forKey: .traceId)
    }
}

public struct FieldViolation: Decodable, Equatable, Sendable {
    public let field: String
    public let code: ApiErrorCode
    public let message: String
}

private struct ErrorResponse: Decodable {
    let error: ApiError
}

enum ResponseMapping {
    static func failure(status: Int, body: Data) -> ApiFailure {
        guard let envelope = try? NozirJSON.decoder().decode(ErrorResponse.self, from: body) else {
            return .unexpectedStatus(status)
        }
        return .server(status: status, error: envelope.error)
    }
}
```

`ApiFailure.swift`:

```swift
/// Everything that can go wrong with a call, in the one shape callers handle.
public enum ApiFailure: Error, Equatable, Sendable {
    /// The server answered with the error body.
    case server(status: Int, error: ApiError)
    /// No answer at all. `code` is `URLError.Code.rawValue`.
    case network(code: Int)
    /// A 2xx whose body did not match the expected shape.
    case decoding(String)
    /// A non-2xx without the error body (a proxy's HTML page, for example).
    case unexpectedStatus(Int)
    /// There is no session, or the server has ended it. Tokens are gone.
    case sessionEnded

    public var code: ApiErrorCode? {
        guard case .server(_, let error) = self else { return nil }
        return error.code
    }

    /// True when the refresh token itself has been refused: signing in again
    /// is the only way forward. A network failure never ends a session.
    public var endsSession: Bool {
        guard case .server(let status, let error) = self, status == 401 else { return false }
        return [.tokenExpired, .tokenRevoked, .invalidToken, .unauthenticated].contains(error.code)
    }
}
```

- [ ] **Step 4: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NozirKit/Sources/NozirNetworking/ApiErrorCode.swift NozirKit/Sources/NozirNetworking/ApiError.swift NozirKit/Sources/NozirNetworking/ApiFailure.swift NozirKit/Tests/NozirNetworkingTests/ApiErrorTests.swift
```

Xabar: `networking: one error shape, and which errors end a session`

---

### Task 5: `ApiClient` — so'rov qurish, sarlavhalar, 401 → bitta refresh → qayta urinish

**Files:**
- Modify: `NozirKit/Package.swift` (`NozirTestSupport` target, test bog'liqligi)
- Create: `NozirKit/Sources/NozirNetworking/ApiRequest.swift`
- Create: `NozirKit/Sources/NozirNetworking/HTTPTransport.swift`
- Create: `NozirKit/Sources/NozirNetworking/AccessTokenProvider.swift`
- Create: `NozirKit/Sources/NozirNetworking/ApiClient.swift`
- Create: `NozirKit/Tests/NozirTestSupport/FakeTransport.swift`
- Create: `NozirKit/Tests/NozirTestSupport/HTTP.swift`
- Test: `NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift`

**Interfaces:**
- Consumes: `ClientIdentity` (Task 1), `NozirJSON` (Task 3), `ApiFailure`, `ResponseMapping` (Task 4).
- Produces:
  - `public enum HTTPMethod: String, Sendable { case get = "GET", post = "POST" }`
  - `public struct ApiRequest: Sendable { method, path, query: [String: String], body: Data?, requiresAuth: Bool; init(method:path:query:body:requiresAuth:); static func post<Body: Encodable>(_ path: String, json: Body, requiresAuth: Bool = true) throws -> ApiRequest }`
  - `public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`, `public struct URLSessionTransport: HTTPTransport`
  - `public protocol AccessTokenProvider: Sendable { func validAccessToken() async throws -> String; func refreshAfterRejection(of token: String) async throws -> String }`
  - `public struct ApiClient: Sendable { init(baseURL:transport:identity:tokens:); func withTokens(_:) -> ApiClient; func send<R: Decodable>(_:as:) async throws -> R; func send(_:) async throws }`
  - Test support: `public actor FakeTransport: HTTPTransport { init(_ script: [Reply]); var requests: [URLRequest] }`, `FakeTransport.Reply.ok(_:)`, `.error(_:code:)`, `URLRequest.jsonBody: [String: String]?`

- [ ] **Step 1: `Package.swift` ni yangilash**

`targets` massivini to'liq almashtirish:

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking"]),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
    ]
```

`NozirTestSupport` hech qaysi `product` ga kirmaydi, ilovaga bog'lanmaydi.

- [ ] **Step 2: Test yordamchilari**

`Tests/NozirTestSupport/FakeTransport.swift`:

```swift
import Foundation
import NozirNetworking

/// Answers requests from a script, in order, and remembers what it was asked.
/// An exhausted script behaves like a phone with no connection.
public actor FakeTransport: HTTPTransport {
    public struct Reply: Sendable {
        public let status: Int
        public let body: String

        public init(status: Int, body: String = "") {
            self.status = status
            self.body = body
        }
    }

    private var script: [Reply]
    public private(set) var requests: [URLRequest] = []

    public init(_ script: [Reply]) {
        self.script = script
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !script.isEmpty else { throw URLError(.notConnectedToInternet) }
        let reply = script.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(reply.body.utf8), response)
    }
}
```

`Tests/NozirTestSupport/HTTP.swift`:

```swift
import Foundation

public extension FakeTransport.Reply {
    static func ok(_ body: String) -> Self {
        .init(status: 200, body: body)
    }

    /// The backend's error body with the given code.
    static func error(_ status: Int, code: String) -> Self {
        .init(status: status, body: #"{"error":{"code":"\#(code)","message":"server text"}}"#)
    }
}

public extension URLRequest {
    /// The body as a flat JSON object, for asserting what was sent.
    var jsonBody: [String: String]? {
        guard let httpBody else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: httpBody)
    }
}
```

- [ ] **Step 3: Failing test**

`Tests/NozirNetworkingTests/ApiClientTests.swift`:

```swift
import Foundation
import Testing
import NozirTestSupport
@testable import NozirNetworking

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
private let base = URL(string: "https://api.test")!

private actor FakeTokens: AccessTokenProvider {
    private var current: String
    private let renewed: String
    private(set) var rejected: [String] = []

    init(current: String, renewed: String = "renewed") {
        self.current = current
        self.renewed = renewed
    }

    func validAccessToken() async throws -> String { current }

    func refreshAfterRejection(of token: String) async throws -> String {
        rejected.append(token)
        current = renewed
        return renewed
    }
}

private struct Echo: Decodable, Equatable {
    let value: String
}

@Suite struct ApiClientTests {
    @Test func anonymousRequestCarriesTheClientHeaderAndNoBearer() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        _ = try await client.send(
            ApiRequest(method: .get, path: "/v1/config", query: ["clientKind": "PARENT_IOS"], requiresAuth: false),
            as: Echo.self
        )

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(sent.url?.absoluteString == "https://api.test/v1/config?clientKind=PARENT_IOS")
        #expect(sent.httpMethod == "GET")
        #expect(sent.value(forHTTPHeaderField: "X-Nozir-Client") == "nozir-parent/1.0.0 (ios; 17.5)")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aTrailingSlashOnTheBaseURLDoesNotDoubleTheSlash() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: URL(string: "https://api.test/")!, transport: transport, identity: identity)

        _ = try await client.send(ApiRequest(method: .get, path: "/v1/config", requiresAuth: false), as: Echo.self)

        let requests = await transport.requests
        #expect(requests.first?.url?.absoluteString == "https://api.test/v1/config")
    }

    @Test func aJSONPostCarriesItsBodyAndContentType() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        _ = try await client.send(
            try .post("/v1/auth/telegram/verify", json: ["code": "123456"], requiresAuth: false),
            as: Echo.self
        )

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(sent.httpMethod == "POST")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.jsonBody == ["code": "123456"])
    }

    @Test func anAuthorisedRequestCarriesTheBearer() async throws {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        let echo = try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        let requests = await transport.requests
        #expect(echo == Echo(value: "x"))
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer acc-1")
    }

    @Test func aServerErrorIsThrownInTheOneShape() async {
        let transport = FakeTransport([.error(400, code: "VALIDATION_FAILED")])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        await #expect(throws: ApiFailure.server(
            status: 400,
            error: ApiError(code: ApiErrorCode(rawValue: "VALIDATION_FAILED"), message: "server text")
        )) {
            try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }

    @Test func a401IsRefreshedOnceAndRetriedWithTheNewToken() async throws {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .ok(#"{"value":"after"}"#)])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        let echo = try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)

        let requests = await transport.requests
        let rejected = await tokens.rejected
        #expect(echo == Echo(value: "after"))
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer renewed")
        #expect(rejected == ["acc-1"])
    }

    @Test func aSecond401IsNotRetriedAgain() async {
        let transport = FakeTransport([.error(401, code: "TOKEN_EXPIRED"), .error(401, code: "TOKEN_REVOKED")])
        let tokens = FakeTokens(current: "acc-1")
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: tokens)

        await #expect(throws: ApiFailure.server(status: 401, error: ApiError(code: .tokenRevoked, message: "server text"))) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        let rejected = await tokens.rejected
        #expect(requests.count == 2)
        #expect(rejected.count == 1)
    }

    @Test func noConnectionIsANetworkFailure() async {
        let client = ApiClient(baseURL: base, transport: FakeTransport([]), identity: identity)

        await #expect(throws: ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)) {
            try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
        }
    }

    @Test func aNoContentAnswerIsASuccess() async throws {
        let transport = FakeTransport([.init(status: 204)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity, tokens: FakeTokens(current: "acc-1"))

        try await client.send(ApiRequest(method: .post, path: "/v1/auth/logout"))

        let requests = await transport.requests
        #expect(requests.count == 1)
    }

    @Test func anAuthorisedRequestWithoutASessionIsNotSent() async {
        let transport = FakeTransport([.ok(#"{"value":"x"}"#)])
        let client = ApiClient(baseURL: base, transport: transport, identity: identity)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await client.send(ApiRequest(method: .get, path: "/v1/parent/x"), as: Echo.self)
        }
        let requests = await transport.requests
        #expect(requests.isEmpty)
    }

    @Test func aSuccessWithTheWrongShapeIsADecodingFailure() async {
        let client = ApiClient(baseURL: base, transport: FakeTransport([.ok("{}")]), identity: identity)

        do {
            _ = try await client.send(ApiRequest(method: .get, path: "/v1/x", requiresAuth: false), as: Echo.self)
            Issue.record("expected a decoding failure")
        } catch let failure as ApiFailure {
            guard case .decoding = failure else {
                Issue.record("expected .decoding, got \(failure)")
                return
            }
        } catch {
            Issue.record("expected ApiFailure, got \(error)")
        }
    }
}
```

- [ ] **Step 4: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `cannot find type 'HTTPTransport' in scope` (NozirTestSupport) va boshqalar.

- [ ] **Step 5: Implementatsiya**

`ApiRequest.swift`:

```swift
import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

/// One call, described without knowing the host, the client header or the token.
public struct ApiRequest: Sendable {
    public var method: HTTPMethod
    /// Starts with "/", e.g. "/v1/config".
    public var path: String
    public var query: [String: String]
    public var body: Data?
    public var requiresAuth: Bool

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
    }

    public static func post<Body: Encodable>(
        _ path: String,
        json body: Body,
        requiresAuth: Bool = true
    ) throws -> ApiRequest {
        ApiRequest(method: .post, path: path, body: try NozirJSON.encoder().encode(body), requiresAuth: requiresAuth)
    }
}
```

`HTTPTransport.swift`:

```swift
import Foundation

/// The one place bytes leave the phone. Tests replace it; the app uses URLSession.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}
```

`AccessTokenProvider.swift`:

```swift
/// Where an authorised call gets its bearer. Implemented by `TokenRefresher`
/// in NozirAuth; declared here so the client does not depend on that module.
public protocol AccessTokenProvider: Sendable {
    /// A token that is not about to expire, refreshing first if it is.
    func validAccessToken() async throws -> String
    /// The server refused `token` with a 401: a newer one, refreshing only if
    /// nobody has refreshed since `token` was handed out.
    func refreshAfterRejection(of token: String) async throws -> String
}
```

`ApiClient.swift`:

```swift
import Foundation

/// Builds requests, sends them, and turns every answer into either a value or
/// an `ApiFailure`. An authorised call that gets a 401 is refreshed once and
/// retried once; a second 401 is returned as it is.
public struct ApiClient: Sendable {
    private let baseURL: URL
    private let transport: any HTTPTransport
    private let identity: ClientIdentity
    private let tokens: (any AccessTokenProvider)?

    public init(
        baseURL: URL,
        transport: any HTTPTransport,
        identity: ClientIdentity,
        tokens: (any AccessTokenProvider)? = nil
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.identity = identity
        self.tokens = tokens
    }

    public func withTokens(_ tokens: any AccessTokenProvider) -> ApiClient {
        ApiClient(baseURL: baseURL, transport: transport, identity: identity, tokens: tokens)
    }

    public func send<Response: Decodable>(_ request: ApiRequest, as type: Response.Type) async throws -> Response {
        let data = try await perform(request)
        do {
            return try NozirJSON.decoder().decode(Response.self, from: data)
        } catch {
            throw ApiFailure.decoding(String(describing: error))
        }
    }

    public func send(_ request: ApiRequest) async throws {
        _ = try await perform(request)
    }

    private func perform(_ request: ApiRequest) async throws -> Data {
        guard request.requiresAuth else {
            let answer = try await transmit(request, bearer: nil)
            return try checked(answer)
        }
        guard let tokens else { throw ApiFailure.sessionEnded }
        let token = try await tokens.validAccessToken()
        let first = try await transmit(request, bearer: token)
        guard first.response.statusCode == 401 else { return try checked(first) }
        let renewed = try await tokens.refreshAfterRejection(of: token)
        let second = try await transmit(request, bearer: renewed)
        return try checked(second)
    }

    private func transmit(
        _ request: ApiRequest,
        bearer: String?
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        let urlRequest = makeURLRequest(request, bearer: bearer)
        do {
            let (data, response) = try await transport.send(urlRequest)
            return (data, response)
        } catch let error as URLError {
            throw ApiFailure.network(code: error.code.rawValue)
        } catch {
            throw ApiFailure.network(code: URLError.Code.unknown.rawValue)
        }
    }

    private func checked(_ answer: (data: Data, response: HTTPURLResponse)) throws -> Data {
        let status = answer.response.statusCode
        guard (200..<300).contains(status) else {
            throw ResponseMapping.failure(status: status, body: answer.data)
        }
        return answer.data
    }

    func makeURLRequest(_ request: ApiRequest, bearer: String?) -> URLRequest {
        var base = baseURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        guard var components = URLComponents(string: base + request.path) else {
            preconditionFailure("Unbuildable API path: \(request.path)")
        }
        if !request.query.isEmpty {
            components.queryItems = request.query
                .sorted { $0.key < $1.key }
                .map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components.url else {
            preconditionFailure("Unbuildable API URL: \(request.path)")
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue(identity.headerValue, forHTTPHeaderField: "X-Nozir-Client")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = request.body {
            urlRequest.httpBody = body
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let bearer {
            urlRequest.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        return urlRequest
    }
}
```

- [ ] **Step 6: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Kutilgan: `** TEST SUCCEEDED **`, Task 1/3/4/5 testlari hammasi yashil.

- [ ] **Step 7: Commit**

```bash
git add NozirKit/Package.swift NozirKit/Sources/NozirNetworking/ApiRequest.swift NozirKit/Sources/NozirNetworking/HTTPTransport.swift NozirKit/Sources/NozirNetworking/AccessTokenProvider.swift NozirKit/Sources/NozirNetworking/ApiClient.swift NozirKit/Tests/NozirTestSupport NozirKit/Tests/NozirNetworkingTests/ApiClientTests.swift
```

Xabar: `networking: one client, one refresh and one retry on a 401`

- [ ] **Step 8: Code review (Networking moduli tugadi)**

**superpowers:requesting-code-review** — `NozirKit/Sources/NozirNetworking` va testlari, spec 6.3 va 7-bo'limlarga qarshi. Topilmalar **superpowers:receiving-code-review** bilan tekshiriladi.

---
### Task 6: Tokenlar va ularni saqlash — `TokenPair`, `TokenStore`, Keychain

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirAuth/TokenPair.swift`
- Create: `NozirKit/Sources/NozirAuth/TokenStore.swift`
- Create: `NozirKit/Sources/NozirAuth/KeychainTokenStore.swift`
- Test: `NozirKit/Tests/NozirAuthTests/TokenStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct TokenPair: Codable, Equatable, Sendable { accessToken: String; accessTokenExpiresAt: Date; refreshToken: String; refreshTokenExpiresAt: Date; init(...) }`
  - `public protocol TokenStore: Sendable { func load() -> TokenPair?; func save(_ tokens: TokenPair) throws; func clear() }`
  - `public final class InMemoryTokenStore: TokenStore` (`init(_ tokens: TokenPair? = nil)`)
  - `public struct KeychainTokenStore: TokenStore` (`init(service: String = "tut.mobile.nozirparent.session")`), `public struct KeychainError: Error, Equatable { status: OSStatus }`

- [ ] **Step 1: `Package.swift` — `targets` massivini almashtirish**

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking"]),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
    ]
```

- [ ] **Step 2: Failing test**

```swift
import Foundation
import Testing
@testable import NozirAuth

private let sample = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969.123456),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

// The keychain is shared by the whole test process: one test at a time, each
// on a service name nothing else uses.
@Suite(.serialized) struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(service: "tut.mobile.nozirparent.tests.\(UUID().uuidString)")

    @Test func anEmptyKeychainHasNoSession() {
        #expect(store.load() == nil)
    }

    @Test func whatIsSavedIsReadBackExactly() throws {
        defer { store.clear() }
        try store.save(sample)
        #expect(store.load() == sample)
    }

    @Test func savingAgainReplacesTheOldPair() throws {
        defer { store.clear() }
        try store.save(sample)
        let rotated = TokenPair(
            accessToken: "acc-2",
            accessTokenExpiresAt: sample.accessTokenExpiresAt.addingTimeInterval(900),
            refreshToken: "ref-2",
            refreshTokenExpiresAt: sample.refreshTokenExpiresAt
        )
        try store.save(rotated)
        #expect(store.load() == rotated)
    }

    @Test func clearRemovesTheSession() throws {
        try store.save(sample)
        store.clear()
        #expect(store.load() == nil)
    }
}

@Suite struct InMemoryTokenStoreTests {
    @Test func savesLoadsAndClears() throws {
        let store = InMemoryTokenStore()
        try store.save(sample)
        #expect(store.load() == sample)
        store.clear()
        #expect(store.load() == nil)
    }
}
```

- [ ] **Step 3: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `NozirAuth` target'ida manba yo'q / `cannot find 'TokenPair' in scope`.

- [ ] **Step 4: Implementatsiya**

`TokenPair.swift`:

```swift
import Foundation

/// The access/refresh pair as the server issues it (`TokenPairResponse`).
public struct TokenPair: Codable, Equatable, Sendable {
    public let accessToken: String
    public let accessTokenExpiresAt: Date
    public let refreshToken: String
    public let refreshTokenExpiresAt: Date

    public init(accessToken: String, accessTokenExpiresAt: Date, refreshToken: String, refreshTokenExpiresAt: Date) {
        self.accessToken = accessToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshToken = refreshToken
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}
```

`TokenStore.swift`:

```swift
import Foundation

/// Where the session lives between launches. A future sign-in provider (for
/// example Sign in with Apple) ends the same way Telegram does: by saving here.
public protocol TokenStore: Sendable {
    func load() -> TokenPair?
    func save(_ tokens: TokenPair) throws
    func clear()
}

/// For tests and previews. Never used by the shipping app.
public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: TokenPair?

    public init(_ tokens: TokenPair? = nil) {
        self.tokens = tokens
    }

    public func load() -> TokenPair? {
        lock.withLock { tokens }
    }

    public func save(_ tokens: TokenPair) throws {
        lock.withLock { self.tokens = tokens }
    }

    public func clear() {
        lock.withLock { tokens = nil }
    }
}
```

`KeychainTokenStore.swift`:

```swift
import Foundation
import Security

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// The session in the keychain, readable after the first unlock and never
/// migrated to another device by a backup.
///
/// Stored with a plain JSONEncoder (dates as numbers): this blob is read only
/// by this type, and a numeric date reads back exactly.
public struct KeychainTokenStore: TokenStore {
    private let service: String
    private let account = "parent-session"

    public init(service: String = "tut.mobile.nozirparent.session") {
        self.service = service
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> TokenPair? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(TokenPair.self, from: data)
    }

    public func save(_ tokens: TokenPair) throws {
        let data = try JSONEncoder().encode(tokens)
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    public func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
```

- [ ] **Step 5: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `** TEST SUCCEEDED **`.

**Ma'lum xavf:** host ilovasiz paket testlari simulyatorda Keychain'ga kirganda `-34018` (`errSecMissingEntitlement`) qaytarishi mumkin — bu Xcode versiyasiga bog'liq va men buni tasdiqlay olmayman. Agar `whatIsSavedIsReadBackExactly` shu sabab bilan yiqilsa: **systematic-debugging** bilan sabab tasdiqlanadi, keyin `KeychainTokenStoreTests` ga `.disabled("needs an app host: errSecMissingEntitlement")` qo'yiladi va Task 13 Step 9 dagi qo'lda tekshiruv ("ilovani qayta ochganda sessiya saqlanadi") Keychain'ning dalili bo'ladi. Testni o'chirish faqat foydalanuvchi bilan kelishib qilinadi.

- [ ] **Step 6: Commit**

```bash
git add NozirKit/Package.swift NozirKit/Sources/NozirAuth NozirKit/Tests/NozirAuthTests/TokenStoreTests.swift
```

Xabar: `auth: the session in the keychain, this device only`

---

### Task 7: `TokenRefresher` — ketma-ket refresh, sessiyani tugatish

Backend `RefreshTokenServiceImpl`: allaqachon rotatsiya qilingan refresh token qayta yuborilsa — butun lineage bekor qilinadi (`TOKEN_REVOKED`). Shuning uchun bu actor bir vaqtda bittadan ortiq refresh yubormasligi shart.

**Files:**
- Create: `NozirKit/Sources/NozirAuth/TokenRefresher.swift`
- Test: `NozirKit/Tests/NozirAuthTests/TokenRefresherTests.swift`

**Interfaces:**
- Consumes: `AccessTokenProvider`, `ApiFailure` (NozirNetworking); `TokenStore`, `TokenPair`, `InMemoryTokenStore` (Task 6).
- Produces: `public actor TokenRefresher: AccessTokenProvider { init(store: any TokenStore, now: @escaping @Sendable () -> Date = { Date() }, refresh: @escaping @Sendable (String) async throws -> TokenPair); nonisolated let sessionEnded: AsyncStream<Void> }`

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
import NozirNetworking
@testable import NozirAuth

private let now = Date(timeIntervalSince1970: 1_791_027_069)

private func pair(_ name: String, accessExpiresIn seconds: TimeInterval) -> TokenPair {
    TokenPair(
        accessToken: "acc-\(name)",
        accessTokenExpiresAt: now.addingTimeInterval(seconds),
        refreshToken: "ref-\(name)",
        refreshTokenExpiresAt: now.addingTimeInterval(30 * 24 * 3600)
    )
}

/// Stands in for POST /v1/auth/token/refresh and counts how often it was called.
private actor RefreshEndpoint {
    private let outcome: Result<TokenPair, ApiFailure>
    private(set) var presented: [String] = []

    init(_ outcome: Result<TokenPair, ApiFailure>) {
        self.outcome = outcome
    }

    func refresh(_ refreshToken: String) async throws -> TokenPair {
        presented.append(refreshToken)
        // Long enough for every concurrent caller to arrive while this is in flight.
        try await Task.sleep(for: .milliseconds(100))
        return try outcome.get()
    }
}

private func makeRefresher(store: InMemoryTokenStore, endpoint: RefreshEndpoint) -> TokenRefresher {
    TokenRefresher(store: store, now: { now }, refresh: { try await endpoint.refresh($0) })
}

@Suite struct TokenRefresherTests {
    @Test func aFreshTokenIsReturnedWithoutRefreshing() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 600))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.validAccessToken()

        let presented = await endpoint.presented
        #expect(token == "acc-1")
        #expect(presented.isEmpty)
    }

    @Test func aTokenAboutToExpireIsRefreshedFirstAndTheNewPairSaved() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 20))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.validAccessToken()

        let presented = await endpoint.presented
        #expect(token == "acc-2")
        #expect(presented == ["ref-1"])
        #expect(store.load() == pair("2", accessExpiresIn: 900))
    }

    @Test func fiveCallersAtOnceCauseOneRefresh() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<5 {
                group.addTask { try await refresher.validAccessToken() }
            }
            var collected: [String] = []
            for try await token in group { collected.append(token) }
            return collected
        }

        let presented = await endpoint.presented
        #expect(tokens == Array(repeating: "acc-2", count: 5))
        #expect(presented == ["ref-1"])
    }

    @Test func aRejectionOfAnAlreadyReplacedTokenDoesNotRefreshAgain() async throws {
        let store = InMemoryTokenStore(pair("2", accessExpiresIn: 900))
        let endpoint = RefreshEndpoint(.success(pair("3", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.refreshAfterRejection(of: "acc-1")

        let presented = await endpoint.presented
        #expect(token == "acc-2")
        #expect(presented.isEmpty)
    }

    @Test func aRejectionOfTheCurrentTokenRefreshes() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: 900))
        let endpoint = RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        let token = try await refresher.refreshAfterRejection(of: "acc-1")

        #expect(token == "acc-2")
    }

    @Test func aRevokedRefreshTokenEndsTheSession() async throws {
        let store = InMemoryTokenStore(pair("1", accessExpiresIn: -5))
        let revoked = ApiFailure.server(status: 401, error: ApiError(code: .tokenRevoked))
        let endpoint = RefreshEndpoint(.failure(revoked))
        let refresher = makeRefresher(store: store, endpoint: endpoint)

        await #expect(throws: ApiFailure.sessionEnded) {
            try await refresher.validAccessToken()
        }

        var events = refresher.sessionEnded.makeAsyncIterator()
        let event: Void? = await events.next()
        #expect(store.load() == nil)
        #expect(event != nil)
    }

    @Test func aNetworkFailureKeepsTheSession() async throws {
        let original = pair("1", accessExpiresIn: -5)
        let store = InMemoryTokenStore(original)
        let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)
        let refresher = makeRefresher(store: store, endpoint: RefreshEndpoint(.failure(offline)))

        await #expect(throws: offline) {
            try await refresher.validAccessToken()
        }
        #expect(store.load() == original)
    }

    @Test func noStoredSessionIsAnEndedSession() async {
        let refresher = makeRefresher(
            store: InMemoryTokenStore(),
            endpoint: RefreshEndpoint(.success(pair("2", accessExpiresIn: 900)))
        )

        await #expect(throws: ApiFailure.sessionEnded) {
            try await refresher.validAccessToken()
        }
    }
}
```

- [ ] **Step 2: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `cannot find 'TokenRefresher' in scope`.

- [ ] **Step 3: Implementatsiya**

```swift
import Foundation
import NozirNetworking

/// The only place a refresh token is spent.
///
/// The server revokes the whole session when a rotated refresh token is shown
/// again (`RefreshTokenServiceImpl.onReuseDetected`), so two refreshes must
/// never race: every caller that needs one while another is in flight waits
/// for that one instead of starting its own.
public actor TokenRefresher: AccessTokenProvider {
    public typealias RefreshCall = @Sendable (String) async throws -> TokenPair

    /// Refresh this long before the access token expires, not after.
    private let leeway: TimeInterval = 30
    private let store: any TokenStore
    private let now: @Sendable () -> Date
    private let refresh: RefreshCall
    private var inFlight: Task<TokenPair, any Error>?

    /// Emits once each time the server ends the session. Single consumer: AppModel.
    public nonisolated let sessionEnded: AsyncStream<Void>
    private let sessionEndedContinuation: AsyncStream<Void>.Continuation

    public init(
        store: any TokenStore,
        now: @escaping @Sendable () -> Date = { Date() },
        refresh: @escaping RefreshCall
    ) {
        self.store = store
        self.now = now
        self.refresh = refresh
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        self.sessionEnded = stream
        self.sessionEndedContinuation = continuation
    }

    public func validAccessToken() async throws -> String {
        guard let tokens = store.load() else { throw ApiFailure.sessionEnded }
        if tokens.accessTokenExpiresAt.timeIntervalSince(now()) > leeway {
            return tokens.accessToken
        }
        return try await rotate(using: tokens.refreshToken).accessToken
    }

    public func refreshAfterRejection(of token: String) async throws -> String {
        guard let tokens = store.load() else { throw ApiFailure.sessionEnded }
        if tokens.accessToken != token {
            // Somebody refreshed after `token` was handed out; use theirs.
            return tokens.accessToken
        }
        return try await rotate(using: tokens.refreshToken).accessToken
    }

    private func rotate(using refreshToken: String) async throws -> TokenPair {
        if let inFlight {
            return try await inFlight.value
        }
        let task = Task { [store, refresh, sessionEndedContinuation] () async throws -> TokenPair in
            do {
                let renewed = try await refresh(refreshToken)
                // A failed save is not a failed refresh: the new pair is valid
                // for this run. The next launch will find the old pair, present
                // a spent token and be signed out, which is the safe outcome.
                try? store.save(renewed)
                return renewed
            } catch let failure as ApiFailure where failure.endsSession {
                store.clear()
                sessionEndedContinuation.yield()
                throw ApiFailure.sessionEnded
            }
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
```

- [ ] **Step 4: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `** TEST SUCCEEDED **`. `fiveCallersAtOnceCauseOneRefresh` ni ishonch uchun 3 marta ishga tushiring (`./scripts/test.sh NozirAuthTests` x3) — har safar yashil bo'lishi kerak.

- [ ] **Step 5: Commit**

```bash
git add NozirKit/Sources/NozirAuth/TokenRefresher.swift NozirKit/Tests/NozirAuthTests/TokenRefresherTests.swift
```

Xabar: `auth: one refresh at a time, because the server punishes two`

---

### Task 8: Telegram orqali kirish — `AuthApi`, `TelegramSignIn`

Manba: backend `identity/internal/web/AuthController.kt`, `AuthDtos.kt`.

**Files:**
- Create: `NozirKit/Sources/NozirAuth/AuthModels.swift`
- Create: `NozirKit/Sources/NozirAuth/AuthApi.swift`
- Create: `NozirKit/Sources/NozirAuth/TelegramSignIn.swift`
- Test: `NozirKit/Tests/NozirAuthTests/TelegramSignInTests.swift`

**Interfaces:**
- Consumes: `ApiClient`, `ApiRequest`, `ApiFailure` (Task 4–5); `TokenPair`, `TokenStore`, `InMemoryTokenStore` (Task 6); `FakeTransport` (Task 5).
- Produces:
  - `public struct TelegramLoginStart: Decodable, Equatable, Sendable { botUsername: String; deepLink: URL; codeLength: Int; codeTtlSeconds: Int }`
  - `public struct ParentAccount: Decodable, Equatable, Sendable { parentId: UUID; familyId: UUID; phoneE164: String?; displayName: String?; locale: String; timeZone: String; role: String; createdAt: Date }`
  - `public struct AuthApi: Sendable { init(client: ApiClient); func telegramStart() async throws -> TelegramLoginStart; func refresh(_ refreshToken: String) async throws -> TokenPair; func logout() async throws }` (+ internal `telegramVerify(code:deviceLabel:)`)
  - `public protocol TelegramSignInService: Sendable { func start() async throws -> TelegramLoginStart; func verify(code: String) async throws }`
  - `public struct TelegramSignIn: TelegramSignInService { init(api: AuthApi, store: any TokenStore, deviceLabel: String) }`

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirAuth

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")

// TelegramLoginStartResponse, AuthDtos.kt
private let startBody = #"{"botUsername":"nozir_bot","deepLink":"https://t.me/nozir_bot","codeLength":6,"codeTtlSeconds":180}"#

// ParentAuthResponse, AuthDtos.kt. phoneE164 is absent: a Telegram parent who added no number.
private let signedInBody = #"""
{"accessToken":"acc-1","accessTokenExpiresAt":"2026-10-03T11:46:09Z","refreshToken":"ref-1","refreshTokenExpiresAt":"2026-11-02T11:31:09Z","parent":{"parentId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","familyId":"2c5ea4c0-4067-11e9-8bad-9b1deb4d3b7d","displayName":"Zohid","locale":"uz","timeZone":"Asia/Tashkent","role":"OWNER","createdAt":"2026-09-01T08:00:00Z"},"isNewAccount":false}
"""#

// TokenPairResponse, AuthDtos.kt
private let refreshedBody = #"{"accessToken":"acc-2","accessTokenExpiresAt":"2026-10-03T11:46:09Z","refreshToken":"ref-2","refreshTokenExpiresAt":"2026-11-02T11:31:09Z"}"#

private let expectedTokens = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

private func makeAuth(_ replies: [FakeTransport.Reply]) -> (AuthApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(baseURL: URL(string: "https://api.test")!, transport: transport, identity: identity)
    return (AuthApi(client: client), transport)
}

@Suite struct TelegramSignInTests {
    @Test func startAsksTheServerWhereToSendTheParent() async throws {
        let (api, transport) = makeAuth([.ok(startBody)])
        let signIn = TelegramSignIn(api: api, store: InMemoryTokenStore(), deviceLabel: "iPhone")

        let start = try await signIn.start()

        let requests = await transport.requests
        #expect(start == TelegramLoginStart(
            botUsername: "nozir_bot",
            deepLink: URL(string: "https://t.me/nozir_bot")!,
            codeLength: 6,
            codeTtlSeconds: 180
        ))
        #expect(requests.first?.httpMethod == "POST")
        #expect(requests.first?.url?.path == "/v1/auth/telegram/start")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func aServerWithoutABotAnswers503() async {
        let (api, _) = makeAuth([.error(503, code: "UPSTREAM_UNAVAILABLE")])
        let signIn = TelegramSignIn(api: api, store: InMemoryTokenStore(), deviceLabel: "iPhone")

        await #expect(throws: ApiFailure.server(status: 503, error: ApiError(code: .upstreamUnavailable, message: "server text"))) {
            try await signIn.start()
        }
    }

    @Test func aGoodCodeSavesTheSession() async throws {
        let (api, transport) = makeAuth([.ok(signedInBody)])
        let store = InMemoryTokenStore()
        let signIn = TelegramSignIn(api: api, store: store, deviceLabel: "iPhone")

        try await signIn.verify(code: "123456")

        let requests = await transport.requests
        #expect(requests.first?.url?.path == "/v1/auth/telegram/verify")
        #expect(requests.first?.jsonBody == ["code": "123456", "deviceLabel": "iPhone"])
        #expect(store.load() == expectedTokens)
    }

    @Test func aRejectedCodeSavesNothing() async {
        let (api, _) = makeAuth([.error(400, code: "OTP_CODE_INVALID")])
        let store = InMemoryTokenStore()
        let signIn = TelegramSignIn(api: api, store: store, deviceLabel: "iPhone")

        await #expect(throws: ApiFailure.server(status: 400, error: ApiError(code: .otpCodeInvalid, message: "server text"))) {
            try await signIn.verify(code: "000000")
        }
        #expect(store.load() == nil)
    }

    @Test func refreshPresentsTheRefreshTokenAnonymously() async throws {
        let (api, transport) = makeAuth([.ok(refreshedBody)])

        let renewed = try await api.refresh("ref-1")

        let requests = await transport.requests
        #expect(renewed.accessToken == "acc-2")
        #expect(renewed.refreshToken == "ref-2")
        #expect(requests.first?.url?.path == "/v1/auth/token/refresh")
        #expect(requests.first?.jsonBody == ["refreshToken": "ref-1"])
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func theParentAccountDecodesWithAnAbsentOrNullPhone() throws {
        let withNull = Data(#"""
        {"parentId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","familyId":"2c5ea4c0-4067-11e9-8bad-9b1deb4d3b7d","phoneE164":null,"displayName":null,"locale":"uz","timeZone":"Asia/Tashkent","role":"GUARDIAN","createdAt":"2026-09-01T08:00:00Z"}
        """#.utf8)
        let account = try NozirJSON.decoder().decode(ParentAccount.self, from: withNull)
        #expect(account.phoneE164 == nil)
        #expect(account.role == "GUARDIAN")
        #expect(account.createdAt == Date(timeIntervalSince1970: 1_788_249_600))
    }
}
```

- [ ] **Step 2: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `cannot find 'TelegramSignIn' in scope` va boshqalar.

- [ ] **Step 3: Implementatsiya**

`AuthModels.swift`:

```swift
import Foundation

/// `TelegramLoginStartResponse`: where to send the parent and how long the
/// code they come back with lasts.
public struct TelegramLoginStart: Decodable, Equatable, Sendable {
    public let botUsername: String
    public let deepLink: URL
    public let codeLength: Int
    public let codeTtlSeconds: Int
}

/// `ParentAccountResponse`. `role` stays a string: the app does not branch on it yet.
public struct ParentAccount: Decodable, Equatable, Sendable {
    public let parentId: UUID
    public let familyId: UUID
    public let phoneE164: String?
    public let displayName: String?
    public let locale: String
    public let timeZone: String
    public let role: String
    public let createdAt: Date
}

/// `ParentAuthResponse`: a flattened token pair plus the parent.
struct ParentAuthResult: Decodable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let parent: ParentAccount
    let isNewAccount: Bool

    var tokens: TokenPair {
        TokenPair(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt
        )
    }
}
```

`AuthApi.swift`:

```swift
import NozirNetworking

/// `/v1/auth`. Every call here except logout is made without a bearer.
public struct AuthApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func telegramStart() async throws -> TelegramLoginStart {
        try await client.send(
            ApiRequest(method: .post, path: "/v1/auth/telegram/start", requiresAuth: false),
            as: TelegramLoginStart.self
        )
    }

    func telegramVerify(code: String, deviceLabel: String) async throws -> ParentAuthResult {
        struct Body: Encodable {
            let code: String
            let deviceLabel: String
        }
        return try await client.send(
            try .post("/v1/auth/telegram/verify", json: Body(code: code, deviceLabel: deviceLabel), requiresAuth: false),
            as: ParentAuthResult.self
        )
    }

    public func refresh(_ refreshToken: String) async throws -> TokenPair {
        struct Body: Encodable {
            let refreshToken: String
        }
        return try await client.send(
            try .post("/v1/auth/token/refresh", json: Body(refreshToken: refreshToken), requiresAuth: false),
            as: TokenPair.self
        )
    }

    /// Revokes every refresh token this parent holds (`AuthController.logout`).
    public func logout() async throws {
        try await client.send(ApiRequest(method: .post, path: "/v1/auth/logout"))
    }
}
```

`TelegramSignIn.swift`:

```swift
/// The two halves of signing in through the bot, as the screen sees them.
public protocol TelegramSignInService: Sendable {
    func start() async throws -> TelegramLoginStart
    func verify(code: String) async throws
}

public struct TelegramSignIn: TelegramSignInService {
    private let api: AuthApi
    private let store: any TokenStore
    /// `UIDevice.model` ("iPhone"), never the device's name: the name is personal.
    private let deviceLabel: String

    public init(api: AuthApi, store: any TokenStore, deviceLabel: String) {
        self.api = api
        self.store = store
        self.deviceLabel = deviceLabel
    }

    public func start() async throws -> TelegramLoginStart {
        try await api.telegramStart()
    }

    public func verify(code: String) async throws {
        let result = try await api.telegramVerify(code: code, deviceLabel: deviceLabel)
        try store.save(result.tokens)
    }
}
```

- [ ] **Step 4: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirAuthTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NozirKit/Sources/NozirAuth/AuthModels.swift NozirKit/Sources/NozirAuth/AuthApi.swift NozirKit/Sources/NozirAuth/TelegramSignIn.swift NozirKit/Tests/NozirAuthTests/TelegramSignInTests.swift
```

Xabar: `auth: sign in through the bot and keep what the server returns`

- [ ] **Step 6: Code review (Auth moduli tugadi)**

**superpowers:requesting-code-review** — `NozirKit/Sources/NozirAuth` va testlari, spec 6.2–6.4 va 8-bo'limga qarshi; alohida e'tibor: `TokenRefresher` dagi poyga holatlari. Topilmalar **superpowers:receiving-code-review** bilan.

---
### Task 9: Server konfiguratsiyasi va majburiy yangilanish darvozasi

Manba: backend `serverconfig/internal/web/ServerConfigController.kt`, `ServerConfigDtos.kt`. Ilovada ishlatilmaydigan maydonlar (`usageSyncIntervalSeconds`, `locationHeartbeatSeconds`, `dataDeletionDelayDays`) e'lon qilinmaydi — dekoder noma'lum maydonlarni e'tiborsiz qoldiradi.

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirConfig/ServerConfig.swift`
- Create: `NozirKit/Sources/NozirConfig/ConfigApi.swift`
- Create: `NozirKit/Sources/NozirConfig/ConfigCache.swift`
- Create: `NozirKit/Sources/NozirConfig/ConfigLoader.swift`
- Create: `NozirKit/Sources/NozirConfig/UpdateGate.swift`
- Test: `NozirKit/Tests/NozirConfigTests/ConfigTests.swift`

**Interfaces:**
- Consumes: `ApiClient`, `ApiRequest` (Task 5), `FakeTransport` (Task 5).
- Produces:
  - `public struct ServerConfig: Codable, Equatable, Sendable { minSupportedVersion; latestVersion; updateRequired: Bool; featureFlags: [String: Bool]; emergencyContacts: EmergencyContacts; privacyPolicyUrl; termsUrl; supportUrl; public init(...) }`
  - `public struct EmergencyContacts: Codable, Equatable, Sendable { emergencyNumber; policeNumber; ambulanceNumber; fireNumber; childHelplineNumber; isChildHelplineEnabled: Bool; public init(...) }`
  - `public struct ConfigApi: Sendable { init(client: ApiClient); func fetch() async throws -> ServerConfig }`
  - `public protocol ConfigCache: Sendable { func load(appVersion: String) -> ServerConfig?; func save(_ config: ServerConfig, appVersion: String) }`, `public final class UserDefaultsConfigCache: ConfigCache { init(defaults: UserDefaults = .standard) }`
  - `public protocol ConfigLoading: Sendable { func load() async -> ServerConfig? }`, `public struct ConfigLoader: ConfigLoading { init(api: ConfigApi, cache: any ConfigCache, appVersion: String) }`
  - `public enum UpdateGate { static func blocks(_ config: ServerConfig?, isExempt: Bool = false) -> Bool }`

- [ ] **Step 1: `Package.swift` — `targets` massivini almashtirish**

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking"]),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirConfigTests", dependencies: ["NozirConfig", "NozirNetworking", "NozirTestSupport"]),
    ]
```

- [ ] **Step 2: Failing test**

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirConfig

private let identity = ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")

// ServerConfigResponse, ServerConfigDtos.kt — including fields the app ignores.
private func configBody(updateRequired: Bool) -> String {
    #"""
    {"minSupportedVersion":"1.0.0","latestVersion":"1.1.0","updateRequired":\#(updateRequired),"featureFlags":{"PHONE_OTP_SIGN_IN":false},"emergencyContacts":{"emergencyNumber":"112","policeNumber":"102","ambulanceNumber":"103","fireNumber":"101","childHelplineNumber":"1246","isChildHelplineEnabled":false},"usageSyncIntervalSeconds":900,"locationHeartbeatSeconds":300,"dataDeletionDelayDays":30,"privacyPolicyUrl":"https://nozir.syncoder.uz/privacy","termsUrl":"https://nozir.syncoder.uz/terms","supportUrl":"https://nozir.syncoder.uz/support"}
    """#
}

private func config(updateRequired: Bool) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: ["PHONE_OTP_SIGN_IN": false],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: "https://nozir.syncoder.uz/privacy",
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support"
    )
}

private func freshCache() -> UserDefaultsConfigCache {
    UserDefaultsConfigCache(defaults: UserDefaults(suiteName: "nozir.tests.\(UUID().uuidString)")!)
}

private func makeLoader(_ replies: [FakeTransport.Reply], cache: any ConfigCache, appVersion: String = "1.0.0")
    -> (ConfigLoader, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(baseURL: URL(string: "https://api.test")!, transport: transport, identity: identity)
    return (ConfigLoader(api: ConfigApi(client: client), cache: cache, appVersion: appVersion), transport)
}

@Suite struct ConfigLoaderTests {
    @Test func asksAsTheIOSParentAppWithoutABearer() async throws {
        let (loader, transport) = makeLoader([.ok(configBody(updateRequired: false))], cache: freshCache())

        let loaded = await loader.load()

        let requests = await transport.requests
        let sent = try #require(requests.first)
        #expect(loaded == config(updateRequired: false))
        #expect(sent.url?.absoluteString == "https://api.test/v1/config?clientKind=PARENT_IOS")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func offlineFallsBackToTheLastConfigForThisVersion() async {
        let cache = freshCache()
        let (online, _) = makeLoader([.ok(configBody(updateRequired: true))], cache: cache)
        _ = await online.load()

        let (offline, _) = makeLoader([], cache: cache)
        #expect(await offline.load() == config(updateRequired: true))
    }

    // Review Focus 3: an "update required" remembered by the old version must
    // not lock out the version the parent just updated to.
    @Test func aCachedConfigFromAnotherAppVersionIsNotUsed() async {
        let cache = freshCache()
        let (old, _) = makeLoader([.ok(configBody(updateRequired: true))], cache: cache, appVersion: "1.0.0")
        _ = await old.load()

        let (updatedOffline, _) = makeLoader([], cache: cache, appVersion: "1.1.0")
        #expect(await updatedOffline.load() == nil)
    }

    @Test func offlineWithNothingCachedIsNil() async {
        let (loader, _) = makeLoader([], cache: freshCache())
        #expect(await loader.load() == nil)
    }

    @Test func aServerErrorFallsBackToTheCacheToo() async {
        let cache = freshCache()
        cache.save(config(updateRequired: false), appVersion: "1.0.0")
        let (loader, _) = makeLoader([.error(500, code: "INTERNAL_ERROR")], cache: cache)
        #expect(await loader.load() == config(updateRequired: false))
    }
}

@Suite struct UpdateGateTests {
    @Test func noConfigNeverBlocks() {
        #expect(!UpdateGate.blocks(nil))
    }

    @Test func aRequiredUpdateBlocks() {
        #expect(UpdateGate.blocks(config(updateRequired: true)))
    }

    @Test func aCurrentAppIsNotBlocked() {
        #expect(!UpdateGate.blocks(config(updateRequired: false)))
    }

    // SOS (P15) is never behind the wall.
    @Test func anExemptScreenIsNeverBlocked() {
        #expect(!UpdateGate.blocks(config(updateRequired: true), isExempt: true))
    }
}
```

- [ ] **Step 3: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirConfigTests`
Kutilgan: `NozirConfig` target'ida manba yo'q / `cannot find 'ServerConfig' in scope`.

- [ ] **Step 4: Implementatsiya**

`ServerConfig.swift`:

```swift
/// `ServerConfigResponse`, reduced to what the app reads.
public struct ServerConfig: Codable, Equatable, Sendable {
    public let minSupportedVersion: String
    public let latestVersion: String
    /// Computed by the server from `X-Nozir-Client` (`ClientVersions.isBelow`).
    public let updateRequired: Bool
    public let featureFlags: [String: Bool]
    public let emergencyContacts: EmergencyContacts
    public let privacyPolicyUrl: String
    public let termsUrl: String
    public let supportUrl: String

    public init(
        minSupportedVersion: String,
        latestVersion: String,
        updateRequired: Bool,
        featureFlags: [String: Bool],
        emergencyContacts: EmergencyContacts,
        privacyPolicyUrl: String,
        termsUrl: String,
        supportUrl: String
    ) {
        self.minSupportedVersion = minSupportedVersion
        self.latestVersion = latestVersion
        self.updateRequired = updateRequired
        self.featureFlags = featureFlags
        self.emergencyContacts = emergencyContacts
        self.privacyPolicyUrl = privacyPolicyUrl
        self.termsUrl = termsUrl
        self.supportUrl = supportUrl
    }
}

public struct EmergencyContacts: Codable, Equatable, Sendable {
    public let emergencyNumber: String
    public let policeNumber: String
    public let ambulanceNumber: String
    public let fireNumber: String
    public let childHelplineNumber: String
    public let isChildHelplineEnabled: Bool

    public init(
        emergencyNumber: String,
        policeNumber: String,
        ambulanceNumber: String,
        fireNumber: String,
        childHelplineNumber: String,
        isChildHelplineEnabled: Bool
    ) {
        self.emergencyNumber = emergencyNumber
        self.policeNumber = policeNumber
        self.ambulanceNumber = ambulanceNumber
        self.fireNumber = fireNumber
        self.childHelplineNumber = childHelplineNumber
        self.isChildHelplineEnabled = isChildHelplineEnabled
    }
}
```

`ConfigApi.swift`:

```swift
import NozirNetworking

/// `GET /v1/config`. Unauthenticated on purpose: an app that cannot sign in
/// must still learn that it has to update and what the emergency number is.
public struct ConfigApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    public func fetch() async throws -> ServerConfig {
        try await client.send(
            ApiRequest(method: .get, path: "/v1/config", query: ["clientKind": "PARENT_IOS"], requiresAuth: false),
            as: ServerConfig.self
        )
    }
}
```

`ConfigCache.swift`:

```swift
import Foundation

/// The last config the server sent to *this* app version. Keyed by version
/// because `updateRequired` is the server's verdict on one version only.
public protocol ConfigCache: Sendable {
    func load(appVersion: String) -> ServerConfig?
    func save(_ config: ServerConfig, appVersion: String)
}

public final class UserDefaultsConfigCache: ConfigCache, @unchecked Sendable {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load(appVersion: String) -> ServerConfig? {
        guard let data = defaults.data(forKey: key(appVersion)) else { return nil }
        return try? JSONDecoder().decode(ServerConfig.self, from: data)
    }

    public func save(_ config: ServerConfig, appVersion: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key(appVersion))
    }

    private func key(_ appVersion: String) -> String {
        "nozir.serverConfig.\(appVersion)"
    }
}
```

`ConfigLoader.swift`:

```swift
public protocol ConfigLoading: Sendable {
    /// The server's config, or the last one this version saw, or nil.
    /// Never throws: no answer must never lock a parent out.
    func load() async -> ServerConfig?
}

public struct ConfigLoader: ConfigLoading {
    private let api: ConfigApi
    private let cache: any ConfigCache
    private let appVersion: String

    public init(api: ConfigApi, cache: any ConfigCache, appVersion: String) {
        self.api = api
        self.cache = cache
        self.appVersion = appVersion
    }

    public func load() async -> ServerConfig? {
        do {
            let config = try await api.fetch()
            cache.save(config, appVersion: appVersion)
            return config
        } catch {
            return cache.load(appVersion: appVersion)
        }
    }
}
```

`UpdateGate.swift`:

```swift
/// Whether the "update the app" wall stands in front of a screen.
///
/// No config means no wall: being unable to reach the server is not a reason
/// to lock a parent out of a child-safety app. SOS is exempt, always.
public enum UpdateGate {
    public static func blocks(_ config: ServerConfig?, isExempt: Bool = false) -> Bool {
        guard !isExempt, let config else { return false }
        return config.updateRequired
    }
}
```

- [ ] **Step 5: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirConfigTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add NozirKit/Package.swift NozirKit/Sources/NozirConfig NozirKit/Tests/NozirConfigTests/ConfigTests.swift
```

Xabar: `config: the update wall, and why no answer never builds it`

---

### Task 10: `AppModel` — ilovaning ildiz holat mashinasi

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirAppFeature/AppModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ConfigLoading`, `ServerConfig`, `EmergencyContacts`, `UpdateGate` (Task 9); `TokenStore`, `InMemoryTokenStore`, `TokenPair` (Task 6).
- Produces:
  - `public enum AppPhase: Equatable, Sendable { case launching; case updateRequired(emergencyNumber: String?); case signedOut; case signedIn }`
  - `@MainActor @Observable public final class AppModel { phase: AppPhase; init(config: any ConfigLoading, tokens: any TokenStore, sessionEnded: AsyncStream<Void>, logout: @escaping @Sendable () async throws -> Void); func start() async; func didSignIn(); func signOut() async; func handleSessionEnded(); func watchSessionEnd() async; func sceneDidEnterBackground(at: Date); func sceneDidBecomeActive(at: Date) async }`

- [ ] **Step 1: `Package.swift` — `targets` massivini almashtirish**

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirAppFeature", dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig"]),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirConfigTests", dependencies: ["NozirConfig", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking"]
        ),
    ]
```

- [ ] **Step 2: Failing test**

```swift
import Foundation
import Testing
import NozirAuth
import NozirConfig
@testable import NozirAppFeature

private func config(updateRequired: Bool) -> ServerConfig {
    ServerConfig(
        minSupportedVersion: "1.0.0",
        latestVersion: "1.1.0",
        updateRequired: updateRequired,
        featureFlags: [:],
        emergencyContacts: EmergencyContacts(
            emergencyNumber: "112",
            policeNumber: "102",
            ambulanceNumber: "103",
            fireNumber: "101",
            childHelplineNumber: "1246",
            isChildHelplineEnabled: false
        ),
        privacyPolicyUrl: "https://nozir.syncoder.uz/privacy",
        termsUrl: "https://nozir.syncoder.uz/terms",
        supportUrl: "https://nozir.syncoder.uz/support"
    )
}

private let someTokens = TokenPair(
    accessToken: "acc-1",
    accessTokenExpiresAt: Date(timeIntervalSince1970: 1_791_027_969),
    refreshToken: "ref-1",
    refreshTokenExpiresAt: Date(timeIntervalSince1970: 1_793_619_069)
)

private actor FakeConfig: ConfigLoading {
    private var result: ServerConfig?
    private(set) var loads = 0

    init(_ result: ServerConfig?) {
        self.result = result
    }

    func set(_ result: ServerConfig?) {
        self.result = result
    }

    func load() async -> ServerConfig? {
        loads += 1
        return result
    }
}

private actor LogoutEndpoint {
    private(set) var calls = 0
    private let fails: Bool

    init(fails: Bool = false) {
        self.fails = fails
    }

    func logout() throws {
        calls += 1
        if fails { throw URLError(.notConnectedToInternet) }
    }
}

@MainActor
private func makeModel(
    config: FakeConfig,
    tokens: InMemoryTokenStore,
    logout: LogoutEndpoint = LogoutEndpoint()
) -> AppModel {
    AppModel(
        config: config,
        tokens: tokens,
        sessionEnded: AsyncStream { _ in },
        logout: { try await logout.logout() }
    )
}

@MainActor
@Suite struct AppModelTests {
    @Test func aRequiredUpdateShowsTheWallWithTheEmergencyNumber() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: true)), tokens: InMemoryTokenStore(someTokens))
        await model.start()
        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func noConfigAndNoSessionIsSignedOut() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore())
        await model.start()
        #expect(model.phase == .signedOut)
    }

    @Test func noConfigWithASessionIsSignedIn() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))
        await model.start()
        #expect(model.phase == .signedIn)
    }

    @Test func signingInMovesToSignedIn() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: false)), tokens: InMemoryTokenStore())
        await model.start()
        model.didSignIn()
        #expect(model.phase == .signedIn)
    }

    @Test func signingOutTellsTheServerAndForgetsTheSession() async {
        let tokens = InMemoryTokenStore(someTokens)
        let logout = LogoutEndpoint()
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: logout)
        await model.start()

        await model.signOut()

        #expect(await logout.calls == 1)
        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func signingOutOfflineStillForgetsTheSession() async {
        let tokens = InMemoryTokenStore(someTokens)
        let model = makeModel(config: FakeConfig(nil), tokens: tokens, logout: LogoutEndpoint(fails: true))
        await model.start()

        await model.signOut()

        #expect(tokens.load() == nil)
        #expect(model.phase == .signedOut)
    }

    @Test func theServerEndingTheSessionSignsOut() async {
        let model = makeModel(config: FakeConfig(nil), tokens: InMemoryTokenStore(someTokens))
        await model.start()

        model.handleSessionEnded()

        #expect(model.phase == .signedOut)
    }

    @Test func theSessionEndingDoesNotHideTheUpdateWall() async {
        let model = makeModel(config: FakeConfig(config(updateRequired: true)), tokens: InMemoryTokenStore(someTokens))
        await model.start()

        model.handleSessionEnded()

        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func returningAfterMoreThanAnHourAsksTheServerAgain() async {
        let server = FakeConfig(config(updateRequired: false))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        await server.set(config(updateRequired: true))
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(3_601))

        #expect(await server.loads == 2)
        #expect(model.phase == .updateRequired(emergencyNumber: "112"))
    }

    @Test func returningWithinTheHourDoesNotAskAgain() async {
        let server = FakeConfig(config(updateRequired: false))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(600))

        #expect(await server.loads == 1)
        #expect(model.phase == .signedIn)
    }

    @Test func theWallComesDownWhenTheServerNoLongerRequiresAnUpdate() async {
        let server = FakeConfig(config(updateRequired: true))
        let model = makeModel(config: server, tokens: InMemoryTokenStore(someTokens))
        await model.start()
        await server.set(config(updateRequired: false))
        let leftAt = Date(timeIntervalSince1970: 1_791_027_069)

        model.sceneDidEnterBackground(at: leftAt)
        await model.sceneDidBecomeActive(at: leftAt.addingTimeInterval(3_601))

        #expect(model.phase == .signedIn)
    }
}
```

Testlarda `FakeConfig` uchun mahalliy nom `server` — `config` nomi global `config(updateRequired:)` funksiyasini yashirib qo'ygan bo'lardi.

- [ ] **Step 3: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Kutilgan: `cannot find 'AppModel' in scope`.

- [ ] **Step 4: Implementatsiya**

`AppModel.swift`:

```swift
import Foundation
import Observation
import NozirAuth
import NozirConfig

public enum AppPhase: Equatable, Sendable {
    case launching
    case updateRequired(emergencyNumber: String?)
    case signedOut
    case signedIn
}

/// Which of the app's top-level states is showing, and every move between them.
@MainActor
@Observable
public final class AppModel {
    public private(set) var phase: AppPhase = .launching

    /// openapi: re-fetch the config after more than an hour in the background.
    private let configRefreshAfter: TimeInterval = 3_600
    private let config: any ConfigLoading
    private let tokens: any TokenStore
    private let sessionEnded: AsyncStream<Void>
    private let logout: @Sendable () async throws -> Void
    private var backgroundedAt: Date?

    public init(
        config: any ConfigLoading,
        tokens: any TokenStore,
        sessionEnded: AsyncStream<Void>,
        logout: @escaping @Sendable () async throws -> Void
    ) {
        self.config = config
        self.tokens = tokens
        self.sessionEnded = sessionEnded
        self.logout = logout
    }

    public func start() async {
        await evaluate()
    }

    public func didSignIn() {
        phase = .signedIn
    }

    /// Tells the server first, then forgets the session whether or not the
    /// server heard: a parent who pressed "sign out" is signed out.
    public func signOut() async {
        try? await logout()
        tokens.clear()
        phase = .signedOut
    }

    /// The refresher found the session revoked or expired. The update wall,
    /// if it is up, stays up.
    public func handleSessionEnded() {
        if phase == .signedIn {
            phase = .signedOut
        }
    }

    public func watchSessionEnd() async {
        for await _ in sessionEnded {
            handleSessionEnded()
        }
    }

    public func sceneDidEnterBackground(at date: Date) {
        backgroundedAt = date
    }

    public func sceneDidBecomeActive(at date: Date) async {
        guard let left = backgroundedAt else { return }
        backgroundedAt = nil
        guard date.timeIntervalSince(left) > configRefreshAfter else { return }
        await evaluate()
    }

    private func evaluate() async {
        let loaded = await config.load()
        if UpdateGate.blocks(loaded) {
            phase = .updateRequired(emergencyNumber: loaded?.emergencyContacts.emergencyNumber)
            return
        }
        phase = tokens.load() == nil ? .signedOut : .signedIn
    }
}
```

- [ ] **Step 5: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add NozirKit/Package.swift NozirKit/Sources/NozirAppFeature/AppModel.swift NozirKit/Tests/NozirAppFeatureTests/AppModelTests.swift
```

Xabar: `app: launching, the wall, signed in and signed out, and every way between`

---

### Task 11: Kirish ekrani mantig'i — `SignInModel`, matnlar, xato xabarlari

Matnlar Android `res/values/strings.xml` dan aynan ko'chirilgan (o'zbek `ʻ` — U+02BB). Android'dagi "telefon raqami bilan kiring" yo'li iOS'da yo'q (foydalanuvchi qarori), shuning uchun faqat-Telegram variantlari olingan.

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Copy.swift`
- Create: `NozirKit/Sources/NozirAppFeature/UserMessage.swift`
- Create: `NozirKit/Sources/NozirAppFeature/SignInModel.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignInModelTests.swift`

**Interfaces:**
- Consumes: `TelegramSignInService`, `TelegramLoginStart` (Task 8); `ApiFailure`, `ApiError`, `ApiErrorCode` (Task 4).
- Produces:
  - `enum Copy` (internal) — barcha foydalanuvchi matnlari.
  - `enum UserMessage { static func text(for error: any Error) -> String }` (internal)
  - `public enum SignInStage: Equatable, Sendable { case choice, telegramCode }`
  - `@MainActor @Observable public final class SignInModel { stage; isBusy; isTelegramAvailable; code; codeLength; codeMinutes; message: String?; botLink: URL?; canVerify: Bool; init(service: any TelegramSignInService, onSignedIn: @escaping @MainActor () -> Void); func chooseTelegram() async -> URL?; func telegramDidNotOpen(); func updateCode(_:); func verify() async }`

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
import NozirAuth
import NozirNetworking
@testable import NozirAppFeature

private let botStart = TelegramLoginStart(
    botUsername: "nozir_bot",
    deepLink: URL(string: "https://t.me/nozir_bot")!,
    codeLength: 6,
    codeTtlSeconds: 180
)

private actor FakeTelegram: TelegramSignInService {
    private let startResult: Result<TelegramLoginStart, ApiFailure>
    private let verifyResult: Result<Void, ApiFailure>
    private(set) var verifiedCodes: [String] = []

    init(start: Result<TelegramLoginStart, ApiFailure> = .success(botStart), verify: Result<Void, ApiFailure> = .success(())) {
        self.startResult = start
        self.verifyResult = verify
    }

    func start() async throws -> TelegramLoginStart {
        try startResult.get()
    }

    func verify(code: String) async throws {
        verifiedCodes.append(code)
        try verifyResult.get()
    }
}

private func failure(_ status: Int, _ code: ApiErrorCode, retryAfter: Int? = nil) -> ApiFailure {
    .server(status: status, error: ApiError(code: code, retryAfterSeconds: retryAfter))
}

@MainActor
@Suite struct SignInModelTests {
    @Test func choosingTelegramOpensTheBotAndAsksForTheCode() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})

        let link = await model.chooseTelegram()

        #expect(link == URL(string: "https://t.me/nozir_bot"))
        #expect(model.stage == .telegramCode)
        #expect(model.codeLength == 6)
        #expect(model.codeMinutes == 3)
        #expect(model.isBusy == false)
    }

    @Test func aServerWithoutABotTurnsTheButtonOff() async {
        let model = SignInModel(service: FakeTelegram(start: .failure(failure(503, .upstreamUnavailable))), onSignedIn: {})

        let link = await model.chooseTelegram()

        #expect(link == nil)
        #expect(model.isTelegramAvailable == false)
        #expect(model.stage == .choice)
    }

    @Test func noConnectionWhileStartingSaysSo() async {
        let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)
        let model = SignInModel(service: FakeTelegram(start: .failure(offline)), onSignedIn: {})

        _ = await model.chooseTelegram()

        #expect(model.message == Copy.Errors.noConnection)
        #expect(model.isTelegramAvailable)
    }

    // Review Focus 4.
    @Test(arguments: zip(
        ["123456", "123 456", "12-34-56", "1234567890", "١٢٣٤٥٦", "12a3"],
        ["123456", "123456", "123456", "123456", "", "123"]
    ))
    func theCodeKeepsOnlyASCIIDigitsUpToItsLength(typed: String, kept: String) async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.updateCode(typed)

        #expect(model.code == kept)
    }

    @Test func verifyIsOnlyPossibleWithAFullCode() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.updateCode("12345")
        #expect(!model.canVerify)
        model.updateCode("123456")
        #expect(model.canVerify)
    }

    @Test func aGoodCodeSignsIn() async {
        let telegram = FakeTelegram()
        var signedIn = false
        let model = SignInModel(service: telegram, onSignedIn: { signedIn = true })
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(await telegram.verifiedCodes == ["123456"])
        #expect(signedIn)
    }

    @Test(arguments: [ApiErrorCode.otpCodeInvalid, .otpCodeExpired])
    func aRejectedCodeIsClearedAndExplained(code: ApiErrorCode) async {
        let model = SignInModel(service: FakeTelegram(verify: .failure(failure(400, code))), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(model.code == "")
        #expect(model.message == Copy.SignIn.codeRejected)
    }

    @Test func tooManyAttemptsSaysHowLongToWait() async {
        let model = SignInModel(service: FakeTelegram(verify: .failure(failure(429, .rateLimited, retryAfter: 42))), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.updateCode("123456")

        await model.verify()

        #expect(model.message == Copy.Errors.rateLimited(seconds: 42))
        #expect(model.code == "123456")
    }

    @Test func telegramNotOpeningIsSaidPlainly() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()

        model.telegramDidNotOpen()

        #expect(model.message == Copy.SignIn.telegramNotOpened)
    }

    @Test func typingClearsAnOldMessage() async {
        let model = SignInModel(service: FakeTelegram(), onSignedIn: {})
        _ = await model.chooseTelegram()
        model.telegramDidNotOpen()

        model.updateCode("1")

        #expect(model.message == nil)
    }
}

@Suite struct UserMessageTests {
    @Test func theServerMessageIsNeverShown() {
        let failure = ApiFailure.server(status: 500, error: ApiError(code: .internalError, message: "NullPointerException at line 42"))
        #expect(UserMessage.text(for: failure) == Copy.Errors.serverProblem)
    }

    @Test func aTimeoutIsNotCalledANoConnection() {
        let timeout = ApiFailure.network(code: URLError.Code.timedOut.rawValue)
        #expect(UserMessage.text(for: timeout) == Copy.Errors.timeout)
    }

    @Test func rateLimitedWithoutASecondsCountStillReads() {
        #expect(UserMessage.text(for: failure(429, .rateLimited)) == Copy.Errors.rateLimited(seconds: nil))
    }

    @Test func anErrorThatIsNotAnApiFailureIsAServerProblem() {
        struct Odd: Error {}
        #expect(UserMessage.text(for: Odd()) == Copy.Errors.serverProblem)
    }
}
```

`aGoodCodeSignsIn` dagi `var signedIn` `@MainActor` closure ichida o'zgartiriladi — test ham `@MainActor`, shuning uchun Swift 6 bunga ruxsat beradi.

- [ ] **Step 2: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Kutilgan: `cannot find 'SignInModel' in scope`, `cannot find 'Copy' in scope`.

- [ ] **Step 3: Implementatsiya**

`Copy.swift`:

```swift
/// Every sentence a parent reads, in Uzbek, copied from the Android app's
/// `res/values/strings.xml` so both apps say the same thing.
enum Copy {
    enum Welcome {
        static let title = "Bolangizning telefonini kuzatmang"
        static let body = "Nozir sizga faqat muhim narsani aytadi. Yozishmalarni hech kim oʻqimaydi — AI xulosa qiladi, siz esa nima qilish kerakligini bilasiz."
        static let benefitSummary = "Kunlik AI xulosa"
        static let benefitScreenTime = "Ekran vaqti va uyqu rejimi"
        static let benefitLocation = "Joylashuv va SOS"
        static let start = "Boshlash"
        static let haveAccount = "Hisobim bor"
        static let logoDescription = "Nozir belgisi"
    }

    enum SignIn {
        static let title = "Nozirga kirish"
        static let subtitleTelegramOnly = "Telegram orqali kiring"
        static let subtitleNoWayIn = "Hozir kirish imkoni yoʻq. Birozdan keyin qayta urinib koʻring."
        static let telegramButton = "Telegram orqali kirish"
        static let telegramWhy = "Raqamingiz Telegram orqali tasdiqlanadi. Muhim xabarlar ham shu bot orqali keladi."
        static let codeTitle = "Botdan kelgan kodni kiriting"
        static func codeSubtitle(minutes: Int) -> String {
            "Telegramda «Start» bosing, raqamingizni ulashing — bot kod yuboradi. Kod \(minutes) daqiqa amal qiladi."
        }
        static let codePlaceholder = "000000"
        static let verify = "Tasdiqlash"
        static let openBotAgain = "Botni qayta ochish"
        static let codeRejected = "Kod mos kelmadi yoki muddati tugadi. Botdan yangi kod soʻrang."
        static let telegramNotOpened = "Telegram ochilmadi. Telefoningizda Telegram oʻrnatilganini tekshiring va qayta urinib koʻring."
        static let privacyNote = "Maʼlumotlaringiz Oʻzbekiston qonunchiligiga muvofiq saqlanadi. Uchinchi shaxslarga sotilmaydi."
    }

    enum Update {
        static let title = "Ilovani yangilash kerak"
        static let body = "Bu versiya endi qoʻllab-quvvatlanmaydi. Qoidalar, tarix va farzandingizning telefoni joyida qoladi — faqat ilovani yangilash kifoya."
        static let action = "Yangilash"
        static let storeMissing = "Doʻkon ochilmadi. Ilovani App Store orqali qoʻlda yangilang."
        static func callEmergency(_ number: String) -> String {
            "Favqulodda: \(number)"
        }
        static let dialerMissing = "Qoʻngʻiroq ilovasi ochilmadi. Raqamni telefon klaviaturasida tering."
    }

    enum Home {
        static let title = "Siz Nozirga kirdingiz"
        static let body = "Asosiy ekran keyingi bosqichda quriladi."
        static let signOut = "Chiqish"
    }

    enum Errors {
        static let noConnection = "Internet aloqasi yoʻq. Ulanishni tekshirib, qayta urinib koʻring."
        static let timeout = "Server javobi juda uzoq kutildi. Qayta urinamizmi?"
        static let serviceUnavailable = "Xizmat hozir javob bermayapti. Bir necha daqiqadan keyin qayta urinamizmi?"
        static let serverProblem = "Serverda nosozlik. Bir necha daqiqadan keyin qayta urinamizmi?"
        static let sessionEnded = "Sessiya yakunlandi. Telegram orqali qaytadan kiring."
        static func rateLimited(seconds: Int?) -> String {
            guard let seconds else {
                return "Soʻrovlar juda tez ketdi. Biroz kutib, qayta urinib koʻring."
            }
            return "Soʻrovlar juda tez ketdi. \(seconds) soniyadan keyin qayta urinib koʻring."
        }
    }
}
```

`Copy.Update.storeMissing` va `Copy.Errors.sessionEnded` — Android matnlaridan iOS uchun moslashtirilgan ("Play Store" → "App Store", "Telefon raqamingizni" → "Telegram orqali"); qolganlari aynan.

`UserMessage.swift`:

```swift
import Foundation
import NozirNetworking

/// The one sentence a parent sees for a failure. Branches on the code and the
/// status only; the server's own `message` is for logs and never reaches here.
enum UserMessage {
    static func text(for error: any Error) -> String {
        guard let failure = error as? ApiFailure else { return Copy.Errors.serverProblem }
        switch failure {
        case .network(let code):
            return code == URLError.Code.timedOut.rawValue ? Copy.Errors.timeout : Copy.Errors.noConnection
        case .server(let status, let apiError):
            if apiError.code == .rateLimited {
                return Copy.Errors.rateLimited(seconds: apiError.retryAfterSeconds)
            }
            if status == 503 || apiError.code == .upstreamUnavailable {
                return Copy.Errors.serviceUnavailable
            }
            return Copy.Errors.serverProblem
        case .sessionEnded:
            return Copy.Errors.sessionEnded
        case .decoding, .unexpectedStatus:
            return Copy.Errors.serverProblem
        }
    }
}
```

`SignInModel.swift`:

```swift
import Foundation
import Observation
import NozirAuth
import NozirNetworking

public enum SignInStage: Equatable, Sendable {
    case choice
    case telegramCode
}

/// P02: open the bot, then type the code it sent.
@MainActor
@Observable
public final class SignInModel {
    public private(set) var stage: SignInStage = .choice
    public private(set) var isBusy = false
    public private(set) var isTelegramAvailable = true
    public private(set) var code = ""
    public private(set) var codeLength = 6
    public private(set) var codeMinutes = 3
    public private(set) var message: String?
    public private(set) var botLink: URL?

    private let service: any TelegramSignInService
    private let onSignedIn: @MainActor () -> Void

    public init(service: any TelegramSignInService, onSignedIn: @escaping @MainActor () -> Void) {
        self.service = service
        self.onSignedIn = onSignedIn
    }

    public var canVerify: Bool {
        code.count == codeLength && !isBusy
    }

    /// Asks the server for the bot and returns the link to open, or nil when
    /// there is nothing to open (the reason is then in `message` or in
    /// `isTelegramAvailable`).
    public func chooseTelegram() async -> URL? {
        guard !isBusy else { return nil }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            let started = try await service.start()
            codeLength = started.codeLength
            codeMinutes = max(1, Int((Double(started.codeTtlSeconds) / 60).rounded(.up)))
            botLink = started.deepLink
            code = ""
            stage = .telegramCode
            return started.deepLink
        } catch let failure as ApiFailure where failure.isServiceUnavailable {
            isTelegramAvailable = false
            return nil
        } catch {
            message = UserMessage.text(for: error)
            return nil
        }
    }

    public func telegramDidNotOpen() {
        message = Copy.SignIn.telegramNotOpened
    }

    /// Keeps ASCII digits only, up to the code's length: the backend accepts
    /// `[0-9]` and nothing else, and a pasted "123 456" is still the code.
    public func updateCode(_ input: String) {
        let digits = input.filter { $0.isASCII && $0.isNumber }
        code = String(digits.prefix(codeLength))
        message = nil
    }

    public func verify() async {
        guard canVerify else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await service.verify(code: code)
            onSignedIn()
        } catch let failure as ApiFailure where failure.code == .otpCodeInvalid || failure.code == .otpCodeExpired {
            // Wrong, expired and never-existed are one answer on the server; one here too.
            code = ""
            message = Copy.SignIn.codeRejected
        } catch {
            message = UserMessage.text(for: error)
        }
    }
}

extension ApiFailure {
    var isServiceUnavailable: Bool {
        guard case .server(let status, let error) = self else { return false }
        return status == 503 || error.code == .upstreamUnavailable
    }
}
```

- [ ] **Step 4: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NozirKit/Sources/NozirAppFeature/Copy.swift NozirKit/Sources/NozirAppFeature/UserMessage.swift NozirKit/Sources/NozirAppFeature/SignInModel.swift NozirKit/Tests/NozirAppFeatureTests/SignInModelTests.swift
```

Xabar: `sign-in: the bot, the code, and one plain sentence for every failure`

- [ ] **Step 6: Code review (Config + AppFeature mantig'i)**

**superpowers:requesting-code-review** — `NozirConfig`, `AppModel`, `SignInModel`, `UserMessage`, spec 6.1, 6.2, 7, 8-bo'limlarga qarshi. Topilmalar **superpowers:receiving-code-review** bilan.

---
### Task 12: Dizayn tizimi — Android tokenlari va asosiy komponentlar

Manba: `NozirParent/app/src/main/java/tut/mobile/nozirparent/core/designsystem/` — `NozirLightColors.kt`, `NozirDarkColors.kt`, `NozirTonalColor.kt` (qorong'i konteyner = rang 12%, chegara 30%), `NozirSpacing.kt`, `NozirShapes.kt`, `NozirSizing.kt`, `NozirTypography.kt`, `component/NozirButton*.kt`, `NozirLogoMark.kt`, `NozirBulletRow.kt`, `NozirTextField.kt`, `NozirInlineMessage.kt`. Faqat poydevor ekranlari ishlatadigan rollar ko'chiriladi.

View'lar uchun unit test yo'q (spec 9: UI testlar YAGNI). Rang aylantirish mantig'i test qilinadi; ko'rinish — `#Preview` va Task 13 dagi simulyator tekshiruvi orqali.

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/NozirColor.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/NozirMetrics.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/NozirText.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirButton.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirCodeField.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirLogoMark.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirMessages.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/DesignSystemGallery.swift`
- Test: `NozirKit/Tests/NozirDesignSystemTests/NozirColorTests.swift`

**Interfaces:**
- Produces:
  - `public enum NozirColor` — `primary onPrimary primaryAccent primaryContainer background card border divider track textPrimary textSecondary textTertiary textDisabled goodContent goodContainer actionContent criticalContent criticalBorder` (hammasi `Color`); internal `static func uiColor(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> UIColor`
  - `public enum NozirSpacing` (`extraSmall 4, small 8, compact 12, medium 16, large 20, extraLarge 24, section 32`), `public enum NozirRadius` (`cardCompact 12, field 12, button 11, logo 17`), `public enum NozirSize` (`buttonCallToAction 52, buttonStandard 48, control 52, icon 24, logo 56, logoRing 24, logoStroke 4, borderResting 1.5, borderEmphasis 2`)
  - `public enum NozirTextStyle { headline, titleLarge, titleSmall, body, bodySmall, label }`, `extension View { public func nozirText(_:color:) -> some View }`
  - `public struct NozirButton: View { init(_ title: String, variant: NozirButtonVariant = .primary, size: NozirButtonSize = .standard, isLoading: Bool = false, action: @escaping () -> Void) }`, `public enum NozirButtonVariant { primary, secondary, ghost, criticalOutline }`, `public enum NozirButtonSize { callToAction, standard }`
  - `public struct NozirCodeField: View { init(code: Binding<String>, placeholder: String) }`
  - `public struct NozirLogoMark: View { init(accessibilityLabel: String) }`
  - `public struct NozirInlineMessage: View { init(_ text: String) }`, `public struct NozirBulletRow: View { init(_ text: String) }`, `public struct NozirPrivacyNote: View { init(_ text: String) }`

- [ ] **Step 1: `Package.swift` — yakuniy `targets` massivi**

```swift
    targets: [
        .target(name: "NozirNetworking"),
        .target(name: "NozirAuth", dependencies: ["NozirNetworking"]),
        .target(name: "NozirConfig", dependencies: ["NozirNetworking"]),
        .target(name: "NozirDesignSystem"),
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem"]
        ),
        .target(
            name: "NozirTestSupport",
            dependencies: ["NozirNetworking"],
            path: "Tests/NozirTestSupport"
        ),
        .testTarget(name: "NozirNetworkingTests", dependencies: ["NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirAuthTests", dependencies: ["NozirAuth", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirConfigTests", dependencies: ["NozirConfig", "NozirNetworking", "NozirTestSupport"]),
        .testTarget(name: "NozirDesignSystemTests", dependencies: ["NozirDesignSystem"]),
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking"]
        ),
    ]
```

- [ ] **Step 2: Failing test**

```swift
import Testing
import UIKit
@testable import NozirDesignSystem

private func components(_ color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return (red, green, blue, alpha)
}

@MainActor
@Suite struct NozirColorTests {
    @Test func aHexLiteralBecomesItsSRGBComponents() {
        let rgb = RGB(hex: 0x0E9F8F)
        #expect(abs(rgb.red - 14.0 / 255) < 0.0001)
        #expect(abs(rgb.green - 159.0 / 255) < 0.0001)
        #expect(abs(rgb.blue - 143.0 / 255) < 0.0001)
    }

    // NozirTonalColor.onDarkSurface: a dark container is its colour at 12%.
    @Test func darkModeUsesTheDarkValueWithItsAlpha() {
        let color = NozirColor.uiColor(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
        let dark = components(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)))
        #expect(abs(dark.red - CGFloat(0x0F) / 255) < 0.001)
        #expect(abs(dark.green - CGFloat(0xA7) / 255) < 0.001)
        #expect(abs(dark.blue - CGFloat(0x99) / 255) < 0.001)
        #expect(abs(dark.alpha - 0.12) < 0.001)
    }

    @Test func lightModeUsesTheLightValueOpaque() {
        let color = NozirColor.uiColor(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
        let light = components(color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)))
        #expect(abs(light.red - CGFloat(0xE7) / 255) < 0.001)
        #expect(abs(light.alpha - 1) < 0.001)
    }
}
```

- [ ] **Step 3: Run (FAIL kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Kutilgan: `NozirDesignSystem` target'ida manba yo'q / `cannot find 'RGB' in scope`.

- [ ] **Step 4: Ranglar, o'lchamlar, matn uslublari**

`NozirColor.swift`:

```swift
import SwiftUI
import UIKit

/// One colour from a 0xRRGGBB literal, as the Android palette writes it.
struct RGB: Equatable {
    let red: Double
    let green: Double
    let blue: Double

    init(hex: UInt32) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
    }
}

/// Android `NozirLightColors` / `NozirDarkColors`, the roles the foundation's
/// screens use. Dark containers and borders are their colour at 12% and 30%,
/// as `NozirTonalColor.onDarkSurface` draws them.
public enum NozirColor {
    public static let primary = color(light: 0x0E9F8F, dark: 0x0FA799)
    public static let onPrimary = color(light: 0xFFFFFF, dark: 0x04211E)
    public static let primaryAccent = color(light: 0x0B8478, dark: 0x2BB9A9)
    public static let primaryContainer = color(light: 0xDCF4F0, dark: 0x0B3F39)
    public static let background = color(light: 0xFBFAF8, dark: 0x141A19)
    public static let card = color(light: 0xFFFFFF, dark: 0x1F2725)
    public static let border = color(light: 0xDCE4E2, dark: 0x28322F)
    public static let divider = color(light: 0xEEF2F1, dark: 0x28322F)
    public static let track = color(light: 0xEEF2F1, dark: 0x28322F)
    public static let textPrimary = color(light: 0x0F1A19, dark: 0xE6ECEA)
    public static let textSecondary = color(light: 0x5B6B68, dark: 0x8FA5A1)
    public static let textTertiary = color(light: 0x8B9A97, dark: 0x5B6B68)
    public static let textDisabled = color(light: 0xB8C4C1, dark: 0x5B6B68)
    public static let goodContent = color(light: 0x0B7A5E, dark: 0x2BB9A9)
    public static let goodContainer = color(light: 0xE7F4EF, dark: 0x0FA799, darkAlpha: 0.12)
    public static let actionContent = color(light: 0xC2410C, dark: 0xF0803F)
    public static let criticalContent = color(light: 0xB91C1C, dark: 0xE66767)
    public static let criticalBorder = color(light: 0xF4C7C7, dark: 0xE66767, darkAlpha: 0.30)

    static func uiColor(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(hex: dark, alpha: darkAlpha)
                : UIColor(hex: light, alpha: 1)
        }
    }

    private static func color(light: UInt32, dark: UInt32, darkAlpha: Double = 1) -> Color {
        Color(uiColor: uiColor(light: light, dark: dark, darkAlpha: darkAlpha))
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: Double) {
        let rgb = RGB(hex: hex)
        self.init(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: alpha)
    }
}
```

`NozirMetrics.swift`:

```swift
import CoreGraphics

/// Android `NozirSpacing` at the reference width.
public enum NozirSpacing {
    public static let extraSmall: CGFloat = 4
    public static let small: CGFloat = 8
    public static let compact: CGFloat = 12
    public static let medium: CGFloat = 16
    public static let large: CGFloat = 20
    public static let extraLarge: CGFloat = 24
    public static let section: CGFloat = 32
}

/// Android `NozirShapes` corner radii.
public enum NozirRadius {
    public static let cardCompact: CGFloat = 12
    public static let field: CGFloat = 12
    public static let button: CGFloat = 11
    public static let logo: CGFloat = 17
}

/// Android `NozirSizing` and component constants.
public enum NozirSize {
    public static let buttonCallToAction: CGFloat = 52
    public static let buttonStandard: CGFloat = 48
    public static let control: CGFloat = 52
    public static let icon: CGFloat = 24
    public static let logo: CGFloat = 56
    public static let logoRing: CGFloat = 24
    public static let logoStroke: CGFloat = 4
    public static let borderResting: CGFloat = 1.5
    public static let borderEmphasis: CGFloat = 2
}
```

`NozirText.swift`:

```swift
import SwiftUI

/// Android `NozirTypography`, the styles the foundation uses. Unlike the
/// Android `sp` values these scale with Dynamic Type, relative to the nearest
/// system style. Line height is approximated with `lineSpacing`.
public enum NozirTextStyle: Sendable {
    case headline, titleLarge, titleSmall, body, bodySmall, label

    var size: CGFloat {
        switch self {
        case .headline: 30
        case .titleLarge: 22
        case .titleSmall: 17
        case .body: 16
        case .bodySmall: 13
        case .label: 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .headline: 36
        case .titleLarge: 28
        case .titleSmall: 23
        case .body: 24
        case .bodySmall: 19
        case .label: 14
        }
    }

    var weight: Font.Weight {
        switch self {
        case .headline, .label: .bold
        case .titleLarge, .titleSmall: .semibold
        case .body, .bodySmall: .regular
        }
    }

    var relativeTo: Font.TextStyle {
        switch self {
        case .headline: .title
        case .titleLarge: .title2
        case .titleSmall: .headline
        case .body: .body
        case .bodySmall: .footnote
        case .label: .caption2
        }
    }
}

struct NozirTextModifier: ViewModifier {
    let style: NozirTextStyle
    let color: Color
    @ScaledMetric private var size: CGFloat
    @ScaledMetric private var lineHeight: CGFloat

    init(style: NozirTextStyle, color: Color) {
        self.style = style
        self.color = color
        _size = ScaledMetric(wrappedValue: style.size, relativeTo: style.relativeTo)
        _lineHeight = ScaledMetric(wrappedValue: style.lineHeight, relativeTo: style.relativeTo)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: style.weight))
            .lineSpacing(max(0, lineHeight - size * 1.2))
            .foregroundStyle(color)
    }
}

extension View {
    public func nozirText(_ style: NozirTextStyle, color: Color = NozirColor.textPrimary) -> some View {
        modifier(NozirTextModifier(style: style, color: color))
    }
}
```

- [ ] **Step 5: Run (PASS kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Kutilgan: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Komponentlar**

`Components/NozirButton.swift`:

```swift
import SwiftUI

public enum NozirButtonVariant: Sendable {
    case primary, secondary, ghost, criticalOutline
}

public enum NozirButtonSize: Sendable {
    case callToAction, standard

    var height: CGFloat {
        switch self {
        case .callToAction: NozirSize.buttonCallToAction
        case .standard: NozirSize.buttonStandard
        }
    }
}

/// Android `NozirButton` with its colour table (`NozirButtonVariantColors.kt`).
/// A disabled button keeps its outline, so a row of actions keeps its shape.
public struct NozirButton: View {
    private let title: String
    private let variant: NozirButtonVariant
    private let size: NozirButtonSize
    private let isLoading: Bool
    private let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    public init(
        _ title: String,
        variant: NozirButtonVariant = .primary,
        size: NozirButtonSize = .standard,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(contentColor)
                } else {
                    Text(title)
                        .nozirText(.titleSmall, color: contentColor)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, minHeight: size.height)
            .padding(.horizontal, NozirSpacing.large)
            .background(RoundedRectangle(cornerRadius: NozirRadius.button).fill(containerColor))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.button)
                    .strokeBorder(borderColor, lineWidth: NozirSize.borderResting)
            )
            .contentShape(RoundedRectangle(cornerRadius: NozirRadius.button))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(title)
    }

    private var containerColor: Color {
        if variant == .ghost { return .clear }
        guard isEnabled else { return NozirColor.track }
        return variant == .primary ? NozirColor.primary : NozirColor.card
    }

    private var contentColor: Color {
        guard isEnabled else { return NozirColor.textDisabled }
        switch variant {
        case .primary: return NozirColor.onPrimary
        case .secondary, .ghost: return NozirColor.primaryAccent
        case .criticalOutline: return NozirColor.criticalContent
        }
    }

    private var borderColor: Color {
        let hasOutline = variant == .secondary || variant == .criticalOutline
        guard isEnabled else { return hasOutline ? NozirColor.border : .clear }
        switch variant {
        case .secondary: return NozirColor.primary
        case .criticalOutline: return NozirColor.criticalBorder
        case .primary, .ghost: return .clear
        }
    }
}
```

`Components/NozirCodeField.swift`:

```swift
import SwiftUI

/// The code box on P02: number pad, one-time-code autofill, focused on appear.
public struct NozirCodeField: View {
    @Binding private var code: String
    private let placeholder: String
    @FocusState private var isFocused: Bool

    public init(code: Binding<String>, placeholder: String) {
        _code = code
        self.placeholder = placeholder
    }

    public var body: some View {
        TextField("", text: $code, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .focused($isFocused)
            .nozirText(.body)
            .padding(.horizontal, NozirSpacing.medium)
            .frame(minHeight: NozirSize.control)
            .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.field)
                    .strokeBorder(NozirColor.primary, lineWidth: NozirSize.borderEmphasis)
            )
            .onAppear { isFocused = true }
    }
}
```

`Components/NozirLogoMark.swift`:

```swift
import SwiftUI

/// Android `NozirLogoMark`: a teal tile with an open ring and a light tail.
/// Arc angles match Compose's (0° at three o'clock, clockwise).
public struct NozirLogoMark: View {
    private let label: String

    public init(accessibilityLabel: String) {
        label = accessibilityLabel
    }

    public var body: some View {
        let ring = NozirSize.logoRing - NozirSize.logoStroke
        RoundedRectangle(cornerRadius: NozirRadius.logo)
            .fill(NozirColor.primary)
            .frame(width: NozirSize.logo, height: NozirSize.logo)
            .overlay {
                ZStack {
                    Circle()
                        .trim(from: 0.125, to: 0.875)
                        .stroke(NozirColor.onPrimary, lineWidth: NozirSize.logoStroke)
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(NozirColor.primaryContainer, lineWidth: NozirSize.logoStroke)
                        .rotationEffect(.degrees(315))
                }
                .frame(width: ring, height: ring)
            }
            .accessibilityElement()
            .accessibilityLabel(label)
    }
}
```

`Components/NozirMessages.swift`:

```swift
import SwiftUI

/// Android `NozirInlineMessage`: one sentence under a field or a button.
public struct NozirInlineMessage: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.bodySmall, color: NozirColor.actionContent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Android `NozirBulletRow`: a tick in a soft green disc, then the text.
public struct NozirBulletRow: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.compact) {
            Text("✓")
                .nozirText(.label, color: NozirColor.goodContent)
                .frame(width: NozirSize.icon, height: NozirSize.icon)
                .background(Circle().fill(NozirColor.goodContainer))
                .accessibilityHidden(true)
            Text(text).nozirText(.body)
        }
    }
}

/// Android `SignInPrivacyNote`: a lock and one reassuring sentence.
public struct NozirPrivacyNote: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: NozirSpacing.small) {
            Text("🔒")
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .accessibilityHidden(true)
            Text(text).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
        .padding(NozirSpacing.compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(NozirColor.divider))
    }
}
```

`Components/DesignSystemGallery.swift`:

```swift
import SwiftUI

#Preview("Nozir components") {
    ScrollView {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: "Nozir")
            Text("Headline").nozirText(.headline)
            Text("Body text").nozirText(.body, color: NozirColor.textSecondary)
            NozirButton("Primary", size: .callToAction) {}
            NozirButton("Loading", isLoading: true) {}
            NozirButton("Secondary", variant: .secondary) {}
            NozirButton("Ghost", variant: .ghost) {}
            NozirButton("Critical", variant: .criticalOutline) {}
            NozirButton("Disabled", variant: .secondary) {}.disabled(true)
            NozirBulletRow("Bullet row")
            NozirInlineMessage("Inline message")
            NozirPrivacyNote("Privacy note")
            NozirCodeField(code: .constant(""), placeholder: "000000")
        }
        .padding(NozirSpacing.medium)
    }
    .background(NozirColor.background)
}
```

- [ ] **Step 7: Run va ko'z bilan tekshiruv**

Run: `./scripts/test.sh` (butun to'plam)
Kutilgan: `** TEST SUCCEEDED **`.

Foydalanuvchi: Xcode'da `NozirKit/Sources/NozirDesignSystem/Components/DesignSystemGallery.swift` ni ochib Canvas'da preview'ni ko'radi, so'ng Canvas'dagi "Color Scheme Variants" bilan qorong'i rejimni ham. Android ilovadagi tugmalar bilan yonma-yon solishtirib skrinshot yuboradi. Farq bo'lsa — keyingi qadamdan oldin tuzatiladi.

- [ ] **Step 8: Commit**

```bash
git add NozirKit/Package.swift NozirKit/Sources/NozirDesignSystem NozirKit/Tests/NozirDesignSystemTests/NozirColorTests.swift
```

Xabar: `design: the Android palette, sizes and the five components the first screens need`

---

### Task 13: Ekranlar, kompozitsiya ildizi va ilovani ulash

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/RootView.swift` (o'rinbosar to'liq almashtiriladi)
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SignedOutFlow.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/WelcomeView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SignInView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/UpdateRequiredView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/HomePlaceholderView.swift`
- Create: `NozirIOS/ApiHost.swift`
- Modify: `NozirIOS/NozirIOSApp.swift`

**Interfaces:**
- Consumes: hamma oldingi tasklar.
- Produces: `@MainActor public final class AppEnvironment { appModel: AppModel; static func live(baseURL: URL, appVersion: String, osVersion: String, deviceLabel: String) -> AppEnvironment }`; `public struct RootView: View { init(environment: AppEnvironment) }`.

View'lar mantiqsiz: holat `AppModel`/`SignInModel` da, ular Task 10–11 da test qilingan. Bu task'ning dalili — kompilyatsiya va Step 8–9 dagi qo'lda tekshiruv.

- [ ] **Step 1: Kompozitsiya ildizi**

`AppEnvironment.swift`:

```swift
import Foundation
import NozirAuth
import NozirConfig
import NozirNetworking

/// Every live object, built once at launch and wired here and nowhere else.
@MainActor
public final class AppEnvironment {
    public let appModel: AppModel
    /// Nil until the app has an App Store ID (no developer account yet).
    let appStoreURL: URL?
    private let telegramSignIn: any TelegramSignInService

    init(appModel: AppModel, telegramSignIn: any TelegramSignInService, appStoreURL: URL?) {
        self.appModel = appModel
        self.telegramSignIn = telegramSignIn
        self.appStoreURL = appStoreURL
    }

    public static func live(baseURL: URL, appVersion: String, osVersion: String, deviceLabel: String) -> AppEnvironment {
        let identity = ClientIdentity(appVersion: appVersion, osVersion: osVersion)
        let anonymous = ApiClient(baseURL: baseURL, transport: URLSessionTransport(), identity: identity)
        let store = KeychainTokenStore()
        // Refresh goes through the anonymous client: refreshing must never
        // itself need a fresh access token.
        let anonymousAuth = AuthApi(client: anonymous)
        let refresher = TokenRefresher(store: store, refresh: { try await anonymousAuth.refresh($0) })
        let authorisedAuth = AuthApi(client: anonymous.withTokens(refresher))
        let config = ConfigLoader(
            api: ConfigApi(client: anonymous),
            cache: UserDefaultsConfigCache(),
            appVersion: appVersion
        )
        let appModel = AppModel(
            config: config,
            tokens: store,
            sessionEnded: refresher.sessionEnded,
            logout: { try await authorisedAuth.logout() }
        )
        return AppEnvironment(
            appModel: appModel,
            telegramSignIn: TelegramSignIn(api: anonymousAuth, store: store, deviceLabel: deviceLabel),
            appStoreURL: nil
        )
    }

    func makeSignInModel() -> SignInModel {
        SignInModel(service: telegramSignIn, onSignedIn: { [appModel] in appModel.didSignIn() })
    }
}
```

- [ ] **Step 2: Ildiz view**

`RootView.swift` (to'liq almashtirish):

```swift
import SwiftUI
import NozirDesignSystem

/// Shows whichever top-level state AppModel is in and reports scene changes to it.
public struct RootView: View {
    private let environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    public init(environment: AppEnvironment) {
        self.environment = environment
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NozirColor.background.ignoresSafeArea())
            .task { await environment.appModel.start() }
            .task { await environment.appModel.watchSessionEnd() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background:
                    environment.appModel.sceneDidEnterBackground(at: Date())
                case .active:
                    Task { await environment.appModel.sceneDidBecomeActive(at: Date()) }
                default:
                    break
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch environment.appModel.phase {
        case .launching:
            ProgressView().tint(NozirColor.primary)
        case .updateRequired(let emergencyNumber):
            UpdateRequiredView(emergencyNumber: emergencyNumber, appStoreURL: environment.appStoreURL)
        case .signedOut:
            SignedOutFlow(environment: environment)
        case .signedIn:
            HomePlaceholderView(onSignOut: {
                Task { await environment.appModel.signOut() }
            })
        }
    }
}
```

- [ ] **Step 3: P01 Welcome va kirish navigatsiyasi**

`Screens/SignedOutFlow.swift`:

```swift
import SwiftUI

/// P01 → P02. Both Welcome buttons lead to sign-in: on iOS there is no
/// sign-up separate from signing in through the bot.
struct SignedOutFlow: View {
    let environment: AppEnvironment
    @State private var showsSignIn = false

    var body: some View {
        NavigationStack {
            WelcomeView(onStart: { showsSignIn = true }, onSignIn: { showsSignIn = true })
                .navigationDestination(isPresented: $showsSignIn) {
                    SignInView(model: environment.makeSignInModel())
                }
        }
    }
}
```

`Screens/WelcomeView.swift`:

```swift
import SwiftUI
import NozirDesignSystem

/// P01, laid out as Android `WelcomeScreen`: the promise centred, the actions at the bottom.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    promise
                        .padding(.horizontal, NozirSpacing.extraLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            VStack(spacing: NozirSpacing.small) {
                NozirButton(Copy.Welcome.start, size: .callToAction, action: onStart)
                NozirButton(Copy.Welcome.haveAccount, variant: .ghost, action: onSignIn)
            }
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.bottom, NozirSpacing.extraLarge)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Welcome.title)
                .nozirText(.headline)
                .padding(.top, NozirSpacing.large)
            Text(Copy.Welcome.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.compact)
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                NozirBulletRow(Copy.Welcome.benefitSummary)
                NozirBulletRow(Copy.Welcome.benefitScreenTime)
                NozirBulletRow(Copy.Welcome.benefitLocation)
            }
            .padding(.top, NozirSpacing.extraLarge)
        }
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}
```

- [ ] **Step 4: P02 Sign in**

`Screens/SignInView.swift`:

```swift
import SwiftUI
import NozirDesignSystem

/// P02 as Android `SignInChoiceStep` + `TelegramCodeStep`, Telegram only.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.openURL) private var openURL

    init(model: SignInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                switch model.stage {
                case .choice:
                    choice
                case .telegramCode:
                    codeStep
                }
                NozirPrivacyNote(Copy.SignIn.privacyNote)
                    .padding(.top, NozirSpacing.extraLarge)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.SignIn.title).nozirText(.titleLarge)
            Text(model.isTelegramAvailable ? Copy.SignIn.subtitleTelegramOnly : Copy.SignIn.subtitleNoWayIn)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            if model.isTelegramAvailable {
                NozirButton(Copy.SignIn.telegramButton, isLoading: model.isBusy) {
                    Task {
                        if let link = await model.chooseTelegram() { open(link) }
                    }
                }
                .padding(.top, NozirSpacing.large)
                Text(Copy.SignIn.telegramWhy)
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                    .padding(.top, NozirSpacing.small)
            }
            if let message = model.message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.medium)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Copy.SignIn.codeTitle).nozirText(.titleLarge)
            Text(Copy.SignIn.codeSubtitle(minutes: model.codeMinutes))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            NozirCodeField(
                code: Binding(get: { model.code }, set: { model.updateCode($0) }),
                placeholder: Copy.SignIn.codePlaceholder
            )
            .padding(.top, NozirSpacing.large)
            if let message = model.message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.small)
            }
            NozirButton(Copy.SignIn.verify, size: .callToAction, isLoading: model.isBusy) {
                Task { await model.verify() }
            }
            // Not `canVerify`: that is false while busy and would grey the button;
            // NozirButton already blocks taps while it shows the spinner.
            .disabled(model.code.count != model.codeLength)
            .padding(.top, NozirSpacing.large)
            NozirButton(Copy.SignIn.openBotAgain, variant: .secondary) {
                if let link = model.botLink { open(link) }
            }
            .padding(.top, NozirSpacing.small)
        }
    }

    private func open(_ link: URL) {
        openURL(link) { accepted in
            if !accepted {
                Task { @MainActor in model.telegramDidNotOpen() }
            }
        }
    }
}
```

- [ ] **Step 5: Yangilash devori va Home o'rinbosari**

`Screens/UpdateRequiredView.swift`:

```swift
import SwiftUI
import NozirDesignSystem

/// Android `UpdateRequiredScreen`: update, and the emergency number stays one tap away.
struct UpdateRequiredView: View {
    let emergencyNumber: String?
    let appStoreURL: URL?
    @Environment(\.openURL) private var openURL
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Update.title)
                .nozirText(.titleLarge)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.medium)
            Text(Copy.Update.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.small)
            NozirButton(Copy.Update.action, size: .callToAction) { openStore() }
                .padding(.top, NozirSpacing.large)
            if let message {
                NozirInlineMessage(message).padding(.top, NozirSpacing.compact)
            }
            if let emergencyNumber {
                NozirButton(Copy.Update.callEmergency(emergencyNumber), variant: .criticalOutline) {
                    call(emergencyNumber)
                }
                .padding(.top, NozirSpacing.medium)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openStore() {
        guard let appStoreURL else {
            message = Copy.Update.storeMissing
            return
        }
        openURL(appStoreURL) { accepted in
            if !accepted {
                Task { @MainActor in message = Copy.Update.storeMissing }
            }
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else {
            message = Copy.Update.dialerMissing
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in message = Copy.Update.dialerMissing }
            }
        }
    }
}

#Preview {
    UpdateRequiredView(emergencyNumber: "112", appStoreURL: nil)
}
```

`Screens/HomePlaceholderView.swift`:

```swift
import SwiftUI
import NozirDesignSystem

/// Stands in for P05 until the next sub-project builds it.
struct HomePlaceholderView: View {
    let onSignOut: () -> Void

    var body: some View {
        VStack(spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: Copy.Welcome.logoDescription)
            Text(Copy.Home.title).nozirText(.titleLarge)
            Text(Copy.Home.body)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            NozirButton(Copy.Home.signOut, variant: .secondary, action: onSignOut)
                .padding(.top, NozirSpacing.large)
        }
        .padding(.horizontal, NozirSpacing.large)
    }
}
```

- [ ] **Step 6: Ilova target'i**

`NozirIOS/ApiHost.swift`:

```swift
import Foundation

/// Which server the app talks to. One host for every build, as on Android.
/// A Debug build can be pointed elsewhere with the scheme's environment
/// variable `NOZIR_API_BASE_URL` (Edit Scheme → Run → Arguments).
enum ApiHost {
    static let production = URL(string: "https://nozir.syncoder.uz")!

    static var current: URL {
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["NOZIR_API_BASE_URL"],
           let url = URL(string: override) {
            return url
        }
        #endif
        return production
    }
}
```

`NozirIOS/NozirIOSApp.swift` (to'liq almashtirish):

```swift
import SwiftUI
import UIKit
import NozirAppFeature

@main
struct NozirIOSApp: App {
    @State private var environment: AppEnvironment

    init() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        _environment = State(initialValue: AppEnvironment.live(
            baseURL: ApiHost.current,
            appVersion: version,
            osVersion: UIDevice.current.systemVersion,
            deviceLabel: UIDevice.current.model
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(environment: environment)
        }
    }
}
```

Lokal backend `http://` bo'lsa ATS uni bloklaydi — bu poydevorda kerak emas (ishlab chiqarish hosti `https`). Kerak bo'lganda alohida qaror.

- [ ] **Step 7: Build va testlar**

Run: `./scripts/test.sh` va

```bash
xcodebuild build -project NozirIOS.xcodeproj -scheme NozirIOS -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO 2>&1 | tail -5
```

Kutilgan: `** TEST SUCCEEDED **` va `** BUILD SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add NozirKit/Sources/NozirAppFeature NozirIOS/ApiHost.swift NozirIOS/NozirIOSApp.swift
```

Xabar: `app: welcome, sign in through the bot, the update wall and a home to land on`

- [ ] **Step 9: Haqiqiy backend bilan qo'lda tekshiruv (foydalanuvchi, simulyator)**

Har bir band uchun natija (skrinshot yoki "ha/yo'q") yuboriladi:

1. Ilova ochiladi → P01 Welcome. Light va Dark rejimda (Settings → Developer → Dark Appearance) Android bilan solishtiring.
2. "Hisobim bor" → P02 → "Telegram orqali kirish" → simulyatorda Safari'da `t.me/<bot>` ochiladi. Telefoningizdagi Telegram'da botni oching, Start, raqamni ulashing → kod keladi.
3. Simulyatorda ilovaga qayting → kod ekrani, "Kod 3 daqiqa amal qiladi" (server `codeTtlSeconds` ga qarab) → kodni kiriting → "Tasdiqlash" → Home o'rinbosari.
4. Ilovani to'xtatib (Cmd+.) qayta ishga tushiring → to'g'ridan-to'g'ri Home (Keychain ishlayapti).
5. "Chiqish" → Welcome.
6. Yana kirishda noto'g'ri kod `000000` → "Kod mos kelmadi yoki muddati tugadi. Botdan yangi kod soʻrang."
7. Mac'da Wi-Fi'ni o'chirib, "Telegram orqali kirish" → "Internet aloqasi yoʻq…". Wi-Fi'ni qayta yoqing.
8. Majburiy yangilanish: target → General → Version'ni vaqtincha `0.9` qiling → ishga tushiring → "Ilovani yangilash kerak" va "Favqulodda: <raqam>" tugmasi. "Yangilash" → "Doʻkon ochilmadi…" (App Store ID hali yo'q). Version'ni qaytaring (commit qilinmaydi — `git status` toza bo'lishi kerak).

Biror band kutilganidek bo'lmasa — **superpowers:systematic-debugging**, keyin tuzatish uchun alohida qadam va commit.

---

### Task 14: Yakuniy tekshiruv va butun branch review

- [ ] **Step 1: To'liq test to'plami lokal va CI'da**

Foydalanuvchi: `./scripts/test.sh` → `** TEST SUCCEEDED **`; `git push` → GitHub Actions `verify` yashil. Ikkala chiqish ham chatga yuboriladi.

- [ ] **Step 2: Butun branch code review**

**superpowers:requesting-code-review** — butun `NozirIOS` repo, spec'ning barcha bo'limlariga va ushbu rejaning "Review Focus" ro'yxatiga qarshi. Topilmalar **superpowers:receiving-code-review** bilan; tuzatishlar TDD bilan, alohida commit'lar.

- [ ] **Step 3: Verification before completion**

**superpowers:verification-before-completion**: spec 1-bo'limdagi to'rtta muvaffaqiyat mezoni har biri dalil bilan (test chiqishi, CI havolasi, Task 13 Step 9 natijalari) sanab chiqiladi. Dalili yo'q mezon — "bajarilmagan" deb aytiladi.

Bu rejaning qamrovi shu yerda tugaydi. Keyingi qadam — 2-sub-loyiha (asosiy ekranlar) uchun brainstorming.
