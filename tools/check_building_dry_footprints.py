"""Inspect every building foundation's full spherical footprint against water.

Samples the complete footprint (not only its centre/corners) at 0.12 m and all
three foundation elevations. The signed lake/river/coast definitions match the
authoring source; no water exclusion or collision filtering is applied.
"""
import json, math
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
districts=json.loads((ROOT/'game/data/districts.json').read_text(encoding='utf8'))
sources={r['asset']:r for r in json.loads((ROOT/'deliverables/building-scale-source-probe.json').read_text(encoding='utf8'))}
R=float(json.loads((ROOT/'game/data/world_layout.json').read_text(encoding='utf8'))['radius'])
def add(a,b): return tuple(x+y for x,y in zip(a,b))
def sub(a,b): return tuple(x-y for x,y in zip(a,b))
def mul(a,s): return tuple(x*s for x in a)
def dot(a,b): return sum(x*y for x,y in zip(a,b))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def norm(a): return mul(a,1/math.sqrt(dot(a,a)))
def transported(v,n):
    k=cross((0,1,0),n)
    return add(add(v,cross(k,v)),mul(cross(k,cross(k,v)),1/(1+n[1])))
def nearest(p,a,b):
    ab=sub(b,a)
    return add(a,mul(ab,max(0,min(1,dot(sub(p,a),ab)/dot(ab,ab)))))
def water_distance(p,data):
    distance=float('inf')
    for water in data['water']:
        if water['kind']=='lake':
            size=water['size']
            local=[(p[i]-water['center'][i])/size[i] for i in range(2)]
            angle=math.atan2(local[1],local[0])
            edge=1+.10*math.sin(angle*3)+.055*math.cos(angle*5)
            distance=min(distance,(math.hypot(*local)-edge)*min(size))
        else:
            for a,b in zip(water['points'],water['points'][1:]):
                distance=min(distance,math.dist(p,nearest(p,a,b))-water['width']/2)
    return distance
def edge_distance(p,data,index):
    local=[p[i]/data['extent'][i] for i in range(2)]
    angle=math.atan2(local[1],local[0])
    edge=1+.045*math.sin(angle*3+index)+.035*math.cos(angle*5-index)
    return (edge-math.hypot(*local))*min(data['extent'])

records=[]
failures=[]
total_samples=0
for district_index,district in enumerate(districts):
    for index,row in enumerate(district['urban_buildings']):
        size=sources[row['asset']]['size']
        scale=min(row['height']/size[1],row['max_width']/size[0],row['max_depth']/size[2])
        half=(size[0]*scale/2+.25,size[2]*scale/2+.25)
        n=norm((row['offset'][0],R,row['offset'][1]))
        origin=mul(n,R+.55)
        yaw=math.radians(row['yaw'])
        ax=transported((math.cos(yaw),0,-math.sin(yaw)),n)
        az=transported((math.sin(yaw),0,math.cos(yaw)),n)
        nx,nz=[math.ceil(h*2/.12) for h in half]
        water_min=edge_min=float('inf')
        wet_point=edge_point=None
        for level in (-.85,-.425,0):
            centre=add(origin,mul(n,level))
            for ix in range(nx+1):
                x=half[0]*(2*ix/nx-1)
                for iz in range(nz+1):
                    z=half[1]*(2*iz/nz-1)
                    world=add(add(centre,mul(ax,x)),mul(az,z))
                    local=(world[0]*R/world[1],world[2]*R/world[1])
                    wet=water_distance(local,district)
                    coast=edge_distance(local,district,district_index)
                    total_samples+=1
                    if wet<water_min: water_min,wet_point=wet,local
                    if coast<edge_min: edge_min,edge_point=coast,local
        record=dict(station=district['station'],index=index,asset=row['asset'],offset=row['offset'],foundation_size=[h*2 for h in half],minimum_water_distance=water_min,minimum_coast_distance=edge_min,water_point=wet_point,coast_point=edge_point,samples=(nx+1)*(nz+1)*3)
        records.append(record)
        if min(water_min,edge_min)<.30:
            failures.append(record)
result=dict(passed=not failures,buildings_checked=len(records),footprint_samples=total_samples,required_bank_buffer=.30,minimum_water_distance=min(r['minimum_water_distance'] for r in records),minimum_coast_distance=min(r['minimum_coast_distance'] for r in records),failures=failures,buildings=records)
(ROOT/'deliverables/building-dry-footprints.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in result.items() if k!='buildings'},indent=2))
raise SystemExit(bool(failures))
