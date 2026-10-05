# Nozir iOS — 2a: Oila va ulanish (+ tillar va tema) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ota-ona bolasini qo'shadi (P03), boshlang'ich qoidalarni beradi (P03b), bola telefonini juftlaydi (P04), bolani tahrirlaydi/o'chiradi/faol qiladi, profilda (P21) temani va tilni (uz/ru/en) almashtiradi.

**Architecture:** Ikki yangi SPM moduli: `NozirL10n` — Android `strings.xml` dan Python skript bilan generatsiya qilingan, tipli `L10n` va `LanguageStore`; `NozirFamily` — family/rules/pairing/subscription/me API'lari, bitta `FamilyService` protokoli orqali, va `FamilyStore`. Ekran modellari `NozirAppFeature` da `@MainActor @Observable` sinflar, `FamilyStore` va `FamilyService` soxtasi bilan testlanadi. Matnlar modelda emas: modellar `UserMessage` enum'ini saqlaydi, view uni joriy tilda chizadi.

**Tech Stack:** Swift 6, SwiftUI (iOS 17), Observation, Swift Testing, CoreImage (QR), Python 3 (`unittest`, `xml.etree`) generator uchun.

**Spec:** `docs/superpowers/specs/2026-10-03-nozir-ios-family-onboarding-design.md` (va poydevor: `docs/superpowers/specs/2026-10-03-nozir-ios-foundation-design.md`)

## Global Constraints

- iOS deployment target 17.0; `swift-tools-version: 6.0` (Swift 6 rejimi, strict concurrency). Uchinchi tomon kutubxonasi yo'q.
- Base URL, `X-Nozir-Client`, token oqimi — poydevordagidek; har bir `/v1/parent/*` chaqiruvi `ApiClient` orqali (`requiresAuth: true`).
- Server `message` maydoni hech qachon ko'rsatilmaydi; foydalanuvchi matni faqat `L10n` dan.
- Tillar: `uz`, `ru`, `en`. Tarjimasi yo'q kalit uz matnini oladi. iOS'ga xos matnlar `NozirKit/l10n/ios/values{,-ru,-en}/strings.xml` da; bir xil kalitda iOS fayli ustun.
- `L10n.generated.swift` qo'lda tahrirlanmaydi; faqat `python3 scripts/gen_l10n.py` bilan. CI `--check` bilan tekshiradi.
- Til va tema UserDefaults'da: `nozir.appLanguage`, `nozir.appearance`; yuborilmagan til belgisi `nozir.appLanguage.unsent`.
- Kesh faqat xotirada (`FamilyStore`); diskka bola ma'lumoti yozilmaydi.
- Rules yozuvlari `If-Match: "<version>"` (qo'shtirnoq ichida) bilan; versiya oldingi javobning `version` maydonidan.
- Bola telefon raqami: `^\+998[0-9]{9}$`; ism 1–40 belgi (bo'shliqlar kesilgan); yosh 7–17.
- Avatar kalitlari: `teal`, `apricot`, `sky` (sukut `teal`).
- P03b sukutlari: dars kunlari 120 daq, dam olish 180 daq, bonus shifti 60 daq; uyqu 22:00–07:00, wind-down 30 daq, 7 kun (ISO 1…7).
- P04 so'rov oralig'i 4 soniya; faqat ekran ko'rinib turganda va ilova faol bo'lganda.
- Commit: faqat aniq yo'llar bilan `git add`; `git add -A` taqiqlangan; push foydalanuvchida. Commit muhiti va izohlari poydevor rejasidagidek (`GIT_AUTHOR_NAME=Zohidjon ...`, `Co-Authored-By` + `Claude-Session` qatorlari).
- Swift kodi test ishlaguncha "yozilgan, tekshirilmagan" hisoblanadi; Python testlarini Claude o'zi (`device_bash`) yuritadi, Swift testlarini — `scripts/test-watch.sh` yoki foydalanuvchi.

## Spec'dan chetlanishlar (reja bosqichida aniqlangan)

Reja yozilayotganda backend kodi, openapi va Android ilovasi o'qildi. Quyidagilar spec'dan farq qiladi; har biri sabab bilan:

| # | Spec | Reja | Sabab |
|---|---|---|---|
| D1 | P04 `GET pairing-code` da `PAIRED` holatini kutadi | Kod yo'qolsa (`404`) `GET /children/{id}` so'raladi: `pairingState == PAIRED` → "Juftlandi", aks holda "kod yo'q" | Backend `PairingServiceImpl.currentCode` faqat jonli (`CODE_ISSUED`/`APP_INSTALLED`) kodni qaytaradi; ishlatilgan kod `404` beradi. Android'da ham shu bo'shliq bor (alohida xabar qilinadi) |
| D2 | `404` → har doim `POST` | Bola juftlanmagan bo'lsa avtomatik `POST`; juftlangan bo'lsa "Kod olish" tugmasi va "qurilma almashtiriladi" tasdig'i | Yangi kod eski telefonni uzadi (backend `redeem`); Android ham so'raydi |
| D3 | Muddatgacha qolgan vaqt (taymer) | Statik "10 daqiqa amal qiladi"; muddat tugashi `404` orqali bilinadi | Android shunday; taymer qo'shimcha holat va testsiz foyda bermaydi |
| D4 | `PAIRED` dan 1.5 s keyin oqim yopiladi | "Bosh ekranga o'tish" tugmasi | Android shunday; vaqtga bog'liq yopilish testda mo'rt |
| D5 | `CONFLICT` da qayta o'qib bir marta avtomatik qayta urinish; baribir bo'lmasa P04 ga o'tish | Xato matni ko'rsatiladi, bola o'chirilmaydi; "Saqlash" qayta bosilsa bola qayta yaratilmaydi, qoidalar yangi versiya bilan yoziladi | openapi `RuleVersionConflict`: "never resend the same body against the new version" — avtomatik qayta yuborish taqiqlangan; Android ham shunday |
| D6 | Tug'ilgan yil 1990…joriy yil | Yosh 7–17 | Backend `AgeGroup` bandlari 7–17; Android shunday tekshiradi |
| D7 | Yosh rejimi override sifatida yuborilishi mumkin | Faqat ko'rsatiladi, yuborilmaydi | Android `AgeModeCard` faqat ko'rsatadi; `CreateChildBody` da bunday maydon yo'q |
| D8 | P21 da ism tahrirlash | Yo'q | Android'da UI ham, matn kalitlari ham yo'q |
| D9 | `ApiRequest.idempotencyKey` | Yo'q | `createChild` `@Idempotent` emas; 2a da kerak emas |
| D10 | `string-array` generatsiya qilinmaydi | Generatsiya qilinadi (`[String]`) | Uyqu kunlari uchun `weekday_names_short` kerak |
| D11 | Generator Android repo'dan to'g'ridan-to'g'ri o'qiydi; `gen-l10n.py` | Android matnlari `NozirKit/l10n/android/` ga nusxalanadi (`scripts/sync-android-strings.sh`); generator `scripts/gen_l10n.py` | CI'da Android repo yo'q; Python modul nomida `-` bo'lmaydi (testdan import) |
| D12 | `UserMessage` matn qaytaradi | `UserMessage` enum; view joriy tilda chizadi; xato kodlari Android jadvali bo'yicha (`PHONE_NUMBER_INVALID`, `VALIDATION_FAILED` → "kiritilgan ma'lumotlar to'g'ri kelmadi") | Til almashganda ko'rinib turgan xabar ham almashadi; Android bilan bir xil |
| D13 | iOS tizim elementlari tizim tilida | Ildizga `.environment(\.locale, …)` qo'yiladi — `DatePicker` kabi SwiftUI elementlari ilova tilida | Spec xavfi 1 ni qisman kamaytiradi; tizim dialoglari baribir tizim tilida |
| D14 | O'chirish — tasdiqlash dialogi | Sahifa ichidagi tasdiq kartasi | Android shunday, matnlari mavjud |
| D15 | — | iOS `bedtime_days_separator` = `", "` (qo'shtirnoqli) | Android qo'shtirnoqsiz `", "` ning oxirgi bo'shlig'ini kesadi deb hisoblayman (aapt), ro'yxat "Dushanba,Chorshanba" bo'lib chiqadi; iOS'da bo'shliq saqlanadi |

## Review Focus

Spec nazarda tutgan, lekin oddiy "baxtli yo'l" testlari ushlamaydigan beshta holat. Har birining testi egasi bo'lgan task'ga qo'shilgan:

1. **Bola kodni kiritdi — `GET pairing-code` endi `404`.** Ota-ona "Juftlandi" ni ko'rishi kerak, "kod yo'q" ni emas → Task 11 `aRedeemedCodeIsSeenThroughTheChild`.
2. **P03b qoidalar yozilmay qoldi, ota-ona "Saqlash" ni yana bosdi.** Ikkinchi bola yaratilmasligi kerak → Task 10 `savingAgainAfterAFailureDoesNotCreateASecondChild`.
3. **Ota-ona P04 dan chiqib ketdi yoki ilovani yopdi.** So'rov to'xtashi kerak → Task 11 `leavingTheScreenStopsThePolling`.
4. **Raqam "+998 90 123-45-67" ko'rinishida joylashtirildi.** To'qqiz xonali abonent raqami qolishi kerak → Task 8 `aPastedFullNumberKeepsTheSubscriberDigits`.
5. **Aka-ukasidan ko'chirilgan qoida slayder oralig'idan tashqarida (masalan 0 yoki 480 daqiqa).** Qiymat jimgina o'zgarmasligi kerak → Task 10 `siblingValuesOutsideTheSliderAreKeptAsTheyAre`.

---

## Fayl xaritasi

**Yangi:**

| Fayl | Vazifasi |
|---|---|
| `scripts/gen_l10n.py` | XML → `L10n.generated.swift` |
| `scripts/tests/test_gen_l10n.py` | Generator testlari |
| `scripts/sync-android-strings.sh` | Android matnlarini nusxalash + generatsiya |
| `NozirKit/l10n/android/values{,-en,-ru}/strings.xml` | Android matnlari nusxasi |
| `NozirKit/l10n/ios/values{,-en,-ru}/strings.xml` | iOS'ga xos matnlar |
| `NozirKit/Sources/NozirL10n/{AppLanguage,L10n,LanguageStore,L10n.generated}.swift` | Til moduli |
| `NozirKit/Sources/NozirFamily/{FamilyModels,RuleModels,AccountModels,FamilyService,FamilyApi,FamilyStore}.swift` | Oila moduli |
| `NozirKit/Sources/NozirDesignSystem/Appearance.swift` | Tema |
| `NozirKit/Sources/NozirDesignSystem/UzbekPhone.swift` | +998 raqam formati |
| `NozirKit/Sources/NozirDesignSystem/Components/{NozirFields,NozirAvatar,NozirCard,NozirRows,NozirQRCode}.swift` | Yangi komponentlar |
| `NozirKit/Sources/NozirAppFeature/{SignedInModel,LocaleSync,Durations}.swift` | Kirgan holat, til sinxroni, daqiqa matni |
| `NozirKit/Sources/NozirAppFeature/Family/{AddChildModel,NewChildRulesModel,PairingModel,ChildDetailsModel,ProfileModel}.swift` | Ekran modellari |
| `NozirKit/Sources/NozirAppFeature/Screens/{SignedInView,AddChildFlow,AddChildView,NewChildRulesView,PairingView,ChildDetailsView,ProfileView}.swift` | Ekranlar |
| `NozirKit/Tests/NozirL10nTests/*`, `NozirKit/Tests/NozirFamilyTests/*`, `NozirKit/Tests/NozirAppFeatureTests/{FakeFamily,…}.swift` | Testlar |

**O'zgaradi:** `NozirKit/Package.swift`, `NozirNetworking/{ApiRequest,ApiClient,ApiErrorCode}.swift`, `NozirTestSupport/HTTP.swift`, `NozirDesignSystem/NozirColor.swift`, `NozirAppFeature/{AppEnvironment,RootView,SignInModel,UserMessage}.swift`, `Screens/{WelcomeView,SignInView,UpdateRequiredView,HomePlaceholderView}.swift`, `.github/workflows/verify.yml`. **O'chiriladi:** `NozirAppFeature/Copy.swift`.

## Ishni boshlash

```bash
cd ~/XCodeProjects/NozirIOS && git checkout main && git checkout -b family-onboarding
```

Har bir Swift test qadamida "Run" — `./scripts/test.sh <Target>` (yoki watcher so'rovi `<Target>`); butun to'plam — `./scripts/test.sh`.

---
### Task 1: Tarjima generatori (Python) va Android matnlari nusxasi

**Files:**
- Create: `scripts/gen_l10n.py`
- Create: `scripts/tests/test_gen_l10n.py`
- Create: `scripts/sync-android-strings.sh`
- Create: `NozirKit/l10n/android/values{,-en,-ru}/strings.xml` (skript nusxalaydi)
- Create: `NozirKit/l10n/ios/values{,-en,-ru}/strings.xml`

**Interfaces:**
- Produces: `python3 scripts/gen_l10n.py [--check]` → `NozirKit/Sources/NozirL10n/L10n.generated.swift`, ichida `public extension L10n { … }`: argumentsiz kalit → `var <lowerCamel>: String`; argumentli → `func <lowerCamel>(_ arg1: Int|String, …) -> String`; `string-array` → `var <lowerCamel>: [String]`. Har biri `switch language { case .uz/.ru/.en }` (Task 2 dagi `L10n.language: AppLanguage`).

Bu task'ning testlari Python'da; Claude ularni `device_bash` da o'zi yuritadi (Xcode kerak emas).

- [ ] **Step 1: Failing testlarni yozish**

`scripts/tests/test_gen_l10n.py`:

```python
"""Tests for scripts/gen_l10n.py. Run: python3 -m unittest discover -s scripts/tests -v"""
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

import gen_l10n  # noqa: E402
from gen_l10n import L10nError  # noqa: E402


def write(root, folder, body):
    path = Path(root) / folder / "strings.xml"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("<resources>\n" + textwrap.dedent(body) + "</resources>\n", encoding="utf-8")


def tables(android, ios=None):
    """android/ios: {folder: xml body}. Returns collect() over temporary files."""
    with tempfile.TemporaryDirectory() as tmp:
        for folder, body in android.items():
            write(Path(tmp) / "android", folder, body)
        for folder, body in (ios or {}).items():
            write(Path(tmp) / "ios", folder, body)
        return gen_l10n.collect(Path(tmp) / "android", Path(tmp) / "ios")


class NamingTests(unittest.TestCase):
    def test_snake_case_becomes_lower_camel_case(self):
        self.assertEqual(gen_l10n.swift_name("sign_in_action_verify"), "signInActionVerify")
        self.assertEqual(gen_l10n.swift_name("glyph_2"), "glyph2")

    def test_a_reserved_word_is_refused(self):
        with self.assertRaises(L10nError):
            gen_l10n.swift_name("default")


class UnescapeTests(unittest.TestCase):
    def test_android_escapes_become_plain_text(self):
        self.assertEqual(gen_l10n.unescape(r"Don\'t say \"hi\"", "t"), "Don't say \"hi\"")
        self.assertEqual(gen_l10n.unescape(r"−", "t"), "−")
        self.assertEqual(gen_l10n.unescape(r"one\ntwo", "t"), "one\ntwo")

    def test_whitespace_collapses_like_android(self):
        self.assertEqual(gen_l10n.unescape("  a \n   b  ", "t"), "a b")

    def test_a_quoted_value_keeps_its_spaces(self):
        self.assertEqual(gen_l10n.unescape('"  a  b "', "t"), "  a  b ")

    def test_an_unknown_escape_is_an_error(self):
        with self.assertRaises(L10nError):
            gen_l10n.unescape(r"a\qb", "t")


class FormatTests(unittest.TestCase):
    def test_positional_arguments_are_typed(self):
        segments, types = gen_l10n.parse_format("%1$s, %2$d yosh", "t")
        self.assertEqual(types, ["String", "Int"])
        self.assertEqual(gen_l10n.swift_literal(segments), '"\\(arg1), \\(arg2) yosh"')

    def test_a_padded_number_keeps_its_padding(self):
        segments, types = gen_l10n.parse_format("%1$ds %2$02dd", "t")
        self.assertEqual(types, ["Int", "Int"])
        self.assertEqual(gen_l10n.swift_literal(segments), '"\\(arg1)s \\(String(format: "%02ld", arg2))d"')

    def test_a_double_percent_is_one_percent(self):
        segments, _ = gen_l10n.parse_format("%1$d%% off", "t")
        self.assertEqual(gen_l10n.swift_literal(segments), '"\\(arg1)% off"')

    def test_quotes_and_backslashes_are_escaped_for_swift(self):
        self.assertEqual(gen_l10n.swift_literal([("text", 'a "b" \\ c')]), '"a \\"b\\" \\\\ c"')

    def test_a_gap_in_the_numbering_is_an_error(self):
        with self.assertRaises(L10nError):
            gen_l10n.parse_format("%2$s", "t")

    def test_a_non_positional_argument_is_an_error(self):
        with self.assertRaises(L10nError):
            gen_l10n.parse_format("%s", "t")


class BuildTests(unittest.TestCase):
    def test_a_missing_translation_falls_back_to_uzbek(self):
        built = gen_l10n.build(tables({
            "values": '<string name="hello">Salom</string>',
            "values-en": "",
        }))
        _, _, _, values, _ = built[0]
        self.assertEqual(values["en"], [("text", "Salom")])

    def test_an_ios_string_wins_over_the_android_one(self):
        built = gen_l10n.build(tables(
            {"values": '<string name="store">Play Store</string>'},
            {"values": '<string name="store">App Store</string>'},
        ))
        self.assertEqual(built[0][3]["uz"], [("text", "App Store")])

    def test_arguments_that_differ_between_languages_are_an_error(self):
        with self.assertRaises(L10nError):
            gen_l10n.build(tables({
                "values": '<string name="age">%1$d yosh</string>',
                "values-ru": '<string name="age">%1$s лет</string>',
            }))

    def test_a_key_only_a_translation_has_is_an_error(self):
        with self.assertRaises(L10nError):
            gen_l10n.build(tables({
                "values": '<string name="a">A</string>',
                "values-en": '<string name="b">B</string>',
            }))

    def test_markup_inside_a_string_is_an_error(self):
        with self.assertRaises(L10nError):
            tables({"values": '<string name="a">A <b>bold</b></string>'})

    def test_an_array_becomes_a_list(self):
        built = gen_l10n.build(tables({
            "values": '<string-array name="days"><item>Du</item><item>Se</item></string-array>',
        }))
        swift = gen_l10n.render(built)
        self.assertIn('var days: [String] {', swift)
        self.assertIn('case .uz: ["Du", "Se"]', swift)


class RenderTests(unittest.TestCase):
    def test_a_string_with_arguments_becomes_a_function(self):
        built = gen_l10n.build(tables({
            "values": '<string name="add_child_age_mode">%1$d yosh — «%2$s» rejimi</string>',
            "values-en": '<string name="add_child_age_mode">%1$d years old — “%2$s” mode</string>',
        }))
        swift = gen_l10n.render(built)
        self.assertIn("    func addChildAgeMode(_ arg1: Int, _ arg2: String) -> String {", swift)
        self.assertIn('        case .uz: "\\(arg1) yosh — «\\(arg2)» rejimi"', swift)
        self.assertIn('        case .en: "\\(arg1) years old — “\\(arg2)” mode"', swift)
        self.assertIn('        case .ru: "\\(arg1) yosh — «\\(arg2)» rejimi"', swift)

    def test_a_plain_string_becomes_a_property(self):
        swift = gen_l10n.render(gen_l10n.build(tables({"values": '<string name="tab_home">Bosh</string>'})))
        self.assertIn("    var tabHome: String {", swift)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `cd ~/XCodeProjects/NozirIOS && python3 -m unittest discover -s scripts/tests -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'gen_l10n'`.

- [ ] **Step 3: Generatorni yozish**

`scripts/gen_l10n.py`:

```python
#!/usr/bin/env python3
"""Generates NozirKit/Sources/NozirL10n/L10n.generated.swift.

Reads the Android parent app's strings (a copy kept in NozirKit/l10n/android,
refreshed by scripts/sync-android-strings.sh) and the iOS-only strings in
NozirKit/l10n/ios. An iOS string wins over an Android one with the same key.

Usage: python3 scripts/gen_l10n.py           write the Swift file
       python3 scripts/gen_l10n.py --check   exit 1 if it is out of date
"""
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ANDROID = ROOT / "NozirKit" / "l10n" / "android"
IOS = ROOT / "NozirKit" / "l10n" / "ios"
OUTPUT = ROOT / "NozirKit" / "Sources" / "NozirL10n" / "L10n.generated.swift"

# (language, Android resource folder). The first is the base every other
# language falls back to.
LANGS = [("uz", "values"), ("ru", "values-ru"), ("en", "values-en")]
BASE = LANGS[0][0]

SWIFT_RESERVED = {
    "any", "as", "associatedtype", "break", "case", "catch", "class", "continue",
    "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
    "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init",
    "inout", "internal", "is", "language", "let", "nil", "open", "operator",
    "private", "protocol", "public", "repeat", "rethrows", "return", "self",
    "some", "static", "struct", "subscript", "super", "switch", "throw", "throws",
    "true", "try", "typealias", "var", "where", "while",
}

ESCAPES = {"\\": "\\", "'": "'", '"': '"', "n": "\n", "t": "\t", "@": "@", "?": "?"}

FORMAT = re.compile(r"%(?:(\d+)\$)?([-#+ 0,(]*)(\d*)([a-zA-Z%])")


class L10nError(Exception):
    pass


def swift_name(key):
    """`sign_in_action_verify` -> `signInActionVerify`."""
    if not re.fullmatch(r"[a-z][a-z0-9]*(_[a-z0-9]+)*", key):
        raise L10nError(f"unusable key: {key!r}")
    first, *rest = key.split("_")
    name = first + "".join(part[0].upper() + part[1:] for part in rest)
    if name in SWIFT_RESERVED:
        raise L10nError(f"key {key!r} becomes the reserved name {name!r}")
    return name


def unescape(raw, where):
    """Android resource text -> the text a person reads."""
    text = raw.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"' and text[-2] != "\\":
        text = text[1:-1]
    else:
        text = re.sub(r"[ \t\r\n]+", " ", text)
    out = []
    i = 0
    while i < len(text):
        char = text[i]
        if char == "\\":
            if i + 1 >= len(text):
                raise L10nError(f"{where}: trailing backslash")
            escaped = text[i + 1]
            if escaped == "u":
                digits = text[i + 2:i + 6]
                if not re.fullmatch(r"[0-9a-fA-F]{4}", digits):
                    raise L10nError(f"{where}: bad \\u escape")
                out.append(chr(int(digits, 16)))
                i += 6
                continue
            if escaped not in ESCAPES:
                raise L10nError(f"{where}: unsupported escape \\{escaped}")
            out.append(ESCAPES[escaped])
            i += 2
            continue
        if char == '"':
            raise L10nError(f"{where}: unescaped double quote")
        out.append(char)
        i += 1
    return "".join(out)


def parse_format(text, where):
    """Splits `%1$s, %2$d yosh` into text and argument segments.

    Returns (segments, argument types). A segment is ("text", str) or
    ("arg", index, printf spec or None).
    """
    segments = []
    types = {}
    position = 0
    for match in FORMAT.finditer(text):
        if match.start() > position:
            segments.append(("text", text[position:match.start()]))
        position = match.end()
        index, flags, width, conversion = match.groups()
        if conversion == "%":
            if index or flags or width:
                raise L10nError(f"{where}: malformed %%")
            segments.append(("text", "%"))
            continue
        if conversion not in ("s", "d"):
            raise L10nError(f"{where}: unsupported conversion %{conversion}")
        if index is None:
            raise L10nError(f"{where}: arguments must be positional (%1$s)")
        number = int(index)
        kind = "String" if conversion == "s" else "Int"
        if types.setdefault(number, kind) != kind:
            raise L10nError(f"{where}: argument {number} is used as two types")
        spec = None
        if flags or width:
            if conversion != "d":
                raise L10nError(f"{where}: width or flags on a string argument")
            # `ld`: a Swift Int is 64 bits, and String(format:) reads `%d` as 32.
            spec = f"%{flags}{width}ld"
        segments.append(("arg", number, spec))
    if position < len(text):
        segments.append(("text", text[position:]))
    count = max(types, default=0)
    if sorted(types) != list(range(1, count + 1)):
        raise L10nError(f"{where}: arguments must be numbered 1..n without gaps")
    return segments, [types[number] for number in range(1, count + 1)]


def load(path):
    """key -> ("string", text) or ("array", [texts]); {} when the file is absent."""
    if not path.exists():
        return {}
    entries = {}
    for element in ET.parse(path).getroot():
        name = element.get("name")
        where = f"{path.parent.name}/{path.name}:{name}"
        if element.tag == "string":
            if len(element):
                raise L10nError(f"{where}: markup inside a string is not supported")
            value = ("string", unescape(element.text or "", where))
        elif element.tag == "string-array":
            items = []
            for item in element:
                if item.tag != "item" or len(item):
                    raise L10nError(f"{where}: an array may hold plain <item>s only")
                items.append(unescape(item.text or "", where))
            value = ("array", items)
        elif element.tag == "plurals":
            raise L10nError(f"{where}: plurals are not supported yet")
        else:
            continue
        if name in entries:
            raise L10nError(f"{where}: defined twice")
        entries[name] = value
    return entries


def collect(android_dir, ios_dir):
    """language -> key -> value, iOS strings laid over Android ones."""
    tables = {}
    for language, folder in LANGS:
        table = load(android_dir / folder / "strings.xml")
        table.update(load(ios_dir / folder / "strings.xml"))
        tables[language] = table
    return tables


def build(tables):
    """Validated entries: (kind, key, swift name, language -> value, argument types)."""
    base = tables[BASE]
    for language, table in tables.items():
        extra = sorted(set(table) - set(base))
        if extra:
            raise L10nError(f"{language}: keys missing from the {BASE} base: {', '.join(extra)}")
    entries = []
    names = {}
    for key in sorted(base):
        name = swift_name(key)
        if name in names:
            raise L10nError(f"{key!r} and {names[name]!r} both become {name!r}")
        names[name] = key
        kind = base[key][0]
        values = {}
        for language, _ in LANGS:
            value = tables[language].get(key, base[key])
            if value[0] != kind:
                raise L10nError(f"{language}:{key}: a string in one language and an array in another")
            values[language] = value[1]
        if kind == "array":
            entries.append(("array", key, name, values, []))
            continue
        parsed = {language: parse_format(text, f"{language}:{key}") for language, text in values.items()}
        arguments = parsed[BASE][1]
        for language, (_, found) in parsed.items():
            if found != arguments:
                raise L10nError(f"{language}:{key}: arguments {found} differ from the {BASE} {arguments}")
        segments = {language: parsed[language][0] for language in values}
        entries.append(("string", key, name, segments, arguments))
    return entries


def swift_literal(segments):
    out = ['"']
    for segment in segments:
        if segment[0] == "text":
            for char in segment[1]:
                if char == "\\":
                    out.append("\\\\")
                elif char == '"':
                    out.append('\\"')
                elif char == "\n":
                    out.append("\\n")
                elif char == "\t":
                    out.append("\\t")
                elif ord(char) < 0x20:
                    out.append("\\u{%x}" % ord(char))
                else:
                    out.append(char)
        else:
            _, number, spec = segment
            if spec is None:
                out.append("\\(arg%d)" % number)
            else:
                out.append('\\(String(format: "%s", arg%d))' % (spec, number))
    out.append('"')
    return "".join(out)


HEADER = """\
// Generated by scripts/gen_l10n.py from NozirKit/l10n. Do not edit by hand:
// change the XML (or sync it from Android) and run `python3 scripts/gen_l10n.py`.

import Foundation

public extension L10n {
"""


def render(entries):
    lines = [HEADER.rstrip("\n")]
    for kind, key, name, values, arguments in entries:
        lines.append(f"    /// `{key}`")
        if kind == "array":
            lines.append(f"    var {name}: [String] {{")
        elif arguments:
            parameters = ", ".join(f"_ arg{number}: {kind_}" for number, kind_ in enumerate(arguments, 1))
            lines.append(f"    func {name}({parameters}) -> String {{")
        else:
            lines.append(f"    var {name}: String {{")
        lines.append("        switch language {")
        for language, _ in LANGS:
            if kind == "array":
                items = ", ".join(swift_literal([("text", item)]) for item in values[language])
                literal = f"[{items}]"
            else:
                literal = swift_literal(values[language])
            lines.append(f"        case .{language}: {literal}")
        lines.append("        }")
        lines.append("    }")
        lines.append("")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main(argv):
    check = "--check" in argv[1:]
    try:
        entries = build(collect(ANDROID, IOS))
    except L10nError as error:
        print(f"gen_l10n: {error}", file=sys.stderr)
        return 1
    swift = render(entries)
    if check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != swift:
            print("gen_l10n: L10n.generated.swift is out of date; run python3 scripts/gen_l10n.py", file=sys.stderr)
            return 1
        print(f"gen_l10n: up to date ({len(entries)} keys)")
        return 0
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(swift, encoding="utf-8")
    print(f"gen_l10n: wrote {len(entries)} keys to {OUTPUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

Keyin: `chmod +x scripts/gen_l10n.py`.

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `python3 -m unittest discover -s scripts/tests -v`
Expected: `Ran 20 tests … OK`.

- [ ] **Step 5: Sinxron skripti va iOS matnlari**

`scripts/sync-android-strings.sh`:

```bash
#!/usr/bin/env bash
# Copies the Android parent app's strings into NozirKit/l10n/android and
# regenerates L10n.generated.swift. Run after the Android strings change.
# Usage: ./scripts/sync-android-strings.sh [path/to/NozirParent]
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="${1:-$HOME/AndroidStudioProjects/NozirParent}/app/src/main/res"
for folder in values values-en values-ru; do
  mkdir -p "NozirKit/l10n/android/$folder"
  cp "$SOURCE/$folder/strings.xml" "NozirKit/l10n/android/$folder/strings.xml"
done
python3 scripts/gen_l10n.py
```

Keyin: `chmod +x scripts/sync-android-strings.sh`.

`NozirKit/l10n/ios/values/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<!-- iOS-only strings. A key here wins over the Android string with the same key. -->
<resources>
    <!-- The App Store, not Play Store. -->
    <string name="update_required_store_missing">Doʻkon ochilmadi. Ilovani App Store orqali qoʻlda yangilang.</string>
    <!-- iOS signs in through Telegram only. -->
    <string name="data_error_not_authenticated">Sessiya yakunlandi. Telegram orqali qaytadan kiring.</string>
    <!-- Home stands in until sub-project 2b builds P05. -->
    <string name="ios_home_placeholder_title">Siz Nozirga kirdingiz</string>
    <string name="ios_home_placeholder_body">Asosiy ekran keyingi bosqichda quriladi.</string>
    <!-- Android trims the trailing space of an unquoted ", ", so its night list
         reads "Dushanba,Chorshanba". Quoted here so the space survives. -->
    <string name="bedtime_days_separator">", "</string>
</resources>
```

`NozirKit/l10n/ios/values-en/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="update_required_store_missing">The store did not open. Update the app from the App Store by hand.</string>
    <string name="data_error_not_authenticated">Your session has ended. Sign in with Telegram again.</string>
    <string name="ios_home_placeholder_title">You are signed in to Nozir</string>
    <string name="ios_home_placeholder_body">The home screen comes in the next stage.</string>
</resources>
```

`NozirKit/l10n/ios/values-ru/strings.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="update_required_store_missing">Магазин не открылся. Обновите приложение вручную через App Store.</string>
    <string name="data_error_not_authenticated">Сессия завершена. Войдите через Telegram заново.</string>
    <string name="ios_home_placeholder_title">Вы вошли в Nozir</string>
    <string name="ios_home_placeholder_body">Главный экран появится на следующем этапе.</string>
</resources>
```

(en/ru iOS matnlarini Claude yozgan — foydalanuvchi ko'rib chiqadi.)

- [ ] **Step 6: Android matnlarini nusxalash va generatsiya**

Claude (`device_bash`, Android repo `$HOME/mnt/NozirParent` da):

```bash
cd "$HOME/mnt/XCodeProjects/NozirIOS" && ./scripts/sync-android-strings.sh "$HOME/mnt/NozirParent"
```

Expected: `gen_l10n: wrote 713 keys to NozirKit/Sources/NozirL10n/L10n.generated.swift` (Android: 708 satr + 3 massiv; iOS: 2 ta yangi kalit. Android matnlari o'zgargan bo'lsa son boshqacha — muhimi xatosiz tugashi). Keyin `python3 scripts/gen_l10n.py --check` → `up to date`.

Generatsiya qilingan faylni kompilyatsiya qilish Task 2 da (u yerda `L10n` turi paydo bo'ladi).

- [ ] **Step 7: Commit**

```bash
git status --short
git add scripts/gen_l10n.py scripts/tests/test_gen_l10n.py scripts/sync-android-strings.sh NozirKit/l10n NozirKit/Sources/NozirL10n/L10n.generated.swift
```

Xabar: `l10n: one generator turns the Android strings into typed Swift`

---
### Task 2: `NozirL10n` moduli — `AppLanguage`, `L10n`, `LanguageStore`; CI generatorni tekshiradi

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirL10n/AppLanguage.swift`
- Create: `NozirKit/Sources/NozirL10n/L10n.swift`
- Create: `NozirKit/Sources/NozirL10n/LanguageStore.swift`
- Test: `NozirKit/Tests/NozirL10nTests/L10nTests.swift`
- Modify: `.github/workflows/verify.yml`

**Interfaces:**
- Consumes: Task 1 dagi `L10n.generated.swift` (`public extension L10n`).
- Produces:
  - `public enum AppLanguage: String, CaseIterable, Sendable { case uz, ru, en }`; `static func preferred(from identifiers: [String]) -> AppLanguage`
  - `public struct L10n: Sendable, Equatable { public let language: AppLanguage; public init(_ language: AppLanguage) }`
  - `EnvironmentValues.l10n: L10n` (sukut `L10n(.uz)`)
  - `@MainActor @Observable public final class LanguageStore { public private(set) var current: AppLanguage; public var l10n: L10n; public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages); public func set(_ language: AppLanguage); static let key = "nozir.appLanguage" }`

- [ ] **Step 1: Package'ga target qo'shish**

`NozirKit/Package.swift` — `targets` ichida `.target(name: "NozirNetworking"),` dan keyin:

```swift
        .target(name: "NozirL10n"),
```

va test target'lar orasiga (`NozirDesignSystemTests` dan keyin):

```swift
        .testTarget(name: "NozirL10nTests", dependencies: ["NozirL10n"]),
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirL10nTests/L10nTests.swift`:

```swift
import Foundation
import Testing
@testable import NozirL10n

@Suite struct L10nTests {
    @Test func aStringFollowsTheLanguage() {
        #expect(L10n(.uz).welcomeTitle == "Bolangizning telefonini kuzatmang")
        #expect(L10n(.ru).welcomeTitle == "Не следите за телефоном ребёнка")
        #expect(L10n(.en).welcomeTitle == "Don't watch your child's phone")
    }

    @Test func argumentsLandWhereEachTranslationPutsThem() {
        #expect(L10n(.uz).addChildAgeMode(9, "Yulduzcha") == "9 yosh — «Yulduzcha» rejimi")
        #expect(L10n(.en).addChildAgeMode(9, "Star") == "9 years old — “Star” mode")
    }

    @Test func aPaddedNumberKeepsItsZero() {
        #expect(L10n(.uz).durationShortHoursMinutes(2, 5) == "2s 05d")
    }

    @Test func aStringWithoutATranslationIsUzbek() {
        #expect(L10n(.en).phoneFieldPrefix == "🇺🇿 +998")
    }

    @Test func anIOSStringReplacesTheAndroidOne() {
        #expect(L10n(.uz).updateRequiredStoreMissing.contains("App Store"))
        #expect(L10n(.en).dataErrorNotAuthenticated.contains("Telegram"))
        #expect(L10n(.ru).bedtimeDaysSeparator == ", ")
    }

    @Test func weekdaysStartOnMonday() {
        #expect(L10n(.uz).weekdayNamesShort == ["Du", "Se", "Ch", "Pa", "Ju", "Sh", "Ya"])
    }
}

@MainActor
@Suite struct LanguageStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "LanguageStoreTests.\(UUID().uuidString)")!
    }

    @Test func aSavedChoiceWins() {
        let defaults = freshDefaults()
        defaults.set("ru", forKey: LanguageStore.key)

        let store = LanguageStore(defaults: defaults, preferredLanguages: ["en-US"])

        #expect(store.current == .ru)
    }

    @Test func withoutAChoiceThePhonesFirstLanguageIsUsed() {
        let store = LanguageStore(defaults: freshDefaults(), preferredLanguages: ["ru-UZ", "en-US"])

        #expect(store.current == .ru)
    }

    @Test func aFirstLanguageNozirDoesNotSpeakMeansUzbek() {
        let store = LanguageStore(defaults: freshDefaults(), preferredLanguages: ["de-DE", "en-US"])

        #expect(store.current == .uz)
    }

    @Test func choosingChangesTheTextAndIsRemembered() {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz-UZ"])

        store.set(.en)

        #expect(store.l10n.welcomeTitle == "Don't watch your child's phone")
        #expect(LanguageStore(defaults: defaults, preferredLanguages: ["ru"]).current == .en)
    }
}
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirL10nTests`
Expected: FAIL — `cannot find type 'L10n' in scope` (generatsiya qilingan fayl `L10n` turini kengaytiradi, tur esa hali yo'q).

- [ ] **Step 4: Minimal implementatsiya**

`NozirKit/Sources/NozirL10n/AppLanguage.swift`:

```swift
/// The languages Nozir speaks, in the order the language picker lists them.
public enum AppLanguage: String, CaseIterable, Sendable {
    case uz, ru, en

    /// The phone's first preferred language if Nozir speaks it, Uzbek otherwise.
    /// Only the first: a parent whose phone is in German and then English has
    /// not asked for English.
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        guard let first = identifiers.first else { return .uz }
        let code = first.split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map { $0.lowercased() } ?? ""
        return AppLanguage(rawValue: code) ?? .uz
    }
}
```

`NozirKit/Sources/NozirL10n/L10n.swift`:

```swift
import SwiftUI

/// Every sentence a parent reads, in one language. The sentences themselves
/// are generated from the Android app's strings (`L10n.generated.swift`).
public struct L10n: Sendable, Equatable {
    public let language: AppLanguage

    public init(_ language: AppLanguage) {
        self.language = language
    }
}

private struct L10nKey: EnvironmentKey {
    static let defaultValue = L10n(.uz)
}

public extension EnvironmentValues {
    /// Set once at the root from `LanguageStore`; every view reads its text here.
    var l10n: L10n {
        get { self[L10nKey.self] }
        set { self[L10nKey.self] = newValue }
    }
}
```

`NozirKit/Sources/NozirL10n/LanguageStore.swift`:

```swift
import Foundation
import Observation

/// The language the parent chose in the app (P21), or the phone's if they
/// have not chosen. Views re-render when it changes because they read `l10n`.
@MainActor
@Observable
public final class LanguageStore {
    static let key = "nozir.appLanguage"

    public private(set) var current: AppLanguage
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard, preferredLanguages: [String] = Locale.preferredLanguages) {
        self.defaults = defaults
        if let saved = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) {
            current = saved
        } else {
            current = AppLanguage.preferred(from: preferredLanguages)
        }
    }

    public var l10n: L10n {
        L10n(current)
    }

    public func set(_ language: AppLanguage) {
        current = language
        defaults.set(language.rawValue, forKey: Self.key)
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirL10nTests`
Expected: `** TEST SUCCEEDED **`, 10 ta test o'tadi. (Birinchi kompilyatsiya generatsiya qilingan ~6400 qatorli fayl tufayli sekinroq bo'lishi mumkin.)

- [ ] **Step 6: CI generatorni tekshiradi**

`.github/workflows/verify.yml` — `Toolchain` qadamidan keyin, `NozirKit tests` dan oldin:

```yaml
      - name: Strings
        run: |
          python3 -m unittest discover -s scripts/tests -v
          python3 scripts/gen_l10n.py --check
```

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirL10n/AppLanguage.swift NozirKit/Sources/NozirL10n/L10n.swift NozirKit/Sources/NozirL10n/LanguageStore.swift NozirKit/Tests/NozirL10nTests .github/workflows/verify.yml
```

Xabar: `l10n: the app speaks the parent's chosen language`

---
### Task 3: Tarmoq — PUT/PATCH/DELETE, `If-Match`, yangi xato kodlari

**Files:**
- Modify: `NozirKit/Sources/NozirNetworking/ApiRequest.swift`
- Modify: `NozirKit/Sources/NozirNetworking/ApiClient.swift` (`makeURLRequest`)
- Modify: `NozirKit/Sources/NozirNetworking/ApiErrorCode.swift`
- Modify: `NozirKit/Sources/NozirNetworking/ApiFailure.swift`
- Modify: `NozirKit/Tests/NozirTestSupport/HTTP.swift`
- Test: `NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift`

**Interfaces:**
- Produces:
  - `HTTPMethod`: `.get, .post, .put, .patch, .delete`
  - `ApiRequest.ifMatch: String?` (init parametri `ifMatch: String? = nil`, `timeout` dan keyin)
  - `static func put<Body: Encodable>(_ path: String, json body: Body, ifMatch: String? = nil) throws -> ApiRequest`
  - `static func patch<Body: Encodable>(_ path: String, json body: Body) throws -> ApiRequest`
  - `ApiErrorCode`: `.forbidden, .notYourChild, .notFound, .conflict, .validationFailed, .missingIfMatch, .phoneNumberInvalid, .childLimitReached, .childNotActive, .subscriptionRequired`
  - `ApiFailure.isNotFound: Bool`
  - Test yordamchisi: `URLRequest.jsonObject: [String: Any]?`

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift`:

```swift
import Foundation
import Testing
import NozirTestSupport
@testable import NozirNetworking

private func client() -> ApiClient {
    ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: FakeTransport([]),
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5")
    )
}

@Suite struct ApiRequestTests {
    @Test func aRuleWriteCarriesTheVersionItWasMadeAgainst() throws {
        struct Limit: Encodable { let schoolDayMinutes: Int }
        let request = try ApiRequest.put("/v1/parent/children/c1/rules/screen-time", json: Limit(schoolDayMinutes: 120), ifMatch: "\"7\"")

        let urlRequest = client().makeURLRequest(request, bearer: "acc")

        #expect(urlRequest.httpMethod == "PUT")
        #expect(urlRequest.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(urlRequest.jsonObject?["schoolDayMinutes"] as? Int == 120)
    }

    @Test func anOrdinaryRequestHasNoIfMatch() {
        let urlRequest = client().makeURLRequest(ApiRequest(method: .get, path: "/v1/parent/children"), bearer: "acc")

        #expect(urlRequest.value(forHTTPHeaderField: "If-Match") == nil)
    }

    @Test func patchSendsJSON() throws {
        struct Body: Encodable { let locale: String }
        let urlRequest = client().makeURLRequest(try .patch("/v1/parent/me", json: Body(locale: "ru")), bearer: "acc")

        #expect(urlRequest.httpMethod == "PATCH")
        #expect(urlRequest.jsonBody == ["locale": "ru"])
    }

    @Test func deleteSendsNoBody() {
        let urlRequest = client().makeURLRequest(ApiRequest(method: .delete, path: "/v1/parent/children/c1"), bearer: "acc")

        #expect(urlRequest.httpMethod == "DELETE")
        #expect(urlRequest.httpBody == nil)
    }

    @Test func notFoundIsRecognisedWithOrWithoutTheErrorBody() {
        #expect(ApiFailure.server(status: 404, error: ApiError(code: .notFound)).isNotFound)
        #expect(ApiFailure.unexpectedStatus(404).isNotFound)
        #expect(!ApiFailure.server(status: 400, error: ApiError(code: .validationFailed)).isNotFound)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Expected: FAIL — `type 'ApiRequest' has no member 'put'`, `jsonObject` topilmadi.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirNetworking/ApiRequest.swift` — butun fayl:

```swift
import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// One call, described without knowing the host, the client header or the token.
public struct ApiRequest: Sendable {
    public var method: HTTPMethod
    /// Starts with "/", e.g. "/v1/config".
    public var path: String
    public var query: [String: String]
    public var body: Data?
    public var requiresAuth: Bool
    /// Seconds before the request gives up; nil keeps URLSession's default (60 s).
    public var timeout: TimeInterval?
    /// The entity tag a write was made against, e.g. `"7"` with the quotes
    /// (`IfMatchVersion.kt`). Every rules write needs one.
    public var ifMatch: String?

    public init(
        method: HTTPMethod,
        path: String,
        query: [String: String] = [:],
        body: Data? = nil,
        requiresAuth: Bool = true,
        timeout: TimeInterval? = nil,
        ifMatch: String? = nil
    ) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.requiresAuth = requiresAuth
        self.timeout = timeout
        self.ifMatch = ifMatch
    }

    public static func post<Body: Encodable>(
        _ path: String,
        json body: Body,
        requiresAuth: Bool = true
    ) throws -> ApiRequest {
        ApiRequest(method: .post, path: path, body: try NozirJSON.encoder().encode(body), requiresAuth: requiresAuth)
    }

    public static func put<Body: Encodable>(_ path: String, json body: Body, ifMatch: String? = nil) throws -> ApiRequest {
        ApiRequest(method: .put, path: path, body: try NozirJSON.encoder().encode(body), ifMatch: ifMatch)
    }

    public static func patch<Body: Encodable>(_ path: String, json body: Body) throws -> ApiRequest {
        ApiRequest(method: .patch, path: path, body: try NozirJSON.encoder().encode(body))
    }
}
```

`NozirKit/Sources/NozirNetworking/ApiClient.swift` — `makeURLRequest` ichida, `if let bearer {` blokidan oldin:

```swift
        if let ifMatch = request.ifMatch {
            urlRequest.setValue(ifMatch, forHTTPHeaderField: "If-Match")
        }
```

`NozirKit/Sources/NozirNetworking/ApiErrorCode.swift` — `internalError` qatoridan keyin:

```swift
    public static let forbidden = ApiErrorCode(rawValue: "FORBIDDEN")
    public static let notYourChild = ApiErrorCode(rawValue: "NOT_YOUR_CHILD")
    public static let notFound = ApiErrorCode(rawValue: "NOT_FOUND")
    public static let conflict = ApiErrorCode(rawValue: "CONFLICT")
    public static let validationFailed = ApiErrorCode(rawValue: "VALIDATION_FAILED")
    public static let missingIfMatch = ApiErrorCode(rawValue: "MISSING_IF_MATCH")
    public static let phoneNumberInvalid = ApiErrorCode(rawValue: "PHONE_NUMBER_INVALID")
    public static let childLimitReached = ApiErrorCode(rawValue: "CHILD_LIMIT_REACHED")
    public static let childNotActive = ApiErrorCode(rawValue: "CHILD_NOT_ACTIVE")
    public static let subscriptionRequired = ApiErrorCode(rawValue: "SUBSCRIPTION_REQUIRED")
```

`NozirKit/Sources/NozirNetworking/ApiFailure.swift` — `endsSession` dan keyin:

```swift
    /// A 404, with or without the error body. For the pairing code it is an
    /// answer ("no live code"), not a fault.
    public var isNotFound: Bool {
        switch self {
        case .server(let status, _): status == 404
        case .unexpectedStatus(let status): status == 404
        default: false
        }
    }
```

`NozirKit/Tests/NozirTestSupport/HTTP.swift` — `URLRequest` kengaytmasiga `jsonBody` dan keyin:

```swift
    /// The body as a JSON object with any value types, for numbers and nulls.
    var jsonObject: [String: Any]? {
        guard let httpBody else { return nil }
        return (try? JSONSerialization.jsonObject(with: httpBody)) as? [String: Any]
    }
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirNetworkingTests`
Expected: `** TEST SUCCEEDED **` — yangi 5 ta va avvalgi barcha networking testlari.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirNetworking NozirKit/Tests/NozirTestSupport/HTTP.swift NozirKit/Tests/NozirNetworkingTests/ApiRequestTests.swift
```

Xabar: `networking: writes that name the version they were made against`

---
### Task 4: Tema — `AppearanceStore`

**Files:**
- Create: `NozirKit/Sources/NozirDesignSystem/Appearance.swift`
- Test: `NozirKit/Tests/NozirDesignSystemTests/AppearanceStoreTests.swift`

**Interfaces:**
- Produces:
  - `public enum AppearanceMode: String, CaseIterable, Sendable { case light, dark, system; public var colorScheme: ColorScheme? }`
  - `@MainActor @Observable public final class AppearanceStore { public private(set) var mode: AppearanceMode; public init(defaults: UserDefaults = .standard); public func set(_ mode: AppearanceMode); static let key = "nozir.appearance" }`

- [ ] **Step 1: Failing testni yozish**

`NozirKit/Tests/NozirDesignSystemTests/AppearanceStoreTests.swift`:

```swift
import Foundation
import SwiftUI
import Testing
@testable import NozirDesignSystem

@MainActor
@Suite struct AppearanceStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "AppearanceStoreTests.\(UUID().uuidString)")!
    }

    @Test func aNewInstallFollowsThePhone() {
        let store = AppearanceStore(defaults: freshDefaults())

        #expect(store.mode == .system)
        #expect(store.mode.colorScheme == nil)
    }

    @Test func aChoiceIsRemembered() {
        let defaults = freshDefaults()
        AppearanceStore(defaults: defaults).set(.dark)

        let again = AppearanceStore(defaults: defaults)

        #expect(again.mode == .dark)
        #expect(again.mode.colorScheme == .dark)
    }

    @Test func lightMeansLight() {
        #expect(AppearanceMode.light.colorScheme == .light)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Expected: FAIL — `cannot find 'AppearanceStore' in scope`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirDesignSystem/Appearance.swift`:

```swift
import Foundation
import Observation
import SwiftUI

/// Android `ThemeMode`, in the order the picker lists it.
public enum AppearanceMode: String, CaseIterable, Sendable {
    case light, dark, system

    /// For `.preferredColorScheme`: nil follows the phone.
    public var colorScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }
}

/// The theme the parent chose on P21. Every colour in `NozirColor` already has
/// a light and a dark value, so the choice only has to reach the root view.
@MainActor
@Observable
public final class AppearanceStore {
    static let key = "nozir.appearance"

    public private(set) var mode: AppearanceMode
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        mode = defaults.string(forKey: Self.key).flatMap(AppearanceMode.init(rawValue:)) ?? .system
    }

    public func set(_ mode: AppearanceMode) {
        self.mode = mode
        defaults.set(mode.rawValue, forKey: Self.key)
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirDesignSystem/Appearance.swift NozirKit/Tests/NozirDesignSystemTests/AppearanceStoreTests.swift
```

Xabar: `design: the theme is the parent's choice, or the phone's`

---
### Task 5: Poydevor ekranlari `L10n` ga o'tadi; `UserMessage` — ma'no, matn emas; ildizda til va tema

**Files:**
- Modify: `NozirKit/Package.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/UserMessage.swift` (butunlay)
- Modify: `NozirKit/Sources/NozirAppFeature/SignInModel.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/RootView.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/Screens/{WelcomeView,SignInView,UpdateRequiredView,HomePlaceholderView}.swift` (butunlay)
- Delete: `NozirKit/Sources/NozirAppFeature/Copy.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift` (yangi)
- Modify: `NozirKit/Tests/NozirAppFeatureTests/SignInModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`L10n`, `LanguageStore`, `\.l10n`), Task 3 (yangi `ApiErrorCode` lar), Task 4 (`AppearanceStore`).
- Produces:
  - `public enum UserMessage: Equatable, Sendable` — `noConnection, timeout, serviceUnavailable, serverProblem, unreadableAnswer, sessionEnded, permissionDenied, notFound, invalidRequest, conflict, childLimitReached, subscriptionRequired, childNotActive, rateLimited(seconds: Int?), codeRejected, telegramNotOpened`; `public init(_ error: any Error)`; `public func text(_ l10n: L10n) -> String`
  - `SignInModel.message: UserMessage?`
  - `AppEnvironment.language: LanguageStore`, `AppEnvironment.appearance: AppearanceStore`

Xatolar jadvali (Android `DataErrorFromApiFailure` + `ApiFailureFromStatus`): avval kod (`RATE_LIMITED`, `UPSTREAM_UNAVAILABLE`, `CHILD_LIMIT_REACHED`, `SUBSCRIPTION_REQUIRED`, `CHILD_NOT_ACTIVE`, `CONFLICT`, `FORBIDDEN`/`NOT_YOUR_CHILD`, `NOT_FOUND`), keyin status (401 → sessiya tugadi, 404 → topilmadi, 408 → vaqt tugadi, 429 → juda tez, 503 → xizmat javob bermayapti, ≥500 → server nosozligi), qolgani → "kiritilgan ma'lumotlar to'g'ri kelmadi". Tarmoq: `timedOut` → vaqt tugadi, boshqasi → internet yo'q. Dekodlash → "javobni o'qib bo'lmadi".

- [ ] **Step 1: Package bog'liqliklari**

`NozirKit/Package.swift` — `NozirAppFeature` target'i:

```swift
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n"]
        ),
```

`NozirAppFeatureTests`:

```swift
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n"]
        ),
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift`:

```swift
import Foundation
import Testing
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private func server(_ status: Int, _ code: ApiErrorCode, retryAfter: Int? = nil) -> ApiFailure {
    .server(status: status, error: ApiError(code: code, retryAfterSeconds: retryAfter))
}

private struct CodeCase: Sendable {
    let status: Int
    let code: ApiErrorCode
    let expected: UserMessage
}

@Suite struct UserMessageTests {
    @Test func theServerMessageIsNeverShown() {
        let failure = ApiFailure.server(status: 500, error: ApiError(code: .internalError, message: "NullPointerException at line 42"))

        let message = UserMessage(failure)

        #expect(message == .serverProblem)
        #expect(message.text(L10n(.uz)) == L10n(.uz).dataErrorServerProblem)
    }

    @Test func aTimeoutIsNotCalledANoConnection() {
        #expect(UserMessage(ApiFailure.network(code: URLError.Code.timedOut.rawValue)) == .timeout)
        #expect(UserMessage(ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)) == .noConnection)
    }

    @Test(arguments: [
        CodeCase(status: 403, code: .childLimitReached, expected: .childLimitReached),
        CodeCase(status: 403, code: .childNotActive, expected: .childNotActive),
        CodeCase(status: 403, code: .subscriptionRequired, expected: .subscriptionRequired),
        CodeCase(status: 409, code: .conflict, expected: .conflict),
        CodeCase(status: 403, code: .forbidden, expected: .permissionDenied),
        CodeCase(status: 403, code: .notYourChild, expected: .permissionDenied),
        CodeCase(status: 400, code: .validationFailed, expected: .invalidRequest),
        CodeCase(status: 400, code: .phoneNumberInvalid, expected: .invalidRequest),
        CodeCase(status: 404, code: .notFound, expected: .notFound),
        CodeCase(status: 503, code: .upstreamUnavailable, expected: .serviceUnavailable),
        CodeCase(status: 502, code: .internalError, expected: .serverProblem),
    ])
    func aCodeBecomesItsMeaning(_ testCase: CodeCase) {
        #expect(UserMessage(server(testCase.status, testCase.code)) == testCase.expected)
    }

    @Test func aStatusWithoutTheErrorBodyStillMeansSomething() {
        #expect(UserMessage(ApiFailure.unexpectedStatus(404)) == .notFound)
        #expect(UserMessage(ApiFailure.unexpectedStatus(502)) == .serverProblem)
        #expect(UserMessage(ApiFailure.unexpectedStatus(418)) == .invalidRequest)
    }

    @Test func anAnswerThatCannotBeReadSaysSo() {
        #expect(UserMessage(ApiFailure.decoding("keyNotFound")) == .unreadableAnswer)
    }

    @Test func rateLimitedSaysHowLongWhenItKnows() {
        let l10n = L10n(.uz)
        #expect(UserMessage(server(429, .rateLimited, retryAfter: 42)).text(l10n) == l10n.dataErrorRateLimitedSeconds(42))
        #expect(UserMessage(server(429, .rateLimited)).text(l10n) == l10n.dataErrorRateLimited)
    }

    @Test func theSameMeaningReadsInEveryLanguage() {
        #expect(UserMessage.noConnection.text(L10n(.ru)) == L10n(.ru).dataErrorNoConnection)
        #expect(UserMessage.sessionEnded.text(L10n(.en)).contains("Telegram"))
    }

    @Test func anErrorThatIsNotAnApiFailureIsAServerProblem() {
        struct Odd: Error {}
        #expect(UserMessage(Odd()) == .serverProblem)
    }
}
```

`NozirKit/Tests/NozirAppFeatureTests/SignInModelTests.swift` — o'zgarishlar:

1. Fayl oxiridagi `@Suite struct UserMessageTests { … }` blokini butunlay o'chiring (yangi faylga ko'chdi).
2. Quyidagi almashtirishlar:

| Eski | Yangi |
|---|---|
| `#expect(model.message == Copy.Errors.noConnection)` | `#expect(model.message == .noConnection)` |
| `#expect(model.message == Copy.SignIn.codeRejected)` (2 joyda) | `#expect(model.message == .codeRejected)` |
| `#expect(model.message == Copy.Errors.rateLimited(seconds: 42))` | `#expect(model.message == .rateLimited(seconds: 42))` |
| `#expect(model.message == Copy.SignIn.telegramNotOpened)` | `#expect(model.message == .telegramNotOpened)` |

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `UserMessage` da `init(_:)` yo'q; `message` `String?` bo'lgani uchun `.noConnection` bilan solishtirib bo'lmaydi.

- [ ] **Step 4: `UserMessage` va `SignInModel`**

`NozirKit/Sources/NozirAppFeature/UserMessage.swift` — butun fayl:

```swift
import Foundation
import NozirL10n
import NozirNetworking

/// What a parent is told, kept as a meaning rather than a sentence: the view
/// renders it in the current language, so switching language also translates a
/// message already on screen. Branches on the code and the status only; the
/// server's own `message` never reaches here.
public enum UserMessage: Equatable, Sendable {
    case noConnection, timeout, serviceUnavailable, serverProblem, unreadableAnswer
    case sessionEnded, permissionDenied, notFound, invalidRequest, conflict
    case childLimitReached, subscriptionRequired, childNotActive
    case rateLimited(seconds: Int?)
    case codeRejected, telegramNotOpened

    /// Android `DataErrorFromApiFailure` and `ApiFailureFromStatus`: the code
    /// first, then the status, and "check what you entered" for the rest.
    public init(_ error: any Error) {
        guard let failure = error as? ApiFailure else {
            self = .serverProblem
            return
        }
        switch failure {
        case .network(let code):
            self = code == URLError.Code.timedOut.rawValue ? .timeout : .noConnection
        case .sessionEnded:
            self = .sessionEnded
        case .decoding:
            self = .unreadableAnswer
        case .unexpectedStatus(let status):
            self = Self.meaning(ofStatus: status, retryAfter: nil) ?? .invalidRequest
        case .server(let status, let error):
            self = Self.meaning(of: error)
                ?? Self.meaning(ofStatus: status, retryAfter: error.retryAfterSeconds)
                ?? .invalidRequest
        }
    }

    private static func meaning(of error: ApiError) -> UserMessage? {
        switch error.code {
        case .rateLimited: return .rateLimited(seconds: error.retryAfterSeconds)
        case .upstreamUnavailable: return .serviceUnavailable
        case .childLimitReached: return .childLimitReached
        case .subscriptionRequired: return .subscriptionRequired
        case .childNotActive: return .childNotActive
        case .conflict: return .conflict
        case .forbidden, .notYourChild: return .permissionDenied
        case .notFound: return .notFound
        default: return nil
        }
    }

    private static func meaning(ofStatus status: Int, retryAfter: Int?) -> UserMessage? {
        switch status {
        case 401: return .sessionEnded
        case 404: return .notFound
        case 408: return .timeout
        case 429: return .rateLimited(seconds: retryAfter)
        case 503: return .serviceUnavailable
        case 500...: return .serverProblem
        default: return nil
        }
    }

    public func text(_ l10n: L10n) -> String {
        switch self {
        case .noConnection: l10n.dataErrorNoConnection
        case .timeout: l10n.dataErrorTimeout
        case .serviceUnavailable: l10n.signInErrorServiceUnavailable
        case .serverProblem: l10n.dataErrorServerProblem
        case .unreadableAnswer: l10n.dataErrorUnreadableAnswer
        case .sessionEnded: l10n.dataErrorNotAuthenticated
        case .permissionDenied: l10n.dataErrorPermissionDenied
        case .notFound: l10n.dataErrorNotFound
        case .invalidRequest: l10n.dataErrorInvalidRequest
        case .conflict: l10n.dataErrorConflict
        case .childLimitReached: l10n.dataErrorChildLimitReached
        case .subscriptionRequired: l10n.dataErrorSubscriptionRequired
        case .childNotActive: l10n.dataErrorChildNotActive
        case .rateLimited(let seconds):
            if let seconds { l10n.dataErrorRateLimitedSeconds(seconds) } else { l10n.dataErrorRateLimited }
        case .codeRejected: l10n.signInTelegramCodeRejected
        case .telegramNotOpened: l10n.signInTelegramNotOpenedOnlyDoor
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/SignInModel.swift` — o'zgarishlar:

1. `public private(set) var message: String?` → `public private(set) var message: UserMessage?`
2. `chooseTelegram` ichida `message = UserMessage.text(for: error)` → `message = UserMessage(error)`
3. `telegramDidNotOpen()` ichida `message = Copy.SignIn.telegramNotOpened` → `message = .telegramNotOpened`
4. `verify()` ichida `message = Copy.SignIn.codeRejected` → `message = .codeRejected`; `message = UserMessage.text(for: error)` → `message = UserMessage(error)`

- [ ] **Step 5: Muhit (environment) va ildiz**

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — butun fayl:

```swift
import Foundation
import NozirAuth
import NozirConfig
import NozirDesignSystem
import NozirL10n
import NozirNetworking

/// Every live object, built once at launch and wired here and nowhere else.
@MainActor
public final class AppEnvironment {
    public let appModel: AppModel
    public let language: LanguageStore
    public let appearance: AppearanceStore
    /// Nil until the app has an App Store ID (no developer account yet).
    let appStoreURL: URL?
    private let telegramSignIn: any TelegramSignInService

    init(
        appModel: AppModel,
        language: LanguageStore,
        appearance: AppearanceStore,
        telegramSignIn: any TelegramSignInService,
        appStoreURL: URL?
    ) {
        self.appModel = appModel
        self.language = language
        self.appearance = appearance
        self.telegramSignIn = telegramSignIn
        self.appStoreURL = appStoreURL
    }

    public static func live(baseURL: URL, appVersion: String, osVersion: String, deviceLabel: String) -> AppEnvironment {
        let identity = ClientIdentity(appVersion: appVersion, osVersion: osVersion)
        let anonymous = ApiClient(baseURL: baseURL, transport: URLSessionTransport(), identity: identity)
        let store = KeychainTokenStore()
        // Reinstalling the app signs the parent out (user decision); must run
        // before anything reads the store.
        FreshInstall.clearSessionLeftByPreviousInstall(store: store)
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
            language: LanguageStore(),
            appearance: AppearanceStore(),
            telegramSignIn: TelegramSignIn(api: anonymousAuth, store: store, deviceLabel: deviceLabel),
            appStoreURL: nil
        )
    }

    func makeSignInModel() -> SignInModel {
        SignInModel(service: telegramSignIn, onSignedIn: { [appModel] in appModel.didSignIn() })
    }
}
```

`NozirKit/Sources/NozirAppFeature/RootView.swift` — butun fayl:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Shows whichever top-level state AppModel is in, in the parent's language and
/// theme, and reports scene changes to it.
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
            .environment(\.l10n, environment.language.l10n)
            // SwiftUI's own pieces (date pickers, formatted numbers) follow the
            // app's language too, not the phone's.
            .environment(\.locale, Locale(identifier: environment.language.current.rawValue))
            .preferredColorScheme(environment.appearance.mode.colorScheme)
            .task { await environment.appModel.start() }
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

- [ ] **Step 6: Ekranlar**

`NozirKit/Sources/NozirAppFeature/Screens/WelcomeView.swift` — butun fayl:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P01, laid out as Android `WelcomeScreen`: the promise centred, the actions at the bottom.
struct WelcomeView: View {
    let onStart: () -> Void
    let onSignIn: () -> Void
    @Environment(\.l10n) private var l10n

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
                NozirButton(l10n.welcomeActionStart, size: .callToAction, action: onStart)
                NozirButton(l10n.welcomeActionHaveAccount, variant: .ghost, action: onSignIn)
            }
            .padding(.horizontal, NozirSpacing.medium)
            .padding(.bottom, NozirSpacing.extraLarge)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 0) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.welcomeTitle)
                .nozirText(.headline)
                .padding(.top, NozirSpacing.large)
            Text(l10n.welcomeBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.compact)
            VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                NozirBulletRow(l10n.welcomeBenefitSummary)
                NozirBulletRow(l10n.welcomeBenefitScreenTime)
                NozirBulletRow(l10n.welcomeBenefitLocation)
            }
            .padding(.top, NozirSpacing.extraLarge)
        }
    }
}

#Preview {
    WelcomeView(onStart: {}, onSignIn: {})
}
```

`NozirKit/Sources/NozirAppFeature/Screens/SignInView.swift` — butun fayl:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P02 as Android `SignInChoiceStep` + `TelegramCodeStep`, Telegram only.
struct SignInView: View {
    @State private var model: SignInModel
    @Environment(\.openURL) private var openURL
    @Environment(\.l10n) private var l10n

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
                NozirPrivacyNote(l10n.signInPrivacyNote)
                    .padding(.top, NozirSpacing.extraLarge)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
    }

    private var choice: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.signInChoiceTitle).nozirText(.titleLarge)
            Text(model.isTelegramAvailable ? l10n.signInChoiceSubtitleTelegramOnly : l10n.signInChoiceSubtitleNoWayIn)
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            if model.isTelegramAvailable {
                NozirButton(l10n.signInActionTelegram, isLoading: model.isBusy) {
                    Task {
                        if let link = await model.chooseTelegram() { open(link) }
                    }
                }
                .padding(.top, NozirSpacing.large)
                Text(l10n.signInTelegramWhy)
                    .nozirText(.bodySmall, color: NozirColor.textTertiary)
                    .padding(.top, NozirSpacing.small)
            }
            if let message = model.message {
                NozirInlineMessage(message.text(l10n)).padding(.top, NozirSpacing.medium)
            }
        }
    }

    private var codeStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(l10n.signInTelegramCodeTitle).nozirText(.titleLarge)
            Text(l10n.signInTelegramCodeSubtitle(model.codeMinutes))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
                .padding(.top, NozirSpacing.extraSmall)
            NozirCodeField(
                code: Binding(get: { model.code }, set: { model.updateCode($0) }),
                placeholder: l10n.signInCodePlaceholder
            )
            .padding(.top, NozirSpacing.large)
            if let message = model.message {
                NozirInlineMessage(message.text(l10n)).padding(.top, NozirSpacing.small)
            }
            NozirButton(l10n.signInActionVerify, size: .callToAction, isLoading: model.isBusy) {
                Task { await model.verify() }
            }
            // Not `canVerify`: that is false while busy and would grey the button;
            // NozirButton already blocks taps while it shows the spinner.
            .disabled(model.code.count != model.codeLength)
            .padding(.top, NozirSpacing.large)
            NozirButton(l10n.signInActionOpenBotAgain, variant: .secondary) {
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

`NozirKit/Sources/NozirAppFeature/Screens/UpdateRequiredView.swift` — butun fayl:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Android `UpdateRequiredScreen`: update, and the emergency number stays one tap away.
struct UpdateRequiredView: View {
    let emergencyNumber: String?
    let appStoreURL: URL?
    @Environment(\.openURL) private var openURL
    @Environment(\.l10n) private var l10n
    @State private var notice: Notice?

    /// Kept as a meaning, so the sentence follows a language change.
    private enum Notice {
        case storeMissing, dialerMissing
    }

    var body: some View {
        // Scrolls, so the emergency button stays reachable at large text sizes
        // and in landscape; centred while it fits.
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.updateRequiredTitle)
                .nozirText(.titleLarge)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.medium)
            Text(l10n.updateRequiredBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, NozirSpacing.small)
            NozirButton(l10n.updateRequiredAction, size: .callToAction) { openStore() }
                .padding(.top, NozirSpacing.large)
            if let notice {
                NozirInlineMessage(text(for: notice)).padding(.top, NozirSpacing.compact)
            }
            if let emergencyNumber {
                NozirButton(l10n.updateRequiredCallEmergency(emergencyNumber), variant: .criticalOutline) {
                    call(emergencyNumber)
                }
                .padding(.top, NozirSpacing.medium)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
        .padding(.vertical, NozirSpacing.extraLarge)
    }

    private func text(for notice: Notice) -> String {
        switch notice {
        case .storeMissing: l10n.updateRequiredStoreMissing
        case .dialerMissing: l10n.updateRequiredDiallerMissing
        }
    }

    private func openStore() {
        guard let appStoreURL else {
            notice = .storeMissing
            return
        }
        openURL(appStoreURL) { accepted in
            if !accepted {
                Task { @MainActor in notice = .storeMissing }
            }
        }
    }

    private func call(_ number: String) {
        guard let url = URL(string: "tel:\(number)") else {
            notice = .dialerMissing
            return
        }
        openURL(url) { accepted in
            if !accepted {
                Task { @MainActor in notice = .dialerMissing }
            }
        }
    }
}

#Preview {
    UpdateRequiredView(emergencyNumber: "112", appStoreURL: nil)
}
```

`NozirKit/Sources/NozirAppFeature/Screens/HomePlaceholderView.swift` — butun fayl (chiqish tugmasi Task 15 da Profile'ga ko'chadi):

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// Stands in for P05 until sub-project 2b builds it.
struct HomePlaceholderView: View {
    var onSignOut: (() -> Void)?
    @Environment(\.l10n) private var l10n

    var body: some View {
        VStack(spacing: NozirSpacing.medium) {
            NozirLogoMark(accessibilityLabel: l10n.contentDescriptionLogo)
            Text(l10n.iosHomePlaceholderTitle).nozirText(.titleLarge)
            Text(l10n.iosHomePlaceholderBody)
                .nozirText(.body, color: NozirColor.textSecondary)
                .multilineTextAlignment(.center)
            if let onSignOut {
                NozirButton(l10n.profileActionSignOut, variant: .secondary, action: onSignOut)
                    .padding(.top, NozirSpacing.large)
            }
        }
        .padding(.horizontal, NozirSpacing.large)
    }
}
```

Keyin: `git rm NozirKit/Sources/NozirAppFeature/Copy.swift`.

- [ ] **Step 7: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`, keyin to'liq `./scripts/test.sh` va ilova: watcher `app` (yoki `xcodebuild build -project Nozir.xcodeproj -scheme Nozir …`).
Expected: barcha testlar o'tadi; `** BUILD SUCCEEDED **`. `grep -rn "Copy\." NozirKit/Sources` hech narsa topmaydi.

- [ ] **Step 8: Simulyatorda qisqa tekshiruv (foydalanuvchi)**

Ilovani ishga tushiring: Welcome, Sign-in, kod ekrani avvalgidek o'zbekcha. (Til almashtirish tugmasi Task 14 da paydo bo'ladi.)

- [ ] **Step 9: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirAppFeature NozirKit/Tests/NozirAppFeatureTests/UserMessageTests.swift NozirKit/Tests/NozirAppFeatureTests/SignInModelTests.swift
```

(`git rm` bilan o'chirilgan `Copy.swift` allaqachon indeksda.)

Xabar: `app: every sentence comes from L10n, and a message is a meaning`

---
### Task 6: `NozirFamily` — bola modeli va `/v1/parent/children` chaqiruvlari

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirFamily/FamilyModels.swift`
- Create: `NozirKit/Sources/NozirFamily/FamilyApi.swift`
- Test: `NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift`
- Test: `NozirKit/Tests/NozirFamilyTests/ChildrenApiTests.swift`

**Interfaces:**
- Consumes: Task 3 (`ApiRequest.put/patch`, `.delete`, `ApiFailure`).
- Produces:
  - `public enum AgeGroup: String, Sendable, Decodable { case star = "STAR", explorer = "EXPLORER", independent = "INDEPENDENT" }`
  - `public enum PairingState: String, Sendable, Decodable { case notPaired = "NOT_PAIRED", codeIssued = "CODE_ISSUED", appInstalled = "APP_INSTALLED", paired = "PAIRED" }`
  - `public struct Child: Decodable, Equatable, Sendable, Identifiable { id: UUID; displayName: String; birthYear: Int; ageGroup: AgeGroup?; avatarKey: String?; phoneE164: String?; pairingState: PairingState }` + `public init(id:displayName:birthYear:ageGroup:avatarKey:phoneE164:pairingState:)` (oxirgi to'rttasi sukutli)
  - `public struct ChildCreate: Encodable, Equatable, Sendable { displayName; birthYear; avatarKey: String?; phoneE164: String? }`
  - `public struct ChildUpdate: Encodable, Equatable, Sendable { displayName: String?; birthYear: Int?; avatarKey: String?; phone: Phone; isEmpty: Bool }`, `enum Phone { case unchanged, cleared, set(String) }`
  - `public struct FamilyApi: Sendable { public init(client: ApiClient); children(); child(_ id:); createChild(_:); updateChild(_ id:, _ update:); removeChild(_ id:) }`

- [ ] **Step 1: Package'ga target qo'shish**

`NozirKit/Package.swift` — `NozirConfig` target'idan keyin:

```swift
        .target(name: "NozirFamily", dependencies: ["NozirNetworking"]),
```

test target'lar orasiga:

```swift
        .testTarget(name: "NozirFamilyTests", dependencies: ["NozirFamily", "NozirNetworking", "NozirTestSupport"]),
```

- [ ] **Step 2: Failing testlarni yozish**

`NozirKit/Tests/NozirFamilyTests/FamilyFixtures.swift`:

```swift
import Foundation
import NozirFamily
import NozirNetworking
import NozirTestSupport

/// A bearer that never expires: these tests are about the family calls, not tokens.
struct FixedToken: AccessTokenProvider {
    func validAccessToken() async throws -> String { "acc" }
    func refreshAfterRejection(of token: String) async throws -> String { "acc" }
    func endSession(rejecting token: String) async {}
}

func familyApi(_ replies: [FakeTransport.Reply]) -> (FamilyApi, FakeTransport) {
    let transport = FakeTransport(replies)
    let client = ApiClient(
        baseURL: URL(string: "https://nozir.example")!,
        transport: transport,
        identity: ClientIdentity(appVersion: "1.0.0", osVersion: "17.5"),
        tokens: FixedToken()
    )
    return (FamilyApi(client: client), transport)
}

let aliId = UUID(uuidString: "0b0e2a52-6a2f-4d8b-9a55-6f1b2a0c1d01")!

/// `ChildResponse` exactly as the backend writes it.
func childJSON(
    id: UUID = aliId,
    name: String = "Ali",
    ageGroup: String = "STAR",
    pairingState: String = "NOT_PAIRED",
    phone: String = "null"
) -> String {
    """
    {"childId":"\(id.uuidString.lowercased())","displayName":"\(name)","birthYear":2015,\
    "ageGroup":"\(ageGroup)","ageGroupIsOverridden":false,"avatarKey":"teal","phoneE164":\(phone),\
    "pairingState":"\(pairingState)","createdAt":"2026-10-03T11:31:09.123456Z"}
    """
}
```

`NozirKit/Tests/NozirFamilyTests/ChildrenApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

@Suite struct ChildrenApiTests {
    @Test func theListReadsTheServersShape() async throws {
        let (api, transport) = familyApi([.ok("[\(childJSON(phone: "\"+998901234567\""))]")])

        let children = try await api.children()

        #expect(children == [Child(
            id: aliId,
            displayName: "Ali",
            birthYear: 2015,
            ageGroup: .star,
            avatarKey: "teal",
            phoneE164: "+998901234567",
            pairingState: .notPaired
        )])
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/parent/children")
    }

    @Test func aChildInAStateThisAppDoesNotKnowStillLoads() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON(ageGroup: "TODDLER", pairingState: "SOMETHING_NEW"))]")])

        let child = try #require(try await api.children().first)

        #expect(child.ageGroup == nil)
        #expect(child.pairingState == .notPaired)
    }

    @Test func creatingSendsOnlyWhatTheParentGave() async throws {
        let (api, transport) = familyApi([.init(status: 201, body: childJSON())])

        let child = try await api.createChild(ChildCreate(displayName: "Ali", birthYear: 2015, avatarKey: "teal", phoneE164: nil))

        #expect(child.id == aliId)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/parent/children")
        let body = try #require(request.jsonObject)
        #expect(Set(body.keys) == ["displayName", "birthYear", "avatarKey"])
        #expect(body["birthYear"] as? Int == 2015)
    }

    @Test func theChildLimitIsTheServersAnswer() async {
        let (api, _) = familyApi([.error(403, code: "CHILD_LIMIT_REACHED")])

        do {
            _ = try await api.createChild(ChildCreate(displayName: "Ali", birthYear: 2015, avatarKey: nil, phoneE164: nil))
            Issue.record("expected the limit")
        } catch let failure as ApiFailure {
            #expect(failure.code == .childLimitReached)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func anEditSendsOnlyWhatChanged() async throws {
        let (api, transport) = familyApi([.ok(childJSON(name: "Vali"))])

        let child = try await api.updateChild(aliId, ChildUpdate(displayName: "Vali"))

        #expect(child.displayName == "Vali")
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
        #expect(request.jsonBody == ["displayName": "Vali"])
    }

    @Test func clearingThePhoneSendsAnExplicitNull() async throws {
        let (api, transport) = familyApi([.ok(childJSON())])

        _ = try await api.updateChild(aliId, ChildUpdate(phone: .cleared))

        let body = try #require(await transport.requests.first?.jsonObject)
        #expect(Set(body.keys) == ["phoneE164"])
        #expect(body["phoneE164"] is NSNull)
    }

    @Test func anUnchangedPhoneIsNotSentAtAll() {
        #expect(ChildUpdate().isEmpty)
        #expect(!ChildUpdate(phone: .set("+998901234567")).isEmpty)
    }

    @Test func removingSendsDelete() async throws {
        let (api, transport) = familyApi([.init(status: 204)])

        try await api.removeChild(aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
    }

    @Test func oneChildIsReadByItsId() async throws {
        let (api, transport) = familyApi([.ok(childJSON(pairingState: "PAIRED"))])

        let child = try await api.child(aliId)

        #expect(child.pairingState == .paired)
        #expect(await transport.requests.first?.url?.path == "/v1/parent/children/\(aliId.uuidString.lowercased())")
    }
}
```

- [ ] **Step 3: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`
Expected: FAIL — `NozirFamily` target'ida manba yo'q / `cannot find 'FamilyApi' in scope`.

- [ ] **Step 4: Implementatsiya**

`NozirKit/Sources/NozirFamily/FamilyModels.swift`:

```swift
import Foundation

/// Backend `AgeGroup`: STAR 7–10, EXPLORER 11–13, INDEPENDENT 14–17.
public enum AgeGroup: String, Sendable, Decodable {
    case star = "STAR"
    case explorer = "EXPLORER"
    case independent = "INDEPENDENT"
}

/// Backend `PairingState`: how far the child's phone has got.
public enum PairingState: String, Sendable, Decodable {
    case notPaired = "NOT_PAIRED"
    case codeIssued = "CODE_ISSUED"
    case appInstalled = "APP_INSTALLED"
    case paired = "PAIRED"
}

/// `ChildResponse`. Decoding is lenient where the server may grow: a band or a
/// state this app does not know yet must not empty the parent's child list.
public struct Child: Decodable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let birthYear: Int
    /// The effective band (the parent's override or the birth year's); never
    /// re-derived here. Nil for a band this app does not know.
    public let ageGroup: AgeGroup?
    public let avatarKey: String?
    /// A minor's number: shown to the parent only, never logged.
    public let phoneE164: String?
    public let pairingState: PairingState

    public init(
        id: UUID,
        displayName: String,
        birthYear: Int,
        ageGroup: AgeGroup? = nil,
        avatarKey: String? = nil,
        phoneE164: String? = nil,
        pairingState: PairingState = .notPaired
    ) {
        self.id = id
        self.displayName = displayName
        self.birthYear = birthYear
        self.ageGroup = ageGroup
        self.avatarKey = avatarKey
        self.phoneE164 = phoneE164
        self.pairingState = pairingState
    }

    private enum CodingKeys: String, CodingKey {
        case id = "childId"
        case displayName, birthYear, ageGroup, avatarKey, phoneE164, pairingState
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        birthYear = try container.decode(Int.self, forKey: .birthYear)
        ageGroup = try? container.decodeIfPresent(AgeGroup.self, forKey: .ageGroup)
        avatarKey = try container.decodeIfPresent(String.self, forKey: .avatarKey)
        phoneE164 = try container.decodeIfPresent(String.self, forKey: .phoneE164)
        pairingState = (try? container.decode(PairingState.self, forKey: .pairingState)) ?? .notPaired
    }
}

/// `CreateChildBody`. Nil fields are left out of the JSON.
public struct ChildCreate: Encodable, Equatable, Sendable {
    public let displayName: String
    public let birthYear: Int
    public let avatarKey: String?
    public let phoneE164: String?

    public init(displayName: String, birthYear: Int, avatarKey: String?, phoneE164: String?) {
        self.displayName = displayName
        self.birthYear = birthYear
        self.avatarKey = avatarKey
        self.phoneE164 = phoneE164
    }
}

/// `UpdateChildBody`: only what changed is sent. The phone has three
/// instructions, because "leave it" and "remove it" are different requests.
public struct ChildUpdate: Encodable, Equatable, Sendable {
    public enum Phone: Equatable, Sendable {
        case unchanged
        case cleared
        case set(String)
    }

    public var displayName: String?
    public var birthYear: Int?
    public var avatarKey: String?
    public var phone: Phone

    public init(displayName: String? = nil, birthYear: Int? = nil, avatarKey: String? = nil, phone: Phone = .unchanged) {
        self.displayName = displayName
        self.birthYear = birthYear
        self.avatarKey = avatarKey
        self.phone = phone
    }

    public var isEmpty: Bool {
        displayName == nil && birthYear == nil && avatarKey == nil && phone == .unchanged
    }

    private enum CodingKeys: String, CodingKey {
        case displayName, birthYear, avatarKey, phoneE164
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(birthYear, forKey: .birthYear)
        try container.encodeIfPresent(avatarKey, forKey: .avatarKey)
        switch phone {
        case .unchanged:
            break
        case .cleared:
            try container.encodeNil(forKey: .phoneE164)
        case .set(let number):
            try container.encode(number, forKey: .phoneE164)
        }
    }
}
```

`NozirKit/Sources/NozirFamily/FamilyApi.swift`:

```swift
import Foundation
import NozirNetworking

/// `/v1/parent/*` for the family: children, their rules, pairing, the
/// subscription's active child and the parent's own record.
public struct FamilyApi: Sendable {
    private let client: ApiClient

    public init(client: ApiClient) {
        self.client = client
    }

    static func childPath(_ id: UUID) -> String {
        "/v1/parent/children/\(id.uuidString.lowercased())"
    }

    public func children() async throws -> [Child] {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/children"), as: [Child].self)
    }

    public func child(_ id: UUID) async throws -> Child {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(id)), as: Child.self)
    }

    public func createChild(_ child: ChildCreate) async throws -> Child {
        try await client.send(try .post("/v1/parent/children", json: child), as: Child.self)
    }

    public func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child {
        try await client.send(try .patch(Self.childPath(id), json: update), as: Child.self)
    }

    /// Irreversible on the server: unpairs the phone and deletes the history.
    public func removeChild(_ id: UUID) async throws {
        try await client.send(ApiRequest(method: .delete, path: Self.childPath(id)))
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`
Expected: `** TEST SUCCEEDED **`, 9 ta test.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirFamily NozirKit/Tests/NozirFamilyTests
```

Xabar: `family: children, as the server keeps them`

---
### Task 7: `NozirFamily` — qoidalar, juftlash, obuna, profil; `FamilyService` va `FamilyStore`

**Files:**
- Create: `NozirKit/Sources/NozirFamily/RuleModels.swift`
- Create: `NozirKit/Sources/NozirFamily/AccountModels.swift`
- Create: `NozirKit/Sources/NozirFamily/FamilyService.swift`
- Create: `NozirKit/Sources/NozirFamily/FamilyStore.swift`
- Modify: `NozirKit/Sources/NozirFamily/FamilyApi.swift`
- Test: `NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift`
- Test: `NozirKit/Tests/NozirFamilyTests/FamilyStoreTests.swift`

**Interfaces:**
- Consumes: Task 6 (`FamilyApi`, `Child`, fixture'lar `familyApi`, `childJSON`, `aliId`).
- Produces:
  - `public struct ClockTime: Hashable, Sendable { hour; minute; init(hour:minute:); init?(_ text: String); var text: String; var minutesSinceMidnight: Int }`
  - `public struct ScreenTimeLimit: Codable, Equatable, Sendable { schoolDayMinutes; weekendMinutes; maxDailyBonusMinutes }`
  - `public struct BedtimeSchedule: Codable, Equatable, Sendable { start: ClockTime; end: ClockTime; windDownMinutes: Int; activeDays: [Int]; lengthMinutes: Int }` (JSON: `startTime`, `endTime`)
  - `public struct RuleSnapshot: Decodable, Equatable, Sendable { version: Int64; screenTime; bedtime }`
  - `public struct PairingCode: Decodable, Equatable, Sendable { code; expiresAt: Date; qrPayload; state: PairingState; qrContent: String }`
  - `public struct ChildDevice: Decodable, Equatable, Sendable { id: UUID; manufacturer; model; isOnline; label: String }`
  - `public struct Subscription: Decodable, Equatable, Sendable { activeChildId: UUID?; func isChildActive(_ id: UUID) -> Bool }`
  - `public struct ParentProfile: Decodable, Equatable, Sendable { displayName: String?; phoneE164: String?; locale: String }`
  - `public protocol FamilyService: Sendable` — quyidagi barcha metodlar; `FamilyApi: FamilyService`
  - `@MainActor @Observable public final class FamilyStore { children: [Child]; hasLoaded: Bool; let service: any FamilyService; init(service:); refresh() async throws; child(_:) -> Child?; replace(_:); remove(_:) }`

`FamilyService` metodlari (aniq imzolar — Task 10–15 shularga tayanadi):

```swift
func children() async throws -> [Child]
func child(_ id: UUID) async throws -> Child
func createChild(_ child: ChildCreate) async throws -> Child
func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child
func removeChild(_ id: UUID) async throws
func rules(of childId: UUID) async throws -> RuleSnapshot
func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot
func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot
/// nil: no live code (404) — an answer, not a fault.
func currentPairingCode(for childId: UUID) async throws -> PairingCode?
func issuePairingCode(for childId: UUID) async throws -> PairingCode
func devices(of childId: UUID) async throws -> [ChildDevice]
func subscription() async throws -> Subscription
func chooseActiveChild(_ childId: UUID) async throws -> Subscription
func me() async throws -> ParentProfile
func updateLocale(_ locale: String) async throws -> ParentProfile
```

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirFamilyTests/RulesAndPairingApiTests.swift`:

```swift
import Foundation
import Testing
import NozirNetworking
import NozirTestSupport
@testable import NozirFamily

/// `RuleSnapshotResponse` with the parts 2a does not read left in, as the server sends them.
private func snapshotJSON(version: Int = 7, start: String = "22:00") -> String {
    """
    {"childId":"\(aliId.uuidString.lowercased())","version":\(version),\
    "screenTime":{"schoolDayMinutes":120,"weekendMinutes":180,"maxDailyBonusMinutes":60},\
    "maxTrustBonusMinutes":30,"locationTracking":{"isEnabled":false},\
    "bedtime":{"startTime":"\(start)","endTime":"07:00","windDownMinutes":30,"activeDays":[1,2,3,4,5,6,7]},\
    "appPolicies":[],"familyRules":[],"neverBlockedPackages":["com.android.dialer"]}
    """
}

private let codeJSON = """
    {"code":"472918","expiresAt":"2026-10-05T10:10:00Z","qrPayload":"nozir://pair?code=472918","state":"APP_INSTALLED"}
    """

private var rulesPath: String { FamilyApi.childPath(aliId) + "/rules" }

@Suite struct RulesAndPairingApiTests {
    @Test func rulesReadTheVersionAndBothRuleSets() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON())])

        let snapshot = try await api.rules(of: aliId)

        #expect(snapshot.version == 7)
        #expect(snapshot.screenTime == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60))
        #expect(snapshot.bedtime.start == ClockTime(hour: 22, minute: 0))
        #expect(snapshot.bedtime.activeDays == [1, 2, 3, 4, 5, 6, 7])
        #expect(await transport.requests.first?.url?.path == rulesPath)
    }

    @Test func aScreenTimeWriteNamesTheVersionItWasMadeAgainst() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 8))])

        let after = try await api.setScreenTime(
            ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 60),
            of: aliId,
            version: 7
        )

        #expect(after.version == 8)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == rulesPath + "/screen-time")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"7\"")
        #expect(request.jsonObject?["schoolDayMinutes"] as? Int == 90)
    }

    @Test func aBedtimeWriteSendsWallClockTimes() async throws {
        let (api, transport) = familyApi([.ok(snapshotJSON(version: 9, start: "21:30"))])
        let bedtime = BedtimeSchedule(
            start: ClockTime(hour: 21, minute: 30),
            end: ClockTime(hour: 7, minute: 0),
            windDownMinutes: 30,
            activeDays: [1, 2, 3, 4, 5]
        )

        _ = try await api.setBedtime(bedtime, of: aliId, version: 8)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == rulesPath + "/bedtime")
        #expect(request.value(forHTTPHeaderField: "If-Match") == "\"8\"")
        let body = try #require(request.jsonObject)
        #expect(body["startTime"] as? String == "21:30")
        #expect(body["endTime"] as? String == "07:00")
        #expect(body["activeDays"] as? [Int] == [1, 2, 3, 4, 5])
    }

    @Test func theNightWindowCrossesMidnight() {
        let bedtime = BedtimeSchedule(start: ClockTime(hour: 22, minute: 0), end: ClockTime(hour: 7, minute: 0), windDownMinutes: 0, activeDays: [1])
        #expect(bedtime.lengthMinutes == 540)
        #expect(ClockTime("7:5") == ClockTime(hour: 7, minute: 5))
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime(hour: 7, minute: 5).text == "07:05")
    }

    @Test func aConflictIsTheServersAnswer() async {
        let (api, _) = familyApi([.error(409, code: "CONFLICT")])

        do {
            _ = try await api.setScreenTime(ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 90, maxDailyBonusMinutes: 60), of: aliId, version: 7)
            Issue.record("expected a conflict")
        } catch let failure as ApiFailure {
            #expect(failure.code == .conflict)
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    @Test func noLiveCodeIsAnAnswerNotAFault() async throws {
        let (api, _) = familyApi([.error(404, code: "NOT_FOUND")])

        #expect(try await api.currentPairingCode(for: aliId) == nil)
    }

    @Test func aLiveCodeIsRead() async throws {
        let (api, transport) = familyApi([.ok(codeJSON)])

        let code = try #require(try await api.currentPairingCode(for: aliId))

        #expect(code.code == "472918")
        #expect(code.state == .appInstalled)
        #expect(code.qrContent == "nozir://pair?code=472918")
        #expect(await transport.requests.first?.url?.path == FamilyApi.childPath(aliId) + "/pairing-code")
    }

    @Test func aCodeWithoutAPayloadPutsTheCodeInTheQR() async throws {
        let (api, _) = familyApi([.ok(#"{"code":"472918","expiresAt":"2026-10-05T10:10:00Z","state":"CODE_ISSUED"}"#)])

        let code = try #require(try await api.currentPairingCode(for: aliId))

        #expect(code.qrContent == "472918")
    }

    @Test func issuingPostsWithoutABody() async throws {
        let (api, transport) = familyApi([.init(status: 201, body: codeJSON)])

        _ = try await api.issuePairingCode(for: aliId)

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == nil)
    }

    @Test func devicesAreListed() async throws {
        let (api, _) = familyApi([.ok("""
            [{"deviceId":"7c9e6679-7425-40de-944b-e07fc1f90ae7","childId":"\(aliId.uuidString.lowercased())",\
            "manufacturer":"Xiaomi","model":"Redmi Note 12","osVersion":"14","appVersion":"1.0.0",\
            "pairedAt":"2026-10-01T08:00:00Z","lastSeenAt":null,"isOnline":true}]
            """)])

        let devices = try await api.devices(of: aliId)

        #expect(devices.first?.label == "Xiaomi Redmi Note 12")
        #expect(devices.first?.isOnline == true)
    }

    @Test func theSubscriptionSaysWhichChildIsActive() async throws {
        let other = UUID()
        let (api, transport) = familyApi([
            .ok(#"{"familyId":"\#(UUID().uuidString)","tier":"FREE","status":"ACTIVE","state":"FREE","planCode":null,"channel":null,"currentPeriodEnd":null,"trialEndsAt":null,"graceUntil":null,"autoRenew":false,"entitlements":[],"quotas":{"CHILDREN":1},"activeChildId":"\#(aliId.uuidString.lowercased())"}"#),
            .ok(#"{"activeChildId":null}"#),
        ])

        let free = try await api.subscription()
        #expect(free.isChildActive(aliId))
        #expect(!free.isChildActive(other))

        let entitled = try await api.chooseActiveChild(other)
        #expect(entitled.isChildActive(other))
        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "PUT")
        #expect(request.url?.path == "/v1/parent/subscription/active-child")
        #expect(request.jsonBody?["childId"]?.lowercased() == other.uuidString.lowercased())
    }

    @Test func theParentsRecordAndLanguage() async throws {
        let parent = #"{"parentId":"\#(UUID().uuidString)","familyId":"\#(UUID().uuidString)","phoneE164":null,"displayName":"Zohid","locale":"uz","timeZone":"Asia/Tashkent","role":"OWNER","createdAt":"2026-10-01T08:00:00Z"}"#
        let (api, transport) = familyApi([.ok(parent), .ok(parent)])

        #expect(try await api.me().displayName == "Zohid")
        _ = try await api.updateLocale("ru")

        let request = try #require(await transport.requests.last)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/parent/me")
        #expect(request.jsonBody == ["locale": "ru"])
    }
}
```

`NozirKit/Tests/NozirFamilyTests/FamilyStoreTests.swift`:

```swift
import Foundation
import Testing
import NozirTestSupport
@testable import NozirFamily

@MainActor
@Suite struct FamilyStoreTests {
    @Test func refreshingReplacesTheList() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON())]")])
        let store = FamilyStore(service: api)

        try await store.refresh()

        #expect(store.children.map(\.displayName) == ["Ali"])
        #expect(store.hasLoaded)
    }

    @Test func aFailedRefreshKeepsWhatWasThere() async throws {
        let (api, _) = familyApi([.ok("[\(childJSON())]")])
        let store = FamilyStore(service: api)
        try await store.refresh()

        await #expect(throws: (any Error).self) { try await store.refresh() }

        #expect(store.children.count == 1)
    }

    @Test func aChangedChildReplacesItsOldSelfAndANewOneIsAdded() {
        let store = FamilyStore(service: familyApi([]).0)
        let ali = Child(id: aliId, displayName: "Ali", birthYear: 2015)

        store.replace(ali)
        store.replace(Child(id: aliId, displayName: "Alisher", birthYear: 2015))
        store.replace(Child(id: UUID(), displayName: "Vali", birthYear: 2013))

        #expect(store.children.map(\.displayName) == ["Alisher", "Vali"])
        #expect(store.child(aliId)?.displayName == "Alisher")
    }

    @Test func aRemovedChildIsGone() {
        let store = FamilyStore(service: familyApi([]).0)
        store.replace(Child(id: aliId, displayName: "Ali", birthYear: 2015))

        store.remove(aliId)

        #expect(store.children.isEmpty)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`
Expected: FAIL — `value of type 'FamilyApi' has no member 'rules'`, `cannot find 'FamilyStore'`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirFamily/RuleModels.swift`:

```swift
import Foundation

/// A wall-clock time in the family's zone, "HH:mm" on the wire.
public struct ClockTime: Hashable, Sendable {
    public let hour: Int
    public let minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public init?(_ text: String) {
        let parts = text.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0..<24).contains(hour), (0..<60).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var text: String {
        (hour < 10 ? "0" : "") + "\(hour):" + (minute < 10 ? "0" : "") + "\(minute)"
    }

    public var minutesSinceMidnight: Int {
        hour * 60 + minute
    }
}

/// `ScreenTimeLimitDto`. "Same every day" is not stored: it is school == weekend.
public struct ScreenTimeLimit: Codable, Equatable, Sendable {
    public var schoolDayMinutes: Int
    public var weekendMinutes: Int
    /// The ceiling on bonus minutes (P12). Not edited in 2a; carried through.
    public var maxDailyBonusMinutes: Int

    public init(schoolDayMinutes: Int, weekendMinutes: Int, maxDailyBonusMinutes: Int) {
        self.schoolDayMinutes = schoolDayMinutes
        self.weekendMinutes = weekendMinutes
        self.maxDailyBonusMinutes = maxDailyBonusMinutes
    }
}

/// `BedtimeScheduleDto`. The window normally crosses midnight, so an end
/// earlier than the start is expected.
public struct BedtimeSchedule: Codable, Equatable, Sendable {
    public var start: ClockTime
    public var end: ClockTime
    /// 0 means no warning before the window.
    public var windDownMinutes: Int
    /// ISO-8601 day numbers, 1 = Monday.
    public var activeDays: [Int]

    public init(start: ClockTime, end: ClockTime, windDownMinutes: Int, activeDays: [Int]) {
        self.start = start
        self.end = end
        self.windDownMinutes = windDownMinutes
        self.activeDays = activeDays
    }

    /// How long the phone stays closed.
    public var lengthMinutes: Int {
        (end.minutesSinceMidnight - start.minutesSinceMidnight + 24 * 60) % (24 * 60)
    }

    private enum CodingKeys: String, CodingKey {
        case startTime, endTime, windDownMinutes, activeDays
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        start = try Self.time(container, .startTime)
        end = try Self.time(container, .endTime)
        windDownMinutes = try container.decode(Int.self, forKey: .windDownMinutes)
        activeDays = try container.decode([Int].self, forKey: .activeDays)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start.text, forKey: .startTime)
        try container.encode(end.text, forKey: .endTime)
        try container.encode(windDownMinutes, forKey: .windDownMinutes)
        try container.encode(activeDays, forKey: .activeDays)
    }

    private static func time(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> ClockTime {
        let text = try container.decode(String.self, forKey: key)
        guard let time = ClockTime(text) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Not HH:mm: \(text)")
        }
        return time
    }
}

/// `RuleSnapshotResponse`, the parts 2a reads. `version` goes back as `If-Match`.
public struct RuleSnapshot: Decodable, Equatable, Sendable {
    public let version: Int64
    public let screenTime: ScreenTimeLimit
    public let bedtime: BedtimeSchedule

    public init(version: Int64, screenTime: ScreenTimeLimit, bedtime: BedtimeSchedule) {
        self.version = version
        self.screenTime = screenTime
        self.bedtime = bedtime
    }
}
```

`NozirKit/Sources/NozirFamily/AccountModels.swift`:

```swift
import Foundation

/// `PairingCodeResponse`. The server only ever returns a live code, so the
/// state is CODE_ISSUED or APP_INSTALLED in practice; anything it does not
/// know reads as CODE_ISSUED (Android does the same).
public struct PairingCode: Decodable, Equatable, Sendable {
    public let code: String
    public let expiresAt: Date
    public let qrPayload: String
    public let state: PairingState

    public init(code: String, expiresAt: Date, qrPayload: String, state: PairingState) {
        self.code = code
        self.expiresAt = expiresAt
        self.qrPayload = qrPayload
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case code, expiresAt, qrPayload, state
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        qrPayload = try container.decodeIfPresent(String.self, forKey: .qrPayload) ?? ""
        state = (try? container.decode(PairingState.self, forKey: .state)) ?? .codeIssued
    }

    /// What the QR carries: the server's payload, or the bare code if it sent none.
    public var qrContent: String {
        qrPayload.isEmpty ? code : qrPayload
    }
}

/// `ChildDeviceResponse`, the parts the replace-the-phone question names.
public struct ChildDevice: Decodable, Equatable, Sendable {
    public let id: UUID
    public let manufacturer: String
    public let model: String
    public let isOnline: Bool

    public init(id: UUID, manufacturer: String, model: String, isOnline: Bool) {
        self.id = id
        self.manufacturer = manufacturer
        self.model = model
        self.isOnline = isOnline
    }

    private enum CodingKeys: String, CodingKey {
        case id = "deviceId"
        case manufacturer, model, isOnline
    }

    public var label: String {
        "\(manufacturer) \(model)"
    }
}

/// `SubscriptionResponse`, the one field 2a needs.
public struct Subscription: Decodable, Equatable, Sendable {
    /// The child a free family keeps fully active; nil while every child is.
    public let activeChildId: UUID?

    public init(activeChildId: UUID?) {
        self.activeChildId = activeChildId
    }

    /// False means frozen: the phone keeps its last rules, but they cannot change.
    public func isChildActive(_ id: UUID) -> Bool {
        activeChildId == nil || activeChildId == id
    }
}

/// `ParentAccountResponse`, the parts P21 shows.
public struct ParentProfile: Decodable, Equatable, Sendable {
    public let displayName: String?
    public let phoneE164: String?
    public let locale: String

    public init(displayName: String?, phoneE164: String?, locale: String) {
        self.displayName = displayName
        self.phoneE164 = phoneE164
        self.locale = locale
    }
}
```

`NozirKit/Sources/NozirFamily/FamilyService.swift`:

```swift
import Foundation

/// Everything the family screens ask the server. `FamilyApi` is the real one;
/// screen-model tests use a scripted fake.
public protocol FamilyService: Sendable {
    func children() async throws -> [Child]
    func child(_ id: UUID) async throws -> Child
    func createChild(_ child: ChildCreate) async throws -> Child
    func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child
    func removeChild(_ id: UUID) async throws
    func rules(of childId: UUID) async throws -> RuleSnapshot
    func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot
    /// nil: no live code (404) — an answer, not a fault.
    func currentPairingCode(for childId: UUID) async throws -> PairingCode?
    func issuePairingCode(for childId: UUID) async throws -> PairingCode
    func devices(of childId: UUID) async throws -> [ChildDevice]
    func subscription() async throws -> Subscription
    func chooseActiveChild(_ childId: UUID) async throws -> Subscription
    func me() async throws -> ParentProfile
    func updateLocale(_ locale: String) async throws -> ParentProfile
}
```

`NozirKit/Sources/NozirFamily/FamilyApi.swift` — `public struct FamilyApi: Sendable {` qatorini `public struct FamilyApi: FamilyService {` ga almashtiring va `removeChild` dan keyin qo'shing:

```swift
    public func rules(of childId: UUID) async throws -> RuleSnapshot {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/rules"), as: RuleSnapshot.self)
    }

    public func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(Self.childPath(childId) + "/rules/screen-time", json: limit, ifMatch: Self.entityTag(version))
        return try await client.send(request, as: RuleSnapshot.self)
    }

    public func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        let request = try ApiRequest.put(Self.childPath(childId) + "/rules/bedtime", json: bedtime, ifMatch: Self.entityTag(version))
        return try await client.send(request, as: RuleSnapshot.self)
    }

    public func currentPairingCode(for childId: UUID) async throws -> PairingCode? {
        do {
            return try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/pairing-code"), as: PairingCode.self)
        } catch let failure as ApiFailure where failure.isNotFound {
            return nil
        }
    }

    /// Revokes the previous code; redeeming the new one retires the child's current phone.
    public func issuePairingCode(for childId: UUID) async throws -> PairingCode {
        try await client.send(ApiRequest(method: .post, path: Self.childPath(childId) + "/pairing-code"), as: PairingCode.self)
    }

    public func devices(of childId: UUID) async throws -> [ChildDevice] {
        try await client.send(ApiRequest(method: .get, path: Self.childPath(childId) + "/devices"), as: [ChildDevice].self)
    }

    public func subscription() async throws -> Subscription {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/subscription"), as: Subscription.self)
    }

    public func chooseActiveChild(_ childId: UUID) async throws -> Subscription {
        struct Body: Encodable {
            let childId: UUID
        }
        return try await client.send(try .put("/v1/parent/subscription/active-child", json: Body(childId: childId)), as: Subscription.self)
    }

    public func me() async throws -> ParentProfile {
        try await client.send(ApiRequest(method: .get, path: "/v1/parent/me"), as: ParentProfile.self)
    }

    public func updateLocale(_ locale: String) async throws -> ParentProfile {
        struct Body: Encodable {
            let locale: String
        }
        return try await client.send(try .patch("/v1/parent/me", json: Body(locale: locale)), as: ParentProfile.self)
    }

    /// `IfMatchVersion.format`: the version in double quotes.
    private static func entityTag(_ version: Int64) -> String {
        "\"\(version)\""
    }
```

`NozirKit/Sources/NozirFamily/FamilyStore.swift`:

```swift
import Foundation
import Observation

/// The family's children for this session, in memory only (nothing about a
/// child is written to disk). Screens read it; whoever changes a child on the
/// server tells it.
@MainActor
@Observable
public final class FamilyStore {
    public private(set) var children: [Child] = []
    public private(set) var hasLoaded = false
    public let service: any FamilyService

    public init(service: any FamilyService) {
        self.service = service
    }

    /// Asks the server. A failure keeps what was there and is rethrown.
    public func refresh() async throws {
        let fresh = try await service.children()
        children = fresh
        hasLoaded = true
    }

    public func child(_ id: UUID) -> Child? {
        children.first { $0.id == id }
    }

    public func replace(_ child: Child) {
        if let index = children.firstIndex(where: { $0.id == child.id }) {
            children[index] = child
        } else {
            children.append(child)
        }
    }

    public func remove(_ id: UUID) {
        children.removeAll { $0.id == id }
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirFamilyTests`
Expected: `** TEST SUCCEEDED **` — 9 + 12 + 4 = 25 ta test.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirFamily NozirKit/Tests/NozirFamilyTests
```

Xabar: `family: rules, pairing and the active child, behind one service`

---
### Task 8: Dizayn tizimi — maydonlar, avatar, karta, qatorlar, QR, +998 raqam

**Files:**
- Modify: `NozirKit/Sources/NozirDesignSystem/NozirColor.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/UzbekPhone.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirFields.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirAvatar.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirRows.swift`
- Create: `NozirKit/Sources/NozirDesignSystem/Components/NozirQRCode.swift`
- Test: `NozirKit/Tests/NozirDesignSystemTests/ComponentLogicTests.swift`

**Interfaces:**
- Produces:
  - `NozirColor.onPrimaryContainer, apricotContent, apricotContainer, skyContent, skyContainer, attentionContent, attentionContainer, attentionBorder`
  - `public enum UzbekPhone { static let subscriberDigits = 9; static func digits(from: String) -> String; static func grouped(_: String) -> String; static func e164(_ digits: String) -> String?; static func digits(fromE164: String?) -> String; static func display(_ e164: String) -> String }`
  - `NozirTextField(_ label: String, text: Binding<String>, placeholder: String, error: String? = nil, keyboard: UIKeyboardType = .default)`
  - `NozirPhoneField(_ label: String, digits: Binding<String>, prefix: String, placeholder: String, error: String? = nil)`
  - `public enum AvatarTone: String, CaseIterable, Sendable { case teal, apricot, sky; static func forKey(_ key: String?, position: Int = 0) -> AvatarTone }`
  - `NozirAvatar(name: String, tone: AvatarTone, fallbackInitial: String, size: CGFloat = 40)`; `static func initial(of name: String, fallback: String) -> String`
  - `NozirAvatarPicker(selection: Binding<AvatarTone>, name: String, fallbackInitial: String, accessibilityLabel: String)`
  - `NozirCard(tone: NozirCardTone = .plain) { … }`, `public enum NozirCardTone { case plain, attention }`
  - `NozirSectionTitle(_ text: String)`, `NozirSettingsRow(_ title: String, value: String? = nil, action:)`, `NozirChecklistRow(_ text: String, isDone: Bool)`, `NozirStatusDot(_ level: NozirStatusLevel)`, `public enum NozirStatusLevel { case good, attention, action }`
  - `NozirQRCode(payload: String, accessibilityLabel: String)`; `static func image(for payload: String) -> UIImage?`

Ranglar Android `NozirLightColors`/`NozirDarkColors` dan: avatar teal = `primaryContainer`/`onPrimaryContainer`, apricot = `accent`, sky = `info`; diqqat kartasi = `statusAttention`. Qorong'i konteynerlar — rangning 12%, chegaralar — 30% (`NozirTonalColor.onDarkSurface`).

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirDesignSystemTests/ComponentLogicTests.swift`:

```swift
import Testing
import UIKit
@testable import NozirDesignSystem

@Suite struct UzbekPhoneTests {
    @Test func typedDigitsAreKeptUpToNine() {
        #expect(UzbekPhone.digits(from: "90 123") == "90123")
        #expect(UzbekPhone.digits(from: "9012345678") == "901234567")
        #expect(UzbekPhone.digits(from: "90a1") == "901")
    }

    // Review Focus 4.
    @Test(arguments: ["+998 90 123-45-67", "998901234567", "+998901234567"])
    func aPastedFullNumberKeepsTheSubscriberDigits(pasted: String) {
        #expect(UzbekPhone.digits(from: pasted) == "901234567")
    }

    @Test func digitsAreGroupedAsTheyArePrinted() {
        #expect(UzbekPhone.grouped("901234567") == "90 123 45 67")
        #expect(UzbekPhone.grouped("9012") == "90 12")
        #expect(UzbekPhone.grouped("") == "")
    }

    @Test func onlyAFullNumberHasAnE164Form() {
        #expect(UzbekPhone.e164("901234567") == "+998901234567")
        #expect(UzbekPhone.e164("90123") == nil)
    }

    @Test func aStoredNumberReadsBack() {
        #expect(UzbekPhone.digits(fromE164: "+998901234567") == "901234567")
        #expect(UzbekPhone.digits(fromE164: nil) == "")
        #expect(UzbekPhone.display("+998901234567") == "+998 90 123 45 67")
    }
}

@Suite struct AvatarTests {
    @Test func aKnownKeyIsItsTone() {
        #expect(AvatarTone.forKey("sky") == .sky)
    }

    @Test func anUnknownKeyFallsBackByPosition() {
        #expect(AvatarTone.forKey(nil) == .teal)
        #expect(AvatarTone.forKey("violet", position: 1) == .apricot)
        #expect(AvatarTone.forKey("violet", position: 5) == .sky)
    }

    @Test func theInitialIsTheNamesFirstLetter() {
        #expect(NozirAvatar.initial(of: "  ali", fallback: "A") == "A")
        #expect(NozirAvatar.initial(of: "vali", fallback: "A") == "V")
        #expect(NozirAvatar.initial(of: " ", fallback: "A") == "A")
    }
}

@Suite struct QRCodeTests {
    @Test func aPayloadBecomesASquareImage() throws {
        let image = try #require(NozirQRCode.image(for: "nozir://pair?code=472918"))
        #expect(image.size.width == image.size.height)
        #expect(image.size.width > 0)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Expected: FAIL — `cannot find 'UzbekPhone' in scope`.

- [ ] **Step 3: Ranglar va raqam**

`NozirKit/Sources/NozirDesignSystem/NozirColor.swift` — `criticalBorder` qatoridan keyin:

```swift
    public static let onPrimaryContainer = color(light: 0x07695F, dark: 0x7FD6CB)
    public static let apricotContent = color(light: 0xC2500F, dark: 0xE59F7E)
    public static let apricotContainer = color(light: 0xFFF0E4, dark: 0xD95926, darkAlpha: 0.12)
    public static let skyContent = color(light: 0x2A78D6, dark: 0x3987E5)
    public static let skyContainer = color(light: 0xE8F2FF, dark: 0x3987E5, darkAlpha: 0.12)
    public static let attentionContent = color(light: 0xB87503, dark: 0xE5A63B)
    public static let attentionContainer = color(light: 0xFDF3E0, dark: 0xE5A63B, darkAlpha: 0.12)
    public static let attentionBorder = color(light: 0xF0D9A8, dark: 0xE5A63B, darkAlpha: 0.30)
```

`NozirKit/Sources/NozirDesignSystem/UzbekPhone.swift`:

```swift
/// A +998 number as a parent types and reads it: the country code is fixed on
/// screen, so the field holds the nine subscriber digits only.
public enum UzbekPhone {
    public static let subscriberDigits = 9

    /// The subscriber digits in whatever was typed or pasted. A whole number
    /// ("+998 90 123-45-67", or autofill's "+998901234567") loses its country code.
    public static func digits(from input: String) -> String {
        var digits = input.filter { $0.isASCII && $0.isNumber }
        if digits.count == 12, digits.hasPrefix("998") {
            digits.removeFirst(3)
        }
        return String(digits.prefix(subscriberDigits))
    }

    /// "901234567" → "90 123 45 67"; a partial number is grouped as far as it goes.
    public static func grouped(_ digits: String) -> String {
        var parts: [String] = []
        var rest = Substring(digits)
        for size in [2, 3, 2, 2] where !rest.isEmpty {
            parts.append(String(rest.prefix(size)))
            rest = rest.dropFirst(size)
        }
        return parts.joined(separator: " ")
    }

    /// The server's form, or nil while the number is incomplete.
    public static func e164(_ digits: String) -> String? {
        digits.count == subscriberDigits ? "+998" + digits : nil
    }

    public static func digits(fromE164 number: String?) -> String {
        guard let number, number.hasPrefix("+998") else { return "" }
        return digits(from: String(number.dropFirst(4)))
    }

    /// "+998901234567" → "+998 90 123 45 67". Anything else is shown as it is.
    public static func display(_ number: String) -> String {
        let digits = digits(fromE164: number)
        return digits.count == subscriberDigits ? "+998 " + grouped(digits) : number
    }
}
```

- [ ] **Step 4: Komponentlar**

`NozirKit/Sources/NozirDesignSystem/Components/NozirFields.swift`:

```swift
import SwiftUI
import UIKit

/// A labelled text field whose owner may refuse a keystroke (a fifth year
/// digit, a 41st letter). Like `NozirCodeField` it keeps its own text and copies
/// the owner's value back after every edit, so what is shown is what is kept.
public struct NozirTextField: View {
    private let label: String
    @Binding private var value: String
    private let placeholder: String
    private let error: String?
    private let keyboard: UIKeyboardType
    @State private var text = ""

    public init(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        error: String? = nil,
        keyboard: UIKeyboardType = .default
    ) {
        self.label = label
        _value = text
        self.placeholder = placeholder
        self.error = error
        self.keyboard = keyboard
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            Text(label).nozirText(.bodySmall, color: NozirColor.textSecondary)
            TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
                .keyboardType(keyboard)
                .nozirText(.body)
                .fieldFrame(hasError: error != nil)
                .accessibilityLabel(label)
            if let error {
                NozirInlineMessage(error)
            }
        }
        .onAppear { text = value }
        .onChange(of: text) { _, typed in
            value = typed
            if text != value { text = value }
        }
        .onChange(of: value) { _, kept in
            if text != kept { text = kept }
        }
    }
}

/// Android `NozirPhoneField`: a fixed "🇺🇿 +998" prefix and nine digits shown
/// as "90 123 45 67". The binding holds the digits only.
public struct NozirPhoneField: View {
    private let label: String
    @Binding private var digits: String
    private let prefix: String
    private let placeholder: String
    private let error: String?
    @State private var text = ""

    public init(_ label: String, digits: Binding<String>, prefix: String, placeholder: String, error: String? = nil) {
        self.label = label
        _digits = digits
        self.prefix = prefix
        self.placeholder = placeholder
        self.error = error
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.small) {
            Text(label).nozirText(.bodySmall, color: NozirColor.textSecondary)
            HStack(spacing: NozirSpacing.small) {
                Text(prefix).nozirText(.body, color: NozirColor.textSecondary)
                TextField("", text: $text, prompt: Text(placeholder).foregroundColor(NozirColor.textTertiary))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .nozirText(.body)
                    .accessibilityLabel(label)
            }
            .fieldFrame(hasError: error != nil)
            if let error {
                NozirInlineMessage(error)
            }
        }
        .onAppear { text = UzbekPhone.grouped(digits) }
        .onChange(of: text) { _, typed in
            let kept = UzbekPhone.digits(from: typed)
            if digits != kept { digits = kept }
            let shown = UzbekPhone.grouped(digits)
            if text != shown { text = shown }
        }
        .onChange(of: digits) { _, kept in
            let shown = UzbekPhone.grouped(kept)
            if text != shown { text = shown }
        }
    }
}

extension View {
    /// The box every Nozir field sits in; the border turns orange with an error.
    func fieldFrame(hasError: Bool) -> some View {
        padding(.horizontal, NozirSpacing.medium)
            .frame(minHeight: NozirSize.control)
            .background(RoundedRectangle(cornerRadius: NozirRadius.field).fill(NozirColor.card))
            .overlay(
                RoundedRectangle(cornerRadius: NozirRadius.field)
                    .strokeBorder(hasError ? NozirColor.actionContent : NozirColor.border, lineWidth: NozirSize.borderResting)
            )
    }
}
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirAvatar.swift`:

```swift
import SwiftUI

/// Android `NozirAvatarTone`: an identity colour, never a status. `rawValue`
/// is what the server stores.
public enum AvatarTone: String, CaseIterable, Sendable {
    case teal, apricot, sky

    /// The stored key's tone; a key this app does not know falls back to a
    /// colour by list position (Android `AvatarToneForChild`).
    public static func forKey(_ key: String?, position: Int = 0) -> AvatarTone {
        if let key, let tone = AvatarTone(rawValue: key) { return tone }
        return allCases[abs(position) % allCases.count]
    }

    var container: Color {
        switch self {
        case .teal: NozirColor.primaryContainer
        case .apricot: NozirColor.apricotContainer
        case .sky: NozirColor.skyContainer
        }
    }

    var content: Color {
        switch self {
        case .teal: NozirColor.onPrimaryContainer
        case .apricot: NozirColor.apricotContent
        case .sky: NozirColor.skyContent
        }
    }
}

/// A child's initial in their colour.
public struct NozirAvatar: View {
    private let initial: String
    private let tone: AvatarTone
    private let size: CGFloat

    public init(name: String, tone: AvatarTone, fallbackInitial: String, size: CGFloat = 40) {
        initial = Self.initial(of: name, fallback: fallbackInitial)
        self.tone = tone
        self.size = size
    }

    static func initial(of name: String, fallback: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).first.map { String($0).uppercased() } ?? fallback
    }

    public var body: some View {
        Text(initial)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tone.content)
            .frame(width: size, height: size)
            .background(Circle().fill(tone.container))
            .accessibilityHidden(true)
    }
}

/// Android `AvatarChoiceRow`: the three tones, the chosen one ringed.
public struct NozirAvatarPicker: View {
    @Binding private var selection: AvatarTone
    private let name: String
    private let fallbackInitial: String
    private let accessibilityLabel: String

    public init(selection: Binding<AvatarTone>, name: String, fallbackInitial: String, accessibilityLabel: String) {
        _selection = selection
        self.name = name
        self.fallbackInitial = fallbackInitial
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.medium) {
            ForEach(AvatarTone.allCases, id: \.self) { tone in
                Button {
                    selection = tone
                } label: {
                    NozirAvatar(name: name, tone: tone, fallbackInitial: fallbackInitial, size: 48)
                        .padding(4)
                        .overlay(
                            Circle().strokeBorder(
                                selection == tone ? NozirColor.primary : Color.clear,
                                lineWidth: NozirSize.borderEmphasis
                            )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tone.rawValue)
                .accessibilityAddTraits(selection == tone ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }
}
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirCard.swift`:

```swift
import SwiftUI

public enum NozirCardTone: Sendable {
    case plain, attention
}

/// Android `NozirCard`: a rounded surface with a hairline border.
public struct NozirCard<Content: View>: View {
    private let tone: NozirCardTone
    private let content: Content

    public init(tone: NozirCardTone = .plain, @ViewBuilder content: () -> Content) {
        self.tone = tone
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.compact) {
            content
        }
        .padding(NozirSpacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .fill(tone == .attention ? NozirColor.attentionContainer : NozirColor.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: NozirRadius.cardCompact)
                .strokeBorder(tone == .attention ? NozirColor.attentionBorder : NozirColor.border, lineWidth: NozirSize.borderResting)
        )
    }
}
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirRows.swift`:

```swift
import SwiftUI

public enum NozirStatusLevel: Sendable {
    case good, attention, action
}

/// A small coloured dot beside a status label; the label carries the meaning.
public struct NozirStatusDot: View {
    private let level: NozirStatusLevel

    public init(_ level: NozirStatusLevel) {
        self.level = level
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .accessibilityHidden(true)
    }

    private var color: Color {
        switch level {
        case .good: NozirColor.goodContent
        case .attention: NozirColor.attentionContent
        case .action: NozirColor.actionContent
        }
    }
}

public struct NozirSectionTitle: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .nozirText(.titleSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A tappable settings line: title, the current value, a chevron.
public struct NozirSettingsRow: View {
    private let title: String
    private let value: String?
    private let action: () -> Void

    public init(_ title: String, value: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.value = value
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: NozirSpacing.small) {
                Text(title).nozirText(.body)
                Spacer(minLength: NozirSpacing.small)
                if let value {
                    Text(value).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(NozirColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: NozirSize.control)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// One step of P04's checklist: done steps are ticked.
public struct NozirChecklistRow: View {
    private let text: String
    private let isDone: Bool

    public init(_ text: String, isDone: Bool) {
        self.text = text
        self.isDone = isDone
    }

    public var body: some View {
        HStack(spacing: NozirSpacing.compact) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? NozirColor.goodContent : NozirColor.textTertiary)
                .accessibilityHidden(true)
            Text(text).nozirText(.body, color: isDone ? NozirColor.textPrimary : NozirColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isDone ? .isSelected : [])
    }
}
```

`NozirKit/Sources/NozirDesignSystem/Components/NozirQRCode.swift`:

```swift
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// The pairing code as a QR. Black on white in both themes, with a quiet zone:
/// scanners look for dark modules on a light ground.
public struct NozirQRCode: View {
    private let payload: String
    private let accessibilityLabel: String
    @State private var image: UIImage?

    public init(payload: String, accessibilityLabel: String) {
        self.payload = payload
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: 184, height: 184)
        .padding(NozirSpacing.compact)
        .background(RoundedRectangle(cornerRadius: NozirRadius.cardCompact).fill(Color.white))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        // Drawn once per code, not on every redraw of the screen around it.
        .task(id: payload) { image = Self.image(for: payload) }
    }

    /// Medium error correction, as the Android app draws it (ZXing ECC M).
    static func image(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
```

- [ ] **Step 5: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirDesignSystemTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirDesignSystem NozirKit/Tests/NozirDesignSystemTests/ComponentLogicTests.swift
```

Xabar: `design: fields, avatars, cards, rows and the pairing QR`

---
### Task 9: P03 — bola haqida (`AddChildModel`, `AddChildView`) va oila soxtasi

**Files:**
- Modify: `NozirKit/Package.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Family/AddChildModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/AddChildView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/AddChildModelTests.swift`

**Interfaces:**
- Consumes: Task 7 (`FamilyService` va modellar), Task 8 (`UzbekPhone`, `AvatarTone`, maydonlar).
- Produces:
  - `public struct ChildDraft: Hashable, Sendable { displayName: String; birthYear: Int; avatarKey: String; phoneE164: String?; var create: ChildCreate }`
  - `enum ChildAge { static let range = 7...17; static let nameLimit = 40; static func of(birthYearText:currentYear:) -> Int?; static func yearDigits(from:) -> String; static func name(from:) -> String }`
  - `@MainActor @Observable public final class AddChildModel { name; birthYearText; phoneDigits; var avatar: AvatarTone; init(currentYear:); updateName(_:); updateBirthYear(_:); updatePhone(_:); age: Int?; showsPhoneError: Bool; draft: ChildDraft?; canContinue: Bool }`
  - `struct AddChildView: View { init(model: AddChildModel, onContinue: @escaping (ChildDraft) -> Void) }`
  - Test yordamchilari (`FakeFamily.swift`): `actor FakeFamily: FamilyService` (`Script` navbatlari, `calls`, `created`, `updates`, `screenTimeWrites`, `bedtimeWrites`, `locales`, `add(_:)`), `offline`, `makeChild(…)`, `snapshot(version:…)`, `pairingCode(…)`, `RuleWrite`

- [ ] **Step 1: Package bog'liqliklari**

`NozirKit/Package.swift` — `NozirAppFeature` dependencies'ga `"NozirFamily"`, `NozirAppFeatureTests` dependencies'ga `"NozirFamily"` va `"NozirDesignSystem"` qo'shing:

```swift
        .target(
            name: "NozirAppFeature",
            dependencies: ["NozirNetworking", "NozirAuth", "NozirConfig", "NozirDesignSystem", "NozirL10n", "NozirFamily"]
        ),
```

```swift
        .testTarget(
            name: "NozirAppFeatureTests",
            dependencies: ["NozirAppFeature", "NozirAuth", "NozirConfig", "NozirNetworking", "NozirL10n", "NozirFamily", "NozirDesignSystem"]
        ),
```

- [ ] **Step 2: Oila soxtasi (keyingi task'lar ham ishlatadi)**

`NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift`:

```swift
import Foundation
import NozirFamily
import NozirNetworking

let offline = ApiFailure.network(code: URLError.Code.notConnectedToInternet.rawValue)

struct RuleWrite<Value: Equatable & Sendable>: Equatable, Sendable {
    let value: Value
    let version: Int64
}

/// Answers each family call from its own queue, in order, and records what was
/// asked. An empty queue answers like a phone with no connection.
actor FakeFamily: FamilyService {
    struct Script: Sendable {
        var children: [Result<[Child], ApiFailure>] = []
        var child: [Result<Child, ApiFailure>] = []
        var create: [Result<Child, ApiFailure>] = []
        var update: [Result<Child, ApiFailure>] = []
        var remove: [Result<Void, ApiFailure>] = []
        var rules: [Result<RuleSnapshot, ApiFailure>] = []
        var screenTime: [Result<RuleSnapshot, ApiFailure>] = []
        var bedtime: [Result<RuleSnapshot, ApiFailure>] = []
        var currentCode: [Result<PairingCode?, ApiFailure>] = []
        var issueCode: [Result<PairingCode, ApiFailure>] = []
        var devices: [Result<[ChildDevice], ApiFailure>] = []
        var subscription: [Result<Subscription, ApiFailure>] = []
        var activeChild: [Result<Subscription, ApiFailure>] = []
        var me: [Result<ParentProfile, ApiFailure>] = []
        var locale: [Result<ParentProfile, ApiFailure>] = []
    }

    private var script: Script
    private(set) var calls: [String] = []
    private(set) var created: [ChildCreate] = []
    private(set) var updates: [ChildUpdate] = []
    private(set) var screenTimeWrites: [RuleWrite<ScreenTimeLimit>] = []
    private(set) var bedtimeWrites: [RuleWrite<BedtimeSchedule>] = []
    private(set) var locales: [String] = []

    init(_ script: Script = Script()) {
        self.script = script
    }

    func add(_ change: @Sendable (inout Script) -> Void) {
        change(&script)
    }

    private func next<T>(_ name: String, _ queue: WritableKeyPath<Script, [Result<T, ApiFailure>]>) throws -> T {
        calls.append(name)
        guard !script[keyPath: queue].isEmpty else { throw offline }
        return try script[keyPath: queue].removeFirst().get()
    }

    func children() async throws -> [Child] { try next("children", \.children) }
    func child(_ id: UUID) async throws -> Child { try next("child", \.child) }

    func createChild(_ child: ChildCreate) async throws -> Child {
        created.append(child)
        return try next("create", \.create)
    }

    func updateChild(_ id: UUID, _ update: ChildUpdate) async throws -> Child {
        updates.append(update)
        return try next("update", \.update)
    }

    func removeChild(_ id: UUID) async throws { try next("remove", \.remove) }
    func rules(of childId: UUID) async throws -> RuleSnapshot { try next("rules", \.rules) }

    func setScreenTime(_ limit: ScreenTimeLimit, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        screenTimeWrites.append(RuleWrite(value: limit, version: version))
        return try next("screenTime", \.screenTime)
    }

    func setBedtime(_ bedtime: BedtimeSchedule, of childId: UUID, version: Int64) async throws -> RuleSnapshot {
        bedtimeWrites.append(RuleWrite(value: bedtime, version: version))
        return try next("bedtime", \.bedtime)
    }

    func currentPairingCode(for childId: UUID) async throws -> PairingCode? { try next("currentCode", \.currentCode) }
    func issuePairingCode(for childId: UUID) async throws -> PairingCode { try next("issueCode", \.issueCode) }
    func devices(of childId: UUID) async throws -> [ChildDevice] { try next("devices", \.devices) }
    func subscription() async throws -> Subscription { try next("subscription", \.subscription) }
    func chooseActiveChild(_ childId: UUID) async throws -> Subscription { try next("activeChild", \.activeChild) }
    func me() async throws -> ParentProfile { try next("me", \.me) }

    func updateLocale(_ locale: String) async throws -> ParentProfile {
        locales.append(locale)
        return try next("locale", \.locale)
    }
}

func makeChild(
    _ name: String = "Ali",
    id: UUID = UUID(),
    birthYear: Int = 2015,
    phone: String? = nil,
    avatar: String? = "teal",
    state: PairingState = .notPaired
) -> Child {
    Child(id: id, displayName: name, birthYear: birthYear, ageGroup: .explorer, avatarKey: avatar, phoneE164: phone, pairingState: state)
}

let defaultLimit = ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60)
let defaultBedtime = BedtimeSchedule(
    start: ClockTime(hour: 22, minute: 0),
    end: ClockTime(hour: 7, minute: 0),
    windDownMinutes: 30,
    activeDays: [1, 2, 3, 4, 5, 6, 7]
)

func snapshot(version: Int64, limit: ScreenTimeLimit = defaultLimit, bedtime: BedtimeSchedule = defaultBedtime) -> RuleSnapshot {
    RuleSnapshot(version: version, screenTime: limit, bedtime: bedtime)
}

func pairingCode(_ code: String = "472918", state: PairingState = .codeIssued) -> PairingCode {
    PairingCode(code: code, expiresAt: Date(timeIntervalSince1970: 1_791_200_000), qrPayload: "nozir://pair?code=\(code)", state: state)
}
```

- [ ] **Step 3: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/AddChildModelTests.swift`:

```swift
import Testing
import NozirDesignSystem
@testable import NozirAppFeature

@MainActor
@Suite struct AddChildModelTests {
    private func makeModel() -> AddChildModel {
        AddChildModel(currentYear: 2026)
    }

    @Test(arguments: zip(["2019", "2015", "2009", "2020", "2008", "201", "1990"], [7, 11, 17, nil, nil, nil, nil] as [Int?]))
    func onlyAnAgeTheChildAppHasABandForCounts(year: String, age: Int?) {
        let model = makeModel()
        model.updateBirthYear(year)

        #expect(model.age == age)
    }

    @Test func theYearKeepsFourDigitsOnly() {
        let model = makeModel()

        model.updateBirthYear("20a155")

        #expect(model.birthYearText == "2015")
    }

    @Test func aNameIsCappedAtFortyAndTrimmedInTheDraft() {
        let model = makeModel()
        model.updateName(String(repeating: "a", count: 45))
        #expect(model.name.count == 40)

        model.updateName("  Ali ")
        model.updateBirthYear("2015")

        #expect(model.draft?.displayName == "Ali")
    }

    @Test func aBlankNameCannotContinue() {
        let model = makeModel()
        model.updateName("   ")
        model.updateBirthYear("2015")

        #expect(!model.canContinue)
    }

    @Test func aPartialPhoneIsAnErrorAndAnEmptyOneIsNot() {
        let model = makeModel()
        model.updateName("Ali")
        model.updateBirthYear("2015")

        model.updatePhone("90123")
        #expect(model.showsPhoneError)
        #expect(!model.canContinue)

        model.updatePhone("")
        #expect(!model.showsPhoneError)
        #expect(model.canContinue)
    }

    @Test func theDraftCarriesWhatTheParentGave() {
        let model = makeModel()
        model.updateName("Ali")
        model.updateBirthYear("2015")
        model.updatePhone("+998 90 123 45 67")
        model.avatar = .sky

        #expect(model.draft == ChildDraft(displayName: "Ali", birthYear: 2015, avatarKey: "sky", phoneE164: "+998901234567"))
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'AddChildModel' in scope`.

- [ ] **Step 5: Model va ekran**

`NozirKit/Sources/NozirAppFeature/Family/AddChildModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily

/// What P03 collects. Nothing reaches the server until P03b saves it.
public struct ChildDraft: Hashable, Sendable {
    public let displayName: String
    public let birthYear: Int
    public let avatarKey: String
    public let phoneE164: String?

    var create: ChildCreate {
        ChildCreate(displayName: displayName, birthYear: birthYear, avatarKey: avatarKey, phoneE164: phoneE164)
    }
}

/// The rules P03 and the child details screen share.
enum ChildAge {
    /// The backend's age bands cover 7–17; Android accepts the same.
    static let range = 7...17
    /// `CreateChildBody.displayName` max length.
    static let nameLimit = 40

    static func of(birthYearText: String, currentYear: Int) -> Int? {
        guard birthYearText.count == 4, let year = Int(birthYearText) else { return nil }
        let age = currentYear - year
        return range.contains(age) ? age : nil
    }

    static func yearDigits(from input: String) -> String {
        String(input.filter { $0.isASCII && $0.isNumber }.prefix(4))
    }

    static func name(from input: String) -> String {
        String(input.prefix(nameLimit))
    }
}

/// P03 (Android `AddChildForm`).
@MainActor
@Observable
public final class AddChildModel {
    public private(set) var name = ""
    public private(set) var birthYearText = ""
    public private(set) var phoneDigits = ""
    public var avatar: AvatarTone = .teal
    private let currentYear: Int

    public init(currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.currentYear = currentYear
    }

    public func updateName(_ input: String) {
        name = ChildAge.name(from: input)
    }

    public func updateBirthYear(_ input: String) {
        birthYearText = ChildAge.yearDigits(from: input)
    }

    public func updatePhone(_ input: String) {
        phoneDigits = UzbekPhone.digits(from: input)
    }

    public var age: Int? {
        ChildAge.of(birthYearText: birthYearText, currentYear: currentYear)
    }

    /// Empty is fine (a child without a number of their own); half a number is not.
    public var showsPhoneError: Bool {
        !phoneDigits.isEmpty && phoneDigits.count != UzbekPhone.subscriberDigits
    }

    public var draft: ChildDraft? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, age != nil, !showsPhoneError, let year = Int(birthYearText) else { return nil }
        return ChildDraft(displayName: trimmed, birthYear: year, avatarKey: avatar.rawValue, phoneE164: UzbekPhone.e164(phoneDigits))
    }

    public var canContinue: Bool {
        draft != nil
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/AddChildView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirL10n

/// P03 as Android `AddChildScreen`: name, birth year (and the age it means),
/// an optional phone, a colour.
struct AddChildView: View {
    @State private var model: AddChildModel
    private let onContinue: (ChildDraft) -> Void
    @Environment(\.l10n) private var l10n

    init(model: AddChildModel, onContinue: @escaping (ChildDraft) -> Void) {
        _model = State(initialValue: model)
        self.onContinue = onContinue
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.addChildTopBar).nozirText(.titleLarge)
                NozirTextField(
                    l10n.addChildLabelName,
                    text: Binding(get: { model.name }, set: { model.updateName($0) }),
                    placeholder: l10n.addChildNamePlaceholder
                )
                NozirTextField(
                    l10n.addChildLabelBirthYear,
                    text: Binding(get: { model.birthYearText }, set: { model.updateBirthYear($0) }),
                    placeholder: l10n.addChildBirthYearPlaceholder,
                    keyboard: .numberPad
                )
                if let age = model.age {
                    NozirCard {
                        Text(l10n.addChildAgeYears(age)).nozirText(.titleSmall)
                        Text(l10n.addChildAgeNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
                VStack(alignment: .leading, spacing: NozirSpacing.small) {
                    NozirPhoneField(
                        l10n.addChildLabelPhone,
                        digits: Binding(get: { model.phoneDigits }, set: { model.updatePhone($0) }),
                        prefix: l10n.phoneFieldPrefix,
                        placeholder: l10n.phoneFieldPlaceholder,
                        error: model.showsPhoneError ? l10n.addChildErrorPhone : nil
                    )
                    Text(l10n.addChildPhoneNote).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
                VStack(alignment: .leading, spacing: NozirSpacing.small) {
                    Text(l10n.addChildLabelAvatar).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    NozirAvatarPicker(
                        selection: $model.avatar,
                        name: model.name,
                        fallbackInitial: l10n.previewAvatarInitial,
                        accessibilityLabel: l10n.contentDescriptionAvatarChoice
                    )
                }
                NozirButton(l10n.buttonContinue, size: .callToAction) {
                    if let draft = model.draft { onContinue(draft) }
                }
                .disabled(!model.canContinue)
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenAddChildTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 6: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Package.swift NozirKit/Sources/NozirAppFeature/Family/AddChildModel.swift NozirKit/Sources/NozirAppFeature/Screens/AddChildView.swift NozirKit/Tests/NozirAppFeatureTests/FakeFamily.swift NozirKit/Tests/NozirAppFeatureTests/AddChildModelTests.swift
```

Xabar: `p03: who the child is, before anything is sent`

---
### Task 10: P03b — boshlang'ich qoidalar (`NewChildRulesModel`, `NewChildRulesView`)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Durations.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/NewChildRulesModelTests.swift`

**Interfaces:**
- Consumes: Task 9 (`ChildDraft`, `FakeFamily`, `makeChild`, `snapshot`, `defaultLimit`, `defaultBedtime`), Task 7 (`FamilyStore`, `ScreenTimeLimit`, `BedtimeSchedule`, `ClockTime`), Task 5 (`UserMessage`).
- Produces:
  - `enum Durations { static func short(_ minutes: Int, _ l10n: L10n) -> String; static func long(_ minutes: Int, _ l10n: L10n) -> String; static func range(_ base: ClosedRange<Int>, including value: Int) -> ClosedRange<Double> }`
  - `extension ClockTime { init(date: Date, calendar: Calendar = .current); func date(calendar: Calendar = .current) -> Date }`
  - `@MainActor @Observable public final class NewChildRulesModel { let draft; var schoolDayMinutes; var weekendMinutes; maxDailyBonusMinutes; var bedtimeStart; var bedtimeEnd; windDownMinutes; activeDays: Set<Int>; isPrefilledFromSibling; isSaving; message: UserMessage?; init(draft:family:); prefill() async; isWindDownOn; setWindDown(on:); setWindDownMinutes(_:); toggleDay(_:); bedtime: BedtimeSchedule; limit: ScreenTimeLimit; save() async -> Child?; static func daysSummary(_:_:) -> String }`
  - `struct NewChildRulesView: View { init(model: NewChildRulesModel, onSaved: @escaping (Child) -> Void) }`

Oqim (D5): `POST children` (faqat birinchi marta) → `GET rules` (har urinishda yangi versiya) → `PUT screen-time` (If-Match: shu versiya) → `PUT bedtime` (If-Match: screen-time javobining versiyasi). Xato → matn, bola saqlanadi, "Saqlash" qayta bosilsa yaratish o'tkazib yuboriladi. Sukutlar Android `NewChildRulesDefaults` (backend `V4__rules.sql` bilan bir xil); aka-uka bo'lsa — oxirgi bolaning qoidalari ko'chiriladi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/NewChildRulesModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
import NozirL10n
import NozirNetworking
@testable import NozirAppFeature

private let draft = ChildDraft(displayName: "Ali", birthYear: 2015, avatarKey: "teal", phoneE164: nil)

@MainActor
private func setup(_ script: FakeFamily.Script = .init(), siblings: [Child] = []) -> (NewChildRulesModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    siblings.forEach(family.replace)
    return (NewChildRulesModel(draft: draft, family: family), fake, family)
}

@MainActor
@Suite struct NewChildRulesModelTests {
    @Test func aFirstChildStartsFromTheDefaults() async {
        let (model, fake, _) = setup()

        await model.prefill()

        #expect(model.limit == ScreenTimeLimit(schoolDayMinutes: 120, weekendMinutes: 180, maxDailyBonusMinutes: 60))
        #expect(model.bedtime == defaultBedtime)
        #expect(!model.isPrefilledFromSibling)
        #expect(await fake.calls.isEmpty)
    }

    @Test func aSecondChildStartsFromTheLastChildsRules() async {
        var script = FakeFamily.Script()
        let siblingBedtime = BedtimeSchedule(start: ClockTime(hour: 21, minute: 0), end: ClockTime(hour: 6, minute: 30), windDownMinutes: 0, activeDays: [1, 2, 3, 4, 5])
        script.rules = [.success(snapshot(version: 3, limit: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 45), bedtime: siblingBedtime))]
        let (model, _, _) = setup(script, siblings: [makeChild("Vali"), makeChild("Sardor")])

        await model.prefill()

        #expect(model.limit == ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 150, maxDailyBonusMinutes: 45))
        #expect(model.bedtime == siblingBedtime)
        #expect(model.isPrefilledFromSibling)
    }

    @Test func aSiblingWhoseRulesCannotBeReadLeavesTheDefaultsQuietly() async {
        let (model, _, _) = setup(siblings: [makeChild("Vali")])

        await model.prefill()

        #expect(model.limit == defaultLimit)
        #expect(!model.isPrefilledFromSibling)
        #expect(model.message == nil)
    }

    // Review Focus 5.
    @Test func siblingValuesOutsideTheSliderAreKeptAsTheyAre() async {
        var script = FakeFamily.Script()
        script.rules = [
            .success(snapshot(version: 3, limit: ScreenTimeLimit(schoolDayMinutes: 0, weekendMinutes: 480, maxDailyBonusMinutes: 60))),
            .success(snapshot(version: 1)),
        ]
        script.create = [.success(makeChild("Ali"))]
        script.screenTime = [.success(snapshot(version: 2))]
        script.bedtime = [.success(snapshot(version: 3))]
        let (model, fake, _) = setup(script, siblings: [makeChild("Vali")])

        await model.prefill()
        _ = await model.save()

        #expect(model.schoolDayMinutes == 0)
        #expect(await fake.screenTimeWrites.first?.value == ScreenTimeLimit(schoolDayMinutes: 0, weekendMinutes: 480, maxDailyBonusMinutes: 60))
    }

    @Test func theLastNightCannotBeTurnedOff() {
        let (model, _, _) = setup()
        for day in 1...6 { model.toggleDay(day) }
        #expect(model.activeDays == [7])

        model.toggleDay(7)

        #expect(model.activeDays == [7])
    }

    @Test func windDownOffIsZeroAndOnIsThirty() {
        let (model, _, _) = setup()

        model.setWindDown(on: false)
        #expect(model.bedtime.windDownMinutes == 0)
        model.setWindDownMinutes(45)
        #expect(model.windDownMinutes == 0)

        model.setWindDown(on: true)
        #expect(model.windDownMinutes == 30)
    }

    @Test func savingCreatesTheChildThenWritesEachRuleAgainstTheVersionBeforeIt() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.create = [.success(ali)]
        script.rules = [.success(snapshot(version: 5))]
        script.screenTime = [.success(snapshot(version: 6))]
        script.bedtime = [.success(snapshot(version: 7))]
        let (model, fake, family) = setup(script)
        model.schoolDayMinutes = 90

        let saved = await model.save()

        #expect(saved == ali)
        #expect(await fake.created == [draft.create])
        #expect(await fake.screenTimeWrites == [RuleWrite(value: ScreenTimeLimit(schoolDayMinutes: 90, weekendMinutes: 180, maxDailyBonusMinutes: 60), version: 5)])
        #expect(await fake.bedtimeWrites.map(\.version) == [6])
        #expect(family.child(ali.id) == ali)
        #expect(!model.isSaving)
    }

    @Test func theChildLimitStopsBeforeAnyRule() async {
        var script = FakeFamily.Script()
        script.create = [.failure(.server(status: 403, error: ApiError(code: .childLimitReached)))]
        let (model, fake, _) = setup(script)

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.message == .childLimitReached)
        #expect(await fake.calls == ["create"])
    }

    @Test func aConflictIsShownAndNotResentBlindly() async {
        var script = FakeFamily.Script()
        script.create = [.success(makeChild("Ali"))]
        script.rules = [.success(snapshot(version: 5))]
        script.screenTime = [.failure(.server(status: 409, error: ApiError(code: .conflict)))]
        let (model, fake, _) = setup(script)

        let saved = await model.save()

        #expect(saved == nil)
        #expect(model.message == .conflict)
        #expect(await fake.calls == ["create", "rules", "screenTime"])
    }

    // Review Focus 2.
    @Test func savingAgainAfterAFailureDoesNotCreateASecondChild() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.create = [.success(ali)]
        script.rules = [.failure(offline), .success(snapshot(version: 8))]
        script.screenTime = [.success(snapshot(version: 9))]
        script.bedtime = [.success(snapshot(version: 10))]
        let (model, fake, _) = setup(script)

        #expect(await model.save() == nil)
        #expect(model.message == .noConnection)
        let saved = await model.save()

        #expect(saved == ali)
        #expect(model.message == nil)
        #expect(await fake.created.count == 1)
        #expect(await fake.screenTimeWrites.map(\.version) == [8])
    }

    @Test func theNightsAreNamed() {
        let l10n = L10n(.uz)
        #expect(NewChildRulesModel.daysSummary([1, 2, 3, 4, 5, 6, 7], l10n) == l10n.bedtimeDaysEveryNight)
        #expect(NewChildRulesModel.daysSummary([3, 1], l10n) == l10n.bedtimeDaysSummary("Dushanba, Chorshanba"))
    }
}

@Suite struct DurationsTests {
    @Test func shortAndLongReadAsAndroidWritesThem() {
        let l10n = L10n(.uz)
        #expect(Durations.short(150, l10n) == "2s 30d")
        #expect(Durations.short(45, l10n) == l10n.durationShortMinutes(45))
        #expect(Durations.long(540, l10n) == l10n.durationLongHoursMinutes(9, 0))
    }

    @Test func aSliderStretchesToHoldAValueOutsideIt() {
        #expect(Durations.range(30...360, including: 120) == 30...360)
        #expect(Durations.range(30...360, including: 0) == 0...360)
        #expect(Durations.range(30...360, including: 480) == 30...480)
    }

    @Test func aClockTimeSurvivesTheDatePicker() {
        let time = ClockTime(hour: 21, minute: 45)
        #expect(ClockTime(date: time.date()) == time)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'NewChildRulesModel' in scope`, `cannot find 'Durations'`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirAppFeature/Durations.swift`:

```swift
import Foundation
import NozirFamily
import NozirL10n

/// Minutes as Android `DurationText` writes them.
enum Durations {
    /// "2s 30d", "45d".
    static func short(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours == 0 ? l10n.durationShortMinutes(rest) : l10n.durationShortHoursMinutes(hours, rest)
    }

    /// "9 soat 0 daqiqa", "45 daqiqa".
    static func long(_ minutes: Int, _ l10n: L10n) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        return hours == 0 ? l10n.durationLongMinutes(rest) : l10n.durationLongHoursMinutes(hours, rest)
    }

    /// A slider's range, stretched to hold a value that came from elsewhere (a
    /// sibling's rules), so the slider never moves it without the parent touching it.
    static func range(_ base: ClosedRange<Int>, including value: Int) -> ClosedRange<Double> {
        Double(min(base.lowerBound, value))...Double(max(base.upperBound, value))
    }
}

extension ClockTime {
    /// The hour and minute a `DatePicker` shows.
    init(date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// Today at this time, for a `DatePicker`.
    func date(calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }
}
```

`NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily
import NozirL10n

/// P03b (Android `NewChildRulesViewModel`): the first limit and bedtime, saved
/// together with the child.
@MainActor
@Observable
public final class NewChildRulesModel {
    static let windDownWhenOn = 30

    public let draft: ChildDraft
    public var schoolDayMinutes = 120
    public var weekendMinutes = 180
    public private(set) var maxDailyBonusMinutes = 60
    public var bedtimeStart = ClockTime(hour: 22, minute: 0)
    public var bedtimeEnd = ClockTime(hour: 7, minute: 0)
    public private(set) var windDownMinutes = NewChildRulesModel.windDownWhenOn
    public private(set) var activeDays: Set<Int> = Set(1...7)
    public private(set) var isPrefilledFromSibling = false
    public private(set) var isSaving = false
    public private(set) var message: UserMessage?
    /// Kept across attempts: a second "Save" must not add a second child.
    @ObservationIgnored private var created: Child?
    private let family: FamilyStore

    public init(draft: ChildDraft, family: FamilyStore) {
        self.draft = draft
        self.family = family
    }

    /// Starts from the rules of the child added last, as Android does. Quiet
    /// when there is none or they cannot be read: the defaults stand.
    public func prefill() async {
        guard !isPrefilledFromSibling, created == nil, let sibling = family.children.last else { return }
        guard let rules = try? await family.service.rules(of: sibling.id) else { return }
        schoolDayMinutes = rules.screenTime.schoolDayMinutes
        weekendMinutes = rules.screenTime.weekendMinutes
        maxDailyBonusMinutes = rules.screenTime.maxDailyBonusMinutes
        bedtimeStart = rules.bedtime.start
        bedtimeEnd = rules.bedtime.end
        windDownMinutes = rules.bedtime.windDownMinutes
        activeDays = Set(rules.bedtime.activeDays)
        isPrefilledFromSibling = true
    }

    public var isWindDownOn: Bool {
        windDownMinutes > 0
    }

    public func setWindDown(on: Bool) {
        windDownMinutes = on ? Self.windDownWhenOn : 0
    }

    public func setWindDownMinutes(_ minutes: Int) {
        guard isWindDownOn else { return }
        windDownMinutes = minutes
    }

    /// At least one night stays on.
    public func toggleDay(_ day: Int) {
        if activeDays.contains(day) {
            guard activeDays.count > 1 else { return }
            activeDays.remove(day)
        } else if (1...7).contains(day) {
            activeDays.insert(day)
        }
    }

    public var limit: ScreenTimeLimit {
        ScreenTimeLimit(schoolDayMinutes: schoolDayMinutes, weekendMinutes: weekendMinutes, maxDailyBonusMinutes: maxDailyBonusMinutes)
    }

    public var bedtime: BedtimeSchedule {
        BedtimeSchedule(start: bedtimeStart, end: bedtimeEnd, windDownMinutes: windDownMinutes, activeDays: activeDays.sorted())
    }

    /// Creates the child once, then writes each rule set against the version
    /// the answer before it gave. Any failure is shown and the child is kept;
    /// a 409 is never resent on its own (openapi `RuleVersionConflict`).
    public func save() async -> Child? {
        guard !isSaving else { return nil }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let child: Child
            if let created {
                child = created
            } else {
                child = try await family.service.createChild(draft.create)
                created = child
                family.replace(child)
            }
            let current = try await family.service.rules(of: child.id)
            let afterLimit = try await family.service.setScreenTime(limit, of: child.id, version: current.version)
            _ = try await family.service.setBedtime(bedtime, of: child.id, version: afterLimit.version)
            return child
        } catch {
            message = UserMessage(error)
            return nil
        }
    }

    /// "Har kuni", or "Faol tunlar: Dushanba, Chorshanba".
    static func daysSummary(_ days: Set<Int>, _ l10n: L10n) -> String {
        if days.count == 7 { return l10n.bedtimeDaysEveryNight }
        let names = days.sorted().compactMap { day in
            l10n.weekdayNames.indices.contains(day - 1) ? l10n.weekdayNames[day - 1] : nil
        }
        return l10n.bedtimeDaysSummary(names.joined(separator: l10n.bedtimeDaysSeparator))
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03b as Android `NewChildRulesScreen`: two limits, the night window, the nights.
struct NewChildRulesView: View {
    @State private var model: NewChildRulesModel
    private let onSaved: (Child) -> Void
    @Environment(\.l10n) private var l10n

    init(model: NewChildRulesModel, onSaved: @escaping (Child) -> Void) {
        _model = State(initialValue: model)
        self.onSaved = onSaved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.newChildRulesTitle(model.draft.displayName)).nozirText(.titleLarge)
                Text(model.isPrefilledFromSibling ? l10n.newChildRulesCopied : l10n.newChildRulesIntro)
                    .nozirText(.body, color: NozirColor.textSecondary)
                NozirCard { limitSection }
                NozirCard { bedtimeSection }
                Text(l10n.newChildRulesAppsLater).nozirText(.bodySmall, color: NozirColor.textTertiary)
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                NozirButton(l10n.newChildRulesActionContinue, size: .callToAction, isLoading: model.isSaving) {
                    Task {
                        if let child = await model.save() { onSaved(child) }
                    }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenNewChildRulesTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.prefill() }
    }

    private var limitSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesLimitLabel).nozirText(.titleSmall)
            minuteSlider(
                title: l10n.dailyLimitSchoolDays,
                caption: l10n.dailyLimitSchoolDaysRange,
                value: $model.schoolDayMinutes,
                accessibility: l10n.dailyLimitSliderSchool
            )
            minuteSlider(
                title: l10n.dailyLimitWeekend,
                caption: l10n.dailyLimitWeekendRange,
                value: $model.weekendMinutes,
                accessibility: l10n.dailyLimitSliderWeekend
            )
            HStack {
                Text(l10n.dailyLimitRangeMin)
                Spacer()
                Text(l10n.dailyLimitRangeMax)
            }
            .nozirText(.label, color: NozirColor.textTertiary)
        }
    }

    private func minuteSlider(title: String, caption: String, value: Binding<Int>, accessibility: String) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).nozirText(.body)
                    Text(caption).nozirText(.bodySmall, color: NozirColor.textTertiary)
                }
                Spacer()
                Text(Durations.short(value.wrappedValue, l10n)).nozirText(.titleSmall, color: NozirColor.primaryAccent)
            }
            // Android `RuleMinuteRange.DAILY_LIMIT`: 30…360 in steps of 15.
            Slider(
                value: Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0.rounded()) }),
                in: Durations.range(30...360, including: value.wrappedValue),
                step: 15
            )
            .tint(NozirColor.primary)
            .accessibilityLabel(accessibility)
            .accessibilityValue(Durations.long(value.wrappedValue, l10n))
        }
    }

    private var bedtimeSection: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.medium) {
            Text(l10n.newChildRulesBedtimeLabel).nozirText(.titleSmall)
            HStack(spacing: NozirSpacing.medium) {
                timePicker(l10n.bedtimeStartLabel, $model.bedtimeStart)
                timePicker(l10n.bedtimeEndLabel, $model.bedtimeEnd)
            }
            Text(l10n.bedtimeLength(Durations.long(model.bedtime.lengthMinutes, l10n)))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(l10n.bedtimeDaysLabel).nozirText(.body)
            HStack(spacing: NozirSpacing.extraSmall) {
                ForEach(1...7, id: \.self) { day in dayChip(day) }
            }
            Text(NewChildRulesModel.daysSummary(model.activeDays, l10n))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            if model.activeDays.count == 1 {
                Text(l10n.bedtimeDaysHint).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            Toggle(isOn: Binding(get: { model.isWindDownOn }, set: { model.setWindDown(on: $0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(l10n.bedtimeWindDownTitle).nozirText(.body)
                    Text(model.isWindDownOn ? l10n.bedtimeWindDownSubtitle(model.windDownMinutes) : l10n.bedtimeWindDownOff)
                        .nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            .tint(NozirColor.primary)
            if model.isWindDownOn {
                // Android `RuleMinuteRange.WIND_DOWN`: 15…60 in steps of 15.
                Slider(
                    value: Binding(get: { Double(model.windDownMinutes) }, set: { model.setWindDownMinutes(Int($0.rounded())) }),
                    in: Durations.range(15...60, including: model.windDownMinutes),
                    step: 15
                )
                .tint(NozirColor.primary)
                .accessibilityLabel(l10n.bedtimeWindDownSlider)
            }
        }
    }

    private func timePicker(_ title: String, _ time: Binding<ClockTime>) -> some View {
        VStack(alignment: .leading, spacing: NozirSpacing.extraSmall) {
            Text(title).nozirText(.bodySmall, color: NozirColor.textSecondary)
            DatePicker(
                title,
                selection: Binding(get: { time.wrappedValue.date() }, set: { time.wrappedValue = ClockTime(date: $0) }),
                displayedComponents: .hourAndMinute
            )
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dayChip(_ day: Int) -> some View {
        let isOn = model.activeDays.contains(day)
        return Button {
            model.toggleDay(day)
        } label: {
            Text(l10n.weekdayNamesShort[day - 1])
                .nozirText(.bodySmall, color: isOn ? NozirColor.onPrimary : NozirColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(RoundedRectangle(cornerRadius: NozirRadius.button).fill(isOn ? NozirColor.primary : NozirColor.track))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(l10n.weekdayNames[day - 1])
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Durations.swift NozirKit/Sources/NozirAppFeature/Family/NewChildRulesModel.swift NozirKit/Sources/NozirAppFeature/Screens/NewChildRulesView.swift NozirKit/Tests/NozirAppFeatureTests/NewChildRulesModelTests.swift
```

Xabar: `p03b: the first rules are saved with the child, and never twice`

---
### Task 11: P04 — juftlash (`PairingModel`, `PairingView`)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Family/PairingModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/PairingView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/PairingModelTests.swift`

**Interfaces:**
- Consumes: Task 9 (`FakeFamily`, `makeChild`, `pairingCode`, `offline`), Task 7 (`FamilyStore`, `PairingCode`, `ChildDevice`), Task 8 (`NozirQRCode`, `NozirChecklistRow`, `NozirCard`).
- Produces:
  - `@MainActor @Observable public final class PairingModel { enum Phase: Equatable { case loading, noCode, waiting(PairingCode), paired }; child: Child; phase; connectedDevice: ChildDevice?; isConfirmingReplacement; isBusy; message: UserMessage?; isAppInstalled: Bool; init(child:family:pollInterval:sleep:); run() async; requestNewCode() async; confirmReplacement() async; dismissReplacement() }`
  - `struct PairingView: View { init(model: PairingModel, onFinished: @escaping () -> Void) }`

Xatti-harakat (D1–D4):
- Birinchi qarash: bola juftlangan bo'lsa — qurilmasi o'qiladi (savol uchun). Jonli kod bo'lsa ko'rsatiladi. Kod yo'q (`nil`) bo'lsa: juftlanmagan bolaga darhol yangi kod; juftlangan bolaga "Kod olish" tugmasi.
- So'rov: har 4 s, faqat `.waiting` da. Kod yo'qolsa (`nil`) — `GET /children/{id}`: `PAIRED` → `.paired` (va `FamilyStore` yangilanadi), aks holda `.noCode` (muddati tugagan).
- Tarmoq xatosi so'rovni to'xtatmaydi; matn ko'rinadi, keyingi muvaffaqiyatli javob uni o'chiradi.
- `run()` bekor qilinsa (ekran yopildi yoki ilova faol emas) — darhol qaytadi.
- Juftlangan bolaga yangi kod: avval "qurilma almashtiriladi" savoli, tasdiqdan keyingina `POST`.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/PairingModelTests.swift`:

```swift
import Foundation
import Testing
import NozirFamily
@testable import NozirAppFeature

/// Lets `run()` wait a fixed number of times, then cancels it the way a
/// screen that goes away does.
private actor Ticks {
    private var left: Int

    init(_ count: Int) {
        left = count
    }

    func take() throws {
        guard left > 0 else { throw CancellationError() }
        left -= 1
    }
}

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    child: Child = makeChild("Ali"),
    ticks: Int = 0
) -> (PairingModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(child)
    let counter = Ticks(ticks)
    let model = PairingModel(child: child, family: family, pollInterval: .seconds(4), sleep: { _ in try await counter.take() })
    return (model, fake, family)
}

@MainActor
@Suite struct PairingModelTests {
    @Test func aChildWithoutAPhoneGetsACodeAtOnce() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(nil)]
        script.issueCode = [.success(pairingCode("472918"))]
        let (model, fake, _) = setup(script)

        await model.run()

        #expect(model.phase == .waiting(pairingCode("472918")))
        #expect(await fake.calls == ["currentCode", "issueCode"])
    }

    @Test func aLiveCodeIsShownNotReplaced() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode(state: .appInstalled))]
        let (model, fake, _) = setup(script)

        await model.run()

        #expect(model.isAppInstalled)
        #expect(await fake.calls == ["currentCode"])
    }

    @Test func aPairedChildsPhoneIsReplacedOnlyAfterTheParentSaysSo() async {
        let device = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: true)
        var script = FakeFamily.Script()
        script.devices = [.success([device])]
        script.currentCode = [.success(nil)]
        script.issueCode = [.success(pairingCode("111222"))]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))

        await model.run()
        #expect(model.phase == .noCode)
        #expect(model.connectedDevice == device)

        await model.requestNewCode()
        #expect(model.isConfirmingReplacement)
        #expect(await fake.calls == ["devices", "currentCode"])

        await model.confirmReplacement()
        #expect(model.phase == .waiting(pairingCode("111222")))
        #expect(!model.isConfirmingReplacement)
    }

    @Test func dismissingTheQuestionSendsNothing() async {
        let device = ChildDevice(id: UUID(), manufacturer: "Xiaomi", model: "Redmi Note 12", isOnline: false)
        var script = FakeFamily.Script()
        script.devices = [.success([device])]
        script.currentCode = [.success(nil)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired))
        await model.run()

        await model.requestNewCode()
        model.dismissReplacement()

        #expect(!model.isConfirmingReplacement)
        #expect(await fake.calls == ["devices", "currentCode"])
    }

    // Review Focus 1.
    @Test func aRedeemedCodeIsSeenThroughTheChild() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .success(nil)]
        script.child = [.success(makeChild("Ali", id: ali.id, state: .paired))]
        let (model, _, family) = setup(script, child: ali, ticks: 5)

        await model.run()

        #expect(model.phase == .paired)
        #expect(family.child(ali.id)?.pairingState == .paired)
    }

    @Test func anExpiredCodeOffersANewOne() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .success(nil)]
        script.child = [.success(ali)]
        let (model, _, _) = setup(script, child: ali, ticks: 1)

        await model.run()

        #expect(model.phase == .noCode)
    }

    // Review Focus 3.
    @Test func leavingTheScreenStopsThePolling() async {
        var script = FakeFamily.Script()
        script.currentCode = Array(repeating: .success(pairingCode()), count: 10)
        let (model, fake, _) = setup(script, ticks: 2)

        await model.run()

        #expect(await fake.calls == ["currentCode", "currentCode", "currentCode"])
    }

    @Test func aDroppedConnectionKeepsWaitingAndSaysSo() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .failure(offline)]
        let (model, _, _) = setup(script, ticks: 1)

        await model.run()

        #expect(model.phase == .waiting(pairingCode()))
        #expect(model.message == .noConnection)
    }

    @Test func theNextGoodAnswerClearsTheMessage() async {
        var script = FakeFamily.Script()
        script.currentCode = [.success(pairingCode()), .failure(offline), .success(pairingCode())]
        let (model, _, _) = setup(script, ticks: 2)

        await model.run()

        #expect(model.message == nil)
    }

    @Test func withoutACodeNothingIsPolled() async {
        var script = FakeFamily.Script()
        script.devices = [.success([])]
        script.currentCode = [.success(nil)]
        let (model, fake, _) = setup(script, child: makeChild("Ali", state: .paired), ticks: 3)

        await model.run()

        #expect(model.phase == .noCode)
        #expect(await fake.calls == ["devices", "currentCode"])
    }

    @Test func aFirstLookThatFailsOffersTheButton() async {
        var script = FakeFamily.Script()
        script.currentCode = [.failure(offline)]
        let (model, _, _) = setup(script)

        await model.run()

        #expect(model.phase == .noCode)
        #expect(model.message == .noConnection)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'PairingModel' in scope`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirAppFeature/Family/PairingModel.swift`:

```swift
import Foundation
import Observation
import NozirFamily

/// P04 (Android `PairingViewModel`), with the gap Android has closed: the server
/// stops returning a code once it is redeemed, so a code that disappears is
/// checked against the child before it is called expired.
@MainActor
@Observable
public final class PairingModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case noCode
        case waiting(PairingCode)
        case paired
    }

    public private(set) var child: Child
    public private(set) var phase: Phase = .loading
    /// The phone a new code would retire; read only for a child already paired.
    public private(set) var connectedDevice: ChildDevice?
    public private(set) var isConfirmingReplacement = false
    public private(set) var isBusy = false
    public private(set) var message: UserMessage?

    private let family: FamilyStore
    private let pollInterval: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var hasLooked = false

    public init(
        child: Child,
        family: FamilyStore,
        pollInterval: Duration = .seconds(4),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.child = child
        self.family = family
        self.pollInterval = pollInterval
        self.sleep = sleep
    }

    public var isAppInstalled: Bool {
        switch phase {
        case .waiting(let code): code.state == .appInstalled
        case .paired: true
        case .loading, .noCode: false
        }
    }

    /// Runs while the screen is visible and the app is active; cancelling the
    /// task that runs it (the screen went away, the app left the foreground)
    /// stops it. Only a code that is waiting is asked about.
    public func run() async {
        if hasLooked {
            await refresh()
        } else {
            hasLooked = true
            await firstLook()
        }
        while phase != .paired {
            do {
                try await sleep(pollInterval)
            } catch {
                return
            }
            await refresh()
        }
    }

    /// The "issue a code" button. A child who already has a phone is asked
    /// about first: redeeming a new code retires that phone.
    public func requestNewCode() async {
        guard !isBusy else { return }
        if connectedDevice != nil {
            isConfirmingReplacement = true
            message = nil
            return
        }
        await issue()
    }

    public func confirmReplacement() async {
        isConfirmingReplacement = false
        await issue()
    }

    public func dismissReplacement() {
        isConfirmingReplacement = false
    }

    private func firstLook() async {
        if child.pairingState == .paired {
            connectedDevice = try? await family.service.devices(of: child.id).first
        }
        do {
            if let code = try await family.service.currentPairingCode(for: child.id) {
                await show(code)
            } else if child.pairingState == .paired {
                phase = .noCode
            } else {
                await issue()
            }
        } catch is CancellationError {
            hasLooked = false
        } catch {
            phase = .noCode
            message = UserMessage(error)
        }
    }

    private func refresh() async {
        guard case .waiting = phase else { return }
        do {
            if let code = try await family.service.currentPairingCode(for: child.id) {
                await show(code)
                return
            }
            // The live code is gone: redeemed, or ran out. The child says which.
            let fresh = try await family.service.child(child.id)
            child = fresh
            family.replace(fresh)
            message = nil
            phase = fresh.pairingState == .paired ? .paired : .noCode
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
        }
    }

    private func show(_ code: PairingCode) async {
        message = nil
        guard code.state == .paired else {
            phase = .waiting(code)
            return
        }
        phase = .paired
        if let fresh = try? await family.service.child(child.id) {
            child = fresh
            family.replace(fresh)
        }
    }

    private func issue() async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            phase = .waiting(try await family.service.issuePairingCode(for: child.id))
        } catch is CancellationError {
            return
        } catch {
            message = UserMessage(error)
            if phase == .loading { phase = .noCode }
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/PairingView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P04 as Android `PairingScreen`: the code, the same code as a QR, and what
/// the child's phone has done so far.
struct PairingView: View {
    @State private var model: PairingModel
    private let onFinished: () -> Void
    @Environment(\.l10n) private var l10n
    @Environment(\.scenePhase) private var scenePhase

    init(model: PairingModel, onFinished: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onFinished = onFinished
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                Text(l10n.pairingInstruction).nozirText(.body, color: NozirColor.textSecondary)
                if model.isConfirmingReplacement, let device = model.connectedDevice {
                    replaceCard(device)
                }
                codeCard
                if case .waiting(let code) = model.phase {
                    VStack(spacing: NozirSpacing.small) {
                        NozirQRCode(payload: code.qrContent, accessibilityLabel: l10n.pairingQrContentDescription)
                        Text(l10n.pairingQrHint)
                            .nozirText(.bodySmall, color: NozirColor.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: NozirSpacing.compact) {
                    NozirChecklistRow(l10n.pairingStepAppInstalled, isDone: model.isAppInstalled)
                    NozirChecklistRow(
                        model.phase == .paired ? l10n.pairingStepPaired : l10n.pairingStepWaitingCode,
                        isDone: model.phase == .paired
                    )
                }
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                if model.phase == .paired {
                    NozirButton(l10n.pairingActionOpenHome, size: .callToAction, action: onFinished)
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.pairingTopBar(model.child.displayName))
        .navigationBarTitleDisplayMode(.inline)
        // Restarted when the app comes back to the foreground, cancelled when it
        // leaves or when this screen goes away.
        .task(id: scenePhase == .active) {
            if scenePhase == .active { await model.run() }
        }
    }

    @ViewBuilder
    private var codeCard: some View {
        NozirCard {
            switch model.phase {
            case .loading:
                ProgressView().tint(NozirColor.primary).frame(maxWidth: .infinity)
            case .waiting(let code):
                Text(l10n.pairingCodeLabel).nozirText(.bodySmall, color: NozirColor.textSecondary)
                Text(Self.grouped(code.code))
                    .font(.system(.largeTitle, design: .monospaced).weight(.bold))
                    .foregroundStyle(NozirColor.textPrimary)
                    .accessibilityLabel(code.code.map(String.init).joined(separator: " "))
                Text(l10n.pairingCodeValidity).nozirText(.bodySmall, color: NozirColor.textTertiary)
            case .noCode:
                Text(l10n.pairingNoCodeTitle).nozirText(.titleSmall)
                Text(l10n.pairingNoCodeBody).nozirText(.bodySmall, color: NozirColor.textSecondary)
                NozirButton(l10n.pairingActionIssueCode, isLoading: model.isBusy) {
                    Task { await model.requestNewCode() }
                }
            case .paired:
                Text(l10n.pairingStepPaired).nozirText(.titleSmall, color: NozirColor.goodContent)
            }
        }
    }

    private func replaceCard(_ device: ChildDevice) -> some View {
        NozirCard(tone: .attention) {
            Text(l10n.pairingReplaceTitle).nozirText(.titleSmall)
            Text(device.isOnline ? l10n.pairingReplaceDeviceOnline(device.label) : l10n.pairingReplaceDeviceOffline(device.label))
                .nozirText(.bodySmall, color: NozirColor.textSecondary)
            Text(l10n.pairingReplaceBody).nozirText(.bodySmall)
            HStack(spacing: NozirSpacing.small) {
                NozirButton(l10n.pairingReplaceCancel, variant: .secondary) { model.dismissReplacement() }
                NozirButton(l10n.pairingReplaceConfirm, isLoading: model.isBusy) {
                    Task { await model.confirmReplacement() }
                }
            }
        }
    }

    /// "472918" → "472 918", easier to read out to a child.
    static func grouped(_ code: String) -> String {
        guard code.count == 6 else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Family/PairingModel.swift NozirKit/Sources/NozirAppFeature/Screens/PairingView.swift NozirKit/Tests/NozirAppFeatureTests/PairingModelTests.swift
```

Xabar: `p04: the code, its QR, and a pairing noticed even after the code is gone`

---
### Task 12: Bola tafsilotlari — tahrirlash, o'chirish, faol qilish

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/Family/ChildDetailsModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/ChildDetailsModelTests.swift`

**Interfaces:**
- Consumes: Task 9 (`ChildAge`, `FakeFamily`, `makeChild`), Task 8 (`UzbekPhone`, `AvatarTone`), Task 7 (`Subscription`, `ChildUpdate`).
- Produces:
  - `@MainActor @Observable public final class ChildDetailsModel { enum Removal { case idle, confirming, removing }; child; name; birthYearText; phoneDigits; var avatar; isSaving; wasSaved; message; removal; wasRemoved; isFrozen; isMakingActive; init(child:family:currentYear:); updateName/updateBirthYear/updatePhone; age; showsPhoneError; changes: ChildUpdate; canSave; save() async; askToRemove(); cancelRemove(); confirmRemove() async; loadPlan() async; makeActive() async }`
  - `struct ChildDetailsView: View { init(model: ChildDetailsModel, onRemoved: @escaping () -> Void) }`
  - `func ageGroupName(_ group: AgeGroup, _ l10n: L10n) -> String`

Qoidalar (Android `ChildDetailsViewModel`): faqat o'zgargan maydonlar yuboriladi; bo'shatilgan telefon → `null` (o'chirish); saqlangan yil yosh oralig'idan tashqarida bo'lsa ham o'zgartirilmasa qabul qilinadi; o'chirish sahifa ichidagi tasdiq bilan (D14); obuna noma'lum bo'lsa hech kim muzlatilmaydi; "PRO ga o'tish" tugmasi P19 qurilmaguncha ko'rsatilmaydi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/ChildDetailsModelTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
@testable import NozirAppFeature

@MainActor
private func setup(_ script: FakeFamily.Script = .init(), child: Child) -> (ChildDetailsModel, FakeFamily, FamilyStore) {
    let fake = FakeFamily(script)
    let family = FamilyStore(service: fake)
    family.replace(child)
    return (ChildDetailsModel(child: child, family: family, currentYear: 2026), fake, family)
}

@MainActor
@Suite struct ChildDetailsModelTests {
    @Test func theFormStartsFromTheChildWithNothingToSave() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2015, phone: "+998901234567", avatar: "sky"))

        #expect(model.name == "Ali")
        #expect(model.birthYearText == "2015")
        #expect(model.phoneDigits == "901234567")
        #expect(model.avatar == .sky)
        #expect(model.changes.isEmpty)
        #expect(!model.canSave)
    }

    @Test func onlyWhatChangedIsSentAndTheFormStartsAgainFromTheAnswer() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.update = [.success(makeChild("Alisher", id: ali.id))]
        let (model, fake, family) = setup(script, child: ali)

        model.updateName("Alisher")
        await model.save()

        #expect(await fake.updates == [ChildUpdate(displayName: "Alisher")])
        #expect(model.wasSaved)
        #expect(family.child(ali.id)?.displayName == "Alisher")
        #expect(!model.canSave)
    }

    @Test func emptyingThePhoneRemovesIt() {
        let (model, _, _) = setup(child: makeChild("Ali", phone: "+998901234567"))

        model.updatePhone("")

        #expect(model.changes == ChildUpdate(phone: .cleared))
        #expect(model.canSave)
    }

    @Test func aNewNumberIsSentWhole() {
        let (model, _, _) = setup(child: makeChild("Ali"))

        model.updatePhone("901112233")

        #expect(model.changes.phone == .set("+998901112233"))
    }

    @Test func anUnknownColourIsNotRewrittenBehindTheParentsBack() {
        let (model, _, _) = setup(child: makeChild("Ali", avatar: "violet"))

        #expect(model.avatar == .teal)
        #expect(model.changes.isEmpty)
    }

    @Test func aStoredYearOutsideTheBandDoesNotBlockOtherEdits() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2005))

        model.updateName("Alisher")

        #expect(model.canSave)
    }

    @Test func aNewYearOutsideTheBandCannotBeSaved() {
        let (model, _, _) = setup(child: makeChild("Ali", birthYear: 2015))

        model.updateBirthYear("2021")

        #expect(!model.canSave)
    }

    @Test func removingAsksFirstThenRemoves() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.remove = [.success(())]
        let (model, fake, family) = setup(script, child: ali)

        model.askToRemove()
        #expect(model.removal == .confirming)
        #expect(await fake.calls.isEmpty)

        await model.confirmRemove()

        #expect(model.wasRemoved)
        #expect(family.children.isEmpty)
    }

    @Test func aFailedRemovalAsksAgain() async {
        let (model, _, family) = setup(child: makeChild("Ali"))
        model.askToRemove()

        await model.confirmRemove()

        #expect(!model.wasRemoved)
        #expect(model.removal == .confirming)
        #expect(model.message == .noConnection)
        #expect(family.children.count == 1)
    }

    @Test func aFrozenChildCanBeMadeTheActiveOne() async {
        let ali = makeChild("Ali")
        var script = FakeFamily.Script()
        script.subscription = [.success(Subscription(activeChildId: UUID()))]
        script.activeChild = [.success(Subscription(activeChildId: ali.id))]
        let (model, _, _) = setup(script, child: ali)

        await model.loadPlan()
        #expect(model.isFrozen)

        await model.makeActive()
        #expect(!model.isFrozen)
    }

    @Test func anUnknownPlanFreezesNobody() async {
        let (model, _, _) = setup(child: makeChild("Ali"))

        await model.loadPlan()

        #expect(!model.isFrozen)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'ChildDetailsModel' in scope`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirAppFeature/Family/ChildDetailsModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// The child details screen (Android `ChildDetailsViewModel`): the P03 form,
/// pre-filled, sending only what changed; removal; the frozen-child lock.
@MainActor
@Observable
public final class ChildDetailsModel {
    public enum Removal: Equatable, Sendable {
        case idle, confirming, removing
    }

    public private(set) var child: Child
    public private(set) var name = ""
    public private(set) var birthYearText = ""
    public private(set) var phoneDigits = ""
    public var avatar: AvatarTone = .teal
    public private(set) var isSaving = false
    public private(set) var wasSaved = false
    public private(set) var message: UserMessage?
    public private(set) var removal: Removal = .idle
    public private(set) var wasRemoved = false
    public private(set) var isFrozen = false
    public private(set) var isMakingActive = false

    private let family: FamilyStore
    private let currentYear: Int

    public init(child: Child, family: FamilyStore, currentYear: Int = Calendar.current.component(.year, from: Date())) {
        self.child = child
        self.family = family
        self.currentYear = currentYear
        load(child)
    }

    private func load(_ child: Child) {
        self.child = child
        name = child.displayName
        birthYearText = String(child.birthYear)
        phoneDigits = UzbekPhone.digits(fromE164: child.phoneE164)
        avatar = AvatarTone.forKey(child.avatarKey)
    }

    public func updateName(_ input: String) {
        name = ChildAge.name(from: input)
        wasSaved = false
    }

    public func updateBirthYear(_ input: String) {
        birthYearText = ChildAge.yearDigits(from: input)
        wasSaved = false
    }

    public func updatePhone(_ input: String) {
        phoneDigits = UzbekPhone.digits(from: input)
        wasSaved = false
    }

    public var age: Int? {
        ChildAge.of(birthYearText: birthYearText, currentYear: currentYear)
    }

    /// The stored year stands even outside the bands; a new one must be inside.
    private var isYearAcceptable: Bool {
        birthYearText == String(child.birthYear) || age != nil
    }

    public var showsPhoneError: Bool {
        !phoneDigits.isEmpty && phoneDigits.count != UzbekPhone.subscriberDigits
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var changes: ChildUpdate {
        var update = ChildUpdate()
        if trimmedName != child.displayName { update.displayName = trimmedName }
        if let year = Int(birthYearText), year != child.birthYear { update.birthYear = year }
        if avatar != AvatarTone.forKey(child.avatarKey) { update.avatarKey = avatar.rawValue }
        if phoneDigits != UzbekPhone.digits(fromE164: child.phoneE164) {
            if phoneDigits.isEmpty {
                update.phone = .cleared
            } else if let number = UzbekPhone.e164(phoneDigits) {
                update.phone = .set(number)
            }
        }
        return update
    }

    public var canSave: Bool {
        !isSaving && !trimmedName.isEmpty && isYearAcceptable && !showsPhoneError && !changes.isEmpty
    }

    public func save() async {
        guard canSave else { return }
        isSaving = true
        message = nil
        defer { isSaving = false }
        do {
            let updated = try await family.service.updateChild(child.id, changes)
            family.replace(updated)
            load(updated)
            wasSaved = true
        } catch {
            message = UserMessage(error)
        }
    }

    public func askToRemove() {
        removal = .confirming
        message = nil
    }

    public func cancelRemove() {
        removal = .idle
    }

    public func confirmRemove() async {
        guard removal == .confirming else { return }
        removal = .removing
        do {
            try await family.service.removeChild(child.id)
            family.remove(child.id)
            wasRemoved = true
        } catch {
            removal = .confirming
            message = UserMessage(error)
        }
    }

    /// An unknown plan freezes nobody (Android `FamilyPlan.Unknown`).
    public func loadPlan() async {
        guard let subscription = try? await family.service.subscription() else { return }
        isFrozen = !subscription.isChildActive(child.id)
    }

    public func makeActive() async {
        guard !isMakingActive else { return }
        isMakingActive = true
        message = nil
        defer { isMakingActive = false }
        do {
            let subscription = try await family.service.chooseActiveChild(child.id)
            isFrozen = !subscription.isChildActive(child.id)
        } catch {
            message = UserMessage(error)
        }
    }
}

func ageGroupName(_ group: AgeGroup, _ l10n: L10n) -> String {
    switch group {
    case .star: l10n.ageGroupStar
    case .explorer: l10n.ageGroupExplorer
    case .independent: l10n.ageGroupIndependent
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// Android `ChildDetailsScreen`: edit, the frozen lock, remove.
struct ChildDetailsView: View {
    @State private var model: ChildDetailsModel
    private let onRemoved: () -> Void
    @Environment(\.l10n) private var l10n

    init(model: ChildDetailsModel, onRemoved: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onRemoved = onRemoved
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                HStack(spacing: NozirSpacing.compact) {
                    NozirAvatar(name: model.name, tone: model.avatar, fallbackInitial: l10n.previewAvatarInitial, size: 56)
                    Text(model.child.displayName).nozirText(.titleLarge)
                }
                if model.isFrozen { frozenCard }
                form
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                if model.wasSaved {
                    Text(l10n.childDetailsSaved).nozirText(.bodySmall, color: NozirColor.goodContent)
                }
                NozirButton(l10n.childDetailsActionSave, size: .callToAction, isLoading: model.isSaving) {
                    Task { await model.save() }
                }
                .disabled(!model.canSave && !model.isSaving)
                removal
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.childDetailsTopBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadPlan() }
        .onChange(of: model.wasRemoved) { _, removed in
            if removed { onRemoved() }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: NozirSpacing.large) {
            NozirTextField(
                l10n.addChildLabelName,
                text: Binding(get: { model.name }, set: { model.updateName($0) }),
                placeholder: l10n.addChildNamePlaceholder
            )
            NozirTextField(
                l10n.addChildLabelBirthYear,
                text: Binding(get: { model.birthYearText }, set: { model.updateBirthYear($0) }),
                placeholder: l10n.addChildBirthYearPlaceholder,
                keyboard: .numberPad
            )
            if let age = model.age {
                NozirCard {
                    // The server's band is shown only for the stored year: a year
                    // being edited has no band until it is saved.
                    if model.birthYearText == String(model.child.birthYear), let group = model.child.ageGroup {
                        Text(l10n.addChildAgeMode(age, ageGroupName(group, l10n))).nozirText(.titleSmall)
                    } else {
                        Text(l10n.addChildAgeYears(age)).nozirText(.titleSmall)
                    }
                    Text(l10n.addChildAgeNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
                }
            }
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                NozirPhoneField(
                    l10n.childDetailsLabelPhone,
                    digits: Binding(get: { model.phoneDigits }, set: { model.updatePhone($0) }),
                    prefix: l10n.phoneFieldPrefix,
                    placeholder: l10n.phoneFieldPlaceholder,
                    error: model.showsPhoneError ? l10n.childDetailsErrorPhone : nil
                )
                Text(l10n.childDetailsPhoneNote).nozirText(.bodySmall, color: NozirColor.textTertiary)
            }
            VStack(alignment: .leading, spacing: NozirSpacing.small) {
                Text(l10n.addChildLabelAvatar).nozirText(.bodySmall, color: NozirColor.textSecondary)
                NozirAvatarPicker(
                    selection: $model.avatar,
                    name: model.name,
                    fallbackInitial: l10n.previewAvatarInitial,
                    accessibilityLabel: l10n.contentDescriptionAvatarChoice
                )
            }
        }
    }

    private var frozenCard: some View {
        NozirCard(tone: .attention) {
            HStack(spacing: NozirSpacing.small) {
                NozirStatusDot(.attention)
                Text(l10n.planLockFrozenBadge).nozirText(.label, color: NozirColor.attentionContent)
            }
            Text(l10n.planLockFrozenChildTitle).nozirText(.titleSmall)
            Text(l10n.planLockFrozenChildBody).nozirText(.bodySmall)
            NozirButton(l10n.planLockChooseActive, variant: .secondary, isLoading: model.isMakingActive) {
                Task { await model.makeActive() }
            }
            Text(l10n.planLockSosNote).nozirText(.bodySmall, color: NozirColor.textSecondary)
        }
    }

    @ViewBuilder
    private var removal: some View {
        switch model.removal {
        case .idle:
            NozirButton(l10n.childDetailsActionRemove, variant: .criticalOutline) { model.askToRemove() }
        case .confirming, .removing:
            NozirCard(tone: .attention) {
                Text(l10n.childDetailsRemoveTitle(model.child.displayName)).nozirText(.titleSmall)
                Text(l10n.childDetailsRemoveBody).nozirText(.bodySmall)
                HStack(spacing: NozirSpacing.small) {
                    NozirButton(l10n.childDetailsRemoveCancel, variant: .secondary) { model.cancelRemove() }
                        .disabled(model.removal == .removing)
                    NozirButton(l10n.childDetailsRemoveConfirm, variant: .criticalOutline, isLoading: model.removal == .removing) {
                        Task { await model.confirmRemove() }
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/Family/ChildDetailsModel.swift NozirKit/Sources/NozirAppFeature/Screens/ChildDetailsView.swift NozirKit/Tests/NozirAppFeatureTests/ChildDetailsModelTests.swift
```

Xabar: `children: edit what changed, remove on purpose, unfreeze one`

---
### Task 13: P21 — profil, tema va til (`ProfileModel`, `LocaleSync`, `ProfileView`)

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/LocaleSync.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/ProfileModelTests.swift`

**Interfaces:**
- Consumes: Task 2 (`LanguageStore`, `AppLanguage`), Task 4 (`AppearanceStore`, `AppearanceMode`), Task 7 (`FamilyStore`, `ParentProfile`), Task 8 (`NozirStatusLevel`, `UzbekPhone`, qatorlar).
- Produces:
  - `@MainActor final class LocaleSync { static let unsentKey = "nozir.appLanguage.unsent"; init(store: LanguageStore, defaults: UserDefaults = .standard, send: @escaping @Sendable (String) async throws -> Void); choose(_:) async; resumeIfNeeded() async }`
  - `@MainActor @Observable public final class ProfileModel { parent: ParentProfile?; message: UserMessage?; isSigningOut; let family; let language; let appearance; init(family:language:appearance:localeSync:currentYear:signOut:); load() async; choose(_ language: AppLanguage) async; choose(_ mode: AppearanceMode); signOut() async; displayName(_ l10n:) -> String; phone: String?; age(of:) -> Int; static func status(of: PairingState, _ l10n:) -> (label: String, level: NozirStatusLevel) }`
  - `struct ProfileView: View { init(model: ProfileModel, onAddChild: @escaping () -> Void, onOpenChild: @escaping (Child) -> Void, onPair: @escaping (Child) -> Void) }`

Til (spec 6.5): tanlov darhol qo'llanadi va saqlanadi; keyin `PATCH /v1/parent/me {locale}`. Yuborilmasa `nozir.appLanguage.unsent` belgisi qoladi va keyingi kirgan holatdagi ishga tushishda qayta yuboriladi. Backenddagi `parent.locale` lokal tanlovni almashtirmaydi (Android ham shunday). Sozlamalarda faqat Ko'rinish va Til; qoidalar/obuna/bildirishnomalar/maxfiylik qatorlari o'z bo'laklarida qo'shiladi.

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/ProfileModelTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

/// Records what reached the server and can refuse it.
private actor LocaleEndpoint {
    private(set) var sent: [String] = []
    private var failures: Int

    init(failing failures: Int = 0) {
        self.failures = failures
    }

    func send(_ locale: String) throws {
        if failures > 0 {
            failures -= 1
            throw offline
        }
        sent.append(locale)
    }
}

private func freshDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ProfileModelTests.\(UUID().uuidString)")!
}

@MainActor
@Suite struct LocaleSyncTests {
    @Test func aChoiceTakesEffectAtOnceAndReachesTheServer() async {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
        let endpoint = LocaleEndpoint()
        let sync = LocaleSync(store: store, defaults: defaults, send: { try await endpoint.send($0) })

        await sync.choose(.ru)

        #expect(store.current == .ru)
        #expect(await endpoint.sent == ["ru"])
        #expect(!defaults.bool(forKey: LocaleSync.unsentKey))
    }

    @Test func aChoiceTheServerMissedIsSentOnTheNextStart() async {
        let defaults = freshDefaults()
        let store = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
        let offlineEndpoint = LocaleEndpoint(failing: 1)
        await LocaleSync(store: store, defaults: defaults, send: { try await offlineEndpoint.send($0) }).choose(.en)
        #expect(defaults.bool(forKey: LocaleSync.unsentKey))

        let endpoint = LocaleEndpoint()
        await LocaleSync(store: store, defaults: defaults, send: { try await endpoint.send($0) }).resumeIfNeeded()

        #expect(await endpoint.sent == ["en"])
        #expect(!defaults.bool(forKey: LocaleSync.unsentKey))
    }

    @Test func nothingUnsentMeansNothingSent() async {
        let defaults = freshDefaults()
        let endpoint = LocaleEndpoint()
        let sync = LocaleSync(store: LanguageStore(defaults: defaults, preferredLanguages: ["uz"]), defaults: defaults, send: { try await endpoint.send($0) })

        await sync.resumeIfNeeded()

        #expect(await endpoint.sent.isEmpty)
    }
}

@MainActor
private func setup(_ script: FakeFamily.Script, signOut: @escaping @MainActor () async -> Void = {}) -> (ProfileModel, FamilyStore, LanguageStore, AppearanceStore) {
    let defaults = freshDefaults()
    let family = FamilyStore(service: FakeFamily(script))
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let appearance = AppearanceStore(defaults: defaults)
    let sync = LocaleSync(store: language, defaults: defaults, send: { _ in })
    let model = ProfileModel(family: family, language: language, appearance: appearance, localeSync: sync, currentYear: 2026, signOut: signOut)
    return (model, family, language, appearance)
}

@MainActor
@Suite struct ProfileModelTests {
    @Test func loadingReadsTheParentAndTheChildren() async {
        var script = FakeFamily.Script()
        script.me = [.success(ParentProfile(displayName: "Zohid", phoneE164: "+998901234567", locale: "uz"))]
        script.children = [.success([makeChild("Ali", birthYear: 2015)])]
        let (model, family, _, _) = setup(script)

        await model.load()

        #expect(model.displayName(L10n(.uz)) == "Zohid")
        #expect(model.phone == "+998 90 123 45 67")
        #expect(family.children.map(\.displayName) == ["Ali"])
        #expect(model.age(of: family.children[0]) == 11)
        #expect(model.message == nil)
    }

    @Test func aParentWithoutANameIsCalledParent() async {
        var script = FakeFamily.Script()
        script.me = [.success(ParentProfile(displayName: "  ", phoneE164: nil, locale: "uz"))]
        let (model, _, _, _) = setup(script)

        await model.load()

        #expect(model.displayName(L10n(.uz)) == L10n(.uz).profileNoName)
        #expect(model.phone == nil)
    }

    @Test func aListThatCannotBeLoadedSaysSo() async {
        let (model, _, _, _) = setup(FakeFamily.Script())

        await model.load()

        #expect(model.message == .noConnection)
    }

    @Test func languageAndThemeAreTheParentsChoice() async {
        let (model, _, language, appearance) = setup(FakeFamily.Script())

        await model.choose(AppLanguage.en)
        model.choose(AppearanceMode.dark)

        #expect(language.current == .en)
        #expect(appearance.mode == .dark)
    }

    @Test func signingOutRunsOnce() async {
        var count = 0
        let (model, _, _, _) = setup(FakeFamily.Script(), signOut: { count += 1 })

        await model.signOut()

        #expect(count == 1)
    }

    @Test func eachPairingStateHasItsLabel() {
        let l10n = L10n(.uz)
        let expected: [(PairingState, String, NozirStatusLevel)] = [
            (.paired, l10n.profileChildStatePaired, .good),
            (.appInstalled, l10n.profileChildStateAppInstalled, .attention),
            (.codeIssued, l10n.profileChildStateCodeIssued, .attention),
            (.notPaired, l10n.profileChildStateNotPaired, .action),
        ]
        for (state, label, level) in expected {
            let status = ProfileModel.status(of: state, l10n)
            #expect(status.label == label)
            #expect(status.level == level)
        }
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'LocaleSync'`, `cannot find 'ProfileModel'`.

- [ ] **Step 3: Implementatsiya**

`NozirKit/Sources/NozirAppFeature/LocaleSync.swift`:

```swift
import Foundation
import NozirL10n

/// The parent's language choice: on screen at once, on the server when it can
/// be (the server writes AI summaries and notifications in it). A choice the
/// server missed is sent again the next time the app starts signed in.
@MainActor
final class LocaleSync {
    static let unsentKey = "nozir.appLanguage.unsent"

    private let store: LanguageStore
    private let defaults: UserDefaults
    private let send: @Sendable (String) async throws -> Void

    init(store: LanguageStore, defaults: UserDefaults = .standard, send: @escaping @Sendable (String) async throws -> Void) {
        self.store = store
        self.defaults = defaults
        self.send = send
    }

    func choose(_ language: AppLanguage) async {
        store.set(language)
        defaults.set(true, forKey: Self.unsentKey)
        await push(language)
    }

    func resumeIfNeeded() async {
        guard defaults.bool(forKey: Self.unsentKey) else { return }
        await push(store.current)
    }

    private func push(_ language: AppLanguage) async {
        do {
            try await send(language.rawValue)
            // A newer choice made meanwhile keeps the mark until it is sent too.
            if store.current == language {
                defaults.removeObject(forKey: Self.unsentKey)
            }
        } catch {
            // Kept for the next start; the screen already speaks the new language.
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P21 (Android `ProfileViewModel`): the parent, the children with their
/// pairing state, theme, language, sign-out.
@MainActor
@Observable
public final class ProfileModel {
    public private(set) var parent: ParentProfile?
    public private(set) var message: UserMessage?
    public private(set) var isSigningOut = false
    public let family: FamilyStore
    public let language: LanguageStore
    public let appearance: AppearanceStore

    private let localeSync: LocaleSync
    private let currentYear: Int
    private let signOutAction: @MainActor () async -> Void

    init(
        family: FamilyStore,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        currentYear: Int = Calendar.current.component(.year, from: Date()),
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        self.currentYear = currentYear
        signOutAction = signOut
    }

    public func load() async {
        message = nil
        if let me = try? await family.service.me() {
            parent = me
        }
        do {
            try await family.refresh()
        } catch {
            message = UserMessage(error)
        }
    }

    public func choose(_ language: AppLanguage) async {
        await localeSync.choose(language)
    }

    public func choose(_ mode: AppearanceMode) {
        appearance.set(mode)
    }

    public func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await signOutAction()
    }

    public func displayName(_ l10n: L10n) -> String {
        let name = parent?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? l10n.profileNoName : name
    }

    public var phone: String? {
        parent?.phoneE164.map(UzbekPhone.display)
    }

    /// Android `profile_child_name_and_age`: this year minus the birth year.
    public func age(of child: Child) -> Int {
        currentYear - child.birthYear
    }

    /// Android `ProfileChildStatus`.
    public static func status(of state: PairingState, _ l10n: L10n) -> (label: String, level: NozirStatusLevel) {
        switch state {
        case .paired: (l10n.profileChildStatePaired, .good)
        case .appInstalled: (l10n.profileChildStateAppInstalled, .attention)
        case .codeIssued: (l10n.profileChildStateCodeIssued, .attention)
        case .notPaired: (l10n.profileChildStateNotPaired, .action)
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P21 as Android `ProfileScreen`, with only the rows whose screens exist.
struct ProfileView: View {
    @State private var model: ProfileModel
    private let onAddChild: () -> Void
    private let onOpenChild: (Child) -> Void
    private let onPair: (Child) -> Void
    @Environment(\.l10n) private var l10n
    @State private var showsTheme = false
    @State private var showsLanguage = false

    init(
        model: ProfileModel,
        onAddChild: @escaping () -> Void,
        onOpenChild: @escaping (Child) -> Void,
        onPair: @escaping (Child) -> Void
    ) {
        _model = State(initialValue: model)
        self.onAddChild = onAddChild
        self.onOpenChild = onOpenChild
        self.onPair = onPair
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NozirSpacing.large) {
                parentCard
                if let message = model.message {
                    NozirInlineMessage(message.text(l10n))
                }
                NozirSectionTitle(l10n.profileSectionChildren)
                NozirCard {
                    ForEach(Array(model.family.children.enumerated()), id: \.element.id) { position, child in
                        childRow(child, position: position)
                        Divider()
                    }
                    Button(action: onAddChild) {
                        Text(l10n.profileAddChild)
                            .nozirText(.titleSmall, color: NozirColor.primaryAccent)
                            .frame(maxWidth: .infinity, minHeight: NozirSize.control, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                NozirSectionTitle(l10n.profileSectionSettings)
                NozirCard {
                    NozirSettingsRow(l10n.profileRowTheme, value: themeLabel(model.appearance.mode)) { showsTheme = true }
                    Divider()
                    NozirSettingsRow(l10n.profileRowLanguage, value: languageLabel(model.language.current)) { showsLanguage = true }
                }
                NozirButton(l10n.profileActionSignOut, variant: .criticalOutline, isLoading: model.isSigningOut) {
                    Task { await model.signOut() }
                }
            }
            .padding(NozirSpacing.medium)
        }
        .background(NozirColor.background.ignoresSafeArea())
        .navigationTitle(l10n.screenProfileTitle)
        .task { await model.load() }
        .refreshable { await model.load() }
        .confirmationDialog(l10n.themeSheetTitle, isPresented: $showsTheme, titleVisibility: .visible) {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Button(themeLabel(mode)) { model.choose(mode) }
            }
        }
        .confirmationDialog(l10n.languageSheetTitle, isPresented: $showsLanguage, titleVisibility: .visible) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Button(languageLabel(language)) {
                    Task { await model.choose(language) }
                }
            }
        }
    }

    private var parentCard: some View {
        NozirCard {
            HStack(spacing: NozirSpacing.compact) {
                NozirAvatar(name: model.displayName(l10n), tone: .teal, fallbackInitial: l10n.previewAvatarInitial, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName(l10n)).nozirText(.titleSmall)
                    if let phone = model.phone {
                        Text(phone).nozirText(.bodySmall, color: NozirColor.textSecondary)
                    }
                }
            }
        }
    }

    private func childRow(_ child: Child, position: Int) -> some View {
        let status = ProfileModel.status(of: child.pairingState, l10n)
        return HStack(spacing: NozirSpacing.compact) {
            Button {
                onOpenChild(child)
            } label: {
                HStack(spacing: NozirSpacing.compact) {
                    NozirAvatar(
                        name: child.displayName,
                        tone: .forKey(child.avatarKey, position: position),
                        fallbackInitial: l10n.previewAvatarInitial
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(l10n.profileChildNameAndAge(child.displayName, model.age(of: child))).nozirText(.body)
                        HStack(spacing: NozirSpacing.extraSmall) {
                            NozirStatusDot(status.level)
                            Text(status.label).nozirText(.bodySmall, color: NozirColor.textSecondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(l10n.contentDescriptionChildDetails)
            Button(child.pairingState == .paired ? l10n.profileActionRepair : l10n.profileActionPair) {
                onPair(child)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(NozirColor.primaryAccent)
        }
        .padding(.vertical, NozirSpacing.extraSmall)
    }

    private func themeLabel(_ mode: AppearanceMode) -> String {
        switch mode {
        case .light: l10n.profileThemeLight
        case .dark: l10n.profileThemeDark
        case .system: l10n.profileThemeSystem
        }
    }

    private func languageLabel(_ language: AppLanguage) -> String {
        switch language {
        case .uz: l10n.languageUz
        case .ru: l10n.languageRu
        case .en: l10n.languageEn
        }
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/LocaleSync.swift NozirKit/Sources/NozirAppFeature/Family/ProfileModel.swift NozirKit/Sources/NozirAppFeature/Screens/ProfileView.swift NozirKit/Tests/NozirAppFeatureTests/ProfileModelTests.swift
```

Xabar: `p21: the family, the theme and the language, from one screen`

---
### Task 14: Kirgan holat — tab paneli, birinchi bola oqimi, ulanish

**Files:**
- Create: `NozirKit/Sources/NozirAppFeature/SignedInModel.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`
- Create: `NozirKit/Sources/NozirAppFeature/Screens/AddChildFlow.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/AppEnvironment.swift`
- Modify: `NozirKit/Sources/NozirAppFeature/RootView.swift`
- Test: `NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`

**Interfaces:**
- Consumes: Task 9–13 modellari va view'lari, Task 7 (`FamilyApi`, `FamilyStore`), Task 13 (`LocaleSync`).
- Produces:
  - `@MainActor @Observable public final class SignedInModel { enum Tab { case home, profile }; var tab; var isAddingChild; let family; init(family:language:appearance:localeSync:signOut:); start() async; presentAddChild(); finishAddChild(); make…Model(…) }`
  - `struct SignedInView: View { init(model: SignedInModel) }`, `struct AddChildFlow: View { init(model: SignedInModel, onClose: @escaping () -> Void) }`
  - `AppEnvironment.makeSignedInModel() -> SignedInModel`

Yo'naltirish (spec 5.4): kirgandan keyin `GET /children`; bo'sh bo'lsa P03 → P03b → P04 to'liq ekranli oqim sifatida ochiladi (orqaga qaytib bo'lmaydigan P04 bilan); ro'yxat yuklanmasa oqim ochilmaydi (keyingi ochilishda qayta so'raladi). Profile → "Bola qo'shish" — shu oqim; bola qatori → tafsilotlar; "Bog'lash"/"Qayta bog'lash" → P04 (Profile stack'ida).

- [ ] **Step 1: Failing testlarni yozish**

`NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift`:

```swift
import Foundation
import Testing
import NozirDesignSystem
import NozirFamily
import NozirL10n
@testable import NozirAppFeature

private actor SentLocales {
    private(set) var values: [String] = []

    func record(_ locale: String) {
        values.append(locale)
    }
}

@MainActor
private func setup(
    _ script: FakeFamily.Script,
    defaults: UserDefaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!,
    sent: SentLocales = SentLocales()
) -> (SignedInModel, FakeFamily) {
    let fake = FakeFamily(script)
    let language = LanguageStore(defaults: defaults, preferredLanguages: ["uz"])
    let model = SignedInModel(
        family: FamilyStore(service: fake),
        language: language,
        appearance: AppearanceStore(defaults: defaults),
        localeSync: LocaleSync(store: language, defaults: defaults, send: { await sent.record($0) }),
        signOut: {}
    )
    return (model, fake)
}

@MainActor
@Suite struct SignedInModelTests {
    @Test func anEmptyFamilyGoesStraightToAddingAChild() async {
        var script = FakeFamily.Script()
        script.children = [.success([])]
        let (model, _) = setup(script)

        await model.start()

        #expect(model.isAddingChild)
    }

    @Test func aFamilyWithChildrenStaysHome() async {
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, _) = setup(script)

        await model.start()

        #expect(!model.isAddingChild)
        #expect(model.tab == .home)
    }

    @Test func aListThatCannotBeLoadedDoesNotTrapTheParentAndIsAskedAgain() async {
        var script = FakeFamily.Script()
        script.children = [.failure(offline), .success([])]
        let (model, _) = setup(script)

        await model.start()
        #expect(!model.isAddingChild)

        await model.start()
        #expect(model.isAddingChild)
    }

    @Test func startingTwiceAsksOnce() async {
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, fake) = setup(script)

        await model.start()
        await model.start()

        #expect(await fake.calls == ["children"])
    }

    @Test func aLanguageTheServerMissedIsSentOnStart() async {
        let defaults = UserDefaults(suiteName: "SignedInModelTests.\(UUID().uuidString)")!
        defaults.set("ru", forKey: "nozir.appLanguage")
        defaults.set(true, forKey: LocaleSync.unsentKey)
        let sent = SentLocales()
        var script = FakeFamily.Script()
        script.children = [.success([makeChild("Ali")])]
        let (model, _) = setup(script, defaults: defaults, sent: sent)

        await model.start()

        #expect(await sent.values == ["ru"])
    }

    @Test func theAddFlowOpensAndCloses() {
        let (model, _) = setup(FakeFamily.Script())

        model.presentAddChild()
        #expect(model.isAddingChild)
        model.finishAddChild()
        #expect(!model.isAddingChild)
    }
}
```

- [ ] **Step 2: Testni ishga tushirish (FAIL kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: FAIL — `cannot find 'SignedInModel' in scope`.

- [ ] **Step 3: Model**

`NozirKit/Sources/NozirAppFeature/SignedInModel.swift`:

```swift
import Foundation
import Observation
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// Everything the signed-in app shares for one session: the family, the tab,
/// and whether the add-a-child flow is up. A new sign-in gets a new one, so a
/// signed-out parent's children never linger in memory.
@MainActor
@Observable
public final class SignedInModel {
    public enum Tab: Hashable, Sendable {
        case home, profile
    }

    public var tab: Tab = .home
    public var isAddingChild = false
    public let family: FamilyStore

    private let language: LanguageStore
    private let appearance: AppearanceStore
    private let localeSync: LocaleSync
    private let signOutAction: @MainActor () async -> Void
    @ObservationIgnored private var hasStarted = false

    init(
        family: FamilyStore,
        language: LanguageStore,
        appearance: AppearanceStore,
        localeSync: LocaleSync,
        signOut: @escaping @MainActor () async -> Void
    ) {
        self.family = family
        self.language = language
        self.appearance = appearance
        self.localeSync = localeSync
        signOutAction = signOut
    }

    /// After sign-in: a family with no children goes straight to adding one
    /// (on iOS `isNewAccount` is always false, so the list decides). A list that
    /// cannot be loaded opens nothing and is asked for again next time.
    public func start() async {
        guard !hasStarted else { return }
        hasStarted = true
        await localeSync.resumeIfNeeded()
        do {
            try await family.refresh()
            if family.children.isEmpty {
                isAddingChild = true
            }
        } catch {
            hasStarted = false
        }
    }

    public func presentAddChild() {
        isAddingChild = true
    }

    public func finishAddChild() {
        isAddingChild = false
    }

    func makeProfileModel() -> ProfileModel {
        ProfileModel(family: family, language: language, appearance: appearance, localeSync: localeSync, signOut: signOutAction)
    }

    func makeAddChildModel() -> AddChildModel {
        AddChildModel()
    }

    func makeRulesModel(_ draft: ChildDraft) -> NewChildRulesModel {
        NewChildRulesModel(draft: draft, family: family)
    }

    func makePairingModel(_ child: Child) -> PairingModel {
        PairingModel(child: child, family: family)
    }

    func makeDetailsModel(_ child: Child) -> ChildDetailsModel {
        ChildDetailsModel(child: child, family: family)
    }
}
```

- [ ] **Step 4: Testni ishga tushirish (PASS kutiladi)**

Run: `./scripts/test.sh NozirAppFeatureTests`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Ekranlar va ulanish**

`NozirKit/Sources/NozirAppFeature/Screens/AddChildFlow.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// P03 → P03b → P04, full screen. P04 has no way back: the child exists by then.
struct AddChildFlow: View {
    enum Step: Hashable {
        case rules(ChildDraft)
        case pairing(UUID)
    }

    private let model: SignedInModel
    private let onClose: () -> Void
    @State private var path: [Step] = []
    @State private var addModel: AddChildModel
    @Environment(\.l10n) private var l10n

    init(model: SignedInModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
        _addModel = State(initialValue: model.makeAddChildModel())
    }

    var body: some View {
        NavigationStack(path: $path) {
            AddChildView(model: addModel) { draft in
                path.append(.rules(draft))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(l10n.contentDescriptionBack)
                }
            }
            .navigationDestination(for: Step.self) { step in
                switch step {
                case .rules(let draft):
                    NewChildRulesView(model: model.makeRulesModel(draft)) { child in
                        path.append(.pairing(child.id))
                    }
                case .pairing(let id):
                    if let child = model.family.child(id) {
                        PairingView(model: model.makePairingModel(child), onFinished: onClose)
                            .navigationBarBackButtonHidden()
                    }
                }
            }
        }
    }
}
```

`NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift`:

```swift
import SwiftUI
import NozirDesignSystem
import NozirFamily
import NozirL10n

/// The signed-in app: Home (P05 comes in 2b) and Profile. Statistics and
/// Location tabs arrive with their slices.
struct SignedInView: View {
    enum ProfileStep: Hashable {
        case child(UUID)
        case pairing(UUID)
    }

    @State private var model: SignedInModel
    @State private var profilePath: [ProfileStep] = []
    @Environment(\.l10n) private var l10n
    @Environment(\.locale) private var locale

    init(model: SignedInModel) {
        _model = State(initialValue: model)
    }

    var body: some View {
        TabView(selection: $model.tab) {
            NavigationStack {
                HomePlaceholderView()
            }
            .tabItem { Label(l10n.tabHome, systemImage: "house") }
            .tag(SignedInModel.Tab.home)

            NavigationStack(path: $profilePath) {
                ProfileView(
                    model: model.makeProfileModel(),
                    onAddChild: { model.presentAddChild() },
                    onOpenChild: { profilePath.append(.child($0.id)) },
                    onPair: { profilePath.append(.pairing($0.id)) }
                )
                .navigationDestination(for: ProfileStep.self) { step in
                    switch step {
                    case .child(let id):
                        if let child = model.family.child(id) {
                            ChildDetailsView(model: model.makeDetailsModel(child), onRemoved: { profilePath.removeAll() })
                        }
                    case .pairing(let id):
                        if let child = model.family.child(id) {
                            PairingView(model: model.makePairingModel(child), onFinished: { profilePath.removeAll() })
                        }
                    }
                }
            }
            .tabItem { Label(l10n.tabProfile, systemImage: "person.crop.circle") }
            .tag(SignedInModel.Tab.profile)
        }
        .tint(NozirColor.primary)
        .fullScreenCover(isPresented: $model.isAddingChild) {
            AddChildFlow(model: model, onClose: { model.finishAddChild() })
                // Said again for the cover, so it cannot fall back to the defaults.
                .environment(\.l10n, l10n)
                .environment(\.locale, locale)
        }
        .task { await model.start() }
    }
}
```

`NozirKit/Sources/NozirAppFeature/AppEnvironment.swift` — o'zgarishlar:

1. `import NozirFamily` qo'shing.
2. Xususiyatlarga qo'shing: `private let authorised: ApiClient`
3. `init` ga `authorised: ApiClient` parametrini qo'shing (`telegramSignIn` dan oldin) va `self.authorised = authorised`.
4. `live(…)` ichida `let authorisedAuth = AuthApi(client: anonymous.withTokens(refresher))` qatorini quyidagiga almashtiring:

```swift
        let authorised = anonymous.withTokens(refresher)
        let authorisedAuth = AuthApi(client: authorised)
```

va `return AppEnvironment(` chaqiruviga `authorised: authorised,` ni (`appearance:` dan keyin) qo'shing.
5. `makeSignInModel()` dan keyin:

```swift
    func makeSignedInModel() -> SignedInModel {
        let api = FamilyApi(client: authorised)
        return SignedInModel(
            family: FamilyStore(service: api),
            language: language,
            appearance: appearance,
            localeSync: LocaleSync(store: language, send: { _ = try await api.updateLocale($0) }),
            signOut: { [appModel] in await appModel.signOut() }
        )
    }
```

`NozirKit/Sources/NozirAppFeature/RootView.swift` — `content` ichidagi `.signedIn` holati:

```swift
        case .signedIn:
            SignedInView(model: environment.makeSignedInModel())
```

`HomePlaceholderView` endi chiqish tugmasisiz chaqiriladi (`onSignOut` ixtiyoriy, `nil`): fayl o'zgarmaydi.

- [ ] **Step 6: Butun to'plam va ilova build'i**

Run: `./scripts/test.sh` va watcher `app` (yoki `xcodebuild build -project Nozir.xcodeproj -scheme Nozir -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`).
Expected: barcha testlar o'tadi; `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git status --short
git add NozirKit/Sources/NozirAppFeature/SignedInModel.swift NozirKit/Sources/NozirAppFeature/Screens/SignedInView.swift NozirKit/Sources/NozirAppFeature/Screens/AddChildFlow.swift NozirKit/Sources/NozirAppFeature/AppEnvironment.swift NozirKit/Sources/NozirAppFeature/RootView.swift NozirKit/Tests/NozirAppFeatureTests/SignedInModelTests.swift
```

Xabar: `app: tabs, and a new family lands on adding its first child`

---
### Task 15: Oxirgi tekshiruv — butun to'plam, CI va simulyatorda E2E

**Files:** (kod o'zgarmaydi; topilgan xatolar alohida TDD sikli bilan tuzatiladi)

- [ ] **Step 1: Butun to'plam**

Run: `python3 -m unittest discover -s scripts/tests && python3 scripts/gen_l10n.py --check && ./scripts/test.sh` va watcher `app`.
Expected: Python testlari OK, `up to date`, `** TEST SUCCEEDED **`, `** BUILD SUCCEEDED **`.

- [ ] **Step 2: E2E (foydalanuvchi, simulyator + haqiqiy bola telefoni)**

Har bir bandga "ha" yoki kuzatilgan holat yoziladi:

1. Bolasi yo'q ota-ona Telegram orqali kiradi → P03 o'zi ochiladi.
2. P03: ism bo'sh yoki yil 2020 (6 yosh) → "Davom etish" o'chiq; yil 2015 → "11 yosh" kartasi; telefon "90 12" → xato matni; to'liq raqam → xato yo'qoladi; avatar rangi tanlanadi.
3. P03b: 2 soat / 3 soat, 22:00–07:00, "Har kuni" ko'rinadi; qiymatlar o'zgartiriladi → "Saqlash va davom etish" → P04.
4. P04: 6 xonali kod va QR. Bola Android telefonida Nozir bola ilovasi o'rnatilib kod kiritiladi → ~4 s ichida "Juftlandi" → "Bosh ekranga o'tish" → Home.
5. Profil: bola "Bogʻlangan" holatida; ota-ona ismi/raqami ko'rinadi.
6. Ko'rinish: Yorug' → Tungi → Avto — har biri darhol qo'llanadi; Avto dan keyin telefonning tizim temasi almashtirilsa ilova ham almashadi; ilova qayta ochilganda tanlov saqlangan.
7. Til: O'zbekcha → Русский → English — tab nomlari, profil, P03/P03b/P04, xato matnlari darhol almashadi; vaqt tanlagich ham shu tilda; qayta ochishda saqlangan. Backend'da `parent.locale` yangilangan (ixtiyoriy: `GET /v1/parent/me`).
8. Bola tafsilotlari: ismni o'zgartirish → "Saqlandi"; telefonni o'chirish → saqlanadi; "Bolani o'chirish" → tasdiq kartasi → "Bekor qilish" hech narsa qilmaydi → "Ha, o'chirilsin" → Profilga qaytadi, bola yo'q.
9. Bepul rejada ikkinchi bola qo'shish → P03b da "Bepul rejada bitta bola qoʻshiladi…" matni (bola yaratilmaydi).
10. P04 ochiq turganda ilova fonga o'tkaziladi va 10 s dan keyin qaytariladi → so'rov davom etadi (kod yangilanadi yoki "Juftlandi" ko'rinadi).
11. Juftlangan bola uchun Profil → "Qayta bogʻlash" → "Kod olish" → "qurilma allaqachon ulangan" kartasi → "Bekor qilish" kod chiqarmaydi.
12. Uch tilda va ikki temada P03, P03b, P04, P21 skrinshotlari (Cmd+S) olinadi.

- [ ] **Step 3: Natijani yozish**

Ledger'ga (`.superpowers/sdd/<plan>/progress.md`) E2E natijalari va kechiktirilgan kichik masalalar yoziladi. Push foydalanuvchida; keyin `superpowers:finishing-a-development-branch`.
