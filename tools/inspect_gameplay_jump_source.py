"""Read-only inventory of the actual graduate master before authoring a new jump."""
import bpy, json
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
out = ROOT / 'deliverables' / 'gameplay-jump'
out.mkdir(parents=True, exist_ok=True)
report = {'blend': bpy.data.filepath, 'version': bpy.app.version_string, 'scenes': []}
for scene in bpy.data.scenes:
    if bpy.context.window: bpy.context.window.scene = scene
    scene.frame_set(1)
    rigs = [o for o in scene.objects if o.type == 'ARMATURE']
    item = {'name': scene.name, 'fps': scene.render.fps, 'frameRange': [scene.frame_start,scene.frame_end], 'meshes': []}
    if rigs:
        rig = rigs[0]
        item['rig'] = {'name':rig.name,'matrix':list(map(list,rig.matrix_world)), 'bones': [
            {'name':b.name,'parent':b.parent.name if b.parent else None,'head':list(b.head_local),'tail':list(b.tail_local),'deform':b.use_deform,
             'rest':list(map(list,b.matrix_local)), 'location':list(rig.pose.bones[b.name].location),
             'quaternion':list(rig.pose.bones[b.name].rotation_quaternion),
             'constraints':[{'type':c.type,'target':getattr(getattr(c,'target',None),'name',None),'subtarget':getattr(c,'subtarget',None)} for c in rig.pose.bones[b.name].constraints]}
            for b in rig.data.bones]}
    for o in scene.objects:
        if o.type != 'MESH' or not o.get('graduate_role') or o.get('preview_fx'): continue
        keys=o.data.shape_keys
        item['meshes'].append({'name':o.name,'role':o.get('graduate_role'),'vertices':len(o.data.vertices),
            'keys':len(keys.key_blocks) if keys else 0,'keyFirst':[k.name for k in list(keys.key_blocks)[:6]] if keys else [],
            'modifiers':[{'type':m.type,'name':m.name,'enabled':m.show_viewport} for m in o.modifiers],
            'groups':[g.name for g in o.vertex_groups]})
    report['scenes'].append(item)
(out/'source-inspection.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('JUMP_SOURCE_INSPECTED '+json.dumps([{'scene':s['name'],'meshes':len(s['meshes']),'clothKeys':[(m['role'],m['keys']) for m in s['meshes'] if m['role'].startswith(('01 |','02 |'))]} for s in report['scenes']]),flush=True)
