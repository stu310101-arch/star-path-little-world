"""Check the new baked rest garment against the actual .52 m seat slab."""
import hashlib, json
from pathlib import Path
import numpy as np
from author_bench_rest import InputGLB, ROOT, STEPS

asset=InputGLB(ROOT/'game/assets/character/graduate_rest.glb')
report=json.loads((ROOT/'deliverables/bench-rest/pose-authoring.json').read_text(encoding='utf-8'))
checks=[]
def check(name,ok,details=None):
    checks.append({'name':name,'passed':bool(ok),'details':details})

contacts=[]
mesh_count=0
for mesh in asset.doc['meshes']:
    mesh_count+=1
    foot_minima=[]
    for primitive in mesh['primitives']:
        points=asset.array(primitive['attributes']['POSITION'])
        targets=primitive['targets']
        check(mesh['name']+' pose count',len(targets)==STEPS)
        check(mesh['name']+' finite standing geometry',np.isfinite(points).all())
        previous=points;finite=True;maximum_step=0.0
        for target in targets:
            pose=points+asset.array(target['POSITION'])
            finite=finite and np.isfinite(pose).all()
            maximum_step=max(maximum_step,float(np.max(np.linalg.norm(pose-previous,axis=1))))
            previous=pose
        check(mesh['name']+' finite sampled geometry',finite)
        check(mesh['name']+' continuous pose steps',maximum_step<.15,maximum_step)
        if 'gown' in mesh['name'] or 'trousers' in mesh['name']:
            triangles=pose[asset.array(primitive['indices']).reshape(-1,3)]
            for a in range(7):
                for b in range(7-a):
                    weights=np.array([a,b,6-a-b])/6
                    points=(triangles*weights[None,:,None]).sum(1)
                    inside=(np.abs(points[:,0])<.70)&(np.abs(points[:,2])<.225)&(points[:,1]>.422)&(points[:,1]<.518)
                    if inside.any():contacts.append({'mesh':mesh['name'],'samples':int(inside.sum())})
        if 'trousers' in mesh['name']:
            foot_minima.append(float(pose[:,1].min()))
    if foot_minima:
        minimum=min(foot_minima)
        check('feet stay at ground at rest',-.015<=minimum<=.035,minimum)
check('seat slab has no garment or trouser intersections',not contacts,contacts)
check('all character parts preserved',mesh_count==27,mesh_count)
for side in ['L','R']:
    knee=report['seated_bones']['LowerLeg.'+side]
    palm=report['seated_bones']['Palm.'+side]
    check('bent knee in front of seat '+side,knee[2]>.34 and .46<knee[1]<.59,knee)
    check('resting hand above lap '+side,.65<palm[1]<.76 and .22<palm[2]<.34,palm)
originals={}
for name in ['graduate.glb','graduate_jump.glb']:
    originals[name]=hashlib.sha256((ROOT/'game/assets/character'/name).read_bytes()).hexdigest()
check('refined flip remains original asset',originals['graduate_jump.glb']=='785f53c1f26577d781f782656be620304f35fde0e1aa1e3174a7c28abb4cd489')
result={'checks':len(checks),'failures':sum(not check['passed'] for check in checks),
        'original_asset_sha256':originals,'results':checks}
(ROOT/'deliverables/bench-rest/pose-checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({key:value for key,value in result.items() if key!='results'}))
raise SystemExit(1 if result['failures'] else 0)
