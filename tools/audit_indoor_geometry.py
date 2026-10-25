"""Read-only GLB geometry audit for the three indoor environments.

No Blender/Godot process, product file, mesh, or import setting is changed.
Counts are asset geometry, not measured frame draw calls or GPU timings.
Camera-volume and buried-face counts are review candidates, never deletion rules:
shadow casting, open windows, alpha surfaces and interaction still need validation.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
              5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
WIDTHS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
CAMERAS = {
    "admissions_studio": ((-8.32, .18, -6.82), (8.32, 4.82, 6.82)),
    "wordking_training_room": ((-9.75, .4, -8.75), (9.75, 3.15, 8.85)),
    # Hall inspection camera stays inside the larger volume below.
    "atrium": ((-15.5, .4, -12.5), (15.5, 5.8, 12.5)),
    "gallery": ((-14.5, .4, -18.5), (14.5, 5.8, 18.5)),
}


def read_glb(path):
    data = path.read_bytes()
    magic, version, length = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or length != len(data):
        raise ValueError(f"Invalid GLB: {path}")
    offset, document, binary = 12, None, b""
    while offset < len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        chunk = data[offset + 8:offset + 8 + size]
        if kind == 0x4E4F534A:
            document = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + size
    if document is None:
        raise ValueError(f"No JSON chunk: {path}")
    return document, binary


def accessor(document, binary, index):
    spec = document["accessors"][index]
    if "sparse" in spec:
        raise ValueError("Sparse accessors require explicit handling")
    if "bufferView" not in spec:
        return [(0,) * WIDTHS[spec["type"]]] * spec["count"]
    view = document["bufferViews"][spec["bufferView"]]
    if view.get("buffer", 0) != 0:
        raise ValueError("External buffers are not supported")
    code, size = COMPONENTS[spec["componentType"]]
    width = WIDTHS[spec["type"]]
    stride = view.get("byteStride", width * size)
    offset = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
    unpack = struct.Struct("<" + code * width).unpack_from
    return [unpack(binary, offset + i * stride) for i in range(spec["count"])]


def triangle_indices(primitive, document, binary):
    if primitive.get("mode", 4) != 4:
        raise ValueError("Audit expects triangle primitives")
    if "indices" in primitive:
        return [row[0] for row in accessor(document, binary, primitive["indices"])]
    return list(range(document["accessors"][primitive["attributes"]["POSITION"]]["count"]))


def transform_point(point, node):
    if "matrix" in node:
        m = node["matrix"]
        return tuple(sum(m[j * 4 + i] * point[j] for j in range(3)) + m[12 + i] for i in range(3))
    x, y, z = [point[i] * node.get("scale", [1, 1, 1])[i] for i in range(3)]
    qx, qy, qz, qw = node.get("rotation", [0, 0, 0, 1])
    tx, ty, tz = 2 * (qy*z-qz*y), 2 * (qz*x-qx*z), 2 * (qx*y-qy*x)
    return (x + qw*tx + qy*tz-qz*ty + node.get("translation", [0, 0, 0])[0],
            y + qw*ty + qz*tx-qx*tz + node.get("translation", [0, 0, 0])[1],
            z + qw*tz + qx*ty-qy*tx + node.get("translation", [0, 0, 0])[2])


def world_point(point, index, nodes, parents):
    while index is not None:
        point = transform_point(point, nodes[index])
        index = parents.get(index)
    return point


def audit(path):
    document, binary = read_glb(path)
    nodes = document.get("nodes", [])
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}
    materials = document.get("materials", [])
    volume = CAMERAS.get(path.stem)
    rows, mesh_hashes = [], collections.defaultdict(list)
    for ni, node in enumerate(nodes):
        if "mesh" not in node:
            continue
        mesh = document["meshes"][node["mesh"]]
        stats = collections.Counter()
        seen = set()
        bounds = [[math.inf]*3, [-math.inf]*3]
        digest = hashlib.sha256()
        material_names = []
        for primitive in mesh["primitives"]:
            positions = accessor(document, binary, primitive["attributes"]["POSITION"])
            indices = triangle_indices(primitive, document, binary)
            digest.update(json.dumps({"positions": positions, "indices": indices,
                                      "material": primitive.get("material")}, separators=(",", ":")).encode())
            world = [world_point(p, ni, nodes, parents) for p in positions]
            for p in world:
                for axis in range(3):
                    bounds[0][axis] = min(bounds[0][axis], p[axis])
                    bounds[1][axis] = max(bounds[1][axis], p[axis])
            material = materials[primitive["material"]] if "material" in primitive else {}
            material_names.append(material.get("name", "<default>"))
            stats["surfaces"] += 1
            stats["vertices"] += len(positions)
            stats["triangles"] += len(indices) // 3
            double_sided = bool(material.get("doubleSided"))
            alpha = material.get("alphaMode", "OPAQUE")
            if double_sided:
                stats["double_sided_triangles"] += len(indices) // 3
            if alpha != "OPAQUE":
                stats["alpha_triangles"] += len(indices) // 3
            for i in range(0, len(indices), 3):
                p, q, r = [world[index] for index in indices[i:i+3]]
                u, v = [q[k]-p[k] for k in range(3)], [r[k]-p[k] for k in range(3)]
                normal = (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])
                area2 = sum(n*n for n in normal)
                if area2 <= 1e-18:
                    stats["degenerate_triangles"] += 1
                # Exact rounded geometry matches across surfaces in one node.
                vertices = [tuple(round(value, 7) for value in pt) for pt in (p, q, r)]
                key = tuple(sorted(vertices))
                if key in seen:
                    stats["coincident_triangle_candidates"] += 1
                seen.add(key)
                if max(p[1], q[1], r[1]) < -.001:
                    stats["entirely_below_floor_candidates"] += 1
                if volume and not double_sided and alpha == "OPAQUE" and area2 > 1e-18:
                    nearest_facing_corner = [volume[1 if normal[k] >= 0 else 0][k] for k in range(3)]
                    dot = sum(normal[k] * (nearest_facing_corner[k] - p[k]) for k in range(3))
                    if dot <= -1e-8:
                        stats["faces_away_from_entire_camera_volume_candidates"] += 1
        row = {"node": node.get("name", str(ni)), "mesh_index": node["mesh"],
               **dict(stats), "material_names": material_names,
               "bounds": [[round(v, 5) for v in line] for line in bounds]}
        rows.append(row)
        mesh_hashes[digest.hexdigest()].append(row["node"])
    total = collections.Counter()
    for row in rows:
        for key, value in row.items():
            if isinstance(value, int) and key != "mesh_index":
                total[key] += value
    canonical_materials = collections.defaultdict(list)
    for material in materials:
        value = {k: v for k, v in material.items() if k not in ("name", "extras")}
        canonical_materials[json.dumps(value, sort_keys=True)].append(material.get("name", "unnamed"))
    return {"path": path.relative_to(ROOT).as_posix(), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "bytes": path.stat().st_size, "mesh_nodes": len(rows),
            "unique_meshes": len(document.get("meshes", [])), "material_count": len(materials),
            "double_sided_materials": [m.get("name") for m in materials if m.get("doubleSided")],
            "embedded_images": len(document.get("images", [])), "totals": dict(total),
            "camera_volume": volume, "nodes": rows,
            "exact_local_geometry_material_duplicate_groups": [v for v in mesh_hashes.values() if len(v) > 1],
            "identical_material_definition_groups": [v for v in canonical_materials.values() if len(v) > 1]}


def texture_duplicates(folder):
    hashes = collections.defaultdict(list)
    for path in folder.rglob("*.png"):
        hashes[hashlib.sha256(path.read_bytes()).hexdigest()].append(path)
    groups = [[{"path": p.relative_to(ROOT).as_posix(), "bytes": p.stat().st_size} for p in paths]
              for paths in hashes.values() if len(paths) > 1]
    return {"groups": groups, "duplicate_file_bytes": sum(sum(p["bytes"] for p in g[1:]) for g in groups),
            "meaning": "Identical source PNG files; does not prove duplicate resident GPU textures."}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "deliverables/graphics-performance/indoor-audit.json")
    args = parser.parse_args()
    paths = [ROOT / "game/assets/admissions_room/admissions_studio.glb",
             ROOT / "game/assets/training_room/wordking_training_room.glb",
             ROOT / "game/assets/exhibits/furina/furina_splendor.glb"]
    paths += sorted((ROOT / "game/assets/university_hall").glob("*.glb"))
    result = {"schema_version": 1, "date": "2026-10-20",
              "method": "Read-only GLB binary inspection; no renderer, asset mutation or GPU performance claim.",
              "cautions": ["Source training GLB differs from loaded generated detail .res resources.",
                           "Candidate counts overlap and must not be added.",
                           "Back-facing candidates may still cast visible shadows. Retain shadow proxies or validate lighting.",
                           "Coincident candidates can be intentional different-material layered surfaces.",
                           "A merged mesh's surfaces are upper bounds, not observed runtime draw calls."],
              "assets": [audit(p) for p in paths],
              "university_texture_files": texture_duplicates(ROOT / "game/assets/university_hall")}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
    for asset in result["assets"]:
        print(json.dumps({"path": asset["path"], "mesh_nodes": asset["mesh_nodes"],
                          "materials": asset["material_count"], **asset["totals"]}, ensure_ascii=False))
    print(f"REPORT {args.output}")


if __name__ == "__main__":
    main()
