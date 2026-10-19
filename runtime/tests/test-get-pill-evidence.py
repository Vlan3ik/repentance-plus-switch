#!/usr/bin/env python3
"""Verify the pinned EntityPlayer.GetPill symbol and direct layout."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-get-pill-evidence.json"
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
    assert evidence["verification_level"] == "hardware_required"
    assert evidence["method"] == "EntityPlayer.GetPill"
    assert "LC_Entity_Player__GetPill" in MAIN.read_text(encoding="utf-8")
    bridge = BRIDGE.read_text(encoding="utf-8")
    assert "kGetPillRva = 0x2E8D80" in bridge
    assert "kGetPillRequiredBytes" in bridge
    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"GET_PILL_EVIDENCE_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    symbols = subprocess.check_output(["readelf", "-sW", str(elf)], text=True)
    symbol = re.search(
        r"\s+[0-9]+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+"
        r"[^ ]*Entity_Player[^ ]*GetPill[^ ]*", symbols)
    assert symbol and int(symbol.group(1), 16) == 0x2e8d80
    assert int(symbol.group(2)) == 0x24
    assert words(elf, 0x2e8d80, 9) == evidence["prologue"]
    print("GET_PILL_EVIDENCE_READY rva=0x2e8d80 size=0x24 required_bytes=0x1c30 verification=hardware_required")


if __name__ == "__main__":
    main()
