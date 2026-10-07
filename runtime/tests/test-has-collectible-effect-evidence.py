#!/usr/bin/env python3
"""Verify the pinned TemporaryEffects.HasCollectibleEffect symbol."""

from __future__ import annotations

import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/temporary-effects-has-collectible-effect-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"
BRIDGE = ROOT / "runtime/source/program/entity_player_bridge.hpp"


def elf_bytes(elf: Path, rva: int, size: int) -> bytes:
    sections = subprocess.check_output(["readelf", "-SW", str(elf)], text=True)
    match = re.search(r"\]\s+\.text\s+\S+\s+([0-9a-f]+)\s+([0-9a-f]+)\s+([0-9a-f]+)", sections)
    assert match, "missing .text section"
    address, offset, section_size = (int(v, 16) for v in match.groups())
    assert address <= rva < address + section_size
    file_offset = offset + (rva - address)
    data = elf.read_bytes()[file_offset:file_offset + size]
    assert len(data) == size
    return data


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    assert evidence["method"] == "TemporaryEffects.HasCollectibleEffect"
    assert evidence["verification_level"] == "hardware_required"
    main_text = MAIN.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    assert "LC_TemporaryEffects__HasCollectibleEffect" in main_text
    assert "kHasCollectibleEffectRva = 0x4A6D60" in bridge_text
    assert "kHasCollectibleEffectSize = 0x64" in bridge_text
    assert evidence["build_id"] in main_text

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"HAS_COLLECTIBLE_EFFECT_ELF_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    raw = elf_bytes(elf, int(evidence["rva"], 16), int(evidence["size"], 16))
    words = [f"{int.from_bytes(raw[i:i + 4], 'little'):08x}"
             for i in range(0, 16, 4)]
    assert words == evidence["prologue"]
    symbols = subprocess.check_output(["readelf", "-Ws", str(elf)], text=True)
    assert re.search(r"004a6d60\s+100\s+FUNC\s+.*TemporaryEffects.*HasEffect", symbols)
    print("HAS_COLLECTIBLE_EFFECT_EVIDENCE_READY rva=0x4a6d60 size=0x64 verification=hardware_required")


if __name__ == "__main__":
    main()
