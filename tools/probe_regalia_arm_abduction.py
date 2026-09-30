"""Read-only representative-frame probe of additional shoulder abduction.

Runs 0, 2, 4, 6, and 8 degree candidates from each freshly restored original
pose; never accumulates the turns, inserts keys, edits morphs, or saves a blend.
Only the requested JSON report is written. Render-evaluated mesh crossings
include Solidify and are categorized rather than silently excluding seams.

Example (coordinate the sole background Blender process first):
 blender -b <candidate.blend> --python-exit-code 1 \
   --python tools/probe_regalia_arm_abduction.py -- \
   --samples 04_IDLE=1,51,91 01_WALK=9 02_RUN=7 03_JUMP=27 \
   --output art/Graduate/animation/arm-abduction-probe.json

This is a geometry probe, not a new cloth solve or a visible-pixel test. A
sewn-region label follows the existing gown source-face heuristic and does
not establish that a visible overlap is acceptable. Root must inspect the
smallest useful angle and then audit the final rebaked animation in full.
"""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import sys
import time

import bpy

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from audit_regalia_pairs import classify_source, relation
from regalia_arm_clearance import ARM_BONES, adjust_current_arm_pose
from validate_sleeve_garment_contact import SCALE, Surface, compare, visible_surfaces

DEFAULT_SAMPLES = {
    "04_IDLE": (1, 51, 91),
    "01_WALK": (9, 27),
    "02_RUN": (7, 19),
    "03_JUMP": (18, 27, 39),
}
ROLES = {
    "left": "02 | Bell sleeve L",
    "right": "02 | Bell sleeve R",
    "gown": "01 | Pleated bachelor gown",
    "skin": "Graduate | restored arm skin",
    "body": "Graduate | original face, hands and trousers",
}
PAIRS = (
    ("left_gown", "left", "gown"), ("right_gown", "right", "gown"),
    ("left_skin", "left", "skin"), ("right_skin", "right", "skin"),
    ("left_hands_body", "left", "body"), ("right_hands_body", "right", "body"),
    ("left_self", "left", "left"), ("right_self", "right", "right"),
    ("left_right", "left", "right"),
)


def set_frame(scene, frame):
    whole = math.floor(frame)
    scene.frame_set(whole, subframe=frame - whole)
    bpy.context.view_layer.update()


def capture_pose(rig):
    # Preserve exact source channels instead of decompose/recompose matrices.
    return {
        bone.name: {
            "rotation_mode": bone.rotation_mode,
            "location": bone.location.copy(),
            "rotation_quaternion": bone.rotation_quaternion.copy(),
            "rotation_euler": bone.rotation_euler.copy(),
            "rotation_axis_angle": tuple(bone.rotation_axis_angle),
            "scale": bone.scale.copy(),
        }
        for bone in rig.pose.bones
    }


def restore_pose(rig, pose):
    for name, values in pose.items():
        bone = rig.pose.bones[name]
        bone.rotation_mode = values["rotation_mode"]
        bone.location = values["location"]
        bone.rotation_quaternion = values["rotation_quaternion"]
        bone.rotation_euler = values["rotation_euler"]
        bone.rotation_axis_angle = values["rotation_axis_angle"]
        bone.scale = values["scale"]
    bpy.context.view_layer.update()


def pose_reset_error(rig, pose):
    errors = []
    for name, values in pose.items():
        bone = rig.pose.bones[name]
        for property_name in ("location", "rotation_quaternion", "rotation_euler", "rotation_axis_angle", "scale"):
            errors.extend(abs(float(a) - float(b)) for a, b in zip(getattr(bone, property_name), values[property_name]))
    return max(errors, default=0.0)


def hand_faces(obj):
    groups = {group.index for group in obj.vertex_groups
              if group.name.startswith(("Palm.", "Finger", "Thumb"))}
    if not groups:
        raise ValueError(f"No hand bone vertex groups on {obj.name}")
    touched = {v.index for v in obj.data.vertices
               if any(g.group in groups and g.weight > 0 for g in v.groups)}
    return {p.index for p in obj.data.polygons if any(v in touched for v in p.vertices)}


def pair_result(a, b, same, seam_faces, hands, epsilon, max_examples):
    evidence = compare(a, b, same, epsilon)
    relations, layers, hands_regions = Counter(), Counter(), Counter()
    examples = []
    for (ia, ib), length in zip(evidence["triangle_pairs"], evidence["intersection_segment_lengths_m"]):
        kind = relation(a, ia, b, ib, seam_faces)
        relations[kind] += 1
        ap = a.source_map[a.polygons[ia]]
        bp = b.source_map[b.polygons[ib]]
        layers[ap["layer"] + " / " + bp["layer"]] += 1
        hand_region = None
        if b.metadata["role"] == ROLES["body"]:
            body_polygon = bp["source_polygon"]
            hand_region = ("hand_weighted_source_face" if body_polygon in hands else
                           "other_body_source_face" if body_polygon is not None else
                           "unmapped_modified_body_face")
            hands_regions[hand_region] += 1
        examples.append({
            "triangle_ids": [ia, ib],
            "source_polygon_ids": [ap["source_polygon"], bp["source_polygon"]],
            "relation": kind, "body_region": hand_region,
            "intersection_segment_m": length,
        })
    examples.sort(key=lambda item: (-item["intersection_segment_m"], item["triangle_ids"]))
    return {
        "roles": [a.metadata["role"], b.metadata["role"]],
        "raw_crossings": evidence["crossings"],
        "relation_counts": dict(relations),
        "hand_region_counts": dict(hands_regions),
        "layer_counts": dict(layers),
        "maximum_intersection_segment_m": evidence["maximum_intersection_segment_m"],
        "total_intersection_segment_m": sum(evidence["intersection_segment_lengths_m"]),
        "adjacent_self_pairs_excluded": evidence["adjacent_excluded"],
        "seam_pairs_excluded": evidence["seam_excluded"],
        "examples": examples[:max_examples],
    }


def collect_contacts(objects, seam_faces, hands, epsilon, max_examples):
    surfaces = {name: Surface(obj) for name, obj in objects.items()}
    for name, surface in surfaces.items():
        # Copies the source seam flags into original_seam and switches off the
        # old compare() seam exclusion; every crossing remains in raw totals.
        classify_source(surface, objects[name])
    pairs = {name: pair_result(surfaces[a], surfaces[b], a == b, seam_faces, hands,
                              epsilon, max_examples)
             for name, a, b in PAIRS}
    gown = [pairs[name] for name in ("left_gown", "right_gown")]
    skin = [pairs[name] for name in ("left_skin", "right_skin")]
    body = [pairs[name] for name in ("left_hands_body", "right_hands_body")]
    self_pairs = [pairs[name] for name in ("left_self", "right_self", "left_right")]
    summary = {
        "gown_raw": sum(p["raw_crossings"] for p in gown),
        "gown_independent": sum(p["relation_counts"].get("independent_surface_contact", 0) for p in gown),
        "gown_armhole_join_region": sum(p["relation_counts"].get("documented_armhole_join_region", 0) for p in gown),
        "gown_pinned_attachment_region": sum(p["relation_counts"].get("pinned_sleeve_attachment_region", 0) for p in gown),
        "restored_skin_raw": sum(p["raw_crossings"] for p in skin),
        "hands_and_body_raw": sum(p["raw_crossings"] for p in body),
        "hands_raw": sum(p["hand_region_counts"].get("hand_weighted_source_face", 0) for p in body),
        "self_and_opposite_sleeve_raw": sum(p["raw_crossings"] for p in self_pairs),
        "maximum_segment_m": max(p["maximum_intersection_segment_m"] for p in pairs.values()),
    }
    return {"summary": summary, "pairs": pairs}


def aggregate(report):
    totals = {}
    for clip in report["clips"].values():
        for frame in clip["frames"]:
            baseline = next(row for row in frame["angles"] if row["additional_degrees"] == 0)
            for row in frame["angles"]:
                angle = str(row["additional_degrees"])
                item = totals.setdefault(angle, {
                    "sampled_frames": 0, "totals": Counter(), "maximum_palm_shift_m": 0.0,
                    "new_skin_body_or_self_contact_frames": 0,
                    "remaining_independent_gown_contact_frames": 0,
                })
                item["sampled_frames"] += 1
                item["totals"].update({key: value for key, value in row["summary"].items()
                                        if key != "maximum_segment_m"})
                item["maximum_palm_shift_m"] = max(item["maximum_palm_shift_m"], *row["palm_head_shift_m"].values())
                item["new_skin_body_or_self_contact_frames"] += int(any(
                    row["summary"][key] > baseline["summary"][key]
                    for key in ("restored_skin_raw", "hands_and_body_raw", "self_and_opposite_sleeve_raw")))
                item["remaining_independent_gown_contact_frames"] += int(row["summary"]["gown_independent"] > 0)
    return totals


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene-prefix", nargs="+", default=list(DEFAULT_SAMPLES))
    parser.add_argument("--samples", nargs="*", default=[], help="Per-scene overrides, e.g. 04_IDLE=1,51,91")
    parser.add_argument("--angles", nargs="+", type=float, default=[0, 2, 4, 6, 8])
    parser.add_argument("--epsilon", type=float, default=1e-6)
    parser.add_argument("--max-examples", type=int, default=8)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    angles = sorted(set(args.angles + [0.0]))
    if any(not math.isfinite(angle) or not 0 <= angle <= 20 for angle in angles):
        parser.error("angles must be finite, between 0 and 20 degrees")
    if args.epsilon <= 0 or args.max_examples < 0:
        parser.error("epsilon must be positive and max-examples nonnegative")
    overrides = {key: tuple(float(value) for value in values.split(","))
                 for key, values in (item.split("=", 1) for item in args.samples)}
    started = time.perf_counter()
    original_scene = bpy.context.window.scene
    original_frames = {s: (s.frame_current, s.frame_subframe) for s in bpy.data.scenes}
    original_poses = {o: capture_pose(o) for s in bpy.data.scenes for o in s.objects if o.type == "ARMATURE"}
    source_gown = next(o for s in bpy.data.scenes if s.name.startswith("03_JUMP")
                       for o in s.objects if o.get("graduate_role") == ROLES["gown"])
    seam_faces = {p.index for p in source_gown.data.polygons if p.center.z > 3.05 and abs(p.center.x) > .34}
    report = {
        "source_blend": bpy.data.filepath, "saved_blend": False, "complete": False,
        "surface": "rendered", "additional_degrees": angles, "epsilon_m": args.epsilon,
        "method": "Exact transverse crossings on evaluated surfaces, including Solidify; no seam exclusions",
        "pose_method": "Fresh frame evaluation and exact original pose channels restored before each single additive turn",
        "joint_region_method": "Same source Jump gown face IDs as audit_regalia_pairs: center.z > 3.05 and abs(center.x) > 0.34",
        "joint_region_source_faces": sorted(seam_faces),
        "limitations": "Representative frames only; contact segment length is not penetration depth. Sewn-region labels are descriptive. No cloth rebake or visible-pixel assessment.",
        "clips": {},
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)

    def save_progress():
        report["aggregate_by_additional_degree"] = aggregate(report)
        report["elapsed_seconds"] = time.perf_counter() - started
        args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")

    try:
        for prefix in args.scene_prefix:
            matches = [scene for scene in bpy.data.scenes if scene.name.startswith(prefix)]
            if len(matches) != 1:
                raise ValueError(f"Expected one scene for {prefix}, got {len(matches)}")
            scene = matches[0]
            bpy.context.window.scene = scene
            rig = next(obj for obj in scene.objects if obj.type == "ARMATURE" and not obj.get("preview_fx"))
            objects = {name: next(obj for obj in scene.objects if obj.get("graduate_role") == role)
                       for name, role in ROLES.items()}
            hands = hand_faces(objects["body"])
            frames = sorted(set(overrides.get(prefix, DEFAULT_SAMPLES.get(prefix, (scene.frame_start,)))))
            if any(not math.isfinite(frame) or not scene.frame_start <= frame <= scene.frame_end for frame in frames):
                raise ValueError(f"Probe frame outside {scene.name}: {frames}")
            clip = {"scene": scene.name, "frames": []}
            report["clips"][prefix] = clip
            with visible_surfaces(scene, list(objects.values()), "rendered"):
                for frame in frames:
                    set_frame(scene, frame)
                    base_pose = capture_pose(rig)
                    for name in ARM_BONES:
                        if base_pose[name]["rotation_mode"] != "QUATERNION":
                            raise ValueError(f"Upper arm must use quaternion: {name}")
                    world = rig.matrix_world.copy()
                    palms = {side: world @ rig.pose.bones["Palm." + side].head for side in ("L", "R")}
                    row = {"frame": frame, "angles": []}
                    clip["frames"].append(row)
                    for angle in angles:
                        # Do not rely on changing the frame to undo the prior
                        # angle: restore explicit original channels even when
                        # the candidate is tested at exactly the same frame.
                        set_frame(scene, frame)
                        restore_pose(rig, base_pose)
                        reset_error = pose_reset_error(rig, base_pose)
                        if reset_error > 1e-7:
                            raise RuntimeError(f"Original pose restoration failed: {reset_error}")
                        adjustments = adjust_current_arm_pose(rig, angle) if angle else []
                        bpy.context.view_layer.update()
                        result = collect_contacts(objects, seam_faces, hands, args.epsilon, args.max_examples)
                        result.update({
                            "additional_degrees": angle,
                            "original_pose_reset_max_channel_error": reset_error,
                            "upper_arm_adjustments": adjustments,
                            "palm_head_shift_m": {
                                side: ((rig.matrix_world @ rig.pose.bones["Palm." + side].head) - palms[side]).length * SCALE
                                for side in ("L", "R")
                            },
                        })
                        row["angles"].append(result)
                        save_progress()
                        print("ARM_ABDUCTION_PROBE", prefix, frame, angle, result["summary"], flush=True)
                    restore_pose(rig, base_pose)
        report["complete"] = True
        save_progress()
    finally:
        for scene, (frame, subframe) in original_frames.items():
            bpy.context.window.scene = scene
            scene.frame_set(frame, subframe=subframe)
        for rig, pose in original_poses.items():
            restore_pose(rig, pose)
        bpy.context.window.scene = original_scene
        bpy.context.view_layer.update()
    print("ARM_ABDUCTION_PROBE_DONE", str(args.output), flush=True)


if __name__ == "__main__":
    main()
