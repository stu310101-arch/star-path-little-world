"""A reusable vertical jump/drop, with no doorway or environment assets."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from regalia_arm_clearance import adjust_current_arm_pose
OUT=ROOT/'art'/'Graduate'
SCALE=1.75/4.8

def curves(action):
    return [fc for l in action.layers for st in l.strips for b in st.channelbags for fc in b.fcurves]
def values(rig):
    return {b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}
def copy_pose(p):
    return {n:tuple(v.copy() for v in val) for n,val in p.items()}
def mix(a,b,t):
    t=max(0,min(1,t));t=t*t*(3-2*t)
    return {n:(a[n][0].lerp(b[n][0],t),a[n][1].slerp(b[n][1],t),a[n][2].lerp(b[n][2],t)) for n in a}
def turn(pose,name,angles):
    loc,q,s=pose[name];pose[name]=(loc,(q@Euler(tuple(math.radians(a) for a in angles)).to_quaternion()).normalized(),s)

assert all(not s.name.startswith('03_') for s in bpy.data.scenes), 'Use the clean two-scene RunCloth candidate.'
walk=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=walk;walk.frame_set(1)
bpy.ops.scene.new(type='FULL_COPY')
scene=bpy.context.scene;scene.name='03_JUMP - Drop and Vanish'
rig=next(o for o in scene.objects if o.type=='ARMATURE');rig.hide_set(False)
character=[o for o in scene.objects if o==rig or o.type=='MESH' and o.get('graduate_role') and o.get('graduate_role')!='Studio floor']
for o in character:
    if o.type=='MESH':
        o.data=o.data.copy()
        if o.data.shape_keys and o.data.shape_keys.animation_data and o.data.shape_keys.animation_data.action:
            o.data.shape_keys.animation_data.action=o.data.shape_keys.animation_data.action.copy()
for o in list(scene.objects):
    if o not in character and o.type not in {'CAMERA','LIGHT'}:
        bpy.data.objects.remove(o,do_unlink=True)

def sample(action,frame):
    for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
    rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
    adjust_current_arm_pose(rig)
    return values(rig)

idle=sample(bpy.data.actions['Man_Idle'],17)
jump_action=bpy.data.actions['Man_Jump']
authored=[]
for f in range(1,73):
    k=min(f,44)
    if k<=6:p=copy_pose(idle)
    elif k<=18:p=mix(idle,sample(jump_action,6*(k-6)/12),min(1,(k-6)/4))
    elif k<=31:p=sample(jump_action,6+7*(k-18)/13)
    else:
        p=mix(sample(jump_action,13),sample(jump_action,17),(k-31)/13)
        turn(p,'Torso',(6*(k-31)/13,0,0))
        turn(p,'Head',(-5*(k-31)/13,0,0))
        for side,sgn in [('L',1),('R',-1)]:
            turn(p,'UpperArm.'+side,(0,0,sgn*9*(k-31)/13))
    p=copy_pose(p)
    if k>=19:
        lift=max(0,p['Body'][0].y-idle['Body'][0].y)
        p['Body'][0].y-=lift
        for side in ['L','R']:
            p['Foot.'+side][0].z-=lift/rig.data.bones['Foot.'+side].matrix_local.col[2].z
    authored.append(p)
rig.animation_data.action=bpy.data.actions.new('Graduate_JumpDown_FullBody')
action=rig.animation_data.action;action.use_fake_user=True
previous={}
for f,p in enumerate(authored,1):
    for n,(loc,q,s) in p.items():
        b=rig.pose.bones[n];b.rotation_mode='QUATERNION'
        if n in previous and q.dot(previous[n])<0:q.negate()
        previous[n]=q.copy();b.location=loc;b.rotation_quaternion=q;b.scale=s
        for channel in ['location','rotation_quaternion','scale']:b.keyframe_insert(channel,frame=f,group=n)
for fc in curves(action):
    for key in fc.keyframe_points:key.interpolation='LINEAR'
root=bpy.data.objects.new('Graduate | JumpDown root',None);scene.collection.objects.link(root)
root['graduate_root']=True;rig.parent=root
for f in range(1,73):
    t=max(0,(min(f,44)-19)/30)
    root.location=(0,0,(2.6*t-.5*9.81*t*t)/SCALE)
    root.keyframe_insert('location',frame=f)
for fc in curves(root.animation_data.action):
    for key in fc.keyframe_points:key.interpolation='LINEAR'
for o in character:
    if o.type=='MESH' and o.data.shape_keys and o.data.shape_keys.animation_data:
        for fc in curves(o.data.shape_keys.animation_data.action):
            for mod in list(fc.modifiers):fc.modifiers.remove(mod)
scene.frame_start=1;scene.frame_end=72;scene.render.fps=30
scene.camera.animation_data_clear()
scene.camera.data.type='ORTHO';scene.camera.data.ortho_scale=7.1
scene.camera.location=(8,-17,6.0)
scene.camera.rotation_euler=(Vector((0,0,1.35))-scene.camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=6
scene.cycles.use_denoising=True
scene.render.resolution_x=540;scene.render.resolution_y=640;scene.render.resolution_percentage=100
scene.render.threads_mode='FIXED';scene.render.threads=4
scene['Animation']='Reusable vertical jump and drop; full-body anticipation, arm swing, knee tuck and downward follow-through. No doorway, portal, floor or level geometry.'
scene['Godot events']='Flash at 1.300000 s / frame 40; hide visual at 1.333333 s / frame 41. Effects run separately from the skeletal/morph animation.'
scene['Root trajectory']='Vertical-only movement, 2.6 m/s takeoff, gravity 9.81 m/s^2; 1 model unit = 1.75/4.8 metres.'
for marker in list(scene.timeline_markers):scene.timeline_markers.remove(marker)
for f,label in [(1,'Ready'),(7,'Anticipation'),(19,'Takeoff'),(27,'Apex'),(35,'Drop'),(40,'FLASH - Godot event'),(41,'HIDE - Godot event'),(60,'Particles end')]:
    scene.timeline_markers.new(label,frame=f)
scene.frame_set(1);rig.hide_set(True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Jump_Authored.blend'))
(OUT/'animation'/'jump-motion-design.json').write_text(json.dumps({'scene':scene.name,'frames':72,'fps':30,'takeoff_frame':19,'flash_frame':40,'hide_frame':41,'flash_seconds':1.3,'hide_seconds':40/30,'jump_source':'Man_Jump','portal_assets':False,'horizontal_root_motion':False,'gravity_m_s2':9.81,'takeoff_velocity_m_s':2.6},indent=2),encoding='utf-8')
print('JUMP_DOWN_AUTHORED',flush=True)
