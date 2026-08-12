#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if (( $# != 1 )); then
    echo "Usage: $0 package.zip" >&2
    exit 2
fi

archive="$1"
if [[ ! -f "$archive" ]]; then
    echo "Package not found: $archive" >&2
    exit 1
fi

for command_name in python3 rg unzip; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "$command_name is required to smoke-test a package." >&2
        exit 127
    }
done

lua_compiler=""
for candidate in luac5.1 luac-5.1 luac; do
    if command -v "$candidate" >/dev/null 2>&1; then
        lua_compiler="$(command -v "$candidate")"
        break
    fi
done
if [[ -z "$lua_compiler" ]] && ! command -v luajit >/dev/null 2>&1; then
    echo "A Lua 5.1 compiler or LuaJIT is required to validate packaged Lua." >&2
    exit 127
fi

python3 - "$archive" <<'PY'
import stat
import sys
import zipfile
from pathlib import PurePosixPath


archive = sys.argv[1]
required = {
    "AbstractFramework/AbstractFramework.toc",
    "AbstractFramework/LICENSE",
    "AbstractFramework/README.md",
}
dev_only = {
    ".gitattributes",
    ".github",
    ".gitignore",
    ".kanban",
    ".lint",
    ".luacheckrc",
    ".pkgmeta",
    ".release",
    ".unused",
    ".utils",
    "AGENTS.md",
    "CONTRIBUTING.md",
    "scripts",
    "tests",
}
errors = []

with zipfile.ZipFile(archive) as package:
    names = [entry.filename for entry in package.infolist()]
    if len(names) != len(set(names)):
        errors.append("archive contains duplicate entries")

    casefolded = {}
    for name in names:
        folded = name.casefold()
        previous = casefolded.get(folded)
        if previous is not None and previous != name:
            errors.append(f"archive contains case-colliding entries: {previous} and {name}")
        casefolded[folded] = name

    for entry in package.infolist():
        name = entry.filename
        path = PurePosixPath(name)
        if "\\" in name or path.is_absolute() or ".." in path.parts:
            errors.append(f"unsafe archive path: {name}")
            continue
        if not path.parts or path.parts[0] != "AbstractFramework":
            errors.append(f"entry is outside the AbstractFramework root: {name}")
            continue
        if len(path.parts) > 1 and path.parts[1] in dev_only:
            errors.append(f"development-only file was packaged: {name}")
        file_type = stat.S_IFMT(entry.external_attr >> 16)
        if file_type == stat.S_IFLNK:
            errors.append(f"symbolic links are not allowed in the package: {name}")

    missing = sorted(required.difference(names))
    for name in missing:
        errors.append(f"required package file is missing: {name}")

if errors:
    for error in errors:
        print(f"package error: {error}", file=sys.stderr)
    sys.exit(1)
PY

unzip -tq "$archive"

scratch="$(mktemp -d)"
cleanup() {
    rm -rf -- "$scratch"
}
trap cleanup EXIT

unzip -q "$archive" -d "$scratch"
./scripts/check-manifest.sh "$scratch/AbstractFramework"

while IFS= read -r -d '' lua_file; do
    if [[ -n "$lua_compiler" ]]; then
        "$lua_compiler" -p "$lua_file"
    else
        luajit -b "$lua_file" /dev/null
    fi
done < <(find "$scratch/AbstractFramework" -type f -name '*.lua' -print0)

if rg -n '@(project-version|localization)@|#@(debug|end-debug|do-not-package|end-do-not-package)@' \
    "$scratch/AbstractFramework"
then
    echo "Unresolved packager tokens are present in the package." >&2
    exit 1
fi

echo "Package smoke test OK: $archive"
