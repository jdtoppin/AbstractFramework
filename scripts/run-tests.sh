#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

runtimes=()
for runtime in lua5.1 luajit; do
    if command -v "$runtime" >/dev/null 2>&1; then
        runtimes+=("$runtime")
    fi
done

if (( ${#runtimes[@]} == 0 )); then
    echo "lua5.1 or luajit is required to run the test suite." >&2
    exit 127
fi

test_list="$(find tests -type f -name '*_test.lua' -print | LC_ALL=C sort)"
if [[ -z "$test_list" ]]; then
    echo "No tests matching tests/**/*_test.lua were found." >&2
    exit 1
fi

for runtime in "${runtimes[@]}"; do
    echo "Running Lua tests with $runtime"
    while IFS= read -r test_file; do
        [[ -n "$test_file" ]] || continue
        echo "  $test_file"
        "$runtime" "$test_file"
    done <<< "$test_list"
done
