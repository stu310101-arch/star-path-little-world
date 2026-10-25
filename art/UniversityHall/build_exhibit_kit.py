"""Curated university exhibits: 8 displays + 36 named modular components.
Run in a fresh background Blender. No hall rebuild and no GPU rendering.
"""
from pathlib import Path
import bpy,bmesh,math,random,json,sys,struct,zlib,os,hashlib,re,ast
import numpy as np
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[2];ART=ROOT/'art/UniversityHall';OUT=ROOT/'game/assets/university_hall';TEX=OUT/'textures'
sys.path.insert(0, str(ROOT / "tools"))
from optimize_indoor_geometry import optimize_glb
assert not bpy.data.filepath,'Run in a fresh --factory-startup process.'
for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.name='大學館 | School-specific modular exhibits';scene.unit_settings.system='METRIC'
COL=None;FRAME=Matrix.Identity(4);ASSETS={};STATS={};M={};RNG=random.Random(138)
source=ROOT/'tools/build_university_hall.py';tree=ast.parse(source.read_text(encoding='utf-8'))
exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,ast.FunctionDef)],type_ignores=[]),str(source),'exec'))
for key in ['walnut','stone','stone_dark','plaster','leather_green','leather_red','leather_blue','paper']:material(key)
material('brass',(.40,.245,.075),metal=.82,rough=.28);material('glass',(.49,.65,.65),rough=.12,alpha=.12)
material('lamp',(1,.62,.26),rough=.45,emission=.7);material('crevice',(.04,.034,.026),rough=.99)
material('foliage',(.15,.235,.13),rough=.87);material('foliage_light',(.29,.34,.16),rough=.88)
material('clay',(.37,.19,.115),rough=.85);material('soil',(.235,.177,.105),rough=.95)
material('water',(.125,.285,.29),metal=.15,rough=.23);material('ochre',(.54,.32,.125),rough=.78)
DISPLAY_VARIANTS=['long_table','corner_cabinet','stepped_case','island_case','open_stage','twin_pedestal','workbench','arc_cabinet']
COMPONENT_KEYS=['palm_avenue','tree_grove','lake','river','coast','hill','terrace','lawn','farm_plots','bridge','academic_block','historic_hall','chapel','library','gallery','stage','hospital','laboratory','workshop','hangar','track','market','station','food_stall','robot_cell','digital_hub','dormitory','museum','ship','tea_pavilion','sculpture','fashion_studio','thu_chapel','ntu_bell','dairy_stall']
BOXES={}

def ellipse(name,p,radii,height,key='stone',n=48):
    x,y,z=p;rx,rz=radii
    points=[(x+math.cos(i*math.tau/n)*rx,y+dy,z+math.sin(i*math.tau/n)*rz) for dy in [0,height] for i in range(n)]
    return mesh(name,points,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],key)

def gable(name,x,z,w,d,y,h,key='clay'):
    pts=[(x-w/2,y,z-d/2),(x+w/2,y,z-d/2),(x,y+h,z-d/2),(x-w/2,y,z+d/2),(x+w/2,y,z+d/2),(x,y+h,z+d/2)]
    return mesh(name,pts,[(0,2,1),(3,4,5),(0,1,4,3),(0,3,5,2),(1,2,5,4)],key)

def facade(name,x,z,w,h,d,key='stone',floors=3,columns=5,y=.025):
    box(name,(x,y+h/2,z),(w,h,d),key,.008);box(name+'_Cornice',(x,y+h,z),(w+.025,.025,d+.025),'walnut',.005)
    for side in [-1,1]:
        for row in range(floors):
            for i in range(columns):
                xx=x+(i-(columns-1)/2)*w*.8/max(columns-1,1);yy=y+h*(row+.5)/floors
                box(name+'_RecessedWindow',(xx,yy,z+side*(d/2+.006)),(w*.105,min(.072,h/floors*.52),.013),'leather_blue',.002)
    box(name+'_Door',(x,y+.075,z+d/2+.009),(min(.09,w*.17),.145,.019),'walnut',.003)

def pad(name,w=1,d=.5,key='stone_dark'):
    box(name+'_Base',(0,.0125,0),(w,.025,d),key,.009)

def curved_patch(name,w,d,key):
    # Filled, slightly irregular rounded landscape outline, no overlay floor.
    n=56;points=[(0,.026,0)]+[(math.cos(i*math.tau/n)*w*.5*(.93+.05*math.cos(i*math.tau*3/n)),.026,math.sin(i*math.tau/n)*d*.5*(.94+.05*math.sin(i*math.tau*2/n))) for i in range(n)]
    mesh(name,points,[(0,1+i,1+(i+1)%n) for i in range(n)],key)
    for i in range(n):
        a=points[1+i];b=points[1+(i+1)%n];rod(name+'_Edge',a,b,.012,'stone',8)

def leaf(name,a,b,width,key='foliage'):
    av,bv=Vector(a),Vector(b);direction=bv-av
    across=Vector((-direction.z,0,direction.x)).normalized()*width
    mid=av+direction*.48+Vector((0,width*.25,0))
    ob=mesh(name,[tuple(av),tuple(mid+across),tuple(bv),tuple(mid-across),tuple(mid+Vector((0,width*.12,0)))],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],key)
    for poly in ob.data.polygons:poly.use_smooth=True

def palm(name,x,z,h=.85,canopy=.20):
    rod(name+'_Trunk',(x,.025,z),(x+.015,h,z+.015),.019,'walnut',14)
    for k in range(6):cylinder(name+'_TrunkRing',(x+k*.002,h*(k+1)/7,z+k*.002),.021,.011,'walnut',12)
    for j in range(9):
        angle=j*math.tau/9
        last=(x,h,z)
        for k in range(1,6):
            r=canopy*k/5;point=(x+math.cos(angle)*r,h+.05*math.sin(k*math.pi/5)-.07*(k/5)**2,z+math.sin(angle)*r)
            rod(name+'_FrondRib',last,point,.004,'foliage',6)
            for side in [-1,1]:
                out_angle=angle+side*.62;tip=(point[0]+math.cos(out_angle)*.073*(1-k/7),point[1]-.035,point[2]+math.sin(out_angle)*.073*(1-k/7))
                leaf(name+'_Leaflet',last,tip,.012,'foliage_light' if j%3==0 else 'foliage')
            last=point

def tree(name,x,z,h=.55,r=.18):
    rod(name+'_Trunk',(x,.025,z),(x,h*.74,z),.017,'walnut',12)
    for j in range(7):
        angle=j*2.399963;end=(x+math.cos(angle)*r*.62,h*(.65+.04*(j%3)),z+math.sin(angle)*r*.62)
        rod(name+'_Branch',(x,h*.44,z),end,.007,'walnut',8)
        for k in range(11):
            a=angle+k*2.399963;radius=r*(.32+.045*k);start=(end[0]+math.cos(a)*radius*.23,end[1]+.025*(k%3),end[2]+math.sin(a)*radius*.23)
            tip=(end[0]+math.cos(a)*radius,end[1]+.05*math.sin(k*1.4),end[2]+math.sin(a)*radius)
            leaf(name+'_Leaf',start,tip,.025,'foliage_light' if (j+k)%4==0 else 'foliage')

def common_reading_front():
    box('ReadingRail',(0,.81,1.055),(5.6,.08,.49),'walnut',.018)
    box('ReadingRail_GoldEdge',(0,.768,1.302),(5.42,.015,.012),'brass',.002)
    study_objects()

def labels_support(key):
    # Two caption centers stay compatible with the runtime labels.
    panel(key+'_TitlePlaque',0,2.65,-1.35,5.14,.53,'walnut')
    box(key+'_TagPlaque',(0,2.13,-1.35),(4.95,.32,.075),'leather_green',.012)

def display(key):
    collection('display_'+key);common_reading_front();labels_support(key)
    boxes=[{'name':'reading_rail','center':[0,.425,1.035],'size':[5.6,.85,.58]}]
    if key=='long_table':
        box('WritingTable_Top',(0,.826,-.23),(5.35,.048,1.98),'walnut',.018)
        for x in [-2.2,2.2]:
            for z in [-.97,.48]:box('WritingTable_TaperLeg',(x,.4,z),(.13,.8,.13),'walnut',.018)
            rod('WritingTable_BackStem',(x,0,-1.32),(x,2.93,-1.32),.025,'brass',16)
        box('WritingTable_Apron',(0,.68,-.23),(5.1,.23,1.8),'walnut',.014)
    elif key=='corner_cabinet':
        box('Corner_Desk',(0,.82,-.22),(5.35,.06,1.95),'walnut',.02)
        box('Corner_LeftWing',(-2.50,1.47,-.55),(.35,2.94,1.7),'walnut',.025)
        for y in [.22,.84,1.49,2.02,2.89]:box('Corner_WingShelf',(-2.28,y,-.52),(.32,.07,1.70),'brass',.008)
        box('Corner_RightChest',(1.9,.40,-.30),(1.20,.8,1.60),'walnut',.03)
        for y in [.16,.39,.62]:panel('Corner_Drawer',1.9,y,.515,1.06,.19)
        rod('Corner_RightStem',(2.5,0,-1.33),(2.5,2.93,-1.33),.022,'brass',16)
        boxes.append({'name':'left_wing','center':[-2.5,1.47,-.55],'size':[.35,2.94,1.7]})
    elif key=='stepped_case':
        for j,w in enumerate([5.35,4.65,4.0]):box('Stepped_StoneBase',(0,.12+j*.23,-.25),(w,.22,1.84),'stone_dark',.022)
        box('Stepped_Top',(0,.827,-.22),(5.35,.046,1.96),'walnut',.018)
        for x in [-2.5,2.5]:box('Stepped_TallPier',(x,1.46,-1.30),(.19,2.92,.27),'stone',.015)
        box('Stepped_PartialGlass',(-2.48,1.54,-.30),(.008,1.32,1.48),'glass',0)
        box('Stepped_PartialCanopy',(-1.325,2.20,-.30),(2.31,.008,1.48),'glass',0)
        boxes.append({'name':'partial_case','center':[-1.325,1.54,-.3],'size':[2.32,1.33,1.49]})
    elif key=='island_case':
        for x in [-1.65,1.65]:ellipse('Island_EllipticPedestal',(x,0,-.2),(.52,.68),.80,'stone_dark')
        ellipse('Island_OvalTop',(0,.80,-.20),(2.70,1.0),.05,'walnut',64)
        for x in [-2.25,2.25]:rod('Island_BrassMast',(x,0,-1.3),(x*.8,2.94,-1.3),.025,'brass',16)
    elif key=='open_stage':
        box('Stage_DisplayDeck',(0,.825,-.2),(5.4,.05,1.99),'stone',.017)
        for j in range(3):box('Stage_FrontSteps',(0,.12+j*.22,-.25),(5.35-j*.45,.21,1.90),'stone_dark',.017)
        arc('Stage_BackArch',0,1.0,-1.50,2.55,.15,.15,'walnut',48)
        for x in [-2.62,2.62]:box('Stage_ArchFoot',(x,.52,-1.50),(.20,1.04,.32),'walnut',.02)
    elif key=='twin_pedestal':
        for x in [-1.47,1.47]:
            box('Twin_Archive',(x,.40,-.3),(1.64,.80,1.72),'walnut',.035)
            for y in [.22,.59]:panel('Twin_Drawer',x,y,.585,1.42,.28)
            box('Twin_StoneSlab',(x,.822,-.3),(1.9,.056,1.88),'stone',.018)
        box('Twin_CentralBridge',(0,.82,-.27),(1.36,.06,1.78),'walnut',.012)
        for x in [-2.4,2.4]:rod('Twin_DisplayPost',(x,.02,-1.33),(x,2.94,-1.33),.032,'brass',16)
    elif key=='workbench':
        box('Workshop_BenchTop',(0,.82,-.2),(5.35,.06,1.98),'walnut',.019)
        for x in [-2.35,2.35]:
            for z in [-1,.55]:rod('Workshop_Trestle',(x,0,z),(x*.91,.79,z),.049,'stone_dark',12)
            rod('Workshop_LowerBrace',(x,.22,-1),(x,.22,.55),.035,'stone_dark',12)
            box('Workshop_BackUpright',(x,1.49,-1.36),(.09,2.98,.12),'stone_dark',.01)
        box('Workshop_LowerShelf',(0,.22,-.3),(4.5,.07,1.43),'walnut',.012)
        for x in [-2.0,2.0]:box('Workshop_ToolWing',(x,1.70,-1.33),(.53,.59,.10),'walnut',.01)
    elif key=='arc_cabinet':
        ellipse('Arc_CabinetBody',(0,0,-.26),(2.60,.90),.79,'walnut',64)
        ellipse('Arc_StoneLip',(0,.79,-.26),(2.68,.95),.06,'stone_dark',64)
        for j in range(15):
            a=j*math.pi/14;rod('Arc_CabinetFluting',(math.cos(a)*2.58,.12,-.26+math.sin(a)*.90),(math.cos(a)*2.58,.70,-.26+math.sin(a)*.90),.014,'brass',10)
        for x in [-2.5,2.5]:box('Arc_CurvedSidePier',(x,1.44,-1.35),(.22,2.88,.24),'walnut',.017)
        for j in range(48):
            a=j*math.pi/48;b=(j+1)*math.pi/48
            rod('Arc_ShallowCrown',(math.cos(a)*2.55,2.93+math.sin(a)*.25,-1.36),(math.cos(b)*2.55,2.93+math.sin(b)*.25,-1.36),.025,'brass',12)
    boxes.append({'name':'display_table','center':[0,.425,-.2],'size':[5.4,.85,2.06]})
    boxes.append({'name':'title_support','center':[0,2.54,-1.35],'size':[5.25,.77,.16]})
    BOXES[key]={'boxes':boxes,'model':'display_'+key,'diorama_origin':[0,.88,-.15]}

def component(key):
    collection('component_'+key)
    if key=='palm_avenue':
        pad('PalmSurvey',1.2,.4,'stone')
        for x in [-.43,0,.43]:
            for z in [-.14,.14]:palm('BotanicalPalm',x,z,.75,.13)
        box('Palm_AxisPath',(0,.036,0),(1.18,.019,.085),'paper',.004)
    elif key=='tree_grove':
        pad('Grove',1,.5,'soil')
        for x,z,h in [(-.32,-.08,.66),(0,.10,.76),(.31,-.10,.61)]:tree('Broadleaf',x,z,h,.14)
    elif key in ['lake','lawn']:
        curved_patch(key,1,.6,'water' if key=='lake' else 'foliage')
        if key=='lake':
            for x in [-.20,.12]:rod('LakeReflection',(x,.031,-.055),(x+.17,.031,-.055),.003,'paper',6)
    elif key=='river':
        n=24;points=[]
        for i in range(n+1):
            x=-.6+1.2*i/n;mid=math.sin(i*math.pi*2/n)*.055
            points.extend([(x,.027,mid-.10),(x,.027,mid+.10)])
        mesh('MeanderingRiver',points,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(n)],'water')
        for side in [0,1]:
            for i in range(n):rod('RiverBank',points[i*2+side],points[(i+1)*2+side],.014,'stone',8)
    elif key=='coast':
        pad('CoastWater',1,.6,'water')
        mesh('CoastLand',[(-.5,.045,-.3),(-.5,.045,.3),(-.18,.045,.3),(-.1,.045,.12),(-.21,.045,-.02),(-.06,.045,-.18),(-.13,.045,-.3)],[(0,1,2,3,4,5,6)],'stone')
        for z in [-.16,.02,.20]:box('CoastBreakwater',(.30,.055,z),(.27,.075,.035),'stone',.004)
    elif key=='hill':
        nx,nz=20,12;pts=[]
        for j in range(nz+1):
            for i in range(nx+1):
                x=i/nx-.5;z=(j/nz-.5)*.6;y=.025+.70*max(0,1-(x/.54)**2-(z/.34)**2)**1.6;pts.append((x,y,z))
        ob=mesh('SculptedMountain',pts,[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(nz) for i in range(nx)],'foliage')
        for p in ob.data.polygons:p.use_smooth=True
    elif key=='terrace':
        for j in range(5):box('TopographicTerrace',(-.40+j*.19,.065+j*.09,0),(.25,.13+j*.18,.6),'stone_dark',.007)
    elif key=='farm_plots':
        pad('AgriculturalField',1,.6,'soil')
        for x in [-.36,-.12,.12,.36]:
            box('FarmRaisedBed',(x,.045,0),(.15,.04,.51),'walnut',.004)
            for z in [-.19,-.09,.01,.11,.21]:leaf('CropLeaves',(x,.066,z),(x+.048,.105,z+.025),.023,'foliage');leaf('CropLeaves',(x,.066,z),(x-.048,.105,z-.025),.023,'foliage_light')
        for x in [-.49,.49]:rod('FarmFence',(x,.025,-.29),(x,.21,-.29),.009,'brass',8)
    elif key=='bridge':
        for x in [-.36,.36]:box('BridgePier',(x,.11,0),(.12,.22,.31),'stone',.005)
        box('BridgeDeck',(0,.235,0),(.97,.05,.38),'walnut',.006)
        for z in [-.19,.19]:
            rod('BridgeHandrail',(-.48,.37,z),(.48,.37,z),.013,'brass',10)
            for x in [-.43,-.21,0,.21,.43]:rod('BridgeBaluster',(x,.26,z),(x,.37,z),.008,'brass',8)
    elif key=='academic_block':
        pad('College');facade('CollegeWing',-.23,0,.47,.42,.42,columns=3);facade('CollegeWing',.29,-.07,.34,.64,.31,columns=2)
        for i in range(3):box('CollegeSteps',(0,.025+i*.025,.19),(.24,.025,.12-i*.022),'stone',.002)
    elif key=='historic_hall':
        pad('Historic');facade('HistoricBrick',0,0,.95,.39,.37,'clay',2,7);gable('HistoricHippedRoof',0,0,1,.44,.415,.19,'walnut')
        for x in [-.35,-.175,0,.175,.35]:cylinder('HistoricColumn',(x,.20,.215),.018,.35,'stone',12)
    elif key=='chapel':
        pad('ChapelCourt',1,.5,'stone');facade('CampusChapel',-.14,0,.61,.40,.39,'plaster',1,3)
        gable('ChapelGabledRoof',-.14,0,.68,.45,.425,.30,'walnut')
        box('ChapelBellTower',(.31,.40,-.02),(.24,.75,.30),'stone',.006)
        gable('ChapelSteeple',.31,-.02,.30,.35,.79,.24,'walnut')
        arc('ChapelBellOpening',.31,.61,.138,.065,.023,.018,'brass',24)
    elif key=='thu_chapel':
        pad('ChapelCourt',1,.5,'stone_dark')
        # Luce Memorial Chapel: four separated ochre shells; taller rear pair,
        # tapering inwards to a narrow ridge skylight, no Gothic spire.
        for side in [-1,1]:
            for front in [-1,1]:
                pts=[];height=.98 if front==-1 else .84;nu,nv=18,10
                for j in range(nu+1):
                    u=j/nu
                    for k in range(nv+1):
                        v=k/nv;x=side*(.46*(1-u)**1.4+.016)
                        y=.028+height*u*(1-.30*v)+.09*math.sin(math.pi*u)*math.sin(math.pi*v)
                        z=front*(.012+(.232-.055*u)*v);pts.append((x,y,z))
                faces=[(j*(nv+1)+k,j*(nv+1)+k+1,(j+1)*(nv+1)+k+1,(j+1)*(nv+1)+k) for j in range(nu) for k in range(nv)]
                ob=mesh('THU_FourHyparShells',pts,faces,'ochre')
                bm=bmesh.new();bm.from_mesh(ob.data)
                for face in bm.faces:
                    if face.normal.z<0:face.normal_flip()
                bm.normal_update();bm.to_mesh(ob.data);bm.free()
                for p in ob.data.polygons:p.use_smooth=True
                shell=ob.modifiers.new('Physical ceramic shell thickness','SOLIDIFY');shell.thickness=.013;shell.offset=-1
                for j in [3,6,9,12,15]:
                    for k in range(nv):rod('THU_SubtleTileSeam',pts[j*(nv+1)+k],pts[j*(nv+1)+k+1],.0025,'brass',6)
        mesh('ChapelRecessedGlazing',[(-.39,.035,.207),(.39,.035,.207),(0,.565,.161)],[(0,1,2)],'leather_blue')
        rod('ChapelDoor',(0,.035,.216),(0,.23,.216),.018,'brass',12)
        # A three-quarter model presentation makes both roof and front legible.
        turn=Matrix.Rotation(math.radians(22),4,'Z')
        for ob in COL.objects:ob.matrix_world=turn@ob.matrix_world
    elif key=='library':
        pad('Library');facade('LibraryBookTower',-.24,0,.33,.90,.32,'stone',6,2)
        facade('LibraryReadingWing',.19,.01,.52,.35,.41,'walnut',2,4)
        for y in [.16,.29,.42,.55,.68,.81]:box('LibraryTowerLouvre',(-.24,y,.171),(.35,.018,.032),'brass',.003)
    elif key=='gallery':
        pad('GalleryCourt');facade('GalleryWall',-.26,0,.43,.37,.37,'plaster',1,2)
        box('GalleryFloatingRoof',(.20,.45,0),(.57,.05,.45),'stone_dark',.01)
        for x in [.0,.42]:rod('GallerySlenderColumn',(x,.025,.17),(x,.43,.17),.012,'brass',12)
        box('GallerySculptureBase',(.18,.065,0),(.17,.08,.16),'stone',.003);arc('GalleryArt',.18,.12,0,.083,.025,.045,'brass',24)
    elif key=='stage':
        pad('Amphitheatre',1,.5,'stone_dark')
        for j in range(5):
            n=28;r=.15+j*.071
            for i in range(n):
                a=math.pi+i*math.pi/n;b=math.pi+(i+1)*math.pi/n
                mesh('FanSeating',[(math.cos(a)*r,.035+j*.05,math.sin(a)*r*.52+.2),(math.cos(b)*r,.035+j*.05,math.sin(b)*r*.52+.2),(math.cos(b)*(r+.045),.035+j*.05,math.sin(b)*(r+.045)*.52+.2),(math.cos(a)*(r+.045),.035+j*.05,math.sin(a)*(r+.045)*.52+.2)],[(0,1,2,3)],'walnut')
        box('PerformanceStage',(0,.08,.17),(.4,.11,.15),'stone',.006)
        for x in [-.43,.43]:rod('TheatreFlyTower',(x,.025,-.20),(x,.72,-.20),.020,'brass',12)
        rod('StageLightingTruss',(-.43,.72,-.20),(.43,.72,-.20),.022,'brass',12)
    elif key=='hospital':
        pad('MedicalCampus');facade('HospitalTallWard',-.23,-.01,.38,.94,.40,'stone',6,3);facade('HospitalClinic',.25,.03,.34,.65,.34,'plaster',4,2)
        box('HospitalSkybridge',(.03,.43,0),(.30,.11,.17),'leather_blue',.004)
        box('MedicalCrossV',(-.23,.78,.208),(.023,.13,.017),'brass',.003);box('MedicalCrossH',(-.23,.78,.218),(.10,.026,.017),'brass',.003)
    elif key=='laboratory':
        pad('ResearchCampus');facade('ResearchLab',-.12,0,.72,.44,.4,'stone',3,6)
        cylinder('ResearchTank',(.34,.38,-.06),.11,.71,'stone_dark',24);cylinder('ResearchTankCap',(.34,.747,-.06),.116,.034,'brass',24)
        for x in [-.35,-.12,.11]:box('LabRoofMonitor',(x,.53,0),(.14,.14,.25),'leather_blue',.008)
    elif key=='workshop':
        pad('Workshop');facade('WorkshopHall',0,0,.95,.29,.42,'clay',1,5)
        for x in [-.33,0,.33]:gable('SawtoothRoof',x,0,.32,.45,.315,.22,'stone_dark');box('WorkshopNorthlight',(x-.08,.422,.225),(.11,.16,.017),'leather_blue',.002)
    elif key=='hangar':
        pad('Hangar');n=32;pts=[]
        for z in [-.22,.22]:
            for i in range(n+1):a=i*math.pi/n;pts.append((math.cos(a)*.48,.025+math.sin(a)*.48,z))
        ob=mesh('HangarBarrelVault',pts,[(i,i+1,i+n+2,i+n+1) for i in range(n)],'stone_dark')
        for p in ob.data.polygons:p.use_smooth=True
        for z in [-.21,-.07,.07,.21]:arc('HangarRib',0,.025,z,.48,.014,.015,'brass',32)
        box('HangarClosedDoor',(0,.19,-.221),(.88,.33,.016),'leather_blue',.002)
    elif key=='track':
        ellipse('AthleticsBase',(0,0,0),(.5,.25),.025,'clay',64)
        ellipse('AthleticsTurf',(0,.026,0),(.32,.13),.004,'foliage',48)
        for i in range(64):
            a=i*math.tau/64;b=(i+1)*math.tau/64
            rod('TrackLane',(math.cos(a)*.42,.032,math.sin(a)*.206),(math.cos(b)*.42,.032,math.sin(b)*.206),.003,'paper',6)
        box('TrackGrandstand',(0,.10,-.225),(.68,.15,.05),'stone',.003)
    elif key=='market':
        pad('MarketStreet')
        for x,h in [(-.33,.27),(0,.40),(.33,.32)]:
            facade('StreetShop',x,-.075,.29,h,.30,'clay',2,2)
            box('MarketAwning',(x,.205,.155),(.30,.025,.16),'leather_green',.004)
            for p in [-.10,.10]:rod('AwningPost',(x+p,.025,.22),(x+p,.21,.22),.006,'brass',8)
    elif key=='station':
        pad('TransitPlatform');box('StationPlatform',(0,.065,0),(.98,.08,.44),'stone',.004)
        for x in [-.36,.36]:rod('StationColumn',(x,.105,-.11),(x,.45,-.11),.014,'brass',12)
        box('StationCanopy',(0,.47,-.04),(1,.04,.37),'stone_dark',.004)
        for z in [.13,.18]:rod('StationTrack',(-.47,.11,z),(.47,.11,z),.006,'walnut',8)
    elif key in ['food_stall','dairy_stall']:
        pad('TeachingShop');box('ShopCounter',(0,.16,0),(.9,.28,.39),'walnut',.008);box('ShopCanopy',(0,.64,-.05),(1,.055,.46),'leather_green',.008)
        for x in [-.41,.41]:rod('ShopCanopyPost',(x,.025,-.17),(x,.63,-.17),.012,'brass',10)
        if key=='dairy_stall':
            for x in [-.24,0,.24]:cylinder('DairyBottle',(x,.405,.06),.040,.22,'stone',20);cylinder('DairyBottleNeck',(x,.535,.06),.022,.04,'stone',16);cylinder('DairyCap',(x,.563,.06),.024,.017,'brass',16)
        else:
            for x in [-.24,.0,.24]:cylinder('StreetFoodBowl',(x,.335,.06),.068,.060,'stone',24,r2=.086);cylinder('StreetFoodSteamBasket',(x,.38,.06),.077,.032,'walnut',24)
    elif key=='robot_cell':
        pad('RobotCell',1,.5,'stone_dark');box('RobotWorkTable',(.22,.20,0),(.39,.35,.34),'walnut',.005)
        cylinder('RobotBase',(-.23,.09,0),.13,.13,'brass',24)
        points=[(-.23,.16,0),(-.24,.46,0),(.06,.67,0),(.27,.48,0)]
        for a,b in zip(points,points[1:]):rod('ArticulatedRobotLink',a,b,.048,'brass',16)
        for p in points[1:]:cylinder('RobotJoint',p,.064,.10,'stone_dark',20)
        for z in [-.055,.055]:rod('RobotGripper',(.27,.48,z),(.29,.39,z),.014,'brass',10)
    elif key=='digital_hub':
        pad('DigitalHub');facade('DataCenter',-.26,0,.4,.65,.4,'stone_dark',4,2)
        for x in [.12,.32]:box('ServerCabinet',(x,.26,0),(.13,.47,.33),'leather_blue',.004)
        for y in [.12,.20,.28,.36,.44]:box('ServerPanel',(.22,y,.177),(.34,.007,.014),'brass',.001)
        arc('DigitalSignal',-.26,.70,0,.12,.017,.018,'brass',24)
    elif key=='dormitory':
        pad('ResidentialCourt');facade('Residence',0,-.04,.9,.73,.33,'clay',5,6)
        for y in [.17,.30,.43,.56,.69]:box('ResidenceBalcony',(0,y,.173),(.92,.024,.10),'stone',.003)
    elif key=='museum':
        pad('MuseumCourt');ellipse('MuseumRotunda',(0,.025,0),(.25,.20),.54,'stone',48)
        cylinder('MuseumDome',(0,.63,0),.25,.13,'walnut',48,r2=.07)
        for x in [-.42,-.28,.28,.42]:cylinder('MuseumColumn',(x,.23,.08),.025,.40,'stone',16)
        box('MuseumPortico',(0,.46,.09),(.96,.05,.28),'stone',.006)
    elif key=='ship':
        points=[(-.47,.10,-.13),(.35,.10,-.15),(.5,.10,0),(.35,.10,.15),(-.47,.10,.13),(-.38,.025,-.07),(.31,.025,-.075),(.39,.025,0),(.31,.025,.075),(-.38,.025,.07)]
        mesh('TrainingVesselHull',points,[(0,1,2,3,4),(5,9,8,7,6)]+[(i,(i+1)%5,(i+1)%5+5,i+5) for i in range(5)],'walnut')
        box('VesselDeckhouse',(-.15,.23,0),(.34,.25,.22),'stone',.009);rod('VesselMast',(.14,.1,0),(.14,.75,0),.015,'brass',12)
        mesh('VesselRiggingSail',[(.16,.69,0),(.16,.22,0),(.42,.22,0)],[(0,1,2)],'paper')
        rod('VesselBoom',(.13,.23,0),(.44,.23,0),.009,'brass',10)
    elif key=='tea_pavilion':
        pad('TeaGarden');box('TeaDeck',(0,.075,0),(.89,.10,.43),'walnut',.007)
        for x in [-.34,.34]:
            for z in [-.15,.15]:rod('TeaPillar',(x,.12,z),(x,.57,z),.020,'walnut',12)
        gable('TeaPavilionRoof',0,0,1,.50,.57,.21,'walnut')
        box('TeaTable',(0,.25,0),(.32,.035,.21),'walnut',.004)
    elif key=='sculpture':
        pad('SculpturePlinth',1,.5);cylinder('SculptureDrum',(0,.09,0),.18,.13,'stone_dark',32)
        for j in range(3):
            ob=arc('PublicSculpture',0,.26+j*.14,0,.14+j*.025,.022,.05,'brass',36);ob.rotation_euler.z=j*.9
    elif key=='fashion_studio':
        pad('FashionAtelier');box('FashionCuttingTable',(-.25,.28,.01),(.43,.06,.34),'walnut',.004)
        for x in [-.4,-.1]:rod('CuttingTableLeg',(x,.025,.01),(x,.25,.01),.014,'brass',10)
        rod('GarmentRail',(.18,.025,-.15),(.18,.81,-.15),.012,'brass',10);rod('GarmentRail',(.46,.025,-.15),(.46,.81,-.15),.012,'brass',10);rod('GarmentRail',(.18,.81,-.15),(.46,.81,-.15),.012,'brass',10)
        mesh('DrapedGarment',[(.22,.73,-.145),(.43,.73,-.145),(.46,.25,-.08),(.39,.21,-.01),(.29,.23,-.07),(.20,.26,-.03)],[(0,1,2,3,4,5)],'leather_red')
    elif key=='ntu_bell':
        pad('FuBellCourt',1,.5,'stone')
        for x in [-.30,.30]:box('FuBellConcretePier',(x,.40,0),(.13,.77,.26),'stone',.008)
        box('FuBellCrossbeam',(0,.82,0),(.79,.13,.30),'stone',.009)
        cylinder('FuBellSuspension',(0,.665,0),.017,.16,'brass',16)
        rings=[(.39,.15),(.42,.125),(.49,.095),(.59,.075),(.64,.047)]
        pts=[(math.cos(j*math.tau/32)*r,y,math.sin(j*math.tau/32)*r) for y,r in rings for j in range(32)]
        ob=mesh('FuBellBronzeBell',pts,[(k*32+j,k*32+(j+1)%32,(k+1)*32+(j+1)%32,(k+1)*32+j) for k in range(len(rings)-1) for j in range(32)],'brass')
        for p in ob.data.polygons:p.use_smooth=True
        cylinder('FuBellLip',(0,.40,0),.155,.025,'brass',32);cylinder('FuBellClapper',(0,.37,0),.022,.08,'brass',16)

def export_kit():
    deps=bpy.context.evaluated_depsgraph_get();outputs=[];manifest={}
    for key,col in ASSETS.items():
        bpy.ops.object.select_all(action='DESELECT');copies=[]
        for ob in col.objects:
            data=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps);copy=bpy.data.objects.new('EXPORT_'+ob.name,data);scene.collection.objects.link(copy);copy.matrix_world=ob.matrix_world.copy();copy.select_set(True);copies.append(copy)
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        out=bpy.context.object;out.name=key;bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        if key.startswith('component_'):
            # Match the published scale contract without arbitrary variants.
            xyz=[Vector((v.co.x,v.co.z,-v.co.y)) for v in out.data.vertices];low=Vector(tuple(min(v[i] for v in xyz) for i in range(3)));high=Vector(tuple(max(v[i] for v in xyz) for i in range(3)))
            short=key.removeprefix('component_');target=(1.2,.4) if short in ['palm_avenue','river'] else (1,.6) if short in ['lake','coast','hill','terrace','lawn','farm_plots'] else (1,.5)
            fx=min(1,target[0]/max(high.x-low.x,.001));fz=min(1,target[1]/max(high.z-low.z,.001));fy=min(1,1.05/max(high.y-low.y,.001))
            for v in out.data.vertices:v.co=Vector(((v.co.x-(low.x+high.x)/2)*fx,(v.co.y+(low.z+high.z)/2)*fz,(v.co.z-low.y)*fy))
        out.data.calc_loop_triangles();bounds=[Vector((v.co.x,v.co.z,-v.co.y)) for v in out.data.vertices]
        manifest[key]={'bounds_min':[round(min(v[i] for v in bounds),5) for i in range(3)],'bounds_max':[round(max(v[i] for v in bounds),5) for i in range(3)],'triangles':len(out.data.loop_triangles),'materials':len(out.data.materials),'source_parts':len(col.objects)}
        outputs.append(out)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in outputs:ob.select_set(True)
    temp=OUT/'exhibit_kit.new.glb';bpy.ops.export_scene.gltf(filepath=str(temp),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_materials='EXPORT',export_vertex_color='NONE');os.replace(temp,OUT/'exhibit_kit.glb')
    optimize_glb(OUT/'exhibit_kit.glb')
    for ob in outputs:bpy.data.objects.remove(ob,do_unlink=True)
    return manifest

exec(compile((ART/'refine_exhibits.py').read_text(encoding='utf-8'),str(ART/'refine_exhibits.py'),'exec'),globals())
print('EXHIBIT_KIT_BUILD_DISPLAYS',flush=True)
for key in DISPLAY_VARIANTS:display(key)
print('EXHIBIT_KIT_BUILD_COMPONENTS',flush=True)
for key in COMPONENT_KEYS:component(key)
print('EXHIBIT_KIT_EXPORT',flush=True);kit=export_kit()
import_path=OUT/'exhibit_kit.glb.import'
if not import_path.exists():
    resource='res://assets/university_hall/exhibit_kit.glb';digest=hashlib.md5(resource.encode()).hexdigest()
    config=(OUT/'feature_book.glb.import').read_text(encoding='utf-8');config=re.sub(r'(?m)^uid=.*\n','',config).replace('feature_book.glb','exhibit_kit.glb')
    config=re.sub(r'exhibit_kit\.glb-[0-9a-f]+\.scn','exhibit_kit.glb-'+digest+'.scn',config);import_path.write_text(config,encoding='utf-8')
for image in bpy.data.images:
    if image.source=='FILE':image.pack()
for key,col in ASSETS.items():col.hide_viewport=key!='display_long_table';col.hide_render=key!='display_long_table'
scene['kit_contract']='Direct named root children, identity transforms; component floor y0; school-specific assembly lives in art_profile.'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'UniversityHall_ExhibitKit.blend'))
layout=json.loads((OUT/'layout.json').read_text(encoding='utf-8'));layout['display_variants']=BOXES;layout['exhibit_kit']='exhibit_kit.glb';(OUT/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
report={'title':'大學館','revision':'2026-10-11-r4-modular-exhibits','source':'UniversityHall_ExhibitKit.blend','module_count':len(kit),'module_keys':list(kit),'modules':kit,'display_variants':DISPLAY_VARIANTS,'canonical_material_prefix':'MAT_University_Library_','triangles_total':sum(v['triangles'] for v in kit.values()),'glb_bytes':(OUT/'exhibit_kit.glb').stat().st_size,'provenance':'Original authored physical-scale architectural models. Individual university selection and compositions are explicitly tied to provided document excerpts; no seeded school variants.'}
(ART/'kit_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8');(OUT/'kit_manifest.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('EXHIBIT_KIT_COMPLETE '+json.dumps({'modules':len(kit),'triangles':report['triangles_total'],'bytes':report['glb_bytes']}),flush=True)
