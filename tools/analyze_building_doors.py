"""Measure low facade panels from the engine-resolved asset geometry."""
import json, math
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
data=json.loads((ROOT/'deliverables/building-scale-source-probe.json').read_text(encoding='utf8'))
output=[]
for entry in data:
    facing=-1 if entry['asset'].startswith('commercial/') else 1
    facets=[]
    for part in entry['parts']:
        vs,colors=part['vertices'],part['colors']
        ids=part['indices'] or list(range(len(vs)))
        for k in range(0,len(ids),3):
            face=[vs[j] for j in ids[k:k+3]]
            rgb=[sum(colors[j][axis] for j in ids[k:k+3])/3 for axis in range(3)]
            if max(p[2] for p in face)-min(p[2] for p in face)>.00002 or min(p[1] for p in face)>.45:
                continue
            if sum(rgb)/3>.52:
                continue
            facets.append((face,rgb))
    vertex_faces=defaultdict(list)
    for i,(face,rgb) in enumerate(facets):
        for p in face:
            vertex_faces[tuple(round(v,5) for v in p)].append(i)
    unseen=set(range(len(facets)))
    candidates=[]
    while unseen:
        stack=[unseen.pop()]; group=[]
        while stack:
            current=stack.pop();group.append(current)
            for p in facets[current][0]:
                for linked in vertex_faces[tuple(round(v,5) for v in p)]:
                    if linked in unseen:
                        unseen.remove(linked);stack.append(linked)
        points=[p for i in group for p in facets[i][0]]
        lo=[min(p[a] for p in points) for a in range(3)]
        hi=[max(p[a] for p in points) for a in range(3)]
        w,h=hi[0]-lo[0],hi[1]-lo[1]
        front=entry['min'][2]+(entry['size'][2] if facing>0 else 0)
        depth=(front-lo[2])*facing
        if .07<w<.55 and .17<h<.56 and lo[1]<.10 and depth<.40:
            candidates.append({'min':lo,'max':hi,'width':w,'height':h,'front_depth':depth})
    candidates.sort(key=lambda panel:(-panel['height'],panel['front_depth']))
    row={'asset':entry['asset'],'size':entry['size'],'panels':candidates}
    output.append(row)
(ROOT/'deliverables/building-door-source-measurements.json').write_text(json.dumps(output,indent=2),encoding='utf8')
for row in output:
    if row['panels']:
        panel=row['panels'][0];w,h,d=row['size']
        print(Path(row['asset']).stem, 'source',round(panel['width'],3),round(panel['height'],3),'door@3.5=',round(panel['height']*3.5/w,2),'body',tuple(round(v,3) for v in row['size']))
    else: print(Path(row['asset']).stem,'NO_DOOR_COMPONENT')
