"""Build game-readable breathing from BeforeIdle; preserve the other clips."""
import bpy,sys,math,json,hashlib
import numpy as np
from pathlib import Path
from mathutils import Euler,Vector
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SCALE,SkinBinding,evaluated_points,fcurves
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import visible_surfaces

PERIOD=120
IDLE_FPS=56
def sample_hashes():
    result={}
    for sc in bpy.data.scenes:
        if not sc.name.startswith(('01_WALK','02_RUN','03_JUMP')):continue
        obs=[o for o in sc.objects if o.type=='MESH' and o.get('graduate_role') and not o.get('preview_fx') and o.get('graduate_role')!='Studio floor']
        with visible_surfaces(sc,obs,'rendered'):
            digest=hashlib.sha256()
            for f in [1,sc.frame_end//2,sc.frame_end]:
                sc.frame_set(f);bpy.context.view_layer.update()
                for o in sorted(obs,key=lambda o:o.get('graduate_role')):
                    digest.update(evaluated_points(o).astype('<f4').tobytes())
            result[sc.name]=digest.hexdigest()
    return result

assert not any(s.name.startswith('04_IDLE') for s in bpy.data.scenes),'Input already has Idle'
before=sample_hashes()
source=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
bpy.context.window.scene=source;source.frame_set(1)
bpy.ops.scene.new(type='FULL_COPY');scene=bpy.context.scene;scene.name='04_IDLE - Breathing'
rig=next(o for o in scene.objects if o.type=='ARMATURE')
meshes=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and not o.get('preview_fx') and o.get('graduate_role')!='Studio floor']
rig.hide_set(False)
for o in meshes:
    o.data=o.data.copy()
    o.hide_set(False);o.hide_viewport=False;o.hide_render=False
scene.frame_set(1);bpy.context.view_layer.update()
base_pose={b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}
cloth=[];neutral={}
with visible_surfaces(scene,meshes,'simulation'):
    for o in meshes:
        if o.data.shape_keys:
            neutral[o]=np.asarray(SkinBinding(o,rig).inverse_points(evaluated_points(o)),dtype=np.float64)
            cloth.append(o)
    for o in cloth:
        o.shape_key_clear();o.data.vertices.foreach_set('co',neutral[o].ravel());o.data.update()
for o in [rig,*meshes]:o.animation_data_clear()
if rig.parent:
    matrix=rig.matrix_world.copy();rig.parent=None;rig.matrix_world=matrix
for o in list(scene.objects):
    if o.get('preview_fx') or o.get('graduate_root'):
        bpy.data.objects.remove(o,do_unlink=True)
for o in scene.objects:
    if o.type in {'CAMERA','LIGHT'}:o.animation_data_clear()

rig.animation_data_create();action=bpy.data.actions.new('Graduate_Idle_Breathing_FullBody')
rig.animation_data.action=action;action.use_fake_user=True
def breath_at(t):
    t=t%1
    return .5-.5*math.cos(math.pi*t/.42) if t<.42 else .5+.5*math.cos(math.pi*(t-.42)/.58)
def turn(name,x=0.,y=0.,z=0.):
    b=rig.pose.bones[name];b.rotation_quaternion=(b.rotation_quaternion@Euler(tuple(math.radians(v) for v in (x,y,z)),'XYZ').to_quaternion()).normalized()
for i in range(PERIOD+1):
    t=(i%PERIOD)/PERIOD;p=math.tau*t;b=breath_at(t)
    for name,(loc,q,scale) in base_pose.items():
        bone=rig.pose.bones[name];bone.rotation_mode='QUATERNION'
        bone.location=loc;bone.rotation_quaternion=q;bone.scale=scale
    # The feet/pole targets remain exactly constant. Body's local Y is up.
    rig.pose.bones['Body'].location.y+=.022/SCALE*b
    rig.pose.bones['Body'].location.x+=.004/SCALE*math.sin(p)
    turn('Body',z=.32*math.sin(p))
    turn('Abdomen',x=-.75*b)
    turn('Torso',x=-1.65*b,y=.35*math.sin(p))
    rig.pose.bones['Torso'].scale=(1+.018*b,1+.012*b,1+.035*b)
    turn('Neck',x=.80*b)
    turn('Head',x=.60*b,z=-.24*math.sin(p))
    for side,sign in [('L',1),('R',-1)]:
        turn('Shoulder.'+side,z=sign*.80*b)
        # The larger chest/shoulder motion already carries the hands. Extra
        # elbow swing was causing the tailored left cuff to touch the wrist.
        turn('UpperArm.'+side,x=.15*math.sin(p-.16),z=sign*.10*b)
        turn('LowerArm.'+side,x=.22*math.sin(p-.24))
        turn('Palm.'+side,y=sign*.32*math.sin(p-.35))
    for bone in rig.pose.bones:
        for channel in ('location','rotation_quaternion','scale'):
            bone.keyframe_insert(channel,frame=i+1,group=bone.name)
for fc in fcurves(action):
    for k in fc.keyframe_points:k.interpolation='LINEAR'
    fc.modifiers.new('CYCLES')

# Start from the verified neutral garment. Breathing introduces restrained
# delayed cloth changes; no walk stride or jump hide keys are carried over.
for o in cloth:
    base=neutral[o];role=o.get('graduate_role');poses=[]
    for i in range(PERIOD):
        p=math.tau*i/PERIOD;lag=math.sin(p-.30)-math.sin(-.30)
        points=base.copy()
        if role.startswith('02 | Bell sleeve'):
            for row in range(17):
                free=(row/16)**2
                points[row*32:(row+1)*32,1]+=.0018/SCALE*free*lag
                points[row*32:(row+1)*32,2]+=.0012/SCALE*free*(math.cos(p-.30)-math.cos(-.30))
        elif role.startswith(('01 |','03 |','04 |')):
            hanging=np.clip((3.0-base[:,2])/1.5,0,1)
            points[:,1]+=.0020/SCALE*hanging*lag
            points[:,2]+=.0030/SCALE*hanging*breath_at((i/PERIOD-.035)%1)
        elif role.startswith(('09 |','10 |','11 |')):
            hanging=np.clip((4.8-base[:,2])/.7,0,1)
            points[:,0]+=.0015/SCALE*hanging*lag
        poses.append(points)
    bake_loop(o,poses,'Graduate_Idle_Breathing_'+role)

scene.frame_start=1;scene.frame_end=PERIOD;scene.render.fps=IDLE_FPS;scene.render.fps_base=1
for marker in list(scene.timeline_markers):scene.timeline_markers.remove(marker)
for frame,label in [(1,'Exhale / loop start'),(51,'Inhale'),(121,'Loop seam')]:scene.timeline_markers.new(label,frame=frame)
scene['Animation']='Readable 15/7-second breathing loop; anchored feet, 22 mm pelvic rise, chest/shoulder opening, delayed hands and restrained cloth.'
scene['Loop']='1-120 at 56fps; 121 repeats 1. Run repair_graduate_regalia.py after authoring to enforce clothing layering.'
scene.camera.data.type='ORTHO';scene.camera.data.ortho_scale=5.9
scene.camera.location=(6,-15,5.7);scene.camera.rotation_euler=(Vector((0,0,2.5))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.resolution_x=720;scene.render.resolution_y=720;scene.render.resolution_percentage=100
scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.use_denoising=True;scene.cycles.device='CPU'
scene.render.threads_mode='FIXED';scene.render.threads=4

after=sample_hashes();assert before==after,{'existing_clips_changed':(before,after)}
bpy.context.window.scene=scene
measure={name:[] for name in ['Body','Torso','Head','Foot.L','Foot.R','Palm.L','Palm.R']}
surface_seams={};first={}
with visible_surfaces(scene,meshes,'simulation'):
    for frame in range(1,PERIOD+2):
        scene.frame_set(frame);bpy.context.view_layer.update()
        for name in measure:measure[name].append(np.asarray(rig.matrix_world@rig.pose.bones[name].head)*SCALE)
        if frame in [1,PERIOD+1]:
            for o in meshes:
                points=evaluated_points(o)
                if frame==1:first[o]=points
                else:surface_seams[o.get('graduate_role')]=float(np.linalg.norm(points-first[o],axis=1).max())
spans={name:np.ptp(np.asarray(v),axis=0).tolist() for name,v in measure.items()}
assert max(spans['Foot.L']+spans['Foot.R'])<1e-5,spans
assert max(surface_seams.values())<1e-5,surface_seams
report={'scene':scene.name,'action':action.name,'period_frames':PERIOD,'fps':IDLE_FPS,'duration_seconds':PERIOD/IDLE_FPS,
        'bone_head_span_metres':spans,'surface_loop_seam_metres':surface_seams,
        'existing_clip_hashes_before':before,'existing_clip_hashes_after':after,
        'existing_clips_preserved':before==after,'method':'Authored readable breathing and restrained delayed garment shapes; planted foot IK',
        'reference_video':'https://www.youtube.com/watch?v=L4YX8Zosw-Q',
        'reference_note':'Chest/shoulder motion and delayed hands observed; our numerical amplitudes are art-directed, not measurements of the reference.'}
baseline_path=ROOT/'art/Graduate/animation/idle-motion-subtle-baseline.json'
if baseline_path.exists():
    baseline=json.loads(baseline_path.read_text(encoding='utf-8'))
    assert baseline['existing_clip_hashes_after']==after,'Existing clips differ from previous delivery'
    report['previous_body_z_span_m']=baseline['bone_head_span_metres']['Body'][2]
    report['body_z_amplitude_ratio']=spans['Body'][2]/report['previous_body_z_span_m']
    assert report['body_z_amplitude_ratio']>4.0
(ROOT/'art/Graduate/animation/idle-motion-validation.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
scene.frame_set(1);rig.hide_set(True)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            sp=area.spaces.active;sp.shading.type='SOLID';sp.shading.color_type='MATERIAL'
            sp.region_3d.view_location=(0,0,2.6);sp.region_3d.view_distance=6.5
            sp.region_3d.view_rotation=Vector((4,-12,3)).to_track_quat('Z','Y')
text=bpy.data.texts.get('IDLE - Readable breathing') or bpy.data.texts.new('IDLE - Readable breathing')
text.clear();text.write('待機呼吸：04_IDLE，1–120 幀／56 fps，約 2.14 秒循環。\n雙腳固定，骨盆約 22 mm 起伏，加強胸肩展開，手腕與衣料延遲跟隨。\n製作後請執行 repair_graduate_regalia.py 修正服裝層次。\nGodot：4 待機、1 走路、2 跑步、3 跳下消失、R 重播。\n')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_Idle_Readable.blend'))
print('GRADUATE_IDLE_SAVED',json.dumps(report),flush=True)
