"""Author curved branching cherry trees with botanical RGBA flower sprigs.

Run in a separate Blender --background --factory-startup process. Original
masters remain intact; revised masters and runtime GLBs are saved explicitly.
"""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector, Quaternion

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'game/assets/scenery'
MASTER = ROOT/'art/WorldScenery'
atlas = bpy.data.images.load(str(OUT/'sakura-atlas.png'))
atlas.pack()

def material(name, color):
    m = bpy.data.materials.new(name); m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=.92
    p.inputs['Specular IOR Level'].default_value=.12
    return m

bark=material('Cherry bark • warm umber',(.19,.105,.085))
bn=bark.node_tree.nodes; bl=bark.node_tree.links
vc=bn.new('ShaderNodeVertexColor'); vc.layer_name='BarkVariation'
bl.new(vc.outputs['Color'],bn.get('Principled BSDF').inputs['Base Color'])
flower=material('Botanical sakura • cutout petals',(.82,.63,.68))
p=flower.node_tree.nodes.get('Principled BSDF')
tex=flower.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=atlas
flower.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
flower.node_tree.links.new(tex.outputs['Alpha'],p.inputs['Alpha'])
flower.use_backface_culling=False
flower.surface_render_method='DITHERED'

class Batch:
    def __init__(self): self.v=[]; self.f=[]; self.uv=[]; self.colors=[]
    def vertex(self,p,uv=(0,0),c=(.19,.105,.085,1)):
        self.v.append(tuple(p)); self.uv.append(uv); self.colors.append(c)
        return len(self.v)-1
    def mesh(self,name,mat):
        mesh=bpy.data.meshes.new(name); mesh.from_pydata(self.v,[],self.f); mesh.update()
        obj=bpy.data.objects.new(name,mesh); bpy.context.collection.objects.link(obj)
        mesh.materials.append(mat)
        uv=mesh.uv_layers.new(name='UVMap')
        col=mesh.color_attributes.new(name='BarkVariation',type='FLOAT_COLOR',domain='POINT')
        for i,c in enumerate(self.colors): col.data[i].color=c
        for face in mesh.polygons:
            face.use_smooth=True
            for li in face.loop_indices: uv.data[li].uv=self.uv[mesh.loops[li].vertex_index]
        return obj

def tube(batch, points, radii, seed):
    rng=random.Random(seed); sides=9; rings=[]
    for j,p in enumerate(points):
        p=Vector(p); tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
        q=tangent.normalized().to_track_quat('Z','Y'); ring=[]
        for i in range(sides):
            a=math.tau*i/sides
            radius=radii[j]*(1+.11*math.sin(a*3+seed))
            c=.72+.20*math.sin(a*4+seed)+rng.random()*.08
            ring.append(batch.vertex(p+q@Vector((math.cos(a)*radius,math.sin(a)*radius,0)),(i/sides,j/len(points)),(.23*c,.135*c,.11*c,1)))
        rings.append(ring)
    for j in range(len(rings)-1):
        for i in range(sides): batch.f.append((rings[j][i],rings[j][(i+1)%sides],rings[j+1][(i+1)%sides],rings[j+1][i]))
    batch.f.append(tuple(reversed(rings[0]))); batch.f.append(tuple(rings[-1]))

def branch(batch,a,b,r0,r1,seed,bend=.18):
    a,b=Vector(a),Vector(b); rng=random.Random(seed)
    side=Vector((rng.uniform(-1,1),rng.uniform(-1,1),.5))*bend
    points=[a.lerp(b,t/7)+side*math.sin(t/7*math.pi) for t in range(8)]
    tube(batch,points,[r0+(r1-r0)*t/7 for t in range(8)],seed)

def card(batch,pos,size,q,tile):
    # Nine vertices curve the sprig in two axes, avoiding a rigid crossed plane.
    u0,v0=[(0,.5),(.5,.5),(.5,0),(0,0)][tile]
    ids=[]
    for y in range(3):
        row=[]
        for x in range(3):
            a=x/2-.5; b=y/2-.5
            p=Vector(pos)+q@Vector((a*size,b*size,(a*a+b*b)*size*.16))
            row.append(batch.vertex(p,(u0+.008+x/2*.484,v0+.008+y/2*.484),(1,1,1,1)))
        ids.append(row)
    for y in range(2):
        for x in range(2): batch.f.append((ids[y][x],ids[y][x+1],ids[y+1][x+1],ids[y+1][x]))

reports=[]
for variant in range(3):
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    rng=random.Random(2309+variant); wood=Batch(); bloom=Batch()
    height=3.55+variant*.16
    spine=[Vector((.11*math.sin(j*.6+variant)-.11*math.sin(variant),.065*math.sin(j*.9),j*.42)) for j in range(8)]
    tube(wood,spine,[.27,.19,.165,.145,.12,.09,.06,.025],variant)
    for i in range(5):
        a=i*math.tau/5+.4
        branch(wood,(math.cos(a)*.60,math.sin(a)*.60,.01),(.03,0,.40),.06,.14,50+i)
    for i in range(13):
        angle=i*2.399+variant*.65
        start=spine[3+i%4]
        reach=1.45+rng.random()*.50
        end=Vector((math.cos(angle)*reach,math.sin(angle)*reach,height-.7+rng.random()*.8))
        branch(wood,start,end,.083,.025,100+i+variant*17,.25)
        for j in range(4):
            a=angle+(j-1.5)*.48
            tip=end+Vector((math.cos(a)*rng.uniform(.35,.75),math.sin(a)*rng.uniform(.35,.75),rng.uniform(-.12,.52)))
            anchor=start.lerp(end,.50+j*.12)
            branch(wood,anchor,tip,.033,.006,300+i*4+j,.12)
            for k in range(6):
                t=.45+k*.12
                pos=anchor.lerp(tip,t)+Vector((rng.uniform(-.25,.25),rng.uniform(-.25,.25),rng.uniform(-.14,.24)))
                normal=Vector((math.cos(a)*.55,math.sin(a)*.55,.8))
                normal+=Vector((rng.uniform(-.6,.6),rng.uniform(-.6,.6),rng.uniform(-.4,.4)))
                q=normal.normalized().to_track_quat('Z','Y') @ Quaternion(Vector((0,0,1)),rng.random()*math.tau)
                card(bloom,pos,rng.uniform(.58,.84),q,(i+j+k+variant)%3)
    wood.mesh('GEO-Sakura flowing trunk and twigs',bark)
    bloom.mesh('GEO-Sakura individual flower sprigs',flower)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER/f'sakura_refined_{variant}.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'sakura_{variant}.glb'),export_format='GLB',use_selection=True,export_animations=False)
    reports.append({'variant':variant,'branch_vertices':len(wood.v),'flower_cards':312,'flower_vertices':len(bloom.v),'atlas':'sakura-atlas.png'})

bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
petal=Batch()
card(petal,(0,0,0),.145,Quaternion(),3)
petal.mesh('GEO-Curled notched sakura petal',flower)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(MASTER/'sakura_petal.blend'))
bpy.ops.export_scene.gltf(filepath=str(OUT/'sakura_petal.glb'),export_format='GLB',use_selection=True,export_animations=False)
(OUT/'sakura-refinement.json').write_text(json.dumps(reports,indent=2),encoding='utf8')
print('REFINED_SAKURA_OK',json.dumps(reports))
