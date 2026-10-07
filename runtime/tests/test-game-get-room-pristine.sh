#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_SOURCE=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
STOCK_COPY="$TMP_DIR/scripts_v2"
cp -a "$STOCK_SOURCE" "$STOCK_COPY"

# The stock snapshot remains untouched: the tracked runtime compatibility
# layer owns the extra cdef and Game.GetRoom wrapper.
if rg -q 'LL_Game__GetRoom|function Game\.GetRoom' "$STOCK_COPY"; then
    echo "pristine stock unexpectedly contains Game.GetRoom" >&2
    exit 1
fi

"$ROOT_DIR/tests/test-bootstrap-host.sh" "$STOCK_COPY" "$MOD_DIR" \
    | grep -F 'REPENTANCE_PLUS_HOST_BOOTSTRAP_READY' >/dev/null
printf 'GAME_GET_ROOM_PRISTINE_STOCK_READY external_patch=none\n'
