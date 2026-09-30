"""Continuous tailored sleeves with stable sections and baked inertial drape.

Run from the Tailored checkpoint. Keeps topology, weights, materials and every
non-sleeve object. This is art-directed secondary motion, not a new Cloth solve.
"""
import bpy,sys,json
import numpy as np
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from simulate_portal_cloth import SCALE,SkinBinding,evaluated_points,bake_keys
from simulate_sleeve_cloth import bake_loop
from validate_sleeve_garment_contact import visible_surfaces

def unit(x):
    return x/max(np.linalg.norm(x),1e-10)

def transport(tangents, hint):
    frames=[];u=unit(hint-tangents[0]*np.dot(hint,tangents[0]))
    old=tangents[0]
    for t in tangents:
        v=np.cross(old,t);c=np.clip(np.dot(old,t),-1,1)
        if c>-.999:
            u=u+np.cross(v,u)+np.cross(v,np.cross(v,u))/(1+c)
        u=unit(u-t*np.dot(u,t));frames.append((u,np.cross(t,u)));old=t
    return np.asarray(frames)

def smooth_path(s,e,w,distances,rest_upper,rest_lower):
    a=unit(e-s);b=unit(w-e)
    la=np.linalg.norm(e-s);lb=np.linalg.norm(w-e)
    rounding=min(.18,la*.68,lb*.68)
    angle=np.arccos(np.clip(np.dot(a,b),-.999999,1))
    normal=unit(b-a*np.dot(a,b)) if angle>1e-4 else np.zeros(3)
    radius=rounding/max(np.tan(angle/2),1e-6)
    points=[];tangents=[]
    for d in distances:
        # Distances are based on the unchanged anatomical rest bones.
        q=d*la/rest_upper if d<=rest_upper else la+(d-rest_upper)*lb/rest_lower
        if q<la-rounding:
            p=s+a*q;t=a
        elif q>la+rounding:
            p=e+b*(q-la);t=b
        else:
            f=(q-(la-rounding))/(2*rounding)
            if angle<1e-4:
                p=s+a*q;t=a
            else:
                origin=e-a*rounding+normal*radius
                p=origin-normal*radius*np.cos(angle*f)+a*radius*np.sin(angle*f)
                t=a*np.cos(angle*f)+normal*np.sin(angle*f)
        points.append(p);tangents.append(t)
    return np.asarray(points),np.asarray(tangents)

def spring_offsets(targets, fps, loop):
    # Critically damped, substepped response. Repeat loop warm-up for closure.
    dt=1/fps/8;omega=2*np.pi*4.5
    x=targets[0].copy();velocity=np.zeros_like(x);result=[]
    for cycle in range(10 if loop else 1):
        result=[]
        for f,target in enumerate(targets):
            previous=targets[f-1] if loop or f else target
            for step in range(8):
                goal=previous+(target-previous)*(step+1)/8
                velocity+=(omega*omega*(goal-x)-2*omega*velocity)*dt
                x+=velocity*dt
            result.append(x.copy())
    return np.asarray(result)

reports=[]
for label,prefix in [('run','02_RUN'),('walk','01_WALK'),('jump','03_JUMP')]:
    scene=next(s for s in bpy.data.scenes if s.name.startswith(prefix))
    bpy.context.window.scene=scene;rig=next(o for o in scene.objects if o.type=='ARMATURE')
    sleeves=[next(o for o in scene.objects if o.get('graduate_role')=='02 | Bell sleeve '+side) for side in ('L','R')]
    arm_skin=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | restored arm skin')
    body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
    period=scene.frame_end;fps=scene.render.fps/scene.render.fps_base
    cache=[]
    with visible_surfaces(scene,[*sleeves,arm_skin,body],'simulation'):
        for o,side in zip(sleeves,('L','R')):
            rest=np.asarray([v.co[:] for v in o.data.vertices]);sections=rest[:544].reshape(17,32,3)
            rest_centers=sections.mean(axis=1)
            upper=rig.data.bones['UpperArm.'+side];lower=rig.data.bones['LowerArm.'+side]
            s0=np.asarray(upper.head_local);e0=np.asarray(upper.tail_local);w0=np.asarray(lower.tail_local)
            sign=1 if side=='L' else -1
            distances=(rest_centers[:,0]-s0[0])*sign*SCALE
            lu=np.linalg.norm(e0-s0)*SCALE;ll=np.linalg.norm(w0-e0)*SCALE
            # Preserve the narrowed cutting pattern, with small arm clearance.
            radii=np.stack([np.ptp(sections[:,:,1],axis=1),np.ptp(sections[:,:,2],axis=1)],axis=1)*SCALE/2
            theta=np.arctan2(sections[0,:,2]-rest_centers[0,2],sections[0,:,1]-rest_centers[0,1])
            if side=='R':theta=-theta
            all_centers=[];all_tangents=[];all_frames=[];all_skin=[];inverses=[]
            binding=SkinBinding(o,rig)
            for frame in range(1,period+1):
                scene.frame_set(frame);bpy.context.view_layer.update()
                world=rig.matrix_world
                ub=rig.pose.bones['UpperArm.'+side];lb=rig.pose.bones['LowerArm.'+side]
                s=np.asarray(world@ub.head)*SCALE;e=np.asarray(world@ub.tail)*SCALE;w=np.asarray(world@lb.tail)*SCALE
                centers,tangents=smooth_path(s,e,w,distances,lu,ll)
                rotation=world.to_3x3()@ub.matrix.to_3x3()@upper.matrix_local.to_3x3().inverted()
                frames=transport(tangents,np.asarray(rotation@Vector((0,1,0))))
                all_centers.append(centers);all_tangents.append(tangents);all_frames.append(frames)
                skin_vertices=evaluated_points(arm_skin)
                # Broad upper-arm triangles need interior samples, since their
                # vertices alone miss skin close to the elbow-side sleeve wall.
                skin_samples=[skin_vertices]
                for poly in arm_skin.data.polygons:
                    ids=list(poly.vertices)
                    for k in range(1,len(ids)-1):
                        a0,b0,c0=skin_vertices[[ids[0],ids[k],ids[k+1]]]
                        skin_samples.append(np.asarray([a0+(b0-a0)*i/6+(c0-a0)*j/6
                            for i in range(7) for j in range(7-i)]))
                all_skin.append(np.concatenate(skin_samples))
                inverses.append(np.asarray([m for m in binding.world_matrices(True)]))
            centers=np.asarray(all_centers);tangents=np.asarray(all_tangents);frames=np.asarray(all_frames)
            # Only the secondary offset is spring-filtered; skeletal travel and
            # section radii are never averaged, avoiding collapsed elbows.
            if label!='jump':
                acceleration=(np.roll(centers,-1,axis=0)-2*centers+np.roll(centers,1,axis=0))*fps*fps
            else:
                acceleration=np.gradient(np.gradient(centers,axis=0),axis=0)*fps*fps
            free=np.clip((distances-.035)/max(distances[-1]-.035,.1),0,1)**1.5
            gravity=np.broadcast_to(np.array([0.,0.,-.015]),centers.shape).copy()
            desired=gravity-.00035*acceleration
            desired-=np.sum(desired*tangents,axis=-1)[...,None]*tangents
            desired*=free[None,:,None]
            length=np.linalg.norm(desired,axis=-1)
            desired*=np.minimum(1,.023/np.maximum(length,1e-10))[...,None]
            offsets=spring_offsets(desired,fps,label!='jump')
            # Maintain orientation-relative drape while avoiding longitudinal slip.
            offsets-=np.sum(offsets*tangents,axis=-1)[...,None]*tangents
            final_centers=centers+offsets
            # A free cuff can tilt relative to the forearm. Spread that tilt
            # over the distal sleeve, rather than hinging one rigid rim.
            tilt=offsets/.023*.18*free[None,:,None]**2
            relaxed_tangents=tangents+tilt
            relaxed_tangents/=np.linalg.norm(relaxed_tangents,axis=-1)[...,None]
            frames=np.asarray([transport(relaxed_tangents[f],frames[f,0,0]) for f in range(period)])
            tangents=relaxed_tangents
            # Size from the real restored skin, not collision capsules. One
            # stable envelope across each clip avoids frame-wise radius popping.
            sizes=np.tile(radii[None,:,:],(period,1,1))
            for f in range(period):
                skin=all_skin[f]
                side_skin=skin[(skin[:,0]-np.asarray(rig.matrix_world.translation)[0]*SCALE)*sign>0]
                delta=side_skin[:,None,:]-final_centers[f][None,:,:]
                along=np.sum(delta*tangents[f][None,:,:],axis=-1)
                for r in range(17):
                    near=abs(along[:,r])<.023
                    if not near.any():continue
                    dr=delta[near,r]
                    xy=dr@frames[f,r].T
                    # Ignore the opposite side or upper torso skin far away.
                    xy=xy[np.linalg.norm(xy,axis=1)<.18]
                    if not len(xy):continue
                    extent=np.sqrt(np.sum((xy/radii[r])**2,axis=1)).max()
                    sizes[f,r]*=max(1.,extent+.007/min(radii[r]))
            # Fit continuously, including the narrow shoulder seam. Preserve
            # the larger forearm cuff proportion of the tailored pattern.
            stable=np.max(sizes,axis=0)
            for _ in range(3):
                for r in range(1,16):stable[r]=np.maximum(stable[r],.25*stable[r-1]+.5*stable[r]+.25*stable[r+1])
            poses=[];worlds=[]
            for f in range(period):
                points=[]
                for r in range(17):
                    # Broad, load-driven flex changes the cross-section without
                    # stretching its circumference. This preserves a soft cuff
                    # rather than a rigid ellipse following the forearm.
                    response=frames[f,r]@offsets[f,r]/.023
                    flex=free[r]**1.5
                    fold=(1+.012*np.cos(theta*4+distances[r]*4)
                          +flex*.095*(response[0]*np.cos(2*theta)+response[1]*np.sin(2*theta))
                          +flex*.030*(response[1]*np.cos(3*theta)-response[0]*np.sin(3*theta)))
                    plain=np.stack((np.cos(theta)*stable[r,0],np.sin(theta)*stable[r,1]),axis=1)
                    xy=plain*fold[:,None]
                    perimeter=lambda p:np.linalg.norm(np.roll(p,-1,axis=0)-p,axis=1).sum()
                    xy*=perimeter(plain)/perimeter(xy)
                    radial=xy@frames[f,r]
                    # Keep the inside of a bent sleeve on its own side of the
                    # arm's bisector; this prevents upper/lower sleeve walls
                    # crossing when the elbow folds tightly during a run.
                    for _ in range(2):
                        for other in range(17):
                            if abs(other-r)<3:continue
                            separation=final_centers[f,other]-final_centers[f,r]
                            gap=np.linalg.norm(separation)
                            normal=separation/max(gap,1e-9)
                            excess=np.maximum(radial@normal-gap*.46,0.)
                            radial-=excess[:,None]*normal
                    points.extend(final_centers[f,r]+radial)
                points.append(final_centers[f,0])
                points=np.asarray(points);worlds.append(points)
                homogeneous=np.concatenate((points/SCALE,np.ones((545,1))),axis=1)
                poses.append(np.einsum('nij,nj->ni',inverses[f],homogeneous)[:,:3])
            if label=='jump':bake_keys(o,poses,1,'Graduate_Jump_ContinuousSleeve_'+side)
            else:bake_loop(o,poses,'Graduate_'+label.title()+'_ContinuousSleeve_'+side)
            for p in o.data.polygons:p.use_smooth=True
            o['Sleeve motion']='Continuous sections; gravity and critically damped inertial drape, baked for Godot.'
            o['Sleeve tailoring']='Whole sleeve narrowed, fitted around actual arm skin; stable section circumference.'
            cache.append(np.asarray(worlds))
            reports.append({'clip':label,'side':side,'max_secondary_m':float(np.max(np.linalg.norm(offsets,axis=-1))),
                            'radii_m':stable.tolist(),'input_radii_m':radii.tolist()})
            print('CONTINUOUS_SLEEVE',label,side,json.dumps(reports[-1]),flush=True)
    np.savez_compressed(ROOT/'art/Graduate/animation'/f'{label}_sleeve_continuous.npz',physical=np.concatenate(cache,axis=1))
scene=next(s for s in bpy.data.scenes if s.name.startswith('02_RUN'))
bpy.context.window.scene=scene;scene.frame_set(1)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/Graduate/Male_Graduate_Sleeves_Continuous.blend'))
(ROOT/'tools/sleeve-continuous-report.json').write_text(json.dumps(reports,indent=2),encoding='utf-8')
print('CONTINUOUS_SLEEVES_SAVED',flush=True)
