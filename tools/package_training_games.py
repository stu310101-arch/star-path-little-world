"""Package the training-room browser games without loading them at world startup."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "index.training-games.js"
MANIFEST = "index.training-games.json"
SOURCE = ROOT / "game/web_games"
ADAPTER = ROOT / "tools/training_computer_games.js"


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def package(folder: Path, source: Path = SOURCE, adapter: Path = ADAPTER) -> dict:
    folder = folder.resolve()
    source = source.resolve()
    html_path = folder / "index.html"
    html = html_path.read_text(encoding="utf-8")
    anchor = '<script src="index.js"></script>'
    tag = f'<script src="{SCRIPT}"></script>'
    if html.count(anchor) != 1:
        raise ValueError("Unknown HTML loader anchor")
    if not (source / "go/index.html").is_file():
        raise FileNotFoundError("Missing training-room Go source")
    paths = sorted(path for path in source.rglob("*") if path.is_file())
    outputs = {SCRIPT: adapter.read_bytes()}
    for path in paths:
        if not path.resolve().is_relative_to(source):
            raise ValueError("Game source escapes its folder")
        outputs["games/" + path.relative_to(source).as_posix()] = path.read_bytes()
    manifest = {"version": 1, "games": {"go": "games/go/index.html"}, "files": {
        name: {"bytes": len(payload), "sha256": digest(payload)} for name, payload in outputs.items()
    }}
    html = re.sub(r"\n?[\t ]*" + re.escape(tag), "", html)
    html = html.replace(anchor, anchor + "\n\t\t" + tag)
    for name, payload in outputs.items():
        target = folder / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
    (folder / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    html_path.write_text(html, encoding="utf-8", newline="\n")
    verify(folder, source, adapter)
    return manifest


def verify(folder: Path, source: Path = SOURCE, adapter: Path = ADAPTER) -> list[str]:
    folder = folder.resolve()
    manifest = json.loads((folder / MANIFEST).read_text(encoding="utf-8"))
    expected = {SCRIPT: adapter.read_bytes()}
    expected.update({"games/" + path.relative_to(source).as_posix(): path.read_bytes()
                     for path in sorted(source.rglob("*")) if path.is_file()})
    if manifest.get("version") != 1 or manifest.get("games") != {"go": "games/go/index.html"} or set(manifest.get("files", {})) != set(expected):
        raise ValueError("Training-game manifest differs from source inventory")
    html = (folder / "index.html").read_text(encoding="utf-8")
    tag = f'<script src="{SCRIPT}"></script>'
    if html.count(tag) != 1 or html.index(tag) < html.index('<script src="index.js"></script>'):
        raise ValueError("Training-game bridge must load once after the engine script")
    for name, payload in expected.items():
        target = (folder / name).resolve()
        if not target.is_relative_to(folder) or target.read_bytes() != payload:
            raise ValueError(f"Training-game copy differs from source: {name}")
        if manifest["files"][name] != {"bytes": len(payload), "sha256": digest(payload)}:
            raise ValueError(f"Training-game metadata differs from source: {name}")
    return [MANIFEST, *expected]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-dir", type=Path, default=ROOT / "build/web")
    args = parser.parse_args()
    print(json.dumps(package(args.web_dir), indent=2))
