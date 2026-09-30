"""Author smooth, separate river-worn stones with outward normals.

Run this in a fresh Blender background process, or import build_bank_stones()
from the ecology asset builder. Other ecological assets are not regenerated.
"""
import bpy
import bmesh
import json
import math
import shutil
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]


def build_bank_stones():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    material = bpy.data.materials.new('River stone | muted warm mineral')
    material.use_nodes = True
    principled = material.node_tree.nodes.get('Principled BSDF')
    principled.inputs['Roughness'].default_value = .93
    principled.inputs['Specular IOR Level'].default_value = .16
    colors = material.node_tree.nodes.new('ShaderNodeVertexColor')
    colors.layer_name = 'StoneMineral'
    material.node_tree.links.new(colors.outputs['Color'], principled.inputs['Base Color'])
    vertices, faces, vertex_colors, uvs = [], [], [], []
    # A loose triangular composition leaves each stone's silhouette readable.
    # Low-frequency shaping describes erosion without the former spiked ridges.
    stones = [
        ((-.48, .16, -.015), (.51, .37, .42), -.22, (.35, .37, .33)),
        ((.40, .18, -.025), (.37, .31, .32), .46, (.40, .405, .355)),
        ((.02, -.36, -.025), (.28, .23, .205), -.75, (.31, .335, .315)),
    ]
    for number, (center, radii, yaw, color) in enumerate(stones):
        center = Vector(center)
        rings = []
        for j in range(1, 12):
            theta = math.pi*j/12
            ring = []
            for i in range(24):
                phi = math.tau*i/24
                erosion = 1 + .035*math.sin(phi*3 + number) * math.sin(theta)**2 + .018*math.cos(theta*3 + phi*2)
                x = math.sin(theta)*math.cos(phi)*radii[0]*erosion
                y = math.sin(theta)*math.sin(phi)*radii[1]*erosion
                z = math.cos(theta)*radii[2]*erosion
                p = center + Vector((x*math.cos(yaw)-y*math.sin(yaw), x*math.sin(yaw)+y*math.cos(yaw), z))
                ring.append(len(vertices))
                vertices.append(tuple(p))
                mineral = .975 + .025*math.sin(phi*2 + theta*2 + number)
                vertex_colors.append(tuple(c*mineral for c in color)+(1,))
                uvs.append((i/24, j/12))
            rings.append(ring)
        north = len(vertices)
        vertices.append(tuple(center+Vector((0,0,radii[2]))))
        vertex_colors.append((*color,1)); uvs.append((.5,0))
        south = len(vertices)
        vertices.append(tuple(center-Vector((0,0,radii[2]))))
        vertex_colors.append((*color,1)); uvs.append((.5,1))
        for i in range(24):
            faces.append((north,rings[0][i],rings[0][(i+1)%24]))
            faces.append((south,rings[-1][(i+1)%24],rings[-1][i]))
        for j in range(len(rings)-1):
            for i in range(24):
                faces.append((rings[j][i],rings[j+1][i],rings[j+1][(i+1)%24],rings[j][(i+1)%24]))
    mesh = bpy.data.meshes.new('Rounded river stones | three closed shells')
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    # Correct outward winding is essential. The previous asset's sphere rings
    # faced inward, causing the concave-looking crushed-metal lighting.
    bm = bmesh.new(); bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bad_edges = sum(not edge.is_manifold for edge in bm.edges)
    volume = bm.calc_volume(signed=True)
    bm.to_mesh(mesh); bm.free()
    assert bad_edges == 0 and volume > 0
    obj = bpy.data.objects.new('GEO-River worn separate bank stones', mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(material)
    color_layer = mesh.color_attributes.new(name='StoneMineral', type='FLOAT_COLOR', domain='POINT')
    for index, rgba in enumerate(vertex_colors):
        color_layer.data[index].color = rgba
    uv_layer = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        for loop_id in polygon.loop_indices:
            uv_layer.data[loop_id].uv = uvs[mesh.loops[loop_id].vertex_index]
    obj['design'] = 'Three separate river-worn stones; grounded, compact, outward normals'
    obj['surface_origin'] = 'Lower halves intentionally buried beneath authored river bank'
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    master = ROOT/'art/Ecology/bank_stones.blend'
    runtime = ROOT/'game/assets/ecology/bank_stones.glb'
    archive = ROOT/'art/Ecology/archive/bank_stones_spiky_v01.blend'
    if master.exists() and not archive.exists():
        archive.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(master, archive)
    bpy.ops.wm.save_as_mainfile(filepath=str(master))
    bpy.ops.export_scene.gltf(filepath=str(runtime), export_format='GLB', use_selection=True, export_animations=False, export_yup=True)
    report = {'asset':'bank_stones','vertices':len(vertices),'triangles':1584,'closed_shells':3,'nonmanifold_edges':bad_edges,'signed_volume':volume,'master':str(master),'runtime':str(runtime)}
    (ROOT/'art/Ecology/bank-stones-revision.json').write_text(json.dumps(report,indent=2),encoding='utf8')
    print('BANK_STONES_AUTHORED', json.dumps(report))
    return report


if __name__ == '__main__':
    build_bank_stones()
