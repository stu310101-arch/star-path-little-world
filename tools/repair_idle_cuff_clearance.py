"""Find the smallest cycle-constant outward Idle cuff translation that is safe.

Run only in the owner's existing background Blender queue on the thin-fabric
candidate. No process is launched and no source blend is overwritten::

    blender -b <candidate.blend> --python-exit-code 1 --python \
      tools/repair_idle_cuff_clearance.py -- --output <new.blend>

Each of the existing 32-vertex sleeve rings receives one translation, smoothly
ramped from zero at ring 8 to full displacement at ring 16. Its magnitude is
constant through the cycle; its direction follows only Body yaw. This keeps
every ring's width/shape and the complete shoulder attachment unchanged.
Candidates are 2, 4, 6, 8, 10 and 12 mm, tested in increasing order across all
120 authored frames. Only a successful, independently verified baked candidate
is saved. --probe-only selects/reports a candidate without baking or saving.

Rendered source-face classification matches audit_regalia_pairs: Jump source
gown face center z>3.05 and abs(x)>.34 describes the pre-existing sewn armhole.
All contacts are reported. No new/worsened sewn, skin/body, other-sleeve,
decoration or self contacts are accepted. Unknown gown faces count as free.
The thin candidate must have no topology/geometry-changing sleeve modifier
other than Armature/Triangulate; an actual rendered post-bake check is required.
"""
from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import sys
import time

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from simulate_portal_cloth import SkinBinding, evaluated_points
from repair_idle_gown_hang import BODY, GOWN, body_yaw
from repair_motion_pants_clearance import (_brief, _maximum, _new_contacts, _protected_snapshot,
    _snapshot_changes, bake_isolated_cache)
from postprocess_regalia_layers import array_surface
from audit_regalia_pairs import classify_source
from validate_sleeve_garment_contact import Surface, compare, visible_surfaces

EPSILON = 1e-6
BAKE_TOLERANCE = 2e-6


def ring_weights():
    values = np.zeros(545)
    for ring in range(17):
        t = np.clip((ring - 8) / 8, 0., 1.)
        values[ring * 32:(ring + 1) * 32] = t * t * (3. - 2. * t)
    return values


def shifted_points(points, direction, distance, weights):
    return np.asarray(points) + weights[:, None] * np.asarray(direction)[None, :] * distance


def ring_shape_error(original, changed):
    errors = []
    for ring in range(17):
        a, b = original[ring * 32:(ring + 1) * 32], changed[ring * 32:(ring + 1) * 32]
        errors.append(_maximum(np.linalg.norm((a - a.mean(axis=0)) - (b - b.mean(axis=0)), axis=1)))
    return max(errors, default=0.)


def _surface(obj):
    surface = Surface(obj)
    classify_source(surface, obj)
    return surface


def _gown_counts(result, gown, sewn_faces):
    counts = Counter()
    examples = []
    for (a, b), length in zip(result['triangle_pairs'], result['intersection_segment_lengths_m']):
        source = gown.source_map[gown.polygons[b]]['source_polygon']
        group = 'documented_sewn_armhole' if source in sewn_faces else 'free_gown'
        counts[group] += 1
        if source is None:
            counts['unmapped_source_counted_as_free'] += 1
        if len(examples) < 20:
            examples.append({'sleeve_triangle': a, 'gown_triangle': b,
                             'source_gown_polygon': source, 'region': group,
                             'intersection_segment_m': length})
    return {'all_crossings': result['crossings'], 'free_gown': counts['free_gown'],
            'documented_sewn_armhole': counts['documented_sewn_armhole'],
            'unmapped_source_counted_as_free': counts['unmapped_source_counted_as_free'],
            'examples': examples}


def _material_contacts(result, target):
    counts = Counter()
    for _, b in result['triangle_pairs']:
        counts[target.source_map[target.polygons[b]]['material'] or 'unknown'] += 1
    return dict(counts)


def _audit(points, row, sewn_faces):
    sleeve = array_surface(points, row['sleeve_triangles'])
    gown = compare(sleeve, row['gown'], False, EPSILON)
    guards = {name: compare(sleeve, surface, False, EPSILON)
              for name, surface in row['guards'].items()}
    self_result = compare(sleeve, sleeve, True, EPSILON)
    return {'gown': gown, 'gown_regions': _gown_counts(gown, row['gown'], sewn_faces),
            'guards': guards, 'self': self_result}


def _summary(audit, row):
    return {'gown': audit['gown_regions'], 'self': _brief(audit['self']),
            'guards': {name: {'stats': _brief(result), 'materials': _material_contacts(result, row['guards'][name])}
                       for name, result in audit['guards'].items()}}


def _regressions(before, after):
    return {'gown': _new_contacts(before['gown'], after['gown']),
            'self': _new_contacts(before['self'], after['self']),
            'guards': {name: _new_contacts(before['guards'][name], result)
                       for name, result in after['guards'].items()}}


def _safe(audit, regressions):
    return (audit['gown_regions']['free_gown'] == 0 and not regressions['gown']
            and not regressions['self'] and not any(regressions['guards'].values()))


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--side', choices=('L', 'R'), default='L')
    parser.add_argument('--steps-mm', default='2,4,6,8,10,12')
    parser.add_argument('--probe-only', action='store_true')
    args = parser.parse_args(argv)
    if not bpy.app.background:
        raise RuntimeError('Use the owner-coordinated background Blender process')
    source, output = Path(bpy.data.filepath).resolve(), args.output.resolve()
    report_path = (args.report or output.with_suffix('.idle-cuff-clearance.json')).resolve()
    if not bpy.data.filepath or not source.is_file():
        raise ValueError('A saved candidate must already be loaded')
    if output == source or output.suffix.lower() != '.blend' or output.exists():
        raise ValueError('Output must be a new, distinct blend path')
    if report_path in (source, output) or report_path.suffix.lower() != '.json':
        raise ValueError('Use a separate JSON report path')
    steps = sorted({float(value) / 1000. for value in args.steps_mm.split(',')})
    if not steps or any(not math.isfinite(value) or value <= 0 or value > .012 for value in steps):
        raise ValueError('Cuff candidates must be positive finite translations no greater than 12 mm')
    scenes = [s for s in bpy.data.scenes if s.name.startswith('04_IDLE')]
    if len(scenes) != 1:
        raise ValueError('Expected exactly one Idle scene')
    scene = scenes[0]
    if scene.frame_start != 1 or scene.frame_end != 120:
        raise ValueError('Expected the existing 1..120 Idle cycle; refusing to retime')
    roles = {}
    for obj in scene.objects:
        role = obj.get('graduate_role')
        if obj.type != 'MESH' or not role or obj.get('preview_fx'):
            continue
        if role in roles:
            raise ValueError('Duplicate garment role: ' + role)
        roles[role] = obj
    sleeve = roles['02 | Bell sleeve ' + args.side]
    gown, body = roles[GOWN], roles[BODY]
    rigs = [o for o in scene.objects if o.type == 'ARMATURE' and not o.get('preview_fx')]
    if len(rigs) != 1:
        raise ValueError('Expected exactly one Idle rig')
    rig = rigs[0]
    if len(sleeve.data.vertices) != 545:
        raise ValueError('Expected 17 existing 32-vertex rings plus the shoulder cap')
    if any(other != scene and sleeve.name in other.objects for other in bpy.data.scenes):
        raise ValueError('Sleeve object is shared with another clip')
    if any(m.show_viewport and m.type not in ('ARMATURE', 'TRIANGULATE') for m in sleeve.modifiers):
        raise ValueError('Use the thin-fabric candidate: sleeve may only have Armature/Triangulate enabled')
    weights = ring_weights()
    group = sleeve.vertex_groups.get('Sleeve shoulder seam only')
    if group is None:
        raise ValueError('Missing explicit shoulder attachment group')
    pinned = np.asarray([any(g.group == group.index and g.weight > 0 for g in v.groups)
                         for v in sleeve.data.vertices])
    if np.any(weights[pinned] > 0):
        raise ValueError('The ring ramp would move a pinned shoulder vertex')
    fixed = weights == 0
    reference_scene = next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
    reference_gown = next(o for o in reference_scene.objects if o.get('graduate_role') == GOWN)
    if [tuple(p.vertices) for p in gown.data.polygons] != [tuple(p.vertices) for p in reference_gown.data.polygons]:
        raise ValueError('Idle/Jump gown source indexing differs; seam classification is ambiguous')
    sewn_faces = {p.index for p in reference_gown.data.polygons if p.center.z > 3.05 and abs(p.center.x) > .34}
    guards = {role: obj for role, obj in roles.items() if obj not in (gown, sleeve)
              and (role.startswith('Graduate |') or role.startswith(('02 |', '03 |', '04 |', '05 |')))}
    objects = [sleeve, gown, *guards.values()]
    protected_before = _protected_snapshot([sleeve], components=True)
    started = time.perf_counter()
    report = {'source_blend': str(source), 'output': str(output), 'scene': scene.name,
              'side': args.side, 'complete': False, 'accepted': False, 'asset_saved': False,
              'probe_only': args.probe_only, 'candidate_shifts_m': steps,
              'method': 'Cycle-constant outward translation of complete sleeve rings in Body yaw coordinates',
              'fixed_rings': list(range(9)), 'full_shift_ring': 16, 'fixed_shoulder_cap_vertex': 544,
              'seam_classification': 'Jump source gown face centers z>3.05 and abs(x)>.34; all counts retained',
              'sewn_source_polygons': sorted(sewn_faces), 'baseline': [], 'trials': [], 'baked_frames': [],
              'guard_roles': sorted(guards), 'all_guard_contacts_reported': True,
              'scope': 'Only one Idle sleeve cache may change; gown, ring widths, other clips, upper attachment, rigs and timing preserved'}
    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    rows, previous_mesh = [], None
    try:
        binding = SkinBinding(sleeve, rig)
        # Source and rendered sleeve coordinates must coincide in the thin
        # candidate, so array trials represent the real rendered triangles.
        with visible_surfaces(scene, [sleeve], 'simulation'):
            source_points = []
            for frame in range(1, 121):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                source_points.append(evaluated_points(sleeve))
        with visible_surfaces(scene, objects, 'rendered'):
            scene.frame_set(1)
            bpy.context.view_layer.update()
            yaw0 = body_yaw(rig)
            across0 = np.asarray([math.cos(yaw0), math.sin(yaw0), 0.])
            reference_center = np.mean(evaluated_points(body), axis=0)
            cuff_center = np.mean(source_points[0][448:544], axis=0)
            side_measure = float(np.dot(cuff_center - reference_center, across0))
            if abs(side_measure) < .02:
                raise ValueError('Cannot identify a reliable outward side from the existing cuff position')
            sign = 1. if side_measure > 0 else -1.
            report['measured_outward_side'] = sign
            for frame in range(1, 121):
                scene.frame_set(frame)
                bpy.context.view_layer.update()
                rendered = _surface(sleeve)
                points = np.asarray([tuple(p) for p in rendered.points])
                if points.shape != (545, 3) or _maximum(np.linalg.norm(points - source_points[frame - 1], axis=1)) > BAKE_TOLERANCE:
                    raise ValueError('Rendered sleeve differs from source midsurface; thin-surface trial is unsupported')
                yaw = body_yaw(rig)
                row = {'frame': frame, 'points': source_points[frame - 1],
                       'direction': sign * np.asarray([math.cos(yaw), math.sin(yaw), 0.]),
                       'sleeve_triangles': rendered.triangles, 'gown': _surface(gown),
                       'guards': {role: _surface(obj) for role, obj in guards.items()}}
                row['before'] = _audit(row['points'], row, sewn_faces)
                rows.append(row)
                report['baseline'].append({'frame': frame, **_summary(row['before'], row)})
                if frame % 20 == 0:
                    checkpoint()
                    print('IDLE_CUFF_BASELINE', frame, flush=True)
        selected = None
        if all(row['before']['gown_regions']['free_gown'] == 0 for row in rows):
            selected = 0.
            report['reason'] = 'Existing sleeve already has no free gown crossings'
        for distance in steps if selected is None else []:
            trial = {'shift_m': distance, 'passed': True, 'frames': []}
            report['trials'].append(trial)
            for row in rows:
                proposed = shifted_points(row['points'], row['direction'], distance, weights)
                if not np.array_equal(proposed[fixed], row['points'][fixed]):
                    raise AssertionError('A fixed ring or shoulder cap moved')
                width_error = ring_shape_error(row['points'], proposed)
                if width_error > 1e-10:
                    raise AssertionError('A translated cross section changed shape')
                after = _audit(proposed, row, sewn_faces)
                regressions = _regressions(row['before'], after)
                passed = _safe(after, regressions)
                trial['frames'].append({'frame': row['frame'], 'passed': passed,
                                        'after': _summary(after, row), 'regressions': regressions,
                                        'ring_shape_error_m': width_error})
                if not passed:
                    trial['passed'] = False
                    trial['first_failed_frame'] = row['frame']
                    trial['remaining_frames_not_evaluated'] = 120 - row['frame']
                    break
            checkpoint()
            print('IDLE_CUFF_TRIAL', distance, trial['passed'], len(trial['frames']), flush=True)
            if trial['passed']:
                selected = distance
                break
        report['selected_shift_m'] = selected
        if selected is None:
            report['reason'] = 'No bounded candidate cleared every frame without a contact regression'
            report['complete'] = True
            return report
        report['candidate_all_120_frames_clear'] = True
        report['accepted'] = True
        if args.probe_only:
            report['reason'] = 'A constant candidate passed array checks; probe only, no bake/save'
            report['complete'] = True
            return report
        if selected > 0:
            samples = []
            with visible_surfaces(scene, [sleeve], 'simulation'):
                for row in rows:
                    scene.frame_set(row['frame'])
                    bpy.context.view_layer.update()
                    target = shifted_points(row['points'], row['direction'], selected, weights)
                    samples.append(np.asarray(binding.inverse_points(target)))
                previous_mesh = sleeve.data
                sleeve.data = sleeve.data.copy()
                bake_isolated_cache(sleeve, samples, 'Idle constant outward cuff relief | ' + args.side, loop=True)
        with visible_surfaces(scene, objects, 'rendered'):
            maximum_error = fixed_error = width_error = 0.
            for row in rows:
                scene.frame_set(row['frame'])
                bpy.context.view_layer.update()
                actual_surface = _surface(sleeve)
                if actual_surface.triangles != row['sleeve_triangles']:
                    raise AssertionError('Baked sleeve topology changed')
                actual = np.asarray([tuple(p) for p in actual_surface.points])
                target = shifted_points(row['points'], row['direction'], selected, weights)
                error = _maximum(np.linalg.norm(actual - target, axis=1))
                fixed_at_frame = _maximum(np.linalg.norm(actual[fixed] - row['points'][fixed], axis=1))
                shape_at_frame = ring_shape_error(row['points'], actual)
                maximum_error, fixed_error, width_error = max(maximum_error, error), max(fixed_error, fixed_at_frame), max(width_error, shape_at_frame)
                if error > BAKE_TOLERANCE or fixed_at_frame > BAKE_TOLERANCE or shape_at_frame > 2 * BAKE_TOLERANCE:
                    raise AssertionError('Baked target, fixed shoulder or ring-width verification failed')
                after = _audit(actual, row, sewn_faces)
                regressions = _regressions(row['before'], after)
                report['baked_frames'].append({'frame': row['frame'], 'after': _summary(after, row),
                                               'regressions': regressions, 'target_error_m': error})
                if not _safe(after, regressions):
                    raise AssertionError('Actual rendered sleeve bake failed a contact guard')
                if row['frame'] % 20 == 0:
                    checkpoint()
                    print('IDLE_CUFF_BAKED', row['frame'], flush=True)
            scene.frame_set(1)
            bpy.context.view_layer.update()
            first = evaluated_points(sleeve)
            scene.frame_set(121)
            bpy.context.view_layer.update()
            loop_error = _maximum(np.linalg.norm(evaluated_points(sleeve) - first, axis=1))
            if loop_error > 1e-5:
                raise AssertionError('Idle cuff loop seam is not closed')
            report['bake_verification'] = {'maximum_target_error_m': maximum_error,
                'fixed_shoulder_error_m': fixed_error, 'maximum_ring_shape_error_m': width_error,
                'rendered_loop_seam_m': loop_error}
        protected_after = _protected_snapshot([sleeve], components=True)
        report['protected_data_changes'] = _snapshot_changes(protected_before, protected_after)
        if protected_before != protected_after:
            raise AssertionError('Protected gown, other clips, rig/actions, modifiers or timing changed')
        report['protected_data_preserved'] = True
        output.parent.mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(output))
        report['asset_saved'] = True
        report['complete'] = True
        report['reason'] = 'Smallest tested constant shift passed all 120 rendered frames, bake, ring-width and preservation checks'
        report['limitations'] = 'Authored integer frames. Exact transverse intersections; coplanar overlap and subframes require separate final review.'
        return report
    except Exception as exc:
        if previous_mesh is not None:
            sleeve.data = previous_mesh
        report['accepted'] = False
        report['asset_saved'] = False
        report['failure'] = str(exc)
        report['edited_sleeve_mesh_restored'] = True
        raise
    finally:
        report['seconds'] = round(time.perf_counter() - started, 3)
        checkpoint()
        print('IDLE_CUFF_DONE', report['accepted'], report['asset_saved'], report.get('selected_shift_m'), flush=True)


if __name__ == '__main__':
    main(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
