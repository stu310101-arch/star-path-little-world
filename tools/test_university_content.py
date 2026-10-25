"""Corpus acceptance checks for the university hall's fixed 2026-10-09 source.

Run: python tools/test_university_content.py
Checks the delivered JSON against the original document, not just its importer.
No network access is performed; URLs and their original reading caveats are
preserved, not claimed to have been newly fact-checked.
"""
from __future__ import annotations

from collections import Counter
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import re
import unittest

import import_university_content as importer

ROOT = Path(__file__).resolve().parents[1]
SOURCE_SHA256 = "c7cab137ece6a49713217d0b8367f67ef8f1266a665892914719f5ee60631cec"


def lines_without_layout(text: str) -> list[str]:
    """Ignore blank layout lines/indentation, retaining all text and punctuation."""
    return [line.strip() for line in text.splitlines() if line.strip()]


class UniversityContentTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.raw_bytes = importer.SOURCE.read_bytes()
        cls.raw = cls.raw_bytes.decode("utf-8-sig")
        cls.catalogue = json.loads(importer.OUTPUT.read_text(encoding="utf-8"))
        cls.cards = json.loads(importer.EDITORIAL.read_text(encoding="utf-8"))
        cls.entries = cls.catalogue["entries"]
        cls.by_id = {entry["id"]: entry for entry in cls.entries}
        cls.body, cls.bibliography = cls.raw.split("\n資料來源\n")

    def test_exact_supplied_source_copy(self):
        self.assertEqual(hashlib.sha256(self.raw_bytes).hexdigest(), SOURCE_SHA256)

    def test_schema_and_stable_ids(self):
        self.assertEqual(set(self.catalogue), {"schema_version", "source_date", "source_note", "regions", "sections", "entries"})
        self.assertEqual(self.catalogue["schema_version"], 1)
        self.assertEqual(self.catalogue["source_date"], "2026-10-09")
        self.assertEqual([entry["id"] for entry in self.entries], [f"{i:03}" for i in range(1, 139)])
        fields = {"id", "entity_id", "name", "aliases", "region", "campus_info", "summary", "highlights", "tags", "sections", "sources", "diorama", "art_profile"}
        for entry in self.entries:
            with self.subTest(entry=entry["id"]):
                self.assertEqual(set(entry) - {"research_update"}, fields)

    def test_all_690_body_sections_match_original_without_lost_text(self):
        # Rebuild each document block from the delivered public schema. This
        # catches missing qualifications, truncated paragraphs and cross-school
        # misassignment even if import and structural checks both succeed.
        original_blocks = re.findall(r"(?ms)^\d{3} .+?(?=^\d{3} |\Z)", self.body)
        self.assertEqual(len(original_blocks), 138)
        for entry, original in zip(self.entries, original_blocks):
            rebuilt = [f"{entry['id']} {entry['name']}"]
            self.assertEqual(set(entry["sections"]), {"location", "surroundings", "food", "reviews", "culture"})
            for index, section in enumerate(self.catalogue["sections"], 1):
                rebuilt.extend([f"{index}. {section['label']}", entry["sections"][section["id"]]])
            with self.subTest(entry=entry["id"]):
                self.assertEqual(lines_without_layout(original), lines_without_layout("\n".join(rebuilt)))
                self.assertEqual(entry["campus_info"], entry["sections"]["location"])

    def test_all_bibliography_titles_urls_notes_match_their_school(self):
        originals = re.findall(r"(?ms)^\d{3} .+?(?=^\d{3} |\Z)", self.bibliography)
        self.assertEqual(len(originals), 138)
        for entry, original in zip(self.entries, originals):
            rebuilt = [f"{entry['id']} {entry['name']}"]
            for source in entry["sources"]:
                self.assertEqual(set(source), {"title", "url", "note"})
                self.assertRegex(source["url"], r"^https?://\S+$")
                rebuilt.extend(["- " + source["title"], source["url"], source["note"]])
            with self.subTest(entry=entry["id"]):
                self.assertGreater(len(entry["sources"]), 0)
                self.assertEqual(lines_without_layout(original), lines_without_layout("\n".join(rebuilt)))

    def test_all_803_urls_and_global_caveats_are_preserved(self):
        original_urls = Counter(re.findall(r"https?://\S+", self.raw))
        actual_urls = Counter(re.findall(r"https?://\S+", self.catalogue["source_note"]))
        actual_urls.update(source["url"] for entry in self.entries for source in entry["sources"])
        self.assertEqual(sum(original_urls.values()), 803)
        self.assertEqual(original_urls, actual_urls)
        self.assertEqual(sum(len(entry["sources"]) for entry in self.entries), 801)
        introduction = self.body[:self.body.index("001 國立臺灣大學")]
        global_sources = self.bibliography[:self.bibliography.index("001 國立臺灣大學")]
        self.assertEqual(lines_without_layout(self.catalogue["source_note"]),
                         lines_without_layout(introduction + "\n資料來源\n" + global_sources))

    def test_school_entities_ndu_and_renamed_search_names(self):
        self.assertEqual(len({entry["entity_id"] for entry in self.entries}), 136)
        self.assertEqual({self.by_id[id]["entity_id"] for id in ["070", "071", "072"]}, {"ndu"})
        self.assertIn("馬偕醫學大學", self.by_id["064"]["aliases"])
        self.assertIn("國防醫學大學", self.by_id["073"]["aliases"])
        self.assertIn("高苑科技大學", self.by_id["101"]["aliases"])
        self.assertIn("遠東科技大學", self.by_id["108"]["aliases"])
        self.assertIn("大華科技大學", self.by_id["122"]["aliases"])
        self.assertIn("經國管理暨健康學院", self.by_id["133"]["aliases"])

    def test_regions_cover_all_entries_and_eight_school_galleries(self):
        expected = {"north": 70, "central": 26, "south": 35, "east": 5, "islands": 2}
        self.assertEqual(dict(Counter(entry["region"] for entry in self.entries)), expected)
        self.assertEqual({region["id"] for region in self.catalogue["regions"]}, set(expected))
        placed = []
        for region in self.catalogue["regions"]:
            entries = [entry for entry in self.entries if entry["region"] == region["id"]]
            galleries = [entries[index:index + 8] for index in range(0, len(entries), 8)]
            for gallery in galleries:
                self.assertTrue(1 <= len(gallery) <= 8)
                placed.extend(entry["id"] for entry in gallery)
        self.assertEqual(sorted(placed), sorted(self.by_id))

    def test_editorial_cards_are_unique_brief_and_complete(self):
        self.assertEqual(len({entry["summary"] for entry in self.entries}), 138)
        for entry in self.entries:
            with self.subTest(entry=entry["id"]):
                self.assertTrue(10 <= len(entry["summary"]) <= 60)
                self.assertEqual(len(entry["highlights"]), 3)
                self.assertEqual(len(set(entry["highlights"])), 3)
                self.assertTrue(all(4 <= len(value) <= 30 for value in entry["highlights"]))
                self.assertGreaterEqual(len(entry["tags"]), 2)
                self.assertTrue(all(isinstance(value, str) and value for value in entry["tags"] + entry["aliases"]))
                self.assertEqual(set(entry["diorama"]), {"theme", "accent", "features"})
                self.assertIn(entry["diorama"]["theme"], {"urban", "woodland", "hills", "coast", "arts", "workshop"})
                self.assertRegex(entry["diorama"]["accent"], r"^#[0-9A-Fa-f]{6}$")
                self.assertEqual(len(entry["diorama"]["features"]), 3)
                self.assertNotIn("\ufffd", json.dumps(entry, ensure_ascii=False))

    def test_admissions_and_review_qualifications_remain_readable(self):
        self.assertIn("停招", self.by_id["038"]["sections"]["culture"])
        self.assertIn("臺北校區", self.by_id["058"]["campus_info"])
        self.assertIn("合校", self.by_id["055"]["campus_info"])
        self.assertIn("遠距", self.by_id["136"]["campus_info"])
        # These are experience summaries, never aggregate satisfaction ratings.
        for entry in self.entries:
            self.assertGreater(len(entry["sections"]["reviews"]), 30)
            self.assertNotIn("rating", entry)
            self.assertNotIn("score", entry)

    def test_rebuild_is_deterministic(self):
        rebuilt = importer.build_catalogue(self.raw, self.cards)
        self.assertEqual(self.catalogue, rebuilt)

    def test_every_art_module_has_the_correct_school_evidence(self):
        for entry in self.entries:
            with self.subTest(entry=entry["id"]):
                profile = entry["art_profile"]
                importer.validate_art_profile(profile, entry)
                self.assertEqual(profile, self.cards[entry["id"]]["art_profile"])
                cues = {cue["id"]: cue for cue in profile["source_cues"]}
                self.assertGreaterEqual(len({cue["feature"] for cue in cues.values()}), 3)
                for module in profile["modules"]:
                    for cue_id in module["cue_ids"]:
                        cue = cues[cue_id]
                        if cue.get("source_kind") == "official":
                            self.assertIn(module["label"], cue["statement"])
                            self.assertTrue(set(cue["source_urls"]) <= {s["url"] for s in entry["research_update"]["sources"]})
                            self.assertEqual(cue["reviewed_on"], entry["research_update"]["reviewed_on"])
                        else:
                            self.assertIn(cue["quote"], entry["sections"][cue["section"]])
                            self.assertIn(module["label"], cue["quote"])
                        self.assertNotIn(cue["feature"], {"校園", "校內", "學校", "特色"})

    def test_art_uses_substantial_distinct_silhouettes_for_representative_schools(self):
        expected = {
            "001": {"palm_avenue", "ntu_bell", "lake"},
            "003": {"lake", "farm_plots", "dairy_stall"},
            "006": {"terrace", "river", "bridge"},
            "009": {"thu_chapel", "farm_plots", "dairy_stall"},
            "020": {"coast", "hill", "ship"},
            "025": {"stage", "terrace", "gallery"},
            "056": {"hospital", "laboratory", "market"},
            "075": {"3d_printer", "laboratory", "workshop", "market"},
            "122": {"robot_cell", "digital_hub", "workshop"},
        }
        silhouettes = []
        for id, keys in expected.items():
            profile = self.by_id[id]["art_profile"]
            actual = {module["key"].removeprefix("component_") for module in profile["modules"]}
            self.assertTrue(keys <= actual, id)
            # Ignore color, positions and IDs: visual diversity must remain
            # visible in actual silhouettes, not a different seed or tiny shift.
            silhouettes.append((profile["display_variant"], tuple(sorted(actual))))
        self.assertEqual(len(set(silhouettes)), len(expected))
        self.assertEqual({e["art_profile"]["display_variant"] for e in self.entries}, importer.DISPLAY_VARIANTS)

    def test_art_transforms_fit_the_shared_module_contract_without_ground_overlap(self):
        manifest_path = ROOT / "art/UniversityHall/kit_manifest.json"
        meshes = json.loads(manifest_path.read_text(encoding="utf-8"))["modules"] if manifest_path.exists() else {}
        for entry in self.entries:
            boxes = []
            for module in entry["art_profile"]["modules"]:
                key = module["key"].removeprefix("component_")
                width, depth = ((1.2, .4) if key in {"palm_avenue", "river"} else
                                (1.0, .6) if key in {"lake", "coast", "hill", "terrace", "lawn", "farm_plots"} else (1.0, .5))
                x, y, z = module["position"]
                sx, sy, sz = module["scale"]
                angle = math.radians(module["rotation_y"])
                wx = abs(width * sx * math.cos(angle)) + abs(depth * sz * math.sin(angle))
                dz = abs(width * sx * math.sin(angle)) + abs(depth * sz * math.cos(angle))
                bounds = (x - wx / 2, z - dz / 2, x + wx / 2, z + dz / 2)
                with self.subTest(entry=entry["id"], module=key):
                    self.assertGreaterEqual(bounds[0], -2.25)
                    self.assertLessEqual(bounds[2], 2.25)
                    self.assertGreaterEqual(bounds[1], -.8)
                    self.assertLessEqual(bounds[3], .8)
                    # Bell and hill meshes are shorter than the maximum kit
                    # height. Use their authored height when enlarging them.
                    height = meshes.get(module["key"], {}).get("bounds_max", [0, 1.05, 0])[1]
                    self.assertLessEqual(y + height * sy, 1.25)
                    for old_key, old in boxes:
                        if entry["id"] == "006" and {key, old_key} == {"bridge", "river"}:
                            bridge = next(m for m in entry["art_profile"]["modules"] if m["key"] == "component_bridge")
                            self.assertGreaterEqual(bridge["position"][1], .05)
                            continue
                        gap_x = max(bounds[0], old[0]) - min(bounds[2], old[2])
                        gap_z = max(bounds[1], old[1]) - min(bounds[3], old[3])
                        self.assertGreaterEqual(max(gap_x, gap_z), .03 - 1e-8, f"{entry['id']}: {key}/{old_key}")
                boxes.append((key, bounds))

    def test_hero_landmarks_have_visible_scale_hierarchy(self):
        for id in ["001", "003", "006", "009", "020", "025", "056", "075"]:
            profile = self.by_id[id]["art_profile"]
            primary = profile["composition"]["primary_modules"]
            footprints = {}
            for module in profile["modules"]:
                key = module["key"].removeprefix("component_")
                width, depth = ((1.2, .4) if key in {"palm_avenue", "river"} else
                                (1.0, .6) if key in {"lake", "coast", "hill", "terrace", "lawn", "farm_plots"} else (1.0, .5))
                footprints[module["key"]] = width * module["scale"][0] * depth * module["scale"][2]
            # A large landmark occupies at least 1.7 times the plan area of
            # any support module. This rejects uniformly small scattered props.
            dominant = max(footprints[key] for key in primary)
            support = max(area for key, area in footprints.items() if key not in primary)
            self.assertGreaterEqual(dominant / support, 1.7, id)
            self.assertTrue(profile["composition"]["hierarchy_note"])

    def test_ntust_printing_equipment_is_an_explicit_official_addition(self):
        entry = self.by_id["075"]
        profile = entry["art_profile"]
        printer = next(m for m in profile["modules"] if m["key"] == "component_3d_printer")
        cue = next(c for c in profile["source_cues"] if c["id"] == printer["cue_ids"][0])
        self.assertEqual(cue["source_kind"], "official")
        self.assertIn("FDM", cue["statement"])
        self.assertIn("光固化", cue["statement"])
        self.assertNotIn("quote", cue)
        self.assertNotIn("section", cue)
        self.assertNotIn("component_robot_cell", {m["key"] for m in profile["modules"]})
        for mutate in [lambda c: c.update(source_urls=["https://unverified.example/printing"]),
                       lambda c: c.update(reviewed_on="2026-10-09"),
                       lambda c: c.update(quote=entry["sections"]["culture"], section="culture")]:
            broken = deepcopy(profile)
            mutate(next(c for c in broken["source_cues"] if c.get("source_kind") == "official"))
            with self.assertRaises(ValueError):
                importer.validate_art_profile(broken, entry)

    def test_campus_and_off_campus_cues_do_not_share_a_false_location_label(self):
        cues = {cue["feature"]: cue for cue in self.by_id["001"]["art_profile"]["source_cues"]}
        self.assertEqual(cues["椰林大道"]["context_scope"], "campus_landscape")
        self.assertEqual(cues["醉月湖"]["context_scope"], "campus_landscape")
        self.assertEqual(cues["公館有書店"]["context_scope"], "nearby_life")
        grapes = next(cue for cue in self.by_id["037"]["art_profile"]["source_cues"] if cue["feature"] == "葡萄")
        self.assertEqual(grapes["context_scope"], "regional_food")

    def test_actual_authored_kit_bounds_leave_reading_labels_clear(self):
        manifest = ROOT / "art/UniversityHall/kit_manifest.json"
        if not manifest.exists():
            self.skipTest("Authored kit must be built before checking its exact mesh bounds")
        result = importer.audit_art_geometry(self.catalogue)
        self.assertEqual(result["status"], "passed", result["violations"])
        self.assertEqual(result["checked_modules"], sum(len(entry["art_profile"]["modules"]) for entry in self.entries))
        self.assertLess(result["highest_world_y"], result["tag_label_y"])
        meshes = json.loads(manifest.read_text(encoding="utf-8"))["modules"]
        bell = next(m for m in self.by_id["001"]["art_profile"]["modules"] if m["key"] == "component_ntu_bell")
        bell_top = .88 + bell["position"][1] + meshes[bell["key"]]["bounds_max"][1] * bell["scale"][1]
        self.assertLessEqual(bell_top, result["tag_plaque_bottom_y"] - .03)

    def test_official_updates_have_separate_dates_and_do_not_replace_student_reviews(self):
        expected = {"001", "003", "006", "009", "020", "025", "056", "075"}
        self.assertEqual({entry["id"] for entry in self.entries if "research_update" in entry}, expected)
        for id in expected:
            entry = self.by_id[id]
            update = entry["research_update"]
            self.assertEqual(update["reviewed_on"], "2026-10-11")
            self.assertEqual(entry["art_profile"]["external_sources"], update["sources"])
            self.assertEqual(entry["art_profile"]["reviewed_on"], update["reviewed_on"])
            self.assertIn("不代表學生評價", update["note"])
            self.assertEqual(len(entry["highlights"]), 3)
            urls = {source["url"] for source in update["sources"]}
            self.assertTrue(urls)
            keys = {module["key"] for module in entry["art_profile"]["modules"]}
            for cue in entry["art_profile"]["research_cues"]:
                self.assertTrue(set(cue["source_urls"]) <= urls)
                self.assertTrue(set(cue["modules"]) <= keys)
            # Full student experiences are checked byte-for-byte against the
            # original corpus elsewhere; official marketing is separate here.
            self.assertNotIn("official", entry["sections"])
        self.assertEqual(self.catalogue["source_date"], "2026-10-09")

    def test_wrong_art_sources_unknown_components_and_nonfinite_transforms_fail(self):
        entry = self.by_id["001"]
        for mutate in [
            lambda p: p["source_cues"][0].update(quote="不在原始正文中的建築"),
            lambda p: p["source_cues"][0].update(feature="不存在的塔樓"),
            lambda p: p["modules"][0].update(key="component_random_castle"),
            lambda p: p["modules"][0].update(cue_ids=["wrong-school-cue"]),
            lambda p: p["modules"][0].update(scale=[float("nan"), 1, 1]),
            lambda p: p.update(display_variant="same_box_with_random_color"),
        ]:
            broken = deepcopy(entry["art_profile"])
            mutate(broken)
            with self.assertRaises(ValueError):
                importer.validate_art_profile(broken, entry)

    def test_missing_school_or_section_cannot_silently_import(self):
        without_section = self.raw.replace("1. 地理位置", "1. 未識別章節", 1)
        with self.assertRaises(ValueError):
            importer.build_catalogue(without_section, self.cards)
        without_school = self.raw.replace("138 臺灣警察專科學校", "139 臺灣警察專科學校", 1)
        with self.assertRaises(ValueError):
            importer.build_catalogue(without_school, self.cards)

    def test_misaligned_bibliography_and_missing_cards_fail(self):
        altered = self.body + "\n資料來源\n" + self.bibliography.replace("003 國立中興大學", "003 錯誤對應", 1)
        with self.assertRaises(ValueError):
            importer.build_catalogue(altered, self.cards)
        with self.assertRaises(ValueError):
            importer.build_catalogue(self.raw, {key: value for key, value in self.cards.items() if key != "003"})


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(UniversityContentTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if importer.REPORT.exists():
        report = json.loads(importer.REPORT.read_text(encoding="utf-8"))
        failed_names = {test._testMethodName for test, _ in result.failures + result.errors}
        report["checks"].update({
            "corpus_tests_passed": result.wasSuccessful(),
            "tests_run": result.testsRun,
            "test_failures": len(result.failures),
            "test_errors": len(result.errors),
            "original_body_preserved": "test_all_690_body_sections_match_original_without_lost_text" not in failed_names,
            "original_bibliography_preserved": "test_all_bibliography_titles_urls_notes_match_their_school" not in failed_names,
            "source_copy_verified_sha256": SOURCE_SHA256,
        })
        importer.write_json(importer.REPORT, report)
    raise SystemExit(0 if result.wasSuccessful() else 1)
