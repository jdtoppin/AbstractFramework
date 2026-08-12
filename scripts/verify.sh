#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

./scripts/lint.sh "$@"
python3 ./tests/external_pins_policy_test.py
python3 ./scripts/check-external-pins.py
./scripts/check-manifest.sh
./scripts/run-tests.sh
node .utils/generate_tabler_icons.cjs --check
