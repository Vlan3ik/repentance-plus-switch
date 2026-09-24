#!/bin/sh
set -eu

IMAGE="devkitpro/devkita64:20260219"
COMMIT="c6ffc141a8762b41703f9287d63d93622a13dd8f"
ARCHIVE_SHA256="6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457"
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD="$ROOT/build"
ARCHIVE="$BUILD/luajit-$COMMIT.tar.gz"
SRC="$BUILD/LuaJIT-$COMMIT"

mkdir -p "$BUILD"
if [ ! -f "$ARCHIVE" ]; then
  curl -L --fail --silent --show-error \
    "https://github.com/LuaJIT/LuaJIT/archive/$COMMIT.tar.gz" -o "$ARCHIVE"
fi
printf '%s  %s\n' "$ARCHIVE_SHA256" "$ARCHIVE" | sha256sum -c -

if [ ! -d "$SRC/src" ]; then
  mkdir -p "$SRC"
  tar -xzf "$ARCHIVE" --strip-components=1 -C "$SRC"
  patch -p1 -d "$SRC" < "$ROOT/patches/0001-nx-entropy-hook.patch"
  patch -p1 -d "$SRC" < "$ROOT/patches/0002-nx-ffi-resolver.patch"
fi

podman run --rm \
  -v "$SRC:/src:Z" \
  -v "$ROOT/smoke:/smoke:ro,Z" \
  "$IMAGE" sh -eu -c '
    export PATH=/opt/devkitpro/devkitA64/bin:$PATH
    mkdir -p /work
    cp -a /src/. /work/
    cd /work
    make -C src clean >/dev/null 2>&1 || true
    make -C src -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" \
      HOST_CC=gcc CROSS=aarch64-none-elf- TARGET_SYS=Other \
      XCFLAGS="-DLJ_TARGET_NX -DLUAJIT_OS=LUAJIT_OS_OTHER -DLUAJIT_DISABLE_JIT -DLUAJIT_USE_SYSMALLOC" \
      BUILDMODE=static libluajit.a
    aarch64-none-elf-gcc -std=c11 -ffreestanding -fno-builtin \
      -I/src/src -c /smoke/nx_entropy_stub.c -o nx_entropy_stub.o
    aarch64-none-elf-gcc -std=c11 -ffreestanding -fno-builtin \
      -I/src/src -c /smoke/nx_smoke.c -o nx_smoke.o
    aarch64-none-elf-gcc nx_smoke.o nx_entropy_stub.o src/libluajit.a \
      -specs=/opt/devkitpro/libnx/switch.specs \
      -L/opt/devkitpro/libnx/lib -lnx -lm -Wl,-z,notext -o nx_smoke.elf
    cp src/libluajit.a /src/libluajit.a
    cp nx_smoke.elf /src/nx_smoke.elf
  '

cp "$SRC/libluajit.a" "$BUILD/libluajit.a"
cp "$SRC/nx_smoke.elf" "$BUILD/nx_smoke.elf"
file "$BUILD/libluajit.a" "$BUILD/nx_smoke.elf"
