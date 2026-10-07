#!/usr/bin/env python3
"""Verify the pinned HasCollectible symbol and exact ARM64 prologue."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-has-collectible-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"
BRIDGE = ROOT / "runtime/source/program/entity_player_bridge.hpp"


def words(elf: Path, start: int, count: int) -> list[str]:
    text = subprocess.check_output([
        "llvm-objdump", "-d", "--arch=aarch64",
        f"--start-address={start:#x}",
        f"--stop-address={start + count * 4:#x}", str(elf),
    ], text=True)
    return re.findall(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+.*$",
                      text, re.MULTILINE)[:count]


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    main_text = MAIN.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    assert evidence["verification_level"] == "hardware_required"
    assert "LC_Entity_Player__HasCollectible" in main_text
    assert "kEntityPlayerHasCollectibleRva = 0x27d3f4" in main_text
    assert "kHasCollectibleRva = 0x27D3F4" in bridge_text
    assert "kHasCollectibleRequiredBytes = 0x27DD" in bridge_text

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"HAS_COLLECTIBLE_EVIDENCE_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    symbols = subprocess.check_output(["readelf", "-sW", str(elf)], text=True,
                                      env=env)
    symbol = re.search(
        r"\s+[0-9]+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+"
        r"[^ ]*Entity_Player[^ ]*HasCollectible[^ ]*", symbols)
    assert symbol and int(symbol.group(1), 16) == 0x27d3f4
    assert int(symbol.group(2)) == 1536
    assert words(elf, 0x27d3f4, 7) == evidence["prologue"]
    body = subprocess.check_output([
        "llvm-objdump", "-d", "--arch=aarch64",
        "--start-address=0x27d3f4", "--stop-address=0x27d9f4", str(elf)
    ], text=True)
    # The compiler materializes 0x27dc in w8 and uses register-offset ldrb;
    # this is the highest direct player field access in the native body.
    assert "5284fb88" in body
    assert "[x20, x8]" in body
    for proof in evidence["proofs"]:
        start = int(proof["rva"], 16)
        assert words(elf, start, len(proof["instructions"])) == proof["instructions"]
    print("HAS_COLLECTIBLE_EVIDENCE_READY rva=0x27d3f4 size=1536 verification=hardware_required")


if __name__ == "__main__":
    main()
