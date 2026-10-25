"""Package verified recommendation candidates and an explicit editable-source set.

This command never builds or deploys. --dry-run performs the same input/hash
checks without creating the output directory. Private QA sessions are excluded.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import zipfile

from package_counseling_delivery import read_json, safe_file as check_delivery_file
from snapshot_admissions_source import read_snapshot

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT_FILES = ("firestore.rules", "firestore.indexes.json", "firebase.json", "INTEREST_DATA.md")
ART_FILES = ("RecommendationRoom.blend", "SOURCE_NOTES.md", "export-report.json")
ROOM_FILES = ("recommendation_room.glb", "recommendation_room.glb.import", "layout.json")
TEXTURES = ("oak_base.png", "joinery_base.png")
SCRIPTS = (
    "recommendation_room", "recommendation_protocol", "recommendation_panel", "recommendation_controller",
    "recommendation_diagnostics", "indoor_transition", "world", "world_hud", "account_session", "account_native_host",
    "account_terminal_frame", "forum_protocol", "progress_protocol", "interest_protocol", "resource_profile",
    "graphics_settings", "indoor_player", "admissions_camera_rig", "admissions_furniture_interaction",
    "university_hall", "university_hall_ui", "university_hall_space",
)
TOOLS = (
    "build_recommendation_room.py", "package_recommendation_delivery.py", "package_counseling_delivery.py",
    "snapshot_admissions_source.py", "web_account_bridge.js", "package_account_bridge.py",
    "package_admissions_site.py", "build_windows_release.py", "build_selectable_windows.py", "prepare_cloudflare_release.py",
    "serve_recommendation_candidate.py",
)


def sha_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_name(name: str) -> str:
    if not isinstance(name, str) or not name or PurePosixPath(name).is_absolute() or "\\" in name or ":" in name or any(ord(char) < 32 for char in name) or any(part in ("", ".", "..") for part in name.split("/")):
        raise ValueError("Unsafe delivery inventory path")
    return name


def safe_file(path: Path, base: Path) -> Path:
    base = base.resolve()
    try:
        relative = path.relative_to(base)
    except ValueError:
        raise ValueError("Input escapes delivery root") from None
    safe_name(relative.as_posix())
    for part in (path, *path.parents):
        if part == base:
            break
        if part.is_symlink() or (hasattr(part, "is_junction") and part.is_junction()):
            raise ValueError("Linked delivery inputs are not allowed")
    check_delivery_file(path, base)
    # Snapshots are source code and may contain synthetic test expressions;
    # actual private-key bodies must still never enter a binary/text patch.
    if path.suffix == ".patch" and re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", path.read_bytes().replace(b"\\n", b"\n")):
        raise ValueError("Private-key material rejected from source snapshot")
    return path


def inventory(folder: Path) -> dict[str, Path]:
    if not folder.is_dir() or folder.is_symlink() or (hasattr(folder, "is_junction") and folder.is_junction()):
        raise ValueError(f"Missing or linked input directory: {folder}")
    files = {}
    for path in sorted(folder.rglob("*")):
        if path.is_symlink() or (hasattr(path, "is_junction") and path.is_junction()):
            raise ValueError("Linked delivery inputs are not allowed")
        if path.is_file():
            files[path.relative_to(folder).as_posix()] = safe_file(path, folder)
    return files


def asset_inventory() -> dict[str, Path]:
    names = ["art/RecommendationRoom/" + name for name in ART_FILES]
    for folder in ("game/assets/recommendation_room", "game/generated/low/recommendation"):
        names.extend(folder + "/" + name for name in ROOM_FILES)
        names.extend(f"{folder}/textures/{name}{suffix}" for name in TEXTURES for suffix in ("", ".import"))
    names.extend("game/assets/recommendation_room/" + name for name in ("import_materials.gd", "import_materials.gd.uid"))
    # The generator reads these original full-size reused maps, not the low maps.
    names.extend("game/assets/counseling_room/textures/" + name for name in TEXTURES)
    names.extend("art/CounselingRoom/" + name for name in ("SOURCE_NOTES.md", "sources.json"))
    names.extend(f"game/scripts/{name}.gd{suffix}" for name in SCRIPTS for suffix in ("", ".uid"))
    names.extend(("game/scripts/recommendation_orrery.gd", "game/scenes/recommendation_room.tscn",
                  "game/scenes/world.tscn", "game/scenes/university_hall.tscn", "game/project.godot", "game/export_presets.cfg",
                  "game/data/world_layout.json", "game/data/districts.json", "game/data/universities.json"))
    if (ROOT / "game/scripts/recommendation_orrery.gd.uid").is_file():
        names.append("game/scripts/recommendation_orrery.gd.uid")
    names.extend("tools/" + name for name in TOOLS)
    names.extend(("docs/recommendation-room.md", "docs/recommendation-validation-20261025.json", "integrations/admissions/README.md",
                  "integrations/admissions/integration.patch", "integrations/admissions/source-manifest.json"))
    return {name: safe_file(ROOT / name, ROOT) for name in sorted(names)}


def check_hashes(files: dict[str, Path], expected: dict, sizes: dict | None = None) -> None:
    if not isinstance(expected, dict) or not expected:
        raise ValueError("Missing release hash inventory")
    for name, row in expected.items():
        safe_name(name)
        digest = row.get("sha256") if isinstance(row, dict) else row
        size = row.get("bytes") if isinstance(row, dict) else (sizes or {}).get(name)
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest) or name not in files or sha_file(files[name]) != digest:
            raise ValueError("Release hash mismatch: " + name)
        if size is not None and (not isinstance(size, int) or size != files[name].stat().st_size):
            raise ValueError("Release size mismatch: " + name)


def plan(windows: Path, cloudflare: Path, output: Path, stamp: str) -> dict:
    if not re.fullmatch(r"\d{8}", stamp):
        raise ValueError("Date must use YYYYMMDD")
    datetime.strptime(stamp, "%Y%m%d")
    windows, cloudflare, output = windows.absolute(), cloudflare.absolute(), output.absolute()
    if output.exists():
        raise ValueError("Output directory must be new; existing archives are never overwritten")
    if any(output.resolve().is_relative_to(source.resolve()) or source.resolve().is_relative_to(output.resolve()) for source in (windows, cloudflare)):
        raise ValueError("Output and candidate directories must be separate")
    native, web = inventory(windows), inventory(cloudflare)
    native_release = read_json(windows / "release.json")
    if set(native) != set(native_release["native_files"]) | {"release.json"} or not {"LittleWorld.exe", "LittleWorld.pck", "index.packs.json"} <= set(native):
        raise ValueError("Windows directory differs from its release inventory")
    if not isinstance(native_release.get("debug_candidate"), bool):
        raise ValueError("Windows release must declare whether it is a local debug candidate")
    if native_release["debug_candidate"] and "Start-Local-Candidate.ps1" not in native:
        raise ValueError("Local debug candidate requires its explicit launcher")
    check_hashes(native, native_release["native_files"], native_release.get("file_bytes"))
    sources = native_release.get("recommendation_source_sha256", {})
    if not sources:
        raise ValueError("Windows release lacks recommendation source provenance")
    check_hashes({name: safe_file(ROOT / "game" / safe_name(name), ROOT / "game") for name in sources}, sources)
    release = read_json(cloudflare / "site/index.release.json")
    expected_web = {"site/" + safe_name(name) for name in release["files"]} | {"site/index.release.json", "auth-worker.js", "wrangler.jsonc", "verification.json"}
    if set(web) != expected_web:
        raise ValueError("Cloudflare candidate differs from its release inventory")
    check_hashes(web, {"site/" + name: row for name, row in release["files"].items()})
    verification = read_json(cloudflare / "verification.json")
    if verification.get("passed") is not True or verification.get("build_id") != release["build_id"] or verification.get("auth_worker_sha256") != sha_file(web["auth-worker.js"]):
        raise ValueError("Cloudflare candidate lacks matching successful verification")
    firebase = read_json(cloudflare / "site/admissions/firebase-config.json")
    if set(firebase) - {"apiKey", "authDomain", "projectId", "appId", "storageBucket", "messagingSenderId", "measurementId"}:
        raise ValueError("Unexpected Firebase configuration fields")
    snapshot, _ = read_snapshot(ROOT / "integrations/admissions")
    admissions = read_json(cloudflare / "site/admissions-source.json")
    if admissions.get("source_base_commit") != snapshot["source_base_commit"] or admissions.get("source_files") != snapshot["working_tree_files"]:
        raise ValueError("Packaged admissions source differs from editable snapshot")
    rules = {name: safe_file(ROOT / "admissions-site" / name, ROOT / "admissions-site") for name in ACCOUNT_FILES}
    archives = {
        f"StarPath-Windows-Recommendations-{stamp}.zip": native,
        f"StarPath-Web-Recommendations-{stamp}.zip": web,
        f"Recommendation-Assets-{stamp}.zip": asset_inventory(),
    }
    return {"output": output, "archives": archives, "rules": rules,
            "hashes": {archive: {name: sha_file(path) for name, path in files.items()} for archive, files in archives.items()},
            "rule_hashes": {name: sha_file(path) for name, path in rules.items()},
            "provenance": {"build_id": release["build_id"], "windows_debug_candidate": native_release["debug_candidate"], "windows_manifest_sha256": sha_file(native["release.json"]),
                           "web_manifest_sha256": sha_file(web["site/index.release.json"]), "admissions_source_sha256": snapshot["source_sha256"],
                           "admissions_patch_sha256": snapshot["patch_sha256"]}}


def describe(selected: dict) -> dict:
    return {"dry_run": True, "output": str(selected["output"]), "archives": {
        name: {"files": len(files), "uncompressed_bytes": sum(path.stat().st_size for path in files.values())}
        for name, files in selected["archives"].items()}, "account_rules": list(selected["rules"]),
        "provenance": selected["provenance"], "release_hashes_verified": True, "writes_performed": False}


def archive(target: Path, files: dict[str, Path], expected_hashes: dict[str, str]) -> dict:
    with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zipped:
        for name, source in files.items():
            safe_name(name)
            before = source.stat()
            zipped.write(source, arcname=name)
            after = source.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValueError("Source changed while archiving: " + name)
    with zipfile.ZipFile(target) as zipped:
        if len(zipped.namelist()) != len(files) or set(zipped.namelist()) != set(files) or zipped.testzip() is not None:
            raise ValueError("Archive CRC or inventory verification failed")
        for name in files:
            digest = hashlib.sha256()
            with zipped.open(name) as stream:
                for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                    digest.update(block)
            if digest.hexdigest() != expected_hashes[name]:
                raise ValueError("Archived content differs from verified input: " + name)
    return {"file": target.name, "bytes": target.stat().st_size, "sha256": sha_file(target),
            "files": len(files), "crc_verified": True, "content_sha256_verified": True}


def package(selected: dict) -> dict:
    output = selected["output"]
    output.mkdir(parents=True, exist_ok=False)
    records = [archive(output / name, files, selected["hashes"][name]) for name, files in selected["archives"].items()]
    rules = output / "account-rules"
    rules.mkdir()
    for name, source in selected["rules"].items():
        shutil.copyfile(source, rules / name)
        if sha_file(rules / name) != selected["rule_hashes"][name]:
            raise ValueError("Account rules changed while packaging")
    assets = records.pop()
    assets["scope"] = "Editable recommendation room and full/low assets, selected integration source files, and a pinned reproducible admissions patch. This is not a standalone full game-source checkout."
    for name, payload in (("packages.json", records), ("assets.json", assets), ("provenance.json", selected["provenance"]),
                          ("source-inventory.json", {"archives": selected["hashes"], "account_rules": selected["rule_hashes"]})):
        (output / name).write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"output": str(output), "packages": records, "assets": assets, "account_rules": list(selected["rules"]), "provenance": selected["provenance"]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-dir", type=Path, default=ROOT / "build/windows-recommendation-20261025-r3")
    parser.add_argument("--cloudflare-dir", type=Path, default=ROOT / "build/cloudflare-recommendation-20261025-r3")
    parser.add_argument("--output-dir", type=Path, default=ROOT / "build/recommendation-delivery-20261025")
    parser.add_argument("--date", default=date.today().strftime("%Y%m%d"))
    parser.add_argument("--dry-run", action="store_true", help="Validate inputs and hashes without writing output")
    args = parser.parse_args()
    selected = plan(args.windows_dir, args.cloudflare_dir, args.output_dir, args.date)
    print(json.dumps(describe(selected) if args.dry_run else package(selected), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
