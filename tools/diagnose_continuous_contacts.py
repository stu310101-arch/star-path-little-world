import bpy,sys,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from validate_sleeve_garment_contact import Surface,visible_surfaces,compare
for prefix,frame,side,kind in [('01_WALK',19,'R','skin'),('02_RUN',3,'R','self'),('03_JUMP',1,'R','skin')]:
 scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
 sleeve=next(o for o in scene.objects if o.get('graduate_role')=='02 | Bell sleeve '+side)
 skin=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | restored arm skin')
 with visible_surfaces(scene,[sleeve,skin],'rendered'):
  scene.frame_set(frame);bpy.context.view_layer.update();a=Surface(sleeve);b=a if kind=='self' else Surface(skin)
  result=compare(a,b,kind=='self',1e-6)
  details=[]
  for (i,j),length in zip(result['triangle_pairs'],result['intersection_segment_lengths_m']):
   ids=a.triangles[i];other=b.triangles[j]
   details.append({'rings':[v%545//32 for v in ids],'other':([v%545//32 for v in other] if kind=='self' else other),'length':length})
  print('CONTACT_DETAIL',prefix,frame,kind,json.dumps(details[:30]),flush=True)
