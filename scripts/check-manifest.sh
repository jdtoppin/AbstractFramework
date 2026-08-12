#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if (( $# > 1 )); then
    echo "Usage: $0 [packaged-addon-directory]" >&2
    exit 2
fi

target_root="${1:-$repo_root}"
mode="source"
if (( $# == 1 )); then
    mode="package"
fi

command -v python3 >/dev/null 2>&1 || {
    echo "python3 is required to validate the manifest." >&2
    exit 127
}

python3 - "$repo_root" "$target_root" "$mode" <<'PY'
import os
import re
import sys
from pathlib import Path, PurePosixPath
from xml.etree import ElementTree


repository_root = Path(sys.argv[1]).resolve()
addon_root = Path(sys.argv[2]).resolve()
mode = sys.argv[3]
toc_path = addon_root / "AbstractFramework.toc"
errors = []


def normalize_reference(reference):
    normalized = reference.strip().replace("\\", "/")
    path = PurePosixPath(normalized)
    if not normalized or path.is_absolute() or ".." in path.parts:
        return None
    return path


def is_exact_case(path):
    try:
        relative = path.relative_to(addon_root)
    except ValueError:
        return False

    current = addon_root
    for part in relative.parts:
        try:
            entries = os.listdir(current)
        except OSError:
            return False
        if part not in entries:
            return False
        current = current / part
    return True


def find_exact(reference, relative_to=None):
    candidates = []
    if relative_to is not None:
        candidates.append(relative_to / reference)
    candidates.append(addon_root / reference)

    for candidate in candidates:
        candidate = candidate.resolve()
        try:
            candidate.relative_to(addon_root)
        except ValueError:
            continue
        if candidate.is_file() and is_exact_case(candidate):
            return candidate
    return None


def read_external_roots():
    pkgmeta = repository_root / ".pkgmeta"
    roots = []
    in_externals = False
    for raw_line in pkgmeta.read_text(encoding="utf-8").splitlines():
        if raw_line == "externals:":
            in_externals = True
            continue
        if raw_line and not raw_line[0].isspace():
            in_externals = False
        if not in_externals:
            continue
        match = re.match(r"^  ([^ ].*?):(?:\s.*)?$", raw_line)
        if match:
            root = normalize_reference(match.group(1))
            if root is not None:
                roots.append(root.as_posix())
    return tuple(roots)


external_roots = read_external_roots() if mode == "source" else ()


def is_external(reference):
    value = reference.as_posix()
    return any(value == root or value.startswith(root + "/") for root in external_roots)


if not toc_path.is_file():
    errors.append(f"missing manifest: {toc_path}")
    toc_lines = []
else:
    toc_lines = toc_path.read_text(encoding="utf-8-sig").splitlines()

loaded_lua = set()
xml_queue = []
toc_entries = 0
skipped_externals = 0

for line_number, raw_line in enumerate(toc_lines, 1):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        continue
    line = re.sub(r"\s+\[[^\]]+\]\s*$", "", line)
    reference = normalize_reference(line)
    if reference is None:
        errors.append(f"{toc_path.name}:{line_number}: invalid path: {raw_line!r}")
        continue

    toc_entries += 1
    resolved = find_exact(reference)
    if resolved is None:
        if mode == "source" and is_external(reference):
            skipped_externals += 1
            continue
        errors.append(f"{toc_path.name}:{line_number}: missing or case-mismatched path: {reference}")
        continue

    relative = resolved.relative_to(addon_root).as_posix()
    if resolved.suffix.lower() == ".lua":
        loaded_lua.add(relative)
    elif resolved.suffix.lower() == ".xml":
        xml_queue.append(resolved)

visited_xml = set()
while xml_queue:
    xml_path = xml_queue.pop()
    relative_xml = xml_path.relative_to(addon_root).as_posix()
    if relative_xml in visited_xml:
        continue
    visited_xml.add(relative_xml)

    try:
        xml_root = ElementTree.parse(xml_path).getroot()
    except (OSError, ElementTree.ParseError) as error:
        errors.append(f"{relative_xml}: invalid XML: {error}")
        continue

    for element in xml_root.iter():
        element_name = element.tag.rsplit("}", 1)[-1].lower()
        if element_name not in ("include", "script"):
            continue
        file_value = element.attrib.get("file")
        if not file_value:
            continue
        reference = normalize_reference(file_value)
        if reference is None:
            errors.append(f"{relative_xml}: invalid {element_name} path: {file_value!r}")
            continue

        resolved = find_exact(reference, xml_path.parent)
        if resolved is None:
            if mode == "source" and is_external(reference):
                skipped_externals += 1
                continue
            errors.append(f"{relative_xml}: missing or case-mismatched {element_name}: {reference}")
            continue

        relative = resolved.relative_to(addon_root).as_posix()
        if resolved.suffix.lower() == ".lua":
            loaded_lua.add(relative)
        elif resolved.suffix.lower() == ".xml":
            xml_queue.append(resolved)

excluded_roots = {
    "Libs",
    "scripts",
    "tests",
    ".github",
    ".lint",
    ".release",
    ".unused",
    ".utils",
}
for lua_path in addon_root.rglob("*.lua"):
    relative = lua_path.relative_to(addon_root)
    if relative.parts[0] in excluded_roots or relative.parts[0].startswith("."):
        continue
    relative_string = relative.as_posix()
    if relative_string not in loaded_lua:
        errors.append(f"first-party Lua file is not reachable from the TOC: {relative_string}")

if errors:
    for error in errors:
        print(f"manifest error: {error}", file=sys.stderr)
    sys.exit(1)

print(
    "Manifest OK: "
    f"{toc_entries} entries, {len(loaded_lua)} Lua files, "
    f"{len(visited_xml)} XML files"
    + (f", {skipped_externals} external entries deferred to packaging" if skipped_externals else "")
)
PY
