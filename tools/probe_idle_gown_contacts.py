"""Read-only localization of inherited shoulder/gown overlap in Idle.

Run with the four-scene .blend. Writes only a new JSON report, never a blend.
The original Jump gown cutting geometry defines the pre-existing armhole
convention. All contacts remain reported, including unknown rendered faces.
"""
import json
import sys
from collections import Counter
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_sleeve_garment_contact import (
    Surface, visible_surfaces, compare, segment_triangle,
)

source = next(s for s in bpy.data.scenes if s.name.startswith("03_JUMP"))
source_gown = next(o for o in source.objects
                   if o.get("graduate_role") == "01 | Pleated bachelor gown")
source_nverts = len(source_gown.data.vertices)
source_faces = {tuple(sorted(p.vertices)): p.index for p in source_gown.data.polygons}
sewn_faces = {p.index for p in source_gown.data.polygons
              if p.center.z > 3.05 and abs(p.center.x) > .34}


def ranges(points):
    return [[min(p[d] for p in points), max(p[d] for p in points)]
            for d in range(3)] if points else None


report = {
    "source": bpy.data.filepath,
    "convention": "Original Jump gown rest face center z > 3.05 and abs(x) > .34 is the pre-existing sewn armhole overlap region",
    "segment_measure": "Triangle intersection segment length, not penetration depth",
    "saved_blend": False,
    "samples": [],
}
for prefix, frame in [("03_JUMP", 1), ("04_IDLE", 1), ("04_IDLE", 51), ("04_IDLE", 91)]:
    scene = next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    roles = ["02 | Bell sleeve L", "02 | Bell sleeve R", "01 | Pleated bachelor gown"]
    objects = [next(o for o in scene.objects if o.get("graduate_role") == role)
               for role in roles]
    for surface in ("simulation", "rendered"):
        with visible_surfaces(scene, objects, surface):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            meshes = [Surface(o) for o in objects]
            gown = meshes[-1]
            # Solidify retains vertex ordering in this asset. Canonical vertex
            # IDs map front/back copies to the source cutting polygon. Rims or
            # unexpected topology stay explicitly unknown instead of excluded.
            source_polygon = {}
            for index, polygon in enumerate(gown.source_polygons):
                key = tuple(sorted({v % source_nverts for v in polygon}))
                source_polygon[index] = source_faces.get(key)
            for side, sleeve in zip(("L", "R"), meshes[:2]):
                evidence = compare(sleeve, gown, False, 1e-6)
                counts = Counter()
                groups = {key: [] for key in ("sewn_joint", "retained_gown", "unknown")}
                rings = Counter()
                for (a, b), length in zip(evidence["triangle_pairs"], evidence["intersection_segment_lengths_m"]):
                    original = source_polygon[gown.polygons[b]]
                    kind = "unknown" if original is None else ("sewn_joint" if original in sewn_faces else "retained_gown")
                    counts[kind] += 1
                    triangles = [[mesh.points[v] for v in mesh.triangles[i]]
                                 for mesh, i in ((sleeve, a), (gown, b))]
                    hits = []
                    for tri, other, normal in ((triangles[0], triangles[1], gown.normals[b]),
                                               (triangles[1], triangles[0], sleeve.normals[a])):
                        for edge in range(3):
                            point = segment_triangle(tri[edge], tri[(edge + 1) % 3], other, normal, 1e-6)
                            if point is not None:
                                hits.append(tuple(point))
                    ring_ids = sorted({(v % 545) // 32 for v in sleeve.triangles[a]})
                    for ring in ring_ids:
                        rings[str(ring)] += 1
                    groups[kind].append({"length_m": length, "intersection_points_m": hits,
                                         "sleeve_rings": ring_ids, "source_gown_face": original})
                sample = {"scene": scene.name, "frame": frame, "surface": surface,
                          "side": side, "crossings": evidence["crossings"],
                          "counts": dict(counts), "sleeve_ring_occurrences": dict(rings),
                          "categories": {}}
                for kind, entries in groups.items():
                    points = [p for entry in entries for p in entry["intersection_points_m"]]
                    sample["categories"][kind] = {
                        "count": len(entries), "intersection_bbox_xyz_metres": ranges(points),
                        "maximum_intersection_segment_m": max((e["length_m"] for e in entries), default=0),
                        "source_gown_faces": sorted({e["source_gown_face"] for e in entries if e["source_gown_face"] is not None}),
                    }
                report["samples"].append(sample)
                print("IDLE_GOWN_PROBE", scene.name, frame, surface, side, sample["counts"], flush=True)

out = ROOT / "art/Graduate/animation/idle-gown-contact-localization.json"
out.write_text(json.dumps(report, indent=2), encoding="utf-8")
print("IDLE_GOWN_PROBE_SAVED", str(out), flush=True)
