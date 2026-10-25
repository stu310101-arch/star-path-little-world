"""Run in Blender with the supplied Furina-Holding-Splendor.blend open.

Keep the editable rig/pose in a separate .blend; bake only the exhibit copy.
The display is a static figure, not a replacement for the playable avatar.
"""
from pathlib import Path
import bpy
from mathutils import Vector, Matrix
import json

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'art/FurinaDisplay'
OUT = ROOT / 'game/assets/exhibits/furina'
ART.mkdir(parents=True, exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
rig = bpy.data.objects['Furina_Rig']
source = bpy.data.filepath
bpy.ops.wm.save_as_mainfile(filepath=str(ART / 'Furina-Holding-Splendor.blend'), copy=True)
deps = bpy.context.evaluated_depsgraph_get()
collection = bpy.data.collections.new('COL_Furina_Display_Export')
bpy.context.scene.collection.children.link(collection)
copies = []
materials = {}
for original in list(bpy.context.scene.objects):
    if original.type != 'MESH' or original.parent != rig:
        continue
    evaluated = original.evaluated_get(deps)
    mesh = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=deps)
    mesh.transform(evaluated.matrix_world)
    is_sword = original.parent_type == 'BONE'
    obj = bpy.data.objects.new('SM_Splendor' if is_sword else 'SM_Furina_' + original.name[:2], mesh)
    collection.objects.link(obj)
    for index, source_mat in enumerate(list(mesh.materials)):
        tex = next(n for n in source_mat.node_tree.nodes if n.type == 'TEX_IMAGE')
        src = next(n for n in source_mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
        key = (tex.image.name, is_sword)
        if key not in materials:
            mat = bpy.data.materials.new('MAT_Furina_' + str(len(materials)))
            mat.use_nodes = True
            mat.use_backface_culling = False
            p = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
            t = mat.node_tree.nodes.new('ShaderNodeTexImage')
            t.image = tex.image
            mat.node_tree.links.new(t.outputs['Color'], p.inputs['Base Color'])
            mat.node_tree.links.new(t.outputs['Color'], p.inputs['Emission Color'])
            if not is_sword:
                mat.node_tree.links.new(t.outputs['Alpha'], p.inputs['Alpha'])
            for field in ['Metallic', 'Roughness', 'Emission Strength']:
                p.inputs[field].default_value = src.inputs[field].default_value
            materials[key] = mat
        mesh.materials[index] = materials[key]
    copies.append(obj)

points = [v.co for obj in copies for v in obj.data.vertices]
lo = Vector(tuple(min(v[i] for v in points) for i in range(3)))
hi = Vector(tuple(max(v[i] for v in points) for i in range(3)))
factor = 1.12 / (hi.z - lo.z)
center = Vector(((lo.x+hi.x)/2, (lo.y+hi.y)/2, lo.z))
for obj in copies:
    for v in obj.data.vertices:
        v.co = (v.co - center) * factor
    obj.data.update()
bpy.ops.object.select_all(action='DESELECT')
body = [o for o in copies if o.name != 'SM_Splendor']
sword = next(o for o in copies if o.name == 'SM_Splendor')
for obj in body:
    obj.select_set(True)
bpy.context.view_layer.objects.active = body[0]
bpy.ops.object.join()
body[0].name = 'SM_Furina_Display'
export_objects = [body[0], sword]
for obj in export_objects:
    obj.select_set(True)
report = {'source': source, 'height_m': 1.12, 'scale': factor,
          'pose': 'Supplied right-hand Splendor pose, evaluated without changes',
          'bounds_m': list((hi-lo)*factor), 'materials': len(materials),
          'meshes': [{'name': o.name, 'triangles': sum(len(p.vertices)-2 for p in o.data.polygons),
                      'uv_layers': len(o.data.uv_layers)} for o in export_objects],
          'textures': [{'name': m.node_tree.nodes.get('Image Texture').image.name,
                        'packed': bool(m.node_tree.nodes.get('Image Texture').image.packed_file)} for m in materials.values()],
          'optimization': 'Static evaluated mesh; no runtime skeleton; identical material slots merged. Godot generates mesh LODs. Source face, fingers, UVs and sword detail retained.'}
bpy.ops.export_scene.gltf(filepath=str(OUT/'furina_splendor.glb'), export_format='GLB',
                          use_selection=True, export_animations=False, export_yup=True)
(ART/'export-report.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(report, ensure_ascii=False))
