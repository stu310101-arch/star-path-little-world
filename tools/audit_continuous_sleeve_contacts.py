"""Check final rendered sleeve surfaces against visible arm/body skin."""
import bpy,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from validate_sleeve_garment_contact import Surface,visible_surfaces,compare
report={'source':bpy.data.filepath,'clips':{},'seam_exclusion':'faces touching shoulder attachment vertices','method':'Exact transverse triangle crossings; rendered Solidify surfaces'}
for label,prefix in [('walk','01_WALK'),('run','02_RUN'),('jump','03_JUMP')]:
 scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
 roles=['02 | Bell sleeve L','02 | Bell sleeve R','Graduate | restored arm skin','Graduate | original face, hands and trousers']
 objects=[next(o for o in scene.objects if o.get('graduate_role')==role) for role in roles]
 frames=[]
 with visible_surfaces(scene,objects,'rendered'):
  for f in range(1,scene.frame_end+1):
   scene.frame_set(f);bpy.context.view_layer.update();surfaces=[Surface(o) for o in objects]
   checks={}
   for i in range(2):
    for j in [i,2,3]:
     result=compare(surfaces[i],surfaces[j],i==j,1e-6)
     checks[f'{i}_{j}']={k:result[k] for k in ['crossings','maximum_intersection_segment_m']}
   frames.append({'frame':f,'checks':checks})
   if f%12==0:print('SLEEVE_CONTACT_PROGRESS',label,f,flush=True)
 report['clips'][label]=frames
out=ROOT/'tools/sleeve-continuous-contact-audit.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SLEEVE_CONTACT_AUDIT_DONE',flush=True)
