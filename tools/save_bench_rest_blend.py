"""Save the delivered rest morphs as a small editable Blender source.

Run only after the native game review. This imports the NEW rest asset into
an empty background Blender process; original character .blend files are
never opened or overwritten.
"""
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'game/assets/character/graduate_rest.glb'))
scene=bpy.context.scene
scene.name='Bench rest - editable morph poses'
scene.render.fps=30
scene.frame_start=1
scene.frame_end=133
for obj in scene.objects:
    if obj.type!='MESH' or not obj.data.shape_keys:continue
    keys=obj.data.shape_keys.key_blocks
    for frame,amount in [(1,0),(37,1),(97,1),(133,0)]:
        sample=amount*12
        for index,key in enumerate(list(keys)[1:]):
            key.value=1.0 if index+1==sample else 0.0
            key.keyframe_insert('value',frame=frame)
    # Each authored pose is traversed; no single large linear squash.
    for sample in range(1,12):
        for frame in [1+sample*3,133-sample*3]:
            for index,key in enumerate(list(keys)[1:]):
                key.value=1.0 if index+1==sample else 0.0
                key.keyframe_insert('value',frame=frame)
for frame,name in [(1,'Standing'),(37,'Seated: feet planted, hands on lap'),(97,'Rise'),(133,'Standing')]:
    scene.timeline_markers.new(name,frame=frame)
for action in bpy.data.actions:
    for layer in action.layers:
        for strip in layer.strips:
            for bag in strip.channelbags:
                for curve in bag.fcurves:
                    for key in curve.keyframe_points:key.interpolation='LINEAR'
text=bpy.data.texts.new('READ ME - Bench rest source')
text.write('Editable rest garment morphs derived from the delivered graduate Idle.\n'
           '12 corrective samples; timeline 1-37 sit, 37-97 rest, 97-133 rise.\n'
           'Reference bench top: 0.52 m. Character -Y front in Blender (+Z Godot).\n'
           'Original graduate rig, walking and frontflip sources remain unchanged.\n'
           'Regenerate with tools/author_bench_rest.py; integrate via bench_pose.gd.\n')
scene.frame_set(37)
bpy.context.preferences.filepaths.save_version=0
path=ROOT/'art/Graduate/Male_Graduate_Bench_Rest.blend'
bpy.ops.wm.save_as_mainfile(filepath=str(path))
print('BENCH_REST_SOURCE',path,flush=True)
