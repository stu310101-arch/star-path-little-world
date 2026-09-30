"""Idle-only gravity-aligned lower gown, retaining the verified neutral outline.

Run by the parent task's sole Blender process:
 blender -b <finished-candidate.blend> --python-exit-code 1 --python tools/repair_idle_gown_hang.py -- \
   --output <idle-hang-candidate.blend>

No new rig animation, thigh weighting, waist scale, or other clip is authored.
Above rest z=3.0 the gown is unchanged; a smooth transition to z=2.3 replaces
lower deformation by the existing frame-1 silhouette, waist translation and
Body horizontal yaw. Pitch/roll/scale/leg deformation cannot balloon the free
skirt. Its additional delayed lateral sway is only 1--1.5 mm amplitude.
The original neutral opening, length, folds and hem are not redesigned.

Lower front-stole rows follow the corrected gown with fixed neutral surface
anchors and intact cross-strip ordering. Their bars follow their actual parent
stole. Upper stoles, rear collar, sleeves, body and other clips stay unchanged.
Exact midpoint self/actual lower Skin/Pants contacts are reported before/after;
legacy neck seams are not projected or hidden. Final rendered QA is required.

--probe-frames 1,31,51,77,91 writes only a report, no morphs/blend. The full
cycle is read to determine the actual waist motion and a cyclic lag.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from simulate_portal_cloth import SCALE, SkinBinding, evaluated_points, fcurves
from simulate_sleeve_cloth import bake_loop
from repair_graduate_regalia import anchors, bar_points, clear_ribbon_rows, deform, triangles
from postprocess_regalia_layers import array_surface, compact_crossings
from validate_sleeve_garment_contact import visible_surfaces

GOWN = "01 | Pleated bachelor gown"
BODY = "Graduate | original face, hands and trousers"


def smooth_hang_weight(rest_z, waist_z=3.0, full_hang_z=2.3):
    t = np.clip((waist_z - np.asarray(rest_z)) / (waist_z - full_hang_z), 0., 1.)
    return t * t * (3. - 2. * t)


def rotation_2d(angle):
    c, s = math.cos(angle), math.sin(angle)
    return np.array(((c, -s), (s, c)))


def hanging_points(neutral, current, weight, waist_neutral, waist_delta, yaw_delta, sway):
    """Pure arrays; world Z remains gravity, no leg/pitch/scale matrix applied."""
    desired = np.asarray(neutral, dtype=float).copy()
    desired[:, :2] = ((desired[:, :2] - waist_neutral[:2]) @ rotation_2d(yaw_delta).T
                      + waist_neutral[:2] + waist_delta[:2] + sway[:2])
    desired[:, 2] += waist_delta[2]
    result = np.asarray(current, dtype=float).copy()
    mask = weight > 0
    result[mask] += weight[mask, None] * (desired[mask] - result[mask])
    return result


def clear_hanging_stole(points, faces, gown_points, gown_faces, row_weights):
    """Reuse the proven whole-row clearance, applying it only to hanging rows.

    The original upper rows never move. A second pass starts from the restored
    fixed/cleared join, so the boundary is queried in its actual configuration.
    Final exact contacts remain in the report rather than assuming this pass
    makes every finite triangle clear.
    """
    original = np.asarray(points, dtype=float).copy()
    result = original.copy()
    movable = np.zeros(len(result), dtype=bool)
    for row, weight in enumerate(row_weights):
        if row >= 3 and weight > 0:
            movable[4 * row:min(4 * row + 4, len(result))] = True
    if np.any(movable):
        for _ in range(2):
            cleared = clear_ribbon_rows(result, faces, gown_points, gown_faces, gap=.007)
            result[movable] = cleared[movable]
            result[~movable] = original[~movable]
    if not np.array_equal(result[:12], original[:12]):
        raise AssertionError("Lower stole clearance changed the upper sewn rows")
    return result, {"maximum_shift_m": float(np.max(np.linalg.norm(result - original, axis=1))),
                    "movable_rows": [int(i) for i, w in enumerate(row_weights) if i >= 3 and w > 0],
                    "all_fixed_rows_exactly_preserved": bool(np.array_equal(result[~movable], original[~movable])),
                    "upper_vertices_0_11_exactly_preserved": True, "midpoint_gown_gap_m": .007}


def rig_hash(rig):
    action = rig.animation_data.action if rig.animation_data else None
    payload = [[fc.data_path, fc.array_index,
                [[*k.co, *k.handle_left, *k.handle_right, k.interpolation] for k in fc.keyframe_points]]
               for fc in fcurves(action)]
    return hashlib.sha256(json.dumps(payload).encode()).hexdigest()


def other_clip_hashes():
    result = {}
    for scene in bpy.data.scenes:
        if not scene.name.startswith(("01_WALK", "02_RUN", "03_JUMP")):
            continue
        meshes = [o for o in scene.objects if o.type == "MESH" and o.get("graduate_role")
                  and not o.get("preview_fx") and o.get("graduate_role") != "Studio floor"]
        digest = hashlib.sha256()
        with visible_surfaces(scene, meshes, "rendered"):
            for frame in sorted({scene.frame_start, (scene.frame_start + scene.frame_end) // 2, scene.frame_end}):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                for obj in sorted(meshes, key=lambda o: o.get("graduate_role")):
                    digest.update(evaluated_points(obj).astype("<f4").tobytes())
        result[scene.name] = digest.hexdigest()
    return result


def body_yaw(rig):
    bone = rig.pose.bones["Body"]
    matrix = rig.matrix_world.to_3x3() @ bone.matrix.to_3x3() @ bone.bone.matrix_local.to_3x3().inverted()
    across = matrix @ Vector((1, 0, 0))
    return math.atan2(across.y, across.x)


def lower_body_faces(body, maximum_rest_z):
    """Actual finite Skin and Pants triangles only, no synthetic leg envelopes."""
    mesh = body.data
    mesh.calc_loop_triangles()
    selected = {"skin": [], "pants_legs": []}
    for triangle in mesh.loop_triangles:
        ids = tuple(triangle.vertices)
        if max(mesh.vertices[i].co.z for i in ids) > maximum_rest_z:
            continue
        material = body.material_slots[mesh.polygons[triangle.polygon_index].material_index].material
        name = material.name if material else ""
        group = "skin" if name == "Skin" or name.startswith("Skin.") else "pants_legs" if name.startswith(("Pants", "Trousers")) else None
        if group:
            selected[group].append(ids)
    return selected


def exact_contacts(points, faces, skin_surfaces):
    surface = array_surface(points, faces)
    result = {"gown_self": compact_crossings(surface, surface, True)}
    for name, other in skin_surfaces.items():
        result[name] = compact_crossings(surface, other)
    return result


def width_profile(points, waist, yaw, bands, placket_pairs):
    horizontal = (points[:, :2] - waist[:2]) @ rotation_2d(yaw)
    result = {name: {"width_m": float(np.ptp(horizontal[mask, 0])),
                     "depth_m": float(np.ptp(horizontal[mask, 1]))}
              for name, mask in bands.items() if np.count_nonzero(mask) > 1}
    result["front_opening_m"] = {str(a): float(np.linalg.norm(horizontal[a] - horizontal[b]))
                                  for a, b in placket_pairs}
    return result


def placket_pairs(rest):
    """Recognize existing duplicate front-edge vertices by unchanged rest y/z."""
    grid_end = (len(rest) // 48) * 48
    center = [i for i in range(grid_end) if i % 48 == 36]
    pairs = []
    for duplicate in range(grid_end, len(rest)):
        matches = [i for i in center if np.linalg.norm(rest[i, 1:] - rest[duplicate, 1:]) < 1e-5]
        if len(matches) == 1:
            pairs.append((matches[0], duplicate))
    return pairs


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--probe-frames")
    parser.add_argument("--waist-z", type=float, default=3.0)
    parser.add_argument("--full-hang-z", type=float, default=2.3)
    parser.add_argument("--sway-x", type=float, default=.0015)
    parser.add_argument("--sway-y", type=float, default=.0010)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    output = args.output.resolve()
    if output == Path(bpy.data.filepath).resolve():
        raise ValueError("Use a separate output; the source candidate must be preserved")
    if not (2.8 <= args.waist_z <= 3.1 and 2.1 <= args.full_hang_z < args.waist_z
            and 0 <= args.sway_x <= .003 and 0 <= args.sway_y <= .003):
        raise ValueError("Expected a bounded lower-gown transition and <=3 mm extra sway")
    scene = next(s for s in bpy.data.scenes if s.name.startswith("04_IDLE"))
    if scene.frame_start != 1:
        raise ValueError("Existing loop baker requires frame_start=1; refusing to retime")
    timing = (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
    period = scene.frame_end
    selected_frames = [int(x) for x in args.probe_frames.split(",")] if args.probe_frames else list(range(1, period + 1))
    if any(frame < 1 or frame > period for frame in selected_frames):
        raise ValueError("Probe frame outside Idle's authored range")
    roles = {o.get("graduate_role"): o for o in scene.objects
             if o.type == "MESH" and o.get("graduate_role") and not o.get("preview_fx")}
    gown, body = roles[GOWN], roles[BODY]
    rig = next(o for o in scene.objects if o.type == "ARMATURE")
    front = {r: o for r, o in roles.items() if r.startswith("03 |") and r.endswith((" L", " R"))}
    bars = {r: o for r, o in roles.items() if r.startswith("04 |")}
    objects = [gown, *front.values(), *bars.values()]
    topology = {o: triangles(o) for o in [gown, *front.values()]}
    rest = np.asarray([v.co[:] for v in gown.data.vertices])
    weight = smooth_hang_weight(rest[:, 2], args.waist_z, args.full_hang_z)
    upper = weight == 0
    waist_mask = np.abs(rest[:, 2] - args.waist_z) <= .15
    if np.count_nonzero(waist_mask) < 12:
        raise ValueError("Insufficient authored waist vertices; refusing an arbitrary pivot")
    leg_weight_vertices = []
    for vertex in gown.data.vertices:
        if weight[vertex.index] <= 0:
            continue
        names = [gown.vertex_groups[g.group].name for g in vertex.groups if g.weight > 1e-5]
        if any("Leg" in name or "Thigh" in name or "Foot" in name for name in names):
            leg_weight_vertices.append(vertex.index)
    skin_faces = lower_body_faces(body, args.waist_z + .15)
    if not skin_faces["pants_legs"]:
        raise ValueError("Actual Pants leg faces not found; refusing an unverified body proxy")
    bands = {"hem": rest[:, 2] < np.min(rest[:, 2]) + .12,
             "knee": (rest[:, 2] >= 1.65) & (rest[:, 2] < 2.0),
             "hip_lower": (rest[:, 2] >= 2.15) & (rest[:, 2] < 2.4),
             "waist_blend": (rest[:, 2] >= 2.65) & (rest[:, 2] < 2.95)}
    pairs = placket_pairs(rest)
    before_other = other_clip_hashes()
    before_rig = rig_hash(rig)
    report = {"source_blend": bpy.data.filepath, "output": str(output), "complete": False,
              "probe_only": bool(args.probe_frames), "scene": scene.name, "timing_before": timing,
              "method": "Neutral world silhouette + measured waist translation + Body yaw, smooth waist transition, millimetre delayed sway",
              "waist_rest_z": args.waist_z, "full_hang_rest_z": args.full_hang_z,
              "sway_amplitude_m": [args.sway_x, args.sway_y],
              "lower_direct_leg_weight_vertices": leg_weight_vertices,
              "direct_leg_weights_are_diagnostic_not_assumed_cause": True,
              "actual_body_collider_faces": {name: len(fs) for name, fs in skin_faces.items()},
              "placket_vertex_pairs": pairs, "frames": [], "final_rendered_audit_required": True}
    report_path = args.report or output.with_suffix(".idle-hang.json")

    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")

    started = time.perf_counter()
    bindings = {obj: SkinBinding(obj, rig) for obj in objects}
    frames, waist, yaws = [], [], []
    with visible_surfaces(scene, [body, *objects], "simulation"):
        for frame in range(1, period + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            row = {obj: evaluated_points(obj) for obj in objects}
            frames.append(row)
            waist.append(np.mean(row[gown][waist_mask], axis=0))
            yaws.append(body_yaw(rig))
        waist = np.asarray(waist)
        yaws = np.unwrap(np.asarray(yaws))
        if np.max(np.ptp(waist, axis=0)) > .08 or np.ptp(yaws) > math.radians(15):
            raise ValueError("Measured motion exceeds a stationary Idle; refusing to suppress locomotion")
        # The attached hem follows vertical waist travel; lag changes timing,
        # not the skeleton's amplitude. Cyclic three-frame blend has no seam.
        lagged_waist = .85 * waist + .15 * np.roll(waist, 3, axis=0)
        waist_delta = lagged_waist - lagged_waist[0]
        neutral = frames[0][gown]
        neutral_stole = {r: frames[0][o] for r, o in front.items()}
        row_links, row_weights, neutral_offsets = {}, {}, {}
        for role, obj in front.items():
            if len(neutral_stole[role]) != 41:
                raise ValueError("Expected the original 41-vertex front stole")
            centers, offsets, z = [], [], []
            source_rest = np.asarray([v.co[:] for v in obj.data.vertices])
            for row in range(11):
                ids = slice(4 * row, min(4 * row + 4, 41))
                center = np.mean(neutral_stole[role][ids], axis=0)
                centers.append(center)
                offsets.append(neutral_stole[role][ids] - center)
                z.append(float(np.mean(source_rest[ids, 2])))
            row_links[role] = anchors(np.asarray(centers), neutral, topology[gown], .0045, True)
            row_weights[role] = smooth_hang_weight(np.asarray(z), args.waist_z, args.full_hang_z)
            neutral_offsets[role] = offsets
        report["measured_waist_span_m"] = np.ptp(waist, axis=0).tolist()
        report["measured_body_yaw_span_degrees"] = math.degrees(float(np.ptp(yaws)))
        report["neutral_width_profile"] = width_profile(neutral, waist[0], yaws[0], bands, pairs)
        result_samples = {obj: [] for obj in objects}
        for frame in selected_frames:
            i = frame - 1
            began = time.perf_counter()
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            phase = math.tau * i / period
            sway = np.array((args.sway_x * (math.sin(phase - .30) - math.sin(-.30)),
                             args.sway_y * (math.sin(phase - .65) - math.sin(-.65)), 0.))
            corrected = hanging_points(neutral, frames[i][gown], weight, waist[0], waist_delta[i],
                                        yaws[i] - yaws[0], sway)
            if not np.array_equal(corrected[upper], frames[i][gown][upper]):
                raise AssertionError("Upper breathing surface was changed")
            posed = {gown: corrected}
            stole_clearance = {}
            for role, obj in front.items():
                points = frames[i][obj].copy()
                centers = deform(row_links[role], corrected)
                for row, w in enumerate(row_weights[role]):
                    if w <= 0:
                        continue
                    ids = slice(4 * row, min(4 * row + 4, 41))
                    offsets = neutral_offsets[role][row].copy()
                    offsets[:, :2] = offsets[:, :2] @ rotation_2d(yaws[i] - yaws[0]).T
                    desired = centers[row] + offsets
                    points[ids] += w * (desired - points[ids])
                posed[obj], stole_clearance[role] = clear_hanging_stole(
                    points, topology[obj], corrected, topology[gown], row_weights[role])
            torso = rig.pose.bones["Torso"]
            forward = rig.matrix_world.to_3x3() @ torso.matrix.to_3x3() @ torso.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0))
            for role, obj in bars.items():
                side = role.rsplit(" ", 1)[1][0]
                parent = next(o for r, o in front.items() if r.endswith(" " + side))
                posed[obj] = bar_points(posed[parent], int(role[-1]), np.asarray(forward.normalized()))
            body_points = evaluated_points(body)
            body_surfaces = {name: array_surface(body_points, fs) for name, fs in skin_faces.items() if fs}
            before_contacts = exact_contacts(frames[i][gown], topology[gown], body_surfaces)
            after_contacts = exact_contacts(corrected, topology[gown], body_surfaces)
            lower_stole_contacts = {}
            gown_surface = array_surface(corrected, topology[gown])
            for role, obj in front.items():
                lower_faces = [face for face in topology[obj] if any(row_weights[role][min(v // 4, 10)] > 0 for v in face)]
                lower_stole_contacts[role] = compact_crossings(array_surface(posed[obj], lower_faces), gown_surface)
            shifts = {obj.get("graduate_role"): float(np.max(np.linalg.norm(posed[obj] - frames[i][obj], axis=1))) for obj in objects}
            entry = {"frame": frame, "maximum_vertex_change_m": shifts,
                     "waist_delta_m": waist_delta[i].tolist(), "body_yaw_delta_degrees": math.degrees(float(yaws[i] - yaws[0])),
                     "before_profile": width_profile(frames[i][gown], waist[i], yaws[i], bands, pairs),
                     "after_profile": width_profile(corrected, waist[i], yaws[i], bands, pairs),
                     "exact_midpoint_before": before_contacts, "exact_midpoint_after": after_contacts,
                     "lower_stole_gown_midpoint": lower_stole_contacts,
                     "lower_stole_clearance": stole_clearance, "upper_gown_exactly_preserved": True,
                     "seconds": round(time.perf_counter() - began, 3)}
            report["frames"].append(entry)
            if not args.probe_frames:
                for obj in objects:
                    result_samples[obj].append(np.asarray(bindings[obj].inverse_points(posed[obj])))
            checkpoint()
            print("IDLE_GOWN_HANG", frame, "gown_delta", shifts[GOWN], "after_contacts",
                  {k: v["crossings"] for k, v in after_contacts.items()}, entry["seconds"], flush=True)
        if not args.probe_frames:
            for obj in objects:
                if obj.data.users > 1:
                    obj.data = obj.data.copy()
                bake_loop(obj, result_samples[obj], "Idle gravity hang | " + obj.get("graduate_role"))
    if rig_hash(rig) != before_rig or timing != (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base):
        raise AssertionError("Idle skeleton amplitude/timing changed")
    after_other = other_clip_hashes()
    if before_other != after_other:
        raise AssertionError("An existing non-Idle clip changed")
    report["other_clips_preserved"] = True
    report["other_clip_hashes_before"] = before_other
    report["other_clip_hashes_after"] = after_other
    report["skeleton_and_timing_preserved"] = True
    report["maximum_width_change_m"] = {
        name: {"before_span": float(np.ptp([f["before_profile"][name]["width_m"] for f in report["frames"]])),
               "after_span": float(np.ptp([f["after_profile"][name]["width_m"] for f in report["frames"]]))}
        for name in bands if name in report["frames"][0]["before_profile"]}
    report["contact_regression_frames"] = [f["frame"] for f in report["frames"]
        if any(f["exact_midpoint_after"][name]["crossings"] > f["exact_midpoint_before"][name]["crossings"]
               for name in f["exact_midpoint_after"])]
    if not args.probe_frames:
        bpy.context.window.scene = scene
        with visible_surfaces(scene, [body, *objects], "rendered"):
            scene.frame_set(1)
            bpy.context.view_layer.update()
            first = {obj: evaluated_points(obj) for obj in objects}
            scene.frame_set(period + 1)
            bpy.context.view_layer.update()
            seam = {obj.get("graduate_role"): float(np.max(np.linalg.norm(evaluated_points(obj) - first[obj], axis=1))) for obj in objects}
        if max(seam.values()) > 1e-5:
            raise AssertionError("Idle lower cloth loop is not closed")
        report["rendered_loop_seam_m"] = seam
        scene.frame_set(1)
        scene["Idle lower gown"] = "Neutral gravity-aligned lower silhouette; waist translation/yaw with millimetre delayed sway. Skeleton/timing unchanged."
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report["complete"] = True
    report["asset_saved"] = not bool(args.probe_frames)
    report["seconds"] = round(time.perf_counter() - started, 3)
    checkpoint()
    print("IDLE_GOWN_HANG_DONE", str(output), str(report_path), report["seconds"], flush=True)


if __name__ == "__main__":
    main()
