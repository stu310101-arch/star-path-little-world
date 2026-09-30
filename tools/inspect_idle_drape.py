from pathlib import Path
import sys,bpy,json,numpy as np
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import evaluated_points
from export_graduate_godot import role_map
from validate_sleeve_garment_contact import visible_surfaces
scene=next(s for s in bpy.data.scenes if s.name.startswith('04_IDLE'));bpy.context.window.scene=scene;scene.frame_set(1)
rig,roles=role_map(scene);gown=roles['01 | Pleated bachelor gown'];body=roles['Graduate | original face, hands and trousers']
with visible_surfaces(scene,[gown,body],'simulation'):
    p=evaluated_points(gown);rest=np.asarray([v.co[:] for v in gown.data.vertices]);b=evaluated_points(body)
    rings=[]
    for row in range(len(rest)//48):
        ids=np.arange(row*48,(row+1)*48);q=p[ids];r=rest[ids]
        rings.append({'row':row,'rest_z':[float(r[:,2].min()),float(r[:,2].mean()),float(r[:,2].max())],'world_z':[float(q[:,2].min()),float(q[:,2].mean()),float(q[:,2].max())], 'center':q.mean(axis=0).tolist(),'width_depth':np.ptp(q[:,:2],axis=0).tolist(),'cardinal':[p[row*48+i].tolist() for i in [0,12,24,36]]})
    (ROOT/'art/Graduate/animation/idle-drape-inspect.json').write_text(json.dumps(rings,indent=2),encoding='utf-8')
    np.savez(ROOT/'art/Graduate/animation/idle-drape-inspect.npz',points=p,rest=rest,body=b)
    print(json.dumps(rings,indent=2),flush=True)
