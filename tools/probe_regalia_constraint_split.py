from pathlib import Path
import sys,bpy
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from repair_gown_sleeve_clearance import repair_clip
for label,prefix,frame in [('idle','04_IDLE',1),('run','02_RUN',7)]:
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
    frozen={p.index for p in gown.data.polygons if p.center.z>3.8 and abs(p.center.x)>.34}
    seams={p.index for p in gown.data.polygons if p.center.z>3.05 and abs(p.center.x)>.34}
    repair_clip(label,frames=[frame],bake=False,report_path=str(ROOT/f'art/Graduate/animation/regalia-constraint-split-{label}.json'),
        iterations=60,clearance=.0038,shell_allowance=False,maximum_displacement=.12,maximum_step=.005,smooth_strength=.05,
        seam_faces=frozen,constraint_seam_faces=seams,check_every=8)
