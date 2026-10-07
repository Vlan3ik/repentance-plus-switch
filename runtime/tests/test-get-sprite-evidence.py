#!/usr/bin/env python3
"""Verify the pinned GetSprite layout and conservative runtime labeling."""

from __future__ import annotations

import json
import hashlib
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-get-sprite-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"
BRIDGE = ROOT / "runtime/source/program/entity_player_bridge.hpp"
PINNED_ELF = ROOT.parent / "switch-port/analysis/nx2elf/Repentance.elf"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    main_text = MAIN.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")

    build = re.search(
        r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"',
        main_text,
        re.DOTALL,
    )
    offset = re.search(
        r"kSpritePointerOffset\s*=\s*0x([0-9a-fA-F]+)", bridge_text
    )
    assert build and build.group(1) == evidence["build_id"]
    assert offset and int(offset.group(1), 16) == int(evidence["offset"], 16)
    assert evidence["verification_level"] == "hardware_required"
    assert "LC_Entity__GetSprite" in main_text
    assert "alignof(void*)" in main_text
    assert "kSpritePointerOffset +" in main_text
    assert "kEntitySpriteSize" in main_text
    borrowed_start = main_text.index("local borrowedSpriteMeta")
    borrowed_end = main_text.index("function Sprite()", borrowed_start)
    borrowed = main_text[borrowed_start:borrowed_end]
    # Comments document why ownership is absent; reject only an actual
    # ffi.gc invocation in the borrowed-wrapper body.
    assert not re.search(r"ffi\.gc\s*\(", borrowed)
    assert "IsaacPort_ANM2_Destroy" not in borrowed

    # When the adjacent pinned analysis checkout is present, verify the
    # concrete folded ARM64 body rather than trusting the JSON annotation.
    if PINNED_ELF.is_file():
        digest = hashlib.sha256(PINNED_ELF.read_bytes()).hexdigest()
        assert digest == evidence["elf"]["sha256"]
        env = dict(os.environ)
        env["LC_ALL"] = "C"
        notes = subprocess.check_output(
            ["readelf", "-n", str(PINNED_ELF)], text=True, env=env
        )
        build_note = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
        assert build_note and build_note.group(1) == evidence["build_id"]

        callsite = evidence["callsite"]
        rva = int(callsite["rva"], 16)
        disassembly = subprocess.check_output(
            [
                "llvm-objdump", "-d", "--arch=aarch64",
                f"--start-address={rva:#x}",
                f"--stop-address={rva + 8:#x}",
                str(PINNED_ELF),
            ],
            text=True,
        )
        words = re.findall(r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+", disassembly,
                           re.MULTILINE)
        assert words[:2] == callsite["instructions"]
    else:
        print(f"GET_SPRITE_ELF_SKIPPED missing={PINNED_ELF}")
    print(
        f"GET_SPRITE_EVIDENCE_READY offset={evidence['offset']} "
        f"build_id={build.group(1)} verification=hardware_required"
    )


if __name__ == "__main__":
    main()
