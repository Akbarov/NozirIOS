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
