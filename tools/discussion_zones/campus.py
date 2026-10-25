"""Limestone cloister garden, authored at ground level around a tiered fountain."""

ZONE_CONTROL=(0,.06,13.0)
ZONE_SIGN=(0,1.7,12.6)
ZONE_SLOTS=[
    {"position":[side*5.4,.02,z],"rotation_y":-side*math.pi/2}
    for z in [8.0,3.5,-1.0,-5.5] for side in [-1,1]
]

district_floor("Cloister_PavedCourt",(0,-.055,0),(34,.11,31),"stone",5)
collision("Cloister_PavedCourt",(0,-.16,0),(34,.32,31))
for x in range(-16,17,2):
    box("Cloister_PavingJoint",(x,.004,0),(.014,.008,30.8),"sand",0)
for z in range(-14,16,2):
    box("Cloister_PavingJoint",(0,.004,z),(33.8,.008,.014),"sand",0)
# Full circular fountain and its apron leave two broad routes around it.
arc_band("Fountain_Apron",(0,.009,-.8),3.15,.12,.013,0,math.tau,"sand",64)
cylinder("Fountain_Foot",(0,.12,-.8),2.18,.24,"stone",segments=64)
arc_band("Fountain_BasinWall",(0,.23,-.8),2.0,.24,.43,0,math.tau,"stone",64)
cylinder("Fountain_Water",(0,.48,-.8),1.87,.025,"water",segments=64)
cylinder("Fountain_CentreFoot",(0,.57,-.8),.44,.45,"stone",top=.32,segments=32)
cylinder("Fountain_Stem",(0,1.0,-.8),.19,.85,"stone",top=.24,segments=24)
cylinder("Fountain_UpperBowl",(0,1.39,-.8),.46,.22,"stone",top=.77,segments=48)
arc_band("Fountain_UpperLip",(0,1.49,-.8),.72,.12,.11,0,math.tau,"stone",48)
cylinder("Fountain_UpperWater",(0,1.53,-.8),.66,.016,"water",segments=48)
cylinder("Fountain_Finial",(0,1.75,-.8),.11,.40,"brass",top=.05,segments=20)
for j in range(12):
    a=j*math.tau/12
    pts=[]
    for k in range(13):
        t=k/12;r=.70+t*.33;y=1.51-1.01*t*t
        pts.append((math.cos(a)*r,y,-.8+math.sin(a)*r))
    for k in range(12):rod("Fountain_WaterRibbon",pts[k],pts[k+1],.012,"water",6)
collision("Fountain",(0,.83,-.8),(4.30,1.66,4.30))

# Three connected arcades: real voussoir arches, a substantial cornice and a
# terracotta-capped outer wall. Their interiors remain open to walk through.
def cloister_run(name,p,count,yaw=0):
    with frame(p,yaw):
        span=4.15;length=count*span
        box(name+"_OuterWall",(0,2.7,-2.55),(length+.6,5.4,.48),"stone",.02)
        collision(name+"_OuterWall",(0,2.7,-2.55),(length+.6,5.4,.48))
        box(name+"_WallCap",(0,5.43,-2.55),(length+.85,.20,.70),"sand",.025)
        for i in range(count):
            x=(i-(count-1)/2)*span
            arch(name+"_Bay",(x,0,0),3.82,2.35,.52,"stone")
            # Rectangular stone spandrel strips sit above the top of each arch.
            box(name+"_Cornice",(x,4.75,0),(span,.30,.72),"stone",.025)
            for z in [-.65,-1.6,-2.5]:
                box(name+"_CeilingBeam",(x,4.68,z),(span,.18,.17),"walnut",.01)
            for panel in [-.90,.90]:
                box(name+"_WallPilaster",(x+panel,2.0,-2.29),(.10,3.4,.08),"sand",.006)
            # Wall-lamp backing and small metal hood, warm ivory glass.
            box(name+"_LanternBack",(x,2.35,-2.24),(.21,.48,.055),"brass",.01)
            box(name+"_LanternGlass",(x,2.35,-2.13),(.16,.32,.15),"paper",.01)
            box(name+"_LanternCap",(x,2.57,-2.13),(.26,.09,.23),"brass",.01)
        box(name+"_Roof",(0,4.98,-1.25),(length+.8,.15,3.6),"clay",.02)
        for j in range(int(length/.32)+2):
            xx=-length/2+j*.32
            rod(name+"_RoofTileRidge",(xx,5.10,.51),(xx,5.10,-3.01),.055,"clay",8)

cloister_run("Cloister_Back",(0,0,-11.8),7)
cloister_run("Cloister_Left",(-13.0,0,1.0),5,math.pi/2)
cloister_run("Cloister_Right",(13.0,0,1.0),5,-math.pi/2)

# Garden rooms beside the main routes have seating beneath hanging vines.
for side in [-1,1]:
    pergola("Cloister_VinePergola",(side*9.7,0,4.9),(4.4,3.2,6.5))
    bench("Cloister_PergolaBench",(side*10.6,0,4.5),-side*math.pi/2)
    planter("Cloister_LongFlowerBed",(side*8.9,.27,-5.4),(4.5,.54,3.1),"stone")
    planter("Cloister_EntranceBed",(side*8.8,.25,10.5),(5.2,.50,2.1),"stone")
    asset("alder",(side*9.4,.55,-5.6),.72,side*.3)
    asset("fern",(side*7.5,.55,-5.5),.7,side*.8)
    asset("fern",(side*10.4,.55,-4.7),.65,side*1.4)
    bench("Cloister_BackBench",(side*5.1,0,-8.8),0)
    for z in [-9.8,-.6,9.6]:
        cylinder("Cloister_TerracottaPot",(side*11.6,.37,z),.40,.72,"clay",top=.51,segments=24)
        cylinder("Cloister_PotSoil",(side*11.6,.74,z),.46,.022,"soil",segments=24)
        broadleaf("Cloister_PottedFern",(side*11.6,.75,z),1.25)
        collision("Cloister_Pot",(side*11.6,.38,z),(.95,.76,.95))
    for j in range(6):
        foliage("Cloister_HangingIvy",(side*12.72,3.2-j*.23,-7.4),(.30,.31,.55),72)

# Mature crowns rise above the perimeter and give the cloister an enclosing
# silhouette without adding obstructions in its walkable bays.
for kind,p,scale in [("birch",(-16.2,0,-13.5),1.05),("alder",(16.2,0,-12.8),.95),
                     ("birch",(-16.0,0,12.8),.90),("alder",(16.0,0,12.8),.90)]:
    asset(kind,p,scale)
