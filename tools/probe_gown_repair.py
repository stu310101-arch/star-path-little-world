from pathlib import Path
import sys
import bpy
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from repair_gown_sleeve_clearance import repair_clip
for clip,frames in [('idle',[1,51,91]),('walk',[9]),('run',[7]),('jump',[27])]:
    prefix={'idle':'04_IDLE','walk':'01_WALK','run':'02_RUN','jump':'03_JUMP'}[clip]
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
    seams={p.index for p in gown.data.polygons if p.center.z>3.8 and abs(p.center.x)>.34}
    repair_clip(clip,report_path=str(ROOT/f'art/Graduate/animation/gown-clearance-probe-{clip}.json'),frames=frames,bake=False,iterations=60,maximum_displacement=.12,maximum_step=.005,seam_faces=seams,smooth_strength=.05)
