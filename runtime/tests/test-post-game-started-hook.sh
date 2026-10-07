#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
MAIN="$ROOT_DIR/source/program/main.cpp"
STOCK="$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2/main.lua"
ELF="$PROJECT_DIR/switch-port/analysis/nx2elf/Repentance.elf"

grep -F 'kManagerExecuteStartGameRva = 0x3f9138' "$MAIN" >/dev/null
grep -F 'ManagerExecuteStartGameHook::InstallAtPtr(execute_start_game)' "$MAIN" >/dev/null
grep -F 'DispatchLuaCallbackWithBool(15, mode == 1)' "$MAIN" >/dev/null
grep -F 'state + 1' "$MAIN" >/dev/null
grep -F 'g_post_game_started_enabled = true' "$MAIN" >/dev/null
grep -F 'PostGameStarted", args = function(p) return p.I1 ~= 0 end' "$STOCK" >/dev/null

if command -v llvm-objdump >/dev/null 2>&1 && [[ -f "$ELF" ]]; then
    PROLOGUE=$(llvm-objdump -d --start-address=0x3f9138 \
        --stop-address=0x3f9148 "$ELF" | tr '\n' ' ')
    for word in d10543ff a9107bfd 910403fd a91167fc; do
        grep -F "$word" <<<"$PROLOGUE" >/dev/null
    done
fi

printf 'POST_GAME_STARTED_HOOK_HOST_READY rva=0x3f9138 continued=(mode==1) verification=hardware_required\n'
