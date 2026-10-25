"""Editable export LODs for authored fern/reed beds. Original assets stay intact."""
from pathlib import Path
import json
import bpy

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/assets/vegetation_rebuilt'
MASTER = ROOT / 'art/Vegetation'
MASTER.mkdir(exist_ok=True, parents=True)
report = {}
for kind, ratio in [('fern', .26), ('cattail', .42)]:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'game/assets/ecology' / (kind + '.glb')))
    count_before = 0
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        obj.data.calc_loop_triangles()
        count_before += len(obj.data.loop_triangles)
        obj.name = 'SM_' + kind + '_bed_LOD'
        modifier = obj.modifiers.new('Fewer segments along each curved blade', 'DECIMATE')
        modifier.ratio = ratio
    bpy.context.view_layer.update()
    count_after = 0
    for obj in bpy.context.scene.objects:
        if obj.type != 'MESH':
            continue
        mesh = obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh()
        mesh.calc_loop_triangles()
        count_after += len(mesh.loop_triangles)
        obj.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear()
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER / (kind + '_beds.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT / (kind + '.glb')), export_format='GLB', export_apply=True, export_animations=False)
    report[kind] = {'original_triangles': count_before, 'bed_lod_triangles': count_after, 'source': str(MASTER / (kind + '_beds.blend')), 'method': 'Live decimation export copy; original botanical mesh and vertex colours preserved'}
(OUT / 'understory-manifest.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
print('UNDERSTORY_LOD', json.dumps(report))
