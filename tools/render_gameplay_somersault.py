"""Eight real Blender camera renders of the authored COM-centred motion."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'deliverables/gameplay-jump/blender-poses';OUT.mkdir(parents=True,exist_ok=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
camera=scene.camera
camera.animation_data_clear();camera.data.type='ORTHO';camera.data.ortho_scale=6.7
scene.render.engine='CYCLES';scene.cycles.samples=6;scene.cycles.use_denoising=True;scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=3
scene.render.resolution_x=420;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
for o in scene.objects:
    if o.get('graduate_role')=='Studio floor':o.hide_render=True
items=[]
for index,frame in enumerate([1,10,25,38,49,60,77,94]):
    scene.frame_set(frame);bpy.context.view_layer.update()
    t=(frame-1)/100
    # Review the asset in place; the game, not this clip, adds its trajectory.
    center=Vector((0,0,2.35))
    camera.location=center+Vector((10,-7,2.2))
    camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(OUT/f'{index+1:02d}-frame-{frame:03d}.png')
    bpy.ops.render.render(write_still=True)
    items.append({'file':str(scene.render.filepath),'frame':frame,'time':t,'view':'COM-centred in-place asset'})
(OUT/'poses.json').write_text(json.dumps(items,indent=2),encoding='utf8')
print('SOMERSAULT_POSES_DONE',flush=True)
