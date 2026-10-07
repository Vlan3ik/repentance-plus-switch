#!/usr/bin/env python3
"""Verify the checked-in AddCacheFlags offset evidence against Repentance.elf."""

from __future__ import annotations

import json
import os
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-cache-flags-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"
DEFAULT_ELF = ROOT.parent / "switch-port/analysis/nx2elf/Repentance.elf"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    elf = Path(__import__("sys").argv[1]) if len(__import__("sys").argv) > 1 else DEFAULT_ELF
    if not elf.is_file():
        print(f"CACHE_FLAGS_EVIDENCE_SKIPPED missing={elf}")
        return

    main_text = MAIN.read_text(encoding="utf-8")
    offset = re.search(r"kPendingCacheFlagsOffset\s*=\s*0x([0-9a-fA-F]+)",
                       (ROOT / "runtime/source/program/entity_player_bridge.hpp").read_text(encoding="utf-8"))
    build = re.search(r"kExpectedRepentanceBuildId\[\].*?\"([0-9a-f]+)\"",
                      main_text, re.DOTALL)
    assert offset and int(offset.group(1), 16) == int(evidence["field"]["offset"], 16)
    assert build and build.group(1) == evidence["build_id"]

    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_match = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_match and build_match.group(1) == evidence["build_id"]

    disassembly = subprocess.check_output(
        ["llvm-objdump", "-d", "--arch=aarch64", str(elf)], text=True
    )
    lines = {}
    for line in disassembly.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+[0-9a-f]+\s+(.+?)\s*$", line)
        if match:
            lines[int(match.group(1), 16)] = re.sub(r"\s+", " ", match.group(2).strip())
    for use in evidence["uses"]:
        addresses = [int(value, 16) for value in use.get(
            "instruction_addresses", [hex(int(use["rva"], 16) + index * 4)
                                        for index in range(3)])]
        actual = [lines.get(address, "") for address in addresses]
        assert actual == use["instructions"], (use, actual)
    print(f"CACHE_FLAGS_EVIDENCE_READY uses={len(evidence['uses'])} build_id={build.group(1)}")


if __name__ == "__main__":
    main()
