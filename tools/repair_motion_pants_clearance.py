"""Bounded actual-trousers relief for Run and Jump, preserving other clips.

Run in the owner's single background Blender process with the desired candidate
already loaded::

    blender -b <candidate.blend> --python-exit-code 1 --python \
      tools/repair_motion_pants_clearance.py -- --output <new.blend>

Only finite actual Pants intersections seed local, nonnegative radial relief.
One scalar per gown vertex is shared across a whole clip and rotates with Body
yaw, while the existing root translation and all original cloth motion remain.
Run uses the existing looping baker; Jump uses the non-looping key baker. Idle,
Walk, rig actions, timing, upper gown and sewn stole rows are protected.

The full authored range is measured before and after on both midsurfaces and
rendered modifier surfaces. Failed clearance, displacement, self-regression,
bake or preservation checks restore all edited mesh datablocks and save no
blend. --probe-frames 1,2,10 measures only those frames and never bakes/saves.
This script launches no process and does nothing on import except definitions.
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
from simulate_portal_cloth import SCALE, SkinBinding, evaluated_points, fcurves
from repair_graduate_regalia import anchors, bar_points, deform, triangles
from repair_idle_gown_hang import (BODY, GOWN, body_yaw, clear_hanging_stole,
    lower_body_faces, rotation_2d, width_profile)
from repair_idle_pants_clearance import (contact_details, grow_relief,
    points_with_relief, topology_placket_pairs)
from postprocess_regalia_layers import array_surface
from validate_sleeve_garment_contact import compare, Surface, visible_surfaces

PREFIXES = {'run': '02_RUN', 'jump': '03_JUMP'}
EPSILON = 1e-6
BAKE_TOLERANCE = 2e-6


def _maximum(values):
    return float(np.asarray(values).max(initial=0))


def _brief(result):
    return {key: value for key, value in result.items()
            if key not in ('triangle_pairs', 'intersection_segment_lengths_m')}


def _new_contacts(before, after):
    """Existing upper/neck contacts cannot license a new lower contact."""
    previous = {tuple(pair): length for pair, length in
                zip(before['triangle_pairs'], before['intersection_segment_lengths_m'])}
    return [{'triangle_pair': pair, 'before_segment_m': previous.get(tuple(pair)),
             'after_segment_m': length}
            for pair, length in zip(after['triangle_pairs'], after['intersection_segment_lengths_m'])
            if tuple(pair) not in previous or length > previous[tuple(pair)] + EPSILON]


def _surface(obj):
    surface = Surface(obj)
    surface.seam = [False] * len(surface.triangles)
    return surface


def _rendered_pants(body):
    """Use the actual evaluated Pants material faces, including modifiers."""
    evaluated = body.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    try:
        mesh.calc_loop_triangles()
        points = np.asarray([(evaluated.matrix_world @ v.co)[:] for v in mesh.vertices]) * SCALE
        faces = []
        for triangle in mesh.loop_triangles:
            index = mesh.polygons[triangle.polygon_index].material_index
            material = evaluated.material_slots[index].material if index < len(evaluated.material_slots) else None
            if material and material.name.startswith(('Pants', 'Trousers')):
                faces.append(tuple(triangle.vertices))
    finally:
        evaluated.to_mesh_clear()
    if not faces:
        raise ValueError('No actual evaluated Pants material triangles')
    return array_surface(points, faces)


def _animation_digest(block, details=False):
    animation = getattr(block, 'animation_data', None)
    if animation is None:
        return None
    actions = [animation.action]
    nla = []
    for track in animation.nla_tracks:
        strips = []
        for strip in track.strips:
            actions.append(strip.action)
            strips.append((strip.name, strip.frame_start, strip.frame_end,
                           strip.action_frame_start, strip.action_frame_end,
                           strip.scale, strip.repeat, strip.influence, strip.mute))
        nla.append((track.name, track.mute, track.is_solo, strips))
    def curve_data(curve):
        return (curve.data_path, curve.array_index, curve.extrapolation, curve.mute,
                [(list(key.co), list(key.handle_left), list(key.handle_right), key.interpolation)
                 for key in curve.keyframe_points],
                [(modifier.type, modifier.mute) for modifier in curve.modifiers])
    payload = {'actions': [(action.name, [curve_data(fc) for fc in fcurves(action)])
                           for action in actions if action], 'nla': nla,
               'drivers': [(curve_data(fc), fc.driver.expression) for fc in animation.drivers]}
    return payload if details else hashlib.sha256(json.dumps(payload, sort_keys=True).encode()).hexdigest()


def _protected_snapshot(editable, components=False):
    """Hash protected source coordinates and animation, including every Idle key.

    This verifies stored data rather than three representative rendered poses.
    Object animation is protected even on an editable garment. Only the mesh
    coordinates/shape-key caches of explicitly editable objects are omitted.
    """
    editable = set(editable)
    parts = {}
    def add(name, value):
        parts[name] = hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()
    for scene in sorted(bpy.data.scenes, key=lambda s: s.name):
        add('scene/' + scene.name, (scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base))
    for obj in sorted(bpy.data.objects, key=lambda o: o.name):
        prefix = 'object/' + obj.name
        add(prefix + '/identity', (obj.type, obj.parent.name if obj.parent else None))
        add(prefix + '/animation', _animation_digest(obj))
        add(prefix + '/modifiers', [(m.name, m.type, m.show_viewport, m.show_render) for m in obj.modifiers])
        if obj.type == 'ARMATURE':
            add(prefix + '/rest_bones', [(b.name, b.parent.name if b.parent else None, [list(row) for row in b.matrix_local], b.use_deform)
                 for b in obj.data.bones])
        if obj.type != 'MESH' or obj in editable:
            continue
        mesh = obj.data
        parts[prefix + '/vertices'] = hashlib.sha256(np.asarray([v.co[:] for v in mesh.vertices], dtype='<f8').tobytes()).hexdigest()
        add(prefix + '/polygons', [list(p.vertices) for p in mesh.polygons])
        add(prefix + '/key_animation', _animation_digest(mesh.shape_keys) if mesh.shape_keys else None)
        if mesh.shape_keys:
            for key in mesh.shape_keys.key_blocks:
                add(prefix + '/key/' + key.name, (key.relative_key.name, key.mute, key.vertex_group))
                parts[prefix + '/key_points/' + key.name] = hashlib.sha256(np.asarray([v.co[:] for v in key.data], dtype='<f8').tobytes()).hexdigest()
    return parts if components else hashlib.sha256(json.dumps(parts, sort_keys=True).encode()).hexdigest()


def _snapshot_changes(before, after):
    return [{'component': key, 'before': before.get(key), 'after': after.get(key)}
            for key in sorted(set(before) | set(after)) if before.get(key) != after.get(key)]


def bake_isolated_cache(obj, samples, label, *, loop):
    """Bake to a new KEY action/slot without reusing the object's shared action.

    The source Jump gown shares one layered Action between its Object visibility
    and Key animation. shape_key_clear + keyframe_insert can reuse that Action,
    append new channels and rename it. Allocate the destination Key action,
    slot and channelbag explicitly before adding curves so the Object action
    (and every other user of the original Action) stays byte-for-byte intact.
    The caller must already have assigned an isolated copy of the mesh.
    """
    before_object_animation = _animation_digest(obj)
    samples = np.asarray(samples)
    if samples.ndim != 3 or samples.shape[1:] != (len(obj.data.vertices), 3) or len(samples) < 2:
        raise ValueError('Expected at least two complete source-vertex samples')
    if not np.isfinite(samples).all():
        raise ValueError('Non-finite bake coordinates')
    obj.shape_key_clear()
    obj.shape_key_add(name='Basis')
    keys = obj.data.shape_keys
    keys.animation_data_clear()
    action = bpy.data.actions.new(label)
    action.use_fake_user = True
    layer = action.layers.new('Isolated garment cache')
    strip = layer.strips.new(type='KEYFRAME')
    slot = action.slots.new(keys.id_type, obj.name)
    bag = strip.channelbags.new(slot)
    animation = keys.animation_data_create()
    animation.action = action
    animation.action_slot = slot
    period = len(samples)
    for index, coords in enumerate(samples):
        key = obj.shape_key_add(name=label[:44] + '_%04d' % (index + 1))
        key.data.foreach_set('co', np.asarray(coords, dtype=np.float32).ravel())
        frame = index + 1
        if loop:
            times = {1: 0., period + 1: 0., max(1, frame - 1): 0., frame: 1., min(period + 1, frame + 1): 0.}
            if index == 0:
                times.update({1: 1., 2: 0., period: 0., period + 1: 1.})
            if index == period - 1:
                times.update({1: 0., period - 1: 0., period: 1., period + 1: 0.})
        else:
            times = {frame: 1.}
            if index:
                times[frame - 1] = 0.
            if index + 1 < period:
                times[frame + 1] = 0.
        curve = bag.fcurves.new(data_path=key.path_from_id('value'), index=0)
        curve.keyframe_points.add(len(times))
        curve.keyframe_points.foreach_set('co', np.asarray(sorted(times.items()), dtype=np.float32).ravel())
        curve.extrapolation = 'CONSTANT'
        for point in curve.keyframe_points:
            point.interpolation = 'LINEAR'
        curve.update()
        if loop:
            curve.modifiers.new('CYCLES')
        key.value = 0.
    if before_object_animation != _animation_digest(obj):
        raise AssertionError('Isolated Key bake changed the protected Object action')


def _rendered_seed_relief(row, envelope, movable, margin, maximum):
    """Shell-only finite crossings also constrain their real source vertices.

    Only a Triangulate/Solidify stack is allowed for this source mapping. The
    final rendered bake is independently evaluated, never inferred from these
    source-plane constraints or a stale shell normal.
    """
    proposal = envelope.copy()
    points = points_with_relief(row, envelope)
    blocked = []
    for seed in row['rendered_seeds']:
        normal, origin = np.asarray(seed['normal']), np.asarray(seed['origin'])
        for vertex in seed['vertices']:
            distance = float(np.dot(points[vertex] - origin, normal))
            if distance >= margin:
                continue
            factor = float(np.dot(row['directions'][vertex], normal))
            if not movable[vertex] or factor <= .15:
                blocked.append({'vertex': vertex, 'rendered_seed': True,
                                'signed_distance_m': distance, 'outward_alignment': factor})
                continue
            required = (margin - distance) / factor
            proposal[vertex] = max(proposal[vertex], min(maximum, envelope[vertex] + required))
    return proposal, blocked


def _clip_objects(clip):
    matches = [s for s in bpy.data.scenes if s.name.startswith(PREFIXES[clip])]
    if len(matches) != 1:
        raise ValueError(f'Expected exactly one {clip} scene')
    scene = matches[0]
    if scene.frame_start != 1 or scene.frame_end < 2:
        raise ValueError('Bakers require frame_start=1 and at least two authored frames')
    roles = {}
    for obj in scene.objects:
        role = obj.get('graduate_role')
        if obj.type != 'MESH' or not role or obj.get('preview_fx'):
            continue
        if role in roles:
            raise ValueError(f'Duplicate garment role: {role}')
        roles[role] = obj
    gown, body = roles[GOWN], roles[BODY]
    rigs = [o for o in scene.objects if o.type == 'ARMATURE' and not o.get('preview_fx')]
    if len(rigs) != 1:
        raise ValueError('Expected exactly one garment rig')
    front = {r: o for r, o in roles.items() if r.startswith('03 |') and r.endswith((' L', ' R'))}
    bars = {r: o for r, o in roles.items() if r.startswith('04 |')}
    objects = [gown, *front.values(), *bars.values()]
    for obj in objects:
        if any(other != scene and obj.name in other.objects for other in bpy.data.scenes):
            raise ValueError(f'{obj.name} is shared by another scene; refusing cross-clip edits')
    if any(len(obj.data.vertices) != 41 for obj in front.values()):
        raise ValueError('Expected the existing 41-vertex front stole topology')
    for modifier in gown.modifiers:
        if modifier.show_viewport and modifier.type not in ('ARMATURE', 'TRIANGULATE', 'SOLIDIFY'):
            raise ValueError('Rendered seed source mapping requires Armature/Triangulate/Solidify only')
    return scene, gown, body, rigs[0], front, bars, objects


def _reattach(row, corrected, gown, front, bars, faces, front_faces, envelope, decoration_cap):
    posed = {obj: points.copy() for obj, points in row['posed'].items()}
    posed[gown] = corrected
    report = {}
    gown_surface = array_surface(corrected, faces)
    old_surface = array_surface(row['gown'], faces)
    for role, obj in front.items():
        original = row['posed'][obj]
        centers = np.asarray([np.mean(original[i:min(i + 4, len(original))], axis=0)
                              for i in range(0, len(original), 4)])
        links = anchors(centers, row['gown'], faces, .0045, True)
        delta = deform(links, corrected) - deform(links, row['gown'])
        touched = []
        for index in range(3, len(centers)):
            ids = links[index][0]
            if not any(envelope[i] > 1e-9 for i in ids) or np.linalg.norm(delta[index]) <= 1e-8:
                continue
            posed[obj][4 * index:min(4 * index + 4, len(original))] += delta[index]
            touched.append(index)
        lower_faces = [face for face in front_faces[role] if any(v >= 12 for v in face)]
        before = compare(array_surface(original, lower_faces), old_surface, False, EPSILON)
        after = compare(array_surface(posed[obj], lower_faces), gown_surface, False, EPSILON)
        clearance = {'maximum_shift_m': 0., 'not_needed': True}
        # Clearance is authorized only when the gown actually moved under this
        # stole. A legacy unrelated contact must not silently re-shape it.
        if touched and _new_contacts(before, after):
            weights = np.zeros(11)
            weights[touched] = 1.
            posed[obj], clearance = clear_hanging_stole(posed[obj], front_faces[role], corrected, faces, weights)
            after = compare(array_surface(posed[obj], lower_faces), gown_surface, False, EPSILON)
        movement = _maximum(np.linalg.norm(posed[obj] - original, axis=1))
        if not np.array_equal(posed[obj][:12], original[:12]):
            raise AssertionError('Upper sewn stole rows changed')
        if movement > decoration_cap + 1e-8:
            raise AssertionError('Lower stole adjustment exceeded the decoration cap')
        regressions = _new_contacts(before, after)
        report[role] = {'gown_before': _brief(before), 'gown_after': _brief(after),
                        'new_or_worse_contacts': regressions, 'touched_rows': touched,
                        'clearance': clearance, 'maximum_change_m': movement}
        if regressions:
            raise AssertionError('Lower stole/gown contacts regressed')
    for role, obj in bars.items():
        side = role.rsplit(' ', 1)[1][0]
        parent = next(o for r, o in front.items() if r.endswith(' ' + side))
        if _maximum(np.linalg.norm(posed[parent] - row['posed'][parent], axis=1)) > 1e-8:
            posed[obj] = bar_points(posed[parent], int(role[-1]), row['forward'])
        if _maximum(np.linalg.norm(posed[obj] - row['posed'][obj], axis=1)) > decoration_cap + 1e-8:
            raise AssertionError('Bar adjustment exceeded the decoration cap')
    return posed, report


def repair_clip(clip, args, report, checkpoint, previous_meshes):
    scene, gown, body, rig, front, bars, objects = _clip_objects(clip)
    object_animation_before = {obj: _animation_digest(obj, details=True) for obj in objects}
    frames = (sorted({int(x) for x in args.probe_frames.split(',')}) if args.probe_frames
              else list(range(1, scene.frame_end + 1)))
    if not frames or any(f < 1 or f > scene.frame_end for f in frames):
        raise ValueError('Probe frames must lie within this clip')
    faces = triangles(gown)
    front_faces = {r: triangles(o) for r, o in front.items()}
    rest = np.asarray([v.co[:] for v in gown.data.vertices])
    movable = rest[:, 2] < 3.0
    waist_mask = np.abs(rest[:, 2] - 3.0) <= .15
    if not np.any(waist_mask):
        raise ValueError('No source waist vertices for stable radial directions')
    placket, ambiguous = topology_placket_pairs(gown.data)
    bands = {'hem': rest[:, 2] < np.min(rest[:, 2]) + .12,
             'knee': (rest[:, 2] >= 1.65) & (rest[:, 2] < 2.0),
             'hip_lower': (rest[:, 2] >= 2.15) & (rest[:, 2] < 2.4),
             'waist_blend': (rest[:, 2] >= 2.65) & (rest[:, 2] < 2.95)}
    pants_faces = lower_body_faces(body, float('inf'))['pants_legs']
    skin_faces = lower_body_faces(body, 3.15)['skin']
    if not pants_faces:
        raise ValueError('No source actual Pants triangles')
    entry = {'scene': scene.name, 'accepted': False, 'saved': False,
             'frames_sampled': frames, 'looping': clip == 'run',
             'actual_pants_triangles': len(pants_faces), 'passes': [], 'frames': [],
             'rendered_before': [], 'rendered_after': [],
             'placket_vertex_pairs': placket, 'placket_unresolved_topology': ambiguous,
             'timing': [scene.frame_start, scene.frame_end, scene.render.fps, scene.render.fps_base]}
    report['clips'][clip] = entry
    bindings = {obj: SkinBinding(obj, rig) for obj in objects}
    rows = []
    with visible_surfaces(scene, [body, *objects], 'simulation'):
        scene.frame_set(1)
        bpy.context.view_layer.update()
        neutral = evaluated_points(gown)
        waist0 = np.mean(neutral[waist_mask], axis=0)
        yaw0 = body_yaw(rig)
        directions0 = np.zeros_like(neutral)
        directions0[:, :2] = neutral[:, :2] - waist0[:2]
        directions0 /= np.maximum(np.linalg.norm(directions0, axis=1), 1e-12)[:, None]
        for frame in frames:
            scene.frame_set(frame)
            bpy.context.view_layer.update()
            posed = {obj: evaluated_points(obj) for obj in objects}
            body_points = evaluated_points(body)
            if len(body_points) != len(body.data.vertices) or posed[gown].shape != rest.shape:
                raise ValueError('Simulation topology does not match source topology')
            yaw = body_yaw(rig)
            directions = directions0.copy()
            directions[:, :2] = directions[:, :2] @ rotation_2d(yaw - yaw0).T
            torso = rig.pose.bones['Torso']
            forward = (rig.matrix_world.to_3x3() @ torso.matrix.to_3x3()
                       @ torso.bone.matrix_local.to_3x3().inverted() @ Vector((0, -1, 0)))
            rows.append({'frame': frame, 'gown': posed[gown], 'posed': posed, 'yaw': yaw,
                         'directions': directions, 'waist': np.mean(posed[gown][waist_mask], axis=0),
                         'pants': array_surface(body_points, pants_faces),
                         'skin': array_surface(body_points, skin_faces) if skin_faces else None,
                         'forward': np.asarray(forward.normalized()), 'rendered_seeds': []})
    with visible_surfaces(scene, [gown, body, *front.values()], 'rendered'):
        for row in rows:
            scene.frame_set(row['frame'])
            bpy.context.view_layer.update()
            rendered, pants = _surface(gown), _rendered_pants(body)
            contacts = compare(rendered, pants, False, EPSILON)
            row['rendered_self_before'] = compare(rendered, rendered, True, EPSILON)
            row['rendered_topology'] = rendered.triangles
            row['rendered_layers_before'] = {
                role: compare(_surface(obj), rendered, False, EPSILON) for role, obj in front.items()}
            for a, b in contacts['triangle_pairs']:
                if any(v >= 2 * len(rest) for v in rendered.triangles[a]):
                    raise ValueError('Rendered gown source-index mapping is ambiguous')
                row['rendered_seeds'].append({
                    'vertices': sorted({int(v % len(rest)) for v in rendered.triangles[a]}),
                    'normal': list(pants.normals[b]), 'origin': list(pants.points[pants.triangles[b][0]])})
            entry['rendered_before'].append({'frame': row['frame'], 'pants': _brief(contacts),
                                             'gown_self': _brief(row['rendered_self_before'])})
    envelope = np.zeros(len(rest))
    for iteration in range(args.passes):
        old = envelope.copy()
        crossings, blocked = 0, []
        for row in rows:
            envelope, contacts, blocks = grow_relief(row, faces, envelope, movable, args.margin, args.maximum_relief)
            envelope, shell_blocks = _rendered_seed_relief(row, envelope, movable, args.margin, args.maximum_relief)
            crossings += contacts['crossings']
            blocked.extend({'frame': row['frame'], **item} for item in blocks + shell_blocks)
        change = _maximum(envelope - old)
        entry['passes'].append({'pass': iteration + 1, 'crossings_seen_before_updates': crossings,
            'maximum_relief_m': _maximum(envelope), 'changed_vertices': int(np.count_nonzero(envelope)),
            'maximum_pass_change_m': change, 'blocked_constraints': blocked[:100]})
        checkpoint()
        print('MOTION_PANTS_PASS', clip, iteration + 1, crossings, _maximum(envelope), flush=True)
        if np.count_nonzero(envelope) > args.maximum_vertices:
            raise AssertionError('Relief exceeded the local vertex-count cap')
        if change < 1e-8:
            break
    entry['relief_by_vertex_m'] = {str(i): float(v) for i, v in enumerate(envelope) if v > 0}
    entry['capped_vertices'] = np.flatnonzero(envelope >= args.maximum_relief - 1e-8).tolist()
    entry['constant_body_local_relief'] = True
    samples, targets = {obj: [] for obj in objects}, {obj: [] for obj in objects}
    changed_objects = set()
    with visible_surfaces(scene, [body, *objects], 'simulation'):
        for row in rows:
            scene.frame_set(row['frame'])
            bpy.context.view_layer.update()
            corrected = points_with_relief(row, envelope)
            if not np.array_equal(corrected[~movable], row['gown'][~movable]):
                raise AssertionError('Upper gown changed')
            if _maximum(np.linalg.norm(corrected - row['gown'], axis=1)) > args.maximum_relief + 1e-8:
                raise AssertionError('Gown relief exceeded displacement cap')
            original_surface, surface = array_surface(row['gown'], faces), array_surface(corrected, faces)
            before, after = compare(original_surface, row['pants'], False, EPSILON), compare(surface, row['pants'], False, EPSILON)
            before_self, after_self = compare(original_surface, original_surface, True, EPSILON), compare(surface, surface, True, EPSILON)
            before_skin = compare(original_surface, row['skin'], False, EPSILON) if row['skin'] else None
            after_skin = compare(surface, row['skin'], False, EPSILON) if row['skin'] else None
            posed, stole_report = _reattach(row, corrected, gown, front, bars, faces, front_faces,
                                            envelope, args.maximum_decoration_adjustment)
            frame_entry = {'frame': row['frame'], 'pants_before': _brief(before), 'pants_after': _brief(after),
                'before_contact_details': contact_details(row['gown'], faces, row['pants'], before),
                'after_contact_details': contact_details(corrected, faces, row['pants'], after),
                'gown_self_before': _brief(before_self), 'gown_self_after': _brief(after_self),
                'self_regressions': _new_contacts(before_self, after_self),
                'skin_regressions': _new_contacts(before_skin, after_skin) if before_skin else [],
                'lower_stoles': stole_report,
                'before_profile': width_profile(row['gown'], row['waist'], row['yaw'], bands, placket),
                'after_profile': width_profile(corrected, row['waist'], row['yaw'], bands, placket),
                'upper_gown_and_sewn_stole_exactly_preserved': True}
            entry['frames'].append(frame_entry)
            if after['crossings'] or frame_entry['self_regressions'] or frame_entry['skin_regressions']:
                entry['reason'] = 'Proposed actual Pants clearance or self/skin preservation failed'
            row['target_self'] = after_self
            for obj in objects:
                targets[obj].append(posed[obj])
                if _maximum(np.linalg.norm(posed[obj] - row['posed'][obj], axis=1)) > 1e-8:
                    changed_objects.add(obj)
                if not args.probe_frames:
                    samples[obj].append(np.asarray(bindings[obj].inverse_points(posed[obj])))
            checkpoint()
            print('MOTION_PANTS_FRAME', clip, row['frame'], before['crossings'], after['crossings'], flush=True)
        entry['midpoint_checks_passed'] = 'reason' not in entry
        if args.probe_frames:
            entry['reason'] = 'Probe only; no cache baked and rendered target not evaluated'
            return
        if not entry['midpoint_checks_passed']:
            raise AssertionError(entry['reason'])
        for obj in objects:
            if obj not in changed_objects:
                continue
            previous_meshes[obj] = obj.data
            obj.data = obj.data.copy()
            label = clip.title() + ' stable local trousers clearance | ' + obj.get('graduate_role')
            bake_isolated_cache(obj, samples[obj], label, loop=clip == 'run')
        verification = {obj.name: {'maximum_target_error_m': 0., 'protected_vertices_error_m': 0.}
                        for obj in changed_objects}
        for index, row in enumerate(rows):
            scene.frame_set(row['frame'])
            bpy.context.view_layer.update()
            for obj in changed_objects:
                actual = evaluated_points(obj)
                error = _maximum(np.linalg.norm(actual - targets[obj][index], axis=1))
                protected = (envelope == 0) if obj == gown else np.arange(len(actual)) < 12 if obj in front.values() else np.zeros(len(actual), dtype=bool)
                fixed_error = _maximum(np.linalg.norm(actual[protected] - row['posed'][obj][protected], axis=1))
                verification[obj.name]['maximum_target_error_m'] = max(verification[obj.name]['maximum_target_error_m'], error)
                verification[obj.name]['protected_vertices_error_m'] = max(verification[obj.name]['protected_vertices_error_m'], fixed_error)
                if error > BAKE_TOLERANCE or fixed_error > BAKE_TOLERANCE:
                    raise AssertionError('Baked geometry or unchanged vertices do not match targets')
            actual = array_surface(evaluated_points(gown), faces)
            pants_check = compare(actual, row['pants'], False, EPSILON)
            self_check = compare(actual, actual, True, EPSILON)
            if pants_check['crossings'] or _new_contacts(row['target_self'], self_check):
                raise AssertionError('Actual baked midsurface contact check failed')
        entry['bake_verification'] = verification
        if clip == 'run':
            seams = {}
            scene.frame_set(1)
            bpy.context.view_layer.update()
            first = {obj: evaluated_points(obj) for obj in changed_objects}
            scene.frame_set(scene.frame_end + 1)
            bpy.context.view_layer.update()
            for obj in changed_objects:
                seams[obj.name] = _maximum(np.linalg.norm(evaluated_points(obj) - first[obj], axis=1))
            entry['run_loop_seams_m'] = seams
            if any(value > 1e-5 for value in seams.values()):
                raise AssertionError('Run loop does not close after baking')
    with visible_surfaces(scene, [body, gown, *front.values()], 'rendered'):
        for row in rows:
            scene.frame_set(row['frame'])
            bpy.context.view_layer.update()
            actual, pants = _surface(gown), _rendered_pants(body)
            if actual.triangles != row['rendered_topology']:
                raise AssertionError('Rendered topology changed; self pair comparison is not valid')
            contact, self_contact = compare(actual, pants, False, EPSILON), compare(actual, actual, True, EPSILON)
            regressions = _new_contacts(row['rendered_self_before'], self_contact)
            layer_regressions = {}
            for role, obj in front.items():
                layers = compare(_surface(obj), actual, False, EPSILON)
                layer_regressions[role] = _new_contacts(row['rendered_layers_before'][role], layers)
            entry['rendered_after'].append({'frame': row['frame'], 'pants': _brief(contact),
                'gown_self': _brief(self_contact), 'self_regressions': regressions,
                'stole_gown_regressions': layer_regressions})
            checkpoint()
            if contact['crossings'] or regressions or any(layer_regressions.values()):
                raise AssertionError('Rendered Pants/self/lower-layer verification failed')
    entry['accepted'] = True
    entry['modified_objects'] = sorted(obj.name for obj in changed_objects)
    entry['reason'] = 'Full authored-range Pants clearance and preservation checks passed'
    entry['limitations'] = 'Authored integer frames; subframe and visual review remain separate. Existing unchanged self contacts are reported, not excluded.'
    entry['object_animation_changes'] = {
        obj.name: {'before': object_animation_before[obj], 'after': _animation_digest(obj, details=True)}
        for obj in objects if object_animation_before[obj] != _animation_digest(obj, details=True)}
    checkpoint()


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--report', type=Path)
    parser.add_argument('--clips', nargs='+', choices=tuple(PREFIXES), default=list(PREFIXES))
    parser.add_argument('--probe-frames')
    parser.add_argument('--diagnose-preservation', action='store_true',
                        help='Sample visibility/frame contexts only, report exact fingerprint differences, never bake/save')
    parser.add_argument('--margin', type=float, default=.003)
    parser.add_argument('--maximum-relief', type=float, default=.020)
    parser.add_argument('--maximum-decoration-adjustment', type=float, default=.025)
    parser.add_argument('--maximum-vertices', type=int, default=48)
    parser.add_argument('--passes', type=int, default=8)
    args = parser.parse_args(argv)
    if not bpy.app.background:
        raise RuntimeError('Run in the owner-coordinated background Blender process')
    source, output = Path(bpy.data.filepath).resolve(), args.output.resolve()
    report_path = (args.report or output.with_suffix('.motion-pants-clearance.json')).resolve()
    if not bpy.data.filepath or not source.is_file():
        raise ValueError('A saved candidate must already be loaded')
    if output == source or output.suffix.lower() != '.blend' or output.exists():
        raise ValueError('Output must be a new, distinct .blend path')
    if report_path in (source, output) or report_path.suffix.lower() != '.json':
        raise ValueError('Report must be a separate JSON path')
    if not (.0015 <= args.margin <= .005 and .001 <= args.maximum_relief <= .030
            and .001 <= args.maximum_decoration_adjustment <= .040
            and 1 <= args.maximum_vertices <= 96 and 1 <= args.passes <= 24):
        raise ValueError('Expected fabric-scale clearance, bounded relief, local vertex cap and 1..24 passes')
    args.clips = list(dict.fromkeys(args.clips))
    editable = [obj for clip in args.clips for obj in _clip_objects(clip)[-1]]
    protected_before = _protected_snapshot(editable, components=True)
    started = time.perf_counter()
    report = {'source_blend': str(source), 'output': str(output), 'complete': False, 'asset_saved': False,
              'probe_only': bool(args.probe_frames), 'clips': {}, 'margin_m': args.margin,
              'maximum_relief_m': args.maximum_relief, 'maximum_changed_vertices': args.maximum_vertices,
              'maximum_decoration_adjustment_m': args.maximum_decoration_adjustment,
              'method': 'One constant Body-yaw-relative scalar relief per source vertex; actual finite Pants contacts only',
              'no_seam_contacts_removed': True,
              'self_policy': 'Report every nonadjacent self crossing; reject new pairs or increased intersection extent',
              'preserved_scope': 'Idle, Walk and unselected clips, every rig/action/timing, upper gown and sewn front-stole rows'}
    def checkpoint():
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding='utf-8')
    previous_meshes = {}
    try:
        checkpoint()
        if args.diagnose_preservation:
            report['diagnostics'] = []
            for clip in args.clips:
                scene, gown, body, rig, front, bars, objects = _clip_objects(clip)
                for mode in ('simulation', 'rendered'):
                    with visible_surfaces(scene, [body, *objects], mode):
                        for frame in (scene.frame_start, scene.frame_end):
                            scene.frame_set(frame)
                            bpy.context.view_layer.update()
                            for obj in objects:
                                evaluated_points(obj)
                    changes = _snapshot_changes(protected_before, _protected_snapshot(editable, components=True))
                    report['diagnostics'].append({'clip': clip, 'mode': mode, 'changes': changes})
                    print('MOTION_PANTS_PRESERVATION', clip, mode, json.dumps(changes), flush=True)
            report['complete'] = True
            return report
        for clip in args.clips:
            repair_clip(clip, args, report, checkpoint, previous_meshes)
        protected_after = _protected_snapshot(editable, components=True)
        report['protected_data_before'] = hashlib.sha256(json.dumps(protected_before, sort_keys=True).encode()).hexdigest()
        report['protected_data_after'] = hashlib.sha256(json.dumps(protected_after, sort_keys=True).encode()).hexdigest()
        report['protected_data_changes'] = _snapshot_changes(protected_before, protected_after)
        report['protected_data_preserved'] = protected_before == protected_after
        if protected_before != protected_after:
            raise AssertionError('Protected animation, source mesh data, modifiers, rig or timing changed')
        if not args.probe_frames and all(item['accepted'] for item in report['clips'].values()):
            output.parent.mkdir(parents=True, exist_ok=True)
            bpy.ops.wm.save_as_mainfile(filepath=str(output))
            report['asset_saved'] = True
            for item in report['clips'].values():
                item['saved'] = True
        report['complete'] = True
    except Exception as exc:
        for obj, mesh in previous_meshes.items():
            obj.data = mesh
        report['failure'] = str(exc)
        report['edited_meshes_restored'] = True
        for item in report['clips'].values():
            item['accepted'] = False
            item['saved'] = False
        checkpoint()
        raise
    finally:
        report['seconds'] = round(time.perf_counter() - started, 3)
        checkpoint()
    print('MOTION_PANTS_DONE', str(output), report['asset_saved'], report['seconds'], flush=True)
    return report


if __name__ == '__main__':
    main(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
