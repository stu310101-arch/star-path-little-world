"""Bounded, local cloth clearance against the graduate's actual neck skin.

This helper does not change a Blender object, modifier, action, or file. Build
the collider after setting each animation frame, then pass posed cloth points
and faces in metres to ``clear_neck``. The returned coordinates have the same
vertex order. The caller owns inverse skinning/baking and exact contact QA.

    neck = build_neck_collider(body)
    corrected, report = clear_neck(points, triangles, neck, margin=.003)

The source inspection identifies material ``Skin`` and Neck rest height near
4.03--4.22 model units. Skin also covers hands/legs, so material alone is NOT
the selection. Only the central rest-space band z=3.75--4.25, |x|<=.42 is
eligible. BVH triangles retain their real, unmodified skin geometry; query
hits are additionally checked against that rest-space band by barycentrics.
No artificial closing faces or whole-body collider participate in pushing.

Verification is sampled (vertices, edge midpoints, polygon and triangle
centres), not proof that all triangles are disjoint. Unresolved constraints
remain in the report, including those that exhaust the 12 mm displacement
budget. An explicit neckline-reshape option permits up to 25 mm while keeping
the same actual neck skin and 30 mm query radius. Run audit_regalia_pairs.py
afterward on the rendered Solidify mesh.
For separately modelled sewn boundaries, the caller must preserve/weld the
shared boundary while applying this correction and recheck the final join.
"""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
import re

import numpy as np

SCALE = 1.75 / 4.8
BODY_ROLE = "Graduate | original face, hands and trousers"
# Diagnostics from regalia-pairs-layers-v2.json; never used as a selection mask.
KNOWN_NECK_POLYGONS = frozenset((12, 38, 219, 220, 294, 320, 502))


def _bounds(points):
    return [np.min(points, axis=0).tolist(), np.max(points, axis=0).tolist()]


def _barycentric(point, triangle):
    a, b, c = triangle
    u, v, d = b - a, c - a, point - a
    uu, uv, vv = np.dot(u, u), np.dot(u, v), np.dot(v, v)
    denominator = uu * vv - uv * uv
    if denominator < 1e-22:
        return None
    beta = (vv * np.dot(d, u) - uv * np.dot(d, v)) / denominator
    gamma = (uu * np.dot(d, v) - uv * np.dot(d, u)) / denominator
    return np.array((1 - beta - gamma, beta, gamma))


def _clip_region(rest, posed, low_z, high_z, limit_x):
    """Clip ONLY for selection/bounds; returned vertices never enter the BVH."""
    polygon = [(r.copy(), p.copy()) for r, p in zip(rest, posed)]
    for axis, value, direction in ((0, -limit_x, 1), (0, limit_x, -1),
                                   (2, low_z, 1), (2, high_z, -1)):
        if not polygon:
            break
        output = []
        previous = polygon[-1]
        previous_d = (previous[0][axis] - value) * direction
        for current in polygon:
            current_d = (current[0][axis] - value) * direction
            if (current_d >= 0) != (previous_d >= 0):
                t = previous_d / (previous_d - current_d)
                output.append(tuple(a + t * (b - a) for a, b in zip(previous, current)))
            if current_d >= 0:
                output.append(current)
            previous, previous_d = current, current_d
        polygon = output
    return polygon


@dataclass
class NeckCollider:
    tree: object
    points: np.ndarray
    rest_points: np.ndarray
    triangles: np.ndarray
    source_polygons: tuple
    rest_z: tuple
    rest_x_limit: float
    bounds: np.ndarray
    selection_report: dict
    vector_type: object

    def query(self, point, max_distance=.030, boundary_tangent_limit=.002):
        """Finite, anatomical nearest-surface query; preserve actual winding.

        An open patch must not act like an infinite plane beyond its edges.
        Reject substantial tangential offsets at a boundary, and reject hits
        whose interpolated original position lies outside the neck band.
        """
        point = np.asarray(point, dtype=np.float64)
        if np.any(point < self.bounds[0] - max_distance) or np.any(point > self.bounds[1] + max_distance):
            return None
        hit, normal, triangle, distance = self.tree.find_nearest(self.vector_type(point), max_distance)
        if hit is None:
            return None
        hit, normal = np.asarray(hit, dtype=float), np.asarray(normal, dtype=float)
        normal_length = np.linalg.norm(normal)
        if normal_length < 1e-10:
            return None
        normal /= normal_length
        ids = self.triangles[triangle]
        weights = _barycentric(hit, self.points[ids])
        if weights is None:
            return None
        rest_hit = weights @ self.rest_points[ids]
        if not (self.rest_z[0] - 1e-6 <= rest_hit[2] <= self.rest_z[1] + 1e-6
                and abs(rest_hit[0]) <= self.rest_x_limit + 1e-6):
            return None
        difference = point - hit
        signed = float(np.dot(difference, normal))
        tangent = float(np.linalg.norm(difference - normal * signed))
        if tangent > boundary_tangent_limit:
            return None
        return {"normal": normal, "signed_gap_m": signed,
                "distance_m": float(distance), "point_m": hit.tolist(),
                "rest_hit": rest_hit.tolist(), "triangle": int(triangle),
                "source_polygon": int(self.source_polygons[triangle])}


def build_neck_collider(body, scale=SCALE, rest_z=(3.75, 4.25), rest_x_limit=.42):
    """Read one evaluated frame; retain actual Skin triangles and face winding.

    Raises on missing Skin/empty region or changed evaluated topology rather
    than guessing source-to-evaluated vertex correspondence. This function
    neither hides modifiers nor edits/deletes/fills any body faces.
    """
    import bpy
    from mathutils import Vector
    from mathutils.bvhtree import BVHTree

    if body.type != "MESH":
        raise ValueError("Neck collider requires the original body mesh")
    role = body.get("graduate_role")
    if role and role != BODY_ROLE:
        raise ValueError("Neck collider was given a non-body graduate role: " + role)
    if not (scale > 0 and 0 < rest_x_limit <= .5 and 3.6 <= rest_z[0] < rest_z[1] <= 4.3):
        raise ValueError("Expected the graduate's narrow neck band in source model coordinates")
    rest = np.asarray([v.co[:] for v in body.data.vertices], dtype=np.float64)
    source_faces = [tuple(p.vertices) for p in body.data.polygons]
    skin_slots = {i for i, slot in enumerate(body.material_slots)
                  if slot.material and re.fullmatch(r"Skin(?:\.\d+)?", slot.material.name)}
    if not skin_slots:
        raise ValueError("Actual body has no Skin material slot; no collider was built")
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        if len(mesh.vertices) != len(rest) or [tuple(p.vertices) for p in mesh.polygons] != source_faces:
            raise ValueError("Evaluated body topology differs from source; refusing anatomical index mapping")
        points = np.asarray([(evaluated.matrix_world @ v.co)[:] for v in mesh.vertices],
                            dtype=np.float64) * scale
        mesh.calc_loop_triangles()
        triangles, polygons, clipped_posed = [], [], []
        for triangle in mesh.loop_triangles:
            polygon = body.data.polygons[triangle.polygon_index]
            if polygon.material_index not in skin_slots:
                continue
            ids = tuple(triangle.vertices)
            region = _clip_region(rest[list(ids)], points[list(ids)], *rest_z, rest_x_limit)
            if len(region) < 3:
                continue
            a, b, c = points[list(ids)]
            if np.linalg.norm(np.cross(b - a, c - a)) < 1e-12:
                continue
            triangles.append(ids)
            polygons.append(int(polygon.index))
            clipped_posed.extend(p for _, p in region)
    finally:
        evaluated.to_mesh_clear()
    if not triangles:
        raise ValueError("No actual Skin triangles in the specified central neck region")
    selected_polygons = set(polygons)
    selected_vertices = sorted({i for tri in triangles for i in tri})
    skin_names = [body.material_slots[i].material.name for i in sorted(skin_slots)]
    report = {"object": body.name, "frame": bpy.context.scene.frame_current,
              "source_vertices": len(rest), "source_polygon_ids": sorted(selected_polygons),
              "actual_skin_triangles": len(triangles), "skin_materials": skin_names,
              "rest_z_band": list(rest_z), "rest_abs_x_limit": rest_x_limit,
              "source_triangle_bounds_model": _bounds(rest[selected_vertices]),
              "query_region_bounds_m": _bounds(np.asarray(clipped_posed)),
              "known_neck_polygons_included": sorted(selected_polygons & KNOWN_NECK_POLYGONS),
              "known_neck_polygons_missing": sorted(KNOWN_NECK_POLYGONS - selected_polygons),
              "known_polygon_ids_are_diagnostics_only": True,
              "actual_skin_unchanged": True, "closure_faces_used": 0,
              "normals": "Actual posed triangle winding; no whole-body or face-normal override"}
    tree = BVHTree.FromPolygons([Vector(p) for p in points], triangles, all_triangles=True)
    return NeckCollider(tree, points, rest, np.asarray(triangles, dtype=np.int32),
                        tuple(polygons), tuple(rest_z), rest_x_limit,
                        np.asarray(report["query_region_bounds_m"]), report, Vector)


def _samples(vertex_count, faces, density=1):
    result = [("vertex", (i,), np.array((1.,))) for i in range(vertex_count)]
    edges = set()
    triangles = []
    for face in faces:
        face = tuple(int(i) for i in face)
        if len(face) < 3 or any(i < 0 or i >= vertex_count for i in face):
            raise ValueError("Cloth faces must reference at least three existing vertices")
        if len(set(face)) != len(face):
            raise ValueError("Degenerate cloth polygon with repeated vertex IDs")
        result.append(("face_center", face, np.full(len(face), 1 / len(face))))
        for i in range(len(face)):
            edges.add(tuple(sorted((face[i], face[(i + 1) % len(face)]))))
        # Matches the project's FIXED quad triangulation. Pass the actual
        # triangles for general nonconvex ngons instead of relying on a fan.
        if len(face) > 3:
            for i in range(1, len(face) - 1):
                tri = (face[0], face[i], face[i + 1])
                triangles.append(tri)
                result.append(("triangle_center", tri, np.full(3, 1 / 3)))
                for j in range(3):
                    edges.add(tuple(sorted((tri[j], tri[(j + 1) % 3]))))
        else:
            triangles.append(face)
    result.extend(("edge_midpoint", edge, np.array((.5, .5))) for edge in sorted(edges))
    if density > 1:
        divisions = 2 ** (density - 1)
        for edge in sorted(edges):
            for step in range(1, 2 * divisions):
                if step == divisions:
                    continue  # Already sampled the midpoint.
                t = step / (2 * divisions)
                result.append(("edge_interior", edge, np.array((1 - t, t))))
        for tri in triangles:
            for i in range(divisions):
                for j in range(divisions - i):
                    centers = [((i + 1 / 3) / divisions, (j + 1 / 3) / divisions)]
                    if i + j < divisions - 1:
                        centers.append(((i + 2 / 3) / divisions, (j + 2 / 3) / divisions))
                    for u, v in centers:
                        weights = np.array((u, v, 1 - u - v))
                        if not np.allclose(weights, 1 / 3):
                            result.append(("subtriangle_center", tri, weights))
    return result


def clear_neck(points, faces, collider, margin=.003, *, max_distance=.030,
               max_correction=.012, max_step=.002, iterations=12,
               tolerance=.00005, fixed=None, max_examples=24,
               support_radius=None, allow_neckline_reshape=False, sample_density=1):
    """Return (new float64 points, JSON-safe sampled-clearance report).

    Only input vertices already within the local neck bounds plus support
    radius can move. ``fixed`` is an optional boolean vertex mask. Net shift
    from the supplied input is capped at max_correction (normally <=12 mm).
    For a documented too-small gown neckline, explicitly pass
    ``allow_neckline_reshape=True, support_radius=.055, max_correction=.025,
    iterations=24``. This releases nearby supporting cloth vertices, not any
    extra body surfaces; actual skin queries remain <=30 mm in that mode.
    ``sample_density=2`` adds edge quarter points and four subtriangle centres
    (the already-sampled centre is deduplicated); 3 uses eighth points and 16
    subtriangle centres. No subdivision or topology change is made to cloth.
    A call does not grant a new budget across repeated calls: the caller must
    retain the pre-repair coordinates and measure the total if it calls again.
    Cloth thickness is not inferred; margin is from the supplied mid-surface.
    """
    original = np.asarray(points, dtype=np.float64).copy()
    if original.ndim != 2 or original.shape[1] != 3 or not np.isfinite(original).all():
        raise ValueError("points must be a finite (N, 3) array in metres")
    support_radius = max_distance if support_radius is None else float(support_radius)
    displacement_limit = .025 if allow_neckline_reshape else .012
    support_limit = .06 if allow_neckline_reshape else max_distance
    query_limit = .030 if allow_neckline_reshape else .04
    if not (0 < margin <= .01 and margin <= max_distance <= query_limit
            and 0 < max_correction <= displacement_limit and 0 < max_step <= .003
            and max_distance <= support_radius <= support_limit
            and 1 <= iterations <= 32 and 0 < tolerance < margin
            and sample_density in (1, 2, 3)):
        raise ValueError("Invalid bounded neck-clearance parameters")
    fixed_mask = np.zeros(len(original), dtype=bool) if fixed is None else np.asarray(fixed, dtype=bool)
    if fixed_mask.shape != (len(original),):
        raise ValueError("fixed must be one boolean per vertex")
    result = original.copy()
    lower, upper = np.asarray(collider.bounds)
    eligible = (np.all(original >= lower - support_radius, axis=1)
                & np.all(original <= upper + support_radius, axis=1) & ~fixed_mask)
    all_samples = _samples(len(original), faces, sample_density)
    samples = []
    for kind, ids, weights in all_samples:
        ids = np.asarray(ids, dtype=np.int32)
        point = weights @ original[ids]
        if (np.all(point >= lower - max_distance - max_correction)
                and np.all(point <= upper + max_distance + max_correction)):
            samples.append((kind, ids, weights))

    def measure(coords):
        valid = 0
        counts, penetrating = Counter(), Counter()
        gaps, examples = [], []
        for kind, ids, weights in samples:
            hit = collider.query(weights @ coords[ids], max_distance=max_distance)
            if hit is None:
                continue
            valid += 1
            gap = hit["signed_gap_m"]
            gaps.append(gap)
            if gap < margin - tolerance:
                counts[kind] += 1
                if gap < -tolerance:
                    penetrating[kind] += 1
                examples.append({"kind": kind, "vertices": ids.tolist(),
                                 "signed_gap_m": gap, "missing_clearance_m": margin - gap,
                                 "skin_source_polygon": hit["source_polygon"],
                                 "point_m": (weights @ coords[ids]).tolist(),
                                 "movable_vertices": int(np.count_nonzero(eligible[ids]))})
        examples.sort(key=lambda row: row["signed_gap_m"])
        return {"queried_local_samples": len(samples), "valid_neck_surface_samples": valid,
                "unresolved_samples": sum(counts.values()), "unresolved_by_kind": dict(counts),
                "penetrating_samples": sum(penetrating.values()), "penetrating_by_kind": dict(penetrating),
                "minimum_signed_gap_m": min(gaps) if gaps else None,
                "max_missing_clearance_m": max(0., margin - min(gaps)) if gaps else 0.,
                "max_penetration_m": max(0., -min(gaps)) if gaps else 0.,
                "worst_examples": examples[:max_examples]}

    before = measure(result)
    capped = set()
    used_iterations = 0
    for iteration in range(iterations):
        sums = np.zeros_like(result)
        counts = np.zeros(len(result), dtype=np.int32)
        for _, ids, weights in samples:
            hit = collider.query(weights @ result[ids], max_distance=max_distance)
            if hit is None or hit["signed_gap_m"] >= margin - tolerance:
                continue
            free = eligible[ids]
            denominator = float(np.dot(weights[free], weights[free]))
            if denominator == 0:
                continue
            delta = hit["normal"] * (margin - hit["signed_gap_m"])
            for vertex, weight, movable in zip(ids, weights, free):
                if movable:
                    sums[vertex] += delta * (weight / denominator)
                    counts[vertex] += 1
        moving = np.flatnonzero(counts)
        if not len(moving):
            break
        moves = sums[moving] / counts[moving, None]
        lengths = np.linalg.norm(moves, axis=1)
        moves *= np.minimum(1., max_step / np.maximum(lengths, 1e-16))[:, None]
        target_shift = result[moving] + moves - original[moving]
        lengths = np.linalg.norm(target_shift, axis=1)
        capped.update(int(i) for i in moving[lengths > max_correction])
        target_shift *= np.minimum(1., max_correction / np.maximum(lengths, 1e-16))[:, None]
        new = original[moving] + target_shift
        maximum_change = float(np.max(np.linalg.norm(new - result[moving], axis=1)))
        result[moving] = new
        used_iterations = iteration + 1
        if maximum_change < tolerance * .05:
            break
    shifts = np.linalg.norm(result - original, axis=1)
    after = measure(result)
    report = {"method": "Local actual-Skin nearest-normal sampled projection; no cap/whole-body collider",
              "units": "metres", "margin_m": margin, "maximum_query_distance_m": max_distance,
              "cloth_support_radius_m": support_radius,
              "explicit_neckline_reshape": bool(allow_neckline_reshape), "sample_density": sample_density,
              "maximum_allowed_vertex_shift_m": max_correction, "iterations": used_iterations,
              "sample_count_total": len(all_samples), "sample_count_local": len(samples),
              "eligible_vertices": int(np.count_nonzero(eligible)),
              "moved_vertices": int(np.count_nonzero(shifts > 1e-8)),
              "maximum_vertex_shift_m": float(np.max(shifts)) if len(shifts) else 0.,
              "capped_vertex_ids": sorted(capped), "fixed_vertices": int(np.count_nonzero(fixed_mask)),
              "before": before, "after": after, "collider": collider.selection_report,
              "exact_triangle_intersection_proof": False,
              "limitations": ["Finite samples can miss intersections between sample positions.",
                              "Open-patch nearest queries beyond the anatomical band or 2 mm tangential boundary are ignored.",
                              "Actual source skin and its face/hair/eye assembly are not modified.",
                              "Rendered cloth thickness, adjacent clothes, and shared seams require final audit."]}
    return result, report
