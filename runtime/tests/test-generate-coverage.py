#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path
import importlib.util

TOOL = Path(__file__).parents[1] / "tools/generate_coverage.py"
spec = importlib.util.spec_from_file_location("generate_coverage", TOOL)
coverage = importlib.util.module_from_spec(spec)
assert spec.loader
spec.loader.exec_module(coverage)


class CoverageGeneratorTest(unittest.TestCase):
    def test_sources_are_joined_and_unresolved_is_explicit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            usage = root / "usage.json"
            usage.write_text(json.dumps({"source": {"lua_files": 1}, "callbacks": {"MC_POST_UPDATE": 2}, "global_calls": {"Game": 3}, "isaac_methods": {"Spawn": 4}}))
            frontier = root / "frontier.json"
            frontier.write_text(json.dumps({"operations": [{"name": "Isaac.Spawn"}, "MC_POST_UPDATE"], "first_unsupported": {"kind": "missing_method", "name": "Foo"}}))
            zhl = root / "zhl"
            zhl.mkdir()
            (zhl / "Game.zhl").write_text('"aa":\n__thiscall Entity* Game::Spawn(unsigned int type);\n')
            ts = root / "ts"
            ts.mkdir()
            (ts / "game.d.ts").write_text("interface Game { readonly Spawn: (type: int) => Entity; }\n")
            result = coverage.build(json.loads(usage.read_text()), frontier, zhl, ts, root / "missing")
        self.assertEqual(result["summary"]["entry_count"], 4)
        spawn = next(entry for entry in result["entries"] if entry["name"] == "Spawn")
        self.assertTrue(spawn["runtime"]["observed"])
        self.assertTrue(spawn["evidence"]["zhl"])
        self.assertTrue(spawn["evidence"]["isaacscript"])
        self.assertEqual(spawn["switch"]["status"], "unresolved")
        self.assertTrue(spawn["switch"]["hardware_required"])
        self.assertEqual(result["runtime"]["blocker"]["name"], "Foo")
        self.assertEqual(result["runtime"]["blocker_report"]["classification"], "pending")
        self.assertFalse(Path(result["sources"]["oracle"]).is_absolute())
        self.assertFalse(any(Path(value).is_absolute() for value in coverage.flatten_strings(result["sources"])))

    def test_deterministic_order_and_missing_optional_inputs(self):
        usage = {"callbacks": {"B": 1, "A": 1}, "global_calls": {}, "isaac_methods": {}}
        result = coverage.build(usage, None, Path("/does/not/exist"), Path("/does/not/exist"), Path("/does/not/exist"))
        self.assertEqual([entry["name"] for entry in result["entries"]], ["A", "B"])
        self.assertFalse(result["runtime"]["oracle_present"])
        self.assertIsNone(result["runtime"]["blocker"])

    def test_frontier_blocker_is_explicit_and_persistence_is_split(self):
        usage = {
            "engine_methods_by_observed_receiver": {
                "colon": {"Player:AddCacheFlags": 37, "player:AddCacheFlags": 5},
            },
            "callbacks": {}, "global_calls": {}, "isaac_methods": {},
        }
        frontier = {
            "stage": "post_game_started_minimal_state",
            "status": "host_bootstrap_blocked",
            "first_unsupported": {
                "name": "EntityPlayer.AddCacheFlags", "reason": "missing_lua_api",
                "line": 2947, "source": "<modroot>/main.lua", "args": ["<table>", 4294967295],
            },
            "operations": [
                {"seq": 1, "name": "Game.GetNumPlayers", "kind": "call"},
                {"seq": 2, "name": "EntityPlayer.AddCacheFlags", "kind": "unsupported"},
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frontier.json"
            path.write_text(json.dumps(frontier))
            result = coverage.build(usage, path, Path("/missing"), Path("/missing"), Path("/missing"))
        report = result["runtime"]["blocker_report"]
        self.assertEqual(report["name"], "EntityPlayer.AddCacheFlags")
        self.assertEqual(report["classification"], "pending")
        self.assertEqual(report["usage"]["static_receiver_method_count"], 42)
        self.assertTrue(report["switch"]["hardware_required"])
        entry = next(e for e in result["entries"] if e["name"] == "EntityPlayer.AddCacheFlags")
        self.assertEqual(entry["runtime"]["status"], "host_tested")
        self.assertNotEqual(entry["switch"]["status"], "implemented")
        persistence = result["runtime"]["previous_persistence"]
        self.assertEqual(persistence["LoadModData"]["host"]["status"], "host_verified")
        self.assertEqual(persistence["LoadModData"]["durable"]["status"], "hardware_required")

    def test_implemented_frontier_endpoint_remains_visible(self):
        usage = {"callbacks": {}, "global_calls": {}, "isaac_methods": {}}
        frontier = {
            "operations": [{"seq": 1, "name": "EntityPlayer.AddCacheFlags",
                            "kind": "call", "args": [4294967295]}],
            "first_unsupported": {"name": "EntityPlayer.EvaluateItems",
                                  "reason": "missing_lua_api"},
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "frontier.json"
            path.write_text(json.dumps(frontier))
            result = coverage.build(usage, path, Path("/missing"),
                                    Path("/missing"), Path("/missing"))
        entry = next(e for e in result["entries"]
                     if e["name"] == "EntityPlayer.AddCacheFlags")
        self.assertTrue(entry["runtime"]["observed"])
        self.assertEqual(entry["runtime"]["status"], "host_tested")
        self.assertEqual(entry["runtime"]["verification_level"], "host_only")
        self.assertTrue(entry["switch"]["hardware_required"])
        self.assertEqual(result["runtime"]["blocker"]["name"],
                         "EntityPlayer.EvaluateItems")


if __name__ == "__main__":
    unittest.main()
