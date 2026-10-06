#!/usr/bin/env python3
"""Validate the two-launch Switch persistence acceptance log.

The validator intentionally consumes text only.  It does not start LuaJIT,
load the host stubs, or claim that a host test proves persistence across a
console restart.
"""

from __future__ import annotations

import argparse
import pathlib
import sys


PREFIX = "RPLUS_PERSISTENCE_ACCEPTANCE "
EXPECTED = [
    "BEGIN",
    "INITIAL_STATE has=false",
    "SAVE_OK",
    "RESTART_REQUIRED exit_game_and_launch_again",
    "BEGIN",
    "INITIAL_STATE has=true",
    "LOAD_AFTER_RESTART_OK",
    "REMOVE_OK",
    "COMPLETE",
]


def extract_markers(text: str) -> list[str]:
    markers = [line.split(PREFIX, 1)[1].strip() for line in text.splitlines() if PREFIX in line]
    # The Lua test writes through both print and Isaac.DebugString so that
    # either console capture path is usable.  When both paths are captured,
    # each marker appears twice adjacently; collapse only those duplicates.
    collapsed: list[str] = []
    for marker in markers:
        if not collapsed or collapsed[-1] != marker:
            collapsed.append(marker)
    return collapsed


def validate(text: str) -> tuple[bool, str]:
    markers = extract_markers(text)
    failures = [marker for marker in markers if marker.startswith("FAIL ")]
    if failures:
        return False, "console reported failure: " + "; ".join(failures)
    if markers != EXPECTED:
        return (
            False,
            "marker sequence mismatch\n"
            f"expected: {EXPECTED}\n"
            f"actual:   {markers}",
        )
    return True, "PERSISTENCE_ACCEPTANCE_VALIDATED"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=pathlib.Path)
    args = parser.parse_args(argv)
    ok, message = validate(args.log.read_text(encoding="utf-8", errors="replace"))
    print(message)
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
