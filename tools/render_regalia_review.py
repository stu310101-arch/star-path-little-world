"""Render a few clearly framed views from the currently loaded candidate."""
from pathlib import Path
import bpy,sys
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'art/Graduate/animation/regalia-review';out.mkdir(exist_ok=True)
shots=[('04_IDLE',51,'idle_front',(3,-12,5.4)),('04_IDLE',51,'idle_back',(-3,12,5.4)),('02_RUN',7,'run_front',(3,-12,5.4)),('03_JUMP',27,'jump_front',(3,-12,5.4))]
if '--checkpoint-walk' in sys.argv:
    shots=[('01_WALK',1,'walk_front',(3,-12,5.4)),('01_WALK',9,'walk_side',(12,-3,5.4)),('01_WALK',19,'walk_contact',(3,-12,5.4)),('01_WALK',36,'walk_back',(-3,12,5.4))]
if '--worst' in sys.argv:
    shots=[('04_IDLE',103,'idle_cuff_close',(3,-12,5.4)),('02_RUN',19,'run_layers_close',(3,-12,5.4)),('02_RUN',16,'run_arm_close',(-8,-12,5.4))]
for prefix,frame,label,camera in shots:
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix));bpy.context.window.scene=scene;scene.frame_set(frame)
    bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();bounds=[]
    for obj in scene.objects:
        if obj.type=='MESH' and obj.get('graduate_role') and obj.get('graduate_role')!='Studio floor' and not obj.get('preview_fx'):
            ev=obj.evaluated_get(dg);bounds.extend(ev.matrix_world@Vector(c) for c in ev.bound_box)
    lo=Vector(tuple(min(p[i] for p in bounds) for i in range(3)));hi=Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    target=(lo+hi)*.5
    scene.camera.location=Vector(camera)-Vector((0,0,2.65))+target;scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
    scene.camera.data.type='ORTHO';scene.camera.data.ortho_scale=max(5.8,(hi.z-lo.z)*1.2)
    if '--worst' in sys.argv:
        target.z=lo.z+(hi.z-lo.z)*.65
        scene.camera.location=Vector(camera)-Vector((0,0,2.65))+target;scene.camera.rotation_euler=(target-scene.camera.location).to_track_quat('-Z','Y').to_euler()
        scene.camera.data.ortho_scale=3.6
    scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.cycles.device='CPU'
    scene.render.threads_mode='FIXED';scene.render.threads=3
    scene.render.resolution_x=640;scene.render.resolution_y=768;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format='PNG';scene.render.filepath=str(out/(label+'.png'))
    bpy.ops.render.render(write_still=True)
    print('REGALIA_RENDER_DONE',label,flush=True)
