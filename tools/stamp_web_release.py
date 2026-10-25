"""Record one exported Web set and reject HTML/PCK/WASM size mismatches."""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import subprocess

from prepare_web_delivery import verify as verify_boot_delivery
from prepare_web_delivery import verify_background_budget
from package_training_games import verify as verify_training_games
from package_account_bridge import verify as verify_account_bridge

ROOT = Path(__file__).resolve().parents[1]
COUNSELING_TEXTURES = ("apricot_base", "fabric_normal", "fabric_rough", "joinery_base", "joinery_normal", "joinery_rough",
                       "linen_base", "oak_base", "oak_normal", "oak_rough", "sage_base")


def counseling_source_paths(root: Path = ROOT) -> list[Path]:
    folder = root / "game/assets/counseling_room"
    return [folder / name for name in ("counseling_room.glb", "counseling_room.glb.import", "layout.json", "import_materials.gd", "import_materials.gd.uid")] + [
        folder / "textures" / f"{name}.png{suffix}" for name in COUNSELING_TEXTURES for suffix in ("", ".import")
    ]


def source_digest(paths: list[Path], root: Path = ROOT) -> str:
    source_hash = hashlib.sha256()
    for path in paths:
        source_hash.update(path.relative_to(root).as_posix().encode())
        # Git normalizes source text line endings; binary scene bytes remain
        # exact. Keep the source ID stable across Windows and Linux checkouts.
        payload = path.read_bytes() if path.suffix in (".scn", ".res", ".glb", ".ttf", ".zip", ".png") else path.read_text(encoding="utf-8").encode("utf-8")
        source_hash.update(hashlib.sha256(payload).digest())
    return source_hash.hexdigest()


def digest(file: Path) -> str:
    with file.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def stamp(folder: Path) -> dict:
    html_path = folder / "index.html"
    html = html_path.read_text(encoding="utf-8")
    match = re.search(r"const GODOT_CONFIG\s*=\s*(\{[^\n]+\});", html)
    if not match:
        raise ValueError("Cannot identify Godot export configuration")
    config = json.loads(match[1])
    for name in ("index.pck", "index.wasm"):
        if config["fileSizes"][name] != (folder / name).stat().st_size:
            raise ValueError(f"HTML fileSizes do not match {name}; re-export the whole set")
    if config.get("experimentalVK", False) or config.get("gdextensionLibs", []):
        raise ValueError("Unexpected export variant")
    source_paths = sorted([
        path for subdir in ("scripts", "scenes", "generated/streaming", "generated/low", "generated/training_room", "assets/university_hall", "assets/admissions_room", "assets/discussion_garden", "assets/character/runtime", "assets/character/runtime_web", "data", "tools")
        for path in (ROOT / "game" / subdir).rglob("*")
        if path.is_file() and path.suffix in (".gd", ".tscn", ".scn", ".json", ".res", ".glb")
    ] + [ROOT / "game/project.godot", ROOT / "game/export_presets.cfg", ROOT / "tools/split_web_packs.py",
         ROOT / "tools/prepare_web_delivery.py", ROOT / "tools/web_boot_delivery.js",
         ROOT / "tools/web_background_packs.js", ROOT / "tools/package_training_games.py",
         ROOT / "tools/training_computer_games.js", ROOT / "tools/build_web_avatar.py",
         ROOT / "tools/package_account_bridge.py", ROOT / "tools/web_account_bridge.js",
         ROOT / "tools/recompress_web_resources.py", ROOT / "tools/recompress_web_resources.cjs",
         ROOT / "tools/build_web_release.py", ROOT / "deploy/github-pages/package.py"]
        + [ROOT / "tools" / name for name in ("build_web_font.py", "build_web_template.py", "prepare_web_platform.py", "web_platform.js", "web_resource_profile.js", "web_service_worker.js", "web_touch.js")]
        + [ROOT / "game/assets/fonts/NotoSansTC.ttf", ROOT / "game/assets/fonts/web/LittleWorldTC.ttf"]
        + [path for path in (ROOT / "game/assets/university_hall/textures").rglob("*.png") if path.is_file()]
        + counseling_source_paths()
        + [path for path in (ROOT / "game/assets/recommendation_room").rglob("*") if path.is_file() and path.suffix in (".glb", ".json", ".png", ".gd", ".import")]
        + [ROOT / "tools/build_recommendation_room.py"]
        + [ROOT / "tools/templates/little-world-web-4.7.2.zip"]
        + [path for path in (ROOT / "game/web_games").rglob("*") if path.is_file()])
    source_hash = source_digest(source_paths)
    build_id = "packs-" + source_hash[:16]
    marker = f'<meta name="little-world-build" content="{build_id}">'
    html = re.sub(r'<meta name="little-world-build"[^>]*>\n?', '', html)
    html = html.replace("</head>", marker + "\n\t</head>")
    html_path.write_text(html, encoding="utf-8", newline="\n")
    names = ["index.html", "index.js", "index.wasm", "index.pck"]
    names.extend(path.name for path in folder.glob('index.audio*.js'))
    names.extend(path.name for path in folder.glob('index*.png'))
    if (folder / "index.platform.js").is_file():
        names.extend(["index.platform.js", "index.resources.js", "index.touch.js"])
    if (folder / "index.webmanifest").is_file():
        names.append("index.webmanifest")
    if (folder / "index.delivery.json").is_file():
        names.extend(verify_boot_delivery(folder))
    if (folder / "index.training-games.json").is_file():
        names.extend(verify_training_games(folder))
    if (folder / "index.account.json").is_file():
        names.extend(verify_account_bridge(folder))
    pack_manifest = folder / "index.packs.json"
    if pack_manifest.is_file():
        verify_background_budget(folder)
        packs = json.loads(pack_manifest.read_text(encoding="utf-8"))
        names.append("index.packs.json")
        for pack in packs["packs"].values():
            name = pack["url"]
            target = (folder / name).resolve()
            if not target.is_relative_to(folder.resolve()) or target.stat().st_size != pack["bytes"] or digest(target) != pack["sha256"]:
                raise ValueError(f"Deferred pack does not match manifest: {name}")
            names.append(name)
    mobile_stamp = folder / "mobile/index.release.json"
    if mobile_stamp.exists():
        mobile = json.loads(mobile_stamp.read_text(encoding="utf-8"))
        for name, item in mobile["files"].items():
            path = folder / "mobile" / name
            if path.stat().st_size != item["bytes"] or digest(path) != item["sha256"]:
                raise ValueError("Mobile release differs from its stamp: " + name)
        names.extend("mobile/" + name for name in mobile["files"])
        names.append("mobile/index.release.json")
    files = {name: {"bytes": (folder / name).stat().st_size, "sha256": digest(folder / name)} for name in names}
    info = {
        "build_id": build_id,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": source_hash,
        "export": "Web release; Compatibility; single-threaded",
        "files": files,
    }
    (folder / "index.release.json").write_text(json.dumps(info, indent=2) + "\n", encoding="utf-8", newline="\n")
    return info


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-dir", type=Path, default=ROOT / "build/web")
    args = parser.parse_args()
    print(json.dumps(stamp(args.web_dir), indent=2))
