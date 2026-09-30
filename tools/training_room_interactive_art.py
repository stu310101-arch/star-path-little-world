"""Scale the detailed lounge and add purposeful, light game furnishings."""
import bpy, math
from mathutils import Matrix, Vector


def enlarge_lounge(objects):
    pivot=Vector((-8.60,-7.82,.035))
    transform=Matrix.Translation(pivot) @ Matrix.Diagonal((1.16,1.16,1.16,1)) @ Matrix.Translation(-pivot)
    for o in objects:
        if o.name.startswith('LOUNGE_') or o.name.startswith('Coffee table miniature'):
            o.matrix_world=transform @ o.matrix_world
            if o.name.startswith('LOUNGE_Coffee_table') or o.name.startswith('Coffee table miniature'):
                o.location.x+=.25
                o.location.y+=.15
    return transform


def build_interactive_decor(collection,M):
    collider_groups={}
    targets=[]

    def mesh(name,vs,fs,mat,smooth=False):
        data=bpy.data.meshes.new(name);data.from_pydata(vs,[],fs);data.update()
        ob=bpy.data.objects.new('DECOR | '+name,data);collection.objects.link(ob);data.materials.append(M[mat])
        for p in data.polygons:p.use_smooth=smooth
        return ob

    def box(name,loc,size,mat,bevel=.02,collider=None):
        x,y,z=[v/2 for v in size]
        ob=mesh(name,[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)],[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],mat)
        ob.location=loc
        if bevel:
            mod=ob.modifiers.new('Soft joinery','BEVEL');mod.width=bevel;mod.segments=3
            ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
        if collider:collider_groups.setdefault(collider,[]).append(ob)
        return ob

    def line(name,pts,mat='wood_dark',radius=.008,closed=False):
        d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=radius;d.bevel_resolution=2
        s=d.splines.new('POLY');s.points.add(len(pts)-1)
        for p,v in zip(s.points,pts):p.co=(*v,1)
        s.use_cyclic_u=closed
        ob=bpy.data.objects.new('DECOR | '+name,d);collection.objects.link(ob);d.materials.append(M[mat]);return ob

    def lathe(name,loc,profile,mat):
        vs=[];fs=[];n=40
        for radius,z in profile:
            for i in range(n):
                a=i*math.tau/n;vs.append((loc[0]+radius*math.cos(a),loc[1]+radius*math.sin(a),loc[2]+z))
        for j in range(len(profile)-1):
            for i in range(n):q=(i+1)%n;fs.append((j*n+i,j*n+q,(j+1)*n+q,(j+1)*n+i))
        return mesh(name,vs,fs,mat,True)

    def tag(objects,name,pivot):
        for ob in objects:ob['interactive_root']=name;ob['interactive_pivot']=list(pivot)

    # A woven area rug connects the bookcase and reading seat into a single bay.
    box('reading woven rug',(8.22,-3.64,.056),(2.54,5.92,.025),'rug',.08)
    for inset in [0,.07]:
        x0,x1=7.03+inset,9.42-inset;y0,y1=-6.50+inset,-.79-inset
        line('reading rug woven border',[(x0,y0,.073),(x1,y0,.073),(x1,y1,.073),(x0,y1,.073)],'sage',.006,True)
    # Entry console is against the wall, leaving a generous route to the portal.
    console_objects=set(collection.objects)
    box('welcome console carcass',(5.0,-8.55,.48),(2.7,.58,.62),'wood',.055,'Welcome_Console')
    box('welcome console stone top',(5.0,-8.55,.817),(2.79,.64,.07),'cream',.035)
    for x in [3.87,6.13]:
        for y in [-8.73,-8.37]:box('welcome console tapered foot',(x,y,.13),(.10,.10,.22),'dark_teal',.012)
    for x in [4.34,5.66]:
        box('welcome console recessed door',(x,-8.246,.48),(1.24,.022,.48),'wood_dark',.015)
        for dx in [-.50,-.38,-.26,-.14,-.02,.10,.22,.34,.46]:
            box('welcome console fluted door',(x+dx,-8.225,.48),(.065,.025,.43),'wood',.015)
        line('welcome console pull',[(x+.43,-8.198,.44),(x+.43,-8.198,.56)],'gold',.012)
    lathe('tall ceramic vase',(4.2,-8.5,.852),[(.05,0),(.16,.04),(.18,.18),(.13,.36),(.068,.48),(.07,.52),(.054,.52),(.052,.46)],'sage')
    lathe('wide ceramic bowl',(4.72,-8.48,.852),[(.08,0),(.18,.035),(.22,.12),(.215,.14),(.20,.13),(.17,.05),(.07,.02)],'cream')
    lathe('small ceramic vase',(5.88,-8.48,.852),[(.05,0),(.13,.07),(.12,.22),(.065,.31),(.052,.32),(.046,.30)],'teal')
    for shift in [-.12,0,.10]:
        line('vase dry botanical stem',[(4.2,-8.5,1.28),(4.2+shift,-8.48,1.66+abs(shift))],'wood_dark',.006)
        for n in range(4):
            z=1.42+n*.065;s=(-1 if n%2 else 1)
            mesh('vase dry botanical leaf',[(4.2+shift*.5,-8.48,z),(4.2+shift*.5+s*.12,-8.47,z+.02),(4.2+shift*.5+s*.055,-8.465,z+.05)],[(0,1,2)],'gold')
    tag(set(collection.objects)-console_objects,'DECOR_Console',(5,-8.55,.85))
    targets.append(dict(id='welcome_console',label='陶藝與木作',position=[5.0,.95,8.13],approach=[5,.04,7.4],kind='decoration',node_name='DECOR_Console',collider_name='Welcome_Console'))

    # A slender curved reading lamp with a hollow shade, not a solid cone.
    lx,ly=-3.43,-7.1
    base=lathe('reading lamp weighted foot',(lx,ly,.04),[(0,0),(.26,0),(.30,.035),(.29,.075),(.22,.10),(0,.10)],'dark_teal')
    collider_groups['Reading_Floor_Lamp']=[base]
    points=[(lx,ly,.10),(lx,ly,1.70)]
    points += [(lx-.37+.37*math.cos(a),ly,1.70+.37*math.sin(a)) for a in [i*math.pi/2/20 for i in range(21)]]
    points.append((lx-.37,ly,1.975))
    line('reading lamp formed arm',points,'wood_dark',.018)
    shadecenter=(lx-.37,ly,1.64)
    shade=lathe('reading lamp linen shade',shadecenter,[(.29,0),(.17,.32),(.16,.34),(.146,.33),(.276,.008),(.29,0)],'rug')
    diffuser=lathe('reading lamp warm diffuser',shadecenter,[(0,.013),(.276,.013),(.27,.026),(0,.026)],'white_light')
    tag([diffuser],'LAMP_Reading',shadecenter)
    targets.append(dict(id='reading_lamp',label='閱讀落地燈',position=[lx,1.45,-ly],approach=[-2.4,.04,7.1],kind='lamp',node_name='LAMP_Reading',light_position=[lx-.37,1.64,-ly],collider_name='Reading_Floor_Lamp'))

    # A real cup and saucer sit on a tray; the cup remains individually pickable.
    tx,ty=-4.69,-5.30
    box('tea tray',(tx,ty,.526),(.67,.46,.035),'wood_dark',.028)
    for x in [tx-.31,tx+.31]:box('tea tray low rim',(x,ty,.555),(.028,.46,.045),'wood',.009)
    lathe('tea saucer',(tx+.13,ty,.546),[(0,0),(.108,.005),(.13,.015),(.128,.03),(.094,.022),(0,.018)],'cream')
    before=set(collection.objects)
    lathe('tea cup',(tx+.13,ty,.563),[(.043,0),(.057,.035),(.062,.11),(.060,.124),(.051,.124),(.048,.04),(.036,.012)],'cream')
    pts=[]
    for i in range(25):
        a=-math.pi*.63+i*math.pi*1.26/24;pts.append((tx+.178+.04*math.cos(a),ty,.633+.04*math.sin(a)))
    line('tea cup loop handle',pts,'cream',.009)
    tag(set(collection.objects)-before,'TEA_Cup',(tx+.13,ty,.62))
    lathe('tea carafe',(tx-.14,ty,.546),[(.055,0),(.075,.03),(.076,.13),(.040,.21),(.039,.25),(.032,.25),(.03,.20)],'teal')
    targets.append(dict(id='tea_cup',label='茶杯',position=[tx+.13,.64,-ty],approach=[-3.8,.04,5.3],kind='tea',node_name='TEA_Cup',collider_name='Coffee_Table'))

    # Clock and plant reliefs add authored visual rhythm above the long sofa.
    botanical_objects=set(collection.objects)
    cy,cz=-5.10,2.11
    ring=[(-9.81,cy+.34*math.cos(t*math.tau/80),cz+.34*math.sin(t*math.tau/80)) for t in range(80)]
    line('wall clock oak rim',ring,'wood_dark',.025,True)
    verts=[(-9.82,cy,cz)]+[(-9.82,cy+.325*math.cos(t*math.tau/80),cz+.325*math.sin(t*math.tau/80)) for t in range(80)]
    mesh('wall clock cream face',verts,[(0,i+1,(i+1)%80+1) for i in range(80)],'cream')
    for i in range(12):
        a=i*math.tau/12
        line('wall clock hour marker',[(-9.785,cy+.26*math.cos(a),cz+.26*math.sin(a)),(-9.785,cy+.29*math.cos(a),cz+.29*math.sin(a))],'dark_teal',.009)
    line('wall clock minute hand',[(-9.77,cy,cz),(-9.77,cy-.18,cz+.15)],'dark_teal',.012)
    line('wall clock hour hand',[(-9.76,cy,cz),(-9.76,cy+.11,cz+.08)],'gold',.018)
    for yy in [-6.39,-3.83]:
        box('botanical framed backing',(-9.855,yy,2.02),(.10,.66,.90),'wood',.02)
        box('botanical woven mat',(-9.790,yy,2.02),(.025,.55,.78),'cream',.005)
        line('botanical relief stem',[(-9.768,yy-.08,1.74),(-9.768,yy+.03,2.29)],'sage',.010)
        for i in range(5):
            z=1.84+i*.085;s=-1 if i%2 else 1
            mesh('botanical relief leaf',[(-9.75,yy-.03,z),(-9.741,yy+s*.16,z+.045),(-9.741,yy+s*.11,z+.11)],[(0,1,2)],'teal')
    tag(set(collection.objects)-botanical_objects,'DECOR_Botanical',(-9.8,-5.1,2.05))
    targets.append(dict(id='botanical_wall',label='植物浮雕與掛鐘',position=[-9.70,2.03,5.10],approach=[-6.55,.04,4.5],kind='decoration',node_name='DECOR_Botanical',collider_name='Sofa_Left_Run'))
    targets.append(dict(id='starry_night',label='梵谷・星空',position=[9.70,1.90,7.15],approach=[8.3,.04,7.15],kind='painting',node_name='PAINTING_StarryNight',collider_name='Reading_Painting'))
    return collider_groups,targets
