"""Deduplicate unchanged embedded garden textures into shared external PNGs.

Each GLB keeps the same geometry, accessor bytes, materials and image bytes.
Only the image storage changes. Godot then imports one Texture2D per content hash,
instead of a duplicate prefixed image for every garden/device scene.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import struct
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "game/assets/discussion_garden"
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942


def ensure_mipmaps(image: Path) -> bool:
    """Keep the original GLB-imported 3D minification policy on external images."""
    settings = Path(str(image) + ".import")
    if settings.exists():
        source = settings.read_text(encoding="utf-8")
        if re.search(r"(?m)^mipmaps/generate[ \t]*=[ \t]*true[ \t]*$", source):
            return False
        if re.search(r"(?m)^mipmaps/generate[ \t]*=", source):
            updated = re.sub(r"(?m)^mipmaps/generate[^\r\n]*", "mipmaps/generate=true", source)
        elif "[params]" in source:
            updated = source.replace("[params]", "[params]\nmipmaps/generate=true", 1)
        else:
            updated = source.rstrip() + "\n\n[params]\nmipmaps/generate=true\n"
    else:
        # Godot fills destination/UID metadata on first import. These explicit
        # options prevent its external-PNG default of no mipmaps.
        updated = ('[remap]\nimporter="texture"\ntype="CompressedTexture2D"\n\n'
                   '[params]\ncompress/mode=0\nmipmaps/generate=true\n')
    settings.write_text(updated, encoding="utf-8", newline="\n")
    return True


def read_glb(path: Path) -> tuple[dict[str, Any], bytes]:
    raw = path.read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw)
    if magic != b"glTF" or version != 2 or length != len(raw):
        raise ValueError(f"Invalid GLB: {path}")
    offset, document, binary = 12, None, b""
    while offset < len(raw):
        size, kind = struct.unpack_from("<II", raw, offset)
        payload = raw[offset + 8:offset + 8 + size]
        if len(payload) != size:
            raise ValueError("Truncated GLB chunk")
        if kind == JSON_CHUNK:
            if document is not None:
                raise ValueError("Duplicate JSON chunk")
            document = json.loads(payload.rstrip(b" \x00"))
        elif kind == BIN_CHUNK:
            binary = payload
        else:
            raise ValueError(f"Unsupported GLB chunk {kind}")
        offset += 8 + size
    if document is None or len(document.get("buffers", [])) != 1:
        raise ValueError("Expected one embedded geometry buffer")
    return document, binary


def encode_glb(document: dict[str, Any], binary: bytes) -> bytes:
    payload = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    payload += b" " * (-len(payload) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    return (struct.pack("<4sII", b"glTF", 2, 28 + len(payload) + len(binary))
            + struct.pack("<II", len(payload), JSON_CHUNK) + payload
            + struct.pack("<II", len(binary), BIN_CHUNK) + binary)


def buffer_view_references(value: Any) -> set[int]:
    found: set[int] = set()
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "bufferView" and isinstance(child, int):
                found.add(child)
            else:
                found.update(buffer_view_references(child))
    elif isinstance(value, list):
        for child in value:
            found.update(buffer_view_references(child))
    return found


def remap_buffer_views(value: Any, mapping: dict[int, int]) -> None:
    if isinstance(value, dict):
        for key, child in value.items():
            if key == "bufferView" and isinstance(child, int):
                value[key] = mapping[child]
            else:
                remap_buffer_views(child, mapping)
    elif isinstance(value, list):
        for child in value:
            remap_buffer_views(child, mapping)


def externalize(path: Path, directory: str = "shared_textures") -> dict[str, Any]:
    path = path.resolve()
    if not directory or Path(directory).name != directory:
        raise ValueError("Shared texture directory must be a simple folder name")
    original = path.read_bytes()
    document, binary = read_glb(path)
    before = copy.deepcopy(document)
    views = document.get("bufferViews", [])
    removed_candidates: set[int] = set()
    textures: list[dict[str, Any]] = []
    extensions = {"image/png": "png", "image/jpeg": "jpg", "image/webp": "webp"}
    output_folder = path.parent / directory
    imports_updated = 0
    for image in document.get("images", []):
        if "bufferView" not in image:
            # Already shared images remain untouched on repeat exports.
            uri = image.get("uri", "")
            if uri.startswith(directory + "/"):
                existing = (path.parent / uri).resolve()
                if existing.parent != output_folder.resolve() or not existing.is_file():
                    raise ValueError("Missing or unsafe shared texture URI")
                imports_updated += int(ensure_mipmaps(existing))
            continue
        view_index = image["bufferView"]
        view = views[view_index]
        if view.get("buffer", 0) != 0:
            raise ValueError("Image points to an unsupported external buffer")
        mime = image.get("mimeType")
        if mime not in extensions:
            raise ValueError(f"Unsupported embedded texture MIME {mime}")
        start, size = view.get("byteOffset", 0), view["byteLength"]
        contents = binary[start:start + size]
        if len(contents) != size:
            raise ValueError("Image buffer view exceeds the geometry buffer")
        digest = hashlib.sha256(contents).hexdigest()
        filename = f"tex_{digest}.{extensions[mime]}"
        destination = output_folder / filename
        output_folder.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            if destination.read_bytes() != contents:
                raise ValueError("Texture hash collision or damaged shared texture")
        else:
            destination.write_bytes(contents)
        imports_updated += int(ensure_mipmaps(destination))
        image.pop("bufferView")
        image["uri"] = f"{directory}/{filename}"
        removed_candidates.add(view_index)
        textures.append({"name": image.get("name", ""), "uri": image["uri"],
                         "sha256": digest, "bytes": size})
    if not textures:
        return {"file": path.name, "changed": False, "before_bytes": len(original),
                "after_bytes": len(original), "textures": [], "texture_imports_updated": imports_updated}
    # Delete only image storage no longer referenced by any accessor/extension.
    retained_references = buffer_view_references(document)
    removed = removed_candidates - retained_references
    mapping: dict[int, int] = {}
    next_views: list[dict[str, Any]] = []
    next_binary = bytearray()
    for index, view in enumerate(views):
        if index in removed:
            continue
        if view.get("buffer", 0) != 0:
            raise ValueError("Expected all retained buffer views in buffer zero")
        start, size = view.get("byteOffset", 0), view["byteLength"]
        segment = binary[start:start + size]
        if len(segment) != size:
            raise ValueError("Buffer view outside the source buffer")
        next_binary.extend(b"\x00" * (-len(next_binary) % 4))
        next_view = dict(view, byteOffset=len(next_binary))
        mapping[index] = len(next_views)
        next_views.append(next_view)
        next_binary.extend(segment)
    document["bufferViews"] = next_views
    document["buffers"][0]["byteLength"] = len(next_binary)
    remap_buffer_views(document, mapping)
    for index, next_index in mapping.items():
        old, new = views[index], next_views[next_index]
        old_start, new_start = old.get("byteOffset", 0), new["byteOffset"]
        if binary[old_start:old_start + old["byteLength"]] != next_binary[new_start:new_start + new["byteLength"]]:
            raise AssertionError("Geometry/animation buffer bytes changed")
    # Materials and nodes are deliberately untouched; surfaces keep PBR values.
    for key in ("materials", "nodes", "accessors", "meshes", "skins", "animations", "textures", "samplers"):
        if key in before:
            expected = copy.deepcopy(before[key])
            remap_buffer_views(expected, mapping)
            if document.get(key) != expected:
                raise AssertionError(f"Unexpected {key} change")
    encoded = encode_glb(document, bytes(next_binary))
    temporary = path.with_suffix(path.suffix + ".shared.tmp")
    temporary.write_bytes(encoded)
    check_document, check_binary = read_glb(temporary)
    if check_document != document or check_binary[:len(next_binary)] != next_binary:
        raise AssertionError("GLB roundtrip verification failed")
    temporary.replace(path)
    return {"file": path.name, "changed": True, "before_bytes": len(original),
            "after_bytes": len(encoded), "before_sha256": hashlib.sha256(original).hexdigest(),
            "after_sha256": hashlib.sha256(encoded).hexdigest(),
            "geometry_views_preserved": len(mapping), "removed_image_views": len(removed),
            "textures": textures, "texture_imports_updated": imports_updated}


def share_textures(paths: list[Path], *, report_path: Path | None = None) -> dict[str, Any]:
    results = [externalize(path) for path in paths]
    unique = {texture["sha256"]: texture["bytes"] for row in results for texture in row["textures"]}
    report = {"method": __doc__, "files": results, "unique_textures_written": len(unique),
              "unique_texture_file_bytes": sum(unique.values()),
              "glb_bytes_removed": sum(row["before_bytes"] - row["after_bytes"] for row in results)}
    if report_path is not None:
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path)
    parser.add_argument("--report", type=Path, default=ROOT / "deliverables/discussion-overhaul/performance/shared-textures.json")
    args = parser.parse_args()
    paths = args.paths or sorted(ASSETS.glob("*.glb"))
    report = share_textures(paths, report_path=args.report)
    print(json.dumps({"files": len(paths), "unique_textures": report["unique_textures_written"],
                      "glb_bytes_removed": report["glb_bytes_removed"], "report": str(args.report)}))


if __name__ == "__main__":
    main()
