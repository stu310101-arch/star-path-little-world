"""Editable, metre-scale vessel kit. Run with Blender 5.2 --background --python.

Blender -Y is the bow, exported Godot +Z is the bow. Origin is the waterline.
Source meshes/modifiers remain editable; only export copies are evaluated/joined.
"""
from pathlib import Path
import bpy, math, json, bmesh
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art' / 'Vessels'
OUT = ROOT / 'game' / 'assets' / 'vessels'
PREVIEW = ROOT / 'deliverables' / 'vessels'
for folder in (ART, OUT, PREVIEW): folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
materials = {}

def mat(name, hex_color, rough=.5, metal=0):
    def linear(v): return v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4
    color = tuple(linear(int(hex_color[i:i+2],16)/255) for i in (0,2,4))
    m=bpy.data.materials.new('MAT_Vessel_'+name); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    m.diffuse_color=(*color,1); materials[name]=m; return m

NAVY=mat('AtlanticPaint','354b59',.44)
CREAM=mat('WarmEnamel','d7d5c8',.44)
RED=mat('Antifouling','673a34',.82)
DECK=mat('NonSlipDeck','596260',.87)
METAL=mat('DarkGalvanized','4b5252',.36,.72)
GLASS=mat('MarineGlazing','263d45',.16,.2)
WOOD=mat('OiledTeak','8d7960',.66)
RUBBER=mat('RubberFender','202728',.87)
OCHRE=mat('SafetyOchre','c5904f',.53)
GREEN=mat('NavigationGreen','4d806c',.33)
REDLIGHT=mat('NavigationRed','a65347',.33)

active_col=None; parts=[]
def register(obj,name,material=None):
    obj.name='SM_'+name
    for c in list(obj.users_collection): c.objects.unlink(obj)
    active_col.objects.link(obj); parts.append(obj)
    if material: obj.data.materials.append(material)
    return obj

def mesh(name, verts, faces, material, smooth=False, indices=None):
    data=bpy.data.meshes.new(name); data.from_pydata(verts,[],faces); data.update()
    obj=bpy.data.objects.new('SM_'+name,data); active_col.objects.link(obj); parts.append(obj)
    for m in material if isinstance(material,list) else [material]: data.materials.append(m)
    for i,p in enumerate(data.polygons):
        p.use_smooth=smooth
        if indices: p.material_index=indices[i]
    bm=bmesh.new(); bm.from_mesh(data); bmesh.ops.recalc_face_normals(bm,faces=bm.faces); bm.to_mesh(data); bm.free()
    return obj

def box(name, pos, size, material, bevel=.015):
    bpy.ops.mesh.primitive_cube_add(size=1,location=pos); o=register(bpy.context.object,name,material)
    o.dimensions=size; bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        m=o.modifiers.new('Manufactured edge radius','BEVEL'); m.width=bevel; m.segments=2
        n=o.modifiers.new('Area weighted face normals','WEIGHTED_NORMAL'); n.keep_sharp=True
    return o

def beam(name,a,b,r,material,segments=10):
    a,b=Vector(a),Vector(b); delta=b-a
    bpy.ops.mesh.primitive_cylinder_add(vertices=segments,radius=r,depth=delta.length,location=(a+b)*.5)
    o=register(bpy.context.object,name,material); o.rotation_mode='QUATERNION'; o.rotation_quaternion=delta.to_track_quat('Z','Y')
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    return o

def torus(name,pos,major,minor,material,rot=(0,0,0),major_segments=32,minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(major_segments=major_segments,minor_segments=minor_segments,location=pos,rotation=rot,major_radius=major,minor_radius=minor)
    o=register(bpy.context.object,name,material)
    for p in o.data.polygons:p.use_smooth=True
    return o

def tube_path(name, points, r, material, segments=8):
    verts=[]; faces=[]
    for i,p in enumerate(points):
        p=Vector(p); d=Vector(points[min(i+1,len(points)-1)])-Vector(points[max(0,i-1)])
        d.normalize(); x=d.cross(Vector((0,0,1)))
        if x.length<.01:x=d.cross(Vector((0,1,0)))
        x.normalize(); z=x.cross(d).normalized()
        for k in range(segments):
            a=math.tau*k/segments; verts.append(p+r*(x*math.cos(a)+z*math.sin(a)))
        if i:
            for k in range(segments):faces.append(((i-1)*segments+k,(i-1)*segments+(k+1)%segments,i*segments+(k+1)%segments,i*segments+k))
    return mesh(name,verts,faces,material,True)

def hull(name,L,B,draft,freeboard,paint=NAVY):
    # Continuous loft: rounded bilges, flared topsides, fine bow and broad stern.
    stations=33; verts=[]; faces=[]; mids=[]; edges=[[],[]]
    for j in range(stations):
        t=j/(stations-1); y=L*(.5-t)
        width=B*.5*(.73+.27*math.sin(math.pi*min(t/.68,1)/2))
        if t>.60:width*=max(.018,1-((t-.60)/.4)**2.45)
        sheer=freeboard+.18*freeboard*(max(0,(t-.62)/.38)**2)+.055*freeboard*(1-t)**3
        # Clockwise around the section, starting at starboard gunwale.
        ring=[(1,sheer),(.995,freeboard*.56),(.93,.12),(.89,-.10),(.72,-draft*.55),(.40,-draft*.91),(.10,-draft),(-.10,-draft),(-.40,-draft*.91),(-.72,-draft*.55),(-.89,-.10),(-.93,.12),(-.995,freeboard*.56),(-1,sheer)]
        for x,z in ring:verts.append((x*width,y,z))
        edges[0].append((width,y,sheer)); edges[1].append((-width,y,sheer))
        if j:
            for k in range(len(ring)-1):
                faces.append(((j-1)*14+k,(j-1)*14+k+1,j*14+k+1,j*14+k))
                mids.append(0 if k in (0,1,11,12) else 1 if k in (2,10) else 2)
    faces.append(tuple(reversed(range(14)))); mids.append(0)
    faces.append(tuple((stations-1)*14+k for k in range(14))); mids.append(0)
    hull_obj=mesh(name+'_LoftedHull',verts,faces,[paint,RUBBER,RED],True,mids)
    hull_obj['design']='waterline origin, curved station loft, closed bow/stern, separated boot top and antifouling'
    deckverts=[]; deckfaces=[]
    for i in range(stations):deckverts.extend([edges[0][i],edges[1][i]])
    for i in range(stations-1):deckfaces.append((2*i,2*i+1,2*i+3,2*i+2))
    mesh(name+'_CamberedDeck',deckverts,deckfaces,DECK)
    for side in range(2):
        tube_path(name+'_RubRail',[(p[0]*1.015,p[1],p[2]-.08) for p in edges[side]],.055 if L<10 else .12,RUBBER)
    return edges

def railing(name, edges, height, radius=.025, post_every=3, start=0,end=None):
    for side,edge in enumerate(edges):
        p=edge[start:end]
        tube_path(name+'_TopRail'+str(side),[(x,y,z+height) for x,y,z in p],radius,CREAM)
        tube_path(name+'_MidRail'+str(side),[(x,y,z+height*.50) for x,y,z in p],radius*.72,METAL)
        for i,(x,y,z) in enumerate(p):
            if i%post_every==0 or i==len(p)-1:beam(name+'_Stanchion',(x,y,z),(x,y,z+height),radius,METAL)

def cabin(name, center, width, length, height, side_windows=3, front_windows=3, paint=CREAM, rake=.16):
    x,y,z=center; hx=width/2; hy=length/2
    # Narrowed upper corners and a raked windshield, with real open window bays.
    low=[Vector((x-hx,y-hy,z)),Vector((x+hx,y-hy,z)),Vector((x+hx,y+hy,z)),Vector((x-hx,y+hy,z))]
    high=[Vector((x-hx*.91,y-hy+rake,z+height)),Vector((x+hx*.91,y-hy+rake,z+height)),Vector((x+hx*.91,y+hy-rake*.3,z+height)),Vector((x-hx*.91,y+hy-rake*.3,z+height))]
    win0=.38; win1=.84
    for face in range(4):
        a=face;b=(face+1)%4
        def p(u,v):return low[a].lerp(low[b],u).lerp(high[a].lerp(high[b],u),v)
        normal=(low[b]-low[a]).cross(high[a]-low[a]).normalized()
        cols=side_windows if face in (1,3) else front_windows
        mesh(name+'_Header',[p(0,win1),p(1,win1),p(1,1),p(0,1)],[(0,1,2,3)],paint)
        for k in range(cols):
            u0=k/cols; u1=(k+1)/cols
            # Mullion widths are measured in metres, never fractions of an
            # entire 24 m saloon wall (which previously made pinhole windows).
            margin=min(.08/(low[b]-low[a]).length,.20/cols)
            door=face==2 and k==cols//2
            sill=.045 if door else win0
            mesh(name+'_Sill', [p(u0,0),p(u1,0),p(u1,sill),p(u0,sill)],[(0,1,2,3)],paint)
            gl=[p(u0+margin,sill+.025),p(u1-margin,sill+.025),p(u1-margin,win1-.025),p(u0+margin,win1-.025)]
            mesh(name+'_RecessedGlass',[q-normal*.028 for q in gl],[(0,1,2,3)],GLASS)
            for i in range(4):beam(name+'_WindowGasket',gl[i],gl[(i+1)%4],.027 if length<10 else .04,RUBBER,8)
            mesh(name+'_WindowPillar',[p(u0,sill),p(u0+margin,sill),p(u0+margin,win1),p(u0,win1)],[(0,1,2,3)],paint)
            mesh(name+'_WindowPillar',[p(u1-margin,sill),p(u1,sill),p(u1,win1),p(u1-margin,win1)],[(0,1,2,3)],paint)
            if door:
                beam(name+'_DoorHandle',p(u1-margin*2,.37)+normal*.06,p(u1-margin*2,.48)+normal*.06,.021,METAL)
    mesh(name+'_Roof',high,[(0,1,2,3)],paint)
    for i in range(4):beam(name+'_RoofEdge',high[i],high[(i+1)%4],.05,paint)
    return high

def cleat(name,pos,scale=1):
    x,y,z=pos;box(name+'_Foot',(x,y,z),(.22*scale,.3*scale,.05*scale),METAL,.008)
    beam(name+'_Stem',(x,y,z),(x,y,z+.13*scale),.038*scale,METAL)
    beam(name+'_Horns',(x-.21*scale,y,z+.14*scale),(x+.21*scale,y,z+.14*scale),.032*scale,METAL)

def coil(name,pos,r=.23):
    x,y,z=pos
    for i in range(4):torus(name,(x,y,z+i*.012),r-i*.03,.018,WOOD,major_segments=32,minor_segments=6)

def ring(name,pos,rot=(math.pi/2,0,0),r=.32):
    o=torus(name,pos,r,.07,OCHRE,rot,32,8);o.data.materials.append(CREAM)
    for p in o.data.polygons:
        a=math.atan2(p.center.y,p.center.x)
        if int((a+math.pi)*8/math.tau)%2==0:p.material_index=1

def fender(name,pos,length=.55,r=.12):
    x,y,z=pos
    beam(name,(x,y,z-length/2),(x,y,z+length/2),r,RUBBER,12)
    for zz in (z-length/2,z+length/2):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=12,ring_count=6,radius=r,location=(x,y,zz));o=register(bpy.context.object,name+'_RoundedCap',RUBBER)
        for p in o.data.polygons:p.use_smooth=True
    beam(name+'_Lanyard',(x,y,z+length/2+r),(x*.95,y,z+length/2+.4),.012,WOOD,6)

def ladder(name,x,y,z,height):
    for dx in (-.22,.22):beam(name+'_Side',(x+dx,y,z),(x+dx,y,z+height),.025,METAL)
    for i in range(int(height/.25)+1):beam(name+'_Rung',(x-.22,y,z+i*.25),(x+.22,y,z+i*.25),.018,METAL,8)

def louver(name,center,width,height,count=7):
    x,y,z=center;box(name+'_VentRecess',(x,y,z),(width,.03,height),RUBBER,.01)
    for i in range(count):box(name+'_VentSlat',(x,y-.023,z-height/2+(i+.5)*height/count),(width*.94,.055,height/count*.23),METAL,.004)

def mast(name,x,y,z,height):
    beam(name+'_Mast',(x,y,z),(x,y,z+height),.035,METAL)
    beam(name+'_RadarArm',(x-.55,y,z+height*.7),(x+.55,y,z+height*.7),.03,CREAM)
    box(name+'_Radar',(x,y,z+height*.72),(.8,.16,.08),CREAM,.035)
    beam(name+'_Whip',(x+.3,y,z+height*.7),(x+.3,y,z+height+.55),.009,METAL,6)
    beam(name+'_NavLamp',(x,y,z+height),(x,y,z+height+.12),.07,CREAM,12)

def winch(name,center,size=1):
    x,y,z=center
    box(name+'_Base',(x,y,z),(.85*size,.68*size,.12*size),METAL,.04)
    for dx in (-.34,.34):box(name+'_Bearing',(x+dx*size,y,z+.27*size),(.1*size,.48*size,.42*size),NAVY,.04)
    beam(name+'_RopeDrum',(x-.26*size,y,z+.39*size),(x+.26*size,y,z+.39*size),.22*size,WOOD,24)
    for i in range(8):torus(name+'_RopeTurns',(x+(-.22+i*.063)*size,y,z+.39*size),.223*size,.019*size,WOOD,(0,math.pi/2,0),24,6)

def nameplate(text,pos,size,rot):
    bpy.ops.object.text_add(location=pos,rotation=rot);o=register(bpy.context.object,'HullRegistration_'+text,CREAM)
    o.data.body=text;o.data.size=size;o.data.extrude=.001;o.data.align_x='CENTER';o.data.resolution_u=4

def fishing():
    edges=hull('HarborLaunch',7.8,2.72,.64,.72)
    railing('LaunchGuard',edges,.76,.023,4,0,30)
    cabin('Wheelhouse',(0,-.64,.76),1.96,2.17,1.93,2,2,rake=.27)
    box('CabinRoofSunVisor',(0,-.77,2.72),(2.24,2.65,.10),CREAM,.065)
    # Aft working deck: teak slats, hatch, winch and clear circulation.
    for i in range(12):box('AftTeakPlank',(-1.02+i*.185,1.68,.747),(.177,2.73,.035),WOOD,.004)
    box('EngineAccessHatch',(0,1.42,.79),(1.1,.77,.05),DECK,.025)
    for x in (-.38,.38):beam('HatchHandle',(x,1.35,.83),(x,1.55,.83),.014,METAL,8)
    winch('HaulingWinch',(0,2.60,.79),.85)
    for x in (-1.04,1.04):
        beam('AftWorkFrame',(x,2.35,.76),(x,2.35,2.3),.038,METAL)
    beam('AftWorkFrameCross',(-1.04,2.35,2.3),(1.04,2.35,2.3),.038,METAL)
    for x in (-1,1):
        for y in (-1.5,.25,2.6):fender('HangingFender',(x*1.37,y,.59),.48,.11)
        cleat('SternCleat',(x*.92,3.24,.78),.8)
        beam('RunningLightHousing',(x*1.02,-1.2,2.1),(x*1.09,-1.2,2.1),.055,GREEN if x>0 else REDLIGHT,12)
    cleat('BowCleat',(0,-3.10,.86));coil('ForedeckRope',(.45,-2.43,.79),.21)
    box('OutboardCowling',(0,3.96,.56),(.64,.66,.74),METAL,.11)
    box('OutboardShaft',(0,4.05,-.18),(.15,.25,.85),METAL,.025)
    beam('PropellerHub',(0,3.88,-.57),(0,4.2,-.57),.095,METAL,16)
    for a in range(3):
        ang=a*math.tau/3
        blade=box('PropellerBlade',(.17*math.cos(ang),4.10,-.57+.17*math.sin(ang)),(.32,.04,.1),METAL,.018);blade.rotation_euler.y=-ang
    ring('PortLifering',(-1.035,-.0,1.95),(0,math.pi/2,0),.27)
    mast('LaunchRadio',0,-.2,2.80,1.02)
    louver('CabinIntake',(0,.46,1.08),.64,.35,6)
    nameplate('KAI 07',(1.365,-.3,.34),.19,(math.pi/2,0,math.pi/2))

def tug():
    edges=hull('HarborTug',17.0,6.1,1.7,1.55,NAVY)
    for side in range(2):tube_path('HeavyRubberPushFender',[(x*1.025,y,z-.3) for x,y,z in edges[side]],.23,RUBBER,12)
    railing('TugGuard',edges,.99,.036,3,0,30)
    cabin('EngineHouse',(0,.4,1.6),4.35,7.3,1.8,5,3,rake=.1)
    cabin('RaisedBridge',(0,-1.94,3.48),4.5,3.62,1.96,3,4,rake=.42)
    box('BridgeWingRoof',(0,-1.91,5.48),(4.97,4.02,.16),CREAM,.085)
    for x in (-1.34,1.34):
        box('ExhaustFunnel',(x,2.48,4.3),(.93,1.25,2.35),OCHRE,.16)
        box('FunnelCowl',(x,2.54,5.48),(1.06,1.36,.32),METAL,.07)
        louver('EngineRoomVent',(x,4.075,2.6),.87,1.2,12)
    winch('AftTowingWinch',(0,5.4,1.65),2.15)
    for x in (-1.05,1.05):
        beam('TowingBitt',(x,6.85,1.65),(x,6.85,2.33),.18,METAL,16)
        beam('TowingBittHorn',(x-.31,6.85,2.3),(x+.31,6.85,2.3),.14,METAL,16)
    coil('HeavyMooringCoil',(1.85,5.6,1.69),.45)
    for x in (-2.5,2.5):
        for y in (-4.9,5.0):cleat('TugMooringBollard',(x,y,1.66),1.55)
        ring('TugLifering',(x*.90,.55,3.09),(0,math.pi/2,0),.38)
        for y in (-3.8,-.6,2.8,5.4):fender('TugSideFender',(x*1.24,y,1.25),.72,.19)
    ladder('BridgeAccessLadder',-2.27,1.1,1.65,1.95)
    mast('TugRadar',0,-.7,5.60,1.85)
    box('ForedeckLocker',(0,-6.0,1.7),(1.5,1.04,.48),DECK,.09)
    nameplate('TUG 03',(3.055,-1.4,.79),.37,(math.pi/2,0,math.pi/2))

def ferry():
    edges=hull('CoastalFerry',36.0,9.8,2.45,2.57,NAVY)
    railing('MainDeckGuard',edges,1.05,.037,2,0,31)
    cabin('PassengerSaloon',(0,1.8,2.62),8.44,23.8,2.43,17,5,rake=.8)
    box('PromenadeDeckSlab',(0,1.55,5.12),(8.95,25.35,.18),CREAM,.1)
    cabin('UpperSaloon',(0,1.38,5.24),7.45,17.45,2.13,12,5,rake=.75)
    cabin('NavigationBridge',(0,-9.0,5.24),7.66,4.98,2.17,3,6,rake=.94)
    box('BridgeSunVisor',(0,-9.29,7.48),(8.33,5.3,.16),CREAM,.085)
    box('UpperSunDeck',(0,1.25,7.43),(7.8,18.2,.16),CREAM,.07)
    # Broad rear promenade with teak inlays and real passenger-height railings.
    for x in (-4.35,4.35):
        tube_path('PromenadeTopRail',[(x,y,6.24) for y in (-10.8,-4,4,12.3)],.033,METAL)
        tube_path('PromenadeMidRail',[(x,y,5.74) for y in (-10.8,-4,4,12.3)],.022,METAL)
        for k in range(19):beam('PromenadeStanchion',(x,-10.8+k*1.28,5.22),(x,-10.8+k*1.28,6.24),.027,METAL)
    for row in range(2):
        y=14.9+row*1.3
        for x in (-1.9,0,1.9):
            for dx in (-.54,.54):box('DeckBenchLeg',(x+dx,y,2.89),(.08,.46,.60),METAL,.015)
            for j in range(4):box('DeckBenchTeak',(x,y-.19+j*.12,3.22),(1.42,.095,.07),WOOD,.01)
            box('DeckBenchBack',(x,y+.25,3.49),(1.42,.07,.40),WOOD,.02)
    # Companionways connect both passenger decks; the aft seating stays
    # outside the enclosed saloon and clear of these circulation aisles.
    for x in (-3.65,3.65):
        for i in range(12):
            top=2.65+(i+1)*.214
            box('CompanionwayTread',(x,16.55-i*.235,top-.065),(.66,.25,.13),DECK,.008)
        for dx in (-.31,.31):
            beam('StairStringer',(x+dx,16.7,2.6),(x+dx,13.9,5.18),.052,METAL)
            beam('StairHandrail',(x+dx,16.7,3.58),(x+dx,13.9,6.17),.032,CREAM)
            for i in (0,5,11):
                y=16.55-i*.235;z=2.65+(i+1)*.214
                beam('StairBaluster',(x+dx,y,z),(x+dx,y,z+.95),.024,METAL)
    for x in (-1.45,1.45):
        funnel=box('SweptFerryFunnel',(x,5.7,8.27),(1.34,2.42,2.0),OCHRE,.18);funnel.rotation_euler.x=math.radians(-12)
        cap=box('FunnelDarkCap',(x,5.87,9.21),(1.4,2.47,.35),METAL,.09);cap.rotation_euler.x=math.radians(-12)
    for x in (-3.85,3.85):
        for y in (4.0,8.2):
            # Covered rescue floats in rigid cradles, not decorative floating pods.
            for dy in (-.58,.58):box('LiferaftCradle',(x,y+dy,7.64),(.62,.14,.21),METAL,.03)
            beam('LiferaftCanister',(x,y-.57,7.99),(x,y+.57,7.99),.32,CREAM,20)
        ring('FerryLifering',(x,11.7,5.99),(0,math.pi/2,0),.35)
    mast('FerryNavigation',0,-7.7,7.59,2.6)
    for x in (-3.5,3.5):
        cleat('FerryBowBollard',(x,-10.9,2.79),2)
        cleat('FerrySternBollard',(x,16.0,2.64),2)
    box('BowAnchorWindlass',(0,-13.95,2.9),(1.7,1.3,.6),METAL,.12)
    for y in (-14.8,-13.1):beam('AnchorChain',(0,y,2.77),(0,y+.75,2.77),.04,METAL,10)
    nameplate('NORTHLINE',(4.93,2.0,1.45),.64,(math.pi/2,0,math.pi/2))

def export_asset(asset, objects):
    copies=[]; deps=bpy.context.evaluated_depsgraph_get()
    for o in objects:
        if o.type not in {'MESH','FONT'}:continue
        evaluated=o.evaluated_get(deps)
        data=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=True,depsgraph=deps)
        copy=bpy.data.objects.new(o.name+'_EXPORT',data);scene.collection.objects.link(copy);copy.matrix_world=o.matrix_world.copy();copies.append(copy)
    bpy.ops.object.select_all(action='DESELECT')
    for o in copies:o.select_set(True)
    bpy.context.view_layer.objects.active=copies[0];bpy.ops.object.join();joined=copies[0];joined.name='SM_'+asset
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bm=bmesh.new();bm.from_mesh(joined.data);bmesh.ops.remove_doubles(bm,verts=bm.verts,dist=.00003);bm.to_mesh(joined.data);bm.free()
    joined.data.calc_loop_triangles(); triangles=len(joined.data.loop_triangles)
    bounds=[Vector(v) for v in joined.bound_box];minimum=Vector(tuple(min(v[i] for v in bounds) for i in range(3)));maximum=Vector(tuple(max(v[i] for v in bounds) for i in range(3)))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(asset+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,export_materials='EXPORT')
    bpy.data.objects.remove(joined,do_unlink=True)
    return {'triangles':triangles,'source_objects':len(objects),'dimensions_m':list(maximum-minimum),'origin':'waterline, centered plan; Godot +Z bow','materials':sorted(set(m.name for o in objects if o.type in {'MESH','FONT'} for m in o.data.materials))}

assets={};manifest={}
for asset,fn in [('fishing_boat',fishing),('tugboat',tug),('liner',ferry)]:
    active_col=bpy.data.collections.new('COL_'+asset);scene.collection.children.link(active_col);parts=[];fn()
    assets[asset]=(active_col,parts[:]);manifest[asset]=export_asset(asset,parts)
assert sum(row['triangles'] for row in manifest.values())<100000,manifest
manifest['total_triangles']=sum(row['triangles'] for row in manifest.values())
(ART/'validation.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')

# Studio look-development uses the exact source objects and PBR materials.
studio=bpy.data.collections.new('COL_Reference_Studio');scene.collection.children.link(studio);active_col=studio;parts=[]
water=mat('PreviewWater','42646f',.23,.35)
box('PreviewWater',(0,0,-.07),(2000,2000,.08),water,0)
scene.world.color=(.18,.22,.26);scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value=(.48,.59,.68,1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45
bpy.ops.object.light_add(type='SUN',location=(10,-10,20));sun=bpy.context.object;sun.name='StudioSun';sun.data.energy=2.2;sun.data.angle=.07;sun.rotation_euler=(math.radians(26),math.radians(-23),math.radians(-26))
bpy.ops.object.light_add(type='AREA',location=(-10,-6,15));fill=bpy.context.object;fill.name='StudioSoftbox';fill.data.energy=2400;fill.data.shape='DISK';fill.data.size=12
fill.rotation_euler=(Vector((0,0,2))-fill.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;scene.camera=cam;cam.data.type='ORTHO';cam.data.lens=45
scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=True
scene.render.resolution_x=1536;scene.render.resolution_y=1024;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
for asset,(col,objs) in assets.items():
    for other,(other_col,_) in assets.items():other_col.hide_render=other!=asset
    L={'fishing_boat':7.8,'tugboat':17,'liner':36}[asset]
    target=Vector((0,0,L*.085));cam.location=(L*.87,-L*.98,L*.65);cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=L*1.37
    scene.render.filepath=str(PREVIEW/(asset+'-blender.png'))
    bpy.ops.render.render(write_still=True)
for asset,(col,objects) in assets.items():
    col.hide_render=False
    # Source collection layout: three separate editable vessels, not an
    # overlapping pile. Export copies above retain the waterline origin.
    offset={'fishing_boat':-23,'tugboat':-9,'liner':12}[asset]
    for obj in objects:obj.location.x+=offset
    col['export_layout_offset_x']=offset
studio.hide_viewport=True;studio.hide_render=True
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'vessels-source.blend'))
print('VESSEL_BUILD_OK '+json.dumps(manifest))
