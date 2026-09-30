"""Read-only measurement of leg collision fit and gait-cloth intersections."""
import bpy, json, math, numpy as np
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT=Path(__file__).resolve().parents[1]
SCALE=1.75/4.8
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
rig.hide_set(False)
bones=['UpperLeg.L','LowerLeg.L','UpperLeg.R','LowerLeg.R']
old_radii={'UpperLeg':(.178,.137),'LowerLeg':(.134,.080)}
groups=[{body.vertex_groups[g.group].name:g.weight for g in v.groups} for v in body.data.vertices]
def mesh_data(obj):
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
    me.calc_loop_triangles()
    points=[ev.matrix_world@v.co for v in me.vertices]
    tris=[tuple(t.vertices) for t in me.loop_triangles]
    ev.to_mesh_clear()
    return points,tris
def triangle_label(tri):
    weights={}
    for i in tri:
        if i>=len(groups):continue
        for name,w in groups[i].items():weights[name]=weights.get(name,0)+w
    return max(weights,key=weights.get) if weights else ''

scene.frame_set(1);rig.data.pose_position='REST';bpy.context.view_layer.update()
rest,triangles=mesh_data(body)
labels=[triangle_label(t) for t in triangles]
profiles={}
for name in bones:
    bone=rig.data.bones[name]
    a=rig.matrix_world@bone.head_local;b=rig.matrix_world@bone.tail_local
    axis=(b-a).normalized()
    u=(rig.matrix_world.to_3x3()@bone.matrix_local.to_3x3()@Vector((1,0,0))).normalized()
    v=axis.cross(u).normalized()
    side=name[-1];ra,rb=old_radii[name.split('.')[0]]
    rows=[]
    for t in [0,.1,.25,.5,.75,.9,1]:
        center=a.lerp(b,t);hits=[]
        for tri,label in zip(triangles,labels):
            if label not in ['UpperLeg.'+side,'LowerLeg.'+side,'Foot.'+side]:continue
            pts=[rest[i] for i in tri];ds=[(p-center).dot(axis) for p in pts]
            for j in range(3):
                k=(j+1)%3
                if ds[j]*ds[k]<0:
                    p=pts[j].lerp(pts[k],ds[j]/(ds[j]-ds[k]));delta=p-center
                    hits.append((delta.dot(u),delta.dot(v)))
                elif abs(ds[j])<1e-7:
                    delta=pts[j]-center;hits.append((delta.dot(u),delta.dot(v)))
        if hits:
            arr=np.array(hits);radius=np.linalg.norm(arr,axis=1)
            rows.append({'t':t,'samples':len(hits),'radius_max':float(radius.max()),
                'u_minmax':[float(arr[:,0].min()),float(arr[:,0].max())],
                'v_minmax':[float(arr[:,1].min()),float(arr[:,1].max())],
                'proxy_radius':ra*(1-t)+rb*t,
                'proxy_radial_deficit_mm':float((radius.max()-(ra*(1-t)+rb*t))*SCALE*1000)})
    profiles[name]={'head':list(a),'tail':list(b),'u_axis':list(u),'v_axis':list(v),'sections':rows}
rig.data.pose_position='POSE';bpy.context.view_layer.update()

npz=np.load(ROOT/'art/Graduate/animation/walk_physical_cloth.npz')
directions=[Vector((1,.173,.041)).normalized(),Vector((-.239,1,.083)).normalized(),Vector((.521,-.773,-.132)).normalized()]
def ray_inside(bvh,p):
    votes=0
    for direction in directions:
        origin=p+direction*1e-5;count=0
        for _ in range(24):
            hit,normal,index,distance=bvh.ray_cast(origin,direction,20)
            if hit is None:break
            count+=1;origin=hit+direction*1e-5
        votes+=count%2
    return votes>=2
summary=[];worst={key:[] for key in ['raw_physics','periodic_npz','final_evaluated']}
for frame in range(1,37):
    scene.frame_set(frame);bpy.context.view_layer.update()
    pts,tris=mesh_data(body);labs=[triangle_label(t) for t in tris]
    bvh=BVHTree.FromPolygons(pts,tris,all_triangles=True)
    gownpoints,gowntris=mesh_data(gown)
    sources={'raw_physics':[Vector(p/SCALE) for p in npz['raw'][frame-1]],
        'periodic_npz':[Vector(p/SCALE) for p in npz['periodic'][frame-1]],
        'final_evaluated':gownpoints}
    row={'frame':frame}
    for label,samples in sources.items():
        records=[]
        for vi,p in enumerate(samples):
            if p.z>2.7 or p.z<-.1:continue
            near,normal,fi,distance=bvh.find_nearest(p)
            if near is None or not labs[fi].startswith(('UpperLeg.','LowerLeg.','Foot.')):continue
            signed=(p-near).dot(normal)
            if signed>=-.002 or not ray_inside(bvh,p):continue
            records.append({'frame':frame,'vertex':vi,'body_region':labs[fi],
                'depth_mm':float(distance*SCALE*1000),'position_model':list(p),
                'body_surface_model':list(near),'surface_normal':list(normal)})
        records.sort(key=lambda r:r['depth_mm'],reverse=True)
        row[label]={'count':len(records),'max_depth_mm':records[0]['depth_mm'] if records else 0,
            'by_region':{region:sum(r['body_region']==region for r in records) for region in sorted(set(r['body_region'] for r in records))}}
        worst[label].extend(records[:10])
    summary.append(row)
    if frame%9==0:print('LEG_AUDIT_FRAME',frame,flush=True)
for k in worst:worst[k]=sorted(worst[k],key=lambda r:r['depth_mm'],reverse=True)[:40]
report={'file':bpy.data.filepath,'scale_to_meters':SCALE,'body_name':body.name,
    'source_body_vertices':len(body.data.vertices),'rest_leg_profiles_model_units':profiles,
    'intersection_method':'Nearest outward body surface negative signed distance > .002 model units plus 2-of-3 oblique ray parity; lower-body vertices only. Open upper body may limit parity confidence.',
    'frames':summary,'worst':worst}
out=ROOT/'tools/audit-leg-colliders.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('LEG_AUDIT_RESULT',json.dumps({'profiles':profiles,'worst':{k:v[:3] for k,v in worst.items()},'output':str(out)}),flush=True)
