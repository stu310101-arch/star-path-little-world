"""Validate source-scaled parcels, or rebuilt actual report with --actual.

This checks imported mesh bounds, uniform plan scaling, reviewed parcel anchors,
minimum architecture height, full sidewalk clearance, and neighboring foundations.
Actual height includes the measured ground-floor refinement and human-size doors.
"""
import argparse
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--actual', action='store_true')
args = parser.parse_args()
districts = json.loads((ROOT/'game/data/districts.json').read_text(encoding='utf8'))
before = json.loads((ROOT/'deliverables/building-scale-before.json').read_text(encoding='utf8'))
walkway_path=ROOT/'deliverables/building-walkway-adjustments.json'
walkway_adjustments={(r['station'],r['index']):r['after'] for r in json.loads(walkway_path.read_text(encoding='utf8'))} if walkway_path.exists() else {}
sources = {r['asset']: r for r in json.loads((ROOT/'deliverables/building-scale-source-probe.json').read_text(encoding='utf8'))}
actual = json.loads((ROOT/'game/generated/build_report.json').read_text(encoding='utf8'))['assets'] if args.actual else []
failures, rows, changed = [], [], []
minimum_road_gap = float('inf')
minimum_path_gap = float('inf')

def scaled(row):
    size = sources[row['asset']]['size']
    factor = min(row['height']/size[1], row['max_width']/size[0], row['max_depth']/size[2])
    return [v*factor for v in size], factor

def axes(row):
    angle = math.radians(row['yaw'])
    return [(math.cos(angle), -math.sin(angle)), (math.sin(angle), math.cos(angle))]

def dot(a, b):
    return sum(x*y for x,y in zip(a,b))

def foundations_overlap(a, b):
    aa, ba = axes(a), axes(b)
    delta = [b['offset'][k]-a['offset'][k] for k in range(2)]
    ah = [v/2+.25 for v in a['footprint']]
    bh = [v/2+.25 for v in b['footprint']]
    for axis in aa+ba:
        extent = sum(ah[k]*abs(dot(aa[k],axis))+bh[k]*abs(dot(ba[k],axis)) for k in range(2))
        if abs(dot(delta,axis)) >= extent-.005:
            return False
    return True

for district in districts:
    station = district['station']
    parcel_rows = []
    for index, row in enumerate(district['urban_buildings']):
        old = before[station][index]
        tag = f'{station}[{index}]'
        approved=walkway_adjustments.get((station,index),old)
        for field in ('offset','yaw','front','role'):
            if row.get(field) != approved.get(field):
                failures.append(f'{tag}: differs from reviewed {field}')
        size, factor = scaled(row)
        entry = dict(station=station,index=index,asset=row['asset'],offset=row['offset'],yaw=row['yaw'],height=size[1],footprint=[size[0],size[2]],uniform_scale=factor)
        if args.actual:
            matches = [r for r in actual if r['kind']=='building' and r['station']==station and r['offset']==row['offset']]
            if len(matches)!=1:
                failures.append(f'{tag}: no unique actual building')
            else:
                measured = matches[0]
                if measured['path'] != 'res://assets/kenney/'+row['asset']:
                    failures.append(f'{tag}: stale built asset')
                frontage=measured.get('frontage',{})
                if not frontage.get('applied',False):
                    failures.append(f'{tag}: missing human-scale frontage refinement')
                if frontage.get('door_height',0)<2.05-.005 or frontage.get('door_width',0)<.95-.005:
                    failures.append(f'{tag}: entrance below 2.05 m high / .95 m wide')
                expected_size=[size[0],size[1]+frontage.get('floor_gain',0),size[2]]
                for expected,observed in zip(expected_size,[measured['footprint'][0],measured['height'],measured['footprint'][1]]):
                    if abs(expected-observed)>.005:
                        failures.append(f'{tag}: actual bounds disagree with uniform footprint / measured floor gain')
                if abs(measured['scale']-factor)>.005:
                    failures.append(f'{tag}: actual scale mismatch')
                entry.update(height=measured['height'],footprint=measured['footprint'],frontage=frontage)
        if entry['height']<2.5:
            failures.append(f'{tag}: architecture below 2.5 m')
        if entry['footprint'][0]>row['max_width']+.005 or entry['footprint'][1]>row['max_depth']+.005:
            failures.append(f'{tag}: exceeds authored parcel dimensions')
        roads = district['roads']+[[district['loop'][k],district['loop'][(k+1)%len(district['loop'])]] for k in range(len(district['loop']))]
        gap = float('inf')
        basis = axes(entry)
        half = [v/2+.25 for v in entry['footprint']]
        for a,b in roads:
            count=max(1,math.ceil(math.dist(a,b)/.05))
            for k in range(count+1):
                local=[a[j]+(b[j]-a[j])*k/count-entry['offset'][j] for j in range(2)]
                distances=[max(0,abs(dot(local,basis[j]))-half[j]) for j in range(2)]
                gap=min(gap,math.hypot(*distances)-2.1)
        minimum_road_gap=min(minimum_road_gap,gap)
        entry['foundation_to_carriageway_gap']=gap
        # The 4.2 m carriageway sits inside a 6.3 m street. Preserve all 1.05 m
        # of sidewalk plus 0.30 m breathing room beyond its outside edge.
        if gap<1.35-.005:
            failures.append(f'{tag}: full sidewalk + .30 m buffer missing ({gap-1.05:.3f} m outside sidewalk)')
        path_gap = float('inf')
        for path in district['paths']:
            for a,b in zip(path,path[1:]):
                count=max(1,math.ceil(math.dist(a,b)/.05))
                for k in range(count+1):
                    local=[a[j]+(b[j]-a[j])*k/count-entry['offset'][j] for j in range(2)]
                    distances=[max(0,abs(dot(local,basis[j]))-half[j]) for j in range(2)]
                    path_gap=min(path_gap,math.hypot(*distances)-1.1)
        minimum_path_gap=min(minimum_path_gap,path_gap)
        entry['foundation_to_authored_path_gap']=path_gap
        if path_gap<-.05:
            failures.append(f'{tag}: foundation encroaches authored walking path {path_gap:.3f} m')
        if row != old:
            oldsize,_ = scaled(old)
            changed.append(dict(entry,previous_asset=old['asset'],previous_height=oldsize[1],previous_footprint=[oldsize[0],oldsize[2]]))
        rows.append(entry)
        parcel_rows.append(entry)
    for i,a in enumerate(parcel_rows):
        for b in parcel_rows[i+1:]:
            if foundations_overlap(a,b):
                failures.append(f'{station}: neighboring foundations overlap {a["index"]}/{b["index"]}')

result=dict(mode='actual_generated_report' if args.actual else 'source_bounds_prediction',buildings_checked=len(rows),changed_count=len(changed),minimum_height=min(r['height'] for r in rows),minimum_foundation_road_gap=minimum_road_gap,minimum_foundation_authored_path_gap=minimum_path_gap,failures=failures,changed=changed,buildings=rows)
output=ROOT/'deliverables'/('building-proportions-actual.json' if args.actual else 'building-proportions-predicted.json')
output.write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in result.items() if k not in ('changed','buildings')},indent=2))
for r in changed:
    print(f'{r["station"]}[{r["index"]}] {r["previous_height"]:.2f} -> {r["height"]:.2f} m; footprint {r["footprint"][0]:.2f} x {r["footprint"][1]:.2f} m')
raise SystemExit(bool(failures))
