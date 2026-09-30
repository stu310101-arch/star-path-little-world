"""Physical, true-size cloth solve for the walking graduate, baked into the file."""
import bpy,bmesh,math,json,sys,numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.geometry import closest_point_on_tri,barycentric_transform
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from cloth_surface_helpers import closed_body_topology,body_surface_positions,enforce_body_clearance,ground_foot_controls,black_regalia
from regalia_arm_clearance import prepare_regalia_arm_clearance,adjust_current_arm_pose
OUT=ROOT/'art'/'Graduate'; ANIM=OUT/'animation'
SCALE=1.75/4.8; PERIOD=36; WARMUP=45; TRANSITION=36; CYCLES=5
walk=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=walk
rig=next(o for o in walk.objects if o.type=='ARMATURE')
gown=next(o for o in walk.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
body=next(o for o in walk.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
stoles=[o for o in walk.objects if 'Blue and gold stole' in o.get('graduate_role','') or 'Stole woven bar' in o.get('graduate_role','')]
walk_action=rig.animation_data.action
arm_clearance=prepare_regalia_arm_clearance(walk,rig,body,PERIOD)
walk_action=rig.animation_data.action

def fcurves(action):
    return [fc for l in action.layers for s in l.strips for b in s.channelbags for fc in b.fcurves]

# A calf-length robe calls for a measured stride and low foot clearance.
for fc in fcurves(walk_action):
    if fc.data_path in ('pose.bones["Foot.L"].location','pose.bones["Foot.R"].location'):
        for k in fc.keyframe_points:
            if fc.array_index==1:k.co.y*=.78
            elif fc.array_index==2 and k.co.y>0:k.co.y*=.65
foot_corrections=ground_foot_controls(walk,rig,body,PERIOD)
black_regalia()

def skin(obj,v):
    result=Matrix([[0.]*4 for _ in range(4)]);total=0
    for g in v.groups:
        bone=rig.pose.bones.get(obj.vertex_groups[g.group].name)
        if not bone or not bone.bone.use_deform or g.weight<=0:continue
        mat=bone.matrix@bone.bone.matrix_local.inverted();total+=g.weight
        for a in range(4):
            for b in range(4):result[a][b]+=mat[a][b]*g.weight
    if total==0:return Matrix.Identity(4)
    return result*(1/total)

def pose_values():
    return {b.name:(b.location.copy(),b.rotation_quaternion.copy(),b.scale.copy()) for b in rig.pose.bones}

def set_values(values):
    for name,(loc,q,scale) in values.items():
        pb=rig.pose.bones[name];pb.location=loc;pb.rotation_quaternion=q;pb.scale=scale
    bpy.context.view_layer.update()

# Preserve the original silhouette, adding height loops for actual cloth bending.
gown.shape_key_clear()
old=[v.co.copy() for v in gown.data.vertices]
# End below the knee, between knee and mid-calf, while keeping the waist fixed.
for co in old:co.z+=.52*min(1,max(0,(2.65-co.z)/(2.65-.62)))
oldweights=[{gown.vertex_groups[g.group].name:g.weight for g in v.groups} for v in gown.data.vertices]
oldmats=list(gown.data.materials)
cuts=[1,4,6,4,3,2,2,2]
verts=[];weights=[]
for row,count in enumerate(cuts):
    for step in range(count):
        t=step/count
        for i in range(48):
            a=row*48+i;b=(row+1)*48+i
            co=old[a].lerp(old[b],t);verts.append(co)
            if co.z<2.22:weights.append({'Hips':1.0})
            else:
                names=set(oldweights[a])|set(oldweights[b])
                w={n:oldweights[a].get(n,0)*(1-t)+oldweights[b].get(n,0)*t for n in names if 'Leg.' not in n}
                total=sum(w.values());weights.append({n:v/total for n,v in w.items()} if total else {'Hips':1.})
verts.extend(old[-48:]);weights.extend(oldweights[-48:])
faces=[];mat_indices=[]
for row in range(len(verts)//48-1):
    for i in range(48):
        faces.append((row*48+i,row*48+(i+1)%48,(row+1)*48+(i+1)%48,(row+1)*48+i))
        mat_indices.append(1 if i%4==0 else (2 if i%4==2 else 0))
# Cut the front placket below the waist into two free cloth edges. A closed
# tube catches both moving shins; an academic gown opens below its fastening.
front_split={}
for vi in range(len(verts)):
    co=verts[vi]
    if vi%48==36 and co.z<2.65:
        gap=.05*min(1,max(0,(2.65-co.z)/.45))
        right=co.copy();right.x+=gap
        co.x-=gap
        front_split[vi]=len(verts)
        verts.append(right);weights.append(weights[vi].copy())
faces=[tuple(front_split.get(v,v) for v in face) if face[0]%48==36 else face for face in faces]
mesh=bpy.data.meshes.new('Graduate gown | cloth-ready vertical loops')
mesh.from_pydata(verts,[],faces);mesh.update()
gown.data=mesh
for m in oldmats:mesh.materials.append(m)
for p,mi in zip(mesh.polygons,mat_indices):p.material_index=mi
gown.vertex_groups.clear()
for i,w in enumerate(weights):
    for name,value in w.items():
        if value>1e-6:
            group=gown.vertex_groups.get(name) or gown.vertex_groups.new(name=name)
            group.add([i],value,'REPLACE')
for obj in stoles:obj.shape_key_clear()
rig.hide_set(False)

# Capture the authored gait plus a stationary and gradually introduced pre-roll.
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=bpy.data.actions['Man_Idle']
if rig.animation_data.action.slots:rig.animation_data.action_slot=rig.animation_data.action.slots[0]
walk.frame_set(17);bpy.context.view_layer.update();adjust_current_arm_pose(rig);idle=pose_values()
rig.animation_data.action=walk_action
if walk_action.slots:rig.animation_data.action_slot=walk_action.slots[0]
cycle=[]
for f in range(1,PERIOD+1):
    walk.frame_set(f);bpy.context.view_layer.update();cycle.append(pose_values())
rig.animation_data.action=None

body_ids,body_faces=closed_body_topology(body)
def collider_geometry():
    return body_surface_positions(body,body_ids,SCALE,margin=.004),body_faces

cloth_inputs=[];body_inputs=[];proxy_faces=None
input_values=[idle]
for k in range(1,TRANSITION+1):
    t=k/TRANSITION;t=t*t*(3-2*t)
    phase=(k-1)%PERIOD;target=cycle[phase]
    input_values.append({name:(idle[name][0].lerp(target[name][0],t),idle[name][1].slerp(target[name][1],t),idle[name][2].lerp(target[name][2],t)) for name in idle})
input_values.extend(cycle)
for values in input_values:
    set_values(values)
    cloth_inputs.append([skin(gown,v)@v.co*SCALE for v in gown.data.vertices])
    points,proxy_faces=collider_geometry();body_inputs.append(points)
rig.animation_data.action=walk_action
walk.frame_set(1);bpy.context.view_layer.update()

sim=bpy.data.scenes.new('TEMP | True-size cloth simulation')
sim.render.fps=30;sim.gravity=(0,0,-9.81)
sim.frame_start=1;sim.frame_end=WARMUP+TRANSITION+CYCLES*PERIOD
bpy.context.window.scene=sim
def proxy(name,positions,polys):
    me=bpy.data.meshes.new(name);me.from_pydata(positions,[],polys);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);sim.collection.objects.link(ob);return ob
cloth=proxy('Physics gown | meters',cloth_inputs[0],faces)
collider=proxy('Physics actual body surface | meters',body_inputs[0],proxy_faces)
print('INITIAL_CLOTH_BOUNDS',np.min(cloth_inputs[0],axis=0).tolist(),np.max(cloth_inputs[0],axis=0).tolist(),flush=True)

def input_keys(obj,inputs):
    obj.shape_key_add(name='Basis')
    keys=[]
    for i,positions in enumerate(inputs):
        key=obj.shape_key_add(name='Motion_%03d'%i)
        for d,co in zip(key.data,positions):d.co=co
        keys.append(key)
    last=None
    for frame in range(1,sim.frame_end+1):
        if frame<=WARMUP:idx=0
        elif frame<=WARMUP+TRANSITION:idx=frame-WARMUP
        else:idx=1+TRANSITION+(frame-WARMUP-TRANSITION-1)%PERIOD
        if last is not None and idx!=last:
            keys[last].value=0;keys[last].keyframe_insert('value',frame=frame)
        if idx!=last:
            if frame>1:keys[idx].value=0;keys[idx].keyframe_insert('value',frame=frame-1)
            keys[idx].value=1;keys[idx].keyframe_insert('value',frame=frame)
        last=idx
    for fc in fcurves(obj.data.shape_keys.animation_data.action):
        for k in fc.keyframe_points:k.interpolation='LINEAR'
input_keys(cloth,cloth_inputs);input_keys(collider,body_inputs)

collider.modifiers.new('Leg and hip contact','COLLISION')
collider.collision.thickness_outer=.0025
collider.collision.thickness_inner=.002
collider.collision.cloth_friction=.2
pin=cloth.vertex_groups.new(name='Waist and upper body fixed')
for i,co in enumerate(verts):
    z=co.z
    value=min(1,max(0,(z-2.20)/.45))
    value=value*value*(3-2*value)
    if value>0:pin.add([i],value,'REPLACE')
mod=cloth.modifiers.new('Academic fabric | physical cloth','CLOTH')
s=mod.settings
s.quality=24;s.mass=.70/len(verts);s.air_damping=.003
s.tension_stiffness=25;s.compression_stiffness=25;s.shear_stiffness=10;s.bending_stiffness=.08
s.tension_damping=.4;s.compression_damping=.4;s.shear_damping=.4;s.bending_damping=.003
s.vertex_group_mass=pin.name;s.pin_stiffness=1
s.use_dynamic_mesh=False
if hasattr(s,'bending_model'):s.bending_model='ANGULAR'
hem=cloth.vertex_groups.new(name='Double folded sewn hem')
for i,co in enumerate(verts):
    value=min(1,max(0,(1.40-co.z)/.20))
    if value>0:hem.add([i],value,'REPLACE')
s.vertex_group_bending=hem.name;s.bending_stiffness_max=.22
c=mod.collision_settings
c.use_collision=True;c.distance_min=.0035;c.collision_quality=8;c.friction=.2
c.use_self_collision=True;c.self_distance_min=.0025;c.self_friction=.2
mod.point_cache.frame_start=1;mod.point_cache.frame_end=sim.frame_end
sim.frame_set(1);bpy.context.view_layer.update()
captured=[]
for frame in range(1,sim.frame_end+1):
    sim.frame_set(frame);bpy.context.view_layer.update()
    dg=bpy.context.evaluated_depsgraph_get();ev=cloth.evaluated_get(dg);me=ev.to_mesh()
    points=np.array([v.co[:] for v in me.vertices],dtype=np.float32)
    if not np.isfinite(points).all() or np.abs(points).max()>8:raise RuntimeError('Cloth simulation became unstable at '+str(frame))
    if frame>WARMUP+TRANSITION+(CYCLES-3)*PERIOD:captured.append(points.copy())
    ev.to_mesh_clear()
    if frame%18==0:print('CLOTH_FRAME',frame,sim.frame_end,'MIN_Z',float(points[:,2].min()),flush=True)
    if '--warmup-test' in sys.argv and frame==WARMUP:
        np.savez_compressed(ANIM/'walk_warmup_test.npz',points=points,initial=np.asarray(cloth_inputs[0]),body=np.asarray(body_inputs[0]),body_faces=np.asarray(proxy_faces),cloth_faces=np.asarray(faces))
        print('WARMUP_TEST_DONE',float(points[:48,2].min()),float(points[:48,2].max()),flush=True)
        bpy.ops.wm.quit_blender()
captured=np.asarray(captured)
last=captured[-PERIOD:]
prev=captured[-2*PERIOD:-PERIOD]
cycle_rms=float(np.sqrt(np.mean((last-prev)**2)))
cycle_max=float(np.linalg.norm(last-prev,axis=2).max())
# A periodic fit retains low-frequency physical cloth motion while removing
# residual simulation jitter at the cycle boundary. Preserve the mean folds.
frequency=np.fft.rfft(last,axis=0)
frequency[9:]=0
periodic=np.fft.irfft(frequency,n=PERIOD,axis=0).astype(np.float32)
# The fully pinned collar and torso must follow the skeleton exactly.
fixed=np.array([v.z>=2.65 for v in verts])
exact=np.asarray(cloth_inputs[1+TRANSITION:])
periodic[:,fixed]=exact[:,fixed]
clearance_report=[]
for i in range(PERIOD):
    periodic[i],contact=enforce_body_clearance(periodic[i],body_inputs[1+TRANSITION+i],proxy_faces,fixed,faces)
    clearance_report.append(contact)
filter_rms=float(np.sqrt(np.mean((periodic-last)**2)))
filter_max=float(np.linalg.norm(periodic-last,axis=2).max())
np.savez_compressed(ANIM/'walk_physical_cloth.npz',raw=last,previous=prev,periodic=periodic,inputs=exact,all_cycles=captured,body_vertices=np.asarray(body_inputs[1+TRANSITION:]),body_faces=np.asarray(proxy_faces),cloth_faces=np.asarray(faces))
physics_report={'scale':SCALE,'vertices':len(verts),'simulation_frames':sim.frame_end,'quality':s.quality,
                'mass_per_vertex_kg':s.mass,'total_gown_mass_kg':s.mass*len(verts),
                'gravity':list(sim.gravity),'self_collision':True,'last_cycle_rms_m':cycle_rms,
                'last_cycle_max_m':cycle_max,'periodic_filter_rms_m':filter_rms,
                'periodic_filter_max_m':filter_max,
                'collider':'actual evaluated body mesh, capped openings, 4 mm surface margin',
                'shortened_m':.52*SCALE,'palette':'black and charcoal with antique gold trim',
                'foot_corrections_before_simulation':foot_corrections,'clearance_corrections':clearance_report,
                'converged':cycle_rms<=.002 and cycle_max<=.01,
                'status':'candidate - requires visual and collision review'}
(ANIM/'cloth-physics-validation.json').write_text(json.dumps(physics_report,indent=2),encoding='utf-8')
print('CLOTH_SOLVED',json.dumps(physics_report),flush=True)

# Bake physical positions into the actual character mesh, compensating for its
# existing skin matrices; Blender can then play without a simulation cache.
bpy.context.window.scene=walk
rig.animation_data.action=walk_action
physical=[np.asarray(frame/SCALE) for frame in periodic]

def bake_keys(obj,positions,label):
    obj.shape_key_add(name='Basis')
    for i,coords in enumerate(positions):
        key=obj.shape_key_add(name=label+'_%02d'%(i+1))
        for d,co in zip(key.data,coords):d.co=co
        f=i+1;times={1:0,PERIOD+1:0,max(1,f-1):0,f:1,min(PERIOD+1,f+1):0}
        if i==0:times.update({1:1,2:0,PERIOD:0,PERIOD+1:1})
        if i==PERIOD-1:times.update({1:0,PERIOD-1:0,PERIOD:1,PERIOD+1:0})
        for frame,value in sorted(times.items()):key.value=value;key.keyframe_insert('value',frame=frame)
    action=obj.data.shape_keys.animation_data.action;action.name=label;action.use_fake_user=True
    for fc in fcurves(action):
        for k in fc.keyframe_points:k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')

gown.data.calc_loop_triangles()
triangles=[tuple(t.vertices) for t in gown.data.loop_triangles]
anchors={}
for obj in stoles:
    objanchors={}
    for v in obj.data.vertices:
        if v.co.z>3.81:continue
        best=None
        for ids in triangles:
            a,b,c=[verts[j] for j in ids]
            point=closest_point_on_tri(v.co,a,b,c);dist=(v.co-point).length_squared
            if best is None or dist<best[0]:best=(dist,ids,point)
        _,ids,point=best;a,b,c=[verts[j] for j in ids]
        bary=barycentric_transform(point,a,b,c,Vector((1,0,0)),Vector((0,1,0)),Vector((0,0,1)))
        normal=(b-a).cross(c-a).normalized()
        objanchors[v.index]=(ids,bary,max(.025,abs((v.co-point).dot(normal))))
    anchors[obj]=objanchors

gown_samples=[];stole_samples={o:[] for o in stoles}
for i,worldarray in enumerate(physical):
    walk.frame_set(i+1);bpy.context.view_layer.update();world=[Vector(v) for v in worldarray]
    gown_samples.append([skin(gown,v).inverted_safe()@world[v.index] for v in gown.data.vertices])
    for obj in stoles:
        points=[]
        for v in obj.data.vertices:
            if v.index not in anchors[obj]:points.append(v.co.copy());continue
            ids,bary,gap=anchors[obj][v.index];a,b,c=[world[j] for j in ids]
            normal=(b-a).cross(c-a).normalized()
            points.append(skin(obj,v).inverted_safe()@(a*bary.x+b*bary.y+c*bary.z+normal*gap))
        stole_samples[obj].append(points)
bake_keys(gown,gown_samples,'Graduate_Walk_PhysicalGown')
for obj,samples in stole_samples.items():bake_keys(obj,samples,'Graduate_Walk_Physical_'+obj.name)
walk['Cloth']='Short black front-opening gown; actual body surface collision and post-fit clearance, with gravity, sewn hem and a baked cycle.'
walk['Cloth simulation scale']=SCALE
rig.hide_set(True);walk.frame_set(1)
bpy.data.scenes.remove(sim)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_WalkCloth_candidate.blend'))
print('PHYSICAL_WALK_SAVED',flush=True)
