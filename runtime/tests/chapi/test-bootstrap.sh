#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_DIR=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
LUAJIT_COMMIT=c6ffc141a8762b41703f9287d63d93622a13dd8f
LUAJIT_SHA256=6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457
VENDORED_ARCHIVE="$ROOT_DIR/vendor/luajit/build/luajit-$LUAJIT_COMMIT.tar.gz"
ARCHIVE="$BUILD_DIR/luajit.tar.gz"

if [[ -f "$VENDORED_ARCHIVE" ]]; then
    cp "$VENDORED_ARCHIVE" "$ARCHIVE"
else
    curl -L --fail --silent --show-error \
        "https://github.com/LuaJIT/LuaJIT/archive/$LUAJIT_COMMIT.tar.gz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$LUAJIT_SHA256" "$ARCHIVE" | sha256sum -c -
rg -q '^local version = 0\.946$' "$MOD_DIR/scripts/customhealthapi/core.lua"
mkdir "$BUILD_DIR/luajit"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$BUILD_DIR/luajit"
make -C "$BUILD_DIR/luajit/src" \
    -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null

python3 "$ROOT_DIR/tests/generate_generic_stubs.py" \
    "$STOCK_DIR/cdefs.lua" "$BUILD_DIR/generic_stubs.c"
cc -shared -fPIC -O2 "$ROOT_DIR/tests/host_stubs.c" \
    "$BUILD_DIR/generic_stubs.c" -o "$BUILD_DIR/libisaac_port_host_stubs.so"

output=$(LD_PRELOAD="$BUILD_DIR/libisaac_port_host_stubs.so" \
    "$BUILD_DIR/luajit/src/luajit" "$ROOT_DIR/tests/chapi/bootstrap_fixture.lua" \
    "$STOCK_DIR" "$MOD_DIR" "$BUILD_DIR/libisaac_port_host_stubs.so" | tail -n 1)
printf '%s\n' "$output" > "$BUILD_DIR/result.json"

python3 - "$BUILD_DIR/result.json" <<'PY'
import json
import sys

result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["api"] == "Custom Health API"
assert result["version"] == 0.946
if result["status"] != "host_bootstrap_complete":
    raise SystemExit("CHAPI 0.946 fixture blocked: " + result.get("error", "unknown error"))
assert result["first_unsupported"] is False, result["first_unsupported"]
print("CHAPI_0946_HOST_BOOTSTRAP_READY events=" + str(result["event_count"]))
PY
