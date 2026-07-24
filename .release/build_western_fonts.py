#!/usr/bin/env python3
"""Build the compact Western font variants shipped by AbstractFramework."""

from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables.O_S_2f_2 import intersectUnicodeRanges
from fontTools.unicodedata import script


ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = ROOT / "ExtraMedia" / "Fonts"
OUTPUT_DIR = ROOT / "Media" / "Fonts"
FONT_NAMES = (
    "NotoSansCJKsc_AP.ttf",
    "NotoSansCJKsc_Dolphin.ttf",
    "Unifont.otf",
)
WESTERN_SCRIPTS = {
    "Cyrl",  # Cyrillic
    "Grek",  # Greek
    "Latn",  # Latin
    "Zinh",  # Inherited characters
    "Zyyy",  # Common punctuation and symbols
}


def build_subset(font_name: str) -> None:
    source_path = SOURCE_DIR / font_name
    output_path = OUTPUT_DIR / font_name
    font = TTFont(source_path, recalcTimestamp=False)
    source_cmap = font.getBestCmap()
    unicodes = {codepoint for codepoint in source_cmap if script(codepoint) in WESTERN_SCRIPTS}

    options = subset.Options()
    options.glyph_names = True
    options.layout_features = ["*"]
    options.legacy_cmap = True
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    options.notdef_glyph = True
    options.notdef_outline = True
    options.prune_unicode_ranges = False
    options.recommended_glyphs = True
    options.symbol_cmap = True

    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=unicodes)
    subsetter.subset(font)

    # FontTools currently recognizes one Unicode 16 block beyond the
    # 0-122 range supported by the OpenType OS/2 table implementation.
    unicode_ranges = {bit for bit in intersectUnicodeRanges(unicodes) if bit <= 122}
    font["OS/2"].setUnicodeRanges(unicode_ranges)
    font.save(output_path)

    output_cmap = set(TTFont(output_path).getBestCmap())
    if output_cmap != unicodes:
        raise RuntimeError(f"{font_name}: generated cmap does not match the selected characters")

    print(f"{font_name}: {len(unicodes)} characters, {output_path.stat().st_size} bytes")


def main() -> None:
    for font_name in FONT_NAMES:
        build_subset(font_name)


if __name__ == "__main__":
    main()
