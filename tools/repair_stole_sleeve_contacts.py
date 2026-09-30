"""Whole-row stole corrections against unchanged real garment/skin surfaces.

Use on the thin-fabric candidate. --probe writes JSON only; otherwise save a
distinct output. --samples accepts PREFIX=frame,frame; --all-frames processes
all four complete clips, smooths corrections, reprojects and bakes full clips.
Sleeves are never edited. Jump is always non-looping.
The solver also separates non-adjacent self intersections using signed
barycentric constraints; shared row translations preserve strip widths/seams.
"""
from pathlib import Path
import argparse
import json
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from finish_regalia_exact_contacts import (
    intersection_constraints, sewn_row_groups, additive_key,
)
from postprocess_regalia_layers import array_surface, compact_crossings
from repair_graduate_regalia import triangles, bar_points
from repair_idle_gown_hang import rig_hash
from regalia_neck_clearance import _barycentric
from simulate_portal_cloth import SCALE, SkinBinding, evaluated_points, fcurves
from repair_motion_pants_clearance import bake_isolated_cache, _animation_digest
from validate_sleeve_garment_contact import compare, segment_triangle, visible_surfaces, Surface
from export_graduate_godot import role_map


def self_constraints(points, faces, offset, margin):
    """Separate two moving non-adjacent faces; both barycentric points move."""
    surface = array_surface(points, faces)
    stats = compare(surface, surface, True, 1e-6)
    constraints, examples = [], []
    for ia, ib in stats["triangle_pairs"]:
        # The later hanging row goes outward relative to the earlier panel.
        if np.mean(np.asarray(faces[ia]) // 4) < np.mean(np.asarray(faces[ib]) // 4):
            ia, ib = ib, ia
        a, b = tuple(faces[ia]), tuple(faces[ib])
        first, second = [surface.points[i] for i in a], [surface.points[i] for i in b]
        normal = surface.normals[ib]
        hits = []
        for source, target, n in ((first, second, normal), (second, first, surface.normals[ia])):
            for edge in range(3):
                hit = segment_triangle(source[edge], source[(edge + 1) % 3], target, n, 1e-6)
                if hit is not None and all((hit - old).length > 1e-6 for old in hits):
                    hits.append(hit)
        if not hits:
            continue
        for point in hits + [sum(hits, Vector((0, 0, 0))) / len(hits)]:
            wa, wb = _barycentric(np.asarray(point), points[list(a)]), _barycentric(np.asarray(point), points[list(b)])
            if wa is None or wb is None:
                continue
            wa, wb = np.clip(wa, 0., 1.), np.clip(wb, 0., 1.)
            wa, wb = wa / wa.sum(), wb / wb.sum()
            constraints.append((tuple(offset + i for i in (*a, *b)),
                                np.concatenate((wa, -wb)), np.asarray(normal), margin))
        examples.append({"triangles": [int(ia), int(ib)], "vertices": [list(a), list(b)],
                         "intersection_points_m": [list(point) for point in hits]})
    return constraints, stats["crossings"], examples


def solve_stole_rows(posed, faces, targets, *, margin=.0025, maximum=.03, iterations=160, initial=None):
    """Pure geometry solve: returns corrected role arrays and exact evidence."""
    names, offsets, base, all_faces, groups = sewn_row_groups(posed, faces)
    base = np.asarray(base, dtype=float)
    current, shift = base.copy(), np.zeros((len(groups), 3))
    group_ids = np.full(len(base), -1, dtype=int)
    for gid, ids in enumerate(groups):
        group_ids[ids] = gid
    indices = np.asarray(all_faces, dtype=int)
    source_normals = np.cross(base[indices[:, 1]] - base[indices[:, 0]], base[indices[:, 2]] - base[indices[:, 0]])
    source_areas = np.linalg.norm(source_normals, axis=1)
    units = source_normals / np.maximum(source_areas[:, None], 1e-16)
    valid = source_areas > 1e-11
    if initial is not None:
        seed = np.concatenate([initial[role] for role in names])
        for gid, ids in enumerate(groups):
            # Every temporal seed remains one translation per complete row.
            shift[gid] = np.mean(seed[ids] - base[ids], axis=0)
        shift *= np.minimum(1., maximum / np.maximum(np.linalg.norm(shift, axis=1), 1e-16))[:, None]
        for factor in (1., .5, .25, .125, 0.):
            current = base.copy()
            for gid, ids in enumerate(groups):
                current[ids] += factor * shift[gid]
            normals = np.cross(current[indices[:, 1]] - current[indices[:, 0]], current[indices[:, 2]] - current[indices[:, 0]])
            if np.all(np.einsum("ij,ij->i", normals, units)[valid] > .04 * source_areas[valid]):
                shift *= factor
                break
    persistent, lookup, first_examples, history = [], set(), {}, []
    capped, rejected, blocked = set(), 0, 0
    best, best_score = base.copy(), None
    initial_counts = None

    def pieces(points):
        return {role: points[offsets[role]:offsets[role] + len(posed[role])] for role in names}

    if initial is not None:
        original_surface = array_surface(base, all_faces)
        initial_counts = {label: compact_crossings(original_surface, target)["crossings"]
                          for label, target in targets.items()}
        for role, points in pieces(base).items():
            original_surface = array_surface(points, faces[role])
            initial_counts["self:" + role] = compact_crossings(original_surface, original_surface, True)["crossings"]

    for iteration in range(iterations + 1):
        fresh, counts = [], {}
        for label, target in targets.items():
            found, count, examples = intersection_constraints(current, all_faces, target, margin)
            counts[label] = count
            fresh.extend((label, item) for item in found)
            if examples and label not in first_examples:
                first_examples[label] = examples
        for role, points in pieces(current).items():
            label = "self:" + role
            found, count, examples = self_constraints(points, faces[role], offsets[role], margin)
            counts[label] = count
            fresh.extend((label, item) for item in found)
            if examples and label not in first_examples:
                first_examples[label] = examples
        if initial_counts is None:
            initial_counts = counts.copy()
        # Do not keep a result that introduces a new self-crossing on a strip.
        admissible = all(counts[label] <= initial_counts[label]
                         for label in counts if label.startswith("self:"))
        score = (sum(counts.values()), max(counts.values(), default=0),
                 float(np.linalg.norm(current - base, axis=1).max(initial=0)))
        if admissible and (best_score is None or score < best_score):
            best, best_score = current.copy(), score
        history.append({"iteration": iteration, "crossings": counts, "admissible_self_counts": admissible})
        if not any(counts.values()) or iteration == iterations:
            break
        for label, (ids, weights, normal, offset) in fresh:
            key = (label, ids, tuple(np.round(weights, 5)), tuple(np.round(normal, 5)))
            if key not in lookup:
                lookup.add(key)
                persistent.append((ids, weights, normal, offset))
        sums, contributions = np.zeros_like(shift), np.zeros(len(groups))
        for ids, weights, normal, offset in persistent:
            need = offset - float(np.dot(weights @ current[list(ids)], normal))
            if need <= 1e-5:
                continue
            distribution = {}
            for vertex, weight in zip(ids, weights):
                gid = int(group_ids[vertex])
                if gid >= 0:
                    distribution[gid] = distribution.get(gid, 0.) + float(weight)
            denom = sum(weight * weight for weight in distribution.values())
            if denom < 1e-12:
                blocked += 1
                continue
            for gid, weight in distribution.items():
                sums[gid] += normal * need * weight / denom
                contributions[gid] += 1
        active = contributions > 0
        if not np.any(active):
            break
        step = np.zeros_like(shift)
        step[active] = sums[active] / contributions[active, None]
        step *= np.minimum(1., .0015 / np.maximum(np.linalg.norm(step, axis=1), 1e-16))[:, None]
        proposed = shift + step
        lengths = np.linalg.norm(proposed, axis=1)
        capped.update(int(i) for i in np.flatnonzero(lengths > maximum))
        proposed *= np.minimum(1., maximum / np.maximum(lengths, 1e-16))[:, None]
        accepted = False
        for factor in (1., .5, .25, .125, .0625):
            attempt = shift + factor * (proposed - shift)
            candidate = base.copy()
            for gid, ids in enumerate(groups):
                candidate[ids] += attempt[gid]
            normals = np.cross(candidate[indices[:, 1]] - candidate[indices[:, 0]], candidate[indices[:, 2]] - candidate[indices[:, 0]])
            if np.all(np.einsum("ij,ij->i", normals, units)[valid] > .04 * source_areas[valid]):
                accepted = True
                break
            rejected += 1
        if not accepted or np.linalg.norm(candidate - current, axis=1).max(initial=0) < 1e-8:
            break
        current, shift = candidate, attempt
    fixed = {role: points.copy() for role, points in pieces(best).items()}
    surface = array_surface(best, all_faces)
    remaining = {label: compact_crossings(surface, target) for label, target in targets.items()}
    remaining_self = {role: compact_crossings(array_surface(points, faces[role]), array_surface(points, faces[role]), True)
                      for role, points in fixed.items()}
    cross_stoles = {a + " <> " + b: compact_crossings(array_surface(fixed[a], faces[a]), array_surface(fixed[b], faces[b]))
                    for i, a in enumerate(names) for b in names[i + 1:]}
    solved = not any(value["crossings"] for value in [*remaining.values(), *remaining_self.values(), *cross_stoles.values()])
    return fixed, {"solved": solved, "before_counts": initial_counts, "remaining": remaining,
                   "remaining_self": remaining_self, "cross_stoles": cross_stoles,
                   "initial_exact_examples": first_examples, "history": history,
                   "maximum_movement_m": float(np.linalg.norm(best - base, axis=1).max(initial=0)),
                   "movement_limit_m": maximum, "capped_groups": sorted(capped),
                   "temporal_seed_used": initial is not None,
                   "blocked_constraints": blocked, "orientation_rejected_steps": rejected,
                   "sewn_endpoint_gaps_m": {"left": float(np.linalg.norm(fixed[names[0]][:4] - fixed[names[2]][:4], axis=1).max()),
                                             "right": float(np.linalg.norm(fixed[names[1]][:4] - fixed[names[2]][-4:], axis=1).max())}}


def smooth_correction_field(values, looping):
    """Five-tap binomial envelope: spreads relief over two adjacent frames."""
    values = np.asarray(values, dtype=float)
    result = np.zeros_like(values)
    frame_ids = np.arange(len(values))
    for offset, weight in zip(range(-2, 3), (1., 4., 6., 4., 1.)):
        ids = (frame_ids + offset) % len(values) if looping else np.clip(frame_ids + offset, 0, len(values) - 1)
        result += values[ids] * (weight / 16.)
    return result


def correction_metrics(baseline, expected, layers, looping):
    fields = [np.asarray([expected[frame][obj] - baseline[frame][obj]
                          for frame in sorted(expected)]) for obj in layers.values()]
    changes = []
    for field in fields:
        delta = np.diff(field, axis=0)
        if looping:
            delta = np.concatenate((delta, (field[:1] - field[-1:])), axis=0)
        changes.extend(np.linalg.norm(delta, axis=2).reshape(-1).tolist())
    return {"maximum_adjacent_correction_step_m": max(changes, default=0.),
            "p95_adjacent_correction_step_m": float(np.percentile(changes, 95)) if changes else 0.,
            "rms_adjacent_correction_step_m": float(np.sqrt(np.mean(np.square(changes)))) if changes else 0.,
            "loop_boundary_included": looping}


def correction_key(obj, delta, frame, period, looping):
    additive_key(obj, delta, frame, period)
    if looping:
        return
    key = obj.data.shape_keys.key_blocks[-1]
    for curve in fcurves(obj.data.shape_keys.animation_data.action):
        if curve.data_path != key.path_from_id("value"):
            continue
        for modifier in list(curve.modifiers):
            if modifier.type == "CYCLES":
                curve.modifiers.remove(modifier)
        curve.extrapolation = "CONSTANT"
        for point in curve.keyframe_points:
            if abs(point.co.x - (period + 1)) < 1e-6:
                point.co.y = 1. if frame == period else 0.


def actual_skin_surface(obj):
    """Finite evaluated Skin triangles only; no caps or proxy volumes."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated = obj.evaluated_get(depsgraph)
    mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
    try:
        mesh.calc_loop_triangles()
        points = np.asarray([((evaluated.matrix_world @ vertex.co) * SCALE)[:] for vertex in mesh.vertices])
        faces = []
        for triangle in mesh.loop_triangles:
            index = mesh.polygons[triangle.polygon_index].material_index
            material = mesh.materials[index] if index < len(mesh.materials) else None
            if material and "skin" in material.name.lower():
                faces.append(tuple(triangle.vertices))
        if not faces:
            raise ValueError("No actual Skin triangles on " + obj.name)
        return array_surface(points, faces)
    finally:
        evaluated.to_mesh_clear()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--probe", action="store_true")
    selection = parser.add_mutually_exclusive_group()
    selection.add_argument("--samples", nargs="+")
    selection.add_argument("--all-frames", action="store_true")
    parser.add_argument("--margin", type=float, default=.0025)
    parser.add_argument("--maximum", type=float, default=.03)
    parser.add_argument("--iterations", type=int, default=160)
    parser.add_argument("--temporal-passes", type=int, default=1,
                        help="All-frames only: five-tap smoothing plus exact reprojection rounds")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if output == Path(bpy.data.filepath).resolve():
        raise ValueError("A distinct output is required")
    if not (.0005 <= args.margin <= .005 and .001 <= args.maximum <= .06 and 1 <= args.iterations <= 400 and 1 <= args.temporal_passes <= 4):
        raise ValueError("Expected bounded whole-row correction settings")
    report_path = args.report.resolve() if args.report else output.with_suffix(".stole-contacts.json")
    report = {"source": bpy.data.filepath, "output": str(output), "probe": args.probe,
              "complete": False, "asset_saved": False, "all_frames": args.all_frames,
              "temporal_passes": args.temporal_passes if args.all_frames else 0, "clips": {}}
    started = time.perf_counter()
    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    if args.all_frames:
        specs = []
        for prefix in ("01_WALK", "02_RUN", "03_JUMP", "04_IDLE"):
            scene = next(scene for scene in bpy.data.scenes if scene.name.startswith(prefix))
            specs.append(prefix + "=" + ",".join(str(frame) for frame in range(scene.frame_start, scene.frame_end + 1)))
    else:
        specs = args.samples or ["02_RUN=7,19,20", "03_JUMP=27"]
    for spec in specs:
        prefix, values = spec.split("=", 1)
        frames = sorted(set(int(value) for value in values.split(",")))
        scene = next(scene for scene in bpy.data.scenes if scene.name.startswith(prefix))
        looping = not prefix.startswith("03_JUMP")
        rig, roles = role_map(scene)
        if scene.frame_start != 1 or not frames or min(frames) < 1 or max(frames) > scene.frame_end:
            raise ValueError("Invalid authored frame range")
        layers = {role: obj for role, obj in roles.items() if role.startswith("03 |")}
        bars = {role: obj for role, obj in roles.items() if role.startswith("04 |")}
        fixed_objects = {role: obj for role, obj in roles.items() if role.startswith(("01 |", "02 |", "05 |")) or role.startswith("Graduate |")}
        relevant = [*layers.values(), *bars.values(), *fixed_objects.values()]
        if any(mod.type == "SOLIDIFY" for obj in [*layers.values(), *fixed_objects.values()] for mod in obj.modifiers):
            raise ValueError("Use the thin-fabric candidate, retaining Triangulate but removing cloth Solidify")
        movable = [*layers.values(), *bars.values()]
        bindings = {obj: SkinBinding(obj, rig) for obj in movable}
        layer_faces = {role: triangles(obj) for role, obj in layers.items()}
        before_rig, timing = rig_hash(rig), (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
        object_actions_before = {obj.name: _animation_digest(obj) for obj in relevant}
        clip = {"frames": [], "timing": timing}
        report["clips"][scene.name] = clip
        deltas, expected = [], {}
        with visible_surfaces(scene, relevant, "rendered"):
            baseline = {}
            for frame in range(1, scene.frame_end + 1):
                scene.frame_set(frame); bpy.context.view_layer.update()
                baseline[frame] = {obj: evaluated_points(obj) for obj in relevant}
            def target_surfaces():
                targets = {role: actual_skin_surface(obj) if role.startswith("Graduate |") else Surface(obj)
                           for role, obj in fixed_objects.items()}
                # A sleeve's pinned attachment is not a sewn joint to a stole.
                # Keep those real sleeve triangles in the accessory solve too.
                for target in targets.values():
                    target.seam = [False] * len(target.triangles)
                return targets

            def include_bars(corrected_layers, original):
                corrected = {obj: corrected_layers[role] for role, obj in layers.items()}
                torso = rig.pose.bones["Torso"]
                forward = rig.matrix_world.to_3x3() @ torso.matrix.to_3x3() @ torso.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0))
                for role, obj in bars.items():
                    parent = next(layer for name, layer in layers.items() if name.endswith(" " + role.rsplit(" ", 1)[1][0]))
                    corrected[obj] = original[obj] if np.array_equal(corrected[parent][32:], original[parent][32:]) else bar_points(corrected[parent], int(role[-1]), np.asarray(forward.normalized()))
                return corrected

            for frame in frames:
                scene.frame_set(frame); bpy.context.view_layer.update()
                original = baseline[frame]
                posed = {role: original[obj] for role, obj in layers.items()}
                corrected_layers, entry = solve_stole_rows(posed, layer_faces, target_surfaces(),
                    margin=args.margin, maximum=args.maximum, iterations=args.iterations)
                entry.update({"frame": frame, "stage": "raw"})
                corrected = include_bars(corrected_layers, original)
                expected[frame] = corrected
                clip["frames"].append(entry); checkpoint()
                print("STOLE_CONTACT_PROBE", scene.name, frame, "solved", entry["solved"], "movement", entry["maximum_movement_m"], flush=True)
            if args.all_frames:
                clip["raw_frame_summaries"] = [{key: entry[key] for key in ("frame", "solved", "before_counts", "maximum_movement_m")}
                                                for entry in clip["frames"]]
                clip["temporal_metrics_raw"] = correction_metrics(baseline, expected, layers, looping)
                clip["temporal_metrics_passes"] = []
                for temporal_pass in range(1, args.temporal_passes + 1):
                    smooth = {role: smooth_correction_field(
                        [expected[frame][obj] - baseline[frame][obj] for frame in frames], looping)
                              for role, obj in layers.items()}
                    for index, frame in enumerate(frames):
                        scene.frame_set(frame); bpy.context.view_layer.update()
                        original = baseline[frame]
                        posed = {role: original[obj] for role, obj in layers.items()}
                        seed = {role: posed[role] + smooth[role][index] for role in layers}
                        fixed, entry = solve_stole_rows(posed, layer_faces, target_surfaces(),
                            margin=args.margin, maximum=args.maximum, iterations=args.iterations, initial=seed)
                        entry.update({"frame": frame, "stage": "temporal_" + str(temporal_pass)})
                        expected[frame] = include_bars(fixed, original)
                        clip["frames"][index] = entry
                        checkpoint()
                        print("STOLE_TEMPORAL_PROJECT", scene.name, temporal_pass, frame,
                              "solved", entry["solved"], "movement", entry["maximum_movement_m"], flush=True)
                    clip["temporal_metrics_passes"].append(correction_metrics(baseline, expected, layers, looping))
                clip["temporal_metrics_final"] = correction_metrics(baseline, expected, layers, looping)
            if not args.probe:
                if not all(entry["solved"] for entry in clip["frames"]):
                    raise RuntimeError("Unresolved exact contacts; refusing to save a partial candidate")
                if args.all_frames:
                    local_samples = {obj: [] for obj in movable}
                    for frame in frames:
                        scene.frame_set(frame); bpy.context.view_layer.update()
                        for obj in movable:
                            local_samples[obj].append(bindings[obj].inverse_points(expected[frame][obj]))
                    for obj in movable:
                        # Always isolate the mesh and allocate a fresh KEY
                        # action/slot; Jump may share its old Action with Object
                        # hide events, which must never acquire morph curves.
                        obj.data = obj.data.copy()
                        label = "Stole temporal clearance | " + obj["graduate_role"]
                        bake_isolated_cache(obj, local_samples[obj], label, loop=looping)
                    clip["bake_mode"] = "complete looping clip" if looping else "complete one-shot, no Cycles"
                else:
                    for frame in frames:
                        scene.frame_set(frame); bpy.context.view_layer.update()
                        for obj in movable:
                            if np.linalg.norm(expected[frame][obj] - baseline[frame][obj], axis=1).max() > 1e-10:
                                delta = np.asarray(bindings[obj].inverse_points(expected[frame][obj])) - np.asarray(bindings[obj].inverse_points(baseline[frame][obj]))
                                deltas.append((obj, frame, delta))
                    for obj, frame, delta in deltas:
                        correction_key(obj, delta, frame, scene.frame_end, looping)
                errors = {"unchanged_sleeves_gown_skin_shirts_m": 0., "untargeted_frames_m": 0., "target_reconstruction_m": 0.}
                for frame in range(1, scene.frame_end + 1):
                    scene.frame_set(frame); bpy.context.view_layer.update()
                    for obj in relevant:
                        fixed_obj = obj in fixed_objects.values()
                        key = "unchanged_sleeves_gown_skin_shirts_m" if fixed_obj else "untargeted_frames_m" if frame not in frames else "target_reconstruction_m"
                        target = baseline[frame][obj] if fixed_obj or frame not in frames else expected[frame][obj]
                        errors[key] = max(errors[key], float(np.linalg.norm(evaluated_points(obj) - target, axis=1).max()))
                clip["preservation"] = errors
                if max(errors.values()) > 1e-6:
                    raise AssertionError("Additive reconstruction/preservation failed: " + str(errors))
                if args.all_frames:
                    scene.frame_set(1); bpy.context.view_layer.update()
                    first = {obj: evaluated_points(obj) for obj in movable}
                    scene.frame_set(scene.frame_end + 1); bpy.context.view_layer.update()
                    if looping:
                        closure = max(float(np.linalg.norm(evaluated_points(obj) - first[obj], axis=1).max()) for obj in movable)
                        clip["loop_endpoint_error_m"] = closure
                        if closure > 1e-6:
                            raise AssertionError("Full clip loop closure changed: " + str(closure))
                    else:
                        cycles = [curve.data_path for obj in movable
                                  for curve in fcurves(obj.data.shape_keys.animation_data.action)
                                  if any(mod.type == "CYCLES" for mod in curve.modifiers)]
                        if cycles:
                            raise AssertionError("Jump acquired cyclic shape animation")
                        clip["jump_shape_curves_nonlooping"] = True
        if before_rig != rig_hash(rig) or timing != (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base):
            raise AssertionError("Rig or timing changed")
        object_actions_after = {obj.name: _animation_digest(obj) for obj in relevant}
        clip["object_actions_before"] = object_actions_before
        clip["object_actions_after"] = object_actions_after
        if object_actions_before != object_actions_after:
            raise AssertionError("Protected Object animation/hide events changed")
        clip["rig_timing_preserved"] = True
        clip["object_actions_and_hide_events_preserved"] = True
        checkpoint()
    if not args.probe:
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        report["asset_saved"] = True
    report["complete"] = True
    report["seconds"] = time.perf_counter() - started
    checkpoint()
    print("STOLE_CONTACT_DONE", str(output), "seconds", report["seconds"], flush=True)


if __name__ == "__main__":
    main()
