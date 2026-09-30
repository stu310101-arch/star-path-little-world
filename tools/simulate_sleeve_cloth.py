"""Solve only the graduate's two sleeves, retaining all other authored caches.

Run once per clip in a separate background Blender; checkpoints accumulate.
Shoulder seam pins, free cuffs, real-metre Cloth gravity and animated contacts.
"""
import argparse
import json
import sys
from pathlib import Path
import bpy
import bmesh
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from simulate_portal_cloth import (SCALE, SkinBinding, evaluated_points, fcurves,
                                  add_proxy, add_collision, bake_keys)
from cloth_surface_helpers import closed_body_topology, body_surface_positions, inside
from sleeve_arm_colliders import arm_capsule_inputs

OUT = ROOT / 'art' / 'Graduate'
ANIM = OUT / 'animation'
ROLES = ['02 | Bell sleeve L', '02 | Bell sleeve R']


def refine_sleeve(obj):
    if len(obj.data.vertices) == 545:
        # Re-solve an already refined candidate from its unchanged cutting
        # mesh, discarding only that sleeve's old physical cache.
        obj.shape_key_clear()
        group=obj.vertex_groups['Sleeve shoulder seam only']
        pins=np.array([next((g.weight for g in v.groups if g.group==group.index),0.) for v in obj.data.vertices])
        cuffs=np.array([480 <= i < 544 for i in range(545)])
        return pins,cuffs,[tuple(p.vertices) for p in obj.data.polygons]
    if len(obj.data.vertices) != 113 or obj.data.shape_keys:
        raise RuntimeError('Expected original 113-vertex rigid sleeve: ' + obj.name)
    old = [v.co.copy() for v in obj.data.vertices]
    old_w = [{obj.vertex_groups[g.group].name: g.weight for g in v.groups}
             for v in obj.data.vertices]
    materials = list(obj.data.materials)
    vertices, weights, faces, indices, pins, cuffs = [], [], [], [], [], []
    # Retain the original silhouette; add longitudinal and circumferential
    # edges so a sleeve can fold instead of rotating as seven rigid hoops.
    rows = [(r, k / n) for r, n in enumerate([2, 4, 3, 4, 2, 1]) for k in range(n)]
    rows.append((5, 1.0))
    for r, t in rows:
        for j in range(32):
            a, u = j // 2, (j % 2) / 2
            ids = [r*16+a, r*16+(a+1)%16, (r+1)*16+a, (r+1)*16+(a+1)%16]
            factors = [(1-t)*(1-u), (1-t)*u, t*(1-u), t*u]
            co = sum((old[v]*w for v,w in zip(ids,factors)), Vector())
            vertices.append(co)
            names = set().union(*(old_w[v] for v in ids))
            weights.append({name: sum(old_w[v].get(name,0)*w for v,w in zip(ids,factors)) for name in names})
            # About the first 8 cm are the shoulder seam transition. No
            # elbow, wrist, or cuff point is pinned to the arm animation.
            along = abs(co.x) - abs(old[0].x)
            pin = np.clip((.27-along)/.16, 0, 1)
            pins.append(float(pin*pin*(3-2*pin)))
            cuffs.append(r == 5)
    nrow = len(rows)
    for r in range(nrow-1):
        for j in range(32):
            faces.append((r*32+j,r*32+(j+1)%32,(r+1)*32+(j+1)%32,(r+1)*32+j))
            indices.append(2 if r == nrow-2 else (1 if (j//2)%4 == 1 else 0))
    cap = len(vertices)
    vertices.append(old[-1]); weights.append(old_w[-1]); pins.append(1.0); cuffs.append(False)
    for j in range(32):
        faces.append((cap,(j+1)%32,j)); indices.append(0)
    mesh = bpy.data.meshes.new(obj.name + ' | flexible fabric topology')
    mesh.from_pydata(vertices, [], faces); mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(mesh);bm.free()
    obj.data=mesh
    for mat in materials: mesh.materials.append(mat)
    for poly,idx in zip(mesh.polygons,indices): poly.material_index=idx
    obj.vertex_groups.clear()
    for i,ws in enumerate(weights):
        for name,w in ws.items():
            if w > 1e-7:
                group=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                group.add([i],w,'REPLACE')
    seam=obj.vertex_groups.new(name='Sleeve shoulder seam only')
    for i,w in enumerate(pins):
        if w:seam.add([i],w,'REPLACE')
    obj['Sleeve dynamics']='Baked physical cloth; shoulder seam attached, elbow and cuff unpinned.'
    obj['Free cuff']=True
    return np.asarray(pins),np.asarray(cuffs),[tuple(p.vertices) for p in mesh.polygons]


def triangles(faces):
    return [tuple((f[0],f[i],f[i+1])) for f in faces for i in range(1,len(f)-1)]


def contact_clearance(points, surfaces, fixed, faces, iterations=7):
    trees=[BVHTree.FromPolygons([Vector(p) for p in pts], polys, all_triangles=True)
           for pts,polys in surfaces]
    coords=[Vector(p) for p in points]; before=np.asarray(points).copy()
    tris=triangles(faces)
    def correction(p, tree):
        hit,normal,_,dist=tree.find_nearest(p)
        if hit is None:return None
        signed=(p-hit).dot(normal)
        if signed < 0 and inside(tree,p):return hit+normal*.0025-p
        if signed >= 0 and dist < .0025:return normal*(.0025-dist)
        return None
    for _ in range(iterations):
        changed=0
        for tree in trees:
            for i,p in enumerate(coords):
                if fixed[i]:continue
                delta=correction(p,tree)
                if delta is not None and delta.length>1e-6:coords[i]+=delta;changed+=1
            for ids in tris:
                free=[i for i in ids if not fixed[i]]
                if not free:continue
                center=sum((coords[i] for i in ids),Vector())/3
                delta=correction(center,tree)
                if delta is not None and delta.length>1e-6:
                    for i in free:coords[i]+=delta*(3/len(free))
                    changed+=1
        if not changed:break
    remaining=[]
    for tree in trees:
        probes=[p for i,p in enumerate(coords) if not fixed[i]]
        probes += [sum((coords[i] for i in ids),Vector())/3 for ids in tris if not all(fixed[i] for i in ids)]
        for p in probes:
            hit,normal,_,dist=tree.find_nearest(p)
            if hit is not None and dist>.0005 and (p-hit).dot(normal)<0 and inside(tree,p):remaining.append(dist)
    result=np.asarray(coords,dtype=np.float32)
    return result, {'max_projection_m':float(np.linalg.norm(result-before,axis=1).max()),
                    'remaining_inside_probes':len(remaining),'max_penetration_m':max(remaining,default=0.0)}


def animate_inputs(obj, inputs, timeline):
    obj.shape_key_add(name='Basis'); keys=[]
    for i,points in enumerate(inputs):
        key=obj.shape_key_add(name='Input_%04d'%i)
        for v,co in zip(key.data,points):v.co=co
        key.value=0;keys.append(key)
    last=None
    for frame,idx in enumerate(timeline,1):
        if last is not None and idx!=last:
            keys[last].value=0;keys[last].keyframe_insert('value',frame=frame)
        if idx!=last:
            if frame>1:keys[idx].value=0;keys[idx].keyframe_insert('value',frame=frame-1)
            keys[idx].value=1;keys[idx].keyframe_insert('value',frame=frame)
        last=idx
    for fc in fcurves(obj.data.shape_keys.animation_data.action):
        for k in fc.keyframe_points:k.interpolation='LINEAR'
    for k in keys:k.value=0


def bake_loop(obj, samples, label):
    period=len(samples)
    obj.shape_key_clear();obj.shape_key_add(name='Basis')
    for i,coords in enumerate(samples):
        key=obj.shape_key_add(name=label+'_%03d'%(i+1))
        for dst,co in zip(key.data,coords):dst.co=co
        f=i+1;times={1:0,period+1:0,max(1,f-1):0,f:1,min(period+1,f+1):0}
        if i==0:times.update({1:1,2:0,period:0,period+1:1})
        if i==period-1:times.update({1:0,period-1:0,period:1,period+1:0})
        for frame,value in sorted(times.items()):key.value=value;key.keyframe_insert('value',frame=frame)
        key.value=0
    action=obj.data.shape_keys.animation_data.action;action.name=label;action.use_fake_user=True
    for fc in fcurves(action):
        for k in fc.keyframe_points:k.interpolation='LINEAR'
        fc.modifiers.new('CYCLES')


def run(label, quality, cycles, output, probe=False, no_self=False, no_gown=False, bending=.06, posed_rest=False):
    prefix={'walk':'01_WALK','run':'02_RUN','jump':'03_JUMP'}[label]
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    bpy.context.window.scene=scene
    rig=next(o for o in scene.objects if o.type=='ARMATURE')
    sleeves=[next(o for o in scene.objects if o.get('graduate_role')==role) for role in ROLES]
    body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
    hidden=[(o,o.hide_get(),o.hide_viewport) for o in [rig,body,gown]+sleeves]
    muted=[]
    for o,_,_ in hidden:
        o.hide_set(False);o.hide_viewport=False
        for fc in fcurves(o.animation_data.action if o.animation_data else None):
            if fc.data_path in ('hide_render','hide_viewport'):
                muted.append((fc,fc.mute));fc.mute=True
    states=[(m,m.show_viewport) for o in sleeves+[gown] for m in o.modifiers if m.type!='ARMATURE']
    for m,_ in states:m.show_viewport=False
    pins=[];cuffs=[];faces=[];offsets=[0]
    for obj in sleeves:
        p,c,fs=refine_sleeve(obj);pins.extend(p);cuffs.extend(c)
        faces.extend(tuple(i+offsets[-1] for i in f) for f in fs);offsets.append(offsets[-1]+len(p))
    pins=np.asarray(pins);fixed=pins>=.999; cuffs=np.asarray(cuffs)
    # Save the actual edited geometry immediately, independently of the long
    # solve. Opening this working file does not control the background solver.
    for m,visible in states:m.show_viewport=visible
    scene.frame_set(1)
    for obj in scene.objects:obj.select_set(False)
    sleeves[0].select_set(True);bpy.context.view_layer.objects.active=sleeves[0]
    workspace=bpy.data.workspaces.get('Default')
    if workspace:bpy.context.window.workspace=workspace
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.shading.type='SOLID';space.shading.color_type='MATERIAL'
                space.region_3d.view_perspective='PERSP'
                space.region_3d.view_location=(0,0,2.7);space.region_3d.view_distance=6.5
                space.region_3d.view_rotation=Vector((5,-12,4)).to_track_quat('Z','Y')
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate_Sleeves_Working.blend'))
    print('SLEEVE_EDITED_WORKING_FILE_SAVED',flush=True)
    for m,_ in states:m.show_viewport=False
    bindings=[SkinBinding(o,rig) for o in sleeves]
    rest=np.concatenate([np.asarray([v.co[:] for v in o.data.vertices])*SCALE for o in sleeves])
    bodyids,bodyfaces=closed_body_topology(body)
    # The visual yoke and separate bell sleeve overlap at their sewn joint.
    # A collider covering that joint makes the sleeve solve inside a closed
    # torso with no armholes. Leave armhole openings in the collision proxy;
    # keep the user's visible gown and existing baked lower hem untouched.
    gownfaces=triangles([tuple(p.vertices) for p in gown.data.polygons
                        if not (p.center.z>3.05 and abs(p.center.x)>.34)])
    inputs=[];body_inputs=[];gown_inputs=[];arms={};armfaces={}
    period=scene.frame_end-scene.frame_start+1
    for frame in range(1,period+1):
        scene.frame_set(frame);bpy.context.view_layer.update()
        inputs.append(np.concatenate([evaluated_points(o) for o in sleeves]))
        body_inputs.append(np.asarray(body_surface_positions(body,bodyids,SCALE,margin=.003)))
        gown_inputs.append(evaluated_points(gown))
        for name,data in arm_capsule_inputs(rig,SCALE).items():
            arms.setdefault(name,[]).append(data['points']);armfaces[name]=data['faces']
    inputs=np.asarray(inputs);body_inputs=np.asarray(body_inputs);gown_inputs=np.asarray(gown_inputs)
    # Use a stationary pre-roll, then introduce locomotion progressively over
    # one cycle. Interpolated surface inputs affect pins and collisions only;
    # the unpinned fabric retains a fixed rest shape throughout the solve.
    warmup=45 if label!='jump' else 30
    transition=period if label!='jump' else 0
    def staged(data):
        if not transition:return np.asarray(data)
        tween=[]
        for i in range(period):
            t=(i+1)/period;t=t*t*(3-2*t)
            tween.append(data[0]*(1-t)+data[i]*t)
        return np.asarray([data[0]]+tween+list(data))
    if transition:
        timeline=[0]*warmup+list(range(1,period+1))+[1+period+i for _ in range(cycles) for i in range(period)]
    else:timeline=[0]*warmup+list(range(period))
    sim=bpy.data.scenes.new('TEMP | '+label+' sleeve cloth solve');sim.render.fps=30
    sim.gravity=(0,0,-9.81);sim.frame_start=1;sim.frame_end=len(timeline)
    bpy.context.window.scene=sim
    cloth=add_proxy(sim,'GEO-two flexible sleeves in metres',inputs[0],faces)
    animate_inputs(cloth,staged(inputs),timeline)
    surfaces=[('body',body_inputs,bodyfaces)]
    if not no_gown:surfaces.append(('gown',gown_inputs,gownfaces))
    surfaces.extend((name,np.asarray(pts),armfaces[name]) for name,pts in arms.items())
    for name,data,polys in surfaces:
        proxy=add_proxy(sim,'GEO-sleeve contact '+name,data[0],polys)
        animate_inputs(proxy,staged(data),timeline);add_collision(proxy)
    group=cloth.vertex_groups.new(name='Shoulder seam only')
    hem=cloth.vertex_groups.new(name='Soft folded cuff edge')
    for i,w in enumerate(pins):
        if w:group.add([i],float(w),'REPLACE')
        if cuffs[i]:hem.add([i],1.0,'REPLACE')
    mod=cloth.modifiers.new('Free sleeve fabric - gravity inertia and contact','CLOTH')
    s=mod.settings;s.quality=quality;s.mass=.22/len(pins);s.air_damping=.003
    s.tension_stiffness=s.compression_stiffness=25;s.shear_stiffness=10;s.bending_stiffness=bending
    s.tension_damping=s.compression_damping=s.shear_damping=.4;s.bending_damping=.004
    s.vertex_group_mass=group.name;s.pin_stiffness=1;s.use_dynamic_mesh=False
    if label != 'walk' and not posed_rest:
        # A bent elbow must not redefine the sewn cloth lengths. This key
        # supplies undeformed cutting geometry without affecting pin targets.
        rest_key=cloth.shape_key_add(name='Unstrained sleeve cutting geometry')
        for vertex,co in zip(rest_key.data,rest):vertex.co=co
        rest_key.value=0
        s.rest_shape_key=rest_key
    s.vertex_group_bending=hem.name;s.bending_stiffness_max=.13
    s.bending_model='ANGULAR'
    c=mod.collision_settings;c.use_collision=True;c.use_self_collision=not no_self
    c.vertex_group_self_collisions=group.name
    c.vertex_group_object_collisions=group.name
    c.distance_min=.0025;c.collision_quality=8;c.friction=.15
    c.self_distance_min=.002;c.self_friction=.15
    mod.point_cache.frame_start=1;mod.point_cache.frame_end=sim.frame_end
    captured=[]
    checkpoint=[]
    capture_start=warmup+transition+(cycles-2)*period if transition else warmup
    print('SLEEVE_BEGIN',label,'vertices',len(pins),'frames',sim.frame_end,'free_cuff',bool(np.all(pins[cuffs]==0)),flush=True)
    probe_frames=[]
    for frame in range(1,(31 if probe else sim.frame_end+1)):
        sim.frame_set(frame);bpy.context.view_layer.update()
        points=evaluated_points(cloth,scale=1).astype(np.float32)
        if probe:probe_frames.append(points.copy())
        if not np.isfinite(points).all() or np.abs(points).max()>12:raise RuntimeError('Unstable sleeve cloth')
        if frame>capture_start:captured.append(points.copy())
        if frame>warmup+transition:checkpoint.append(points.copy())
        if frame>warmup+transition and (frame-warmup-transition)%period==0:
            np.savez_compressed(ANIM/(label+'_sleeve_simulation_checkpoint.npz'),
                                solved=np.asarray(checkpoint[-2*period:]),
                                simulation_frame=frame,period=period,inputs=inputs,
                                pins=pins,cuffs=cuffs,offsets=offsets)
            print('SLEEVE_CHECKPOINT',label,frame,flush=True)
        if frame%15==0:print('SLEEVE_FRAME',label,frame,sim.frame_end,flush=True)
    if probe:
        np.savez_compressed(ANIM/(output.stem+'.npz'),raw=np.asarray(probe_frames),inputs=inputs,rest=rest,
                            pins=pins,cuffs=cuffs,offsets=offsets,body_vertices=body_inputs,
                            body_faces=bodyfaces,gown_vertices=gown_inputs,gown_faces=gownfaces,
                            arm_vertices=np.asarray([v for v in arms.values()]),
                            arm_faces=np.asarray(list(armfaces.values())),cloth_triangles=triangles(faces))
        bpy.context.window.scene=scene;scene.frame_set(1);bpy.context.view_layer.update()
        for j,obj in enumerate(sleeves):
            coords=bindings[j].inverse_points(probe_frames[-1][offsets[j]:offsets[j+1]])
            bake_keys(obj,[coords],1,'PROBE ONLY - '+label)
        for m,visible in states:m.show_viewport=visible
        for fc,mute in muted:fc.mute=mute
        for obj,hide,hide_viewport in hidden:obj.hide_set(hide);obj.hide_viewport=hide_viewport
        for obj in list(sim.objects):bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.scenes.remove(sim)
        scene.frame_set(1);bpy.ops.wm.save_as_mainfile(filepath=str(output))
        print('SLEEVE_WARMUP_PROBE_SAVED',str(output),flush=True)
        return
    raw=np.asarray(captured[-period:]);physical=raw.copy()
    if transition:
        spectrum=np.fft.rfft(raw,axis=0);spectrum[9 if label=='walk' else 7:]=0
        physical=np.fft.irfft(spectrum,n=period,axis=0).astype(np.float32)
    physical[:,fixed]=inputs[:,fixed]
    clearance=[]
    for i in range(period):
        contacts=[(body_inputs[i],bodyfaces)]+[(np.asarray(pts[i]),armfaces[name]) for name,pts in arms.items()]
        physical[i],report=contact_clearance(physical[i],contacts,fixed,faces)
        clearance.append(report)
        if (i+1)%12==0:print('SLEEVE_CLEARANCE',label,i+1,period,flush=True)
    np.savez_compressed(ANIM/(label+'_sleeve_cloth.npz'),raw=raw,physical=physical,inputs=inputs,rest=rest,
                        pins=pins,cuffs=cuffs,offsets=offsets,body_vertices=body_inputs,
                        body_faces=bodyfaces,cloth_triangles=triangles(faces))
    bpy.context.window.scene=scene
    samples=[[] for _ in sleeves]
    for i in range(period):
        scene.frame_set(i+1);bpy.context.view_layer.update()
        for j,binding in enumerate(bindings):samples[j].append(binding.inverse_points(physical[i,offsets[j]:offsets[j+1]]))
    for obj,data in zip(sleeves,samples):
        name='Graduate_'+label.title()+'_Physical_'+obj.get('graduate_role')
        if transition:bake_loop(obj,data,name)
        else:bake_keys(obj,data,1,name)
    errors=[]
    for i in range(period):
        scene.frame_set(i+1);bpy.context.view_layer.update()
        actual=np.concatenate([evaluated_points(o) for o in sleeves])
        errors.append(float(np.linalg.norm(actual-physical[i],axis=1).max()))
    if max(errors)>.0002:raise RuntimeError('Baked sleeve world-space mismatch '+str(max(errors)))
    free_diff=np.linalg.norm(physical[:,cuffs]-inputs[:,cuffs],axis=2)
    report={'clip':label,'frames':period,'vertices_per_sleeve':offsets[1],
            'physics':'Blender Cloth, real-scale gravity, shoulder-only pinning, body and four arm colliders',
            'self_collision':not no_self,'gown_collision_during_solve':not no_gown,'bending_stiffness':bending,
            'gravity':[0,0,-9.81],'quality':quality,'simulation_frames':sim.frame_end,
            'total_sleeve_mass_kg':.22,'cuff_pinned_vertices':int(np.count_nonzero(pins[cuffs])),
            'max_cuff_departure_from_rigid_skin_m':float(free_diff.max()),
            'mean_cuff_departure_from_rigid_skin_m':float(free_diff.mean()),
            'baked_world_max_error_m':max(errors),'clearance':clearance,
            'remaining_inside_probes':sum(r['remaining_inside_probes'] for r in clearance),
            'max_penetration_m':max(r['max_penetration_m'] for r in clearance),
            'status':'candidate - requires visual review'}
    for m,visible in states:m.show_viewport=visible
    for fc,mute in muted:fc.mute=mute
    for obj,hide,hide_viewport in hidden:obj.hide_set(hide);obj.hide_viewport=hide_viewport
    scene['Sleeves']='Physical sleeve cloth baked; shoulder seam attached, free cuffs, gravity and arm collisions.'
    scene.frame_set(1)
    for obj in list(sim.objects):bpy.data.objects.remove(obj,do_unlink=True)
    bpy.data.scenes.remove(sim)
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    (ANIM/(label+'-sleeve-validation.json')).write_text(json.dumps(report,indent=2),encoding='utf-8')
    print('SLEEVE_SAVED',json.dumps(report),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--clip',choices=['walk','run','jump'],required=True)
    parser.add_argument('--quality',type=int,default=20);parser.add_argument('--settle-loops',type=int,default=3)
    parser.add_argument('--output',required=True)
    parser.add_argument('--probe',action='store_true');parser.add_argument('--no-self',action='store_true')
    parser.add_argument('--no-gown',action='store_true');parser.add_argument('--bending',type=float,default=.06)
    parser.add_argument('--posed-rest',action='store_true')
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    run(args.clip,args.quality,args.settle_loops,Path(args.output).resolve(),args.probe,args.no_self,args.no_gown,args.bending,args.posed_rest)
