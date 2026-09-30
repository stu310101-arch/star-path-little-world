import bpy,json
from pathlib import Path
from mathutils import Matrix
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE');rig.hide_set(False)
action=bpy.data.actions['Man_Jump'];rig.animation_data.action=action
if action.slots:rig.animation_data.action_slot=action.slots[0]
result={}
for f in [0,3,6,9,12,15,18,21,25]:
    for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
    scene.frame_set(f);bpy.context.view_layer.update()
    result[f]={n:{'loc':list(b.location),'head':list(b.head),'parent':b.parent.name if b.parent else None,'local_axes':[list(b.bone.matrix_local.col[i]) for i in range(3)]} for n,b in rig.pose.bones.items() if n in ['Body','Hips','Foot.L','Foot.R','PoleTarget.L','PoleTarget.R','UpperArm.L','LowerArm.L']}
path=Path(__file__).resolve().parent/'jump-source-inspection.json'
path.write_text(json.dumps(result,indent=2),encoding='utf-8')
for f,row in result.items():print('JUMP',f,{n:{'loc':v['loc'],'head':v['head']} for n,v in row.items() if n in ['Body','Foot.L','Foot.R']},flush=True)
