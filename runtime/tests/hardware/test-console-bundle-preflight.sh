#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
PREFLIGHT="$ROOT_DIR/runtime/tests/hardware/console_bundle_preflight.py"
OUT="$ROOT_DIR/runtime/out"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

before_hash=$(sha256sum "$OUT/atmosphere/contents/010021C000B6A000/exefs/subsdk9")
python3 "$PREFLIGHT" --out "$OUT" --manifest "$TMP_DIR/release-manifest.json" | grep -Fx CONSOLE_BUNDLE_PREFLIGHT_OK
test ! -e "$OUT/atmosphere/contents/010021C000B6A000/romfs/mods/rplus-persistence-acceptance"
test "$(sha256sum "$OUT/atmosphere/contents/010021C000B6A000/exefs/subsdk9")" = "$before_hash"

python3 "$PREFLIGHT" \
    --out "$OUT" \
    --test-bundle "$TMP_DIR/console-test" \
    --manifest "$TMP_DIR/test-manifest.json" \
    | grep -Fx CONSOLE_BUNDLE_PREFLIGHT_OK
test -f "$TMP_DIR/console-test/atmosphere/contents/010021C000B6A000/romfs/mods/rplus-persistence-acceptance/main.lua"
test ! -e "$OUT/atmosphere/contents/010021C000B6A000/romfs/mods/rplus-persistence-acceptance"
python3 - "$TMP_DIR/release-manifest.json" "$TMP_DIR/test-manifest.json" <<'PY'
import json
import pathlib
import sys

release = json.loads(pathlib.Path(sys.argv[1]).read_text())
test = json.loads(pathlib.Path(sys.argv[2]).read_text())
assert release["checks"]["persistence_acceptance_mod"] is False
assert test["checks"]["persistence_acceptance_mod"] is True
assert all(not value.startswith("/") for value in test["nso"].values() if isinstance(value, str))
assert all(not entry["path"].startswith("/") for entry in test["files"])
assert len(test["files"]) == len(release["files"]) + 1
PY

echo CONSOLE_BUNDLE_PREFLIGHT_TEST_READY
