#!/usr/bin/env python3
"""Check the checked-in Game::_room evidence against source guards."""

from __future__ import annotations

import json
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/game-get-room-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    source = MAIN.read_text(encoding="utf-8")
    build = re.search(
        r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"', source, re.S
    )
    offset = re.search(r"kGameRoomOffset\s*=\s*0x([0-9a-fA-F]+)", source)
    assert build and build.group(1) == evidence["build_id"]
    assert offset and int(offset.group(1), 16) == int(evidence["offset"], 16)
    assert evidence["member"] == "_room"
    assert evidence["return_contract"].startswith("non-owning")
    assert len(evidence["uses"]) == 4
    assert "isaac_port::game_room::Resolve" in source

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT.parent / "switch-port/analysis/nx2elf/Repentance.elf"
    if not elf.is_file():
        print(f"GAME_GET_ROOM_EVIDENCE_SKIPPED missing={elf}")
        return
    digest = hashlib.sha256(elf.read_bytes()).hexdigest()
    assert digest == evidence["elf_sha256"], (digest, evidence["elf_sha256"])
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_id = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_id and build_id.group(1) == evidence["build_id"]

    disassembly = subprocess.check_output(
        ["llvm-objdump", "-d", "--arch=aarch64", str(elf)], text=True, env=env
    )
    instructions = {}
    for line in disassembly.splitlines():
        match = re.match(r"^\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+", line)
        if match:
            instructions[int(match.group(1), 16)] = match.group(2)
    for use in evidence["uses"]:
        addresses = [int(value, 16) for value in use["instruction_addresses"]]
        assert addresses[0] == int(use["rva"], 16)
        actual = [instructions.get(address) for address in addresses]
        assert actual == use["instructions"], (use, actual)
    print("GAME_GET_ROOM_EVIDENCE_READY uses=4 offset=0x21550 elf_verified=true")


if __name__ == "__main__":
    main()
