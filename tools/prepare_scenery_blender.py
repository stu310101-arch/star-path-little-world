"""Task-owned Blender process: stylize CC0 marine models and author sakura variants."""
import bpy, math, json, random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/scenery'
MASTERS = ROOT / 'art/WorldScenery'
OUT.mkdir(parents=True, exist_ok=True)
MASTERS.mkdir(parents=True, exist_ok=True)
report = []

def clear():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

def material(name, rgb):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*rgb, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*rgb, 1)
    bs.inputs['Roughness'].default_value = 0.88
    bs.inputs['Specular IOR Level'].default_value = 0.18
    return m

def ico(name, pos, scale, mat, subdivisions=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdivisions, radius=1, location=pos)
    o = bpy.context.object; o.name = 'GEO-' + name; o.scale = scale
    o.data.materials.append(mat)
    return o

def segment(name, a, b, radius, mat, tip=None):
    a,b = Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=7, radius1=radius, radius2=radius if tip is None else tip, depth=(b-a).length, location=(a+b)/2)
    o=bpy.context.object; o.name='GEO-'+name
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    o.data.materials.append(mat)
    return o

def finish(name, source):
    meshes = [o for o in bpy.context.scene.objects if o.type=='MESH']
    # Merge static parts into one mesh with material slots, reducing scene overhead.
    bpy.ops.object.select_all(action='DESELECT')
    for o in meshes: o.select_set(True)
    bpy.context.view_layer.objects.active=meshes[0]
    bpy.ops.object.join()
    o=bpy.context.object; o.name='GEO-'+name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTERS/(name+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')), export_format='GLB', use_selection=True, export_animations=False)
    report.append({'name':name,'source':source,'vertices':len(o.data.vertices),'dimensions':list(o.dimensions)})

def mesh_bounds():
    points=[o.matrix_world @ Vector(c) for o in bpy.context.scene.objects if o.type=='MESH' for c in o.bound_box]
    return Vector(tuple(min(p[i] for p in points) for i in range(3))),Vector(tuple(max(p[i] for p in points) for i in range(3)))

def normalize_import(length, submerged=0.0):
    bpy.context.view_layer.update()
    lo,hi=mesh_bounds()
    scale=length/max(hi.x-lo.x,hi.y-lo.y)
    centre=Vector(((lo.x+hi.x)/2,(lo.y+hi.y)/2,lo.z))
    # Imported static boats/OBJ meshes: bake world transforms before normalization.
    for o in list(bpy.context.scene.objects):
        if o.type!='MESH':continue
        world=o.matrix_world.copy()
        o.parent=None; o.matrix_world.identity()
        for v in o.data.vertices: v.co=(world @ v.co-centre)*scale-Vector((0,0,submerged))
    return lo,hi

for variant in range(3):
    clear(); rng=random.Random(640+variant)
    bark=material('Sakura warm bark',(0.24,0.15,0.13))
    pinks=[material('Petals rose',(0.32,0.025,0.075)),material('Petals blush',(0.50,0.08,0.17)),material('Petals cream pink',(0.72,0.18,0.30))]
    height=3.1+variant*0.28
    segment('Trunk',(0,0,0),(0.14,-0.06,height*0.65),0.15,bark,0.08)
    for i in range(7):
        angle=i*math.tau/7+variant*0.7
        reach=0.8+rng.random()*0.6
        end=(math.cos(angle)*reach, math.sin(angle)*reach, height*(0.72+rng.random()*0.2))
        segment('Branch',(0.08,0,height*0.43),end,0.075,bark,0.025)
        ico('Blossom cluster',end,(0.9+rng.random()*0.2,0.8+rng.random()*0.25,0.5+rng.random()*0.25),pinks[(i+variant)%3],2)
    ico('Crown',(0,0,height),(1.15,1.05,0.6),pinks[2],2)
    finish('sakura_'+str(variant),'Original task-authored Blender geometry')

fish_root=ROOT/'assets/source/marine/fish/Animated Fish Pack by @Quaternius/OBJ'
for index in [1,2]:
    clear()
    bpy.ops.wm.obj_import(filepath=str(fish_root/('Fish'+str(index)+'.obj')))
    print('SOURCE_FISH',index,[(o.name,tuple(o.dimensions)) for o in bpy.context.scene.objects])
    normalize_import(0.85)
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        for m in o.data.materials:
            if m and m.use_nodes:
                bs=m.node_tree.nodes.get('Principled BSDF')
                if bs:
                    bs.inputs['Roughness'].default_value=0.75
                    bs.inputs['Specular IOR Level'].default_value=0.15
    finish('fish_'+str(index),'Quaternius Animated Fish CC0; normalized static mesh; world supplies leap motion')

boat_root=ROOT/'assets/source/marine/watercraft/Models/GLB format'
for source,name,length in [('boat-tug-a','tugboat',4.3),('ship-ocean-liner-small','liner',7.8),('boat-row-large','fishing_boat',3.8)]:
    clear()
    bpy.ops.import_scene.gltf(filepath=str(boat_root/(source+'.glb')))
    print('SOURCE_BOAT',source,[(o.name,tuple(o.dimensions)) for o in bpy.context.scene.objects if o.type=='MESH'])
    normalize_import(length,0.18)
    for o in bpy.context.scene.objects:
        if o.type!='MESH':continue
        for m in o.data.materials:
            if m and m.use_nodes:
                bs=m.node_tree.nodes.get('Principled BSDF')
                if bs:
                    bs.inputs['Roughness'].default_value=0.88
                    bs.inputs['Specular IOR Level'].default_value=0.12
                    # Keep the supplied palette texture, reduce its saturation with material tint.
                    bs.inputs['Base Color'].default_value=(0.8,0.88,0.84,1)
    if name=='fishing_boat':
        skin=material('Angler skin',(0.69,0.42,0.27)); shirt=material('Angler cream',(0.75,0.69,0.51))
        navy=material('Angler trousers',(0.13,0.26,0.31)); hat=material('Angler coral hat',(0.64,0.25,0.22))
        rod=material('Fishing pole',(0.21,0.17,0.13)); line=material('Fishing line',(0.63,0.71,0.68))
        ico('Seated torso',(0,0,0.65),(0.22,0.16,0.3),shirt,2)
        ico('Head',(0,-0.01,1.07),(0.16,0.15,0.18),skin,2)
        segment('Hat brim',(0,0,1.18),(0,0,1.22),0.26,hat)
        segment('Hat crown',(0,0,1.2),(0,0,1.37),0.17,hat,0.14)
        for x in [-0.12,0.12]:
            segment('Thigh',(x,0,0.5),(x,-0.35,0.46),0.075,navy)
            segment('Shin',(x,-0.35,0.46),(x,-0.35,0.18),0.065,navy)
            segment('Arm',(x*1.5,0,0.82),(x,-0.38,0.71),0.055,shirt)
        segment('Fishing rod',(0,-0.35,0.72),(0,-1.65,1.8),0.018,rod,0.008)
        segment('Fishing line',(0,-1.65,1.8),(0,-2.5,-0.12),0.004,line)
    finish(name,'Kenney Watercraft Kit 2.1 CC0; normalized and styled in Blender'+('; custom seated angler and rod' if name=='fishing_boat' else ''))

(OUT/'derivation.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('SCENERY_EXPORT_OK',json.dumps(report))
