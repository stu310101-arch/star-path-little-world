"""Create an original, editable low-poly graduation outfit over Quaternius' rig.

Run with Blender in background, after opening the original Male_Casual.blend.
All clothing is generated locally; no external texture or paid assets required.
"""
import bpy, bmesh, math, json
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'art' / 'Graduate'
OUT.mkdir(parents=True, exist_ok=True)
scene = bpy.context.scene
rig = bpy.data.objects['HumanArmature']
body = bpy.data.objects['BaseHuman']
rig.data.pose_position = 'REST'
bpy.context.view_layer.update()

def collection(name):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    return c

wardrobe = collection('GRADUATE | Gown, stole and mortarboard')
studio = collection('STUDIO | Preview only')

def linear(v):
    return v / 12.92 if v <= .04045 else ((v+.055)/1.055)**2.4

def material(name, hex_color, roughness=.75, metallic=0):
    m = bpy.data.materials.new(name)
    rgb = tuple(linear(int(hex_color[i:i+2],16)/255) for i in (0,2,4))
    m.diffuse_color = (*rgb,1)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*rgb,1)
    p.inputs['Roughness'].default_value = roughness
    p.inputs['Metallic'].default_value = metallic
    return m

navy = material('Gown | midnight navy wool', '202D40')
navy_light = material('Gown | fold light', '25354A')
navy_dark = material('Gown | fold shadow', '1A2434')
blue = material('Stole | graduation blue satin', '37799F', .42)
gold = material('Trim | warm antique gold', 'D8B969', .4, .18)
gold_dark = material('Tassel | gold shadow', 'AA793A', .55)
ivory = material('Shirt | ivory cotton', 'F3EBDD')
trousers = material('Trousers | graphite', '272C35')

# Refresh legacy Blender 2.7 materials for modern Eevee while preserving colors.
for mat in list(body.data.materials):
    color = tuple(mat.diffuse_color)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    p = mat.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
    p.inputs['Base Color'].default_value = color
    p.inputs['Roughness'].default_value = .82
    out = mat.node_tree.nodes.new('ShaderNodeOutputMaterial')
    mat.node_tree.links.new(p.outputs['BSDF'], out.inputs['Surface'])

# Keep the original face, hair, hands, shoes and rig. Remove hidden casual sleeves
# inside the new gown and extend the original leg surface into dark trousers.
body.data.materials.append(trousers)
pants_index = len(body.data.materials)-1
bm = bmesh.new()
bm.from_mesh(body.data)
remove=[]
for f in bm.faces:
    center=f.calc_center_median()
    mat=body.data.materials[f.material_index].name
    if mat == 'Shirt':
        remove.append(f)
    elif mat == 'Skin' and center.z > 3.3 and .70 < abs(center.x) < 1.90:
        remove.append(f)
    elif mat in ('Pants','Socks') or (mat == 'Skin' and center.z < 1.78):
        f.material_index=pants_index
bmesh.ops.delete(bm, geom=remove, context='FACES')
bm.to_mesh(body.data)
bm.free()
body.name = 'Graduate | original face, hands and trousers'

def mesh_obj(name, verts, faces, mats, indices=None):
    mesh=bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj=bpy.data.objects.new(name,mesh)
    wardrobe.objects.link(obj)
    for m in mats: mesh.materials.append(m)
    if indices:
        for p,i in zip(mesh.polygons,indices): p.material_index=i
    bm=bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh); bm.free()
    return obj

def bind(obj, weights):
    obj.parent=rig
    for i,w in enumerate(weights):
        for name,value in w.items():
            if value > 1e-6:
                g=obj.vertex_groups.get(name) or obj.vertex_groups.new(name=name)
                g.add([i],value,'REPLACE')
    mod=obj.modifiers.new('Follow original character skeleton','ARMATURE')
    mod.object=rig
    return obj

def solid(obj, thickness=.012):
    m=obj.modifiers.new('Fabric edge thickness','SOLIDIFY')
    m.thickness=thickness
    m.offset=0

def torso_weights(v):
    z=v[2]
    if z >= 3.55: return {'Torso':1}
    if z >= 2.75:
        t=(z-2.75)/.80
        return {'Abdomen':1-t,'Torso':t}
    if z >= 2.20:
        t=(z-2.20)/.55
        return {'Hips':1-t,'Abdomen':t}
    # The calf-length skirt must follow each knee, with a blended center seam.
    t=min(.90,max(0,(2.2-z)/.65*.90))
    left=min(1,max(0,.5+v[0]/.42))
    return {'Hips':1-t,'UpperLeg.L':t*left,'UpperLeg.R':t*(1-left)}

# Elliptical rings, 12 restrained pleats and a shaped neck opening.
N=48
rings=[(.62,.73,.48,.51),(.70,.726,.476,.507),(1.30,.69,.45,.49),
       (2.15,.61,.42,.46),(2.75,.55,.41,.44),(3.30,.53,.40,.43),
       (3.65,.56,.37,.425),(3.88,.58,.31,.40)]
verts=[]
for j,(z,rx,front,back) in enumerate(rings):
    for i in range(N):
        a=2*math.pi*i/N
        amp=.032*(1-min(1,max(0,(z-2.2)/1.5)))+.007
        pleat=amp*math.cos(a*12)
        factor=1+pleat
        zz=z+(.015*math.cos(a*6) if j<2 else 0)
        if j==len(rings)-1:
            zz-=.19*max(0,-math.sin(a))**2
        verts.append((rx*math.cos(a)*factor, (back if math.sin(a)>0 else front)*math.sin(a)*factor,zz))
for i in range(N):
    a=2*math.pi*i/N
    front=max(0,-math.sin(a))
    verts.append((.216*math.cos(a), .125+.218*math.sin(a),4.065-.15*front**3))
faces=[]; ids=[]
for j in range(len(rings)):
    for i in range(N):
        faces.append((j*N+i,j*N+(i+1)%N,(j+1)*N+(i+1)%N,(j+1)*N+i))
        ids.append(1 if i%4==0 and j<6 else (2 if i%4==2 and j<6 else 0))
gown=mesh_obj('01 | Pleated bachelor gown',verts,faces,[navy,navy_light,navy_dark],ids)
bind(gown,[torso_weights(v) for v in verts]); solid(gown,.02)

def body_front(x,z):
    for a,b in zip(rings,rings[1:]):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]); rx=a[1]*(1-t)+b[1]*t; ry=a[2]*(1-t)+b[2]*t
            return -ry*math.sqrt(max(.05,1-(x/rx)**2))-.032
    return -.32

# Generous bell sleeves generated in the existing T-pose, then skinned to arms.
for side,sign in [('L',1),('R',-1)]:
    upper=rig.data.bones['UpperArm.'+side]
    lower=rig.data.bones['LowerArm.'+side]
    shoulder=abs(upper.head_local.x); elbow=abs(lower.head_local.x); wrist=abs(lower.tail_local.x)
    rows=[(shoulder-.05,.265,.265),(shoulder+.13,.28,.28),
          (elbow-.16,.235,.26),(elbow+.10,.25,.30),
          (wrist-.23,.285,.34),(wrist-.08,.30,.37),(wrist-.055,.30,.37)]
    vs=[]; ws=[]; fs=[]; mi=[]
    for x,ry,rz in rows:
        cx=sign*x
        t=min(1,max(0,(x-shoulder)/(wrist-shoulder)))
        center=upper.head_local.lerp(lower.tail_local,t)
        for i in range(16):
            a=i*2*math.pi/16
            # In rest pose, -Z maps to the outward draping side of a lowered arm.
            vs.append((cx,center.y+ry*math.cos(a),center.z+rz*math.sin(a)-.035))
            wt=min(1,max(0,(x-(elbow-.19))/.38))
            ws.append({'UpperArm.'+side:1-wt,'LowerArm.'+side:wt})
    for j in range(len(rows)-1):
        for i in range(16):
            fs.append((j*16+i,j*16+(i+1)%16,(j+1)*16+(i+1)%16,(j+1)*16+i))
            mi.append(2 if j==len(rows)-2 else (1 if i%4==1 else 0))
    # Domed shoulder closes the upper sleeve, overlapping the gown yoke.
    cap_index=len(vs)
    vs.append((sign*(shoulder-.19),upper.head_local.y,upper.head_local.z))
    ws.append({'UpperArm.'+side:1})
    for i in range(16):
        fs.append((cap_index,(i+1)%16,i)); mi.append(0)
    sleeve=mesh_obj('02 | Bell sleeve '+side,vs,fs,[navy,navy_light,navy_dark],mi)
    bind(sleeve,ws); solid(sleeve,.018)

# Broad blue academic stole with fine gold piping and pointed ends.
for side,sign in [('L',1),('R',-1)]:
    path=[(.235,.335,3.97),(.29,.16,4.075),(.275,-.11,4.005),
          (.25,None,3.80),(.24,None,3.65),(.235,None,3.50),(.235,None,3.00),(.25,None,2.50),
          (.28,None,2.02),(.29,None,1.78),(.29,None,1.66)]
    widths=[.16,.20,.20,.20,.195,.19,.18,.18,.18,.18,0]
    vs=[]
    for row,((x,y,z),w) in enumerate(zip(path,widths)):
        if w==0:
            xx=sign*x
            vs.append((xx,body_front(xx,z)-.01,z))
            continue
        for frac in [-.5,-.43,.43,.5]:
            xx=sign*(x+frac*w)
            yy=body_front(xx,z)-.01 if y is None else y
            vs.append((xx,yy,z))
    fs=[]; mi=[]
    for j in range(len(path)-1):
        for k in range(3):
            if j==len(path)-2:
                fs.append((j*4+k,j*4+k+1,len(vs)-1))
            else:
                fs.append((j*4+k,j*4+k+1,(j+1)*4+k+1,(j+1)*4+k))
            mi.append(0 if k==1 else 1)
    stole=mesh_obj('03 | Blue and gold stole '+side,vs,fs,[blue,gold],mi)
    bind(stole,[torso_weights(v) for v in vs]); solid(stole,.01)
    # Two small woven graduation bars at the tail, modeled as independent faces.
    for n in range(2):
        z=1.90+n*.07; cx=sign*.285
        vv=[(cx-.062,body_front(cx-.062,z)-.024,z), (cx+.062,body_front(cx+.062,z)-.024,z),
            (cx+.062,body_front(cx+.062,z+.016)-.024,z+.016),(cx-.062,body_front(cx-.062,z+.016)-.024,z+.016)]
        bar=mesh_obj('04 | Stole woven bar '+side+str(n),vv,[(0,1,2,3)],[gold])
        bind(bar,[torso_weights(v) for v in vv])

# Continuous stole collar around the back of the neck, joining both front tails.
vs=[];fs=[];mi=[]
for i in range(13):
    a=math.pi*i/12
    for t in [0,.075,.925,1]:
        rx=.255*(1-t)+.36*t
        ry=.245*(1-t)+.30*t
        vs.append((rx*math.cos(a),.125+ry*math.sin(a),4.095*(1-t)+3.94*t))
for i in range(12):
    for j in range(3):
        fs.append((i*4+j,i*4+j+1,(i+1)*4+j+1,(i+1)*4+j))
        mi.append(0 if j==1 else 1)
stole_back=mesh_obj('03 | Continuous stole back collar',vs,fs,[blue,gold],mi)
bind(stole_back,[{'Torso':1}]*len(vs));solid(stole_back,.009)

# Ivory shirt front and folded collar visible within the graduation gown's V.
bib_verts=[(-.185,-.095,4.065),(.185,-.095,4.065),(.12,-.205,3.925),(0,-.235,3.885),(-.12,-.205,3.925)]
bib=mesh_obj('05 | Ivory shirt bib',bib_verts,[(0,1,2,3,4)],[ivory]); bind(bib,[{'Torso':1}]*5); solid(bib)
for sign in [-1,1]:
    vs=[(sign*.012,-.126,4.045),(sign*.17,-.10,4.075),(sign*.205,-.20,3.99),(sign*.075,-.245,3.90)]
    obj=mesh_obj('05 | Folded shirt collar '+str(sign),vs,[(0,1,2,3)],[ivory]); bind(obj,[{'Torso':1}]*4); solid(obj)

def box(name,center,scale,mat,angle=0,bone='Head'):
    vs=[]
    for z in [-1,1]:
        for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]:
            xx=x*scale[0]/2; yy=y*scale[1]/2
            vs.append((center[0]+xx*math.cos(angle)-yy*math.sin(angle),center[1]+xx*math.sin(angle)+yy*math.cos(angle),center[2]+z*scale[2]/2))
    obj=mesh_obj(name,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],[mat])
    if bone: bind(obj,[{bone:1}]*len(vs))
    return obj

def tube(name,points,radii,mat,sides=8,bone='Head'):
    vs=[]; fs=[]
    for j,point in enumerate(points):
        point=Vector(point)
        tangent=Vector(points[min(j+1,len(points)-1)])-Vector(points[max(0,j-1)])
        tangent.normalize(); u=tangent.cross(Vector((0,1,0)))
        if u.length<.01: u=tangent.cross(Vector((1,0,0)))
        u.normalize(); v=tangent.cross(u).normalized()
        r=radii[j] if isinstance(radii,list) else radii
        for i in range(sides):
            co=point+r*(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))
            vs.append(tuple(co))
    for j in range(len(points)-1):
        for i in range(sides): fs.append((j*sides+i,j*sides+(i+1)%sides,(j+1)*sides+(i+1)%sides,(j+1)*sides+i))
    fs.extend([tuple(reversed(range(sides))),tuple((len(points)-1)*sides+i for i in range(sides))])
    obj=mesh_obj(name,vs,fs,[mat]); bind(obj,[{bone:1}]*len(vs))
    return obj

# Fitted cap crown plus a real thin square board (not a pyramidal hat).
vs=[]
for z,rx,ry in [(4.72,.273,.34),(4.86,.283,.354),(4.96,.29,.36)]:
    for i in range(16):
        a=i*math.tau/16
        vs.append((rx*math.cos(a),.082+ry*math.sin(a),z))
fs=[]
for j in range(2):
    for i in range(16): fs.append((j*16+i,j*16+(i+1)%16,(j+1)*16+(i+1)%16,(j+1)*16+i))
fs.append(tuple(32+i for i in range(16)))
crown=mesh_obj('06 | Fitted graduation cap',vs,fs,[navy]); bind(crown,[{'Head':1}]*len(vs)); solid(crown)
board=box('07 | Square mortarboard',(0,.082,4.985),(.89,.89,.065),navy,math.radians(45))
bevel=board.modifiers.new('Tiny tailored board edges','BEVEL'); bevel.width=.009; bevel.segments=1
tube('08 | Cap button',[(0,.082,5.021),(0,.082,5.055)],[.033,.024],gold,12)
tube('09 | Gold tassel cord',[(0,.082,5.054),(.18,.072,5.04),(.42,.06,5.037),(.625,.05,5.026),(.65,.04,4.96),(.65,.027,4.67)],.010,gold,6)
tube('10 | Tassel knot',[(.65,.027,4.70),(.65,.027,4.64)],[.023,.028],gold,8)
for i in range(7):
    a=i*math.tau/7
    px=.65+.021*math.cos(a); py=.027+.021*math.sin(a)
    tube('11 | Tassel strand %02d'%i,[(px,py,4.65),(px+.010*math.cos(a),py+.010*math.sin(a),4.48),
             (px+.013*math.cos(a),py+.013*math.sin(a),4.435+(i%3)*.009)], [.008,.009,.006],gold if i%3 else gold_dark,5)

# Studio is an independent collection, easy to hide when reusing the character.
def move_to(obj,c):
    for old in list(obj.users_collection): old.objects.unlink(obj)
    c.objects.link(obj)

floor_mat=material('Studio | warm mist', 'E1E4E5', .9)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.026))
floor=bpy.context.object; floor.name='Studio floor'; move_to(floor,studio); floor.data.materials.append(floor_mat)
floor.hide_set(True)

def aim(obj,point): obj.rotation_euler=(Vector(point)-obj.location).to_track_quat('-Z','Y').to_euler()

bpy.ops.object.camera_add(location=(8,-15,8.4))
camera=bpy.context.object; camera.name='Camera | graduate portrait'; move_to(camera,studio)
aim(camera,(0,0,2.48)); camera.data.type='ORTHO'; camera.data.ortho_scale=6.3; scene.camera=camera

def area(name,location,power,size,color):
    data=bpy.data.lights.new(name,'AREA'); data.energy=power; data.shape='DISK'; data.size=size; data.color=color
    o=bpy.data.objects.new(name,data); studio.objects.link(o); o.location=location; aim(o,(0,0,2.5)); return o

area('Key | softbox',(-4,-6,9),1000,5.0,(1,.88,.74))
area('Fill | cool softbox',(5,-3,6),750,4.0,(.74,.86,1))
area('Rim | overhead',(1,4,8),1300,3.0,(1,.92,.80))
scene.world=bpy.data.worlds.new('Studio ambient')
scene.world.use_nodes=True
background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs[0].default_value=(.65,.72,.82,1)
background.inputs[1].default_value=.45
scene.render.engine='CYCLES'
# CPU rendering avoids consuming the laptop's limited discrete GPU memory.
scene.cycles.device='CPU'; scene.cycles.samples=24; scene.cycles.use_denoising=True
scene.render.resolution_x=900; scene.render.resolution_y=1000; scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'; scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'

rig.data.pose_position='POSE'
rig.animation_data.action=bpy.data.actions['Man_Idle']
scene.frame_start=0; scene.frame_end=100; scene.frame_set(17)
bpy.context.view_layer.update()
rig.hide_set(True)
for obj in studio.objects:
    if obj != floor: obj.hide_set(True)
for obj in bpy.context.selected_objects: obj.select_set(False)
bpy.context.view_layer.objects.active=gown

# Start in the source's spacious 3D workspace, facing the dressed character.
for screen in bpy.data.screens:
    for area_ in screen.areas:
        if area_.type=='VIEW_3D':
            space=area_.spaces.active
            space.shading.type='SOLID'; space.shading.color_type='MATERIAL'
            space.shading.light='STUDIO'; space.shading.studiolight_rotate_z=.5
            space.shading.show_shadows=True; space.shading.show_cavity=True
            space.shading.cavity_type='BOTH'
            space.overlay.show_overlays=False
            space.region_3d.view_distance=7.7
            space.region_3d.view_location=(0,0,2.5)
            space.region_3d.view_rotation=(Vector((7,-17,7.7))-Vector((0,0,2.5))).to_track_quat('Z','Y')
            space.region_3d.view_perspective='ORTHO'
if bpy.context.window:
    ws=bpy.data.workspaces.get('3D View Full')
    if ws: bpy.context.window.workspace=ws

scene['Design']='Original low-poly academic regalia: midnight navy gown, blue/gold stole, mortarboard and gold tassel.'
scene['Source']='Quaternius Male_Casual, CC0. Outfit created procedurally for this project.'
scene['Rig notes']='Clothing weighted to original skeleton. Skirt follows pelvis and knees with a blended center; fast motion may require further cloth/weight tuning.'
# Drop a missing, unused legacy image that was displayed only in an old editor.
used_images={n.image for m in bpy.data.materials if m.node_tree for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image}
for screen in bpy.data.screens:
    for area_ in screen.areas:
        for space in area_.spaces:
            if space.type=='IMAGE_EDITOR' and space.image and space.image not in used_images and space.image.source=='FILE':
                space.image=None
for img in list(bpy.data.images):
    if img.source=='FILE' and img not in used_images and not img.packed_file and img.filepath and not Path(bpy.path.abspath(img.filepath)).is_file():
        bpy.data.images.remove(img,do_unlink=True)
scene.render.filepath=str(OUT/'Graduate_preview.png')
scene.render.use_file_extension=True
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Male_Graduate.blend'))

stats={'file':str(OUT/'Male_Graduate.blend'),'meshes':[],'actions':len(bpy.data.actions),'missing_external_images':[]}
for img in bpy.data.images:
    if img.source=='FILE' and not img.packed_file and img.filepath and not Path(bpy.path.abspath(img.filepath)).is_file():
        stats['missing_external_images'].append(img.filepath)
for o in [body]+list(wardrobe.objects):
    if o.type=='MESH':
        stats['meshes'].append({'name':o.name,'vertices':len(o.data.vertices),'faces':len(o.data.polygons),'weighted':all(len(v.groups)>0 for v in o.data.vertices)})
stats['total_vertices']=sum(o['vertices'] for o in stats['meshes'])
stats['total_faces']=sum(o['faces'] for o in stats['meshes'])
(OUT/'model-info.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
scene.render.filepath=str(OUT/'Graduate_preview.png')
bpy.ops.render.render(write_still=True)
print('GRADUATE_COMPLETE',json.dumps(stats))
