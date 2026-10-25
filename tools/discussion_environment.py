"""Five authored, distinct places linked by a landscaped walking hub.

Executed by build_discussion_garden.py in its Blender authoring namespace.
User selected independent production from the generated visual references.
"""
import struct
import numpy as np

VEGETATION = ROOT / "game/assets/vegetation_rebuilt"
ASSET_CACHE = {}
material("brick",(.43,.17,.085),.86)
material("concrete",(.43,.46,.44),.88)
material("steel",(.075,.09,.095),.42,.72)
material("oak",(.55,.36,.17),.56,texture="walnut")
material("roof",(.12,.15,.16),.75)
material("glass",(.13,.22,.25),.19,.35)
material("water",(.065,.22,.23),.24,.22)
material("grass",(.17,.235,.145),.95)
material("forest_floor",(.13,.18,.11),1)
material("paving_dark",(.20,.255,.25),.91)
material("contact",(.105,.125,.105),1)
material("hill_near",(.19,.28,.22),1)
material("hill_far",(.30,.405,.395),1)
material("linen",(.58,.54,.43),.97)

# Brick is an original seamless material, with readable mortar and restrained
# per-brick variation; it does not rely on a Blender-only shader at export.
def bake_brick():
    n=512
    yy,xx=np.mgrid[0:n,0:n]
    row=yy//32
    shifted=(xx+(row%2)*51)%n
    mortar=(yy%32<3)|(shifted%102<3)
    noise=np.random.default_rng(82).random((n,n))*.07
    cell=((shifted//102+row*7)%9)/9
    pix=np.ones((n,n,4),dtype=np.float32)
    for i,v in enumerate((.46,.20,.105)):
        pix[:,:,i]=v*(.84+cell*.22)+noise
        pix[:,:,i][mortar]=(.55,.51,.43)[i]+noise[mortar]*.2
    im=bpy.data.images.new("Garden_Brick_Base",width=n,height=n)
    im.pixels.foreach_set(pix.ravel())
    im.pack()
    mat=MATS["brick"]
    node=mat.node_tree.nodes.new("ShaderNodeTexImage");node.image=im
    bsdf=next(n for n in mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
    mat.node_tree.links.new(node.outputs["Color"],bsdf.inputs["Base Color"])

bake_brick()

def bake_surface(key, base, amplitude=.03):
    """Small seamless grain maps share the existing world's 1.2m UV scale."""
    n=512;random=np.random.default_rng(900+sum(map(ord,key)))
    noise=random.normal(size=(n,n));frequencies=np.fft.fftfreq(n)*n
    fy,fx=np.meshgrid(frequencies,frequencies)
    # Isotropic filtered noise has no sinusoidal bands or directional pattern.
    broad=np.fft.ifft2(np.fft.fft2(noise)*np.exp(-(fx*fx+fy*fy)/48.0)).real
    broad/=max(1e-6,float(broad.std()))
    grain=np.clip(broad*.14+random.normal(size=(n,n))*.025,-.4,.4)
    pix=np.ones((n,n,4),dtype=np.float32)
    for channel,value in enumerate(base):pix[:,:,channel]=np.clip(value+grain*amplitude,0,1)
    im=bpy.data.images.new("Garden_"+key+"_Grain",width=n,height=n);im.pixels.foreach_set(pix.ravel());im.pack()
    node=MATS[key].node_tree.nodes.new("ShaderNodeTexImage");node.image=im
    bsdf=next(n for n in MATS[key].node_tree.nodes if n.type=="BSDF_PRINCIPLED")
    MATS[key].node_tree.links.new(node.outputs["Color"],bsdf.inputs["Base Color"])
    uv_metres=5.0 if key in ("grass","forest_floor") else 2.4
    MATS[key]["uv_metres"]=uv_metres
    ASSET_AUDIT["surface_"+key]={"resolution":[512,512],"originalProcedural":True,"uvMetres":uv_metres}

for key,base,amplitude in [("grass",(.17,.235,.145),.10),("forest_floor",(.13,.18,.11),.09),
    ("concrete",(.43,.46,.44),.055),("sand",(.43,.38,.27),.08),("paving_dark",(.20,.255,.25),.055)]:
    bake_surface(key,base,amplitude)
# The oak has its own baked colour copy, retaining the project's timber grain.
for n in MATS["oak"].node_tree.nodes:
    if n.type=="TEX_IMAGE" and n.image and n.image.colorspace_settings.name=="sRGB":
        a=np.array(n.image.pixels[:],dtype=np.float32).reshape((-1,4))
        a[:,:3]=np.clip(a[:,:3]*1.12+np.array([.07,.06,.037]),0,.80)
        n.image.pixels.foreach_set(a.ravel());n.image.pack()

def leaf_cards(source, keep, label):
    """Flatten each existing bent 8-triangle atlas spray to 2 triangles.

    UVs and crown normals are retained. Uniform deterministic thinning spreads
    cards through the crown rather than deleting the back half of the tree.
    """
    adjacent=[set() for _ in source.vertices]
    for edge in source.edges:
        a,b=edge.vertices;adjacent[a].add(b);adjacent[b].add(a)
    uv_by_vertex={}
    for loop in source.loops: uv_by_vertex[loop.vertex_index]=tuple(source.uv_layers.active.data[loop.index].uv)
    seen=set();components=[]
    for index in range(len(adjacent)):
        if index in seen:continue
        stack=[index];seen.add(index);component=[]
        while stack:
            current=stack.pop();component.append(current)
            for nxt in adjacent[current]:
                if nxt not in seen: seen.add(nxt);stack.append(nxt)
        components.append(component)
    verts=[];faces=[];uvs=[]
    for index,component in enumerate(components):
        if (index*0.61803398875)%1 >= keep:continue
        if len(component)<4:continue
        corners=[min(component,key=lambda v:(uv_by_vertex[v][0]-u)**2+(uv_by_vertex[v][1]-v2)**2) for u,v2 in [(0,0),(1,0),(1,1),(0,1)]]
        if len(set(corners))<4:continue
        center=sum((source.vertices[c].co for c in corners),Vector())/4
        scale=1.08 if keep>.6 else 1.22
        start=len(verts)
        verts.extend(tuple(center+(source.vertices[c].co-center)*scale) for c in corners)
        uvs.extend(uv_by_vertex[c] for c in corners);faces.append(tuple(start+i for i in range(4)))
    data=bpy.data.meshes.new(label);data.from_pydata(verts,[],faces);data.update()
    for mat in source.materials:data.materials.append(mat)
    layer=data.uv_layers.new(name="UV_Surface")
    for loop in data.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
    for poly in data.polygons:poly.use_smooth=True
    if verts:
        height=max(v[2] for v in verts)
        data.normals_split_custom_set([tuple(Vector((verts[loop.vertex_index][0]*.25,verts[loop.vertex_index][1]*.25,.7+(verts[loop.vertex_index][2]-height*.6)*.14)).normalized()) for loop in data.loops])
    return data

def simplified_branch(source, ratio, label):
    temp=bpy.data.objects.new("ExportBranchAudit",source.copy());scene.collection.objects.link(temp)
    mod=temp.modifiers.new("Silhouette-preserving branch reduction","DECIMATE");mod.ratio=ratio
    graph=bpy.context.evaluated_depsgraph_get();data=bpy.data.meshes.new_from_object(temp.evaluated_get(graph),depsgraph=graph)
    data.name=label;bpy.data.objects.remove(temp,do_unlink=True)
    return data

def asset(kind,p,scale=1,yaw=0):
    """Instance existing production botanical meshes, not dot-like leaves."""
    if kind not in ASSET_CACHE:
        before=set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=str(VEGETATION/(kind+".glb")))
        created=set(bpy.data.objects)-before
        entries=[]
        for ob in sorted(created,key=lambda o:o.name):
            if ob.type!="MESH":continue
            source=ob.data
            if "Foliage" in ob.name:
                high=leaf_cards(source,.82,"Garden_"+kind+"_Canopy");low=leaf_cards(source,.40,"Garden_"+kind+"_CanopyLow")
            elif kind!="fern":
                high=simplified_branch(source,.68,"Garden_"+kind+"_Branches");low=simplified_branch(source,.28,"Garden_"+kind+"_BranchesLow")
            else:
                high=source;low=simplified_branch(source,.45,"Garden_FernLow")
            low.use_fake_user=True
            entries.append((high,low,ob.matrix_world.copy()))
            high.calc_loop_triangles();low.calc_loop_triangles();source.calc_loop_triangles()
            ASSET_AUDIT[ob.name]={"originalTriangles":len(source.loop_triangles),"highTriangles":len(high.loop_triangles),"lowTriangles":len(low.loop_triangles)}
        ASSET_CACHE[kind]=entries
        for ob in created: bpy.data.objects.remove(ob,do_unlink=True)
    v=(scale,scale,scale) if isinstance(scale,(float,int)) else (scale[0],scale[2],scale[1])
    transform=FRAME @ Matrix.Translation(gv(p)) @ Matrix.Rotation(yaw,4,"Z") @ Matrix.Diagonal((*v,1))
    for i,(data,low,local) in enumerate(ASSET_CACHE[kind]):
        ob=bpy.data.objects.new("SM_"+kind+"_"+str(i),data)
        COL.objects.link(ob);ob.matrix_world=transform @ local;ob["botanical_low_mesh"]=low.name
    if kind!="fern":
        contact_patch("TreeRootContact",p,(.58*scale,.58*scale) if isinstance(scale,(int,float)) else (.6,.6))

def contact_patch(name,p,span):
    # Opaque two-tone grounding inside the object footprint: no transparency,
    # realtime light or shadow-map required on low-end renderers.
    points=[(p[0],p[1]+.006,p[2])]
    for i in range(12):
        a=i*math.tau/12;r=.92+.06*math.sin(i*2.6)
        points.append((p[0]+math.cos(a)*span[0]*r,p[1]+.006,p[2]+math.sin(a)*span[1]*r))
    return mesh(name,points,[(0,1+i,1+(i+1)%12) for i in range(12)],"contact")

def district_floor(name,p,size,mat,front_cut=3):
    """Chamfered level floor clipped at neighbouring district bisectors.

    Compact districts can share a continuous campus without two coplanar slabs
    fighting at the boundary. Collision ground stays level and uninterrupted.
    """
    w,h,d=size;w/=2;d/=2
    outline=[(-w,-d),(w,-d),(w,d-front_cut),(w-front_cut,d),(-w+front_cut,d),(-w,d-front_cut)]
    world=[]
    for x,z in outline:
        q=FRAME@gv((x+p[0],0,z+p[2]));world.append((q.x,-q.y))
    origin=FRAME@gv((0,0,0));own=(origin.x,-origin.y)
    for _,_,other in ZONE_SPECS:
        delta=(other[0]-own[0],other[2]-own[1])
        if math.hypot(*delta)<.01:continue
        limit=(other[0]**2+other[2]**2-own[0]**2-own[1]**2)/2
        output=[];a=world[-1];va=limit-a[0]*delta[0]-a[1]*delta[1]
        for b in world:
            vb=limit-b[0]*delta[0]-b[1]*delta[1]
            if (va>=0)!=(vb>=0):
                t=va/(va-vb);output.append((a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])))
            if vb>=0:output.append(b)
            a,va=b,vb
        world=output
    inv=FRAME.inverted();points=[]
    for y in [p[1]-h/2,p[1]+h/2]:
        for x,z in world:
            q=inv@gv((x,y,z));points.append((q.x,q.z,-q.y))
    n=len(world)
    return mesh(name,points,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)

def broadleaf(name,p,scale=1):
    pts,faces=[],[]
    for j in range(11):
        a=j*2.399
        length=(.42+.25*(j%3)/2)*scale
        width=(.09+.025*(j%2))*scale
        base=len(pts)
        for k in range(6):
            t=k/5
            radius=length*t*.8
            height=length*(math.sin(t*2.3)*.7+.05)
            w=width*max(.015,math.sin(math.pi*t))
            for side in [-1,0,1]:
                pts.append((p[0]+math.cos(a)*radius-math.sin(a)*w*side,p[1]+height-(abs(side)*.035*scale),p[2]+math.sin(a)*radius+math.cos(a)*w*side))
        for k in range(5):
            for side in range(2):
                x=base+k*3+side;faces.append((x,x+1,x+4,x+3))
    return mesh(name,pts,faces,"leaf" if rng.random()<.6 else "leaf_light")

def flowers(name,p,scale=1):
    for j in range(5):
        a=j*2.399
        q=(p[0]+math.cos(a)*.18*scale,p[1]+(.25+j*.035)*scale,p[2]+math.sin(a)*.18*scale)
        rod(name+"_Stem",p,q,.007*scale,"leaf",6)
        for k in range(5):
            angle=k*math.tau/5
            pp=(q[0]+math.cos(angle)*.036*scale,q[1],q[2]+math.sin(angle)*.036*scale)
            cylinder(name+"_Petal",pp,.035*scale,.013*scale,"paper",segments=6)
        cylinder(name+"_Centre",(q[0],q[1]+.012*scale,q[2]),.018*scale,.014*scale,"flower",segments=8)

def planter(name,p,size,mat="stone"):
    w,h,d=size
    round_box(name,p,size,min(.18,w*.12,d*.12),mat)
    box(name+"_Soil",(p[0],p[1]+h/2+.006,p[2]),(w-.15,.018,d-.15),"soil",0)
    collision(name,p,size)
    count=max(2,int(w*d*.42))
    # The soil is visible between deliberate planting clusters.
    for j in range(count):
        pp=(p[0]+rng.uniform(-w*.37,w*.37),p[1]+h/2+.02,p[2]+rng.uniform(-d*.33,d*.33))
        broadleaf(name+"_Leaf",pp,rng.uniform(.7,1.25))
        if j%4==0: flowers(name+"_Flowers",pp,.65)

def arc_band(name,p,radius,width,height,start,end,mat="stone",segments=32):
    pts=[]
    for y in [p[1],p[1]+height]:
        for r in [radius-width/2,radius+width/2]:
            for j in range(segments+1):
                a=start+(end-start)*j/segments
                pts.append((p[0]+math.sin(a)*r,y,p[2]+math.cos(a)*r))
    n=segments+1;faces=[]
    for j in range(segments):
        faces += [(j,j+1,n+j+1,n+j),(2*n+j,3*n+j,3*n+j+1,2*n+j+1),
                  (j,2*n+j,2*n+j+1,j+1),(n+j,n+j+1,3*n+j+1,3*n+j)]
    faces += [(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)]
    return bevel(mesh(name,pts,faces,mat),.012)

def arch(name,p,width=4.0,spring=2.25,depth=.42,mat="stone"):
    r=width/2;outer=r+.32;seg=24
    pts=[]
    for z in [-depth/2,depth/2]:
        for rad in [r,outer]:
            for j in range(seg+1):
                a=math.pi*j/seg
                pts.append((p[0]+math.cos(a)*rad,p[1]+spring+math.sin(a)*rad,p[2]+z))
    n=seg+1;faces=[]
    for j in range(seg):
        faces += [(j,j+1,n+j+1,n+j),(2*n+j,3*n+j,3*n+j+1,2*n+j+1),(j,2*n+j,2*n+j+1,j+1),(n+j,n+j+1,3*n+j+1,3*n+j)]
    faces += [(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)]
    bevel(mesh(name+"_Arch",pts,faces,mat),.008)
    for x in [-outer+.16,outer-.16]:
        box(name+"_Pier",(p[0]+x,p[1]+spring/2,p[2]),(.32,spring,depth),mat,.018)
        box(name+"_Capital",(p[0]+x,p[1]+spring-.08,p[2]),(.48,.18,depth+.18),mat,.015)
        box(name+"_Foot",(p[0]+x,p[1]+.12,p[2]),(.48,.24,depth+.16),mat,.015)
        collision(name+"_Pier",(p[0]+x,p[1]+spring/2,p[2]),(.48,spring,depth+.16))

def pergola(name,p,size=(7,3.6,4),yaw=0):
    w,h,d=size
    with frame(p,yaw):
        for x in [-w/2,w/2]:
            for z in [-d/2,d/2]:
                box(name+"_Foot",(x,.22,z),(.46,.44,.46),"stone",.02)
                box(name+"_Column",(x,h/2,z),(.22,h,.22),"walnut",.014)
                collision(name+"_Column",(x,h/2,z),(.48,h,.48))
        for z in [-d/2,d/2]:box(name+"_Beam",(0,h,z),(w+.7,.24,.20),"walnut",.018)
        for j in range(int(w/.45)+1):
            x=-w/2+j*w/int(w/.45)
            box(name+"_Rafter",(x,h+.17,0),(.09,.18,d+.8),"walnut",.009)
        for x in [-w/2,w/2]:
            for y in [.7,1.5,2.3,3.1]:
                foliage(name+"_Climber",(x,y,-d/2),(.38,.48,.36),65)
        for j in range(9):
            foliage(name+"_Canopy",(-w/2+w*j/8,h+.23,-d/2),(.65,.22,.45),95)

# Device families retain the approved silhouette and use coherent, distinct
# physical material assignments per district. Public text remains code-native.
DEVICE_REPORTS={}
theme_mats={
 "university":{"walnut":"walnut","stone":"concrete","teal":"slate","brass":"brass","paper":"paper"},
 "major":{"walnut":"walnut","stone":"brick","teal":"steel","brass":"brass","paper":"paper"},
 "career":{"walnut":"steel","stone":"concrete","teal":"teal","brass":"glass","paper":"paper"},
 "high_school":{"walnut":"oak","stone":"stone","teal":"sage","brass":"steel","paper":"paper"},
 "campus":{"walnut":"walnut","stone":"stone","teal":"teal","brass":"brass","paper":"paper"}}
for ident,mapping in theme_mats.items():
    group("Device_"+ident)
    for source in GROUPS["MessageDevice"].objects:
        ob=source.copy();ob.data=source.data.copy();COL.objects.link(ob)
        ob.name=source.name+"_"+ident
        for slot in ob.material_slots:
            key=slot.material.name.removeprefix("MAT_Garden_")
            target=mapping.get(key,key)
            # Major deliberately combines an exposed metal outer frame and
            # timber column; the whole object is not recoloured uniformly.
            if ident=="major" and any(word in source.name for word in ["SideFrame","CrossFrame","Backing"]):target="steel"
            slot.material=MATS[target]
    DEVICE_REPORTS[ident]=evaluated_export([COL],"message_device_"+ident+".glb")
    COL.hide_render=True;COL.hide_viewport=True

group("GardenGround")
box("MeadowGround",(0,-.195,-5),(102,.30,106),"grass",0)
collision("MeadowGround",(0,-.20,-5),(102,.40,106))
# Landscaping serves as the distant edge; actual bounds have simple invisible
# collision barriers while the authored districts own their close-up walls.
for x in [-50.4,50.4]:collision("LandscapeBounds",(x,2,-5),(.4,4,106))
for z in [-57.4,47.4]:collision("LandscapeBounds",(0,2,z),(102,4,.4))

# Land beyond the playable bounds closes the horizon. It is a few continuous
# low-poly ridges, not dozens of costly full trees or a flat infinite plane.
group("GardenLandscape")
for layer,(rx,rz,height,key) in enumerate([(62,68,3.3,"hill_near"),(94,103,15.0,"hill_far")]):
    points=[];segments=96
    for ring in range(3):
        for i in range(segments):
            angle=i*math.tau/segments
            ripple=(math.sin(angle*3+layer*.8)+.60*math.sin(angle*7+.7)+.26*math.cos(angle*11+1.3))/1.86
            radius=1+ring*.18+.035*math.sin(angle*5+layer)
            y=-.19 if ring==0 else height*(.38+(ripple+.45)**2*.42) if ring==1 else -.3
            points.append((math.cos(angle)*rx*radius,y,-5+math.sin(angle)*rz*radius))
    faces=[]
    for ring in range(2):
        for i in range(segments):
            a=ring*segments+i;b=ring*segments+(i+1)%segments
            faces.append((a,b,b+segments,a+segments))
    ob=mesh("Garden_LandscapeRidge_"+str(layer),points,faces,key)
    for poly in ob.data.polygons:poly.use_smooth=True

group("GardenHub")
cylinder("HubPlaza",(0,-.015,0),7.2,.035,"stone",segments=96)
arc_band("HubPavingBorder",(0,.008,0),6.96,.32,.012,0,math.tau,"paving_dark",64)
for i in range(12):
    a=i*math.tau/12
    rod("HubRadialJoint",(math.sin(a)*1.4,.012,math.cos(a)*1.4),(math.sin(a)*6.6,.012,math.cos(a)*6.6),.008,"paving_dark",4)
cylinder("HubCompassInset",(0,.012,0),1.4,.014,"paving_dark",segments=40)
for a in [0,math.pi/2,math.pi,math.pi*1.5]:
    with frame(yaw=a):
        mesh("HubCompassPetal",[(0,.022,1.05),(.19,.022,.20),(0,.022,.32),(-.19,.022,.20)],[(0,1,2,3)],"brass")
arc_band("HubCompassRing",(0,.006,0),6.6,.075,.012,0,math.tau,"brass",80)
for angle in [0,math.pi/2,math.pi,math.pi*1.5]:
    with frame(yaw=angle):box("HubCompassRay",(0,.014,0),(.045,.012,10.8),"sand",0)
for x in [-3.8,3.8]:
    box("WelcomePier",(x,1.6,13.5),(.38,3.2,.38),"stone",.025)
    collision("WelcomePier",(x,1.6,13.5),(.48,3.2,.48))
box("WelcomeLintel",(0,3.3,13.5),(8.3,.38,.4),"walnut",.02)
box("WelcomeSign",(0,2.95,13.65),(4.5,.5,.06),"teal",.015)
collision("WelcomeLintelCamera",(0,3.3,13.5),(8.3,.38,.40))
COLLIDERS[-1]["camera_only"]=True
collision("WelcomeSignCamera",(0,2.95,13.65),(4.5,.5,.09))
COLLIDERS[-1]["camera_only"]=True
box("EntryPath",(0,-.01,14.05),(4.4,.04,13.9),"stone",0)
for side in [-1,1]:box("EntryPathDarkBorder",(side*2.08,.016,14.05),(.17,.016,13.9),"paving_dark",0)
for z in range(7,20,2):box("EntryPathCrossJoint",(0,.015,z),(4.0,.008,.018),"sand",0)
for side in [-1,1]:
    # Planting pockets sit between the diagonal spokes, leaving their entire
    # 4.2 m width clear, rather than only keeping a central walking point free.
    planter("HubPlanting",(side*11,.28,1),(3.5,.56,3.5),"stone")
    asset("alder",(side*11,.57,1),.80)
    bench("WelcomeBench",(side*8.9,0,1),math.pi/2 if side<0 else -math.pi/2)
    contact_patch("WelcomeBenchContact",(side*8.9,0,1),(.5,1.05))

def district_details(ident):
    """Readable destination thresholds and intentional small human details."""
    global ZONE_SIGN
    palette={"university":"slate","major":"brick","career":"teal","high_school":"oak","campus":"sand"}
    accent=palette[ident]
    # A flush mat locates the entry without narrowing the 4.2m route.
    box(ident+"_EntryThreshold",(0,.014,11.15),(4.1,.018,.52),accent,0)
    for side in [-1,1]:
        box(ident+"_ThresholdEdge",(side*2.16,.016,11.15),(.1,.02,2.0),"paving_dark",0)
    sign_z=14.0 if ident=="campus" else 11.6
    with frame((3.35,0,sign_z)):
        post_mat="steel" if ident in ("major","career") else "walnut"
        for x in [-.63,.63]:
            box(ident+"_WayfindingPost",(x,.72,0),(.075,1.44,.075),post_mat,.008)
            box(ident+"_WayfindingFoot",(x,.04,0),(.26,.08,.24),"stone",.008)
            contact_patch(ident+"_WayfindingContact",(x,0,0),(.18,.17))
        box(ident+"_WayfindingFrame",(0,1.48,0),(1.75,.62,.09),post_mat,.012)
        box(ident+"_WayfindingFace",(0,1.48,.052),(1.65,.52,.025),"teal",.005)
        box(ident+"_WayfindingAccent",(0,1.23,.068),(1.62,.025,.007),accent,0)
        collision(ident+"_Wayfinding",(0,.88,0),(1.75,1.76,.18))
    ZONE_SIGN=(3.35,1.48,sign_z+.075)
    for index,slot in enumerate(ZONE_SLOTS):
        p=slot["position"]
        with frame(p,slot.get("rotation_y",0)):
            # Every lectern owns an inlaid pad and a shadow on the same ground.
            round_box(ident+"_DeviceApron",(0,-.002,.10),(1.30,.012,1.25),.12,"paving_dark")
            contact_patch(ident+"_DeviceContact",(0,.004,0),(.36,.29))
            box(ident+"_DeviceApproachMarker",(0,.009,.62),(.44,.012,.035),accent,0)
    # Tableware and an open reference book tell the purpose of the spaces,
    # kept to one composition each instead of repeated scattered clutter.
    locations={"university":(-2.75,.57,-10.12),"major":(-7.0,.96,6.7),"career":(-7.45,.54,4.75),"high_school":(-6.2,.54,8.2),"campus":(-5.1,.54,-8.8)}
    p=locations[ident]
    with frame(p,.14):
        box(ident+"_ReadingBook",(0,0,0),(.36,.045,.27),accent,.004)
        box(ident+"_OpenPages",(0,.026,0),(.33,.012,.25),"paper",0)
        box(ident+"_BookBinding",(0,.035,0),(.012,.006,.24),"walnut",0)
        cylinder(ident+"_Cup",(.34,.06,0),.045,.12,"linen",top=.052,segments=12)

ZONE_SPECS=[
 ("university","大學交流區",(-21.2132,0,21.2132)),
 ("major","科系交流區",(-27.38455,0,-12.25098)),
 ("career","未來就業交流區",(21.2132,0,21.2132)),
 ("high_school","高中生發問區",(27.38455,0,-12.25098)),
 ("campus","校園討論區",(0,0,-33))]
ZONES=[]

# A short, continuous northern walk links adjacent destinations without forcing
# everyone back through the hub. The southern opening preserves the gateway.
# The 3.6m strip has >.75m clearance to solid scenery and avoids the tree stems.
group("GardenRingWalk")
_ring_radius=15.6
_ring_stops=sorted((math.atan2(center[0],center[2])%math.tau,ident) for ident,_,center in ZONE_SPECS)
_ring_angles=[_ring_stops[0][0]]
_ring_indices={_ring_stops[0][1]:0}
for (_a,_),(_b,_ident) in zip(_ring_stops,_ring_stops[1:]):
    _steps=math.ceil((_b-_a)*_ring_radius/1.8)
    _ring_angles.extend(_a+(_b-_a)*i/_steps for i in range(1,_steps+1))
    _ring_indices[_ident]=len(_ring_angles)-1

def ring_strip(name,inner,outer,y,material_key):
    points=[(math.sin(a)*r,y,math.cos(a)*r) for a in _ring_angles for r in [inner,outer]]
    return mesh(name,points,[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(_ring_angles)-1)],material_key)

ring_strip("Garden_NorthLinkWalk",_ring_radius-1.8,_ring_radius+1.8,.022,"stone")
for _edge in [-1,1]:
    _r=_ring_radius+_edge*1.75
    ring_strip("Garden_NorthLinkBorder",_r-.05,_r+.05,.027,"paving_dark")
RING_POINTS=[[round(math.sin(a)*_ring_radius,5),.06,round(math.cos(a)*_ring_radius,5)] for a in _ring_angles]
NAVIGATION={"ring_points":RING_POINTS,"ring_closed":False,"ring_width":3.6,
    "spokes":[{"zone_id":ident,"ring_index":_ring_indices[ident],"point":RING_POINTS[_ring_indices[ident]]} for ident,_,_ in ZONE_SPECS]}
def build_district(ident,label,center):
    # Each author may use ordinary loop variables such as yaw or label.
    # Driver coordinates must remain in a private scope, not their exec scope.
    global ZONE_SLOTS,ZONE_CONTROL,ZONE_SIGN
    yaw=math.atan2(-center[0],-center[2])
    length=math.hypot(center[0],center[2])-10
    # Three-metre-plus routes connect all five distinctive places continuously.
    with frame(yaw=yaw+math.pi):
        start=7.0
        box(ident+"_ApproachPath",(0,-.005,(length+start)/2),(4.2,.04,length-start),"stone",0)
        for side in [-1,1]:
            box(ident+"_PathBorder",(side*2.13,.018,(length+start)/2),(.09,.045,length-start),"sand",0)
        for z in range(8,int(length),3):
            box(ident+"_ApproachPavingJoint",(0,.017,z),(4.15,.006,.014),"paving_dark",0)
    group("Zone_"+ident)
    ZONE_SLOTS=[];ZONE_CONTROL=(0,.06,10.2);ZONE_SIGN=(0,1.7,10)
    with frame(center,yaw):
        script=ROOT/"tools/discussion_zones"/(ident+".py")
        exec(compile(script.read_text(encoding="utf-8"),str(script),"exec"),globals())
        district_details(ident)
    def to_world(p):
        return [round(center[0]+math.cos(yaw)*p[0]+math.sin(yaw)*p[2],5),p[1],round(center[2]-math.sin(yaw)*p[0]+math.cos(yaw)*p[2],5)]
    slots=[{"position":to_world(s["position"]),"rotation_y":s.get("rotation_y",0)+yaw} for s in ZONE_SLOTS]
    assert len(slots)==8,(ident,len(slots))
    control=to_world(ZONE_CONTROL)
    ZONES.append({"id":ident,"label":label,"center":list(center),"rotation_y":yaw,"slots":slots,
        "device_model":"message_device_"+ident+".glb","sign":{"position":to_world(ZONE_SIGN),"rotation_y":yaw},
        "controls":{"point":control,"radius":2.0,"sign":{"position":to_world(ZONE_SIGN),"rotation_y":yaw,"label_width_m":1.45,"physical_board":True}},
        "walk_path":[[0,.06,0],to_world((0,.06,14)),control]})
    if ident=="high_school":
        ZONES[-1]["indoor_footprints"]=[
            {"center":to_world(p),"size":[7.4,5.2,6.75],"rotation_y":yaw+angle}
            for p,angle in [((-8.3,0,1.8),math.pi/2-.12),((8.3,0,-5.0),-math.pi/2+.12)]]
    group("GardenConnections_"+ident)
    # Distinct tree groves soften long views between themed districts.
    for j,offset in enumerate([-1,1]):
        side=Vector((math.cos(yaw),0,-math.sin(yaw)))
        mid=Vector(center)*.57+side*offset*5.3
        asset("birch" if ident in ("major","high_school") else "alder",tuple(mid),.9,yaw+j)

for spec in ZONE_SPECS:
    print("BUILD_DISTRICT",spec[0],flush=True)
    build_district(*spec)

for spoke in NAVIGATION["spokes"]:
    spoke["entry"]=next(z["controls"]["point"] for z in ZONES if z["id"]==spoke["zone_id"])

environment=[c for key,c in GROUPS.items() if not key.startswith("Device_") and key!="MessageDevice"]
garden_report=evaluated_export(environment,"garden.glb")
assert garden_report["triangles"] < 650000,garden_report["triangles"]
garden_low_report=evaluated_export(environment,"garden_low.glb",low=True)
assert garden_low_report["triangles"] < 280000,garden_low_report["triangles"]

# Blender's imported masked foliage can otherwise be exported as BLEND.
import importlib.util
_cleanup_spec=importlib.util.spec_from_file_location("clean_discussion_glb",ROOT/"tools/clean_discussion_glb.py")
_cleanup=importlib.util.module_from_spec(_cleanup_spec);_cleanup_spec.loader.exec_module(_cleanup)
for filename,export_report in [("garden.glb",garden_report),("garden_low.glb",garden_low_report)]:
    glb_path=OUT/filename
    payload=glb_path.read_bytes();json_len=struct.unpack_from("<I",payload,12)[0]
    doc=json.loads(payload[20:20+json_len]);tail=payload[20+json_len:]
    for mat in doc.get("materials",[]):
        if "foliage" in mat.get("name","").lower():
            mat["alphaMode"]="MASK";mat["alphaCutoff"]=.5;mat["doubleSided"]=True
    encoded=json.dumps(doc,separators=(",",":")).encode();encoded+=b" "*((-len(encoded))%4)
    glb_path.write_bytes(struct.pack("<III",0x46546c67,2,20+len(encoded)+len(tail))+struct.pack("<II",len(encoded),0x4e4f534a)+encoded+tail)
    audit=_cleanup.clean_glb(glb_path)
    (ART/(filename.removesuffix(".glb")+"-geometry-audit.json")).write_text(json.dumps(audit,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    export_report["preCleanupTriangles"]=export_report["triangles"]
    export_report["triangles"]=audit["remaining"];export_report["degenerateTriangles"]=0;export_report["bytes"]=glb_path.stat().st_size

# All environments and device families share the same content-addressed image
# files, so Godot does not upload the same paper/wood/stone texture repeatedly.
_texture_spec=importlib.util.spec_from_file_location("share_discussion_textures",ROOT/"tools/share_discussion_textures.py")
_textures=importlib.util.module_from_spec(_texture_spec);_texture_spec.loader.exec_module(_textures)
_textures.share_textures(sorted(OUT.glob("*.glb")),report_path=ROOT/"deliverables/discussion-overhaul/performance/shared-textures.json")
_channels_spec=importlib.util.spec_from_file_location("audit_discussion_material_channels",ROOT/"tools/audit_discussion_material_channels.py")
_channels=importlib.util.module_from_spec(_channels_spec);_channels_spec.loader.exec_module(_channels)
_channel_reports=[_channels.audit(OUT/name) for name in ("garden.glb","garden_low.glb")]
_channel_result={"passed":all(row["passed"] for row in _channel_reports),"assets":_channel_reports}
(ART/"material-channel-qa.json").write_text(json.dumps(_channel_result,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
assert _channel_result["passed"],_channel_reports
for filename,export_report in [("garden.glb",garden_report),("garden_low.glb",garden_low_report)]:
    export_report["bytes"]=(OUT/filename).stat().st_size
for ident,export_report in DEVICE_REPORTS.items():export_report["bytes"]=(OUT/("message_device_"+ident+".glb")).stat().st_size
device_report["bytes"]=(OUT/"message_device.glb").stat().st_size

layout={"schemaVersion":1,"revision":"2026-10-23-compact-garden-overhaul-v4","architecture":{"major_truss_brackets_baked":True},"environment_models":{"standard":"garden.glb","low":"garden_low.glb"},"navigation":NAVIGATION,"bounds":{"min":[-51,0,-58],"max":[51,30,48]},
    "hub":[0,.06,0],"spawn":{"position":[0,.06,8.0],"facing":[0,0,-1]},
    "exit":{"position":[0,.06,17.8],"radius":1.7,"label":"返回星途大世界"},"title_anchor":[0,2.95,13.73],
    "colliders":COLLIDERS,"zones":ZONES,"device":{"front":"+Z","collider":{"center":[0,.75,0],"size":[.84,1.5,.56]},"preview_anchor":[0,1.07,.18]}}
(OUT/"layout.json").write_text(json.dumps(layout,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
report={"schemaVersion":3,"device":device_report,"deviceVariants":DEVICE_REPORTS,"garden":garden_report,"gardenLow":garden_low_report,"botanicalAndMaterialAudit":ASSET_AUDIT,"slotCount":40,"zones":5,
    "style":"Five distinct authored environments, per-zone material-specific message lecterns","source":"Built-in imagegen concepts; original Blender modelling; existing project botanical models and material textures","sourceTexturesUntouched":True}
(ART/"export-report.json").write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")

# Linked editable preview geometry in the .blend makes the actual layout visible.
# It is deliberately added after export, because Godot owns runtime instances.
group("DevicePreview")
for zone in ZONES:
    for slot in zone["slots"]:
        transform=Matrix.Translation(gv(slot["position"])) @ Matrix.Rotation(slot["rotation_y"],4,"Z")
        for source in GROUPS["Device_"+zone["id"]].objects:
            ob=source.copy();ob.data=source.data;COL.objects.link(ob)
            ob.matrix_world=transform @ source.matrix_world

group("Reference")
human=box("ScaleReference_175cm",(1,.875,10),(.42,1.75,.28),"teal",.06)
human.hide_render=True;human.hide_viewport=True
sun_data=bpy.data.lights.new("GardenSun","SUN");sun_data.energy=2.5;sun_data.angle=.10
sun=bpy.data.objects.new("GardenSun",sun_data);scene.collection.objects.link(sun)
sun.rotation_euler=(math.radians(24),math.radians(-28),math.radians(-22))
scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.type=="BACKGROUND")
background.inputs["Color"].default_value=(.68,.79,.94,1);background.inputs["Strength"].default_value=.55
camera_data=bpy.data.cameras.new("GardenCamera");camera=bpy.data.objects.new("GardenCamera",camera_data)
scene.collection.objects.link(camera);scene.camera=camera
def camera_at(p,target,lens=26):
    camera.location=gv(p);camera.rotation_euler=(gv(target)-camera.location).to_track_quat("-Z","Y").to_euler()
    camera_data.lens=lens;camera_data.clip_end=300
camera_at((70,65,86),(0,0,-8),38)
scene.render.resolution_x=1440;scene.render.resolution_y=960
scene.cycles.samples=32
for img in bpy.data.images:
    if img.source=="FILE" and not img.packed_file:
        try:img.pack()
        except RuntimeError:pass
# Transient evaluated meshes are exports, not editable source assets.
for data in list(bpy.data.meshes):
    if data.users==0 and not data.use_fake_user:bpy.data.meshes.remove(data)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/"DiscussionGarden.blend"))
for zone in ZONES if os.environ.get("GARDEN_SKIP_RENDERS")!="1" else []:
    center=zone["center"];yaw=zone["rotation_y"]
    def worldpos(p):return (center[0]+math.cos(yaw)*p[0]+math.sin(yaw)*p[2],p[1],center[2]-math.sin(yaw)*p[0]+math.cos(yaw)*p[2])
    camera_at(worldpos((1.0,2.15,11.5)),worldpos((0,1.65,-1.0)),22 if zone["id"]=="campus" else 24)
    scene.render.filepath=str(ART/(zone["id"]+"-blender.png"))
    bpy.ops.render.render(write_still=True)
print("DISCUSSION_GARDEN_REPORT "+json.dumps(report,ensure_ascii=False))
