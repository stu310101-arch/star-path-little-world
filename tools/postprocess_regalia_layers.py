"""Small final neck/accessory pass, preserving finished lower cloth and gait.

Run by the owner of the sole background Blender process, for example:
 blender -b <candidate.blend> --python-exit-code 1 --python tools/postprocess_regalia_layers.py -- \
   --output <new-postprocessed.blend> --scene-prefix 01_WALK

Without --scene-prefix all four clips are processed. --probe-frames 1,9,19
only writes the report, not a blend or morphs. Source paths are never silently
overwritten. The script preserves scene frame ranges/FPS and rig actions.

Gown: only another bounded 12 mm anatomical-neck projection with denser
samples, not the sleeve/gown solver. Front stoles: only rows 0--2 may move;
rows 3--tip and the existing bars stay unchanged. Rear collar: restore its
ordered four-column cross sections, then translate complete rows. Shared
front/rear sewn rows share a translation group. Gown and actual neck Skin
clearance are solved together. Shirts keep their positions, with fabric
thickness reduced from the inherited 4.375 mm to 0.8 mm.

Reports include exact MID-SURFACE crossings before/after, not a false zero
for rendered shells or sewn seams. A final rendered audit remains required.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
import sys
import time
from types import SimpleNamespace

import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from regalia_neck_clearance import BODY_ROLE, _samples, build_neck_collider, clear_neck
from probe_regalia_neck import local_faces
from repair_graduate_regalia import triangles
from simulate_portal_cloth import SCALE, SkinBinding, bake_keys, evaluated_points
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import compare, visible_surfaces

GOWN = "01 | Pleated bachelor gown"
_ROW_LAYOUT_CACHE = {}


def array_surface(points, faces):
    vectors = [Vector(p) for p in points]
    faces = [tuple(int(i) for i in face) for face in faces]
    normals = []
    for a, b, c in faces:
        normal = (vectors[b] - vectors[a]).cross(vectors[c] - vectors[a])
        normals.append(normal.normalized() if normal.length > 1e-12 else None)
    return SimpleNamespace(points=vectors, triangles=faces, normals=normals,
                           seam=[False] * len(faces),
                           tree=BVHTree.FromPolygons(vectors, faces, all_triangles=True))


def compact_crossings(a, b, same=False):
    result = compare(a, b, same, 1e-6)
    return {key: result[key] for key in ("crossings", "maximum_intersection_segment_m",
                                         "bvh_candidates", "adjacent_excluded", "seam_excluded")}


def exact_neck_report(gown_points, gown_faces, layer_points, layer_faces, neck, *,
                      skin_surface=None, gown_surface=None):
    """Count actual midpoint intersections; no source seam masks are removed."""
    gown = gown_surface if gown_surface is not None else array_surface(gown_points, gown_faces)
    skin = skin_surface if skin_surface is not None else array_surface(neck.points, neck.triangles)
    surfaces = {role: array_surface(points, layer_faces[role]) for role, points in layer_points.items()}
    result = {"gown_skin_selected_actual_triangles": compact_crossings(gown, skin), "layers": {}}
    for role, surface in surfaces.items():
        result["layers"][role] = {"skin": compact_crossings(surface, skin),
                                  "gown": compact_crossings(surface, gown)}
        if "back collar" in role:
            result["layers"][role]["self"] = compact_crossings(surface, surface, True)
    back_role = next(role for role in surfaces if "back collar" in role)
    result["front_back_midpoint_seams"] = {
        role: compact_crossings(surface, surfaces[back_role])
        for role, surface in surfaces.items() if role.endswith((" L", " R"))}
    result["scope"] = "Actual selected Skin triangles, no artificial caps; includes their full finite geometry. Rendered Solidify and white-shirt pairs require final audit."
    result["self_limit"] = "Self triangles sharing source vertices are excluded, consistent with the full audit."
    return result


def ordered_neck_rows(posed):
    """Restore width ordering using real existing boundary points, not a new design."""
    result = {role: np.asarray(points, dtype=float).copy() for role, points in posed.items()}
    left = next(role for role in result if role.endswith(" L"))
    right = next(role for role in result if role.endswith(" R"))
    back = next(role for role in result if "back collar" in role)
    if len(result[left]) != 41 or len(result[right]) != 41 or len(result[back]) != 52:
        raise ValueError("Expected the existing 41/41/52-vertex graduate stole topology")
    for row in range(13):
        ids = slice(row * 4, row * 4 + 4)
        a, d = result[back][row * 4].copy(), result[back][row * 4 + 3].copy()
        result[back][ids] = a + np.array((0., .075, .925, 1.))[:, None] * (d - a)
    for role in (left, right):
        for row in (1, 2):
            a, d = result[role][row * 4].copy(), result[role][row * 4 + 3].copy()
            result[role][row * 4:row * 4 + 4] = a + np.array((0., .07, .93, 1.))[:, None] * (d - a)
    result[left][:4] = result[back][:4]
    result[right][:4] = result[back][-4:]
    return result, (left, right, back)


def row_layout(names, vertex_counts, faces):
    """Cache only static indices/weights, with complete topology as the key.

    Posed coordinates, areas, normals, corrections and collision results are
    never reused across frames. Keep original sample and contribution order.
    """
    canonical_faces = tuple(tuple(tuple(int(i) for i in face) for face in faces[role]) for role in names)
    key = (names, tuple(vertex_counts[role] for role in names), canonical_faces)
    if key in _ROW_LAYOUT_CACHE:
        return _ROW_LAYOUT_CACHE[key]
    left, right, back = names
    offsets, cursor = {}, 0
    for role in names:
        offsets[role] = cursor
        cursor += vertex_counts[role]
    all_faces = np.asarray([tuple(offsets[role] + i for i in face) for role in names for face in faces[role]], dtype=np.int32)
    groups = []

    def row_ids(role, row):
        start = offsets[role] + 4 * row
        return list(range(start, start + 4))

    # One ordered chain: L row2 -> L row1 -> sewn L/back -> back -> sewn R/back -> R1 -> R2.
    groups.extend((row_ids(left, 2), row_ids(left, 1)))
    groups.append(row_ids(left, 0) + row_ids(back, 0))
    groups.extend(row_ids(back, row) for row in range(1, 12))
    groups.append(row_ids(back, 12) + row_ids(right, 0))
    groups.extend((row_ids(right, 1), row_ids(right, 2)))
    group_id = np.full(cursor, -1, dtype=int)
    for gid, vertices in enumerate(groups):
        group_id[vertices] = gid
    active_faces = all_faces[np.any(group_id[all_faces] >= 0, axis=1)]
    samples = []
    for kind, ids, weights in _samples(cursor, active_faces, 2):
        ids = np.asarray(ids, dtype=np.int32)
        contribution = {}
        for vertex, weight in zip(ids, weights):
            gid = int(group_id[vertex])
            if gid >= 0:
                contribution[gid] = contribution.get(gid, 0.) + weight
        if contribution:
            gids = np.asarray(list(contribution), dtype=int)
            group_weights = np.asarray(list(contribution.values()))
            denominator = float(np.dot(group_weights, group_weights))
            samples.append((kind, ids, weights, gids, group_weights, denominator))
    layout = offsets, groups, active_faces, samples
    _ROW_LAYOUT_CACHE[key] = layout
    return layout


def clear_accessory_rows(posed, faces, gown_points, gown_faces, neck, *,
                         gown_gap=.005, skin_gap=.004, iterations=24, max_shift=.012,
                         gown_surface=None):
    """Pure arrays: translate sewn cross-strip rows, retaining all four columns.

    Return (role -> points, report). Gown/skin normals retain real winding.
    Both constraints use finite nearest triangles within 35/30 mm. Triangle
    orientation/area guards reject step proposals that invert the cleaned
    strip. Corrections beyond the budget remain explicitly unresolved.
    """
    original = {role: np.asarray(points, dtype=float).copy() for role, points in posed.items()}
    cleaned, (left, right, back) = ordered_neck_rows(original)
    names = (left, right, back)
    offsets, groups, active_faces, samples = row_layout(names, {role: len(cleaned[role]) for role in names}, faces)
    base = np.concatenate([cleaned[role] for role in names])
    coordinates = base.copy()
    source_normals = np.cross(base[active_faces[:, 1]] - base[active_faces[:, 0]],
                              base[active_faces[:, 2]] - base[active_faces[:, 0]])
    source_area = np.linalg.norm(source_normals, axis=1)
    usable_area = source_area > 1e-11
    source_unit = source_normals / np.maximum(source_area[:, None], 1e-16)
    gown_tree = gown_surface.tree if gown_surface is not None else BVHTree.FromPolygons(
        [Vector(p) for p in gown_points], [tuple(int(i) for i in face) for face in gown_faces], all_triangles=True)
    constraint_cache = {}
    query_count = cache_hits = 0

    def constraints(point):
        nonlocal query_count, cache_hits
        query_count += 1
        # Exact bytes, no spatial rounding or approximate reuse. Duplicate
        # samples still contribute separately to sums/counts in original order.
        key = point.tobytes()
        cached = constraint_cache.get(key)
        if cached is not None:
            cache_hits += 1
            return cached
        found = []
        skin = neck.query(point, max_distance=.030)
        if skin is not None:
            found.append(("skin", skin["normal"], skin["signed_gap_m"], skin_gap))
        hit, normal, index, distance = gown_tree.find_nearest(Vector(point), .035)
        if hit is not None:
            delta = np.asarray(point) - np.asarray(hit)
            normal = np.asarray(normal)
            signed = float(np.dot(delta, normal))
            # Finite boundary, not an infinite extrapolated shoulder plane.
            if np.linalg.norm(delta - signed * normal) <= .002:
                found.append(("gown", normal, signed, gown_gap))
        cached = tuple(found)
        constraint_cache[key] = cached
        return cached

    def measure(points):
        counts, penetrations = Counter(), Counter()
        minimum, worst = {}, []
        for kind, ids, weights, gids, group_weights, denominator in samples:
            point = weights @ points[ids]
            for target, normal, gap, required in constraints(point):
                minimum[target] = min(minimum.get(target, float("inf")), gap)
                if gap < required - .00005:
                    counts[target] += 1
                    if gap < -.00005:
                        penetrations[target] += 1
                    worst.append({"target": target, "kind": kind, "vertices": ids.tolist(),
                                  "signed_gap_m": gap, "missing_clearance_m": required - gap,
                                  "groups": gids.tolist(), "point_m": point.tolist()})
        worst.sort(key=lambda e: e["missing_clearance_m"], reverse=True)
        return {"unresolved_by_target": dict(counts), "unresolved_samples": sum(counts.values()),
                "penetrating_by_target": dict(penetrations), "penetrating_samples": sum(penetrations.values()),
                "minimum_signed_gap_m": minimum, "worst_examples": worst[:24]}

    before = measure(coordinates)
    shift = np.zeros((len(groups), 3))
    cap_ids, rejected_steps = set(), 0
    used = 0
    for iteration in range(iterations):
        sums, counts = np.zeros_like(shift), np.zeros(len(groups))
        for _, ids, weights, gids, group_weights, denominator in samples:
            point = weights @ coordinates[ids]
            for target, normal, gap, required in constraints(point):
                if gap >= required - .00005:
                    continue
                delta = normal * (required - gap)
                for gid, weight in zip(gids, group_weights):
                    sums[gid] += delta * weight / denominator
                    counts[gid] += 1
        active = counts > 0
        if not np.any(active):
            break
        steps = np.zeros_like(shift)
        steps[active] = sums[active] / counts[active, None]
        # Small correction-field smoothing, never smoothing the authored cloth.
        smoothed = steps.copy()
        for gid in range(len(groups)):
            neighbors = [i for i in (gid - 1, gid + 1) if 0 <= i < len(groups)]
            smoothed[gid] = .9 * steps[gid] + .1 * np.mean(steps[neighbors], axis=0)
        lengths = np.linalg.norm(smoothed, axis=1)
        smoothed *= np.minimum(1., .002 / np.maximum(lengths, 1e-16))[:, None]
        proposal = shift + smoothed
        lengths = np.linalg.norm(proposal, axis=1)
        cap_ids.update(int(i) for i in np.flatnonzero(lengths > max_shift))
        proposal *= np.minimum(1., max_shift / np.maximum(lengths, 1e-16))[:, None]
        accepted = False
        for factor in (1., .5, .25, .125, .0625):
            candidate_shift = shift + factor * (proposal - shift)
            candidate = base.copy()
            for gid, vertices in enumerate(groups):
                candidate[vertices] += candidate_shift[gid]
            normals = np.cross(candidate[active_faces[:, 1]] - candidate[active_faces[:, 0]],
                               candidate[active_faces[:, 2]] - candidate[active_faces[:, 0]])
            signed_area = np.einsum("ij,ij->i", normals, source_unit)
            if np.all(signed_area[usable_area] > .04 * source_area[usable_area]):
                accepted = True
                break
            rejected_steps += 1
        if not accepted:
            break
        movement = float(np.max(np.linalg.norm(candidate - coordinates, axis=1)))
        coordinates, shift = candidate, candidate_shift
        used = iteration + 1
        if movement < 1e-7:
            break
    result = {role: coordinates[offsets[role]:offsets[role] + len(cleaned[role])].copy() for role in names}
    restoration = {role: float(np.max(np.linalg.norm(cleaned[role] - original[role], axis=1))) for role in names}
    movement = {role: float(np.max(np.linalg.norm(result[role] - original[role], axis=1))) for role in names}
    lower_equal = {role: bool(np.array_equal(result[role][12:], original[role][12:])) for role in (left, right)}
    if not all(lower_equal.values()):
        raise AssertionError("Accessory pass changed a protected lower stole vertex")
    after = measure(coordinates)
    return result, {"before_row_solve": before, "after": after,
                    "iterations": used, "maximum_group_shift_m": float(np.max(np.linalg.norm(shift, axis=1))),
                    "group_shift_limit_m": max_shift, "capped_group_ids": sorted(cap_ids),
                    "row_restore_max_m": restoration, "total_vertex_shift_m": movement,
                    "triangle_orientation_rejected_steps": rejected_steps,
                    "lower_stoles_exactly_preserved": lower_equal,
                    "left_seam_gap_m": float(np.max(np.linalg.norm(result[left][:4] - result[back][:4], axis=1))),
                    "right_seam_gap_m": float(np.max(np.linalg.norm(result[right][:4] - result[back][-4:], axis=1))),
                    "combined_vertex_offsets": offsets,
                    "constraint_queries": query_count, "constraint_cache_hits": cache_hits,
                    "constraint_cache_unique_points": len(constraint_cache),
                    "method": "Ordered width rows and shared sewn translation groups; simultaneous actual Skin/gown clearance. No rendered seam intersections hidden."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--scene-prefix", nargs="+", default=("01_WALK", "02_RUN", "03_JUMP", "04_IDLE"))
    parser.add_argument("--probe-frames", help="Comma-separated frames; report-only, no blend/morph writes")
    parser.add_argument("--row-iterations", type=int, default=24)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if output == Path(bpy.data.filepath).resolve():
        raise ValueError("--output must differ from the loaded source blend")
    report_path = args.report or output.with_suffix(".postprocess.json")
    selected = [scene for scene in bpy.data.scenes if any(scene.name.startswith(p) for p in args.scene_prefix)]
    if not selected:
        raise ValueError("No matching animation scenes")
    report = {"source_blend": bpy.data.filepath, "output": str(output), "complete": False,
              "probe_only": bool(args.probe_frames), "clips": {},
              "scope": "Gown neckline, upper stole rows and back collar only; shirt thickness. Body, sleeves, lower stoles, bars and rig actions preserved.",
              "final_rendered_audit_required": True}

    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    initial_scene = bpy.context.window.scene
    started = time.perf_counter()
    for scene in selected:
        if scene.frame_start != 1:
            raise ValueError("Existing loop baker requires authored frame_start=1; refusing retiming")
        original_timing = (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
        roles = {o.get("graduate_role"): o for o in scene.objects
                 if o.type == "MESH" and o.get("graduate_role") and not o.get("preview_fx")}
        gown, body = roles[GOWN], roles[BODY_ROLE]
        stoles = {role: obj for role, obj in roles.items() if role.startswith("03 |")}
        shirts = [obj for role, obj in roles.items() if role.startswith("05 |")]
        rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
        action = rig.animation_data.action if rig.animation_data else None
        objects = [gown, *stoles.values()]
        topology = {obj: np.asarray(triangles(obj), dtype=np.int32) for obj in objects}
        layer_faces = {role: topology[obj] for role, obj in stoles.items()}
        bindings = {obj: SkinBinding(obj, rig) for obj in objects}
        samples = {obj: [] for obj in objects}
        frames = [int(x) for x in args.probe_frames.split(",")] if args.probe_frames else range(scene.frame_start, scene.frame_end + 1)
        clip = {"timing_before": original_timing, "frames": [], "shirt_thickness_m": .0008,
                "shirt_thickness_applied": not bool(args.probe_frames)}
        report["clips"][scene.name] = clip
        for shirt in shirts:
            for modifier in shirt.modifiers:
                if modifier.type == "SOLIDIFY" and not args.probe_frames:
                    modifier.thickness = .0008 / SCALE
                    modifier.offset = 0
        with visible_surfaces(scene, [body, *objects], "simulation"):
            for frame in frames:
                if not scene.frame_start <= frame <= scene.frame_end:
                    raise ValueError("Probe frame outside authored range")
                began = time.perf_counter()
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                neck = build_neck_collider(body)
                gown_original = evaluated_points(gown)
                posed = {role: evaluated_points(obj) for role, obj in stoles.items()}
                skin_surface = array_surface(neck.points, neck.triangles)
                before = exact_neck_report(gown_original, topology[gown], posed, layer_faces, neck,
                                           skin_surface=skin_surface)
                gown_points, neck_report = clear_neck(
                    gown_original, local_faces(gown_original, topology[gown], neck.bounds, .055), neck,
                    margin=.004, allow_neckline_reshape=True, support_radius=.055,
                    max_correction=.012, sample_density=2, iterations=24)
                gown_surface = array_surface(gown_points, topology[gown])
                fixed, row_report = clear_accessory_rows(posed, layer_faces, gown_points, topology[gown], neck,
                                                        iterations=args.row_iterations, gown_surface=gown_surface)
                after = exact_neck_report(gown_points, topology[gown], fixed, layer_faces, neck,
                                          skin_surface=skin_surface, gown_surface=gown_surface)
                if not args.probe_frames:
                    samples[gown].append(np.asarray(bindings[gown].inverse_points(gown_points)))
                    for role, obj in stoles.items():
                        samples[obj].append(np.asarray(bindings[obj].inverse_points(fixed[role])))
                neck_report.pop("collider", None)
                entry = {"frame": frame, "seconds": round(time.perf_counter() - began, 3),
                         "gown_neck": neck_report, "rows": row_report,
                         "exact_midpoint_before": before, "exact_midpoint_after": after}
                clip["frames"].append(entry)
                checkpoint()
                print("REGALIA_ACCESSORY_POSTPASS", scene.name, frame,
                      "gown_skin", before["gown_skin_selected_actual_triangles"]["crossings"],
                      after["gown_skin_selected_actual_triangles"]["crossings"],
                      "rows_unresolved", row_report["after"]["unresolved_samples"],
                      "max_row_shift", row_report["maximum_group_shift_m"], entry["seconds"], flush=True)
        if not args.probe_frames:
            for obj in objects:
                if obj.data.users > 1:
                    obj.data = obj.data.copy()
                label = "Regalia neck accessory finish | " + obj.get("graduate_role")
                if scene.name.startswith("03_JUMP"):
                    bake_keys(obj, samples[obj], scene.frame_start, label)
                else:
                    bake_loop(obj, samples[obj], label)
        current_timing = (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
        if current_timing != original_timing or (rig.animation_data.action if rig.animation_data else None) != action:
            raise AssertionError("Accessory pass changed authored timing or rig action")
        clip["timing_after"] = current_timing
        if not args.probe_frames:
            recovery = output.with_name(output.stem + "_Checkpoint.blend")
            bpy.context.preferences.filepaths.save_version = 0
            bpy.ops.wm.save_as_mainfile(filepath=str(recovery))
            clip["recovery_blend"] = str(recovery)
        checkpoint()
    bpy.context.window.scene = initial_scene
    if not args.probe_frames:
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report["complete"] = True
    report["seconds"] = round(time.perf_counter() - started, 3)
    report["asset_saved"] = not bool(args.probe_frames)
    checkpoint()
    print("REGALIA_ACCESSORY_POSTPASS_DONE", str(output), str(report_path), report["seconds"], flush=True)


if __name__ == "__main__":
    main()
