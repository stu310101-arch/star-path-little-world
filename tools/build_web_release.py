"""Reproduce the single-threaded Web export, deferred packs and Pages package.

Requires Godot 4.7.2 and matching templates, Python/NumPy, and Node 24+.
Does not publish or push. Run from any directory; logs go into build/.
"""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=shutil.which("godot_console") or shutil.which("godot"))
    parser.add_argument("--node", default=shutil.which("node"), help="Node 24+ for lossless Web resource compression")
    parser.add_argument("--rebuild-world", action="store_true")
    parser.add_argument("--local-only", action="store_true", help="Keep publication files untouched; produce build/web and _site for localhost only")
    args = parser.parse_args()
    if not args.godot:
        parser.error("Pass --godot with the installed Godot 4.7.2 console executable")
    if not args.node:
        parser.error("Pass --node with Node 24+ or put it on PATH")
    version = subprocess.check_output([args.godot, "--version"], text=True).strip()
    if not version.startswith("4.7.2.stable."):
        raise RuntimeError(f"Expected project/template version 4.7.2.stable, got {version}")
    build = ROOT / "build"
    web = build / "web"
    web.mkdir(parents=True, exist_ok=True)

    def run(label: str, command: list[str]) -> None:
        print(label, flush=True)
        environment = dict(os.environ, PYTHONIOENCODING="utf-8")
        result = subprocess.run(command, cwd=ROOT, env=environment, text=True, encoding="utf-8", errors="replace", stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (build / f"web-{label}.log").write_text(result.stdout, encoding="utf-8")
        if result.returncode or re.search(r"SCRIPT ERROR|Parse Error|^ERROR:", result.stdout, re.M):
            print(result.stdout[-12000:])
            raise RuntimeError(f"{label} failed; see build/web-{label}.log")

    engine = [args.godot, "--headless", "--path", str(ROOT / "game")]
    run("avatar", [sys.executable, "tools/build_web_avatar.py"])
    run("font", [sys.executable, "tools/build_web_font.py"])
    run("import", engine + ["--editor", "--import"])
    if args.rebuild_world:
        run("generate", engine + ["--script", "res://tools/build_streaming_world.gd"])
    inventory = build / "web-pack-dependencies.json"
    run("dependencies", engine + ["--script", "res://tools/collect_web_pack_dependencies.gd", "--", str(inventory)])
    isolated = build / "pack-validation-empty"
    isolated.mkdir(exist_ok=True)
    # Stamp mobile first; desktop's stamp also covers the full mobile set.
    for preset, output, label in (("Web Mobile", web / "mobile", "mobile"), ("Web", web, "desktop")):
        output.mkdir(parents=True, exist_ok=True)
        run(label + "-export", engine + ["--editor", "--export-release", preset, str(output / "index.html")])
        run(label + "-resource-compression", [sys.executable, "tools/recompress_web_resources.py", str(output / "index.pck"), "--node", args.node])
        run(label + "-split", [sys.executable, "tools/split_web_packs.py", "--source", str(output / "index.pck"), "--dependencies", str(inventory), "--output", str(output)])
        run(label + "-validate-packs", [args.godot, "--headless", "--audio-driver", "Dummy", "--path", str(isolated), "--main-pack", str(output / "index.pck"), "--script", str(ROOT / "game/tools/validate_web_packs.gd"), "--", str(output), str(inventory)])
        run(label + "-boot-delivery", [sys.executable, "tools/prepare_web_delivery.py", "--web-dir", str(output)])
        run(label + "-training-games", [sys.executable, "tools/package_training_games.py", "--web-dir", str(output)])
        run(label + "-notices", [sys.executable, "tools/package_web_notices.py", "--godot-bin", args.godot, "--web-dir", str(output)])
        run(label + "-platform", [sys.executable, "tools/prepare_web_platform.py", "inject", "--web-dir", str(output)])
        run(label + "-stamp", [sys.executable, "tools/stamp_web_release.py", "--web-dir", str(output)])
    run("cache-worker", [sys.executable, "tools/prepare_web_platform.py", "worker", "--web-dir", str(web)])
    package = "build/local-web-package" if args.local_only else "deploy/github-pages"
    run("prepare", [sys.executable, "deploy/github-pages/package.py", "prepare", "--source", str(web), "--package", package])
    run("assemble", [sys.executable, "deploy/github-pages/package.py", "assemble", "--package", package, "--output", "_site"])
    print("Exported, split, stamped and assembled. Validate localhost before committing/pushing.")


if __name__ == "__main__":
    main()
