import bpy,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'deliverables/frontflip-refined/blender';OUT.mkdir(parents=True,exist_ok=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
camera=scene.camera;camera.animation_data_clear();camera.data.type='ORTHO';camera.data.ortho_scale=6.5
scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=2
scene.render.resolution_x=420;scene.render.resolution_y=480;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
for o in scene.objects:
 if o.get('graduate_role')=='Studio floor':o.hide_render=True
rows=[]
for i,frame in enumerate([10,25,45,60,80,97,106,126,151,177,202,217]):
 scene.frame_set(frame);bpy.context.view_layer.update()
 center=Vector((0,0,2.35));camera.location=center+Vector((10,-7,2.0))
 camera.rotation_euler=(center-camera.location).to_track_quat('-Z','Y').to_euler()
 scene.render.filepath=str(OUT/f'pose-{frame:03d}.png')
 bpy.ops.render.render(write_still=True)
 rows.append({'file':scene.render.filepath,'frame':frame,'seconds':(frame-1)/100})
(OUT/'poses.json').write_text(json.dumps(rows,indent=2),encoding='utf8')
print('REFINED_RENDER_DONE',flush=True)
