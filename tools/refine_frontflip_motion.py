"""Re-author the existing somersault copy; preserve all original master assets.

100 Hz source: start 0-.24, air .24-.96, landing and drape .96-2.16.
Run on the timestamped pre-revision somersault, then simulate_frontflip_drape.py.
"""
import bpy, sys, math, json
from pathlib import Path
import numpy as np
from mathutils import Matrix, Vector, Euler
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SkinBinding,evaluated_points,fcurves,SCALE
OUT=ROOT/'art/Graduate/Male_Graduate_Frontflip_Refined_Authored.blend'
REPORT=ROOT/'deliverables/frontflip-refined'
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
scene.frame_set(1);bpy.context.view_layer.update()
rig=next(o for o in scene.objects if o.type=='ARMATURE')
meshes=[o for o in scene.objects if o.type=='MESH' and o.get('graduate_role') and o.get('graduate_role')!='Studio floor']
states=[(m,m.show_viewport) for o in meshes for m in o.modifiers if m.type!='ARMATURE']
for m,_ in states:m.show_viewport=False
neutral={b.name:b.matrix_basis.copy() for b in rig.pose.bones}
world=rig.matrix_world.copy()
feet={s:rig.pose.bones['Foot.'+s].matrix.copy() for s in ['L','R']}
for o in meshes:
 if o.data.shape_keys:
  points=np.asarray(SkinBinding(o,rig).inverse_points(evaluated_points(o)))
  o.shape_key_clear();o.data.vertices.foreach_set('co',points.ravel());o.data.update()
for o in [rig,*meshes]:o.animation_data_clear()
for m,vis in states:m.show_viewport=vis
rig.animation_data_create();rig.animation_data.action=bpy.data.actions.new('Refined_Frontflip_ContinuousMomentum')
scene.render.fps=100;scene.render.fps_base=1;scene.frame_start=1;scene.frame_end=217
COM=Vector((0,-.05,2.35))

def curve(t,keys):
 """Monotone cubic Hermite: shared slopes at knots, no repeated angular stops."""
 x=np.array([k[0] for k in keys]);y=np.array([k[1] for k in keys])
 h=np.diff(x);d=np.diff(y)/h;m=np.zeros(len(x))
 for i in range(1,len(x)-1):
  if d[i-1]*d[i]>0:
   w1=2*h[i]+h[i-1];w2=h[i]+2*h[i-1]
   m[i]=(w1+w2)/(w1/d[i-1]+w2/d[i])
 if t<=x[0]:return float(y[0])
 if t>=x[-1]:return float(y[-1])
 i=int(np.searchsorted(x,t)-1);u=(t-x[i])/h[i]
 return float((2*u**3-3*u*u+1)*y[i]+(u**3-2*u*u+u)*h[i]*m[i]+(-2*u**3+3*u*u)*y[i+1]+(u**3-u*u)*h[i]*m[i+1])

def turn(n,x=0,y=0,z=0):
 b=rig.pose.bones[n];b.rotation_mode='QUATERNION'
 b.rotation_quaternion=(b.rotation_quaternion@Euler(tuple(math.radians(v) for v in (x,y,z)),'XYZ').to_quaternion()).normalized()

def aim(n,direction,weight):
 b=rig.pose.bones[n];mat=b.matrix.copy();q=mat.to_quaternion()
 desired=(q@Vector((0,1,0))).rotation_difference(Vector(direction).normalized())@q
 b.matrix=Matrix.LocRotScale(mat.translation,q.slerp(desired,weight),mat.to_scale())
 bpy.context.view_layer.update()

rows=[]
for frame in range(1,218):
 t=(frame-1)/100
 angle=curve(t,[(0,0),(.12,0),(.24,20),(.39,90),(.54,192),(.69,298),(.85,352),(.96,360),(2.16,360)])
 tuck=curve(t,[(0,0),(.18,0),(.31,.45),(.44,1),(.61,1),(.76,.50),(.90,.04),(.96,0),(2.16,0)])
 squat=curve(t,[(0,0),(.09,.46),(.12,.29),(.23,0),(.96,.035),(1.045,.48),(1.18,.18),(1.35,.018),(1.48,0),(2.16,0)])
 lean=curve(t,[(0,0),(.10,19),(.24,4),(.44,23),(.63,25),(.84,4),(.96,5),(1.06,19),(1.26,3),(1.46,0),(2.16,0)])
 arms=curve(t,[(0,0),(.10,.25),(.21,.70),(.37,1),(.64,1),(.82,.60),(.96,.44),(1.06,.62),(1.35,.12),(1.52,0),(2.16,0)])
 for name,mat in neutral.items():rig.pose.bones[name].matrix_basis=mat
 rig.matrix_world=world
 rig.pose.bones['Body'].location.y-=squat
 turn('Abdomen',x=lean*.42);turn('Torso',x=lean*.58)
 turn('Neck',x=tuck*5-lean*.15);turn('Head',x=tuck*6-lean*.35)
 bpy.context.view_layer.update()
 for side,sign in [('L',1),('R',-1)]:
  foot=feet[side].copy()
  foot.translation+=Vector((sign*.025*tuck,-.72*tuck,1.46*tuck))
  foot=foot@Matrix.Rotation(math.radians(tuck*16),4,'X')
  rig.pose.bones['Foot.'+side].matrix=foot;bpy.context.view_layer.update()
  # Backward preparatory sweep, forward throw, close knees, open for landing.
  prep=curve(t,[(0,0),(.09,1),(.18,0),(2.16,0)])
  aim('UpperArm.'+side,(sign*(.22+.08*(1-tuck)),-.76+.99*prep,-.54),arms)
  aim('LowerArm.'+side,(-sign*.20,-.65,.76*tuck+.14*(1-tuck)),arms)
  turn('Palm.'+side,x=-8*tuck,y=sign*10*tuck,z=-sign*12*tuck)
  turn('Fingers.'+side,z=-sign*16*tuck)
 roll=Matrix.Rotation(math.radians(angle),4,'X')
 rig.matrix_world=Matrix.Translation(COM)@roll@Matrix.Translation(-COM)@world
 bpy.context.view_layer.update()
 for b in rig.pose.bones:
  b.rotation_mode='QUATERNION'
  for channel in ('location','rotation_quaternion','scale'):b.keyframe_insert(channel,frame=frame,group=b.name)
 rig.rotation_mode='QUATERNION'
 for channel in ('location','rotation_quaternion','scale'):rig.keyframe_insert(channel,frame=frame)
 rows.append({'frame':frame,'seconds':t,'angle':angle,'tuck':tuck,'squat':squat})
for fc in fcurves(rig.animation_data.action):
 for k in fc.keyframe_points:k.interpolation='LINEAR'
for marker in list(scene.timeline_markers):scene.timeline_markers.remove(marker)
for f,label in [(1,'Neutral'),(10,'Anticipation'),(13,'Takeoff'),(25,'JumpAir'),(55,'Tucked momentum'),(86,'Unfold'),(97,'Contact / JumpLand'),(106,'Absorb impact'),(146,'Body recovered / cloth still free'),(217,'Cloth settled')]:scene.timeline_markers.new(label,frame=f)
scene['motion_contract']='JumpStart .24 / JumpAir .72 / JumpLand 1.20; one full forward rotation, continuous angular velocity.'
scene['cloth_method']='Neutral surfaces prepared for a new world-space gravity/contact bake.'
scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT))
(REPORT/'motion.json').write_text(json.dumps({'output':str(OUT),'poses':rows,'method':'Monotone cubic with shared tangents; IK feet and articulated arm sweep'},indent=2),encoding='utf8')
print('REFINED_MOTION_SAVED',str(OUT),flush=True)
