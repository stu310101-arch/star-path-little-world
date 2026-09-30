"""Author the lake's small floating water-lily cluster in an isolated Blender CLI.

Six genuinely notched, cupped leaves, narrow geometric veins, a layered flower,
and a closed bud. Units are metres; Blender Z becomes Godot Y on GLB export.
The editable master keeps each leaf and petal separate. Only an export copy is
joined, with five untextured, double-sided PBR material slots and no colliders.

Usage: blender --background --factory-startup --python tools/author_water_lilies.py
Optional: -- --preview C:/absolute/task-preview.png
"""

import argparse
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
MASTER = ROOT / "art/Ecology/Water_Lilies.blend"
EXPORT = ROOT / "game/assets/ecology/water_lily.glb"
parser = argparse.ArgumentParser()
parser.add_argument("--preview")
args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = "METRIC"
scene.unit_settings.scale_length = 1.0
source = bpy.data.collections.new("Water lilies | editable source")
scene.collection.children.link(source)


def material(name, color, roughness):
    mat = bpy.data.materials.new("MAT-" + name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Specular IOR Level"].default_value = .22
    return mat


LEAF = material("water-lily-leaf-jade", (.075, .245, .092), .60)
VEIN = material("water-lily-vein-sage", (.18, .32, .13), .78)
IVORY = material("water-lily-petal-ivory", (.94, .84, .79), .75)
BLUSH = material("water-lily-petal-blush", (.73, .40, .49), .76)
GOLD = material("water-lily-stamen-gold", (.88, .52, .075), .73)


def mesh_object(name, vertices, faces, mat, smooth=True):
    mesh = bpy.data.meshes.new(name + " mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new("GEO-" + name, mesh)
    source.objects.link(obj)
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    return obj


def orient_xy(x, y, angle, center, z):
    return (center[0] + x * math.cos(angle) - y * math.sin(angle),
            center[1] + x * math.sin(angle) + y * math.cos(angle), z)


def leaf_pad(index, center, radius, angle, elevation):
    steps = 20
    notch = .25 + .025 * (index % 3)
    angles = [notch + (math.tau - 2 * notch) * k / steps for k in range(steps + 1)]

    def height(t, theta):
        return elevation + .003 * t + .010 * t ** 4 * (.6 + .4 * math.sin(theta * 3 + index))

    def point(t, theta, lift=0):
        r = radius * t * (1 + .023 * math.sin(5 * theta + index))
        return orient_xy(r * math.cos(theta), r * math.sin(theta) * .92,
                         angle, center, height(t, theta) + lift)

    # The wedge remains absent through both rings, producing a true V opening.
    vertices = [orient_xy(radius * .045, 0, angle, center, elevation)]
    for t in (.54, 1.0):
        vertices.extend(point(t, theta) for theta in angles)
    faces = []
    for k in range(steps):
        faces.append((0, 1 + k, 2 + k))
        faces.append((1 + k, 22 + k, 23 + k, 2 + k))
    # A thin perimeter and underside remain readable from shore-level cameras.
    boundary = [0, *range(22, 43)]
    bottom_start = len(vertices)
    vertices.extend((vertices[i][0], vertices[i][1], vertices[i][2] - .0025) for i in boundary)
    bottom_center = len(vertices)
    center_average = Vector((center[0], center[1], elevation - .0025))
    vertices.append(tuple(center_average))
    for k, top in enumerate(boundary):
        nxt = (k + 1) % len(boundary)
        faces.append((top, bottom_start + k, bottom_start + nxt, boundary[nxt]))
        # Fan follows the actual V contour; no solid disc fills the cut.
        faces.append((bottom_center, bottom_start + nxt, bottom_start + k))
    leaf = mesh_object(f"Leaf {index + 1:02d} | notched curved blade", vertices, faces, LEAF)
    leaf["water_surface_origin"] = True
    leaf["radius_m"] = radius
    vein_vertices, vein_faces = [], []
    for vein in range(7):
        theta = notch + .22 + (math.tau - 2 * notch - .44) * vein / 6
        rows = []
        for t, width in [(.13, .0012), (.54, .00085), (.91, .00022)]:
            pos = Vector(point(t, theta, .0009))
            side = Vector((-math.sin(theta + angle), math.cos(theta + angle), 0)) * width
            rows.append((len(vein_vertices), len(vein_vertices) + 1))
            vein_vertices.extend((tuple(pos - side), tuple(pos + side)))
        for a, b in zip(rows, rows[1:]):
            vein_faces.append((a[0], b[0], b[1], a[1]))
    mesh_object(f"Leaf {index + 1:02d} | fine radial veins", vein_vertices, vein_faces, VEIN)


# Unequal radii and independently directed notches avoid a stamped rosette.
for i, row in enumerate([
    ((-.23, -.13), .183, 3.40, .007),
    ((.145, -.19), .202, 5.00, .013),
    ((.31, .135), .168, .50, .009),
    ((.02, .31), .176, 1.70, .012),
    ((-.305, .20), .172, 2.10, .008),
    ((-.04, .055), .202, 4.00, .019),
]):
    leaf_pad(i, *row)


def petal(name, center, angle, length, width, rise, material_value):
    def p(t, lateral):
        r = .009 + length * t
        half = width * math.sin(math.pi * t) ** .8
        z = center[2] + rise * t ** 1.65 + .013 * math.sin(math.pi * t)
        z += .009 * abs(lateral) * math.sin(math.pi * t)
        return orient_xy(r, lateral * half, angle, center, z)
    vertices = [p(0, 0)]
    for t in (.23, .5, .76):
        vertices.extend(p(t, side) for side in (-1, 0, 1))
    vertices.append(p(1, 0))
    faces = [(0, 1, 2), (0, 2, 3)]
    for row in range(2):
        a = 1 + row * 3
        b = a + 3
        faces.extend([(a, b, b + 1, a + 1), (a + 1, b + 1, b + 2, a + 2)])
    faces.extend([(7, 10, 8), (8, 10, 9)])
    return mesh_object(name, vertices, faces, material_value)


flower = (-.015, .048, .059)
for tier, count, length, width, rise in [(0, 10, .141, .041, .022),
                                        (1, 9, .110, .035, .060),
                                        (2, 7, .077, .026, .094)]:
    for i in range(count):
        petal(f"Flower | tier {tier + 1} petal {i + 1:02d}", flower,
              math.tau * i / count + tier * .29,
              length * (1 + .028 * math.sin(i * 2.1)), width, rise,
              BLUSH if tier == 0 else IVORY)


def lathe(name, center, profile, segments, mat):
    vertices = []
    for radius, z in profile:
        vertices.extend((center[0] + radius * math.cos(i * math.tau / segments),
                         center[1] + radius * math.sin(i * math.tau / segments),
                         center[2] + z) for i in range(segments))
    faces = []
    for row in range(len(profile) - 1):
        for i in range(segments):
            j = (i + 1) % segments
            faces.append((row * segments + i, row * segments + j,
                          (row + 1) * segments + j, (row + 1) * segments + i))
    faces.append(tuple(reversed(range(segments))))
    faces.append(tuple((len(profile) - 1) * segments + i for i in range(segments)))
    return mesh_object(name, vertices, faces, mat)


lathe("Flower | low submerged stalk", flower[:2] + (.0,), [(.008, 0), (.006, .07)], 6, LEAF)
lathe("Flower | golden centre", flower[:2] + (.078,), [(.021, 0), (.028, .028), (.016, .05)], 10, GOLD)
for i in range(9):
    angle = i * math.tau / 9
    center = (flower[0] + .031 * math.cos(angle), flower[1] + .031 * math.sin(angle), .103)
    lathe(f"Flower | stamen {i + 1:02d}", center, [(.003, 0), (.0048, .026)], 4, GOLD)

bud_center = (.245, -.105, .058)
lathe("Bud | slender stalk", bud_center[:2] + (0,), [(.005, 0), (.004, .08)], 5, LEAF)
lathe("Bud | folded pink petals", bud_center,
      [(.013, .006), (.029, .045), (.021, .084), (.004, .115)], 10, BLUSH)
for i in range(4):
    petal(f"Bud | protective sepal {i + 1}", bud_center, math.tau * i / 4, .018, .014, .07, LEAF)

# Keep a neutral product camera in the editable master, outside the exported selection.
qa = bpy.data.collections.new("QA | camera and lights, excluded from export")
scene.collection.children.link(qa)
camera_data = bpy.data.cameras.new("CAM-Water lily detail")
camera = bpy.data.objects.new("CAM-Water lily detail", camera_data)
qa.objects.link(camera)
camera.location = (1.05, -1.45, 1.85)
camera.rotation_euler = (Vector((0, .03, .045)) - camera.location).to_track_quat("-Z", "Y").to_euler()
camera_data.type = "ORTHO"
camera_data.ortho_scale = 1.24
scene.camera = camera
for name, position, energy, size in [("Key", (-2, -3, 4), 220, 3), ("Fill", (2, 1, 2), 70, 2)]:
    data = bpy.data.lights.new("LGT-Lily " + name, "AREA")
    data.energy, data.shape, data.size = energy, "DISK", size
    obj = bpy.data.objects.new("LGT-Lily " + name, data)
    qa.objects.link(obj)
    obj.location = position
    obj.rotation_euler = (-obj.location).to_track_quat("-Z", "Y").to_euler()
scene.world = bpy.data.worlds.new("WORLD-Lily neutral studio")
scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (.08, .15, .17, 1)
scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = .65
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 20
scene.render.resolution_x = 640
scene.render.resolution_y = 640
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
scene["asset_description"] = "Six notched floating leaves, one pink-white water lily and one closed bud; original project artwork."
scene["waterline_m"] = 0.0
scene["export_axis"] = "Blender Z up exports to Godot Y up"

MASTER.parent.mkdir(parents=True, exist_ok=True)
EXPORT.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(MASTER))
if args.preview:
    scene.render.filepath = str(Path(args.preview).resolve())
    bpy.ops.render.render(write_still=True)

# No destructive joins occur in the editable .blend. Make one runtime mesh copy.
copies = bpy.data.collections.new("Export copy")
scene.collection.children.link(copies)
bpy.ops.object.select_all(action="DESELECT")
for obj in source.objects:
    copy = obj.copy()
    copy.data = obj.data.copy()
    copies.objects.link(copy)
    copy.select_set(True)
bpy.context.view_layer.objects.active = list(copies.objects)[0]
bpy.ops.object.join()
export_object = bpy.context.object
export_object.name = "GEO-WaterLilyCluster"
scene.cursor.location = (0, 0, 0)
bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
export_object.data.calc_loop_triangles()
points = [export_object.matrix_world @ v.co for v in export_object.data.vertices]
low = [min(p[i] for p in points) for i in range(3)]
high = [max(p[i] for p in points) for i in range(3)]
report = {
    "asset": str(EXPORT.relative_to(ROOT)),
    "master": str(MASTER.relative_to(ROOT)),
    "leaf_count": 6,
    "flower_count": 1,
    "bud_count": 1,
    "vertices": len(export_object.data.vertices),
    "triangles": len(export_object.data.loop_triangles),
    "materials": len(export_object.data.materials),
    "blender_dimensions_m": [high[i] - low[i] for i in range(3)],
    "godot_dimensions_m": [high[0] - low[0], high[2] - low[2], high[1] - low[1]],
    "waterline_origin": [0, 0, 0],
    "vertical_bounds_m": [low[2], high[2]],
}
assert report["materials"] == 5
assert 1000 <= report["triangles"] <= 1700, report
bpy.ops.export_scene.gltf(filepath=str(EXPORT), export_format="GLB", use_selection=True,
                         export_apply=True, export_animations=False, export_yup=True,
                         export_materials="EXPORT", export_cameras=False, export_lights=False)
report["bytes"] = EXPORT.stat().st_size
print("WATER_LILY_EXPORT " + json.dumps(report, ensure_ascii=False))
