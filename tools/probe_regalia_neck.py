"""Read-only representative-frame neck solver probe; no Blender asset saves.

Run in the one background Blender owned by the parent task:
  blender -b <input.blend> --python-exit-code 1 --python tools/probe_regalia_neck.py -- \
    --output art/Graduate/animation/regalia-neck-probe.json

Default frames: Idle 1/51/91, Walk 9, Run 7, Jump 27. Only a JSON report is
written. Posed midpoint cloth geometry is copied to NumPy; corrected results
are measured but are never written back to objects or shape keys. Visibility
and modifier switches used to read the midpoint surface are restored.

IMPORTANT: the 25 mm gown displacement budget is relative to the loaded file.
Use the pre-neck GameReady source to verify a single 25 mm repair. A candidate
already containing a 12 mm repair instead tests an additional displacement.
Existing stoles/shirts are probed independently; they are not reattached to
the hypothetical corrected gown. Exact rendered intersections need the final
pair audit; this script only tests sampled finite-surface constraints.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from regalia_neck_clearance import BODY_ROLE, build_neck_collider, clear_neck
from simulate_portal_cloth import evaluated_points
from validate_sleeve_garment_contact import visible_surfaces

GOWN = "01 | Pleated bachelor gown"
DEFAULT_SAMPLES = (("04_IDLE", (1, 51, 91)), ("01_WALK", (9,)),
                   ("02_RUN", (7,)), ("03_JUMP", (27,)))


def triangles(obj):
    """Match the repair's FIXED quad triangulation without adding vertices."""
    obj.data.calc_loop_triangles()
    ngon_triangles = {}
    for triangle in obj.data.loop_triangles:
        ngon_triangles.setdefault(triangle.polygon_index, []).append(tuple(triangle.vertices))
    result = []
    for polygon in obj.data.polygons:
        ids = tuple(polygon.vertices)
        if len(ids) == 3:
            result.append(ids)
        elif len(ids) == 4:
            result.extend(((ids[0], ids[1], ids[2]), (ids[0], ids[2], ids[3])))
        else:
            result.extend(ngon_triangles[polygon.index])
    return np.asarray(result, dtype=np.int32)


def local_faces(points, faces, bounds, padding):
    """Conservative triangle AABB pruning before dense sample construction."""
    if not len(faces):
        return faces
    corners = points[faces]
    lo, hi = np.asarray(bounds)
    keep = (np.all(corners.max(axis=1) >= lo - padding, axis=1)
            & np.all(corners.min(axis=1) <= hi + padding, axis=1))
    return faces[keep]


def combine_layers(objects, points, faces):
    unique, lookup, maps, all_faces = [], {}, {}, []
    degenerate = 0
    for obj in objects:
        mapping = []
        for point in points[obj]:
            key = tuple(np.round(point, 8))
            if key not in lookup:
                lookup[key] = len(unique)
                unique.append(point)
            mapping.append(lookup[key])
        maps[obj.get("graduate_role")] = mapping
        for face in faces[obj]:
            mapped = tuple(mapping[i] for i in face)
            if len(set(mapped)) < 3:
                degenerate += 1
            else:
                all_faces.append(mapped)
    return np.asarray(unique, dtype=np.float64), np.asarray(all_faces, dtype=np.int32), maps, degenerate


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "art/Graduate/animation/regalia-neck-probe.json")
    parser.add_argument("--only", choices=("all", "gown", "layers"), default="all")
    parser.add_argument("--gown-density", type=int, choices=(1, 2, 3), default=1)
    parser.add_argument("--layer-density", type=int, choices=(1, 2, 3), default=2)
    parser.add_argument("--samples", nargs="+", metavar="PREFIX=1,51,91")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    samples = DEFAULT_SAMPLES
    if args.samples:
        samples = [(value.split("=", 1)[0], tuple(int(n) for n in value.split("=", 1)[1].split(",")))
                   for value in args.samples]
    report = {"source_blend": bpy.data.filepath, "complete": False,
              "asset_saved": False, "mesh_or_morph_written": False,
              "method": "Representative-frame bounded anatomical neck samples on copied posed midpoint cloth",
              "budget_reference": "Loaded input coordinates; previous candidate repairs are not subtracted",
              "layers_reference": "Existing loaded stoles/shirts; not reattached to hypothetical corrected gown",
              "exact_rendered_intersection_proof": False, "clips": {}}

    def checkpoint():
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")

    old_scene = bpy.context.window.scene
    started = time.perf_counter()
    try:
        for prefix, frames in samples:
            scene = next((s for s in bpy.data.scenes if s.name.startswith(prefix)), None)
            if scene is None:
                raise ValueError("Missing requested scene prefix " + prefix)
            roles = {o.get("graduate_role"): o for o in scene.objects
                     if o.type == "MESH" and o.get("graduate_role") and not o.get("preview_fx")}
            body, gown = roles[BODY_ROLE], roles[GOWN]
            layers = [o for role, o in roles.items() if role.startswith(("03 |", "05 |"))]
            measured = [gown] if args.only == "gown" else layers if args.only == "layers" else [gown, *layers]
            topology = {o: triangles(o) for o in measured}
            keys = gown.data.shape_keys
            existing_neck_keys = bool(keys and any("neck" in k.name.lower() for k in keys.key_blocks))
            report["clips"][scene.name] = []
            with visible_surfaces(scene, [body, *measured], "simulation"):
                for frame in frames:
                    if not scene.frame_start <= frame <= scene.frame_end:
                        raise ValueError("Requested frame outside the clip: " + str(frame))
                    began = time.perf_counter()
                    scene.frame_set(frame)
                    bpy.context.view_layer.update()
                    neck = build_neck_collider(body)
                    points = {o: evaluated_points(o) for o in measured}
                    entry = {"frame": frame, "gown_has_existing_neck_shape_keys": existing_neck_keys,
                             "neck_selection": neck.selection_report}
                    if args.only != "layers":
                        faces = local_faces(points[gown], topology[gown], neck.bounds, .030 + .025)
                        _, result = clear_neck(points[gown], faces, neck, margin=.004,
                                               allow_neckline_reshape=True, support_radius=.055,
                                               max_correction=.025, iterations=24,
                                               sample_density=args.gown_density)
                        result.pop("collider", None)
                        result["faces_total"] = len(topology[gown])
                        result["faces_local"] = len(faces)
                        entry["gown"] = result
                    if args.only != "gown" and layers:
                        layer_points, layer_faces, maps, degenerate = combine_layers(layers, points, topology)
                        faces = local_faces(layer_points, layer_faces, neck.bounds, .030 + .012)
                        _, result = clear_neck(layer_points, faces, neck, margin=.004,
                                               sample_density=args.layer_density)
                        result.pop("collider", None)
                        result["faces_total"] = len(layer_faces)
                        result["faces_local"] = len(faces)
                        result["degenerate_faces_after_seam_weld"] = degenerate
                        result["object_vertex_maps"] = maps
                        entry["layers"] = result
                    entry["seconds"] = round(time.perf_counter() - began, 3)
                    report["clips"][scene.name].append(entry)
                    checkpoint()
                    compact = {role: {"before_penetrating": entry[role]["before"]["penetrating_samples"],
                                      "after_penetrating": entry[role]["after"]["penetrating_samples"],
                                      "unresolved": entry[role]["after"]["unresolved_samples"],
                                      "max_shift_m": entry[role]["maximum_vertex_shift_m"],
                                      "capped_vertices": len(entry[role]["capped_vertex_ids"])}
                               for role in ("gown", "layers") if role in entry}
                    print("REGALIA_NECK_PROBE", scene.name, frame, json.dumps(compact), entry["seconds"], flush=True)
    finally:
        bpy.context.window.scene = old_scene
    report["complete"] = True
    report["seconds"] = round(time.perf_counter() - started, 3)
    checkpoint()
    print("REGALIA_NECK_PROBE_DONE", str(args.output), report["seconds"], flush=True)


if __name__ == "__main__":
    main()
