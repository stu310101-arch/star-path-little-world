import bpy,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
scene=next(s for s in bpy.data.scenes if s.name.startswith('03_JUMP'))
bpy.context.window.scene=scene;scene.frame_set(1)
rig=next(o for o in scene.objects if o.type=='ARMATURE')
rig.hide_set(False);bpy.context.view_layer.update()
report={'source':bpy.data.filepath,'scene':scene.name,'bones':{},'meshes':[]}
for b in rig.pose.bones:
 report['bones'][b.name]={'parent':b.parent.name if b.parent else None,'head':list(b.head),'tail':list(b.tail),
  'location':list(b.location),'quaternion':list(b.rotation_quaternion),'scale':list(b.scale),
  'constraints':[(c.type,getattr(c,'subtarget','')) for c in b.constraints]}
for o in scene.objects:
 if o.type=='MESH' and o.get('graduate_role'):
  report['meshes'].append({'role':o.get('graduate_role'),'vertices':len(o.data.vertices),
   'modifiers':[(m.type,m.show_viewport) for m in o.modifiers],
   'shape_keys':len(o.data.shape_keys.key_blocks) if o.data.shape_keys else 0})
(ROOT/'tools/idle-setup-inspection.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('IDLE_SETUP_INSPECTED',json.dumps({'bones':list(report['bones']),'mesh_count':len(report['meshes'])}),flush=True)
