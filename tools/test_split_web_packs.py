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
        entries["atrium.scn"] = b"university atrium"
        inventory["groups"]["university_hall"] = ["res://atrium.scn"]
        inventory["dependencies"]["res://atrium.scn"] = ["res://code.gdc"]
        inventory["prerequisites"]["university_hall"] = ["avatar"]
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
        self.assertFalse(manifest["packs"]["university_hall"]["startup"])
        self.assertEqual(manifest["resources"]["res://atrium.scn"], "university_hall")
        self.assertNotIn("atrium.scn", boot.entries)
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

    def test_university_mesh_dependency_cannot_leak_into_boot(self):
        entries, inventory = self.fixture()
        inventory["groups"]["university_hall"] = inventory["groups"].pop("room")
        inventory["prerequisites"]["university_hall"] = inventory["prerequisites"].pop("room")
        inventory["dependencies"]["res://world.scn"].append("res://room.scn")
        with self.assertRaisesRegex(ValueError, "university_hall"):
            plan_pack(Pack((4, 7, 2), entries), inventory)

    def test_recommendation_variants_are_optional_and_never_cross_load_geometry(self):
        entries, inventory = self.fixture()
        inventory["profiles"] = {"full":["avatar"], "low":["avatar"]}
        inventory["shared_on_demand"] = ["recommendation_room", "recommendation_low"]
        for key in inventory["shared_on_demand"]:
            source = "res://" + key + ".scn"
            entries[key + ".scn"] = key.encode()
            inventory["groups"][key] = [source]
            inventory["dependencies"][source] = ["res://code.gdc"]
        contents, deps, resources, _ = plan_pack(Pack((4,7,2),entries),inventory)
        low = pack_dependency_closure("recommendation_low",deps,set(contents))
        self.assertNotIn("recommendation_room",low)
        self.assertNotIn("recommendation_room.scn",contents["boot"])
        self.assertNotIn("recommendation_low.scn",contents["boot"])
        self.assertEqual(resources["res://recommendation_low.scn"],"recommendation_low")
        inventory["dependencies"]["res://world.scn"].append("res://recommendation_low.scn")
        with self.assertRaisesRegex(ValueError,"recommendation_low"):
            plan_pack(Pack((4,7,2),entries),inventory)

    def test_admissions_model_and_layout_are_deferred_together(self):
        entries, inventory = self.fixture()
        model = "res://assets/admissions_room/admissions_studio.glb"
        layout = "res://assets/admissions_room/layout.json"
        payload = ".godot/imported/admissions_studio.glb-test.scn"
        entries[model.removeprefix("res://") + ".import"] = f'[remap]\npath="res://{payload}"\n'.encode()
        entries[payload] = b"authored studio mesh and embedded materials"
        entries[layout.removeprefix("res://")] = b'{"schemaVersion":1,"stations":[]}'
        inventory["groups"]["admissions_room"] = [model, layout]
        inventory["prerequisites"]["admissions_room"] = ["avatar"]
        inventory["dependencies"].update({model: [], layout: []})
        contents, deps, resources, _ = plan_pack(Pack((4, 7, 2), entries), inventory)
        self.assertEqual(resources[model], "admissions_room")
        self.assertEqual(resources[layout], "admissions_room")
        self.assertEqual(deps["admissions_room"], ["avatar"])
        self.assertIn(payload, contents["admissions_room"])
        self.assertNotIn(payload, contents["boot"])
        inventory["dependencies"]["res://world.scn"].append(model)
        with self.assertRaisesRegex(ValueError, "admissions_room"):
            plan_pack(Pack((4, 7, 2), entries), inventory)

    def test_university_kit_keeps_shared_palette_deferred_and_omits_legacy_art(self):
        entries, inventory = self.fixture()
        prefix = "assets/university_hall/"
        roots = []
        palette = prefix + "textures/Walnut_base.png"
        palette_import = palette + ".import"
        palette_payload = ".godot/imported/Walnut_base.png-test.ctex"
        entries[palette_import] = f'[remap]\npath="res://{palette_payload}"\n'.encode()
        entries[palette_payload] = b"canonical university palette"
        inventory["dependencies"]["res://" + palette] = []
        for model in ("atrium", "gallery", "exhibit_kit", "feature_book"):
            source = prefix + model + ".glb"
            imported = ".godot/imported/" + model + ".glb-test.scn"
            entries[source + ".import"] = f'[remap]\npath="res://{imported}"\n'.encode()
            entries[imported] = (model + " mesh data").encode()
            roots.append("res://" + source)
            inventory["dependencies"]["res://" + source] = ["res://" + palette]
        entries[prefix + "layout.json"] = b'{"collision": []}'
        roots.append("res://" + prefix + "layout.json")
        inventory["dependencies"][roots[-1]] = []
        legacy = {prefix + "booth.glb.import", ".godot/imported/booth.glb-test.scn",
                  prefix + "theme_urban.glb.import", ".godot/imported/theme_urban.glb-test.scn",
                  prefix + "exhibit_kit_Walnut.png.import", ".godot/imported/exhibit_kit_Walnut.png-test.ctex"}
        entries.update({name: ("unused " + name).encode() for name in legacy})
        inventory["groups"]["university_hall"] = roots
        inventory["prerequisites"]["university_hall"] = ["avatar"]

        contents, deps, resources, report = plan_pack(Pack((4, 7, 2), entries), inventory)
        self.assertEqual(deps["university_hall"], ["avatar"])
        self.assertTrue(all(resources[path] == "university_hall" for path in roots))
        self.assertIn(palette_payload, contents["university_hall"])
        self.assertIn(palette_import, contents["university_hall"])
        self.assertEqual(sum(palette_payload in pack for pack in contents.values()), 1)
        self.assertFalse(set(contents["boot"]).intersection(contents["university_hall"]))
        shipped = set().union(*(set(pack) for pack in contents.values()))
        self.assertFalse(legacy.intersection(shipped))
        self.assertTrue(legacy.issubset({row["path"] for row in report["omitted_entries"]}))

    def test_single_full_counseling_room_is_deferred_for_both_profiles(self):
        entries, inventory = self.fixture()
        model = "res://assets/counseling_room/counseling_room.glb"
        layout = "res://assets/counseling_room/layout.json"
        payload = ".godot/imported/counseling_room-fixture.scn"
        entries[model.removeprefix("res://") + ".import"] = f'[remap]\npath="res://{payload}"\n'.encode()
        entries[payload] = b"one complete counseling room"
        entries[layout.removeprefix("res://")] = b'{"schemaVersion":1}'
        inventory["groups"]["counseling_room"] = [model, layout]
        inventory["profiles"] = {"full": ["avatar", "room"], "low": ["avatar"]}
        inventory["shared_on_demand"] = ["counseling_room"]
        inventory["dependencies"].update({model: [], layout: []})
        contents, dependencies, resources, _ = plan_pack(Pack((4, 7, 2), entries), inventory)
        self.assertEqual(resources[model], "counseling_room")
        self.assertIn(payload, contents["counseling_room"])
        self.assertNotIn(payload, contents["boot"])
        self.assertNotIn("counseling_room_low", contents)
        for roots in inventory["profiles"].values():
            installed = set().union(*(pack_dependency_closure(key, dependencies, set(contents)) for key in roots))
            self.assertNotIn("counseling_room", installed)
        source = self.write(entries)
        inventory_path = self.root / "dependencies.json"
        inventory_path.write_text(json.dumps(inventory), encoding="utf-8")
        web = self.root / "web"
        web.mkdir()
        (web / "index.html").write_text('const GODOT_CONFIG = {"fileSizes":{"index.pck":100}};\n', encoding="utf-8")
        split(source, inventory_path, web, self.root / "report.json")
        manifest = json.loads((web / "index.packs.json").read_text())
        self.assertEqual(manifest["shared_on_demand"], ["counseling_room"])
        self.assertFalse(manifest["packs"]["counseling_room"]["startup"])
        inventory["dependencies"]["res://world.scn"].append(model)
        with self.assertRaisesRegex(ValueError, "counseling_room"):
            plan_pack(Pack((4, 7, 2), entries), inventory)

    def test_optional_shared_room_cannot_reenter_installation_directly_or_by_dependency(self):
        entries, inventory = self.fixture()
        inventory["shared_on_demand"] = ["room"]
        inventory["profiles"] = {"full": ["avatar"], "low": ["avatar"]}
        contents, dependencies, _, _ = plan_pack(Pack((4, 7, 2), entries), inventory)
        self.assertIn("shared", contents)
        self.assertIn("shared", dependencies["room"])
        inventory["profiles"]["full"].append("room")
        with self.assertRaisesRegex(ValueError, "cannot be installed"):
            plan_pack(Pack((4, 7, 2), entries), inventory)
        inventory["profiles"]["full"].remove("room")
        inventory["dependencies"]["res://avatar.scn"].append("res://room.scn")
        with self.assertRaisesRegex(ValueError, "on-demand resource leaked"):
            plan_pack(Pack((4, 7, 2), entries), inventory)

    def garden_fixture(self):
        entries, inventory = self.fixture()
        prefix = "res://assets/discussion_garden/"
        texture = prefix + "shared_textures/paper.png"
        entries[texture.removeprefix("res://")] = b"shared exact paper pixels"
        inventory["dependencies"][texture] = []
        for name in ("garden", "garden_low", "message_device"):
            source = prefix + name + ".glb"
            payload = f".godot/imported/{name}-fixture.scn"
            entries[source.removeprefix("res://") + ".import"] = f'[remap]\npath="res://{payload}"\n'.encode()
            entries[payload] = (name + " unique geometry").encode()
            inventory["dependencies"][source] = [texture]
        layout = prefix + "layout.json"
        entries[layout.removeprefix("res://")] = b'{"zones":[]}'
        inventory["dependencies"][layout] = []
        inventory["groups"].update({"discussion_common": [prefix + "message_device.glb", layout],
                                    "discussion_garden": [prefix + "garden.glb"],
                                    "discussion_garden_low": [prefix + "garden_low.glb"]})
        inventory["prerequisites"].update({"discussion_common": ["avatar"],
                                           "discussion_garden": ["avatar", "discussion_common"],
                                           "discussion_garden_low": ["avatar", "discussion_common"]})
        return entries, inventory, prefix

    def test_minimum_garden_loads_common_devices_and_texture_without_standard_geometry(self):
        entries, inventory, prefix = self.garden_fixture()
        contents, deps, resources, report = plan_pack(Pack((4, 7, 2), entries), inventory)
        low = pack_dependency_closure("discussion_garden_low", deps, set(contents))
        self.assertIn("discussion_common", low)
        self.assertIn("avatar", low)
        self.assertIn("shared", low)
        self.assertNotIn("discussion_garden", low)
        self.assertEqual(resources[prefix + "garden_low.glb"], "discussion_garden_low")
        self.assertEqual(resources[prefix + "garden.glb"], "discussion_garden")
        available = set().union(*(set(contents[key]) for key in low))
        self.assertIn(".godot/imported/message_device-fixture.scn", available)
        self.assertIn("assets/discussion_garden/shared_textures/paper.png", available)
        self.assertNotIn(".godot/imported/garden-fixture.scn", available)

    def test_minimum_garden_and_common_assets_cannot_leak_into_boot(self):
        for path in ("garden_low.glb", "message_device.glb", "layout.json"):
            entries, inventory, prefix = self.garden_fixture()
            inventory["dependencies"]["res://world.scn"].append(prefix + path)
            with self.assertRaisesRegex(ValueError, "discussion_"):
                plan_pack(Pack((4, 7, 2), entries), inventory)

    def test_minimum_garden_cannot_pull_standard_geometry_through_shared_dependency(self):
        entries, inventory, prefix = self.garden_fixture()
        inventory["dependencies"][prefix + "garden_low.glb"].append(prefix + "garden.glb")
        with self.assertRaisesRegex(ValueError, "Standard garden geometry leaked"):
            plan_pack(Pack((4, 7, 2), entries), inventory)


if __name__ == "__main__":
    unittest.main()
