"""Read-only NumPy diagnostics for the graduate sleeve world-space caches.

Run after solving any clips, for example::

    python tools/audit_sleeve_motion.py --clip walk run jump

The arrays are measured in metres. This audit distinguishes deformation from
rigid movement, quantifies filtering/contact corrections, and reports the loop
join as an ordinary last-to-first interval: these caches do not contain a
duplicated endpoint. Metrics are diagnostics, not a visual-quality verdict or
a substitute for collision review. No Blender process or asset edit is used.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


ROOT = Path(__file__).resolve().parents[1]
ANIMATION = ROOT / "art" / "Graduate" / "animation"


def stats(values):
    values = np.asarray(values, dtype=np.float64).ravel()
    if not values.size:
        return {"count": 0}
    if not np.isfinite(values).all():
        raise ValueError("Non-finite diagnostic values")
    return {
        "count": int(values.size), "min": float(values.min()),
        "mean": float(values.mean()), "median": float(np.median(values)),
        "p95": float(np.percentile(values, 95)), "max": float(values.max()),
        "rms": float(np.sqrt(np.mean(values * values))),
        "std": float(values.std()),
    }


def fit_rigid(source, target):
    """Proper Kabsch rotation in row-vector convention; scale is not fitted."""
    source_center = source.mean(axis=0)
    target_center = target.mean(axis=0)
    u, _, vt = np.linalg.svd((source - source_center).T @ (target - target_center))
    determinant_fix = np.eye(3)
    determinant_fix[2, 2] = np.linalg.det(u @ vt)
    rotation = u @ determinant_fix @ vt
    aligned = (source - source_center) @ rotation + target_center
    return aligned, rotation


def point_departure(candidate, inputs, region):
    distances = np.linalg.norm(candidate[:, region] - inputs[:, region], axis=-1)
    return {
        "distance_m": stats(distances),
        "per_frame_rms_m": np.sqrt(np.mean(distances * distances, axis=1)).tolist(),
        "per_frame_max_m": distances.max(axis=1).tolist(),
    }


def cuff_shape(candidate, inputs, selection):
    """Measure each sleeve separately so arm rotations cannot mimic draping."""
    candidate = candidate[:, selection]
    inputs = inputs[:, selection]
    first = candidate[0]
    _, _, axes = np.linalg.svd(first - first.mean(axis=0), full_matrices=False)
    frame_rows = []
    input_residuals, temporal_residuals, extents = [], [], []
    for frame, (reference, points) in enumerate(zip(inputs, candidate), start=1):
        aligned_input, _ = fit_rigid(reference, points)
        from_input = np.linalg.norm(points - aligned_input, axis=1)
        aligned_first, rotation = fit_rigid(first, points)
        from_first = np.linalg.norm(points - aligned_first, axis=1)
        # Express current points in the first frame's fitted rigid coordinates.
        local = (points - points.mean(axis=0)) @ rotation.T
        extent = np.ptp(local @ axes.T, axis=0)
        input_residuals.extend(from_input)
        temporal_residuals.extend(from_first)
        extents.append(extent)
        frame_rows.append({
            "frame": frame,
            "nonrigid_residual_from_same_frame_input_rms_m": float(np.sqrt(np.mean(from_input ** 2))),
            "nonrigid_residual_from_same_frame_input_max_m": float(from_input.max()),
            "nonrigid_change_from_first_frame_rms_m": float(np.sqrt(np.mean(from_first ** 2))),
            "nonrigid_change_from_first_frame_max_m": float(from_first.max()),
            "rigid_aligned_principal_axis_extents_m": extent.tolist(),
        })
    extents = np.asarray(extents)
    return {
        "vertex_count": int(len(first)),
        "fit": "Independent proper rotation and translation, no scaling; one fit per sleeve per frame",
        "nonrigid_residual_from_same_frame_input_m": stats(input_residuals),
        "nonrigid_change_from_first_frame_m": stats(temporal_residuals),
        "principal_axis_extent_ranges_m": np.ptp(extents, axis=0).tolist(),
        "principal_axis_extent_min_m": extents.min(axis=0).tolist(),
        "principal_axis_extent_max_m": extents.max(axis=0).tolist(),
        "per_frame": frame_rows,
    }


def mesh_measures(points, triangles, edges):
    edge_lengths = np.linalg.norm(points[:, edges[:, 1]] - points[:, edges[:, 0]], axis=-1)
    corners = points[:, triangles]
    area = np.linalg.norm(np.cross(corners[:, :, 1] - corners[:, :, 0],
                                   corners[:, :, 2] - corners[:, :, 0]), axis=-1) * 0.5
    return edge_lengths, area


def mesh_distortion(candidate, inputs, triangles, pins=None,
                    reference="Same frame of rigid skinned inputs, before cloth simulation"):
    edges = np.unique(np.sort(triangles[:, [[0, 1], [1, 2], [2, 0]]].reshape(-1, 2), axis=1), axis=0)
    lengths, areas = mesh_measures(candidate, triangles, edges)
    input_lengths, input_areas = mesh_measures(inputs, triangles, edges)
    # These cutoffs only exclude a zero/ill-conditioned denominator, not cloth.
    edge_valid = input_lengths > 1e-10
    area_valid = input_areas > 1e-14
    edge_ratio = np.divide(lengths, input_lengths, out=np.full_like(lengths, np.nan), where=edge_valid)
    area_ratio = np.divide(areas, input_areas, out=np.full_like(areas, np.nan), where=area_valid)
    per_frame = []
    for f in range(len(candidate)):
        valid_edge_ratio = edge_ratio[f, edge_valid[f]]
        valid_area_ratio = area_ratio[f, area_valid[f]]
        per_frame.append({
            "frame": f + 1,
            "edge_length_ratio": stats(valid_edge_ratio),
            "triangle_area_ratio": stats(valid_area_ratio),
            "total_area_ratio": float(areas[f].sum() / input_areas[f].sum()),
            "triangle_counts_below_input_area_fraction": {
                str(threshold): int(np.count_nonzero(valid_area_ratio < threshold))
                for threshold in (0.5, 0.1, 0.01)
            },
        })
    max_edge_flat = int(np.nanargmax(edge_ratio))
    edge_frame, edge_index = np.unravel_index(max_edge_flat, edge_ratio.shape)
    min_area_flat = int(np.nanargmin(area_ratio))
    area_frame, area_index = np.unravel_index(min_area_flat, area_ratio.shape)
    region_ratios = {}
    if pins is not None:
        free_edges = np.all(pins[edges] == 0, axis=1)
        for name, region in (("both_vertices_unpinned", free_edges),
                             ("touches_pin_transition_or_fixed_seam", ~free_edges)):
            region_ratios[name] = stats(edge_ratio[:, region][edge_valid[:, region]])
    return {
        "unique_edge_count": int(len(edges)), "triangle_count": int(len(triangles)),
        "reference": reference,
        "area_fraction_bins_are_descriptive_not_pass_fail_thresholds": True,
        "excluded_input_edges_near_zero": int(np.count_nonzero(~edge_valid)),
        "excluded_input_triangles_near_zero": int(np.count_nonzero(~area_valid)),
        "edge_length_ratio": stats(edge_ratio[edge_valid]),
        "edge_length_ratio_by_attachment": region_ratios,
        "edge_fraction_above_reference_extension": {
            str(extension): float(np.mean(edge_ratio[edge_valid] > 1 + extension))
            for extension in (0.05, 0.1, 0.2, 0.5)
        },
        "triangle_area_ratio": stats(area_ratio[area_valid]),
        "largest_edge_stretch": {
            "frame": int(edge_frame + 1), "vertices": edges[edge_index].tolist(),
            "length_ratio": float(edge_ratio[edge_frame, edge_index]),
        },
        "smallest_triangle_area_fraction": {
            "frame": int(area_frame + 1), "vertices": triangles[area_index].tolist(),
            "area_ratio": float(area_ratio[area_frame, area_index]),
        },
        "per_frame": per_frame,
    }


def reconstructed_cutting_rest(offsets):
    """Reproduce original builder geometry when an older NPZ lacks `rest`.

    This is a documented source reconstruction, not a Blender scene read.
    A bounds check against the original sleeve inspection guards against
    silently applying the wrong builder dimensions or rig to another asset.
    """
    inspection_path = ROOT / "tools" / "sleeves-inspection.json"
    if not inspection_path.exists() or list(np.diff(offsets)) != [545, 545]:
        return None, {"available": False, "reason": "NPZ has no rest and source reconstruction is unavailable"}
    inspected = json.loads(inspection_path.read_text(encoding="utf-8"))[0]
    bones = inspected["bones"]
    all_rest = []
    maximum_bounds_error = 0.0
    for side, sign in (("L", 1), ("R", -1)):
        upper = bones[f"UpperArm.{side}"]
        lower = bones[f"LowerArm.{side}"]
        head, tail = np.asarray(upper["head"]), np.asarray(lower["tail"])
        shoulder, elbow, wrist = abs(head[0]), abs(lower["head"][0]), abs(tail[0])
        rings = ((shoulder - .05, .265, .265), (shoulder + .13, .28, .28),
                 (elbow - .16, .235, .26), (elbow + .10, .25, .30),
                 (wrist - .23, .285, .34), (wrist - .08, .30, .37),
                 (wrist - .055, .30, .37))
        original = []
        for x, radius_y, radius_z in rings:
            t = np.clip((x - shoulder) / (wrist - shoulder), 0, 1)
            center = head * (1 - t) + tail * t
            for j in range(16):
                angle = j * 2 * np.pi / 16
                original.append((sign * x, center[1] + radius_y * np.cos(angle),
                                 center[2] + radius_z * np.sin(angle) - .035))
        original.append((sign * (shoulder - .19), head[1], head[2]))
        original = np.asarray(original)
        observed = next(s for s in inspected["sleeves"] if s["role"] == f"02 | Bell sleeve {side}")
        bounds_error = float(np.max(np.abs(np.array([original.min(axis=0), original.max(axis=0)]) - observed["bounds"])))
        maximum_bounds_error = max(maximum_bounds_error, bounds_error)
        if bounds_error > 1e-5:
            return None, {"available": False, "reason": "Reconstructed original sleeve bounds do not match inspection",
                          "max_bounds_error_model_units": bounds_error}
        for r, t in [(r, k / n) for r, n in enumerate((2, 4, 3, 4, 2, 1)) for k in range(n)] + [(5, 1.0)]:
            for j in range(32):
                a, u = j // 2, (j % 2) / 2
                ids = (r * 16 + a, r * 16 + (a + 1) % 16,
                       (r + 1) * 16 + a, (r + 1) * 16 + (a + 1) % 16)
                weights = np.array(((1 - t) * (1 - u), (1 - t) * u,
                                    t * (1 - u), t * u))
                all_rest.append(np.sum(original[list(ids)] * weights[:, None], axis=0))
        all_rest.append(original[-1])
    return np.asarray(all_rest) * (1.75 / 4.8), {
        "available": True,
        "method": "Reconstructed original unstrained cutting geometry from build_graduate.py sleeve dimensions, inspected rest bones, and simulate_sleeve_cloth.py subdivision",
        "inspection_source": str(inspection_path),
        "max_original_bounds_error_model_units": maximum_bounds_error,
        "caveat": "Older NPZ does not contain the solver rest array; this reconstructs source geometry and may differ by Blender float rounding",
    }


def loop_join(points, fps):
    """Compare the wrap interval and adjacent velocities with internal ones."""
    internal_steps = np.diff(points, axis=0)
    wrap_step = points[0] - points[-1]
    internal_lengths = np.linalg.norm(internal_steps, axis=-1)
    wrap_lengths = np.linalg.norm(wrap_step, axis=-1)
    internal_velocity_changes = np.diff(internal_steps, axis=0) * fps
    before_wrap_velocity_change = (wrap_step - internal_steps[-1]) * fps
    after_wrap_velocity_change = (internal_steps[0] - wrap_step) * fps
    internal_rms = float(np.sqrt(np.mean(internal_lengths ** 2)))
    wrap_rms = float(np.sqrt(np.mean(wrap_lengths ** 2)))
    return {
        "sampling": "Period samples exclude a duplicated endpoint; first and last positions should not be forced equal",
        "internal_interval_displacement_m": stats(internal_lengths),
        "wrap_interval_displacement_m": stats(wrap_lengths),
        "wrap_to_internal_rms_displacement_ratio": wrap_rms / internal_rms if internal_rms else None,
        "internal_interval_speed_m_per_s": stats(internal_lengths * fps),
        "wrap_interval_speed_m_per_s": stats(wrap_lengths * fps),
        "internal_adjacent_velocity_difference_m_per_s": stats(np.linalg.norm(internal_velocity_changes, axis=-1)),
        "velocity_difference_entering_wrap_m_per_s": stats(np.linalg.norm(before_wrap_velocity_change, axis=-1)),
        "velocity_difference_leaving_wrap_m_per_s": stats(np.linalg.norm(after_wrap_velocity_change, axis=-1)),
        "per_frame_interval_rms_displacement_m": np.sqrt(np.mean(internal_lengths ** 2, axis=1)).tolist() + [wrap_rms],
    }


def load_arrays(path):
    required = ("raw", "physical", "inputs", "pins", "cuffs", "offsets", "cloth_triangles")
    with np.load(path, allow_pickle=False) as archive:
        missing = set(required) - set(archive.files)
        if missing:
            raise ValueError(f"{path.name}: missing arrays: {sorted(missing)}")
        data = {name: archive[name] for name in required}
        if "rest" in archive.files:
            data["rest"] = archive["rest"]
    shape = data["inputs"].shape
    if len(shape) != 3 or shape[2] != 3 or shape[0] < 3:
        raise ValueError(f"{path.name}: expected at least three F x V x 3 frames")
    for name in ("raw", "physical", "inputs"):
        if data[name].shape != shape or not np.isfinite(data[name]).all():
            raise ValueError(f"{path.name}: invalid {name} geometry")
        data[name] = data[name].astype(np.float64)
    for name in ("pins", "cuffs"):
        if data[name].shape != (shape[1],) or not np.isfinite(data[name]).all():
            raise ValueError(f"{path.name}: invalid {name}")
    offsets = data["offsets"]
    if offsets.ndim != 1 or len(offsets) < 2 or offsets[0] != 0 or offsets[-1] != shape[1] or np.any(np.diff(offsets) <= 0):
        raise ValueError(f"{path.name}: invalid sleeve offsets")
    if offsets.dtype.kind not in "iu":
        raise ValueError(f"{path.name}: offsets must be integer vertex indices")
    triangles = data["cloth_triangles"]
    if triangles.ndim != 2 or triangles.shape[1] != 3 or not len(triangles) or triangles.dtype.kind not in "iu" or triangles.min() < 0 or triangles.max() >= shape[1]:
        raise ValueError(f"{path.name}: invalid cloth triangles")
    data["cuffs"] = data["cuffs"].astype(bool)
    if "rest" in data and (data["rest"].shape != shape[1:] or not np.isfinite(data["rest"]).all()):
        raise ValueError(f"{path.name}: rest must be finite V x 3 geometry")
    return data


def audit(clip, fps):
    path = ANIMATION / f"{clip}_sleeve_cloth.npz"
    data = load_arrays(path)
    inputs, raw, physical = (data[name] for name in ("inputs", "raw", "physical"))
    pins, cuffs, offsets, triangles = (data[name] for name in ("pins", "cuffs", "offsets", "cloth_triangles"))
    regions = {
        "all_vertices": np.ones(len(pins), dtype=bool),
        "fully_pinned_seam": pins >= 0.999,
        "partially_pinned_transition": (pins > 0) & (pins < 0.999),
        "unpinned_fabric": pins == 0,
        "cuffs": cuffs,
    }
    regions = {name: mask for name, mask in regions.items() if np.any(mask)}
    sleeves = {}
    for i, (start, end) in enumerate(zip(offsets[:-1], offsets[1:])):
        selection = np.arange(start, end)[cuffs[start:end]]
        if len(selection) < 3:
            raise ValueError(f"{clip}: sleeve {i} has fewer than three cuff points")
        sleeves[f"sleeve_{i + 1}"] = {
            "vertex_range_start_inclusive_end_exclusive": [int(start), int(end)],
            "raw_cuff_shape": cuff_shape(raw, inputs, selection),
            "physical_cuff_shape": cuff_shape(physical, inputs, selection),
        }
    report = {
        "source": str(path), "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "frames": int(len(inputs)), "vertices": int(inputs.shape[1]), "fps": fps,
        "looping": clip in ("walk", "run"), "length_unit": "metres",
        "cuff_pin_weight": stats(pins[cuffs]),
        "region_vertex_counts": {name: int(np.count_nonzero(mask)) for name, mask in regions.items()},
        "raw_departure_from_rigid_inputs": {name: point_departure(raw, inputs, mask) for name, mask in regions.items()},
        "physical_departure_from_rigid_inputs": {name: point_departure(physical, inputs, mask) for name, mask in regions.items()},
        "postprocess_change_from_raw_solver": {name: point_departure(physical, raw, mask) for name, mask in regions.items()},
        "sleeves": sleeves,
        "raw_mesh_distortion": mesh_distortion(raw, inputs, triangles, pins),
        "physical_mesh_distortion": mesh_distortion(physical, inputs, triangles, pins),
    }
    if "rest" in data:
        rest = data["rest"]
        rest_source = {"available": True, "method": "NPZ rest array written by solver"}
    else:
        rest, rest_source = reconstructed_cutting_rest(offsets)
    report["unstrained_cutting_geometry_source"] = rest_source
    if rest is not None:
        reference = np.broadcast_to(rest, inputs.shape)
        report["distortion_from_unstrained_cutting_geometry"] = {
            name: mesh_distortion(points, reference, triangles, pins,
                                  reference="Static unstrained source sleeve cutting geometry; includes pinned-seam strain from armature skinning")
            for name, points in (("rigid_inputs", inputs), ("raw", raw), ("physical", physical))
        }
    if report["looping"]:
        report["loop_join"] = {
            name: {region: loop_join(points[:, mask], fps) for region, mask in regions.items()}
            for name, points in (("rigid_inputs", inputs), ("raw", raw), ("physical", physical))
        }
    else:
        report["loop_join"] = None
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--clip", nargs="+", choices=("walk", "run", "jump"), default=["walk", "run", "jump"])
    parser.add_argument("--fps", type=float, default=30.0)
    parser.add_argument("--output", default="sleeve-motion-audit.json", help="Report filename within art/Graduate/animation")
    args = parser.parse_args()
    if not np.isfinite(args.fps) or args.fps <= 0:
        parser.error("--fps must be positive and finite")
    if Path(args.output).name != args.output or not args.output.endswith(".json"):
        parser.error("--output must be a .json filename, not a path")
    report = {
        "format_version": 2,
        "status": "Diagnostic measurements; requires visual motion and collision review",
        "interpretation": [
            "World-space departure from skinned inputs includes both rigid repositioning and fabric deformation.",
            "Kabsch residual removes cuff translation and rotation; a nonzero result demonstrates nonrigid shape change.",
            "A static drape can have nonzero input residual; first-frame residual additionally measures shape changes over time.",
            "Edge and area ratios compare the same frame to skinned inputs, not to material rest lengths or stress.",
            "Loop boundary speed need not be zero; compare its interval and velocity changes to normal internal intervals.",
            "Jump is a one-shot and is intentionally not judged as a loop.",
            "No scalar threshold here proves realistic fabric; inspect exaggerated stretch, collapse, and boundary spikes.",
        ],
        "clips": {clip: audit(clip, args.fps) for clip in dict.fromkeys(args.clip)},
    }
    output = ANIMATION / args.output
    temporary = output.with_suffix(".tmp")
    temporary.write_text(json.dumps(report, indent=2, allow_nan=False), encoding="utf-8")
    temporary.replace(output)
    print(f"SLEEVE_MOTION_AUDIT {output}")
    for clip, value in report["clips"].items():
        cuff = value["physical_departure_from_rigid_inputs"]["cuffs"]["distance_m"]
        nonrigid = [s["physical_cuff_shape"]["nonrigid_residual_from_same_frame_input_m"]["rms"] for s in value["sleeves"].values()]
        print(json.dumps({"clip": clip, "cuff_departure_rms_m": cuff["rms"],
                          "cuff_nonrigid_rms_m_per_sleeve": nonrigid,
                          "physical_edge_ratio_max": value["physical_mesh_distortion"]["edge_length_ratio"]["max"],
                          "physical_triangle_area_ratio_min": value["physical_mesh_distortion"]["triangle_area_ratio"]["min"]}))


if __name__ == "__main__":
    main()
