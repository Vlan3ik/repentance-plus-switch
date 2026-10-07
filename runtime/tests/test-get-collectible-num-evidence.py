#!/usr/bin/env python3
"""Verify the pinned EntityPlayer.GetCollectibleNum symbol and ABI."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-get-collectible-num-evidence.json"
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
    assert "LC_Entity_Player__GetCollectibleNum" in main_text
    assert "kEntityPlayerGetCollectibleNumRva = 0x29164c" in main_text
    assert "kGetCollectibleNumRva = 0x29164C" in bridge_text
    assert "kGetCollectibleNumRequiredBytes = 0x27E0" in bridge_text

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"GET_COLLECTIBLE_NUM_EVIDENCE_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    symbols = subprocess.check_output(["readelf", "-sW", str(elf)], text=True, env=env)
    symbol = re.search(
        r"\s+[0-9]+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+"
        r"[^ ]*Entity_Player[^ ]*NumCollectibleHeld[^ ]*", symbols)
    assert symbol and int(symbol.group(1), 16) == 0x29164c
    assert int(symbol.group(2)) == 0x570
    assert words(elf, 0x29164c, 7) == evidence["prologue"]
    body = subprocess.check_output([
        "llvm-objdump", "-d", "--arch=aarch64",
        "--start-address=0x29164c", "--stop-address=0x291bbc", str(elf)
    ], text=True)
    assert "b967de88" in body
    assert "[x20, #0x27dc]" in body
    for proof in evidence["proofs"]:
        start = int(proof["rva"], 16)
        assert words(elf, start, len(proof["instructions"])) == proof["instructions"]
    print("GET_COLLECTIBLE_NUM_EVIDENCE_READY rva=0x29164c size=0x570 verification=hardware_required")


if __name__ == "__main__":
    main()
