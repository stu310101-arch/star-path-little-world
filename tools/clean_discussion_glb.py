"""Remove degenerate GLB triangle indices without rewriting vertex/image bytes.

Only the Python standard library is required. Import ``clean_glb(Path(...))``
after export, or use ``python tools/clean_discussion_glb.py file.glb --dry-run``.
The in-place write is atomic; validation failures leave the source untouched.
The cleaner appends index accessors instead of modifying possibly shared data.
An already-clean file is not rewritten, including its JSON formatting/padding.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
import os
from pathlib import Path
import struct
import tempfile
from typing import Any


AREA_THRESHOLD = 1e-12
_JSON = 0x4E4F534A
_BIN = 0x004E4942
_INDEX_FORMATS = {5121: "B", 5123: "H", 5125: "I"}


class GLBValidationError(ValueError):
    """Unsupported or invalid input; no output has been committed."""


def _integer(value: Any, label: str, minimum: int = 0) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        raise GLBValidationError(f"{label} must be an integer >= {minimum}")
    return value


def _at(sequence: list, index: Any, label: str) -> Any:
    index = _integer(index, label)
    if index >= len(sequence):
        raise GLBValidationError(f"{label} is out of bounds: {index}")
    return sequence[index]


def _read(raw: bytes) -> tuple[dict, list[tuple[int, bytes]], int]:
    if len(raw) < 20:
        raise GLBValidationError("Truncated GLB header")
    magic, version, length = struct.unpack_from("<III", raw)
    if magic != 0x46546C67 or version != 2 or length != len(raw):
        raise GLBValidationError("Expected a complete GLB 2.0 file")
    chunks = []
    offset = 12
    while offset < len(raw):
        if offset + 8 > len(raw):
            raise GLBValidationError("Truncated GLB chunk header")
        size, kind = struct.unpack_from("<II", raw, offset)
        offset += 8
        if size % 4 or offset + size > len(raw):
            raise GLBValidationError("Invalid GLB chunk size/alignment")
        chunks.append((kind, raw[offset:offset + size]))
        offset += size
    if not chunks or chunks[0][0] != _JSON:
        raise GLBValidationError("First GLB chunk must be JSON")
    if sum(kind == _JSON for kind, _ in chunks) != 1:
        raise GLBValidationError("Expected one JSON chunk")
    binary_chunks = [i for i, (kind, _) in enumerate(chunks) if kind == _BIN]
    if len(binary_chunks) != 1:
        raise GLBValidationError("Expected one embedded BIN chunk")
    try:
        document = json.loads(chunks[0][1].decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise GLBValidationError("Invalid GLB JSON") from exc
    if not isinstance(document, dict) or document.get("asset", {}).get("version") != "2.0":
        raise GLBValidationError("Expected a glTF 2.0 document")
    buffers = document.get("buffers", [])
    if len(buffers) != 1 or "uri" in buffers[0]:
        raise GLBValidationError("Only a single embedded buffer is supported")
    binary_index = binary_chunks[0]
    size = _integer(buffers[0].get("byteLength"), "buffer.byteLength")
    if not size <= len(chunks[binary_index][1]) <= size + 3:
        raise GLBValidationError("BIN chunk size does not match buffer.byteLength")
    return document, chunks, binary_index


def _values(document: dict, binary: bytes, accessor_index: int, *, positions: bool) -> tuple[list, dict]:
    accessor = _at(document.get("accessors", []), accessor_index, "accessor index")
    if "sparse" in accessor:
        raise GLBValidationError("Sparse accessors are unsupported; export dense geometry first")
    if accessor.get("normalized", False):
        raise GLBValidationError("Normalized position/index accessors are unsupported")
    count = _integer(accessor.get("count"), "accessor.count", 1)
    component_type = accessor.get("componentType")
    if positions:
        if accessor.get("type") != "VEC3" or component_type != 5126:
            raise GLBValidationError("POSITION must be a FLOAT VEC3 accessor")
        reader = struct.Struct("<fff")
    else:
        if accessor.get("type") != "SCALAR" or component_type not in _INDEX_FORMATS:
            raise GLBValidationError("Indices must be an unsigned SCALAR accessor")
        reader = struct.Struct("<" + _INDEX_FORMATS[component_type])
    view = _at(document.get("bufferViews", []), accessor.get("bufferView"), "bufferView index")
    if view.get("buffer", 0) != 0 or "EXT_meshopt_compression" in view.get("extensions", {}):
        raise GLBValidationError("Compressed or external bufferViews are unsupported")
    view_start = _integer(view.get("byteOffset", 0), "bufferView.byteOffset")
    view_length = _integer(view.get("byteLength"), "bufferView.byteLength")
    if view_start + view_length > document["buffers"][0]["byteLength"]:
        raise GLBValidationError("bufferView exceeds the embedded buffer")
    relative_start = _integer(accessor.get("byteOffset", 0), "accessor.byteOffset")
    stride = _integer(view.get("byteStride", reader.size), "bufferView.byteStride", reader.size)
    component_size = 4 if positions else reader.size
    if stride % component_size or (view_start + relative_start) % component_size:
        raise GLBValidationError("Accessor offset/stride is not component-aligned")
    if relative_start + (count - 1) * stride + reader.size > view_length:
        raise GLBValidationError("Accessor exceeds its bufferView")
    start = view_start + relative_start
    if stride == reader.size:
        values = list(reader.iter_unpack(memoryview(binary)[start:start + count * reader.size]))
    else:
        values = [reader.unpack_from(binary, start + i * stride) for i in range(count)]
    if positions:
        if any(not all(math.isfinite(value) for value in point) for point in values):
            raise GLBValidationError(f"POSITION accessor {accessor_index} contains NaN or infinity")
    else:
        values = [value[0] for value in values]
    return values, accessor


def _analyze(document: dict, binary: bytes) -> tuple[dict, list]:
    total = removed = 0
    per_mesh = []
    replacements = []
    position_cache: dict[int, list] = {}
    for mesh_index, mesh in enumerate(document.get("meshes", [])):
        mesh_count = mesh_removed = 0
        per_primitive = []
        primitives = mesh.get("primitives", [])
        if not primitives:
            raise GLBValidationError(f"Mesh {mesh_index} has no primitives")
        for primitive_index, primitive in enumerate(primitives):
            label = f"mesh {mesh_index}, primitive {primitive_index}"
            if primitive.get("mode", 4) != 4:
                raise GLBValidationError(f"{label}: only mode TRIANGLES (4) is supported")
            if "KHR_draco_mesh_compression" in primitive.get("extensions", {}):
                raise GLBValidationError(f"{label}: compressed primitives are unsupported")
            position_index = _integer(primitive.get("attributes", {}).get("POSITION"), "POSITION accessor")
            if position_index not in position_cache:
                position_cache[position_index] = _values(document, binary, position_index, positions=True)[0]
            points = position_cache[position_index]
            indexed = "indices" in primitive
            if indexed:
                indices, index_accessor = _values(document, binary, primitive["indices"], positions=False)
                component_type = index_accessor["componentType"]
            else:
                indices = range(len(points))
                component_type = 5123 if len(points) <= 65536 else 5125
            if len(indices) % 3:
                raise GLBValidationError(f"{label}: triangle index count is not divisible by three")
            if any(index >= len(points) for index in indices):
                raise GLBValidationError(f"{label}: index is outside the POSITION accessor")
            kept = []
            candidate_count = 0
            minimum_kept_area = None
            for i in range(0, len(indices), 3):
                ia, ib, ic = indices[i:i + 3]
                a, b, c = points[ia], points[ib], points[ic]
                ux, uy, uz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
                vx, vy, vz = c[0] - a[0], c[1] - a[1], c[2] - a[2]
                area = 0.5 * math.hypot(uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx)
                if not math.isfinite(area):
                    raise GLBValidationError(f"{label}: computed triangle area is non-finite")
                if area < AREA_THRESHOLD:
                    candidate_count += 1
                else:
                    kept.extend((ia, ib, ic))
                    minimum_kept_area = area if minimum_kept_area is None else min(minimum_kept_area, area)
            triangle_count = len(indices) // 3
            if candidate_count:
                # glTF forbids a zero-count accessor. Reject rather than silently
                # delete a mesh/primitive or emit an invalid empty accessor.
                if not kept:
                    raise GLBValidationError(f"{label}: all triangles are degenerate; cannot preserve the primitive")
                replacements.append((mesh_index, primitive_index, component_type, kept))
            mesh_count += triangle_count
            mesh_removed += candidate_count
            per_primitive.append({"primitive": primitive_index, "indexed": indexed,
                                  "count": triangle_count, "wouldRemove": candidate_count,
                                  "minimumKeptArea": minimum_kept_area})
        total += mesh_count
        removed += mesh_removed
        per_mesh.append({"mesh": mesh_index, "name": mesh.get("name", f"mesh_{mesh_index}"),
                         "count": mesh_count, "wouldRemove": mesh_removed,
                         "primitives": per_primitive})
    audit = {"schemaVersion": 1, "areaThreshold": AREA_THRESHOLD,
             "areaSpace": "primitive POSITION coordinates", "count": total,
             "wouldRemove": removed, "perMesh": per_mesh,
             "validated": {"finitePositions": True, "indexBounds": True,
                           "triangleMode": True, "accessorBounds": True}}
    return audit, replacements


def _result(audit: dict, path: Path, *, dry_run: bool, changed: bool, before: int, after: int) -> dict:
    audit.update({"path": str(path), "dryRun": dry_run, "changed": changed,
                  "removed": 0 if dry_run else audit["wouldRemove"],
                  "remaining": audit["count"] - (0 if dry_run else audit["wouldRemove"]),
                  "degenerateRemaining": audit["wouldRemove"] if dry_run else 0,
                  "bytesBefore": before, "bytesAfter": after})
    for mesh in audit["perMesh"]:
        for item in [mesh, *mesh["primitives"]]:
            item["removed"] = 0 if dry_run else item["wouldRemove"]
            item["remaining"] = item["count"] - item["removed"]
    return audit


def audit_glb(path: Path) -> dict:
    """Read-only audit; ``wouldRemove`` reports candidates, ``removed`` is zero."""
    path = Path(path)
    raw = path.read_bytes()
    document, chunks, binary_index = _read(raw)
    audit, _ = _analyze(document, chunks[binary_index][1])
    return _result(audit, path, dry_run=True, changed=False, before=len(raw), after=len(raw))


def clean_glb(path: Path) -> dict:
    """Atomically clean a GLB in place and return total/per-mesh audit counts.

    Dense FLOAT positions, interleaved views, unsigned index types, shared
    accessors and non-indexed TRIANGLES are supported. Unsupported geometry
    (including sparse/compressed or wholly degenerate primitives) fails closed.
    Existing BIN bytes, attributes, materials, embedded images and unknown
    chunks are preserved; only new index data/accessors are appended.
    """
    path = Path(path)
    raw = path.read_bytes()
    document, chunks, binary_index = _read(raw)
    original_binary = chunks[binary_index][1]
    audit, replacements = _analyze(document, original_binary)
    if not replacements:
        return _result(audit, path, dry_run=False, changed=False, before=len(raw), after=len(raw))
    updated = copy.deepcopy(document)
    binary = bytearray(original_binary)
    for mesh_index, primitive_index, component_type, indices in replacements:
        binary.extend(b"\0" * (-len(binary) % 4))
        offset = len(binary)
        writer = struct.Struct("<" + _INDEX_FORMATS[component_type])
        index_bytes = bytearray(len(indices) * writer.size)
        for i, index in enumerate(indices):
            writer.pack_into(index_bytes, i * writer.size, index)
        binary.extend(index_bytes)
        view_index = len(updated["bufferViews"])
        updated["bufferViews"].append({"buffer": 0, "byteOffset": offset,
                                       "byteLength": len(index_bytes), "target": 34963})
        accessor_index = len(updated["accessors"])
        updated["accessors"].append({"bufferView": view_index, "componentType": component_type,
                                     "count": len(indices), "type": "SCALAR",
                                     "min": [min(indices)], "max": [max(indices)]})
        updated["meshes"][mesh_index]["primitives"][primitive_index]["indices"] = accessor_index
    updated["buffers"][0]["byteLength"] = len(binary)
    binary.extend(b"\0" * (-len(binary) % 4))
    encoded = json.dumps(updated, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    encoded += b" " * (-len(encoded) % 4)
    output_chunks = list(chunks)
    output_chunks[0] = (_JSON, encoded)
    output_chunks[binary_index] = (_BIN, bytes(binary))
    payload = b"".join(struct.pack("<II", len(data), kind) + data for kind, data in output_chunks)
    output = struct.pack("<III", 0x46546C67, 2, 12 + len(payload)) + payload
    # Re-read the assembled file and re-audit before committing anything.
    checked_doc, checked_chunks, checked_bin_index = _read(output)
    checked_audit, pending = _analyze(checked_doc, checked_chunks[checked_bin_index][1])
    if pending or checked_audit["count"] != audit["count"] - audit["wouldRemove"]:
        raise GLBValidationError("Post-clean triangle audit failed")
    if checked_chunks[checked_bin_index][1][:len(original_binary)] != original_binary:
        raise GLBValidationError("Original embedded buffer bytes changed")
    temp_name = None
    try:
        with tempfile.NamedTemporaryFile(dir=path.parent, prefix=f".{path.name}.clean-", delete=False) as temp:
            temp_name = temp.name
            temp.write(output)
            temp.flush()
            os.fsync(temp.fileno())
        if path.read_bytes() != raw:
            raise GLBValidationError("Source changed during cleanup; refusing to overwrite a concurrent export")
        os.replace(temp_name, path)
        temp_name = None
    finally:
        if temp_name is not None:
            Path(temp_name).unlink(missing_ok=True)
    return _result(audit, path, dry_run=False, changed=True, before=len(raw), after=len(output))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    parser.add_argument("--dry-run", action="store_true", help="Audit without modifying the GLB")
    args = parser.parse_args()
    result = audit_glb(args.path) if args.dry_run else clean_glb(args.path)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
