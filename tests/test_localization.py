#!/usr/bin/env python3
import json
import pathlib
import re
import shutil
import subprocess
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "Shuttle"
TRANSLATED_LANGUAGES = ["es", "fr", "zh-Hans"]
LOCALIZED_STRING_RE = re.compile(r'NSLocalizedString\(@"((?:[^"\\]|\\.)*)"')


def localized_keys_in_sources():
    keys = set()
    for source in SOURCE_DIR.glob("*.m"):
        for literal in LOCALIZED_STRING_RE.findall(source.read_text(encoding="utf-8")):
            keys.add(literal.replace('\\"', '"').replace("\\\\", "\\"))
    return keys


def load_strings(path):
    output = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)],
                            check=True, capture_output=True, text=True).stdout
    return json.loads(output)


@unittest.skipUnless(shutil.which("plutil"), "reading .strings files requires plutil")
class LocalizationTests(unittest.TestCase):
    def test_every_localized_string_is_translated(self):
        keys = localized_keys_in_sources()
        self.assertTrue(keys, "no NSLocalizedString keys found")

        for language in TRANSLATED_LANGUAGES:
            with self.subTest(language=language):
                strings = load_strings(SOURCE_DIR / (language + ".lproj") / "Localizable.strings")
                self.assertEqual(sorted(keys - strings.keys()), [], "missing translations")
                self.assertEqual(sorted(strings.keys() - keys), [], "translations no longer used by the code")

    def test_translations_keep_format_placeholders(self):
        for language in TRANSLATED_LANGUAGES:
            strings = load_strings(SOURCE_DIR / (language + ".lproj") / "Localizable.strings")
            for key, value in strings.items():
                with self.subTest(language=language, key=key):
                    self.assertEqual(value.count("%@"), key.count("%@"))


if __name__ == "__main__":
    unittest.main()
