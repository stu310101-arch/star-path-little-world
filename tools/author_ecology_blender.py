"""Original botanical meshes: swept trunks, curved leaf blades, pinnate ferns,
cattail inflorescences and weathered bank stones. Separate Blender process."""
import bpy, math, random, json
from pathlib import Path
from mathutils import Vector, Quaternion
ROOT=Path(__file__).resolve().parents[1]
# Reuse the established swept branch and vertex-color mesh authoring tools.
exec((ROOT/'tools/refine_sakura_blender.py').read_text(encoding='utf8').split('reports=[]')[0])
OUT=ROOT/'game/assets/ecology'; OUT.mkdir(exist_ok=True)
MASTER=ROOT/'art/Ecology'; MASTER.mkdir(exist_ok=True)
def vertex_mat(name):
    mat=material(name,(1,1,1)); mat.use_backface_culling=False
    n=mat.node_tree.nodes.new('ShaderNodeVertexColor'); n.layer_name='BarkVariation'
    mat.node_tree.links.new(n.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    return mat
green=vertex_mat('Botanical leaves • midrib and edge colour'); timber=vertex_mat('Bark • longitudinal ridges'); earth=vertex_mat('Weathered mineral grain')
def leaf(batch,base,direction,length,width,color,lobed=False):
    q=Vector(direction).normalized().to_track_quat('Y','Z'); base=Vector(base); rings=[]
    for j in range(5):
        t=j/4; w=math.sin(math.pi*t)**.75*width*(1+.20*math.sin(t*math.pi*8) if lobed else 1)
        row=[]
        for k in [-1,0,1]:
            p=base+q@Vector((k*w,length*t,.12*length*math.sin(t*math.pi)+abs(k)*.045*length))
            shade=(.83 if k else 1.22)*(1-.17*t)
            row.append(batch.vertex(p,c=tuple(min(1,c*shade) for c in color)+(1,)))
        rings.append(row)
    for j in range(4):
        for k in range(2): batch.f.append((rings[j][k],rings[j+1][k],rings[j+1][k+1],rings[j][k+1]))
def recolor(batch,color):
    for i,p in enumerate(batch.v):
        f=.85+.15*math.sin(p[2]*27+p[0]*32)+.06*math.sin(p[1]*49)
        batch.colors[i]=tuple(c*f for c in color)+(1,)
report=[]
def save(name,batches):
    for title,batch,mat in batches: batch.mesh('GEO-'+title,mat)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_animations=False)
    report.append(dict(asset=name,vertices=sum(len(b.v) for _,b,_ in batches)))
def clear():
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for kind in ['alder','birch','willow','pine']:
    clear(); wood=Batch(); foliage=Batch(); rng=random.Random(719+len(kind))
    H={'alder':4.3,'birch':5.3,'willow':4.2,'pine':5.8}[kind]
    spine=[Vector((.10*math.sin(i*.6),.075*math.sin(i*.9),H*i/10)) for i in range(11)]
    tube(wood,spine,[.23*(1-i/11)**1.3+.006 for i in range(11)],31)
    for j in range(5):
        a=j*math.tau/5; branch(wood,(math.cos(a)*.46,math.sin(a)*.46,.0),spine[1],.045,.12,j)
    for j in range(13):
        a=j*2.399; start=spine[3+j%6]; reach=(1.4 if kind!='pine' else 1.65)*(1-(start.z/H)*.52)
        end=Vector((math.cos(a)*reach,math.sin(a)*reach,start.z+.7))
        branch(wood,start,end,.06,.01,j+40,.18)
        for k in range(5):
            angle=a+(k-2)*.4
            tip=end+Vector((math.cos(angle)*.6,math.sin(angle)*.6,.25))
            stem=start.lerp(end,.3+k*.13)
            if kind=='willow': tip.z-=.4+k*.12
            branch(wood,stem,tip,.018,.003,j*9+k+100,.12)
            for n in range(5):
                t=.28+n*.16; p=stem.lerp(tip,t)
                for sign in [-1,1]:
                    d=Vector((math.cos(angle+sign*.9),math.sin(angle+sign*.9),rng.uniform(.0,.65)))
                    if kind=='willow': d.z=-1.3
                    if kind=='pine':
                        for fan in range(1): leaf(foliage,p,d+Vector((.1*fan,-.1*fan,.2)),.35,.022,(.15,.31,.19))
                    else:
                        color={'alder':(.25,.43,.19),'birch':(.40,.55,.22),'willow':(.34,.48,.28)}[kind]
                        leaf(foliage,p,d,.32 if kind!='willow' else .43,.095 if kind!='willow' else .034,color,kind=='alder')
    recolor(wood,(.64,.62,.52) if kind=='birch' else (.24,.18,.12))
    # Birch lenticels are actual dark narrow bark patches, not cylinder stripes.
    if kind=='birch':
        for i in range(55):
            a=rng.random()*math.tau; z=rng.uniform(.35,H*.7); r=.23*(1-z/H)**1.3+.009
            p=Vector((.10*math.sin(z/H*6),.075*math.sin(z/H*9),z))+Vector((math.cos(a)*r,math.sin(a)*r,0))
            leaf(wood,p,(-math.sin(a),math.cos(a),.05),rng.uniform(.05,.13),.009,(.18,.19,.16))
    save(kind,[(kind+' branching bark',wood,timber),(kind+' individual veined leaves',foliage,green)])
clear(); fern=Batch()
for j in range(9):
    a=j*2.399
    for k in range(12):
        t=k/12; p=Vector((math.cos(a)*t*.65,math.sin(a)*t*.65,.16+.58*math.sin(t*math.pi*.8)))
        for side in [-1,1]:
            leaf(fern,p,(math.cos(a+side*.85),math.sin(a+side*.85),.1),.18*(1-t)+.045,.033*(1-t)+.004,(.22,.42,.20),True)
save('fern',[('Fern pinnate curved fronds',fern,green)])
clear(); reeds=Batch(); heads=Batch()
for i in range(13):
    a=i*2.399; p=Vector((math.cos(a)*.35,math.sin(a)*.35,0)); h=.85+(i%4)*.19
    tube(reeds,[p,p+Vector((.06,.03,h))],[.012,.008],i)
    tube(heads,[p+Vector((.06,.03,h*.80)),p+Vector((.065,.031,h))],[.043,.038],i)
    for j in range(3): leaf(reeds,p+Vector((0,0,.10+j*.12)),(math.cos(a+j),math.sin(a+j),1.4),h*.85,.035,(.32,.40,.15))
recolor(heads,(.28,.16,.08)); save('cattail',[('Arching reed blades',reeds,green),('Cattail seed heads',heads,timber)])
# Keep the corrected standalone stone source authoritative for full rebuilds.
import importlib.util
stone_spec = importlib.util.spec_from_file_location('author_bank_stones', ROOT/'tools/author_bank_stones.py')
stone_module = importlib.util.module_from_spec(stone_spec)
stone_spec.loader.exec_module(stone_module)
stone_report = stone_module.build_bank_stones()
report.append(dict(asset='bank_stones', vertices=stone_report['vertices']))
(OUT/'model-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ECOLOGY_MODELS_OK',json.dumps(report))
