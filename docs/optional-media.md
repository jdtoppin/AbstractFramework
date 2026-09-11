# Optional font package

AbstractFramework core and `AbstractFramework_Media` are separate installable
addons. Core retains its small fonts and all locale text. The optional pack
provides the existing `Noto_AP`, `Noto_Dolphin`, and `Unifont` font choices,
including their bundled license notices. Both Noto files contain CJK glyphs;
the small `Dolphin.ttf` font remains in core.

Install `AbstractFramework_Media/` beside `AbstractFramework/` in the game's
`Interface/AddOns/` directory. The media addon is optional for every client
language. CJK clients can use the game's own font when the pack is absent.
The optional addon README describes font selection and compatibility behavior.

## Build and inspect

From an AbstractFramework checkout:

```sh
python3 scripts/build-media-package.py --output /tmp/AbstractFramework_Media-r1.zip
python3 tests/media_package_test.py
```

The builder uses its own checkout as the source, independently of the caller's
working directory. A consumer such as BFInfinite can call this script from its
pinned AbstractFramework checkout and use an absolute destination path.
`--source-commit <full-sha>` optionally asserts that the source checkout HEAD
matches the consumer's pin; it cannot override the recorded commit.

The builder emits the ZIP, a `.zip.sha256` checksum file covering both the ZIP
and a `.zip.provenance.json` manifest. The manifest records source repository, HEAD,
dirty state, and the SHA-256 and byte length of every packaged file and the
archive itself. Local changes are allowed for testing and explicitly recorded
as dirty; they must not be presented as the contents of an unmodified commit.
Archives use sorted paths, fixed timestamps and permissions, and no build time
metadata, so repeated builds with the same bytes and compression implementation
are identical.

The source file set is deliberately closed: three font binaries, registration
Lua, one TOC, README, and license notices. The builder rejects missing licenses,
extra files, links, malformed TOC entries, and unsafe archives, then checks every
archived byte against the source. The ordinary core package validator remains
restricted to the single `AbstractFramework/` root and rejects optional font
binaries even if copied into another core subdirectory.

## Release behavior

The existing core packaging path continues to embed its normal libraries.
`.pkgmeta` excludes the entire `OptionalMedia/` tree. CI builds the optional
archive into `.release/media/` only after validating core, uploads it as a
separate artifact, and links both artifacts on the PR. GitHub tag releases
attach both archives, the core checksums, and the optional pack's checksum and
provenance. Consumers should install the media archive only when they want the
additional fonts.

The optional pack has its own TOC version (`r1` initially). Increase that version
when changing its installed files; an AF core release does not by itself require
a media version change. There is no second locale-specific core release or
automatic upload of a language variant to another addon distribution project.
Both archives currently use manual installation. Publishing the optional addon
as its own project for addon managers is a separate distribution step.
