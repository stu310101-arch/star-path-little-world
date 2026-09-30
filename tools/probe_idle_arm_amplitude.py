"""Read-only test of arm follow-through against the left cuff."""
import bpy,sys,math,json
from pathlib import Path
from mathutils import Euler
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from validate_sleeve_garment_contact import Surface,visible_surfaces,compare
source=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
bpy.context.window.scene=source;source.frame_set(1)
src=next(o for o in source.objects if o.type=='ARMATURE')
base={b.name:b.rotation_quaternion.copy() for b in src.pose.bones}
scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
left=next(o for o in scene.objects if o.get('graduate_role')=='02 | Bell sleeve L')
skin=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
report=[]
with visible_surfaces(scene,[left,skin],'rendered'):
 for f in [83,90,99]:
  for mode in ['current','wrist_subtle','forearm_subtle','all_arm_subtle','no_cuff_secondary']:
   scene.frame_set(f);p=math.tau*(f-1)/120
   if mode in ['wrist_subtle','all_arm_subtle']:
    rig.pose.bones['Palm.L'].rotation_quaternion=base['Palm.L']@Euler((0,math.radians(.32*math.sin(p-.35)),0),'XYZ').to_quaternion()
   if mode in ['forearm_subtle','all_arm_subtle']:
    rig.pose.bones['LowerArm.L'].rotation_quaternion=base['LowerArm.L']@Euler((math.radians(.22*math.sin(p-.24)),0,0),'XYZ').to_quaternion()
   if mode=='all_arm_subtle':
    t=(f-1)/120;b=.5-.5*math.cos(math.pi*t/.42) if t<.42 else .5+.5*math.cos(math.pi*(t-.42)/.58)
    rig.pose.bones['UpperArm.L'].rotation_quaternion=base['UpperArm.L']@Euler((math.radians(.15*math.sin(p-.16)),0,math.radians(.10*b)),'XYZ').to_quaternion()
   if mode=='no_cuff_secondary':
    for key in left.data.shape_keys.key_blocks:key.value=0
   bpy.context.view_layer.update()
   a,b=Surface(left),Surface(skin);c=compare(a,b,False,1e-6)
   ids={v for i,j in c['triangle_pairs'] for v in a.triangles[i]}
   record={'frame':f,'mode':mode,'crossings':c['crossings'],'max_segment_m':c['maximum_intersection_segment_m'],
     'left_rings':sorted({(v%545)//32 for v in ids})}
   report.append(record);print('IDLE_ARM_PROBE',record,flush=True)
(ROOT/'tools/idle-arm-amplitude-probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
