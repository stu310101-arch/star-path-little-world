"""Architectural/landscape detailing pass for the editable exhibition kit.

Executed in build_exhibit_kit's namespace, after baseline helpers are defined.
Every shape has a construction purpose; none is seeded school decoration.
"""
material('site_sage',(.245,.285,.225),rough=.94)
material('site_taupe',(.32,.29,.235),rough=.92)
material('site_slate',(.205,.255,.27),rough=.91)
material('oxide_red',(.245,.052,.032),metal=.45,rough=.53)
material('bronze_patina',(.16,.255,.19),metal=.58,rough=.49)
material('stone_warm',(.38,.36,.30),rough=.86)

def rim(name,x,y,z,w,h,t=.006,key='stone_warm',side=0):
    pts=[]
    for ww,hh in [(w,h),(w-2*t,h-2*t)]:
        pts += [(x-ww/2,y-hh/2,z),(x+ww/2,y-hh/2,z),(x+ww/2,y+hh/2,z),(x-ww/2,y+hh/2,z)]
    ob=mesh(name,pts,[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],key)
    return ob

def facade(name,x,z,w,h,d,key='stone',floors=3,columns=5,y=.025):
    box(name+'_Masonry',(x,y+h/2,z),(w,h,d),key,.005)
    box(name+'_FoundationCourse',(x,y+.017,z),(w+.018,.034,d+.018),'stone_warm',.002)
    box(name+'_RoofCoping',(x,y+h+.011,z),(w+.022,.022,d+.022),'stone_warm',.003)
    box(name+'_RoofMembrane',(x,y+h+.026,z),(w-.034,.012,d-.034),'stone_dark',.001)
    # Window reveals, individual frames and sills on all four elevations.
    ww=min(w*.10,w/columns*.54);wh=min(.088,h/floors*.53)
    for side in [-1,1]:
        zz=z+side*(d/2+.006)
        for row in range(floors):
            yy=y+h*(row+.5)/floors
            for i in range(columns):
                xx=x+(i-(columns-1)/2)*w*.79/max(columns-1,1)
                box(name+'_WindowReveal',(xx,yy,zz),(ww+.015,wh+.014,.010),'crevice',0)
                rim(name+'_StoneWindowFrame',xx,yy,zz+side*.006,ww+.017,wh+.018,.005,'stone_warm')
                box(name+'_BlueGreyGlazing',(xx,yy,zz+side*.007),(ww-.003,wh-.004,.004),'leather_blue',0)
                box(name+'_WindowMullion',(xx,yy,zz+side*.010),(.004,wh,.006),'walnut',0)
                box(name+'_ProjectingSill',(xx,yy-wh/2-.008,zz+side*.006),(ww+.026,.009,.028),'stone_warm',.001)
        # Continuous string courses and regularly spaced masonry pilasters.
        for row in range(1,floors):box(name+'_FloorCourse',(x,y+h*row/floors,zz),(w,.009,.016),'stone_warm',.001)
        for xx in [x-w/2+.019,x+w/2-.019]:box(name+'_CornerQuoin',(xx,y+h/2,zz),(.020,h-.020,.018),'stone_warm',.002)
    sidecols=max(2,round(d/.12))
    for sign in [-1,1]:
        xx=x+sign*(w/2+.006)
        for row in range(floors):
            yy=y+h*(row+.5)/floors
            for j in range(sidecols):
                zz=z+(j-(sidecols-1)/2)*d*.67/max(1,sidecols-1)
                sw=min(.055,d/sidecols*.50)
                box(name+'_SideWindowReveal',(xx,yy,zz),(.010,wh+.015,sw+.014),'stone_warm',0)
                box(name+'_SideGlazing',(xx+sign*.006,yy,zz),(.005,wh,sw),'leather_blue',0)
                box(name+'_SideSill',(xx+sign*.005,yy-wh/2-.008,zz),(.026,.009,sw+.024),'stone_warm',0)
                box(name+'_SideMullion',(xx+sign*.010,yy,zz),(.005,wh,.004),'walnut',0)
    doorw=min(.085,w*.17);zz=z+d/2+.012
    box(name+'_Door',(x,y+.067,zz),(doorw,.132,.019),'walnut',.002)
    rim(name+'_DoorSurround',x,y+.068,zz+.011,doorw+.027,.155,.007,'stone_warm')
    box(name+'_DoorGlazing',(x,y+.085,zz+.013),(doorw*.74,.075,.006),'leather_blue',0)
    box(name+'_DoorTransom',(x,y+.055,zz+.018),(doorw,.005,.006),'brass',0)
    box(name+'_DoorHandle',(x+doorw*.28,y+.056,zz+.022),(.006,.025,.006),'brass',0)
    box(name+'_EntranceCanopy',(x,y+.168,zz+.023),(doorw+.07,.014,.077),'stone_warm',.002)

def pad(name,w=1,d=.5,key='stone_dark'):
    box(name+'_CutStoneBase',(0,.010,0),(w,.020,d),key,.007)
    # Edge stones and four paving bands rather than a noisy tile grid.
    for z in [-d/2+.010,d/2-.010]:box(name+'_StoneCurb',(0,.023,z),(w-.014,.006,.011),'stone_warm',.002)
    for x in [-w/2+.010,w/2-.010]:box(name+'_StoneCurb',(x,.023,0),(.011,.006,d-.015),'stone_warm',.002)
    for x in [-w*.3,-w*.1,w*.1,w*.3]:box(name+'_PavingJoint',(x,.0206,0),(.0018,.0012,d-.024),'crevice',0)

def canopy_mesh(name,x,y,z,r,seed=0):
    pts=[];faces=[]
    # Fibonacci leaf arrangement forms a full, non-spherical broadleaf crown.
    for i in range(150):
        a=i*2.399963+seed;v=(i+.5)/150;rr=r*math.sqrt(max(0,1-(2*v-1)**2))
        c=Vector((x+math.cos(a)*rr,y+r*(2*v-1)*.64,z+math.sin(a)*rr))
        direction=Vector((math.cos(a+.8),.15*math.sin(i*1.7),math.sin(a+.8)))
        across=Vector((-direction.z,.10,direction.x))
        length=r*(.30+.06*math.sin(i));width=r*.16
        tip=c+direction*length;start=c-direction*length*.55
        sides=[start,c+across*width,tip,c-across*width,c+Vector((0,width*.35,0))]
        k=len(pts);pts.extend(tuple(p) for p in sides);faces.extend([(k,k+1,k+4),(k+1,k+2,k+4),(k+2,k+3,k+4),(k+3,k,k+4)])
    ob=mesh(name,pts,faces,'foliage')
    for p in ob.data.polygons:p.use_smooth=True

def tree(name,x,z,h=.55,r=.18):
    rod(name+'_TaperedTrunk',(x,.022,z),(x+.012,h*.75,z-.008),.012,'walnut',10)
    for j in range(7):
        a=j*2.399963;end=(x+math.cos(a)*r*.67,h*(.65+.04*(j%3)),z+math.sin(a)*r*.67)
        rod(name+'_Branch',(x,h*.43,z),end,.004,'walnut',7)
    canopy_mesh(name+'_BroadleafCrown',x,h*.76,z,r)
    ellipse(name+'_RootMulch',(x,.022,z),(r*.37,r*.34),.009,'soil',18)

def palm(name,x,z,h=.85,canopy=.20):
    rod(name+'_TaperedPalmTrunk',(x,.022,z),(x+.014,h,z+.014),.014,'walnut',12)
    for k in range(17):cylinder(name+'_LeafScarRing',(x+.014*k/17,.026+(h-.05)*k/17,z+.014*k/17),.0145,.004,'stone_warm',10)
    ellipse(name+'_TreeGrate',(x,.025,z),(.043,.043),.009,'soil',20)
    for j in range(16):
        a=j*math.tau/16;last=(x+.014,h,z+.014)
        length=canopy*(.88+.10*math.sin(j*3));sag=.12 if j%2 else .085
        for k in range(1,9):
            t=k/8;r=length*t;p=(x+.014+math.cos(a)*r,h+.052*math.sin(t*math.pi)-sag*t*t,z+.014+math.sin(a)*r)
            rod(name+'_FrondSpine',last,p,.0024,'foliage',5)
            for side in [-1,1]:
                out=a+side*1.08;ll=canopy*.44*(1-t*.80)
                tip=(p[0]+math.cos(out)*ll,p[1]-.014-ll*.2,p[2]+math.sin(out)*ll)
                leaf(name+'_PinnateLeaflet',last,tip,.0075,'foliage_light' if j%5==0 else 'foliage')
            last=p

def small_shrub(name,x,y,z,r=.065):
    canopy_mesh(name,x,y+r*.66,z,r)

def dairy_bottle(name,x,y,z,h=.095):
    # Lathed glass-bottle silhouette with an actual shoulder and narrow neck.
    rings=[(0,.017),(.006,.018),(.025,.018),(.050,.018),(.061,.018),(.070,.0165),(.080,.010),(.094,.010)]
    n=16;factor=h/.102
    pts=[(x+math.cos(i*math.tau/n)*r*factor,y+yy*factor,z+math.sin(i*math.tau/n)*r*factor) for yy,r in rings for i in range(n)]
    faces=[(j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i) for j in range(len(rings)-1) for i in range(n)]
    faces.extend([tuple(range(n-1,-1,-1)),tuple(range((len(rings)-1)*n,len(rings)*n))])
    ob=mesh(name+'_MilkBottle',pts,faces,'stone')
    ob.data.materials.append(M['paper'])
    for i in range(2*n,3*n):ob.data.polygons[i].material_index=1
    for p in ob.data.polygons:p.use_smooth=True
    cylinder(name+'_GreenBottleCap',(x,y+.098*factor,z),.0115*factor,.008*factor,'leather_green',16)
    # The neutral label is a material region of the same mesh: no coplanar overlay.

def rock(name,x,y,z,s=.06):
    pts=[(x-s*.6,y,z-s*.4),(x+s*.5,y,z-s*.45),(x+s*.6,y,z+s*.3),(x-s*.5,y,z+s*.45),(x-s*.27,y+s*.62,z-s*.28),(x+s*.25,y+s*.55,z-s*.20),(x+s*.29,y+s*.48,z+s*.24),(x-s*.3,y+s*.53,z+s*.26)]
    mesh(name,pts,[(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],'stone_warm')

def curved_patch(name,w,d,key):
    n=64;inner=[];outer=[]
    for i in range(n):
        a=i*math.tau/n;f=.89+.055*math.sin(a*3)+.025*math.cos(a*5)
        inner.append((math.cos(a)*w*.43*f,.029,math.sin(a)*d*.43*f))
        outer.append((math.cos(a)*w*.5*f,.045,math.sin(a)*d*.5*f))
    mesh(name+'_WaterBasin',[(0,.029,0)]+inner,[(0,i+1,(i+1)%n+1) for i in range(n)],key)
    mesh(name+'_Promenade',inner+outer,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],'stone_warm')
    for i in range(n):rod(name+'_CutBankEdge',inner[i],inner[(i+1)%n],.006,'stone_dark',6)
    if key=='water':
        for j in [3,7,13,21,38,44,53]:
            a=j*math.tau/n;x,y,z=outer[j];rock(name+'_BankRock',x,y,z,.037)
            for k in range(3):rod(name+'_Reed',(x,y,z),(x+.011*math.cos(k*2),y+.060+.014*k,z+.011*math.sin(k*2)),.0018,'foliage',5)
        for k in [-1,0,1]:
            last=None
            for i in range(14):
                a=-.7+i*.10;p=(.09+k*.027+math.cos(a)*w*.17,.0305,.025+math.sin(a)*d*.12)
                if last:rod(name+'_QuietWaterRipple',last,p,.0012,'site_slate',5)
                last=p
        # Offset waterside seats are built objects, not invented campus topology.
        for x in [-.25,.22]:
            box(name+'_WatersideBench',(x,.057,-d*.385),(.095,.011,.028),'walnut',.002)
            for dx in [-.032,.032]:box(name+'_BenchFoot',(x+dx,.044,-d*.385),(.009,.027,.015),'stone_dark',0)

_base_display=display
def display(key):
    _base_display(key)
    color={'long_table':'site_sage','corner_cabinet':'site_taupe','stepped_case':'site_sage','island_case':'site_slate','open_stage':'site_taupe','twin_pedestal':'site_taupe','workbench':'site_slate','arc_cabinet':'site_sage'}[key]
    # All module bottoms remain y=.88, five mm clear of this physical tray.
    if key in ['island_case','arc_cabinet']:
        ellipse('SurveyTray_BrassRim',(0,.851,-.15),(2.53,.94),.023,'brass',80)
        ellipse('SurveyTray_MatteSiteSurface',(0,.862,-.15),(2.51,.92),.013,color,80)
    else:
        box('SurveyTray_BrassLip',(0,.860,-.15),(4.69,.022,1.68),'brass',.015)
        box('SurveyTray_MatteSiteSurface',(0,.8695,-.15),(4.66,.011,1.65),color,.012)
    # Sparse physical measuring ticks near the front lip; no fictional routes.
    for i in range(15):
        x=-2.1+i*.30;box('SurveyTray_EngravedScale',(x,.876,.617),(.006,.002,.026 if i%5 else .048),'stone_warm',0)

_base_component=component
def component(key):
    if key not in ['hill','terrace','coast','river','bridge','ship','workshop','stage','ntu_bell','3d_printer','dairy_stall']:
        return _base_component(key)
    collection('component_'+key)
    if key=='3d_printer':
        import runpy
        runpy.run_path(str(ART/'refine_printer.py'))['build_printer'](globals())
    elif key=='dairy_stall':
        pad('DairyTeachingShop',1,.5,'stone_warm')
        # Timber kiosk with an open serving frontage and exposed retail fittings.
        box('DairyRearWall',(0,.318,-.202),(.93,.56,.026),'walnut',.003)
        for x in [-.445,.445]:
            box('DairyStructuralPost',(x,.333,-.18),(.035,.61,.045),'walnut',.004)
            box('DairyPostFoot',(x,.057,-.18),(.051,.065,.057),'stone_dark',.003)
        roof=box('DairySlopedCanopy',(0,.65,-.047),(.98,.029,.40),'leather_green',.007)
        roof.rotation_euler.x=math.radians(5)
        box('DairyCanopyFascia',(0,.627,.150),(.98,.038,.018),'walnut',.003)
        for x in [-.45,.45]:rod('DairyCanopyDiagonalBrace',(x,.47,-.18),(x,.627,.10),.009,'brass',10)
        for y in [.08,.14,.20,.26,.32,.38,.44,.50,.56]:box('DairyShiplapSeam',(0,y,-.184),(.9,.003,.003),'crevice',0)
        # Front wood panel counter leaves the tall refrigerator visible at right.
        box('DairySalesCounter',(-.19,.135,.068),(.52,.22,.29),'walnut',.007)
        box('DairyCounterStoneTop',(-.19,.253,.068),(.56,.018,.32),'stone_warm',.004)
        for x in [-.39,-.19,.01]:
            rim('DairyCounterRaisedPanel',x,.137,.217,.165,.155,.010,'stone_warm')
        box('DairyCounterToeKick',(-.19,.036,.220),(.50,.030,.013),'stone_dark',.002)
        # Two open shelves, backrests and shelf lips; small bottles in coherent groups.
        for y in [.287,.423]:
            box('DairyDisplayShelf',(-.145,y,-.070),(.36,.016,.16),'stone_warm',.002)
            box('DairyShelfBack',(-.145,y+.049,-.149),(.36,.09,.013),'walnut',.002)
            box('DairyShelfLip',(-.145,y+.015,.014),(.36,.024,.008),'brass',.001)
            for x in [-.270,-.207,-.144,-.081,-.018]:dairy_bottle('ShelfDairy',x,y+.008,-.052,.093)
        # Solid surround around a hollow chilled cabinet; clear door does not mask contents.
        for x in [.135,.425]:box('DairyFridgeSide',(x,.293,-.005),(.018,.49,.335),'stone_dark',.003)
        for y in [.049,.536]:box('DairyFridgeTopBottom',(.28,y,-.005),(.308,.020,.335),'stone_dark',.003)
        box('DairyFridgeBack',(.28,.292,-.169),(.29,.476,.015),'stone_warm',.002)
        for y in [.126,.247,.368]:
            box('ChillerShelf',(.28,y,-.002),(.264,.009,.30),'stone_warm',.001)
            for x in [.194,.253,.312,.371]:dairy_bottle('ChilledDairy',x,y+.006,.027,.092)
        box('DairyFridgeGlazing',(.28,.293,.167),(.273,.447,.006),'glass',0)
        rim('DairyFridgeDoorFrame',.28,.293,.172,.294,.470,.012,'stone_warm')
        rod('DairyFridgeDoorHandle',(.398,.238,.187),(.398,.359,.187),.006,'brass',10)
        for x in [.388,.408]:box('DairyChillerVent',(x,.075,.176),(.010,.033,.010),'stone_warm',0)
        # Cash drawer, tilted POS screen and service-edge bottle pair.
        box('DairyCashDrawer',(-.357,.277,.118),(.119,.030,.091),'stone_dark',.003)
        rod('DairyPOSStem',(-.357,.292,.104),(-.357,.355,.090),.009,'brass',10)
        pos=box('DairyPOSTerminal',(-.357,.365,.093),(.103,.061,.014),'stone_dark',.003)
        pos.rotation_euler.x=math.radians(-14)
        screen=box('DairyPOSDisplay',(-.357,.365,.103),(.081,.040,.006),'leather_blue',.001)
        screen.rotation_euler.x=math.radians(-14)
        for x in [-.105,-.045]:dairy_bottle('CounterMilk',x,.265,.155,.09)
    elif key in ['hill','terrace']:
        # Contoured hillsides with retaining walls and a switchback footpath.
        def height(x,z):
            if key=='hill':return .023+.53*max(0,1-(x/.57)**2-(z/.35)**2)**1.25
            return .024+.46*((x+.50)/1.0)**1.2*(.85+.15*math.cos(z*4))
        nx,nz=34,20;pts=[]
        for j in range(nz+1):
            for i in range(nx+1):
                x=i/nx-.5;z=(j/nz-.5)*.6;pts.append((x,height(x,z),z))
        ob=mesh('Hillside_ContouredGround',pts,[(j*(nx+1)+i,j*(nx+1)+i+1,(j+1)*(nx+1)+i+1,(j+1)*(nx+1)+i) for j in range(nz) for i in range(nx)],'foliage')
        for p in ob.data.polygons:p.use_smooth=True
        # A solid cutaway landform, not a floating paper-thin contour sheet.
        # Use exactly the existing boundary and lowest surface level so bounds
        # and curated placement transforms remain unchanged.
        outline=[pts[i] for i in range(nx+1)]
        outline += [pts[j*(nx+1)+nx] for j in range(1,nz+1)]
        outline += [pts[nz*(nx+1)+i] for i in range(nx-1,-1,-1)]
        outline += [pts[j*(nx+1)] for j in range(nz-1,0,-1)]
        base_y=min(p[1] for p in pts);n=len(outline)
        shellpts=outline+[(x,base_y,z) for x,y,z in outline]
        shellfaces=[]
        for i in range(n):
            nxt=(i+1)%n
            if max(outline[i][1],outline[nxt][1])-base_y>.00001:
                shellfaces.append((i,nxt,n+nxt,n+i))
        shellfaces.append(tuple(range(n,2*n)))
        mesh('Hillside_SolidEarthCutProfile',shellpts,shellfaces,'soil')
        route=[(-.44,.24),(-.29,-.22),(-.06,.20),(.13,-.20),(.33,.17),(.44,.0)] if key=='terrace' else [(-.44,.12),(-.26,-.11),(-.05,.03),(.13,-.08),(.33,.13)]
        for i in range(len(route)-1):
            a=Vector(route[i]);b=Vector(route[i+1]);tangent=b-a;normal=Vector((-tangent.y,tangent.x)).normalized()*.026
            for j in range(9):
                p=a+(b-a)*j/9;q=a+(b-a)*(j+1)/9
                pp=[p-normal,p+normal,q+normal,q-normal]
                mesh('Hillside_SwitchbackPaving',[(v.x,height(v.x,v.y)+.009,v.y) for v in pp],[(0,1,2,3)],'stone_warm')
                rod('Hillside_PathEdge',(p.x+normal.x,height(p.x+normal.x,p.y+normal.y)+.007,p.y+normal.y),(q.x+normal.x,height(q.x+normal.x,q.y+normal.y)+.007,q.y+normal.y),.006,'stone_dark',6)
        for j,(x,z) in enumerate([(-.37,-.18),(-.17,.22),(.07,-.24),(.29,.24),(.43,-.17)]):
            y=height(x,z);rock('Hillside_Outcrop',x,y,z,.077);small_shrub('Hillside_Shrub',x-.025,y+.026,z+.025,.048)
        if key=='terrace':
            for x in [-.30,-.03,.23]:
                for k in range(4):
                    z=-.27+k*.046;y=height(x,z)
                    box('Terrace_RetainingMasonry',(x,y-.038,z),(.028,.076,.044),'stone_warm',.003)
                    box('Terrace_Coping',(x,y+.003,z),(.042,.008,.045),'stone',.001)
        else:
            for x,z in [(-.27,.02),(.20,.13)]:
                y=height(x,z);before=set(COL.objects);tree('HillsideTree',x,z,.23,.062)
                for ob in set(COL.objects)-before:ob.location.z+=y
    elif key=='river':
        n=40;pts=[]
        for i in range(n+1):
            x=-.60+1.2*i/n;mid=math.sin(i*math.tau/n)*.043;pts.extend([(x,.025,mid-.095),(x,.025,mid+.095)])
        mesh('RiverWater',pts,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(n)],'water')
        for side in [0,1]:
            sign=-1 if side==0 else 1
            for i in range(n):
                a=Vector(pts[i*2+side]);b=Vector(pts[(i+1)*2+side]);c=b+Vector((0,.018,sign*.050));d=a+Vector((0,.018,sign*.050))
                mesh('RiverEmbankment',[tuple(a),tuple(b),tuple(c),tuple(d)],[(0,1,2,3)],'stone_warm')
                rod('RiverCoping',tuple(c),tuple(d),.004,'stone',6)
            for x in [-.47,-.28,.28,.47]:
                z=math.sin((x+.6)/1.2*math.tau)*.043+sign*.145
                rock('RiversideRock',x,.042,z,.034)
                for k in range(3):rod('RiversideReeds',(x,.044,z),(x+.01*math.cos(k*2),.11+.009*k,z+.012*math.sin(k*2)),.0015,'foliage',5)
    elif key=='coast':
        pad('CoastalWater',1,.6,'water')
        outline=[(-.5,.048,-.3),(-.5,.048,.3),(-.24,.048,.3),(-.14,.048,.17),(-.20,.048,.04),(-.09,.048,-.15),(-.15,.048,-.3)]
        mesh('CoastalHeadland',outline,[(0,1,2,3,4,5,6)],'stone_warm')
        for i in range(2,len(outline)-1):
            a=outline[i];b=outline[i+1]
            for j in range(4):
                x=a[0]+(b[0]-a[0])*j/4;z=a[2]+(b[2]-a[2])*j/4
                rock('CoastalRipRap',x,.031,z,.050)
        box('HarbourQuay',(-.12,.070,-.18),(.36,.080,.17),'stone_warm',.009)
        box('HarbourQuayEdge',(.062,.12,-.18),(.016,.013,.17),'stone',.002)
        for z in [-.24,-.16,-.09]:cylinder('MooringBollard',(.020,.125,z),.010,.025,'stone_dark',10)
        for z in [-.20,.10]:
            box('HarbourBreakwater',(.25,.046,z),(.37,.046,.029),'stone_warm',.004)
            for x in [.12,.24,.37]:box('BreakwaterCap',(x,.074,z),(.09,.008,.034),'stone',.001)
        cylinder('HarbourBeacon',(.41,.115,-.20),.024,.085,'stone',16);cylinder('BeaconLantern',(.41,.167,-.20),.027,.025,'oxide_red',16)
        for x,z in [(-.42,.17),(-.35,-.03)]:small_shrub('CoastalScrub',x,.05,z,.065)
    elif key=='bridge':
        # Stone arched abutments, curved deck, continuous rail and individually laid planks.
        for x in [-.37,.37]:
            box('BridgeStoneAbutment',(x,.095,0),(.12,.19,.31),'stone_warm',.006)
            for y in [.045,.09,.135]:box('BridgeMasonryCourse',(x,y,.159),(.115,.003,.002),'crevice',0)
        for i in range(26):
            x=-.48+i*.96/25;y=.212+.035*(1-(x/.48)**2)
            box('BridgeDeckPlank',(x,y,0),(.035,.024,.36),'walnut',.001)
        for z in [-.178,.178]:
            for i in range(24):
                x=-.48+i*.96/24;xx=x+.96/24;y=.326+.035*(1-(x/.48)**2);yy=.326+.035*(1-(xx/.48)**2)
                rod('BridgeTopRail',(x,y,z),(xx,yy,z),.0055,'brass',8)
                rod('BridgeLowerBeam',(x,y-.123,z),(xx,yy-.123,z),.010,'stone_dark',8)
            for x in [-.46,-.345,-.23,-.115,0,.115,.23,.345,.46]:
                y=.326+.035*(1-(x/.48)**2);rod('BridgeBaluster',(x,y-.09,z),(x,y,z),.0045,'brass',7)
    elif key=='ship':
        # Planked research-vessel hull with raised bow, working afterdeck and wheelhouse.
        sections=[(-.47,.070,.100),(-.39,.130,.128),(-.13,.152,.142),(.17,.137,.148),(.34,.092,.170),(.47,.003,.195)]
        pts=[]
        for x,w,h in sections:
            pts.extend([(x,.032,0),(x,.061,-w*.65),(x,h,-w),(x,h,w),(x,.061,w*.65)])
        faces=[]
        for i in range(len(sections)-1):
            for j in range(5):faces.append((i*5+j,i*5+(j+1)%5,(i+1)*5+(j+1)%5,(i+1)*5+j))
        faces += [tuple(range(4,-1,-1)),tuple(range(25,30))]
        ob=mesh('ResearchVesselHull',pts,faces,'leather_blue')
        for p in ob.data.polygons:p.use_smooth=True
        deck=[]
        for x,w,h in sections:deck.append((x,h+.003,-w*.91))
        for x,w,h in reversed(sections):deck.append((x,h+.003,w*.91))
        mesh('ShipTeakDeck',deck,[tuple(range(len(deck)))],'walnut')
        for side in [-1,1]:
            for i in range(len(sections)-1):
                x,w,h=sections[i];xx,ww,hh=sections[i+1]
                rod('VesselGunwale',(x,h,side*w),(xx,hh,side*ww),.006,'stone_warm',8)
                rod('VesselSafetyRail',(x,h+.068,side*w),(xx,hh+.068,side*ww),.003,'brass',6)
                for t in [0,.5]:
                    ax=x+(xx-x)*t;aw=w+(ww-w)*t;ah=h+(hh-h)*t
                    rod('VesselRailStanchion',(ax,ah,side*aw),(ax,ah+.068,side*aw),.0025,'stone',6)
        box('WheelhouseLower',(.02,.227,0),(.32,.15,.225),'stone_warm',.008)
        box('WheelhouseGlazing',(.03,.332,0),(.28,.087,.218),'leather_blue',.010)
        box('WheelhouseRoof',(.03,.389,0),(.33,.025,.26),'stone',.005)
        for x in [-.09,-.015,.06,.135]:
            for z in [-.112,.112]:rod('WheelhouseWindowFrame',(x,.297,z),(x,.371,z),.003,'stone_warm',6)
        for z in [-.075,0,.075]:rod('BridgeFrontMullion',(.173,.298,z),(.173,.369,z),.003,'stone_warm',6)
        rod('RadarMast',(-.03,.40,0),(-.03,.63,0),.006,'stone_warm',8)
        rod('RadarYard',(-.15,.55,0),(.09,.55,0),.006,'stone_warm',8)
        box('RotatingRadar',(-.03,.637,0),(.17,.015,.025),'stone',.002)
        cylinder('ShipFunnel',(-.17,.26,0),.041,.18,'oxide_red',18)
        for z in [-.087,.087]:ellipse('InflatableLiferaft',(-.18,.245,z),(.059,.025),.028,'stone',20)
        cylinder('AftWinch',(-.35,.178,0),.038,.035,'brass',18)
        rod('AftSamplingCrane',(-.40,.15,-.06),(-.40,.41,-.06),.009,'stone_warm',10)
        rod('AftSamplingCrane',(-.40,.41,-.06),(-.27,.46,-.06),.008,'stone_warm',10)
        rod('CraneCable',(-.27,.46,-.06),(-.27,.18,-.06),.0017,'crevice',5)
        for x in [.24,.31]:cylinder('ForedeckBollard',(x,.20,0),.010,.027,'stone_dark',10)
    elif key=='workshop':
        pad('TechnicalWorkshop',1,.5,'stone_warm')
        # Open front reveals the work floor; rooflights retain the sawtooth silhouette.
        box('WorkshopRearBrickWall',(0,.18,-.215),(.96,.31,.035),'clay',.003)
        for x in [-.475,.475]:box('WorkshopSideWall',(x,.18,0),(.035,.31,.43),'clay',.003)
        for x in [-.46,-.16,.16,.46]:rod('SteelWorkshopColumn',(x,.025,.20),(x,.34,.20),.010,'stone_dark',8)
        box('WorkshopEavesBeam',(0,.34,.20),(.96,.020,.027),'stone_dark',.002)
        for x in [-.32,0,.32]:
            # Asymmetric north-light section, rear opaque pitch and clear upright glazing.
            pts=[(x-.155,.347,-.23),(x+.155,.347,-.23),(x+.100,.515,-.23),(x-.155,.347,.23),(x+.155,.347,.23),(x+.100,.515,.23)]
            mesh('SawtoothOpaqueRoof',pts,[(0,2,5,3)],'stone_dark')
            mesh('SawtoothNorthlight',pts,[(2,1,4,5)],'leather_blue')
            for z in [-.23,0,.23]:rod('RooflightSteelRafter',(x-.155,.347,z),(x+.100,.515,z),.004,'stone_warm',7)
            for zz in [-.13,.0,.13]:rod('RooflightMullion',(x+.155,.347,zz),(x+.100,.515,zz),.003,'stone_warm',6)
        for x in [-.31,.0,.31]:
            box('WorkshopMachineCabinet',(x,.102,-.04),(.18,.15,.22),'leather_green',.004)
            box('WorkshopMachineBed',(x,.188,-.04),(.21,.022,.25),'stone',.002)
            rod('WorkshopMachineUpright',(x-.055,.20,-.11),(x-.055,.30,-.11),.007,'stone_dark',8)
            rod('WorkshopCrosshead',(x-.055,.30,-.11),(x+.075,.30,-.11),.009,'stone_dark',8)
            cylinder('WorkshopSpindle',(x+.057,.251,-.065),.015,.09,'brass',12)
        for x in [-.30,.30]:box('WorkshopSafetyFloorStripe',(x,.0235,.15),(.24,.002,.013),'ochre',0)
    elif key=='stage':
        pad('PerformanceCourt',1,.5,'stone_warm')
        # Deep fan seating, two radial aisles, individual bench boards.
        for j in range(5):
            r=.17+j*.065;y=.040+j*.044;n=36
            for i in range(n):
                if i in [10,11,24,25]:continue
                a=math.pi+i*math.pi/n;b=math.pi+(i+1)*math.pi/n
                pts=[(math.cos(a)*r,y,math.sin(a)*r*.49+.20),(math.cos(b)*r,y,math.sin(b)*r*.49+.20),(math.cos(b)*(r+.045),y,math.sin(b)*(r+.045)*.49+.20),(math.cos(a)*(r+.045),y,math.sin(a)*(r+.045)*.49+.20)]
                mesh('AmphitheatreBenchBoards',pts,[(0,1,2,3)],'walnut')
                mesh('AmphitheatreStoneRiser',pts+[tuple(Vector(p)-Vector((0,.041,0))) for p in pts],[(2,3,7,6)],'stone_warm')
        box('PerformanceStage',(0,.080,.17),(.40,.10,.15),'walnut',.004)
        for x in [-.43,.43]:
            for z in [-.22,-.18]:rod('TheatreTrussTower',(x,.025,z),(x,.67,z),.007,'stone_dark',8)
            for y in [.10,.20,.30,.40,.50,.60]:rod('TheatreTrussBrace',(x,y,-.22),(x,y+.06,-.18),.003,'brass',6)
        for y in [.65,.69]:rod('StageLightingTruss',(-.43,y,-.20),(.43,y,-.20),.007,'stone_dark',8)
        for i in range(12):
            x=-.43+i*.86/12;rod('TrussDiagonal',(x,.65,-.20),(x+.86/12,.69,-.20),.0025,'brass',6)
        for x in [-.31,-.10,.10,.31]:
            box('StageSpotlight',(x,.625,-.19),(.043,.050,.050),'stone_dark',.004)
            cylinder('StageLampLens',(x,.594,-.182),.019,.008,'lamp',12)
    elif key=='ntu_bell':
        # NTU Alumni Bimonthly: circular raised platform, eight short piers,
        # four dark red iron members rising and fanning out above the bell.
        ellipse('FuBellLowerStep',(0,0,0),(.43,.23),.014,'stone_warm',64)
        ellipse('FuBellRaisedPlaza',(0,.014,0),(.37,.20),.036,'stone',64)
        ellipse('FuBellInlaidCircle',(0,.050,0),(.29,.16),.003,'stone_warm',64)
        for i in range(8):
            a=i*math.tau/8;x=math.cos(a)*.365;z=math.sin(a)*.191
            cylinder('FuBellEightStonePiers',(x,.088,z),.017,.078,'stone_warm',16)
            cylinder('FuBellPierCap',(x,.130,z),.020,.008,'stone',16)
        for i in [0,2,4,6]:
            a=(i+.5)*math.tau/8
            for j in range(3):
                r=.31+j*.025;box('FuBellRadialSteps',(math.cos(a)*r,.014+j*.010,math.sin(a)*r*.52),(.069,.012,.032),'stone_warm',.002)
        for sx,sz in [(-1,-1),(-1,1),(1,-1),(1,1)]:
            points=[(sx*.15,.05,sz*.095),(sx*.135,.38,sz*.080),(sx*.21,.76,sz*.123),(sx*.31,.95,sz*.17)]
            for a,b in zip(points,points[1:]):rod('FuBellRedSplayedSteel',a,b,.016,'oxide_red',12)
            box('FuBellSteelFoot',(sx*.15,.066,sz*.095),(.062,.022,.050),'oxide_red',.003)
            rod('FuBellCrownTie',(sx*.21,.76,sz*.123),(0,.73,0),.008,'oxide_red',10)
        rod('FuBellSuspension',(0,.72,0),(0,.62,0),.010,'stone_dark',10)
        rings=[(.305,.132),(.322,.129),(.35,.105),(.40,.086),(.51,.065),(.565,.047),(.578,.025)]
        pts=[(math.cos(j*math.tau/40)*r,y,math.sin(j*math.tau/40)*r) for y,r in rings for j in range(40)]
        ob=mesh('FuBellPatinatedBronze',pts,[(k*40+j,k*40+(j+1)%40,(k+1)*40+(j+1)%40,(k+1)*40+j) for k in range(len(rings)-1) for j in range(40)],'bronze_patina')
        for p in ob.data.polygons:p.use_smooth=True
        for y,r in [(.312,.132),(.345,.109),(.515,.065)]:
            for j in range(40):
                a=j*math.tau/40;b=(j+1)*math.tau/40;rod('FuBellCastBronzeRing',(math.cos(a)*r,y,math.sin(a)*r),(math.cos(b)*r,y,math.sin(b)*r),.0035,'brass',6)
        cylinder('FuBellClapper',(0,.29,0),.014,.072,'brass',14)

if '3d_printer' not in COMPONENT_KEYS:COMPONENT_KEYS.append('3d_printer')
