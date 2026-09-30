import bpy, json
from pathlib import Path
out=Path(__file__).resolve().parents[1]/'deliverables/frontflip-refined'
out.mkdir(parents=True,exist_ok=True)
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
scene.frame_set(1)
rig=next(o for o in scene.objects if o.type=='ARMATURE')
report={'file':bpy.data.filepath,'version':bpy.app.version_string,'scene':scene.name,
 'bones':[{'name':b.name,'head':list(b.head_local),'tail':list(b.tail_local),
 'constraints':[c.type for c in rig.pose.bones[b.name].constraints]} for b in rig.data.bones], 'meshes':[]}
for o in scene.objects:
 if o.type!='MESH' or not o.get('graduate_role'):continue
 keys=o.data.shape_keys
 report['meshes'].append({'name':o.name,'role':o.get('graduate_role'),'verts':len(o.data.vertices),
 'z':[min(v.co.z for v in o.data.vertices),max(v.co.z for v in o.data.vertices)],
 'keys':len(keys.key_blocks) if keys else 0,
 'mods':[(m.type,m.show_viewport) for m in o.modifiers],
 'props':{k:str(v) for k,v in o.items()},'groups':[g.name for g in o.vertex_groups]})
(out/'source-inspection.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=True))
