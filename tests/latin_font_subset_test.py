#!/usr/bin/env python3
"""Verify the Latin subset's provenance, coverage, geometry and reproducibility."""

from __future__ import annotations

import hashlib
import importlib.util
import io
import sys
import unittest
from pathlib import Path

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location("latin_subset", REPO_ROOT / "scripts/subset-noto-ap.py")
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class LatinFontSubsetTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.source_bytes = BUILDER.SOURCE.read_bytes()
        cls.latin_bytes = BUILDER.OUTPUT.read_bytes()
        cls.source = TTFont(io.BytesIO(cls.source_bytes))
        cls.latin = TTFont(io.BytesIO(cls.latin_bytes))

    @classmethod
    def tearDownClass(cls) -> None:
        cls.source.close()
        cls.latin.close()

    def test_reviewed_source_and_deterministic_generation(self) -> None:
        self.assertEqual(hashlib.sha256(self.source_bytes).hexdigest(), BUILDER.SOURCE_SHA256)
        self.assertEqual(BUILDER.make_subset(self.source_bytes), self.latin_bytes)
        self.assertEqual(BUILDER.make_subset(self.source_bytes), self.latin_bytes)
        with self.assertRaisesRegex(ValueError, "SHA256 differs"):
            BUILDER.make_subset(self.source_bytes + b"changed")

    def test_latin_coverage_preserves_english_and_excludes_cjk(self) -> None:
        actual = set(self.latin.getBestCmap())
        expected = set(self.source.getBestCmap()) & BUILDER.requested_codepoints()
        self.assertEqual(actual, expected)
        self.assertTrue(set(range(0x20, 0x7F)) <= actual)
        for character in "éñö–—‘’“”€£¥":
            with self.subTest(character=character):
                self.assertIn(ord(character), actual)
        for first, last in ((0x2E80, 0x9FFF), (0xAC00, 0xD7AF), (0xF900, 0xFAFF),
                            (0x20000, 0x323AF)):
            self.assertFalse(any(first <= codepoint <= last for codepoint in actual))
        self.assertLess(len(self.latin_bytes), 250_000)

    def test_existing_bfi_control_preview_and_status_symbols_are_retained(self) -> None:
        # ClickCastings controls, NameplatesPreview cast/channel text, and
        # UIWidgets/MythicPlus score changes and completion status use these.
        required = "↑↓→←▲▼•✓○"
        actual = self.latin.getBestCmap()
        for character in required:
            with self.subTest(character=character):
                self.assertIn(ord(character), actual)
        for character in "−∞≠≤≥":
            with self.subTest(mathematical_symbol=character):
                self.assertIn(ord(character), actual)

    def test_every_retained_glyph_keeps_original_geometry_and_spacing(self) -> None:
        source_cmap = self.source.getBestCmap()
        latin_cmap = self.latin.getBestCmap()
        source_glyphs = self.source.getGlyphSet()
        latin_glyphs = self.latin.getGlyphSet()
        glyph_pairs = [(source_cmap[codepoint], name) for codepoint, name in latin_cmap.items()]
        glyph_pairs.append((".notdef", ".notdef"))
        for source_name, latin_name in glyph_pairs:
            with self.subTest(glyph=latin_name):
                source_pen = DecomposingRecordingPen(source_glyphs)
                latin_pen = DecomposingRecordingPen(latin_glyphs)
                source_glyphs[source_name].draw(source_pen)
                latin_glyphs[latin_name].draw(latin_pen)
                self.assertEqual(source_pen.value, latin_pen.value)
                self.assertEqual(self.source["hmtx"][source_name], self.latin["hmtx"][latin_name])
                self.assertEqual(self.source["vmtx"][source_name], self.latin["vmtx"][latin_name])

    def test_global_size_and_baseline_metrics_are_preserved(self) -> None:
        fields = {
            "head": ("unitsPerEm", "xMin", "xMax", "yMin", "yMax", "created", "modified"),
            "hhea": ("ascent", "descent", "lineGap"),
            "vhea": ("ascent", "descent", "lineGap"),
            "OS/2": ("sTypoAscender", "sTypoDescender", "sTypoLineGap", "usWinAscent",
                     "usWinDescent", "sCapHeight", "sxHeight", "fsSelection"),
        }
        for table, attributes in fields.items():
            for attribute in attributes:
                with self.subTest(table=table, attribute=attribute):
                    self.assertEqual(getattr(self.source[table], attribute),
                                     getattr(self.latin[table], attribute))

    def test_font_has_distinct_names_and_preserves_copyright_and_license(self) -> None:
        self.assertEqual(self.latin["name"].getDebugName(1), "Noto AP Latin")
        self.assertEqual(self.latin["name"].getDebugName(6), "NotoAPLatin-Bold")
        for name_id in (0, 13, 14):
            self.assertEqual(self.source["name"].getDebugName(name_id),
                             self.latin["name"].getDebugName(name_id))
        notice = (REPO_ROOT / "Media/Fonts/NotoSansCJKsc_AP_Latin-OFL.txt").read_text(encoding="utf-8")
        original = (REPO_ROOT / "OptionalMedia/AbstractFramework_Media/LICENSES/NotoSansCJKsc_OFL.txt").read_text(encoding="utf-8")
        self.assertIn(original, notice)
        self.assertIn(BUILDER.SOURCE_SHA256, notice)
        self.assertIn(BUILDER.FONTTOOLS_VERSION, notice)


if __name__ == "__main__":
    unittest.main()
