"""Re-style the authored lounge for Little World and export a game duplicate.

Open WordKing_TrainingRoom.blend in a separate Blender background process.
The original file is never overwritten. The editable Game.blend keeps the
upholstery topology and references; only the unsaved export copy is simplified.
"""
from pathlib import Path
from collections import defaultdict
import bpy, bmesh, math, json, re, sys, shutil
from mathutils import Vector, Matrix

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art'/'TrainingRoom'
DEST=ROOT/'game'/'assets'/'training_room'
DEST.mkdir(parents=True, exist_ok=True)
sys.path.insert(0,str(ROOT/'tools'))
from training_room_reading_wall import build_reading_wall
from training_room_interactive_art import enlarge_lounge, build_interactive_decor
assert Path(bpy.data.filepath).name=='WordKing_TrainingRoom.blend'
scene=bpy.context.scene
assert sum(o.get('device_type')=='wordking_training' for o in scene.objects)==1
assert sum(bool(o.get('intentionally_empty')) for o in scene.objects)==6

def linear_hex(h):
    vals=[int(h[i:i+2],16)/255 for i in (0,2,4)]
    return tuple(c/12.92 if c<=.04045 else ((c+.055)/1.055)**2.4 for c in vals)

def material(name,h,rough=.8,metal=.0,emission=0,alpha=1):
    m=bpy.data.materials.new('MAT_Game_'+name);m.use_nodes=True
    color=linear_hex(h);m.diffuse_color=(*color,alpha)
    p=next((n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None)
    if p is None:
        p=m.node_tree.nodes.new('ShaderNodeBsdfPrincipled')
        out=next((n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL'),None) or m.node_tree.nodes.new('ShaderNodeOutputMaterial')
        m.node_tree.links.new(p.outputs['BSDF'],out.inputs['Surface'])
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal
    p.inputs['Specular IOR Level'].default_value=.25
    p.inputs['Alpha'].default_value=alpha
    if emission:
        p.inputs['Emission Color'].default_value=(*color,1)
        p.inputs['Emission Strength'].default_value=emission
    if alpha<1:m.surface_render_method='DITHERED'
    m.use_backface_culling=False
    m['style_source']='Little World WordKing district / warm stone, wood, teal, pale gold'
    return m

M={
    'cream':material('Warm_Plaster','dedcc7',.9),
    'stone':material('Limestone','b4b6a3',.9),
    'stone_alt':material('Limestone_Alternate','aeb2a1',.9),
    'wood':material('Honey_Oak','b39673',.77),
    'wood_dark':material('Oak_Edge','846747',.79),
    'teal':material('Soft_Teal_Upholstery','345c58',.78),
    'dark_teal':material('Deep_Teal_Frame','284a4d',.82),
    'sage':material('Sage_Fabric','708474',.92),
    'rug':material('Oatmeal_Rug','b1aa8d',.99),
    'gold':material('WordKing_Champagne','d4cd84',.53,.18),
    'gold_light':material('Warm_Inlay','d4cd84',.73,emission=.24),
    'aqua_light':material('Soft_Aqua_Light','81bec0',.6,emission=.48),
    'white_light':material('Cream_Lamp','fff0c8',.64,emission=.65),
    'holo_light':material('Hologram_Cyan','1ba5ff',.4,emission=2.2),
    'holo_type':material('Hologram_Type','a0edff',.4,emission=2.7),
    'holo_grid':material('Hologram_Grid','1371db',.7,emission=.85),
    'holo_sheet':material('Hologram_Glass','0746a3',.73,emission=.4,alpha=.38),
    'holo_beam':material('Hologram_Beam','188cfa',.73,emission=.6,alpha=.12),
    'projector_blue':material('Projector_Blue_Inlay','149eff',.35,emission=2.1),
    'glass':material('Display_Glass','b4dbd1',.24,alpha=.09),
    'screen':material('Screen_Ink','15363e',.64,emission=.06),
    'green':material('Plant_Sage','526e42',.91),
    'green2':material('Plant_Highlight','779359',.88),
    'soil':material('Pot_Soil','594f3e',1),
}
painting_image=bpy.data.images.load(str(DEST/'textures'/'starry_night.jpg'),check_existing=True)
painting_image.pack()
M['starry_night']=material('Starry_Night_Canvas','ffffff',.94)
canvas_nodes=M['starry_night'].node_tree
canvas_bsdf=next(n for n in canvas_nodes.nodes if n.type=='BSDF_PRINCIPLED')
canvas_texture=canvas_nodes.nodes.new('ShaderNodeTexImage');canvas_texture.image=painting_image
canvas_nodes.links.new(canvas_texture.outputs['Color'],canvas_bsdf.inputs['Base Color'])
M['starry_night']['image_aspect_height']=painting_image.size[1]/painting_image.size[0]
M['starry_night']['artwork']='Vincent van Gogh, The Starry Night, 1889; public domain'

col_by_prefix={c.name[:2]:c for c in scene.collection.children}
game_decor=bpy.data.collections.new('14 | Little World woodwork');scene.collection.children.link(game_decor)
orig_mat_map={
 'Obsidian lacquer':'dark_teal','Graphite brushed aluminium':'dark_teal',
 'Machined silver':'gold','Electric blue light':'gold_light','Cyan optical light':'aqua_light',
 'Pearl white LED':'white_light','Holographic grid':'holo_grid',
 'Transparent holographic blue':'holo_sheet','Soft black leather':'teal',
 'Charcoal woven rug':'rug','Midnight curtain velvet':'sage','Dark olive leaves':'green',
 'Leaf highlights':'green2','Pot soil':'soil','Display glass':'glass',
 'Neutral warm lamp':'white_light','Screen navy':'screen','Seam stitching':'sage',
 'Midnight veined marble':'stone','Portal signature gold':'gold',
 'dark leather saddle stitching':'sage',
}
source_objects=list(scene.objects)
enlarge_lounge(source_objects)
for o in source_objects:
    if o.type not in {'MESH','CURVE','FONT'}:continue
    if o.data.users>1:o.data=o.data.copy()
    for i,slot in enumerate(list(o.data.materials)):
        key=slot.name.removeprefix('MAT | ') if slot else ''
        replacement=M.get(orig_mat_map.get(key,'dark_teal'))
        o.data.materials[i]=replacement
    name=o.name
    def setmat(key):
        o.data.materials.clear();o.data.materials.append(M[key])
    if name.startswith('ARCH |'):
        setmat('cream')
        if 'recessed wall' in name:setmat('stone')
        elif 'structural plinth' in name:setmat('dark_teal')
        elif 'feature tower' in name:setmat('wood')
    if name.startswith('FLOOR |'):
        parts=re.findall(r'\d+',name)
        setmat('stone_alt' if sum(map(int,parts))%4==0 else 'stone')
    if name=='ARCH | optional ceiling':setmat('cream')
    if name.startswith('CENTER | flush'):setmat('sage')
    if 'track pelmet' in name:setmat('wood')
    if name.startswith('SIGN |'):setmat('gold' if name.endswith('title') else 'cream')
    if name.startswith('CEILING | recessed'):setmat('wood')
    if name.startswith('GAMING'):
        if any(s in name for s in ['continuous desk','desk leg']):setmat('wood')
        if 'racing shell' in name.lower():setmat('teal')
        if 'screen frame' in name:setmat('dark_teal')
        if 'wall sign' in name:setmat('dark_teal')
    if name.startswith('DISPLAY'):
        if any(s in name for s in ['full back','canopy','substantial shelf','vertical mullion']):setmat('wood')
        if any(s in name for s in ['Genshin brand','reserve caption']):setmat('cream')
    if name.startswith('LOUNGE_'):
        if any(s in name for s in ['Left_frame','Return_frame','Coffee_table_plinth','Side_table_top']):setmat('wood')
        if 'Coffee_table_marble' in name:setmat('cream')
        if 'Loose_pillow_A' in name:setmat('gold' if 'stitches' not in name else 'cream')
        if 'Loose_pillow_B' in name:setmat('sage')
        if 'Loose_pillow_C' in name:setmat('cream')
        if 'leather welt' in name:setmat('dark_teal')
    if name.startswith('GEO-WK-'):
        # Optical elements need separate draw groups in Godot: transparent
        # light never receives warm room shading or casts an opaque shadow.
        if 'Projection_light_field' in name:setmat('holo_beam')
        elif 'Hologram_transparent_trapezoid' in name:setmat('holo_sheet')
        elif 'Hologram_fine_grid' in name:setmat('holo_grid')
        elif any(s in name for s in ['Main_Chinese_logotype','Training_subline','Crown_']):setmat('holo_type')
        elif any(s in name for s in ['Hologram_','Projection_']):setmat('holo_light')
        elif any(s in name for s in ['Blue_luminous_seam','Lens_outer_ring','Lens_middle_ring','Lens_inner_ring','Lens_core_ring','Central_optic','Shoulder_blue_status','Power_badge_ring','Power_symbol']):setmat('projector_blue')
        elif 'Upper_chamfered_housing' in name:setmat('dark_teal')
    if name.startswith('PORTAL |'):
        if 'open doorway' in name:setmat('wood')
        if 'service plate' in name:setmat('dark_teal')
        if 'arrival pad' in name:setmat('sage')
    if 'tapered pot' in name:setmat('cream')

bpy.data.objects['SIGN | title'].data.body='練功區'
bpy.data.objects['SIGN | subtitle'].data.body='T R A I N I N G   L O U N G E'
bpy.data.objects['SIGN | title'].data.materials[0]=M['cream']

def line(name,points,mat,radius=.025):
    d=bpy.data.curves.new(name,'CURVE');d.dimensions='3D';d.bevel_depth=radius;d.bevel_resolution=1
    d.resolution_u=1;s=d.splines.new('POLY');s.points.add(len(points)-1)
    for p,v in zip(s.points,points):p.co=(*v,1)
    o=bpy.data.objects.new(name,d);game_decor.objects.link(o);d.materials.append(mat);return o

# Authored timber arches visually connect this interior with the small civic
# buildings outside. They are shallow wall joinery, so the walkable plan is kept.
for side in [-1,1]:
    x=side*9.90
    for y in [-6.30,6.45]:
        if side==1 and y<0:continue # replaced by the functional reading wall
        points=[(x,y-.79,.72),(x,y-.79,2.05)]
        points += [(x,y+.79*math.cos(a),2.05+.79*math.sin(a)) for a in [math.pi-i*math.pi/24 for i in range(25)]]
        points += [(x,y+.79,.72)]
        line('WOODWORK | arched side inlay',points,M['wood'],.047)
    line('WOODWORK | continuous low rail',[(side*9.91,-8.92,.70),(side*9.91,8.87,.70)],M['wood'],.039)

reading_colliders=build_reading_wall(game_decor,M,bpy.data.objects['SIGN | title'].data.font)
decor_colliders,decor_targets=build_interactive_decor(game_decor,M)
reading_colliders.update(decor_colliders)

# Keep the full room available in the editable master. The export includes its
# roof and front wall; its lighting is owned by the Godot room scene.
for c in scene.collection.children:
    if c.name.startswith('13'):
        c.hide_viewport=False;c.hide_render=False
for o in scene.objects:
    if o.type=='LIGHT':
        o.data.color=(1,.91,.76)
        if 'uplight' in o.name:o.data.energy=35
background=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND')
background.inputs['Color'].default_value=(.50,.56,.52,1)
background.inputs['Strength'].default_value=.35
scene['style_revision']='Interactive training lounge: enlarged tailored sofa, individually selectable books, Starry Night, authored ceramic and textile details'
scene['room_display_name']='練功區'
scene['delivery_scope']='Editable Blender game-style master; optimized GLB duplicate for Godot integration'
scene['modeling_preserved']='22 individually sculpted sewn upholstery surfaces, shaped chairs, 1 device, 6 empty sockets'
scene.view_settings.view_transform='AgX'
bpy.context.view_layer.update()

def godot(v):return [round(v.x,5),round(v.z,5),round(-v.y,5)]
def world_bounds(objects):
    pts=[o.matrix_world@Vector(v) for o in objects for v in o.bound_box if o.type in {'MESH','CURVE','FONT'}]
    lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
    return lo,hi

colliders=[]
def collider(name,objects,angle=0,pivot=None):
    if not objects:return
    if pivot is None:
        lo,hi=world_bounds(objects);center=(lo+hi)*.5;size=hi-lo
    else:
        pivot=Vector(pivot);rotation=Matrix.Rotation(angle,3,'Z')
        pts=[rotation.inverted()@(o.matrix_world@Vector(v)-pivot) for o in objects for v in o.bound_box]
        lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)))
        hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
        center=pivot+rotation@((lo+hi)*.5);size=hi-lo
    colliders.append({'name':name,'center':godot(center),'size':[round(size.x,5),round(size.z,5),round(size.y,5)],'rotation_y':angle})

def names(*frags):return [o for o in source_objects if any(s in o.name for s in frags)]
collider('Sofa_Left_Run',names('LOUNGE_Left_frame','LOUNGE_Left_back_shell','LOUNGE_Left_end_arm','LOUNGE_Left_seat_','LOUNGE_Left_back_cushion_','LOUNGE_Corner_left_back_cushion_'))
collider('Sofa_Return_Run',names('LOUNGE_Return_frame','LOUNGE_Return_back_shell','LOUNGE_Return_end_arm','LOUNGE_Return_seat_','LOUNGE_Return_back_cushion_','LOUNGE_Corner_back'))
collider('Sofa_Corner',names('LOUNGE_Corner_seat'))
collider('Coffee_Table',names('LOUNGE_Coffee_table_plinth','LOUNGE_Coffee_table_marble'))
collider('Side_Table',names('LOUNGE_Side_table_base','LOUNGE_Side_table_top'))
collider('Gaming_Desk',names('GAMING | continuous desk','GAMING | desk leg'),math.radians(-10),(-7.95,3.6,0))
for idx in [1,2,3]:
    chair_prefixes=tuple('GAMING | '+s+' '+str(idx) for s in ['shaped seat','sculpted racing shell','shaped arm pad','soft head pad'])
    objs=[o for o in source_objects if o.name.startswith(chair_prefixes)]
    collider('Gaming_Chair_'+str(idx),objs)
collider('Genshin_Cabinet',names('DISPLAY | full back','DISPLAY | substantial shelf','DISPLAY | canopy','DISPLAY | vertical mullion'),math.radians(18),(8.05,3.6,0))
for o in source_objects:
    if 'tapered pot' in o.name and 'miniature' not in o.name:collider('Planter_'+o.name.split(' |')[0],[o])
for name,objects in reading_colliders.items():collider(name,objects)
lamp_collider=next(c for c in colliders if c['name']=='Reading_Floor_Lamp')
lamp_collider.update(center=[-3.43,.99,7.1],size=[.45,1.90,.45])

seats=[]
def seat(id,label,ob,facing,collider_name,approach_offset):
    lo,hi=world_bounds([ob]);center=(lo+hi)*.5
    # Use the cushion crown as the seating surface, with 8 mm compression.
    top=hi.z-.008
    position=godot(Vector((center.x,center.y,top)))
    approach=[round(position[0]+approach_offset[0],5),.04,round(position[2]+approach_offset[1],5)]
    # The seated graduate was authored on a shallow bench. Deeper cushions
    # need the pelvis nearer their front edge so knees and calves clear them.
    pose_forward=.24 if id.startswith('reading_') else (.28 if id.startswith('sofa_left_') else (.26 if id.startswith('sofa_return_') else (.66 if id=='sofa_corner' else .06)))
    seats.append(dict(id=id,label=label,position=position,surface_height=round(top,5),facing=facing,approach=approach,collider_name=collider_name,pose_forward=pose_forward))
for idx in range(3):
    seat('sofa_left_'+str(idx+1),'沙發',bpy.data.objects['LOUNGE_Left_seat_%02d'%idx],math.pi/2,'Sofa_Left_Run',(1.22,0))
    seat('sofa_return_'+str(idx+1),'沙發',bpy.data.objects['LOUNGE_Return_seat_%02d'%idx],math.pi,'Sofa_Return_Run',(0,-1.10))
seat('sofa_corner','沙發轉角',bpy.data.objects['LOUNGE_Corner_seat'],3*math.pi/4,'Sofa_Corner',(1.23,-.66))
for idx in range(1,4):
    seat('gaming_'+str(idx),'電競椅 '+str(idx),bpy.data.objects['GAMING | shaped seat '+str(idx)],-math.pi/2-math.radians(10),'Gaming_Chair_'+str(idx),(1.12,.12))
bench_seats=sorted([o for o in game_decor.objects if o.name.startswith('READING | bench tailored seat') and o.type=='MESH'],key=lambda o:o.name)
for idx,ob in enumerate(bench_seats,1):seat('reading_'+str(idx),'閱讀座 '+str(idx),ob,-math.pi/2,'Reading_Bench',(-1.23,0))

books=[]
for idx in range(1,14):
    ob=next(o for o in game_decor.objects if o.get('book_index')==idx)
    pivot=Vector(ob['interactive_pivot'])
    books.append(dict(id='book_%02d'%idx,title='書籍 %02d'%idx,node_name='BOOK_%02d'%idx,position=godot(pivot),color=ob.get('book_cover_color','#345c58'),rotation_y=-math.pi/2))

# Moving parts keep their own GLB parent instead of disappearing into material
# batches. The hinge nodes use true hinge-local vertices, ready for rotation.
cabinet_doors=[]
display_rotation=Matrix.Rotation(math.radians(18),3,'Z')
display_pivot=Vector((8.05,3.6,0))
for idx in range(6):
    suffix='' if idx==0 else '.%03d'%idx
    glass=bpy.data.objects['DISPLAY | glass door'+suffix]
    row,col=idx%2,idx//2
    base=.27+row*1.39;yy=col*1.8
    pivot=display_pivot+display_rotation@(Vector((5.60,yy+.795,base+.63))-Vector((6.1,1.8,0)))
    name='CABINET_DOOR_%02d'%(idx+1)
    for prefix in ['DISPLAY | glass door','DISPLAY | formed glass-door handle','DISPLAY | glass edge frame']:
        ob=bpy.data.objects[prefix+suffix];ob['interactive_root']=name;ob['interactive_pivot']=list(pivot)
    center=display_pivot+display_rotation@(Vector((5.605,yy,base+.63))-Vector((6.1,1.8,0)))
    approach=center+display_rotation@Vector((-1.0,0,0));approach.z=.04
    cabinet_doors.append(dict(id='cabinet_%02d'%(idx+1),node_name=name,hinge=godot(pivot),approach=godot(approach),position=godot(center),open_angle=-math.pi*.43))
computers=[]
gaming_rotation=Matrix.Rotation(math.radians(-10),3,'Z')
for idx in range(1,4):
    for ob in source_objects:
        if ob.name.startswith('GAMING %d | luminous screen'%idx):
            ob['interactive_root']='SCREEN_%02d'%idx;ob['interactive_pivot']=[0,0,0]
    # Interface lines also belong to the corresponding display, not the room.
    yy=[.35,2,3.65][idx-1]
    for sub in range(3):
        n=(idx-1)*3+sub;suffix='' if n==0 else '.%03d'%n
        ob=bpy.data.objects['GAMING | blue interface lines'+suffix]
        ob['interactive_root']='SCREEN_%02d'%idx;ob['interactive_pivot']=[0,0,0]
    p=Vector((-7.95,3.6,0))+gaming_rotation@(Vector((-5.20,yy,.04))-Vector((-5.7,2,0)))
    chair_seat=next(s for s in seats if s['id']=='gaming_'+str(idx))
    # Keep the seat's straight-ahead aisle anchor for sitting; the computer
    # power interaction lives 0.63 m to its side, so both E actions are reachable.
    computer_approach=[round(chair_seat['approach'][0]-.10,5),.04,round(chair_seat['approach'][2]+.62,5)]
    computers.append(dict(id='computer_%02d'%idx,node_name='SCREEN_%02d'%idx,position=godot(p),approach=computer_approach,collider_name='Gaming_Desk',label='電腦 '+str(idx)))

layout={
 'coordinate_convention':'GLB/Godot Y-up; [Blender x, Blender z, -Blender y]; distances metres; collider rotation_y radians',
 'floor_y':.0375,'room_bounds':{'min':[-10,.0375,-9],'max':[10,3.4,9]},
 'spawn':[0,.09,6.2],'exit':[0,.04,8.48],'device':[.65,.034,-.8],
 'device_collision':{'center':[.65,.30,-.8],'radius':.93,'height':.55},
 'portal_opening':{'center':[0,1.67,9.08],'size':[2.44,3.2,.4]},
 'room_display_name':'練功區','device_count':1,'empty_display_sockets':6,'colliders':colliders,
 'seats':seats,'books':books,'bookcase':{'position':[8.10,.04,1.95],'radius':1.6,'label':'按 E 選取書籍閱讀'},
 'reading_spot':[7.4,.04,3.1],'cabinet_doors':cabinet_doors,'computers':computers,'decor_targets':decor_targets,
 'projector_optics':{'emitter':[.65,.527,-.8],'beam_bottom_y':.529,'screen_bottom_y':1.384,'screen_top_y':2.584,'screen_z':-.835,'screen_center_x':.65,'screen_bottom_half_width':.8,'screen_top_half_width':1.1},
 'style_palette':{'plaster':'dedcc7','limestone':'b4b6a3','oak':'b39673','teal':'345c58','wordking_accent':'d4cd84'},
}
(DEST/'layout.json').write_text(json.dumps(layout,ensure_ascii=False,indent=2),encoding='utf-8')
scene['layout_metadata']=str(DEST/'layout.json')
if '--layout-only' in sys.argv:
    print('LAYOUT_ONLY_COMPLETE',flush=True)
    raise SystemExit(0)
enclosure=next(c for c in scene.collection.children if c.name.startswith('13'))
enclosure.hide_viewport=True;enclosure.hide_render=True
scene['editable_preview']='Cutaway overview; enable collection 13 for enclosed view. GLB includes enclosure.'
master_path=OUT/'WordKing_TrainingRoom_Game.blend'
backup=OUT/'WordKing_TrainingRoom_Game_before_interactions_20260929.blend'
if master_path.exists() and not backup.exists():shutil.copy2(master_path,backup)
bpy.ops.wm.save_as_mainfile(filepath=str(master_path))
enclosure.hide_viewport=False;enclosure.hide_render=False
print('GAME_MASTER_SAVED',flush=True)

# Export duplicate: procedural microtexture has been replaced with a compact
# portable palette. The custom cushion topology is only reduced on this copy.
export_col=bpy.data.collections.new('EXPORT_ONLY');scene.collection.children.link(export_col)
groups=defaultdict(lambda:{'verts':[],'faces':[],'smooth':[],'uvs':[],'authored_uv':False})
interactive_roots={}
audit=[]
omitted=[]
deps=bpy.context.evaluated_depsgraph_get()

def zone(o):
    c=next((c for c in o.users_collection if c!=export_col),None)
    z={'01':'Architecture','02':'Inlays','03':'Backdrop','04':'Gaming','05':'Lounge','06':'Display','07':'Device','08':'Portal','09':'Plants','13':'Enclosure','14':'Woodwork'}.get(c.name[:2] if c else '','Decor')
    return z

for o in list(scene.objects):
    if o.type not in {'MESH','CURVE','FONT'}:continue
    if any(c.name.startswith('12') for c in o.users_collection):continue
    if 'Soft_carpet_pile' in o.name:
        omitted.append(o.name);continue
    if 'saddle stitches' in o.name:
        # These sub-mm lines are preserved in the master; the broad shaped
        # welt remains modeled for the third-person game camera.
        omitted.append(o.name);continue
    duplicate=o.copy();duplicate.data=o.data.copy();export_col.objects.link(duplicate)
    duplicate.parent=None;duplicate.matrix_world=o.matrix_world.copy()
    if duplicate.type=='CURVE':duplicate.data.bevel_resolution=0
    if duplicate.type=='FONT':duplicate.data.resolution_u=3
    for mod in duplicate.modifiers:
        if mod.type=='BEVEL':mod.segments=min(mod.segments,2)
    if o.get('upholstered'):
        dec=duplicate.modifiers.new('Game duplicate: retain soft silhouette','DECIMATE');dec.ratio=.42
    elif 'curved leaves' in o.name:
        dec=duplicate.modifiers.new('Game duplicate: broad leaf silhouette','DECIMATE');dec.ratio=.25
    elif 'continuous velvet pleats' in o.name:
        dec=duplicate.modifiers.new('Game duplicate: broad textile folds','DECIMATE');dec.ratio=.40
    bpy.context.view_layer.update()
    evaluated=duplicate.evaluated_get(deps)
    me=bpy.data.meshes.new_from_object(evaluated,preserve_all_data_layers=False,depsgraph=deps)
    world=duplicate.matrix_world
    vs=[tuple(world@v.co) for v in me.vertices]
    mats=list(me.materials)
    z=o.get('interactive_root') or zone(o)
    if o.get('interactive_root'):interactive_roots[z]=Vector(o['interactive_pivot'])
    triangle_count=sum(len(p.vertices)-2 for p in me.polygons)
    audit.append({'name':o.name,'zone':z,'triangles':triangle_count})
    material_faces=defaultdict(list)
    for p in me.polygons:material_faces[p.material_index].append(p)
    for index,polys in material_faces.items():
        mat=mats[index] if index<len(mats) and mats[index] else M['dark_teal']
        group=groups[(z,mat.name)]
        used=set(v for p in polys for v in p.vertices)
        offset=len(group['verts']);mapping={v:offset+i for i,v in enumerate(sorted(used))}
        group['verts'] += [vs[v] for v in sorted(used)]
        group['faces'] += [tuple(mapping[v] for v in p.vertices) for p in polys]
        group['smooth'] += [p.use_smooth for p in polys]
        if o.get('preserve_authored_uv'):
            assert me.uv_layers.active is not None
            group['authored_uv']=True
            group['uvs'] += [[tuple(me.uv_layers.active.data[li].uv) for li in p.loop_indices] for p in polys]
        else:group['uvs'] += [None for p in polys]
    bpy.data.meshes.remove(me);bpy.data.objects.remove(duplicate,do_unlink=True)

export_objects=[]
root_nodes={}
for name,pivot in interactive_roots.items():
    ob=bpy.data.objects.new(name,None);export_col.objects.link(ob);ob.location=pivot
    ob['interactive_kind']=name.split('_')[0];root_nodes[name]=ob;export_objects.append(ob)
for (z,mat_name),g in groups.items():
    name='SM_'+z+'_'+mat_name.removeprefix('MAT_Game_')
    me=bpy.data.meshes.new(name);me.from_pydata(g['verts'],[],g['faces']);me.update()
    me.materials.append(bpy.data.materials[mat_name])
    for p,smooth in zip(me.polygons,g['smooth']):p.use_smooth=smooth
    uv=me.uv_layers.new(name='UVMap')
    for p,authored_uvs in zip(me.polygons,g['uvs']):
        major=max(range(3),key=lambda i:abs(p.normal[i]));axes=[i for i in range(3) if i!=major]
        for idx,li in enumerate(p.loop_indices):
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=authored_uvs[idx] if authored_uvs else (co[axes[0]]*.25,co[axes[1]]*.25)
    bm=bmesh.new();bm.from_mesh(me)
    bmesh.ops.triangulate(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
    ob=bpy.data.objects.new(name,me);export_col.objects.link(ob)
    if z in root_nodes:
        pivot=interactive_roots[z]
        for vertex in me.vertices:vertex.co-=pivot
        ob.parent=root_nodes[z]
    ob['training_room_zone']=z;export_objects.append(ob)

for marker in [o for o in source_objects if o.get('device_type') or o.get('intentionally_empty')]:
    cp=marker.copy();export_col.objects.link(cp);cp.parent=None;cp.matrix_world=marker.matrix_world.copy()
    cp.name=('ANCHOR_WordKing_Device' if marker.get('device_type') else 'SOCKET_Genshin_'+str(len(export_objects)))
    export_objects.append(cp)

bpy.ops.object.select_all(action='DESELECT')
for o in export_objects:o.hide_set(False);o.select_set(True)
bpy.context.view_layer.objects.active=export_objects[0]
path=DEST/'wordking_training_room.glb'
bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,
    export_apply=False,export_yup=True,export_materials='EXPORT',
    export_normals=True,export_tangents=True,export_texcoords=True,
    export_animations=False,export_skins=False,export_morph=False,
    export_cameras=False,export_lights=False,export_extras=True)

report={'editable_master':str(OUT/'WordKing_TrainingRoom_Game.blend'),
 'glb':str(path),'glb_bytes':path.stat().st_size,
 'export_mesh_objects':sum(o.type=='MESH' for o in export_objects),
 'material_count':len(set(m.name for o in export_objects if o.type=='MESH' for m in o.data.materials)),
 'triangles':sum(row['triangles'] for row in audit),'source_objects_batched':len(audit),
 'original_upholstery_preserved_in_master':22,'export_upholstery_ratio':.42,
 'omitted_microgeometry':omitted,'materials':'Standard Principled PBR palette plus embedded public-domain Starry Night canvas texture',
 'uv_validation':'All exported mesh surfaces have UVMap and tangents; original painting 0-1 UVs preserved through batching and triangulation',
 'interactive_root_count':len(root_nodes),'seat_count':len(seats),'book_count':len(books),
 'engine_validation':'Pending parent Godot gameplay and visual checks',
 'largest_objects':sorted(audit,key=lambda x:-x['triangles'])[:25]}
(OUT/'validation'/'game_export_report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print('GAME_EXPORT_COMPLETE '+json.dumps({k:report[k] for k in ['glb_bytes','triangles','export_mesh_objects','material_count']}),flush=True)
