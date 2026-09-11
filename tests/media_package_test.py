#!/usr/bin/env python3
"""Release checks for the separately installable optional media package."""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
import tempfile
import unittest
import warnings
import zipfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.dont_write_bytecode = True
SPEC = importlib.util.spec_from_file_location(
    "media_package", REPO_ROOT / "scripts" / "build-media-package.py"
)
BUILDER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BUILDER)


class MediaPackageTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / BUILDER.ADDON
        for name in BUILDER.PACKAGE_FILES:
            path = self.source / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(f"fixture: {name}\n".encode())
        (self.source / f"{BUILDER.ADDON}.toc").write_text(
            "## Interface: 120100\n## Version: r1\n## Dependencies: AbstractFramework\nRegister.lua\n", encoding="utf-8"
        )
        self.output = self.root / "output" / f"{BUILDER.ADDON}-r1.zip"
        self.snapshot = {
            "repository": BUILDER.REPOSITORY,
            "commit": "a" * 40,
            "dirty": True,
            "directory": BUILDER.SOURCE_DIRECTORY.as_posix(),
        }

    def build(self) -> dict:
        return BUILDER.write_package(self.source, self.output, self.snapshot)

    def test_real_source_has_complete_media_and_license_set(self) -> None:
        version, contents = BUILDER.read_source(REPO_ROOT / BUILDER.SOURCE_DIRECTORY)
        self.assertEqual(version, "r1")
        self.assertEqual(
            {name for name in contents if name.endswith((".ttf", ".otf"))},
            {
                "Media/Fonts/NotoSansCJKsc_AP.ttf",
                "Media/Fonts/NotoSansCJKsc_Dolphin.ttf",
                "Media/Fonts/Unifont.otf",
            },
        )
        for name in BUILDER.FONT_FILES:
            self.assertGreater(len(contents[name]), 1_000_000)

    def test_deterministic_archive_preserves_files_and_records_actual_bytes(self) -> None:
        manifest = self.build()
        first_archive = self.output.read_bytes()
        first_manifest = self.output.with_suffix(".zip.provenance.json").read_bytes()
        for path in self.source.rglob("*"):
            os.utime(path, (1_700_000_000, 1_700_000_000))
        self.build()
        self.assertEqual(first_archive, self.output.read_bytes())
        self.assertEqual(first_manifest, self.output.with_suffix(".zip.provenance.json").read_bytes())
        self.assertEqual(manifest["source"], self.snapshot)
        self.assertEqual(manifest["archive"]["sha256"], BUILDER.sha256(first_archive))
        self.assertEqual(manifest["archive"]["bytes"], len(first_archive))
        self.assertEqual(json.loads(first_manifest), manifest)
        self.assertEqual(
            self.output.with_suffix(".zip.sha256").read_text(),
            f"{BUILDER.sha256(first_archive)}  {self.output.name}\n"
            f"{BUILDER.sha256(first_manifest)}  {self.output.with_suffix('.zip.provenance.json').name}\n",
        )
        with zipfile.ZipFile(self.output) as package:
            self.assertEqual(len(package.namelist()), len(BUILDER.PACKAGE_FILES))
            for name in BUILDER.PACKAGE_FILES:
                archive_name = f"{BUILDER.ADDON}/{name}"
                expected = (self.source / name).read_bytes()
                self.assertEqual(package.read(archive_name), expected)
                self.assertEqual(manifest["files"][archive_name], {
                    "bytes": len(expected), "sha256": BUILDER.sha256(expected)
                })
                self.assertEqual(package.getinfo(archive_name).date_time, (1980, 1, 1, 0, 0, 0))

    def test_missing_license_and_unexpected_file_are_rejected(self) -> None:
        license_path = self.source / "LICENSES/Unifont-OFL.txt"
        license_path.unlink()
        with self.assertRaisesRegex(ValueError, "missing=.*Unifont-OFL"):
            self.build()
        license_path.write_text("restored license\n")
        (self.source / "private-settings.txt").write_text("do not package\n")
        with self.assertRaisesRegex(ValueError, "extra=.*private-settings"):
            self.build()
        self.assertFalse(self.output.exists())

    def test_symlink_source_is_rejected(self) -> None:
        font = self.source / "Media/Fonts/Unifont.otf"
        font.unlink()
        font.symlink_to(self.source / "LICENSE")
        with self.assertRaisesRegex(ValueError, "symbolic links"):
            self.build()

    def test_output_cannot_be_inside_media_source(self) -> None:
        with self.assertRaisesRegex(ValueError, "outside"):
            BUILDER.write_package(self.source, self.source / "media.zip", self.snapshot)

    def test_toc_cannot_load_unknown_files(self) -> None:
        (self.source / f"{BUILDER.ADDON}.toc").write_text(
            "## Version: r1\n../AbstractFramework/Init.lua\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(ValueError, "exactly Register.lua"):
            self.build()

    def test_archive_rejects_unexpected_duplicate_and_unsafe_entries(self) -> None:
        _, contents = BUILDER.read_source(self.source)
        for unexpected in (
            "AbstractFramework/Init.lua",
            f"{BUILDER.ADDON}/../outside.lua",
            f"{BUILDER.ADDON}/Register.lua",
        ):
            with self.subTest(unexpected=unexpected):
                self.build()
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore", UserWarning)
                    with zipfile.ZipFile(self.output, "a") as package:
                        package.writestr(unexpected, "extra data")
                with self.assertRaisesRegex(ValueError, "duplicate, missing, or unexpected"):
                    BUILDER.validate_archive(self.output, contents)

    def test_toc_requires_framework_and_eager_registration(self) -> None:
        toc = self.source / f"{BUILDER.ADDON}.toc"
        toc.write_text("## Version: r1\nRegister.lua\n", encoding="utf-8")
        with self.assertRaisesRegex(ValueError, "depend on AbstractFramework"):
            self.build()
        toc.write_text(
            "## Version: r1\n## Dependencies: AbstractFramework\n## LoadOnDemand: 1\nRegister.lua\n",
            encoding="utf-8",
        )
        with self.assertRaisesRegex(ValueError, "normal startup"):
            self.build()

    def test_archive_rejects_symlink_metadata_and_changed_content(self) -> None:
        _, contents = BUILDER.read_source(self.source)
        for mutate_link in (True, False):
            with self.subTest(mutate_link=mutate_link):
                self.build()
                with zipfile.ZipFile(self.output) as package:
                    entries = [(entry, package.read(entry)) for entry in package.infolist()]
                with zipfile.ZipFile(self.output, "w") as package:
                    for entry, data in entries:
                        if entry.filename.endswith("Register.lua"):
                            if mutate_link:
                                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                            else:
                                data += b"changed"
                        package.writestr(entry, data)
                with self.assertRaisesRegex(ValueError, "non-regular|differs from source"):
                    BUILDER.validate_archive(self.output, contents)

    def test_source_commit_assertion_cannot_claim_another_revision(self) -> None:
        actual = BUILDER.source_snapshot(REPO_ROOT, None)
        self.assertRegex(actual["commit"], r"^[0-9a-f]{40}$")
        self.assertIsInstance(actual["dirty"], bool)
        self.assertEqual(BUILDER.source_snapshot(REPO_ROOT, actual["commit"]), actual)
        with self.assertRaisesRegex(ValueError, "does not match HEAD"):
            BUILDER.source_snapshot(REPO_ROOT, "0" * 40)

    def test_core_package_rejects_optional_media_at_any_location(self) -> None:
        archive = self.root / "core.zip"
        for optional in (None, "OptionalMedia/readme.txt", "Media/Fonts/Unifont.otf",
                         "Media/Fonts/NotoSansCJKsc_AP.ttf", "Media/Fonts/NotoSansCJKsc_Dolphin.ttf"):
            with self.subTest(optional=optional):
                with zipfile.ZipFile(archive, "w") as package:
                    for name in ("AbstractFramework.toc", "LICENSE", "README.md",
                                 "Media/Fonts/NotoSansCJKsc_AP_Latin.ttf",
                                 "Media/Fonts/NotoSansCJKsc_AP_Latin-OFL.txt"):
                        package.writestr(f"AbstractFramework/{name}", "# fixture\n")
                    if optional:
                        package.writestr(f"AbstractFramework/{optional}", "optional media")
                result = subprocess.run(
                    [str(REPO_ROOT / "scripts/check-package.sh"), str(archive)],
                    capture_output=True, text=True, check=False,
                )
                if optional:
                    self.assertNotEqual(result.returncode, 0)
                    self.assertRegex(result.stderr, "optional media font|development-only file")
                else:
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_core_package_requires_included_latin_font_and_license(self) -> None:
        archive = self.root / "missing-base-font.zip"
        with zipfile.ZipFile(archive, "w") as package:
            for name in ("AbstractFramework.toc", "LICENSE", "README.md"):
                package.writestr(f"AbstractFramework/{name}", "# fixture\n")
        result = subprocess.run(
            [str(REPO_ROOT / "scripts/check-package.sh"), str(archive)],
            capture_output=True, text=True, check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("required package file is missing: AbstractFramework/Media/Fonts/NotoSansCJKsc_AP_Latin.ttf", result.stderr)
        self.assertIn("required package file is missing: AbstractFramework/Media/Fonts/NotoSansCJKsc_AP_Latin-OFL.txt", result.stderr)


if __name__ == "__main__":
    unittest.main()
