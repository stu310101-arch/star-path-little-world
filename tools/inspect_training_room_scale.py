import bpy, json
from mathutils import Vector
from pathlib import Path
data=[]
for o in bpy.context.scene.objects:
    if any(s in o.name for s in ['LOUNGE_Left_seat','LOUNGE_Left_back','LOUNGE_Return_seat','LOUNGE_Return_back','LOUNGE_Corner','LOUNGE_Rug','Coffee_table','miniature','shaped seat','station ']):
        pts=[o.matrix_world@Vector(v) for v in o.bound_box]
        lo=[min(v[i] for v in pts) for i in range(3)]
        hi=[max(v[i] for v in pts) for i in range(3)]
        data.append(dict(name=o.name,lo=lo,hi=hi,loc=list(o.location),parent=o.parent.name if o.parent else None,scale=list(o.scale)))
Path(__file__).resolve().parents[1].joinpath('art/TrainingRoom/validation/interactive_scale_before.json').write_text(json.dumps(data,indent=2))
print(json.dumps(data))
