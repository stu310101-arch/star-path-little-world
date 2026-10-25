"""Validate the .208 m seat variant without changing the full-height pose."""
import hashlib, json
import numpy as np
from author_bench_rest import InputGLB, ROOT, STEPS

asset=InputGLB(ROOT/'game/assets/character/graduate_rest_small.glb')
original=InputGLB(ROOT/'game/assets/character/graduate_rest.glb')
folder=ROOT/'deliverables/bench-rest-small'
report=json.loads((folder/'pose-authoring.json').read_text(encoding='utf-8'))
checks=[]
def check(label,passed,detail=None):checks.append(dict(test=label,passed=bool(passed),detail=detail))
check('Original standing and full-height rest assets unchanged',all(hashlib.sha256((ROOT/'game/assets/character'/name).read_bytes()).hexdigest()==sha for name,sha in {
 'graduate.glb':'cef60f3c9b551cbdbbf6ad8e0e7967575b1e9b53e671375dc51395dad6cb5e4b',
 'graduate_rest.glb':'ed43c4a23a697836acc72d072d2d813fd20613143ae3c17eb273905c8eedd30d'}.items()))
check('Independent .208 m seat asset',asset.doc['extras']['seat_top_m']==.208)
check('Original number of parts and materials',len(asset.doc['meshes'])==27 and asset.doc['materials']==original.doc['materials'])
contacts=[];triangles_count=0;support_count=0;feet_min=[]
for mesh,base in zip(asset.doc['meshes'],original.doc['meshes']):
 for primitive,base_primitive in zip(mesh['primitives'],base['primitives']):
  points=asset.array(primitive['attributes']['POSITION']);old_points=original.array(base_primitive['attributes']['POSITION'])
  name=mesh['name'];indices=asset.array(primitive['indices']).reshape(-1,3);triangles_count+=len(indices)
  check(name+' original-size standing pose',np.array_equal(points,old_points))
  check(name+' original topology',np.array_equal(indices,original.array(base_primitive['indices']).reshape(-1,3)))
  check(name+' 12 editable pose samples',len(primitive['targets'])==STEPS)
  poses=[points+asset.array(t['POSITION']) for t in primitive['targets']]
  check(name+' finite complete motion',all(np.isfinite(p).all() for p in poses))
  check(name+' stays above floor',min(float(p[:,1].min()) for p in poses)>=-.001)
  travel=max(float(np.linalg.norm(b-a,axis=1).max()) for a,b in zip([points]+poses[:-1],poses))
  check(name+' continuous lowering arc',travel<.15,travel)
  final=poses[-1]
  if 'gown' in name or 'trousers' in name:
   tris=final[indices]
   for a in range(9):
    for b in range(9-a):
     sample=(tris*(np.array([a,b,8-a-b])/8)[None,:,None]).sum(1)
     inside=(np.abs(sample[:,0])<.28)&(np.abs(sample[:,2])<.09)&(sample[:,1]>.169)&(sample[:,1]<.207)
     if inside.any():contacts.append({'mesh':name,'samples':int(inside.sum())})
   support_count+=int(((np.abs(final[:,0])<.28)&(np.abs(final[:,2])<.1)&(final[:,1]>=.208)&(final[:,1]<.235)).sum())
  mask=points[:,1]<.13
  if mask.any() and points[:,1].min()<.02:
   feet_min=[float(p[mask,1].min()) for p in poses]
   check('Feet remain on ground throughout sitting',max(feet_min)<.035 and min(feet_min)>=-.001,feet_min)
check('No sampled cloth/trouser intersection inside seat slab',not contacts,contacts)
check('Garment has supported contact above the small seat',support_count>0,support_count)
for side in ['L','R']:
 for upper,lower in [('UpperLeg.','LowerLeg.'),('LowerLeg.','Foot.')]:
  posed=report['seated_bones'];standing=report['standing_bones']
  length=lambda bones:float(np.linalg.norm(np.array(bones[upper+side])-np.array(bones[lower+side])))
  check(side+' '+upper+' keeps original bone length',abs(length(posed)-length(standing))<.00001,[length(posed),length(standing)])
 knee=report['seated_bones']['LowerLeg.'+side];hip=report['seated_bones']['UpperLeg.'+side]
 check(side+' knees bend forward above low hips',knee[1]>hip[1]+.1 and knee[2]>.25,[hip,knee])
check('Topology stays within existing rest asset budget',triangles_count==sum(len(original.array(p['indices']))//3 for m in original.doc['meshes'] for p in m['primitives']),triangles_count)
result=dict(checks=len(checks),failures=sum(not c['passed'] for c in checks),triangles=triangles_count,parts=len(asset.doc['meshes']),materials=len(asset.doc['materials']),results=checks)
(folder/'pose-checks.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k!='results'}))
for item in checks:
 if not item['passed']:print(json.dumps(item))
raise SystemExit(bool(result['failures']))
