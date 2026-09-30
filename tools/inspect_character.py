import bpy, json
from mathutils import Vector

report = {"blender": bpy.app.version_string, "objects": [], "materials": [], "actions": []}
for obj in bpy.data.objects:
    item = {"name": obj.name, "type": obj.type, "location": list(obj.location), "rotation": list(obj.rotation_euler), "scale": list(obj.scale), "parent": obj.parent.name if obj.parent else None}
    if obj.type == 'MESH':
        item.update(vertices=len(obj.data.vertices), polygons=len(obj.data.polygons), materials=[m.name for m in obj.data.materials], groups=[g.name for g in obj.vertex_groups], modifiers=[{"name":m.name,"type":m.type,"object":m.object.name if m.type=='ARMATURE' and m.object else None} for m in obj.modifiers])
        item['bounds'] = [list(obj.matrix_world @ Vector(c)) for c in obj.bound_box]
        item['material_regions'] = []
        for i, mat in enumerate(obj.data.materials):
            inds = {v for p in obj.data.polygons if p.material_index == i for v in p.vertices}
            coords = [obj.matrix_world @ obj.data.vertices[v].co for v in inds]
            if coords:
                item['material_regions'].append({'name':mat.name, 'faces':sum(p.material_index==i for p in obj.data.polygons), 'bounds':[[min(c[k] for c in coords) for k in range(3)], [max(c[k] for c in coords) for k in range(3)]]})
    if obj.type == 'ARMATURE':
        item['bones'] = [{"name":b.name,"head":list(b.head_local),"tail":list(b.tail_local),"parent":b.parent.name if b.parent else None} for b in obj.data.bones]
        item['pose_position'] = obj.data.pose_position
        item['animation'] = obj.animation_data.action.name if obj.animation_data and obj.animation_data.action else None
    report['objects'].append(item)
for mat in bpy.data.materials:
    report['materials'].append({'name':mat.name,'color':list(mat.diffuse_color), 'nodes':[(n.name, n.type) for n in mat.node_tree.nodes] if mat.node_tree else []})
for action in bpy.data.actions:
    report['actions'].append({'name':action.name,'range':list(action.frame_range)})
report['frame'] = bpy.context.scene.frame_current
report['render_engine'] = bpy.context.scene.render.engine
print('CHARACTER_REPORT_START')
print(json.dumps(report, indent=2))
print('CHARACTER_REPORT_END')
