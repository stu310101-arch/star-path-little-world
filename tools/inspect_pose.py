import bpy, json
from pathlib import Path
rig=bpy.data.objects['HumanArmature']
scene=bpy.context.scene
scene.frame_set(0)
mesh=bpy.data.objects['BaseHuman']
data={}
for frame in [0,17,50,100]:
    scene.frame_set(frame)
    data[str(frame)]={b.name:{'head':list(b.head),'tail':list(b.tail)} for b in rig.pose.bones if b.name in ['Head','Neck','Torso','UpperArm.L','LowerArm.L','Palm.L','UpperArm.R','LowerArm.R','Palm.R','Hips']}
scene.frame_set(0)
rig.data.pose_position='REST'
bpy.context.view_layer.update()
data['torso_slices']=[]
for z in [2.6,3.0,3.5,3.8,3.95,4.05]:
    verts=[v.co for v in mesh.data.vertices if abs(v.co.z-z)<.1 and abs(v.co.x)<.55]
    data['torso_slices'].append({'z':z,'bounds':[[min(c[k] for c in verts) for k in range(3)],[max(c[k] for c in verts) for k in range(3)]] if verts else None})
Path('tools/pose-inspection.json').write_text(json.dumps(data,indent=2))
print(json.dumps(data,indent=2))
