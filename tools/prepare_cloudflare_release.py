"""Package verified world/admissions exports and an optional native-auth Worker.

No Git mutations, R2 or source upload. Native auth uses SQLite Durable Objects.
Oversized originals are reconstructed and SHA-256 verified in the browser.
The output must be a new directory so historical exports cannot leak into it.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
from pathlib import Path
import re
import shutil

from package_admissions_site import package as package_admissions
from prepare_web_platform import resource_cache_groups

ROOT = Path(__file__).resolve().parents[1]
LIMIT = 25 * 1024 * 1024
PART_SIZE = 8 * 1024 * 1024


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def metadata(path: Path) -> dict:
    return {"bytes": path.stat().st_size, "sha256": digest(path.read_bytes())}


def relative_path(name: str) -> Path:
    if not re.fullmatch(r"[A-Za-z0-9_./-]+", name) or any(p in ("", ".", "..") for p in name.split("/")):
        raise ValueError(f"Unsafe release path: {name}")
    return Path(name)


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def prepare(source: Path, output: Path, name: str = "star-path-little-world", *,
            admissions_source: Path | None = None, admissions_out: Path | None = None,
            auth_worker: Path | None = None, auth_vars: Path | None = None) -> dict:
    source, output = source.resolve(), output.resolve()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,62}", name):
        raise ValueError("Invalid Cloudflare project name")
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError("Export and Cloudflare output must be separate directories")
    if output.exists():
        raise ValueError("Choose a new output directory; existing release files are preserved")
    stamp = json.loads((source / "index.release.json").read_text(encoding="utf-8"))
    selected = dict(stamp["files"])
    # The stamp includes both variants, never scan old packs or _site.
    selected.pop("index.service-worker.js", None)
    for variant in (source, source / "mobile"):
        license_manifest = variant / "licenses/manifest.json"
        licenses = json.loads(license_manifest.read_text(encoding="utf-8"))
        notices = variant / "THIRD_PARTY_NOTICES.txt"
        if digest(notices.read_bytes()) != licenses["notice_sha256"]:
            raise ValueError("Attribution notices differ from their manifest")
        license_paths = []
        for row in licenses["licenses"]:
            path = variant / relative_path(row["delivered_file"])
            if digest(path.read_bytes()) != row["sha256"]:
                raise ValueError("License text differs from its manifest")
            license_paths.append(path)
        for path in [notices, license_manifest, *license_paths]:
            if not path.is_file():
                raise ValueError(f"Missing release attribution: {path}")
            selected[path.relative_to(source).as_posix()] = metadata(path)
    for key, expected in selected.items():
        path = source / relative_path(key)
        if not path.resolve().is_relative_to(source) or metadata(path) != expected:
            raise ValueError(f"Export changed or has invalid metadata: {key}")

    site = output / "site"
    site.mkdir(parents=True)
    manifest = {"version": 1, "files": {}}
    for key, expected in sorted(selected.items()):
        original = source / key
        if expected["bytes"] > LIMIT:
            parts = []
            with original.open("rb") as stream:
                for payload in iter(lambda: stream.read(PART_SIZE), b""):
                    sha = digest(payload)
                    part_name = f"chunks/part.{sha[:16]}.{sha[16:]}.bin"
                    part_path = site / part_name
                    part_path.parent.mkdir(exist_ok=True)
                    if part_path.exists() and part_path.read_bytes() != payload:
                        raise ValueError("Chunk hash collision")
                    part_path.write_bytes(payload)
                    parts.append({"url": part_name, "bytes": len(payload), "sha256": sha})
            manifest["files"][key] = {**expected, "parts": parts}
        else:
            destination = site / key
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(original, destination)

    adapter = (ROOT / "tools/web_chunk_delivery.js").read_text(encoding="utf-8")
    manifest_text = json.dumps(manifest, separators=(",", ":"))
    script = adapter + "\nLittleWorldChunkDelivery.install(" + manifest_text + ", globalThis, document.currentScript.src);\n"
    script_hash = digest(script.encode("utf-8"))
    script_name = f"index.chunks.{script_hash[:16]}.js"
    (site / script_name).write_text(script, encoding="utf-8", newline="\n")
    for variant in ("", "mobile/"):
        # Pair the chunk transport with the current boot loader so real download
        # progress keeps its idle timeout alive before the verified response.
        delivery = site / variant / "index.delivery.js"
        if not delivery.is_file():
            raise ValueError("Missing boot delivery adapter")
        shutil.copyfile(ROOT / "tools/web_boot_delivery.js", delivery)
        page = site / variant / "index.html"
        html = page.read_text(encoding="utf-8")
        # Before every script, including platform, Godot and captured fetch.
        anchor = html.find("<script")
        if anchor < 0:
            raise ValueError("Missing exported script anchor")
        script_url = ("../" if variant else "") + script_name
        html = html[:anchor] + f'<script src="{script_url}"></script>\n' + html[anchor:]
        page.write_text(html, encoding="utf-8", newline="\n")

    admissions = None
    if (admissions_source is None) != (admissions_out is None):
        raise ValueError("Provide both admissions source and output")
    if admissions_source is not None:
        admissions = package_admissions(admissions_source, admissions_out, site)

    # Include adapter + real content in the transformed build identity.
    identity = hashlib.sha256()
    identity.update(stamp["build_id"].encode())
    identity.update(Path(__file__).read_bytes())
    identity.update((ROOT / "tools/prepare_web_platform.py").read_bytes())
    identity.update((ROOT / "tools/web_service_worker.js").read_bytes())
    for path in sorted(site.rglob("*")):
        if path.is_file() and path.name != "index.release.json":
            identity.update(path.relative_to(site).as_posix().encode())
            identity.update(bytes.fromhex(metadata(path)["sha256"]))
    build_id = "cf-" + identity.hexdigest()[:16]
    for variant in ("", "mobile/"):
        path = site / variant / "index.html"
        html = path.read_text(encoding="utf-8")
        html = re.sub(r'(<meta name="little-world-build" content=")[^"]+(">)', lambda m: m[1] + build_id + m[2], html)
        path.write_text(html, encoding="utf-8", newline="\n")
    info = {"build_id": build_id, "source_build_id": stamp["build_id"],
            "source_sha256": stamp["source_sha256"], "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
            "export": "Godot Web; Cloudflare Static Assets; client-side verified chunks",
            "server_side_code": auth_worker is not None,
            "virtual_files": manifest["files"]}
    mobile_files = {p.relative_to(site / "mobile").as_posix(): metadata(p)
                    for p in sorted((site / "mobile").rglob("*")) if p.is_file() and p.name != "index.release.json"}
    write_json(site / "mobile/index.release.json", {**info, "files": mobile_files})
    (site / "_headers").write_text("""/
  Cache-Control: no-cache
/mobile/
  Cache-Control: no-cache
/*.html
  Cache-Control: no-cache
/*.json
  Cache-Control: no-cache
/*.webmanifest
  Cache-Control: no-cache
  Content-Type: application/manifest+json
/*.js
  Cache-Control: no-cache
/chunks/*
  Cache-Control: public, max-age=31536000, immutable
  Content-Type: application/octet-stream
/packs/*
  Cache-Control: public, max-age=31536000, immutable
/mobile/packs/*
  Cache-Control: public, max-age=31536000, immutable
/admissions/firebase-config.json
  Cache-Control: no-store
/admissions/*
  Referrer-Policy: same-origin
""", encoding="utf-8")
    files = {p.relative_to(site).as_posix(): metadata(p) for p in sorted(site.rglob("*")) if p.is_file()}
    shell = [key for key in files if key.endswith((".html", ".js", ".json", ".webmanifest"))
             and not key.startswith(("games/", "licenses/", "admissions/", "admissions-source.json")) and "/games/" not in key and "/licenses/" not in key]
    config = {"build_id": build_id, "files": files, "shell": shell, **resource_cache_groups(source, manifest["files"])}
    worker = ("const RELEASE = " + json.dumps(config, separators=(",", ":")) + ";\n").encode() + (ROOT / "tools/web_service_worker.js").read_bytes()
    (site / "index.service-worker.js").write_bytes(worker)
    files["index.service-worker.js"] = metadata(site / "index.service-worker.js")
    write_json(site / "index.release.json", {**info, "files": files})
    wrangler = {
        "name": name, "compatibility_date": "2026-10-19", "workers_dev": True,
        "assets": {"directory": "./site", "not_found_handling": "404-page"},
        "send_metrics": False,
        "observability": {"enabled": False},
    }
    if auth_worker is not None:
        if admissions is None or auth_vars is None:
            raise ValueError("Auth Worker requires admissions and public deployment variables")
        public_vars = json.loads(auth_vars.read_text(encoding="utf-8"))
        expected = {"PUBLIC_ORIGIN", "FIREBASE_PROJECT_ID", "FIREBASE_API_KEY", "SERVICE_ACCOUNT_EMAIL"}
        if set(public_vars) != expected or not all(public_vars.values()):
            raise ValueError("Only complete public Auth Worker variables are allowed in the release")
        if public_vars["FIREBASE_PROJECT_ID"] != admissions["firebase_project_id"]:
            raise ValueError("Worker and website Firebase projects must match")
        shutil.copyfile(auth_worker, output / "auth-worker.js")
        wrangler.update({"main": "auth-worker.js", "vars": public_vars,
                         "durable_objects": {"bindings": [
                             {"name": "NATIVE_AUTH", "class_name": "NativeAuthHandoff"},
                             {"name": "NATIVE_AUTH_LIMITS", "class_name": "NativeAuthLimits"}]},
                         "migrations": [{"tag": "native-auth-v1", "new_sqlite_classes": ["NativeAuthHandoff", "NativeAuthLimits"]}]})
        wrangler["assets"].update({"binding": "ASSETS", "run_worker_first": ["/api/native-auth/*"]})
    write_json(output / "wrangler.jsonc", wrangler)
    report = verify(site)
    report["server_side_code"] = auth_worker is not None
    if admissions:
        report["admissions"] = {key: admissions[key] for key in ("source_base_commit", "source_sha256", "firebase_project_id", "base_path")}
    if auth_worker:
        report["auth_worker_sha256"] = metadata(output / "auth-worker.js")["sha256"]
    write_json(output / "verification.json", report)
    return report


def verify(site: Path) -> dict:
    stamp = json.loads((site / "index.release.json").read_text(encoding="utf-8"))
    actual = {p.relative_to(site).as_posix(): metadata(p) for p in site.rglob("*") if p.is_file()}
    if set(actual) != set(stamp["files"]) | {"index.release.json"}:
        raise ValueError("Unlisted or missing deployment files")
    for key, expected in stamp["files"].items():
        if actual[key] != expected or actual[key]["bytes"] > LIMIT:
            raise ValueError(f"Invalid uploaded file: {key}")
    for key, item in stamp["virtual_files"].items():
        if (site / key).exists():
            raise ValueError("Oversized original must not be uploaded")
        checksum, total = hashlib.sha256(), 0
        for part in item["parts"]:
            path = site / relative_path(part["url"])
            if metadata(path) != {"bytes": part["bytes"], "sha256": part["sha256"]}:
                raise ValueError("Invalid chunk")
            checksum.update(path.read_bytes())
            total += part["bytes"]
        if total != item["bytes"] or checksum.hexdigest() != item["sha256"]:
            raise ValueError("Chunks do not reconstruct the original export")
    if len(actual) > 20000:
        raise ValueError("Cloudflare Free file count exceeded")
    return {"passed": True, "build_id": stamp["build_id"], "source_build_id": stamp["source_build_id"],
            "uploaded_files": len(actual), "uploaded_bytes": sum(x["bytes"] for x in actual.values()),
            "maximum_file_bytes": max(x["bytes"] for x in actual.values()), "limit_bytes": LIMIT,
            "split_originals": len(stamp["virtual_files"]), "reconstruction_sha256_verified": True,
            "server_side_code": stamp.get("server_side_code", False), "github_operations": "none"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "build/web")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--name", default="star-path-little-world")
    parser.add_argument("--admissions-source", type=Path)
    parser.add_argument("--admissions-out", type=Path)
    parser.add_argument("--auth-worker", type=Path)
    parser.add_argument("--auth-vars", type=Path)
    args = parser.parse_args()
    print(json.dumps(prepare(args.source, args.output, args.name,
                             admissions_source=args.admissions_source, admissions_out=args.admissions_out,
                             auth_worker=args.auth_worker, auth_vars=args.auth_vars), indent=2))
