import bpy, json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def vertex_signature(obj, vertex):
    return (tuple(vertex.co), tuple(sorted((obj.vertex_groups[g.group].name, g.weight) for g in vertex.groups)))

def face_signature(obj, polygon):
    return tuple(sorted(tuple(obj.data.vertices[i].co) for i in polygon.vertices))

def inspect(obj):
    sums = [sum(g.weight for g in v.groups) for v in obj.data.vertices]
    return {'name': obj.name, 'vertices': len(obj.data.vertices), 'faces': len(obj.data.polygons),
        'unweighted': sum(len(v.groups) == 0 for v in obj.data.vertices),
        'bad_weight_sum': sum(abs(value - 1) > 1e-4 for value in sums),
        'weight_sum_min': min(sums), 'weight_sum_max': max(sums),
        'degenerate_faces': sum(p.area < 1e-9 for p in obj.data.polygons)}

def images():
    report = []
    user_map = bpy.data.user_map()
    for image in bpy.data.images:
        refs = []
        for texture in bpy.data.textures:
            if getattr(texture, 'image', None) == image:
                refs.append({'kind': 'texture', 'name': texture.name, 'users': texture.users})
        for material in bpy.data.materials:
            if material.node_tree:
                for node in material.node_tree.nodes:
                    if getattr(node, 'image', None) == image:
                        refs.append({'kind': 'material_node', 'material': material.name, 'node': node.name, 'material_users': material.users})
        report.append({'name': image.name, 'filepath': image.filepath, 'users': image.users,
            'fake_user': image.use_fake_user, 'packed': bool(image.packed_file), 'references': refs,
            'id_users': [{'type': user.bl_rna.identifier, 'name': user.name} for user in user_map.get(image, set())],
            'editor_users': [{'screen': screen.name, 'space': space.type} for screen in bpy.data.screens for area in screen.areas for space in area.spaces if getattr(space, 'image', None) == image]})
    return report

original = bpy.data.objects['BaseHuman']
source_vertices = Counter(vertex_signature(original, v) for v in original.data.vertices)
source_bad_faces = Counter(face_signature(original, p) for p in original.data.polygons if p.area < 1e-9)
report = {'source_file': bpy.data.filepath, 'source_body': inspect(original), 'source_images': images()}
bpy.ops.wm.open_mainfile(filepath=str(ROOT / 'art' / 'Graduate' / 'Male_Graduate.blend'), load_ui=False)
graduate = next(o for o in bpy.data.objects if o.type == 'MESH' and o.name.startswith('Graduate | original'))
new_vertices = Counter(vertex_signature(graduate, v) for v in graduate.data.vertices)
new_bad_faces = Counter(face_signature(graduate, p) for p in graduate.data.polygons if p.area < 1e-9)
report['graduate_body'] = inspect(graduate)
report['graduate_vertices_not_identical_to_source_position_and_weights'] = sum((new_vertices - source_vertices).values())
report['graduate_degenerate_faces_not_present_in_source'] = sum((new_bad_faces - source_bad_faces).values())
report['graduate_images'] = images()
(ROOT / 'tools' / 'qa-source-temp.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('SOURCE_QA_RESULT', json.dumps(report))
