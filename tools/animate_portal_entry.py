"""Author a complete approach, anticipation, leap and fall into a procedural void."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix, Euler
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from build_void_portal import build_void_portal
from regalia_arm_clearance import adjust_current_arm_pose
OUT=ROOT/'art'/'Graduate'

def curves(action):
    return [fc for l in action.layers for st in l.strips for b in st.channelbags for fc in b.fcurves]

def values(rig):
    return {b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}

def mix(a,b,t):
    t=max(0,min(1,t));t=t*t*(3-2*t)
    return {n:(a[n][0].lerp(b[n][0],t),a[n][1].slerp(b[n][1],t),a[n][2].lerp(b[n][2],t)) for n in a}

def turn(pose,name,angles):
    loc,q,s=pose[name];pose[name]=(loc,(q@Euler(tuple(math.radians(a) for a in angles)).to_quaternion()).normalized(),s)

walk=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=walk;walk.frame_set(1)
bpy.ops.scene.new(type='FULL_COPY')
scene=bpy.context.scene;scene.name='03_PORTAL - Leap into the Void'
rig=next(o for o in scene.objects if o.type=='ARMATURE');rig.hide_set(False)
character=[o for o in scene.objects if o==rig or o.type=='MESH' and o.get('graduate_role') and o.get('graduate_role')!='Studio floor']
for o in character:
    if o.type=='MESH':
        o.data=o.data.copy()
        if o.data.shape_keys and o.data.shape_keys.animation_data and o.data.shape_keys.animation_data.action:
            o.data.shape_keys.animation_data.action=o.data.shape_keys.animation_data.action.copy()
# Copied studio objects belong only to this new scene; remove them from its view.
for o in list(scene.objects):
    if o not in character:
        o.hide_render=True;o.hide_set(True)
walk_action=rig.animation_data.action
walkposes=[]
for f in range(1,37):
    scene.frame_set(f);bpy.context.view_layer.update();walkposes.append(values(rig))

def sample(action,frame,clear_arms=False):
    for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
    rig.animation_data.action=action
    if action.slots:rig.animation_data.action_slot=action.slots[0]
    scene.frame_set(math.floor(frame),subframe=frame-math.floor(frame));bpy.context.view_layer.update()
    if clear_arms:adjust_current_arm_pose(rig)
    return values(rig)

idle_action=bpy.data.actions.get('Man_Idle')
idle=sample(idle_action,17)
adjust_current_arm_pose(rig)
idle=values(rig)
jump_action=next((a for a in bpy.data.actions if a.name=='Man_Jump'),None)
if jump_action is None:
    jump_action=next((a for a in bpy.data.actions if 'jump' in a.name.lower()),None)
if jump_action is None:raise RuntimeError('Original jump action must be inspected before authoring the leap.')
jstart,jend=jump_action.frame_range
jump_poses=[sample(jump_action,jstart+(jend-jstart)*i/60,True) for i in range(61)]

authored=[]
for f in range(1,151):
    if f<=60:p=walkposes[(f-1)%36]
    elif f<=72:p=mix(walkposes[59%36],idle,(f-60)/12)
    elif f<=86:
        j=int(14*(f-72)/14)
        p=mix(idle,jump_poses[j],min(1,(f-72)/5))
    elif f<=107:
        j=14+int(17*(f-86)/21)
        p={n:tuple(v.copy() for v in val) for n,val in jump_poses[j].items()}
    else:
        p=mix(jump_poses[31],jump_poses[43],(f-107)/16)
        turn(p,'Torso',(min(12,(f-107)*.5),0,0))
        turn(p,'Head',(-5,0,0))
        for side,sgn in [('L',1),('R',-1)]:
            turn(p,'UpperArm.'+side,(0,0,sgn*min(12,(f-107)*.5)))
    p={n:tuple(v.copy() for v in val) for n,val in p.items()}
    # Source jump raises Body and both foot IK targets together. Transfer
    # that shared lift to the authored root arc; retain the extra knee tuck.
    # The original crouch stays grounded through frame 86.
    if f>=87:
        lift=max(0,p['Body'][0].y-idle['Body'][0].y)
        p['Body'][0].y-=lift
        for side in ['L','R']:
            p['Foot.'+side][0].z-=lift/rig.data.bones['Foot.'+side].matrix_local.col[2].z
    authored.append(p)

rig.animation_data.action=bpy.data.actions.new('Graduate_Portal_Approach_Crouch_Leap_Fall')
action=rig.animation_data.action;action.use_fake_user=True
previous={}
for f,p in enumerate(authored,1):
    for n,(loc,q,s) in p.items():
        b=rig.pose.bones[n];b.rotation_mode='QUATERNION'
        if n in previous and q.dot(previous[n])<0:q.negate()
        previous[n]=q.copy();b.location=loc;b.rotation_quaternion=q;b.scale=s
        for channel in ['location','rotation_quaternion','scale']:b.keyframe_insert(channel,frame=f,group=n)
for fc in curves(action):
    for k in fc.keyframe_points:k.interpolation='LINEAR'

root=bpy.data.objects.new('Graduate | portal root trajectory',None);scene.collection.objects.link(root)
rig.parent=root
for f in range(1,151):
    if f<=60:root.location=(0,1.6-3.8*(f-1)/59,0)
    elif f<=86:root.location=(0,-2.2,0)
    else:
        t=(f-86)/30
        root.location=(.05*math.sin(t*2),-2.2-5*t,8.6*t-.5*(9.81/(1.75/4.8))*t*t)
    root.keyframe_insert('location',frame=f)
for fc in curves(root.animation_data.action):
    for k in fc.keyframe_points:k.interpolation='LINEAR'

# Retain the physically settled initial gown for the new one-shot cloth solve.
for o in character:
    if o.type=='MESH' and o.data.shape_keys and o.data.shape_keys.animation_data:
        for fc in curves(o.data.shape_keys.animation_data.action):
            for mod in list(fc.modifiers):fc.modifiers.remove(mod)
scene.frame_start=1;scene.frame_end=150;scene.render.fps=30;scene.frame_set(1)
environment=build_void_portal(scene,portal_y=-4,floor_z=-.026,opening_width=4,opening_height=6.5,approach_length=9,void_depth=30)
for name in ['Runway','Frame']:
    environment['objects'][name]['portal_cloth_collider']=True
for name in ['GoldLight','CyanLight']:
    mat=environment['materials'][name]
    for node in mat.node_tree.nodes:
        if node.type=='BSDF_PRINCIPLED':
            socket=node.inputs.get('Emission Strength')
            if socket:
                baseline=socket.default_value
                for frame,factor in [(1,1),(85,1),(99,1.8),(115,1.15),(140,1)]:
                    socket.default_value=baseline*factor;socket.keyframe_insert('default_value',frame=frame)

scene.world=scene.world.copy() if scene.world else bpy.data.worlds.new('Void world')
scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value=(.006,.009,.017,1);background.inputs[1].default_value=.35
camdata=bpy.data.cameras.new('Portal story camera');cam=bpy.data.objects.new('Portal story camera',camdata);scene.collection.objects.link(cam)
camdata.lens=36;camdata.clip_end=200
for f,pos,target in [(1,(11,8,6.8),(0,-2.5,3.1)),(78,(10.2,6.3,6.4),(0,-3.7,3.3)),(108,(9.4,4.3,6.4),(0,-5.3,3.0)),(150,(9,3.8,6.1),(0,-6,1.8))]:
    cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.keyframe_insert('location',frame=f);cam.keyframe_insert('rotation_euler',frame=f)
scene.camera=cam
def area(name,location,target,power,color,size):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(name,d);scene.collection.objects.link(o);o.location=location;o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Portal story | neutral key',(3,2,8),(0,-1,2.5),1250,(1,.95,.87),5)
area('Portal story | soft fill',(-5,1,5),(0,-2,2.5),750,(.85,.92,1),5)
scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.cycles.use_denoising=True
scene.render.resolution_x=800;scene.render.resolution_y=450;scene.render.resolution_percentage=100
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.image_settings.file_format='PNG'
for f,label in [(1,'Approach'),(73,'Anticipation'),(86,'Takeoff'),(98,'Cross doorway'),(113,'Fall into void'),(140,'Portal remains')]:
    marker=scene.timeline_markers.new(label,frame=f)
scene['Animation']='A full-body approach, grounded anticipation, coordinated arm swing, ballistic forward leap through the doorway, then a fall into the void.'
scene['Source motion']=jump_action.name+'; Quaternius CC0, locally tailored'
scene['Root trajectory']='Metre-calibrated gravity 9.81 m/s^2 after frame 86; no landing surface beyond doorway.'
rig.hide_set(True);scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Portal_Authored.blend'))
(OUT/'animation'/'portal-motion-design.json').write_text(json.dumps({'scene':scene.name,'frames':150,'fps':30,'jump_source':jump_action.name,'source_range':[jstart,jend],'takeoff_frame':86,'door_crossing_frame':98,'cloth_status':'awaiting one-shot solve'},indent=2),encoding='utf-8')
print('PORTAL_MOTION_AUTHORED',flush=True)
