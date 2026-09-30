"""Build an independent, editable Blender training-room study.

Run in a fresh Blender process with --factory-startup --python this_file.
Never opens or modifies an existing project. All dimensions are metres.
"""
from pathlib import Path
import bpy, math, sys, json, random
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art' / 'TrainingRoom'
sys.path.insert(0, str(ROOT / 'tools'))
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
BLOCK = '--blockout' in ARGS
assert not bpy.data.filepath, 'This builder requires a fresh factory-startup process.'
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
scene = bpy.context.scene
scene.name = 'WORDKING | Training Room'
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene['brief'] = 'Reference-based training room; exactly one WordKing device; empty Genshin display; entry teleport.'
scene['delivery_scope'] = 'Blender spatial / visual design. No gameplay, Godot import, or character models.'
scene['room_dimensions_m'] = [20, 18, 3.4]
scene['layout_revision'] = 'spacious_v02 - furniture kept at original human scale'

def col(name):
    c = bpy.data.collections.new(name); scene.collection.children.link(c); return c
C = {k:col(n) for k,n in {
    'arch':'01 | Architecture', 'trim':'02 | Blue lighting strips',
    'curtain':'03 | Pleated curtain wall', 'gaming':'04 | Three gaming desks',
    'lounge':'05 | Leather lounge', 'display':'06 | Genshin display - EMPTY',
    'device':'07 | WordKing - SINGLE DEVICE', 'portal':'08 | Entry teleport',
    'plants':'09 | Plants and decor', 'lights':'10 | Lighting',
    'cameras':'11 | Cameras', 'refs':'12 | References and scale guides',
    'enclosure':'13 | Roof and front wall - toggle for enclosed room'
}.items()}
C['enclosure'].hide_render=True; C['enclosure'].hide_viewport=True
C['refs'].hide_render=True; C['refs'].hide_viewport=True

def mat(name, rgb, rough=.4, metal=0, emission=0, alpha=1):
    m=bpy.data.materials.new('MAT | '+name); m.diffuse_color=(*rgb,alpha); m.use_nodes=True
    b=m.node_tree.nodes.get('Principled BSDF')
    for k,v in {'Base Color':(*rgb,1),'Roughness':rough,'Metallic':metal,'Alpha':alpha}.items(): b.inputs[k].default_value=v
    if emission:
        b.inputs['Emission Color'].default_value=(*rgb,1); b.inputs['Emission Strength'].default_value=emission
    if alpha<1: m.surface_render_method='DITHERED'
    return m
M={
 'black':mat('Obsidian lacquer',(.009,.014,.023),.27),
 'metal':mat('Graphite brushed aluminium',(.08,.105,.14),.3,1),
 'chrome':mat('Machined silver',(.43,.51,.62),.24,1),
 'blue':mat('Electric blue light',(.006,.095,1),.25,emission=4.5),
 'cyan':mat('Cyan optical light',(.025,.47,1),.25,emission=3.8),
 'white':mat('Pearl white LED',(.55,.78,1),.3,emission=2.2),
 'grid':mat('Holographic grid',(.008,.16,.75),.4,emission=.8),
 'hologram':mat('Transparent holographic blue',(.012,.09,.28),.4,emission=.65,alpha=.14),
 'leather':mat('Soft black leather',(.019,.024,.032),.38),
 'rug':mat('Charcoal woven rug',(.018,.023,.031),.94),
 'velvet':mat('Midnight curtain velvet',(.004,.009,.022),.91),
 'green':mat('Dark olive leaves',(.035,.095,.041),.43),
 'green2':mat('Leaf highlights',(.075,.16,.056),.48),
 'soil':mat('Pot soil',(.015,.011,.008),.95),
 'glass':mat('Display glass',(.23,.45,.6),.12,alpha=.075),
 'warm':mat('Neutral warm lamp',(.94,.8,.58),.4,emission=3),
 'screen':mat('Screen navy',(.004,.018,.045),.3,emission=.3),
 'seam':mat('Seam stitching',(.07,.09,.13),.7),
 'marble':mat('Midnight veined marble',(.015,.025,.037),.22),
 'gold':mat('Portal signature gold',(.48,.29,.08),.32,1),
}

def noise_bump(m, scale, strength, distance):
    ns=m.node_tree.nodes; ls=m.node_tree.links; b=ns.get('Principled BSDF')
    n=ns.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value=scale; n.inputs['Detail'].default_value=2
    bump=ns.new('ShaderNodeBump'); bump.inputs['Strength'].default_value=strength; bump.inputs['Distance'].default_value=distance
    ls.new(n.outputs['Fac'],bump.inputs['Height']); ls.new(bump.outputs['Normal'],b.inputs['Normal'])
noise_bump(M['leather'],850,.20,.0018); noise_bump(M['rug'],170,.35,.012)
ln=M['leather'].node_tree.nodes; ll=M['leather'].node_tree.links
leather_variation=ln.new('ShaderNodeTexNoise');leather_variation.inputs['Scale'].default_value=5.5;leather_variation.inputs['Detail'].default_value=3
leather_roughness=ln.new('ShaderNodeMapRange');leather_roughness.inputs['From Min'].default_value=.15;leather_roughness.inputs['From Max'].default_value=.85
leather_roughness.inputs['To Min'].default_value=.29;leather_roughness.inputs['To Max'].default_value=.43
ll.new(leather_variation.outputs['Fac'],leather_roughness.inputs['Value']);ll.new(leather_roughness.outputs['Result'],ln.get('Principled BSDF').inputs['Roughness'])
noise_bump(M['velvet'],125,.11,.006)
M['leather'].node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.25
glass_bsdf=M['glass'].node_tree.nodes.get('Principled BSDF')
glass_bsdf.inputs['Base Color'].default_value=(.92,.96,1,1)
glass_bsdf.inputs['Alpha'].default_value=1
glass_bsdf.inputs['Transmission Weight'].default_value=1
glass_bsdf.inputs['IOR'].default_value=1.45
glass_bsdf.inputs['Roughness'].default_value=.035
M['velvet'].node_tree.nodes.get('Principled BSDF').inputs['Sheen Weight'].default_value=.06
M['velvet'].node_tree.nodes.get('Principled BSDF').inputs['Specular IOR Level'].default_value=.16
ns=M['marble'].node_tree.nodes; ls=M['marble'].node_tree.links; bs=ns.get('Principled BSDF')
tc=ns.new('ShaderNodeTexCoord'); n=ns.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value=.65; n.inputs['Detail'].default_value=3
ls.new(tc.outputs['Object'],n.inputs['Vector'])
mix=ns.new('ShaderNodeVectorMath'); mix.operation='ADD'; ls.new(tc.outputs['Object'],mix.inputs[0]); ls.new(n.outputs['Color'],mix.inputs[1])
v=ns.new('ShaderNodeTexVoronoi'); v.feature='DISTANCE_TO_EDGE'; v.inputs['Scale'].default_value=1.9; ls.new(mix.outputs[0],v.inputs['Vector'])
r=ns.new('ShaderNodeValToRGB'); r.color_ramp.elements[0].position=.001; r.color_ramp.elements[0].color=(.030,.041,.057,1)
r.color_ramp.elements[1].position=.008; r.color_ramp.elements[1].color=(.008,.013,.020,1)
ls.new(v.outputs['Distance'],r.inputs[0]); ls.new(r.outputs['Color'],bs.inputs['Base Color'])
bs.inputs['Coat Weight'].default_value=.28

FONT=bpy.data.fonts.load('C:/Windows/Fonts/msjhbd.ttc')
CACHE={}
def mesh(name, verts, faces, material, collection):
    d=bpy.data.meshes.new(name); d.from_pydata(verts,[],faces); d.update()
    o=bpy.data.objects.new(name,d); collection.objects.link(o)
    if material: d.materials.append(material)
    return o
def box(name, loc, dims, material, collection, bevel=.025):
    key=(tuple(dims),material.name,bevel)
    if key in CACHE:
        o=bpy.data.objects.new(name,CACHE[key]); collection.objects.link(o)
    else:
        a,b,c=[x/2 for x in dims]
        vs=[(-a,-b,-c),(a,-b,-c),(a,b,-c),(-a,b,-c),(-a,-b,c),(a,-b,c),(a,b,c),(-a,b,c)]
        fs=[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
        o=mesh(name,vs,fs,material,collection); CACHE[key]=o.data
    o.location=loc
    if bevel:
        m=o.modifiers.new('Soft edge highlights','BEVEL'); m.width=bevel; m.segments=3
        m=o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o
def cyl(name, loc, radius, depth, material, collection, vertices=48, radius2=None):
    bpy.ops.mesh.primitive_cone_add(vertices=vertices,radius1=radius,radius2=radius if radius2 is None else radius2,depth=depth,location=loc)
    o=bpy.context.object; o.name=name
    for c in list(o.users_collection): c.objects.unlink(o)
    collection.objects.link(o); o.data.materials.append(material)
    for p in o.data.polygons: p.use_smooth=len(p.vertices)==4
    be=o.modifiers.new('Rim bevel','BEVEL'); be.width=.018; be.segments=2
    return o
def lines(name,paths,material,collection,radius=.012,closed=False):
    d=bpy.data.curves.new(name,'CURVE'); d.dimensions='3D'; d.resolution_u=1; d.bevel_depth=radius; d.bevel_resolution=1
    for path in paths:
        s=d.splines.new('POLY'); s.points.add(len(path)-1)
        for p,co in zip(s.points,path): p.co=(*co,1)
        s.use_cyclic_u=closed
    o=bpy.data.objects.new(name,d); collection.objects.link(o); d.materials.append(material); return o
def ring(name,center,radius,material,collection,thick=.012,steps=96):
    x,y,z=center
    return lines(name,[[(x+radius*math.cos(i*math.tau/steps),y+radius*math.sin(i*math.tau/steps),z) for i in range(steps)]],material,collection,thick,True)
def label(name,body,loc,size,material,collection,rot=(math.pi/2,0,0),align='CENTER'):
    d=bpy.data.curves.new(name,'FONT'); d.body=body; d.font=FONT; d.size=size; d.align_x=align; d.align_y='CENTER'; d.extrude=.0015; d.resolution_u=5
    o=bpy.data.objects.new(name,d); collection.objects.link(o); o.location=loc; o.rotation_euler=rot; d.materials.append(material); return o
def light(name,loc,target,power,color,size=3):
    d=bpy.data.lights.new(name,'AREA'); d.energy=power; d.color=color; d.shape='DISK'; d.size=size
    o=bpy.data.objects.new(name,d); C['lights'].objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); return o
def camera(name,loc,target,ortho=None,lens=32):
    d=bpy.data.cameras.new(name); o=bpy.data.objects.new(name,d); C['cameras'].objects.link(o); o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler(); d.lens=lens
    if ortho: d.type='ORTHO'; d.ortho_scale=ortho
    return o

# Architectural shell. Front is cut away for the reference-view presentation.
box('ARCH | structural plinth',(0,0,-.21),(20.5,18.5,.4),M['black'],C['arch'],.08)
for x in range(10):
    for y in range(9):
        box(f'FLOOR | marble tile {x+1}.{y+1}',(-9+x*2,-8+y*2,.005),(1.993,1.993,.065),M['marble'],C['arch'],.007)
box('ARCH | rear wall',(0,9.12,1.7),(20.5,.28,3.4),M['black'],C['arch'])
for side in [-1,1]:
    box('ARCH | side wall',(side*10.12,0,1.7),(.28,18.2,3.4),M['black'],C['arch'])
    for y in [-7.5,-5,-2.5,0,2.5,5,7.5]:
        box('ARCH | recessed wall panel',(side*9.962,y,1.75),(.034,2.34,2.65),M['metal'],C['arch'],.014)
    box('TRIM | perimeter LED',(side*9.94,0,.10),(.028,17.95,.035),M['blue'],C['trim'],.005)
    box('TRIM | upper wall LED',(side*9.94,0,3.15),(.03,17.95,.025),M['blue'],C['trim'],.005)
for x in [-5.82,5.82]:
    box('ARCH | front cutaway curb',(x,-9.07,.26),(8.6,.27,.52),M['black'],C['arch'])
    box('ARCH | full front wall',(x,-9.07,1.95),(8.6,.27,2.9),M['black'],C['enclosure'])
box('ARCH | optional ceiling',(0,0,3.49),(20.5,18.5,.18),M['black'],C['enclosure'])
for x in [-6,6]:
    box('CEILING | recessed channel',(x,0,3.36),(.20,14.1,.075),M['metal'],C['enclosure'],.016)
    box('CEILING | diffused linear light',(x,0,3.315),(.055,13.8,.014),M['white'],C['enclosure'],.005)
for x in [-6,0,6]:
    for y in [-4.5,4.5]:
        fixture=light('CEILING | soft interior fill',(x,y,3.22),(x,y,0),240,(.64,.77,1),3)
        C['lights'].objects.unlink(fixture);C['enclosure'].objects.link(fixture)
box('ENTRY | approach platform',(0,-6.95,-.09),(3.25,2.1,.18),M['marble'],C['portal'],.06)

# Curtain wall, hand authored folds rather than repeated rods.
verts=[]; faces=[]; steps=384; curtain_rows=24
for i in range(steps+1):
    x=-6.65+13.3*i/steps
    for j in range(curtain_rows+1):
        t=j/curtain_rows
        phase=i/steps*math.tau*48+.11*math.sin(t*math.pi*1.5+i*.05)*(1-t)
        y=8.8+(.075+.045*(1-t))*math.cos(phase)+.010*math.sin(t*math.pi*3+i*.08)
        z=.19+2.99*t+.018*(1-t)**4*math.sin(i*.12)
        verts.append((x,y,z))
for i in range(steps):
    for j in range(curtain_rows):
        a=i*(curtain_rows+1)+j;faces.append((a,a+1,a+curtain_rows+2,a+curtain_rows+1))
o=mesh('CURTAIN | continuous velvet pleats',verts,faces,M['velvet'],C['curtain'])
for p in o.data.polygons:p.use_smooth=True
box('CURTAIN | track pelmet',(0,8.65,3.24),(13.6,.43,.2),M['metal'],C['curtain'])
for z in [.13,3.12]:box('CURTAIN | blue cove',(0,8.64,z),(13.3,.055,.035),M['blue'],C['trim'],.008)
label('SIGN | title','單字王  /  練功區',(0,8.58,2.55),.52,M['white'],C['curtain'])
label('SIGN | subtitle','W O R D K I N G   ·   T R A I N I N G   L O U N G E',(0,8.56,2.03),.125,M['cyan'],C['curtain'])
for x in [-8,8]:
    box('ARCH | rear feature tower',(x,8.88,1.7),(1.55,.4,3.4),M['metal'],C['arch'])
    box('TRIM | tower light',(x-.68,8.65,1.7),(.03,.035,3.24),M['blue'],C['trim'])

# Center remains an open circle with only one actual device.
cyl('CENTER | flush circular stone inset',(.65,.8,.047),2.3,.024,M['black'],C['arch'],96)
for rad in [2.16,2.29]: ring('CENTER | concentric floor light',(.65,.8,.069),rad,M['blue'],C['trim'],.016)
for i in range(24):
    a=math.tau*i/24
    lines('CENTER | radial calibration marker',[[ (.65+2.06*math.cos(a),.8+2.06*math.sin(a),.071),(.65+2.13*math.cos(a),.8+2.13*math.sin(a),.071)]],M['cyan'],C['trim'],.008)

if BLOCK:
    cyl('BLOCK | single projector',(.65,.8,.3),.9,.5,M['metal'],C['device'])
    box('BLOCK | hologram',(.65,.8,1.9),(2.2,.03,1.25),M['cyan'],C['device'])
    box('BLOCK | gaming desks',(-5.7,2,.42),(1,5,.8),M['metal'],C['gaming'])
    box('BLOCK | lounge',(-4.5,-3.4,.45),(4.4,3.1,.9),M['leather'],C['lounge'])
    box('BLOCK | display',(6.15,1.7,1.45),(.85,5.4,2.9),M['metal'],C['display'])
else:
    from training_room_device import build_device
    from training_room_lounge import build_lounge
    from training_room_upholstery import refine_upholstery
    build_device(C['device'],M,FONT).location.z=.034
    build_lounge(C['lounge'],M)
    refine_upholstery(C['lounge'],M)
    for lounge_object in list(C['lounge'].objects):
        lounge_object.location.z+=.035
        lounge_object.location.x-=2.25
        lounge_object.location.y-=2.6
        if lounge_object.name.startswith('LOUNGE_Side_table'):
            lounge_object.location.x+=1.3
            lounge_object.location.y+=.05

    # Three distinct workstations along one real continuous desk.
    box('GAMING | carpet',(-5.15,2,.067),(2.7,5.5,.05),M['rug'],C['gaming'],.035)
    box('GAMING | continuous desk',(-6,2,.79),(1.08,5.28,.10),M['black'],C['gaming'],.04)
    box('GAMING | blue desk edge',(-5.44,2,.775),(.02,5.24,.022),M['blue'],C['gaming'],.006)
    for y in [-.45,4.45]:box('GAMING | desk leg',(-6,y,.4),(.82,.10,.72),M['metal'],C['gaming'])
    for idx,y in enumerate([.35,2,3.65]):
        # Screens face the aisle (+X), with slight toe-in of satellite panels.
        for j,dy in enumerate([-.43,0,.43]):
            mon=box(f'GAMING {idx+1} | screen frame {j}',(-6.28,y+dy,1.23),(.062,.425,.49),M['black'],C['gaming'],.016)
            box(f'GAMING {idx+1} | luminous screen {j}',(-6.241,y+dy,1.23),(.01,.387,.44),M['screen'],C['gaming'],.006)
            paths=[]
            for k in range(4):paths.append([(-6.229,y+dy-.16,1.08+k*.085),(-6.229,y+dy+.12*(1-k*.1),1.08+k*.085)])
            lines('GAMING | blue interface lines',paths,M['cyan'],C['gaming'],.006)
        box('GAMING | monitor neck',(-6.25,y,.965),(.045,.065,.28),M['metal'],C['gaming'])
        box('GAMING | monitor foot',(-6.19,y,.857),(.24,.34,.025),M['metal'],C['gaming'])
        box('GAMING | keyboard',(-5.77,y,.86),(.2,.62,.035),M['black'],C['gaming'],.012)
        keypaths=[]
        for row in range(4):
            for k in range(12):keypaths.append([(-5.855+row*.045,y-.265+k*.047,.88),(-5.83+row*.045,y-.265+k*.047,.88)])
        lines('GAMING | RGB keys',keypaths,M['cyan'] if idx!=1 else M['blue'],C['gaming'],.007)
        box('GAMING | mouse',(-5.76,y-.49,.887),(.13,.085,.044),M['black'],C['gaming'],.027)
        # Under-desk tower with twin fan rings.
        box('GAMING | PC tower',(-6.05,y+.56,.36),(.46,.26,.61),M['black'],C['gaming'],.033)
        for z in [.25,.48]:
            rr=ring('GAMING | PC intake light',(-5.81,y+.56,z),.075,M['blue'],C['gaming'],.008,40)
            # ring generated XY; rotate plane to YZ around its own coordinates via vertex transform.
            for s in rr.data.splines:
                for p in s.points:
                    a,b,c,_=p.co; p.co=(-5.809,b,z+(a+5.81),1)
        # Human-scale upholstered racing chair, facing wall.
        cyl('GAMING | chair pedestal',(-4.91,y,.28),.06,.40,M['chrome'],C['gaming'],24)
        box('GAMING | chair cushion',(-4.97,y,.49),(.61,.61,.15),M['leather'],C['gaming'],.072)
        back=box('GAMING | chair back',(-4.68,y,.94),(.17,.55,.87),M['leather'],C['gaming'],.065); back.rotation_euler[1]=-.10
        box('GAMING | headrest',(-4.65,y,1.42),(.17,.39,.19),M['leather'],C['gaming'],.06)
        for side in [-1,1]:
            box('GAMING | chair bolster',(-4.77,y+side*.23,.98),(.20,.10,.74),M['black'],C['gaming'],.047)
            box('GAMING | arm pad',(-4.97,y+side*.36,.74),(.42,.085,.07),M['leather'],C['gaming'],.025)
            box('GAMING | arm support',(-4.85,y+side*.34,.61),(.05,.05,.24),M['metal'],C['gaming'])
        for a in range(5):
            t=a*math.tau/5; end=(-4.91+.36*math.cos(t),y+.36*math.sin(t),.105)
            lines('GAMING | chair star base',[[(-4.91,y,.19),end]],M['metal'],C['gaming'],.033)
            cyl('GAMING | chair castor',(end[0],end[1],.07),.052,.055,M['black'],C['gaming'],16)
    label('GAMING | wall sign','GAME ON',(-6.916,2,2.35),.30,M['cyan'],C['gaming'],(math.pi/2,0,math.pi/2))
    from training_room_gaming import refine_gaming
    refine_gaming(C['gaming'],M)

    # Empty glazed display: six generous compartments, no proxy figures.
    # Face is -X; caption, shelves and blue frame make the future purpose legible.
    box('DISPLAY | recessed floor plinth',(6.16,1.8,.09),(.90,5.28,.15),M['black'],C['display'],.035)
    box('DISPLAY | brushed plinth reveal',(5.68,1.8,.13),(.026,5.25,.035),M['chrome'],C['display'],.008)
    box('DISPLAY | full back',(6.57,1.8,1.6),(.15,5.35,2.92),M['black'],C['display'])
    for y in [-.89,.9,2.7,4.49]:
        box('DISPLAY | vertical mullion',(6.15,y,1.6),(.95,.065,2.92),M['metal'],C['display'])
        box('DISPLAY | blue mullion',(5.65,y,1.6),(.025,.032,2.78),M['blue'],C['display'],.006)
    for z in [.18,1.57,2.96]:
        box('DISPLAY | substantial shelf',(6.1,1.8,z),(1.02,5.45,.085),M['metal'],C['display'])
        box('DISPLAY | front shelf light',(5.578,1.8,z),(.024,5.43,.028),M['blue'],C['display'],.006)
    for iy,y in enumerate([0,1.8,3.6]):
        for iz,z in enumerate([.27,1.66]):
            plinth=cyl(f'DISPLAY | EMPTY pedestal {iy+1}.{iz+1}',(6.02,y,z),.36,.1,M['black'],C['display'],48)
            cyl('DISPLAY | recessed velvet pad',(6.02,y,z+.053),.30,.010,M['velvet'],C['display'],64)
            ring('DISPLAY | machined pedestal lip',(6.02,y,z+.042),.352,M['chrome'],C['display'],.007,64)
            ring('DISPLAY | pedestal rim',(6.02,y,z+.056),.33,M['cyan'],C['display'],.008,48)
            slot=bpy.data.objects.new(f'SOCKET | Genshin character {iy+1}.{iz+1} - empty',None); C['display'].objects.link(slot); slot.location=(6.02,y,z+.055); slot.empty_display_size=.18; slot['intentionally_empty']=True
            # Clear separate door with slim handle, no occluding placeholders.
            box('DISPLAY | glass door',(5.605,y,z+.63),(.014,1.71,1.28),M['glass'],C['display'],.003)
            lines('DISPLAY | formed glass-door handle',[[ (5.56,y-.70,z+.53),(5.50,y-.70,z+.55),(5.495,y-.70,z+.72),(5.56,y-.70,z+.74)]],M['chrome'],C['display'],.014)
            for zz in [z+.17,z+1.1]:
                box('DISPLAY | door hinge leaf',(5.605,y+.77,zz),(.034,.065,.10),M['chrome'],C['display'],.006)
                cyl('DISPLAY | cylindrical hinge',(5.60,y+.795,zz),.025,.085,M['metal'],C['display'],20)
            # Real thin glazing is framed by a satin metal edge and an interior light channel.
            lines('DISPLAY | glass edge frame',[[ (5.591,y-.855,z-.01),(5.591,y+.855,z-.01),(5.591,y+.855,z+1.27),(5.591,y-.855,z+1.27)]],M['metal'],C['display'],.010,True)
            box('DISPLAY | inset ceiling light',(6.22,y,z+1.27),(.045,1.45,.017),M['white'],C['display'],.006)
    box('DISPLAY | canopy',(6.1,1.8,3.18),(1.1,5.53,.35),M['black'],C['display'],.033)
    label('DISPLAY | Genshin brand','GENSHIN IMPACT',(5.526,1.8,3.19),.24,M['white'],C['display'],(math.pi/2,0,-math.pi/2))
    label('DISPLAY | reserve caption','原神角色展示區',(5.53,1.8,2.965),.13,M['cyan'],C['display'],(math.pi/2,0,-math.pi/2))

    # Both reference zones angle gently toward the central entrance.
    bpy.context.view_layer.update()
    for key,old,new,degrees in [('display',(6.1,1.8,0),(8.05,3.6,0),18),('gaming',(-5.7,2,0),(-7.95,3.6,0),-10)]:
        transform=Matrix.Translation(Vector(new)) @ Matrix.Rotation(math.radians(degrees),4,'Z') @ Matrix.Translation(-Vector(old))
        for item in C[key].objects:
            item.matrix_world=transform @ item.matrix_world
    gaming_sign=bpy.data.objects.get('GAMING | wall sign')
    gaming_sign.location=(-9.916,3.6,2.35)
    gaming_sign.rotation_euler=(math.pi/2,0,math.pi/2)

# Portal frame reproduces the established chamfered silhouette, with a ground pad.
from build_void_portal import _chamfered_outline, _ring_mesh_data
inner=_chamfered_outline(1.22,.07,3.27,.23)
outer=_chamfered_outline(1.48,-.025,3.53,.28)
vs,fs=_ring_mesh_data(inner,outer,-6.27,-5.89)
o=mesh('PORTAL | chamfered obsidian open doorway',vs,fs,M['metal'],C['portal'])
be=o.modifiers.new('Machined frame bevel','BEVEL');be.width=.035;be.segments=3
for y in [-6.29,-5.88]:
    lines('PORTAL | blue inner border',[[(x,y,z) for x,z in inner]],M['cyan'],C['portal'],.026,True)
outerline=_chamfered_outline(1.38,.025,3.43,.26)
lines('PORTAL | fine signature inlay',[[(x,-6.295,z) for x,z in outerline]],M['gold'],C['portal'],.012,True)
for x in [-1.37,1.37]:
    for z in [.66,2.60]:
        box('PORTAL | inset machined service plate',(x,-6.31,z),(.12,.034,.42),M['black'],C['portal'],.018)
        for zz in [z-.15,z+.15]:
            screw=cyl('PORTAL | inset hex fastener',(x,-6.338,zz),.016,.012,M['chrome'],C['portal'],6)
            screw.rotation_euler.x=math.pi/2
cyl('PORTAL | arrival pad',(0,-5.48,.067),1.13,.075,M['black'],C['portal'],96)
for r0 in [.86,1.035]:ring('PORTAL | arrival ring',(0,-5.48,.111),r0,M['cyan'],C['portal'],.014)
label('PORTAL | entry caption','傳送入口',(0,-6.5,.022),.2,M['cyan'],C['portal'],(0,0,0))
for y in [-7.5,-7.1,-4.02]:
    lines('PORTAL | direction chevron',[[(-.16,y-.10,.044),(0,y+.05,.044),(.16,y-.10,.044)]],M['cyan'],C['portal'],.018)
# Sparse constellation strands communicate a teleport surface without blocking the opening.
paths=[]
for i in range(11):
    z=.55+i*.21; half=.88-.06*math.sin(i*.8)
    paths.append([(-half,-6.06,z),(0,-6.075,z+.04), (half,-6.06,z)])
lines('PORTAL | faint energy scanlines',paths,M['grid'],C['portal'],.004)
for portal_object in C['portal'].objects:
    portal_object.location.y-=3

def plant(name,x,y,height=1.55):
    c=C['plants']; cyl(name+' | tapered pot',(x,y,.22),.24,.40,M['black'],c,32,radius2=.32)
    ring(name+' | pot rim',(x,y,.43),.30,M['chrome'],c,.012,48)
    cyl(name+' | soil',(x,y,.42),.279,.018,M['soil'],c,32)
    paths=[]; leafvs=[]; leaffs=[]
    for k in range(9):
        a=k*2.399; z=.65+(k%4)*.20; reach=.38+(k%3)*.055
        top=Vector((x+math.cos(a)*reach,y+math.sin(a)*reach,height-.12*(k%3)))
        base=Vector((x,y,.43)); mid=Vector((x+math.cos(a)*reach*.3,y+math.sin(a)*reach*.3,z))
        paths.append([base,mid,top])
        for j in range(1,6):
            t=j/6; stem=mid.lerp(top,t)
            for s in [-1,1]:
                ang=a+s*1.02; end=stem+Vector((math.cos(ang)*.26,math.sin(ang)*.26,.06-(j*.016)))
                perp=Vector((-math.sin(ang),math.cos(ang),0));n=len(leafvs)
                for u in range(9):
                    t=u/8
                    spine=stem.lerp(end,t)+Vector((0,0,.023*math.sin(t*math.pi)-.025*t*t))
                    width=.036*math.sin(math.pi*t)**.72+.0004
                    for v in range(5):
                        cross=-1+v*.5
                        q=spine+perp*(cross*width)+Vector((0,0,-.011*cross*cross*math.sin(t*math.pi)))
                        leafvs.append(tuple(q))
                for u in range(8):
                    for v in range(4):
                        a=n+u*5+v;leaffs.append((a,a+1,a+6,a+5))
    lines(name+' | stems',paths,M['green'],c,.008)
    leaves=mesh(name+' | curved leaves',leafvs,leaffs,M['green2'],c)
    for polygon in leaves.data.polygons:polygon.use_smooth=True
if not BLOCK:
    for args in [('Rear left fern',-8.35,7.75,1.62),('Rear right fern',8.55,7.75,1.65),('Entry left plant',-2.5,-8.1,1.27),('Entry right plant',8.2,-7.75,1.42),('Lounge fern',-9.15,-8.15,1.45)]:plant(*args)
    plant('Coffee table miniature',-3.65,-2.68,.81)
    # Lift miniature off floor and scale to tabletop.
    for o in list(C['plants'].objects):
        if o.name.startswith('Coffee table miniature'):
            for v in o.data.vertices if o.type=='MESH' else []:
                if o.location.length<.01:v.co.x=-3.65+(v.co.x+3.65)*.45;v.co.y=-2.68+(v.co.y+2.68)*.45;v.co.z=.45+v.co.z*.40
            if o.location.length>.01:
                o.scale*=.45;o.location.x=-3.65+(o.location.x+3.65)*.45;o.location.y=-2.68+(o.location.y+2.68)*.45;o.location.z=.45+o.location.z*.4
            if o.type=='CURVE':
                for s in o.data.splines:
                    for p in s.points:p.co=(-3.65+(p.co.x+3.65)*.45,-2.68+(p.co.y+2.68)*.45,.45+p.co.z*.4,1)
            o.location.x-=2.25
            o.location.y-=2.6

# Practical fixtures plus modest soft boxes: controlled blue accents, readable dark surfaces.
for side in [-1,1]:
    for y in [-7,-2,3,7]:
        box('LIGHT | wall sconce housing',(side*9.87,y,2.62),(.12,.32,.13),M['black'],C['trim'])
        box('LIGHT | wall sconce LED',(side*9.79,y,2.58),(.05,.19,.035),M['warm'],C['trim'])
        light('LIGHT | sconce wash',(side*9.65,y,2.60),(side*8.5,y,.5),65,(.7,.82,1),.5)
light('LIGHT | broad neutral key',(1,-3,9),(0,0,0),1300,(.67,.77,1),10).data.specular_factor=.12
light('LIGHT | left softbox',(-7,-1,5),(-7,2,.6),650,(.56,.70,1),5).data.specular_factor=.35
light('LIGHT | leather texture softbox',(-6.5,-5.7,4.4),(-6.7,-5.6,.5),340,(.73,.82,1),3.5)
display_fill=light('LIGHT | display softbox',(6,3,5),(8,3,1.4),700,(.65,.80,1),4)
display_fill.data.specular_factor=.35
display_fill.visible_glossy=False
for x in [-5,-2.5,0,2.5,5]: light('LIGHT | curtain uplight',(x,8.35,.26),(x,8.8,2),100,(.015,.095,1),1.2)
light('LIGHT | projector spill',(.65,.8,1.05),(.65,.8,0),85,(.01,.18,1),1.3)
light('LIGHT | portal spill',(0,-8.9,2),(0,-8.1,.1),95,(.015,.25,1),1.8)
world=bpy.data.worlds.new('WORLD | deep navy studio');world.use_nodes=True
world.node_tree.nodes['Background'].inputs['Color'].default_value=(.015,.025,.055,1)
world.node_tree.nodes['Background'].inputs['Strength'].default_value=.12;scene.world=world

cams={
'overview':camera('CAM | 01 reference overview',(.6,-29,25),(0,-.2,1),25.5),
'interior':camera('CAM | 02 eye-level room',(-3.8,-6.6,1.72),(.7,2.6,1.52),lens=21),
'device':camera('CAM | 03 WordKing device',(3.8,-5.8,3.05),(.65,.8,1.30),lens=53),
'display':camera('CAM | 04 empty display',(2.7,-.6,2.6),(8.05,3.6,1.7),lens=36),
'sofa':camera('CAM | 05 upholstered leather sofa',(-1.0,.25,4.15),(-6.7,-5.7,.60),lens=47),
}
scene.camera=cams['overview']

# Reference images and a non-rendering human-size guide are packed into the project.
for file,name,x in [('room_reference.png','REFERENCE | supplied room',-11),('device_reference.png','REFERENCE | supplied device',11)]:
    o=bpy.data.objects.new(name,None);o.empty_display_type='IMAGE';o.data=bpy.data.images.load(str(OUT/'references'/file));o.empty_display_size=7;o.location=(x,0,2);C['refs'].objects.link(o)
box('SCALE GUIDE | human 1.75 m',(0,3.8,.875),(.42,.24,1.75),M['chrome'],C['refs'],.06)

scene.render.engine='CYCLES'
scene.cycles.device='CPU'
scene.cycles.samples=12 if BLOCK else 24
scene.cycles.use_denoising=True
scene.cycles.max_bounces=5
scene.cycles.diffuse_bounces=2
scene.cycles.glossy_bounces=3
scene.cycles.transmission_bounces=6
scene.cycles.transparent_max_bounces=6
scene.render.resolution_x=1440;scene.render.resolution_y=1080;scene.render.resolution_percentage=50 if BLOCK else 80
scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False
scene.render.threads_mode='FIXED';scene.render.threads=4
scene.render.compositor_device='CPU'
scene.eevee.taa_render_samples=16 if BLOCK else 32
scene.eevee.use_raytracing=False
scene.view_settings.view_transform='AgX';scene.view_settings.look='AgX - Medium High Contrast';scene.view_settings.exposure=-.30

# Blender 5.2 compositor API: keep glow separate and editable.
ng=bpy.data.node_groups.new('COMPOSITOR | restrained blue glow','CompositorNodeTree')
ng.interface.new_socket(name='Image',in_out='OUTPUT',socket_type='NodeSocketColor')
rl=ng.nodes.new('CompositorNodeRLayers');gl=ng.nodes.new('CompositorNodeGlare');gl.inputs['Type'].default_value='Fog Glow';gl.inputs['Quality'].default_value='Medium'
if 'Threshold' in gl.inputs:gl.inputs['Threshold'].default_value=1.4
if 'Strength' in gl.inputs:gl.inputs['Strength'].default_value=.28
go=ng.nodes.new('NodeGroupOutput');ng.links.new(rl.outputs['Image'],gl.inputs['Image']);ng.links.new(gl.outputs['Image'],go.inputs['Image'])
scene.compositing_node_group=ng
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_perspective='CAMERA';area.spaces.active.shading.type='SOLID';area.spaces.active.shading.color_type='MATERIAL'
            area.spaces.active.shading.use_scene_world=True;area.spaces.active.shading.use_scene_lights=True
            area.spaces.active.overlay.show_overlays=False

OUT.mkdir(parents=True,exist_ok=True)
if not BLOCK:
    for obj in scene.objects:
        if obj.type=='MESH' and any(m in [M['glass'],M['hologram']] for m in obj.data.materials):
            obj.display_type='WIRE'
    info=bpy.data.texts.new('READ ME | Training Room')
    info.write('單字王練功區 — Blender 空間設計\n\n20 × 18 m; 3.4 m interior height. Spacious layout revision: furniture and device retain original human scale.\nExactly one WordKing training device. Six empty Genshin display sockets; no characters supplied or built.\nThree gaming stations, black leather L lounge, pleated curtain wall, blue floor accents, chamfered entry portal and arrival pad.\nCameras 01 overview / 02 eye-level / 03 device / 04 display.\nCollection 13 contains removable front wall and roof; disabled for cutaway.\nAll mesh parts, bevel modifiers, materials, reference images, and generation scripts remain editable.\nThis is a Blender visual scene, not gameplay-ready export.\n')
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'WordKing_TrainingRoom.blend'))
    report={'scope':'Blender scene only','room_dimensions_m':[20,18,3.4],'layout_revision':'spacious_v02','previous_floor_area_m2':168,'floor_area_m2':360,'device_count':sum(o.get('device_type')=='wordking_training' for o in scene.objects),'character_models':0,'empty_display_sockets':len([o for o in scene.objects if o.get('intentionally_empty')]),'object_count':len(scene.objects),'mesh_source_triangles':sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in scene.objects if o.type=='MESH'),'collections':list(C.keys()),'camera_names':[o.name for o in cams.values()]}
    (OUT/'validation'/'scene_manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8');print('TRAINING_ROOM_REPORT',json.dumps(report))
if '--no-render' not in ARGS:
    scene.render.filepath=str(OUT/'previews'/('00_blockout.png' if BLOCK else '01_overview_draft.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDER_SAVED',scene.render.filepath)
