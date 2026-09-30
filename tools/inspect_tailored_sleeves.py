import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
scene=next(s for s in bpy.data.scenes if s.name.startswith('02_RUN'))
bpy.context.window.scene=scene;scene.frame_set(1)
rig=next(o for o in scene.objects if o.type=='ARMATURE')
result={'frame_end':scene.frame_end,'bones':{},'sleeves':[]}
for b in rig.data.bones:
 if any(s in b.name for s in ('Arm','Shoulder','Hand')):
  result['bones'][b.name]={'head':list(b.head_local),'tail':list(b.tail_local)}
for o in scene.objects:
 if o.get('graduate_role') in ('02 | Bell sleeve L','02 | Bell sleeve R'):
  result['sleeves'].append({'name':o.name,'modifiers':[(m.name,m.type,m.show_viewport,m.show_render) for m in o.modifiers],
    'rings':[[list(v.co) for v in o.data.vertices][i*32:(i+1)*32] for i in range(17)]})
(ROOT/'tools/tailored-inspection.json').write_text(json.dumps(result),encoding='utf-8')
print('INSPECTION_DONE',flush=True)
