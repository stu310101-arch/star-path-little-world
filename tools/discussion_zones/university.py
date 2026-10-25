"""Lakeside university forum; executed inside the garden author's local frame.

All eight interaction positions sit on the level sandstone promenade. The
curved seating is deliberately outside the accessible route, not a staircase
that the player must climb to reach a message. No reset, export, or scene setup.
"""
import math

ZONE_CONTROL = (0, .06, 10.2)
ZONE_SIGN = (0, 1.7, 10.0)
ZONE_SLOTS = [
    {"position": [side * 3.2, .02, z], "rotation_y": -side * math.pi / 2}
    for z in (7.0, 3.65, .3, -3.05) for side in (-1, 1)
]

_university_instances = {}
def uni_bar(name, p, size, mat, edge=.008):
    key = (tuple(size), mat, edge)
    if key not in _university_instances:
        _university_instances[key] = box(name, p, size, mat, edge)
        return _university_instances[key]
    ob = _university_instances[key].copy()
    ob.data = _university_instances[key].data
    ob.name = 'SM_' + name
    COL.objects.link(ob)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    return ob

def uni_arc(name, center, inner, outer, start, end, bottom, top, mat, steps=28, blocking=False):
    points = []
    for y in (bottom, top):
        for radius in (inner, outer):
            for i in range(steps + 1):
                a = math.radians(start + (end - start) * i / steps)
                points.append((center[0] + math.cos(a) * radius, y, center[1] + math.sin(a) * radius))
    n = steps + 1
    faces = []
    for i in range(steps):
        faces += [(i, i + 1, n + i + 1, n + i),
                  (2*n + i, 3*n + i, 3*n + i + 1, 2*n + i + 1),
                  (i, 2*n + i, 2*n + i + 1, i + 1),
                  (n + i, n + i + 1, 3*n + i + 1, 3*n + i)]
    faces += [(0, n, 3*n, 2*n), (n-1, 3*n-1, 4*n-1, 2*n-1)]
    result = mesh(name, points, faces, mat)
    bevel(result, .018, 2)
    if blocking:
        # Short tangent boxes closely follow the seating silhouette; they do
        # not create a convex blocker over the open centre of the terrace.
        segments = 12
        for i in range(segments):
            a = math.radians(start + (end - start) * (i + .5) / segments)
            radius = (inner + outer) / 2
            with frame((center[0] + math.cos(a)*radius, (bottom+top)/2, center[1] + math.sin(a)*radius), -a):
                collision(name + '_Proxy_' + str(i), (0, 0, 0),
                          (outer-inner+.025, top-bottom, radius*math.radians(abs(end-start))/segments+.035))
    return result

def uni_reeds(name, p, count=32, height=.85):
    # Bent leaf ribbons and a few seed heads, intentionally unlike round shrubs.
    points, faces = [], []
    for i in range(count):
        angle = i * 2.39996
        radius = .36 * math.sqrt((i+.5)/count)
        x, z = p[0]+math.cos(angle)*radius, p[2]+math.sin(angle)*radius
        h = height * (.60 + .4 * ((i*13)%19)/19)
        dx, dz = math.cos(angle)*h*.24, math.sin(angle)*h*.24
        width = .025 + (i%3)*.008
        sx, sz = math.cos(angle+math.pi/2)*width, math.sin(angle+math.pi/2)*width
        base = len(points)
        points += [(x-sx,p[1],z-sz),(x+sx,p[1],z+sz),
                   (x+dx*.45+sx,p[1]+h*.64,z+dz*.45+sz),
                   (x+dx*.45-sx,p[1]+h*.64,z+dz*.45-sz),
                   (x+dx,p[1]+h,z+dz)]
        faces += [(base,base+1,base+2,base+3),(base+3,base+2,base+4)]
        if i % 7 == 0:
            rod(name+'_Stem',(x,p[1],z),(x+dx*.5,p[1]+h*1.1,z+dz*.5),.009,'sage',6)
            rod(name+'_Seed',(x+dx*.5,p[1]+h*.94,z+dz*.5),(x+dx*.5,p[1]+h*1.12,z+dz*.5),.025,'sand',7)
    mesh(name+'_Leaves',points,faces,'sage')

# One continuous, flush walking surface; individual inlays describe the paving.
district_floor('University_Promenade', (0,-.12,2.4), (28,.24,19.2), 'stone',3)
collision('University_LevelPromenade',(0,-.16,2.4),(28,.32,19.2))
for z in (-6.8,-4.4,-2.0,.4,2.8,5.2,7.6,10.0):
    uni_bar('University_PavingCrossJoint',(0,.002,z),(27.7,.004,.014),'sand',0)
for x in (-11.4,-8.6,-5.8,-2.9,0,2.9,5.8,8.6,11.4):
    uni_bar('University_PavingLongJoint',(x,.003,2.3),(.012,.004,18.5),'sand',0)
for side in (-1,1):
    uni_bar('University_PathEdge',(side*4.5,.006,2.2),(.055,.012,18.5),'brass',.003)
    box('University_EdgeCoping',(side*13.78,.075,.8),(.44,.15,15.7),'stone',.025)
    collision('University_SideBoundary',(side*13.86,.56,.8),(.28,1.12,15.7))
    for z in (-6.9,-4.6,-2.3,0,2.3,4.6,6.9,8.6):
        uni_bar('University_SideRailPost',(side*13.86,.58,z),(.055,1.16,.055),'steel',.006)
    for y in (.46,1.10):
        rod('University_SideRail',(side*13.86,y,-7.05),(side*13.86,y,8.7),.032,'steel',10)

# Concentric sandstone sitting terraces with joinery strips and thin seat pads.
for side, start, end in ((1,-23,48),(-1,132,203)):
    label = 'East' if side > 0 else 'West'
    for tier in range(3):
        inner, outer, top = 6.65+tier*1.04, 7.69+tier*1.04, .40+tier*.36
        uni_arc('University_'+label+'_Terrace'+str(tier),(0,-1.0),inner,outer,start,end,-.01,top,'stone',blocking=True)
        uni_arc('University_'+label+'_SeatReveal'+str(tier),(0,-1.0),inner+.025,inner+.055,start,end,top-.095,top-.065,'sand')
        # Short timber seating segments leave the pale curved stone legible.
        for j in range(5):
            a0=start+3+j*(end-start-6)/5
            a1=a0+(end-start-6)/5-2.4
            uni_arc('University_'+label+'_OakSeat',(0,-1.0),inner+.10,inner+.59,a0,a1,top+.008,top+.058,'oak',steps=5)
    uni_arc('University_'+label+'_PlantingWall',(0,-1.0),9.82,10.72,start,end,-.02,.38,'stone')
    uni_arc('University_'+label+'_PlantingSoil',(0,-1.0),9.94,10.60,start+1,end-1,.37,.39,'soil')
    for j in range(6):
        a=math.radians(start+5+j*(end-start-10)/5)
        point=(math.cos(a)*10.26,.39,-1+math.sin(a)*10.26)
        flowers('University_'+label+'_Meadow'+str(j),point,scale=.7)
        if j%2==0: uni_reeds('University_'+label+'_Grass'+str(j),point,22,.6)

# Lake begins beyond the masonry quay, with the jetty as a level continuation.
box('University_Lake',(0,-.020,-14.0),(26,.06,14.0),'water',0)
box('University_LakeBed',(0,-.36,-14.0),(26,.18,14.0),'slate',0)
for shore_x in [-11.5,11.5]:
    asset('willow',(shore_x,0,-20.6),scale=.78,yaw=shore_x*.1)
    for shore_z in [-18.5,-20]: uni_reeds('University_FarBankReeds',(shore_x,0,shore_z),35,1.1)
for side in (-1,1):
    box('University_QuayCoping',(side*9.35,.06,-7.05),(9.3,.18,.5),'stone',.035)
    collision('University_QuayWaterBarrier',(side*9.35,.56,-7.12),(9.3,1.12,.22))
    for j in range(7):
        x=side*(4.8+j*1.48)
        uni_bar('University_QuayRailPost',(x,.59,-7.12),(.055,1.12,.055),'steel',.006)
    for y in (.46,1.10):
        rod('University_QuayRail',(side*4.65,y,-7.12),(side*13.95,y,-7.12),.032,'steel',10)
    for j in range(6):
        uni_reeds('University_LakeReed'+str(side)+'_'+str(j),(side*(5.3+j*1.42),-.08,-7.65-(j%2)*.4),28,1.1)

box('University_JettyStructure',(0,-.14,-8.75),(9.2,.25,5.1),'walnut',.025)
collision('University_JettyFloor',(0,-.13,-8.75),(9.2,.26,5.1))
for i in range(34):
    z=-6.26-i*.148
    uni_bar('University_JettyPlank',(0,.004,z),(9.16,.035,.138),'oak',.005)
for x in (-4.55,4.55):
    for z in (-6.65,-8.0,-9.4,-11.25):
        uni_bar('University_JettyPost',(x,.58,z),(.07,1.16,.07),'steel',.008)
    for y in (.45,1.12): rod('University_JettySideRail',(x,y,-6.55),(x,y,-11.28),.034,'steel',10)
    collision('University_JettySideBarrier',(x,.59,-8.9),(.18,1.18,4.9))
for x in (-4.55,-3.03,-1.52,0,1.52,3.03,4.55):
    uni_bar('University_JettyRearPost',(x,.58,-11.28),(.07,1.16,.07),'steel',.008)
for y in (.45,1.12): rod('University_JettyRearRail',(-4.55,y,-11.28),(4.55,y,-11.28),.034,'steel',10)
collision('University_JettyRearBarrier',(0,.59,-11.28),(9.25,1.18,.18))
bench('University_OverlookBenchLeft',(-2.75,.026,-10.12))
bench('University_OverlookBenchRight',(2.75,.026,-10.12))

# Mature trees frame the vista; planting stays outside device approach circles.
for name,p,scale in [('WillowWest',(-11.85,0,-4.95),.90),('WillowEast',(11.8,0,-4.9),.86)]:
    asset('willow',p,scale=scale,yaw=.4 if p[0]<0 else -.6)
    collision('University_'+name+'_Trunk',(p[0],1.1,p[2]),(.72,2.2,.72))
for side in (-1,1):
    planter('University_EntryPlanter'+str(side),(side*10.6,0,9.0),(4.2,.38,2.3),mat='stone')
    broadleaf('University_EntryTree'+str(side),(side*11.0,.4,9.0),scale=.75)
    flowers('University_EntryFlowers'+str(side),(side*9.55,.40,8.85),scale=.8)
    asset('fern',(side*12.0,.40,8.8),scale=.7,yaw=side*.8)
    collision('University_EntryPlanterBlock'+str(side),(side*10.6,.24,9.0),(4.2,.48,2.3))
    # Restrained low lanterns, rather than a second row of message-like objects.
    for z in (5.4,-4.7):
        box('University_BollardFoot',(side*4.65,.04,z),(.24,.08,.24),'stone',.025)
        box('University_Bollard',(side*4.65,.34,z),(.10,.60,.10),'steel',.012)
        box('University_BollardLantern',(side*4.65,.65,z),(.16,.08,.16),'paper',.015)
        collision('University_BollardProxy',(side*4.65,.35,z),(.24,.70,.24))
