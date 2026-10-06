#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT
LUAJIT_COMMIT=c6ffc141a8762b41703f9287d63d93622a13dd8f
LUAJIT_SHA256=6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457
ARCHIVE="$BUILD_DIR/luajit.tar.gz"
VENDORED_ARCHIVE="$ROOT_DIR/vendor/luajit/build/luajit-$LUAJIT_COMMIT.tar.gz"
if [[ -f "$VENDORED_ARCHIVE" ]]; then cp "$VENDORED_ARCHIVE" "$ARCHIVE"
else curl -L --fail --silent --show-error "https://github.com/LuaJIT/LuaJIT/archive/$LUAJIT_COMMIT.tar.gz" -o "$ARCHIVE"; fi
printf '%s  %s\n' "$LUAJIT_SHA256" "$ARCHIVE" | sha256sum -c -
mkdir "$BUILD_DIR/luajit"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$BUILD_DIR/luajit"
make -C "$BUILD_DIR/luajit/src" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null
cc -shared -fPIC -O2 "$ROOT_DIR/tests/persistence_stubs.c" -o "$BUILD_DIR/libpersistence.so"
LD_PRELOAD="$BUILD_DIR/libpersistence.so" "$BUILD_DIR/luajit/src/luajit" "$ROOT_DIR/tests/persistence_host.lua"
