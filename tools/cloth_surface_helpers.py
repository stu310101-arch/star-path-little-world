"""Body-mesh contacts for garment baking, in real-size simulation coordinates."""
import bpy,bmesh,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

def closed_body_topology(body):
    bm=bmesh.new();bm.from_mesh(body.data)
    bm.verts.ensure_lookup_table()
    source=bm.verts.layers.int.new('source_vertex')
    for i,v in enumerate(bm.verts):v[source]=i
    # Preserve complete actual components. Audited source opening caps are
    # small local closures, with no membrane across the torso. Cutting faces
    # by height instead leaves open wrists and breaks signed contact tests.
    bad=[f for f in bm.faces if f.calc_area()<1e-10]
    if bad:bmesh.ops.delete(bm,geom=bad,context='FACES_ONLY')
    edges=[e for e in bm.edges if e.is_boundary]
    if edges:bmesh.ops.holes_fill(bm,edges=edges,sides=0)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bmesh.ops.triangulate(bm,faces=list(bm.faces))
    bm.verts.index_update();bm.verts.ensure_lookup_table()
    ids=[v[source] for v in bm.verts]
    faces=[tuple(v.index for v in f.verts) for f in bm.faces]
    boundary=sum(e.is_boundary for e in bm.edges)
    bm.free()
    print('BODY_COLLIDER_TOPOLOGY',len(ids),len(faces),'boundary_edges',boundary,flush=True)
    return ids,faces

def body_surface_positions(body,ids,scale,margin=.004):
    ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
    mat=ev.matrix_world;norm=mat.to_3x3()
    points=[(mat@me.vertices[i].co)*scale+(norm@me.vertices[i].normal).normalized()*margin for i in ids]
    ev.to_mesh_clear();return points

def inside(tree,p):
    votes=0
    for direction in [Vector((1,.371,.529)).normalized(),Vector((.217,1,.413)).normalized(),Vector((.323,.197,1)).normalized()]:
        origin=p.copy();hits=0
        for _ in range(40):
            hit,_,_,_=tree.ray_cast(origin,direction,8)
            if hit is None:break
            hits+=1;origin=hit+direction*.00001
        votes+=hits%2
    return votes>=2

def enforce_body_clearance(points,bodypoints,bodyfaces,fixed,clothfaces,margin=.003):
    tree=BVHTree.FromPolygons(bodypoints,bodyfaces,all_triangles=True)
    original=np.asarray(points).copy();coords=[Vector(p) for p in points]
    def correction(p):
        hit,normal,_,distance=tree.find_nearest(p)
        if hit is None:return None
        signed=(p-hit).dot(normal)
        if signed<0 and inside(tree,p):return hit+normal*margin-p
        if signed>=0 and distance<margin:return normal*(margin-distance)
        return None
    # Vertex and face-centre contacts prevent both point and coarse-face cuts.
    triangles=[t for f in clothfaces for t in [(f[0],f[1],f[2]),(f[0],f[2],f[3])]]
    for iteration in range(8):
        changed=0
        for i,p in enumerate(coords):
            if fixed[i]:continue
            delta=correction(p)
            if delta is not None and delta.length>1e-7:coords[i]+=delta;changed+=1
        for ids in triangles:
            free=[i for i in ids if not fixed[i]]
            if not free:continue
            center=sum((coords[i] for i in ids),Vector())/3
            delta=correction(center)
            if delta is not None and delta.length>1e-7:
                for i in free:coords[i]+=delta*(3/len(free))
                changed+=1
        if not changed:break
    # A face-centre correction can alter a neighbour's vertex clearance.
    for i,p in enumerate(coords):
        if not fixed[i]:
            delta=correction(p)
            if delta is not None:coords[i]+=delta
    remaining_vertices=[];remaining_centres=[]
    def penetration(p):
        hit,normal,_,distance=tree.find_nearest(p)
        if hit is not None and (p-hit).dot(normal)<0 and distance>.0001 and inside(tree,p):return distance
        return 0.
    for i,p in enumerate(coords):
        if not fixed[i]:
            depth=penetration(p)
            if depth:remaining_vertices.append(depth)
    for ids in triangles:
        if not all(fixed[i] for i in ids):
            depth=penetration(sum((coords[i] for i in ids),Vector())/3)
            if depth:remaining_centres.append(depth)
    result=np.array([p[:] for p in coords],dtype=np.float32)
    shifts=np.linalg.norm(result-original,axis=1)
    return result,{'moved_vertices':int(np.count_nonzero(shifts>.00001)),'max_correction_m':float(shifts.max()),'rms_correction_m':float(np.sqrt(np.mean(shifts**2))),
                  'remaining_inside_vertices':len(remaining_vertices),'remaining_inside_centres':len(remaining_centres),'max_remaining_penetration_m':max(remaining_vertices+remaining_centres,default=0.)}

def ground_foot_controls(scene,rig,body,period):
    ids={}
    for side in ['L','R']:
        group=body.vertex_groups.get('Foot.'+side)
        ids[side]=[v.index for v in body.data.vertices if v.co.z<.4 and group and any(g.group==group.index and g.weight>.1 for g in v.groups)]
    changed=[]
    rig.hide_set(False)
    for f in range(1,period+2):
        scene.frame_set(f);bpy.context.view_layer.update()
        for side in ['L','R']:
            ev=body.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh()
            low=min((ev.matrix_world@me.vertices[i].co).z for i in ids[side]);ev.to_mesh_clear()
            if low<-.024:
                delta=-.024-low;foot=rig.pose.bones['Foot.'+side]
                foot.location.z+=delta/foot.bone.matrix_local.col[2].z
                foot.keyframe_insert('location',frame=f);bpy.context.view_layer.update()
                changed.append((f,side,delta))
    return changed

def black_regalia():
    for obj in bpy.data.objects:
        if 'Blue and gold stole' in obj.name:obj.name=obj.name.replace('Blue and gold stole','Black and gold stole')
    for light in bpy.data.lights:
        if light.name.startswith('Fill |'):light.color=(1,1,1)
        elif light.name.startswith('Key |'):light.color=(1,.97,.93)
        elif light.name.startswith('Rim |'):light.color=(1,.97,.90)
    for world in bpy.data.worlds:
        if world.use_nodes:
            for node in world.node_tree.nodes:
                if node.type=='BACKGROUND':node.inputs[0].default_value=(.72,.72,.72,1)
    colors={'Gown | midnight navy wool':('Gown | black wool','151515'),
            'Gown | fold light':('Gown | charcoal fold light','1E1E1E'),
            'Gown | fold shadow':('Gown | black fold shadow','101010'),
            'Stole | graduation blue satin':('Stole | black satin','252525'),
            'Trousers | graphite':('Trousers | graphite','202020')}
    for m in bpy.data.materials:
        match=next((pair for old,pair in colors.items() if m.name==old or m.name.startswith(old+'.')),None)
        if not match:continue
        name,color=match
        srgb=[int(color[i:i+2],16)/255 for i in (0,2,4)]
        rgb=[v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in srgb]
        m.diffuse_color=(*rgb,1)
        if m.use_nodes:
            for n in m.node_tree.nodes:
                if n.type=='BSDF_PRINCIPLED':n.inputs['Base Color'].default_value=(*rgb,1)
        m.name=name
