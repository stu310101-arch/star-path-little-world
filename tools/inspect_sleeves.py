import bpy,json
from pathlib import Path
out=[]
for s in bpy.data.scenes:
 bpy.context.window.scene=s;s.frame_set(1)
 rig=next((o for o in s.objects if o.type=='ARMATURE'),None)
 if not rig:continue
 entry={'scene':s.name,'frames':[s.frame_start,s.frame_end],'rig':rig.name,'bones':{b.name:{'head':list(b.head_local),'tail':list(b.tail_local),'deform':b.use_deform} for b in rig.data.bones if 'Arm' in b.name},'sleeves':[]}
 for o in s.objects:
  if 'Bell sleeve' not in o.get('graduate_role',''):continue
  entry['sleeves'].append({'name':o.name,'role':o.get('graduate_role'),'verts':len(o.data.vertices),'faces':len(o.data.polygons),'keys':len(o.data.shape_keys.key_blocks) if o.data.shape_keys else 0,'mods':[(m.name,m.type) for m in o.modifiers],'bounds':[list(min(v.co[i] for v in o.data.vertices) for i in range(3)),list(max(v.co[i] for v in o.data.vertices) for i in range(3))]})
 out.append(entry)
path=Path(__file__).with_name('sleeves-inspection.json');path.write_text(json.dumps(out,indent=2),encoding='utf-8')
print('SLEEVES_INSPECTED',json.dumps(out),flush=True)
