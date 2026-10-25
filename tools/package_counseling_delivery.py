"""Package existing verified counseling candidates; never build or deploy.

Use --dry-run to inspect the inventory without creating an output directory.
The editable asset allowlist contains canonical art and its generator dependencies.
"""
from __future__ import annotations

import argparse
from datetime import date, datetime
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT_FILES = ("firestore.rules", "firestore.indexes.json", "firebase.json", "INTEREST_DATA.md")
ART_FILES = ("acceptance-manifest.json", "CounselingRoom.blend", "export-report.json", "prepare_textures.py",
             "README.md", "source-verification-2k.json", "SOURCE_NOTES.md", "sources.json")
SOURCE_FILES = ("Fabric060_1K-JPG.zip", "Fabric060_1K-JPG_Color.jpg", "Fabric060_1K-JPG_NormalGL.jpg",
                "Fabric060_1K-JPG_Roughness.jpg", *(f"wood_floor_{kind}_{size}.jpg" for kind in ("diff", "nor_gl", "rough") for size in ("1k", "2k")),
                *(f"wood_table_001_{kind}_2k.jpg" for kind in ("diff", "nor_gl", "rough")))
RUNTIME_FILES = ("counseling_room.glb", "counseling_room.glb.import", "import_materials.gd", "import_materials.gd.uid", "layout.json")
TEXTURES = ("apricot_base", "fabric_normal", "fabric_rough", "joinery_base", "joinery_normal", "joinery_rough",
            "linen_base", "oak_base", "oak_normal", "oak_rough", "sage_base")
GENERATOR_FILES = ("build_counseling_room.py", "counseling_botanicals.py", "counseling_soft_furnishings.py", "counseling_wood_chair.py",
                   "optimize_indoor_geometry.py", "audit_indoor_geometry.py")
SECRET_KEYS = {"password", "private_key", "privatekey", "client_secret", "refreshtoken", "idtoken", "accesstoken", "customtoken"}


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


def safe_file(path: Path, base: Path) -> Path:
    if path.is_symlink() or not path.resolve().is_relative_to(base) or not path.is_file():
        raise ValueError(f"Missing or unsafe input: {path}")
    name = path.relative_to(base).as_posix()
    if re.search(r"(^|/)(?:\.env(?:\.|$)|\.dev\.vars(?:\.|$)|\.git(?:/|$)|tests?(?:/|$)|fixtures?(?:/|$))", name, re.I) or re.search(r"(?:^|[/_.-])(?:fixture|credentials|qa[-_]session|service[-_]account[-_]key)(?:[/_.-]|$)|\.(?:pem|key|p12|pfx|log|blend\d+)$", name, re.I):
        raise ValueError(f"Secret, fixture or non-delivery file rejected: {name}")
    if path.suffix.lower() in (".json", ".jsonc", ".md", ".txt", ".js", ".py", ".gd"):
        payload = path.read_bytes()
        # The auth Worker legitimately contains PEM parser marker strings.
        # Reject a key body, not the parser's public source code.
        if re.search(rb"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----[\r\n]+[A-Za-z0-9+/=\r\n]{64,}-----END (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", payload.replace(b"\\n", b"\n")):
            raise ValueError(f"Private-key material rejected: {name}")
        if path.suffix.lower() in (".json", ".jsonc"):
            def inspect(value):
                if isinstance(value, dict):
                    for key, child in value.items():
                        if key.lower() in SECRET_KEYS and isinstance(child, str) and child:
                            raise ValueError(f"Credential field rejected: {name}")
                        inspect(child)
                elif isinstance(value, list):
                    for child in value:
                        inspect(child)
            inspect(json.loads(payload.decode("utf-8-sig")))
    return path


def inventory(folder: Path) -> dict[str, Path]:
    if not folder.is_dir():
        raise ValueError(f"Missing input directory: {folder}")
    return {path.relative_to(folder).as_posix(): safe_file(path, folder)
            for path in sorted(folder.rglob("*")) if path.is_file() or path.is_symlink()}


def asset_inventory() -> dict[str, Path]:
    names = ["art/CounselingRoom/" + name for name in ART_FILES]
    names += ["art/CounselingRoom/sources/" + name for name in SOURCE_FILES]
    names += ["game/assets/counseling_room/" + name for name in RUNTIME_FILES]
    names += [f"game/assets/counseling_room/textures/{name}.png{suffix}" for name in TEXTURES for suffix in ("", ".import")]
    names += ["game/scenes/counseling_room.tscn", "game/scripts/counseling_room.gd", "game/scripts/admissions_furniture_interaction.gd"]
    names += ["tools/" + name for name in GENERATOR_FILES]
    return {name: safe_file(ROOT / name, ROOT) for name in sorted(names)}


def plan(windows: Path, cloudflare: Path, output: Path, stamp: str) -> dict:
    datetime.strptime(stamp, "%Y%m%d")
    if not re.fullmatch(r"\d{8}", stamp):
        raise ValueError("Date must use YYYYMMDD")
    windows, cloudflare, output = windows.resolve(), cloudflare.resolve(), output.resolve()
    if output.exists():
        raise ValueError("Output directory must be new; existing archives are never overwritten")
    if any(output.is_relative_to(source) or source.is_relative_to(output) for source in (windows, cloudflare)):
        raise ValueError("Output and candidate directories must be separate")
    native = inventory(windows)
    expected_native = set(read_json(windows / "release.json")["native_files"]) | {"release.json"}
    if set(native) != expected_native or not {"LittleWorld.exe", "LittleWorld.pck", "index.packs.json"} <= set(native):
        raise ValueError("Windows directory differs from its release inventory")
    web = inventory(cloudflare)
    release = read_json(cloudflare / "site/index.release.json")
    expected_web = {"site/" + name for name in release["files"]} | {"site/index.release.json", "auth-worker.js", "wrangler.jsonc", "verification.json"}
    if set(web) != expected_web:
        raise ValueError("Cloudflare candidate differs from its release inventory")
    verification = read_json(cloudflare / "verification.json")
    if verification.get("passed") is not True or verification.get("build_id") != release["build_id"]:
        raise ValueError("Cloudflare candidate lacks matching successful verification")
    firebase = read_json(cloudflare / "site/admissions/firebase-config.json")
    if set(firebase) - {"apiKey", "authDomain", "projectId", "appId", "storageBucket", "messagingSenderId", "measurementId"}:
        raise ValueError("Unexpected production Firebase configuration fields")
    rules = {name: safe_file(ROOT / "admissions-site" / name, ROOT / "admissions-site") for name in ACCOUNT_FILES}
    return {"output": output, "archives": {
        f"StarPath-Windows-Counseling-{stamp}.zip": native,
        f"StarPath-Web-Counseling-{stamp}.zip": web,
        f"Counseling-Assets-{stamp}.zip": asset_inventory(),
    }, "rules": rules}


def describe(plan_data: dict) -> dict:
    return {"dry_run": True, "output": str(plan_data["output"]), "archives": {
        name: {"files": len(files), "uncompressed_bytes": sum(path.stat().st_size for path in files.values())}
        for name, files in plan_data["archives"].items()
    }, "account_rules": list(plan_data["rules"]), "writes_performed": False}


def archive(target: Path, files: dict[str, Path]) -> dict:
    # Exclusive creation also protects against a concurrent packaging process.
    with zipfile.ZipFile(target, "x", compression=zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as zipped:
        for name, source in files.items():
            before = source.stat()
            zipped.write(source, arcname=name)
            after = source.stat()
            if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                raise ValueError(f"Source changed while archiving: {name}")
    with zipfile.ZipFile(target) as zipped:
        bad = zipped.testzip()
        if bad is not None or set(zipped.namelist()) != set(files):
            raise ValueError(f"Archive CRC or inventory verification failed: {target.name}")
    digest = hashlib.sha256()
    with target.open("rb") as stream:
        for chunk in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    label = target.relative_to(ROOT).as_posix() if target.is_relative_to(ROOT) else str(target)
    return {"file": label, "bytes": target.stat().st_size, "sha256": digest.hexdigest(), "files": len(files), "crc_verified": True}


def package(plan_data: dict) -> dict:
    output = plan_data["output"]
    output.mkdir(parents=True, exist_ok=False)
    records = [archive(output / name, files) for name, files in plan_data["archives"].items()]
    rules = output / "account-rules"
    rules.mkdir()
    for name, source in plan_data["rules"].items():
        shutil.copyfile(source, rules / name)
    assets = records.pop()
    assets["scope"] = "Editable Blender source, canonical runtime assets, original licensed source maps and generator scripts with their local dependencies. Full game source remains in this workspace."
    (output / "packages.json").write_text(json.dumps(records, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "assets.json").write_text(json.dumps(assets, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return {"output": str(output), "packages": records, "assets": assets, "account_rules": list(plan_data["rules"])}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--windows-dir", type=Path, required=True)
    parser.add_argument("--cloudflare-dir", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--date", default=date.today().strftime("%Y%m%d"), help="Archive filename date, YYYYMMDD")
    parser.add_argument("--dry-run", action="store_true", help="Validate and print inventory only; create no files")
    args = parser.parse_args()
    selected = plan(args.windows_dir, args.cloudflare_dir, args.output_dir, args.date)
    print(json.dumps(describe(selected) if args.dry_run else package(selected), ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
