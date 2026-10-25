"""Original meter-scale tree meshes and baked PBR/leaf atlases, Blender 5.2.
No downloaded assets. Root is ground level; roots terminate below ground.
"""
import bpy, math, random, json, struct
import numpy as np
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'game/assets/vegetation_rebuilt'; ART=ROOT/'art/Vegetation'; REVIEW=ROOT/'deliverables/vegetation'
for p in (OUT,ART,REVIEW,OUT/'textures'): p.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
scene=bpy.context.scene; scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1
scene.render.engine='CYCLES'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.resolution_x=1000; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
geo=bpy.data.collections.new('COL_Geo'); scene.collection.children.link(geo)
studio=bpy.data.collections.new('COL_ReferenceAndStudio'); scene.collection.children.link(studio)

def image(name,rgba):
    im=bpy.data.images.new(name,width=rgba.shape[1],height=rgba.shape[0],alpha=True)
    im.pixels.foreach_set(rgba.astype(np.float32).ravel()); im.filepath_raw=str(OUT/'textures'/(name+'.png')); im.file_format='PNG'; im.save(); im.pack()
    return im

def bark_images(key):
    N=512; yy,xx=np.mgrid[0:N,0:N]/N; rng=np.random.default_rng(172+len(key))
    grain=(np.sin(xx*math.tau*29+np.sin(yy*math.tau*3)*.7)+np.sin(xx*math.tau*67+np.sin(yy*17)*1.7))*.5
    groove=np.clip((-grain-.4)*1.2,0,1)
    noise=rng.random((N,N))*.07
    value=.68+.16*grain+noise-groove*.22
    color=np.zeros((N,N,4)); color[:,:,3]=1
    if key=='birch':
        tone=np.ones((N,N))*.72+noise
        for j in range(44):
            x,y=rng.random(2); w=rng.uniform(.015,.075); h=rng.uniform(.002,.009)
            patch=((np.minimum(abs(xx-x),1-abs(xx-x))/w)**2+((yy-y)/h)**2)<1
            tone[patch]=rng.uniform(.07,.16)
        for i,c in enumerate((1.0,.99,.90)): color[:,:,i]=tone*c
        height=tone*.15+grain*.02
    else:
        base={'alder':(.26,.225,.175),'pine':(.30,.235,.16),'willow':(.285,.255,.205)}[key]
        for i,c in enumerate(base): color[:,:,i]=value*c
        height=grain*.14-groove*.15
    dy,dx=np.gradient(height); normal=np.stack((-dx*35,-dy*35,np.ones_like(dx)),axis=2); normal/=np.linalg.norm(normal,axis=2)[:,:,None]
    rgba=np.ones((N,N,4)); rgba[:,:,:3]=normal*.5+.5
    return image(key+'_bark_color',color),image(key+'_bark_normal',rgba)

def foliage_image(key):
    N=512; rgba=np.zeros((N,N,4),dtype=float); yy,xx=np.mgrid[0:N,0:N]/N
    rng=random.Random(900+len(key)); base={'alder':(.24,.36,.11),'birch':(.26,.40,.13),'pine':(.18,.29,.17),'willow':(.34,.43,.20)}[key]
    def leaf(cx,cy,length,width,angle,tone=1):
        vx,vy=xx-cx,yy-cy; u=(vx*math.cos(angle)+vy*math.sin(angle))/length; v=(-vx*math.sin(angle)+vy*math.cos(angle))/width
        edge=np.maximum(0,1-u*u)**.65*(1+.045*np.cos(u*42))
        mask=(np.abs(u)<1)&(np.abs(v)<edge)
        veins=(np.exp(-np.abs(v)*45)+.28*np.exp(-np.abs(np.sin((u+abs(v)*.55)*33))*25))
        light=tone*(.88+.10*u+.12*(1-abs(v)))
        for c in range(3): rgba[:,:,c][mask]=(base[c]*light+veins*.025)[mask]
        rgba[:,:,3][mask]=1
    # Thin twig retained in the atlas connects all leaves to the bough.
    stem=(abs(xx-(.5+.025*np.sin(yy*6)))<.004)&(yy>.03)&(yy<.95)
    rgba[stem]=(.22,.19,.10,1)
    if key=='pine':
        for j in range(13):
            y=.11+j*.061
            for side in (-1,1):
                x=.5+side*(.06+.035*math.sin(j))
                for needle in range(9):
                    a=math.pi/2+side*(.25+needle*.10)
                    leaf(x+side*needle*.014,y+needle*.009,.16-rng.random()*.04,.0045,a,.82+rng.random()*.3)
    else:
        for j in range(7):
            y=.14+j*.11
            for side in (-1,1):
                x=.5+side*(.16+.035*math.sin(j*1.7))
                a=math.pi/2-side*(.65+rng.random()*.25)
                leaf(x,y,.16 if key!='willow' else .215,.075 if key!='willow' else .029,a,.80+rng.random()*.34)
        leaf(.5,.88,.105,.055 if key!='willow' else .027,math.pi/2,1.05)
    return image(key+'_foliage_atlas',rgba)

def material(key):
    col,nor=bark_images(key)
    bark=bpy.data.materials.new('MAT_'+key+'_BarkPBR'); bark.use_nodes=True
    p=bark.node_tree.nodes.get('Principled BSDF'); p.inputs['Roughness'].default_value=.89
    nodes=bark.node_tree.nodes; tex=nodes.new('ShaderNodeTexImage'); tex.image=col; bark.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    tx=nodes.new('ShaderNodeTexImage'); tx.image=nor; nor.colorspace_settings.name='Non-Color'
    nm=nodes.new('ShaderNodeNormalMap'); nm.inputs['Strength'].default_value=.5
    bark.node_tree.links.new(tx.outputs['Color'],nm.inputs['Color']); bark.node_tree.links.new(nm.outputs['Normal'],p.inputs['Normal'])
    leaves=bpy.data.materials.new('MAT_'+key+'_FoliageCutout'); leaves.use_nodes=True; leaves.use_backface_culling=False
    leaves.surface_render_method='DITHERED'
    p=leaves.node_tree.nodes.get('Principled BSDF'); p.inputs['Roughness'].default_value=.84
    p.inputs['Specular IOR Level'].default_value=.22
    tex=leaves.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=foliage_image(key)
    leaves.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color']); leaves.node_tree.links.new(tex.outputs['Alpha'],p.inputs['Alpha'])
    # Exporter reads the standard glTF alpha mode metadata when configured.
    leaves['alpha_mode']='MASK'; leaves['alpha_cutoff']=.5
    return bark,leaves

class Tree:
    def __init__(self,key,height):
        self.key=key; self.height=height; self.rng=random.Random({'alder':32,'birch':83,'pine':71,'willow':94}[key]); self.bv=[];self.bf=[];self.buv=[];self.lv=[];self.lf=[];self.luv=[];self.cards=[]
    def tube(self,points,radii,sides=5):
        off=len(self.bv); distance=0
        for j,p in enumerate(points):
            p=Vector(p); direction=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
            direction.normalize(); tangent=direction.cross(Vector((0,1,0))).normalized()
            if tangent.length<.1:tangent=direction.cross(Vector((1,0,0))).normalized()
            bitangent=direction.cross(tangent).normalized()
            if j:distance+=(p-Vector(points[j-1])).length
            for i in range(sides+1):
                angle=math.tau*i/sides; self.bv.append(tuple(p+radii[j]*(tangent*math.cos(angle)+bitangent*math.sin(angle))))
                self.buv.append((i/sides,distance*.65))
        for j in range(len(points)-1):
            for i in range(sides):
                a=off+j*(sides+1)+i; self.bf.append((a,a+1,a+sides+2,a+sides+1))
        self.bf.append(tuple(off+i for i in reversed(range(sides))))
        self.bf.append(tuple(off+(len(points)-1)*(sides+1)+i for i in range(sides)))
    def card(self,at,direction,size=.78):
        at=Vector(at); direction=Vector(direction).normalized()
        # Leaves fan around a branch in several planes, with a curved center.
        z=direction; x=z.cross(Vector((0,0,1))).normalized()
        if x.length<.1:x=Vector((1,0,0))
        angle=self.rng.uniform(-1.2,1.2); y=z.cross(x).normalized(); x=x*math.cos(angle)+y*math.sin(angle); y=z.cross(x).normalized()
        off=len(self.lv); self.cards.append((at.copy(),x.copy(),z.copy(),size))
        for j in range(3):
            v=j/2
            for i in range(3):
                u=i/2; p=at+x*(u-.5)*size+z*(v-.3)*size+y*(math.sin(u*math.pi)*.06+math.sin(v*math.pi)*.025)
                self.lv.append(tuple(p));self.luv.append((u,v))
        for j in range(2):
            for i in range(2):
                a=off+j*3+i;self.lf.append((a,a+1,a+4,a+3))
    def make(self):
        key=self.key; H=self.height; rng=self.rng
        trunk_radius={'alder':.19,'birch':.115,'pine':.145,'willow':.25}[key]
        trunk=[Vector((.06*math.sin(i*.55),.04*math.sin(i*.8),-.16+(H+.06)*i/14)) for i in range(15)]
        radii=[trunk_radius*(1-i/15)**1.1+.008 for i in range(15)];radii[0]*=1.25
        self.tube(trunk,radii,9)
        if key=='pine': self.pine(trunk);return
        count=13 if key!='willow' else 11
        for i in range(count):
            fraction=.32+i/count*.57+rng.uniform(-.025,.025); start=Vector((.06*math.sin(fraction*14*.55),.04*math.sin(fraction*14*.8),H*fraction))
            a=i*2.399+rng.uniform(-.25,.25); radial=Vector((math.cos(a),math.sin(a),0))
            crown=max(.20,1-((fraction-.56)/.46)**2)**.5
            extent=(2.05 if key=='alder' else 1.23 if key=='birch' else 2.6)*crown*rng.uniform(.82,1.12)
            end=start+radial*extent+Vector((0,0,rng.uniform(.35,.85)))
            self.tube([start,start.lerp(end,.32)+Vector((0,0,.15)),start.lerp(end,.7),end],[trunk_radius*.49,.065,.038,.011],6)
            for j in range(4):
                t=.36+j*.19; base=start.lerp(end,t); angle=a+(-1 if j%2 else 1)*rng.uniform(.35,.8)
                d=Vector((math.cos(angle),math.sin(angle),rng.uniform(.1,.5)))
                finish=base+d*rng.uniform(.45 if key=='birch' else .6,.72 if key=='birch' else 1.08)
                self.tube([base,base.lerp(finish,.55)+Vector((0,0,.10)),finish],[.031,.018,.004],5)
                for n in range(2):
                    self.card(base+Vector((rng.uniform(-.25,.25),rng.uniform(-.25,.25),rng.uniform(-.2,.5))),Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(.3,1))),.83)
                if key=='willow':
                    for w in range(3):
                        top=base.lerp(finish,.45+w*.24);drop=rng.uniform(.85,1.8);out=radial*rng.uniform(.08,.3)
                        pts=[top,top+out+Vector((0,0,-drop*.25)),top+out*1.2+Vector((0,0,-drop*.6)),top+out*.8+Vector((0,0,-drop))]
                        self.tube(pts,[.011,.008,.005,.0018],4)
                        for n in range(4):self.card(pts[min(n,2)].lerp(pts[min(n+1,3)],.3),(rng.uniform(-.2,.2),rng.uniform(-.2,.2),-1),.73)
                else:
                    for k in range(3):
                        twigbase=base.lerp(finish,.43+k*.25);ta=angle+(-1 if k%2 else 1)*rng.uniform(.4,1.0)
                        td=Vector((math.cos(ta),math.sin(ta),rng.uniform(-.05,.6)));te=twigbase+td*rng.uniform(.25,.42 if key=='birch' else .64)
                        self.tube([twigbase,twigbase.lerp(te,.5),te],[.009,.005,.0015],4)
                        for n in range(3):
                            at=twigbase.lerp(te,.24+n*.33)
                            self.card(at,td+Vector((rng.uniform(-.4,.4),rng.uniform(-.4,.4),rng.uniform(-.4,.5))),.72 if key=='birch' else .83)
            # Branch-tip spray closes the crown without a solid canopy mesh.
            for k in range(5):self.card(end+Vector((rng.uniform(-.18,.18),rng.uniform(-.18,.18),rng.uniform(-.1,.25))),radial+Vector((rng.uniform(-.5,.5),rng.uniform(-.5,.5),.5)),.78)
        for k in range(46):
            a=k*2.399; r=rng.uniform(.12,.66);p=Vector((math.cos(a)*r,math.sin(a)*r,H-.18+rng.uniform(-.52,.12)))
            self.card(p,Vector((math.cos(a)*.45,math.sin(a)*.45,.8)),.71)
    def pine(self,trunk):
        rng=self.rng;H=self.height
        for tier in range(9):
            z=H*(.20+tier*.082); extent=2.0*(1-tier/10)**.85
            for j in range(6):
                a=j*math.tau/6+tier*1.13+rng.uniform(-.18,.18);d=Vector((math.cos(a),math.sin(a),0));start=Vector((0,0,z+rng.uniform(-.14,.14)));end=start+d*extent*rng.uniform(.87,1.13)+Vector((0,0,-.05+extent*.16))
                self.tube([start,start.lerp(end,.5)+Vector((0,0,-.12)),end],[.045*(1-tier/12),.018,.003],5)
                for k in range(4):
                    base=start.lerp(end,.25+k*.22);side=Vector((-d.y,d.x,.12))*(-1 if k%2 else 1);tip=base+side*extent*.30+d*.2
                    self.tube([base,tip],[.009,.002],4)
                    for n in range(3):self.card(base.lerp(tip,.25+n*.34),d+side*.7+Vector((0,0,.4)),.70 if tier<6 else .51)
        for k in range(36):
            a=k*2.399;z=H-.65+k/36*.58;r=(H-z)*.55
            self.card(Vector((math.cos(a)*r,math.sin(a)*r,z)),Vector((math.cos(a)*.25,math.sin(a)*.25,.9)),.39)

def mesh(name,verts,faces,uv,mat):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    ob=bpy.data.objects.new(name,data);geo.objects.link(ob);data.materials.append(mat)
    layer=data.uv_layers.new(name='UV_Surface')
    for poly in data.polygons:
        poly.use_smooth=True
        for li in poly.loop_indices:layer.data[li].uv=uv[data.loops[li].vertex_index]
    if 'Foliage' in name:
        # The bough's bent cards share crown-oriented normals rather than
        # alternating black undersides. This is baked mesh data, not a shader.
        height=max(v[2] for v in verts);normals=[]
        for loop in data.loops:
            p=data.vertices[loop.vertex_index].co
            n=Vector((p.x*.25,p.y*.25,.7+(p.z-height*.6)*.14)).normalized()
            normals.append(tuple(n))
        data.normals_split_custom_set(normals)
    return ob

def ensure_cutout(path):
    raw=path.read_bytes(); json_length=struct.unpack_from('<I',raw,12)[0]
    gltf=json.loads(raw[20:20+json_length]);tail=raw[20+json_length:]
    for mat in gltf.get('materials',[]):
        if 'Foliage' in mat.get('name',''):
            mat['alphaMode']='MASK';mat['alphaCutoff']=.5;mat['doubleSided']=True
        else:mat['doubleSided']=False
    encoded=json.dumps(gltf,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4E4F534A)+encoded+tail)

trees={};report={'authorship':'Original parametric branch topology and original algorithmic bark/leaf textures; no external asset sources.','units':'meters','root':'Ground at y=0 in Godot; trunk extends 0.16 m below ground. No exposed sculpted roots.','models':{}}
for key,height in [('alder',6.4),('birch',6.85),('pine',7.2),('willow',6.6)]:
    tree=Tree(key,height);tree.make();bark,leaves=material(key)
    wood=mesh('SM_'+key+'_BarkBranches',tree.bv,tree.bf,tree.buv,bark)
    foliage=mesh('SM_'+key+'_Foliage',tree.lv,tree.lf,tree.luv,leaves)
    trees[key]=[wood,foliage];tris=0
    for ob in trees[key]:ob.data.calc_loop_triangles();tris+=len(ob.data.loop_triangles)
    assert tris<=12000,(key,tris)
    bpy.ops.object.select_all(action='DESELECT')
    for ob in trees[key]:ob.select_set(True)
    bpy.context.view_layer.objects.active=wood
    bpy.ops.export_scene.gltf(filepath=str(OUT/(key+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_animations=False,export_extras=True)
    ensure_cutout(OUT/(key+'.glb'))
    bounds=[Vector(v) for ob in trees[key] for v in ob.bound_box]
    report['models'][key]={'triangles':tris,'leaf_sprays':len(tree.cards),'materials':2,'dimensions_blender_xyz':[max(v[i] for v in bounds)-min(v[i] for v in bounds) for i in range(3)],'source_file':'art/Vegetation/TemperateTrees.blend','asset':key+'.glb'}
    print('TREE_EXPORTED',key,tris,len(tree.cards),flush=True)

# Neutral daylight with a meter-scale reference for real silhouette evaluation.
world=bpy.data.worlds.new('TreeDaylight');world.use_nodes=True;scene.world=world;world.node_tree.nodes['Background'].inputs['Color'].default_value=(.62,.72,.83,1);world.node_tree.nodes['Background'].inputs['Strength'].default_value=.65
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='StudioGround';floor.location.z=-.015
mat=bpy.data.materials.new('MAT_StudioGround');mat.diffuse_color=(.22,.24,.20,1);mat.use_nodes=True;mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'].default_value=(.22,.24,.20,1);mat.node_tree.nodes.get('Principled BSDF').inputs['Roughness'].default_value=.95;floor.data.materials.append(mat)
sun_data=bpy.data.lights.new('Sun','SUN');sun_data.energy=2.2;sun_data.angle=.09;sun=bpy.data.objects.new('Sun',sun_data);studio.objects.link(sun);sun.rotation_euler=(.5,-.5,-.5)
cam_data=bpy.data.cameras.new('TreeReview');cam=bpy.data.objects.new('TreeReview',cam_data);studio.objects.link(cam);scene.camera=cam;cam_data.lens=52
for key,obs in trees.items():
    for ob in geo.objects:ob.hide_render=ob not in obs
    cam.location=(10,-13,7);cam.rotation_euler=(Vector((0,0,3.5))-cam.location).to_track_quat('-Z','Y').to_euler()
    scene.render.filepath=str(REVIEW/(key+'.png'));bpy.ops.render.render(write_still=True)
for i,(key,obs) in enumerate(trees.items()):
    for ob in obs:ob.hide_render=False;ob.location.x=(i-1.5)*7
cam.location=(20,-34,13);cam_data.lens=43;cam.rotation_euler=(Vector((0,0,3.4))-cam.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath=str(REVIEW/'forest_species.png');bpy.ops.render.render(write_still=True)
(OUT/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
(ART/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'TemperateTrees.blend'))
print('VEGETATION_COMPLETE',report,flush=True)
