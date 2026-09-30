"""Structural check of the emitted game room, independent of Blender's exporter."""
from pathlib import Path
import json, struct, math

root=Path(__file__).resolve().parents[1]
path=root/'game/assets/training_room/wordking_training_room.glb'
raw=path.read_bytes()
magic,version,length=struct.unpack_from('<III',raw)
assert magic==0x46546c67 and version==2 and length==len(raw)
json_length,json_type=struct.unpack_from('<II',raw,12)
assert json_type==0x4e4f534a
doc=json.loads(raw[20:20+json_length])
nodes=doc['nodes'];meshes=doc['meshes'];materials=doc['materials']
markers=[n for n in nodes if n.get('name','').startswith('SOCKET_Genshin_')]
device=[n for n in nodes if n.get('name')=='ANCHOR_WordKing_Device']
assert len(markers)==6 and len(device)==1
primitives=[p for m in meshes for p in m['primitives']]
for p in primitives:
    assert {'POSITION','NORMAL','TEXCOORD_0','TANGENT'} <= set(p['attributes'])
    assert p.get('mode',4)==4
    assert doc['accessors'][p['indices']]['count']%3==0
assert not doc.get('cameras')
assert len(doc.get('images',[]))==1
assert all('bufferView' in image and 'uri' not in image for image in doc['images'])
assert all(m['name'].startswith('MAT_Game_') for m in materials)
counts={key:sum(doc['accessors'][p[key]]['count']//3 for p in primitives) for key in ['indices']}
layout=json.loads((path.parent/'layout.json').read_text(encoding='utf-8'))
collider_names={c['name'] for c in layout['colliders']}
assert {'Sofa_Left_Run','Sofa_Return_Run','Coffee_Table','Side_Table',
        'Gaming_Desk','Genshin_Cabinet','Reading_Bookcase','Reading_Bench',
        'Reading_Bench_Back','Reading_Bench_Canopy','Reading_Painting','Sofa_Corner','Welcome_Console','Reading_Floor_Lamp'} <= collider_names
assert len([c for c in layout['colliders'] if c['name'].startswith('Gaming_Chair')])==3
assert len([c for c in layout['colliders'] if c['name'].startswith('Planter_')])==5
assert layout['room_display_name']=='練功區'
optical_names={'MAT_Game_'+suffix for suffix in ['Hologram_Beam','Hologram_Glass',
    'Hologram_Grid','Hologram_Cyan','Hologram_Type','Projector_Blue_Inlay']}
assert optical_names <= {m['name'] for m in materials}
for c in layout['colliders']:
    assert len(c['center'])==len(c['size'])==3 and all(v>0 for v in c['size'])
    if c['name'].startswith('Reading_') and c['name']!='Reading_Floor_Lamp':
        assert c['center'][0]-c['size'][0]/2 > 8.69
bench=next(c for c in layout['colliders'] if c['name']=='Reading_Bench')
assert .55 < bench['center'][1]+bench['size'][1]/2 < .59
names={n.get('name') for n in nodes}
assert {'BOOK_%02d'%i for i in range(1,14)}<=names
assert {'CABINET_DOOR_%02d'%i for i in range(1,7)}<=names
assert {'SCREEN_%02d'%i for i in range(1,4)}<=names
assert {'TEA_Cup','LAMP_Reading','DECOR_Console','DECOR_Botanical','PAINTING_StarryNight'}<=names
assert len(layout['seats'])==12 and len(layout['books'])==13
assert all(.55<seat['surface_height']<.59 for seat in layout['seats'])
for seat in layout['seats']:
    p=seat['approach']
    for collider in layout['colliders']:
        if collider['center'][1]-collider['size'][1]/2>1.64:continue
        x,z=p[0]-collider['center'][0],p[2]-collider['center'][2]
        angle=collider['rotation_y']
        local_x=math.cos(angle)*x-math.sin(angle)*z
        local_z=math.sin(angle)*x+math.cos(angle)*z
        dx=max(abs(local_x)-collider['size'][0]/2,0)
        dz=max(abs(local_z)-collider['size'][2]/2,0)
        assert dx*dx+dz*dz>.27**2,(seat['id'],'approach intersects',collider['name'])
assert len(layout['cabinet_doors'])==6 and len(layout['computers'])==3
assert all(n in names for n in [book['node_name'] for book in layout['books']])
painting=next(m for m in materials if m['name']=='MAT_Game_Starry_Night_Canvas')
assert 'baseColorTexture' in painting['pbrMetallicRoughness']
report={'glb_version':version,'file_bytes':len(raw),'mesh_nodes':len(meshes),
    'material_count':len(materials),'render_triangles':counts['indices'],
    'all_primitives_have_normals_uv_and_tangents':True,'external_textures':0,
    'embedded_images':1,'interactive_books':len(layout['books']),'usable_seats':len(layout['seats']),
    'animated_cabinet_doors':6,'individual_computer_screens':3,
    'device_anchors':device,'display_socket_count':len(markers),
    'furniture_colliders':len(layout['colliders']),
    'room_display_name':layout['room_display_name'],
    'projector_optics_separate_materials':sorted(optical_names),
    'engine_validation':'Parent performs Godot traversal, materials, collision and visual verification.'}
target=root/'art/TrainingRoom/validation/game_glb_validation.json'
target.write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps(report,ensure_ascii=False))
