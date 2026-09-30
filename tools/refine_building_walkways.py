"""Reviewed parcel and entrance changes from the full body corridor failures."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
path = ROOT/'game/data/districts.json'
changes = {
    # Two houses share the left block: use a narrower tall apartment and retain
    # the red-roof house, with daylight between both foundations and sidewalks.
    ('counseling',2): dict(asset='commercial/Models/GLB format/building-d.glb',height=4.0,offset=[-10.5,8],front=2.9),
    ('counseling',3): dict(offset=[-6.6,8],front=2.8),
    ('counseling',5): dict(offset=[8.7,8],front=2.8),
    # Pull upper-edge residences inward, preserving the block's row rhythm.
    ('admissions',3): dict(offset=[10,7.1]),
    ('admissions',4): dict(offset=[2,7.1]),
    ('admissions',5): dict(offset=[-10,8.4]),
    ('admissions',7): dict(asset='commercial/Models/GLB format/building-d.glb',height=4.4,offset=[20,-18],front=3.4),
    ('wordking',0): dict(offset=[-11.5,-8],front=3.8),
    ('wordking',4): dict(offset=[-4,9.1]),
    # Both north-campus shops now face the garden promenade, with a real front
    # court outside the foundation; their entrances no longer route sideways.
    ('universities',6): dict(offset=[-8,-25],yaw=0,front=2.8),
    ('universities',7): dict(offset=[8,-25],yaw=0,front=3.0),
    ('universities',1): dict(asset='commercial/Models/GLB format/building-i.glb',height=5.5),
    ('universities',3): dict(asset='commercial/Models/GLB format/building-d.glb',height=4.6,front=3.0),
    ('universities',4): dict(yaw=90,front=3.4),
    ('universities',5): dict(yaw=-90,front=3.3),
    ('recommendations',5): dict(yaw=-90,front=3.4),
    ('recommendations',7): dict(yaw=180,front=3.3),
    ('life',0): dict(yaw=90,front=3.1),
    ('life',1): dict(front=4.1),
    # The residential garden spur remains connected at [-5,4]; the house faces
    # it directly, so its forecourt approaches the door without crossing a wall.
    ('life',2): dict(yaw=90,front=3.4),
    ('life',3): dict(front=3.7),
    ('life',4): dict(front=3.4),
    ('life',5): dict(yaw=90,front=3.3),
    # These two shops had faced away from the ring road; their straight access
    # paths crossed their own buildings. Turn both toward the public sidewalk.
    ('life',6): dict(offset=[26,-9],yaw=-90,front=3.3),
    ('life',7): dict(asset='commercial/Models/GLB format/building-d.glb',height=4.0,yaw=90,front=3.4),
}
districts=json.loads(path.read_text(encoding='utf8'))
record=[]
for district in districts:
    for index,row in enumerate(district['urban_buildings']):
        patch=changes.get((district['station'],index))
        if patch:
            record.append(dict(station=district['station'],index=index,before=dict(row),after=dict(row,**patch)))
            row.update(patch)
path.write_text(json.dumps(districts,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
report_path=ROOT/'deliverables/building-walkway-adjustments.json'
prior={(r['station'],r['index']):r for r in json.loads(report_path.read_text(encoding='utf8'))} if report_path.exists() else {}
for row in record:
    key=(row['station'],row['index'])
    if key in prior:
        row['before']=prior[key]['before']
    prior[key]=row
report_path.write_text(json.dumps(list(prior.values()),indent=2),encoding='utf8')
print(f'Adjusted {len(record)} parcels/entrances after complete sidewalk capsule review.')
