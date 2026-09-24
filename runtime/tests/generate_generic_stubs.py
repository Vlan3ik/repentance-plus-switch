#!/usr/bin/env python3
"""Generate inert host symbols so stock Lua can bind its method tables."""

from __future__ import annotations

import re
import sys
from pathlib import Path


IMPLEMENTED = {
    "L_DebugString", "L_EnableCallback", "LL_Isaac__GetFrameCount",
    "LL_Isaac__GetEntityTypeByName", "LL_Isaac__GetEntityVariantByName",
    "LL_Isaac__GetItemIdByName", "LL_Isaac__GetPlayerTypeByName",
    "LL_Isaac__GetCardIdByName", "LL_Isaac__GetPillEffectByName",
    "LL_Isaac__GetTrinketIdByName", "LL_Isaac__GetChallengeIdByName",
    "LL_Isaac__GetCostumeIdByPath", "LL_Isaac__GetCurseIdByName",
    "LL_Isaac__GetSoundIdByName", "LC_RNG__SetSeed",
    "LC_RNG__RandomInt", "LC_RNG__RandomFloat", "LC_RNG__Next",
}


def main() -> int:
    source, output = map(Path, sys.argv[1:3])
    declaration = re.compile(
        r"^\s*[^()]+?\b([A-Za-z_][A-Za-z0-9_]*)\s*\([^;]*\)\s*;\s*$"
    )
    symbols = set()
    for line in source.read_text(encoding="utf-8").splitlines():
        match = declaration.match(line)
        if match and match.group(1) not in IMPLEMENTED:
            symbols.add(match.group(1))
    rows = ["#include <stdint.h>", ""]
    rows.extend(f"uintptr_t {symbol}(void) {{ return 0; }}" for symbol in sorted(symbols))
    output.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
