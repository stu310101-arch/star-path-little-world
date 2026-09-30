"""Read-only transverse triangle-intersection audit of graduate sleeve caches.

Run in one existing background Blender process; this script never saves a blend
or changes an asset on disk. The sole output is the requested JSON report::

    blender -b <candidate.blend> --python-exit-code 1 \
        --python tools/validate_sleeve_garment_contact.py -- \
        --output tools/sleeve-garment-contact.json

The default checks the actual evaluated render surfaces, including Solidify.
``--surface simulation`` temporarily hides non-Armature modifiers to isolate
the simulated midsurface. All in-memory visibility changes are restored.

BVH overlap only produces candidates. Every retained pair must have a finite
noncoplanar intersection segment found by segment/triangle tests; mere AABB
overlap, coplanar contact and point contact are not reported as penetration.
Faces touching any vertex with a positive "Sleeve shoulder seam only" weight
are excluded as intentional sewn attachments. Self pairs sharing a vertex are
also excluded. All exclusions and triangle index tables are included in JSON.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import json
from pathlib import Path
import sys

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree


SCALE = 1.75 / 4.8
SCENES = (("Walk", "01_WALK"), ("Run", "02_RUN"), ("JumpDown", "03_JUMP"))
ROLES = {"left": "02 | Bell sleeve L", "right": "02 | Bell sleeve R",
         "gown": "01 | Pleated bachelor gown"}
SEAM_GROUP = "Sleeve shoulder seam only"
PAIRS = (("left_gown", "left", "gown"),
         ("right_gown", "right", "gown"),
         ("left_right", "left", "right"),
         ("left_self", "left", "left"),
         ("right_self", "right", "right"))


def action_curves(action):
    if action is None:
        return []
    if hasattr(action, "layers"):
        return [curve for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for curve in bag.fcurves]
    return list(action.fcurves)


@contextmanager
def visible_surfaces(scene, objects, surface):
    """Unhide JumpDown after frame 40 and restore every changed field."""
    old_scene = bpy.context.window.scene
    bpy.context.window.scene = scene
    old_frame, old_subframe = scene.frame_current, scene.frame_subframe
    states, curves, modifiers = [], [], []
    # Unhide the rig and mesh ancestors as well as the measured garments.
    targets = set(objects)
    targets.update(obj for obj in scene.objects if obj.type == "ARMATURE")
    for obj in list(targets):
        parent = obj.parent
        while parent:
            targets.add(parent)
            parent = parent.parent
    try:
        for obj in targets:
            states.append((obj, obj.hide_get(), obj.hide_viewport, obj.hide_render))
            for curve in action_curves(obj.animation_data.action
                                       if obj.animation_data else None):
                if curve.data_path in {"hide_viewport", "hide_render"}:
                    curves.append((curve, curve.mute))
                    curve.mute = True
            obj.hide_set(False)
            obj.hide_viewport = False
            obj.hide_render = False
        if surface == "simulation":
            for obj in objects:
                for modifier in obj.modifiers:
                    if modifier.type != "ARMATURE":
                        modifiers.append((modifier, modifier.show_viewport))
                        modifier.show_viewport = False
        bpy.context.view_layer.update()
        yield
    finally:
        for modifier, visible in modifiers:
            modifier.show_viewport = visible
        for curve, muted in curves:
            curve.mute = muted
        for obj, hidden, viewport, render in states:
            obj.hide_set(hidden)
            obj.hide_viewport = viewport
            obj.hide_render = render
        scene.frame_set(old_frame, subframe=old_subframe)
        bpy.context.window.scene = old_scene


class Surface:
    def __init__(self, obj):
        depsgraph = bpy.context.evaluated_depsgraph_get()
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
        try:
            mesh.calc_loop_triangles()
            self.points = [(evaluated.matrix_world @ vertex.co) * SCALE
                           for vertex in mesh.vertices]
            self.triangles = [tuple(triangle.vertices) for triangle in mesh.loop_triangles]
            self.polygons = [triangle.polygon_index for triangle in mesh.loop_triangles]
            self.source_polygons = [tuple(polygon.vertices) for polygon in mesh.polygons]
            group = obj.vertex_groups.get(SEAM_GROUP)
            pin_index = group.index if group else None
            pins = [any(weight.group == pin_index and weight.weight > 0
                        for weight in vertex.groups)
                    for vertex in mesh.vertices]
            self.seam = [any(pins[index] for index in triangle)
                         for triangle in self.triangles]
            self.metadata = {
                "object": obj.name, "role": obj.get("graduate_role"),
                "vertex_count": len(self.points), "triangle_count": len(self.triangles),
                "seam_group_present": group is not None,
                "seam_vertices": [i for i, pinned in enumerate(pins) if pinned],
                "excluded_seam_triangles": [i for i, pinned in enumerate(self.seam) if pinned],
                "triangles": self.triangles, "polygon_indices": self.polygons,
                "source_polygons": self.source_polygons,
            }
        finally:
            evaluated.to_mesh_clear()
        self.tree = BVHTree.FromPolygons(self.points, self.triangles, all_triangles=True)
        self.normals = []
        self.degenerate = []
        for index, ids in enumerate(self.triangles):
            a, b, c = [self.points[i] for i in ids]
            normal = (b - a).cross(c - a)
            if normal.length_squared < 1e-20:
                self.normals.append(None)
                self.degenerate.append(index)
            else:
                self.normals.append(normal.normalized())
        self.metadata["degenerate_triangles"] = self.degenerate


def segment_triangle(start, end, triangle, normal, epsilon):
    """Return an intersection point with a finite segment, or None.

    Plane distances are in metres. Barycentric membership is tested against
    each triangle edge with the same geometric distance tolerance, avoiding a
    fixed determinant threshold that would reject narrow fabric triangles.
    """
    denominator = normal.dot(end - start)
    if abs(denominator) <= epsilon:
        return None
    t = normal.dot(triangle[0] - start) / denominator
    parameter_slack = epsilon / max((end - start).length, epsilon)
    if t < -parameter_slack or t > 1 + parameter_slack:
        return None
    point = start.lerp(end, min(1.0, max(0.0, t)))
    for index in range(3):
        a, b = triangle[index], triangle[(index + 1) % 3]
        edge = b - a
        if edge.cross(point - a).dot(normal) < -epsilon * edge.length:
            return None
    return point


def crossing_segment(first, first_normal, second, second_normal, epsilon):
    """Exact candidate test, excluding coplanar and zero-length contacts."""
    if first_normal is None or second_normal is None:
        return None, "degenerate"
    if first_normal.cross(second_normal).length_squared < 1e-14:
        return None, "parallel_or_coplanar"
    distances_a = [second_normal.dot(p - second[0]) for p in first]
    distances_b = [first_normal.dot(p - first[0]) for p in second]
    if (min(distances_a) > epsilon or max(distances_a) < -epsilon
            or min(distances_b) > epsilon or max(distances_b) < -epsilon):
        return None, "separated"
    # A noncoplanar pair meeting only along an edge of a triangle is tangency,
    # not transverse penetration. Both surfaces must cross the other's plane.
    if (min(distances_a) >= -epsilon or max(distances_a) <= epsilon
            or min(distances_b) >= -epsilon or max(distances_b) <= epsilon):
        return None, "touch_only"
    hits = []
    for a, b, n in ((first, second, second_normal), (second, first, first_normal)):
        for edge in range(3):
            point = segment_triangle(a[edge], a[(edge + 1) % 3], b, n, epsilon)
            if point is not None and all((point - old).length > epsilon for old in hits):
                hits.append(point)
    extent = max(((a - b).length for a in hits for b in hits), default=0.0)
    if extent <= 2 * epsilon:
        return None, "touch_or_outside"
    return extent, "crossing"


def compare(first, second, same, epsilon):
    stats = {"bvh_candidates": 0, "seam_excluded": 0, "adjacent_excluded": 0,
             "exact_tests": 0, "crossings": 0, "maximum_intersection_segment_m": 0.0,
             "triangle_pairs": [], "intersection_segment_lengths_m": [],
             "rejected_candidates": {}}
    # Self BVHs may yield both (a, b) and (b, a); keep one canonical ordering.
    candidates = {(min(a, b), max(a, b)) if same else (a, b)
                  for a, b in first.tree.overlap(second.tree) if not same or a != b}
    for a, b in sorted(candidates):
        stats["bvh_candidates"] += 1
        if first.seam[a] or second.seam[b]:
            stats["seam_excluded"] += 1
            continue
        ia, ib = first.triangles[a], second.triangles[b]
        if same and set(ia).intersection(ib):
            stats["adjacent_excluded"] += 1
            continue
        stats["exact_tests"] += 1
        extent, reason = crossing_segment(
            [first.points[i] for i in ia], first.normals[a],
            [second.points[i] for i in ib], second.normals[b], epsilon)
        if extent is not None:
            stats["crossings"] += 1
            stats["triangle_pairs"].append([a, b])
            stats["intersection_segment_lengths_m"].append(extent)
            stats["maximum_intersection_segment_m"] = max(
                stats["maximum_intersection_segment_m"], extent)
        else:
            rejected = stats["rejected_candidates"]
            rejected[reason] = rejected.get(reason, 0) + 1
    return stats


def audit(args):
    report = {"source_blend": bpy.data.filepath, "surface": args.surface,
              "metres_per_blender_unit": SCALE, "epsilon_m": args.epsilon,
              "method": "BVH candidates and noncoplanar finite segment-triangle intersections",
              "seam_exclusion": "any vertex with positive Sleeve shoulder seam only weight",
              "self_exclusion": "any shared vertex; coplanar and point contacts ignored",
              "saved_blend": False, "clips": {}, "total_crossings": 0}
    for label, prefix in SCENES:
        if args.clip != "all" and args.clip != label.lower():
            continue
        scene = next(scene for scene in bpy.data.scenes if scene.name.startswith(prefix))
        objects = {key: next(obj for obj in scene.objects if obj.get("graduate_role") == role)
                   for key, role in ROLES.items()}
        clip = {"scene": scene.name, "frames": [], "surfaces": {}, "triangle_tables": {},
                "pair_totals": {key: 0 for key, _, _ in PAIRS}, "total_crossings": 0}
        triangulations = {key: {} for key in objects}
        with visible_surfaces(scene, list(objects.values()), args.surface):
            for frame in range(scene.frame_start, scene.frame_end + 1):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                surfaces = {key: Surface(obj) for key, obj in objects.items()}
                if not clip["surfaces"]:
                    clip["surfaces"] = {key: value.metadata for key, value in surfaces.items()}
                else:
                    for key, value in surfaces.items():
                        baseline = clip["surfaces"][key]
                        if (len(value.points) != baseline["vertex_count"]
                                or value.source_polygons != baseline["source_polygons"]):
                            raise RuntimeError(f"Topology changes at {label} frame {frame}: {key}")
                # Blender can choose a different diagonal for the same
                # deforming quad. That is valid tessellation, not a topology
                # change. Pair indices below reference this frame's table.
                table_ids = {}
                for key, value in surfaces.items():
                    signature = tuple(value.triangles)
                    table_id = triangulations[key].get(signature)
                    if table_id is None:
                        table_id = f"{key}_{len(triangulations[key]):03d}"
                        triangulations[key][signature] = table_id
                        clip["triangle_tables"][table_id] = {
                            "surface": key, "first_used_frame": frame,
                            "triangles": value.triangles, "polygon_indices": value.polygons,
                            "excluded_seam_triangles": [i for i, seam in enumerate(value.seam) if seam],
                        }
                    table_ids[key] = table_id
                item = {"frame": frame, "triangle_table_ids": table_ids,
                        "degenerate_triangles": {key: value.degenerate for key, value in surfaces.items()},
                        "pairs": {}, "total_crossings": 0}
                for key, a, b in PAIRS:
                    result = compare(surfaces[a], surfaces[b], a == b, args.epsilon)
                    item["pairs"][key] = result
                    item["total_crossings"] += result["crossings"]
                    clip["pair_totals"][key] += result["crossings"]
                clip["frames"].append(item)
                clip["total_crossings"] += item["total_crossings"]
                if frame % 12 == 0 or item["total_crossings"]:
                    print("SLEEVE_GARMENT_CONTACT", label, frame,
                          {key: item["pairs"][key]["crossings"] for key, _, _ in PAIRS}, flush=True)
        report["clips"][label] = clip
        report["total_crossings"] += clip["total_crossings"]
    report["status"] = "no_transverse_crossings" if report["total_crossings"] == 0 else "crossings_require_review"
    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("SLEEVE_GARMENT_CONTACT_SAVED", str(output), report["status"],
          report["total_crossings"], flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--surface", choices=("rendered", "simulation"), default="rendered")
    parser.add_argument("--clip", choices=("all", "walk", "run", "jumpdown"), default="all")
    parser.add_argument("--epsilon", type=float, default=1e-7, help="Geometric tolerance in metres")
    arguments = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if arguments.epsilon <= 0:
        parser.error("--epsilon must be positive")
    audit(arguments)
