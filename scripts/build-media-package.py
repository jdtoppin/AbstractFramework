#!/usr/bin/env python3
"""Build the separately installable optional font addon without external tools."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import subprocess
import sys
import zipfile
from pathlib import Path, PurePosixPath


REPO_ROOT = Path(__file__).resolve().parents[1]
ADDON = "AbstractFramework_Media"
SOURCE_DIRECTORY = Path("OptionalMedia") / ADDON
REPOSITORY = "https://github.com/jdtoppin/AbstractFramework"
FONT_FILES = frozenset({
    "Media/Fonts/NotoSansCJKsc_AP.ttf",
    "Media/Fonts/NotoSansCJKsc_Dolphin.ttf",
    "Media/Fonts/Unifont.otf",
})
PACKAGE_FILES = FONT_FILES | {
    f"{ADDON}.toc",
    "Register.lua",
    "README.md",
    "LICENSE",
    "LICENSES/NotoSansCJKsc_OFL.txt",
    "LICENSES/Unifont-OFL.txt",
    "LICENSES/source.txt",
}


def sha256(contents: bytes) -> str:
    return hashlib.sha256(contents).hexdigest()


def read_source(source: Path) -> tuple[str, dict[str, bytes]]:
    """Reject accidental files and links instead of shipping extra repository data."""
    if source.is_symlink() or not source.is_dir():
        raise ValueError(f"missing or symbolic-link media source directory: {source}")
    paths = {}
    for path in source.rglob("*"):
        if path.is_symlink():
            raise ValueError(f"symbolic links are not allowed in media source: {path}")
        if path.is_dir():
            continue
        relative = path.relative_to(source).as_posix()
        if not stat.S_ISREG(path.stat().st_mode):
            raise ValueError(f"non-regular media source file: {relative}")
        paths[relative] = path
    if set(paths) != PACKAGE_FILES:
        missing = sorted(PACKAGE_FILES - paths.keys())
        extra = sorted(paths.keys() - PACKAGE_FILES)
        raise ValueError(f"media source file set differs: missing={missing}, extra={extra}")

    contents = {name: paths[name].read_bytes() for name in sorted(paths)}
    for name, data in contents.items():
        if not data:
            raise ValueError(f"empty media source file: {name}")
    toc = contents[f"{ADDON}.toc"].decode("utf-8-sig")
    versions = re.findall(r"^## Version:\s*(r[1-9][0-9]*)\s*$", toc, re.MULTILINE)
    if len(versions) != 1:
        raise ValueError("media TOC must contain exactly one literal r<number> version")
    entries = [line.strip() for line in toc.splitlines()
               if line.strip() and not line.lstrip().startswith("#")]
    if entries != ["Register.lua"]:
        raise ValueError("media TOC must load exactly Register.lua")
    dependencies = re.findall(r"^## Dependencies:\s*(.*?)\s*$", toc, re.MULTILINE)
    if dependencies != ["AbstractFramework"]:
        raise ValueError("media TOC must depend on AbstractFramework")
    if re.search(r"^## LoadOnDemand:\s*1\s*$", toc, re.MULTILINE):
        raise ValueError("media addon must register fonts during normal startup")
    return versions[0], contents


def source_snapshot(repository_root: Path, expected_commit: str | None) -> dict:
    def git(*args: str) -> str:
        return subprocess.check_output(
            ["git", "-C", str(repository_root), *args], text=True
        ).strip()

    if Path(git("rev-parse", "--show-toplevel")).resolve() != repository_root.resolve():
        raise ValueError("media builder must run from an AbstractFramework checkout")
    commit = git("rev-parse", "HEAD")
    if not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise ValueError("source HEAD is not a complete Git commit SHA")
    if expected_commit is not None and expected_commit != commit:
        raise ValueError(f"requested source commit {expected_commit} does not match HEAD {commit}")
    return {
        "repository": REPOSITORY,
        "commit": commit,
        "dirty": bool(git("status", "--porcelain=v1", "--untracked-files=all")),
        "directory": SOURCE_DIRECTORY.as_posix(),
    }


def validate_archive(archive: Path, contents: dict[str, bytes]) -> None:
    expected = {f"{ADDON}/{name}": data for name, data in contents.items()}
    with zipfile.ZipFile(archive) as package:
        names = package.namelist()
        if len(names) != len(set(names)) or set(names) != set(expected):
            raise ValueError("media archive contains duplicate, missing, or unexpected entries")
        folded = set()
        for entry in package.infolist():
            name = entry.filename
            path = PurePosixPath(name)
            if ("\\" in name or path.is_absolute() or ".." in path.parts
                    or path.parts[0] != ADDON or name.casefold() in folded):
                raise ValueError(f"unsafe or case-colliding media archive path: {name}")
            folded.add(name.casefold())
            if stat.S_IFMT(entry.external_attr >> 16) != stat.S_IFREG:
                raise ValueError(f"media archive contains a non-regular file: {name}")
            if package.read(entry) != expected[name]:
                raise ValueError(f"media archive content differs from source: {name}")


def write_package(source: Path, output: Path, snapshot: dict) -> dict:
    version, contents = read_source(source)
    if output.suffix != ".zip":
        raise ValueError("output must have a .zip extension")
    if output.resolve().is_relative_to(source.resolve()):
        raise ValueError("output must be outside the optional addon source directory")
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        for name, data in contents.items():
            entry = zipfile.ZipInfo(f"{ADDON}/{name}", date_time=(1980, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = (stat.S_IFREG | 0o644) << 16
            entry.compress_type = zipfile.ZIP_DEFLATED
            package.writestr(entry, data, compresslevel=9)
    validate_archive(output, contents)
    archive_data = output.read_bytes()
    archive_sha = sha256(archive_data)
    provenance = {
        "schema_version": 1,
        "addon": ADDON,
        "version": version,
        "source": snapshot,
        "archive": {"name": output.name, "bytes": len(archive_data), "sha256": archive_sha},
        "files": {
            f"{ADDON}/{name}": {"bytes": len(data), "sha256": sha256(data)}
            for name, data in contents.items()
        },
    }
    provenance_path = output.with_suffix(".zip.provenance.json")
    provenance_bytes = (json.dumps(provenance, indent=2, sort_keys=True) + "\n").encode("utf-8")
    provenance_path.write_bytes(provenance_bytes)
    output.with_suffix(".zip.sha256").write_text(
        f"{archive_sha}  {output.name}\n"
        f"{sha256(provenance_bytes)}  {provenance_path.name}\n", encoding="utf-8"
    )
    return provenance


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True, help="destination .zip path")
    parser.add_argument("--source-commit", help="assert that checkout HEAD matches this full SHA")
    args = parser.parse_args()
    try:
        snapshot = source_snapshot(REPO_ROOT, args.source_commit)
        result = write_package(REPO_ROOT / SOURCE_DIRECTORY, args.output, snapshot)
    except (OSError, ValueError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"media package error: {error}", file=sys.stderr)
        return 1
    print(f"Media package OK: {args.output} ({result['archive']['bytes']} bytes)")
    if snapshot["dirty"]:
        print("Source has local changes; provenance records dirty=true and actual file hashes.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
