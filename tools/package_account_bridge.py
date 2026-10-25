"""Inject the lazy account host bridge into each desktop/mobile Web export."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = "index.account.js"
MANIFEST = "index.account.json"
ADAPTER = ROOT / "tools/web_account_bridge.js"


def package(folder: Path) -> dict:
    page = folder / "index.html"
    html = page.read_text(encoding="utf-8")
    anchor = '<script src="index.js"></script>'
    tag = f'<script src="{SCRIPT}"></script>'
    if html.count(anchor) != 1:
        raise ValueError("Unknown HTML loader anchor")
    html = re.sub(r"\n?[\t ]*" + re.escape(tag), "", html)
    payload = ADAPTER.read_bytes()
    manifest = {"version": 1, "host": "/admissions/host/", "files": {
        SCRIPT: {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}}}
    (folder / SCRIPT).write_bytes(payload)
    (folder / MANIFEST).write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    page.write_text(html.replace(anchor, anchor + "\n\t\t" + tag), encoding="utf-8", newline="\n")
    verify(folder)
    return manifest


def verify(folder: Path) -> list[str]:
    payload = ADAPTER.read_bytes()
    expected = {"version": 1, "host": "/admissions/host/", "files": {
        SCRIPT: {"bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}}}
    if json.loads((folder / MANIFEST).read_text(encoding="utf-8")) != expected:
        raise ValueError("Account bridge manifest differs from source")
    if (folder / SCRIPT).read_bytes() != payload:
        raise ValueError("Account bridge copy differs from source")
    html = (folder / "index.html").read_text(encoding="utf-8")
    tag = f'<script src="{SCRIPT}"></script>'
    if html.count(tag) != 1 or html.index(tag) < html.index('<script src="index.js"></script>'):
        raise ValueError("Account bridge must load once after the engine script")
    return [MANIFEST, SCRIPT]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--web-dir", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(package(args.web_dir), indent=2))
