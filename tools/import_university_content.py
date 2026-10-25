"""Build the university hall catalogue from the supplied document and edited cards.

Usage: python tools/import_university_content.py [--source /path/to/document.txt]
The source copy is kept byte-for-byte. School IDs come from the document, never
from names or generated sort order. The input is content, not executable code.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
from pathlib import Path
import re
import shutil
from collections import Counter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "content/universities/source-20261009.txt"
EDITORIAL = ROOT / "content/universities/editorial.json"
OUTPUT = ROOT / "game/data/universities.json"
REPORT = ROOT / "deliverables/university-hall/content-report.json"
REGIONS = [
    {"id": "north", "label": "北部"},
    {"id": "central", "label": "中部"},
    {"id": "south", "label": "南部"},
    {"id": "east", "label": "東部"},
    {"id": "islands", "label": "離島"},
]
SECTIONS = [
    {"id": "location", "label": "地理位置"},
    {"id": "surroundings", "label": "附近介紹"},
    {"id": "food", "label": "特色美食介紹"},
    {"id": "reviews", "label": "學生評論"},
    {"id": "culture", "label": "校園風氣"},
]
ACCENTS = {"urban": "#C88657", "woodland": "#719A70", "hills": "#7E9674",
           "coast": "#589DAE", "arts": "#B18192", "workshop": "#C49B59"}
DISPLAY_VARIANTS = {"long_table", "corner_cabinet", "stepped_case", "island_case", "open_stage", "twin_pedestal", "workbench", "arc_cabinet"}
ART_MODULES = {"component_" + name for name in (
    "palm_avenue tree_grove lake river coast hill terrace lawn farm_plots bridge academic_block historic_hall chapel library gallery stage hospital laboratory workshop hangar track market station food_stall robot_cell digital_hub dormitory museum ship tea_pavilion sculpture fashion_studio thu_chapel ntu_bell dairy_stall 3d_printer"
).split()}
ART_CONTEXTS = {"campus_landscape", "campus_life", "nearby_life", "learning_symbol", "campus_food", "regional_food", "mixed_context"}
HEADING = re.compile(r"^(\d{3}) (.+)$", re.MULTILINE)
SECTION_HEADING = re.compile(r"^([1-5])\. (.+)$", re.MULTILINE)
URL = re.compile(r"https?://\S+")
EXPECTED_IDS = [f"{number:03d}" for number in range(1, 139)]


def blocks(text: str) -> tuple[str, list[tuple[str, str, str]]]:
    headings = list(HEADING.finditer(text))
    if not headings:
        raise ValueError("The document has no numbered school headings")
    result = []
    for index, match in enumerate(headings):
        end = headings[index + 1].start() if index + 1 < len(headings) else len(text)
        result.append((match[1], match[2].strip(), text[match.end():end].strip()))
    if [item[0] for item in result] != EXPECTED_IDS:
        raise ValueError("Expected exactly 001–138, once each, in source order")
    return text[:headings[0].start()].strip(), result


def parse_source(text: str) -> tuple[str, list[dict]]:
    # Split first: bibliography headings must never become duplicate schools.
    halves = re.split(r"(?m)^資料來源\s*$", text)
    if len(halves) != 2:
        raise ValueError("Expected exactly one standalone 資料來源 heading")
    introduction, bodies = blocks(halves[0])
    bibliography_intro, bibliography = blocks(halves[1])
    entries = []
    for (entry_id, name, body), (source_id, source_name, source_body) in zip(bodies, bibliography):
        if (entry_id, name) != (source_id, source_name):
            raise ValueError(f"Bibliography correspondence failed at {entry_id}")
        headings = list(SECTION_HEADING.finditer(body))
        if [(match[1], match[2]) for match in headings] != [
            (str(i + 1), section["label"]) for i, section in enumerate(SECTIONS)
        ]:
            raise ValueError(f"Unexpected section headings at {entry_id}")
        if body[:headings[0].start()].strip():
            raise ValueError(f"Unassigned body text at {entry_id}")
        sections = {}
        for index, (heading, section) in enumerate(zip(headings, SECTIONS)):
            end = headings[index + 1].start() if index + 1 < len(headings) else len(body)
            value = body[heading.end():end].strip()
            if not value:
                raise ValueError(f"Empty section {entry_id}/{section['id']}")
            sections[section["id"]] = value
        records = re.split(r"(?m)^- ", source_body)
        if records[0].strip():
            raise ValueError(f"Unassigned bibliography text at {entry_id}")
        sources = []
        for record in records[1:]:
            lines = [line.strip() for line in record.strip().splitlines() if line.strip()]
            if len(lines) < 2 or not URL.fullmatch(lines[1]):
                raise ValueError(f"Malformed source record at {entry_id}: {record}")
            if len(URL.findall(record)) != 1:
                raise ValueError(f"Expected one URL per source record at {entry_id}")
            sources.append({"title": lines[0], "url": lines[1], "note": "\n".join(lines[2:])})
        entries.append({"id": entry_id, "name": name, "sections": sections, "sources": sources})
    # Preserve the whole introduction, source caveats and the two roster URLs.
    return introduction + "\n\n資料來源\n\n" + bibliography_intro, entries


def validate_art_profile(profile: dict, entry: dict) -> None:
    """Reject unsupported source cues and malformed render instructions early."""
    id = entry["id"]
    if not isinstance(profile, dict) or profile.get("version") != 1:
        raise ValueError(f"Missing or unsupported art profile for {id}")
    if profile.get("display_variant") not in DISPLAY_VARIANTS:
        raise ValueError(f"Unknown display variant for {id}")
    composition = profile.get("composition", {})
    if any(not isinstance(composition.get(key), str) or not composition[key].strip() for key in ["id", "layout", "description"]):
        raise ValueError(f"Incomplete composition for {id}")
    palette = profile.get("palette", {})
    if any(not isinstance(palette.get(key), str) or not palette[key].strip() for key in ["display", "ground", "architecture", "detail", "note"]):
        raise ValueError(f"Incomplete palette for {id}")
    if not re.fullmatch(r"#[0-9a-fA-F]{6}", palette.get("accent", "")):
        raise ValueError(f"Invalid palette accent for {id}")
    cues = profile.get("source_cues", [])
    if not isinstance(cues, list) or len(cues) < 3:
        raise ValueError(f"At least three source cues required for {id}")
    cue_ids = set()
    for cue in cues:
        if not isinstance(cue, dict) or not cue.get("id") or cue["id"] in cue_ids:
            raise ValueError(f"Duplicate or missing art cue ID for {id}")
        cue_ids.add(cue["id"])
        feature = cue.get("feature")
        if cue.get("source_kind") == "official":
            statement = cue.get("statement")
            allowed_urls = {source["url"] for source in profile.get("external_sources", [])}
            urls, reviewed = cue.get("source_urls"), cue.get("reviewed_on", "")
            if not isinstance(statement, str) or not isinstance(feature, str) or len(feature) < 2 or feature not in statement:
                raise ValueError(f"Official art cue must explain its feature: {id}/{cue['id']}")
            if not isinstance(urls, list) or not urls or not set(urls) <= allowed_urls:
                raise ValueError(f"Official art cue needs identified external sources: {id}/{cue['id']}")
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", reviewed) or reviewed != profile.get("reviewed_on"):
                raise ValueError(f"Official art cue needs its own review date: {id}/{cue['id']}")
            if "section" in cue or "quote" in cue:
                raise ValueError(f"Official paraphrase must not impersonate document text: {id}/{cue['id']}")
        elif cue.get("source_kind", "document") == "document":
            section, quote = cue.get("section"), cue.get("quote")
            if section not in entry["sections"] or not isinstance(quote, str) or quote not in entry["sections"][section]:
                raise ValueError(f"Art cue must quote the original school section: {id}/{cue['id']}")
            if not isinstance(feature, str) or len(feature) < 2 or feature not in quote:
                raise ValueError(f"Art feature must appear in its quoted source: {id}/{cue['id']}")
        else:
            raise ValueError(f"Unknown art cue source kind: {id}/{cue['id']}")
        if cue.get("context_scope") not in ART_CONTEXTS or not cue.get("interpretation"):
            raise ValueError(f"Missing art cue context for {id}/{cue['id']}")
    modules = profile.get("modules", [])
    if not isinstance(modules, list) or not 3 <= len(modules) <= 6:
        raise ValueError(f"Expected 3–6 meaningful art modules for {id}")
    used_cues = set()
    for module in modules:
        if module.get("key") not in ART_MODULES:
            raise ValueError(f"Unknown renderable art module for {id}")
        for field in ["position", "scale"]:
            vector = module.get(field)
            if not isinstance(vector, list) or len(vector) != 3 or any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v) for v in vector):
                raise ValueError(f"Invalid art transform {id}/{field}")
        if any(value <= 0 or value > 4 for value in module["scale"]):
            raise ValueError(f"Invalid art scale for {id}")
        x, y, z = module["position"]
        if abs(x) > 2.25 or not 0 <= y <= 1.25 or abs(z) > .8:
            raise ValueError(f"Art origin outside the display bounds for {id}")
        rotation = module.get("rotation_y")
        if isinstance(rotation, bool) or not isinstance(rotation, (int, float)) or not math.isfinite(rotation) or abs(rotation) > 360:
            raise ValueError(f"Invalid art rotation for {id}")
        references = module.get("cue_ids")
        if not isinstance(references, list) or not references or any(cue not in cue_ids for cue in references):
            raise ValueError(f"Art module lacks source evidence for {id}")
        used_cues.update(references)
    if used_cues != cue_ids:
        raise ValueError(f"Unused art source cues for {id}")
    if not profile.get("representation_note"):
        raise ValueError(f"Art representation disclaimer missing for {id}")


def build_catalogue(source_text: str, editorial: dict) -> dict:
    source_note, entries = parse_source(source_text)
    if set(editorial) != set(EXPECTED_IDS):
        raise ValueError("Editorial cards must cover exactly all 138 entry IDs")
    for entry in entries:
        card = editorial[entry["id"]]
        required = {"region", "summary", "highlights", "tags", "aliases", "theme", "features", "art_profile"}
        if set(card) - {"research_update"} != required:
            raise ValueError(f"Unexpected editorial fields for {entry['id']}")
        if card["region"] not in {region["id"] for region in REGIONS}:
            raise ValueError(f"Unknown region for {entry['id']}")
        if card["theme"] not in ACCENTS:
            raise ValueError(f"Unknown diorama theme for {entry['id']}")
        if not isinstance(card["summary"], str) or not card["summary"].strip():
            raise ValueError(f"Missing summary for {entry['id']}")
        if len(card["highlights"]) != 3 or any(not s for s in card["highlights"]):
            raise ValueError(f"Expected three editorial highlights for {entry['id']}")
        entry["entity_id"] = "ndu" if entry["id"] in {"070", "071", "072"} else "university-" + entry["id"]
        entry["aliases"] = list(dict.fromkeys(card["aliases"]))
        entry["region"] = card["region"]
        # Full location context preserves every secondary campus for search and
        # explicitly retains renamed, merged and discontinued admissions notes.
        entry["campus_info"] = entry["sections"]["location"]
        entry["summary"] = card["summary"]
        entry["highlights"] = card["highlights"]
        entry["tags"] = card["tags"]
        entry["diorama"] = {"theme": card["theme"], "accent": ACCENTS[card["theme"]], "features": card["features"]}
        validate_art_profile(card["art_profile"], entry)
        entry["art_profile"] = card["art_profile"]
        if "research_update" in card:
            update = card["research_update"]
            if not isinstance(update, dict) or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", update.get("reviewed_on", "")) or not update.get("note") or not update.get("sources"):
                raise ValueError(f"Incomplete research update for {entry['id']}")
            for source in update["sources"]:
                if set(source) != {"title", "url", "note"} or not URL.fullmatch(source.get("url", "")):
                    raise ValueError(f"Malformed official supplement source for {entry['id']}")
            entry["research_update"] = update
    return {"schema_version": 1, "source_date": "2026-10-09", "source_note": source_note,
            "regions": REGIONS, "sections": SECTIONS, "entries": entries}


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def audit_art_geometry(catalogue: dict) -> dict:
    """Check the actual authored kit bounds, including asymmetric rotated parts."""
    manifest_path = ROOT / "art/UniversityHall/kit_manifest.json"
    if not manifest_path.exists():
        return {"status": "not_run", "reason": "Authored kit manifest is not available"}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    violations, checked, highest = [], 0, 0.0
    near_plaque = []
    for entry in catalogue["entries"]:
        previous = []
        for module in entry["art_profile"]["modules"]:
            checked += 1
            key = module["key"]
            model = manifest["modules"].get(key)
            if model is None:
                violations.append({"entry": entry["id"], "module": key, "reason": "missing kit module"})
                continue
            angle = math.radians(module["rotation_y"])
            c, s = math.cos(angle), math.sin(angle)
            position, scale = module["position"], module["scale"]
            points = []
            for corner in itertools.product(*zip(model["bounds_min"], model["bounds_max"])):
                x, y, z = [corner[i] * scale[i] for i in range(3)]
                points.append((position[0] + c*x + s*z, position[1] + y, position[2] - s*x + c*z))
            low = [min(point[i] for point in points) for i in range(3)]
            high = [max(point[i] for point in points) for i in range(3)]
            highest = max(highest, high[1])
            if high[1] + .88 > 1.94:
                near_plaque.append({"entry": entry["id"], "module": key,
                                    "world_top_y": round(high[1] + .88, 6),
                                    "world_z_range": [round(low[2] - .15, 6), round(high[2] - .15, 6)]})
            if low[0] < -2.25 or high[0] > 2.25 or low[2] < -.8 or high[2] > .8 or low[1] < -.001 or high[1] > 1.25:
                violations.append({"entry": entry["id"], "module": key, "reason": "outside local display bounds", "min": low, "max": high})
            for prior_key, prior_low, prior_high in previous:
                # This one intentional bridge uses y=.05, above the river's
                # .025 water surface, so the modules are not coplanar patches.
                if entry["id"] == "006" and {key, prior_key} == {"component_bridge", "component_river"}:
                    continue
                gap_x = max(low[0], prior_low[0]) - min(high[0], prior_high[0])
                gap_z = max(low[2], prior_low[2]) - min(high[2], prior_high[2])
                if max(gap_x, gap_z) < .03 - 1e-8:
                    violations.append({"entry": entry["id"], "module": key, "other": prior_key, "reason": "ground footprints need .03m separation"})
            previous.append((key, low, high))
    return {"status": "passed" if not violations else "failed", "kit_revision": manifest.get("revision"),
            "kit_manifest_sha256": hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
            "checked_modules": checked, "violations": violations, "highest_local_y": round(highest, 6),
            "model_root_y": .88, "highest_world_y": round(highest + .88, 6), "tag_label_y": 2.13,
            "tag_plaque_bottom_y": 1.97, "tag_plaque_z": -1.35,
            "near_tag_plaque_height": near_plaque,
            "plaque_note": "Modules are separated from the back plaque in Z; those within .03m of its bottom height or higher need a rendered camera check for visual tangencies, not only a center-height test.",
            "minimum_ground_gap": .03, "intentional_overlap": {"entry": "006", "modules": ["component_river", "component_bridge"], "bridge_base_y": .05},
            "scope": "Transformed authored module bounds; actual rendered appearance is verified separately in Godot."}


def make_report(catalogue: dict, source_bytes: bytes) -> dict:
    entries = catalogue["entries"]
    region_counts = Counter(entry["region"] for entry in entries)
    source_urls = [s["url"] for entry in entries for s in entry["sources"]]
    signatures = {}
    for entry in entries:
        profile = entry["art_profile"]
        signature = (profile["display_variant"], tuple(module["key"] for module in profile["modules"]))
        signatures.setdefault(signature, []).append(entry["id"])
    return {
        "schema_version": 1,
        "source_date": catalogue["source_date"],
        "source_sha256": hashlib.sha256(source_bytes).hexdigest(),
        "entries": len(entries),
        "school_entities": len({entry["entity_id"] for entry in entries}),
        "sections": sum(len(entry["sections"]) for entry in entries),
        "school_source_urls": len(source_urls),
        "roster_source_urls": len(URL.findall(catalogue["source_note"])),
        "all_source_urls": len(URL.findall(source_bytes.decode("utf-8-sig"))),
        "unique_summaries": len({entry["summary"] for entry in entries}),
        "highlights": sum(len(entry["highlights"]) for entry in entries),
        "region_counts": dict(region_counts),
        "gallery_counts_max_eight": {key: (count + 7) // 8 for key, count in region_counts.items()},
        "theme_counts": dict(Counter(entry["diorama"]["theme"] for entry in entries)),
        "art_profiles": len([entry for entry in entries if entry.get("art_profile")]),
        "art_display_counts": dict(Counter(entry["art_profile"]["display_variant"] for entry in entries)),
        "art_layout_counts": dict(Counter(entry["art_profile"]["composition"]["layout"] for entry in entries)),
        "art_module_counts": dict(Counter(module["key"] for entry in entries for module in entry["art_profile"]["modules"])),
        "art_source_cues": sum(len(entry["art_profile"]["source_cues"]) for entry in entries),
        "art_document_cues": sum(cue.get("source_kind", "document") == "document" for entry in entries for cue in entry["art_profile"]["source_cues"]),
        "art_official_cues": sum(cue.get("source_kind") == "official" for entry in entries for cue in entry["art_profile"]["source_cues"]),
        "art_shared_module_combinations": [ids for ids in signatures.values() if len(ids) > 1],
        "art_diversity_note": "共用模組依正文選擇；不使用隨機seed、顏色或微小位移湊唯一。相近教學場景允許相近組合，實際剪影另由Godot畫面驗證。",
        "art_geometry_audit": audit_art_geometry(catalogue),
        "officially_updated_short_cards": [entry["id"] for entry in entries if entry.get("research_update")],
        "official_supplement_urls": sum(len(entry.get("research_update", {}).get("sources", [])) for entry in entries),
        "region_policy": "北部：雙北、基隆、桃園、新竹；中部：苗栗、臺中、彰化、南投、雲林；南部：嘉義、臺南、高雄、屏東；東部：宜蘭、花蓮、臺東；離島：金門、澎湖。跨區學校依正文主要生活校區安排，其他校區保留於 campus_info 及 location。",
        "special_cases": {
            "ndu_shared_entity": ["070", "071", "072"],
            "historical_name_with_current_alias": ["064", "073"],
            "merged_or_renamed_history_retained": ["012", "055", "079", "101", "108", "122", "133"],
            "admissions_change_context_retained": ["038", "058"],
            "distance_learning": ["136", "137"],
        },
        "checks": {"import_complete": True},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Copy this supplied text document into the project first")
    args = parser.parse_args()
    if args.source and args.source.resolve() != SOURCE.resolve():
        SOURCE.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(args.source, SOURCE)
    source_bytes = SOURCE.read_bytes()
    catalogue = build_catalogue(source_bytes.decode("utf-8-sig"), json.loads(EDITORIAL.read_text(encoding="utf-8")))
    write_json(OUTPUT, catalogue)
    report = make_report(catalogue, source_bytes)
    write_json(REPORT, report)
    print(json.dumps({"output": str(OUTPUT), "entries": report["entries"], "entities": report["school_entities"],
                      "sources": report["all_source_urls"], "regions": report["region_counts"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
