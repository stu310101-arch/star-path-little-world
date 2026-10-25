"""Export reduced-density art copies; never save or overwrite the source .blend files.

Blender --background --factory-startup --python tools/export_low_art.py
Godot's low-pack builder subsequently downsizes textures and packages these copies.
"""
import bpy,json,re,hashlib,sys,argparse
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art/LowResources/runtime_exports'
OUT.mkdir(parents=True,exist_ok=True)
parser=argparse.ArgumentParser()
parser.add_argument('--only',choices=['garden','admissions','counseling'])
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
REPORT=json.loads((OUT/'report.json').read_text(encoding='utf8')) if args.only and (OUT/'report.json').exists() else {}
MICRO=('SpineBand','BookPages','Perpend','BedJoint','RoofSeam','RoofReturnSeam','SoffitLinearJoint','DrainSlot','RoofTileRidge','LeafVein','WaterRibbon')

def skip(kind,ob):
 name=ob.name
 if kind=='garden':
  if name.startswith(('SM_LearningGrove_EastCabin','SM_Maker_East')):return 'secondary_building'
  if any(token in name for token in MICRO):return 'micro_detail'
  # Tree meshes share suffixes and location: retain entire trees, never half a crown.
  if re.match(r'SM_(alder|birch|pine|willow)_',name):
   if int(name.rsplit('.',1)[1])%3==1 if '.' in name else False:return 'repeated_tree'
  if any(token in name for token in ('Flowers','FlowerDrift','PathFlowers','LakeReed','FarBankReeds')):
   suffix=int(name.rsplit('.',1)[1]) if '.' in name else 0
   if suffix%3==1:return 'repeated_plant'
 elif kind=='counseling':
  if name.startswith('SM_WestSillPlantSmall'):return 'extra_small_plant'
  book=re.match(r'SM_(?:HighOneShelfBook|HighThreeShelfBook|EastWallBook)_(\d+)(?:_|\.|$)',name)
  if book and int(book.group(1))%3==1:return 'repeated_book'
  if any(token in name for token in ('_SeatSeam','RugStitchLine','_SpineLabel','_Stitch','_PageLine')):return 'micro_detail'
 else:
  if name.startswith(('SM_Passport_Fern','SM_Special_Plant')):return 'extra_pot'
  if any(token in name for token in ('_CaseVent','_FileLabel','BrochureText','_Workstation_Key','_Motif')):return 'micro_detail'
  if '_File' in name:
   suffix=int(name.rsplit('.',1)[1]) if '.' in name else 0
   if suffix%2:return 'repeated_file'
  if 'Exterior' in ' '.join(c.name for c in ob.users_collection):
   # Keep the architecture outside the windows, reduce repeated vegetation only.
   if 'Leaf' in name or 'Crown' in name:
    suffix=int(name.rsplit('.',1)[1]) if '.' in name else 0
    if suffix%3==1:return 'exterior_plant'
 return ''

def palette_material():
 mat=bpy.data.materials.new('MAT_Low_AuthoredPalette');mat.use_nodes=True
 bsdf=mat.node_tree.nodes.get('Principled BSDF')
 color=mat.node_tree.nodes.new('ShaderNodeVertexColor');color.layer_name='LowPalette'
 mat.node_tree.links.new(color.outputs['Color'],bsdf.inputs['Base Color'])
 bsdf.inputs['Roughness'].default_value=.8
 return mat

def compact(mesh,palette,kind):
 previous=mesh.color_attributes.active_color
 original=[tuple(previous.data[loop.index if previous.domain=='CORNER' else loop.vertex_index].color) for loop in mesh.loops] if previous else []
 colors=mesh.color_attributes.new(name='LowPalette',type='FLOAT_COLOR',domain='CORNER')
 for poly in mesh.polygons:
  mat=mesh.materials[poly.material_index] if mesh.materials else None
  bsdf=next((n for n in mat.node_tree.nodes if n.type=='BSDF_PRINCIPLED'),None) if mat and mat.use_nodes else None
  textured=bool(bsdf and bsdf.inputs['Base Color'].is_linked)
  tone=tuple(bsdf.inputs['Base Color'].default_value) if bsdf and not textured else (1,1,1,1)
  for index in poly.loop_indices:colors.data[index].color=original[index] if textured and original else tone
  preserve=kind=='counseling' and bsdf and (bsdf.inputs['Alpha'].default_value<.999 or bsdf.inputs['Emission Strength'].default_value>0)
  if not textured and not preserve:
   if palette.name not in mesh.materials:mesh.materials.append(palette)
   poly.material_index=mesh.materials.find(palette.name)
 for layer in list(mesh.color_attributes):
  if layer.name!='LowPalette':mesh.color_attributes.remove(layer)
 mesh.color_attributes.active_color=colors
 mesh.color_attributes.render_color_index=mesh.color_attributes.find('LowPalette')
 if mesh.uv_layers:
  mesh.uv_layers.active.name='UVMap'
  mesh.uv_layers.active.active_render=True
 mesh.update()

for kind,source in [('garden','DiscussionGarden/DiscussionGarden.blend'),('admissions','AdmissionsRoom/AdmissionsStudio.blend'),('counseling','CounselingRoom/CounselingRoom.blend')]:
 if args.only and kind!=args.only:continue
 source=ROOT/'art'/source
 before=hashlib.sha256(source.read_bytes()).hexdigest()
 bpy.ops.wm.open_mainfile(filepath=str(source))
 scene=bpy.context.scene
 prefixes={'garden':('COL_Zone_','COL_Garden'),'admissions':('COL_Studio_',),'counseling':('COL_Counseling_',)}[kind]
 collections=[c for c in bpy.data.collections if c.name.startswith(prefixes)]
 # Source modifiers stay editable on disk; evaluate a modest single-segment bevel.
 for collection in collections:
  for ob in collection.objects:
   for mod in ob.modifiers:
    if mod.type=='BEVEL':mod.segments=1
    if mod.type=='SUBSURF':mod.levels=min(mod.levels,1)
 deps=bpy.context.evaluated_depsgraph_get();deps.update()
 stats={'source_sha256':before,'removed':{},'retained_objects':0,'triangles':0,'groups':[],'removed_tree_positions':[]}
 outputs=[];palette=palette_material()
 for collection in collections:
  copies=[]
  for ob in list(collection.objects):
   if ob.type!='MESH':continue
   reason=skip(kind,ob)
   if reason:
    stats['removed'][reason]=stats['removed'].get(reason,0)+1
    if reason=='repeated_tree':
     at=ob.matrix_world.translation
     stats['removed_tree_positions'].append([at.x,at.z,-at.y])
    continue
   data=bpy.data.meshes.new_from_object(ob.evaluated_get(deps),preserve_all_data_layers=True,depsgraph=deps)
   if kind=='garden' and ob.get('botanical_low_mesh'):
    bpy.data.meshes.remove(data);data=bpy.data.meshes[ob['botanical_low_mesh']].copy()
   compact(data,palette,kind)
   cp=bpy.data.objects.new('LowCopy_'+ob.name,data);scene.collection.objects.link(cp);cp.matrix_world=ob.matrix_world.copy();copies.append(cp)
  if not copies:continue
  bpy.ops.object.select_all(action='DESELECT')
  for cp in copies:cp.select_set(True)
  bpy.context.view_layer.objects.active=copies[0]
  bpy.ops.object.join();joined=bpy.context.object
  # Furniture interaction resolves these exact chair names from the layout.
  joined.name=('SM_' if kind=='counseling' else 'SM_Low_')+collection.name.removeprefix('COL_')
  bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
  joined.data.calc_loop_triangles();stats['triangles']+=len(joined.data.loop_triangles)
  stats['retained_objects']+=len(copies);stats['groups'].append(joined.name);outputs.append(joined)
 bpy.ops.object.select_all(action='DESELECT')
 for ob in outputs:ob.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',use_selection=True,export_animations=False,export_cameras=False,export_lights=False,export_yup=True,export_apply=True,export_vertex_color='NAME',export_vertex_color_name='LowPalette',export_all_vertex_colors=False)
 assert hashlib.sha256(source.read_bytes()).hexdigest()==before
 REPORT[kind]=stats
(OUT/'report.json').write_text(json.dumps(REPORT,ensure_ascii=False,indent=2),encoding='utf8')
print('BALANCED_LOW_ART_READY',json.dumps({k:{'triangles':v['triangles'],'removed':v['removed']} for k,v in REPORT.items()}))
