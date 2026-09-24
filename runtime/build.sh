#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
VENDOR_DIR="$ROOT_DIR/vendor/exlaunch"
STAGE_DIR="$ROOT_DIR/.build/exlaunch-stage"
OUTPUT_DIR="$ROOT_DIR/out"
PACKAGE_EXEFS_DIR="$OUTPUT_DIR/atmosphere/contents/010021C000B6A000/exefs"
PACKAGE_ROMFS_DIR="$OUTPUT_DIR/atmosphere/contents/010021C000B6A000/romfs"
PACKAGE_MOD_DIR="$PACKAGE_ROMFS_DIR/mods/repentanceplus"
PACKAGE_RESOURCE_PATCH_DIR="$PACKAGE_ROMFS_DIR/rp_patch/resources"
if [[ -d "/reference/stock-lua/dlc/resources/scripts_v2" ]]; then
    LUA_SOURCE_DIR="/reference/stock-lua/dlc/resources/scripts_v2"
else
    LUA_SOURCE_DIR="$ROOT_DIR/../reference/stock-lua/dlc/resources/scripts_v2"
fi
if [[ -d "/repentanceplus" ]]; then
    MOD_SOURCE_DIR="/repentanceplus"
else
    MOD_SOURCE_DIR="$ROOT_DIR/../repentanceplus"
fi
LUA_GENERATOR="$ROOT_DIR/tools/generate_embedded_lua.py"

if [[ -z "${DEVKITPRO:-}" ]]; then
    echo "DEVKITPRO is not set; use ./build-container.sh or a devkitPro shell" >&2
    exit 2
fi

if [[ ! -d "$LUA_SOURCE_DIR" ]]; then
    echo "missing stock Lua source: $LUA_SOURCE_DIR (mount reference/ into the build container)" >&2
    exit 2
fi
if [[ ! -d "$MOD_SOURCE_DIR" ]]; then
    echo "missing Repentance Plus Lua source: $MOD_SOURCE_DIR (mount repentanceplus into the build container)" >&2
    exit 2
fi

rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -a "$VENDOR_DIR/Makefile" "$VENDOR_DIR/misc" "$VENDOR_DIR/source" "$STAGE_DIR/"
cp "$ROOT_DIR/config.mk" "$STAGE_DIR/config.mk"
cp "$VENDOR_DIR/misc/npdm-json/qlaunch.json" "$STAGE_DIR/config.json"
cp "$ROOT_DIR/source/program/main.cpp" "$STAGE_DIR/source/program/main.cpp"

mkdir -p "$STAGE_DIR/source/generated"
python3 "$LUA_GENERATOR" \
    --source "$LUA_SOURCE_DIR" "" \
    --source "$MOD_SOURCE_DIR" mods/repentanceplus \
    --output "$STAGE_DIR/source/generated"

sed -i \
    -e 's/"title_id": "0x[0-9a-fA-F]*"/"title_id": "0x010021c000b6a000"/' \
    "$STAGE_DIR/config.json"

LUAJIT_LIB="$STAGE_DIR/../../vendor/luajit/build/libluajit.a"
if [[ ! -f "$LUAJIT_LIB" ]]; then
    echo "missing ready LuaJIT archive: $LUAJIT_LIB" >&2
    exit 2
fi

make -C "$STAGE_DIR" LIBS="$LUAJIT_LIB" "$@"

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR" "$PACKAGE_EXEFS_DIR" "$PACKAGE_MOD_DIR" \
    "$PACKAGE_RESOURCE_PATCH_DIR"
cp "$STAGE_DIR/deploy/subsdk9" "$OUTPUT_DIR/subsdk9"
cp "$STAGE_DIR/deploy/subsdk9" "$PACKAGE_EXEFS_DIR/subsdk9"

# Keep a conventional loose-mod tree for the game's surviving ModManager.
# Only runtime inputs are shipped; editor, workshop and repository metadata are
# intentionally excluded from the SD package.
cp "$MOD_SOURCE_DIR/main.lua" "$MOD_SOURCE_DIR/metadata.xml" \
    "$PACKAGE_MOD_DIR/"
for relative_dir in content resources resources-dlc3 scripts; do
    if [[ -d "$MOD_SOURCE_DIR/$relative_dir" ]]; then
        cp -a "$MOD_SOURCE_DIR/$relative_dir" "$PACKAGE_MOD_DIR/"
    fi
done

# Repentance's resource mount builder explicitly mounts rp_patch/resources.
# Mirroring the loose resources here makes graphics/audio available through
# the stock content manager even before the Lua-side mod scanner is restored.
cp -a "$MOD_SOURCE_DIR/resources/." "$PACKAGE_RESOURCE_PATCH_DIR/"
if [[ -d "$MOD_SOURCE_DIR/resources-dlc3" ]]; then
    cp -a "$MOD_SOURCE_DIR/resources-dlc3/." \
        "$PACKAGE_RESOURCE_PATCH_DIR/"
fi

echo "Built $OUTPUT_DIR/subsdk9"
echo "Packaged $PACKAGE_EXEFS_DIR/subsdk9"
echo "Packaged $PACKAGE_MOD_DIR and $PACKAGE_RESOURCE_PATCH_DIR"
