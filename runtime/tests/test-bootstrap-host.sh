#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
STOCK_DIR=${1:-"$ROOT_DIR/../reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$ROOT_DIR/../../repentanceplus"}
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
        "https://github.com/LuaJIT/LuaJIT/archive/$LUAJIT_COMMIT.tar.gz" \
        -o "$ARCHIVE"
fi
printf '%s  %s\n' "$LUAJIT_SHA256" "$ARCHIVE" | sha256sum -c -
mkdir "$BUILD_DIR/luajit"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$BUILD_DIR/luajit"
make -C "$BUILD_DIR/luajit/src" \
    -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null
HOST_LUAJIT="$BUILD_DIR/luajit/src/luajit"

python3 "$ROOT_DIR/tests/generate_generic_stubs.py" \
    "$STOCK_DIR/cdefs.lua" "$BUILD_DIR/generic_stubs.c"
cc -shared -fPIC -O2 "$ROOT_DIR/tests/host_stubs.c" \
    "$BUILD_DIR/generic_stubs.c" \
    -o "$BUILD_DIR/libisaac_port_host_stubs.so"
LD_PRELOAD="$BUILD_DIR/libisaac_port_host_stubs.so" \
"$HOST_LUAJIT" "$ROOT_DIR/tests/bootstrap_host.lua" "$STOCK_DIR" "$MOD_DIR" \
    "$BUILD_DIR/libisaac_port_host_stubs.so"
