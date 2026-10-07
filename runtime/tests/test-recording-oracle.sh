#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_DIR=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
OUT_JSON=${3:-"$ROOT_DIR/../analysis/api-usage/runtime-frontier.json"}
STOCK_DIR=$(realpath -e -- "$STOCK_DIR")
MOD_DIR=$(realpath -e -- "$MOD_DIR")
BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

LUAJIT_COMMIT=c6ffc141a8762b41703f9287d63d93622a13dd8f
LUAJIT_SHA256=6e5fec07750add912e7c3eae0c194d24cd6d023714e1f04a0298a5b4819e4457
VENDORED_ARCHIVE="$ROOT_DIR/vendor/luajit/build/luajit-$LUAJIT_COMMIT.tar.gz"
ARCHIVE="$BUILD_DIR/luajit.tar.gz"
if [[ -f "$VENDORED_ARCHIVE" ]]; then cp "$VENDORED_ARCHIVE" "$ARCHIVE"
else curl -L --fail --silent --show-error "https://github.com/LuaJIT/LuaJIT/archive/$LUAJIT_COMMIT.tar.gz" -o "$ARCHIVE"; fi
printf '%s  %s\n' "$LUAJIT_SHA256" "$ARCHIVE" | sha256sum -c -
mkdir "$BUILD_DIR/luajit"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$BUILD_DIR/luajit"
make -C "$BUILD_DIR/luajit/src" -j"$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)" >/dev/null

python3 "$ROOT_DIR/tests/generate_generic_stubs.py" "$STOCK_DIR/cdefs.lua" "$BUILD_DIR/generic_stubs.c"
# Some blocker experiments provide a host implementation for the same mod
# persistence symbols that are also emitted from stock cdefs.  The oracle
# does not exercise that native persistence ABI, so allow the duplicate test
# symbols while keeping the build self-contained.
cc -shared -fPIC -Wl,--allow-multiple-definition -O2 "$ROOT_DIR/tests/host_stubs.c" "$BUILD_DIR/generic_stubs.c" -o "$BUILD_DIR/libisaac_port_host_stubs.so"
mkdir -p "$(dirname "$OUT_JSON")"
LD_PRELOAD="$BUILD_DIR/libisaac_port_host_stubs.so" "$BUILD_DIR/luajit/src/luajit" \
  "$ROOT_DIR/tests/oracle/recording_oracle.lua" "$STOCK_DIR" "$MOD_DIR" "$OUT_JSON" \
  "$BUILD_DIR/libisaac_port_host_stubs.so"
test -s "$OUT_JSON"
# Resolve the same inputs through symlinks as a second invocation.  The
# oracle's canonicalization must make the complete report byte-identical.
ln -s "$STOCK_DIR" "$BUILD_DIR/stock-link"
ln -s "$MOD_DIR" "$BUILD_DIR/mod-link"
SECOND_JSON="$BUILD_DIR/second-frontier.json"
LD_PRELOAD="$BUILD_DIR/libisaac_port_host_stubs.so" "$BUILD_DIR/luajit/src/luajit" \
  "$ROOT_DIR/tests/oracle/recording_oracle.lua" "$BUILD_DIR/stock-link" "$BUILD_DIR/mod-link" "$SECOND_JSON" \
  "$BUILD_DIR/libisaac_port_host_stubs.so" >/dev/null
test -s "$SECOND_JSON"
cmp -s "$OUT_JSON" "$SECOND_JSON"
test "$(sha256sum "$OUT_JSON" | awk '{print $1}')" = "$(sha256sum "$SECOND_JSON" | awk '{print $1}')"
MOD_LUA_COUNT=$(find "$MOD_DIR" -type f -name '*.lua' -printf '%f\n' | wc -l)
test "$MOD_LUA_COUNT" -eq 53
python3 - "$OUT_JSON" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("schema") == 1
assert d.get("status") in {"host_bootstrap_blocked", "host_bootstrap_complete"}
assert d.get("verification_level") == "host_only"
assert d.get("stage") == "post_game_started_then_post_update_minimal_state"
assert isinstance(d.get("operations"), list)
assert len(d.get("callbacks", [])) == 123
assert d["operations"]
cache_calls = [event for event in d["operations"]
               if event.get("name") == "EntityPlayer.AddCacheFlags"
               and event.get("kind") == "call"]
assert cache_calls and cache_calls[-1]["args"] == [4294967295]
evaluate_calls = [event for event in d["operations"]
                  if event.get("name") == "EntityPlayer.EvaluateItems"
                  and event.get("kind") == "call"]
assert evaluate_calls
if d["status"] == "host_bootstrap_blocked":
    assert d.get("first_unsupported")
    assert d["first_unsupported"]["name"] == "TemporaryEffects.GetCollectibleEffectNum"
    trinket_calls = [event for event in d["operations"]
                     if event.get("name") == "EntityPlayer.HasTrinket"
                     and event.get("kind") == "call"]
    assert trinket_calls
    collectible_calls = [event for event in d["operations"]
                         if event.get("name") == "EntityPlayer.HasCollectible"
                         and event.get("kind") == "call"]
    assert len(collectible_calls) >= 3
    effects_calls = [event for event in d["operations"]
                     if event.get("name") == "EntityPlayer.GetEffects"
                     and event.get("kind") == "call"]
    assert effects_calls
    effect_calls = [event for event in d["operations"]
                     if event.get("name") == "TemporaryEffects.HasCollectibleEffect"
                     and event.get("kind") == "call"]
    assert effect_calls and effect_calls[-1]["args"]
    collectible_num_calls = [event for event in d["operations"]
                             if event.get("name") == "EntityPlayer.GetCollectibleNum"
                             and event.get("kind") == "call"]
    assert collectible_num_calls and collectible_num_calls[-1]["args"]
    fixture_calls = [event for event in d["operations"]
                     if event.get("name") == "EntityPlayer.GetData"
                     and event.get("kind") == "fixture_satisfied"]
    assert len(fixture_calls) >= 4
    assert fixture_calls[0]["args"] == ["stable_identity", "retained_value", "player_isolation"]
    blocker = d["first_unsupported"]
    assert isinstance(blocker, dict)
    assert isinstance(blocker.get("name"), str) and blocker["name"]
    assert isinstance(blocker.get("reason"), str) and blocker["reason"]
else:
    assert d["status"] == "host_bootstrap_complete"
    assert d.get("first_unsupported") is None
PY
printf 'runtime frontier: %s\n' "$OUT_JSON"
