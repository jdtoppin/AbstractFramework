# AbstractFramework Media

This optional addon supplies the three large multilingual font files previously
included in AbstractFramework. It contains `Noto_AP`, `Noto_Dolphin`, and
`Unifont`, using their existing LibSharedMedia names. The small Latin-only
`Dolphin` and `Accidental Presidency` fonts remain in AbstractFramework.

The Noto variants combine Simplified Chinese Noto Sans CJK with Latin glyphs.
They are font choices, not separate language translations. English and Chinese
localization text remains in the core addons.

Install the `AbstractFramework_Media` folder alongside `AbstractFramework` and
`BFInfinite` in `Interface/AddOns`, then reload the UI. AbstractFramework is
required. BFInfinite declares this pack as an optional dependency so its fonts
are registered before BFInfinite applies saved settings.

Without the pack, AbstractFramework resolves saved `Noto_AP`, `Noto_Dolphin`,
and `Unifont` selections to the original client UI font. It also recognizes the
old AbstractFramework file paths and new media-pack file paths. Saved choices
are preserved and resolve to the chosen font again after reinstalling or
reenabling the pack and reloading. Other addons that store raw font paths or
call LibSharedMedia directly must implement their own fallback.

The pack has no SavedVariables, event frames, or polling. It registers its
fonts once during addon load. Disabling it takes effect after a UI reload.

## Font sources and licenses

The font files are relocated byte-for-byte from AbstractFramework r43, commit
`7748b2cabf566e2e0646f6829f9d9d473f39b3a5`. This change does not rebuild or
modify any font. The archive's adjacent provenance manifest records their
checksums.

`LICENSES/NotoSansCJKsc_OFL.txt` preserves the existing Noto font notice and
SIL Open Font License. `LICENSES/source.txt` preserves the existing Unifont
source reference. `LICENSES/Unifont-OFL.txt` includes Unifont's embedded
copyright, version and dual-license notice, with the full SIL Open Font
License text. The root `LICENSE` covers the addon's first-party code; the
font licenses remain independent.
