"""Copy a verified Next static export into the world release, with source provenance.

The admissions checkout is maintained as its own Git repository. No Git writes,
installation or builds are performed by this packager.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import subprocess


def sha(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def package(source: Path, exported: Path, site: Path) -> dict:
    source, exported, site = source.resolve(), exported.resolve(), site.resolve()
    destination = site / "admissions"
    if destination.exists():
        raise ValueError("Admissions destination must be absent in a new release")
    for required in ("index.html", "host/index.html", "account/index.html",
                     "account/native/index.html", "firebase-config.json"):
        if not (exported / required).is_file():
            raise ValueError("Missing admissions build output: " + required)
    config = json.loads((exported / "firebase-config.json").read_text(encoding="utf-8"))
    if not all(config.get(key) for key in ("apiKey", "authDomain", "projectId", "appId")):
        raise ValueError("Production Firebase web configuration is incomplete")
    allowed_config = {"apiKey", "authDomain", "projectId", "appId", "storageBucket", "messagingSenderId", "measurementId"}
    if set(config) - allowed_config:
        raise ValueError("Unexpected Firebase production config fields (no emulator or secrets allowed)")
    paths = subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"], cwd=source).decode("utf-8").split("\0")
    provenance: dict[str, str] = {}
    for name in sorted(set(filter(None, paths))):
        original = source / name
        path = original.resolve()
        if original.is_symlink() or not path.is_relative_to(source):
            raise ValueError("Invalid source inventory: " + name)
        if not path.is_file():
            continue
        if name.startswith((".next/", "out/", "node_modules/", ".git/")):
            raise ValueError("Invalid source inventory: " + name)
        provenance[name] = sha(path.read_bytes())
    outputs = {}
    for path in sorted(exported.rglob("*")):
        if not path.is_file():
            continue
        if path.is_symlink() or not path.resolve().is_relative_to(exported):
            raise ValueError("Static output escapes the admissions export")
        name = path.relative_to(exported).as_posix()
        if any(part.startswith(".") for part in Path(name).parts) or path.suffix == ".map":
            continue
        payload = path.read_bytes()
        target = destination / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        outputs[name] = {"bytes": len(payload), "sha256": sha(payload)}
    manifest = {
        "version": 1,
        "source_repository": "https://github.com/stu310101-arch/113-115-admission-screening",
        "source_base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip(),
        "source_sha256": sha(json.dumps(provenance, sort_keys=True, separators=(",", ":")).encode()),
        "source_files": provenance,
        "base_path": "/admissions",
        "firebase_project_id": config["projectId"],
        "files": outputs,
    }
    (site / "admissions-source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest
