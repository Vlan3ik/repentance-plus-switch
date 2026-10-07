#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_DIR=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
FRONTIER="$ROOT_DIR/../analysis/api-usage/runtime-frontier.json"
REGRESSION_TMP=$(mktemp -d)
trap 'rm -rf "$REGRESSION_TMP"' EXIT

cd "$ROOT_DIR/.."
./runtime/tests/test-bootstrap-host.sh "$STOCK_DIR" "$MOD_DIR"
./runtime/tests/test-persistence-host.sh
./runtime/tests/test-add-cache-flags.sh
python3 ./runtime/tests/test-cache-flags-evidence.py
./runtime/tests/test-evaluate-items.sh
./runtime/tests/test-game-get-room.sh
./runtime/tests/test-game-get-room-pristine.sh "$STOCK_DIR" "$MOD_DIR"
python3 ./runtime/tests/test-game-get-room-evidence.py
./runtime/tests/test-get-sprite.sh
python3 ./runtime/tests/test-get-sprite-evidence.py
./runtime/tests/test-get-baby-skin.sh
python3 ./runtime/tests/test-get-baby-skin-evidence.py
./runtime/tests/test-post-game-started-hook.sh
./runtime/tests/dss/test_dss_host.sh "$STOCK_DIR" "$MOD_DIR" \
    >"$REGRESSION_TMP/dss.first"
./runtime/tests/dss/test_dss_host.sh "$STOCK_DIR" "$MOD_DIR" \
    >"$REGRESSION_TMP/dss.second"
cmp -s "$REGRESSION_TMP/dss.first" "$REGRESSION_TMP/dss.second"
cat "$REGRESSION_TMP/dss.first"

./runtime/tests/test-recording-oracle.sh "$STOCK_DIR" "$MOD_DIR" "$FRONTIER"

./runtime/tests/chapi/test-bootstrap.sh "$STOCK_DIR" "$MOD_DIR" \
    2>/dev/null | tail -n 1 >"$REGRESSION_TMP/chapi.first"
./runtime/tests/chapi/test-bootstrap.sh "$STOCK_DIR" "$MOD_DIR" \
    2>/dev/null | tail -n 1 >"$REGRESSION_TMP/chapi.second"
cmp -s "$REGRESSION_TMP/chapi.first" "$REGRESSION_TMP/chapi.second"
cat "$REGRESSION_TMP/chapi.first"

# Coverage consumes the fresh oracle frontier; status consumes both reports.
python3 ./runtime/tools/generate_coverage.py --frontier "$FRONTIER"
python3 ./runtime/tests/test-generate-coverage.py
python3 ./runtime/tests/test-generate-status.py
printf 'HOST_REGRESSION_READY\n'
