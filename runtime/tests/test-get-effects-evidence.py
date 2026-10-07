#!/usr/bin/env python3
"""Verify the pinned TemporaryEffects field and ARM64 use sites."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-get-effects-evidence.json"
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
    assert evidence["method"] == "EntityPlayer.GetEffects"
    assert evidence["verification_level"] == "hardware_required"
    assert "LC_Entity_Player__GetEffects" in main_text
    assert "kTemporaryEffectsOffset = 0x18D8" in bridge_text
    assert "kTemporaryEffectsSize = 0x30" in bridge_text
    assert "kTemporaryEffectsOwnerOffset = 0x28" in bridge_text
    build = re.search(r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"',
                      main_text, re.DOTALL)
    assert build and build.group(1) == evidence["build_id"]

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"GET_EFFECTS_ELF_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_match = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_match and build_match.group(1) == evidence["build_id"]
    for proof in evidence["proofs"]:
        rva = int(proof["rva"], 16)
        assert words(elf, rva, len(proof["instructions"])) == proof["instructions"], proof
    print("GET_EFFECTS_EVIDENCE_READY offset=0x18d8 size=0x30 owner=0x28 verification=hardware_required")


if __name__ == "__main__":
    main()
