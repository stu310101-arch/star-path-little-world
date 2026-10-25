"""Author the StarPath warm-window counseling studio. Run with Blender --background --factory-startup.

All construction coordinates are Godot Y-up metres. Editable bevels remain in
the blend; evaluated export copies are joined by spatial zone to bound draw calls.
"""
from __future__ import annotations
import bpy
import bmesh
import json
import math
import os
import random
import sys
from contextlib import contextmanager
from pathlib import Path
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from optimize_indoor_geometry import optimize_glb
ART = ROOT / 'art/CounselingRoom'
OUT = ROOT / 'game/assets/counseling_room'
TEX = OUT / 'textures'
ART.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
SCENE = bpy.context.scene
SCENE.unit_settings.system = 'METRIC'
SCENE.render.engine = 'CYCLES'
SCENE.cycles.samples = 32
SCENE.cycles.use_denoising = True
SCENE.render.resolution_x = 1600
SCENE.render.resolution_y = 1000
SCENE.render.resolution_percentage = 100
SCENE.view_settings.view_transform = 'AgX'
SCENE.world.color = (.22, .26, .30)
MATS, COLS, COLLIDERS = {}, {}, []
FRAME = Matrix.Identity(4)
COL = None
RNG = random.Random(20261024)
SOFA_POSITION = (-4.68, 0, .35)
SIDE_TABLE_POSITION = (-4.18, 0, 2.45)
DESK_CHAIR_Z = -1.76
DESK_APPROACH_Z = -.88

def gv(p): return Vector((p[0], -p[2], p[1]))

def material(key, color, rough=.5, metal=0, texture=None, emission=0):
    mat = bpy.data.materials.new('MAT_Counseling_' + key)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    bsdf = next(n for n in nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color, 1)
        bsdf.inputs['Emission Strength'].default_value = emission
    if texture:
        fabric = texture in ['sage', 'apricot', 'linen']
        for suffix, plug in [('base', 'Base Color'), ('rough', 'Roughness'), ('normal', 'Normal')]:
            stem = 'fabric' if fabric and suffix != 'base' else texture
            im = bpy.data.images.load(str(TEX / f'{stem}_{suffix}.png'), check_existing=True)
            im.colorspace_settings.name = 'sRGB' if suffix == 'base' else 'Non-Color'
            node = nodes.new('ShaderNodeTexImage'); node.image = im
            if suffix == 'normal':
                normal = nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value = .28 if fabric else .22
                links.new(node.outputs['Color'], normal.inputs['Color']); links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
            else:
                links.new(node.outputs['Color'], bsdf.inputs[plug])
    MATS[key] = mat

def collection(name):
    global COL
    COL = bpy.data.collections.new('COL_Counseling_' + name)
    SCENE.collection.children.link(COL)
    COLS[name] = COL

@contextmanager
def frame(p=(0, 0, 0), angle=0):
    global FRAME
    old = FRAME
    FRAME = FRAME @ Matrix.Translation(gv(p)) @ Matrix.Rotation(angle, 4, 'Z')
    yield
    FRAME = old

def mesh(name, points, faces, mat):
    if mat == 'oak' and name != 'StudioOakFloor': mat = 'joinery'
    data = bpy.data.meshes.new('MSH_' + name)
    data.from_pydata([gv(p) for p in points], [], faces)
    data.update()
    bm = bmesh.new(); bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data); bm.free()
    uv = data.uv_layers.new(name='UVMap')
    for poly in data.polygons:
        major = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != major]
        if mat in ('oak','joinery'):
            spans = [max(data.vertices[data.loops[j].vertex_index].co[i] for j in poly.loop_indices) - min(data.vertices[data.loops[j].vertex_index].co[i] for j in poly.loop_indices) for i in axes]
            if spans[0] > spans[1]: axes.reverse()
        scale = .65 if mat in ('sage', 'apricot', 'linen') else 1.7
        for j in poly.loop_indices:
            co = data.vertices[data.loops[j].vertex_index].co
            uv.data[j].uv = (co[axes[0]] / scale, co[axes[1]] / scale)
    obj = bpy.data.objects.new('SM_' + name, data)
    COL.objects.link(obj); data.materials.append(MATS[mat])
    obj.matrix_world = FRAME.copy()
    return obj

def bevel(obj, width=.012, segments=2):
    mod = obj.modifiers.new('Soft manufactured edges', 'BEVEL')
    mod.width = width; mod.segments = segments
    mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    return obj

def box(name, p, size, mat='oak', edge=.012):
    x, y, z = [v / 2 for v in size]
    ob = mesh(name, [(-x,-y,-z),(x,-y,-z),(x,-y,z),(-x,-y,z),(-x,y,-z),(x,y,-z),(x,y,z),(-x,y,z)], [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    if edge: bevel(ob, min(edge, min(size) * .38))
    return ob

def rounded(name, p, size, radius, mat='oak', edge=.006):
    """Closed rounded rectangle prism, rounded in plan without inflated thickness."""
    w, h, d = size
    points = []
    for yy in [-h / 2, h / 2]:
        for cx, cz, start in [(w/2-radius,d/2-radius,0),(w/2-radius,-d/2+radius,90),(-w/2+radius,-d/2+radius,180),(-w/2+radius,d/2-radius,270)]:
            for j in range(9):
                a = math.radians(start + j * 90 / 8)
                points.append((cx + math.sin(a)*radius, yy, cz + math.cos(a)*radius))
    n = len(points)//2
    ob = mesh(name, points, [tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    if edge: bevel(ob, min(edge, h*.25), 2)
    return ob

def cylinder(name, p, radius, height, mat, top=None, segments=24):
    top = radius if top is None else top
    points = [(math.cos(j*math.tau/segments)*r,y,math.sin(j*math.tau/segments)*r) for y,r in [(-height/2,radius),(height/2,top)] for j in range(segments)]
    ob = mesh(name, points, [tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]+[(j,(j+1)%segments,(j+1)%segments+segments,j+segments) for j in range(segments)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    for poly in ob.data.polygons:
        poly.use_smooth = len(poly.vertices)==4
    return ob

def rod(name, a, b, radius, mat='brass', segments=12):
    av, bv = gv(a), gv(b)
    ob = cylinder(name, (0,0,0), radius, (bv-av).length, mat, segments=segments)
    ob.matrix_world = FRAME @ Matrix.Translation((av+bv)/2) @ (bv-av).to_track_quat('Z','Y').to_matrix().to_4x4()
    return ob

def collider(name,p,size,angle=0,camera_only=False):
    COLLIDERS.append(dict(id=name,center=list(p),size=list(size),rotation_y=angle,camera_only=camera_only))

def book(name,p,size=(.27,.045,.34),mat='cover_sage',angle=0):
    w,h,d=size
    mat={'sage':'cover_sage','apricot':'cover_clay','linen':'cover_taupe'}.get(mat,mat)
    with frame(p,angle):
        for y in [-h/2,h/2]:box(name+'_ClothboundCover',(0,y,0),(w,.004,d),mat,.002)
        box(name+'_PaperBlock',(.003,0,0),(w-.015,h-.009,d-.014),'paper',.002)
        ob=box(name+'_RoundedSpine',(-w/2+.003,0,0),(.016,h+.007,d),mat,.004)
        ob.modifiers[0].segments=4
        for y in [-h*.28,0,h*.28]:box(name+'_PageEdges',(.008,y,d/2-.006),(w-.028,.0008,.0015),'paper_edge',0)
        for z in [-d*.32,d*.32]:box(name+'_SpineBands',(-w/2-.005,0,z),(.002,h*.7,.008),'brass',0)
        box(name+'_CoverTitle',(0,h/2+.0025,-d*.09),(w*.50,.001,.025),'paper',0)
        box(name+'_CoverSubtitle',(0,h/2+.0025,-d*.22),(w*.32,.001,.007),'paper',0)


def chair(name,p,angle=0,mat='sage'):
    with frame(p,angle):
        rounded(name+'_SeatShell',(0,.435,0),(.57,.075,.55),.13,'oak')
        rounded(name+'_SeatCushion',(0,.49,-.012),(.53,.08,.50),.13,mat)
        # Wrapped upholstered back, open beneath it; different from a slab chair.
        pts=[]; n=20
        for y,r in [(.57,.285),(.91,.315)]:
            for j in range(n+1):
                a=math.radians(-65+j*130/n)
                pts.append((math.sin(a)*r,y,math.cos(a)*r-.04))
        ob=mesh(name+'_CurvedBack',pts,[(j,j+1,j+1+n+1,j+n+1) for j in range(n)],mat)
        sol=ob.modifiers.new('Upholstery thickness','SOLIDIFY');sol.thickness=.065
        bevel(ob,.025,3)
        for poly in ob.data.polygons:poly.use_smooth=True
        for sx in [-1,1]:
            for sz in [-1,1]:
                rod(name+'_TaperedLeg',(sx*.245,.04,sz*.23),(sx*.19,.42,sz*.18),.023,'oak')
                cylinder(name+'_Foot',(sx*.245,.025,sz*.23),.025,.035,'brass',segments=12)
            rod(name+'_BackSupport',(sx*.22,.43,.18),(sx*.25,.71,.23),.018,'oak')

def task_lamp(name,p):
    with frame(p):
        cylinder(name+'_Foot',(0,.014,0),.13,.028,'brass')
        rod(name+'_Upright',(0,.03,0),(0,.40,0),.011)
        rod(name+'_Arm',(0,.40,0),(.13,.47,0),.012)
        cylinder(name+'_Shade',(.13,.46,0),.14,.12,'sage',top=.085)
        cylinder(name+'_Diffuser',(.13,.401,0),.125,.006,'light')

def tablet(name,p,angle=0):
    with frame(p,angle):
        rounded(name+'_WeightedBase',(0,.018,.005),(.34,.036,.23),.045,'dark')
        rounded(name+'_BaseInlay',(0,.038,.005),(.29,.005,.19),.035,'brass',.001)
        # A folded stand meets the rear hinge; visible construction, not a thin pole.
        rod(name+'_HingeSupport',(0,.04,-.055),(0,.27,-.065),.025,'brass',16)
        rod(name+'_HingeBar',(-.13,.27,-.065),(.13,.27,-.065),.023,'dark',24)
        with frame((0,.34,-.025)):
            ob=box(name+'_RoundedHousing',(0,0,0),(.72,.47,.05),'device',.018)
            ob.modifiers[0].segments=5
            box(name+'_ScreenGasket',(0,0,.027),(.664,.423,.006),'dark',.005)
            box(name+'_Glass',(0,0,.032),(.62,.40,.003),'screen',.001)
            box(name+'_ScreenTitle',(-.065,.145,.034),(.41,.018,.001),'ui_pale',0)
            for row in range(3):
                for col in range(2):
                    x=-.155+col*.31;y=.060-row*.073
                    box(name+'_InputBorder',(x,y,.034),(.25,.045,.001),'ui_pale',.002)
                    box(name+'_InputInset',(x,y,.035),(.242,.036,.001),'screen',.002)
            box(name+'_ScreenAction',(.18,-.157,.035),(.16,.025,.001),'ui_accent',.003)
            for x in [-.23,.23]:
                sphere(name+'_RearScrew',(x,-.15,-.027),.006,'brass',12,6,(1,1,.25))
            for x in [-.18,-.12,-.06,0,.06,.12,.18]:box(name+'_RearVent',(x,.135,-.026),(.030,.007,.002),'dark',.001)


def cabinet(name,p,width=2.6,height=1.25,angle=0):
    with frame(p,angle):
        box(name+'_Plinth',(0,.06,0),(width-.1,.12,.40),'dark')
        box(name+'_Back',(0,height/2,-.22),(width,height,.05),'oak')
        for x in [-width/2,width/2]:box(name+'_Side',(x,height/2,0),(.065,height,.50),'oak')
        for y in [.14,height*.5,height]:box(name+'_Shelf',(0,y,0),(width+.06,.045,.53),'oak')
        for x in [-width*.166,width*.166]:box(name+'_Divider',(x,height/2,0),(.035,height-.1,.45),'oak')
        for cell in range(3):
            cx=(cell-1)*width/3
            box(name+'_Door',(cx,height*.255,.258),(width/3-.035,height*.44,.035),'oak')
            rod(name+'_Handle',(cx-.08,height*.40,.29),(cx+.08,height*.40,.29),.009,'brass')
            for j in range(4+cell):
                # Upright paper files have visible spines and foot gaps.
                x=cx-width/7+.09*j
                box(name+'_File',(x,height*.5+.17,.02),(.064,.29+.025*(j%2),.28),['sage','apricot','cream'][j%3],.003)
                box(name+'_FileLabel',(x,height*.5+.19,.164),(.035,.045,.003),'paper',.001)


def export():
    deps=bpy.context.evaluated_depsgraph_get();outputs=[];stats={};issues=[]
    for name,col in COLS.items():
        copies=[];bpy.ops.object.select_all(action='DESELECT')
        for ob in col.objects:
            if ob.type!='MESH':continue
            data=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
            cp=bpy.data.objects.new('EXPORT_'+ob.name,data);SCENE.collection.objects.link(cp);cp.matrix_world=ob.matrix_world.copy();cp.select_set(True);copies.append(cp)
            if not data.uv_layers:issues.append(ob.name+': missing UV')
            if not all(math.isfinite(c) for v in data.vertices for c in v.co):issues.append(ob.name+': nonfinite')
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        result=bpy.context.object;result.name='SM_Counseling_'+name
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        result.data.calc_loop_triangles()
        bm=bmesh.new();bm.from_mesh(result.data)
        nonmanifold=sum(not edge.is_manifold for edge in bm.edges)
        bm.free()
        if nonmanifold:issues.append(f'{name}: {nonmanifold} non-manifold edges')
        stats[name]=dict(triangles=len(result.data.loop_triangles),source_parts=len(copies),materials=len(result.data.materials),nonmanifold_edges=nonmanifold)
        outputs.append(result)
    triangles=sum(s['triangles'] for s in stats.values())
    if triangles>180000:issues.append(f'Triangle budget exceeded: {triangles} > 180000')
    if issues:raise RuntimeError('; '.join(issues))
    bpy.ops.object.select_all(action='DESELECT')
    for ob in outputs:ob.select_set(True)
    tmp=OUT/'counseling_room.new.glb'
    bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_materials='EXPORT',export_vertex_color='NONE')
    os.replace(tmp,OUT/'counseling_room.glb')
    cleanup = optimize_glb(OUT/'counseling_room.glb')
    report=dict(revision='counseling-studio-r8',blender=bpy.app.version_string,triangles=triangles,budget=180000,zones=stats,materials=len({row['material'] for row in cleanup['surfaces']}),bytes=(OUT/'counseling_room.glb').stat().st_size,issues=issues,source='CounselingRoom.blend',texture_source='Poly Haven wood_floor + wood_table_001 2K, ambientCG Fabric060 1K; CC0; recolored runtime maps with originals retained',uv='Metre-scale planar per-face UV, oak grain oriented to longest edge. Intentional repeating UV for shared surfaces.',runtime_acceptance='r8 furniture revision. Brief engine review is recorded separately under deliverables/counseling-room/r8; this report only describes authored geometry.')
    report['export_cleanup'] = cleanup
    report['triangles'] = cleanup['triangles_after']
    (ART/'export-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    for ob in outputs:bpy.data.objects.remove(ob,do_unlink=True)
    print('COUNSELING_EXPORT '+json.dumps(report),flush=True)

def area(name,p,target,power,color,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler()

def camera(name,p,target,lens=24):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;SCENE.camera=ob


def plant(name,p,height=1.0):
    with frame(p):
        pot_h=min(.34,height*.28)
        lathe_vessel(name+'_Planter',(0,0,0),.19,pot_h,'pottery')
        cylinder(name+'_Soil',(0,pot_h-.028,0),.165,.012,'soil',segments=32)
        for i in range(3):
            a=i*2.18+.35
            tip=(math.sin(a)*height*.15,height*(.78+.08*(i%2)),math.cos(a)*height*.15)
            tube_path(name+'_BentStem',[(0,pot_h-.01,0),(tip[0]*.25,height*.48,tip[2]*.25),tip],.009,'bark',10)
            for j in range(4):
                t=.35+j*.16
                start=(tip[0]*t,pot_h+(tip[1]-pot_h)*t,tip[2]*t)
                side=a+(1 if j%2 else -1)*1.10
                end=(start[0]+math.sin(side)*height*(.23-.02*j),start[1]+height*(.07+.015*j),start[2]+math.cos(side)*height*(.23-.02*j))
                organic_leaf(name+'_SculptedLeaf',start,end,height*(.065-.005*j),'foliage' if j%3 else 'foliage_light')


def cushion(name, p, size, mat='sage', angle=0):
    with frame(p, angle):
        ob = box(name, (0, 0, 0), size, mat, min(size)*.33)
        ob.modifiers[0].segments = 5
        for polygon in ob.data.polygons:
            polygon.use_smooth = True
        return ob

def sofa(name, p, angle=0):
    with frame(p, angle):
        rounded(name+'_OakBase', (0,.25,0), (2.45,.17,.90), .17, 'oak')
        for x in [-1.0,1.0]:
            for z in [-.29,.29]:
                rod(name+'_Feet', (x,.035,z),(x*.97,.25,z*.94),.035,'oak',16)
        for x in [-.59,.59]:
            cushion(name+'_Seat', (x,.44,-.02),(1.12,.22,.82),'sage')
            cushion(name+'_Back', (x,.79,.32),(1.12,.65,.24),'sage')
        for x in [-1.19,1.19]:
            cushion(name+'_Arms',(x,.59,-.01),(.22,.48,.88),'sage')
        cushion(name+'_Pillow',(-.72,.77,.17),(.47,.45,.15),'apricot',.16)
        cushion(name+'_Pillow',(.73,.77,.17),(.47,.45,.15),'linen',-.13)
        # Raised fabric piping has real scale and stays subtle at game distance.
        for x in [-.59,.59]:
            rod(name+'_SeatSeam',(x-.43,.47,-.437),(x+.43,.47,-.437),.0035,'linen',8)

def curtain(name,z):
    # Closed, pleated linen strips; backing is opaque so GL has no sorting artifacts.
    points=[]; n=40; width=.82
    for y in [.91,3.98]:
        for j in range(n+1):
            t=j/n
            points.append((-6.16+.065*math.cos(t*math.tau*5),y,z+(t-.5)*width))
    ob=mesh(name,points,[(j,j+1,j+n+2,j+n+1) for j in range(n)],'linen')
    for polygon in ob.data.polygons: polygon.use_smooth=True
    sol=ob.modifiers.new('Woven linen thickness','SOLIDIFY'); sol.thickness=.008
    for j in range(6):
        rod(name+'_HangingLoop',(-6.16,3.98,z-.35+j*.14),(-6.16,4.05,z-.35+j*.14),.011,'brass')

def tube_path(name, points, radius, mat='brass', sides=10):
    pts=[Vector(p) for p in points]; vertices=[]
    for i,p in enumerate(pts):
        tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
        up=Vector((0,1,0)) if abs(tangent.y)<.95 else Vector((0,0,1))
        u=tangent.cross(up).normalized();v=tangent.cross(u).normalized()
        for j in range(sides):
            q=p+radius*(math.cos(j*math.tau/sides)*u+math.sin(j*math.tau/sides)*v)
            vertices.append(tuple(q))
    faces=[tuple(range(sides-1,-1,-1)),tuple(range((len(pts)-1)*sides,len(pts)*sides))]
    for i in range(len(pts)-1):
        for j in range(sides):faces.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    ob=mesh(name,vertices,faces,mat)
    for poly in ob.data.polygons:poly.use_smooth=len(poly.vertices)==4
    return ob


def arc_band(name, center, inner, outer, height, start, end, mat, steps=64):
    pts=[]
    for y in [-height/2,height/2]:
        for r in [inner,outer]:
            for j in range(steps+1):
                a=start+(end-start)*j/steps
                pts.append((center[0]+math.sin(a)*r,center[1]+y,center[2]+math.cos(a)*r))
    n=steps+1;faces=[]
    for j in range(steps):
        faces.extend([(j,j+1,n+j+1,n+j),(2*n+j,3*n+j,3*n+j+1,2*n+j+1),
            (j,2*n+j,2*n+j+1,j+1),(n+j,n+j+1,3*n+j+1,3*n+j)])
    faces.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
    ob=mesh(name,pts,faces,mat)
    if height > .05: bevel(ob,min(.012,height*.2),2)
    return ob


def sphere(name,p,r,mat,segments=20,rings=12,scale=(1,1,1)):
    pts=[(p[0],p[1]-r*scale[1],p[2])]
    for i in range(1,rings):
        theta=math.pi*i/rings
        for j in range(segments):
            a=j*math.tau/segments
            pts.append((p[0]+math.sin(theta)*math.cos(a)*r*scale[0],p[1]-math.cos(theta)*r*scale[1],p[2]+math.sin(theta)*math.sin(a)*r*scale[2]))
    pts.append((p[0],p[1]+r*scale[1],p[2]));faces=[]
    for j in range(segments):faces.append((0,1+(j+1)%segments,1+j))
    for i in range(rings-2):
        for j in range(segments):
            a=1+i*segments+j;b=1+i*segments+(j+1)%segments
            faces.append((a,b,b+segments,a+segments))
    end=len(pts)-1;base=1+(rings-2)*segments
    for j in range(segments):faces.append((base+j,base+(j+1)%segments,end))
    ob=mesh(name,pts,faces,mat)
    for poly in ob.data.polygons:poly.use_smooth=True
    return ob


def flower_vase():
    pass  # Removed with the greenhouse; no r5 flower/cart/rug geometry is used.


def hanging_planter():
    pass  # Removed with the greenhouse; no r5 flower/cart/rug geometry is used.


def richer_foreground():
    pass  # Removed with the greenhouse; no r5 flower/cart/rug geometry is used.


def rug_detail():
    pass  # Removed with the greenhouse; no r5 flower/cart/rug geometry is used.


def gathered_curtain(name,p,width=.44,height=2.12):
    # A small gathered panel frames the window without covering the daylight.
    points=[];nx=40;ny=10
    for j in range(ny+1):
        t=j/ny
        for i in range(nx+1):
            u=i/nx
            x=(u-.5)*width*(1.10-.14*t)
            z=.032*math.cos(u*math.tau*5)+.009*math.sin(t*math.pi)*math.sin(u*math.tau)
            y=t*height+.009*(1-t)*math.cos(u*math.tau*5)
            points.append((p[0]+x,p[1]+y,p[2]+z))
    faces=[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(ny) for i in range(nx)]
    ob=mesh(name,points,faces,'linen')
    for poly in ob.data.polygons:poly.use_smooth=True
    sol=ob.modifiers.new('Sewn cloth thickness','SOLIDIFY');sol.thickness=.003
    for t in [.018,.965]:
        tube_path(name+'_Hem',[(p[0]+(i/nx-.5)*width*(1.10-.14*t),p[1]+t*height,p[2]+.032*math.cos(i/nx*math.tau*5)+.002) for i in range(nx+1)],.002,'linen',6)
    for j in range(6):
        x=p[0]+(j/5-.5)*width*.96
        rod(name+'_Tab',(x,p[1]+height-.02,p[2]),(x,p[1]+height+.055,p[2]),.006,'linen',8)


def hollow_lampshade(name,p):
    # Four continuous rings form an open frustum with real inner lining and rims.
    n=56;profile=[(.31,-.17),(.23,.17),(.218,.17),(.298,-.17)]
    points=[(p[0]+r*math.cos(j*math.tau/n),p[1]+y,p[2]+r*math.sin(j*math.tau/n)) for r,y in profile for j in range(n)]
    faces=[(i*n+j,i*n+(j+1)%n,((i+1)%4)*n+(j+1)%n,((i+1)%4)*n+j) for i in range(4) for j in range(n)]
    ob=mesh(name,points,faces,'linen');ob.data.materials.append(MATS['cream'])
    for poly in ob.data.polygons:
        poly.use_smooth=True
        if n<=poly.index<3*n:poly.material_index=1
    for a in [0,math.tau/3,2*math.tau/3]:
        rod(name+'_InnerSupport',(p[0],p[1]-.08,p[2]),(p[0]+.285*math.cos(a),p[1]-.12,p[2]+.285*math.sin(a)),.004,'brass',8)
    cylinder(name+'_Socket',(p[0],p[1]-.09,p[2]),.022,.065,'brass',segments=16)
    sphere(name+'_Bulb',(p[0],p[1]-.035,p[2]),.038,'light',20,12,(1,1.35,1))


def low_wainscot(name,width):
    """Quiet painted panels with a restrained timber cap, tight against the wall."""
    box(name+'_PanelBacking',(0,.405,.185),(width,.55,.025),'cream',.002)
    box(name+'_TimberCap',(0,.714,.205),(width+.03,.047,.065),'oak',.007)
    box(name+'_UpperPaintedRail',(0,.66,.207),(width,.062,.024),'cream',.004)
    box(name+'_LowerPaintedRail',(0,.163,.207),(width,.062,.024),'cream',.004)
    count=max(2,round(width/.64));step=width/count
    for j in range(count+1):
        box(name+'_InsetStile',(-width/2+j*step,.412,.208),(.035,.46,.025),'cream',.003)
    for j in range(count):
        cx=-width/2+(j+.5)*step
        box(name+'_InsetPanel',(cx,.409,.201),(step-.075,.40,.009),'plaster',.004)


def ceiling_cornice(name,width):
    # Stepped profiles soften the ceiling line without adding a low beam.
    # Butt the end-wall profiles against the side runs, with a 2 mm joint.
    end_wall=name.startswith(('Back','Entry'))
    box(name+'_LowerPaintedCove',(0,3.345,.205),(10.316 if end_wall else width,.065,.07),'cream',.010)
    box(name+'_TimberShadowLine',(0,3.390,.235),(10.216 if end_wall else width,.025,.11),'oak',.005)
    box(name+'_UpperPaintedCove',(0,3.445,.25),(10.156 if end_wall else width,.085,.14),'cream',.012)


def storage_box(name,p,width,height,depth):
    """Paperboard archive box, overlapping lid and recessed label holder."""
    with frame(p):
        rounded(name+'_Body',(0,height/2,0),(width,height,depth),.018,'cover_taupe',.003)
        rounded(name+'_OverlappingLid',(0,height-.006,0),(width+.018,.038,depth+.018),.020,'cover_clay',.003)
        box(name+'_LabelMount',(0,height*.59,depth/2+.003),(.155,.067,.005),'brass',.003)
        box(name+'_PaperLabel',(0,height*.59,depth/2+.006),(.137,.049,.002),'paper',.001)
        for yy,ww in [(height*.62,.086),(height*.58,.056)]:
            box(name+'_LabelRule',(0,yy,depth/2+.0072),(ww,.002,.001),'paper_edge',0)
        tube_path(name+'_PullLoop',[(-.04,height*.31,depth/2+.004),(-.04,height*.27,depth/2+.016),
                    (.04,height*.27,depth/2+.016),(.04,height*.31,depth/2+.004)],.0035,'brass',8)


def magazine_holder(name,p,width,height,depth,mat):
    """Open sloping sides expose actual paper magazines instead of a solid block."""
    with frame(p):
        box(name+'_Base',(0,.006,0),(width-.012,.012,depth-.024),mat,.002)
        box(name+'_Back',(0,height/2,-depth/2+.005),(width,height,.010),mat,.002)
        box(name+'_Front',(0,height*.205,depth/2-.005),(width,height*.41,.010),mat,.002)
        outline=[(-depth/2,0),(-depth/2,height),(-depth*.17,height),
                 (depth/2,height*.43),(depth/2,0)]
        for side in [-1,1]:
            pts=[(side*width/2+dx,y,z) for dx in [-.004,.004] for z,y in outline]
            n=len(outline)
            faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
            bevel(mesh(name+'_SlopedSide',pts,faces,mat),.002,2)
        for i in range(3):
            x=-width*.27+i*width*.27
            upright_book(name+'_Magazine_'+str(i),(x,.014,-.005),width*.19,height*(.78+.035*i),depth*.82,
                         ['cover_clay','cover_taupe','cover_sage'][i])
        box(name+'_SpineLabel',(0,height*.22,depth/2+.001),(width*.61,.040,.002),'paper',.001)


def room_shell():
    collection('StudioArchitecture')
    box('StudioOakFloor',(0,-.10,0),(10.8,.20,8.6),'oak',.015)
    box('StudioCeiling',(0,3.57,0),(11.2,.14,9.0),'plaster',0)
    # Deep real window openings, plaster reveals, timber sills and slender frames.
    for name,p,span,opening,angle in [
        ('West',(-5.40,0,0),8.60,4.10,math.pi/2),
        ('East',(5.40,0,.10),8.60,3.65,-math.pi/2),
        ('Back',(0,0,-4.30),10.80,2.10,0)]:
        with frame(p,angle):
            side=(span-opening)/2
            for sign in [-1,1]:
                box(name+'PlasterWall',(sign*(opening/2+side/2),1.75,0),(side,3.50,.34),'plaster',0)
                box(name+'WindowReveal',(sign*(opening/2-.025),1.83,.025),(.10,1.95,.40),'cream',.008)
                box(name+'WindowUpright',(sign*(opening/2-.07),1.83,-.13),(.055,1.95,.065),'oak',.006)
            box(name+'WindowSillWall',(0,.425,0),(opening,.85,.34),'plaster',0)
            box(name+'WindowLintel',(0,3.15,0),(opening,.70,.34),'plaster',0)
            box(name+'DeepTimberSill',(0,.86,.10),(opening+.12,.065,.56),'oak',.012)
            for y in [.92,2.79]:box(name+'WindowFrame',(0,y,-.13),(opening-.20,.055,.065),'oak',.006)
            box(name+'ClearWindowGlass',(0,1.85,-.16),(opening-.14,1.85,.014),'glass',.001)
            for x in [-opening*.25,opening*.25]:box(name+'WindowMullion',(x,1.85,-.12),(.035,1.85,.06),'oak',.004)
            box(name+'Skirting',(0,.08,.205),(10.336 if name=='Back' else span,.13,.05),'oak',.006)
            low_wainscot(name+'WindowApron',opening-.03)
            ceiling_cornice(name+'Cornice',span-.20)
            if name in ('West','East'):
                rod(name+'CurtainRail',(-opening/2-.16,3.04,.20),(opening/2+.16,3.04,.20),.012,'brass',16)
                for sign in [-1,1]:gathered_curtain(name+'GatheredLinen',(sign*(opening/2-.17),.86,.20))
        collider(name+'Wall',[p[0],1.75,p[2]],[span,3.5,.34],angle)
    for x in [-3.25,3.25]:
        box('EntryPlasterWall',(x,1.75,4.30),(4.30,3.5,.34),'plaster',0)
        with frame((x,0,4.30),math.pi):
            low_wainscot('EntryWallApron',4.20)
            box('EntrySkirting',(-.12 if x<0 else .12,.08,.205),(3.976,.13,.05),'oak',.006)
    with frame((0,0,4.30),math.pi):ceiling_cornice('EntryCornice',10.55)
    box('EntryLintel',(0,2.98,4.30),(2.2,1.04,.34),'plaster',0)
    for x in [-1.07,1.07]:box('EntryTimberJamb',(x,1.22,4.29),(.075,2.44,.42),'oak',.012)
    box('EntryTimberHeader',(0,2.44,4.29),(2.20,.075,.42),'oak',.012)
    collider('Floor',[0,-.1,0],[10.8,.20,8.6])
    collider('EntrySafety',[0,1.75,4.38],[10.8,3.5,.15])
    collider('CeilingSafety',[0,3.56,0],[10.8,.12,8.6],camera_only=True)
    # Two properly scaled textiles, with subdued inner fields and bound edges.
    for x,color in [(-2.95,'sage'),(2.65,'apricot')]:
        rounded('BoundWovenRug',(x,.012,-1.80),(2.90,.024,2.72),.16,color,.003)
        rounded('WovenInset',(x,.026,-1.80),(2.66,.008,2.48),.12,'linen',.001)
        for z in [-2.94,-.66]:
            box('RugWovenStripe',(x,.032,z),(2.42,.002,.035),color,0)
            box('RugStitchLine',(x,.033,z+.065),(2.42,.002,.012),color,0)


def interest_desk():
    collection('GradeOneAssessment')
    with frame((-2.95,0,-2.65)):
        box('HighOneAlcoveBacking',(0,1.65,-1.15),(3.05,2.30,.12),'paint_sage',.02)
        for x in [-1.52,1.52]:box('HighOneAlcoveStile',(x,1.65,-1.08),(.07,2.3,.18),'oak',.009)
        box('HighOneAlcoveCornice',(0,2.82,-1.09),(3.1,.09,.20),'oak',.012)
        rounded('HighOneCraftedDesktop',(0,.86,0),(2.56,.065,1.02),.22,'oak',.012)
        box('HighOneDrawerCase',(-.91,.44,-.02),(.58,.77,.78),'oak',.012)
        for y in [.25,.52,.73]:
            box('HighOneDrawerFront',(-.91,y,.39),(.52,.18,.035),'paint_sage',.008)
            rod('HighOneDrawerPull',(-1.00,y+.015,.42),(-.82,y+.015,.42),.007,'brass',10)
        for z in [-.34,.34]:rod('HighOneSlimLeg',(.97,.05,z),(.97,.82,z),.025,'brass',12)
        rod('HighOneLegBrace',(.97,.17,-.34),(.97,.17,.34),.016,'brass',12)
        tablet('HighOne_AssessmentTablet',(.08,.898,.17),0)
        book('HighOneJournal',(-.73,.926,.03),(.25,.04,.32),'sage',-.07)
        box('HighOneWallPlaque',(0,2.10,-1.065),(1.65,.235,.025),'cream',.008)
        box('HighOneDisplayShelf',(0,2.47,-.88),(2.70,.045,.43),'oak',.009)
    collider('HighOneDesk',[-2.95,.445,-2.65],[2.56,.89,1.02])
    collider('HighOneBacking',[-2.95,1.65,-3.80],[3.10,2.35,.18])
    collection('GradeThreeAssessment')
    with frame((2.65,0,-2.65)):
        box('HighThreeAlcoveBacking',(0,1.65,-1.15),(3.03,2.30,.12),'paint_clay',.02)
        for x in [-1.50,1.50]:box('HighThreeAlcoveStile',(x,1.65,-1.08),(.07,2.30,.18),'oak',.009)
        box('HighThreeCornice',(0,2.82,-1.09),(3.08,.09,.20),'oak',.012)
        desktop=rounded('HighThreeDesktop',(0,.86,0),(2.55,.065,1.02),.12,'oak',.012)
        return_top=rounded('HighThreeReturn',(1.15,.86,-.40),(.58,.065,1.72),.10,'oak',.012)
        # A single evaluated L-shaped surface replaces overlapping table slabs.
        union=desktop.modifiers.new('Joined L desktop — remove coplanar faces','BOOLEAN')
        union.operation='UNION';union.solver='EXACT';union.object=return_top
        operands=bpy.data.collections.get('COL_RepairOperands') or bpy.data.collections.new('COL_RepairOperands')
        if operands.name not in SCENE.collection.children:SCENE.collection.children.link(operands)
        COL.objects.unlink(return_top);operands.objects.link(return_top)
        return_top.hide_render=True;return_top.hide_set(True)
        for x in [-.97,.97]:
            box('HighThreeBaseCase',(x,.44,-.04),(.50,.78,.79),'cream',.01)
            box('HighThreeInsetDoor',(x,.44,.37),(.42,.65,.025),'paint_clay',.007)
            rod('HighThreeDoorPull',(x-.06,.68,.40),(x+.06,.68,.40),.007,'brass',10)
        tablet('HighThree_AssessmentTablet',(-.04,.898,.17),0)
        book('HighThreeExplorationJournal',(.75,.925,.05),(.25,.035,.32),'apricot',.08)
        box('HighThreeWallPlaque',(0,2.10,-1.065),(1.95,.235,.025),'cream',.008)
        box('HighThreeDisplayShelf',(0,2.47,-.88),(2.70,.045,.43),'oak',.009)
    collider('HighThreeDesk',[2.65,.445,-2.65],[2.55,.89,1.02])
    collider('HighThreeReturn',[3.8,.445,-3.05],[.58,.89,1.72])
    collider('HighThreeBacking',[2.65,1.65,-3.80],[3.10,2.35,.18])


def crescent_bench(name,p,angle):
    with frame(p,angle):
        arc_band(name+'_FloatingOakBase',(0,.30,0),.70,1.45,.16,-.92,.92,'oak',40)
        arc_band(name+'_UpholsteredSeat',(0,.46,0),.73,1.42,.18,-.92,.92,'sage',48)
        arc_band(name+'_CurvedBack',(0,.76,0),1.35,1.49,.60,-.94,.94,'sage',48)
        tube_path(name+'_BrassSeam',[(1.49*math.sin(-.94+j*1.88/48),1.04,1.49*math.cos(-.94+j*1.88/48)) for j in range(49)],.008,'brass',8)
        for a in [-.65,.65]:
            rod(name+'_Foot',(.98*math.sin(a),.03,.98*math.cos(a)),(.98*math.sin(a),.29,.98*math.cos(a)),.055,'oak',16)
        for x in [-.68,.68]:cushion(name+'_Pillow',(x,.75,1.02),(.35,.36,.16),'apricot',x*.20)
    # One named proxy is shared by both seats, so the stand-up solver can ignore it.
    cp=(p[0]+math.sin(angle)*1.02,.58,p[2]+math.cos(angle)*1.02)
    collider(name,list(cp),[2.42,1.16,.96],angle)


def consultation():
    collection('SharedQuietSeating')
    sofa('WindowSofa',SOFA_POSITION,-math.pi/2)
    # The window seating now rests directly on the timber floor.
    collider('WindowSofa',[SOFA_POSITION[0],.55,SOFA_POSITION[2]],[2.55,1.1,1.04],-math.pi/2)
    tx,_,tz=SIDE_TABLE_POSITION
    cylinder('WindowSideTable',(tx,.28,tz),.30,.56,'oak',segments=40)
    book('WindowReadingBook',(tx,.59,tz),(.24,.035,.29),'sage',.12)
    collider('WindowSideTable',[tx,.30,tz],[.63,.60,.63])
    cylinder('WindowLampFoot',(-4.75,.025,-1.27),.24,.05,'brass',segments=32)
    rod('WindowLampStem',(-4.75,.05,-1.27),(-4.75,1.63,-1.27),.016,'brass',12)
    hollow_lampshade('WindowLampShade',(-4.75,1.57,-1.27))
    collider('WindowLamp',[-4.75,.85,-1.27],[.58,1.7,.58])
    from counseling_wood_chair import build_wood_chair
    for name,x in [('HighOneWoodChair',-2.95),('HighThreeWoodChair',2.65)]:
        # Keep each chair as its own exported mesh so seated movement can move
        # only that furniture, independently of the sofa and static room.
        collection(name)
        build_wood_chair(globals(),name,(x,0,DESK_CHAIR_Z))
        collider(name,[x,.47,DESK_CHAIR_Z+.0175],[.54,.94,.565])


def entrance_nook():
    collection('OriginalDecor')
    # Shallow wall-attached pieces stay outside all direct assessment paths.
    with frame((4.96,0,.70),-math.pi/2):
        box('EastBuiltInBacking',(0,1.13,-.13),(2.7,1.12,.08),'paint_sage',.01)
        for y in [.75,1.35]:box('EastFloatingShelf',(0,y,.02),(2.8,.055,.40),'oak',.009)
        for x in [-1.05,1.05]:
            rod('EastShelfBracket',(x,.76,-.12),(x,1.34,-.12),.014,'brass',10)
            rod('EastShelfBracketArm',(x,.77,-.12),(x,.77,.18),.014,'brass',10)
        # The lower tier stays inside the existing shallow collision proxy.
        box('EastStorageBacking',(0,.55,-.155),(2.72,.43,.035),'paint_sage',.005)
        box('EastStorageBottom',(0,.34,.015),(2.80,.04,.40),'oak',.008)
        for x in [-1.365,-.46,.30,1.365]:
            box('EastStorageDivider',(x,.55,.015),(.035,.42,.38),'oak',.006)
        storage_box('EastArchiveBox',(-.08,.36,.025),.59,.31,.31)
        for i in range(3):
            magazine_holder('EastMagazineFile_'+str(i),(.53+i*.255,.36,.025),.19,.30,.30,
                            ['cover_taupe','cover_sage','cover_clay'][i])
    collider('EastBuiltIn',[4.96,.95,.70],[.48,1.3,2.84])
    collection('OutsideGarden')
    box('OutsideCourtGround',(0,-.23,0),(17,.10,15),'leaf_dark',0)
    box('EntryPorch',(0,-.05,5.2),(3.1,.10,1.8),'stone',.02)


def write_layout():
    stations=[]
    for key,title,x,subtitle,screen_x in [
        ('interest_high1','高一・興趣量表',-2.95,'六項 RIASEC 興趣分數',-2.87),
        ('interest_high3','高三・學系探索量表',2.65,'33 種知識興趣・適配度與 Z 分數',2.61)]:
        stations.append(dict(view=key,title=title,subtitle=subtitle,approach=[x,.06,DESK_APPROACH_Z],radius=1.2,
            sign=dict(position=[x,2.10,-3.699],width=1.45 if x<0 else 1.75,color='355b4c'),
            screen=dict(center=[screen_x,1.238,-2.4715],normal=[0,0,1],right=[1,0,0],width=.62,height=.40)))
    stations.append(dict(view='exit',title='返回星途',subtitle='回到原來的位置',approach=[0,.06,3.65],radius=.9,
        sign=dict(position=[0,2.72,4.10],rotation_y=math.pi,width=1.20,color='355b4c')))
    seats=[]
    for index,z in enumerate([-.24,.94]):
        seats.append(dict(id='window_sofa_'+str(index),kind='seat',title='窗邊共用沙發',seat_point=[SOFA_POSITION[0],.55,z],
            stand_point=[SOFA_POSITION[0]+.91,.06,z],facing=math.pi/2,radius=.9,collider_id='WindowSofa'))
    for key,title,x,name in [('interest_high1','高一木椅',-2.95,'HighOneWoodChair'),('interest_high3','高三木椅',2.65,'HighThreeWoodChair')]:
        seats.append(dict(id=key+'_chair',kind='seat',title=title,seat_point=[x,.50,DESK_CHAIR_Z-.012],
            stand_point=[x,.06,DESK_APPROACH_Z],facing=math.pi,radius=.72,collider_id=name,station_view=key,
            movable=True,movement_speed=2.6,visual_node='SM_Counseling_'+name))
    data=dict(schemaVersion=1,revision='2026-10-24-counseling-studio-r8',bounds=dict(min=[-5.4,0,-4.3],max=[5.4,3.5,4.3]),
        spawn=dict(position=[0,.06,1.0],facing=[0,0,-1]),exit=dict(position=[0,.06,3.65]),colliders=COLLIDERS,stations=stations,interactables=seats)
    (OUT/'layout.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')



def lathe_vessel(name,p,radius=.12,height=.18,mat='pottery'):
    # Continuous outer wall, rolled rim and inner wall down to a real basin.
    profile=[(.72,0),(.82,.06),(.98,.22),(1,.80),(.96,.96),(.92,1),(.80,1),(.80,.94),(.86,.78),(.84,.22),(.64,.14)]
    steps=40;pts=[(p[0]+r*radius*math.cos(j*math.tau/steps),p[1]+y*height,p[2]+r*radius*math.sin(j*math.tau/steps)) for r,y in profile for j in range(steps)]
    faces=[tuple(range(steps-1,-1,-1)),tuple(range((len(profile)-1)*steps,len(profile)*steps))]
    for i in range(len(profile)-1):
        for j in range(steps):faces.append((i*steps+j,i*steps+(j+1)%steps,(i+1)*steps+(j+1)%steps,(i+1)*steps+j))
    ob=mesh(name,pts,faces,mat)
    for face in ob.data.polygons:face.use_smooth=len(face.vertices)==4
    return ob


def organic_leaf(name,start,end,width,mat='foliage'):
    a,b=Vector(start),Vector(end);axis=b-a
    side=axis.cross(Vector((0,1,0))).normalized()
    if side.length<.1:side=Vector((1,0,0))
    pts=[];n=12
    for i in range(n+1):
        t=i/n;center=a+axis*t+Vector((0,math.sin(math.pi*t)*axis.length*.15,0))
        for v in [-1,0,1]:
            q=center+side*(v*width*math.sin(math.pi*t)**.8)+Vector((0,-abs(v)*width*.23*math.sin(math.pi*t),0))
            # Tiny finite base/tip width keeps the closed solid free of zero-area faces.
            if i in [0,n]:q+=side*(v*.0005)
            pts.append(tuple(q))
    faces=[]
    for i in range(n):
        for j in range(2):faces.append((i*3+j,i*3+j+1,(i+1)*3+j+1,(i+1)*3+j))
    ob=mesh(name,pts,faces,mat)
    for face in ob.data.polygons:face.use_smooth=True
    sol=ob.modifiers.new('Living leaf thickness','SOLIDIFY');sol.thickness=.0013
    tube_path(name+'_Midrib',[tuple(a),tuple((a+b)/2+Vector((0,axis.length*.15,0))),tuple(b)],.0015,'foliage_vein',6)


def upright_book(name,p,w,h,d,mat='cover_sage',lean=0):
    with frame(p):
        for x in [-w/2,w/2]:box(name+'_Cover',(x,h/2,-.0045),(.004,h,d-.009),mat,.002)
        box(name+'_Pages',(0,h/2,-.002),(w-.006,h-.018,d-.014),'paper',.001)
        ob=box(name+'_Spine',(0,h/2,d/2), (w+.004,h,.014),mat,.004)
        ob.modifiers[0].segments=4
        for yy in [h*.15,h*.80]:box(name+'_Binding',(0,yy,d/2+.007),(w*.86,.007,.001),'brass',0)
        box(name+'_Title',(0,h*.61,d/2+.008),(w*.65,h*.13,.001),'paper',0)
        for yy in [h*.42,h*.37]:box(name+'_SpineText',(0,yy,d/2+.008),(w*.60,.004,.001),'paper',0)


def open_journal(name,p,angle=0):
    with frame(p,angle):
        rounded(name+'_OpenCover',(0,.004,0),(.48,.008,.31),.008,'cover_clay',.001)
        for side in [-1,1]:
            for layer in range(3):
                pts=[];steps=12
                for z in [-.145,.145]:
                    for i in range(steps+1):
                        t=i/steps
                        pts.append((side*(.008+.223*t),.011+layer*.0015+.017*math.sin(math.pi*t)-.003*t,z))
                ob=mesh(name+'_CurvedPage',pts,[(j,j+1,j+steps+2,j+steps+1) for j in range(steps)],'paper')
                sol=ob.modifiers.new('Page thickness','SOLIDIFY');sol.thickness=.0007
            for j in range(7):
                x0=side*.04;x1=side*(.16+.018*(j%3));z=-.11+j*.029
                tube_path(name+'_PrintedLine',[(x0,.026,z),(side*.11,.033,z),(x1,.030,z)],.0012,'ink',6)
        box(name+'_Ribbon',(.025,.009,.165),(.012,.002,.08),'cover_sage',.001)


def text_mesh(name,body,p,size=.055,mat='ink'):
    data=bpy.data.curves.new(name,'FONT');data.body=body;data.align_x='CENTER';data.size=size;data.extrude=.0003
    ob=bpy.data.objects.new('SM_'+name,data);COL.objects.link(ob);data.materials.append(MATS[mat])
    ob.matrix_world=FRAME @ Matrix.Translation(gv(p)) @ Matrix.Rotation(math.pi/2,4,'X')
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob;bpy.ops.object.convert(target='MESH')
    ob=bpy.context.object
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.000001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(ob.data);bm.free()
    ob.data.uv_layers.new(name='UVMap');return ob


def growth_print(name,p,width=.90,height=.95,angle=0):
    with frame(p,angle):
        box(name+'_Backing',(0,0,-.025),(width-.004,height-.004,.03),'oak',.006)
        box(name+'_PaperMat',(0,0,-.006),(width-.035,height-.035,.012),'cream',.002)
        box(name+'_PrintedPaper',(0,0,.002),(width-.15,height-.15,.002),'paper',0)
        for x in [-(width-.025)/2,(width-.025)/2]:box(name+'_FrameSide',(x,0,.012),(.025,height,.045),'oak',.004)
        for y in [-(height-.025)/2,(height-.025)/2]:box(name+'_FrameRail',(0,y,.012),(width-.052,.025,.045),'oak',.004)
        text_mesh(name+'_Heading','ROOM TO GROW',(0,height*.29,.006),width*.065)
        text_mesh(name+'_Caption','NOTICE  /  EXPLORE  /  TRY',(0,-height*.31,.006),width*.038)
        for i in range(3):
            x=(i-1)*width*.23;base=-height*.17;tip=base+.15+i*.055
            tube_path(name+'_PrintedStem',[(x,base,.007),(x+.018,tip-.08,.007),(x,tip,.007)],.0025,'cover_sage',6)
            for j in range(i+1):
                yy=tip-.035-j*.06;direction=1 if j%2 else -1
                ob=sphere(name+'_PrintedLeaf',(x+direction*.034,yy,.007),.040,'cover_sage',16,8,(1,.48,.018))
        for x in [-width*.23,0,width*.23]:rod(name+'_GroundLine',(x-.06,-height*.18,.007),(x+.06,-height*.18,.007),.0018,'paper_edge',6)


def crafted_details():
    global COL
    # Every cluster belongs to the wall or desktop; all movement triangles stay empty.
    COL=COLS['GradeOneAssessment']
    with frame((-2.95,0,-2.65)):
        for i in range(6):
            upright_book('HighOneShelfBook_%d'%i,(-1.10+i*.115,2.495,-.83),.07+.008*(i%3),.24+.028*(i%4),.20,['cover_sage','cover_clay','cover_taupe'][i%3])
        for i in range(3):book('HighOneShelfStack_%d'%i,(.65,2.52+i*.045,-.83),(.33,.038,.22),['cover_clay','cover_taupe','cover_sage'][i],.04*(i-1))
        lathe_vessel('HighOneShelfBowl',(1.08,2.495,-.83),.10,.095)
        growth_print('HighOneGrowthPrint',(.89,1.66,-1.05),.68,.62)
        open_journal('HighOneOpenJournal',(-.70,.902,.02),-.09)
        lathe_vessel('HighOnePenCup',(.88,.90,-.23),.045,.085,'pottery')
        for i in range(3):rod('HighOnePens',(.86+i*.016,.94,-.23),(.85+i*.019,1.065+.012*i,-.23),.003,'oak',8)
        box('HighOneUnderShelfLight',(0,2.439,-.75),(2.4,.012,.025),'light',.002)
    COL=COLS['GradeThreeAssessment']
    with frame((2.65,0,-2.65)):
        for i in range(4):
            upright_book('HighThreeShelfBook_%d'%i,(.67+i*.11,2.495,-.83),.075,.24+.032*(i%3),.19,['cover_taupe','cover_sage','cover_clay'][i%3])
        growth_print('HighThreeShelfPrint',(-.62,2.70,-.82),.54,.40,-.04)
        lathe_vessel('HighThreeCup',(.92,.90,-.30),.052,.087,'pottery')
        tube_path('HighThreeCupHandle',[(.96,.965,-.30),(1.035,.971,-.30),(1.042,.934,-.30),(.96,.924,-.30)],.008,'pottery',12)
        cylinder('HighThreeTea',(.92,.966,-.30),.040,.003,'tea',segments=24)
        for i in range(2):book('HighThreeNotes_%d'%i,(-.82,.925+.04*i,.10),(.24,.035,.30),['cover_taupe','cover_sage'][i],-.08+i*.10)
        box('HighThreeUnderShelfLight',(0,2.439,-.75),(2.4,.012,.025),'light',.002)
    COL=COLS['OriginalDecor']
    with frame((4.96,0,.70),-math.pi/2):
        for i in range(7):upright_book('EastWallBook_%d'%i,(-1.12+i*.10,.78,.04),.058+.008*(i%3),.23+.025*(i%3),.20,['cover_sage','cover_clay','cover_taupe'][i%3])
        for i in range(3):book('EastWallStack_%d'%i,(.55,.80+i*.045,.04),(.35,.04,.23),['cover_sage','cover_taupe','cover_clay'][i],.035*(i-1))
        growth_print('EastMoodPrint',(-.70,1.73,-.025),.86,.68)
        from counseling_botanicals import build_tulip_arrangement
        build_tulip_arrangement(globals(),'EastShelfTulips',(.61,1.38,.03),1.0)
    plant('WestSillPlant',(-5.12,.895,.60),.65)
    plant('WestSillPlantSmall',(-5.12,.895,-.30),.42)
    plant('BackWindowPlant',(.61,.895,-4.09),.65)
    # Tailored textile seam on the sofa and a folded throw on its far arm.
    COL=COLS['SharedQuietSeating']
    with frame(SOFA_POSITION,-math.pi/2):
        for x in [-.59,.59]:
            tube_path('SofaBackPiping',[(x-.48,.53,.185),(x-.50,1.04,.185),(x+.50,1.04,.185),(x+.48,.53,.185)],.0033,'linen',8)
    from counseling_soft_furnishings import add_soft_furnishings
    add_soft_furnishings(globals())
    COL=COLS['OutsideGarden']
    for name,p,h in [('WestGarden',(-6.6,0,-.6),2.8),('EastGarden',(6.65,0,.9),2.45),('RearGarden',(-.60,0,-5.6),2.6)]:
        plant(name,p,h)
    for x,z in [(-6.7,2.4),(6.7,-1.5),(1.7,-5.8)]:
        box('CourtyardLowPlanter',(x,.22,z),(1.2,.44,.70),'stone',.025)
        plant('CourtShrub',(x,.45,z),.90)


def finish():
    for key,color,rough,metal in [
        ('cream',(.68,.62,.51),.72,0),('plaster',(.64,.60,.52),.94,0),('paint_sage',(.19,.30,.23),.48,0),('paint_clay',(.46,.25,.14),.52,0),('brass',(.43,.31,.14),.38,.65),
        ('dark',(.052,.075,.061),.65,0),('ceramic',(.80,.76,.65),.36,0),
        ('leaf',(.24,.39,.17),.82,0),('leaf_dark',(.12,.23,.12),.9,0),
        ('ink',(.25,.33,.27),.92,0),('screen_ink',(.55,.70,.57),.7,0),
        ('key',(.32,.40,.33),.65,0),('paper',(.90,.85,.72),.92,0)]:
        material(key,color,rough,metal)
    material('oak',(1,1,1),.65,texture='oak')
    material('joinery',(1,1,1),.52,texture='joinery')
    for key,color,rough in [('cover_sage',(.10,.22,.17),.78),('cover_clay',(.36,.14,.075),.80),('cover_taupe',(.30,.25,.18),.85),('paper_edge',(.38,.32,.23),.94),('pottery',(.45,.39,.29),.28),('soil',(.055,.035,.020),.98),('bark',(.16,.09,.045),.88),('foliage',(.08,.18,.055),.62),('foliage_light',(.18,.31,.10),.70),('foliage_vein',(.25,.34,.14),.80),('device',(.12,.17,.15),.38),('ui_pale',(.62,.72,.59),.7),('ui_accent',(.70,.40,.21),.7),('tea',(.11,.052,.015),.22)]:material(key,color,rough)
    for key in ['sage','apricot','linen']:material(key,(1,1,1),.92,texture=key)
    material('mint',(.40,.61,.49),.62)
    material('stone',(.67,.71,.65),.88)
    material('science',(.23,.55,.54),.22)
    material('glass',(.75,.91,.86),.18)
    glass=MATS['glass']; bsdf=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    bsdf.inputs['Alpha'].default_value=.12
    glass.diffuse_color=(.75,.91,.86,.12)
    glass.surface_render_method='DITHERED'
    material('light',(1,.92,.75),.55,emission=.28)
    material('screen',(.22,.42,.36),.62,emission=.08)
    room_shell(); interest_desk(); consultation(); entrance_nook(); crafted_details(); write_layout()
    export()
    for im in bpy.data.images:
        if im.source=='FILE':im.pack()
    # Blender-only authoring lights are inside the actual studio shell.
    # They are excluded from GLB and are not Godot lighting acceptance.
    area('LGT_Window',(-5.12,2.4,0),(0,1,-1),550,(1,.94,.83),3.0)
    area('LGT_Ceiling',(0,3.25,0),(0,0,0),120,(1,.96,.87),5)
    area('LGT_Entry',(0,2.4,3.95),(0,1,-3),80,(.88,.94,1),3.5)
    camera('CAM_Counseling_Entry',(0,3.12,3.85),(0,1.0,-1.8),22)
    SCENE['style']='r8 warm-window studio: windowward sofa on bare timber floor, forward round side table and two wooden assessment chairs. Existing wainscot, cornice, wall storage and tailored textiles retained. 10.8x8.6m, exactly two grade areas; high art only.'
    SCENE['provenance']='Project-authored geometry. Poly Haven wood_floor and ambientCG Fabric060 CC0 maps, sources retained.'
    reference=bpy.data.objects.new('REF_Human_1.75m',None); SCENE.collection.objects.link(reference)
    reference.empty_display_type='CUBE'; reference.empty_display_size=.875; reference.location=gv((0,.875,2.8)); reference.hide_render=True
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'CounselingRoom.blend'))
    if '--no-render' not in sys.argv:
        SCENE.render.filepath=str(ART/'room-entry.png');bpy.ops.render.render(write_still=True)
    print('COUNSELING_COMPLETE',flush=True)

finish()
