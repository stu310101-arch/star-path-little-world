"""Coarsen only the low garden's static cell meshes into collection/material batches.

This operates on GLB bytes instead of a Blender round trip: UVs, normalized color,
normals, materials, images, samplers and winding remain unchanged. Current authored
nodes are flat and translation-only. Other transform/animation layouts fail closed.
"""
from __future__ import annotations
import argparse
from collections import defaultdict
import copy
import hashlib
import json
from pathlib import Path
import re
import struct

from share_discussion_textures import ASSETS, ROOT, encode_glb, read_glb, share_textures

SIZES = {5121: 1, 5123: 2, 5125: 4, 5126: 4}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def accessor_bytes(document, binary, index):
    accessor = document["accessors"][index]
    if "sparse" in accessor: raise ValueError("Sparse accessor is unsupported")
    view = document["bufferViews"][accessor["bufferView"]]
    size = SIZES[accessor["componentType"]] * COMPONENTS[accessor["type"]]
    stride = view.get("byteStride", size)
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    if stride == size: return binary[start:start + accessor["count"] * size]
    return b"".join(binary[start + i * stride:start + i * stride + size] for i in range(accessor["count"]))


def schema(accessor):
    return {key: accessor[key] for key in ("componentType", "type", "normalized") if key in accessor}


def coarsen(path: Path, *, backup_dir: Path, report_path: Path) -> dict:
    document, binary = read_glb(path)
    if document.get("asset", {}).get("extras", {}).get("discussion_low_batch_version") == 1:
        return {"changed": False, "file": str(path), "reason": "already collection batched"}
    if document.get("animations") or document.get("skins"): raise ValueError("Static art only")
    if any("bufferView" in image for image in document.get("images", [])):
        raise ValueError("Run share_discussion_textures.py before batching embedded images")
    roots = document["scenes"][document.get("scene", 0)]["nodes"]
    if sorted(roots) != list(range(len(document["nodes"]))): raise ValueError("Expected flat scene roots")
    groups = defaultdict(list)
    for node in document["nodes"]:
        if set(node) - {"mesh", "name", "translation", "extras"}: raise ValueError("Translation-only flat nodes required")
        if "mesh" not in node: raise ValueError("Expected mesh node")
        group = re.sub(r"_Cell_-?\d+_-?\d+$", "", node["name"])
        groups[group].append(node)
    result = copy.deepcopy(document)
    result.update(nodes=[], meshes=[], accessors=[], bufferViews=[])
    output = bytearray()
    audit_groups = []
    total_triangles = 0
    max_position_error = 0.0
    attribute_hashes = defaultdict(hashlib.sha256)
    protected = {key: copy.deepcopy(document.get(key)) for key in ("materials", "images", "textures", "samplers")}

    def add_accessor(payload, attributes, count, *, bounds=None, index_buffer=False):
        output.extend(b"\0" * (-len(output) % 4))
        view_id = len(result["bufferViews"])
        result["bufferViews"].append({"buffer": 0, "byteOffset": len(output), "byteLength": len(payload), "target": 34963 if index_buffer else 34962})
        output.extend(payload)
        accessor = dict(attributes, bufferView=view_id, count=count)
        if bounds is not None: accessor.update(min=bounds[0], max=bounds[1])
        result["accessors"].append(accessor)
        return len(result["accessors"]) - 1

    for name, nodes in groups.items():
        lower = [float("inf")] * 3
        upper = [-float("inf")] * 3
        batches = defaultdict(list)
        for node in nodes:
            translation = node.get("translation", [0, 0, 0])
            for primitive in document["meshes"][node["mesh"]]["primitives"]:
                if set(primitive) - {"attributes", "indices", "material", "mode"}: raise ValueError("Unexpected primitive extension/morph target")
                if primitive.get("mode", 4) != 4 or "indices" not in primitive: raise ValueError("Indexed triangles required")
                position = document["accessors"][primitive["attributes"]["POSITION"]]
                if schema(position) != {"componentType": 5126, "type": "VEC3"}: raise ValueError("Float32 VEC3 positions required")
                for xyz in struct.iter_unpack("<fff", accessor_bytes(document, binary, primitive["attributes"]["POSITION"])):
                    for axis in range(3):
                        world = xyz[axis] + translation[axis]
                        lower[axis] = min(lower[axis], world)
                        upper[axis] = max(upper[axis], world)
                key = json.dumps({"material": primitive.get("material"), "attributes": {semantic: schema(document["accessors"][index]) for semantic, index in primitive["attributes"].items()}}, sort_keys=True)
                batches[key].append((node, primitive))
        center = [(lower[i] + upper[i]) * .5 for i in range(3)]
        mesh = {"name": name + "_LowBatch", "primitives": []}
        group_triangles = 0
        for records in batches.values():
            streams = {semantic: bytearray() for semantic in records[0][1]["attributes"]}
            indices = []
            vertex_count = 0
            local_min = [float("inf")] * 3
            local_max = [-float("inf")] * 3
            for node, primitive in records:
                translation = node.get("translation", [0, 0, 0])
                count = document["accessors"][primitive["attributes"]["POSITION"]]["count"]
                for semantic, index in primitive["attributes"].items():
                    if document["accessors"][index]["count"] != count: raise ValueError("Attribute count mismatch")
                    payload = accessor_bytes(document, binary, index)
                    if semantic != "POSITION":
                        streams[semantic].extend(payload)
                        attribute_hashes[semantic].update(payload)
                        continue
                    for xyz in struct.iter_unpack("<fff", payload):
                        packed = struct.pack("<fff", *(xyz[i] + translation[i] - center[i] for i in range(3)))
                        merged = struct.unpack("<fff", packed)
                        streams[semantic].extend(packed)
                        for axis in range(3):
                            max_position_error = max(max_position_error, abs(merged[axis] + center[axis] - xyz[axis] - translation[axis]))
                            local_min[axis] = min(local_min[axis], merged[axis])
                            local_max[axis] = max(local_max[axis], merged[axis])
                index_accessor = document["accessors"][primitive["indices"]]
                index_format = {5121: "B", 5123: "H", 5125: "I"}[index_accessor["componentType"]]
                old_indices = [item[0] for item in struct.iter_unpack("<" + index_format, accessor_bytes(document, binary, primitive["indices"]))]
                if len(old_indices) % 3 or max(old_indices) >= count: raise ValueError("Invalid triangle indices")
                indices.extend(index + vertex_count for index in old_indices)
                vertex_count += count
            new_primitive = {"attributes": {}}
            template = records[0][1]
            if "material" in template: new_primitive["material"] = template["material"]
            for semantic, payload in streams.items():
                new_primitive["attributes"][semantic] = add_accessor(payload, schema(document["accessors"][template["attributes"][semantic]]), vertex_count, bounds=(local_min, local_max) if semantic == "POSITION" else None)
            new_primitive["indices"] = add_accessor(struct.pack("<" + "I" * len(indices), *indices), {"componentType": 5125, "type": "SCALAR"}, len(indices), index_buffer=True)
            mesh["primitives"].append(new_primitive)
            group_triangles += len(indices) // 3
        result["nodes"].append({"name": name + "_LowBatch", "mesh": len(result["meshes"]), "translation": center})
        result["meshes"].append(mesh)
        audit_groups.append({"name": name, "input_cells": len(nodes), "surfaces": len(mesh["primitives"]), "triangles": group_triangles, "world_aabb": {"min": lower, "max": upper}})
        total_triangles += group_triangles
    if max_position_error > .00002: raise ValueError("Position tolerance exceeded")
    original_triangles = sum(document["accessors"][primitive["indices"]]["count"] // 3 for node in document["nodes"] for primitive in document["meshes"][node["mesh"]]["primitives"])
    if total_triangles != original_triangles: raise ValueError("Triangle count changed")
    result["scenes"] = [{"name": document["scenes"][document.get("scene", 0)].get("name", "Scene"), "nodes": list(range(len(result["nodes"])))}]
    result["scene"] = 0
    result["buffers"] = [{"byteLength": len(output)}]
    result["asset"].setdefault("extras", {})["discussion_low_batch_version"] = 1
    for key, value in protected.items():
        if result.get(key) != value: raise ValueError("Changed protected material/image data")
    # Re-read serialized streams: COLOR/UV/normals must remain byte-for-byte equal.
    after_hashes = defaultdict(hashlib.sha256)
    for mesh in result["meshes"]:
        for primitive in mesh["primitives"]:
            for semantic, index in primitive["attributes"].items():
                if semantic != "POSITION": after_hashes[semantic].update(accessor_bytes(result, output, index))
    for key in attribute_hashes:
        if attribute_hashes[key].digest() != after_hashes[key].digest(): raise ValueError("Attribute bytes changed: " + key)
    before = path.read_bytes()
    digest = hashlib.sha256(before).hexdigest()
    backup_dir.mkdir(parents=True, exist_ok=True)
    backup = backup_dir / (path.stem + "-before-batching-" + digest[:12] + ".glb")
    if not backup.exists(): backup.write_bytes(before)
    encoded = encode_glb(result, output)
    temporary = path.with_suffix(".batching.glb")
    temporary.write_bytes(encoded)
    read_glb(temporary)
    temporary.replace(path)
    share_textures([path])
    report = {"changed": True, "backup": str(backup), "source_sha256": digest, "result_sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "before_bytes": len(before), "after_bytes": path.stat().st_size, "triangles_before": original_triangles, "triangles_after": total_triangles, "cells_before": len(document["nodes"]), "batches_after": len(result["nodes"]), "surfaces_before": sum(len(m["primitives"]) for m in document["meshes"]), "surfaces_after": sum(len(m["primitives"]) for m in result["meshes"]), "max_world_vertex_error_m": max_position_error, "attribute_sha256": {key: value.hexdigest() for key, value in attribute_hashes.items()}, "material_image_sampler_data_exact": True, "groups": audit_groups}
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", nargs="?", type=Path, default=ASSETS / "garden_low.glb")
    parser.add_argument("--report", type=Path, default=ROOT / "deliverables/discussion-overhaul/performance/low-collection-batching.json")
    args = parser.parse_args()
    report = coarsen(args.path, backup_dir=ROOT / "deliverables/discussion-overhaul/performance/source-backups", report_path=args.report)
    print(json.dumps({key: value for key, value in report.items() if key != "groups"}, indent=2))
