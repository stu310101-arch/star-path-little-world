"""Read-only rendered intersection audit for every graduate mesh pair.

Example (run by the owner of the single background Blender process):
 blender -b <candidate.blend> --python-exit-code 1 --python tools/audit_regalia_pairs.py -- \
   --scene-prefix 04_IDLE 01_WALK 02_RUN 03_JUMP --sample-count 5 --output <new.json>

Use --stride 1 for all integer frames, optionally --half-frames. --frames
1,51,91 selects explicit frames instead. No asset is saved or modified on disk.
All exact crossings are counted, including seams. Connection tags and shell
layers are descriptive, not exclusions. External ray reachability is a
visibility probe, not proof of visible pixels or penetration depth. Occluded
contacts remain in the report. Hand inspection of worst frames is required.
"""
from __future__ import annotations

import argparse
from collections import Counter
import itertools
import json
import math
from pathlib import Path
import sys
import time

import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from validate_sleeve_garment_contact import Surface, visible_surfaces, compare, segment_triangle

_SOURCE_POLYGON_CACHE = {}


def bounds(points):
    return [[min(p[d] for p in points), max(p[d] for p in points)] for d in range(3)] if points else None


def overlap(a, b):
    return all(a[d][0] <= b[d][1] and b[d][0] <= a[d][1] for d in range(3))


def frame_samples(scene, args):
    start, end = scene.frame_start, scene.frame_end
    mapped = next((value for prefix, value in args.scene_frames.items() if scene.name.startswith(prefix)), None)
    if mapped:
        frames = [float(value) for value in mapped.split(',')]
    elif args.frames:
        frames = [float(value) for value in args.frames.split(',')]
    elif args.stride:
        frames = list(range(start, end + 1, args.stride)) + [end]
    else:
        # Include the inhale extremum as well as evenly spaced representatives.
        frames = [round(start + (end - start) * i / max(args.sample_count - 1, 1))
                  for i in range(args.sample_count)]
        if scene.name.startswith('04_IDLE'):
            frames += [51]
    # Authored loops explicitly repeat their first pose at end + 1. Include
    # requested samples in that final interpolation interval as well.
    last_valid = end + 1 if scene.name.startswith(('01_WALK', '02_RUN', '04_IDLE')) else end
    frames = sorted({f for f in frames if start <= f <= last_valid})
    if args.half_frames:
        frames = sorted(set(frames + [f + .5 for f in frames if f + .5 <= last_valid]))
    return frames


def set_frame(scene, frame):
    whole = math.floor(frame)
    scene.frame_set(whole, subframe=frame - whole)
    bpy.context.view_layer.update()


def source_polygon_maps(mesh):
    """Cache source faces and unambiguous triangles of their vertex sets.

    A preceding Triangulate modifier splits source quads/ngons without adding
    vertices. Retain the existing exact-face lookup first; a triangle shared
    by multiple source polygons deliberately maps to None in the fallback.
    This read-only audit never changes source topology during its lifetime.
    """
    key = (mesh.as_pointer(), len(mesh.vertices), len(mesh.polygons))
    if key not in _SOURCE_POLYGON_CACHE:
        exact = {tuple(sorted(poly.vertices)): poly.index for poly in mesh.polygons}
        triangles = {}
        for poly in mesh.polygons:
            for triple in itertools.combinations(sorted(set(poly.vertices)), 3):
                if triple not in triangles:
                    triangles[triple] = poly.index
                elif triangles[triple] != poly.index:
                    triangles[triple] = None
        _SOURCE_POLYGON_CACHE[key] = exact, triangles
    return _SOURCE_POLYGON_CACHE[key]


def classify_source(surface, obj):
    n = len(obj.data.vertices)
    lookup, triangle_lookup = source_polygon_maps(obj.data)
    polygons = {}
    solid = next((m for m in obj.modifiers if m.type == 'SOLIDIFY' and m.show_viewport), None)
    for i, ids in enumerate(surface.source_polygons):
        canonical = tuple(sorted(set(v % n for v in ids))) if solid else tuple(sorted(ids))
        original = lookup.get(canonical)
        if original is None and len(canonical) == 3:
            original = triangle_lookup.get(canonical)
        if solid and all(v < n for v in ids):
            layer = 'original_layer'
        elif solid and all(n <= v < 2 * n for v in ids):
            layer = 'solidify_duplicate'
        elif solid:
            layer = 'solidify_rim_or_other'
        else:
            layer = 'single_surface' if original is not None else 'modified_surface'
        material = None
        if original is not None:
            slot = obj.data.polygons[original].material_index
            if slot < len(obj.material_slots) and obj.material_slots[slot].material:
                material = obj.material_slots[slot].material.name
        polygons[i] = {'source_polygon': original, 'layer': layer, 'material': material}
    surface.source_map = polygons
    surface.bounds = bounds(surface.points)
    surface.original_seam = surface.seam[:]
    # Existing compare() excludes every sewn vertex face. This audit does not.
    surface.seam = [False] * len(surface.seam)
    surface.extra_metadata = {
        'vertices': len(surface.points), 'triangles': len(surface.triangles),
        'source_vertices': n,
        'solidify': {'offset': solid.offset, 'thickness_model': solid.thickness} if solid else None,
        'bounds_m': surface.bounds,
    }


def contact_points(a, ia, b, ib, epsilon):
    ta = [a.points[v] for v in a.triangles[ia]]
    tb = [b.points[v] for v in b.triangles[ib]]
    hits = []
    for tri, other, normal in ((ta, tb, b.normals[ib]), (tb, ta, a.normals[ia])):
        for edge in range(3):
            point = segment_triangle(tri[edge], tri[(edge + 1) % 3], other, normal, epsilon)
            if point is not None and all((point - old).length > epsilon for old in hits):
                hits.append(point)
    return hits


def relation(a, ia, b, ib, seam_faces):
    ra, rb = a.metadata['role'], b.metadata['role']
    if ra == rb:
        return 'self_intersection'
    if 'Bell sleeve' in ra and rb == '01 | Pleated bachelor gown':
        polygon = b.source_map[b.polygons[ib]]['source_polygon']
        if polygon in seam_faces:
            return 'documented_armhole_join_region'
    if 'Bell sleeve' in rb and ra == '01 | Pleated bachelor gown':
        return relation(b, ib, a, ia, seam_faces)
    if a.original_seam[ia] or b.original_seam[ib]:
        return 'pinned_sleeve_attachment_region'
    roles = (ra, rb)
    if all(r.startswith(('06 |', '07 |', '08 |')) for r in roles):
        return 'cap_assembly_contact_review'
    if all(r.startswith(('09 |', '10 |', '11 |')) for r in roles):
        return 'tassel_assembly_contact_review'
    if any(r.startswith('09 |') for r in roles) and any(r.startswith(('07 |', '08 |')) for r in roles):
        return 'tassel_anchor_contact_review'
    if any('Stole woven bar' in r for r in roles) and any('stole' in r.lower() and 'woven' not in r for r in roles):
        return 'applied_stole_trim_review'
    if all(r.startswith('05 |') for r in roles):
        return 'shirt_layer_contact_review'
    return 'independent_surface_contact'


def ray_directions():
    # Eight azimuths at horizontal and two elevations; outside the character.
    return [Vector((math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e)))
            for e in (0, math.radians(35), math.radians(-25))
            for a in [i * math.tau / 8 for i in range(8)]]


def audit_frame(scene, frame, objects, seam_faces, args):
    bpy.context.window.scene = scene
    set_frame(scene, frame)
    originally_rendered = {o.get('graduate_role'): not o.hide_render for o in objects}
    with visible_surfaces(scene, objects, args.surface):
        set_frame(scene, frame)
        surfaces = [Surface(obj) for obj in objects]
        for surface, obj in zip(surfaces, objects):
            classify_source(surface, obj)
        combined_points, combined_triangles = [], []
        for surface in surfaces:
            if not originally_rendered[surface.metadata['role']]:
                continue
            offset = len(combined_points)
            combined_points += surface.points
            combined_triangles += [tuple(v + offset for v in t) for t in surface.triangles]
        tree = BVHTree.FromPolygons(combined_points, combined_triangles, all_triangles=True) if combined_triangles else None
        directions = ray_directions()
        entries = []
        checked_pairs = 0
        for i, j in itertools.combinations_with_replacement(range(len(surfaces)), 2):
            a, b = surfaces[i], surfaces[j]
            if not overlap(a.bounds, b.bounds):
                continue
            checked_pairs += 1
            evidence = compare(a, b, i == j, args.epsilon)
            if not evidence['crossings']:
                continue
            relation_counts, visible_relation_counts, layer_counts, material_counts = Counter(), Counter(), Counter(), Counter()
            relation_points, external_relation_points, relation_rings, external_relation_rings = {}, {}, {}, {}
            all_points, visible_points, records = [], [], []
            rendered_pair = originally_rendered[a.metadata['role']] and originally_rendered[b.metadata['role']]
            visible_count = 0
            for (ia, ib), length in zip(evidence['triangle_pairs'], evidence['intersection_segment_lengths_m']):
                hits = contact_points(a, ia, b, ib, args.epsilon)
                if not hits:
                    raise RuntimeError('Exact crossing lacks recoverable intersection points')
                point = sum(hits, Vector()) / len(hits)
                all_points += hits
                kind = relation(a, ia, b, ib, seam_faces)
                relation_counts[kind] += 1
                relation_points.setdefault(kind, []).extend(hits)
                sleeve_rings = []
                for mesh, triangle_id in ((a, ia), (b, ib)):
                    if 'Bell sleeve' in mesh.metadata['role'] and mesh.extra_metadata['source_vertices'] == 545:
                        sleeve_rings.extend((v % 545) // 32 for v in mesh.triangles[triangle_id])
                relation_rings.setdefault(kind, set()).update(sleeve_rings)
                ap = a.source_map[a.polygons[ia]]
                bp = b.source_map[b.polygons[ib]]
                layer = ap['layer'] + ' / ' + bp['layer']
                layer_counts[layer] += 1
                material_pair = str(ap['material']) + ' / ' + str(bp['material'])
                material_counts[material_pair] += 1
                reached = []
                if tree is not None and rendered_pair:
                    for di, direction in enumerate(directions):
                        origin = point + direction * 3
                        hit, normal, triangle, distance = tree.ray_cast(origin, -direction, 3.01)
                        if hit is not None and abs(distance - 3) <= args.visibility_tolerance:
                            reached.append(di)
                if reached:
                    visible_count += 1
                    visible_relation_counts[kind] += 1
                    visible_points += hits
                    external_relation_points.setdefault(kind, []).extend(hits)
                    external_relation_rings.setdefault(kind, set()).update(sleeve_rings)
                records.append({'triangles': [ia, ib], 'source_polygons': [ap['source_polygon'], bp['source_polygon']],
                                'relation': kind, 'layers': layer, 'point_m': list(point),
                                'materials': material_pair, 'sleeve_rings': sorted(set(sleeve_rings)),
                                'segment_length_m': length, 'external_ray_directions': reached})
            records.sort(key=lambda x: (not bool(x['external_ray_directions']), -x['segment_length_m']))
            entries.append({'roles': [a.metadata['role'], b.metadata['role']],
                            'raw_crossings': evidence['crossings'], 'external_ray_reachable_crossings': visible_count,
                            'both_objects_rendered': rendered_pair, 'relation_counts': dict(relation_counts),
                            'external_reachable_relation_counts': dict(visible_relation_counts), 'layer_counts': dict(layer_counts),
                            'material_counts': dict(material_counts),
                            'relation_contact_bbox_xyz_m': {kind: bounds(points) for kind, points in relation_points.items()},
                            'external_relation_contact_bbox_xyz_m': {kind: bounds(points) for kind, points in external_relation_points.items()},
                            'relation_sleeve_rings': {kind: sorted(rings) for kind, rings in relation_rings.items()},
                            'external_relation_sleeve_rings': {kind: sorted(rings) for kind, rings in external_relation_rings.items()},
                            'contact_bbox_xyz_m': bounds(all_points), 'external_contact_bbox_xyz_m': bounds(visible_points),
                            'maximum_intersection_segment_m': evidence['maximum_intersection_segment_m'],
                            'examples': records[:args.max_examples], 'examples_total': len(records)})
        return {'frame': frame, 'broadphase_pairs_checked': checked_pairs,
                'surface_metadata': {s.metadata['role']: s.extra_metadata for s in surfaces},
                'raw_crossings': sum(p['raw_crossings'] for p in entries),
                'external_ray_reachable_crossings': sum(p['external_ray_reachable_crossings'] for p in entries),
                'pairs': entries}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scene-prefix', nargs='+', default=['04_IDLE', '01_WALK', '02_RUN', '03_JUMP'])
    parser.add_argument('--frames', help='Comma-separated frame positions; overrides stride/sample count')
    parser.add_argument('--samples', nargs='*', default=[], help='Per-scene frames, e.g. 04_IDLE=1,51,91 01_WALK=9')
    parser.add_argument('--sample-count', type=int, default=5)
    parser.add_argument('--stride', type=int, default=0)
    parser.add_argument('--half-frames', action='store_true')
    parser.add_argument('--max-examples', type=int, default=24)
    parser.add_argument('--epsilon', type=float, default=1e-6)
    parser.add_argument('--visibility-tolerance', type=float, default=.0005)
    parser.add_argument('--surface', choices=['rendered', 'simulation'], default='rendered')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    args.scene_frames = dict(value.split('=', 1) for value in args.samples)
    if args.sample_count < 1 or args.stride < 0 or args.max_examples < 0:
        parser.error('sample count positive, stride and example limit nonnegative')
    started = time.perf_counter()
    report = {'source_blend': bpy.data.filepath, 'saved_blend': False, 'complete': False, 'surface': args.surface,
              'method': 'Exact transverse triangle intersections on evaluated meshes; no seam exclusions',
              'visibility_method': 'Contact midpoint ray reachability from 24 external directions through all rendered character meshes',
              'visibility_limit': 'Sampled geometric reachability only; small hidden contacts or other viewpoints can differ. Not pixel visibility or penetration depth.',
              'example_limit_per_pair': args.max_examples, 'visibility_tolerance_m': args.visibility_tolerance,
              'clips': {}}
    jump = next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
    gown = next(o for o in jump.objects if o.get('graduate_role') == '01 | Pleated bachelor gown')
    seam_faces = {p.index for p in gown.data.polygons if p.center.z > 3.05 and abs(p.center.x) > .34}
    original_scene = bpy.context.window.scene
    scene_frames = {s: (s.frame_current, s.frame_subframe) for s in bpy.data.scenes}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    try:
        for prefix in args.scene_prefix:
            scene = next(s for s in bpy.data.scenes if s.name.startswith(prefix))
            objects = sorted([o for o in scene.objects if o.type == 'MESH' and o.get('graduate_role')
                              and o.get('graduate_role') != 'Studio floor' and not o.get('preview_fx')],
                             key=lambda o: o.get('graduate_role'))
            entries = []
            report['clips'][scene.name] = entries
            for frame in frame_samples(scene, args):
                entry = audit_frame(scene, frame, objects, seam_faces, args)
                entries.append(entry)
                report['elapsed_seconds'] = time.perf_counter() - started
                args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
                print('REGALIA_PAIR_AUDIT', scene.name, frame, 'raw', entry['raw_crossings'],
                      'external', entry['external_ray_reachable_crossings'], 'seconds', round(report['elapsed_seconds'], 2), flush=True)
        report['complete'] = True
        report['elapsed_seconds'] = time.perf_counter() - started
        args.output.write_text(json.dumps(report, indent=2), encoding='utf-8')
    finally:
        for scene, (frame, subframe) in scene_frames.items():
            scene.frame_set(frame, subframe=subframe)
        bpy.context.window.scene = original_scene
    print('REGALIA_PAIR_AUDIT_DONE', str(args.output), flush=True)


if __name__ == '__main__':
    main()
