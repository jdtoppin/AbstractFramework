#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="${1:-$(git -C "$repo_root" describe --tags --always)}"
release_dir="$repo_root/.release"
package_name="AbstractFramework_ExtraMedia"
archive_name="${package_name}-${version}.zip"
staging_dir="$(mktemp -d)"

cleanup() {
    rm -rf "$staging_dir"
}
trap cleanup EXIT

mkdir -p "$release_dir" "$staging_dir/$package_name"
cp -R "$repo_root/ExtraMedia/." "$staging_dir/$package_name/"

(
    cd "$staging_dir"
    zip -9 -q -r "$release_dir/$archive_name" "$package_name"
)

echo "$release_dir/$archive_name"
