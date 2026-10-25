"""Report coplanar axis-aligned face overlaps in the editable room (Blender)."""
import bpy, json, sys
from collections import defaultdict
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'art/CounselingRoom/CounselingRoom.blend'))
deps=bpy.context.evaluated_depsgraph_get()
planes=defaultdict(list)
duplicates=[];seen={}
for ob in bpy.context.scene.objects:
    if ob.type!='MESH' or not any(c.name.startswith('COL_Counseling_') for c in ob.users_collection):continue
    ev=ob.evaluated_get(deps);mesh=ev.to_mesh()
    points=[ob.matrix_world@v.co for v in mesh.vertices]
    for face in mesh.polygons:
        vs=[points[i] for i in face.vertices]
        key=tuple(sorted(tuple(round(x,5) for x in v) for v in vs))
        if key in seen:duplicates.append([seen[key],ob.name,face.index])
        seen[key]=ob.name
        normal=(ob.matrix_world.to_3x3()@face.normal).normalized()
        axis=max(range(3),key=lambda a:abs(normal[a]))
        if abs(normal[axis])<.999999 or face.area<.0001:continue
        others=[i for i in range(3) if i!=axis]
        lo=[min(v[i] for v in vs) for i in others];hi=[max(v[i] for v in vs) for i in others]
        planes[(axis,round(vs[0][axis],5),1 if normal[axis]>0 else -1)].append((ob.name,lo,hi,face.index))
    ev.to_mesh_clear()
overlaps={}
for plane,rows in planes.items():
    for i,a in enumerate(rows):
        for b in rows[i+1:]:
            if a[0]==b[0]:continue
            sizes=[min(a[2][k],b[2][k])-max(a[1][k],b[1][k]) for k in range(2)]
            if min(sizes)<=.00001:continue
            area=sizes[0]*sizes[1]
            if area<.0001:continue
            key=tuple(sorted((a[0],b[0])))
            if key not in overlaps or overlaps[key]['area']<area:overlaps[key]=dict(objects=key,plane=plane,area=area)
report=dict(duplicate_faces=duplicates,overlaps=sorted(overlaps.values(),key=lambda r:-r['area']))
output=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'build/counseling-faces-audit.json'
(ROOT/output).write_text(json.dumps(report,indent=2))
print('COUNSELING_FACES_AUDIT',len(duplicates),'duplicate faces;',len(overlaps),'coplanar bounding-box candidates')
