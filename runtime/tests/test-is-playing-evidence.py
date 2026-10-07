"""Verify the pinned ANM2::IsPlaying symbol and wrapper contract."""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "analysis/abi/anm2-is-playing-evidence.json"
MAIN = ROOT / "runtime/source/program/main.cpp"


def main() -> None:
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    source = MAIN.read_text(encoding="utf-8")
    build = re.search(
        r'kExpectedRepentanceBuildId\[\].*?"([0-9a-f]+)"', source, re.S
    )
    assert evidence["method"] == "Sprite.IsPlaying"
    assert evidence["rva"] == "0xa454"
    assert evidence["prologue"] == [
        "a9bf7bfd", "910003fd", "f9401c08", "b4000128"
    ]
    assert evidence["verification_level"] == "hardware_required"
    assert build and build.group(1) == evidence["build_id"]
    assert "kAnm2IsPlayingRva = 0xa454" in source
    assert "kExpectedAnm2IsPlayingPrologue" in source
    assert "IsMappedCodeAddress(target)" in source
    assert "IsMappedDataRange(object_address, kAnm2Size" in source
    assert "IsMappedCString(animation)" in source
    assert "IsaacPort_ANM2_IsPlaying" in source

    elf = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / evidence["elf"]["path"]
    if not elf.is_file():
        print(f"IS_PLAYING_EVIDENCE_SKIPPED missing={elf}")
        return
    assert hashlib.sha256(elf.read_bytes()).hexdigest() == evidence["elf"]["sha256"]
    env = dict(os.environ)
    env["LC_ALL"] = "C"
    notes = subprocess.check_output(["readelf", "-n", str(elf)], text=True, env=env)
    build_match = re.search(r"Build ID:\s*([0-9a-f]+)", notes)
    assert build_match and build_match.group(1) == evidence["build_id"]
    disassembly = subprocess.check_output(
        ["llvm-objdump", "-d", "--arch=aarch64",
         f"--start-address={int(evidence['rva'], 16):#x}",
         f"--stop-address={int(evidence['rva'], 16) + evidence['size']:#x}",
         str(elf)], text=True, env=env
    )
    actual = re.findall(
        r"^\s*[0-9a-f]+:\s+([0-9a-f]{8})\s+.*$",
        disassembly, re.MULTILINE
    )
    assert actual[:4] == evidence["prologue"]
    assert "IsPlaying" in disassembly
    print(
        f"IS_PLAYING_EVIDENCE_READY rva={evidence['rva']} "
        f"build_id={evidence['build_id']} verification=hardware_required"
    )


if __name__ == "__main__":
    main()
