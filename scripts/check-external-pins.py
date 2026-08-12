#!/usr/bin/env python3
"""Reject floating AbstractFramework package externals."""

from __future__ import annotations

import re
import sys
from pathlib import Path


GIT_SHA = re.compile(r"^[0-9a-f]{40}$")
SVN_PEG = re.compile(r"^https://[^\s]+@[1-9][0-9]*$")


def parse_externals(pkgmeta: Path) -> tuple[dict[str, dict[str, str]], list[str]]:
    externals: dict[str, dict[str, str]] = {}
    errors: list[str] = []
    current: str | None = None
    in_externals = False

    for line_number, raw_line in enumerate(pkgmeta.read_text(encoding="utf-8").splitlines(), 1):
        if raw_line == "externals:":
            in_externals = True
            current = None
            continue
        if in_externals and raw_line and not raw_line[0].isspace():
            break
        if not in_externals or not raw_line.strip() or raw_line.lstrip().startswith("#"):
            continue

        external_match = re.fullmatch(r"  ([^ \t:#][^:]*):(.*)", raw_line)
        if external_match:
            current = external_match.group(1).strip()
            scalar = external_match.group(2).strip()
            if current in externals:
                errors.append(f"{pkgmeta}:{line_number}: duplicate external {current}")
            externals[current] = {}
            if scalar:
                errors.append(
                    f"{pkgmeta}:{line_number}: {current} uses a floating scalar URL; "
                    "use an explicit commit or SVN peg revision"
                )
            continue

        property_match = re.fullmatch(r"    ([a-z-]+):\s*(.*?)\s*", raw_line)
        if property_match and current:
            key, value = property_match.groups()
            if key in externals[current]:
                errors.append(f"{pkgmeta}:{line_number}: duplicate {current}.{key}")
            externals[current][key] = value
            continue

        errors.append(f"{pkgmeta}:{line_number}: unsupported externals syntax: {raw_line!r}")

    if not externals:
        errors.append(f"{pkgmeta}: no externals were found")
    return externals, errors


def validate(pkgmeta: Path) -> list[str]:
    externals, errors = parse_externals(pkgmeta)
    for name, fields in externals.items():
        url = fields.get("url", "")
        external_type = fields.get("type", "git")
        forbidden = sorted(set(fields).intersection({"branch", "tag"}))
        if forbidden:
            errors.append(f"{name}: forbidden floating selector(s): {', '.join(forbidden)}")

        if external_type == "svn":
            unexpected = sorted(set(fields).difference({"url", "type"}))
            if unexpected:
                errors.append(f"{name}: unsupported SVN field(s): {', '.join(unexpected)}")
            if not SVN_PEG.fullmatch(url):
                errors.append(f"{name}: SVN URL must end in an explicit numeric peg revision")
        elif external_type == "git":
            unexpected = sorted(set(fields).difference({"url", "commit"}))
            if unexpected:
                errors.append(f"{name}: unsupported Git field(s): {', '.join(unexpected)}")
            commit = fields.get("commit", "")
            if not GIT_SHA.fullmatch(commit):
                errors.append(f"{name}: Git commit must be a full lowercase 40-character SHA")
            if commit in {"default", "latest"}:
                errors.append(f"{name}: Git commit may not be {commit!r}")
            if not re.fullmatch(r"https://[^\s]+", url):
                errors.append(f"{name}: Git URL must be an explicit HTTPS URL")
        else:
            errors.append(f"{name}: unsupported external type {external_type!r}")

    return errors


def main() -> int:
    if len(sys.argv) > 2:
        print(f"Usage: {Path(sys.argv[0]).name} [.pkgmeta]", file=sys.stderr)
        return 2

    pkgmeta = Path(sys.argv[1] if len(sys.argv) == 2 else ".pkgmeta")
    if not pkgmeta.is_file():
        print(f"External pin check failed: missing {pkgmeta}", file=sys.stderr)
        return 1

    errors = validate(pkgmeta)
    if errors:
        print("External pin check failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        return 1

    externals, _ = parse_externals(pkgmeta)
    print(f"External pin check passed: {len(externals)} immutable revisions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
