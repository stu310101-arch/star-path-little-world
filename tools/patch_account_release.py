"""Prepare an account-site update while preserving the deployed Godot export.

Requires a matching public release manifest. Never deploys or alters the base.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
from pathlib import Path
import shutil

from package_admissions_site import package
from prepare_cloudflare_release import metadata, verify, write_json

ROOT = Path(__file__).resolve().parents[1]


def prepare(base: Path, live_manifest: Path, output: Path) -> dict:
    base, output = base.resolve(), output.resolve()
    if output.exists() or base == output or output.is_relative_to(base) or base.is_relative_to(output):
        raise ValueError("Use a new, separate release directory")
    previous = json.loads((base / "site/index.release.json").read_text(encoding="utf-8"))
    live = json.loads(live_manifest.read_text(encoding="utf-8"))
    if previous != live:
        raise ValueError("Base does not match the current public release; preserve newer game changes")
    verify(base / "site")
    config = json.loads((base / "wrangler.jsonc").read_text(encoding="utf-8"))
    if config["name"] != "star-path-little-world" or config["vars"]["FIREBASE_PROJECT_ID"] != "star-path-75457":
        raise ValueError("Not the independent StarPath service")
    if config["assets"]["directory"] != "./site" or config["main"] != "auth-worker.js":
        raise ValueError("Unexpected release layout")
    site = output / "site"
    site.mkdir(parents=True)
    for name in previous["files"]:
        if name.startswith("admissions/") or name in ("admissions-source.json", "index.service-worker.js"):
            continue
        target = site / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(base / "site" / name, target)
    for name in ("auth-worker.js", "wrangler.jsonc"):
        shutil.copyfile(base / name, output / name)
    admissions = package(ROOT / "admissions-site", ROOT / "admissions-site/out", site)
    if admissions["firebase_project_id"] != config["vars"]["FIREBASE_PROJECT_ID"]:
        raise ValueError("Account and auth Worker Firebase projects differ")
    old_worker = (base / "site/index.service-worker.js").read_text(encoding="utf-8")
    header, body = old_worker.split("\n", 1)
    if not header.startswith("const RELEASE = ") or not header.endswith(";"):
        raise ValueError("Unknown service worker manifest")
    worker_manifest = json.loads(header[len("const RELEASE = "):-1])
    worker_manifest["files"] = {p.relative_to(site).as_posix(): metadata(p)
                                for p in sorted(site.rglob("*")) if p.is_file()}
    (site / "index.service-worker.js").write_text(
        "const RELEASE = " + json.dumps(worker_manifest, separators=(",", ":")) + ";\n" + body,
        encoding="utf-8", newline="\n")
    previous["account_update"] = {
        "source_sha256": admissions["source_sha256"],
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "firebase_project_id": admissions["firebase_project_id"],
    }
    previous["files"] = {p.relative_to(site).as_posix(): metadata(p)
                         for p in sorted(site.rglob("*")) if p.is_file()}
    write_json(site / "index.release.json", previous)
    preserved = [name for name in live["files"] if not name.startswith("admissions/")
                 and name not in ("admissions-source.json", "index.service-worker.js")]
    if not all(previous["files"].get(name) == live["files"][name] for name in preserved):
        raise ValueError("Game content changed in an account-only update")
    report = {**verify(site), "account_update": previous["account_update"],
              "preserved_game_files": len(preserved), "auth_worker_unchanged": True,
              "rules_sha256": metadata(ROOT / "admissions-site/firestore.rules")["sha256"]}
    write_json(output / "verification.json", report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", required=True, type=Path)
    parser.add_argument("--live-manifest", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.base, args.live_manifest, args.output), indent=2))
