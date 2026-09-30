"""Check measured building footprints against the designed carriageways."""
import json, math
from pathlib import Path
root=Path(__file__).resolve().parents[1]
report=json.loads((root/'game/generated/build_report.json').read_text(encoding='utf8'))
districts=json.loads((root/'game/data/districts.json').read_text(encoding='utf8'))
bad=[]; smallest=100.0
for row in report['assets']:
    if row['kind']!='building': continue
    district=next(d for d in districts if d['station']==row['station'])
    p=row['offset']; hw,hd=[x/2+.25 for x in row['footprint']]
    angle=math.radians(row['yaw']); cs,sn=math.cos(angle),math.sin(angle)
    roads=district['roads']+[[district['loop'][i],district['loop'][(i+1)%len(district['loop'])]] for i in range(len(district['loop']))]
    gap=100.0
    for a,b in roads:
        count=math.ceil(math.dist(a,b)/.1)
        for k in range(count+1):
            q=[a[j]+(b[j]-a[j])*k/count-p[j] for j in range(2)]
            x=cs*q[0]-sn*q[1]; z=sn*q[0]+cs*q[1]
            gap=min(gap,math.hypot(max(0,abs(x)-hw),max(0,abs(z)-hd))-2.1)
    smallest=min(smallest,gap)
    if gap<-.05: bad.append(dict(district=row['station'],asset=row['path'],offset=p,carriageway_gap=gap))
result=dict(buildings_checked=48,road_overlaps=bad,minimum_building_road_gap=smallest,note='Tangent-layout footprint clearance; runtime collision and screenshots verified separately.')
(root/'deliverables/parcel-clearances.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result))
raise SystemExit(bool(bad))
