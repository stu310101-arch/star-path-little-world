"""Reproducible Blender authoring from the saved imagegen message-device concept.

Run Blender 5.2 --background --factory-startup --python this_file.py.
Godot Y-up metres are converted to Blender Z-up at the authoring boundary.
Editable components/modifiers stay in the .blend; evaluated export copies are
joined per spatial group, so runtime furniture does not incur per-piece draws.
"""
from __future__ import annotations
import bpy
import bmesh
import json
import math
import random
import os
from pathlib import Path
from contextlib import contextmanager
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "art/DiscussionGarden"
OUT = ROOT / "game/assets/discussion_garden"
TEX = ROOT / "game/assets/university_hall/textures"
ART.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.render.engine = "CYCLES"
scene.cycles.samples = 24
scene.cycles.use_denoising = True
scene.render.resolution_x = 1200
scene.render.resolution_y = 900
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.world.color = (.22, .26, .30)
MATS, GROUPS, COLLIDERS = {}, {}, []
FRAME = Matrix.Identity(4)
COL = None
rng = random.Random(20261023)
ASSET_AUDIT = {}

def gv(v):
    return Vector((v[0], -v[2], v[1]))

def material(key, color, rough=.6, metal=0, texture=None):
    mat = bpy.data.materials.new("MAT_Garden_" + key)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    if texture:
        for suffix, socket in [("base", "Base Color"), ("rough", "Roughness")]:
            source = bpy.data.images.load(str(TEX / f"{texture}_{suffix}.png"), check_existing=True)
            img = source.copy()
            img.name = "Garden_" + texture + "_" + suffix
            img.colorspace_settings.name = "sRGB" if suffix == "base" else "Non-Color"
            img.scale(512, 512)
            img.pack()
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = img
            mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs[socket])
    MATS[key] = mat
    return mat

def group(name):
    global COL
    COL = bpy.data.collections.new("COL_" + name)
    scene.collection.children.link(COL)
    GROUPS[name] = COL
    return COL

@contextmanager
def frame(position=(0, 0, 0), yaw=0, tilt=0):
    global FRAME
    old = FRAME
    FRAME = FRAME @ Matrix.Translation(gv(position)) @ Matrix.Rotation(yaw, 4, "Z") @ Matrix.Rotation(tilt, 4, "X")
    try:
        yield
    finally:
        FRAME = old

def mesh(name, points, faces, mat):
    data = bpy.data.meshes.new("MSH_" + name)
    data.from_pydata([gv(p) for p in points], [], faces)
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(data)
    bm.free()
    uv = data.uv_layers.new(name="UVMap")
    for poly in data.polygons:
        major = max(range(3), key=lambda i: abs(poly.normal[i]))
        axes = [i for i in range(3) if i != major]
        for loop in poly.loop_indices:
            co = data.vertices[data.loops[loop].vertex_index].co
            uv_scale=float(MATS[mat].get("uv_metres",1.2))
            uv.data[loop].uv = (co[axes[0]] / uv_scale, co[axes[1]] / uv_scale)
    ob = bpy.data.objects.new("SM_" + name, data)
    COL.objects.link(ob)
    data.materials.append(MATS[mat])
    ob.matrix_world = FRAME.copy()
    return ob

def bevel(ob, width=.012, segments=1):
    mod = ob.modifiers.new("Editable edge bevel", "BEVEL")
    mod.width = width
    mod.segments = segments
    mod = ob.modifiers.new("Weighted edge shading", "WEIGHTED_NORMAL")
    mod.keep_sharp = True
    return ob

def box(name, p, size, mat, edge=.012):
    x, y, z = (n / 2 for n in size)
    ob = mesh(name, [(-x,-y,-z),(x,-y,-z),(x,-y,z),(-x,-y,z),(-x,y,-z),(x,y,-z),(x,y,z),(-x,y,z)],
              [(0,1,2,3),(4,7,6,5),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    if edge:
        bevel(ob, min(edge, min(size)*.4))
    return ob

def round_box(name, p, size, radius, mat):
    # A soft rectangle in the horizontal XZ plane, extruded vertically.
    w, h, d = size
    points = []
    for yy in [-h/2, h/2]:
        for cx, cz, start in [(w/2-radius,d/2-radius,0),(w/2-radius,-d/2+radius,90),(-w/2+radius,-d/2+radius,180),(-w/2+radius,d/2-radius,270)]:
            for j in range(7):
                a = math.radians(start+j*15)
                points.append((cx+math.sin(a)*radius, yy, cz+math.cos(a)*radius))
    n = len(points)//2
    ob = mesh(name, points, [tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]+[(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    bevel(ob, min(.008,h*.2))
    return ob

def cylinder(name, p, radius, height, mat, top=None, segments=24):
    top = radius if top is None else top
    pts = [(math.cos(j*math.tau/segments)*r,y,math.sin(j*math.tau/segments)*r) for y,r in [(-height/2,radius),(height/2,top)] for j in range(segments)]
    ob = mesh(name, pts, [tuple(range(segments-1,-1,-1)),tuple(range(segments,2*segments))]+[(j,(j+1)%segments,(j+1)%segments+segments,j+segments) for j in range(segments)], mat)
    ob.matrix_world = FRAME @ Matrix.Translation(gv(p))
    for poly in ob.data.polygons:
        poly.use_smooth = len(poly.vertices)==4
    return ob

def rod(name, a, b, radius, mat="brass", segments=12):
    av, bv = gv(a), gv(b)
    ob = cylinder(name, (0,0,0), radius, (bv-av).length, mat, segments=segments)
    ob.matrix_world = FRAME @ Matrix.Translation((av+bv)/2) @ (bv-av).to_track_quat("Z","Y").to_matrix().to_4x4()
    return ob

def collision(name, p, size, yaw=0):
    world = FRAME @ gv(p)
    COLLIDERS.append({"name":name,"center":[world.x,world.z,-world.y],"size":list(size),"rotation_y": math.atan2(FRAME[1][0],FRAME[0][0])+yaw})

for key,color,rough,metal,tex in [
    ("walnut",(.24,.12,.055),.48,0,"walnut"), ("stone",(.77,.73,.64),.8,0,"stone"),
    ("paper",(.91,.86,.73),.88,0,"paper"), ("teal",(.065,.20,.18),.58,0,None),
    ("brass",(.52,.34,.12),.3,.72,None), ("soil",(.09,.07,.045),1,0,None),
    ("leaf",(.105,.205,.115),.86,0,None), ("leaf_light",(.22,.31,.17),.86,0,None),
    ("bark",(.20,.15,.10),.9,0,None), ("clay",(.48,.24,.16),.84,0,None),
    ("slate",(.21,.30,.36),.76,0,None), ("sage",(.32,.42,.32),.78,0,None),
    ("sand",(.43,.38,.27),.88,0,None), ("flower",(.62,.55,.31),.8,0,None),
]: material(key,color,rough,metal,tex)

group("MessageDevice")
round_box("Message_Base",(0,.07,0),(.62,.14,.48),.055,"stone")
round_box("Message_FootCollar",(0,.158,0),(.29,.035,.21),.018,"brass")
box("Message_Column",(0,.425,-.01),(.24,.51,.18),"walnut",.022)
for x in [-.10,.10]: box("Message_ColumnInlay",(x,.425,.084),(.005,.48,.003),"brass",0)
# Joinery braces are real wedges rather than decorative floating primitives.
for sign in [-1,1]:
    pts=[(sign*x,y,z) for x,y,z in [(.10,.50,-.06),(.10,.72,-.06),(.31,.72,-.06),(.10,.50,.07),(.10,.72,.07),(.31,.72,.07)]]
    bevel(mesh("Message_Corbel",pts,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)],"walnut"),.008)
with frame((0,1.025,-.015),tilt=math.radians(-15)):
    box("Message_Backing",(0,0,0),(.78,.86,.09),"walnut",.024)
    box("Message_Recess",(0,0,.049),(.704,.775,.012),"teal",.009)
    box("Message_BrassBorder",(0,.002,.058),(.630,.704,.009),"brass",.006)
    box("Message_Paper",(0,.002,.065),(.616,.690,.009),"paper",.003)
    for x in [-.37,.37]: box("Message_SideFrame",(x,0,.064),(.045,.86,.055),"walnut",.012)
    for y in [-.408,.408]: box("Message_CrossFrame",(0,y,.064),(.73,.044,.055),"walnut",.012)
    box("Message_HandLedge",(0,-.405,.105),(.81,.055,.145),"walnut",.015)
    box("Message_LedgeReveal",(0,-.38,.167),(.74,.008,.006),"brass",.002)
    rod("Message_Lamp",(-.09,.45,.065),(.09,.45,.065),.022,"brass",20)
    for x in [-.064,.064]: rod("Message_LampArm",(x,.413,.025),(x,.448,.045),.008,"brass",10)

PALETTE_MATERIALS={}
def compact_palette(data):
    """One vertex-colour material per physical finish, instead of per hue."""
    replacements={}
    for index,mat in enumerate(data.materials):
        if not mat or not mat.name.startswith("MAT_Garden_") or mat.name in ("MAT_Garden_glass","MAT_Garden_water"):continue
        if any(n.type in ("TEX_IMAGE","VERTEX_COLOR") for n in mat.node_tree.nodes):continue
        bsdf=next(n for n in mat.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
        finish="Metal" if bsdf.inputs["Metallic"].default_value>.5 else "Matte"
        if finish not in PALETTE_MATERIALS:
            palette=bpy.data.materials.new("MAT_Garden_Palette"+finish);palette.use_nodes=True
            target=next(n for n in palette.node_tree.nodes if n.type=="BSDF_PRINCIPLED")
            target.inputs["Roughness"].default_value=.38 if finish=="Metal" else .82
            target.inputs["Metallic"].default_value=.74 if finish=="Metal" else 0
            color=palette.node_tree.nodes.new("ShaderNodeVertexColor");color.layer_name="GardenPalette"
            palette.node_tree.links.new(color.outputs["Color"],target.inputs["Base Color"])
            PALETTE_MATERIALS[finish]=palette
        replacements[index]=(PALETTE_MATERIALS[finish],tuple(bsdf.inputs["Base Color"].default_value))
    # glTF has one COLOR_0 across all materials of a mesh. Joining differently
    # named active layers otherwise gives some surfaces white/black defaults.
    previous=data.color_attributes.active_color
    original=[]
    if previous:
        for loop in data.loops:
            index=loop.index if previous.domain=="CORNER" else loop.vertex_index
            original.append(tuple(previous.data[index].color))
    colors=data.color_attributes.get("GardenPalette") or data.color_attributes.new(name="GardenPalette",type="FLOAT_COLOR",domain="CORNER")
    data.color_attributes.active_color=colors
    data.color_attributes.render_color_index=data.color_attributes.find("GardenPalette")
    for loop in data.loops:colors.data[loop.index].color=original[loop.index] if original else (1,1,1,1)
    for poly in data.polygons:
        if poly.material_index in replacements:
            rgba=replacements[poly.material_index][1]
            for loop in poly.loop_indices:colors.data[loop].color=rgba
    for index,(mat,_) in replacements.items():data.materials[index]=mat
    for layer in list(data.color_attributes):
        if layer.name!="GardenPalette":data.color_attributes.remove(layer)
    # Imported canopy UV_Surface must share the architecture's UVMap before
    # a join. Otherwise masked leaves sample the transparent atlas corner.
    if data.uv_layers:
        data.uv_layers.active.name="UVMap"
        data.uv_layers.active.active_render=True
    data.update()

def evaluated_export(collections, name, low=False):
    """Spatially batch compatible parts, preserving independent culling bounds.

    Editable objects stay untouched. Low detail strips micro trim and evaluates
    source bevels off, rather than indiscriminately collapsing architecture.
    """
    changed=[]
    if low:
        for collection in collections:
            for ob in collection.objects:
                for mod in ob.modifiers:
                    if mod.type in ("BEVEL","WEIGHTED_NORMAL") and mod.show_viewport:
                        changed.append(mod);mod.show_viewport=False
    depsgraph = bpy.context.evaluated_depsgraph_get()
    depsgraph.update()
    copies=[]
    report={"groups":{},"triangles":0,"materials":set(),"degenerateTriangles":0}
    low_skip=("SpineBand","BookPages","Perpend","BedJoint","RoofSeam","RoofReturnSeam","SoffitLinearJoint","DrainSlot","WindowBand","RoofTileRidge","LeafVein","WaterRibbon")
    for collection in collections:
        buckets={}
        for ob in collection.objects:
            if ob.type != "MESH": continue
            if low and any(token in ob.name for token in low_skip): continue
            evaluated=ob.evaluated_get(depsgraph)
            data=bpy.data.meshes.new_from_object(evaluated,depsgraph=depsgraph)
            if low and ob.get("botanical_low_mesh"):
                bpy.data.meshes.remove(data)
                data=bpy.data.meshes[ob["botanical_low_mesh"]].copy()
            # Devices retain their five material identity for exact gameplay
            # batching; only the surrounding environment uses the colour atlas.
            if name.startswith("garden"):compact_palette(data)
            data.calc_loop_triangles()
            count=len(data.loop_triangles)
            report["triangles"]+=count
            report["degenerateTriangles"]+=sum(t.area < 1e-12 for t in data.loop_triangles)
            report["materials"].update(m.name for m in data.materials if m)
            copy=bpy.data.objects.new(ob.name+"_Export",data)
            scene.collection.objects.link(copy)
            copy.matrix_world=ob.matrix_world.copy()
            # Standard detail uses 16m cells for visibility granularity. On the
            # minimum renderer the compact campus puts most cells on screen:
            # collection-wide batches keep draw calls down without losing art.
            center=sum((ob.matrix_world @ Vector(p) for p in ob.bound_box),Vector())/8
            cell=(math.floor(center.x/16),math.floor(-center.y/16)) if not low and not collection.name.startswith("COL_Device") and collection.name != "COL_MessageDevice" else (0,0)
            buckets.setdefault(cell,[]).append(copy)
        for cell,parts in buckets.items():
            bpy.ops.object.select_all(action="DESELECT")
            for part in parts: part.select_set(True)
            bpy.context.view_layer.objects.active=parts[0]
            bpy.ops.object.join()
            combined=parts[0]
            combined.name="SM_"+collection.name.removeprefix("COL_")+("_Cell_%s_%s" % cell if len(buckets)>1 else "")
            bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
            # Correct local origin matters for Godot visibility_range_end.
            if len(buckets)>1:
                bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY",center="BOUNDS")
            copies.append(combined)
            report["groups"][combined.name]=len(combined.data.polygons)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in copies: ob.select_set(True)
    settings={"export_vertex_color":"NAME","export_vertex_color_name":"GardenPalette","export_all_vertex_colors":False} if name.startswith("garden") else {}
    bpy.ops.export_scene.gltf(filepath=str(OUT/name),export_format="GLB",use_selection=True,export_apply=True,export_animations=False,export_yup=True,**settings)
    for ob in copies:
        bpy.data.objects.remove(ob,do_unlink=True)
    for mod in changed:mod.show_viewport=True
    report["materials"]=sorted(report["materials"])
    report["bytes"]=(OUT/name).stat().st_size
    report["spatialCellMetres"]=0 if low else 16
    report["grouping"]="collection" if low else "spatial_cells"
    report["lowDetail"]=low
    return report

device_report=evaluated_export([GROUPS["MessageDevice"]],"message_device.glb")
assert device_report["triangles"] < 8000 and len(device_report["materials"]) <= 5
GROUPS["MessageDevice"].hide_render=True
GROUPS["MessageDevice"].hide_viewport=True

def foliage(name,center,span,count,mat="leaf"):
    points,faces=[],[]
    for k in range(count):
        a=rng.uniform(0,math.tau)
        zz=rng.uniform(-1,1)
        rr=math.sqrt(1-zz*zz)*rng.random()**.33
        p=Vector((center[0]+math.cos(a)*rr*span[0],center[1]+zz*span[1],center[2]+math.sin(a)*rr*span[2]))
        axis=Vector((rng.uniform(-1,1),rng.uniform(-.3,.8),rng.uniform(-1,1))).normalized()
        side=axis.cross(Vector((0,1,0))).normalized()*rng.uniform(.035,.07)
        length=rng.uniform(.12,.22)
        base=len(points)
        mid=p+axis*length*.55
        points += [tuple(p),tuple(mid+side),tuple(p+axis*length),tuple(mid-side),tuple(mid+Vector((0,.018,0)))]
        faces += [(base,base+1,base+4),(base+1,base+2,base+4),(base+2,base+3,base+4),(base+3,base,base+4)]
    return mesh(name,points,faces,mat)

def tree(name,p,height=4.8):
    with frame(p):
        cylinder(name+"_Trunk",(0,height*.28,0),.12,height*.56,"bark",top=.065,segments=14)
        for i in range(8):
            a=i*2.399
            end=(math.cos(a)*1.25,height*(.60+(i%3)*.085),math.sin(a)*1.25)
            rod(name+"_Branch",(0,height*.44,0),end,.035,"bark",8)
            foliage(name+"_Leaves",end,(.93,.58,.83),180,"leaf" if i%2 else "leaf_light")

def bench(name,p,yaw=0):
    with frame(p,yaw):
        for x in [-.85,.85]:
            for z in [-.21,.21]: box(name+"_Leg",(x,.23,z),(.065,.46,.065),"teal",.008)
            box(name+"_Frame",(x,.44,0),(.07,.08,.62),"teal",.008)
            rod(name+"_BackPost",(x,.42,-.24),(x,.99,-.31),.035,"teal")
            box(name+"_Arm",(x,.66,.01),(.07,.065,.55),"teal",.014)
        for z in [-.20,-.067,.067,.20]: box(name+"_SeatSlat",(0,.49,z),(1.95,.055,.12),"walnut",.009)
        for y in [.68,.82,.96]: box(name+"_BackSlat",(0,y,-.28),(1.95,.11,.045),"walnut",.009)
        collision(name,(0,.50,0),(2.05,1.0,.65))

exec(compile((ROOT / "tools/discussion_environment.py").read_text(encoding="utf-8"), str(ROOT / "tools/discussion_environment.py"), "exec"), globals())
