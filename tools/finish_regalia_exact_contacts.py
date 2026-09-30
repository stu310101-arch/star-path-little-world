"""Targeted exact-intersection finishing; preserve existing animation keys.

 blender -b <Pants_Candidate.blend> --python-exit-code 1 --python tools/finish_regalia_exact_contacts.py -- --output <new.blend>
Defaults: Walk 5/13/24, Run 1/22. --probe writes only JSON. --samples accepts
PREFIX=frame,frame pairs. New additive corrective keys have zero value at all
other integer frames; existing keys/actions and unaffected objects are kept.
Actual finite intersection endpoints/midpoints create persistent barycentric
outward clearance constraints. Gown vertices are local to the neck; stoles
translate complete four-column rows, sharing both sewn collar endpoints.
No dense-grid success assumption and no removal of seam crossing counts.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

import bpy
import numpy as np
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from simulate_portal_cloth import SkinBinding, evaluated_points, fcurves
from repair_graduate_regalia import triangles, bar_points
from repair_idle_gown_hang import BODY, GOWN, rig_hash
from regalia_neck_clearance import build_neck_collider, _barycentric
from postprocess_regalia_layers import array_surface, compact_crossings, exact_neck_report
from validate_sleeve_garment_contact import compare, segment_triangle, visible_surfaces


def intersection_constraints(points, faces, target, margin):
    surface = array_surface(points, faces)
    stats = compare(surface, target, False, 1e-6)
    constraints, examples = [], []
    for a, b in stats['triangle_pairs']:
        ids = tuple(faces[a])
        first = [surface.points[i] for i in ids]
        second = [target.points[i] for i in target.triangles[b]]
        normal = target.normals[b]
        hits = []
        for x, y, n in ((first, second, normal), (second, first, surface.normals[a])):
            for edge in range(3):
                p = segment_triangle(x[edge], x[(edge + 1) % 3], y, n, 1e-6)
                if p is not None and all((p - q).length > 1e-6 for q in hits):
                    hits.append(p)
        if not hits:
            continue
        samples = hits + [sum(hits, Vector((0, 0, 0))) / len(hits)]
        for p in samples:
            weights = _barycentric(np.asarray(p), points[list(ids)])
            if weights is None:
                continue
            weights = np.clip(weights, 0., 1.)
            weights /= np.sum(weights)
            constraints.append((ids, weights, np.asarray(normal), float(normal.dot(p)) + margin))
        examples.append({'cloth_triangle': int(a), 'cloth_vertices': list(ids),
                         'target_triangle': int(b), 'target_vertices': list(target.triangles[b]),
                         'intersection_points_m': [list(p) for p in hits], 'normal': list(normal)})
    return constraints, stats['crossings'], examples


def exact_project(base, faces, groups, targets, *, margin=.0025, maximum=.012, iterations=64):
    """Small PBD solve using exact crossing positions and persistent planes."""
    base = np.asarray(base, dtype=float)
    current = base.copy()
    group_ids = np.full(len(base), -1, dtype=int)
    for gid, vertices in enumerate(groups):
        group_ids[vertices] = gid
    shift = np.zeros((len(groups), 3))
    fixed_constraints, lookup, first_examples = [], set(), {}
    face_array = np.asarray(faces, dtype=np.int32)
    original_normals = np.cross(base[face_array[:, 1]] - base[face_array[:, 0]], base[face_array[:, 2]] - base[face_array[:, 0]])
    original_area = np.linalg.norm(original_normals, axis=1)
    units = original_normals / np.maximum(original_area[:, None], 1e-16)
    valid = original_area > 1e-11
    capped, blocked, rejected = set(), 0, 0
    histories = []
    for iteration in range(iterations):
        counts_now = {}
        for label, target in targets.items():
            fresh, count, examples = intersection_constraints(current, faces, target, margin)
            counts_now[label] = count
            if examples and label not in first_examples:
                first_examples[label] = examples
            for ids, weights, normal, offset in fresh:
                # Persist discovered actual contact locations even after a
                # later iteration has separated that particular face pair.
                key = (label, ids, tuple(np.round(weights, 5)), tuple(np.round(normal, 5)))
                if key not in lookup:
                    lookup.add(key)
                    fixed_constraints.append((ids, weights, normal, offset))
        sums, counts = np.zeros_like(shift), np.zeros(len(groups))
        worst = 0.
        for ids, weights, normal, offset in fixed_constraints:
            need = offset - float(np.dot(weights @ current[list(ids)], normal))
            if need <= .00001:
                continue
            distribution = {}
            for vertex, weight in zip(ids, weights):
                gid = int(group_ids[vertex])
                if gid >= 0:
                    distribution[gid] = distribution.get(gid, 0.) + float(weight)
            denom = sum(w * w for w in distribution.values())
            if denom < 1e-12:
                blocked += 1
                continue
            worst = max(worst, need)
            for gid, weight in distribution.items():
                sums[gid] += normal * need * weight / denom
                counts[gid] += 1
        histories.append({'iteration': iteration, 'crossings': counts_now, 'worst_constraint_gap_m': worst})
        if not np.any(counts):
            break
        step = np.zeros_like(shift)
        active = counts > 0
        step[active] = sums[active] / counts[active, None]
        step *= np.minimum(1., .0015 / np.maximum(np.linalg.norm(step, axis=1), 1e-16))[:, None]
        proposed = shift + step
        lengths = np.linalg.norm(proposed, axis=1)
        capped.update(int(i) for i in np.flatnonzero(lengths > maximum))
        proposed *= np.minimum(1., maximum / np.maximum(lengths, 1e-16))[:, None]
        accepted = False
        for factor in (1., .5, .25, .125, .0625):
            attempt = shift + factor * (proposed - shift)
            candidate = base.copy()
            for gid, vertices in enumerate(groups):
                candidate[vertices] += attempt[gid]
            normals = np.cross(candidate[face_array[:, 1]] - candidate[face_array[:, 0]], candidate[face_array[:, 2]] - candidate[face_array[:, 0]])
            areas = np.einsum('ij,ij->i', normals, units)
            if np.all(areas[valid] > original_area[valid] * .04):
                accepted = True
                break
            rejected += 1
        if not accepted:
            break
        movement = float(np.max(np.linalg.norm(candidate - current, axis=1)))
        shift, current = attempt, candidate
        if movement < 1e-8:
            break
    final = {label: compact_crossings(array_surface(current, faces), target) for label, target in targets.items()}
    return current, {'initial_exact_examples': first_examples, 'iterations': histories,
                     'remaining': final, 'maximum_movement_m': float(np.max(np.linalg.norm(current - base, axis=1))),
                     'capped_groups': sorted(capped), 'blocked_fixed_constraints': blocked,
                     'orientation_rejected_steps': rejected, 'contact_constraints': len(fixed_constraints)}


def sewn_row_groups(posed, faces):
    left = next(r for r in posed if r.endswith(' L'))
    right = next(r for r in posed if r.endswith(' R'))
    back = next(r for r in posed if 'back collar' in r)
    names = [left, right, back]
    offsets, cursor = {}, 0
    for role in names:
        offsets[role] = cursor
        cursor += len(posed[role])
    def row(role, n):
        return list(range(offsets[role] + 4 * n, offsets[role] + min(4 * n + 4, len(posed[role]))))
    groups = [row(left, 0) + row(back, 0), row(right, 0) + row(back, 12)]
    groups += [row(role, n) for role in (left, right) for n in range(1, 11)]
    groups += [row(back, n) for n in range(1, 12)]
    combined = np.concatenate([posed[role] for role in names])
    all_faces = [tuple(offsets[role] + i for i in face) for role in names for face in faces[role]]
    return names, offsets, combined, all_faces, groups


def additive_key(obj, local_delta, frame, period):
    """Keep all existing source keys untouched; a correction is zero elsewhere."""
    if obj.data.users > 1:
        obj.data = obj.data.copy()
    keys = obj.data.shape_keys
    if keys is None or not keys.use_relative:
        raise ValueError('Expected the existing relative cloth morph animation')
    if keys.animation_data and keys.animation_data.action and keys.animation_data.action.users > 1:
        keys.animation_data.action = keys.animation_data.action.copy()
    basis = keys.reference_key
    key = obj.shape_key_add(name='Exact contact correction F%03d' % frame)
    key.relative_key = basis
    for vertex, reference, delta in zip(key.data, basis.data, local_delta):
        vertex.co = reference.co + Vector(delta)
    values = {1: 0., period + 1: 0., max(1, frame - 1): 0., frame: 1., min(period + 1, frame + 1): 0.}
    if frame == 1:
        values.update({1: 1., 2: 0., period: 0., period + 1: 1.})
    if frame == period:
        values.update({1: 0., period - 1: 0., period: 1., period + 1: 0.})
    for time, value in sorted(values.items()):
        key.value = value
        key.keyframe_insert('value', frame=time)
    for curve in fcurves(obj.data.shape_keys.animation_data.action):
        if curve.data_path == key.path_from_id('value'):
            for point in curve.keyframe_points:
                point.interpolation = 'LINEAR'
            if not any(m.type == 'CYCLES' for m in curve.modifiers):
                curve.modifiers.new('CYCLES')
    key.value = 0.


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--probe', action='store_true')
    parser.add_argument('--samples', nargs='+', default=['01_WALK=5,13,24', '02_RUN=1,22'])
    parser.add_argument('--margin', type=float, default=.0025)
    parser.add_argument('--maximum', type=float, default=.012)
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    output = args.output.resolve()
    if output == Path(bpy.data.filepath).resolve():
        raise ValueError('Separate output required')
    if not (.0015 <= args.margin <= .005 and .001 <= args.maximum <= .025):
        raise ValueError('Expected bounded local clearance')
    report_path = args.report or output.with_suffix('.exact-finish.json')
    report = {'source': bpy.data.filepath, 'output': str(output), 'probe': args.probe,
              'complete': False, 'clips': {}, 'method': 'Persistent constraints at actual finite intersection endpoints/midpoints; additive isolated-frame morphs'}
    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    started = time.perf_counter()
    for spec in args.samples:
        prefix, number_text = spec.split('=', 1)
        targets = sorted(set(int(x) for x in number_text.split(',')))
        scene = next(s for s in bpy.data.scenes if s.name.startswith(prefix))
        period = scene.frame_end
        if scene.frame_start != 1 or min(targets) < 1 or max(targets) > period:
            raise ValueError('Requested frame outside the authored loop')
        roles = {o.get('graduate_role'): o for o in scene.objects if o.type == 'MESH' and o.get('graduate_role') and not o.get('preview_fx')}
        body, gown = roles[BODY], roles[GOWN]
        rig = next(o for o in scene.objects if o.type == 'ARMATURE')
        layers = {r: o for r, o in roles.items() if r.startswith('03 |')}
        bars = {r: o for r, o in roles.items() if r.startswith('04 |')}
        objects = [gown, *layers.values(), *bars.values()]
        faces = triangles(gown)
        layer_faces = {r: triangles(o) for r, o in layers.items()}
        rest = np.asarray([v.co[:] for v in gown.data.vertices])
        gown_groups = [[int(i)] for i in np.flatnonzero((rest[:, 2] > 3.5) & (np.abs(rest[:, 0]) < .60))]
        binding = {obj: SkinBinding(obj, rig) for obj in objects}
        old_rig, timing = rig_hash(rig), (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base)
        clip = {'targets': targets, 'frames': [], 'preservation': {}, 'timing': timing}
        report['clips'][scene.name] = clip
        local_deltas = []
        expected_targets = {}
        with visible_surfaces(scene, [body, *objects], 'simulation'):
            baseline = {}
            for frame in range(1, period + 1):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                baseline[frame] = {obj: evaluated_points(obj) for obj in objects}
            for frame in targets:
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                original = baseline[frame]
                gown_points = original[gown]
                posed = {r: original[o] for r, o in layers.items()}
                neck = build_neck_collider(body)
                skin = array_surface(neck.points, neck.triangles)
                before = exact_neck_report(gown_points, faces, posed, layer_faces, neck, skin_surface=skin)
                gown_fixed, gown_report = exact_project(gown_points, faces, gown_groups, {'actual_neck_skin': skin}, margin=args.margin, maximum=args.maximum)
                names, offsets, combined, all_faces, groups = sewn_row_groups(posed, layer_faces)
                fixed, row_report = exact_project(combined, all_faces, groups,
                    {'gown': array_surface(gown_fixed, faces), 'actual_neck_skin': skin}, margin=args.margin, maximum=args.maximum)
                fixed_layers = {r: fixed[offsets[r]:offsets[r] + len(posed[r])].copy() for r in names}
                corrected = {gown: gown_fixed, **{layers[r]: fixed_layers[r] for r in names}}
                torso = rig.pose.bones['Torso']
                forward = rig.matrix_world.to_3x3() @ torso.matrix.to_3x3() @ torso.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0))
                for role, obj in bars.items():
                    parent = next(o for r, o in layers.items() if r.endswith(' ' + role.rsplit(' ', 1)[1][0]))
                    corrected[obj] = original[obj] if np.array_equal(corrected[parent][32:], original[parent][32:]) else bar_points(corrected[parent], int(role[-1]), np.asarray(forward.normalized()))
                after = exact_neck_report(gown_fixed, faces, fixed_layers, layer_faces, neck, skin_surface=skin)
                expected_targets[frame] = corrected
                changes = {obj.get('graduate_role'): float(np.max(np.linalg.norm(corrected[obj] - original[obj], axis=1))) for obj in objects}
                for obj in objects:
                    if changes[obj.get('graduate_role')] > 1e-10:
                        delta = np.asarray(binding[obj].inverse_points(corrected[obj])) - np.asarray(binding[obj].inverse_points(original[obj]))
                        local_deltas.append((obj, frame, delta))
                entry = {'frame': frame, 'before': before, 'after': after, 'gown_solver': gown_report,
                         'row_solver': row_report, 'maximum_vertex_movement_m': changes,
                         'gown_self': compact_crossings(array_surface(gown_fixed, faces), array_surface(gown_fixed, faces), True),
                         'max_extra_adjacent_integer_frame_delta_m': max(changes.values())}
                entry['sewn_endpoint_gaps_m'] = {'left': float(np.max(np.linalg.norm(fixed_layers[names[0]][:4] - fixed_layers[names[2]][:4], axis=1))), 'right': float(np.max(np.linalg.norm(fixed_layers[names[1]][:4] - fixed_layers[names[2]][-4:], axis=1)))}
                clip['frames'].append(entry)
                checkpoint()
                print('EXACT_FINISH', scene.name, frame, changes, 'gown_remaining', gown_report['remaining'], 'row_remaining', row_report['remaining'], flush=True)
            if not args.probe:
                for obj, frame, delta in local_deltas:
                    additive_key(obj, delta, frame, period)
                untouched_error, target_error = 0., 0.
                for frame in range(1, period + 1):
                    scene.frame_set(frame)
                    bpy.context.view_layer.update()
                    if frame not in targets:
                        untouched_error = max(untouched_error, max(float(np.max(np.linalg.norm(evaluated_points(obj) - baseline[frame][obj], axis=1))) for obj in objects))
                    else:
                        target_error = max(target_error, max(float(np.max(np.linalg.norm(evaluated_points(obj) - expected_targets[frame][obj], axis=1))) for obj in objects))
                if untouched_error > 1e-7:
                    raise AssertionError('Untargeted integer frame changed: ' + str(untouched_error))
                if target_error > 1e-6:
                    raise AssertionError('Corrective key did not reproduce target: ' + str(target_error))
                clip['preservation']['untargeted_integer_frame_error_m'] = untouched_error
                clip['preservation']['target_reconstruction_error_m'] = target_error
        if old_rig != rig_hash(rig) or timing != (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base):
            raise AssertionError('Rig/timing changed')
        clip['rig_and_timing_unchanged'] = True
        checkpoint()
    if not args.probe:
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report['asset_saved'] = not args.probe
    report['complete'] = True
    report['seconds'] = round(time.perf_counter() - started, 3)
    checkpoint()
    print('EXACT_FINISH_DONE', str(output), report['seconds'], flush=True)


if __name__ == '__main__':
    main()
