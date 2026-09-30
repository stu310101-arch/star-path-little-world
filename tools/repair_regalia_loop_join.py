"""Optional, bounded garment repair of a measured loop correction jump.

No work happens on import. The background CLI reads original and candidate
blends, edits accepted gown and attached decoration caches, and saves a distinct output.
It skips loops without a measured correction discontinuity. No engine is
launched. Stoles preserve their local surface offsets and bars follow their
stoles only on affected frames. The final full-character audit remains required.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from validate_regalia_trajectory import collect_current, compare_caches, GOWN, PREFIXES


def propose_window(original, candidate, rotations, window=6, maximum_adjustment=.025, frozen=None):
    """Split the correction jump between the head/tail in torso coordinates.

    rotations maps frame indices to 3x3 torso-local-to-world rotations. It is
    needed only in the selected window. The returned world points include the
    complete unchanged clip; this function is independent of Blender.
    """
    original, candidate = np.asarray(original), np.asarray(candidate)
    if original.shape != candidate.shape or candidate.ndim != 3 or candidate.shape[2] != 3:
        raise ValueError("Expected matching [frame, vertex, xyz] arrays")
    count = len(candidate)
    if not 2 <= window <= count // 2 or maximum_adjustment <= 0:
        raise ValueError("Window must be 2..half the period and adjustment positive")
    if frozen is None:
        frozen = np.zeros(candidate.shape[1], dtype=bool)
    correction = candidate - original
    jump = correction[0] @ rotations[0] - correction[-1] @ rotations[count - 1]
    proposed = candidate.copy()
    selected = list(range(window)) + list(range(count - window, count))
    for index in selected:
        distance = index if index < window else count - 1 - index
        weight = .5 * (1.0 + np.cos(np.pi * distance / (window - 1)))
        sign = -1.0 if index < window else 1.0
        shift = (sign * .5 * weight * jump) @ rotations[index].T
        lengths = np.linalg.norm(shift, axis=1)
        shift *= np.minimum(1.0, maximum_adjustment / np.maximum(lengths, 1e-12))[:, None]
        shift[frozen] = 0
        proposed[index] += shift
    changed = [i for i in selected if np.linalg.norm(proposed[i] - candidate[i], axis=1).max(initial=0) > 1e-8]
    return proposed, changed


def _one_clip_report(clip, original, candidate):
    def wrap(entry):
        return {"blend": entry.get("blend", "in-memory"), "world_scale_to_m": 1.0,
                "clips": {clip: entry}}
    return compare_caches(wrap(original), wrap(candidate), top=8)["clips"][clip]


def _trigger(entry, ratio, minimum):
    data = entry["wrap_vs_other_transitions_p95"]["max_m"]
    threshold = max(minimum, ratio * data["other_transitions_p95"])
    return data["wrap"] > threshold, threshold


def _improved(before, after, changed, ratio, minimum):
    """Do not merely move a wrap spike into an adjacent interior transition."""
    old = before["wrap_vs_other_transitions_p95"]["max_m"]
    new = after["wrap_vs_other_transitions_p95"]["max_m"]
    limit = max(minimum, ratio * old["other_transitions_p95"])
    count = before["frame_count"]
    pairs = {index for frame in changed for index in (frame, (frame - 1) % count)}
    violations = []
    for index in sorted(pairs):
        previous = before["frame_pairs"][index]["correction_delta"]["max_m"]
        value = after["frame_pairs"][index]["correction_delta"]["max_m"]
        allowed = limit if index == count - 1 else max(limit, previous * 1.05)
        if value > allowed + 1e-6:
            violations.append({"frame_from": before["frame_pairs"][index]["frame_from"],
                               "frame_to": before["frame_pairs"][index]["frame_to"],
                               "before_m": previous, "after_m": value, "allowed_m": allowed})
    improved = new["wrap"] <= old["wrap"] * .75 and not violations
    return improved, {"wrap_before_m": old["wrap"], "wrap_after_m": new["wrap"],
                      "allowed_wrap_m": limit, "adjacent_regressions": violations,
                      "required_wrap_reduction_fraction": .25}


def _reattach_layers(scene, rig, gown, old_gown, new_gown, frames, changed, maximum_adjustment):
    """Preserve candidate-frame tangent/normal offsets while following the gown."""
    import bpy
    from mathutils import Vector
    from simulate_portal_cloth import SkinBinding, evaluated_points
    from simulate_sleeve_cloth import bake_loop
    from validate_sleeve_garment_contact import visible_surfaces
    from repair_graduate_regalia import (anchors, deform, triangles, stable_ribbon,
        clear_ribbon_rows, project_clearance, continuous_back_collar, bar_points)

    stoles = [o for o in scene.objects if str(o.get("graduate_role", "")).startswith("03 |")]
    bars = [o for o in scene.objects if str(o.get("graduate_role", "")).startswith("04 |")]
    objects = stoles + bars
    result = {"accepted": True, "frames": [], "modified_objects": [],
              "maximum_anchor_target_movement_m": 0.0, "maximum_decoration_movement_m": 0.0,
              "tiny_movement_threshold_m": 1e-6, "normal_gap_clamping": False}
    if not objects:
        return result
    faces = {o: triangles(o) for o in [gown, *objects]}
    parents = {}
    for bar in bars:
        side = bar.get("graduate_role").rsplit(" ", 1)[1][0]
        parents[bar] = next(o for o in stoles if o.get("graduate_role").endswith(" " + side))
    bindings = {o: SkinBinding(o, rig) for o in objects}
    baseline = {o: [] for o in objects}
    targets = {o: [] for o in objects}
    moved_frames = {o: [] for o in objects}
    previous_meshes = {}
    changed_set = set(changed)
    with visible_surfaces(scene, [gown, *objects], "simulation"):
        for index, frame in enumerate(frames):
            scene.frame_set(frame); bpy.context.view_layer.update()
            original = {o: evaluated_points(o) for o in objects}
            posed = {o: points.copy() for o, points in original.items()}
            if index in changed_set:
                entry = {"frame": frame, "anchor_target_movements_m": {}, "final_movements_m": {}}
                any_attached_motion = False
                for obj in stoles:
                    links = anchors(original[obj], old_gown[index], faces[gown], 0.0, True)
                    exact_links = []
                    for point, (ids, bary, x, y, _) in zip(original[obj], links):
                        a, b, c = old_gown[index][list(ids)]
                        normal = np.cross(b - a, c - a)
                        normal /= max(np.linalg.norm(normal), 1e-12)
                        # The main anchors helper intentionally clamps normal
                        # gaps. Here restore the exact pre-existing offset.
                        z = float(np.dot(point - old_gown[index][list(ids)].T @ bary, normal))
                        exact_links.append((ids, bary, x, y, z))
                    anchored = deform(exact_links, new_gown[index])
                    movement = float(np.linalg.norm(anchored - original[obj], axis=1).max(initial=0))
                    entry["anchor_target_movements_m"][obj.name] = movement
                    result["maximum_anchor_target_movement_m"] = max(result["maximum_anchor_target_movement_m"], movement)
                    if movement > 1e-6:
                        posed[obj] = anchored
                        any_attached_motion = True
                if any_attached_motion:
                    torso = rig.pose.bones["Torso"]
                    basis = rig.matrix_world.to_3x3() @ torso.matrix.to_3x3() @ torso.bone.matrix_local.to_3x3().inverted()
                    across = np.asarray((basis @ Vector((1, 0, 0))).normalized())
                    for obj in stoles:
                        if np.linalg.norm(posed[obj] - original[obj], axis=1).max(initial=0) <= 1e-6:
                            continue
                        if obj.get("graduate_role").endswith((" L", " R")):
                            posed[obj] = stable_ribbon(posed[obj], obj.get("graduate_role")[-1], across)
                            posed[obj] = clear_ribbon_rows(posed[obj], faces[obj], new_gown[index], faces[gown])
                        else:
                            posed[obj] = project_clearance(posed[obj], faces[obj], new_gown[index], faces[gown], .0045)
                    back = next((o for o in stoles if "back collar" in o.get("graduate_role")), None)
                    left = next((o for o in stoles if o.get("graduate_role").endswith(" L")), None)
                    right = next((o for o in stoles if o.get("graduate_role").endswith(" R")), None)
                    if all(o is not None for o in (back, left, right)):
                        posed[back] = continuous_back_collar(posed[left], posed[right], posed[back])
                    forward = np.asarray((basis @ Vector((0, -1, 0))).normalized())
                    for bar in bars:
                        parent = parents[bar]
                        if np.linalg.norm(posed[parent] - original[parent], axis=1).max(initial=0) > 1e-6:
                            posed[bar] = bar_points(posed[parent], int(bar.get("graduate_role")[-1]), forward)
                for obj in objects:
                    movement = float(np.linalg.norm(posed[obj] - original[obj], axis=1).max(initial=0))
                    entry["final_movements_m"][obj.name] = movement
                    result["maximum_decoration_movement_m"] = max(result["maximum_decoration_movement_m"], movement)
                    if movement > maximum_adjustment + .015:
                        result["accepted"] = False
                        result["reason"] = "Decoration reattachment exceeded bounded gown adjustment plus15mm"
                        result["frames"].append(entry)
                        return result
                    if movement > 1e-6:
                        moved_frames[obj].append(frame)
                    else:
                        posed[obj] = original[obj]
                result["frames"].append(entry)
            for obj in objects:
                baseline[obj].append(original[obj])
                targets[obj].append(posed[obj])
        try:
            for obj in objects:
                if not moved_frames[obj]:
                    continue
                local = []
                for frame, points in zip(frames, targets[obj]):
                    scene.frame_set(frame); bpy.context.view_layer.update()
                    local.append(bindings[obj].inverse_points(points))
                previous_meshes[obj] = obj.data
                obj.data = obj.data.copy()
                bake_loop(obj, local, "Regalia_LocalLoopAttachment_" + str(obj.get("graduate_role")))
                max_error, preserved_error = 0.0, 0.0
                for index, frame in enumerate(frames):
                    scene.frame_set(frame); bpy.context.view_layer.update()
                    points = evaluated_points(obj)
                    max_error = max(max_error, float(np.linalg.norm(points - targets[obj][index], axis=1).max(initial=0)))
                    if frame not in moved_frames[obj]:
                        preserved_error = max(preserved_error, float(np.linalg.norm(points - baseline[obj][index], axis=1).max(initial=0)))
                scene.frame_set(frames[-1] + 1); bpy.context.view_layer.update()
                endpoint_error = float(np.linalg.norm(evaluated_points(obj) - targets[obj][0], axis=1).max(initial=0))
                result["modified_objects"].append({"name": obj.name, "frames": moved_frames[obj],
                    "bake_target_error_m": max_error, "unchanged_frames_error_m": preserved_error,
                    "endpoint_error_m": endpoint_error})
                if max_error > 2e-6 or preserved_error > 2e-6 or endpoint_error > 1e-5:
                    raise RuntimeError("Decoration bake verification failed")
        except Exception as exc:
            for obj, mesh in previous_meshes.items():
                obj.data = mesh
            result["accepted"] = False
            result["reason"] = str(exc)
    return result


def repair_open_clip(clip, original, candidate, *, window=6, trigger_ratio=1.5,
                     minimum_wrap=.005, maximum_adjustment=.025,
                     clearance=.0025, tolerance=.00005, projection_iterations=12,
                     projection_maximum=.008):
    """Operate only on this clip's gown in the currently loaded candidate.

    On rejection original mesh datablocks are restored. Accepted gown changes
    reattach stoles/bars at affected frames; the skeleton and other objects are
    untouched. This function does not save.
    """
    import bpy
    from simulate_portal_cloth import SkinBinding, evaluated_points
    from simulate_sleeve_cloth import bake_loop
    from validate_sleeve_garment_contact import visible_surfaces
    from repair_gown_sleeve_clearance import (SLEEVES, SleeveProxy, Tessellation,
        _crossings, _requests, _samples_clear, _shell_radius, _project)

    if not .002 <= projection_maximum <= .02 or not 0 <= projection_iterations <= 24:
        raise ValueError("Projection limit must be2..20mm with at most24 iterations")
    before = _one_clip_report(clip, original, candidate)
    triggered, threshold = _trigger(before, trigger_ratio, minimum_wrap)
    report = {"clip": clip, "triggered": triggered, "accepted": False,
              "trigger_threshold_m": threshold, "before_trajectory": before,
              "frames": [], "changed_frames": [], "skeleton_and_unrelated_objects_preserved": True,
              "projection_maximum_m": projection_maximum, "total_adjustment_limit_m": maximum_adjustment}
    if not triggered:
        report["reason"] = "Wrap correction is within the configured temporal threshold"
        return report
    scene = next(s for s in bpy.data.scenes if s.name.startswith(PREFIXES[clip]))
    if scene.frame_start != 1 or candidate["frames"][0] != 1:
        raise ValueError("The existing loop baker requires authored frames to start at1")
    gown = next(o for o in scene.objects if o.get("graduate_role") == GOWN)
    rig = next(o for o in scene.objects if o.type == "ARMATURE" and not o.get("preview_fx"))
    sleeves = [next(o for o in scene.objects if o.get("graduate_role") == role) for role in SLEEVES]
    polygons = [tuple(p.vertices) for p in gown.data.polygons]
    frozen_faces = {p.index for p in gown.data.polygons if p.center.z > 3.8 and abs(p.center.x) > .34}
    seam_faces = {p.index for p in gown.data.polygons if p.center.z > 3.05 and abs(p.center.x) > .34}
    frozen = np.zeros(len(gown.data.vertices), dtype=bool)
    for face in frozen_faces:
        frozen[list(polygons[face])] = True
    neighbors = [set() for _ in frozen]
    for polygon in polygons:
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            neighbors[a].add(b)
            neighbors[b].add(a)
    sleeve_faces = [[tuple(p.vertices) for p in o.data.polygons] for o in sleeves]
    pinned_faces = []
    for obj in sleeves:
        group = obj.vertex_groups.get("Sleeve shoulder seam only")
        if group is None:
            raise ValueError("Missing explicit sleeve attachment group")
        pins = {v.index for v in obj.data.vertices if any(g.group == group.index and g.weight > 0 for g in v.groups)}
        pinned_faces.append({p.index for p in obj.data.polygons if any(i in pins for i in p.vertices)})
    gaps = [clearance + _shell_radius(gown) + _shell_radius(obj) for obj in sleeves]
    report["effective_midsurface_gap_m"] = gaps
    frames = candidate["frames"]
    window = min(window, len(frames) // 2)
    selected = list(range(window)) + list(range(len(frames) - window, len(frames)))
    rotations, proxies_by_frame = {}, {}

    with visible_surfaces(scene, [gown, *sleeves], "simulation"):
        binding = SkinBinding(gown, rig)
        for index in selected:
            scene.frame_set(frames[index]); bpy.context.view_layer.update()
            torso = rig.pose.bones["Torso"]
            rotation = (rig.matrix_world.to_3x3() @ torso.matrix.to_3x3()
                        @ torso.bone.matrix_local.to_3x3().inverted()).to_quaternion().to_matrix()
            rotations[index] = np.asarray(rotation, dtype=np.float64)
            right = rotations[index][:, 0]
            proxies_by_frame[index] = [SleeveProxy(evaluated_points(obj), faces, direction, gap, pins)
                for obj, faces, direction, gap, pins in zip(sleeves, sleeve_faces, (-right, right), gaps, pinned_faces)]
        proposed, changed = propose_window(original["points"], candidate["points"], rotations,
                                           window, maximum_adjustment, frozen)
        report["changed_frames"] = [frames[i] for i in changed]
        if not changed:
            report["reason"] = "No editable correction remained after frozen-attachment constraints"
            return report

        def audit(index, points):
            tess = Tessellation(candidate["points"][index], polygons)
            try:
                triangles, parents = tess.evaluate(points)
                cross = _crossings(points, triangles, parents, seam_faces, proxies_by_frame[index], frozen=frozen)
                _, samples = _requests(points, triangles, parents, seam_faces, frozen, proxies_by_frame[index])
            finally:
                tess.close()
            return {"crossings": cross, "samples": samples,
                    "clear": cross["free_region"] == 0 and cross["gown_self"] == 0 and _samples_clear(samples, tolerance)}

        for index in changed:
            current = candidate["points"][index]
            baseline = audit(index, current)
            state = audit(index, proposed[index])
            entry = {"frame": frames[index], "before": baseline, "target": state, "projected": False}
            report["frames"].append(entry)
            if not baseline["clear"]:
                report["reason"] = "An affected baseline frame is not already clear; resolve its contacts before temporal repair"
                return report
            if not state["clear"] and state["crossings"]["gown_self"] == 0 and projection_iterations:
                # Use the target as the solve baseline, then independently
                # enforce zero contacts/self against the original safe frame.
                # Calling _project(current, target) would discard a valid
                # temporal target whenever current already has score (0,0,0).
                proposed[index], solve = _project(proposed[index], proposed[index], proxies_by_frame[index],
                    polygons, seam_faces, frozen, neighbors, projection_iterations, .002, projection_maximum, 0,
                    check_every=4, clearance_tolerance=tolerance)
                state = audit(index, proposed[index])
                entry["projected"], entry["projection"] = True, solve
            movement = np.linalg.norm(proposed[index] - current, axis=1)
            entry["after"] = state
            entry["maximum_adjustment_m"] = float(movement.max(initial=0))
            entry["frozen_vertex_error_m"] = float(movement[frozen].max(initial=0))
            if not state["clear"] or movement.max(initial=0) > maximum_adjustment + 1e-7 or movement[frozen].max(initial=0) > 1e-7:
                report["reason"] = "A proposed frame failed contact, self, displacement, or attachment limits; entire clip unchanged"
                return report
        target_cache = dict(candidate)
        target_cache["points"] = proposed
        target_cache["endpoint"] = candidate["endpoint"] + proposed[0] - candidate["points"][0]
        after = _one_clip_report(clip, original, target_cache)
        accepted, continuity = _improved(before, after, changed, trigger_ratio, minimum_wrap)
        report["proposed_trajectory"], report["continuity_test"] = after, continuity
        if not accepted:
            report["reason"] = "Proposed correction did not sufficiently improve wrap and adjacent transitions; entire clip unchanged"
            return report
        local = []
        for frame, points in zip(frames, proposed):
            scene.frame_set(frame); bpy.context.view_layer.update()
            local.append(binding.inverse_points(points))
        previous_mesh = gown.data
        gown.data = previous_mesh.copy()
        try:
            bake_loop(gown, local, "Regalia_LocalLoopJoin_" + clip)
            actual = []
            for frame in frames + [frames[-1] + 1]:
                scene.frame_set(frame); bpy.context.view_layer.update()
                actual.append(evaluated_points(gown))
            target_cache["points"], target_cache["endpoint"] = np.asarray(actual[:-1]), actual[-1]
            error = float(np.linalg.norm(target_cache["points"] - proposed, axis=2).max(initial=0))
            untouched = sorted(set(range(len(frames))) - set(changed))
            preserved = float(np.linalg.norm(target_cache["points"][untouched] - candidate["points"][untouched], axis=2).max(initial=0)) if untouched else 0.0
            report["bake_target_error_m"], report["unchanged_frames_error_m"] = error, preserved
            bake_safe = error <= 2e-6 and preserved <= 2e-6
            for entry, index in zip(report["frames"], changed):
                entry["baked"] = audit(index, target_cache["points"][index])
                bake_safe = bake_safe and entry["baked"]["clear"]
            report["after_trajectory"] = _one_clip_report(clip, original, target_cache)
            continuity_ok, final_test = _improved(before, report["after_trajectory"], changed, trigger_ratio, minimum_wrap)
            report["continuity_test"] = final_test
            endpoint = report["after_trajectory"]["loop_endpoint"]["candidate_endpoint_minus_first"]["max_m"]
            bake_safe = bake_safe and continuity_ok and endpoint <= 1e-5
            if not bake_safe:
                gown.data = previous_mesh
                report["reason"] = "Baked verification failed; original mesh restored"
                return report
            report["decoration_reattachment"] = _reattach_layers(scene, rig, gown,
                candidate["points"], target_cache["points"], frames, changed, maximum_adjustment)
            if not report["decoration_reattachment"]["accepted"]:
                gown.data = previous_mesh
                report["reason"] = "Decoration reattachment failed; entire clip restored"
                return report
        except Exception:
            gown.data = previous_mesh
            raise
        candidate.update(target_cache)
        report["accepted"] = True
        report["reason"] = "Local wrap correction passed contact, self, gap, attachment, bake, and adjacent-motion checks"
        report["requires_final_layer_neck_render_audit"] = True
        return report


def main(argv=None):
    import bpy
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--original", type=Path, default=ROOT / "art/Graduate/Male_Graduate_GameReady.blend")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, default=ROOT / "art/Graduate/animation/regalia-local-loop-join.json")
    parser.add_argument("--clips", choices=tuple(PREFIXES), nargs="+", default=list(PREFIXES))
    parser.add_argument("--window", type=int, default=6)
    parser.add_argument("--trigger-ratio", type=float, default=1.5)
    parser.add_argument("--minimum-wrap", type=float, default=.005)
    parser.add_argument("--maximum-adjustment", type=float, default=.025)
    parser.add_argument("--projection-iterations", type=int, default=12)
    parser.add_argument("--projection-maximum", type=float, default=.008)
    args = parser.parse_args(argv)
    if not bpy.app.background:
        raise RuntimeError("This CLI loads files; use a coordinated background Blender process")
    source, original, output, report_path = [p.resolve() for p in (args.candidate, args.original, args.output, args.report)]
    if not source.is_file() or not original.is_file():
        raise FileNotFoundError("Both candidate and original must exist")
    if output in (source, original) or output.suffix.lower() != ".blend" or output.exists():
        raise ValueError("Output must be a new, distinct .blend path")
    if report_path in (source, original, output) or report_path.suffix.lower() != ".json":
        raise ValueError("Report must be a separate JSON path")
    if not 2 <= args.window <= 12 or not 1.0 < args.trigger_ratio <= 4:
        raise ValueError("Use a 2..12 frame window and trigger ratio >1..4")
    if not 0 < args.minimum_wrap <= .05 or not 0 < args.maximum_adjustment <= .04 or not 0 <= args.projection_iterations <= 24:
        raise ValueError("Bound wrap threshold to50mm, adjustment to40mm, and projection to24 iterations")
    if not .002 <= args.projection_maximum <= .02:
        raise ValueError("Projection maximum must be2..20mm; total adjustment limit remains separate")
    started = time.perf_counter()
    bpy.ops.wm.open_mainfile(filepath=str(original), load_ui=False)
    reference = collect_current(args.clips)
    bpy.ops.wm.open_mainfile(filepath=str(source), load_ui=False)
    candidate = collect_current(args.clips)
    report = {"source": str(source), "original": str(original), "output": str(output),
              "saved": False, "complete": False, "clips": {},
              "scope": "Accepted gown caches and attached stoles/bars change only at affected frames; original bone poses, timing, sleeves, shirts and unrelated objects are preserved",
              "limitations": "Gown midsurface versus sleeves and gown self audited at authored frames. Decoration placement follows the changed gown. Render shells, body/neck, subframes, and final layer contacts require caller audit."}
    for clip in args.clips:
        report["clips"][clip] = repair_open_clip(clip, reference["clips"][clip], candidate["clips"][clip],
            window=args.window, trigger_ratio=args.trigger_ratio, minimum_wrap=args.minimum_wrap,
            maximum_adjustment=args.maximum_adjustment, projection_iterations=args.projection_iterations,
            projection_maximum=args.projection_maximum)
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print("REGALIA_LOOP_JOIN", clip, report["clips"][clip]["accepted"], report["clips"][clip]["reason"], flush=True)
    if any(item["accepted"] for item in report["clips"].values()):
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        report["saved"] = True
    report["complete"], report["elapsed_seconds"] = True, time.perf_counter() - started
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
