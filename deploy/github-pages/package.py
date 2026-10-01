"""Prepare and reassemble the published Godot Web build for GitHub Pages.

GitHub rejects Git objects over 100 MiB. This script stores the exported PCK
in small, individually verified parts, then restores it in the Pages workflow.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil


PART_SIZE = 45 * 1024 * 1024
BLOCK = 1024 * 1024


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(BLOCK), b""):
            result.update(block)
    return result.hexdigest()


def safe_relative(value: str) -> Path:
    relative = Path(value)
    if relative.is_absolute() or not value or ".." in relative.parts:
        raise ValueError(f"Invalid release path: {value}")
    return relative


def prepare(source: Path, package: Path) -> None:
    source = source.resolve()
    package = package.resolve()
    pck = source / "index.pck"
    if not pck.is_file() or not (source / "index.html").is_file():
        raise FileNotFoundError("Export Godot Web before packaging it")
    previous_path = package / "manifest.json"
    previous = json.loads(previous_path.read_text(encoding="utf-8")) if previous_path.is_file() else {}
    (package / "parts").mkdir(parents=True, exist_ok=True)
    (package / "files").mkdir(parents=True, exist_ok=True)

    parts: list[dict[str, object]] = []
    whole = hashlib.sha256()
    with pck.open("rb") as stream:
        for index, payload in enumerate(iter(lambda: stream.read(PART_SIZE), b"")):
            name = f"index.pck.part{index:03d}"
            (package / "parts" / name).write_bytes(payload)
            whole.update(payload)
            parts.append({"name": name, "bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()})
    if not parts or whole.hexdigest() != digest(pck):
        raise RuntimeError("PCK was not copied consistently")

    paths = sorted(
        [path for path in source.glob("index.*") if path.is_file() and path.name != "index.pck"]
        + [source / "THIRD_PARTY_NOTICES.txt"]
        + list((source / "licenses").glob("*"))
        + list((source / "packs").glob("*.pck"))
    )
    files: list[dict[str, object]] = []
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
        relative = path.relative_to(source)
        dest = package / "files" / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(path, dest)
        files.append({"path": relative.as_posix(), "bytes": path.stat().st_size, "sha256": digest(path)})

    manifest = {
        "format": 1,
        "game": "星途 · Little World",
        "pck": {"bytes": pck.stat().st_size, "sha256": whole.hexdigest(), "parts": parts},
        "files": files,
    }
    (package / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    # A smaller release must not leave old, unused PCK parts in Git. Only prune
    # files owned by the preceding manifest, after the replacement is complete.
    old_owned = {"parts/" + str(item["name"]) for item in previous.get("pck", {}).get("parts", [])}
    old_owned.update("files/" + str(item["path"]) for item in previous.get("files", []))
    new_owned = {"parts/" + str(item["name"]) for item in parts}
    new_owned.update("files/" + str(item["path"]) for item in files)
    for name in old_owned - new_owned:
        obsolete = (package / safe_relative(name)).resolve()
        if not obsolete.is_relative_to(package):
            raise ValueError(f"Release path escapes package: {name}")
        if obsolete.is_file():
            obsolete.unlink()
    print(f"Prepared {len(parts)} PCK parts and {len(files)} site files; PCK SHA-256 {whole.hexdigest()}")


def assemble(package: Path, output: Path) -> None:
    package = package.resolve()
    output = output.resolve()
    manifest = json.loads((package / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("format") != 1:
        raise ValueError("Unknown release manifest format")
    output.mkdir(parents=True, exist_ok=True)
    pck_info = manifest["pck"]
    pck = output / "index.pck"
    with pck.open("wb") as dest:
        for part in pck_info["parts"]:
            source = package / "parts" / safe_relative(part["name"])
            if source.stat().st_size != part["bytes"] or digest(source) != part["sha256"]:
                raise RuntimeError(f"Invalid PCK part: {source}")
            with source.open("rb") as stream:
                shutil.copyfileobj(stream, dest, BLOCK)
    if pck.stat().st_size != pck_info["bytes"] or digest(pck) != pck_info["sha256"]:
        raise RuntimeError("Reassembled PCK differs from Godot export")

    for item in manifest["files"]:
        relative = safe_relative(item["path"])
        source = package / "files" / relative
        if source.stat().st_size != item["bytes"] or digest(source) != item["sha256"]:
            raise RuntimeError(f"Invalid site file: {source}")
        dest = output / relative
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
    (output / ".nojekyll").touch()
    print(f"Verified Pages site: {pck.stat().st_size} byte PCK, {len(manifest['files'])} other files")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "assemble"])
    parser.add_argument("--source", type=Path)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.mode == "prepare":
        if args.source is None:
            parser.error("prepare requires --source")
        prepare(args.source, args.package)
    else:
        if args.output is None:
            parser.error("assemble requires --output")
        assemble(args.package, args.output)


if __name__ == "__main__":
    main()
