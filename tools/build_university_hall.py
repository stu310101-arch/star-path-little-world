"""Academic library, Blender 5.2.2 -> Godot 4.7.2. Fresh background process only.
--stage primary writes atrium + booth for actual-game review. All coords Godot metres.
Actual raster PBR colour/normal/roughness maps, material-scale UVs, atomic GLB output.
"""
from pathlib import Path
import bpy,bmesh,math,random,json,sys,struct,zlib,os,hashlib,re
import numpy as np
from mathutils import Vector,Matrix
ROOT=Path(__file__).resolve().parents[1];ART=ROOT/'art/UniversityHall';OUT=ROOT/'game/assets/university_hall';TEX=OUT/'textures'
sys.path.insert(0, str(ROOT / "tools"))
from optimize_indoor_geometry import optimize_glb
for path in [ART,OUT,TEX]:path.mkdir(parents=True,exist_ok=True)
if '--exhibit-kit' in sys.argv:
    import runpy
    runpy.run_path(str(ART/'build_exhibit_kit.py'),run_name='__main__')
    raise SystemExit(0)
PRIMARY='primary' in sys.argv
assert not bpy.data.filepath,'Use --factory-startup in a separate background process.'
for ob in list(bpy.data.objects):bpy.data.objects.remove(ob,do_unlink=True)
bpy.context.preferences.filepaths.save_version=0
scene=bpy.context.scene;scene.name='University Library | Academic Hall';scene.unit_settings.system='METRIC'
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True
scene.render.resolution_x=1280;scene.render.resolution_y=800;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG'
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.29,.34,.40,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.32
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast'
RNG=random.Random(138);COL=None;FRAME=Matrix.Identity(4);ASSETS={};STATS={};M={}

def png(path,array):
    a=np.ascontiguousarray(np.clip(array*255+.5,0,255).astype(np.uint8))
    if a.ndim==2:a=np.repeat(a[:,:,None],3,axis=2)
    h,w,c=a.shape
    def chunk(t,d):return struct.pack('>I',len(d))+t+d+struct.pack('>I',zlib.crc32(t+d)&0xffffffff)
    rows=b''.join(b'\x00'+a[y].tobytes() for y in range(h))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(rows,8))+chunk(b'IEND',b''))

def noise(u,v,seed,terms=16):
    r=np.random.default_rng(seed);out=np.zeros_like(u)
    for i in range(terms):out+=np.sin(math.tau*(u*int(r.integers(1,3+2*i))+v*int(r.integers(1,3+2*i)))+r.uniform(0,math.tau))/(1+i*.45)
    return out/max(float(out.std()),.01)

def isotropic_noise(n,seed,frequency):
    # Radially filtered random Fourier noise avoids directional sine banding.
    white=np.random.default_rng(seed).normal(0,1,(n,n))
    ky=np.fft.fftfreq(n)[:,None];kx=np.fft.rfftfreq(n)[None,:]
    filt=np.exp(-(kx*kx+ky*ky)/(frequency*frequency))
    field=np.fft.irfft2(np.fft.rfft2(white)*filt,s=(n,n)).astype(np.float32)
    field-=field.mean();return field/max(float(field.std()),.001)

def bake_maps():
    n=1024;v,u=np.mgrid[0:n,0:n].astype(np.float32)/n
    coarse=isotropic_noise(n,138,.018);fine=isotropic_noise(n,731,.22)
    warp=.027*np.sin(math.tau*v)+.013*np.sin(math.tau*(v*3+u))
    grain=np.sin(math.tau*(u*47+warp*15))*.5+np.sin(math.tau*(u*131+warp*34))*.18
    veins=np.sin(math.tau*(u*9+.10*np.sin(math.tau*v*2)))
    walnut=.032*grain+.019*veins+.004*fine+.005*coarse;stone=.006*coarse+.0015*fine
    fleck=np.maximum(0,np.sin((u+v)*n*4.1)*np.cos((u-v)*n*3.7)-.77)*.13
    families={
      'walnut':(np.stack([.405+walnut,.267+walnut*.78,.168+walnut*.50],2),.47+grain*.045+fine*.025,grain*.016+veins*.005),
      'stone':(np.stack([.64+stone+fleck*.20,.625+stone+fleck*.20,.583+stone+fleck*.20],2),.62+coarse*.018,coarse*.0015+fine*.0008),
      'stone_dark':(np.stack([.195+stone*.65,.223+stone*.65,.214+stone*.65],2),.38+coarse*.015,coarse*.0015),
      'plaster':(np.stack([.63+coarse*.003+fine*.0015,.606+coarse*.003+fine*.0015,.563+coarse*.003+fine*.0015],2),.87+fine*.012,fine*.0008),
      'leather_green':(np.stack([.125+fine*.004,.203+fine*.006,.164+fine*.005],2),.60+fine*.025,fine*.003),
      'leather_red':(np.stack([.275+fine*.007,.132+fine*.004,.105+fine*.003],2),.62+fine*.025,fine*.003),
      'leather_blue':(np.stack([.144+fine*.004,.17+fine*.005,.217+fine*.006],2),.58+fine*.025,fine*.003),
      'paper':(np.stack([.82+fine*.008,.775+fine*.008,.665+fine*.008],2),.84+fine*.025,fine*.004)}
    for key,(base,rough,height) in families.items():
        png(TEX/(key+'_base.png'),base);png(TEX/(key+'_rough.png'),rough)
        dz,dx=np.gradient(height);normal=np.stack([-dx*28,-dz*28,np.ones_like(dx)],2);normal/=np.sqrt((normal**2).sum(2,keepdims=True))
        png(TEX/(key+'_normal.png'),normal*.5+.5)
    ensure_texture_imports()

def ensure_texture_imports():
    # Explicit import policy: UI-style auto-detection otherwise leaves these
    # canonical 3D rasters without mipmaps, causing severe distant shimmer.
    for path in TEX.glob('*.png'):
        imported=Path(str(path)+'.import')
        if imported.exists():
            content=imported.read_text(encoding='utf-8')
            content=re.sub(r'mipmaps/generate=(true|false)','mipmaps/generate=true',content)
        else:
            resource='res://assets/university_hall/textures/'+path.name
            dest='res://.godot/imported/'+path.name+'-'+hashlib.md5(resource.encode()).hexdigest()+'.ctex'
            content='[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\npath="'+dest+'"\nmetadata={\n"vram_texture": false\n}\n\n[deps]\n\nsource_file="'+resource+'"\ndest_files=["'+dest+'"]\n\n[params]\n\ncompress/mode=0\ncompress/normal_map=0\nmipmaps/generate=true\nmipmaps/limit=-1\nprocess/fix_alpha_border=true\nprocess/normal_map_invert_y=false\ndetect_3d/compress_to=1\n'
        imported.write_text(content,encoding='utf-8')

def material(key,color=(1,1,1),metal=0,rough=.5,alpha=1,emission=0):
    m=bpy.data.materials.new('MAT_University_Library_'+key);m.use_nodes=True;m.diffuse_color=(*color,alpha)
    p=m.node_tree.nodes.get('Principled BSDF');ns=m.node_tree.nodes;links=m.node_tree.links
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;p.inputs['Alpha'].default_value=alpha
    if alpha<1:m.surface_render_method='DITHERED'
    if emission:p.inputs['Emission Color'].default_value=(*color,1);p.inputs['Emission Strength'].default_value=emission
    for suffix,plug in [('base','Base Color'),('rough','Roughness')]:
        path=TEX/(key+'_'+suffix+'.png')
        if path.exists():
            im=bpy.data.images.load(str(path),check_existing=True);im.colorspace_settings.name='sRGB' if suffix=='base' else 'Non-Color'
            tex=ns.new('ShaderNodeTexImage');tex.image=im;tex.extension='REPEAT';links.new(tex.outputs['Color'],p.inputs[plug])
    path=TEX/(key+'_normal.png')
    if path.exists():
        im=bpy.data.images.load(str(path),check_existing=True);im.colorspace_settings.name='Non-Color';tex=ns.new('ShaderNodeTexImage');tex.image=im
        normal=ns.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.7;links.new(tex.outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],p.inputs['Normal'])
    M[key]=m

def gv(p):return Vector((p[0],-p[2],p[1]))
def collection(name):
    global COL
    COL=bpy.data.collections.new('COL_Library_'+name);scene.collection.children.link(COL);ASSETS[name]=COL;return COL

def uv_project(data,key):
    uv=data.uv_layers.new(name='UVMap');scale=2.0 if key.startswith('stone') else .45 if key.startswith('leather') or key=='paper' else 1.1
    for poly in data.polygons:
        major=max(range(3),key=lambda i:abs(poly.normal[i]));axes=[i for i in range(3) if i!=major]
        spans=[max(data.vertices[data.loops[l].vertex_index].co[i] for l in poly.loop_indices)-min(data.vertices[data.loops[l].vertex_index].co[i] for l in poly.loop_indices) for i in axes]
        if key=='walnut' and spans[0]>spans[1]:axes.reverse()
        for loop in poly.loop_indices:
            co=data.vertices[data.loops[loop].vertex_index].co;uv.data[loop].uv=(co[axes[0]]/scale,co[axes[1]]/scale)

def mesh(name,points,faces,key):
    data=bpy.data.meshes.new('MSH_'+name);data.from_pydata([gv(p) for p in points],[],faces);data.update()
    bm=bmesh.new();bm.from_mesh(data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(data);bm.free();uv_project(data,key)
    ob=bpy.data.objects.new('SM_'+name,data);COL.objects.link(ob);data.materials.append(M[key]);ob.matrix_world=FRAME.copy();return ob

def box(name,p,size,key='walnut',bevel=.012):
    a,b,c=[v*.5 for v in size]
    ob=mesh(name,[(-a,-b,-c),(a,-b,-c),(a,-b,c),(-a,-b,c),(-a,b,-c),(a,b,-c),(a,b,c),(-a,b,c)],[(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)],key);ob.matrix_world=FRAME@Matrix.Translation(gv(p))
    if bevel:
        mod=ob.modifiers.new('Hand-finished edges','BEVEL');mod.width=min(bevel,min(size)*.35);mod.segments=2
        mod=ob.modifiers.new('Weighted normals','WEIGHTED_NORMAL');mod.keep_sharp=True
    return ob

def plane(name,p,size,key):
    x,y,z=p;w,d=size;return mesh(name,[(x-w/2,y,z-d/2),(x-w/2,y,z+d/2),(x+w/2,y,z+d/2),(x+w/2,y,z-d/2)],[(0,1,2,3)],key)

def cylinder(name,p,r,h,key='brass',n=20,r2=None):
    if r2 is None:r2=r
    pts=[(math.cos(j*math.tau/n)*rr,yy,math.sin(j*math.tau/n)*rr) for yy,rr in [(-h/2,r),(h/2,r2)] for j in range(n)]
    ob=mesh(name,pts,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)],key);ob.matrix_world=FRAME@Matrix.Translation(gv(p))
    for polygon in ob.data.polygons:
        if len(polygon.vertices)==4:polygon.use_smooth=True
    return ob

def rod(name,a,b,r,key='brass',n=12):
    av,bv=gv(a),gv(b);ob=cylinder(name,(0,0,0),r,(bv-av).length,key,n);ob.matrix_world=FRAME@Matrix.Translation((av+bv)*.5)@(bv-av).to_track_quat('Z','Y').to_matrix().to_4x4();return ob

def arc(name,x,y,z,r,width,depth,key='walnut',steps=32):
    pts=[];faces=[]
    for i in range(steps+1):
        a=i*math.pi/steps
        for zz in [-depth/2,depth/2]:
            for rr in [r,r+width]:pts.append((x+math.cos(a)*rr,y+math.sin(a)*rr,z+zz))
    for i in range(steps):
        j=i*4;k=j+4;faces.extend([(j,k,k+1,j+1),(j+2,j+3,k+3,k+2),(j,j+2,k+2,k),(j+1,k+1,k+3,j+3)])
    faces.extend([(0,1,3,2),(steps*4,steps*4+2,steps*4+3,steps*4+1)]);return mesh(name,pts,faces,key)

def panel(name,x,y,z,w,h,key='walnut'):
    box(name,(x,y,z),(w,h,.06),key,.018)
    for xx in [-w/2+.06,w/2-.06]:box(name+'_Side',(x+xx,y,z+.04),(.025,h-.08,.022),'brass',.006)
    for yy in [-h/2+.05,h/2-.05]:box(name+'_Rail',(x,y+yy,z+.04),(w-.08,.025,.022),'brass',.006)

def book(name,x,y,z,w=.08,h=.33,d=.23,key='leather_green',detail=True):
    box(name+'_BoundVolume',(x,y+h/2,z),(w,h,d),key,.004 if detail else 0)
    if detail:
        box(name+'_PageEdges',(x,y+h/2,z-.025),(max(.018,w-.012),h-.025,d-.025),'paper',.002)
        box(name+'_Spine',(x,y+h/2,z+d/2),(w+.003,h,.012),key,.003)
        for yy in [.055,h-.06]:box(name+'_GiltBand',(x,y+yy,z+d/2+.007),(w*.78,.008,.0015),'brass',0)

def bookcase(name,p,w=4.7,h=3.35,angle=0,upper=False):
    global FRAME
    old=FRAME;FRAME=FRAME@Matrix.Translation(gv(p))@Matrix.Rotation(angle,4,'Z')
    box(name+'_ShadowBack',(0,h/2,-.29),(w,h,.10),'leather_green',0)
    for x in [-w/2,w/2]:
        box(name+'_Stile',(x,h/2,0),(.15,h,.67),'walnut',.025);box(name+'_Fluting',(x,h/2,.348),(.025,h-.25,.024),'brass',.008)
    for yy,depth in [(.11,.74),(.27,.68),(h-.10,.72),(h,.84)]:box(name+'_Cornice',(0,yy,.025),(w+.24,.10,depth),'walnut',.015)
    shelves=5 if h>3 else 4
    for row in range(shelves):
        yy=.4+row*(h-.62)/shelves;box(name+'_Shelf',(0,yy,0),(w,.065,.63),'walnut',.009);count=round(w/.18)
        for i in range(count):
            x=-w*.5+.12+i*(w-.25)/count
            if (i+row*3)%17 in [14,15]:continue
            bw=.085+RNG.random()*.065;bh=.27+RNG.random()*.16;key=['leather_green','leather_red','leather_blue'][(i*3+row+i//5)%3]
            book(name+'_Book',x,yy+.04,.075,bw,bh,.28,key,detail=not upper and i%5==0)
    for xx in [-w*.22,w*.22]:box(name+'_Divider',(xx,h*.53,-.05),(.075,h-.42,.56),'walnut',.008)
    FRAME=old

def rail(name,a,b,y=5.33):
    x1,z1=a;x2,z2=b;rod(name+'_Top',(x1,y+.52,z1),(x2,y+.52,z2),.034,'walnut',16);rod(name+'_Bottom',(x1,y-.38,z1),(x2,y-.38,z2),.022,'brass',12)
    n=round(math.hypot(x2-x1,z2-z1)/.65)
    for i in range(n+1):
        t=i/max(n,1);x=x1+(x2-x1)*t;z=z1+(z2-z1)*t;rod(name+'_Baluster',(x,y-.42,z),(x,y+.50,z),.015,'brass',10);cylinder(name+'_Collar',(x,y+.10,z),.035,.055,'brass',12)

def portal(name,x,z,w=3.65):
    r=w/2;spring=1.85
    for side in [-1,1]:
        xx=x+side*(r+.14);box(name+'_StonePier',(xx,1.10,z),(.36,2.2,.50),'stone',.024);box(name+'_Pilaster',(xx,1.08,z+.29),(.22,2.0,.10),'walnut',.016)
        for offset in [-.07,0,.07]:box(name+'_Flute',(xx+offset,1.09,z+.35),(.012,1.68,.015),'brass',.003)
        for yy in [.14,1.83]:box(name+'_Capital',(xx,yy,z),(.50,.16,.67),'walnut',.020)
    arc(name+'_Archivolt',x,spring,z,r,.30,.50,'stone');arc(name+'_WoodInset',x,spring,z+.265,r+.05,.10,.06,'walnut')
    box(name+'_Keystone',(x,3.80,z+.27),(.30,.28,.12),'stone',.02);panel(name+'_Title',x,4.18,z,4.00,.52,'leather_green');box(name+'_Threshold',(x,.025,z),(3.7,.04,1.1),'stone_dark',.01)
    # Closed archive door makes the portal a credible entrance; E opens travel.
    outline=[(x-r,.035,z-.33),(x+r,.035,z-.33)]+[(x+math.cos(i*math.pi/32)*(r-.015),spring+math.sin(i*math.pi/32)*(r-.015),z-.33) for i in range(33)]
    mesh(name+'_DoorShadowLining',outline,[tuple(range(len(outline)))],'leather_green')
    for side in [-1,1]:
        xx=x+side*r*.47
        box(name+'_DoorLeaf',(xx,1.28,z-.285),(r*.89,2.49,.065),'walnut',.020)
        for yy,hh in [(.54,.65),(1.38,.75),(2.16,.55)]:panel(name+'_DoorRaisedPanel',xx,yy,z-.235,r*.72,hh,'walnut')
        rod(name+'_DoorHandle',(x+side*.18,1.03,z-.13),(x+side*.18,1.33,z-.13),.018,'brass',16)
    box(name+'_DoorCentralStile',(x,1.73,z-.26),(.07,3.41,.09),'walnut',.012)

def lamp(name,x,z,y=.88,scale=1):
    cylinder(name+'_Base',(x,y+.027*scale,z),.18*scale,.054*scale,'brass',24);rod(name+'_Stem',(x,y+.06*scale,z),(x,y+.53*scale,z),.022*scale,'brass',16)
    rod(name+'_Arm',(x-.25*scale,y+.5*scale,z),(x+.25*scale,y+.5*scale,z),.015*scale,'brass',12)
    arc(name+'_GreenShade',x,y+.52*scale,z,.19*scale,.025*scale,.58*scale,'leather_green',20)
    box(name+'_Diffuser',(x,y+.49*scale,z),(.34*scale,.018*scale,.48*scale),'lamp',.008)
    rod(name+'_PullChain',(x+.22*scale,y+.48*scale,z+.13*scale),(x+.22*scale,y+.22*scale,z+.13*scale),.004*scale,'brass',6)

def chandelier(name,x,z,y=5.4):
    cylinder(name+'_CeilingRose',(x,9.81,z),.24,.12,'brass',32)
    rod(name+'_Suspension',(x,y+.38,z),(x,9.76,z),.020,'brass',16)
    cylinder(name+'_CentralFinial',(x,y-.15,z),.10,.38,'brass',24,r2=.065)
    for j in range(48):
        a=j*math.tau/48;b=(j+1)*math.tau/48
        rod(name+'_Ring',(x+math.cos(a)*.87,y,z+math.sin(a)*.87),(x+math.cos(b)*.87,y,z+math.sin(b)*.87),.033,'brass',10)
    for j in range(8):
        a=j*math.tau/8;xx=x+math.cos(a)*.87;zz=z+math.sin(a)*.87
        rod(name+'_Spoke',(x,y-.12,z),(xx,y,zz),.015,'brass',10)
        cylinder(name+'_CandleCup',(xx,y+.025,zz),.11,.05,'brass',24,r2=.13)
        cylinder(name+'_OpalDiffuser',(xx,y+.20,zz),.083,.30,'lamp',24,r2=.12)
        cylinder(name+'_ShadeRim',(xx,y+.355,zz),.122,.017,'brass',24)
        if j%2==0:rod(name+'_Support',(xx,y+.025,zz),(x,y+1.18,z),.009,'brass',10)

def floor(name,w,d):
    # One geometric surface: tile joints, inlays and compass are in a unique
    # atlas, never a second mesh a few millimetres above another floor.
    key='floor_'+name.lower();n=2048
    row,col=np.mgrid[0:n,0:n].astype(np.float32);xx=(col+.5)/n*w-w/2;zz=d/2-(row+.5)/n*d
    fine=isotropic_noise(n,551,.24)*.0015;coarse=isotropic_noise(n,551,.014)*.004
    colour=np.stack([.64+fine+coarse,.625+fine+coarse,.583+fine+coarse],2)
    def paint(mask,rgb):
        nonlocal colour
        alpha=np.asarray(mask,dtype=np.float32)[:,:,None];colour=colour*(1-alpha)+np.asarray(rgb,dtype=np.float32)*alpha
    tilew=w/round(w/1.55);tiled=d/round(d/1.55)
    gx=np.mod(xx+w/2,tilew);gz=np.mod(zz+d/2,tiled);dist=np.minimum(np.minimum(gx,tilew-gx),np.minimum(gz,tiled-gz));aa=max(w,d)/n
    paint(np.clip((.008+aa*.5-dist)/aa,0,1),(.42,.41,.38))
    paint(((abs(abs(xx)-(w/2-1.05))<.095)&(abs(zz)<d/2-.95))|((abs(abs(zz)-(d/2-1.05))<.095)&(abs(xx)<w/2-.95)),(.195,.223,.214))
    paint((abs(abs(xx)-4)<.028)&(abs(zz)<d/2-1),(.51,.38,.16))
    mz,mr=(6.7,2.35) if name=='Atrium' else (14.5,1.8)
    distance=np.sqrt(xx*xx+(zz-mz)**2);paint(distance<mr,(.195,.223,.214));paint(distance<mr-.055,(.64,.625,.583))
    for j in range(8):
        angle=j*math.tau/8
        points=[(0,mz),(math.cos(angle-.10)*mr*.31,mz+math.sin(angle-.10)*mr*.31),(math.cos(angle)*mr*.75,mz+math.sin(angle)*mr*.75),(math.cos(angle+.10)*mr*.31,mz+math.sin(angle+.10)*mr*.31)]
        mask=np.ones(xx.shape,dtype=bool)
        for a,b in zip(points,points[1:]+points[:1]):mask&=((b[0]-a[0])*(zz-a[1])-(b[1]-a[1])*(xx-a[0]))>=0
        paint(mask,(.51,.38,.16) if j%2 else (.195,.223,.214))
    png(TEX/(key+'_base.png'),colour);png(TEX/(key+'_rough.png'),np.full((256,256),.64,dtype=np.float32));png(TEX/(key+'_normal.png'),np.broadcast_to(np.array([.5,.5,1],dtype=np.float32),(256,256,3)))
    ensure_texture_imports();material(key)
    ob=plane(name+'_FloorSurface',(0,0,0),(w,d),key)
    uv=ob.data.uv_layers.active
    for loop in ob.data.loops:
        co=ob.data.vertices[loop.vertex_index].co;uv.data[loop.index].uv=(co.x/w+.5,-co.y/d+.5)

def medallion(x,z,r=2):
    pass  # Already baked into the single floor atlas; no overlay geometry.

def entrance_wall(name,w,d):
    # Close the positive-Z end, with shelves that face back into the room.
    z=d/2-.12;box(name+'_FrontWall',(0,5.1,z),(w-.3,10.2,.12),'plaster',.01)
    for x in [-8,8]:bookcase(name+'_EntranceBooks',(x,0,z-.70),6.8,3.5,math.pi)
    box(name+'_FrontMezzanine',(0,4.82,z-1.23),(w-.8,.30,2.4),'walnut',.02)
    box(name+'_FrontFascia',(0,4.71,z-2.50),(w-.8,.44,.18),'walnut',.02)
    rail(name+'_FrontRailing',(-w/2+1.2,z-2.64),(w/2-1.2,z-2.64),5.4)
    for x in [-10,-5,0,5,10]:bookcase(name+'_UpperEntranceBooks',(x,5.16,z-.70),4.7,2.60,math.pi,True)
    box(name+'_FrontShadowReveal',(0,.046,z-.10),(w-.5,.09,.12),'crevice',0)

def reverse_portal(prefix,z):
    pivot=Matrix.Translation(gv((0,0,z)));rotation=pivot@Matrix.Rotation(math.pi,4,'Z')@pivot.inverted()
    for ob in COL.objects:
        if ob.name.startswith('SM_'+prefix+'_'):ob.matrix_world=rotation@ob.matrix_world

def bench(name,x,z,w=3):
    for xx in [-w*.37,w*.37]:box(name+'_Leg',(x+xx,.23,z),(.12,.46,.62),'walnut',.025);box(name+'_Shoe',(x+xx,.07,z),(.14,.12,.64),'brass',.012)
    box(name+'_Frame',(x,.43,z),(w,.14,.66),'walnut',.035);box(name+'_LeatherSeat',(x,.54,z),(w-.12,.11,.58),'leather_green',.045)
    for xx in [-w*.46,w*.46]:box(name+'_BackPost',(x+xx,.73,z-.30),(.09,.69,.09),'walnut',.014)
    box(name+'_LeatherBack',(x,.94,z-.30),(w-.17,.30,.08),'leather_green',.025)

def ceiling(name,w,d):
    for side in [-1,1]:
        box(name+'_CofferBand',(side*(w/2+5)/2,10.15,0),(w/2-5,.18,d),'walnut',.02);box(name+'_ClerestoryRim',(side*5,10.12,0),(.28,.42,d),'walnut',.025)
    for z in [-d/2+2,d/2-2]:box(name+'_EndCoffer',(0,10.15,z),(10,.18,4),'walnut',.02)
    for z in range(-int(d/2)+2,int(d/2),3):
        box(name+'_CrossBeam',(0,9.98,z),(w,.26,.19),'walnut',.024)
        for side in [-1,1]:box(name+'_CofferGoldLine',(side*(w/2+5)/2,9.88,z),(w/2-5-.35,.026,.028),'brass',.004)
    for side in [-1,1]:
        for z in range(-int(d/2)+3,int(d/2)-1,4):
            box(name+'_ClerestoryPane',(side*(w/2-.14),8.98,z),(.022,1.85,3.42),'glass',0)
            for yy in [8.04,9.93]:box(name+'_WindowRail',(side*(w/2-.10),yy,z),(.13,.11,3.58),'walnut',.01)

def build_atrium():
    collection('atrium');floor('Atrium',32,26);medallion(0,6.7,2.35);box('Atrium_BackWall',(0,5.1,-12.9),(31.9,10.2,.10),'plaster',.01)
    for side in [-1,1]:
        box('Atrium_SideWall',(side*15.9,3.9,0),(.10,7.8,25.8),'plaster',.01)
        for z in [-8,-2,4,10]:
            bookcase('Atrium_LowerBookcase',(side*15.1,0,z),4.85,3.6,-side*math.pi/2);bookcase('Atrium_UpperBookcase',(side*15.1,5.15,z),4.85,2.55,-side*math.pi/2,True)
        box('Atrium_SideMezzanine',(side*13.65,4.82,0),(4.3,.30,25.6),'walnut',.025);box('Atrium_SideFascia',(side*11.48,4.7,0),(.17,.46,25.6),'walnut',.02)
        rail('Atrium_UpperRailing',(side*11.39,-11.3),(side*11.39,11.2),5.4)
        for z in [-10,-5,0,5,10]:
            xx=side*14.65;box('Atrium_Column',(xx,2.3,z),(.34,4.6,.34),'walnut',.035)
            for yy in [.15,4.4]:box('Atrium_ColumnCapital',(xx,yy,z),(.57,.23,.57),'walnut',.02)
            box('Atrium_ColumnCollar',(xx,4.22,z),(.40,.06,.40),'brass',.008)
        bench('Atrium_ReadingBench',side*7,4.8)
        for z in [-3.5,3.5]:
            box('Atrium_SideCabinet',(side*12,.47,z),(1.20,.94,3.35),'walnut',.035);box('Atrium_CabinetStoneTop',(side*12,.98,z),(1.30,.08,3.45),'stone_dark',.02);lamp('Atrium_ReadingLamp',side*12,z,1.02,.95)
            for j in range(3):book('Atrium_DeskBook',side*12-.22+j*.13,1.04,z+.82,.09,.32,.25,['leather_green','leather_red','leather_blue'][j])
    box('Atrium_BackMezzanine',(0,4.82,-11.45),(31,.30,2.7),'walnut',.02);box('Atrium_BackFascia',(0,4.71,-10.08),(31.1,.44,.18),'walnut',.02);rail('Atrium_BackRailing',(-14.8,-9.95),(14.8,-9.95),5.4)
    for x in [-12,-6,0,6,12]:portal('RegionPortal',x,-9);bookcase('Atrium_UpperArchive',(x,5.16,-12.2),4.9,2.68,upper=True)
    for x in [-9,-3,3,9]:bookcase('Atrium_LowerArchive',(x,0,-12.2),2.40,3.5)
    ceiling('Atrium',32,26);box('Map_Plinth',(0,.40,0),(2.30,.8,1.70),'walnut',.055)
    for x in [-.8,0,.8]:panel('Map_RaisedPanel',x,.42,.89,.66,.53)
    box('Map_Cornice',(0,.795,0),(2.66,.08,2.08),'brass',.01);box('Map_ReadingSurface',(0,.845,0),(2.70,.09,2.1),'paper',.018);portal('Exit',0,11,3.7)
    for z in [-4.5,4.5]:chandelier('Atrium_BrassChandelier',0,z)
    for side in [-1,1]:box('Atrium_WallShadowReveal',(side*15.83,.046,0),(.12,.09,25.7),'crevice',0)
    box('Atrium_BackShadowReveal',(0,.046,-12.83),(31.7,.09,.12),'crevice',0)
    for side in [-1,1]:
        for z in [-3.5,3.5]:box('Atrium_CabinetToeShadow',(side*12,.04,z),(1.22,.075,3.37),'crevice',.01)
    entrance_wall('Atrium',32,26);reverse_portal('Exit',11)

def study_objects():
    for x in [-2,-1,0,1,2]:box('Object_LeatherPad',(x,.867,1.12),(.68,.020,.46),'leather_green',.009);box('Object_Caption',(x,.754,1.37),(.69,.12,.015),'brass',.009)
    box('Map_Paper',(-2,.892,1.13),(.48,.014,.33),'paper',.004)
    for dx in [-.16,0,.16]:box('Map_Fold',(-2+dx,.901,1.13),(.002,.002,.31),'walnut',0)
    for zz in [1.03,1.13,1.23]:box('Map_Grid',(-2,.902,zz),(.46,.001,.0015),'brass',0)
    cylinder('Map_Compass',(-1.86,.91,1.22),.042,.005,'brass',20);box('Landscape_Tray',(-1,.895,1.13),(.45,.035,.31),'brass',.006)
    for i in range(5):box('Landscape_ContourModel',(-1+i*.007,.93+i*.023,1.13),(.39-i*.052,.022,.28-i*.035),'stone',.008)
    cylinder('Meal_Plate',(0,.895,1.13),.20,.020,'stone',32);cylinder('Meal_PlateInset',(0,.909,1.13),.16,.010,'paper',32);cylinder('Meal_Bowl',(0,.965,1.13),.073,.105,'stone',32,r2=.11);cylinder('Meal_Tea',(0,1.019,1.13),.095,.002,'walnut',24);rod('Meal_Spoon',(.14,.925,1.04),(.14,.925,1.25),.007,'brass',10)
    for j in range(3):box('Messages_Envelope',(1+j*.012,.89+j*.008,1.13),(.44,.007,.30),'paper',.003)
    cylinder('Messages_Seal',(1.03,.921,1.14),.033,.009,'leather_red',24);rod('Messages_Pen',(.86,.93,1.02),(1.18,.93,1.26),.009,'walnut',12)
    box('Study_Cover',(2,.89,1.13),(.49,.018,.34),'leather_blue',.007)
    for side in [-1,1]:
        box('Study_Pages',(2+side*.115,.924,1.13),(.23,.037,.30),'paper',.006)
        for zz in [1.04,1.08,1.12,1.16,1.20]:box('Study_PrintLine',(2+side*.12,.946,zz),(.17,.001,.0012),'walnut',0)

def build_booth():
    collection('booth')
    for x in [-2.30,2.30]:box('Archive_Pedestal',(x,.39,-.01),(.38,.78,2.2),'walnut',.028);box('Archive_Foot',(x,.095,0),(.54,.19,2.37),'walnut',.025);box('Archive_Shoe',(x,.044,0),(.56,.06,2.39),'brass',.008)
    box('Archive_Apron',(0,.665,0),(5.35,.26,2.4),'walnut',.03);box('Archive_Top',(0,.825,0),(5.60,.05,2.6),'walnut',.018);box('Archive_Inlay',(0,.786,1.302),(5.45,.018,.012),'brass',.002);box('Archive_DisplayBed',(0,.876,-.17),(4.95,.030,1.83),'leather_green',.01)
    for x in [-2.48,2.48]:
        box('Archive_GlassSide',(x,1.43,-.20),(.008,1.07,1.83),'glass',0)
        for z in [-1.12,.70]:rod('Archive_Post',(x,.89,z),(x,1.97,z),.013,'brass',12)
    box('Archive_GlassTop',(0,1.97,-.20),(4.96,.008,1.84),'glass',0)
    for z in [-1.12,.72]:rod('Archive_CaseRail',(-2.48,1.98,z),(2.48,1.98,z),.013,'brass',12)
    for x in [-2.66,2.66]:box('Archive_Pilaster',(x,1.44,-1.35),(.13,2.88,.16),'walnut',.022);box('Archive_Flute',(x,1.46,-1.26),(.023,2.53,.015),'brass',.003)
    box('Archive_DisplayBack',(0,1.65,-1.37),(5.18,1.46,.10),'leather_green',.022);panel('Archive_NamePlaque',0,2.65,-1.35,5.22,.53);study_objects()

def build_gallery():
    collection('gallery');floor('Gallery',30,38);ceiling('Gallery',30,38)
    for side in [-1,1]:
        box('Gallery_SideWall',(side*14.9,4,0),(.10,8,37.8),'plaster',.01);box('Gallery_Mezzanine',(side*13.8,4.82,0),(2.05,.30,37.8),'walnut',.025);rail('Gallery_UpperRail',(side*12.67,-17.5),(side*12.67,17.5),5.4)
        for z in [-14,-7,0,7,14]:bookcase('Gallery_UpperBooks',(side*14.20,5.15,z),5.9,2.6,-side*math.pi/2,True);bookcase('Gallery_LowerBooks',(side*14.20,0,z),5.9,3.55,-side*math.pi/2)
        for z in [-17,-9,-1,7,15]:box('Gallery_Pier',(side*13.1,2.3,z),(.30,4.6,.30),'walnut',.025);box('Gallery_Capital',(side*13.1,4.55,z),(.5,.25,.5),'walnut',.02)
    box('Gallery_BackWall',(0,5,-18.88),(29.7,10,.1),'plaster',.01)
    for x in [-11,0,11]:bookcase('Gallery_BackBooks',(x,0,-18.15),5,3.65)
    for x in [-10,-5,0,5,10]:bookcase('Gallery_UpperBackBooks',(x,5.16,-18.15),4.7,2.65,upper=True)
    for x in [-7,7]:portal('Gallery_Page',x,-16);panel('Gallery_Caption',x,4.28,-15.97,4,.52,'leather_green')
    portal('Gallery_Return',0,17.8);medallion(0,14.5,1.8)
    for x in [-3.8,3.8]:box('Gallery_Console',(x,.4,-17.8),(.75,.8,.55),'walnut',.025);lamp('Gallery_Lamp',x,-17.8,.82)
    for side in [-1,1]:box('Gallery_WallShadowReveal',(side*14.83,.046,0),(.12,.09,37.7),'crevice',0)
    box('Gallery_BackShadowReveal',(0,.046,-18.81),(29.7,.09,.12),'crevice',0)
    entrance_wall('Gallery',30,38);reverse_portal('Gallery_Return',17.8)

def building(name,x,z,w,h,d,y=.07,roof='stone_dark'):
    box(name+'_Massing',(x,y+h/2,z),(w,h,d),'stone',.012);box(name+'_Cornice',(x,y+h-.015,z),(w+.045,.035,d+.045),'stone',.006);box(name+'_Roof',(x,y+h+.006,z),(w+.035,.028,d+.035),roof,.007)
    count=max(2,round(w/.16));levels=max(1,round(h/.19))
    for i in range(count):
        for j in range(levels):
            xx=x+(i-(count-1)/2)*(w-.15)/max(count-1,1);yy=y+.10+j*(h-.17)/max(levels-1,1)
            box(name+'_Window',(xx,yy,z+d/2+.003),(.065,.092,.009),'leather_blue',.001);box(name+'_Sill',(xx,yy-.05,z+d/2+.010),(.078,.012,.027),'stone',.003)
    for i in range(4):box(name+'_Step',(x,y-.01+i*.018,z+d/2+.10-i*.023),(w*.32,.018,.18-i*.025),'stone',.003)

def theme_base():
    box('Model_WalnutBase',(0,.025,-.10),(4.60,.05,1.60),'walnut',.012);box('Model_Survey',(0,.06,-.10),(4.51,.018,1.51),'paper',.005)
    for x in [-2,-1.5,-1,-.5,0,.5,1,1.5,2]:box('Model_Grid',(x,.071,-.10),(.002,.001,1.49),'brass',0)
    for z in [-.65,-.15,.35]:box('Model_Grid',(0,.071,z),(4.49,.001,.002),'brass',0)

def themes():
    collection('theme_urban');theme_base()
    for x,z,w,h,d in [(-1.72,-.3,.67,.71,.58),(-.78,-.28,.68,.48,.6),(.2,-.25,.71,.90,.63),(1.27,-.30,1.1,.64,.64)]:building('Urban_Faculty',x,z,w,h,d)
    box('Urban_Street',(0,.078,.49),(4.25,.012,.16),'stone_dark',.003)
    collection('theme_woodland');theme_base();building('Courtyard_College',0,-.35,2.50,.55,.58)
    for x in [-1.52,1.52]:building('Courtyard_Wing',x,-.02,.52,.49,1.06)
    box('Courtyard_Pool',(0,.083,.29),(1.70,.010,.45),'leather_blue',.018)
    for x in [-1.04,1.04]:box('Courtyard_Colonnade',(x,.28,.25),(.09,.42,.11),'stone',.004)
    collection('theme_hills');theme_base()
    for x,h in [(-1.65,.10),(-.60,.20),(.45,.31),(1.50,.42)]:box('Hills_Terrace',(x,.075+h/2,-.10),(1.02,h,1.1),'stone_dark',.015);building('Hills_Department',x,-.22,.83,.33,.63,y=.075+h)
    collection('theme_coast');theme_base();box('Coast_SurveyWater',(.95,.077,-.10),(2.42,.014,1.45),'leather_blue',.006);building('Coast_Institute',-1.20,-.23,1.7,.49,.65)
    cylinder('Coast_Tower',(-.1,.38,-.34),.16,.60,'stone',24,r2=.125);cylinder('Coast_Observatory',(-.1,.72,-.34),.18,.065,'brass',24);box('Coast_Jetty',(.36,.12,.29),(1.35,.055,.16),'stone',.006)
    collection('theme_arts');theme_base();building('Arts_Academy',-1.35,-.29,1.5,.52,.68)
    for j in range(4):box('Arts_Tier',(.98,.10+j*.07,.41-j*.23),(1.73,.07,.22),'stone',.007)
    for x in [.25,.61,.97,1.33,1.69]:cylinder('Arts_Column',(x,.40,-.58),.035,.62,'stone',16)
    box('Arts_Portico',(.97,.73,-.57),(1.73,.045,.37),'stone',.008)
    collection('theme_workshop');theme_base();building('Applied_Lab',-1.25,-.25,1.6,.50,.72);building('Applied_Workshop',.87,-.24,1.8,.39,.72,roof='leather_blue')
    for x in [.25,.66,1.07,1.48]:box('Applied_RoofLight',(x,.52,-.23),(.29,.10,.48),'glass',.005)

def features():
    collection('feature_palm');cylinder('Herbarium_Base',(0,.025,0),.23,.05,'brass',24);rod('Herbarium_Palm',(0,.05,0),(.015,.60,0),.021,'walnut',16)
    for j in range(9):
        a=j*math.tau/9
        for k in range(3):
            rr=.10+k*.055;yy=.62-.08*(rr/.21)**2;xx=math.cos(a)*rr;zz=math.sin(a)*rr;rod('Herbarium_Frond',(xx*.6,yy+.016,zz*.6),(xx,yy,zz),.006,'brass',6)
    collection('feature_dairy');cylinder('Agriculture_Base',(0,.025,0),.24,.05,'walnut',24);cylinder('Agriculture_MilkBottle',(0,.20,0),.083,.31,'stone',32);cylinder('Agriculture_Shoulder',(0,.365,0),.083,.045,'stone',32,r2=.041);cylinder('Agriculture_Neck',(0,.413,0),.041,.051,'stone',24);cylinder('Agriculture_Cap',(0,.447,0),.047,.02,'brass',24)
    collection('feature_book')
    for j,key in enumerate(['leather_red','leather_green','leather_blue']):box('Research_BoundVolume',(0,.040+j*.056,0),(.43,.048,.31),key,.008);box('Research_PageEdge',(0,.040+j*.056,.157),(.39,.029,.012),'paper',.002)
    collection('feature_tea');cylinder('Tea_Tray',(0,.022,0),.25,.044,'walnut',32);cylinder('Tea_Cup',(0,.095,0),.085,.11,'stone',32,r2=.108);cylinder('Tea_Infusion',(0,.152,0),.096,.003,'walnut',32);arc('Tea_Handle',.11,.09,0,.053,.011,.014,'brass',20)

def export_asset(name,col):
    deps=bpy.context.evaluated_depsgraph_get();outputs=[];total_triangles=0;unique_materials=set()
    groups={'Architecture':[ob for ob in col.objects if 'FloorSurface' not in ob.name],'Floor':[ob for ob in col.objects if 'FloorSurface' in ob.name]}
    for group,objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT');copies=[]
        for ob in objects:
            if ob.type!='MESH':continue
            data=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps);copy=bpy.data.objects.new('EXPORT_'+ob.name,data);scene.collection.objects.link(copy);copy.matrix_world=ob.matrix_world.copy();copy.select_set(True);copies.append(copy)
        if not copies:continue
        bpy.context.view_layer.objects.active=copies[0]
        if len(copies)>1:bpy.ops.object.join()
        out=bpy.context.object;out.name='SM_University_Library_'+name+('_Floor' if group=='Floor' else '');bpy.ops.object.transform_apply(location=True,rotation=True,scale=True);out.data.calc_loop_triangles();total_triangles+=len(out.data.loop_triangles);unique_materials.update(mat.name for mat in out.data.materials);outputs.append(out)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in outputs:ob.select_set(True)
    stats={'triangles':total_triangles,'source_parts':len(col.objects),'materials':len(unique_materials),'textures':'PBR base colour, normal and roughness','uv':'Material-scale planar UVs; floor is a unique single-surface atlas'}
    tmp=OUT/(name+'.new.glb');bpy.ops.export_scene.gltf(filepath=str(tmp),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_materials='EXPORT',export_vertex_color='NONE');os.replace(tmp,OUT/(name+'.glb'))
    stats['export_cleanup']=optimize_glb(OUT/(name+'.glb'))
    stats['triangles']=stats['export_cleanup']['triangles_after']
    stats['bytes']=(OUT/(name+'.glb')).stat().st_size;STATS[name]=stats
    for ob in outputs:bpy.data.objects.remove(ob,do_unlink=True)
    print('LIBRARY_ASSET_READY '+name+' '+json.dumps(stats),flush=True)

def camera(name,p,target,lens=26):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;scene.camera=ob
def area(name,p,target,power,color,size):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.color=color;data.shape='DISK';data.size=size;ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=gv(p);ob.rotation_euler=(gv(target)-ob.location).to_track_quat('-Z','Y').to_euler()
def render(name,visible):
    for key,col in ASSETS.items():col.hide_render=key!=visible
    scene.render.filepath=str(ART/(name+'.png'));bpy.ops.render.render(write_still=True)

print('LIBRARY_BAKING_TEXTURES',flush=True);bake_maps()
for key in ['walnut','stone','stone_dark','plaster','leather_green','leather_red','leather_blue','paper']:material(key)
material('brass',(.40,.245,.075),metal=.82,rough=.28);material('glass',(.49,.65,.65),rough=.12,alpha=.12);material('lamp',(1,.62,.26),rough=.45,emission=1.25)
material('crevice',(.04,.034,.026),rough=.99)
print('LIBRARY_AUTHORING_PRIMARY',flush=True);build_atrium();build_booth()
for key in ['atrium','booth']:export_asset(key,ASSETS[key])
if not PRIMARY:
    print('LIBRARY_AUTHORING_GALLERIES',flush=True);build_gallery();themes();features()
    for key in ASSETS:
        if key not in ['atrium','booth']:export_asset(key,ASSETS[key])
for im in bpy.data.images:
    if im.source=='FILE':im.pack()
for key,col in ASSETS.items():col.hide_viewport=key!='atrium';col.hide_render=key!='atrium'
scene['floor_single_surface']=True;scene['art_revision']='r3.1-library-single-surface-floor';scene['source_provenance']='Original metric modeling and deterministic mathematical PBR raster bakes; no downloaded assets.'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'UniversityHall_Library.blend'))
layout_path=OUT/'layout.json';layout=json.loads(layout_path.read_text(encoding='utf-8')) if layout_path.exists() else {};layout['style']='classical_academic_library';layout['ceiling_height']=10.3
layout.setdefault('atrium',{})['lights']=[{'position':[side*12,1.55,3.5],'color':'#ffd7a0','energy':2.0,'range':8.5} for side in [-1,1]]+[{'position':[0,5.4,z],'color':'#ffdbad','energy':3.0,'range':10.5} for z in [-4.5,4.5]]
layout.setdefault('gallery',{})['lights']=[{'position':[x,1.35,-17.8],'color':'#ffd7a0','energy':2.0,'range':8.5} for x in [-3.8,3.8]]
def collider(name,center,size):return {'name':name,'center':center,'size':size}
atrium_colliders=[collider('map',[0,.445,0],[2.8,.89,2.15])]
for side in [-1,1]:
    atrium_colliders.append(collider('reading_bench',[side*7,.55,4.8],[3.05,1.10,.75]))
    for z in [-3.5,3.5]:atrium_colliders.append(collider('reading_cabinet',[side*12,.51,z],[1.3,1.02,3.45]))
    for z in [-8,-2,4,10]:atrium_colliders.append(collider('side_bookcase',[side*15.1,1.84,z],[.95,3.68,5.12]))
    for z in [-10,-5,0,5,10]:atrium_colliders.append(collider('walnut_column',[side*14.65,2.3,z],[.57,4.6,.57]))
for x in [-9,-3,3,9]:atrium_colliders.append(collider('back_bookcase',[x,1.8,-12.2],[2.64,3.6,.95]))
for x,z in [(x,-9) for x in [-12,-6,0,6,12]]+[(0,11)]:
    for side in [-1,1]:atrium_colliders.append(collider('archive_door_pier',[x+side*1.965,1.10,z],[.50,2.2,.67]))
    atrium_colliders.append(collider('archive_door',[x,1.25,z+(.28 if z>0 else -.28)],[3.65,2.5,.12]))
for x in [-8,8]:atrium_colliders.append(collider('entrance_bookcase',[x,1.80,12.18],[7.05,3.60,.95]))
layout['atrium']['obstacles']=atrium_colliders
gallery_colliders=[]
for side in [-1,1]:
    for z in [-14,-7,0,7,14]:gallery_colliders.append(collider('side_bookcase',[side*14.2,1.825,z],[.95,3.65,6.15]))
    for z in [-17,-9,-1,7,15]:gallery_colliders.append(collider('walnut_pier',[side*13.1,2.3,z],[.50,4.6,.50]))
for x in [-11,0,11]:gallery_colliders.append(collider('back_bookcase',[x,1.875,-18.15],[5.25,3.75,.95]))
for x in [-3.8,3.8]:gallery_colliders.append(collider('reading_console',[x,.4,-17.8],[.75,.8,.55]))
for x,z in [(-7,-16),(7,-16),(0,17.8)]:
    for side in [-1,1]:gallery_colliders.append(collider('archive_door_pier',[x+side*1.965,1.10,z],[.50,2.2,.67]))
    gallery_colliders.append(collider('archive_door',[x,1.25,z+(.28 if z>0 else -.28)],[3.65,2.5,.12]))
for x in [-8,8]:gallery_colliders.append(collider('entrance_bookcase',[x,1.80,18.18],[7.05,3.60,.95]))
layout['gallery']['obstacles']=gallery_colliders
layout.setdefault('booth',{})['display_collision_center']=[0,1.43,-.20];layout['booth']['display_collision_size']=[4.96,1.08,1.84]
layout_path.write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
manifest={'title':'典雅大學圖書館','revision':'2026-10-11-r3.1-library','stage':'primary' if PRIMARY else 'complete','source':'UniversityHall_Library.blend','style':'Real-scale walnut academic library, two-storey bookcases, honed stone inlays, brass rails, textured leather volumes, warm task lights. No faceted plants or colourful toy scenery.','textures':{'source':'Original deterministic mathematical PNG bakes: walnut grain, stone mottling, leather pores, paper fibres','size':1024,'maps':['sRGB base colour','non-colour roughness','tangent normal +Y'],'uv':'Physical-scale planar projection; intentional tiling at construction seams','license':'Project-authored, no external assets'},'stats':STATS,'runtime_note':'No COLOR_0 required; PBR image maps carry appearance. Import helper must preserve albedo/roughness/normal maps.'}
(ART/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8');(ART/'validation_report.json').write_text(json.dumps({'revision':manifest['revision'],'stage':manifest['stage'],'blender':bpy.app.version_string,'assets':STATS,'total_triangles':sum(v['triangles'] for v in STATS.values()),'total_bytes':sum(v['bytes'] for v in STATS.values()),'verification':'UV and textured GLB exports complete; actual Godot view remains the acceptance gate.'},ensure_ascii=False,indent=2),encoding='utf-8')
(ART/'SOURCE_NOTES.md').write_text('# Classical academic library — revision 3\n\nThe user selected a dignified university library, replacing the rejected toy-like garden studies. Current editable source: `UniversityHall_Library.blend`. Earlier named .blend files and revision folders are draft studies.\n\nAll architecture is original metric geometry. Walnut, stone, leather and paper maps are original deterministic mathematical raster bakes in tools/build_university_hall.py. Real 1024px glTF base colour, roughness and normal images replace the old vertex-only palette. UV repeats are intentional at physical scale and construction seams. No external assets or fonts are embedded.\n\nRuntime labels, collision and lighting remain Godot-owned. Two front bankers lamps and two central brass chandeliers in the atrium provide four practical light positions; the gallery has two reading-lamp light positions in layout.json. Updated furniture and glass showcase collision boxes are included. Upper galleries are visual architecture and inaccessible. GLBs are replaced atomically. Source images are packed in the editable Blender library.\n\nThe previous white model bug was Godot retaining COLOR_0 but disabling vertex_color_use_as_albedo. The new PBR materials must retain image inputs; the importer must not replace them with a vertex-only material.\n',encoding='utf-8')
area('LGT_Clerestory',(0,10.7,0),(0,0,-2),3300,(.80,.88,1),11);area('LGT_FrontFill',(0,6,10),(0,2,-8),1100,(1,.79,.56),8)
for side in [-1,1]:area('LGT_Reading',(side*11.5,2.2,0),(side*8,0,0),400,(1,.65,.32),5)
camera('CAM_Library_Player',(0,3.3,9),(0,2.8,-9),24);render('library_atrium_player','atrium')
for col in ASSETS.values():col.hide_viewport=False
camera('CAM_Library_Vitrine',(6.8,4.6,7.4),(0,1.3,0),48);area('LGT_Vitrine_Key',(1,6,3),(0,1,0),500,(1,.86,.68),4);render('library_archive_vitrine','booth')
print('LIBRARY_BUILD_COMPLETE',flush=True)
