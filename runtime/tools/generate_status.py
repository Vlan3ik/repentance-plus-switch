#!/usr/bin/env python3
"""Generate a conservative, source-derived runtime status snapshot.

This is intentionally a small inventory rather than a claim that the bridge
works on a console.  Anything that reaches a live game object, an ARM64 RVA,
or a native callback is marked ``hardware_required`` until a Switch log proves
it.  The output is stable so it can be checked into the repository and used as
the baseline for the next blocker.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
MAIN = ROOT / "runtime/source/program/main.cpp"
CONFIG = ROOT / "runtime/config.mk"
BRIDGE = ROOT / "analysis/api-usage/native-bridge.json"
FRONTIER = ROOT / "analysis/api-usage/runtime-frontier.json"
DEFAULT_OUTPUT = ROOT / "analysis/abi/status.json"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def _one(pattern: str, text: str, label: str) -> str:
    match = re.search(pattern, text, re.MULTILINE)
    if not match:
        raise RuntimeError(f"could not find {label}")
    return match.group(1)


def _sorted_unique(values: list[str]) -> list[str]:
    return sorted(set(values))


def _frontier_report() -> dict:
    if not FRONTIER.is_file():
        return {
            "status": "missing",
            "verification_level": "host_only",
            "blocker": None,
        }
    data = json.loads(_read(FRONTIER))
    blocker = data.get("first_unsupported")
    if not isinstance(blocker, dict):
        blocker = None
    return {
        "status": data.get("status", "unknown"),
        "stage": data.get("stage"),
        "verification_level": data.get("verification_level", "host_only"),
        "blocker": {
            "name": blocker.get("name"),
            "classification": "pending",
            "reason": blocker.get("reason"),
            "source": blocker.get("source"),
            "line": blocker.get("line"),
            "args": blocker.get("args", []),
            "switch_status": "unresolved",
            "hardware_required": True,
        } if blocker else None,
    }


def _persistence_report() -> dict:
    return {
        "LoadModData": {
            "host": {"status": "host_verified", "test": "host_persistence"},
            "durable": {"status": "hardware_required", "evidence": "console reboot/save-data cycle pending"},
        },
        "SaveModData": {
            "host": {"status": "host_verified", "test": "host_persistence"},
            "durable": {"status": "hardware_required", "evidence": "console reboot/save-data cycle pending"},
        },
        "hardware_persistence_sentinel": {
            "status": "pending",
            "verification_level": "hardware_required",
            "requires": "save on console, restart process, load and compare sentinel",
        },
    }


def generate(output: Path) -> dict:
    main = _read(MAIN)
    config = _read(CONFIG)
    bridge = json.loads(_read(BRIDGE))

    title_id = _one(r"^PROGRAM_ID\s*:=\s*([0-9A-Fa-f]+)\s*$", config, "title ID").upper()
    main_build_id = _one(r"kExpectedMainBuildId\[\]\s*=\s*\n?\s*\"([0-9a-f]+)\"", main, "main build ID")
    repentance_build_id = _one(r"kExpectedRepentanceBuildId\[\]\s*=\s*\n?\s*\"([0-9a-f]+)\"", main, "Repentance build ID")

    resolver_start = main.index('extern "C" void* luaJIT_nx_resolve')
    resolver_end = main.index("return nullptr;", resolver_start)
    resolver_block = main[resolver_start:resolver_end]
    resolver_symbols = _sorted_unique(
        re.findall(r'std::strcmp\(name,\s*"([^"]+)"\)', resolver_block)
    )

    # These are the native entry points implemented in main.cpp and exposed
    # through the resolver.  Keep the source inventory separate from the 544
    # stock cdefs: most cdefs still have no implementation here.
    wrapper_names = _sorted_unique(
        re.findall(
            r'extern "C"\s+(?:NORETURN\s+)?[^{;\n]+?\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(',
            main,
        )
    )
    wrapper_names = [
        name
        for name in wrapper_names
        if name.startswith(("L_", "LL_", "LC_", "IsaacPort_"))
        or name == "IsaacPortSmoke"
    ]

    resolver_entries = [
        {
            "name": name,
            "source": "runtime/source/program/main.cpp:luaJIT_nx_resolve",
            "verification_level": "hardware_required",
        }
        for name in resolver_symbols
    ]
    wrapper_entries = [
        {
            "name": name,
            "resolver_exposed": name in resolver_symbols,
            "source": "runtime/source/program/main.cpp",
            "verification_level": "hardware_required",
        }
        for name in wrapper_names
    ]

    callback_hooks = [
        {
            "name": "ManagerUpdateHook",
            "callback_ids": [],
            "evidence": "pinned Manager::Update RVA and prologue gate",
            "verification_level": "hardware_required",
        },
        {
            "name": "GameUpdateHook",
            "callback_ids": [1],
            "evidence": "pinned Game::Update RVA and MC_POST_UPDATE dispatch",
            "verification_level": "hardware_required",
        },
    ]

    # Marker names are deliberately explicit: REPENTANCE_PLUS_%s is a format
    # string in the source, so the status records the two emitted outcomes.
    marker_names = [
        "BOOTSTRAP_COMPAT_FAIL",
        "ENGINE_HOOK_READY",
        "ENGINE_SMOKE_READY",
        "JSON_PRELOAD_FAIL",
        "LATE_INIT",
        "LUA_CALLBACK_ENABLED",
        "LUA_CALLBACK_FAIL",
        "LUA_CHUNK_FAIL",
        "LUA_SMOKE_FAIL",
        "LUA_SMOKE_READY",
        "MICRO_MOD_FAIL",
        "MOD_MANAGER_CONFIG_READY",
        "MOD_MANAGER_LIST_READY",
        "MOD_MANAGER_SCAN_BEGIN",
        "MOD_MANAGER_SCAN_FAIL",
        "MOD_SOURCE_FAIL",
        "MOD_SOURCES_FAIL",
        "MOD_SOURCES_READY",
        "REPENTANCE_PLUS_FAIL",
        "REPENTANCE_PLUS_READY",
        "SAFE_INIT_READY",
        "STOCK_API_FAIL",
        "STOCK_API_READY",
    ]
    markers = [
        {
            "name": name,
            "source": "runtime/source/program/main.cpp",
            "verification_level": "hardware_required",
        }
        for name in marker_names
    ]

    tests = [
        {
            "name": "host_bootstrap",
            "command": "./runtime/tests/test-bootstrap-host.sh",
            "scope": "LuaJIT + stock scripts + mod bootstrap with fake/stub engine APIs; no live engine pointers",
            "verification_level": "host_only",
        },
        {
            "name": "host_persistence",
            "command": "./runtime/tests/test-persistence-host.sh",
            "scope": "LuaJIT + in-memory persistence stub; verifies Lua-facing save/load/remove contract only",
            "verification_level": "host_only",
        },
        {
            "name": "hardware_persistence_sentinel",
            "command": "not_run: requires Switch save/restart/load cycle",
            "scope": "durable LoadModData/SaveModData across a real console process restart",
            "verification_level": "hardware_required",
        },
        {
            "name": "switch_runtime_build",
            "command": "./runtime/build-container.sh",
            "scope": "devkitA64/exlaunch subsdk9 build",
            "verification_level": "build_verified",
        },
    ]

    status = {
        "schema_version": 1,
        "title": {
            "id": title_id,
            "main_build_id": main_build_id,
            "repentance_build_id": repentance_build_id,
        },
        "source": {
            "runtime": "runtime/source/program/main.cpp",
            "config": "runtime/config.mk",
            "native_bridge": "analysis/api-usage/native-bridge.json",
            "native_bridge_declared_unique": bridge["stock_cdefs"]["declared_unique"],
            "native_bridge_required_closure": bridge["closure"]["required_unique"],
        },
        "implemented": {
            "resolver_symbols": resolver_entries,
            "wrappers": wrapper_entries,
        },
        "callback_hooks": callback_hooks,
        "frontier": _frontier_report(),
        "persistence": _persistence_report(),
        "markers": markers,
        "tests": tests,
        "verification_levels": {
            "host_only": "executed by a host-side test with fake/stub engine APIs; does not prove Switch readiness",
            "host_verified": "executed by a host-side test with fake/stub engine APIs",
            "build_verified": "compiled by the declared Switch build command",
            "hardware_required": "requires the pinned NRO, live pointers, ARM64 ABI, or console callback log",
        },
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(status, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return status


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    generate(args.output.resolve())


if __name__ == "__main__":
    main()
