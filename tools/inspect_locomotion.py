"""Read-only inspection of source locomotion and IK; never saves the blend."""
import bpy, json, math, re
from pathlib import Path
from mathutils import Matrix

ROOT = Path(__file__).resolve().parents[1]
rig = bpy.data.objects['HumanArmature']
scene = bpy.context.scene
rig.data.pose_position = 'POSE'

def compact(value):
    if isinstance(value, (str, bool, int, float)) or value is None:
        return value
    if isinstance(value, bpy.types.ID):
        return value.name
    try:
        return list(value)
    except TypeError:
        return str(value)

def constraints(bone):
    result = []
    for constraint in bone.constraints:
        row = {}
        for prop in constraint.bl_rna.properties:
            if prop.identifier in ('rna_type',):
                continue
            try:
                row[prop.identifier] = compact(getattr(constraint, prop.identifier))
            except (AttributeError, TypeError):
                pass
        result.append(row)
    return result

def curves(action):
    result = []
    if hasattr(action, 'fcurves'):
        result.extend(action.fcurves)
    for layer in getattr(action, 'layers', []):
        for strip in layer.strips:
            for bag in getattr(strip, 'channelbags', []):
                result.extend(bag.fcurves)
    return list({id(curve): curve for curve in result}.values())

def span(vectors):
    return [[min(v[i] for v in vectors) for i in range(3)], [max(v[i] for v in vectors) for i in range(3)]]

def rotation_delta(first, other):
    return math.degrees(2 * math.acos(min(1.0, abs(first.normalized().dot(other.normalized())))))

report = {'file': bpy.data.filepath, 'bones': {}, 'actions': {}}
for pose in rig.pose.bones:
    bone = pose.bone
    report['bones'][pose.name] = {'parent': bone.parent.name if bone.parent else None,
        'deform': bone.use_deform, 'rotation_mode': pose.rotation_mode,
        'rest_head': list(bone.head_local), 'rest_tail': list(bone.tail_local),
        'rest_matrix': [list(row) for row in bone.matrix_local],
        'constraints': constraints(pose), 'ik_stretch': pose.ik_stretch,
        'lock_ik': [pose.lock_ik_x, pose.lock_ik_y, pose.lock_ik_z],
        'use_ik_limit': [pose.use_ik_limit_x, pose.use_ik_limit_y, pose.use_ik_limit_z]}

for name in ('Man_Walk', 'Man_Run'):
    action = bpy.data.actions[name]
    for pose in rig.pose.bones:
        pose.matrix_basis = Matrix.Identity(4)
    rig.animation_data.action = action
    if getattr(action, 'slots', None):
        rig.animation_data.action_slot = action.slots[0]
    start, end = [int(value) for value in action.frame_range]
    row = {'range': [start, end], 'fps': scene.render.fps / scene.render.fps_base,
        'channels': [], 'by_bone': {}, 'samples': []}
    for curve in curves(action):
        values = [point.co.y for point in curve.keyframe_points]
        frames = [point.co.x for point in curve.keyframe_points]
        channel = {'path': curve.data_path, 'index': curve.array_index,
            'keyframes': len(values), 'value_min': min(values) if values else None,
            'value_max': max(values) if values else None,
            'frames': frames, 'interpolation': sorted({p.interpolation for p in curve.keyframe_points}),
            'modifiers': [modifier.type for modifier in curve.modifiers]}
        row['channels'].append(channel)
        match = re.match(r'pose\.bones\["(.+)"\]\.(.+)', curve.data_path)
        if match:
            row['by_bone'].setdefault(match.group(1), []).append(channel)
    head_samples = {bone.name: [] for bone in rig.pose.bones}
    tail_samples = {bone.name: [] for bone in rig.pose.bones}
    quaternion_samples = {bone.name: [] for bone in rig.pose.bones}
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        sample = {'frame': frame, 'bones': {}}
        for pose in rig.pose.bones:
            head_samples[pose.name].append(pose.head.copy())
            tail_samples[pose.name].append(pose.tail.copy())
            quaternion_samples[pose.name].append(pose.matrix.to_quaternion())
            sample['bones'][pose.name] = {'head': list(pose.head), 'tail': list(pose.tail),
                'location': list(pose.location), 'rotation_quaternion': list(pose.rotation_quaternion),
                'rotation_euler': list(pose.rotation_euler), 'scale': list(pose.scale)}
        row['samples'].append(sample)
    row['motion_summary'] = {}
    for name in head_samples:
        heads = head_samples[name]
        tails = tail_samples[name]
        quaternions = quaternion_samples[name]
        row['motion_summary'][name] = {'head_range': span(heads), 'tail_range': span(tails),
            'max_head_displacement_from_start': max((v - heads[0]).length for v in heads),
            'max_rotation_degrees_from_start': max(rotation_delta(quaternions[0], q) for q in quaternions),
            'cycle_head_gap': (heads[-1] - heads[0]).length,
            'cycle_rotation_gap_degrees': rotation_delta(quaternions[0], quaternions[-1])}
    report['actions'][action.name] = row

destination = ROOT / 'tools' / 'locomotion-inspection.json'
destination.write_text(json.dumps(report, indent=2), encoding='utf-8')
print('LOCOMOTION_REPORT', str(destination))
for name, action in report['actions'].items():
    print('ACTION', name, 'RANGE', action['range'], 'CHANNELS', len(action['channels']))
    for bone, summary in action['motion_summary'].items():
        keyed = action['by_bone'].get(bone, [])
        varying = sorted({channel['path'].split('].')[-1] for channel in keyed if channel['value_min'] is not None and abs(channel['value_max']-channel['value_min']) > 1e-5})
        print(bone, 'varying', varying, 'rotation_deg', round(summary['max_rotation_degrees_from_start'], 2), 'head_motion', round(summary['max_head_displacement_from_start'], 3), 'cycle_gap', round(summary['cycle_head_gap'], 6))
print('CONSTRAINTS', json.dumps({name: bone['constraints'] for name, bone in report['bones'].items() if bone['constraints']}))
