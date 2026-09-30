"""Reconstruct the previous FULL-BODY cap algorithm, never import the current helper."""
import bpy,bmesh,json,math
from pathlib import Path
from mathutils import Vector,Matrix
from mathutils.bvhtree import BVHTree
ROOT=Path(__file__).resolve().parents[1];SCALE=1.75/4.8
scene=next(s for s in bpy.data.scenes if s.name.startswith('01_WALK'))
bpy.context.window.scene=scene
rig=next(o for o in scene.objects if o.type=='ARMATURE')
body=next(o for o in scene.objects if o.get('graduate_role')=='Graduate | original face, hands and trousers')
gown=next(o for o in scene.objects if o.get('graduate_role')=='01 | Pleated bachelor gown')
rig.hide_set(False)
bm=bmesh.new();bm.from_mesh(body.data);bm.verts.ensure_lookup_table()
source=bm.verts.layers.int.new('source_vertex');cap=bm.faces.layers.int.new('audit_cap')
for i,v in enumerate(bm.verts):v[source]=i
for f in bm.faces:f[cap]=0
bad=[f for f in bm.faces if f.calc_area()<1e-10]
if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
edges=[e for e in bm.edges if e.is_boundary]
before_boundary=len(edges)
result=bmesh.ops.holes_fill(bm,edges=edges,sides=0) if edges else {'faces':[]}
caps_before=[]
for f in result['faces']:
    f[cap]=1;caps_before.append([v[source] for v in f.verts])
bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.verts.index_update();bm.verts.ensure_lookup_table()
ids=[v[source] for v in bm.verts];faces=[tuple(v.index for v in f.verts) for f in bm.faces]
cap_flags=[f[cap]==1 for f in bm.faces]
after_boundary=sum(e.is_boundary for e in bm.edges);bm.free()
for b in rig.pose.bones:b.matrix_basis=Matrix.Identity(4)
rig.animation_data.action=bpy.data.actions['Man_Idle']
if rig.animation_data.action.slots:rig.animation_data.action_slot=rig.animation_data.action.slots[0]
scene.frame_set(17);bpy.context.view_layer.update()
ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();mat=ev.matrix_world
posed=[mat@v.co for v in me.vertices]
posed_proxy=[(mat@me.vertices[i].co)*SCALE+(mat.to_3x3()@me.vertices[i].normal).normalized()*.004 for i in ids]
ev.to_mesh_clear()
rest=[body.matrix_world@v.co for v in body.data.vertices]
def bounds(points):return {'min':[min(p[j] for p in points) for j in range(3)],'max':[max(p[j] for p in points) for j in range(3)]}
def stats(sourceids,positions):
    points=[positions[i] for i in sourceids]
    edges=[(points[(i+1)%len(points)]-p).length for i,p in enumerate(points)]
    area=sum((points[i]-points[0]).cross(points[i+1]-points[0]).length/2 for i in range(1,len(points)-1))
    return {'bounds_model':bounds(points),'max_edge_model':max(edges),'area_model2':area}
tri_caps=[]
for fi,(face,is_cap) in enumerate(zip(faces,cap_flags)):
    if is_cap:
        sid=[ids[i] for i in face]
        tri_caps.append({'face':fi,'source_ids':sid,'rest':stats(sid,rest),'idle_frame17':stats(sid,posed)})
tri_caps.sort(key=lambda r:r['idle_frame17']['max_edge_model'],reverse=True)

short=[];short_world=[];unshort_world=[];lower=[]
def skin(weights):
    matrix=Matrix([[0.]*4 for _ in range(4)]);total=sum(weights.values())
    if not total:return Matrix.Identity(4)
    for name,w in weights.items():
        pb=rig.pose.bones[name];m=pb.matrix@pb.bone.matrix_local.inverted()
        for i in range(4):
            for j in range(4):matrix[i][j]+=m[i][j]*w/total
    return matrix
for vertex in gown.data.vertices:
    co=vertex.co.copy();co.z+=.52*min(1,max(0,(2.65-co.z)/(2.65-.62)))
    if co.z<2.22:w={'Hips':1.}
    else:w={gown.vertex_groups[g.group].name:g.weight for g in vertex.groups if 'Leg.' not in gown.vertex_groups[g.group].name}
    short.append(co);short_world.append((skin(w)@co)*SCALE)
    unshort_world.append((skin({'Hips':1.})@vertex.co)*SCALE)
    if co.z<2.65:lower.append(vertex.index)
tree=BVHTree.FromPolygons(posed_proxy,faces,all_triangles=True)
def inside(p):
    votes=0
    for direction in [Vector((1,.371,.529)).normalized(),Vector((.217,1,.413)).normalized(),Vector((.323,.197,1)).normalized()]:
        origin=p.copy();count=0
        for _ in range(40):
            hit,_,_,_=tree.ray_cast(origin,direction,8)
            if hit is None:break
            count+=1;origin=hit+direction*.00001
        votes+=count%2
    return votes>=2
contacts=[]
for vi in lower:
    p=short_world[vi];hit,normal,fi,distance=tree.find_nearest(p)
    if distance<.02 or inside(p):
        contacts.append({'vertex':vi,'position_m':list(p),'nearest_face':fi,'nearest_is_added_cap':cap_flags[fi],
            'distance_m':distance,'signed_m':(p-hit).dot(normal),'inside':inside(p),'body_source_ids':[ids[i] for i in faces[fi]]})
report={'source_file':bpy.data.filepath,'algorithm':'OLD full-body holes_fill without component filtering',
    'deleted_degenerate_faces':len(bad),'boundary_before':before_boundary,'boundary_after':after_boundary,
    'cap_polygons':caps_before,'cap_polygon_count':len(caps_before),'cap_triangle_count':len(tri_caps),
    'cap_triangles':tri_caps,'shortened_rest_bounds_model':bounds(short),
    'shortened_rest_hem_z_m':[min(p.z for p in short[:48])*SCALE,max(p.z for p in short[:48])*SCALE],
    'shortened_idle_hem_z_m':[min(p.z for p in short_world[:48]),max(p.z for p in short_world[:48])],
    'unshortened_idle_hem_z_m':[min(p.z for p in unshort_world[:48]),max(p.z for p in unshort_world[:48])],
    'idle_initial_lower_cloth_contacts':contacts}
out=ROOT/'tools/audit-old-body-caps.json';out.write_text(json.dumps(report,indent=2),encoding='utf-8')
print('OLD_CAP_AUDIT_RESULT',json.dumps({k:v for k,v in report.items() if k not in ('cap_triangles','cap_polygons')}) ,flush=True)
print('LARGEST_CAPS',json.dumps(tri_caps[:8]),flush=True)
