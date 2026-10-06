#!/usr/bin/env python3
"""Build the cross-source API coverage inventory.

The output is deliberately evidence-oriented.  A name match is not an ABI
match: entries retain their source evidence and keep Switch resolution as
``unknown`` until an RVA has been checked against the target NRO.
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any, Iterable

SCHEMA_VERSION = 1
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_USAGE = Path(__file__).parents[2] / "analysis/api-usage/api-usage.json"
DEFAULT_FRONTIER = Path(__file__).parents[2] / "analysis/api-usage/runtime-frontier.json"
DEFAULT_OUTPUT = Path(__file__).parents[2] / "analysis/abi/coverage.json"
DEFAULT_ZHL = Path(__file__).parents[3] / "porting-reference-repositories/REPENTOGON/libzhl/functions"
DEFAULT_ISAACSCRIPT = Path(__file__).parents[3] / "porting-reference-repositories/isaacscript/packages/isaac-typescript-definitions/src"
DEFAULT_ISAACSCRIPT_RG = Path(__file__).parents[3] / "porting-reference-repositories/isaacscript/packages/isaac-typescript-definitions-repentogon/src"


def read_json(path: Path, fallback: Any) -> Any:
    if not path or not path.is_file():
        return fallback
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return fallback


def source_path(path: Path | None) -> str | None:
    if not path or not path.exists():
        return None
    resolved = path.resolve()
    for base, prefix in ((PROJECT_ROOT, ""), (PROJECT_ROOT.parent, "../")):
        try:
            return prefix + resolved.relative_to(base).as_posix()
        except ValueError:
            pass
    # External fixtures must not bake a machine-specific absolute path into a
    # checked-in report.
    return resolved.name


def flatten_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for child in value.values():
            yield from flatten_strings(child)
    elif isinstance(value, list):
        for child in value:
            yield from flatten_strings(child)


def portable_values(value: Any) -> Any:
    """Copy metadata while replacing checkout-specific absolute paths."""
    if isinstance(value, dict):
        return {key: portable_values(child) for key, child in value.items()}
    if isinstance(value, list):
        return [portable_values(child) for child in value]
    if isinstance(value, str):
        for base, prefix in ((PROJECT_ROOT, ""), (PROJECT_ROOT.parent, "../")):
            try:
                return prefix + Path(value).resolve().relative_to(base).as_posix()
            except (ValueError, OSError):
                pass
        return value
    return value


def frontier_data(path: Path | None) -> dict[str, Any]:
    """Normalize the several recording-proxy frontier formats in circulation."""
    raw = read_json(path, {}) if path else {}
    if not isinstance(raw, dict):
        return {"order": [], "blocker": None, "raw": raw}
    order: list[Any] = []
    for key in ("order", "runtime_order", "operations", "events", "calls", "records", "frontier"):
        value = raw.get(key)
        if isinstance(value, list):
            order.extend(value)
            break
    blocker = raw.get("blocker", raw.get("first_blocker", raw.get("first_unsupported")))
    if blocker is None and isinstance(raw.get("error"), (str, dict)):
        blocker = raw["error"]
    return {"order": order, "blocker": blocker, "raw": raw}


def parse_zhl(directory: Path) -> dict[str, list[dict[str, str]]]:
    result: dict[str, list[dict[str, str]]] = {}
    if not directory.is_dir():
        return result
    # A ZHL file consists of a masked x86 pattern followed by a declaration.
    declaration = re.compile(r"(?:__thiscall\s+)?(?:static\s+)?(?:[\w:*<>]+)\s+([\w:]+)\s*\(([^;]*)\)")
    for path in sorted(directory.glob("*.zhl")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        pending_pattern: str | None = None
        for line in text.splitlines():
            line = line.strip()
            if line.startswith('"') and line.endswith(":"):
                pending_pattern = line[:-2].strip('"')
                continue
            match = declaration.search(line)
            if not match:
                continue
            symbol, args = match.groups()
            short = symbol.rsplit("::", 1)[-1]
            record = {"symbol": symbol, "signature": line.rstrip(";"), "pattern": pending_pattern or "", "source": path.name}
            for key in dict.fromkeys((symbol, short)):
                result.setdefault(key, []).append(record)
            pending_pattern = None
    return result


def parse_typescript(root: Path) -> dict[str, list[dict[str, str]]]:
    result: dict[str, list[dict[str, str]]] = {}
    if not root.is_dir():
        return result
    # IsaacScript declarations use function types as well as scalar fields.
    # Keep the parser intentionally permissive; the source text is evidence,
    # not a claim that the Switch ABI has been proven.
    method = re.compile(r"\b(?:readonly\s+)?([A-Za-z_$][\w$]*)\s*:\s*([^;]+);")
    enum = re.compile(r"^\s*([A-Z][A-Z0-9_]*)\s*=\s*([^,]+),?", re.MULTILINE)
    for path in sorted(root.rglob("*.d.ts")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in method.finditer(text):
            name = match.group(1)
            result.setdefault(name, []).append({"name": name, "source": str(path.relative_to(root))})
    for path in sorted(root.rglob("*.ts")):
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for match in enum.finditer(text):
            name, value = match.groups()
            result.setdefault(name, []).append({"name": name, "value": value.strip(), "source": str(path.relative_to(root))})
    return result


def usage_entries(usage: dict[str, Any]) -> list[tuple[str, str, int]]:
    out: list[tuple[str, str, int]] = []
    for section in ("callbacks", "global_calls", "isaac_methods"):
        values = usage.get(section, {})
        if not isinstance(values, dict):
            continue
        for name, count in sorted(values.items()):
            out.append((section, str(name), int(count) if isinstance(count, (int, float)) else 0))
    return out


def method_usage(usage: dict[str, Any], method: str) -> int:
    """Return static receiver-method usage for a frontier method.

    The Lua usage report has receiver-qualified spellings (``Player:Foo`` and
    ``player:Foo``), while the recording oracle reports the runtime class
    spelling (``EntityPlayer.Foo``).  Keep that normalization local to the
    reporting layer; it is evidence, not an implementation claim.
    """
    suffix = method.rsplit(".", 1)[-1]
    total = 0
    section = usage.get("engine_methods_by_observed_receiver", {})
    for values in section.values() if isinstance(section, dict) else []:
        if not isinstance(values, dict):
            continue
        for name, count in values.items():
            if str(name).rsplit(":", 1)[-1] == suffix:
                total += int(count) if isinstance(count, (int, float)) else 0
    return total


def blocker_record(frontier: dict[str, Any], usage: dict[str, Any]) -> dict[str, Any] | None:
    blocker = frontier.get("blocker")
    if not isinstance(blocker, dict) or not isinstance(blocker.get("name"), str):
        return None
    name = blocker["name"]
    operations = frontier.get("order", [])
    blocker_index = next(
        (index for index, event in enumerate(operations)
         if isinstance(event, dict) and event.get("name") == name and event.get("kind") == "unsupported"),
        None,
    )
    evidence = []
    if blocker_index is not None:
        evidence = operations[max(0, blocker_index - 2): blocker_index + 1]
    return {
        "name": name,
        "classification": "pending",
        "reason": blocker.get("reason", "unsupported"),
        "source": blocker.get("source"),
        "line": blocker.get("line"),
        "args": blocker.get("args", []),
        "usage": {
            "static_receiver_method_count": method_usage(usage, name),
            "frontier_occurrences": 1 if blocker_index is not None else 0,
        },
        "evidence": {
            "oracle_stage": frontier.get("raw", {}).get("stage"),
            "operations": evidence,
            "verification_level": "host_only",
        },
        "switch": {
            "status": "unresolved",
            "confidence": "unknown",
            "hardware_required": True,
        },
    }


def persistence_inventory() -> dict[str, Any]:
    """Report the old persistence blocker at two separate verification levels."""
    return {
        "LoadModData": {
            "host": {"status": "host_verified", "evidence": "runtime/tests/test-persistence-host.sh"},
            "durable": {"status": "hardware_required", "evidence": "no reboot/save-data console proof yet"},
        },
        "SaveModData": {
            "host": {"status": "host_verified", "evidence": "runtime/tests/test-persistence-host.sh"},
            "durable": {"status": "hardware_required", "evidence": "no reboot/save-data console proof yet"},
        },
        "hardware_persistence_sentinel": {
            "status": "pending",
            "verification_level": "hardware_required",
            "requires": "console save, process restart, and subsequent load verification",
        },
    }


def zhl_for(name: str, zhl: dict[str, list[dict[str, str]]]) -> list[dict[str, str]]:
    # Global Isaac methods can be represented by Class::Method in ZHL.
    return zhl.get(name, [])


def make_entry(kind: str, name: str, count: int, zhl: dict[str, list[dict[str, str]]], ts: dict[str, list[dict[str, str]]]) -> dict[str, Any]:
    evidence = zhl_for(name, zhl)
    typed = ts.get(name, [])
    return {
        "kind": kind,
        "name": name,
        "usage_count": count,
        "runtime": {"observed": False, "order": None},
        "evidence": {"zhl": evidence, "isaacscript": typed},
        "switch": {"rva": None, "confidence": "unknown", "status": "unresolved", "hardware_required": True},
    }


def apply_runtime(entries: list[dict[str, Any]], frontier: dict[str, Any]) -> None:
    by_name = {entry["name"]: entry for entry in entries}
    for index, event in enumerate(frontier["order"]):
        raw_names = set(flatten_strings(event)) if isinstance(event, (dict, list)) else {str(event)}
        names = set(raw_names)
        for name in raw_names:
            names.add(name.rsplit(".", 1)[-1])
        for name in names & by_name.keys():
            by_name[name]["runtime"] = {"observed": True, "order": index}


def build(usage: dict[str, Any], frontier_path: Path | None, zhl_dir: Path, isaacscript_dir: Path, isaacscript_rg_dir: Path) -> dict[str, Any]:
    zhl = parse_zhl(zhl_dir)
    ts = parse_typescript(isaacscript_dir)
    ts_rg = parse_typescript(isaacscript_rg_dir)
    for name, records in ts_rg.items():
        ts.setdefault(name, []).extend(records)
    frontier = frontier_data(frontier_path)
    entries = [make_entry(kind, name, count, zhl, ts) for kind, name, count in usage_entries(usage)]
    apply_runtime(entries, frontier)
    blocker = blocker_record(frontier, usage)
    if blocker and not any(entry["name"] == blocker["name"] for entry in entries):
        entries.append({
            "kind": "runtime_frontier_blocker",
            "name": blocker["name"],
            "usage_count": blocker["usage"]["static_receiver_method_count"],
            "runtime": {"observed": True, "order": blocker["evidence"]["operations"][-1].get("seq") if blocker["evidence"]["operations"] else None, "status": "unsupported"},
            "evidence": {"zhl": zhl_for(blocker["name"], zhl), "isaacscript": ts.get(blocker["name"], [])},
            "switch": blocker["switch"],
            "classification": blocker["classification"],
        })
    entries.sort(key=lambda item: (item["kind"], item["name"]))
    return {
        "schema_version": SCHEMA_VERSION,
        "sources": {
            "usage": portable_values(usage.get("source", {})),
            "oracle": source_path(frontier_path),
            "repentogon_zhl": source_path(zhl_dir),
            "isaacscript": [source_path(isaacscript_dir), source_path(isaacscript_rg_dir)],
        },
        "runtime": {
            "order": frontier["order"], "blocker": frontier["blocker"],
            "blocker_report": blocker,
            "previous_persistence": persistence_inventory(),
            "oracle_present": bool(frontier_path and frontier_path.is_file()),
            "verification_level": "host_only",
            "switch_readiness": "not_claimed",
        },
        "entries": entries,
        "summary": {
            "entry_count": len(entries),
            "runtime_observed": sum(1 for entry in entries if entry["runtime"]["observed"]),
            "zhl_evidenced": sum(1 for entry in entries if entry["evidence"]["zhl"]),
            "isaacscript_evidenced": sum(1 for entry in entries if entry["evidence"]["isaacscript"]),
            "unresolved": sum(1 for entry in entries if entry["switch"]["status"] == "unresolved"),
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--usage", type=Path, default=DEFAULT_USAGE)
    parser.add_argument("--frontier", "--oracle", dest="frontier", type=Path, default=DEFAULT_FRONTIER, help="recording-proxy runtime-frontier JSON")
    parser.add_argument("--zhl-dir", type=Path, default=DEFAULT_ZHL)
    parser.add_argument("--isaacscript-dir", type=Path, default=DEFAULT_ISAACSCRIPT)
    parser.add_argument("--isaacscript-repentogon-dir", type=Path, default=DEFAULT_ISAACSCRIPT_RG)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    usage = read_json(args.usage, {})
    result = build(usage, args.frontier, args.zhl_dir, args.isaacscript_dir, args.isaacscript_repentogon_dir)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {args.output} ({result['summary']['entry_count']} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
