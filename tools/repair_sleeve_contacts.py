"""Bounded geometric contact cleanup of an existing physical sleeve bake.

Import this module and call ``repair_clip('walk', report_path=...)`` inside an
already-open Blender file. Nothing runs on import, no subprocess is launched,
and no blend is saved. Only the two sleeve shape-key caches may be changed.
Original sampled surfaces are preserved beside the report in a separate NPZ.

This is a conservative cleanup, not a replacement cloth simulation. It cannot
promise to undo a deeply knotted mesh. Reports preserve all unresolved contact
counts and identify displacement limits. Caller must inspect the result before
saving. Jump frames 41 onward are audited but left untouched by default.
"""

from __future__ import annotations

import json
from pathlib import Path
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cloth_surface_helpers import closed_body_topology, body_surface_positions, inside
from simulate_portal_cloth import SCALE, SkinBinding, bake_keys, evaluated_points
from simulate_sleeve_cloth import bake_loop
from sleeve_arm_colliders import arm_capsule_inputs
from validate_sleeve_garment_contact import crossing_segment, visible_surfaces

ROLES = ("02 | Bell sleeve L", "02 | Bell sleeve R")
PREFIXES = {"walk": "01_WALK", "run": "02_RUN", "jump": "03_JUMP"}
SEAM_GROUP = "Sleeve shoulder seam only"


def _tree(points, triangles):
    return BVHTree.FromPolygons([Vector(point) for point in points], triangles, all_triangles=True)


def _evaluated_geometry(obj):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        return (np.asarray([(evaluated.matrix_world @ vertex.co)[:] for vertex in mesh.vertices]) * SCALE,
                [tuple(face.vertices) for face in mesh.polygons],
                [tuple(triangle.vertices) for triangle in mesh.loop_triangles],
                [triangle.polygon_index for triangle in mesh.loop_triangles])
    finally:
        evaluated.to_mesh_clear()


class Tessellation:
    """Reuse one temporary mesh so repaired quads get Blender's actual diagonals."""
    def __init__(self, points, polygons):
        self.mesh = bpy.data.meshes.new("TEMP | Sleeve contact tessellation")
        self.mesh.from_pydata(points, [], polygons)

    def triangles(self, points):
        self.mesh.vertices.foreach_set("co", np.asarray(points, dtype=np.float64).reshape(-1))
        self.mesh.update()
        self.mesh.calc_loop_triangles()
        return [tuple(triangle.vertices) for triangle in self.mesh.loop_triangles]

    def close(self):
        bpy.data.meshes.remove(self.mesh)


def _closed_gown_tree(points, polygons):
    """Cap neck/hem/front boundaries only for inside/outside classification.

    The cap faces are never used to push cloth. Nearest-contact tests use the
    untouched original gown surface and its explicit sewn-joint exclusion.
    """
    mesh = bmesh.new()
    try:
        for point in points:
            mesh.verts.new(point)
        mesh.verts.ensure_lookup_table()
        for polygon in polygons:
            mesh.faces.new([mesh.verts[index] for index in polygon])
        boundary = [edge for edge in mesh.edges if edge.is_boundary]
        if boundary:
            bmesh.ops.holes_fill(mesh, edges=boundary, sides=0)
        bmesh.ops.recalc_face_normals(mesh, faces=list(mesh.faces))
        bmesh.ops.triangulate(mesh, faces=list(mesh.faces))
        mesh.verts.ensure_lookup_table()
        mesh.verts.index_update()
        vertices = [vertex.co[:] for vertex in mesh.verts]
        triangles = [tuple(vertex.index for vertex in face.verts) for face in mesh.faces]
        unclosed = sum(edge.is_boundary for edge in mesh.edges)
        if unclosed:
            raise RuntimeError(f"Gown volume still has {unclosed} boundary edges after temporary capping")
        return _tree(vertices, triangles)
    finally:
        mesh.free()


def _normal(points, ids):
    a, b, c = [Vector(points[index]) for index in ids]
    value = (b - a).cross(c - a)
    return value.normalized() if value.length_squared > 1e-20 else None


def _contacts(points, triangles, seam, gown_points, gown_triangles, retained, split):
    """Keep exact pair indices and segment lengths; no count suppression."""
    sleeve_tree = _tree(points, triangles)
    gown_tree = _tree(gown_points, gown_triangles)
    normals = [_normal(points, ids) for ids in triangles]
    gown_normals = [_normal(gown_points, ids) for ids in gown_triangles]
    records = {"sewn_joint": [], "retained_gown": [], "self": [], "left_right": []}
    for a, b in sleeve_tree.overlap(gown_tree):
        if any(seam[index] for index in triangles[a]):
            continue
        extent, _ = crossing_segment([Vector(points[index]) for index in triangles[a]], normals[a],
                                     [Vector(gown_points[index]) for index in gown_triangles[b]],
                                     gown_normals[b], 1e-7)
        if extent is not None:
            records["retained_gown" if retained[b] else "sewn_joint"].append((a, b, extent))
    pairs = {(min(a, b), max(a, b)) for a, b in sleeve_tree.overlap(sleeve_tree) if a != b}
    for a, b in sorted(pairs):
        ia, ib = triangles[a], triangles[b]
        if set(ia).intersection(ib) or any(seam[index] for index in ia + ib):
            continue
        extent, _ = crossing_segment([Vector(points[index]) for index in ia], normals[a],
                                     [Vector(points[index]) for index in ib], normals[b], 1e-7)
        if extent is not None:
            category = "self" if (ia[0] < split) == (ib[0] < split) else "left_right"
            records[category].append((a, b, extent))
    return records


def _contact_summary(records):
    return {name: {"count": len(items), "maximum_segment_m": max((item[2] for item in items), default=0.0)}
            for name, items in records.items()}


def _limited(delta, limit):
    length = float(np.linalg.norm(delta))
    return delta * min(1.0, limit / max(length, 1e-12))


def _gown_vertices(points, frozen, gown_tree, volume, retained, margin, step):
    touched = set()
    for index in np.flatnonzero(~frozen):
        point = Vector(points[index])
        hit, normal, triangle, distance = gown_tree.find_nearest(point)
        if hit is None or not retained[triangle] or distance > .10:
            continue
        signed = (point - hit).dot(normal)
        penetrates = signed < 0 and inside(volume, point)
        if penetrates or (signed >= 0 and distance < margin):
            points[index] += _limited(np.asarray(normal) * (margin - signed), step)
            touched.add(int(index))
    return touched


def _gown_crossings(points, frozen, records, triangles, gown_points, gown_triangles, margin, step):
    touched = set()
    for sleeve_id, gown_id, _ in records["retained_gown"]:
        garment_triangle = gown_triangles[gown_id]
        normal = _normal(gown_points, garment_triangle)
        if normal is None:
            continue
        normal = np.asarray(normal)
        origin = gown_points[garment_triangle[0]]
        for index in triangles[sleeve_id]:
            if frozen[index]:
                continue
            distance = float((points[index] - origin) @ normal)
            if distance < margin:
                points[index] += normal * min(step, margin - distance)
                touched.add(index)
    return touched


def _self_separate(points, frozen, records, triangles, adjacency, gap, step):
    """Translate a crossed local layer toward its nearest separating side."""
    touched = set()
    for a, b, _ in records["self"] + records["left_right"]:
        options = []
        for moving, obstacle in ((triangles[a], triangles[b]), (triangles[b], triangles[a])):
            # Moving an entire triangle avoids stretching it or pulling the
            # shoulder seam off the rig. A blocked pair remains in the report.
            if any(frozen[index] for index in moving):
                continue
            normal = _normal(points, obstacle)
            if normal is None:
                continue
            normal = np.asarray(normal)
            distances = (points[list(moving)] - points[obstacle[0]]) @ normal
            options.append((max(0.0, gap - float(distances.min())), moving, normal))
            options.append((max(0.0, gap + float(distances.max())), moving, -normal))
        if not options:
            continue
        amount, ids, normal = min(options, key=lambda option: option[0])
        if amount <= 0:
            continue
        delta = normal * min(step, amount)
        patch = {index: 1.0 for index in ids}
        for index in ids:
            for neighbor in adjacency[index]:
                patch.setdefault(neighbor, .25)
        for index, weight in patch.items():
            if not frozen[index]:
                points[index] += delta * weight
                touched.add(index)
    return touched


def _smooth_self_patch(points, frozen, records, triangles, adjacency):
    """Fair crossed triangles plus two neighbor rings, without rest-edge forces."""
    core = {index for a, b, _ in records["self"] + records["left_right"]
            for index in triangles[a] + triangles[b]}
    weights = {index: .25 for index in core}
    frontier = core
    for strength in (.12, .06):
        following = {neighbor for index in frontier for neighbor in adjacency[index]} - set(weights)
        weights.update({index: strength for index in following})
        frontier = following
    previous = points.copy()
    touched = set()
    for index, strength in weights.items():
        if frozen[index] or not adjacency[index]:
            continue
        points[index] += (previous[list(adjacency[index])].mean(axis=0) - previous[index]) * strength
        touched.add(index)
    return touched


def _relax(points, original, frozen, touched, adjacency, edges, lengths, step, fairing=True,
           restore_lengths=True):
    if touched and fairing:
        previous = points.copy()
        for index in touched:
            if frozen[index] or not adjacency[index]:
                continue
            neighbors = list(adjacency[index])
            # A small local fairing step releases crossed folds. It does not
            # pull the sleeve toward the rigid arm-skinned starting surface.
            delta = (previous[neighbors].mean(axis=0) - previous[index]) * .035
            points[index] += _limited(delta, step * .25)
    for _ in range(2 if restore_lengths else 0):
        for (a, b), rest in zip(edges, lengths):
            if a not in touched and b not in touched:
                continue
            delta = points[b] - points[a]
            length = float(np.linalg.norm(delta))
            target = min(max(length, rest * .80), rest * 1.10)
            if length < 1e-10 or abs(target - length) < 1e-7:
                continue
            free = int(not frozen[a]) + int(not frozen[b])
            if not free:
                continue
            correction = _limited(delta * ((length - target) / length / free), step)
            if not frozen[a]:
                points[a] += correction
            if not frozen[b]:
                points[b] -= correction


def _body_clearance(points, frozen, trees, margin, step, move=True):
    violations = 0
    for tree in trees:
        for index in np.flatnonzero(~frozen):
            point = Vector(points[index])
            hit, normal, _, distance = tree.find_nearest(point)
            if hit is None or distance > .10:
                continue
            signed = (point - hit).dot(normal)
            penetrates = signed < -.0005 and inside(tree, point)
            if penetrates:
                violations += 1
            if move and (penetrates or (signed >= 0 and distance < margin)):
                points[index] += _limited(np.asarray(normal) * (margin - signed), step)
    return violations


def repair_clip(clip, report_path, *, iterations=18, gown_margin=.005, self_gap=.007,
                maximum_step=.004, maximum_displacement=.065, repair_hidden=False, bake=True,
                frames=None, repair_self=True, self_method="smooth", relax_edges=True):
    """Repair sleeves in memory, preserving every non-sleeve asset and source sample."""
    if clip not in PREFIXES:
        raise ValueError("clip must be walk, run, or jump")
    if self_method not in {"smooth", "separate"}:
        raise ValueError("self_method must be smooth or separate")
    requested_frames = None if frames is None else set(frames)
    scene = next(scene for scene in bpy.data.scenes if scene.name.startswith(PREFIXES[clip]))
    rig = next(obj for obj in scene.objects if obj.type == "ARMATURE")
    sleeves = [next(obj for obj in scene.objects if obj.get("graduate_role") == role) for role in ROLES]
    gown = next(obj for obj in scene.objects if obj.get("graduate_role") == "01 | Pleated bachelor gown")
    body = next(obj for obj in scene.objects if obj.get("graduate_role") == "Graduate | original face, hands and trousers")
    offsets = np.cumsum([0] + [len(obj.data.vertices) for obj in sleeves])
    polygons, seam = [], []
    for offset, obj in zip(offsets, sleeves):
        group = obj.vertex_groups.get(SEAM_GROUP)
        if group is None:
            raise RuntimeError("Physical sleeve seam group missing: " + obj.name)
        seam.extend(any(weight.group == group.index and weight.weight > 0 for weight in vertex.groups)
                    for vertex in obj.data.vertices)
        polygons.extend(tuple(int(index + offset) for index in face.vertices) for face in obj.data.polygons)
    seam = np.asarray(seam, dtype=bool)
    adjacency = [set() for _ in seam]
    for polygon in polygons:
        for a, b in zip(polygon, polygon[1:] + polygon[:1]):
            adjacency[a].add(b)
            adjacency[b].add(a)
    frozen = seam.copy()
    for index in np.flatnonzero(seam):
        frozen[list(adjacency[index])] = True
    edges = sorted({(min(a, b), max(a, b)) for a, neighbors in enumerate(adjacency) for b in neighbors})
    omitted_polygons = {face.index for face in gown.data.polygons
                        if face.center.z > 3.05 and abs(face.center.x) > .34}
    body_ids, body_faces = closed_body_topology(body)
    report = {"clip": clip, "source_blend": bpy.data.filepath, "saved_blend": False,
              "method": "Bounded post-simulation contact projection and local fold relaxation",
              "gown_margin_m": gown_margin, "self_gap_m": self_gap,
              "maximum_allowed_displacement_m": maximum_displacement,
              "seam_vertices": int(seam.sum()), "frozen_seam_and_neighbors": int(frozen.sum()),
              "frames": [], "baked": False}
    original_samples, repaired_samples = [], []
    with visible_surfaces(scene, [body, gown] + sleeves, "simulation"):
        bindings = [SkinBinding(obj, rig) for obj in sleeves]
        for frame in range(scene.frame_start, scene.frame_end + 1):
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            original = np.concatenate([evaluated_points(obj) for obj in sleeves])
            points = original.copy()
            gp, gf, gt, parent_polygons = _evaluated_geometry(gown)
            retained = [polygon not in omitted_polygons for polygon in parent_polygons]
            gown_tree, volume = _tree(gp, gt), _closed_gown_tree(gp, gf)
            body_points = body_surface_positions(body, body_ids, SCALE, margin=0)
            body_trees = [_tree(body_points, body_faces)]
            body_trees.extend(_tree(data["points"], data["faces"])
                              for data in arm_capsule_inputs(rig, SCALE).values())
            lengths = np.asarray([np.linalg.norm(original[a] - original[b]) for a, b in edges])
            tessellation = Tessellation(points, polygons)
            try:
                triangles = tessellation.triangles(points)
                before = _contacts(points, triangles, seam, gp, gt, retained, offsets[1])
                initial_body = _body_clearance(points, frozen, body_trees, .0035, maximum_step, move=False)
                active = ((clip != "jump" or frame <= 40 or repair_hidden)
                          and (requested_frames is None or frame in requested_frames))
                completed = 0
                best_points = points.copy()
                best_iteration = 0
                categories = ("retained_gown", "self", "left_right")
                best_score = (sum(len(before[key]) for key in categories),
                              sum(item[2] for key in categories for item in before[key]))
                for iteration in range(iterations if active else 0):
                    records = _contacts(points, triangles, seam, gp, gt, retained, offsets[1])
                    touched = _gown_vertices(points, frozen, gown_tree, volume, retained,
                                             gown_margin, maximum_step)
                    touched.update(_gown_crossings(points, frozen, records, triangles, gp, gt,
                                                   gown_margin, maximum_step))
                    if repair_self:
                        if self_method == "smooth":
                            touched.update(_smooth_self_patch(points, frozen, records, triangles, adjacency))
                        else:
                            touched.update(_self_separate(points, frozen, records, triangles, adjacency,
                                                          self_gap, maximum_step))
                    _relax(points, original, frozen, touched, adjacency, edges, lengths, maximum_step,
                           fairing=repair_self and self_method == "separate",
                           restore_lengths=relax_edges and (not repair_self or self_method == "separate"))
                    _body_clearance(points, frozen, body_trees, .0035, maximum_step)
                    delta = points - original
                    magnitude = np.linalg.norm(delta, axis=1)
                    points = original + delta * np.minimum(1, maximum_displacement / np.maximum(magnitude, 1e-12))[:, None]
                    points[frozen] = original[frozen]
                    triangles = tessellation.triangles(points)
                    completed = iteration + 1
                    candidate = _contacts(points, triangles, seam, gp, gt, retained, offsets[1])
                    candidate_body = _body_clearance(points, frozen, body_trees, .0035, maximum_step, move=False)
                    score = (sum(len(candidate[key]) for key in categories),
                             sum(item[2] for key in categories for item in candidate[key]))
                    if (candidate_body <= initial_body
                            and all(len(candidate[key]) <= len(before[key]) for key in categories)
                            and score < best_score):
                        best_points = points.copy()
                        best_score = score
                        best_iteration = completed
                    if not touched and not any(records[key] for key in ("retained_gown", "self", "left_right")):
                        break
                points = best_points
                triangles = tessellation.triangles(points)
                after = _contacts(points, triangles, seam, gp, gt, retained, offsets[1])
                final_body = _body_clearance(points, frozen, body_trees, .0035, maximum_step, move=False)
            finally:
                tessellation.close()
            movement = np.linalg.norm(points - original, axis=1)
            result = {"frame": frame, "visible": clip != "jump" or frame <= 40,
                      "repaired": active, "iterations": completed,
                      "accepted_iteration": best_iteration,
                      "before": _contact_summary(before), "after": _contact_summary(after),
                      "body_inside_vertices_before": initial_body, "body_inside_vertices_after": final_body,
                      "maximum_displacement_m": float(movement.max()),
                      "vertices_at_displacement_limit": int(np.count_nonzero(movement >= maximum_displacement - 1e-6)),
                      "frozen_vertex_max_error_m": float(movement[frozen].max(initial=0))}
            report["frames"].append(result)
            original_samples.append(original)
            repaired_samples.append(points)
            print("SLEEVE_REPAIR_FRAME", clip, frame,
                  {key: result["after"][key]["count"] for key in ("retained_gown", "self", "left_right")}, flush=True)
        if bake:
            samples = [[] for _ in sleeves]
            for frame, points in zip(range(scene.frame_start, scene.frame_end + 1), repaired_samples):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                for index, binding in enumerate(bindings):
                    samples[index].append(binding.inverse_points(points[offsets[index]:offsets[index + 1]]))
            for obj, poses in zip(sleeves, samples):
                name = "Graduate_" + clip.title() + "_ContactCleanup_" + obj.get("graduate_role")
                if clip == "jump":
                    bake_keys(obj, poses, scene.frame_start, name)
                else:
                    bake_loop(obj, poses, name)
            report["baked"] = True
    original_samples = np.asarray(original_samples)
    repaired_samples = np.asarray(repaired_samples)
    correction = repaired_samples - original_samples
    report["maximum_correction_change_between_frames_m"] = float(
        np.linalg.norm(np.diff(correction, axis=0), axis=2).max(initial=0))
    report["visible_remaining_contacts"] = sum(
        frame["after"][key]["count"] for frame in report["frames"] if frame["visible"]
        for key in ("retained_gown", "self", "left_right"))
    report["visible_body_inside_vertices"] = sum(frame["body_inside_vertices_after"]
                                                for frame in report["frames"] if frame["visible"])
    report["status"] = "requires review" if (report["visible_remaining_contacts"]
                                            or report["visible_body_inside_vertices"]) else "contact checks clear; visual review required"
    output = Path(report_path).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    samples_path = output.with_suffix(".npz")
    np.savez_compressed(samples_path, original=original_samples, repaired=repaired_samples,
                        correction=correction, frozen=frozen, seam=seam, offsets=offsets)
    report["preserved_samples"] = str(samples_path)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("SLEEVE_REPAIR_COMPLETE", clip, report["status"], str(output), flush=True)
    return report
