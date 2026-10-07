#!/usr/bin/env python3
"""Determinism and conservatism checks for generate_status.py."""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATOR = ROOT / "runtime/tools/generate_status.py"
CHECKED_IN = ROOT / "analysis/abi/status.json"
FRONTIER = ROOT / "analysis/api-usage/runtime-frontier.json"


def run_generator(path: Path) -> bytes:
    subprocess.run(
        [sys.executable, str(GENERATOR), "--output", str(path)],
        check=True,
    )
    return path.read_bytes()


def main() -> None:
    with tempfile.TemporaryDirectory() as directory:
        first = Path(directory) / "first.json"
        second = Path(directory) / "second.json"
        first_bytes = run_generator(first)
        second_bytes = run_generator(second)
        assert first_bytes == second_bytes, "status generator is not deterministic"
        assert first_bytes == CHECKED_IN.read_bytes(), "checked-in status is stale"

    status = json.loads(CHECKED_IN.read_text(encoding="utf-8"))
    assert status["title"]["id"] == "010021C000B6A000"
    assert len(status["implemented"]["resolver_symbols"]) >= 20
    assert len(status["implemented"]["wrappers"]) >= 20
    assert {hook["verification_level"] for hook in status["callback_hooks"]} == {
        "hardware_required"
    }
    assert all(
        marker["verification_level"] == "hardware_required"
        for marker in status["markers"]
    )
    assert any(test["verification_level"] == "host_only" for test in status["tests"])
    assert any(test["name"] == "host_persistence" for test in status["tests"])
    assert any(test["name"] == "hardware_persistence_sentinel" and test["verification_level"] == "hardware_required" for test in status["tests"])
    frontier = json.loads(FRONTIER.read_text(encoding="utf-8"))
    expected_blocker = frontier.get("first_unsupported")
    assert isinstance(expected_blocker, dict)
    assert status["frontier"]["blocker"]["name"] == expected_blocker["name"]
    assert status["frontier"]["blocker"]["classification"] == "pending"
    assert status["frontier"]["blocker"]["switch_status"] == "unresolved"
    assert status["persistence"]["LoadModData"]["host"]["status"] == "host_verified"
    assert status["persistence"]["LoadModData"]["durable"]["status"] == "hardware_required"
    assert status["persistence"]["hardware_persistence_sentinel"]["status"] == "pending"
    assert any(test["name"] == "host_evaluate_items" for test in status["tests"])
    assert any(test["name"] == "host_get_sprite" for test in status["tests"])
    assert any(test["name"] == "static_get_sprite_evidence" and
               test["verification_level"] == "hardware_required"
               for test in status["tests"])
    assert any(test["name"] == "host_dss_isolated" for test in status["tests"])
    assert any(test["name"] == "host_chapi_0946_isolated" for test in status["tests"])
    print("GENERATE_STATUS_TEST_READY")


if __name__ == "__main__":
    main()
