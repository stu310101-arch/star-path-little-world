"""Conservative offline cleanup of authored indoor export copies.

Keeps every vertex attribute, transform, visible silhouette and collision source.
Only zero-area/identical indexed triangles and specifically sealed floor bottoms
are removed. Backface culling requires a closed, consistently oriented manifold.
Editable .blend sources are never opened or written.
"""
from __future__ import annotations

import argparse
from collections import defaultdict
import hashlib
import json
from pathlib import Path
import struct

from audit_indoor_geometry import ROOT, accessor, read_glb, triangle_indices, world_point

EXCLUDED_CULL = ("leaf", "foliage", "grass", "glass", "hologram", "projection",
                 "screen", "hair", "furina", "water", "beam", "halo", "lens")


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def zero_area(a, b, c):
    # Exact arithmetic comparison: never discard merely small triangles.
    return cross(tuple(b[i]-a[i] for i in range(3)),
                 tuple(c[i]-a[i] for i in range(3))) == (0, 0, 0)


def closed_outward(positions, indices, winding=1):
    """All welded components must be closed, oriented and have outward volume.

    Exact position welding only. A near seam fails closed instead of being fused.
    winding=+1 for glTF counterclockwise; -1 for Godot clockwise.
    """
    weld, vertex_ids = {}, []
    for point in positions:
        key = tuple(point)
        if key not in weld:
            weld[key] = len(weld)
        vertex_ids.append(weld[key])
    edges, neighbors = defaultdict(list), defaultdict(list)
    faces = [indices[i:i+3] for i in range(0, len(indices), 3)]
    if not faces:
        return False, "empty"
    for fi, face in enumerate(faces):
        ids = [vertex_ids[i] for i in face]
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edges[(min(a, b), max(a, b))].append((fi, 1 if a < b else -1))
    for matches in edges.values():
        if len(matches) != 2 or matches[0][1] + matches[1][1] != 0:
            return False, "open_or_nonmanifold_or_inconsistent"
        a, b = matches[0][0], matches[1][0]
        neighbors[a].append(b)
        neighbors[b].append(a)
    visited = set()
    for start in range(len(faces)):
        if start in visited:
            continue
        stack, component = [start], []
        while stack:
            face = stack.pop()
            if face in visited:
                continue
            visited.add(face)
            component.append(face)
            stack.extend(n for n in neighbors[face] if n not in visited)
        # Use a component-local origin to limit cancellation for tiny props.
        origin = positions[faces[start][0]]
        volume6 = 0.0
        for fi in component:
            points = [tuple(positions[j][k]-origin[k] for k in range(3)) for j in faces[fi]]
            volume6 += dot(points[0], cross(points[1], points[2]))
        if volume6 * winding <= 0:
            return False, "inverted_or_zero_volume"
    return True, "closed_outward"


def under_sealed_floor(asset, node, points):
    # Admissions foundation top is y=-.02; tiles cover it. Never touch the
    # garden visible through the window, slab top/bevels, walls or desk contents.
    if asset == "admissions_studio" and node == "SM_Admissions_Architecture":
        return all(-8.56 < p[0] < 8.56 and -7.06 < p[2] < 7.06 and p[1] < -.025 for p in points)
    # Training tiles stand above a separate continuous plinth whose top is
    # y=-.01. Only the two named tile batches below that opaque cover qualify;
    # the plinth, grout-visible upper bevels and entrance remain intact.
    if asset == "training_runtime" and node in ("SM_Architecture_Limestone", "SM_Architecture_Limestone_Alternate"):
        return all(-10.26 < p[0] < 10.26 and -9.26 < p[2] < 9.26 and p[1] < -.015 for p in points)
    return False


def plan_surface(positions, indices, world_positions, *, asset, node, material,
                 opaque=True, winding=1):
    cleaned, counts, seen = [], {"degenerate": 0, "duplicate": 0, "buried": 0}, set()
    for offset in range(0, len(indices), 3):
        face = indices[offset:offset+3]
        if zero_area(*(positions[i] for i in face)):
            counts["degenerate"] += 1
            continue
        # Cyclic equality preserves winding. Different indices/UVs/materials,
        # reversed triangles and spatially coincident layers are not conflated.
        key = min(tuple(face), tuple(face[1:]+face[:1]), tuple(face[2:]+face[:2]))
        if key in seen:
            counts["duplicate"] += 1
            continue
        seen.add(key)
        cleaned.extend(face)
    can_cull, reason = False, "excluded_material"
    if opaque and not any(word in material.lower() for word in EXCLUDED_CULL):
        # Test topology BEFORE removing buried faces, which intentionally opens
        # inaccessible bottoms. No decimation or vertex welding is applied.
        can_cull, reason = closed_outward(positions, cleaned, winding)
    retained = []
    for offset in range(0, len(cleaned), 3):
        face = cleaned[offset:offset+3]
        if under_sealed_floor(asset, node, [world_positions[i] for i in face]):
            counts["buried"] += 1
        else:
            retained.extend(face)
    # Avoid invalid empty surfaces. Tiny all-degenerate surfaces stay untouched.
    if not retained:
        return {"indices": indices, "removed": {k: 0 for k in counts},
                "can_cull": False, "cull_reason": "empty_surface_retained"}
    return {"indices": retained, "removed": counts, "can_cull": can_cull, "cull_reason": reason}


def optimize_glb(path: Path, *, write=True):
    document, binary = read_glb(path)
    before_hash = hashlib.sha256(path.read_bytes()).hexdigest()
    nodes = document.get("nodes", [])
    parents = {child: i for i, node in enumerate(nodes) for child in node.get("children", [])}
    materials = document.get("materials", [])
    uses = defaultdict(list)
    for ni, node in enumerate(nodes):
        if "mesh" in node:
            uses[node["mesh"]].append(ni)
    material_eligible = defaultdict(list)
    plans, records = [], []
    for mi, mesh in enumerate(document.get("meshes", [])):
        if mi not in uses:
            continue
        ni = uses[mi][0]
        node = nodes[ni]
        for pi, primitive in enumerate(mesh["primitives"]):
            if primitive.get("mode", 4) != 4 or "targets" in primitive or any("skin" in nodes[n] for n in uses[mi]):
                raise ValueError("Only static triangle exports are permitted")
            positions = accessor(document, binary, primitive["attributes"]["POSITION"])
            indices = triangle_indices(primitive, document, binary)
            # Shared instances may sit elsewhere, so never apply a floor rule.
            world = [world_point(p, ni, nodes, parents) for p in positions]
            material = materials[primitive["material"]] if "material" in primitive else {}
            plan = plan_surface(positions, indices, world,
                                asset=path.stem if len(uses[mi]) == 1 else "",
                                node=node.get("name", ""), material=material.get("name", ""),
                                opaque=material.get("alphaMode", "OPAQUE") == "OPAQUE")
            if "material" in primitive:
                material_eligible[primitive["material"]].append(plan["can_cull"])
            record = {"node": node.get("name"), "surface": pi, "material": material.get("name"),
                      "before": len(indices)//3, "after": len(plan["indices"])//3,
                      "removed": plan["removed"], "cull_reason": plan["cull_reason"]}
            records.append(record)
            if indices != plan["indices"]:
                plans.append((primitive, plan["indices"]))
    culled = []
    for index, flags in material_eligible.items():
        if all(flags) and materials[index].get("doubleSided", False):
            materials[index]["doubleSided"] = False
            culled.append(materials[index].get("name"))
    if write and (plans or culled):
        buf = bytearray(binary)
        for primitive, indices in plans:
            while len(buf) % 4:
                buf.append(0)
            start = len(buf)
            buf.extend(struct.pack("<" + "I"*len(indices), *indices))
            vi = len(document["bufferViews"])
            document["bufferViews"].append({"buffer": 0, "byteOffset": start,
                                           "byteLength": len(indices)*4, "target": 34963})
            ai = len(document["accessors"])
            document["accessors"].append({"bufferView": vi, "componentType": 5125,
                                         "count": len(indices), "type": "SCALAR",
                                         "min": [min(indices)], "max": [max(indices)]})
            primitive["indices"] = ai
        # Keep original attributes/images byte-for-byte. Appended index slices
        # cost a little source disk space; the importer only uploads used slices.
        document["buffers"][0]["byteLength"] = len(buf)
        payload = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode()
        payload += b" " * ((-len(payload)) % 4)
        buf += b"\0" * ((-len(buf)) % 4)
        packed = struct.pack("<III", 0x46546C67, 2, 12+8+len(payload)+8+len(buf))
        packed += struct.pack("<II", len(payload), 0x4E4F534A) + payload
        packed += struct.pack("<II", len(buf), 0x004E4942) + buf
        path.write_bytes(packed)
    return {"path": path.relative_to(ROOT).as_posix(), "source_sha256": before_hash,
            "output_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "triangles_before": sum(r["before"] for r in records),
            "triangles_after": sum(r["after"] for r in records),
            "backface_culled_materials": culled, "surfaces": records, "written": write}


def runtime_plan(source, output):
    data = json.loads(source.read_text(encoding="utf-8-sig"))
    eligible = defaultdict(list)
    plans = []
    for entry in data["surfaces"]:
        plan = plan_surface(entry["positions"], entry["indices"], entry["world_positions"],
                            asset="training_runtime", node=entry["node"],
                            material=entry["material_name"], opaque=entry["opaque"], winding=-1)
        eligible[entry["material_key"]].append(plan["can_cull"])
        plans.append({"key": entry["key"], "material_key": entry["material_key"], **plan,
                      "before": len(entry["indices"])//3, "after": len(plan["indices"])//3})
    # Shared materials change only if every referencing surface passed.
    safe = [key for key, flags in eligible.items() if all(flags)]
    result = {"surfaces": plans, "safe_material_keys": safe}
    output.write_text(json.dumps(result, separators=(",", ":")), encoding="utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--runtime-plan", type=Path)
    parser.add_argument("--plan-output", type=Path)
    args = parser.parse_args()
    if args.runtime_plan:
        runtime_plan(args.runtime_plan, args.plan_output)
        return
    paths = [ROOT/"game/assets/admissions_room/admissions_studio.glb"]
    paths += [ROOT/"game/assets/university_hall"/name for name in
              ("atrium.glb", "gallery.glb", "exhibit_kit.glb", "feature_book.glb")]
    report = {"method": __doc__, "assets": [optimize_glb(p, write=not args.dry_run) for p in paths]}
    out = ROOT/"deliverables/graphics-performance"/("indoor-dry-run.json" if args.dry_run else "indoor-optimization.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    for record in report["assets"]:
        print(json.dumps({k: record[k] for k in ("path", "triangles_before", "triangles_after",
                                               "backface_culled_materials")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
