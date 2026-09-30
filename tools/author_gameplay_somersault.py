"""Author an independent, editable graduate forward somersault; preserve the master.

Run against Male_Graduate_GameReady.blend. All changes live only in the new
Male_Graduate_ForwardSomersault.blend. No physical trajectory is in the asset:
the rig transform only rotates about the hips, with pivot compensation.
"""
import bpy, sys, math, json, hashlib
from pathlib import Path
import numpy as np
from mathutils import Matrix, Vector, Euler

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SkinBinding, evaluated_points, fcurves, SCALE, bake_keys

OUT=ROOT/'art/Graduate/Male_Graduate_ForwardSomersault.blend'
REPORT=ROOT/'deliverables/gameplay-jump'
REPORT.mkdir(parents=True,exist_ok=True)
SOURCE=Path(bpy.data.filepath)
source_hash=hashlib.sha256(SOURCE.read_bytes()).hexdigest()
source=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
bpy.context.window.scene=source
source.frame_set(1)
bpy.ops.scene.new(type='FULL_COPY')
scene=bpy.context.scene
scene.name='05_FORWARD_SOMERSAULT - Space Jump'
rig=next(o for o in scene.objects if o.type=='ARMATURE')
meshes=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and o.get('graduate_role')!='Studio floor' and not o.get('preview_fx')]
for o in [rig,*meshes]:
    o.hide_set(False);o.hide_viewport=False;o.hide_render=False
scene.frame_set(1);bpy.context.view_layer.update()
neutral_pose={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
neutral_rig=rig.matrix_world.copy()
neutral_feet={s:rig.pose.bones['Foot.'+s].matrix.copy() for s in ['L','R']}
neutral_arms={n:rig.pose.bones[n].matrix.copy() for n in ['UpperArm.L','LowerArm.L','UpperArm.R','LowerArm.R']}
neutral_points={o.get('graduate_role'):evaluated_points(o) for o in meshes}
cloth=[];neutral={}
for o in meshes:
    if not o.data.shape_keys:continue
    # Preserve the current physical Idle0 surface exactly before authoring.
    neutral[o]=np.asarray(SkinBinding(o,rig).inverse_points(evaluated_points(o)),dtype=np.float64)
    o.shape_key_clear();o.data.vertices.foreach_set('co',neutral[o].ravel());o.data.update()
    cloth.append(o)
for o in [rig,*meshes]:o.animation_data_clear()
if rig.parent:
    mat=rig.matrix_world.copy();rig.parent=None;rig.matrix_world=mat
for o in list(scene.objects):
    if o.get('preview_fx') or o.get('graduate_root'):bpy.data.objects.remove(o,do_unlink=True)
for o in scene.objects:
    if o.type in {'CAMERA','LIGHT'}:o.animation_data_clear()
scene.render.fps=100;scene.render.fps_base=1
scene.frame_start=1;scene.frame_end=94
rig.animation_data_create()
rig.animation_data.action=bpy.data.actions.new('Graduate_ForwardSomersault_FullBody')
rig.animation_data.action.use_fake_user=True
COM=Vector((0,-.05,2.35))

def smooth(v):
    v=max(0.,min(1.,v));return v*v*(3-2*v)

def keycurve(t,keys):
    if t<=keys[0][0]:return keys[0][1]
    for (a,x),(b,y) in zip(keys,keys[1:]):
        if t<=b:return x+(y-x)*smooth((t-a)/(b-a))
    return keys[-1][1]

def parameters(t):
    return {
      'angle':keycurve(t,[(0,0),(.12,0),(.24,35),(.36,125),(.47,250),(.60,344),(.69,360),(.93,360)]),
      'tuck':keycurve(t,[(0,0),(.12,0),(.24,.42),(.36,1),(.46,1),(.59,.25),(.69,0),(.93,0)]),
      'squat':keycurve(t,[(0,0),(.09,.34),(.12,.19),(.19,0),(.69,0),(.755,.34),(.82,.17),(.93,0)]),
      'lean':keycurve(t,[(0,0),(.10,13),(.18,2),(.29,11),(.44,19),(.60,3),(.69,2),(.755,12),(.93,0)]),
      'arms':keycurve(t,[(0,0),(.10,.28),(.19,.50),(.32,1),(.49,1),(.61,.42),(.69,.34),(.76,.48),(.93,0)]),
      'cloth':keycurve(t,[(0,0),(.12,-.25),(.25,.68),(.39,1),(.52,.75),(.66,-.32),(.76,-.12),(.85,.20),(.93,0)])}

def turn(name,x=0,y=0,z=0):
    b=rig.pose.bones[name]
    b.rotation_mode='QUATERNION'
    b.rotation_quaternion=(b.rotation_quaternion@Euler(tuple(math.radians(v) for v in (x,y,z)),'XYZ').to_quaternion()).normalized()

def aim_bone(name,direction,amount):
    b=rig.pose.bones[name]
    current=b.matrix.copy()
    q=current.to_quaternion()
    desired=(q@Vector((0,1,0))).rotation_difference(Vector(direction).normalized())@q
    b.matrix=Matrix.LocRotScale(current.translation,q.slerp(desired,amount),current.to_scale())
    bpy.context.view_layer.update()

def pose(t):
    p=parameters(t)
    rig.matrix_world=neutral_rig
    for name,mat in neutral_pose.items():rig.pose.bones[name].matrix_basis=mat
    rig.pose.bones['Body'].location.y-=p['squat']
    turn('Abdomen',x=p['lean']*.45)
    turn('Torso',x=p['lean']*.55)
    turn('Neck',x=p['tuck']*4)
    turn('Head',x=p['tuck']*7-p['lean']*.30)
    bpy.context.view_layer.update()
    for side,sign in [('L',1),('R',-1)]:
        foot=neutral_feet[side].copy()
        # Lift both heels into a real IK knee fold, keeping a slightly staggered silhouette.
        foot.translation+=Vector((sign*.05*p['tuck'],-.63*p['tuck'],1.35*p['tuck']))
        rig.pose.bones['Foot.'+side].matrix=foot
        bpy.context.view_layer.update()
        aim_bone('UpperArm.'+side,(sign*.34,-.66,-.67),p['arms'])
        aim_bone('LowerArm.'+side,(-sign*.12,-.76,.64),p['arms'])
        turn('Palm.'+side,x=7*p['tuck'],z=-sign*5*p['tuck'])
    # A complete forward rotation around the COM, NOT the foot root.
    roll=Matrix.Rotation(math.radians(p['angle']),4,'X')
    rig.matrix_world=Matrix.Translation(COM)@roll@Matrix.Translation(-COM)@neutral_rig
    bpy.context.view_layer.update()
    return p

samples={o:[] for o in cloth}
pose_report=[]
for frame in range(1,95):
    t=(frame-1)/100
    p=pose(t)
    for o in cloth:
        base=neutral[o];points=base.copy();role=o.get('graduate_role')
        # Hand-authored follow-through in the existing cloth's bind space.
        # Attachment rows stay fixed; free hems lag the takeoff and the unfolding.
        if role.startswith(('01 |','03 |','04 |')):
            free=np.clip((3.25-base[:,2])/2.35,0,1)
            free=free*free
            points[:,0]+=base[:,0]*free*(.11*p['tuck']+.045*abs(p['cloth']))
            points[:,1]-=free*(.26*p['tuck']+.12*p['cloth'])
            points[:,2]+=free*(.90*p['tuck']+.15*p['cloth'])
        elif role.startswith('02 |'):
            free=np.clip(np.arange(len(base))//32/16,0,1)**2
            points[:,1]-=free*(.14*p['cloth']+.10*p['tuck'])
            points[:,2]+=free*.11*p['cloth']
        elif role.startswith(('09 |','10 |','11 |')):
            free=np.clip((4.85-base[:,2])/.65,0,1)
            points[:,1]+=free*.14*p['cloth']
            points[:,0]+=free*.035*p['cloth']
        samples[o].append(points)
    for b in rig.pose.bones:
        b.rotation_mode='QUATERNION'
        for channel in ('location','rotation_quaternion','scale'):b.keyframe_insert(channel,frame=frame,group=b.name)
    rig.rotation_mode='QUATERNION'
    for channel in ('location','rotation_quaternion','scale'):rig.keyframe_insert(channel,frame=frame)
    pose_report.append({'frame':frame,'t':t,**p})
for curve in fcurves(rig.animation_data.action):
    for k in curve.keyframe_points:k.interpolation='LINEAR'
for o in cloth:bake_keys(o,samples[o],1,'ForwardSomersault_'+o.get('graduate_role'))
for marker in list(scene.timeline_markers):scene.timeline_markers.remove(marker)
for f,label in [(1,'JumpStart | Idle0'),(13,'Physical takeoff at .12 s'),(25,'JumpAir | 35 degrees'),(43,'Tuck through apex'),(70,'JumpLand | feet down, wait for physical contact'),(77,'Landing compression'),(94,'Idle0 / recovered')]:scene.timeline_markers.new(label,frame=f)
scene['motion_contract']='JumpStart .24 / JumpAir .45 non-loop / JumpLand .24. Physics takeoff .12, flight7.8m/s gravity18. Asset has no trajectory; rig COM-pivot compensation must remain.'
scene['cloth_method']='Authored pinned-attachment secondary shapes, not a new cloth simulation. Existing evaluated Idle0 is the exact boundary pose.'
scene['source_master_sha256']=source_hash
scene.frame_set(1);bpy.context.view_layer.update()
seams={}
for o in meshes:
    r=o.get('graduate_role');seams[r]=float(np.max(np.linalg.norm(evaluated_points(o)-neutral_points[r],axis=1)))
scene.frame_set(94);bpy.context.view_layer.update()
end_seams={}
for o in meshes:
    r=o.get('graduate_role');end_seams[r]=float(np.max(np.linalg.norm(evaluated_points(o)-neutral_points[r],axis=1)))
assert max(seams.values())<1e-5,seams
assert max(end_seams.values())<1e-5,end_seams

# Keep this deliverable small and editable: only the new scene, with original
# rig controls and separate cloth keys. No original disk asset is saved.
for old in list(bpy.data.scenes):
    if old!=scene:bpy.data.scenes.remove(old)
bpy.ops.outliner.orphans_purge(do_recursive=True)
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
assert hashlib.sha256(SOURCE.read_bytes()).hexdigest()==source_hash
report={'source':str(SOURCE),'source_sha256':source_hash,'source_unchanged':True,'output':str(OUT),
 'clips':[{'name':'JumpStart','startFrame':1,'endFrame':25,'seconds':.24},{'name':'JumpAir','startFrame':25,'endFrame':70,'seconds':.45,'loop':False},{'name':'JumpLand','startFrame':70,'endFrame':94,'seconds':.24}],
 'rotation_axis':'Blender +X (forward over -Y)','pivot_source_units':list(COM),'body_scale':SCALE,
 'start_Idle0_error_metres':seams,'end_Idle0_error_metres':end_seams,'poses':pose_report,
 'cloth_method':scene['cloth_method'],'validation':'Boundary geometry exact; render and engine review required.'}
(REPORT/'authored-motion.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('FORWARD_SOMERSAULT_AUTHORED '+str(OUT),flush=True)
