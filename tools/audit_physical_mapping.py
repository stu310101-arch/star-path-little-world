import bpy,numpy as np,json
from pathlib import Path
R=Path(__file__).resolve().parents[1]
s=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=s
g=next(o for o in s.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
rig=next(o for o in s.objects if o.type=='ARMATURE')
print('MATRICES',g.matrix_world[:],rig.matrix_world[:],flush=True)
print('MODS',[(m.name,m.type) for m in g.modifiers],flush=True)
for m in g.modifiers:
    if m.type!='ARMATURE':m.show_viewport=False
data=np.load(R/'art/Graduate/animation/walk_physical_cloth.npz')
for f in [1,10,19,28]:
    s.frame_set(f);bpy.context.view_layer.update()
    ev=g.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
    pos=np.array([v.co[:] for v in me.vertices])*.36458333333333337
    error=np.linalg.norm(pos-data['periodic'][f-1],axis=1)
    print('MAPPING',f,'rms',np.sqrt(np.mean(error**2)),'max',error.max(),'hem-z',pos[:48,2].mean(),flush=True)
    ev.to_mesh_clear()
print('LOWER_WEIGHTS',[(v.index,[(g.vertex_groups[x.group].name,x.weight) for x in v.groups]) for v in list(g.data.vertices)[:3]],flush=True)
