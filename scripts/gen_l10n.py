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
