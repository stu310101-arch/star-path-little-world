"""Copy source notices verbatim after a Godot Web export; no game scene is run."""
from __future__ import annotations

import argparse
import hashlib
import json
import mmap
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SOURCES = [
    ("Vincent van Gogh - The Starry Night (1889)", "game/assets/training_room/textures/ATTRIBUTION.md", "Van-Gogh-Starry-Night-Public-Domain.txt", "Public-domain painting reproduction used on the training-room wall and in its painting viewer.", "https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg"),
    ("Kenney City Kit Suburban 2.0", "game/assets/kenney/suburban/License.txt", "Kenney-City-Kit-Suburban-CC0.txt", "Kenney; user-supplied source pack. Red-roof houses are project modifications.", "https://kenney.nl"),
    ("Kenney City Kit Commercial 2.1", "game/assets/kenney/commercial/License.txt", "Kenney-City-Kit-Commercial-CC0.txt", "Commercial buildings; original archive assets/source/urban/kenney-city-commercial.zip.", "https://kenney.nl/assets/city-kit-commercial"),
    ("Kenney Modular Buildings 2.1", "game/assets/kenney/modular/License.txt", "Kenney-Modular-Buildings-CC0.txt", "Source pack resources included by the current all_resources Web export.", "https://kenney.nl"),
    ("Kenney 3D Road Tiles", "game/assets/kenney/roads/License.txt", "Kenney-3D-Road-Tiles-CC0.txt", "Source pack resources included by the current all_resources Web export; current road surfaces are authored procedurally.", "https://kenney.nl"),
    ("Kenney Car Kit 3.1", "game/assets/urban/License.txt", "Kenney-Car-Kit-CC0.txt", "Sedan, hatchback-sports and SUV; original archive assets/source/urban/kenney-cars.zip.", "https://kenney.nl/assets/car-kit"),
    ("Kenney Watercraft Kit 2.1", "game/assets/scenery/Kenney-CC0.txt", "Kenney-Watercraft-Kit-CC0.txt", "Liner, tugboat and rowboat derivatives; original sources under assets/source/marine.", "https://kenney.nl/assets/watercraft-kit"),
    ("Quaternius base character", "game/assets/character/License.txt", "Quaternius-Character-CC0.txt", "User-supplied Blends-20260912T235614Z-1-001.zip; base character retained in art/Graduate. Graduate clothing and task animations are project modifications.", "See art/Graduate/README.md and SOURCE_LICENSE.txt in the source project."),
    ("Quaternius Animated Fish", "game/assets/scenery/Quaternius-CC0.txt", "Quaternius-Animated-Fish-CC0.txt", "Fish 1 and Fish 2 are normalized static derivatives; spherical-world motion is project-authored.", "https://opengameart.org/content/animated-fish"),
    ("Noto Sans TC", "game/assets/fonts/OFL.txt", "Noto-Sans-TC-OFL.txt", "Embedded font metadata identifies Adobe, copyright 2014-2021, Reserved Font Name Source; accompanying SIL OFL 1.1 text is copied without editing.", "Font source file: game/assets/fonts/NotoSansTC.ttf; local font folder does not record a download URL."),
]


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def read_engine_notices(godot: Path) -> dict:
    # Engine-only metadata query in an isolated empty project. It cannot load
    # the user's world, assets, editor plugins or rendering workload.
    with tempfile.TemporaryDirectory(prefix="little-world-notices-") as raw:
        folder = Path(raw)
        (folder / "project.godot").write_text('config_version=5\n', encoding="utf-8")
        script = '''extends SceneTree
func _initialize() -> void:
    var result: Dictionary = {"version":Engine.get_version_info(),"license":Engine.get_license_text(),"third_party_licenses":Engine.get_license_info(),"copyright":Engine.get_copyright_info()}
    var output: FileAccess = FileAccess.open(OS.get_cmdline_user_args()[0],FileAccess.WRITE)
    output.store_string(JSON.stringify(result,"\\t"))
    output.close()
    quit()
'''
        (folder / "export_notices.gd").write_text(script, encoding="utf-8")
        target = folder / "engine-notices.json"
        process = subprocess.run(
            [str(godot), "--headless", "--path", str(folder), "--script", "res://export_notices.gd", "--", str(target)],
            capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=30,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        if process.returncode or not target.is_file() or "SCRIPT ERROR:" in process.stdout + process.stderr:
            raise RuntimeError("Godot notice extraction failed: " + process.stdout + process.stderr)
        return json.loads(target.read_text(encoding="utf-8"))


def pck_metadata(path: Path) -> dict:
    with path.open("rb") as stream:
        header = stream.read(20)
        magic, pack_version, major, minor, patch = struct.unpack("<5I", header)
        if magic != 0x43504447:
            raise ValueError("Unexpected Godot PCK header")
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as mapped:
            embedded = {
                name: mapped.find(prefix.encode("utf-8")) >= 0
                for name, prefix in {
                    "modular_buildings": "assets/kenney/modular",
                    "road_tiles": "assets/kenney/roads",
                    "font_OFL_already_in_pck": "assets/fonts/OFL.txt",
                }.items()
            }
    return {"pack_version": pack_version, "engine_version": [major, minor, patch], "embedded_resource_families": embedded}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-dir", type=Path, default=ROOT / "build/web")
    parser.add_argument("--godot-bin", type=Path, default=Path(os.environ.get("LOCALAPPDATA", "")) / "Microsoft/WinGet/Links/godot_console.exe")
    args = parser.parse_args()
    output = args.web_dir.resolve()
    if not (output / "index.pck").is_file() or not (output / "index.html").is_file():
        raise FileNotFoundError("Run the Godot Web export before packaging its notices.")
    metadata = pck_metadata(output / "index.pck")
    engine = read_engine_notices(args.godot_bin)
    installed = [int(engine["version"][field]) for field in ["major", "minor", "patch"]]
    if installed != metadata["engine_version"]:
        raise RuntimeError(f"Export engine {metadata['engine_version']} differs from notice source {installed}.")
    folder = output / "licenses"
    folder.mkdir(parents=True, exist_ok=True)
    manifest = {"web_export": metadata, "licenses": []}
    lines = [
        "STAR PATH / LITTLE WORLD - THIRD-PARTY NOTICES",
        "",
        "These notices accompany this Web distribution. Original license files",
        "are copied byte-for-byte from the verified local source project.",
        "",
    ]
    for family, source, filename, usage, origin in SOURCES:
        if family.startswith("Kenney Modular") and not metadata["embedded_resource_families"]["modular_buildings"]:
            continue
        if family == "Kenney 3D Road Tiles" and not metadata["embedded_resource_families"]["road_tiles"]:
            continue
        source_path = ROOT / source
        destination = folder / filename
        shutil.copyfile(source_path, destination)
        source_hash = digest(source_path)
        if digest(destination) != source_hash:
            raise RuntimeError("License copy verification failed: " + filename)
        declared = "SIL Open Font License 1.1" if family == "Noto Sans TC" else "CC0 1.0 (as declared in the original file)"
        lines.extend([family, "  Use: " + usage, "  Source: " + origin, "  License: " + declared, "  Original text: licenses/" + filename, ""])
        manifest["licenses"].append({"family": family, "source_file": source, "delivered_file": "licenses/" + filename, "sha256": source_hash, "copy_verified": True})
    (folder / "Godot-Engine-MIT.txt").write_text(engine["license"], encoding="utf-8")
    engine_lines = ["Godot engine bundled third-party license texts", "Metadata from the installed engine matching this PCK version.", ""]
    for title, text in sorted(engine["third_party_licenses"].items()):
        engine_lines.extend([title, "=" * len(title), text, ""])
    (folder / "Godot-Third-Party-Licenses.txt").write_text("\n".join(engine_lines), encoding="utf-8")
    (folder / "Godot-Copyright-Information.json").write_text(json.dumps(engine["copyright"], ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines.extend([
        "Godot Web engine", "  Version: " + str(engine["version"].get("string", installed)),
        "  Source: https://godotengine.org/", "  Engine license: licenses/Godot-Engine-MIT.txt",
        "  Engine-provided third-party texts: licenses/Godot-Third-Party-Licenses.txt",
        "  Engine-provided copyright metadata: licenses/Godot-Copyright-Information.json", "",
        "PROJECT-AUTHORED CONTENT AND DERIVATIVES", "",
        "World layout, buildings' foundations, paving, benches, dock details,",
        "botanical reserve geometry, graduate clothing and task animation edits",
        "are documented as authored or modified in this source project.",
        "Original scripts and editable Blender masters remain in the source project.", "",
        "Sakura blossom atlas", "  game/assets/scenery/SOURCES.md records that sakura-atlas.png was generated",
        "  with the image-generation tool on 2026-09-24 for this project.",
        "  It is project-generated artwork, not a downloaded asset declared CC0.",
        "  No CC0 dedication for the generated atlas is asserted here.", "",
        "Source records: game/assets/scenery/SOURCES.md, game/assets/ecology/SOURCES.md,",
        "game/assets/urban/SOURCES.md, game/assets/kenney/suburban-edited/SOURCES.md,",
        "and art/Graduate/README.md. This file inventories recorded provenance;",
        "it does not replace the original licenses or make a legal conclusion.", "",
        "Rebuild notices after every Web export:", "  python -X utf8 tools/package_web_notices.py", "",
    ])
    notices = output / "THIRD_PARTY_NOTICES.txt"
    notices.write_text("\n".join(lines), encoding="utf-8")
    manifest["godot_engine_version"] = engine["version"]
    manifest["notice_sha256"] = digest(notices)
    for name in ["Godot-Engine-MIT.txt", "Godot-Third-Party-Licenses.txt", "Godot-Copyright-Information.json"]:
        manifest["licenses"].append({"family": "Godot engine", "source": "Engine metadata API for matching exported engine version", "delivered_file": "licenses/" + name, "sha256": digest(folder / name)})
    (folder / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"ok": True, "web_dir": str(output), "license_files": len(manifest["licenses"]), "original_copies_verified": sum(row.get("copy_verified", False) for row in manifest["licenses"]), "engine_version_matches_export": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
