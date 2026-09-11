#!/usr/bin/env python3
"""Reproduce the small Latin font from the unchanged optional Noto_AP font.

Install the optional build dependency with:
    python3 -m pip install -r .utils/requirements-fonts.txt
Then generate with:
    python3 scripts/subset-noto-ap.py
Or verify the checked-in binary without changing files:
    python3 scripts/subset-noto-ap.py --check

No font tools are required by the addon at runtime or to package its files.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import sys
from pathlib import Path

try:
    import fontTools
    from fontTools import subset
    from fontTools.ttLib import TTFont
except ImportError as error:
    raise SystemExit(
        "Font subsetting requires: python3 -m pip install -r .utils/requirements-fonts.txt"
    ) from error


REPO_ROOT = Path(__file__).resolve().parents[1]
SOURCE = REPO_ROOT / "OptionalMedia/AbstractFramework_Media/Media/Fonts/NotoSansCJKsc_AP.ttf"
OUTPUT = REPO_ROOT / "Media/Fonts/NotoSansCJKsc_AP_Latin.ttf"
FONTTOOLS_VERSION = "4.60.2"
SOURCE_SHA256 = "55fe9ec3c00308f7d04e9a7c8da2093f54a202097dde1b4a718da617e4d82413"
FAMILY = "Noto AP Latin"
POSTSCRIPT_NAME = "NotoAPLatin-Bold"
SUBSET_VERSION = "1.000"

# Preserve practical English/Latin text, punctuation and the symbols used by
# BFI controls (arrows), previews, and Mythic+ status text (triangles/checks).
# Codepoints absent from the pinned source remain absent; no glyphs are invented.
UNICODE_RANGES = (
    (0x0020, 0x007E),  # Printable ASCII.
    (0x00A0, 0x024F),  # Latin-1 Supplement and Latin Extended A/B.
    (0x1E00, 0x1EFF),  # Latin Extended Additional.
    (0x2000, 0x206F),  # General punctuation.
    (0x20A0, 0x20CF),  # Currency symbols.
    (0x2100, 0x214F),  # Letterlike symbols.
    (0x2190, 0x21FF),  # Arrows used by controls and cast previews.
    (0x2200, 0x22FF),  # Mathematical operators and comparison symbols.
    (0x25A0, 0x25FF),  # Geometric shapes, including status circles/triangles.
    (0x2700, 0x27BF),  # Dingbats, including the Mythic+ completion checkmark.
    (0xFFFD, 0xFFFD),  # Replacement character, if the source supplies it.
)


def requested_codepoints() -> set[int]:
    return {codepoint for first, last in UNICODE_RANGES for codepoint in range(first, last + 1)}


def make_subset(source_bytes: bytes) -> bytes:
    if fontTools.__version__ != FONTTOOLS_VERSION:
        raise ValueError(
            f"expected fonttools {FONTTOOLS_VERSION}, found {fontTools.__version__}; "
            "install .utils/requirements-fonts.txt"
        )
    actual_sha256 = hashlib.sha256(source_bytes).hexdigest()
    if actual_sha256 != SOURCE_SHA256:
        raise ValueError(f"Noto_AP source SHA256 differs from the reviewed source: {actual_sha256}")

    # Preserve the hybrid font's exact glyph coordinates, widths, global metrics,
    # hinting and timestamps. Plain Accidental Presidency has different metrics.
    font = TTFont(io.BytesIO(source_bytes), recalcBBoxes=False, recalcTimestamp=False)
    options = subset.Options()
    options.recalc_bounds = False
    options.recalc_timestamp = False
    options.notdef_outline = True
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.name_legacy = True
    options.layout_features = ["*"]
    worker = subset.Subsetter(options=options)
    worker.populate(unicodes=requested_codepoints())
    worker.subset(font)

    # Keep all copyright/license records while distinguishing this derivative
    # from the full font installed by AbstractFramework_Media.
    replacements = {
        1: FAMILY,
        3: f"{POSTSCRIPT_NAME}:Version {SUBSET_VERSION}; AF Latin subset",
        4: f"{FAMILY} Bold",
        5: f"Version {SUBSET_VERSION}; Latin subset of Noto_AP 2.004; fonttools {FONTTOOLS_VERSION}",
        6: POSTSCRIPT_NAME,
        16: FAMILY,
        18: f"{FAMILY} Bold",
        21: FAMILY,
        25: "NotoAPLatin",
    }
    for record in list(font["name"].names):
        if record.nameID in replacements:
            font["name"].setName(
                replacements[record.nameID], record.nameID,
                record.platformID, record.platEncID, record.langID,
            )
    output = io.BytesIO()
    font.save(output, reorderTables=True)
    font.close()
    return output.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify the committed binary without writing")
    args = parser.parse_args()
    try:
        generated = make_subset(SOURCE.read_bytes())
        if args.check:
            if OUTPUT.read_bytes() != generated:
                raise ValueError("Latin font differs; regenerate with python3 scripts/subset-noto-ap.py")
            print(f"Latin font reproducibility OK: {len(generated):,} bytes")
        else:
            OUTPUT.write_bytes(generated)
            print(f"Generated {OUTPUT.relative_to(REPO_ROOT)} ({len(generated):,} bytes)")
    except (OSError, ValueError) as error:
        print(f"Latin font error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
