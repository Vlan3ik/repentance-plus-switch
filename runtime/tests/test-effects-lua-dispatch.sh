#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_DIR=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cat >"$TMP_DIR/effects_dispatch.lua" <<'LUA'
local player = Isaac.GetPlayer(0)
local first = player:GetEffects()
local second = player:GetEffects()
assert(first ~= nil and second ~= nil, "GetEffects returned nil")
assert(first.__borrowed and second.__borrowed, "effects must be borrowed")
assert(first.__native == second.__native, "borrowed effects identity changed")
assert(first:HasCollectibleEffect(42) == true, "resolver true result lost")
assert(first:HasCollectibleEffect(43) == false, "resolver false result lost")
assert(first:GetCollectibleEffectNum(42) == 3, "resolver count result lost")
assert(first:GetCollectibleEffectNum(43) == 0, "resolver zero count result lost")
io.stdout:write("EFFECTS_LUA_DISPATCH_READY borrowed_identity=stable bool=true,false count=3,0\n")
LUA

"$ROOT_DIR/tests/test-bootstrap-host.sh" "$STOCK_DIR" "$MOD_DIR" \
    "" "$TMP_DIR/effects_dispatch.lua"
