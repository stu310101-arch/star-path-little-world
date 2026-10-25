"""Build the editable StarPath compass study and its full/low GLB exports.

Run Blender --background --factory-startup --python tools/build_recommendation_room.py.
Coordinates are Godot Y-up metres. Original objects/modifiers remain in the master;
only evaluated copies are joined for export. Existing CC0 timber textures are reused.
"""
from __future__ import annotations
import bpy
import bmesh
import json
import math
import random
import shutil
from pathlib import Path
from contextlib import contextmanager
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/RecommendationRoom'
FULL = ROOT / 'game/assets/recommendation_room'
LOW = ROOT / 'game/generated/low/recommendation'
SOURCE_TEX = ROOT / 'game/assets/counseling_room/textures'
for directory in (ART, FULL, LOW, FULL/'textures', LOW/'textures'):
    directory.mkdir(parents=True, exist_ok=True)
SCENE = bpy.context.scene
MATS, COLS, COLLIDERS = {}, {}, []
FRAME = Matrix.Identity(4)
COL = None
IS_LOW = False
RNG = random.Random(20261025)

def gv(point): return Vector((point[0], -point[2], point[1]))

def collection(name):
    global COL
    COL = bpy.data.collections.new('COL_Recommendation_'+name)
    SCENE.collection.children.link(COL)
    COLS[name] = COL

@contextmanager
def frame(point=(0,0,0), angle=0):
    global FRAME
    previous = FRAME
    FRAME = FRAME @ Matrix.Translation(gv(point)) @ Matrix.Rotation(angle,4,'Z')
    yield
    FRAME = previous

def material(key,color,rough=.6,metal=0,texture=None,emission=0):
    mat = bpy.data.materials.new('MAT_Recommendation_'+key)
    mat.diffuse_color = (*color,1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color,1)
    bsdf.inputs['Roughness'].default_value = rough
    bsdf.inputs['Metallic'].default_value = metal
    if emission:
        bsdf.inputs['Emission Color'].default_value = (*color,1)
        bsdf.inputs['Emission Strength'].default_value = emission
    if texture:
        image = bpy.data.images.load(str((LOW if IS_LOW else FULL)/'textures'/texture),check_existing=True)
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
        mix=mat.node_tree.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY'
        mix.inputs[0].default_value=1;mix.inputs[2].default_value=(*color,1)
        mat.node_tree.links.new(tex.outputs['Color'],mix.inputs[1])
        mat.node_tree.links.new(mix.outputs[0],bsdf.inputs['Base Color'])
    MATS[key]=mat

def mesh(name,points,faces,mat):
    data=bpy.data.meshes.new('MSH_'+name)
    data.from_pydata([gv(p) for p in points],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free()
    uv=data.uv_layers.new(name='UVMap')
    for polygon in data.polygons:
        major=max(range(3),key=lambda i:abs(polygon.normal[i]))
        axes=[i for i in range(3) if i!=major]
        for j in polygon.loop_indices:
            co=data.vertices[data.loops[j].vertex_index].co
            uv.data[j].uv=(co[axes[0]]/1.4,co[axes[1]]/1.4)
    obj=bpy.data.objects.new('SM_'+name,data);COL.objects.link(obj)
    obj.matrix_world=FRAME.copy();data.materials.append(MATS[mat])
    return obj

def bevel(obj,width=.012):
    mod=obj.modifiers.new('Crafted softened edges','BEVEL');mod.width=width;mod.segments=1 if IS_LOW else 3
    normal=obj.modifiers.new('Weighted surface normals','WEIGHTED_NORMAL');normal.keep_sharp=True
    return obj

def box(name,p,size,mat,edge=.012):
    x,y,z=[v/2 for v in size]
    obj=mesh(name,[(-x,-y,-z),(x,-y,-z),(x,-y,z),(-x,-y,z),(-x,y,-z),(x,y,-z),(x,y,z),(-x,y,z)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],mat)
    obj.matrix_world=FRAME@Matrix.Translation(gv(p))
    return bevel(obj,min(edge,min(size)*.3)) if edge else obj

def rounded(name,p,size,radius,mat):
    w,h,d=size;points=[];steps=3 if IS_LOW else 8
    for y in [-h/2,h/2]:
        for cx,cz,start in [(w/2-radius,d/2-radius,0),(w/2-radius,-d/2+radius,90),(-w/2+radius,-d/2+radius,180),(-w/2+radius,d/2-radius,270)]:
            for j in range(steps+1):
                a=math.radians(start+j*90/steps)
                points.append((cx+math.sin(a)*radius,y,cz+math.cos(a)*radius))
    n=len(points)//2
    obj=mesh(name,points,[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],mat)
    obj.matrix_world=FRAME@Matrix.Translation(gv(p))
    return bevel(obj,min(.012,h*.18))

def cylinder(name,p,radius,height,mat,top=None,segments=None):
    n=segments or (16 if IS_LOW else 32);top=radius if top is None else top
    points=[(math.cos(j*math.tau/n)*r,y,math.sin(j*math.tau/n)*r) for y,r in [(-height/2,radius),(height/2,top)] for j in range(n)]
    obj=mesh(name,points,[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],mat)
    obj.matrix_world=FRAME@Matrix.Translation(gv(p))
    for polygon in obj.data.polygons:polygon.use_smooth=len(polygon.vertices)==4
    return obj

def rod(name,a,b,radius,mat='brass'):
    av,bv=gv(a),gv(b)
    obj=cylinder(name,(0,0,0),radius,(bv-av).length,mat,segments=8 if IS_LOW else 12)
    obj.matrix_world=FRAME@Matrix.Translation((av+bv)/2)@(bv-av).to_track_quat('Z','Y').to_matrix().to_4x4()
    return obj

def ring(name,center,radius,tube,mat='brass',vertical=False):
    n=48 if IS_LOW else 96;m=6 if IS_LOW else 8
    points=[]
    for j in range(n):
        a=j*math.tau/n
        for k in range(m):
            b=k*math.tau/m;r=radius+math.cos(b)*tube
            local=(r*math.sin(a),r*math.cos(a),math.sin(b)*tube) if vertical else (r*math.sin(a),math.sin(b)*tube,r*math.cos(a))
            points.append(tuple(center[i]+local[i] for i in range(3)))
    faces=[(j*m+k,((j+1)%n)*m+k,((j+1)%n)*m+(k+1)%m,j*m+(k+1)%m) for j in range(n) for k in range(m)]
    obj=mesh(name,points,faces,mat)
    for poly in obj.data.polygons:poly.use_smooth=True
    return obj

def collider(name,p,size,angle=0,camera_only=False):
    COLLIDERS.append(dict(id=name,center=list(p),size=list(size),rotation_y=angle,camera_only=camera_only))

def compass(name,center,radius,vertical=False):
    def pt(x,y,depth=0):
        return (center[0]+x,center[1]+y,center[2]+depth) if vertical else (center[0]+x,center[1]+depth,center[2]+y)
    ring(name+'_Outer',center,radius,.012,'brass',vertical)
    ring(name+'_Inner',center,radius*.86,.006,'brass',vertical)
    for j in range(8):
        a=j*math.tau/8;r=radius*.74 if j%2==0 else radius*.49
        tip=(math.sin(a)*r,math.cos(a)*r)
        left=(math.sin(a-.25)*radius*.14,math.cos(a-.25)*radius*.14)
        right=(math.sin(a+.25)*radius*.14,math.cos(a+.25)*radius*.14)
        # Thin closed inlay prism; floor decoration rises under 8 mm.
        points=[pt(x,y,z) for z in [-.002,.002] for x,y in [(0,0),left,tip,right]]
        mesh(name+'_Needle'+str(j),points,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'brass' if j%2==0 else 'pale')
    for j in range(32 if IS_LOW else 64):
        a=j*math.tau/(32 if IS_LOW else 64);r0=radius*(.91 if j%4==0 else .95)
        rod(name+'_Graduation'+str(j),pt(math.sin(a)*r0,math.cos(a)*r0),pt(math.sin(a)*radius*.99,math.cos(a)*radius*.99),.003)

def book(name,p,cover='lavender',size=(.25,.05,.33),angle=0):
    with frame(p,angle):
        w,h,d=size
        for y in [-h/2,h/2]:rounded(name+'_Cover',(0,y,0),(w,.007,d),.012,cover)
        box(name+'_Pages',(.005,0,0),(w-.018,h-.009,d-.018),'paper',.003)
        box(name+'_Spine',(-w/2+.005,0,0),(.018,h+.008,d),cover,.005)
        box(name+'_Foil',(0,h/2+.004,0),(w*.5,.001,.012),'brass',0)

def tablet(name,p):
    with frame(p):
        rounded(name+'_Base',(0,.025,0),(.44,.05,.31),.07,'brass')
        rod(name+'_Support',(0,.04,-.08),(0,.25,-.08),.035,'device')
        rod(name+'_Hinge',(-.20,.27,-.08),(.20,.27,-.08),.026)
        box(name+'_Housing',(0,.48,-.06),(.85,.55,.065),'device',.025)
        box(name+'_Display',(0,.48,-.022),(.77,.47,.007),'screen',.018)
        # Abstract static diagram, never counterfeit readable controls.
        for i,width in enumerate([.43,.57,.32]):
            box(name+'_Line'+str(i),(-.05,.60-i*.09,-.017),(width,.014,.003),'pale',.001)
        box(name+'_Diagram',(.25,.40,-.015),(.10,.10,.004),'lavender',.006)

def prism(name,p,outline,height,mat):
    points=[(x,y,z) for y in [-height/2,height/2] for x,z in outline]
    n=len(outline)
    obj=mesh(name,points,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],mat)
    obj.matrix_world=FRAME@Matrix.Translation(gv(p))
    return bevel(obj,.016)

def sphere(name,p,radius,mat):
    bm=bmesh.new();bmesh.ops.create_icosphere(bm,subdivisions=1 if IS_LOW else 3,radius=radius)
    bm.verts.ensure_lookup_table();bm.faces.ensure_lookup_table()
    points=[tuple(v.co) for v in bm.verts];faces=[tuple(v.index for v in face.verts) for face in bm.faces];bm.free()
    obj=mesh(name,points,faces,mat);obj.matrix_world=FRAME@Matrix.Translation(gv(p))
    for face in obj.data.polygons:face.use_smooth=True
    return obj

def data_desk(p):
    name='DataDesk'
    with frame(p):
        # A true L-shaped writing surface and upright file return, not a reused kiosk.
        outline=[(-1.28,-1.00),(-.60,-1.00),(-.60,-.48),(1.25,-.48),(1.25,.46),(-1.28,.46)]
        prism(name+'_LWritingSurface',(0,.79,0),outline,.09,'walnut')
        box(name+'_FileCabinet',(-.94,.37,-.22),(.59,.69,1.38),'indigo',.025)
        for y in [.20,.40,.60]:
            box(name+'_Drawer',(-.94,y,.484),(.54,.17,.025),'walnut',.008)
            rod(name+'_Pull',(-1.06,y,.515),(-.82,y,.515),.009)
        # A single bent side frame leaves the writing side open.
        for z in [-.32,.32]:rod(name+'_Leg',(1.05,.74,z),(1.14,.035,z),.026)
        rod(name+'_FootRail',(1.14,.07,-.34),(1.14,.07,.34),.026)
        rounded(name+'_WritingMat',(.38,.839,.07),(1.12,.009,.60),.04,'indigo')
        rod(name+'_LaidPencil',(.66,.854,-.02),(.89,.854,.18),.006)
        # Clear working envelope: no paper, book or letter tray in front of the screen.
        tablet(name+'_Terminal',(0,.84,-.20))
    collider(name+'Body',(p[0],.43,p[2]),(2.55,.86,1.02))
    collider('DataDeskReturn',(p[0]-.95,.43,p[2]-.65),(.67,.86,.76))

def recommendation_desk(p):
    name='RecommendationDesk'
    with frame(p):
        # Broad faceted navigation table on a fluted central drum.
        outline=[(-1.55,-.25),(-1.08,-.51),(.92,-.49),(1.55,-.08),(1.36,.36),(.50,.50),(-1.08,.45),(-1.55,.18)]
        prism(name+'_ChartTable',(0,.80,0),outline,.11,'walnut')
        prism(name+'_BrassLip',(0,.734,0),[(x*.98,z*.98) for x,z in outline],.023,'brass')
        cylinder(name+'_OctagonalBase',(-.12,.09,0),.65,.15,'walnut',segments=8)
        cylinder(name+'_FlutedDrum',(-.12,.43,0),.45,.60,'indigo',segments=12)
        for j in range(12):
            angle=j*math.tau/12
            rod(name+'_DrumRib',(-.12+math.sin(angle)*.455,.15,math.cos(angle)*.455),(-.12+math.sin(angle)*.455,.71,math.cos(angle)*.455),.012)
        rounded(name+'_ChartInset',(-.67,.86,.05),(.90,.008,.57),.07,'device')
        compass(name+'_TableCompass',(-.67,.868,.05),.24)
        # A low hinged reading slate is distinct from the upright data terminal.
        with frame((-.98,.89,-.20),-.10):
            slate=box(name+'_ReadingSlate',(0,.05,0),(.46,.035,.34),'brass',.025)
            slate.matrix_world=slate.matrix_world@Matrix.Rotation(math.radians(18),4,'X')
            screen=box(name+'_SlateDisplay',(0,.074,-.012),(.40,.012,.28),'screen',.015)
            screen.matrix_world=screen.matrix_world@Matrix.Rotation(math.radians(18),4,'X')
        cylinder(name+'_OrreryStand',(.65,.93,-.11),.21,.14,'brass',segments=16)
        cylinder(name+'_OrreryColumn',(.65,1.08,-.11),.037,.27,'brass')
        sphere(name+'_OrrerySun',(.65,1.23,-.11),.084,'pale')
    collider(name+'Body',(p[0],.43,p[2]),(3.1,.86,1.02))

def animated_orrery():
    # Independent origins/hierarchy survive GLB. Static export joining skips this collection.
    collection('AnimatedInstrument')
    with frame((.65,1.23,-3.83)):
        outer=ring('OrreryOuter',(0,0,0),.40,.014)
        outer.name='OrreryOuterRing';outer.matrix_world=FRAME@Matrix.Rotation(math.radians(65),4,'X')
        inner=ring('OrreryInner',(0,0,0),.29,.012,'pale',True)
        inner.name='OrreryInnerRing';inner.matrix_world=FRAME@Matrix.Rotation(math.radians(-23),4,'Z')
        pivot=bpy.data.objects.new('OrreryOrbit',None);COL.objects.link(pivot);pivot.matrix_world=FRAME.copy();pivot.empty_display_size=.15
        for name,p,r,mat in [('OrreryPlanetA',(.34,.015,0),.045,'lavender'),('OrreryPlanetB',(-.18,-.018,.26),.029,'brass')]:
            planet=sphere(name,p,r,mat);planet.name=name
            original=planet.matrix_world.copy();planet.parent=pivot;planet.matrix_world=original

def compare_desk(p):
    name='CompareDesk'
    with frame(p):
        # Open-legged exhibition rack: three offset sloping folios across two levels.
        for x in [-1.06,1.06]:
            rod(name+'_AngledUpright',(x,.04,.36),(x,.96,-.33),.035,'walnut')
            rod(name+'_BackLeg',(x,.04,-.43),(x,.96,-.33),.035,'walnut')
            rod(name+'_Foot',(x,.045,-.48),(x,.045,.40),.022)
        box(name+'_LowerShelf',(0,.29,-.02),(2.38,.055,.66),'indigo',.025)
        box(name+'_FrontReadingLedge',(0,.75,.29),(2.55,.08,.40),'walnut',.025)
        box(name+'_UpperDisplayShelf',(.38,1.04,-.24),(1.76,.06,.42),'walnut',.02)
        for x in [-.48,1.22]:rod(name+'_TierBracket',(x,.76,-.24),(x,1.04,-.24),.017)
        for i,(x,y,z,w) in enumerate([(-.83,.86,-.12,.58),(-.02,1.14,-.23,.62),(.81,1.14,-.23,.62)]):
            with frame((x,y,z)):
                board=box(name+'_FolioFrame'+str(i),(0,0,0),(w,.035,.40),'brass',.025)
                board.matrix_world=board.matrix_world@Matrix.Rotation(math.radians(35),4,'X')
                paper=box(name+'_FolioPage'+str(i),(0,.022,-.008),(w-.055,.012,.34),'paper' if i!=1 else 'screen',.012)
                paper.matrix_world=paper.matrix_world@Matrix.Rotation(math.radians(35),4,'X')
                rod(name+'_FolioClip'+str(i),(-.09,.13,-.13),(.09,.13,-.13),.009)
        for i in range(3):book(name+'_Portfolio'+str(i),(-.72+i*.44,.36,.02),'lavender' if i%2 else 'indigo',size=(.33,.07,.40),angle=.02*i)
        box(name+'_CompareLegend',(.43,.797,.31),(.90,.004,.18),'device',.006)
        for x in [.13,.43,.73]:cylinder(name+'_ChoiceToken',(x,.807,.31),.036,.018,'brass')
    collider(name+'Body',(p[0],.62,p[2]),(2.55,1.24,1.02))

def reading_bench(p):
    name='QuietChairRight' # Retains the fixed-seat interaction identity.
    with frame(p):
        rounded(name+'_LongSeat',(0,.43,0),(2.10,.11,.73),.12,'walnut')
        for x in [-.69,0,.69]:rounded(name+'_TailoredCushion',(x,.525,0),(.64,.10,.67),.11,'lavender')
        for x in [-.87,.87]:
            box(name+'_Trestle',(x,.23,.0),(.12,.39,.59),'indigo',.02)
            rod(name+'_SideArm',(x,.73,-.27),(x,.73,.29),.032,'walnut')
            rod(name+'_ArmPost',(x,.43,-.25),(x,.73,-.25),.022)
        # Slatted back and one bolster make a different silhouette from the wing chair.
        for y in [.72,.91,1.1]:rounded(name+'_BackSlat',(0,y,.34),(2.08,.125,.065),.025,'walnut')
        for x in [-.87,.87]:box(name+'_BackPost',(x,.78,.35),(.065,.72,.07),'walnut')
        rounded(name+'_Bolster',(.72,.72,.13),(.26,.31,.47),.10,'indigo')
    collider(name,(p[0],.59,p[2]),(2.18,1.18,.90))

def chair(name,p,angle=0):
    with frame(p,angle):
        rounded(name+'_Seat',(0,.48,0),(.76,.14,.73),.18,'lavender')
        rounded(name+'_Base',(0,.385,0),(.70,.075,.65),.15,'walnut')
        n=10 if IS_LOW else 24;pts=[]
        for y,r in [(.53,.38),(1.12,.41)]:
            for j in range(n+1):
                a=math.radians(-76+j*152/n);pts.append((math.sin(a)*r,y,math.cos(a)*r-.06))
        obj=mesh(name+'_WraparoundBack',pts,[(j,j+1,j+n+2,j+n+1) for j in range(n)],'lavender')
        mod=obj.modifiers.new('Upholstered back thickness','SOLIDIFY');mod.thickness=.075
        bevel(obj,.024)
        for polygon in obj.data.polygons:polygon.use_smooth=True
        for sx in [-1,1]:
            for sz in [-1,1]:rod(name+'_TaperedLeg',(sx*.30,.04,sz*.28),(sx*.24,.39,sz*.23),.026,'walnut')
            rod(name+'_Arm',(sx*.37,.69,-.26),(sx*.39,.72,.18),.035,'walnut')
    collider(name,p=(p[0],.58,p[2]),size=(.92,1.16,.90),angle=angle)

def office_work_chair(p):
    name='DataOfficeChair'
    with frame(p):
        rounded(name+'_CushionedSeat',(0,.47,0),(.65,.12,.60),.13,'lavender')
        rounded(name+'_SeatPan',(0,.392,0),(.60,.045,.56),.12,'device')
        cylinder(name+'_LiftColumn',(0,.26,.01),.045,.30,'brass')
        cylinder(name+'_LiftCollar',(0,.17,.01),.07,.12,'device')
        for j in range(5):
            angle=j*math.tau/5
            end=(math.sin(angle)*.37,.075,math.cos(angle)*.37)
            rod(name+'_StarBase',(0,.13,.01),end,.023,'device')
            for offset in [-.025,.025]:
                wheel=cylinder(name+'_Caster',(end[0]+offset,.06,end[2]),.055,.025,'device',segments=10 if IS_LOW else 18)
                wheel.matrix_world=wheel.matrix_world@Matrix.Rotation(math.pi/2,4,'X')
        rod(name+'_BackSupport',(0,.40,.22),(0,.89,.29),.026,'device')
        back=rounded(name+'_ErgonomicBack',(0,.90,.29),(.59,.085,.56),.14,'indigo')
        back.matrix_world=back.matrix_world@Matrix.Rotation(math.pi/2,4,'X')
        pad=rounded(name+'_BackPad',(0,.90,.235),(.51,.035,.46),.11,'lavender')
        pad.matrix_world=pad.matrix_world@Matrix.Rotation(math.pi/2,4,'X')
        for x in [-.35,.35]:
            rod(name+'_ArmStem',(x,.42,.10),(x,.68,.10),.018,'device')
            rounded(name+'_ArmPad',(x,.69,-.04),(.075,.04,.37),.03,'walnut')
        rod(name+'_HeightLever',(.20,.36,0),(.37,.36,.08),.014,'brass')
    collider(name,(p[0],.62,p[2]),(.80,1.24,.86))

def instrument_stool(p):
    name='RecommendationStool'
    with frame(p):
        cylinder(name+'_RoundCushion',(0,.60,0),.30,.10,'lavender')
        cylinder(name+'_SeatRim',(0,.54,0),.31,.035,'brass')
        for j in range(4):
            angle=j*math.tau/4+math.pi/4
            rod(name+'_SplayedLeg',(math.sin(angle)*.22,.52,math.cos(angle)*.22),(math.sin(angle)*.31,.04,math.cos(angle)*.31),.026,'walnut')
        ring(name+'_FootRing',(0,.20,0),.25,.017,'brass')
        for x in [-.21,.21]:rod(name+'_LowBackPost',(x,.50,.23),(x,.90,.25),.017,'brass')
        rounded(name+'_LowBackRest',(0,.88,.27),(.52,.13,.075),.03,'walnut')
    collider(name,(p[0],.49,p[2]),(.70,.98,.70))

def comparison_wood_chair(p):
    name='CompareWoodChair'
    with frame(p):
        rounded(name+'_SaddleSeat',(0,.465,0),(.61,.07,.59),.09,'walnut')
        for x in [-.25,.25]:
            for z in [-.23,.23]:rod(name+'_TaperedLeg',(x,.44,z),(x*1.19,.035,z*1.20),.025,'walnut')
            rod(name+'_Stretcher',(x*1.1,.20,-.25),(x*1.1,.20,.25),.015,'brass')
            rod(name+'_BackPost',(x,.42,.24),(x,1.10,.29),.025,'walnut')
        rounded(name+'_TopRail',(0,1.08,.29),(.58,.11,.07),.04,'walnut')
        for x in [-.14,0,.14]:rod(name+'_BackSpindle',(x,.57,.25),(x,1.04,.29),.014,'brass')
        rounded(name+'_SmallSeatPad',(0,.514,-.015),(.49,.025,.45),.07,'indigo')
    collider(name,(p[0],.56,p[2]),(.70,1.12,.72))

def shelf(name,p,width):
    with frame(p):
        box(name+'_Back',(0,1.1,0),(width,1.55,.08),'indigo')
        for y in [.34,.88,1.47,1.89]:box(name+'_Shelf',(0,y,.18),(width+.05,.055,.44),'walnut')
        for x in [-width/2,width/2]:box(name+'_Side',(x,1.1,.15),(.06,1.64,.4),'walnut')
        for i in range(4 if IS_LOW else 8):
            x=-width*.40+i*width*.80/(3 if IS_LOW else 7)
            box(name+'_Archive'+str(i),(x,.61,.15),(.18,.46,.26),'lavender' if i%2 else 'device',.01)
            box(name+'_Label'+str(i),(x,.62,.285),(.10,.075,.004),'paper',.002)

def room_geometry():
    collection('Architecture')
    box('DarkTimberFloor',(0,-.1,0),(12,.2,10),'floor',.008)
    box('Ceiling',(0,3.58,0),(12.3,.16,10.3),'plaster')
    box('NorthWall',(0,1.75,-5.08),(12.3,3.5,.18),'indigo')
    collider('Floor',(0,-.1,0),(12,.2,10))
    collider('NorthWall',(0,1.75,-5.08),(12.3,3.5,.18))
    for x in [-6.08,6.08]:
        # True window opening: separate sill, header and end piers.
        for z,length in [(-3.95,2.1),(3.95,2.1)]:box('SidePier',(x,1.75,z),(.18,3.5,length),'plaster')
        box('WindowSillWall',(x,.48,0),(.18,.96,5.8),'plaster')
        box('WindowHeader',(x,3.2,0),(.18,.60,5.8),'plaster')
        collider('WestWall' if x<0 else 'EastWall',(x,1.75,0),(.18,3.5,10))
        for z in ([-2.9,-1.1,1.4,2.9] if x<0 else [-2.9,1.85,2.9]):box('WindowMullion',(x,1.95,z),(.24,2.0,.055),'walnut')
        for y in [1.0,2.92]:box('WindowRail',(x,y,0),(.24,.07,5.9),'walnut')
        box('WindowDeepSill',(x+(.10 if x<0 else -.10),.98,0),(.52,.09,6.0),'walnut')
        box('FrostedWindow',(x,1.96,0),(.025,1.85,5.7),'glass',0)
    for x in [-3.75,3.75]:
        box('SouthWall',(x,1.75,5.08),(4.5,3.5,.18),'plaster')
        collider('SouthWallLeft' if x<0 else 'SouthWallRight',(x,1.75,5.08),(4.5,3.5,.18))
    box('DoorHeader',(0,3.05,5.08),(3,.9,.18),'plaster')
    collider('ExitBoundary',(0,1.75,5.10),(3,3.5,.18))
    for x in [-1.5,1.5]:box('DoorJamb',(x,1.3,4.98),(.11,2.6,.26),'walnut')
    box('ExitDoor',(0,1.3,5.1),(2.95,2.6,.09),'indigo')
    for x in [-.73,.73]:box('DoorRecess',(x,1.35,5.04),(1.25,2.12,.04),'lavender')
    for x in [-.11,.11]:rod('DoorHandle',(x,1.02,4.98),(x,1.35,4.98),.018)
    for z in [-4.94,4.94]:
        box('Skirting',(0,.12,z),(11.9,.24,.08),'walnut')
        box('Cornice',(0,3.35,z),(11.9,.07,.10),'brass')
    for x in [-5.94,5.94]:
        box('Skirting',(x,.12,0),(.08,.24,9.9),'walnut')
        box('Cornice',(x,3.35,0),(.1,.07,9.9),'brass')
    # Broad coffer strips give ceiling construction without obstructing the lens.
    for z in [-3,0,3]:box('CeilingBeam',(0,3.46,z),(11.95,.08,.12),'walnut')
    collection('CompassInlay')
    compass('FloorCompass',(0,.007,.15),1.35)
    collection('NorthChart')
    box('ChartBackboard',(0,2.28,-4.92),(5.35,2.12,.08),'device',.05)
    for x in [-2.72,2.72]:box('ChartFrame',(x,2.28,-4.84),(.055,2.24,.07),'brass')
    for y in [1.16,3.40]:box('ChartFrame',(0,y,-4.84),(5.49,.055,.07),'brass')
    compass('ChartCompass',(-.32,2.25,-4.81),.70,True)
    # Original fictional constellation; no claimed astronomical coordinates.
    for side,points in [('West',[(-2.42,1.61),(-2.15,2.15),(-2.31,2.94),(-1.77,3.12),(-1.47,2.68),(-1.22,2.86)]),('East',[(.70,1.51),(1.12,1.74),(1.38,2.20),(1.87,2.31),(2.36,2.79),(2.12,3.12),(1.67,2.91)])]:
        nodes=[(x,y,-4.80) for x,y in points]
        for i,p in enumerate(nodes):
            ring('ConstellationStar'+str(side)+'_'+str(i),p,.026 if i%2 else .04,.008,'pale',True)
            if i:rod('ConstellationLink',nodes[i-1],p,.004,'brass')
    # A short plotted arc only on the east, never a mirrored chart copy.
    for i in range(12):
        angle=math.radians(-50+i*7)
        rod('ChartRouteDot',(1.48+math.sin(angle)*.65,1.73+math.cos(angle)*.51,-4.80),(1.48+math.sin(angle)*.65,1.73+math.cos(angle)*.51,-4.79),.009,'pale')
    collection('DataWorkbench');data_desk((-3.8,0,-.65))
    collection('RecommendationWorkbench');recommendation_desk((0,0,-3.72))
    collection('CompareWorkbench');compare_desk((3.8,0,-.65))
    collection('WorkChairs')
    office_work_chair((-3.8,0,.43))
    instrument_stool((-.9,0,-2.50))
    comparison_wood_chair((3.8,0,.43))
    collection('QuietSeats')
    chair('QuietChairLeft',(-4.3,0,3.4))
    reading_bench((4.3,0,3.4))
    cylinder('ReadingTableFoot',(-3.45,.04,3.5),.25,.06,'brass')
    cylinder('ReadingTableStem',(-3.45,.30,3.5),.035,.51,'brass')
    rounded('ReadingTableTop',(-3.45,.58,3.5),(.65,.07,.65),.20,'walnut')
    book('ReadingBook',(-3.45,.65,3.5),'indigo',angle=.20)
    collider('SideTableLeft',(-3.45,.32,3.5),(.69,.65,.69))
    # Tall arc reading lamp on the west, low magazine wall rail by the east bench.
    cylinder('ReadingLampBase',(-5.10,.035,3.82),.22,.06,'device')
    rod('ReadingLampStem',(-5.10,.06,3.82),(-5.10,1.62,3.82),.016)
    rod('ReadingLampOverarm',(-5.10,1.62,3.82),(-4.58,1.75,3.65),.016)
    cylinder('ReadingLampShade',(-4.58,1.69,3.65),.17,.18,'indigo',top=.105)
    for y in [.85,1.33]:box('BenchMagazineRail',(5.62,y,3.28),(.15,.055,1.18),'walnut')
    for i in range(3):box('BenchMagazine', (5.68,1.09,2.92+i*.32),(.065,.39,.25),'lavender' if i%2 else 'paper',.008)
    collection('LibraryDetails')
    shelf('WestArchiveShelf',(-4.45,.0,-4.78),2.0)
    collider('ArchiveShelfLeft',(-4.45,.98,-4.55),(2.1,2.0,.6))
    # The former screen-blocking white stack is now over three metres away on storage.
    for level in range(3):
        y=1.96+level*.095
        box('ArchiveLetterTray',(-4.90,y,-4.55),(.48,.016,.31),'brass',.005)
        box('ArchiveTrayPaper',(-4.90,y+.018,-4.55),(.42,.022,.27),'paper',.002)
    for x in [-5.15,-4.65]:rod('ArchiveTraySupport',(x,1.91,-4.68),(x,2.20,-4.68),.012)
    book('ArchivedReference',(-4.13,1.96,-4.53),'paper',size=(.38,.035,.39),angle=-.15)
    box('ArchivedLooseDocument',(-3.75,1.923,-4.53),(.26,.002,.34),'paper',0)
    # The east wall instead holds a low plan chest and overlapping pinned sample sheets.
    rounded('EastPlanChest',(4.34,.52,-4.52),(2.32,.91,.62),.055,'indigo')
    for i in range(4):
        y=.25+i*.19
        box('EastPlanDrawer',(4.34,y,-4.185),(2.20,.155,.035),'walnut',.01)
        for x in [3.65,4.98]:rod('EastDrawerPull',(x-.12,y,-4.14),(x+.12,y,-4.14),.009)
    rounded('EastPlanChestTop',(4.34,1.02,-4.51),(2.43,.065,.71),.055,'walnut')
    collider('ArchiveShelfRight',(4.34,.56,-4.52),(2.44,1.12,.72))
    for i,(x,y,w,h) in enumerate([(3.72,2.16,.68,1.42),(4.50,2.42,.57,.95),(5.05,1.90,.45,.64)]):
        box('PinnedPlanBack'+str(i),(x,y,-4.94),(w+.04,h+.04,.026),'brass',.014)
        box('PinnedPlan'+str(i),(x,y,-4.91),(w,h,.012),'paper' if i!=1 else 'lavender',.008)
        for j in range(3):box('PinnedPlanMark',(x,y+h*.22-j*.14,-4.899),(w*.65,.009,.003),'device',0)
        cylinder('PlanRoll'+str(i),(3.65+i*.42,1.10,-4.48),.065,.14,'paper')
    box('WestSconcePlate',(-3.2,2.6,-4.90),(.18,.45,.06),'brass')
    cylinder('WestSconceShade',(-3.2,2.62,-4.64),.14,.31,'pale',top=.105)
    cylinder('WestSconceDiffuser',(-3.2,2.46,-4.64),.12,.012,'light')
    rod('EastPictureLamp',(3.70,3.00,-4.72),(5.16,3.00,-4.72),.025)
    box('EastPictureLampDiffuser',(4.43,2.98,-4.72),(1.38,.025,.07),'light',.008)
    animated_orrery()

def write_layout():
    stations=[]
    for view,title,subtitle,x,z,sx,sz in [('data','我的資料與偏好','選擇興趣量表、成績與探索偏好',-2.60,.65,-3.8,-.85),('recommendations','我的推薦','理解推薦原因，探索適合的校系',.50,-2.10,0,-3.82),('compare','收藏與比較','把想進一步了解的校系放在一起',2.60,.65,3.8,-.85)]:
        stations.append(dict(view=view,title=title,subtitle=subtitle,approach=[x,.06,z],radius=1.15,sign=dict(position=[sx,1.85,sz],width=1.45,color='e9dbb8')))
    stations.append(dict(view='exit',title='返回星途',subtitle='回到原來的位置',approach=[0,.06,4.15],radius=.8,sign=dict(position=[0,2.83,4.91],rotation_y=math.pi,width=1.1,color='e9dbb8')))
    layout=dict(schemaVersion=1,revision='2026-10-25-compass-study-r3-work-seats',bounds=dict(min=[-6,0,-5],max=[6,3.5,5]),spawn=dict(position=[0,.06,2],facing=[0,0,-1]),exit=dict(position=[0,.06,4.15]),colliders=COLLIDERS,stations=stations,interactables=[],displays=[dict(view='identity',title='星圖羅盤室',sign=dict(position=[0,3.15,-4.76],width=1.8,color='f1dfb0'))])
    for view,title,body,x,y,z,stand_z in [('data','資料台工作椅','DataOfficeChair',-3.8,.52,.43,1.35),('recommendations','羅盤儀器凳','RecommendationStool',-.9,.65,-2.50,-1.40),('compare','比較台木椅','CompareWoodChair',3.8,.53,.43,1.35)]:
        layout['interactables'].append(dict(id='work_seat_'+view,kind='seat',title=title,seat_point=[x,y,z],stand_point=[x,.06,stand_z],facing=math.pi,radius=.72,collider_id=body,station_view=view))
    for side,x in [('Left',-4.3),('Right',4.3)]:
        # The delivered rest-pose mesh faces +Z; the modeled chair faces -Z.
        layout['interactables'].append(dict(id='quiet_seat_'+side.lower(),kind='seat',title='窗邊閱讀椅' if side=='Left' else '靜思長椅',seat_point=[x,.55,3.4],stand_point=[x,.06,2.35],facing=math.pi,radius=.85,collider_id='QuietChair'+side))
    for out in (FULL,LOW):(out/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf8')

def setup_materials():
    for key,color,rough,metal in [('indigo',(.075,.10,.21),.65,0),('plaster',(.57,.57,.66),.9,0),('lavender',(.32,.29,.46),.82,0),('brass',(.61,.40,.16),.38,.72),('pale',(.72,.65,.49),.66,0),('paper',(.79,.74,.61),.92,0),('ceramic',(.57,.53,.65),.28,0),('device',(.023,.032,.065),.44,0)]:material(key,color,rough,metal)
    material('walnut',(.40,.28,.22),.54,texture='joinery_base.png')
    material('floor',(.68,.56,.44),.68,texture='oak_base.png')
    material('screen',(.15,.22,.35),.48,emission=.2)
    material('glass',(.33,.46,.62),.6,emission=.35)
    material('light',(.95,.77,.46),.6,emission=.8)

def export_profile(out,budget):
    deps=bpy.context.evaluated_depsgraph_get();outputs=[];stats={};issues=[];animated=[]
    for name,col in COLS.items():
        if name=='AnimatedInstrument':
            triangles=0;bad=0
            for obj in col.objects:
                animated.append(obj)
                if obj.type!='MESH':continue
                data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
                data.calc_loop_triangles();triangles+=len(data.loop_triangles)
                bm=bmesh.new();bm.from_mesh(data);bad+=sum(not e.is_manifold for e in bm.edges);bm.free()
                if not data.uv_layers:issues.append(obj.name+': no UV')
                bpy.data.meshes.remove(data)
            stats[name]=dict(triangles=triangles,source_parts=len(animated),nonmanifold_edges=bad)
            if bad:issues.append(name+': nonmanifold '+str(bad))
            continue
        copies=[];bpy.ops.object.select_all(action='DESELECT')
        for obj in col.objects:
            if obj.type!='MESH':continue
            data=bpy.data.meshes.new_from_object(obj.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
            cp=bpy.data.objects.new('EXPORT_'+obj.name,data);SCENE.collection.objects.link(cp);cp.matrix_world=obj.matrix_world.copy();cp.select_set(True);copies.append(cp)
            if not data.uv_layers:issues.append(obj.name+': no UV')
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        result=bpy.context.object;result.name='SM_Recommendation_'+name
        bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        # Apply only to export copy; the editable source retains its stack.
        result.data.calc_loop_triangles()
        bm=bmesh.new();bm.from_mesh(result.data);bad=sum(not e.is_manifold for e in bm.edges);bm.free()
        if bad:issues.append(name+': nonmanifold '+str(bad))
        stats[name]=dict(triangles=len(result.data.loop_triangles),source_parts=len(copies),nonmanifold_edges=bad)
        outputs.append(result)
    triangles=sum(row['triangles'] for row in stats.values())
    if triangles>budget:issues.append(f'Triangle budget {triangles}/{budget}')
    if issues:raise RuntimeError('; '.join(issues))
    bpy.ops.object.select_all(action='DESELECT')
    for obj in outputs+animated:obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out/'recommendation_room.glb'),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_materials='EXPORT',export_vertex_color='NONE')
    report=dict(profile='low' if IS_LOW else 'full',triangles=triangles,budget=budget,materials=len(MATS),zones=stats,animated_nodes=[obj.name for obj in animated],issues=issues,texture_max=256 if IS_LOW else 2048,bytes=(out/'recommendation_room.glb').stat().st_size)
    for obj in outputs:bpy.data.objects.remove(obj,do_unlink=True)
    return report

def reset(low):
    global FRAME,IS_LOW
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for col in list(bpy.data.collections):bpy.data.collections.remove(col)
    MATS.clear();COLS.clear();COLLIDERS.clear();FRAME=Matrix.Identity(4);IS_LOW=low
    SCENE.unit_settings.system='METRIC'

def main():
    for name in ['joinery_base.png','oak_base.png']:
        shutil.copy2(SOURCE_TEX/name,FULL/'textures'/name)
        image=bpy.data.images.load(str(SOURCE_TEX/name),check_existing=False)
        image.scale(256,256);image.filepath_raw=str(LOW/'textures'/name);image.file_format='PNG';image.save();bpy.data.images.remove(image)
    reset(False);setup_materials();room_geometry();write_layout()
    full=export_profile(FULL,180000)
    reference=bpy.data.objects.new('REF_Human_1.75m',None);SCENE.collection.objects.link(reference);reference.empty_display_type='CUBE';reference.empty_display_size=.875;reference.location=gv((0,.875,2));reference.hide_render=True
    SCENE['art_direction']='12x10x3.5m indigo compass study; asymmetric L writing desk with clear computer access and office chair, fluted instrument table with stool, tiered comparison rack with wood chair; reading chair versus long bench; unequal wall archives and original constellation. Three stations and five actual seats, open centre.'
    SCENE['animation_contract']='OrreryOuterRing, OrreryInnerRing: independent local origins. OrreryOrbit empty owns OrreryPlanetA/B. All centered Godot (0.65,1.23,-3.83). Never join these nodes.'
    SCENE['source']='Original geometry. Existing Poly Haven wood floor and wood table 001 CC0 textures; see SOURCE_NOTES.md.'
    for im in bpy.data.images:
        if im.source=='FILE':im.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(ART/'RecommendationRoom.blend'))
    reset(True);setup_materials();room_geometry()
    low=export_profile(LOW,60000)
    (ART/'export-report.json').write_text(json.dumps(dict(full=full,low=low,blender=bpy.app.version_string,scope='Geometry/material export validation only; native rendering and walking evidence recorded separately.'),ensure_ascii=False,indent=2),encoding='utf8')
    print('RECOMMENDATION_ROOM_COMPLETE '+json.dumps(dict(full=full,low=low)),flush=True)

if __name__=='__main__':main()
