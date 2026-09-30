"""CPU-only conservative spherical parcel/corridor preflight.

Uses the source mesh bounds and the generator's transported tangent frames and
joined-strip miter, including physical street widths. It complements the actual
scene capsule sweeps; it does not replace mesh collision or floor validation.
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
def lerp(a,b,t): return add(mul(a,1-t),mul(b,t))
def spherical(p): return norm((p[0],R,p[1]))
def angle(a,b): return math.acos(max(-1,min(1,dot(a,b))))
def slerp(a,b,t):
    theta=angle(a,b)
    if theta<1e-8: return a
    return add(mul(a,math.sin((1-t)*theta)/math.sin(theta)),mul(b,math.sin(t*theta)/math.sin(theta)))
def transported(v,n):
    k=cross((0,1,0),n)
    return add(add(v,cross(k,v)),mul(cross(k,cross(k,v)),1/(1+n[1])))
def closest(p,a,b):
    ab=sub(b,a)
    return lerp(a,b,max(0,min(1,dot(sub(p,a),ab)/dot(ab,ab))))
def samples(path,closed=False):
    points=[spherical(p) for p in path]
    sides=[]
    for i,n in enumerate(points):
        incoming=norm(cross(points[i-1],n))
        outgoing=norm(cross(n,points[(i+1)%len(points)]))
        if not closed and i==0: incoming=outgoing
        if not closed and i==len(points)-1: outgoing=incoming
        bisector=norm(add(incoming,outgoing))
        sides.append(mul(bisector,1/max(dot(bisector,outgoing),.25)))
    result=[]
    for i in range(len(points) if closed else len(points)-1):
        j=(i+1)%len(points)
        count=max(1,math.ceil(angle(points[i],points[j])*R/.16))
        for k in range(count+1):
            t=k/count
            result.append((slerp(points[i],points[j],t),lerp(sides[i],sides[j],t)))
    return result

failures=[]
tested=0
parcel_summary=[]
for district in districts:
    station=district['station']
    edges=district['roads']+[[district['loop'][i],district['loop'][(i+1)%len(district['loop'])]] for i in range(len(district['loop']))]
    authored_edges=[edge for path in district['paths'] for edge in zip(path,path[1:])]
    parcels=[]
    corridors=[('street loop',samples(district['loop'],True),6.3,.30)]
    corridors += [(f'interior street {i}',samples(path),6.3,.30) for i,path in enumerate(district['roads'])]
    corridors += [(f'public path {i}',samples(path),2.2,.30) for i,path in enumerate(district['paths'])]
    for index,row in enumerate(district['urban_buildings']):
        size=sources[row['asset']]['size']
        factor=min(row['height']/size[1],row['max_width']/size[0],row['max_depth']/size[2])
        n=spherical(row['offset'])
        yaw=math.radians(row['yaw'])
        ax=transported((math.cos(yaw),0,-math.sin(yaw)),n)
        az=transported((math.sin(yaw),0,math.cos(yaw)),n)
        parcel=dict(index=index,origin=mul(n,R+.55),x=ax,z=az,half=(size[0]*factor/2+.25,size[2]*factor/2+.25))
        parcels.append(parcel)
        forward=(math.sin(yaw),math.cos(yaw))
        start=add(row['offset'],mul(forward,row['front']))
        nearest=min([closest(start,*edge) for edge in edges+authored_edges],key=lambda p:math.dist(p,start))
        if math.dist(start,nearest)>.3:
            corridors.append((f'forecourt {index}',samples([start,nearest]),1.4,.10))
    minima={i:float('inf') for i in range(len(parcels))}
    for name,route,width,buffer in corridors:
        bad={}
        for n,side in route:
            for ratio in (-1,-.5,0,.5,1):
                point=mul(norm(add(mul(n,R),mul(side,(width/2+buffer)*ratio))),R+.55)
                for parcel in parcels:
                    delta=sub(point,parcel['origin'])
                    if dot(delta,delta)>81: continue
                    tested+=1
                    dx=abs(dot(delta,parcel['x']))-parcel['half'][0]
                    dz=abs(dot(delta,parcel['z']))-parcel['half'][1]
                    clearance=math.hypot(max(dx,0),max(dz,0))
                    minima[parcel['index']]=min(minima[parcel['index']],clearance)
                    if dx<-.005 and dz<-.005 and (parcel['index'] not in bad or min(-dx,-dz)>bad[parcel['index']]['penetration']):
                        bad[parcel['index']]=dict(station=station,corridor=name,building=parcel['index'],local=[round(point[0]*R/point[1],3),round(point[2]*R/point[1],3)],penetration=round(min(-dx,-dz),3))
        failures.extend(bad.values())
    parcel_summary.append(dict(station=station,minimum_foundation_corridor_distances=minima))
result=dict(passed=not failures,tested_proximity_samples=tested,failures=failures,parcels=parcel_summary,note='Conservative transported 3D foundation bounds against spherical joined street/promenade/forecourt envelopes. Actual mesh capsule sweeps remain required.')
(ROOT/'deliverables/building-spherical-clearances.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in result.items() if k!='parcels'},indent=2))
raise SystemExit(bool(failures))
