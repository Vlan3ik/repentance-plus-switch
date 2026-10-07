"""Verify the pinned GetBabySkin field contract and conservative labeling."""

from __future__ import annotations

import json
import hashlib
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/entity-player-baby-skin-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"
BRIDGE = ROOT / "runtime/source/program/entity_player_bridge.hpp"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    main_text = MAIN.read_text(encoding="utf-8")
    bridge_text = BRIDGE.read_text(encoding="utf-8")
    build = re.search(
        r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"',
        main_text,
        re.DOTALL,
    )
    offset = re.search(r"kBabySkinOffset\s*=\s*0x([0-9a-fA-F]+)", bridge_text)
    assert evidence["method"] == "EntityPlayer.GetBabySkin"
    assert evidence["field"] == {
        "name": "babySkin", "offset": "0x20e8", "size": 4,
        "signed": True, "type": "int32"
    }
    assert evidence["verification_level"] == "hardware_required"
    assert build and build.group(1) == evidence["build_id"]
    assert offset and int(offset.group(1), 16) == 0x20E8
    assert "LC_Entity_Player__GetBabySkin" in main_text
    assert "sizeof(std::int32_t)" in main_text
    assert "alignof(void*)" in main_text
    assert len(evidence["proofs"]) == 8
    assert {p["kind"] for p in evidence["proofs"]} <= {"read", "write", "call"}

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"GET_BABY_SKIN_ELF_SKIPPED missing={elf}")
        return

    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_match = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_match and build_match.group(1) == evidence["build_id"]

    writes = {p["rva"] for p in evidence["proofs"] if p["kind"] == "write"}
    reads = {p["rva"] for p in evidence["proofs"] if p["kind"] == "read"}
    assert len(writes) >= 3 and len(reads) >= 2
    for proof in evidence["proofs"]:
        rva = int(proof["rva"], 16)
        words = proof["instructions"]
        disassembly = subprocess.check_output(
            ["llvm-objdump", "-d", "--arch=aarch64",
             f"--start-address={rva:#x}",
             f"--stop-address={rva + len(words) * 4:#x}", str(elf)],
            text=True,
        )
        actual = re.findall(
            r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+.*$",
            disassembly, re.MULTILINE,
        )
        assert actual[:len(words)] == words, (proof, actual)
        if proof["kind"] in {"read", "write"}:
            assert "#0x20e8" in disassembly
    print(
        f"GET_BABY_SKIN_EVIDENCE_READY offset={evidence['field']['offset']} "
        f"build_id={evidence['build_id']} verification=hardware_required"
    )


if __name__ == "__main__":
    main()
