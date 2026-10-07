"""Build bounded, static training-room export copies. Never edits authored blends.

Run in a fresh Blender CLI process; source GLB is only read. The detailed copy
reduces dense upholstery/frame tessellation. The light copy keeps every named
part, silhouette, material and transform, with a 256 px painting for startup.
Godot's build_training_room_runtime.gd converts these interchange files into
the boot scene and independently loadable detail meshes.
"""
from pathlib import Path
import hashlib
import json
import math
import bpy

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "game/assets/training_room/wordking_training_room.glb"
OUTPUT = ROOT / "art/TrainingRoom/runtime_exports"
OUTPUT.mkdir(parents=True, exist_ok=True)
# This script is only invoked with --factory-startup in a separate process.
assert not bpy.data.filepath, "Use a fresh process; never alter the open artwork"
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))

def triangles(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)

def simplify(obj, ratio):
    if ratio >= 1 or triangles(obj) < 160:
        return
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    modifier = obj.modifiers.new("RuntimeSilhouette", "DECIMATE")
    modifier.decimate_type = "COLLAPSE"
    modifier.ratio = ratio
    modifier.use_collapse_triangulate = True
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)

meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
before = {obj.name: triangles(obj) for obj in meshes}
transforms = {obj.name: [list(row) for row in obj.matrix_world] for obj in meshes}
for obj in meshes:
    name = obj.name
    # Architectural seams, entrances and the training projector retain geometry.
    protected = any(key in name for key in ("Architecture", "Portal", "Device", "Hologram", "BOOK_", "Screen"))
    ratio = 1.0 if protected else (.30 if "Lounge" in name or "Gaming" in name else .55)
    simplify(obj, ratio)

def export(filename):
    bpy.ops.export_scene.gltf(filepath=str(OUTPUT / filename), export_format="GLB",
        export_animations=False, export_cameras=False, export_lights=False,
        export_extras=True, export_normals=True, export_tangents=False,
        export_materials="EXPORT", export_yup=True)

detail = {obj.name: triangles(obj) for obj in meshes}
# This painting is the only room image. 1024 px covers the 512 px inspection
# viewer while avoiding a multi-megabyte synchronous texture decode/upload.
# The full-resolution source JPG and the authored blends remain unchanged.
for image in bpy.data.images:
    if image.size[0] > 1024 or image.size[1] > 1024:
        scale = 1024 / max(image.size)
        image.scale(max(1, round(image.size[0] * scale)), max(1, round(image.size[1] * scale)))
export("room_detail.glb")
for obj in meshes:
    name = obj.name
    protected = any(key in name for key in ("Architecture", "Portal", "Device", "Hologram", "BOOK_", "Screen"))
    # Keep geometry at enclosure joints; simplify furnishing curves in the copy.
    simplify(obj, 1.0 if protected else .18)
for image in bpy.data.images:
    if image.size[0] > 256 or image.size[1] > 256:
        scale = 256 / max(image.size)
        image.scale(max(1, round(image.size[0] * scale)), max(1, round(image.size[1] * scale)))
light = {obj.name: triangles(obj) for obj in meshes}
export("room_light.glb")
assert all(transforms[obj.name] == [list(row) for row in obj.matrix_world] for obj in meshes)
report = {"source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(),
    "blender": bpy.app.version_string, "nodes": len(meshes),
    "triangles": {"source": sum(before.values()), "detail": sum(detail.values()), "light": sum(light.values())},
    "preserved_transforms": True, "originals_modified": False,
    "per_mesh": [{"name": name, "source": before[name], "detail": detail[name], "light": light[name]} for name in before]}
(OUTPUT / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
print("TRAINING_RUNTIME_COPY " + json.dumps(report["triangles"]))
