"""Retime only Idle from four to three seconds, retaining every pose value.

Run with ordinary Python for the GLB; run inside Blender with --blend to
update scene timing. Blender's 120 stored samples now play at 40 fps.
"""
from pathlib import Path
from datetime import datetime, timezone
import hashlib, json, shutil, sys

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/Graduate'


def retime_blend():
    import bpy
    def curve_hashes():
        results = {}
        for action in bpy.data.actions:
            curves = [fc for layer in action.layers for strip in layer.strips
                      for bag in strip.channelbags for fc in bag.fcurves]
            payload = [(fc.data_path, fc.array_index,
                        [(list(k.co), list(k.handle_left), list(k.handle_right), k.interpolation)
                         for k in fc.keyframe_points]) for fc in curves]
            results[action.name] = hashlib.sha256(json.dumps(payload).encode()).hexdigest()
        return results
    before = curve_hashes()
    timing_before = {s.name: [s.frame_start, s.frame_end, s.render.fps, s.render.fps_base]
                     for s in bpy.data.scenes}
    scene = next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
    assert scene.frame_start == 1 and scene.frame_end == 120
    assert scene.render.fps / scene.render.fps_base == 30, 'Expected four-second source'
    scene.render.fps = 40
    scene.render.fps_base = 1
    scene['Animation'] = 'Readable 3-second breathing loop; anchored feet, 22 mm pelvic rise, chest/shoulder opening, delayed hands and restrained cloth.'
    scene['Loop'] = '1-120 at 40fps; 121 repeats 1. No root travel or disappearance.'
    text = bpy.data.texts.get('IDLE - Readable breathing')
    if text:
        text.clear()
        text.write('待機呼吸：04_IDLE，1–120 幀／40 fps，3 秒循環。\n幅度不變，雙腳固定，骨盆約 22 mm 起伏，胸肩、手腕與衣料同步加快。\nGodot：4 待機、1 走路、2 跑步、3 跳下消失、R 重播。\n')
    after = curve_hashes()
    assert before == after, 'Animation pose values changed'
    for s in bpy.data.scenes:
        if s != scene:
            assert timing_before[s.name] == [s.frame_start, s.frame_end, s.render.fps, s.render.fps_base]
    bpy.context.window.scene = scene
    scene.frame_set(1)
    bpy.context.preferences.filepaths.save_version = 0
    output = ART / 'Male_Graduate_Idle_Faster.blend'
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report = {'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
              'periodFrames': 120, 'fps': 40, 'durationSeconds': 3,
              'allActionCurvesUnchanged': before == after,
              'actionCount': len(before), 'otherSceneTimingUnchanged': True,
              'before': timing_before, 'output': str(output)}
    (ART / 'animation/idle-fast-blender-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print('IDLE_FAST_BLEND_DONE', json.dumps(report), flush=True)


def retime_glb():
    import numpy as np
    from export_graduate_godot import read_glb, write_glb, accessor_values, append_accessor, validate_glb
    path = ART / 'Godot/assets/graduate.glb'
    backup = ART / 'animation/graduate-before-idle-speed.glb'
    assert not backup.exists(), 'Do not replace the pre-speed backup'
    shutil.copy2(path, backup)
    document, binary = read_glb(path)
    before_bytes = bytes(binary)
    before_animations = json.loads(json.dumps(document['animations']))
    animation = next(a for a in document['animations'] if a['name'] == 'Idle')
    remap = {}
    for sampler in animation['samplers']:
        old = sampler['input']
        if old not in remap:
            times = accessor_values(document, binary, old, np)
            assert abs(float(times[-1, 0]) - 4) < 1e-5
            times *= .75
            remap[old] = append_accessor(document, binary, times, 'SCALAR', np, limits=True)
        sampler['input'] = remap[old]
    animation.setdefault('extras', {})['fps'] = 40
    animation['extras']['durationSeconds'] = 3
    assert binary[:len(before_bytes)] == before_bytes, 'Existing pose or geometry bytes changed'
    assert document['animations'][:3] == before_animations[:3], 'Other clips changed'
    assert [s['output'] for s in animation['samplers']] == [s['output'] for s in before_animations[3]['samplers']]
    candidate = path.with_name('graduate-idle-fast.tmp.glb')
    write_glb(candidate, document, binary)
    validation = validate_glb(candidate, np, 0)
    validation['file'] = str(path)
    report = {'generatedAtUtc': datetime.now(timezone.utc).isoformat(),
              'durationBeforeSeconds': 4, 'durationAfterSeconds': 3,
              'speedMultiplier': 4/3, 'originalBinaryPrefixUnchanged': True,
              'otherAnimationDefinitionsUnchanged': True,
              'idleOutputAccessorsUnchanged': True,
              'retimedInputAccessors': len(remap), 'glb': validation}
    candidate.replace(path)
    (ART / 'animation/idle-fast-glb-validation.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    old_report_path = path.with_name('graduate-export-validation.json')
    previous = json.loads(old_report_path.read_text(encoding='utf-8'))
    previous['idleTimingRevision'] = report
    previous['glb'] = validation
    old_report_path.write_text(json.dumps(previous, indent=2), encoding='utf-8')
    print('IDLE_FAST_GLB_DONE', json.dumps(report), flush=True)


if __name__ == '__main__':
    retime_blend() if '--blend' in sys.argv else retime_glb()
