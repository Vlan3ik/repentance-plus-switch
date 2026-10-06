#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PROJECT_DIR=$(cd "$ROOT_DIR/../.." && pwd)
STOCK_DIR=${1:-"$PROJECT_DIR/switch-port/reference/stock-lua/dlc/resources/scripts_v2"}
MOD_DIR=${2:-"$PROJECT_DIR/repentanceplus"}
FRONTIER="$ROOT_DIR/../analysis/api-usage/runtime-frontier.json"

cd "$ROOT_DIR/.."
./runtime/tests/test-bootstrap-host.sh "$STOCK_DIR" "$MOD_DIR"
./runtime/tests/test-persistence-host.sh
./runtime/tests/test-recording-oracle.sh "$STOCK_DIR" "$MOD_DIR" "$FRONTIER"
python3 ./runtime/tools/generate_coverage.py --frontier "$FRONTIER"
python3 ./runtime/tests/test-generate-coverage.py
python3 ./runtime/tests/test-generate-status.py
printf 'HOST_REGRESSION_READY\n'
