"""Original, metre-scale tulips for the counseling room's Blender generator.

Integration: build_tulip_arrangement(globals(), "SideboardTulips", (x, y, z)).
The API uses the room generator's Y-up frame/mesh/tube_path/material helpers.
Geometry and simple Principled materials survive GLB export without baking.
Run in background Blender with -- --preview-dir PATH for an isolated studio.
"""
from __future__ import annotations

import math
from pathlib import Path
import random


def _smooth(obj):
    for face in obj.data.polygons:
        face.use_smooth = True
    return obj


def _strip_mesh(api, name, front, rows, cols, material, thickness, normal_at):
    """Closed thin surface with explicit back and perimeter, no loose edges."""
    back = [tuple(p[k] - thickness * normal_at(i)[k] for k in range(3))
            for i, p in enumerate(front)]
    vertices = front + back
    n = len(front)
    faces = []
    for row in range(rows - 1):
        for col in range(cols - 1):
            a = row * cols + col
            faces.extend([(a, a + 1, a + cols + 1, a + cols),
                          (n + a + cols, n + a + cols + 1, n + a + 1, n + a)])
    border = (list(range(cols)) + [r * cols + cols - 1 for r in range(1, rows)]
              + list(range((rows - 1) * cols + cols - 2, (rows - 1) * cols - 1, -1))
              + [r * cols for r in range(rows - 2, 0, -1)])
    for a, b in zip(border, border[1:] + border[:1]):
        faces.append((a, n + a, n + b, b))
    obj = _smooth(api['mesh'](name, vertices, faces, material))
    # Petals/leaves use intentional shared longitudinal UV strips. No planar
    # projection seam crosses their visible face; no texture/vertex-colour trick.
    uv = obj.data.uv_layers.active
    for face in obj.data.polygons:
        for loop in face.loop_indices:
            index = obj.data.loops[loop].vertex_index % n
            uv.data[loop].uv = ((index % cols) / (cols - 1), (index // cols) / (rows - 1))
    return obj


def _bezier(points, t):
    a, b, c, d = points
    return tuple((1-t)**3*a[k] + 3*(1-t)**2*t*b[k] + 3*(1-t)*t*t*c[k] + t**3*d[k]
                 for k in range(3))


def _vase(api, name, scale):
    # Outside, rolled lip, actual inside wall, recessed interior floor. Both
    # underside and interior centre are single vertices, not zero-area rings.
    profile = [(0,.004),(.034,.004),(.038,.007),(.039,.015),(.041,.021),
               (.050,.036),(.058,.069),(.060,.096),(.056,.125),(.047,.151),
               (.035,.174),(.034,.190),(.037,.194),(.0375,.198),(.035,.201),
               (.030,.201),(.0285,.197),(.029,.190),(.030,.175),(.042,.149),
               (.050,.122),(.054,.096),(.052,.069),(.045,.040),(.033,.026),(0,.026)]
    sides = 36
    points, rings = [], []
    for radius, y in profile:
        ring = []
        for j in range(1 if radius == 0 else sides):
            a = j * math.tau / sides
            ring.append(len(points))
            points.append((radius * math.cos(a)*scale, y*scale, radius*math.sin(a)*scale))
        rings.append(ring)
    faces = []
    for aa, bb in zip(rings, rings[1:]):
        for j in range(sides):
            if len(aa) == 1:
                faces.append((aa[0], bb[j], bb[(j+1)%sides]))
            elif len(bb) == 1:
                faces.append((aa[j], bb[0], aa[(j+1)%sides]))
            else:
                faces.append((aa[j], bb[j], bb[(j+1)%sides], aa[(j+1)%sides]))
    obj = _smooth(api['mesh'](name+'_HollowCeramic', points, faces, 'tulip_vase_glaze'))
    obj.data.materials.append(api['MATS']['tulip_vase_foot'])
    for face in obj.data.polygons:
        if max(obj.data.vertices[i].co.z for i in face.vertices) < .021*scale:
            face.material_index = 1
    obj['construction'] = 'Closed ceramic volume; 5 mm lip, deep cavity, unglazed foot.'
    # Cylindrical seam at the back; overlap between outside and interior is
    # intentional because this vessel uses uniform ceramic master materials.
    uv = obj.data.uv_layers.active
    for face in obj.data.polygons:
        coords = []
        for loop in face.loop_indices:
            p = obj.data.vertices[obj.data.loops[loop].vertex_index].co
            coords.append(((math.atan2(-p.y,p.x)/math.tau)%1, p.z/(.201*scale)))
        if max(c[0] for c in coords)-min(c[0] for c in coords)>.5:
            coords = [(u+1 if u<.5 else u,v) for u,v in coords]
        for loop, coord in zip(face.loop_indices,coords): uv.data[loop].uv=coord
    return obj


def build_tulip_arrangement(api: dict, name: str, p: tuple, scale: float = 1.0):
    """Build one ~48 cm arrangement: three six-petal blooms and folded leaves.

    Returns source objects. Call in the destination collection/frame. Helpers
    accept coordinates in Godot Y-up metres, exactly like the room generator.
    """
    from mathutils import Vector

    if not .25 <= scale <= 2:
        raise ValueError('Tulip arrangement scale must stay between .25 and 2')
    palettes = {
        'tulip_coral': ((.66,.205,.155), .47),
        'tulip_coral_inner': ((.79,.305,.235), .45),
        'tulip_ivory': ((.88,.805,.59), .48),
        'tulip_ivory_inner': ((.96,.885,.70), .45),
        'tulip_leaf': ((.105,.235,.105), .57),
        'tulip_midrib': ((.19,.32,.125), .59),
        'tulip_vase_glaze': ((.60,.68,.60), .27),
        'tulip_vase_foot': ((.43,.39,.30), .84),
    }
    for key,(color,rough) in palettes.items():
        if key not in api['MATS']:
            api['material'](key,color,rough)
    objects=[]
    rng=random.Random(61024)
    mul=lambda q:tuple(v*scale for v in q)
    # Separated heights, splayed stems and different opening/tilt. Broadest
    # head is ~7 cm; the ivory one is more closed, rather than another copy.
    flowers=[((-0.065,.386,.015),(-.30,.95,.05),.056,.030,.008,'coral'),
             ((.028,.418,-.022),(.16,.975,-.14),.058,.027,.002,'ivory'),
             ((.078,.348,.025),(.39,.90,.18),.053,.029,.011,'coral')]
    with api['frame'](p):
        objects.append(_vase(api,name,scale))
        for bloom,(center,axis,length,radius,opening,color) in enumerate(flowers):
            stem=[(center[0]*.10,.07,center[2]*.10),
                  (-center[0]*.24,.22,-.008),
                  (center[0]*.62,center[1]-.075,center[2]*1.1),center]
            objects.append(api['tube_path'](name+f'_Stem_{bloom}',
                [mul(_bezier(stem,j/15)) for j in range(16)],.00225*scale,'tulip_leaf',8))
            up=Vector(axis).normalized()
            right=Vector((1,0,0));right=(right-up*right.dot(up)).normalized()
            forward=right.cross(up).normalized()
            origin=Vector(center)
            for petal in range(6):
                inner=petal>=3
                angle=(petal%3)*math.tau/3 + (math.pi/3 if inner else 0) + bloom*.27
                angle+=rng.uniform(-.006,.006)
                plen=length*(.965 if inner else 1)*rng.uniform(.965,1.035)
                rad=radius*(.82 if inner else 1)
                # Each three-petal whorl stays just under 120 degrees wide.
                # The second, inset whorl covers its seams: nearby surfaces
                # overlap in projection without coplanar/intersection patches.
                halfwidth=1.035
                points=[];normals=[];rows,cols=9,9
                for row in range(rows):
                    t=row/(rows-1)
                    width=math.sin(math.pi*(.035+.87*t))**.6
                    for col in range(cols):
                        u=col/(cols-1)*2-1
                        a=angle+u*halfwidth*width
                        r=.0035+rad*math.sin(math.pi*t*.78)**.83
                        r+=opening*t**5*(.9 if inner else 1)
                        # Soft longitudinal cup, asymmetric edge and slight
                        # outward tip curl, all geometry, not a flat spoon.
                        r+=.0013*math.sin(math.pi*t)*math.cos(u*math.pi*1.5)
                        r+=.0016*t**7*(1-u*u)
                        y=plen*(t-.12*t**7*u*u)
                        y+=.0003*math.sin(u*3.7+petal)*t**4
                        normal=(right*math.cos(a)+forward*math.sin(a)).normalized()
                        pos=origin+normal*r+up*y
                        points.append(tuple(pos*scale));normals.append(tuple(normal))
                mat='tulip_'+color+('_inner' if inner else '')
                obj=_strip_mesh(api,name+f'_Bloom_{bloom}_Petal_{petal}',points,rows,cols,
                                mat,.00048*scale,lambda i: normals[i])
                obj['surface']='Cupped overlapping petal with tapered base, curled rim and thickness.'
                objects.append(obj)
            # A restrained green receptacle closes the underside of each head.
            objects.append(api['tube_path'](name+f'_Receptacle_{bloom}',
                [mul(tuple(origin-up*.009)),mul(tuple(origin+up*.004))],.0047*scale,'tulip_leaf',8))
        leaves=[((-.010,.185,.008),(-.132,.322,.013),.026,-.28),
                ((.007,.205,.014),(.146,.288,.074),.025,.32),
                ((.001,.217,-.009),(-.052,.385,-.072),.020,-.12),
                ((.012,.185,-.012),(.100,.366,-.053),.021,.16)]
        for leaf,(base,tip,width,twist) in enumerate(leaves):
            start,end=Vector(base),Vector(tip)
            horizontal=Vector((end.x-start.x,0,end.z-start.z)).normalized()
            cross=Vector((-horizontal.z,0,horizontal.x))
            points=[]; normals=[];mid=[];rows,cols=13,5
            for row in range(rows):
                t=row/(rows-1)
                c=start.lerp(end,t)
                c.y+=.035*math.sin(math.pi*t)-.015*t**5
                # Narrow sheathing base and fine tip; centre ridge with drooped
                # margins gives the characteristic folded tulip ribbon leaf.
                w=max(.00065,width*math.sin(math.pi*t)**.85)
                mid.append(tuple((c+Vector((0,.0008,0)))*scale))
                for col in range(cols):
                    u=col/(cols-1)*2-1
                    pos=c+cross*(w*u)
                    pos.y-=w*.42*abs(u)
                    pos.y+=twist*w*u*t
                    points.append(tuple(pos*scale));normals.append((0,1,0))
            objects.append(_strip_mesh(api,name+f'_FoldedLeaf_{leaf}',points,rows,cols,
                                      'tulip_leaf',.00055*scale,lambda i: normals[i]))
            objects.append(api['tube_path'](name+f'_LeafMidrib_{leaf}',mid,.00052*scale,'tulip_midrib',6))
    for obj in objects: obj['asset_family']='Original counseling tulips v1'
    return objects


def _preview(directory):
    """Isolated editable studio evidence; does not import/reset the room file."""
    import bpy
    import bmesh
    import json
    from contextlib import contextmanager
    from mathutils import Matrix,Vector
    directory=Path(directory).resolve();directory.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    scene=bpy.context.scene;scene.unit_settings.system='METRIC'
    collection=bpy.data.collections.new('COL_OriginalTulips');scene.collection.children.link(collection)
    state={'matrix':Matrix.Identity(4)};mats={}
    gv=lambda p:Vector((p[0],-p[2],p[1]))
    @contextmanager
    def frame(p):
        old=state['matrix'];state['matrix']=old@Matrix.Translation(gv(p))
        yield
        state['matrix']=old
    def material(key,color,rough):
        m=bpy.data.materials.new('MAT_Counseling_'+key);m.diffuse_color=(*color,1);m.use_nodes=True
        b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough
        mats[key]=m
    def mesh(name,points,faces,mat):
        data=bpy.data.meshes.new('MSH_'+name);data.from_pydata([gv(p) for p in points],[],faces);data.update()
        bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
        data.uv_layers.new(name='UVMap')
        ob=bpy.data.objects.new('SM_'+name,data);collection.objects.link(ob);data.materials.append(mats[mat]);ob.matrix_world=state['matrix'].copy()
        return ob
    def tube_path(name,points,radius,mat,sides):
        vertices=[];pts=[Vector(p) for p in points]
        for i,p in enumerate(pts):
            tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
            ref=Vector((0,1,0)) if abs(tangent.y)<.95 else Vector((0,0,1))
            u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
            vertices.extend(tuple(p+radius*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides))) for j in range(sides))
        faces=[tuple(range(sides-1,-1,-1)),tuple(range((len(pts)-1)*sides,len(pts)*sides))]
        faces.extend((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j) for i in range(len(pts)-1) for j in range(sides))
        return _smooth(mesh(name,vertices,faces,mat))
    objects=build_tulip_arrangement(dict(frame=frame,mesh=mesh,tube_path=tube_path,material=material,MATS=mats),'HeroTulips',(0,0,0))
    triangles=0;bad=0
    for ob in objects:
        ob.data.calc_loop_triangles();triangles+=len(ob.data.loop_triangles)
        bm=bmesh.new();bm.from_mesh(ob.data);bad+=sum(not e.is_manifold for e in bm.edges);bm.free()
    coords=[ob.matrix_world@v.co for ob in objects for v in ob.data.vertices]
    dimensions=[max(p[i] for p in coords)-min(p[i] for p in coords) for i in range(3)]
    report={'asset':'Original three-stem tulips','triangles':triangles,'source_meshes':len(objects),'materials':len(mats),'nonmanifold_edges':bad,'dimensions_xyz_m':dimensions,'blooms':3,'petals_per_bloom':6,'vase_height_m':.201,'uv_meshes':sum(bool(o.data.uv_layers) for o in objects),'method':'Original curved surface modelling; no downloaded or AI imagery.','notes':'Y-up helper, studio dimensions are Blender Z-up. Shared longitudinal petal/leaf UVs; uniform PBR materials. Main room generator keeps all source meshes editable.'}
    assert bad==0 and 5000<=triangles<=10000,report
    (directory/'geometry-validation.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
    bpy.ops.object.select_all(action='DESELECT')
    for ob in objects:ob.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(directory/'original-tulips.glb'),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_vertex_color='NONE')
    # Neutral studio tabletop/background, for judging the asset itself.
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,0))
    ground=bpy.context.object;ground.name='STUDIO_Ground'
    material('studio',(.30,.32,.30),.72);ground.data.materials.append(mats['studio'])
    world=bpy.data.worlds.new('NeutralStudio');scene.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs[0].default_value=(.38,.40,.43,1)
    world.node_tree.nodes['Background'].inputs[1].default_value=.35
    def light(name,p,energy,size):
        data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.shape='DISK';data.size=size
        ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=p;ob.rotation_euler=(Vector((0,0,.25))-ob.location).to_track_quat('-Z','Y').to_euler()
    light('STUDIO_Key',(-.65,-.8,1.0),40,.75)
    light('STUDIO_Fill',(.8,-.1,.7),12,.60)
    light('STUDIO_Rim',(.2,.6,.9),28,.55)
    data=bpy.data.cameras.new('CAM_TulipCraft');cam=bpy.data.objects.new('CAM_TulipCraft',data);scene.collection.objects.link(cam);scene.camera=cam
    data.type='ORTHO';data.ortho_scale=.57
    cam.location=(.57,-.95,.64);cam.rotation_euler=(Vector((0,0,.245))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=48;scene.cycles.use_denoising=True
    scene.render.resolution_x=1200;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
    scene.view_settings.view_transform='AgX'
    bpy.ops.wm.save_as_mainfile(filepath=str(directory/'original-tulips.blend'))
    scene.render.filepath=str(directory/'studio-arrangement.png');bpy.ops.render.render(write_still=True)
    data.ortho_scale=.265;cam.location=(.39,-.62,.66);cam.rotation_euler=(Vector((.012,0,.381))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.resolution_x=1400;scene.render.resolution_y=1100
    scene.render.filepath=str(directory/'studio-petal-closeup.png');bpy.ops.render.render(write_still=True)
    print('TULIP_VALIDATION '+json.dumps(report),flush=True)


if __name__=='__main__':
    import argparse,sys
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preview-dir',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:])
    _preview(args.preview_dir)
