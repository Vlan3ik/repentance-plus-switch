#!/usr/bin/env python3
"""Verify the pinned HasTrinket symbol, ABI prologue and callsites."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-has-trinket-evidence.json"
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
    build = re.search(r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"',
                      main_text, re.DOTALL)
    assert build and build.group(1) == evidence["build_id"]
    assert evidence["verification_level"] == "hardware_required"
    assert "IsaacPort_Entity_Player__HasTrinket" in main_text
    assert "LC_Entity_Player__HasTrinket" in main_text
    assert "kHasTrinketRva = 0x28D3B8" in bridge_text
    assert "kGoldenTrinketFlag = 0x8000u" in bridge_text
    assert "kTrinketIdMask = 0x7FFFu" in bridge_text

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"HAS_TRINKET_EVIDENCE_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_note = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_note and build_note.group(1) == evidence["build_id"]
    symbols = subprocess.check_output(["readelf", "-sW", str(elf)], text=True,
                                      env=env)
    symbol = re.search(
        r"\s+[0-9]+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+"
        r"[^ ]*Entity_Player[^ ]*HasTrinket[^ ]*", symbols)
    assert symbol and int(symbol.group(1), 16) == 0x28d3b8
    assert int(symbol.group(2)) == 164
    assert words(elf, 0x28d3b8, 4) == evidence["prologue"]
    body = subprocess.check_output([
        "llvm-objdump", "-d", "--arch=aarch64",
        "--start-address=0x28d3b8", "--stop-address=0x28d45c", str(elf)
    ], text=True)
    assert len(re.findall(r"and\s+w9,\s+w9,\s+#0x7fff", body)) == 1
    assert len(re.findall(r"and\s+w8,\s+w8,\s+#0x7fff", body)) == 1
    for proof in evidence["proofs"]:
        start = int(proof["rva"], 16)
        assert words(elf, start, len(proof["instructions"])) == proof["instructions"]
    print("HAS_TRINKET_EVIDENCE_READY rva=0x28d3b8 size=164 verification=hardware_required")


if __name__ == "__main__":
    main()
