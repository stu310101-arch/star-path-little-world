"""Reject incomplete/stale authored room payloads without launching Godot."""
from __future__ import annotations

import hashlib
import fnmatch
import json
from pathlib import Path
import tempfile
import unittest

from build_windows_release import ACCOUNT_SCRIPTS, ADMISSIONS_LAYOUT, ADMISSIONS_MODEL, GARDEN_SCRIPTS, verify_admissions_export, verify_garden_export, COUNSELING_MODEL, COUNSELING_LAYOUT, COUNSELING_SCRIPTS, INTEREST_CATALOG, verify_counseling_export, RECOMMENDATION_SCRIPTS, verify_recommendation_export


class RecommendationExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.entries = {}
        for name in ('scenes/recommendation_room.tscn', *(f'scripts/{item}.gd' for item in RECOMMENDATION_SCRIPTS)):
            self.entries[name] = ('current ' + name).encode()
            self.write(name, self.entries[name])
        for folder in ('assets/recommendation_room', 'generated/low/recommendation'):
            layout, model = folder+'/layout.json', folder+'/recommendation_room.glb'
            self.entries[layout] = b'{"stations":["data","recommendations","compare"]}'
            self.write(layout, self.entries[layout])
            self.write(model, ('model '+folder).encode())
            target = '.godot/imported/'+('low' if 'low' in folder else 'full')+'.scn'
            self.entries[model+'.import'] = f'[remap]\npath="res://{target}"\n'.encode()
            self.entries[target] = ('import '+folder).encode()
            self.write(target, self.entries[target])
            self.write(str(Path(target).with_suffix('.md5')), f'source_md5="{hashlib.md5((self.game/model).read_bytes()).hexdigest()}"\n'.encode())

    def write(self, name, payload):
        path = self.game/name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)

    def test_both_variants_and_animation_code_have_provenance(self):
        report = verify_recommendation_export(self.entries, self.game)
        self.assertIn('generated/low/recommendation/recommendation_room.glb', report['recommendation_source_sha256'])
        self.assertIn('scripts/recommendation_orrery.gd', report['recommendation_export_sha256'])

    def test_stale_low_layout_fails_even_with_fresh_full_variant(self):
        self.entries['generated/low/recommendation/layout.json'] = b'old'
        with self.assertRaisesRegex(RuntimeError, 'layout differs'):
            verify_recommendation_export(self.entries, self.game)

    def test_changed_model_must_be_reimported(self):
        self.write('assets/recommendation_room/recommendation_room.glb', b'new design')
        with self.assertRaisesRegex(RuntimeError, 'Stale recommendation model import'):
            verify_recommendation_export(self.entries, self.game)

    def test_old_export_cannot_pass_with_fresh_source(self):
        self.entries['.godot/imported/low.scn'] = b'previous model'
        with self.assertRaisesRegex(RuntimeError, 'Stale recommendation model export'):
            verify_recommendation_export(self.entries, self.game)

    def test_animation_uid_alone_cannot_replace_runtime_code(self):
        self.entries.pop('scripts/recommendation_orrery.gd')
        self.entries['scripts/recommendation_orrery.gd.uid'] = b'uid://fixture'
        with self.assertRaisesRegex(RuntimeError, 'Only metadata'):
            verify_recommendation_export(self.entries, self.game)


class WindowsAdmissionsExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.entries = {"scenes/admissions_room.tscn": b"scene", ADMISSIONS_LAYOUT: b'{"schemaVersion":1}'}
        self.write(ADMISSIONS_LAYOUT, self.entries[ADMISSIONS_LAYOUT])
        self.write(ADMISSIONS_MODEL, b"current authored GLB")
        self.target = ".godot/imported/admissions_studio.glb-fixture.scn"
        self.entries[ADMISSIONS_MODEL + ".import"] = f'[remap]\npath="res://{self.target}"\n'.encode()
        self.entries[self.target] = b"current imported scene"
        self.write(self.target, self.entries[self.target])
        source_md5 = hashlib.md5((self.game / ADMISSIONS_MODEL).read_bytes()).hexdigest()
        self.write(str(Path(self.target).with_suffix(".md5")), f'source_md5="{source_md5}"\n'.encode())
        for script in ACCOUNT_SCRIPTS:
            source = f"scripts/{script}.gd"
            self.write(source, ("extends Node # " + script).encode())
            self.entries[source + ".remap"] = f'[remap]\npath="res://scripts/{script}.gdc"\n'.encode()
            self.entries[f"scripts/{script}.gdc"] = ("compiled " + script).encode()

    def write(self, name, value):
        path = self.game / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)

    def test_manifest_records_source_and_actual_exported_payloads(self):
        result = verify_admissions_export(self.entries, self.game)
        self.assertIn("admissions_camera_rig", result["account_source_sha256"])
        self.assertIn("admissions_furniture_interaction", result["account_source_sha256"])
        self.assertIn("account_terminal_frame", result["account_source_sha256"])
        self.assertEqual(result["admissions_source_sha256"][ADMISSIONS_MODEL], hashlib.sha256(b"current authored GLB").hexdigest())
        self.assertEqual(result["admissions_export_sha256"][self.target], hashlib.sha256(self.entries[self.target]).hexdigest())

    def test_missing_new_camera_code_cannot_pass_with_uid_only(self):
        del self.entries["scripts/admissions_camera_rig.gd.remap"]
        del self.entries["scripts/admissions_camera_rig.gdc"]
        self.entries["scripts/admissions_camera_rig.gd.uid"] = b"uid://fixture"
        with self.assertRaisesRegex(RuntimeError, "Only metadata"):
            verify_admissions_export(self.entries, self.game)

    def test_layout_must_match_current_metadata(self):
        self.entries[ADMISSIONS_LAYOUT] = b"old layout"
        with self.assertRaisesRegex(RuntimeError, "layout differs"):
            verify_admissions_export(self.entries, self.game)

    def test_changed_glb_requires_reimport(self):
        self.write(ADMISSIONS_MODEL, b"new authored GLB")
        with self.assertRaisesRegex(RuntimeError, "cache is stale"):
            verify_admissions_export(self.entries, self.game)

    def test_old_export_is_rejected_after_current_import(self):
        self.entries[self.target] = b"old room mesh"
        with self.assertRaisesRegex(RuntimeError, "current imported scene"):
            verify_admissions_export(self.entries, self.game)

    def test_remap_cannot_point_to_missing_model(self):
        del self.entries[self.target]
        with self.assertRaisesRegex(ValueError, "missing entry"):
            verify_admissions_export(self.entries, self.game)

    def test_all_export_presets_include_layout_and_authored_texture_dependencies(self):
        import re
        presets = (Path(__file__).resolve().parents[1] / "game/export_presets.cfg").read_text(encoding="utf-8")
        include_filters = re.findall(r'^include_filter="([^"]*)"', presets, re.MULTILINE)
        exclude_filters = re.findall(r'^exclude_filter="([^"]*)"', presets, re.MULTILINE)
        self.assertGreaterEqual(len(include_filters), 4)
        for include in include_filters:
            self.assertTrue(any(fnmatch.fnmatch(ADMISSIONS_LAYOUT, glob) for glob in include.split(",")))
        texture = "assets/admissions_room/admissions_studio_oak.png"
        for exclude in exclude_filters:
            self.assertFalse(any(fnmatch.fnmatch(texture, glob) for glob in exclude.split(",")))


class WindowsGardenExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.entries = {}
        self.write("assets/discussion_garden/layout.json", json.dumps({"zones": [{"device_model": "res://assets/discussion_garden/message_device_university.glb"}]}).encode())
        self.models = ("garden.glb", "garden_low.glb", "message_device_university.glb")
        for name in self.models:
            source = "assets/discussion_garden/" + name
            self.write(source, ("current " + name).encode())
            target = ".godot/imported/" + name + "-fixture.scn"
            self.entries[source + ".import"] = f'[remap]\npath="res://{target}"\n'.encode()
            self.entries[target] = ("imported " + name).encode()
            self.write(target, self.entries[target])
            digest = hashlib.md5((self.game / source).read_bytes()).hexdigest()
            self.write(str(Path(target).with_suffix(".md5")), f'source_md5="{digest}"\n'.encode())
        for script in GARDEN_SCRIPTS:
            source = f"scripts/{script}.gd"
            self.write(source, ("extends Node # " + script).encode())
            self.entries[source + ".remap"] = f'[remap]\npath="res://scripts/{script}.gdc"\n'.encode()
            self.entries[f"scripts/{script}.gdc"] = ("compiled " + script).encode()
        source = "shaders/discussion_water.gdshader"
        self.entries[source] = b"shader_type spatial;"
        self.write(source, self.entries[source])

    def write(self, name, value):
        path = self.game / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)

    def test_both_detail_levels_and_new_helpers_are_recorded(self):
        result = verify_garden_export(self.entries, self.game)
        for name in self.models:
            self.assertIn("assets/discussion_garden/" + name, result["garden_source_sha256"])
        self.assertIn("scripts/discussion_navigation.gd", result["garden_source_sha256"])
        self.assertIn("shaders/discussion_water.gdshader", result["garden_source_sha256"])

    def test_changed_minimum_art_requires_reimport(self):
        self.write("assets/discussion_garden/garden_low.glb", b"new minimum asset")
        with self.assertRaisesRegex(RuntimeError, "Stale garden import"):
            verify_garden_export(self.entries, self.game)

    def test_old_minimum_payload_is_rejected(self):
        self.entries[".godot/imported/garden_low.glb-fixture.scn"] = b"old minimum scene"
        with self.assertRaisesRegex(RuntimeError, "Stale garden export"):
            verify_garden_export(self.entries, self.game)

    def test_uid_only_cannot_stand_in_for_navigation_code(self):
        del self.entries["scripts/discussion_navigation.gd.remap"]
        del self.entries["scripts/discussion_navigation.gdc"]
        self.entries["scripts/discussion_navigation.gd.uid"] = b"uid://fixture"
        with self.assertRaisesRegex(RuntimeError, "Only metadata"):
            verify_garden_export(self.entries, self.game)

    def test_duplicate_extracted_textures_are_rejected(self):
        self.entries["assets/discussion_garden/garden_PalettePaper.png"] = b"obsolete duplicate"
        with self.assertRaisesRegex(RuntimeError, "Duplicate extracted garden texture"):
            verify_garden_export(self.entries, self.game)


class WindowsCounselingExportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.game = Path(self.temp.name)
        self.entries = {}
        for source in ("scenes/counseling_room.tscn", COUNSELING_LAYOUT, INTEREST_CATALOG,
                       *(f"scripts/{name}.gd" for name in COUNSELING_SCRIPTS)):
            self.entries[source] = ("current " + source).encode()
            self.write(source, self.entries[source])
        self.write(COUNSELING_MODEL, b"complete high detail room")
        self.target = ".godot/imported/counseling_room.glb-fixture.scn"
        self.entries[COUNSELING_MODEL + ".import"] = f'[remap]\npath="res://{self.target}"\n'.encode()
        self.entries[self.target] = b"current imported model"
        self.write(self.target, self.entries[self.target])
        digest = hashlib.md5((self.game / COUNSELING_MODEL).read_bytes()).hexdigest()
        self.write(str(Path(self.target).with_suffix(".md5")), f'source_md5="{digest}"\n'.encode())

    def write(self, name, value):
        path = self.game / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)

    def test_catalog_model_and_editor_are_in_the_delivered_manifest(self):
        result = verify_counseling_export(self.entries, self.game)
        self.assertIn(INTEREST_CATALOG, result["counseling_source_sha256"])
        self.assertIn("scripts/interest_panel.gd", result["counseling_export_sha256"])
        self.assertIn(self.target, result["counseling_export_sha256"])

    def test_stale_catalog_is_rejected(self):
        self.entries[INTEREST_CATALOG] = b"old catalog"
        with self.assertRaisesRegex(RuntimeError, "data differs"):
            verify_counseling_export(self.entries, self.game)

    def test_old_import_and_duplicate_textures_are_rejected(self):
        self.write(COUNSELING_MODEL, b"new model")
        with self.assertRaisesRegex(RuntimeError, "cache is stale"):
            verify_counseling_export(self.entries, self.game)
        self.entries["assets/counseling_room/counseling_room_Palette.png"] = b"duplicate"
        with self.assertRaisesRegex(RuntimeError, "Duplicate extracted"):
            verify_counseling_export(self.entries, self.game)


if __name__ == "__main__":
    unittest.main()
