"""Preserve Kenney originals; assign a brick-red roof material in Blender."""
import bpy, json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'game/assets/kenney/suburban-edited'; OUT.mkdir(exist_ok=True)
MASTER=ROOT/'art/RedRoofHomes'; MASTER.mkdir(exist_ok=True)
report=[]
for letter in ['b','f','a','c','d','e']:
    bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
    bpy.ops.import_scene.gltf(filepath=str(ROOT/f'game/assets/kenney/suburban/Models/GLB format/building-type-{letter}.glb'))
    red=bpy.data.materials.new('Roof • brick red'); red.diffuse_color=(.46,.095,.065,1); red.use_nodes=True
    bs=red.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=red.diffuse_color; bs.inputs['Roughness'].default_value=.86
    count=0; samples=[]
    for obj in list(bpy.context.scene.objects):
        if obj.type!='MESH': continue
        mesh=obj.data; index=len(mesh.materials); mesh.materials.append(red)
        for face in mesh.polygons:
            mat=mesh.materials[face.material_index]
            if mat==red or not mat.use_nodes: continue
            images=[n.image for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image]
            if not images or not mesh.uv_layers: continue
            uv=sum((mesh.uv_layers.active.data[k].uv for k in face.loop_indices),__import__('mathutils').Vector((0,0)))/len(face.loop_indices)
            image=images[0]; w,h=image.size; x=min(w-1,max(0,int(uv.x*w))); y=min(h-1,max(0,int(uv.y*h)))
            px=tuple(image.pixels[(y*w+x)*4:(y*w+x)*4+3]); samples.append(px)
            # Palette green uniquely identifies the original roof surfaces,
            # including sloping faces, gables and eaves. Windows/walls retain UVs.
            if px[1]>px[0]*1.12 and px[1]>px[2]*1.08:
                face.material_index=index; count+=1
    assert count>0,(letter,set(samples))
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.wm.save_as_mainfile(filepath=str(MASTER/f'house-{letter}-red.blend'))
    bpy.ops.export_scene.gltf(filepath=str(OUT/f'house-{letter}-red.glb'),export_format='GLB',use_selection=True)
    report.append(dict(model=letter,roof_faces=count))
(OUT/'roof-report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('RED_ROOFS_OK',json.dumps(report))
