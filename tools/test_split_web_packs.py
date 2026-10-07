"""Meaningful failure and dependency tests for the Web PCK splitter."""
import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from split_web_packs import Pack, closure, exported_entries, pack_dependency_closure, plan_pack, read_pack, split, write_pack


class SplitPackTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def write(self, entries):
        path = self.root / "full.pck"
        write_pack(path, entries, (4, 7, 2))
        return path

    def test_round_trip_preserves_paths_and_exact_bytes_with_one_alias_payload(self):
        values = {"assets/a.png": b"pixels" * 100, "assets/b.png": b"pixels" * 100, "scripts/c.gdc": b"code"}
        path = self.root / "test.pck"
        report = write_pack(path, values, (4, 7, 2))
        actual = read_pack(path)
        self.assertEqual(actual.engine, (4, 7, 2))
        self.assertEqual({k: bytes(v) for k, v in actual.entries.items()}, values)
        self.assertEqual(report["deduplicated_bytes"], 600)
        self.assertEqual(report["sha256"], hashlib.sha256(path.read_bytes()).hexdigest())

    def test_corrupt_payload_is_rejected(self):
        path = self.write({"a": b"valid payload"})
        data = bytearray(path.read_bytes())
        data[113] ^= 1
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "MD5 mismatch"):
            read_pack(path)

    def test_out_of_bounds_directory_is_rejected(self):
        path = self.write({"a": b"valid"})
        data = bytearray(path.read_bytes())
        struct.pack_into("<Q", data, 32, len(data) + 100)
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "out of bounds"):
            read_pack(path)

    def test_truncated_directory_record_is_rejected(self):
        path = self.write({"a": b"valid"})
        path.write_bytes(path.read_bytes()[:-1])
        with self.assertRaisesRegex(ValueError, "Truncated|count"):
            read_pack(path)

    def test_unsupported_pack_flags_are_rejected(self):
        path = self.write({"a": b"valid"})
        data = bytearray(path.read_bytes())
        struct.pack_into("<I", data, 20, 3)
        path.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "Unsupported"):
            read_pack(path)

    def test_unsafe_path_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            self.write({"../outside": b"valid"})

    def test_import_and_remap_destinations_are_required(self):
        entries = {"a.png.import": memoryview(b'[remap]\npath="res://.godot/imported/a.ctex"\n'),
                   ".godot/imported/a.ctex": memoryview(b"pixels")}
        self.assertEqual(exported_entries("res://a.png", entries), set(entries))
        del entries[".godot/imported/a.ctex"]
        with self.assertRaisesRegex(ValueError, "missing entry"):
            exported_entries("res://a.png", entries)

    def test_source_graph_cycles_are_safe_but_missing_records_fail(self):
        self.assertEqual(closure(["a"], {"a": ["b"], "b": ["a"]}), {"a", "b"})
        with self.assertRaisesRegex(ValueError, "no record"):
            closure(["a"], {"a": ["b"]})

    def test_pack_cycles_and_missing_prerequisites_fail(self):
        with self.assertRaisesRegex(ValueError, "Cyclic"):
            pack_dependency_closure("a", {"a": ["b"], "b": ["a"]}, {"a", "b"})
        with self.assertRaisesRegex(ValueError, "Missing"):
            pack_dependency_closure("a", {"a": ["b"]}, {"a"})

    def fixture(self):
        entries = {"project.binary": b"project", "world.scn": b"world", "code.gdc": b"code",
                   "avatar.scn": b"avatar", "room.scn": b"room", "a.ctex": b"same pixels",
                   "b.ctex": b"same pixels", "build_only.scn": b"unused build asset"}
        inventory = {"version": 1, "engine": {"major": 4, "minor": 7, "patch": 2}, "errors": [],
                     "groups": {"boot": ["res://world.scn"], "avatar": ["res://avatar.scn"], "room": ["res://room.scn"]},
                     "prerequisites": {"room": ["avatar"]},
                     "dependencies": {"res://world.scn": ["res://code.gdc"], "res://code.gdc": [],
                                      "res://avatar.scn": ["res://code.gdc", "res://a.ctex"],
                                      "res://room.scn": ["res://code.gdc", "res://b.ctex"],
                                      "res://a.ctex": [], "res://b.ctex": []}}
        return entries, inventory

    def test_shared_bytes_move_to_one_pack_with_explicit_readiness_dependencies(self):
        entries, inventory = self.fixture()
        contents, deps, resources, report = plan_pack(Pack((4, 7, 2), entries), inventory)
        self.assertEqual(set(contents["boot"]), {"project.binary", "world.scn", "code.gdc"})
        self.assertEqual(set(contents["shared"]), {"a.ctex", "b.ctex"})
        self.assertEqual(deps["avatar"], ["shared"])
        self.assertEqual(deps["room"], ["avatar", "shared"])
        self.assertEqual(resources["res://avatar.scn"], "avatar")
        self.assertEqual([row["path"] for row in report["omitted_entries"]], ["build_only.scn"])
        self.assertEqual(sum(len(v) for v in contents.values()), 7)

    def test_wrong_engine_inventory_is_rejected(self):
        entries, inventory = self.fixture()
        with self.assertRaisesRegex(ValueError, "different Godot"):
            plan_pack(Pack((4, 7, 1), entries), inventory)

    def test_full_indoor_dependency_cannot_leak_into_boot(self):
        entries, inventory = self.fixture()
        inventory["groups"]["training_room"] = inventory["groups"].pop("room")
        inventory["prerequisites"]["training_room"] = inventory["prerequisites"].pop("room")
        inventory["dependencies"]["res://world.scn"].append("res://room.scn")
        with self.assertRaisesRegex(ValueError, "[Ii]ndoor|training_room"):
            plan_pack(Pack((4, 7, 2), entries), inventory)

    def test_complete_split_records_identical_manifest_and_refuses_double_split(self):
        entries, inventory = self.fixture()
        inventory["groups"]["training_room"] = inventory["groups"].pop("room")
        inventory["prerequisites"]["training_room"] = inventory["prerequisites"].pop("room")
        source = self.write(entries)
        original_bytes = source.stat().st_size
        inventory_path = self.root / "dependencies.json"
        inventory_path.write_text(json.dumps(inventory), encoding="utf-8")
        web = self.root / "web"
        web.mkdir()
        (web / "index.html").write_text('const GODOT_CONFIG = {"fileSizes":{"index.pck":100}};\n', encoding="utf-8")
        report = split(source, inventory_path, web, self.root / "report.json")
        self.assertEqual(report["source_bytes"], original_bytes)
        boot = read_pack(web / "index.pck")
        self.assertEqual(bytes(boot.entries["data/web_packs.json"]), (web / "index.packs.json").read_bytes())
        manifest = json.loads((web / "index.packs.json").read_text())
        self.assertFalse(manifest["packs"]["training_room"]["startup"])
        self.assertTrue(manifest["packs"]["avatar"]["startup"])
        physical_paths = set(boot.entries)
        for row in manifest["packs"].values():
            path = web / row["url"]
            self.assertEqual(path.stat().st_size, row["bytes"])
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(), row["sha256"])
            data = read_pack(path)
            self.assertFalse(physical_paths.intersection(data.entries))
            physical_paths.update(data.entries)
        with self.assertRaisesRegex(ValueError, "already split"):
            split(web / "index.pck", inventory_path, web, self.root / "report2.json")


if __name__ == "__main__":
    unittest.main()
