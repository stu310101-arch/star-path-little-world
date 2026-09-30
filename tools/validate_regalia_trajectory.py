"""Read-only comparison of baked gown motion against its original animation.

Run in a coordinated background Blender process, never the interactive editor::

    blender -b --python-exit-code 1 --python tools/validate_regalia_trajectory.py -- \
        --candidate art/Graduate/Male_Graduate_Regalia_Layers_Candidate.blend

The CLI loads both files, samples their gown midsurfaces at the authored frame
indices, and writes only JSON. It does not save either blend or launch a process.
``collect_current`` restores temporary visibility/modifier/frame changes;
``compare_caches`` is a NumPy-only function for existing world-space caches.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
GOWN = "01 | Pleated bachelor gown"
PREFIXES = {"walk": "01_WALK", "run": "02_RUN", "idle": "04_IDLE"}


def _norm_stats(vectors):
    lengths = np.linalg.norm(vectors, axis=-1)
    return {"max_m": float(lengths.max(initial=0)),
            "rms_m": float(np.sqrt(np.mean(lengths ** 2))),
            "p95_m": float(np.percentile(lengths, 95))}


def _topology_hash(polygons):
    return hashlib.sha256(json.dumps(polygons, separators=(",", ":")).encode()).hexdigest()


def _vertex_regions(source_points, polygons):
    """Coordinate labels are descriptive regions, not a collision exemption."""
    source = np.asarray(source_points, dtype=np.float64)
    shoulder, armhole = set(), set()
    incident = [[] for _ in source]
    for index, polygon in enumerate(polygons):
        center = source[list(polygon)].mean(axis=0)
        for vertex in polygon:
            incident[vertex].append(index)
        if center[2] > 3.05 and abs(center[0]) > .34:
            armhole.update(polygon)
        if center[2] > 3.8 and abs(center[0]) > .34:
            shoulder.update(polygon)
    low, high = float(source[:, 2].min()), float(source[:, 2].max())
    hem_top = low + .2 * (high - low)
    regions = []
    for vertex, (x, y, z) in enumerate(source):
        if vertex in shoulder:
            band = "protected_shoulder"
        elif vertex in armhole:
            band = "documented_armhole_join"
        elif z <= hem_top:
            band = "hem_lower_20_percent"
        elif abs(x) > .34:
            band = "free_side_panel"
        else:
            band = "central_panel"
        regions.append({"band": band, "x_side": "positive" if x >= 0 else "negative",
                        "y_side": "positive" if y >= 0 else "negative"})
    return regions, incident


def collect_current(clips=("walk", "run", "idle")):
    """Read the currently loaded blend, retaining no Blender object references."""
    import bpy
    sys.path.insert(0, str(ROOT / "tools"))
    from simulate_portal_cloth import SCALE, evaluated_points
    from validate_sleeve_garment_contact import visible_surfaces

    cache = {"blend": bpy.data.filepath, "world_scale_to_m": SCALE, "clips": {}}
    for clip in clips:
        matches = [s for s in bpy.data.scenes if s.name.startswith(PREFIXES[clip])]
        if len(matches) != 1:
            raise ValueError(f"Expected one {clip} scene, found {len(matches)}")
        scene = matches[0]
        gowns = [o for o in scene.objects if o.get("graduate_role") == GOWN]
        if len(gowns) != 1:
            raise ValueError(f"Expected one gown in {scene.name}, found {len(gowns)}")
        gown = gowns[0]
        frames = list(range(scene.frame_start, scene.frame_end + 1))
        if len(frames) < 2:
            raise ValueError(f"{scene.name} needs at least two distinct authored frames")
        source = np.asarray([v.co[:] for v in gown.data.vertices], dtype=np.float64)
        polygons = [tuple(p.vertices) for p in gown.data.polygons]
        samples = []
        with visible_surfaces(scene, [gown], "simulation"):
            for frame in frames + [scene.frame_end + 1]:
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                points = evaluated_points(gown)
                if points.shape != source.shape:
                    raise ValueError(f"Midsurface/source vertex mismatch in {scene.name}: {points.shape}/{source.shape}")
                samples.append(points)
        cache["clips"][clip] = {
            "scene": scene.name, "object": gown.name,
            "fps": scene.render.fps / scene.render.fps_base, "frames": frames,
            "source_points": source, "polygons": polygons,
            "topology_hash": _topology_hash(polygons),
            "points": np.asarray(samples[:-1]), "endpoint": samples[-1],
        }
        print("REGALIA_TRAJECTORY_SAMPLED", Path(cache["blend"]).name, clip,
              len(frames), "frames", len(source), "vertices", flush=True)
    return cache


def compare_caches(original, candidate, top=12):
    """Compare matching frame indices; deltas are world-space, in meters.

    Each transition is (candidate-next - original-next) minus
    (candidate-now - original-now). Thus ordinary authored movement cancels.
    The final transition is the last unique frame to the first unique frame.
    The separately sampled end+1 checks whether that wrap exists in the bake.
    """
    if not 1 <= top <= 100:
        raise ValueError("top must be between 1 and 100")
    if set(original["clips"]) != set(candidate["clips"]):
        raise ValueError("The caches must contain the same clips")
    if original.get("world_scale_to_m") != candidate.get("world_scale_to_m"):
        raise ValueError("Caches use different world scales")
    report = {
        "original_blend": original["blend"], "candidate_blend": candidate["blend"],
        "read_only": True, "complete": False,
        "units": "meters; original source coordinates are unscaled Blender mesh-local units",
        "surface": "evaluated gown midsurface; non-ARMATURE modifiers temporarily disabled",
        "formula": "correction[f,v]=candidate[f,v]-original[f,v]; transition=correction[next,v]-correction[f,v]",
        "wrap_definition": "last unique authored frame to first; end+1 sampled separately to verify closure",
        "percentile_definition": "other-transition p95 is taken over per-transition maxima or RMS, excluding wrap",
        "region_definition": "Original source polygon centers: protected shoulder z>3.8 and abs(x)>.34; documented armhole z>3.05 and abs(x)>.34. Hem is lower20% of source z range. Regions do not establish collision safety.",
        "limitations": "Samples authored integer frames; no collision, shell, subframe, skeleton-preservation, or visual acceptance assertion. FPS differences are reported; frame indices must still represent corresponding poses.",
        "clips": {},
    }
    for clip, ref in original["clips"].items():
        now = candidate["clips"][clip]
        frames = ref["frames"]
        if frames != now["frames"]:
            raise ValueError(f"{clip}: different frame ranges")
        if ref["topology_hash"] != now["topology_hash"]:
            raise ValueError(f"{clip}: different polygon/vertex indexing")
        old_points, new_points = np.asarray(ref["points"]), np.asarray(now["points"])
        if old_points.shape != new_points.shape or old_points.ndim != 3 or old_points.shape[-1] != 3:
            raise ValueError(f"{clip}: invalid or mismatched cache shapes")
        if not np.isfinite(old_points).all() or not np.isfinite(new_points).all():
            raise ValueError(f"{clip}: non-finite cached coordinates")
        nframes, nvertices, _ = old_points.shape
        if nframes != len(frames) or nframes < 2 or not nvertices:
            raise ValueError(f"{clip}: invalid frame/vertex counts")
        regions, incident = _vertex_regions(ref["source_points"], ref["polygons"])
        correction = new_points - old_points
        delta = np.roll(correction, -1, axis=0) - correction
        old_delta = np.roll(old_points, -1, axis=0) - old_points
        new_delta = np.roll(new_points, -1, axis=0) - new_points
        lengths = np.linalg.norm(delta, axis=2)

        def vertex_record(pair_index, vertex):
            nxt = (pair_index + 1) % nframes
            return {
                "frame_from": frames[pair_index], "frame_to": frames[nxt],
                "wrap": pair_index == nframes - 1, "vertex_id": int(vertex),
                "region": regions[vertex], "source_xyz": ref["source_points"][vertex].tolist(),
                "incident_source_polygons": incident[vertex],
                "correction_from_xyz_m": correction[pair_index, vertex].tolist(),
                "correction_to_xyz_m": correction[nxt, vertex].tolist(),
                "correction_delta_xyz_m": delta[pair_index, vertex].tolist(),
                "correction_delta_m": float(lengths[pair_index, vertex]),
                "original_motion_m": float(np.linalg.norm(old_delta[pair_index, vertex])),
                "candidate_motion_m": float(np.linalg.norm(new_delta[pair_index, vertex])),
            }

        pairs, magnitudes = [], []
        for i, frame in enumerate(frames):
            vertex = int(np.argmax(lengths[i]))
            pairs.append({
                "frame_from": frame, "frame_to": frames[(i + 1) % nframes],
                "wrap": i == nframes - 1,
                "correction_delta": _norm_stats(delta[i]),
                "original_motion": _norm_stats(old_delta[i]),
                "candidate_motion": _norm_stats(new_delta[i]),
                "largest_vertex": vertex_record(i, vertex),
            })
            magnitudes.append({"frame": frame, **_norm_stats(correction[i])})
        other_max = np.asarray([p["correction_delta"]["max_m"] for p in pairs[:-1]])
        other_rms = np.asarray([p["correction_delta"]["rms_m"] for p in pairs[:-1]])
        p95_max, p95_rms = float(np.percentile(other_max, 95)), float(np.percentile(other_rms, 95))
        wrap_stats = pairs[-1]["correction_delta"]
        comparison = {}
        for metric, p95 in (("max_m", p95_max), ("rms_m", p95_rms)):
            value = wrap_stats[metric]
            comparison[metric] = {"wrap": value, "other_transitions_p95": p95,
                                  "wrap_minus_p95": value - p95,
                                  "wrap_to_p95_ratio": value / p95 if p95 > 1e-12 else None,
                                  "wrap_exceeds_p95": value > p95 + 1e-12}
        flat = lengths.reshape(-1)
        count = min(top, len(flat))
        # Deterministic full sort is small for these authored gown caches.
        largest = np.argsort(-flat, kind="stable")[:count]
        events = [vertex_record(int(index // nvertices), int(index % nvertices)) for index in largest]
        region_summary = {}
        for band in sorted({r["band"] for r in regions}):
            ids = np.asarray([i for i, r in enumerate(regions) if r["band"] == band])
            region_summary[band] = {"vertex_count": len(ids),
                                    "all_transitions": _norm_stats(delta[:, ids]),
                                    "wrap": _norm_stats(delta[-1, ids])}
        old_endpoint, new_endpoint = np.asarray(ref["endpoint"]), np.asarray(now["endpoint"])
        if old_endpoint.shape != old_points[0].shape or new_endpoint.shape != new_points[0].shape:
            raise ValueError(f"{clip}: endpoint topology mismatch")
        endpoint_correction = new_endpoint - old_endpoint
        report["clips"][clip] = {
            "original_scene": ref["scene"], "candidate_scene": now["scene"],
            "frame_range": [frames[0], frames[-1]], "frame_count": nframes,
            "vertex_count": nvertices, "topology_matches": True,
            "original_fps": ref["fps"], "candidate_fps": now["fps"],
            "fps_matches": ref["fps"] == now["fps"],
            "per_frame_correction": magnitudes, "frame_pairs": pairs,
            "largest_frame_pairs": sorted(pairs, key=lambda p: p["correction_delta"]["max_m"], reverse=True)[:top],
            "largest_vertex_events": events, "regions": region_summary,
            "wrap_vs_other_transitions_p95": comparison,
            "loop_endpoint": {
                "endpoint_frame": frames[-1] + 1, "reference_frame": frames[0],
                "original_endpoint_minus_first": _norm_stats(old_endpoint - old_points[0]),
                "candidate_endpoint_minus_first": _norm_stats(new_endpoint - new_points[0]),
                "correction_endpoint_minus_first": _norm_stats(endpoint_correction - correction[0]),
                "actual_last_to_endpoint_correction_delta": _norm_stats(endpoint_correction - correction[-1]),
            },
        }
    report["complete"] = True
    return report


def main(argv=None):
    import bpy
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--original", type=Path, default=ROOT / "art/Graduate/Male_Graduate_GameReady.blend")
    parser.add_argument("--output", type=Path, default=ROOT / "art/Graduate/animation/regalia-trajectory-validation.json")
    parser.add_argument("--clips", choices=tuple(PREFIXES), nargs="+", default=list(PREFIXES))
    parser.add_argument("--top", type=int, default=12)
    args = parser.parse_args(argv)
    if not bpy.app.background:
        raise RuntimeError("Use a background Blender process: this CLI loads two files and must not replace an interactive unsaved scene")
    paths = [path.resolve() for path in (args.candidate, args.original)]
    output = args.output.resolve()
    if output in paths or output.suffix.lower() != ".json":
        raise ValueError("Output must be a separate JSON file")
    for path in paths:
        if not path.is_file():
            raise FileNotFoundError(path)
    if len(set(args.clips)) != len(args.clips):
        raise ValueError("Do not repeat clips")
    started = time.perf_counter()
    bpy.ops.wm.open_mainfile(filepath=str(paths[0]), load_ui=False)
    candidate = collect_current(args.clips)
    bpy.ops.wm.open_mainfile(filepath=str(paths[1]), load_ui=False)
    original = collect_current(args.clips)
    report = compare_caches(original, candidate, args.top)
    report["elapsed_seconds"] = time.perf_counter() - started
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    for clip, entry in report["clips"].items():
        peak = entry["largest_vertex_events"][0]
        print("REGALIA_TRAJECTORY", clip, "largest_pair", peak["frame_from"], peak["frame_to"],
              "vertex", peak["vertex_id"], "delta_m", peak["correction_delta_m"],
              "wrap", entry["wrap_vs_other_transitions_p95"]["max_m"], flush=True)
    print("REGALIA_TRAJECTORY_REPORT", str(output), flush=True)
    return report


if __name__ == "__main__":
    main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
