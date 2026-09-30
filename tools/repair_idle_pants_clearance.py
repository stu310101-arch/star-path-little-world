"""Local, cycle-constant lower-gown relief against the actual trousers.

Owner runs the sole Blender process, after the neckline postpass:
 blender -b <candidate.blend> --python-exit-code 1 --python tools/repair_idle_pants_clearance.py -- --output <new.blend>
 --probe-frames 1,51,77 computes corrections and writes JSON only.

All frames share one nonnegative scalar relief per gown vertex, rotated only
by the measured Body yaw. This cannot restore the breathing-driven skirt
balloon. Only actual finite trousers intersections seed constraints; their
outward triangle planes create local clearance. No body proxies/caps, seam
exclusions, rig changes, or global skirt-width scaling are used. Guardrails
and unresolved contacts are reported, never relabelled as successful seams.
"""
from __future__ import annotations
import argparse
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from simulate_portal_cloth import SkinBinding, evaluated_points
from simulate_sleeve_cloth import bake_loop
from repair_graduate_regalia import anchors, deform, triangles, bar_points
from repair_idle_gown_hang import (BODY, GOWN, body_yaw, rotation_2d, rig_hash,
    other_clip_hashes, lower_body_faces, clear_hanging_stole, width_profile)
from postprocess_regalia_layers import array_surface, compact_crossings
from validate_sleeve_garment_contact import compare, Surface, visible_surfaces, segment_triangle


def topology_placket_pairs(mesh):
    """Use authored ring/column edge connectivity, not deformed rest positions."""
    n = len(mesh.vertices)
    grid_end = (n // 48) * 48
    adjacent = [set() for _ in range(n)]
    for polygon in mesh.polygons:
        ids = list(polygon.vertices)
        for a, b in zip(ids, ids[1:] + ids[:1]):
            adjacent[a].add(b)
            adjacent[b].add(a)
    pairs, unresolved = [], []
    for duplicate in range(grid_end, n):
        right = [v for v in adjacent[duplicate] if v < grid_end and v % 48 == 37]
        if len(right) == 1 and right[0] - 1 < grid_end:
            pairs.append((right[0] - 1, duplicate))
        else:
            unresolved.append({'duplicate': duplicate, 'right_column_neighbors': sorted(right)})
    return pairs, unresolved


def contact_details(points, faces, body_surface, result):
    examples = []
    for (a, b), extent in zip(result['triangle_pairs'], result['intersection_segment_lengths_m']):
        cloth = [Vector(points[i]) for i in faces[a]]
        target = [body_surface.points[i] for i in body_surface.triangles[b]]
        normal = body_surface.normals[b]
        hits = [segment_triangle(cloth[j], cloth[(j + 1) % 3], target, normal, 1e-6) for j in range(3)]
        hits = [p for p in hits if p is not None]
        point = np.mean([tuple(p) for p in hits], axis=0) if hits else np.mean(points[list(faces[a])], axis=0)
        examples.append({'gown_triangle': int(a), 'gown_vertices': list(faces[a]),
                         'body_triangle': int(b), 'body_vertices': list(body_surface.triangles[b]),
                         'point_m': point.tolist(), 'intersection_segment_m': extent,
                         'body_outward_normal': list(normal)})
    return examples


def points_with_relief(row, envelope):
    return row['gown'] + row['directions'] * envelope[:, None]


def grow_relief(row, faces, envelope, movable, margin, maximum):
    """Conservative local half-space constraints from finite crossing pairs.

    The pair has already passed exact finite-triangle intersection tests.
    Making its three cloth vertices lie outside the actual body face is a
    sufficient separating condition, not a claim based on nearest samples.
    Only outward-directed constraints are accepted; incompatible/capped
    constraints stay visible in the final exact report.
    """
    points = points_with_relief(row, envelope)
    surface = array_surface(points, faces)
    contacts = compare(surface, row['pants'], False, 1e-6)
    proposal = envelope.copy()
    blocked = []
    for a, b in contacts['triangle_pairs']:
        normal = np.asarray(row['pants'].normals[b])
        origin = np.asarray(row['pants'].points[row['pants'].triangles[b][0]])
        for vertex in faces[a]:
            distance = float(np.dot(points[vertex] - origin, normal))
            if distance >= margin:
                continue
            factor = float(np.dot(row['directions'][vertex], normal))
            if not movable[vertex] or factor <= .15:
                blocked.append({'vertex': int(vertex), 'triangle': int(a), 'body_triangle': int(b),
                                'signed_distance_m': distance, 'outward_alignment': factor})
                continue
            required = (margin - distance) / factor
            proposal[vertex] = max(proposal[vertex], min(maximum, envelope[vertex] + required))
    return proposal, contacts, blocked


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--probe-frames')
    parser.add_argument('--margin', type=float, default=.003)
    parser.add_argument('--maximum-relief', type=float, default=.020)
    parser.add_argument('--passes', type=int, default=8)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    output = args.output.resolve()
    if output == Path(bpy.data.filepath).resolve():
        raise ValueError('Separate output required')
    if not (.0015 <= args.margin <= .005 and .001 <= args.maximum_relief <= .030 and 1 <= args.passes <= 24):
        raise ValueError('Expected fabric-scale margin and bounded local relief')
    scene = next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
    if scene.frame_start != 1:
        raise ValueError('Loop baker requires frame_start=1; refusing to retime')
    timing = (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
    period = scene.frame_end
    frames = [int(x) for x in args.probe_frames.split(',')] if args.probe_frames else list(range(1, period + 1))
    if any(f < 1 or f > period for f in frames):
        raise ValueError('Probe outside authored Idle cycle')
    roles = {o.get('graduate_role'): o for o in scene.objects if o.type == 'MESH' and o.get('graduate_role') and not o.get('preview_fx')}
    gown, body = roles[GOWN], roles[BODY]
    rig = next(o for o in scene.objects if o.type == 'ARMATURE')
    front = {r: o for r, o in roles.items() if r.startswith('03 |') and r.endswith((' L', ' R'))}
    bars = {r: o for r, o in roles.items() if r.startswith('04 |')}
    objects = [gown, *front.values(), *bars.values()]
    faces = triangles(gown)
    fronts_faces = {r: triangles(o) for r, o in front.items()}
    rest = np.asarray([v.co[:] for v in gown.data.vertices])
    # The newly detected right thigh patch lies well below this boundary.
    movable = rest[:, 2] < 3.0
    waist_mask = np.abs(rest[:, 2] - 3.0) <= .15
    bands = {'hem': rest[:, 2] < np.min(rest[:, 2]) + .12,
             'knee': (rest[:, 2] >= 1.65) & (rest[:, 2] < 2.0),
             'hip_lower': (rest[:, 2] >= 2.15) & (rest[:, 2] < 2.4),
             'waist_blend': (rest[:, 2] >= 2.65) & (rest[:, 2] < 2.95)}
    placket, ambiguous = topology_placket_pairs(gown.data)
    selected_body = lower_body_faces(body, 3.15)
    pants_faces = selected_body['pants_legs']
    if not pants_faces:
        raise ValueError('Actual trousers triangles not found')
    before_other, before_rig = other_clip_hashes(), rig_hash(rig)
    report = {'source_blend': bpy.data.filepath, 'output': str(output), 'complete': False,
              'probe_only': bool(args.probe_frames), 'method': 'One cycle-constant local radial relief per vertex from exact actual-trousers intersections',
              'margin_m': args.margin, 'maximum_relief_limit_m': args.maximum_relief,
              'no_seam_contacts_removed': True, 'placket_vertex_pairs': placket,
              'placket_unresolved_topology': ambiguous, 'actual_pants_faces': len(pants_faces),
              'timing_before': timing, 'passes': [], 'frames': []}
    report_path = args.report or output.with_suffix('.pants-clearance.json')
    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    started = time.perf_counter()
    bindings = {obj: SkinBinding(obj, rig) for obj in objects}
    rows = []
    with visible_surfaces(scene, [body, *objects], 'simulation'):
        scene.frame_set(1)
        bpy.context.view_layer.update()
        neutral = evaluated_points(gown)
        waist0 = np.mean(neutral[waist_mask], axis=0)
        yaw0 = body_yaw(rig)
        directions0 = neutral.copy() * 0.
        directions0[:, :2] = neutral[:, :2] - waist0[:2]
        directions0 /= np.maximum(np.linalg.norm(directions0, axis=1), 1e-12)[:, None]
        for frame in frames:
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            posed = {obj: evaluated_points(obj) for obj in objects}
            yaw = body_yaw(rig)
            directions = directions0.copy()
            directions[:, :2] = directions[:, :2] @ rotation_2d(yaw - yaw0).T
            body_points = evaluated_points(body)
            torso = rig.pose.bones['Torso']
            forward = rig.matrix_world.to_3x3() @ torso.matrix.to_3x3() @ torso.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0))
            rows.append({'frame': frame, 'gown': posed[gown], 'posed': posed, 'yaw': yaw,
                         'directions': directions, 'waist': np.mean(posed[gown][waist_mask], axis=0),
                         'pants': array_surface(body_points, pants_faces),
                         'skin': array_surface(body_points, selected_body['skin']) if selected_body['skin'] else None,
                         'forward': np.asarray(forward.normalized())})
        envelope = np.zeros(len(rest))
        for iteration in range(args.passes):
            old = envelope.copy()
            crossings, blocks = 0, []
            for row in rows:
                envelope, contacts, blocked = grow_relief(row, faces, envelope, movable, args.margin, args.maximum_relief)
                crossings += contacts['crossings']
                blocks.extend({'frame': row['frame'], **b} for b in blocked)
            entry = {'pass': iteration + 1, 'crossings_seen_before_each_update': crossings,
                     'maximum_relief_m': float(np.max(envelope)), 'changed_vertices': int(np.count_nonzero(envelope)),
                     'maximum_pass_change_m': float(np.max(envelope - old)), 'blocked_constraints': blocks[:100]}
            report['passes'].append(entry)
            checkpoint()
            print('IDLE_PANTS_PASS', iteration + 1, crossings, entry['maximum_relief_m'], entry['changed_vertices'], flush=True)
            if np.max(envelope - old) < 1e-8:
                break
        report['relief_by_vertex_m'] = {str(i): float(v) for i, v in enumerate(envelope) if v > 0}
        report['capped_vertices'] = np.flatnonzero(envelope >= args.maximum_relief - 1e-8).tolist()
        samples = {obj: [] for obj in objects}
        for row in rows:
            frame = row['frame']
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            corrected = points_with_relief(row, envelope)
            if not np.array_equal(corrected[~movable], row['gown'][~movable]):
                raise AssertionError('Upper gown changed')
            posed = {obj: points.copy() for obj, points in row['posed'].items()}
            posed[gown] = corrected
            before = compare(array_surface(row['gown'], faces), row['pants'], False, 1e-6)
            surface = array_surface(corrected, faces)
            after = compare(surface, row['pants'], False, 1e-6)
            stole_report = {}
            for role, obj in front.items():
                original = row['posed'][obj]
                centers = np.asarray([np.mean(original[i:min(i + 4, len(original))], axis=0) for i in range(0, len(original), 4)])
                links = anchors(centers, row['gown'], faces, .0045, True)
                delta = deform(links, corrected) - deform(links, row['gown'])
                for ri in range(3, len(centers)):
                    posed[obj][4 * ri:min(4 * ri + 4, len(original))] += delta[ri]
                lower_faces = [face for face in fronts_faces[role] if any(v >= 12 for v in face)]
                before_clear = compact_crossings(array_surface(posed[obj], lower_faces), surface)
                clearance = {'maximum_shift_m': 0., 'not_needed': True}
                if before_clear['crossings']:
                    posed[obj], clearance = clear_hanging_stole(posed[obj], fronts_faces[role], corrected, faces, np.array([0., 0., 0.] + [1.] * 8))
                if not np.array_equal(posed[obj][:12], original[:12]):
                    raise AssertionError('Upper sewn stole changed')
                stole_report[role] = {'gown': compact_crossings(array_surface(posed[obj], lower_faces), surface),
                                      'clearance': clearance,
                                      'maximum_change_m': float(np.max(np.linalg.norm(posed[obj] - original, axis=1)))}
            for role, obj in bars.items():
                side = role.rsplit(' ', 1)[1][0]
                parent = next(o for r, o in front.items() if r.endswith(' ' + side))
                if not np.array_equal(posed[parent], row['posed'][parent]):
                    posed[obj] = bar_points(posed[parent], int(role[-1]), row['forward'])
            entry = {'frame': frame, 'pants_before': {k: v for k, v in before.items() if k not in ('triangle_pairs', 'intersection_segment_lengths_m')},
                     'pants_after': {k: v for k, v in after.items() if k not in ('triangle_pairs', 'intersection_segment_lengths_m')},
                     'before_contact_details': contact_details(row['gown'], faces, row['pants'], before),
                     'after_contact_details': contact_details(corrected, faces, row['pants'], after),
                     'gown_self': compact_crossings(surface, surface, True),
                     'lower_skin': compact_crossings(surface, row['skin']) if row['skin'] else {'crossings': 0, 'selected_actual_skin_faces': 0},
                     'lower_stoles': stole_report,
                     'before_profile': width_profile(row['gown'], row['waist'], row['yaw'], bands, placket),
                     'after_profile': width_profile(corrected, row['waist'], row['yaw'], bands, placket),
                     'upper_gown_and_sewn_stole_exactly_preserved': True}
            report['frames'].append(entry)
            if not args.probe_frames:
                for obj in objects:
                    samples[obj].append(np.asarray(bindings[obj].inverse_points(posed[obj])))
            checkpoint()
            print('IDLE_PANTS_FRAME', frame, before['crossings'], after['crossings'], entry['gown_self']['crossings'], flush=True)
        if not args.probe_frames:
            for obj in objects:
                if obj.data.users > 1:
                    obj.data = obj.data.copy()
                bake_loop(obj, samples[obj], 'Idle stable local trousers clearance | ' + obj.get('graduate_role'))
    if before_rig != rig_hash(rig) or timing != (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base):
        raise AssertionError('Skeleton/timing changed')
    if before_other != other_clip_hashes():
        raise AssertionError('Non-Idle clip changed')
    report['skeleton_timing_other_clips_preserved'] = True
    report['rendered_pants_after'] = []
    if not args.probe_frames:
        with visible_surfaces(scene, [gown, body], 'rendered'):
            for row in rows:
                scene.frame_set(row['frame'])
                bpy.context.view_layer.update()
                actual = Surface(gown)
                actual.seam = [False] * len(actual.triangles)
                pants = array_surface(evaluated_points(body), pants_faces)
                stats = compact_crossings(actual, pants)
                report['rendered_pants_after'].append({'frame': row['frame'], **stats})
            scene.frame_set(1)
            bpy.context.view_layer.update()
            first = evaluated_points(gown)
            scene.frame_set(period + 1)
            bpy.context.view_layer.update()
            seam = float(np.max(np.linalg.norm(evaluated_points(gown) - first, axis=1)))
        if seam > 1e-5:
            raise AssertionError('Loop seam not closed')
        report['rendered_gown_loop_seam_m'] = seam
        bpy.context.window.scene = scene
        scene.frame_set(1)
        bpy.context.preferences.filepaths.save_version = 0
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report['all_actual_midpoint_contacts_clear'] = all(f['pants_after']['crossings'] == 0 and f['gown_self']['crossings'] == 0 and f['lower_skin']['crossings'] == 0 and all(s['gown']['crossings'] == 0 for s in f['lower_stoles'].values()) for f in report['frames'])
    report['all_rendered_pants_contacts_clear'] = None if args.probe_frames else all(f['crossings'] == 0 for f in report['rendered_pants_after'])
    report['asset_saved'] = not bool(args.probe_frames)
    report['complete'] = True
    report['seconds'] = round(time.perf_counter() - started, 3)
    checkpoint()
    print('IDLE_PANTS_DONE', str(output), report['all_actual_midpoint_contacts_clear'], report['all_rendered_pants_contacts_clear'], report['seconds'], flush=True)


if __name__ == '__main__':
    main()
