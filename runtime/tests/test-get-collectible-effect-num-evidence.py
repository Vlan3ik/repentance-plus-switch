#!/usr/bin/env python3
"""Verify the pinned TemporaryEffects collectible count symbol and ABI."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/temporary-effects-get-collectible-effect-num-evidence.json"
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
    assert evidence["method"] == "TemporaryEffects.GetCollectibleEffectNum"
    assert evidence["verification_level"] == "hardware_required"
    assert "LC_TemporaryEffects__GetCollectibleEffectNum" in main_text
    assert "kTemporaryEffectsGetCollectibleEffectNumRva = 0x4a7228" in main_text
    assert "kTemporaryEffectsGetCollectibleEffectNumSize = 0x68" in main_text
    assert "kExpectedTemporaryEffectsGetCollectibleEffectNumPrologue" in main_text
    for word in evidence["prologue"]:
        assert f"0x{word}" in main_text
    assert "kGetCollectibleEffectNumRva = 0x4A7228" in bridge_text
    assert "kGetCollectibleEffectNumSize = 0x68" in bridge_text
    build = re.search(r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"',
                      main_text, re.DOTALL)
    assert build and build.group(1) == evidence["build_id"]

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"GET_COLLECTIBLE_EFFECT_NUM_ELF_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_match = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_match and build_match.group(1) == evidence["build_id"]
    symbols = subprocess.check_output(["readelf", "-sW", str(elf)], text=True, env=env)
    symbol = re.search(
        r"\s+[0-9]+:\s+([0-9a-f]+)\s+(\d+)\s+FUNC\s+GLOBAL\s+DEFAULT\s+\d+\s+"
        r"[^ ]*TemporaryEffects[^ ]*GetEffectNum[^ ]*eCollectibleType[^ ]*", symbols)
    assert symbol and int(symbol.group(1), 16) == 0x4a7228
    assert int(symbol.group(2)) == 0x68
    assert words(elf, 0x4a7228, 4) == evidence["prologue"]
    print("GET_COLLECTIBLE_EFFECT_NUM_EVIDENCE_READY rva=0x4a7228 size=0x68 verification=hardware_required")


if __name__ == "__main__":
    main()
