"""Career forum: a modern glazed work terrace with timber-lined steel canopies.

The eight devices flank a generous level central walk. Planting, lounge
furniture, glazing and skyline silhouettes are kept in perimeter pockets.
Executed in the parent's active Blender collection and local frame.
"""
import math

ZONE_CONTROL = (0, .06, 10.2)
ZONE_SIGN = (0, 1.7, 10.0)
ZONE_SLOTS = [
    {"position": [side*3.35,.02,z], "rotation_y": -side*math.pi/2}
    for z in (7.25,3.4,-.45,-4.3) for side in (-1,1)
]

_career_instances={}
def career_bar(name,p,size,mat,edge=.008):
    key=(tuple(size),mat,edge)
    if key not in _career_instances:
        _career_instances[key]=box(name,p,size,mat,edge)
        return _career_instances[key]
    ob=_career_instances[key].copy()
    ob.data=_career_instances[key].data
    ob.name='SM_'+name
    COL.objects.link(ob)
    ob.matrix_world=FRAME @ Matrix.Translation(gv(p))
    return ob

def career_grasses(name,p,scale=1):
    points,faces=[],[]
    for i in range(52):
        a=i*2.39996; r=.46*math.sqrt((i+.5)/52)*scale
        x,z=p[0]+math.cos(a)*r,p[2]+math.sin(a)*r
        h=(.45+.46*((i*7)%17)/17)*scale
        dx,dz=math.cos(a)*h*.35,math.sin(a)*h*.35
        width=.018*scale
        sx,sz=math.cos(a+math.pi/2)*width,math.sin(a+math.pi/2)*width
        k=len(points)
        points += [(x-sx,p[1],z-sz),(x+sx,p[1],z+sz),
                   (x+dx*.40+sx,p[1]+h*.70,z+dz*.40+sz),
                   (x+dx*.40-sx,p[1]+h*.70,z+dz*.40-sz),(x+dx,p[1]+h,z+dz)]
        faces += [(k,k+1,k+2,k+3),(k+3,k+2,k+4)]
        if i%9==0:
            rod(name+'_SeedStem',(x,p[1],z),(x+dx*.6,p[1]+h*1.12,z+dz*.6),.008*scale,'sand',6)
            rod(name+'_SeedHead',(x+dx*.6,p[1]+h*.94,z+dz*.6),(x+dx*.6,p[1]+h*1.15,z+dz*.6),.029*scale,'sand',7)
    mesh(name+'_Blades',points,faces,'sage')

def career_chair(name,p,yaw=0):
    with frame(p,yaw):
        for x in (-.43,.43):
            for z in (-.36,.36): career_bar(name+'_Leg',(x,.225,z),(.045,.45,.045),'steel')
            career_bar(name+'_Arm',(x,.67,.01),(.08,.07,.93),'oak',.014)
            career_bar(name+'_ArmSupport',(x,.50,.36),(.045,.34,.045),'steel')
        round_box(name+'_Seat',(0,.48,0),(.92,.15,.84),.06,'teal')
        with frame((0,.79,-.38),tilt=math.radians(-8)):
            round_box(name+'_Back',(0,0,0),(.92,.55,.16),.04,'teal')
        career_bar(name+'_UnderSeat',(0,.37,0),(.95,.05,.87),'oak')
        collision(name+'_Proxy',(0,.49,0),(1.02,.98,1.02))

def career_table(name,p):
    with frame(p):
        cylinder(name+'_Base',(0,.045,0),.29,.09,'steel',segments=20)
        cylinder(name+'_Stem',(0,.25,0),.035,.43,'steel',segments=12)
        round_box(name+'_Top',(0,.49,0),(.80,.055,.80),.07,'oak')
        collision(name+'_Proxy',(0,.26,0),(.80,.52,.80))

# Monolithic, pale concrete paving with a rectilinear expansion-joint grid.
district_floor('Career_TerraceSlab',(0,-.13,0),(28,.26,24),'concrete',2)
collision('Career_LevelFloor',(0,-.16,0),(28,.32,24))
for x in (-12,-9,-6,-3,0,3,6,9,12):
    career_bar('Career_PavingJointX',(x,.003,0),(.014,.006,23.7),'slate',0)
for z in (-10,-7.5,-5,-2.5,0,2.5,5,7.5,10):
    career_bar('Career_PavingJointZ',(0,.003,z),(27.7,.006,.014),'slate',0)
for x in (-4.75,4.75):
    box('Career_DrainGrate',(x,.008,0),(.15,.016,20.5),'steel',.003)
    for i in range(68): career_bar('Career_DrainSlot',(x,.018,-10.05+i*.30),(.155,.006,.024),'concrete',0)

# Long glazed workplace edge; the canopy is a real structural rhythm with an
# inset timber soffit, not a row of unrelated pergola blocks.
box('Career_FacadePlinth',(-13.15,.20,-.2),(.50,.40,20.4),'concrete',.02)
box('Career_FacadeBack',(-13.69,2.1,-.2),(.20,3.9,20.4),'slate',.012)
for i in range(9):
    z=-9.2+i*2.25
    box('Career_GlassPanel',(-13.02,2.10,z),(.035,3.42,2.15),'glass',0)
    career_bar('Career_WindowMullion',(-12.96,2.10,z-1.10),(.10,3.66,.075),'steel')
    # Warm interior reveals help glass read as glazing rather than a black wall.
    box('Career_InteriorLight',(-13.50,3.45,z),(.025,.055,1.55),'paper',.003)
for y in (.38,2.6,3.84): box('Career_FacadeTransom',(-12.96,y,-.2),(.12,.075,20.4),'steel')
collision('Career_GlazingWall',(-13.12,2.0,-.2),(.30,4.0,20.4))

box('Career_CanopyRoof',(-8.95,4.17,-.2),(8.95,.25,20.8),'steel',.025)
box('Career_CanopyUpperCap',(-8.95,4.31,-.2),(9.05,.06,20.9),'roof',.015)
box('Career_CanopySoffit',(-8.95,4.015,-.2),(8.60,.055,20.35),'oak',.008)
for i in range(42):
    z=-10.15+i*.49
    career_bar('Career_SoffitLinearJoint',(-8.95,3.982,z),(8.55,.009,.012),'walnut',0)
for z in (-9.7,-3.4,3.1,9.6):
    box('Career_CanopyColumn',(-4.65,2.0,z),(.22,4.0,.22),'steel',.02)
    box('Career_ColumnBase',(-4.65,.055,z),(.42,.11,.42),'concrete',.025)
    collision('Career_CanopyColumnProxy',(-4.65,2.0,z),(.25,4.0,.25))
    box('Career_CanopyCrossBeam',(-8.95,3.87,z),(8.70,.23,.16),'steel',.015)
for z in (-6.5,.0,6.5):
    box('Career_LinearLight',(-8.20,3.977,z),(3.15,.024,.038),'paper',.008)

# Open-sided second shelter anchors the far side without closing the sky.
box('Career_EastCanopy',(9.1,3.66,-5.6),(5.8,.20,7.4),'steel',.025)
box('Career_EastSoffit',(9.1,3.54,-5.6),(5.55,.045,7.15),'oak',.008)
for x in (6.35,11.85):
    for z in (-9.05,-2.15):
        box('Career_EastColumn',(x,1.77,z),(.16,3.54,.16),'steel',.016)
        collision('Career_EastColumnProxy',(x,1.77,z),(.20,3.54,.20))
for z in (-7.6,-4.0): box('Career_EastLight',(9.1,3.507,z),(2.0,.025,.04),'paper',.007)

# Grouped concrete planters and ornamental grasses keep the palette controlled.
for name,p,size in [('EntryEast',(9.05,0,8.6),(7.2,.68,2.25)),
                    ('MidEast',(10.0,0,2.0),(5.2,.68,2.2)),
                    ('WestEntry',(-8.8,0,10.1),(6.5,.60,1.25)),
                    ('Rear',(.8,0,-9.35),(9.5,.62,1.35))]:
    planter('Career_'+name,p,size,mat='concrete')
    collision('Career_'+name+'_Proxy',(p[0],size[1]/2,p[2]),size)
    for i in range(max(2,int(size[0]/1.2))):
        x=p[0]-size[0]/2+.65+i*1.1
        career_grasses('Career_'+name+'_Grass'+str(i),(x,size[1]+.025,p[2]),.9)
for name,p,scale in [('EntryTree',(11.2,.70,8.6),.78),('TerraceTree',(10.4,.70,2.0),.73)]:
    broadleaf('Career_'+name,p,scale=scale)
    collision('Career_'+name+'_Trunk',(p[0],p[1]+.75,p[2]),(.45,1.5,.45))
for x,z in [(-11.6,-7.2),(-11.6,6.1)]:
    planter('Career_FacadeFern',(x,0,z),(1.65,.52,1.65),mat='concrete')
    asset('fern',(x,.54,z),scale=.85,yaw=z*.1)
    collision('Career_FacadeFernProxy',(x,.26,z),(1.65,.52,1.65))

# Comfortable work-lounge pockets, all outside the 6 m central promenade.
for name,p,yaw in [('WestA',(-8.8,0,5.65),math.pi/2),('WestB',(-8.8,0,3.9),math.pi/2),
                   ('WestC',(-8.8,0,-2.65),math.pi/2),('WestD',(-8.8,0,-4.4),math.pi/2),
                   ('EastA',(9.2,0,-5.0),-math.pi/2),('EastB',(9.2,0,-6.75),-math.pi/2)]:
    career_chair('Career_Lounge'+name,p,yaw)
for p in [(-7.45,0,4.75),(-7.45,0,-3.55),(7.85,0,-5.85)]:
    career_table('Career_LoungeTable',p)
for z in (-.05,1.0):
    box('Career_EntrySeat',(-9.0,.36,z),(3.0,.72,.65),'concrete',.04)
    box('Career_EntrySeatTop',(-9.0,.75,z),(3.02,.06,.68),'oak',.015)
    collision('Career_EntrySeatProxy',(-9.0,.4,z),(3.04,.80,.70))

# The skyline is a restrained backdrop beyond a physical terrace balustrade.
for i,(x,w,h,z) in enumerate([(-12,3.8,7.1,-18.0),(-7.1,3.3,10.2,-21.3),(-2.6,3.5,6.5,-17.4),
                              (2.2,3.0,12.0,-23.0),(6.6,3.6,8.9,-20.6),(11.4,4.1,6.8,-17.8)]):
    # Real depth and staggered setbacks avoid a row of billboard towers.
    depth=3.8+(i%2)*1.4
    box('Career_SkylineTower'+str(i),(x,h/2,z),(w,h,depth),'slate',.025)
    box('Career_SkylineCrown'+str(i),(x,h+.10,z),(w*.9,.20,depth*.9),'concrete',.008)
    for level in range(1,int(h/1.05)):
        career_bar('Career_SkylineWindowBand',(x,level*1.05,z+depth/2+.012),(w*.86,.40,.02),'glass',0)
    for xx in (-w*.28,w*.28):
        box('Career_SkylineVerticalFin',(x+xx,h/2,z+depth/2+.03),(.075,h-.25,.06),'concrete',0)
for x in range(-13,14,2):
    career_bar('Career_RearRailPost',(x,.58,-10.35),(.055,1.16,.055),'steel')
for y in (.15,1.15): rod('Career_RearRail',(-13.8,y,-10.35),(13.8,y,-10.35),.03,'steel',10)
for x in range(-12,13,2):
    box('Career_RearGlassPanel',(x,.65,-10.35),(1.93,.88,.025),'glass',0)
collision('Career_RearBoundary',(0,.62,-10.35),(27.8,1.24,.18))
for x in (-13.85,13.85):
    box('Career_PerimeterCoping',(x,.14,.2),(.30,.28,20.8),'concrete',.018)
    collision('Career_PerimeterBoundary',(x,.62,.2),(.30,1.24,20.8))
    for z in (-9.8,-7.6,-5.4,-3.2,-1.0,1.2,3.4,5.6,7.8,10.0):
        career_bar('Career_PerimeterPost',(x,.65,z),(.055,1.10,.055),'steel')
    for y in (.22,1.17): rod('Career_PerimeterRail',(x,y,-10.0),(x,y,10.45),.028,'steel',10)
