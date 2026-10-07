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

ROOT = Path(__file__).resolve().parents[1]


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
        path for subdir in ("scripts", "scenes", "generated/streaming", "generated/training_room", "assets/character/runtime", "data", "tools")
        for path in (ROOT / "game" / subdir).rglob("*")
        if path.is_file() and path.suffix in (".gd", ".tscn", ".scn", ".json", ".res", ".glb")
    ] + [ROOT / "game/project.godot", ROOT / "game/export_presets.cfg", ROOT / "tools/split_web_packs.py",
         ROOT / "tools/prepare_web_delivery.py", ROOT / "tools/web_boot_delivery.js",
         ROOT / "tools/web_background_packs.js"])
    source_hash = hashlib.sha256()
    for path in source_paths:
        source_hash.update(path.relative_to(ROOT).as_posix().encode())
        # Git normalizes source text line endings; binary scene bytes remain
        # exact. Keep the source ID stable across Windows and Linux checkouts.
        payload = path.read_bytes() if path.suffix in (".scn", ".res", ".glb") else path.read_text(encoding="utf-8").encode("utf-8")
        source_hash.update(hashlib.sha256(payload).digest())
    build_id = "packs-" + source_hash.hexdigest()[:16]
    marker = f'<meta name="little-world-build" content="{build_id}">'
    html = re.sub(r'<meta name="little-world-build"[^>]*>\n?', '', html)
    html = html.replace("</head>", marker + "\n\t</head>")
    html_path.write_text(html, encoding="utf-8", newline="\n")
    names = ["index.html", "index.js", "index.wasm", "index.pck"]
    if (folder / "index.delivery.json").is_file():
        names.extend(verify_boot_delivery(folder))
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
    files = {name: {"bytes": (folder / name).stat().st_size, "sha256": digest(folder / name)} for name in names}
    info = {
        "build_id": build_id,
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source_base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "source_sha256": source_hash.hexdigest(),
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
