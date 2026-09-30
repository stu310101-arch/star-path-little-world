from pathlib import Path
import sys,numpy as np,bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from repair_gown_sleeve_clearance import repair_clip
from repair_graduate_regalia import triangles
from regalia_neck_clearance import build_neck_collider,clear_neck
from probe_regalia_neck import local_faces
from simulate_portal_cloth import SkinBinding,evaluated_points
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import visible_surfaces
scene=next(s for s in bpy.data.scenes if s.name.startswith('02_RUN'));bpy.context.window.scene=scene
gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
rig=next(o for o in scene.objects if o.type=='ARMATURE')
seams={p.index for p in gown.data.polygons if p.center.z>3.8 and abs(p.center.x)>.34}
opts=dict(frames=[7],bake=False,iterations=60,clearance=.0038,shell_allowance=False,maximum_displacement=.12,maximum_step=.005,seam_faces=seams,smooth_strength=.05,check_every=8)
repair_clip('run',report_path=str(ROOT/'art/Graduate/animation/regalia-run-order-before.json'),**opts)
with visible_surfaces(scene,[gown,body],'simulation'):
    scene.frame_set(7);bpy.context.view_layer.update();neck=build_neck_collider(body);points=evaluated_points(gown)
    points,report=clear_neck(points,local_faces(points,np.asarray(triangles(gown),dtype=np.int32),neck.bounds,.055),neck,margin=.004,allow_neckline_reshape=True,support_radius=.055,max_correction=.025,iterations=24)
    inv=SkinBinding(gown,rig).inverse_points(points)
    bake_loop(gown,[inv]*24,'Order probe neck only')
repair_clip('run',report_path=str(ROOT/'art/Graduate/animation/regalia-run-order-after.json'),**opts)
