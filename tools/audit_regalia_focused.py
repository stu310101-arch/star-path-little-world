"""Read-only, all-frame regalia regression audit with geometry-proven scope.

Run in one Blender process after the candidate is complete::

  blender --background --factory-startup --threads 2 --python-exit-code 1 \
    --python tools/audit_regalia_focused.py -- \
    --baseline art/Graduate/Male_Graduate_GameReady.blend \
    --candidate art/Graduate/Male_Graduate_Regalia_Final_Candidate.blend \
    --output art/Graduate/animation/regalia-focused.json

The baseline is loaded and fingerprinted first, then the candidate is loaded.
Each candidate frame still evaluates every real rendered character surface.
Only a pair whose two meshes are outside the requested clothing scope AND
whose complete evaluated geometry/visibility equal the baseline at that frame
can bypass intersection testing. Unexpected changes are audited automatically.
The existing exact-contact classification and 24-direction visibility test are
reused unchanged. No asset is saved, no additional process is launched.

Fingerprints prove collision geometry preservation, not material appearance.
Existing contacts between unchanged meshes are inherited, not reported as zero.
The underlying checker excludes coplanar, tangent and shared-vertex self pairs;
its visibility rays are not pixel visibility or penetration-depth measurements.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import audit_regalia_pairs as audit
from export_graduate_godot import role_map
from validate_sleeve_garment_contact import visible_surfaces

PREFIXES = ("01_WALK", "02_RUN", "03_JUMP", "04_IDLE")
CLOTHING_PREFIXES = ("01 |", "02 |", "03 |", "04 |", "05 |")
ORIGINAL_SURFACE = audit.Surface
ORIGINAL_COMPARE = audit.compare


def file_digest(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(4 * 1024 * 1024), b""):
            digest.update(block)
    stat = path.stat()
    return {"path": str(path), "sha256": digest.hexdigest(),
            "bytes": stat.st_size, "mtime_ns": stat.st_mtime_ns}


def geometry_digest(surface):
    """All evaluated world-space points, triangles and exact-test normals."""
    digest = hashlib.sha256()
    arrays = (
        np.asarray(surface.points, dtype="<f8").reshape((-1, 3)),
        np.asarray(surface.triangles, dtype="<i8").reshape((-1, 3)),
        np.asarray([tuple(n) if n is not None else (0., 0., 0.)
                    for n in surface.normals], dtype="<f8").reshape((-1, 3)),
        np.asarray(surface.degenerate, dtype="<i8"),
    )
    parts = {}
    for name, array in zip(("world_points_sha256", "triangle_indices_sha256",
                            "triangle_normals_sha256", "degenerate_indices_sha256"), arrays):
        if not np.isfinite(array).all():
            raise ValueError("Non-finite evaluated geometry: " + surface.metadata["role"])
        payload = str(array.shape).encode("ascii") + array.tobytes(order="C")
        digest.update(payload)
        parts[name] = hashlib.sha256(payload).hexdigest()
    return {"sha256": digest.hexdigest(), "vertices": len(surface.points),
            "triangles": len(surface.triangles), **parts}


def scene_for(prefix):
    matches = [scene for scene in bpy.data.scenes if scene.name.startswith(prefix)]
    if len(matches) != 1:
        raise ValueError(f"Expected one scene for {prefix}; got {len(matches)}")
    return matches[0]


def frame_plan(scene, half_frames):
    frames = [float(frame) for frame in range(scene.frame_start, scene.frame_end + 1)]
    if not scene.name.startswith("03_JUMP"):
        frames.append(float(scene.frame_end + 1))
    if half_frames:
        frames.extend(frame + .5 for frame in range(scene.frame_start, int(max(frames))))
    return sorted(frames)


def frame_key(frame):
    return f"{frame:g}"


def expected_affected(role):
    return role.startswith(CLOTHING_PREFIXES)


def collect_baseline(path, args, progress):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    result = {}
    for prefix in PREFIXES:
        scene = scene_for(prefix)
        _, meshes = role_map(scene)
        objects = [meshes[role] for role in sorted(meshes)]
        protected = [obj for obj in objects if not expected_affected(obj["graduate_role"])]
        frames = frame_plan(scene, args.half_frames)
        clip = {"scene": scene.name, "fps": scene.render.fps / scene.render.fps_base,
                "frame_start": scene.frame_start, "frame_end": scene.frame_end,
                "roles": sorted(meshes), "frames": {}}
        for frame in frames:
            bpy.context.window.scene = scene
            audit.set_frame(scene, frame)
            rendered = {obj["graduate_role"]: not obj.hide_render for obj in objects}
            fingerprints = {}
            with visible_surfaces(scene, objects, "rendered"):
                audit.set_frame(scene, frame)
                for obj in protected:
                    role = obj["graduate_role"]
                    fingerprints[role] = geometry_digest(ORIGINAL_SURFACE(obj))
                    fingerprints[role]["rendered"] = rendered[role]
            clip["frames"][frame_key(frame)] = fingerprints
            progress({"stage": "baseline", "clip": prefix, "frame": frame,
                      "protected_meshes": len(fingerprints)})
        result[prefix] = clip
    return result


def run_candidate(path, baseline, args, progress):
    bpy.ops.wm.open_mainfile(filepath=str(path))
    summary = {"clips": {}, "unexpected_changed_roles": {}, "raw_crossings": 0,
               "external_ray_reachable_crossings": 0, "exact_pair_checks": 0,
               "proven_unchanged_pair_skips": 0}
    for prefix in PREFIXES:
        scene = scene_for(prefix)
        _, meshes = role_map(scene)
        objects = [meshes[role] for role in sorted(meshes)]
        source = baseline[prefix]
        frames = frame_plan(scene, args.half_frames)
        if sorted(meshes) != source["roles"]:
            raise ValueError(f"Role inventory changed in {prefix}; review additions/removals first")
        if [frame_key(frame) for frame in frames] != list(source["frames"]):
            raise ValueError(f"Frame plan changed in {prefix}; refusing unmatched preservation claims")
        gown = meshes["01 | Pleated bachelor gown"]
        seam_faces = {poly.index for poly in gown.data.polygons
                      if poly.center.z > 3.05 and abs(poly.center.x) > .34}
        clip = {"scene": scene.name, "fps": scene.render.fps / scene.render.fps_base,
                "baseline_fps": source["fps"], "frame_start": scene.frame_start,
                "frame_end": scene.frame_end, "sample_count": len(frames),
                "requested_affected_roles": [role for role in sorted(meshes) if expected_affected(role)],
                "protected_role_count": sum(not expected_affected(role) for role in meshes),
                "raw_crossings": 0, "external_ray_reachable_crossings": 0,
                "unexpected_geometry_changes": {}, "preserved_roles_all_samples": [],
                "worst_pairs": {}, "loop_endpoint_errors_m": {}}
        preserved_all = {role for role in meshes if not expected_affected(role)}
        first_points = {}
        for frame in frames:
            fingerprint = {}
            unchanged = set()
            changes = {}
            checked, skipped = [], []
            bpy.context.window.scene = scene
            audit.set_frame(scene, frame)
            rendered = {obj["graduate_role"]: not obj.hide_render for obj in objects}

            def recording_surface(obj):
                surface = ORIGINAL_SURFACE(obj)
                role = obj["graduate_role"]
                if frame == frames[0] and not prefix.startswith("03_JUMP"):
                    first_points[role] = np.asarray(surface.points, dtype=float).copy()
                if frame == frames[-1] and not prefix.startswith("03_JUMP"):
                    current = np.asarray(surface.points, dtype=float)
                    first = first_points[role]
                    clip["loop_endpoint_errors_m"][role] = (
                        float(np.linalg.norm(current - first, axis=1).max(initial=0))
                        if current.shape == first.shape else None)
                if not expected_affected(role):
                    value = geometry_digest(surface)
                    value["rendered"] = rendered[role]
                    fingerprint[role] = value
                    prior = source["frames"][frame_key(frame)][role]
                    if value == prior:
                        unchanged.add(role)
                    else:
                        reasons = [key for key in value if value[key] != prior[key]]
                        changes[role] = {"reason": reasons, "baseline": prior, "candidate": value}
                return surface

            def focused_compare(first, second, same, epsilon):
                roles = [first.metadata["role"], second.metadata["role"]]
                if all(role in unchanged for role in roles):
                    skipped.append(roles)
                    return {"crossings": 0}
                checked.append(roles)
                return ORIGINAL_COMPARE(first, second, same, epsilon)

            audit.Surface, audit.compare = recording_surface, focused_compare
            try:
                entry = audit.audit_frame(scene, frame, objects, seam_faces, args)
            finally:
                audit.Surface, audit.compare = ORIGINAL_SURFACE, ORIGINAL_COMPARE
            preserved_all.intersection_update(unchanged)
            entry["broadphase_candidate_pairs"] = entry["broadphase_pairs_checked"]
            entry["broadphase_pairs_checked"] = len(checked)
            entry["exact_checked_role_pairs"] = checked
            entry["proven_unchanged_pairs_skipped"] = skipped
            entry["protected_mesh_fingerprints"] = fingerprint
            entry["unexpected_changed_meshes_audited"] = changes
            for role, change in changes.items():
                clip["unexpected_geometry_changes"].setdefault(role, []).append(frame)
                summary["unexpected_changed_roles"].setdefault(role, {}).setdefault(prefix, []).append(frame)
            for pair in entry["pairs"]:
                key = " <> ".join(pair["roles"])
                previous = clip["worst_pairs"].get(key)
                if previous is None or pair["maximum_intersection_segment_m"] > previous["maximum_intersection_segment_m"]:
                    clip["worst_pairs"][key] = {"frame": frame, **pair}
            for field in ("raw_crossings", "external_ray_reachable_crossings"):
                clip[field] += entry[field]
                summary[field] += entry[field]
            summary["exact_pair_checks"] += len(checked)
            summary["proven_unchanged_pair_skips"] += len(skipped)
            progress({"stage": "candidate", "clip": prefix, **entry})
        clip["preserved_roles_all_samples"] = sorted(preserved_all)
        summary["clips"][prefix] = clip
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--half-frames", action="store_true")
    parser.add_argument("--max-examples", type=int, default=4)
    parser.add_argument("--epsilon", type=float, default=1e-6)
    parser.add_argument("--visibility-tolerance", type=float, default=.0005)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    args.surface = "rendered"
    for key in ("baseline", "candidate", "output"):
        setattr(args, key, getattr(args, key).resolve())
    if args.baseline == args.candidate:
        parser.error("Baseline and candidate must be different files")
    if args.output in (args.baseline, args.candidate):
        parser.error("Report must not overwrite an asset")
    if args.max_examples < 0 or not math.isfinite(args.epsilon) or args.epsilon <= 0:
        parser.error("max-examples must be nonnegative and epsilon finite positive")
    if not math.isfinite(args.visibility_tolerance) or args.visibility_tolerance <= 0:
        parser.error("visibility-tolerance must be finite positive")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    details = args.output.with_suffix(".frames.jsonl")
    manifest = args.output.with_suffix(".baseline.json")
    started = time.perf_counter()
    report = {"complete": False, "asset_saved": False,
              "baseline": file_digest(args.baseline), "candidate": file_digest(args.candidate),
              "surface": "rendered, including enabled Triangulate and Solidify",
              "scope": "Every pair with requested clothing or a changed evaluated mesh; every affected self pair",
              "preservation": "Exact evaluated world-space points, triangle topology, normals and render visibility per frame; not material appearance",
              "skipped_pair_meaning": "Both meshes proven unchanged at this frame; inherited contacts are not recounted and are not asserted absent",
              "contact_method": "Existing finite transverse intersections, no sewn-region exclusion; classifications retained",
              "contact_limits": "Coplanar/tangent contacts and shared-vertex self pairs excluded; integer frames and loop endpoints do not prove continuous-time clearance",
              "visibility_method": "All exact contacts retain 24 external rays through all rendered meshes; not pixel visibility or penetration depth",
              "half_frames": args.half_frames, "epsilon_m": args.epsilon,
              "frame_report": str(details), "baseline_manifest": str(manifest)}
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    with details.open("w", encoding="utf-8") as stream:
        def progress(entry):
            entry["elapsed_seconds"] = time.perf_counter() - started
            stream.write(json.dumps(entry, separators=(",", ":")) + "\n")
            stream.flush()
            print("REGALIA_FOCUSED", entry["stage"], entry["clip"], entry["frame"],
                  "raw", entry.get("raw_crossings", "-"),
                  "seconds", round(entry["elapsed_seconds"], 2), flush=True)
        try:
            baseline = collect_baseline(args.baseline, args, progress)
            manifest.write_text(json.dumps(baseline, separators=(",", ":")), encoding="utf-8")
            report.update(run_candidate(args.candidate, baseline, args, progress))
            report["inputs_unchanged"] = all(
                file_digest(getattr(args, name)) == report[name] for name in ("baseline", "candidate"))
            if not report["inputs_unchanged"]:
                raise RuntimeError("An input asset changed during the audit")
            report["complete"] = True
        except Exception as error:
            report["error"] = f"{type(error).__name__}: {error}"
            raise
        finally:
            audit.Surface, audit.compare = ORIGINAL_SURFACE, ORIGINAL_COMPARE
            report["elapsed_seconds"] = time.perf_counter() - started
            args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("REGALIA_FOCUSED_DONE", str(args.output), flush=True)


if __name__ == "__main__":
    main()
