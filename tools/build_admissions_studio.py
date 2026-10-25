"""Author the StarPath advising studio. Run with Blender --background --factory-startup.

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
ART = ROOT / 'art/AdmissionsRoom'
OUT = ROOT / 'game/assets/admissions_room'
TEX = ROOT / 'game/assets/university_hall/textures'
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
RNG = random.Random(20261019)

def gv(p): return Vector((p[0], -p[2], p[1]))

def material(key, color, rough=.5, metal=0, texture=None, emission=0):
    mat = bpy.data.materials.new('MAT_Studio_' + key)
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
        for suffix, plug in [('base', 'Base Color'), ('rough', 'Roughness')]:
            im = bpy.data.images.load(str(TEX / f'{texture}_{suffix}.png'), check_existing=True)
            im.colorspace_settings.name = 'sRGB' if suffix == 'base' else 'Non-Color'
            if im.size[0] > 512: im.scale(512, 512)
            node = nodes.new('ShaderNodeTexImage'); node.image = im
            links.new(node.outputs['Color'], bsdf.inputs[plug])
        im = bpy.data.images.load(str(TEX / f'{texture}_normal.png'), check_existing=True)
        im.colorspace_settings.name = 'Non-Color'
        if im.size[0] > 512: im.scale(512, 512)
        tex = nodes.new('ShaderNodeTexImage'); tex.image = im
        normal = nodes.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value = .38
        links.new(tex.outputs['Color'], normal.inputs['Color'])
        links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
    MATS[key] = mat

def collection(name):
    global COL
    COL = bpy.data.collections.new('COL_Studio_' + name)
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
        if mat == 'walnut':
            spans = [max(data.vertices[data.loops[j].vertex_index].co[i] for j in poly.loop_indices) - min(data.vertices[data.loops[j].vertex_index].co[i] for j in poly.loop_indices) for i in axes]
            if spans[0] > spans[1]: axes.reverse()
        scale = .65 if mat in ('teal', 'clay', 'fabric') else 1.2
        for j in poly.loop_indices:
            co = data.vertices[data.loops[j].vertex_index].co
            uv.data[j].uv = (co[axes[0]] / scale, co[axes[1]] / scale)
    obj = bpy.data.objects.new('SM_' + name, data)
    COL.objects.link(obj); data.materials.append(MATS[mat])
    obj.matrix_world = FRAME.copy()
    return obj

def bevel(obj, width=.012, segments=3):
    mod = obj.modifiers.new('Soft manufactured edges', 'BEVEL')
    mod.width = width; mod.segments = segments
    mod = obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    mod.keep_sharp = True
    return obj

def box(name, p, size, mat='walnut', edge=.012):
    x, y, z = [v / 2 for v in size]
    ob = mesh(name, [(-x,-y,-z),(x,-y,-z),(x,-y,z),(-x,-y,z),(-x,y,-z),(x,y,-z),(x,y,z),(-x,y,z)], [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    if edge: bevel(ob, min(edge, min(size) * .38))
    return ob

def rounded(name, p, size, radius, mat='walnut', edge=.006):
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

def book(name,p,size=(.27,.045,.34),mat='teal',angle=0):
    w,h,d=size
    with frame(p,angle):
        for y in [-h/2,h/2]: box(name+'_Cover',(0,y,0),(w,.008,d),mat,.003)
        box(name+'_Pages',(.003,0,0),(w-.018,h-.008,d-.015),'paper',.002)
        box(name+'_Spine',(-w/2+.004,0,0),(.012,h+.008,d),mat,.003)
        for z in [-d*.34,d*.34]: box(name+'_Binding',(-w/2-.003,0,z),(.003,h*.7,.008),'brass',0)

def plant(name,p,height=.9):
    with frame(p):
        cylinder(name+'_Pot',(0,.15,0),.20,.30,'ceramic',top=.25)
        cylinder(name+'_Soil',(0,.295,0),.222,.012,'dark')
        for j in range(8):
            a=j*2.39
            tip=(math.cos(a)*height*.36,height*(.65+.04*j),math.sin(a)*height*.36)
            rod(name+'_Stem',(0,.28,0),tip,.008,'leaf_dark',8)
            for step in [0,1]:
                y=tip[1]-.05-step*.22
                side=a+step*2.3
                x,z=tip[0]*(.8-step*.15),tip[2]*(.8-step*.15)
                length=height*.27
                pts=[(x,y,z),(x+math.cos(side-.5)*length*.55,y+.07,z+math.sin(side-.5)*length*.55),(x+math.cos(side)*length,y+.14,z+math.sin(side)*length),(x+math.cos(side+.5)*length*.55,y+.07,z+math.sin(side+.5)*length*.55),(x+math.cos(side)*length*.48,y+.105,z+math.sin(side)*length*.48)]
                leaf=mesh(name+'_Leaf',pts,[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'leaf' if j%3 else 'leaf_dark')
                solid=leaf.modifiers.new('Leaf thickness','SOLIDIFY');solid.thickness=.002

def chair(name,p,angle=0,mat='teal'):
    with frame(p,angle):
        rounded(name+'_SeatShell',(0,.435,0),(.57,.075,.55),.13,'walnut')
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
                rod(name+'_TaperedLeg',(sx*.245,.04,sz*.23),(sx*.19,.42,sz*.18),.023,'walnut')
                cylinder(name+'_Foot',(sx*.245,.025,sz*.23),.025,.035,'brass',segments=12)
            rod(name+'_BackSupport',(sx*.22,.43,.18),(sx*.25,.71,.23),.018,'walnut')

def task_lamp(name,p):
    with frame(p):
        cylinder(name+'_Foot',(0,.014,0),.13,.028,'brass')
        rod(name+'_Upright',(0,.03,0),(0,.40,0),.011)
        rod(name+'_Arm',(0,.40,0),(.13,.47,0),.012)
        cylinder(name+'_Shade',(.13,.46,0),.14,.12,'teal',top=.085)
        cylinder(name+'_Diffuser',(.13,.401,0),.125,.006,'light')

def tablet(name,p,angle=0):
    with frame(p,angle):
        rounded(name+'_Base',(0,.018,0),(.25,.036,.18),.035,'brass')
        rod(name+'_Stem',(0,.025,0),(0,.19,-.035),.015,'brass')
        with frame((0,.24,-.025)):
            ob=box(name+'_Housing',(0,0,0),(.42,.29,.028),'dark',.012)
            ob.rotation_euler.x=math.radians(13)
            ob=box(name+'_Glass',(0,0,.016),(.387,.252,.004),'screen',.001)
            ob.rotation_euler.x=math.radians(13)

def monitor(name,p,angle=0):
    with frame(p,angle):
        rounded(name+'_Base',(0,.016,0),(.38,.032,.23),.04,'dark')
        rod(name+'_Neck',(0,.03,-.04),(0,.23,-.04),.025,'brass')
        box(name+'_Housing',(0,.43,-.04),(.83,.49,.045),'dark',.018)
        box(name+'_Screen',(0,.43,-.014),(.785,.447,.005),'screen',.001)
        cylinder(name+'_Power',(0,.177,-.007),.009,.008,'light',segments=12)
        # Quiet screen layout; decoration contains no invented admission results.
        for j,w in enumerate([.32,.48,.41]):
            box(name+'_ScreenLine',(-.13,.54-j*.073,-.010),(w,.012,.002),'screen_ink',.001)
        rounded(name+'_Keyboard',(0,.022,.39),(.58,.035,.19),.025,'dark')
        for row in range(3):
            for col in range(12):box(name+'_Key',(-.25+col*.045,.043,.335+row*.047),(.036,.008,.034),'key',.002)
        rounded(name+'_Space',(0,.043,.48),(.27,.008,.026),.008,'key',.001)
        rounded(name+'_Mouse',(.42,.026,.39),(.075,.045,.12),.035,'dark')
        rounded(name+'_MouseMat',(.42,.003,.39),(.24,.004,.28),.025,'teal',.001)

def cabinet(name,p,width=2.6,height=1.25,angle=0):
    with frame(p,angle):
        box(name+'_Plinth',(0,.06,0),(width-.1,.12,.40),'dark')
        box(name+'_Back',(0,height/2,-.22),(width,height,.05),'walnut')
        for x in [-width/2,width/2]:box(name+'_Side',(x,height/2,0),(.065,height,.50),'walnut')
        for y in [.14,height*.5,height]:box(name+'_Shelf',(0,y,0),(width+.06,.045,.53),'walnut')
        for x in [-width*.166,width*.166]:box(name+'_Divider',(x,height/2,0),(.035,height-.1,.45),'walnut')
        for cell in range(3):
            cx=(cell-1)*width/3
            box(name+'_Door',(cx,height*.255,.258),(width/3-.035,height*.44,.035),'walnut')
            rod(name+'_Handle',(cx-.08,height*.40,.29),(cx+.08,height*.40,.29),.009,'brass')
            for j in range(4+cell):
                # Upright paper files have visible spines and foot gaps.
                x=cx-width/7+.09*j
                box(name+'_File',(x,height*.5+.17,.02),(.064,.29+.025*(j%2),.28),['teal','clay','cream'][j%3],.003)
                box(name+'_FileLabel',(x,height*.5+.19,.164),(.035,.045,.003),'paper',.001)

def room():
    collection('Architecture')
    box('Foundation',(0,-.14,0),(17.1,.24,14.1),'stone',.01)
    # Individual honed limestone slabs, subtle seams rather than flat yellow ground.
    for ix in range(12):
        for iz in range(10):
            x=-8.5+(ix+.5)*17/12;z=-7+(iz+.5)*1.4
            box('HonedFloorTile',(x,-.007,z),(17/12-.006,.014,1.394),'stone',.001)
    for x in [-7.8,7.8]:box('FloorBorder',(x,.001,0),(.035,.003,12.6),'brass',0)
    for z in [-6.3,6.3]:box('FloorBorder',(0,.001,z),(15.63,.003,.035),'brass',0)
    box('BackWall',(0,2.5,-7),(17,.20+4.8,.24),'plaster',.015)
    box('RightWall',(8.5,2.5,0),(.24,5,14),'plaster',.015)
    # Left wall is a genuine window opening, with reveal depth and sill.
    box('LeftLowerWall',(-8.5,.52,0),(.24,1.04,14),'plaster')
    box('LeftHeader',(-8.5,4.65,0),(.24,.7,14),'plaster')
    for z,w in [(-6.7,.6),(6.6,.8),(.45,.18)]:box('WindowPier',(-8.5,2.65,z),(.30,3.4,w),'plaster')
    for z in [-3.1,3.55]:
        box('WindowSill',(-8.34,1.06,z),(.57,.08,5.9),'stone',.015)
        for zz in [z-2.88,z,z+2.88]:box('WindowMullion',(-8.45,2.7,zz),(.13,3.25,.075),'walnut',.007)
        for y in [1.15,3.45,4.28]:box('WindowRail',(-8.45,y,z),(.13,.075,5.85),'walnut',.007)
    for x in [-5.25,5.25]:box('EntranceWall',(x,2.5,7),(6.5,5,.24),'plaster')
    box('DoorHeader',(0,4.15,7),(4.1,1.7,.24),'plaster')
    for x in [-2.05,2.05]:box('DoorJamb',(x,1.65,6.88),(.16,3.3,.25),'walnut')
    box('DoorLintel',(0,3.29,6.88),(4.25,.16,.25),'walnut')
    for side in [-1,1]:
        box('GlazedDoor', (side*.98,1.6,7.04),(1.92,3.14,.06),'teal')
        box('DoorInset',(side*.98,1.83,6.997),(1.66,2.32,.022),'screen')
        rod('DoorPull',(side*.16,1.12,6.9),(side*.16,1.48,6.9),.018)
    for x in [-8.32,8.32]:box('TimberSkirting',(x,.15,0),(.055,.3,13.8),'walnut')
    box('BackSkirting',(0,.15,-6.84),(16.8,.3,.055),'walnut')
    box('BackPictureRail',(0,3.65,-6.85),(16.8,.07,.075),'walnut')
    box('Ceiling',(0,5.05,0),(17.2,.14,14.2),'cream')
    for z in [-5.8,-1.8,2.2,6.2]:
        box('CeilingJoist',(0,4.83,z),(16.9,.28,.16),'walnut')
        for x in [-5,0,5]:
            box('FlushLightHousing',(x,4.73,z),(1.1,.07,.11),'brass')
            box('FlushLightDiffuser',(x,4.69,z),(1.02,.006,.08),'light',.002)
        collider('CeilingJoist',[0,4.83,z],[16.9,.28,.16],camera_only=True)
    collider('Floor',[0,-.12,0],[17.1,.24,14.1])
    collider('BackWall',[0,2.5,-7],[17,5,.24])
    collider('LeftWall',[-8.5,2.5,0],[.24,5,14])
    collider('RightWall',[8.5,2.5,0],[.24,5,14])
    collider('EntryWall',[0,2.5,7],[17,5,.24])
    collider('Ceiling',[0,5.05,0],[17.2,.14,14.2],camera_only=True)

def general_desk():
    collection('General')
    rounded('General_Rug',(-4.8,.013,-2.3),(5.3,.024,4.5),.55,'rug')
    with frame((-4.8,0,-2.3)):
        rounded('General_OvalTable',(0,.755,0),(3.3,.075,1.45),.70,'walnut')
        rounded('General_Underside',(0,.698,0),(3.12,.045,1.28),.60,'dark')
        for x in [-1.02,1.02]:
            for z in [-.42,.42]:rod('General_SplayedLeg',(x*1.1,.035,z*1.22),(x,.69,z),.043,'walnut',16)
        rod('General_BrassFootRail',(-1.08,.18,0),(1.08,.18,0),.025)
        book('General_OpenGuide',(-.48,.82,.12),(.37,.035,.45),'cream',-.13)
        book('General_Notebook',(.45,.82,.16),(.25,.025,.33),'teal',.12)
        box('General_Paper',(.44,.838,.16),(.21,.004,.29),'paper',.001)
        rod('General_Pencil',(.42,.85,.06),(.55,.85,.24),.005,'brass',8)
        tablet('General_Terminal',(.92,.795,-.25),-.08)
        task_lamp('General_Lamp',(-1.18,.795,-.18))
        cylinder('General_CeramicCup',(-.1,.85,-.2),.048,.11,'ceramic',top=.054)
        for x in [-.47,.47]:rod('General_SignPost',(x,.80,-.50),(x,1.43,-.50),.012,'brass')
        box('General_DeskPlaque',(0,1.40,-.50),(1.22,.27,.035),'cream',.012)
    for x in [-5.55,-4.2]:chair('General_WindowChair',(x,.025,-3.48),math.pi)
    chair('General_VisitorChair',(-6.75,.025,-2.1),-math.pi/2)
    cabinet('General_LowLibrary',(-7.95,0,-2.8),3.4,1.0,math.pi/2)
    plant('General_WindowPlant',(-7.75,1.02,-4.15),.65)
    collider('GeneralTable',[-4.8,.395,-2.3],[3.25,.79,1.4])
    for i,x in enumerate([-5.55,-4.2]):collider('GeneralChair'+str(i+1),[x,.48,-3.48],[.7,.96,.7])
    collider('GeneralVisitorChair',[-6.75,.48,-2.1],[.7,.96,.7])
    collider('GeneralLibrary',[-7.95,.53,-2.8],[.6,1.06,3.5])

def special_desk():
    collection('Special')
    rounded('Special_Rug',(-.1,.013,-4.7),(3.8,.024,3.4),.28,'clay_rug')
    with frame((-.15,0,-4.75),-.12):
        rounded('Special_ConsultationDesk',(0,.755,0),(2.35,.07,1.05),.16,'walnut')
        for x in [-.99,.99]:
            for z in [-.36,.36]:rod('Special_FrameLeg',(x,.04,z),(x,.72,z),.025,'brass')
        box('Special_DrawerUnit',(.7,.59,-.06),(.49,.22,.67),'walnut',.018)
        for y in [.535,.64]:
            box('Special_Drawer',(.7,y,.286),(.45,.09,.025),'walnut',.006)
            rod('Special_DrawerPull',(.62,y,.31),(.78,y,.31),.008)
        box('Special_DeskMat',(-.28,.794,.03),(.94,.008,.53),'clay',.003)
        book('Special_Guide',(-.32,.83,.05),(.34,.04,.39),'cream',.12)
        tablet('Special_Terminal',(.58,.795,-.14))
        task_lamp('Special_Lamp',(-.91,.795,-.23))
    chair('Special_AdviserChair',(-.3,.025,-5.78),math.pi,'clay')
    chair('Special_VisitorChair',(-1.53,.025,-3.9),-.48,'clay')
    cabinet('Special_Credenza',(-.2,0,-6.52),4.3,1.30)
    for x in [-3.05,2.70]:
        box('Special_WallPilaster',(x,1.97,-6.82),(.075,3.28,.08),'walnut')
    plant('Special_Plant',(1.48,1.34,-6.48),.66)
    # Wall-mounted display case, brochures and a soft fabric pinboard.
    box('Special_NoticeFrame',(-.55,2.52,-6.76),(3.0,1.55,.13),'walnut')
    box('Special_NoticeFabric',(-.55,2.52,-6.681),(2.86,1.41,.023),'clay')
    for x,y,w,h in [(-1.36,2.39,.53,.62),(-.58,2.31,.54,.47),(.24,2.46,.48,.66)]:
        box('Special_Brochure',(x,y,-6.662),(w,h,.008),'paper',.002)
        for j in range(3):box('Special_BrochureText',(x,y+.10-j*.07,-6.656),(w*.65,.009,.002),'ink',0)
        rod('Special_Pin',(x,y+h*.43,-6.65),(x,y+h*.43,-6.63),.012,'brass')
    collider('SpecialDesk',[-.15,.39,-4.75],[2.35,.78,1.05],-.12)
    collider('SpecialAdviserChair',[-.3,.48,-5.78],[.7,.96,.7])
    collider('SpecialVisitorChair',[-1.53,.48,-3.9],[.7,.96,.7],-.48)
    collider('SpecialCabinet',[-.2,.67,-6.52],[4.45,1.34,.6])

def apcs_desk():
    collection('APCS')
    rounded('APCS_Rug',(5.3,.013,-2.8),(4.8,.024,4.5),.3,'rug')
    with frame((6.65,0,-2.4),-math.pi/2):
        rounded('APCS_LongBench',(0,.755,0),(3.5,.075,.93),.11,'walnut')
        rounded('APCS_Return',(-1.30,.755,1.01),(.9,.075,1.35),.11,'walnut')
        for x,z in [(-1.48,-.28),(1.48,-.28),(1.48,.28),(-1.48,1.54),(-1.01,1.54)]:
            rod('APCS_Leg',(x,.04,z),(x,.72,z),.025,'dark')
        box('APCS_CableTray',(0,.64,-.28),(2.9,.09,.14),'dark')
        monitor('APCS_Workstation',(.30,.795,-.08))
        box('APCS_Computer',(-1.18,.26,.0),(.23,.49,.41),'dark',.025)
        for j in range(6):box('APCS_CaseVent',(-1.18,.22+j*.031,.211),(.15,.009,.004),'key',.002)
        book('APCS_ProgrammingNotes',(-1.3,.83,.93),(.30,.04,.38),'teal',.05)
        task_lamp('APCS_Lamp',(-1.25,.795,1.45))
    chair('APCS_Chair',(5.15,.025,-2.55),-math.pi/2)
    cabinet('APCS_Supplies',(7.96,0,-2.8),4.8,1.15,-math.pi/2)
    with frame((8.31,0,-2.7),-math.pi/2):
        box('APCS_WallPanel',(0,2.55,0),(4.5,1.8,.06),'teal')
        for x in [-2.18,2.18]:box('APCS_PanelTrim',(x,2.55,.043),(.025,1.8,.02),'brass',.003)
        # A subtle geometric circuit motif engraved into the panel.
        for j in range(5):
            x=-1.55+j*.75
            rod('APCS_Motif',(x,2.15,.04),(x,2.6+(j%2)*.22,.04),.006,'brass',8)
            rod('APCS_Motif',(x,2.6+(j%2)*.22,.04),(x+.35,2.6+(j%2)*.22,.04),.006,'brass',8)
    collider('APCSBench',[6.65,.395,-2.4],[.93,.79,3.5])
    collider('APCSReturn',[5.64,.395,-1.1],[1.35,.79,.9])
    collider('APCSChair',[5.15,.48,-2.55],[.7,.96,.7])
    collider('APCSCabinet',[7.96,.6,-2.8],[.6,1.2,4.95])

def entrance():
    collection('Passport')
    with frame((5.1,0,2.6)):
        rounded('Passport_Counter',(0,.87,0),(2.7,.08,1.10),.36,'walnut')
        rounded('Passport_Base',(0,.40,-.08),(2.32,.76,.78),.27,'teal')
        rounded('Passport_RecessedPlinth',(0,.045,-.08),(2.12,.09,.64),.22,'dark')
        for x in [-.95,-.76,-.57,-.38,-.19,0,.19,.38,.57,.76,.95]:
            box('Passport_FlutedFront',(x,.43,.321),(.025,.62,.023),'walnut',.009)
        tablet('Passport_Scores',(-.61,.915,-.03),.07)
        tablet('Passport_Account',(.61,.915,-.03),-.07)
        book('Passport_Booklet',(0,.94,.21),(.25,.035,.32),'cream',-.11)
        for x in [-.61,.61]:
            box('Passport_NamePlate',(x,1.255,.20),(.76,.20,.025),'cream',.01)
            rod('Passport_NameStand',(x,.92,.20),(x,1.26,.20),.012,'brass')
    plant('Passport_Fern',(7.5,0,5.75),1.4)
    collider('PassportKiosk',[5.1,.46,2.6],[2.7,.92,1.1])
    collider('PassportPlant',[7.5,.7,5.75],[.65,1.4,.65])
    collection('Lounge')
    with frame((-5.55,0,4.65)):
        rounded('Lounge_Rug',(0,.013,-.45),(4.7,.024,3.2),.38,'clay_rug')
        rounded('Lounge_SofaBase',(0,.29,0),(2.8,.18,.91),.15,'walnut')
        for x in [-1.15,1.15]:
            for z in [-.32,.32]:cylinder('Lounge_Foot',(x,.12,z),.037,.24,'brass',segments=16)
        for x in [-.65,.65]:rounded('Lounge_Seat',(x,.44,-.05),(1.25,.18,.79),.16,'fabric')
        box('Lounge_Back',(0,.76,.38),(2.8,.65,.23),'fabric',.086)
        for x in [-1.37,1.37]:box('Lounge_Arm',(x,.58,0),(.20,.42,.89),'fabric',.07)
        rounded('Lounge_CoffeeTable',(0,.44,-1.15),(1.35,.055,.67),.31,'walnut')
        for x in [-.43,.43]:rod('Lounge_TableLeg',(x,.02,-1.15),(x,.42,-1.15),.027,'brass')
        book('Lounge_Magazine',(.12,.49,-1.17),(.3,.025,.37),'clay',-.17)
    plant('Lounge_Palm',(-7.65,0,5.85),1.65)
    collider('LoungeSofa',[-5.55,.52,4.65],[2.95,1.04,1])
    collider('LoungeTable',[-5.55,.24,3.5],[1.35,.48,.67])
    collider('LoungePlant',[-7.65,.8,5.85],[.65,1.6,.65])
    collection('Exterior')
    # Sunlit garden visible through the west windows, not a featureless sky slab.
    box('GardenGround',(-11,-.16,0),(5,.2,18),'leaf_dark')
    for z in [-5.5,-1.0,4.8]:plant('GardenShrub',(-10,0,z),2.4)

def write_layout():
    stations=[
        dict(view='general',title='一般大學',subtitle='學測採計校系',approach=[-4.8,.06,-.65],radius=1.55,sign=dict(position=[-4.8,1.40,-2.775],width=1.0,color='244954'),focus_camera=[-3.45,2.04,.23],focus_target=[-4.8,.95,-2.30],focus_fov=48),
        dict(view='special',title='特殊招生',subtitle='各校獨立招生',approach=[-.05,.06,-3.18],radius=1.35,sign=dict(position=[-.55,3.04,-6.59],width=1.25,color='efe4cb'),focus_camera=[.45,1.95,-1.9],focus_target=[-.15,.92,-4.75],focus_fov=48),
        dict(view='apcs',title='APCS 校系',subtitle='採計程式檢測',approach=[4.30,.06,-1.40],radius=1.5,sign=dict(position=[8.20,3.16,-2.7],rotation_y=-math.pi/2,width=1.55,color='efe4cb'),focus_camera=[3.6,2.05,-.15],focus_target=[6.65,1.12,-2.4],focus_fov=48),
        dict(view='scores',title='我的成績',subtitle='模擬考與練習紀錄',approach=[4.45,.06,4.1],radius=.9,sign=dict(position=[4.49,1.255,2.82],width=.64,color='244954'),focus_camera=[4.2,1.7,4.5],focus_target=[4.5,1.05,2.6],focus_fov=46),
        dict(view='account',title='星途帳號',subtitle='登入與帳號設定',approach=[5.65,.06,4.1],radius=.9,sign=dict(position=[5.71,1.255,2.82],width=.64,color='244954'),focus_camera=[5.8,1.7,4.5],focus_target=[5.7,1.05,2.6],focus_fov=46),
        dict(view='exit',title='返回星途',subtitle='回到原來的位置',approach=[0,.06,6.4],radius=1.45,sign=dict(position=[0,3.66,6.80],rotation_y=math.pi,width=1.35,color='244954'))
    ]
    seats=[]
    for id,title,point,stand,facing,body,desk in [
        ('general_window_left','窗邊座椅',[-5.55,.555,-3.48],[-5.55,.06,-4.42],0,'GeneralChair1','general'),
        ('general_window_right','窗邊座椅',[-4.2,.555,-3.48],[-4.2,.06,-4.42],0,'GeneralChair2','general'),
        ('general_visitor','討論桌座椅',[-6.75,.555,-2.1],[-6.85,.06,-1.20],math.pi/2,'GeneralVisitorChair','general'),
        ('special_adviser','諮詢桌座椅',[-.3,.555,-5.78],[.75,.06,-5.75],0,'SpecialAdviserChair','special'),
        ('special_visitor','諮詢座椅',[-1.53,.555,-3.9],[-2.5,.06,-3.50],math.pi-.48,'SpecialVisitorChair','special'),
        ('apcs_computer','電腦桌座椅',[5.15,.555,-2.55],[4.25,.06,-2.55],math.pi/2,'APCSChair','apcs'),
        ('lounge_left','休息沙發',[-6.2,.53,4.60],[-7.4,.06,4.15],math.pi,'LoungeSofa',None),
        ('lounge_right','休息沙發',[-4.9,.53,4.60],[-3.65,.06,4.15],math.pi,'LoungeSofa',None),
    ]:
        entry=dict(id=id,kind='seat',title=title,seat_point=point,stand_point=stand,facing=facing,radius=1.05,collider_id=body)
        if desk:entry['station_view']=desk
        seats.append(entry)
    data=dict(schemaVersion=1,revision='2026-10-19-advising-studio',bounds=dict(min=[-8.5,0,-7],max=[8.5,5,7]),spawn=dict(position=[0,.06,3.3],facing=[0,0,-1]),exit=dict(position=[0,.06,6.4]),colliders=COLLIDERS,stations=stations,interactables=seats)
    (OUT/'layout.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

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
        result=bpy.context.object;result.name='SM_Admissions_'+name
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
    tmp=OUT/'admissions_studio.new.glb'
    bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_materials='EXPORT',export_vertex_color='NONE')
    os.replace(tmp,OUT/'admissions_studio.glb')
    cleanup = optimize_glb(OUT/'admissions_studio.glb')
    report=dict(revision='advising-studio-r1',blender=bpy.app.version_string,triangles=triangles,budget=180000,zones=stats,materials=len(MATS),bytes=(OUT/'admissions_studio.glb').stat().st_size,issues=issues,source='AdmissionsStudio.blend',texture_source='Project-authored university hall textures, shared palette',uv='Metre-scale planar per-face UV, walnut grain oriented to longest edge. Intentional repeating UV for shared surfaces.',runtime_acceptance='Pending actual Godot views and continuous traversal.')
    report['export_cleanup'] = cleanup
    report['triangles'] = cleanup['triangles_after']
    (ART/'export-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
    for ob in outputs:bpy.data.objects.remove(ob,do_unlink=True)
    print('STUDIO_EXPORT '+json.dumps(report),flush=True)

def area(name,p,target,power,color,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler()

def camera(name,p,target,lens=24):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);SCENE.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;SCENE.camera=ob

for key,tex in [('walnut','walnut'),('stone','stone'),('plaster','plaster'),('teal','leather_green'),('clay','leather_red'),('paper','paper')]:material(key,(1,1,1),texture=tex)
for key,color,rough,metal in [('cream',(.68,.63,.52),.82,0),('brass',(.43,.28,.105),.3,.75),('dark',(.033,.045,.041),.4,.1),('fabric',(.34,.40,.34),.92,0),('rug',(.15,.23,.20),.97,0),('clay_rug',(.38,.28,.21),.97,0),('ceramic',(.62,.65,.57),.25,0),('leaf',(.13,.23,.09),.75,0),('leaf_dark',(.065,.13,.05),.86,0),('ink',(.18,.23,.21),.9,0),('screen_ink',(.31,.48,.44),.6,0),('key',(.18,.22,.20),.55,0)]:material(key,color,rough,metal)
material('light',(1,.78,.46),.45,emission=.8)
material('screen',(.065,.16,.16),.32,emission=.12)
room();general_desk();special_desk();apcs_desk();entrance();write_layout()
export()
for im in bpy.data.images:
    if im.source=='FILE':im.pack()
area('LGT_Window',(-8,3.6,-1),(1,.3,-2),1900,(1,.91,.75),7)
area('LGT_Ceiling',(1,4.6,1),(0,0,-2),950,(1,.88,.70),7)
area('LGT_EntryFill',(0,3.4,6),(0,1,-3),500,(.75,.86,1),5)
camera('CAM_Studio_Entry',(.2,2.65,6.45),(-.7,1.4,-3),21)
SCENE['style']='Grounded warm academic advising studio, matching walnut library and teal training room. Three distinct workbenches, real furniture scale, no billboard counters.'
SCENE['provenance']='Original metric geometry. Existing project-authored PBR textures reused; no external assets.'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'AdmissionsStudio.blend'))
if '--no-render' not in sys.argv:
    SCENE.render.filepath=str(ART/'studio-entry.png');bpy.ops.render.render(write_still=True)
    camera('CAM_General_Close',(-1.9,2.25,.25),(-4.8,.78,-2.35),37)
    SCENE.render.filepath=str(ART/'studio-general-detail.png');bpy.ops.render.render(write_still=True)
print('STUDIO_COMPLETE',flush=True)
