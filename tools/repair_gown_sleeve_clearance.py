"""Bounded gown-only clearance from the existing, unchanged sleeve surfaces.

Import in the already-open Blender process; importing performs no work::

    from repair_gown_sleeve_clearance import repair_clip
    probe = repair_clip('idle', report_path='.../probe.json',
                        frames=[1, 51, 91], bake=False)
    result = repair_clip('idle', report_path='.../repair.json', bake=True)

Only the gown's morph cache is replaced when bake=True. No skeleton, sleeve,
material, topology, frame range or FPS is changed; no blend is saved. The
caller must subsequently reattach decorative layers and audit/render the
complete result. This is a bounded geometric repair, not a cloth simulation.
"""

from __future__ import annotations

from collections import Counter
import json
from pathlib import Path
import sys
import time

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cloth_surface_helpers import inside
from simulate_portal_cloth import SCALE, SkinBinding, bake_keys, evaluated_points
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import crossing_segment, segment_triangle, visible_surfaces

PREFIXES = {"idle": "04_IDLE", "walk": "01_WALK", "run": "02_RUN", "jump": "03_JUMP", "jumpdown": "03_JUMP"}
GOWN = "01 | Pleated bachelor gown"
SLEEVES = ("02 | Bell sleeve L", "02 | Bell sleeve R")


def _tree(points, triangles):
    return BVHTree.FromPolygons([Vector(p) for p in points], triangles, all_triangles=True)


def _normals(points, triangles):
    values = []
    for ids in triangles:
        a, b, c = [Vector(points[i]) for i in ids]
        normal = (b - a).cross(c - a)
        values.append(normal.normalized() if normal.length_squared > 1e-20 else None)
    return values


class SleeveProxy:
    """Capped volume for containment; uncapped original faces for projection."""

    def __init__(self, points, polygons, direction, gap, pinned_faces=()):
        self.direction = Vector(direction).normalized()
        tangent = Vector((0, 0, 1)).cross(self.direction).normalized()
        self.directions = [self.direction] + [(self.direction + tangent * amount).normalized()
                                              for amount in (-.75, .75, -1.5, 1.5)]
        self.gap = gap
        self.minimum, self.maximum = np.min(points, axis=0), np.max(points, axis=0)
        bm = bmesh.new()
        try:
            for p in points:
                bm.verts.new(p)
            bm.verts.ensure_lookup_table()
            source = bm.faces.layers.int.new("original_sleeve_face")
            for index, polygon in enumerate(polygons):
                face = bm.faces.new([bm.verts[i] for i in polygon])
                face[source] = index + 1
            boundary = [e for e in bm.edges if e.is_boundary]
            if boundary:
                result = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
                for face in result.get("faces", []):
                    face[source] = 0
            if any(e.is_boundary or not e.is_manifold for e in bm.edges):
                raise RuntimeError("Temporary sleeve volume is not closed/manifold")
            bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
            if bm.calc_volume(signed=True) < 0:
                bmesh.ops.reverse_faces(bm, faces=list(bm.faces))
            bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="FIXED", ngon_method="EAR_CLIP")
            bm.verts.index_update()
            self.points = [v.co.copy() for v in bm.verts]
            all_triangles = [tuple(v.index for v in f.verts) for f in bm.faces]
            self.triangles = [tuple(v.index for v in f.verts) for f in bm.faces if f[source] > 0]
            self.pinned = [f[source] - 1 in pinned_faces for f in bm.faces if f[source] > 0]
            self.temporary_cap_triangles = len(all_triangles) - len(self.triangles)
        finally:
            bm.free()
        self.volume = _tree(self.points, all_triangles)
        self.surface = _tree(self.points, self.triangles)
        self.normals = _normals(self.points, self.triangles)

    def correction(self, point, force_free=False):
        """Return (delta or None, inside, requested_distance, region) for contact.

        Inward means toward the torso in its current lateral plane. Cap faces
        never supply hit locations or normals; an exit through a cuff cap is
        explicitly unprojectable and remains in the report.
        """
        p = Vector(point)
        if any(p[i] < self.minimum[i] - self.gap or p[i] > self.maximum[i] + self.gap for i in range(3)):
            return None
        hit, normal, triangle, distance = self.surface.find_nearest(p)
        if hit is None:
            return None
        in_bounds = all(self.minimum[i] <= p[i] <= self.maximum[i] for i in range(3))
        contained = bool(in_bounds and inside(self.volume, p))
        if not contained and distance >= self.gap - 1e-6:
            return None
        if self.pinned[triangle] and not force_free:
            return (None, contained, None, "pinned_attachment")
        candidates = []
        if contained:
            # Pure sideways projection can unnecessarily traverse 8cm of a
            # diagonal sleeve. Also test a bounded forward/backward cone;
            # every direction retains >=55% torso-directed lateral motion.
            for direction in self.directions:
                exit_hit, exit_normal, exit_triangle, travel = self.surface.ray_cast(p + direction * 1e-7, direction, .5)
                if exit_hit is None or self.pinned[exit_triangle] or exit_normal.dot(direction) <= .05:
                    continue
                required = travel + self.gap / max(exit_normal.dot(direction), .1) + 1e-6
                candidates.append(np.asarray(direction) * required)
            if normal.dot(self.direction) >= .55:
                candidates.append(np.asarray(hit + normal * self.gap - p))
        else:
            for direction in self.directions:
                alignment = normal.dot(direction)
                if alignment > .05:
                    required = max(0.0, self.gap - distance) / max(alignment, .1) + 1e-6
                    candidates.append(np.asarray(direction) * required)
        if not candidates:
            return (None, contained, None, "independent")
        delta = min(candidates, key=lambda value: float(np.dot(value, value)))
        return (delta, contained, float(np.linalg.norm(delta)), "independent")


class Tessellation:
    def __init__(self, points, polygons):
        # Match the candidate's Regalia stable cloth triangles modifier.
        # Dynamic calc_loop_triangles can switch quad diagonals during a
        # correction and falsely create/remove pairs in the acceptance test.
        bm = bmesh.new()
        try:
            for point in points:
                bm.verts.new(point)
            bm.verts.ensure_lookup_table()
            source = bm.faces.layers.int.new("gown_source_polygon")
            for index, polygon in enumerate(polygons):
                face = bm.faces.new([bm.verts[i] for i in polygon])
                face[source] = index
            bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="FIXED", ngon_method="EAR_CLIP")
            bm.verts.index_update()
            self.triangles = [tuple(v.index for v in f.verts) for f in bm.faces]
            self.parents = [f[source] for f in bm.faces]
        finally:
            bm.free()

    def evaluate(self, points):
        return self.triangles, self.parents

    def close(self):
        pass


def _constraint_vertex_regions(polygons, parents, seam_faces):
    """Separate seam-only vertices from shared vertices owned by a free face."""
    seam_owned, free_owned = set(), set()
    for ids, parent in zip(polygons, parents):
        (seam_owned if parent in seam_faces else free_owned).update(ids)
    return seam_owned - free_owned, seam_owned & free_owned


def _features(vertex_count, triangles, parents, seam_faces, frozen):
    seam_only, _ = _constraint_vertex_regions(triangles, parents, seam_faces)
    for i in range(vertex_count):
        if not frozen[i] and i not in seam_only:
            yield (i,), (1.0,), "vertex"
    edges = set()
    for ids, parent in zip(triangles, parents):
        if parent in seam_faces or all(frozen[i] for i in ids):
            continue
        yield ids, (1 / 3,) * 3, "triangle_center"
        for a, b in zip(ids, ids[1:] + ids[:1]):
            edge = (min(a, b), max(a, b))
            if edge not in edges and not all(frozen[i] for i in edge):
                edges.add(edge)
                yield edge, (.5, .5), "edge_midpoint"


def _requests(points, triangles, parents, seam_faces, frozen, proxies):
    stats = Counter()
    requests = []
    maximum_request = 0.0
    for ids, weights, kind in _features(len(points), triangles, parents, seam_faces, frozen):
        point = sum((points[i] * weight for i, weight in zip(ids, weights)), np.zeros(3))
        for proxy in proxies:
            answer = proxy.correction(point)
            if answer is None:
                continue
            delta, contained, required, region = answer
            if region == "pinned_attachment":
                stats["pinned_attachment_samples"] += 1
                continue
            stats[kind + ("_inside" if contained else "_clearance")] += 1
            if delta is None:
                stats["unprojectable_samples"] += 1
            else:
                requests.append((ids, weights, delta))
                maximum_request = max(maximum_request, required)
    # Narrow crossed slivers can miss all vertices, edge midpoints and face
    # centres. Feed exact intersection midpoints back as barycentric contacts.
    tree = _tree(points, triangles)
    normals = _normals(points, triangles)
    for proxy in proxies:
        for a, b in tree.overlap(proxy.surface):
            if parents[a] in seam_faces or proxy.pinned[b]:
                continue
            ids = triangles[a]
            first = [Vector(points[i]) for i in ids]
            second = [Vector(proxy.points[i]) for i in proxy.triangles[b]]
            extent, _ = crossing_segment(first, normals[a], second, proxy.normals[b], 1e-7)
            if extent is None:
                continue
            stats["exact_intersection"] += 1
            if all(frozen[i] for i in ids):
                stats["frozen_intersection_samples"] += 1
                continue
            hits = []
            for tri, other, normal in ((first, second, proxy.normals[b]), (second, first, normals[a])):
                for edge in range(3):
                    hit = segment_triangle(tri[edge], tri[(edge + 1) % 3], other, normal, 1e-7)
                    if hit is not None:
                        hits.append(hit)
            if not hits:
                stats["unprojectable_samples"] += 1
                continue
            point = sum(hits, Vector()) / len(hits)
            v0, v1, v2 = first[1] - first[0], first[2] - first[0], point - first[0]
            d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
            determinant = d00 * d11 - d01 * d01
            if abs(determinant) < 1e-20:
                continue
            wb = (d11 * v2.dot(v0) - d01 * v2.dot(v1)) / determinant
            wc = (d00 * v2.dot(v1) - d01 * v2.dot(v0)) / determinant
            weights = np.clip([1 - wb - wc, wb, wc], 0, 1)
            weights /= weights.sum()
            # A tiny inward offset avoids an ambiguous parity test directly
            # on the sleeve wall. Targets still come from original sleeve faces.
            inset = proxy.normals[b] * 2e-6
            answer = proxy.correction(point - inset, force_free=True)
            if answer is None or answer[0] is None:
                stats["unprojectable_samples"] += 1
                continue
            delta = answer[0] - np.asarray(inset)
            requests.append((ids, tuple(weights), delta))
            maximum_request = max(maximum_request, float(np.linalg.norm(delta)))
    diagnostics = {"unprojectable_samples", "pinned_attachment_samples", "frozen_intersection_samples"}
    return requests, {"counts": dict(stats), "violating_samples": sum(value for key, value in stats.items() if key not in diagnostics),
                      "pinned_attachment_samples": stats["pinned_attachment_samples"],
                      "frozen_intersection_samples": stats["frozen_intersection_samples"],
                      "unprojectable_samples": stats["unprojectable_samples"], "maximum_requested_projection_m": maximum_request}


def _crossings(points, triangles, parents, seam_faces, proxies, epsilon=1e-7, frozen=None):
    tree = _tree(points, triangles)
    normals = _normals(points, triangles)
    counts = Counter()
    maximum = 0.0
    for proxy in proxies:
        for a, b in tree.overlap(proxy.surface):
            extent, _ = crossing_segment([Vector(points[i]) for i in triangles[a]], normals[a],
                                         [Vector(proxy.points[i]) for i in proxy.triangles[b]], proxy.normals[b], epsilon)
            if extent is not None:
                region = ("sewn_region" if parents[a] in seam_faces else
                          "pinned_attachment" if proxy.pinned[b] else "free_region")
                counts[region] += 1
                if region == "free_region" and frozen is not None:
                    fixed_count = sum(bool(frozen[i]) for i in triangles[a])
                    counts["free_with_all_frozen_vertices" if fixed_count == 3 else
                           "free_with_some_frozen_vertices" if fixed_count else
                           "free_with_no_frozen_vertices"] += 1
                maximum = max(maximum, extent)
    pairs = {(min(a, b), max(a, b)) for a, b in tree.overlap(tree) if a != b}
    for a, b in pairs:
        if set(triangles[a]).intersection(triangles[b]):
            continue
        extent, _ = crossing_segment([Vector(points[i]) for i in triangles[a]], normals[a],
                                     [Vector(points[i]) for i in triangles[b]], normals[b], epsilon)
        if extent is not None:
            counts["gown_self"] += 1
    return {key: counts[key] for key in ("free_region", "sewn_region", "pinned_attachment", "gown_self")} | {
        "free_with_all_frozen_vertices": counts["free_with_all_frozen_vertices"],
        "free_with_some_frozen_vertices": counts["free_with_some_frozen_vertices"],
        "free_with_no_frozen_vertices": counts["free_with_no_frozen_vertices"],
        "raw_sleeve_crossings": counts["free_region"] + counts["sewn_region"] + counts["pinned_attachment"],
        "maximum_segment_m": maximum}


def _samples_clear(stats, tolerance):
    counts = stats["counts"]
    return (not any(value for key, value in counts.items() if key.endswith("_inside"))
            and not counts.get("exact_intersection", 0)
            and not stats["unprojectable_samples"]
            and stats["maximum_requested_projection_m"] <= tolerance)


def _bounded(points, original, frozen, maximum):
    delta = points - original
    length = np.linalg.norm(delta, axis=1)
    delta *= np.minimum(1.0, maximum / np.maximum(length, 1e-12))[:, None]
    delta[frozen] = 0.0
    return original + delta


def _project(original, initial, proxies, polygons, seam_faces, frozen, neighbors, iterations,
             maximum_step, maximum_displacement, smooth_strength, check_every=2,
             clearance_tolerance=.00005):
    points = _bounded(initial.copy(), original, frozen, maximum_displacement)
    tess = Tessellation(original, polygons)
    largest_request = 0.0
    completed = 0
    try:
        triangles, parents = tess.evaluate(original)
        _, before_samples = _requests(original, triangles, parents, seam_faces, frozen, proxies)
        before = _crossings(original, triangles, parents, seam_faces, proxies, frozen=frozen)
        best_points, best_after, best_samples = original.copy(), before.copy(), before_samples.copy()
        best_score = (before["free_region"], before_samples["violating_samples"],
                      before_samples["maximum_requested_projection_m"])
        best_iteration = 0
        best_improved = False
        diagnostics = []

        def consider(candidate, iteration):
            nonlocal best_points, best_after, best_samples, best_score, best_iteration, best_improved
            ids, parents_now = tess.evaluate(candidate)
            _, sampling = _requests(candidate, ids, parents_now, seam_faces, frozen, proxies)
            crossing = _crossings(candidate, ids, parents_now, seam_faces, proxies, frozen=frozen)
            score = (crossing["free_region"], sampling["violating_samples"], sampling["maximum_requested_projection_m"])
            safe = crossing["gown_self"] <= before["gown_self"] and crossing["free_region"] <= before["free_region"]
            diagnostics.append({"iteration": iteration, "crossings": crossing,
                                "violating_samples": sampling["violating_samples"],
                                "maximum_displacement_m": float(np.linalg.norm(candidate - original, axis=1).max(initial=0)),
                                "safe_against_original": safe})
            if safe and score < best_score:
                best_points, best_after, best_samples = candidate.copy(), crossing, sampling
                best_score, best_iteration = score, iteration
                best_improved = True
            return crossing, sampling, safe

        if np.any(points != original):
            consider(points, 0)
        for iteration in range(iterations):
            triangles, parents = tess.evaluate(points)
            requests, sample_stats = _requests(points, triangles, parents, seam_faces, frozen, proxies)
            largest_request = max(largest_request, sample_stats["maximum_requested_projection_m"])
            if not requests or _samples_clear(sample_stats, clearance_tolerance):
                break
            sums, counts = np.zeros_like(points), np.zeros(len(points))
            active = set()
            for ids, weights, delta in requests:
                free = [(i, w) for i, w in zip(ids, weights) if not frozen[i]]
                denominator = sum(w * w for _, w in free)
                for i, weight in free:
                    proposal = delta * weight / max(denominator, 1e-12)
                    length = np.linalg.norm(proposal)
                    proposal *= min(1.0, maximum_step / max(length, 1e-12))
                    sums[i] += proposal
                    counts[i] += 1
                    active.add(i)
            touched = counts > 0
            points[touched] += sums[touched] / counts[touched, None]
            points = _bounded(points, original, frozen, maximum_displacement)
            # Smooth correction vectors only, so authored folds and gown
            # motion are retained. Spread over at most two contact-neighbor
            # rings; do not globally fair/shrink the garment.
            # Reserve the final quarter (at least two) for pure reprojection so a
            # final fairing pass cannot immediately undo the required gap.
            if iteration < max(0, iterations - max(2, iterations // 4)) and smooth_strength:
                patch = set(active)
                for _ in range(2):
                    patch.update(j for i in list(patch) for j in neighbors[i])
                correction = points - original
                previous = correction.copy()
                for i in patch:
                    if not frozen[i] and neighbors[i]:
                        correction[i] += smooth_strength * (previous[list(neighbors[i])].mean(axis=0) - previous[i])
                points = _bounded(original + correction, original, frozen, maximum_displacement)
            completed = iteration + 1
            # Keep usable intermediate improvements if a later projection
            # would fold a panel. Never disable the zero-new-self-crossing guard.
            if completed % check_every == 0 and completed != iterations:
                consider(points, completed)
        proposal_after, proposal_samples, proposal_safe = consider(points, completed)
        points, after, after_samples = best_points, best_after, best_samples
        rejected = not best_improved and not proposal_safe
        movement = np.linalg.norm(points - original, axis=1)
        return points, {
            "iterations": completed, "before": before, "after": after,
            "before_samples": before_samples, "after_samples": after_samples,
            "accepted_iteration": best_iteration,
            "last_proposal_crossings": proposal_after,
            "last_proposal_samples": proposal_samples,
            "last_proposal_rejected": not proposal_safe,
            "iteration_diagnostics": diagnostics,
            "rejected_due_to_crossing_regression": rejected,
            "maximum_requested_projection_m": largest_request,
            "maximum_displacement_m": float(movement.max(initial=0)),
            "rms_displacement_m": float(np.sqrt(np.mean(movement ** 2))),
            "moved_vertices": int(np.count_nonzero(movement > 1e-6)),
            "vertices_at_displacement_limit": int(np.count_nonzero(movement >= maximum_displacement - 1e-6)),
            "frozen_vertex_max_error_m": float(movement[frozen].max(initial=0)),
            "clearance_tolerance_m": clearance_tolerance,
            "clearance_within_tolerance": _samples_clear(after_samples, clearance_tolerance),
            "requires_more_than_limit_or_another_method": bool(after["free_region"] or not _samples_clear(after_samples, clearance_tolerance)),
        }
    finally:
        tess.close()


def _shell_radius(obj):
    scale = max(abs(value) for value in obj.matrix_world.to_scale()) * SCALE
    return sum(abs(m.thickness) * (1 + abs(m.offset)) * .5 * scale for m in obj.modifiers
               if m.type == "SOLIDIFY" and m.show_viewport)


def repair_clip(clip, report_path=None, *, frames=None, bake=True, iterations=12,
                clearance=.0025, maximum_step=.004, maximum_displacement=.025,
                shell_allowance=True, smooth_strength=.18, temporal_passes=0,
                temporal_reproject_iterations=5, seam_faces=None, warm_start=False,
                warm_start_iterations=10, check_every=2, clearance_tolerance=.00005,
                warm_smooth_strength=0.0, return_geometry=False,
                constraint_seam_faces=None):
    """Repair one scene in memory, or probe selected frames without baking.

    ``frames`` subsets require bake=False, because partial caches must never
    replace a complete clip. Full caches preserve original FPS and period;
    Walk/Run/Idle repeat their first pose at period+1, Jump holds its endpoints.
    ``temporal_passes`` optionally smooths correction vectors in time, followed
    by bounded per-frame reprojection. Frozen shoulder geometry stays exact.
    ``warm_start=True`` transports the previous frame's correction in the
    torso rotation basis. Later frames first use warm_start_iterations, with
    an automatic remaining-budget retry if they are still crossed. The first
    frame uses the full budget. check_every changes intermediate self audits;
    original and final geometry are always audited. No early exit tolerates a
    transverse intersection; clearance_tolerance applies only to the air gap.
    Warm passes default to pure projection because their seed is already
    spatially smoothed; this avoids repeatedly reducing the established gap.
    ``return_geometry=True`` adds in-memory ``_corrected_points`` world-space
    NumPy arrays and ``_frames`` to the returned report, after its final JSON
    write. With bake=False this supports bounded, selected-frame postpasses
    without modifying the asset or serializing the geometry in the report.
    ``seam_faces`` determines only the vertices held exactly fixed.
    ``constraint_seam_faces`` independently identifies documented sewn faces
    excluded from sleeve-clearance constraints; their raw crossings are still
    counted as sewn_region. Seam-only vertices supply no contact requests,
    while shared boundary vertices owned by any outside face remain eligible.
    None uses seam_faces for both masks, preserving existing call behavior.
    """
    prefix = PREFIXES.get(clip.lower(), clip)
    found = [s for s in bpy.data.scenes if s.name.startswith(prefix)]
    if len(found) != 1:
        raise ValueError(f"Expected one scene for {clip}, found {len(found)}")
    scene = found[0]
    if bake and frames is not None:
        raise ValueError("Subset probes require bake=False")
    if iterations < 0 or temporal_passes < 0 or temporal_reproject_iterations < 0:
        raise ValueError("Iteration counts must be nonnegative")
    if warm_start_iterations < 1 or check_every < 1 or not 0 <= clearance_tolerance <= .0001:
        raise ValueError("Warm budget/check interval positive; clearance tolerance between0 and0.1mm")
    if not (0 < clearance <= .02 and 0 < maximum_step <= maximum_displacement <= .12):
        raise ValueError("Use positive clearance <=20mm and step<=displacement<=120mm; default displacement remains25mm")
    if not 0 <= smooth_strength <= .5:
        raise ValueError("smooth_strength must be between 0 and .5")
    if not 0 <= warm_smooth_strength <= .5:
        raise ValueError("warm_smooth_strength must be between 0 and .5")
    loop = not prefix.startswith("03_JUMP")
    if loop and scene.frame_start != 1:
        raise ValueError("Current loop baker requires frame_start=1")
    selected = list(range(scene.frame_start, scene.frame_end + 1)) if frames is None else sorted(set(int(f) for f in frames))
    if not selected or any(f < scene.frame_start or f > scene.frame_end for f in selected):
        raise ValueError("Invalid frame selection")
    if temporal_passes and frames is not None:
        raise ValueError("Temporal smoothing requires contiguous full-clip frames")
    rig = next(o for o in scene.objects if o.type == "ARMATURE" and not o.get("preview_fx"))
    gown = next(o for o in scene.objects if o.get("graduate_role") == GOWN)
    sleeves = [next(o for o in scene.objects if o.get("graduate_role") == role) for role in SLEEVES]
    polygons = [tuple(p.vertices) for p in gown.data.polygons]
    protected = set(seam_faces) if seam_faces is not None else {
        p.index for p in gown.data.polygons if p.center.z > 3.05 and abs(p.center.x) > .34}
    if any(i < 0 or i >= len(polygons) for i in protected):
        raise ValueError("Invalid source seam-face index")
    constraint_seams = set(constraint_seam_faces) if constraint_seam_faces is not None else protected.copy()
    if any(i < 0 or i >= len(polygons) for i in constraint_seams):
        raise ValueError("Invalid constraint seam-face index")
    constraint_seam_only, constraint_boundary = _constraint_vertex_regions(
        polygons, range(len(polygons)), constraint_seams)
    frozen = np.zeros(len(gown.data.vertices), dtype=bool)
    for face in protected:
        frozen[list(polygons[face])] = True
    neighbors = [set() for _ in frozen]
    for ids in polygons:
        for a, b in zip(ids, ids[1:] + ids[:1]):
            neighbors[a].add(b)
            neighbors[b].add(a)
    sleeve_faces = [[tuple(p.vertices) for p in obj.data.polygons] for obj in sleeves]
    sleeve_pinned_faces = []
    for obj in sleeves:
        group = obj.vertex_groups.get("Sleeve shoulder seam only")
        if group is None:
            raise ValueError("Missing explicit sleeve shoulder seam group: " + obj.name)
        vertices = {v.index for v in obj.data.vertices
                    if any(g.group == group.index and g.weight > 0 for g in v.groups)}
        sleeve_pinned_faces.append({p.index for p in obj.data.polygons if any(v in vertices for v in p.vertices)})
    gap = [clearance + (_shell_radius(gown) + _shell_radius(obj) if shell_allowance else 0) for obj in sleeves]
    started = time.perf_counter()
    report = {
        "clip": clip, "scene": scene.name, "source_blend": bpy.data.filepath,
        "saved_blend": False, "baked": False, "complete": False,
        "method": "Gown-only torso-directed projection with closed sleeve containment and original sleeve surfaces",
        "surface": "evaluated midsurface; optional conservative Solidify thickness allowance",
        "clearance_m": clearance, "effective_midsurface_gap_m": gap,
        "maximum_displacement_m": maximum_displacement, "maximum_step_m": maximum_step,
        "source_sewn_faces": sorted(constraint_seams), "source_frozen_faces": sorted(protected),
        "protected_vertex_count": int(frozen.sum()),
        "constraint_seam_faces_explicit": constraint_seam_faces is not None,
        "constraint_seam_only_vertex_count": len(constraint_seam_only),
        "constraint_boundary_vertex_count": len(constraint_boundary),
        "sleeve_pinned_face_counts": [len(faces) for faces in sleeve_pinned_faces],
        "crossing_regions": "gown constraint-seam face first, then sleeve pinned attachment, then independent free region; all raw counts retained. source_frozen_faces controls attachment separately",
        "triangulation": "FIXED quad diagonals, EAR_CLIP ngons; matches Regalia stable cloth triangles",
        "projection_direction": "Shortest valid torso-directed ray in a forward/backward cone with >=55% lateral inward component",
        "fps": scene.render.fps / scene.render.fps_base, "loop": loop,
        "frame_range": [scene.frame_start, scene.frame_end], "temporal_passes": temporal_passes,
        "warm_start": warm_start, "warm_start_iterations": warm_start_iterations,
        "warm_smooth_strength": warm_smooth_strength,
        "intermediate_check_every": check_every, "clearance_tolerance_m": clearance_tolerance,
        "limitations": "Vertex/triangle/edge samples plus exact midsurface crossings. Render shells, body clearance, decorative layers, and subframes require final full-scene audit. No new cloth solve.",
        "frames": [],
    }
    output = Path(report_path).resolve() if report_path else None
    if output:
        output.parent.mkdir(parents=True, exist_ok=True)

    def write_report():
        report["elapsed_seconds"] = time.perf_counter() - started
        if output:
            output.write_text(json.dumps(report, indent=2), encoding="utf-8")

    cache, corrected = [], []
    previous_correction, previous_basis = None, None
    with visible_surfaces(scene, [gown, *sleeves], "simulation"):
        binding = SkinBinding(gown, rig)
        for frame in selected:
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            original = evaluated_points(gown)
            if len(original) != len(frozen):
                raise ValueError("Gown midsurface topology does not match source vertices")
            sleeve_points = [evaluated_points(obj) for obj in sleeves]
            torso = rig.pose.bones["Torso"]
            rotation = (rig.matrix_world.to_3x3() @ torso.matrix.to_3x3()
                        @ torso.bone.matrix_local.to_3x3().inverted()).to_quaternion().to_matrix()
            basis = np.asarray(rotation, dtype=np.float64)
            right = (rotation @ Vector((1, 0, 0))).normalized()
            directions = [-right, right]
            proxies = [SleeveProxy(points, faces, direction, margin, pinned)
                       for points, faces, direction, margin, pinned in zip(sleeve_points, sleeve_faces, directions, gap, sleeve_pinned_faces)]
            warmed = bool(warm_start and previous_correction is not None)
            seed = original.copy()
            if warmed:
                seed += previous_correction @ previous_basis @ basis.T
            budget = min(warm_start_iterations, iterations) if warmed else iterations
            frame_smoothing = warm_smooth_strength if warmed else smooth_strength
            points, item = _project(original, seed, proxies, polygons, constraint_seams, frozen, neighbors,
                                    budget, maximum_step, maximum_displacement, frame_smoothing,
                                    check_every, clearance_tolerance)
            item["warm_start_used"] = warmed
            item["warm_start_full_retry"] = False
            item["iterations_this_frame"] = item["iterations"]
            if warmed and item["requires_more_than_limit_or_another_method"] and iterations > budget:
                warm_result = item
                points, item = _project(original, points, proxies, polygons, constraint_seams, frozen, neighbors,
                                        iterations - budget, maximum_step, maximum_displacement, warm_smooth_strength,
                                        check_every, clearance_tolerance)
                item["warm_start_used"] = True
                item["warm_start_full_retry"] = True
                item["warm_attempt_after"] = warm_result["after"]
                item["iterations_this_frame"] = warm_result["iterations"] + item["iterations"]
            if warmed and item["after"]["free_region"]:
                # A previous pose can place this solve in a different fold
                # configuration. Retry the actual authored frame when the
                # warm solution cannot become disjoint without new self hits.
                warm_points,warm_item=points,item
                cold_points,cold_item=_project(original,original,proxies,polygons,constraint_seams,frozen,neighbors,
                    iterations,maximum_step,maximum_displacement,smooth_strength,check_every,clearance_tolerance)
                cold_score=(cold_item['after']['free_region'],cold_item['after_samples']['violating_samples'])
                warm_score=(warm_item['after']['free_region'],warm_item['after_samples']['violating_samples'])
                if cold_score<warm_score:points,item=cold_points,cold_item
                item['warm_start_used']=True
                item['warm_start_cold_retry']=True
                item['cold_retry_retained']=cold_score<warm_score
                item['warm_attempt_after']=warm_item['after']
                item['iterations_this_frame']=warm_item.get('iterations_this_frame',warm_item['iterations'])+cold_item['iterations']
            previous_correction, previous_basis = points - original, basis
            item["frame"] = frame
            item["temporary_cap_triangles"] = [p.temporary_cap_triangles for p in proxies]
            report["frames"].append(item)
            cache.append((original, sleeve_points, [tuple(d) for d in directions]))
            corrected.append(points)
            write_report()
            print("GOWN_SLEEVE_REPAIR_FRAME", scene.name, frame, item["before"], item["after"],
                  "max_m", item["maximum_displacement_m"], flush=True)
        if temporal_passes:
            corrections = np.asarray(corrected) - np.asarray([item[0] for item in cache])
            for _ in range(temporal_passes):
                previous = np.roll(corrections, 1, axis=0)
                following = np.roll(corrections, -1, axis=0)
                if not loop:
                    previous[0], following[-1] = corrections[0], corrections[-1]
                corrections = .25 * previous + .5 * corrections + .25 * following
                corrections[:, frozen] = 0
            for index, (original, sleeve_points, directions) in enumerate(cache):
                proxies = [SleeveProxy(points, faces, direction, margin, pinned)
                           for points, faces, direction, margin, pinned in zip(sleeve_points, sleeve_faces, directions, gap, sleeve_pinned_faces)]
                points, item = _project(original, original + corrections[index], proxies, polygons, constraint_seams,
                                        frozen, neighbors, temporal_reproject_iterations, maximum_step,
                                        maximum_displacement, smooth_strength, check_every, clearance_tolerance)
                item["frame"] = selected[index]
                item["temporal_reprojection"] = True
                corrected[index] = points
                report["frames"][index] = item
                write_report()
        if bake:
            local_samples = []
            for frame, points in zip(selected, corrected):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                local_samples.append(binding.inverse_points(points))
            if gown.data.users > 1:
                gown.data = gown.data.copy()
            label = "Graduate_Gown_SleeveClearance_" + clip
            if loop:
                bake_loop(gown, local_samples, label)
            else:
                bake_keys(gown, local_samples, scene.frame_start, label)
            report["baked"] = True
    corrections = np.asarray(corrected) - np.asarray([item[0] for item in cache])
    differences = np.diff(corrections, axis=0)
    if loop and len(corrections) > 1:
        differences = np.concatenate((differences, (corrections[:1] - corrections[-1:])), axis=0)
    report["maximum_correction_change_between_sampled_frames_m"] = float(np.linalg.norm(differences, axis=2).max(initial=0))
    report["remaining_free_midsurface_crossings"] = sum(item["after"]["free_region"] for item in report["frames"])
    report["remaining_sample_violations"] = sum(item["after_samples"]["violating_samples"] for item in report["frames"])
    report["rejected_frames"] = [item["frame"] for item in report["frames"] if item["rejected_due_to_crossing_regression"]]
    report["maximum_actual_displacement_m"] = max(item["maximum_displacement_m"] for item in report["frames"])
    report["requires_review"] = bool(report["remaining_free_midsurface_crossings"] or report["remaining_sample_violations"])
    report["complete"] = True
    write_report()
    print("GOWN_SLEEVE_REPAIR_DONE", scene.name, "baked", bake, "remaining_free",
          report["remaining_free_midsurface_crossings"], "remaining_samples", report["remaining_sample_violations"], flush=True)
    if return_geometry:
        report["_corrected_points"] = corrected
        report["_frames"] = selected
    return report
