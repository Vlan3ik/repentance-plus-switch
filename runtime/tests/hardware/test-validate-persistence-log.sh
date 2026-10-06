#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
VALIDATOR="$ROOT_DIR/runtime/tests/hardware/validate_persistence_log.py"
FIXTURES="$ROOT_DIR/runtime/tests/hardware/fixtures"

python3 "$VALIDATOR" "$FIXTURES/persistence-complete.log" | grep -Fx PERSISTENCE_ACCEPTANCE_VALIDATED
if python3 "$VALIDATOR" "$FIXTURES/persistence-first-launch-only.log" >/dev/null 2>&1; then
    echo "validator accepted a single launch" >&2
    exit 1
fi
if python3 "$VALIDATOR" "$FIXTURES/persistence-wrong-order.log" >/dev/null 2>&1; then
    echo "validator accepted an invalid marker order" >&2
    exit 1
fi
echo PERSISTENCE_LOG_VALIDATOR_TEST_READY
