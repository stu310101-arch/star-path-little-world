"""Bake frontflip gravity/inertia with free gown and cuff boundaries.

World-metre solve includes a temporary ballistic trajectory, torso pins,
animated body and closed arm capsules. Only the rig pivot remains in export.
"""
import bpy, sys, json
from pathlib import Path
import numpy as np
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import (SCALE,SkinBinding,evaluated_points,add_proxy,add_collision,
 animate_proxy,bake_keys,make_stole_anchors)
from cloth_surface_helpers import closed_body_topology,body_surface_positions
from sleeve_arm_colliders import arm_capsule_inputs
from simulate_sleeve_cloth import contact_clearance
OUT=ROOT/'deliverables/frontflip-refined'
scene=next(s for s in bpy.data.scenes if s.name.startswith('05_FORWARD'))
bpy.context.window.scene=scene
scene.frame_set(1);bpy.context.view_layer.update()
rig=next(o for o in scene.objects if o.type=='ARMATURE')
roles={o.get('graduate_role'):o for o in scene.objects if o.type=='MESH' and o.get('graduate_role')}
gown=roles['01 | Pleated bachelor gown']
garments=[gown,roles['02 | Bell sleeve L'],roles['02 | Bell sleeve R']]
stoles=[o for r,o in roles.items() if r.startswith(('03 |','04 |'))]
body=roles['Graduate | original face, hands and trousers']
states=[(m,m.show_viewport) for o in garments+stoles for m in o.modifiers if m.type!='ARMATURE']
for m,_ in states:m.show_viewport=False
bindings={o:SkinBinding(o,rig) for o in garments+stoles}
rest={o:np.array([v.co[:] for v in o.data.vertices]) for o in garments+stoles}
initial={o:evaluated_points(o) for o in garments+stoles}
anchors=make_stole_anchors(gown,initial[gown],stoles,initial,rest)
offsets=[0];faces=[];pins=[]
for o in garments:
 faces.extend(tuple(int(i)+offsets[-1] for i in p.vertices) for p in o.data.polygons)
 if o==gown:
  weight=np.clip((rest[o][:,2]-2.30)/.43,0,1)
  pins.extend(weight*weight*(3-2*weight))
 else:
  seam=o.vertex_groups['Sleeve shoulder seam only'].index
  pins.extend(next((g.weight for g in v.groups if g.group==seam),0.) for v in o.data.vertices)
 offsets.append(offsets[-1]+len(o.data.vertices))
pins=np.array(pins);fixed=pins>=.999
body_ids,body_faces=closed_body_topology(body)
cloth_inputs=[];body_inputs=[];arm_inputs={};arm_faces={};translations=[]
for f in range(1,218):
 scene.frame_set(f);bpy.context.view_layer.update()
 t=(f-1)/100
 u=np.clip((t-.12)/.84,0,1)
 flight=u*(2*7.8/18)
 translation=np.array([0.,0.,7.8*flight-9*flight*flight])
 translations.append(translation)
 cloth_inputs.append(np.concatenate([evaluated_points(o) for o in garments])+translation)
 body_inputs.append(np.asarray(body_surface_positions(body,body_ids,SCALE,margin=.002))+translation)
 for name,data in arm_capsule_inputs(rig).items():
  arm_inputs.setdefault(name,[]).append(data['points']+translation);arm_faces[name]=data['faces']
 if f%40==1:print('DRAPE_INPUT',f,flush=True)
cloth_inputs=np.array(cloth_inputs);body_inputs=np.array(body_inputs);translations=np.array(translations)
scene.frame_set(1)
sim=bpy.data.scenes.new('TEMP_Frontflip_Physical_Drape')
sim.render.fps=100;sim.gravity=(0,0,-18)
warmup=90;sim.frame_start=1;sim.frame_end=warmup+217
bpy.context.window.scene=sim
cloth=add_proxy(sim,'Free gown and sleeve cloth',cloth_inputs[0],faces)
animate_proxy(cloth,cloth_inputs,warmup)
collider=add_proxy(sim,'Actual body collision',body_inputs[0],body_faces)
animate_proxy(collider,body_inputs,warmup);add_collision(collider)
for name,inputs in arm_inputs.items():
 proxy=add_proxy(sim,name+' collision',inputs[0],arm_faces[name])
 animate_proxy(proxy,inputs,warmup);add_collision(proxy)
pin=cloth.vertex_groups.new(name='Sewn torso and shoulder boundaries')
for i,w in enumerate(pins):
 if w:pin.add([i],float(w),'REPLACE')
mod=cloth.modifiers.new('Gravity inertia and self contact','CLOTH')
s=mod.settings;s.quality=12;s.mass=.70/len(cloth.data.vertices)
s.air_damping=.12
s.tension_stiffness=s.compression_stiffness=32
s.shear_stiffness=18;s.bending_stiffness=.10
s.tension_damping=s.compression_damping=s.shear_damping=2.0;s.bending_damping=.08
s.vertex_group_mass=pin.name;s.pin_stiffness=1;s.use_dynamic_mesh=False
c=mod.collision_settings;c.use_collision=True;c.use_self_collision=True
c.distance_min=.003;c.collision_quality=6;c.friction=2
c.self_distance_min=.002;c.self_friction=2
mod.point_cache.frame_start=1;mod.point_cache.frame_end=sim.frame_end
if '--reuse-raw' in sys.argv:
 raw=np.load(OUT/'raw-cloth.npz')['raw']
else:
 raw=[]
 for f in range(1,sim.frame_end+1):
  sim.frame_set(f);bpy.context.view_layer.update()
  points=evaluated_points(cloth,scale=1)
  assert np.isfinite(points).all() and np.abs(points).max()<12,('unstable cloth',f)
  if f>warmup:raw.append(points.copy())
  if f%20==0:print('DRAPE_SOLVE',f,sim.frame_end,flush=True)
 raw=np.array(raw)
 np.savez_compressed(OUT/'raw-cloth.npz',raw=raw,inputs=cloth_inputs,translations=translations,pins=pins)
# Filter sub-face buckling from this low-resolution game garment. Smooth only
# the simulated displacement, preserving the original tailored folds and cuffs.
neighbors=[set() for _ in pins]
for face in faces:
 for a,b in zip(face,face[1:]+face[:1]):neighbors[a].add(b);neighbors[b].add(a)
delta=raw-cloth_inputs
for _ in range(10):
 averaged=np.stack([delta[:,list(ns)].mean(axis=1) if ns else delta[:,i] for i,ns in enumerate(neighbors)],axis=1)
 delta=delta*.55+averaged*.45
 delta[:,fixed]=0
# The sleeve's sewn circular sections retain an opening around the arm. Use
# the freely simulated inertial offset with a broad, bounded envelope so tight
# elbow folds cannot collapse into needle-shaped cloth during the tuck.
for j in [1,2]:
 ids=slice(offsets[j],offsets[j+1]);movement=delta[:,ids]
 length=np.linalg.norm(movement,axis=2)
 movement*=np.minimum(1,.055/np.maximum(length,1e-10))[...,None]
 delta[:,ids]=movement*.65
raw=cloth_inputs+delta
physical=raw.copy();contacts=[]
for i in range(217):
 # Preserve original clip boundary and softly settle the final residual into
 # the exact existing hanging pose; free motion occupies the full landing.
 t=i/100
 start=np.clip(t/.10,0,1);start=start*start*(3-2*start)
 end=np.clip((t-1.55)/.61,0,1);end=end*end*(3-2*end)
 weight=start*(1-end)
 physical[i]=cloth_inputs[i]*(1-weight)+physical[i]*weight
 physical[i,fixed]=cloth_inputs[i,fixed]
 surfaces=[(body_inputs[i],body_faces)]+[(arm_inputs[n][i],arm_faces[n]) for n in arm_inputs]
 physical[i],report=contact_clearance(physical[i],surfaces,fixed,faces,iterations=5)
 contacts.append({'frame':i+1,**report})
 if i%30==0:print('DRAPE_CLEARANCE',i+1,report,flush=True)
np.savez_compressed(OUT/'physical-cloth.npz',points=physical,inputs=cloth_inputs,translations=translations,pins=pins)
bpy.context.window.scene=scene
samples={o:[] for o in garments+stoles}
for i in range(217):
 scene.frame_set(i+1);bpy.context.view_layer.update()
 for j,o in enumerate(garments):
  points=physical[i,offsets[j]:offsets[j+1]]-translations[i]
  samples[o].append(bindings[o].inverse_points(points))
 world=[Vector(p) for p in physical[i,:offsets[1]]-translations[i]]
 for o in stoles:
  inv=bindings[o].world_matrices(inverse=True);coords=rest[o].copy()
  for index,(ids,bary,gap) in anchors[o].items():
   a,b,c=[world[j] for j in ids];normal=(b-a).cross(c-a).normalized()
   coords[index]=inv[index]@((a*bary.x+b*bary.y+c*bary.z+normal*gap)/SCALE)
  samples[o].append(coords)
for o,data in samples.items():bake_keys(o,data,1,'RefinedGravity_'+o.get('graduate_role'))
errors=[]
for i in [0,12,24,45,60,84,96,105,125,155,185,216]:
 scene.frame_set(i+1);bpy.context.view_layer.update()
 for j,o in enumerate(garments):
  desired=physical[i,offsets[j]:offsets[j+1]]-translations[i]
  errors.append(float(np.max(np.linalg.norm(evaluated_points(o)-desired,axis=1))))
assert max(errors)<.0002,errors
for m,vis in states:m.show_viewport=vis
for o in list(sim.objects):bpy.data.objects.remove(o,do_unlink=True)
bpy.data.scenes.remove(sim)
bpy.ops.outliner.orphans_purge(do_recursive=True)
scene['cloth_method']='World-metre Blender cloth: free hem/cuffs, torso/shoulder pins, body/arm/self contact, ballistic reference motion. Baked morphs with final endpoint relaxation.'
scene['cloth_gravity']=18.0;scene['cloth_warmup_seconds']=.90
scene.frame_set(1)
target=ROOT/'art/Graduate/Male_Graduate_Frontflip_Refined.blend'
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(target))
hem=rest[gown][:,2]<1.40
positions=physical[:,:offsets[1]]-translations[:,None,:]
hem_delta=np.mean(np.linalg.norm(positions[:,hem]-cloth_inputs[:,np.flatnonzero(hem)]+translations[:,None,:],axis=2),axis=1)
report={'source':str(target),'frames':217,'fps':100,'gravity':18,'warmup':90,'quality':12,
 'fixed_vertices':int(fixed.sum()),'free_vertices':int((~fixed).sum()),'bake_error_m':max(errors),
 'contacts':contacts,'hem_mean_deflection_m':hem_delta.tolist(),
 'validation':'Candidate requires actual visual/engine playback review; contact residuals listed, not hidden.'}
(OUT/'cloth-validation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('REFINED_DRAPE_SAVED',target,flush=True)
