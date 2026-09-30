"""Optionally restore the original skin exposed by freely moving sleeves.

Import and call ``restore_hidden_forearms()`` from an existing Blender session.
Importing or executing this module alone does nothing. The function appends
source data temporarily, edits only memory, returns a report, and never saves
a blend or starts another Blender process.

Extraction exactly matches build_graduate.py's deleted Skin faces:
``face.calc_center_median().z > 3.3 and .70 < abs(center.x) < 1.90``.
The source Skin material is resolved explicitly through the library loader;
object and material names may receive suffixes without affecting selection.
No Shirt faces, new anatomy, or substitute capsule surfaces are introduced.

The three destination armatures must retain the source rest bones. Their
existing body's Skin material is reused so restored skin matches the already
modernized face and hands. Geometry, original vertex groups and weights,
face shading, UV/custom mesh layers, and original object transforms survive.
Each scene receives one mesh object with the same reusable graduate_role.
"""

from __future__ import annotations

from pathlib import Path
import re

import bmesh
import bpy


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "QuaterniusMen" / "Blends" / "Male_Casual.blend"
ROLE = "Graduate | restored arm skin"
BODY_ROLE = "Graduate | original face, hands and trousers"
SCENE_PREFIXES = ("01_WALK", "02_RUN", "03_JUMP")


def _matrix_error(first, second):
    return max(abs(first[row][column] - second[row][column])
               for row in range(4) for column in range(4))


def _curves(action):
    if action is None:
        return []
    if hasattr(action, "layers"):
        return [curve for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for curve in bag.fcurves]
    return list(action.fcurves)


def _source_face_ids(obj, source_skin):
    """Use the exact bmesh median and strict inequalities of the removal."""
    skin_slots = {index for index, material in enumerate(obj.data.materials)
                  if material == source_skin}
    if not skin_slots:
        return []
    mesh = bmesh.new()
    try:
        mesh.from_mesh(obj.data)
        mesh.faces.ensure_lookup_table()
        result = []
        for face in mesh.faces:
            center = face.calc_center_median()
            if (face.material_index in skin_slots and center.z > 3.3
                    and .70 < abs(center.x) < 1.90):
                result.append(face.index)
        return result
    finally:
        mesh.free()


def _destination_skin(body, source_skin):
    # build_graduate.py preserved the legacy diffuse colour and refreshed only
    # its node tree. Require that material lineage, rather than guessing by
    # the current localized Principled-node name or an arbitrary skin colour.
    candidates = [material for material in body.data.materials if material
                  and re.fullmatch(r"Skin(?:\.\d+)?", material.name)]
    if len(candidates) != 1:
        raise RuntimeError(f"Expected one existing Skin material on {body.name}; "
                           f"found {[material.name for material in candidates]}")
    material = candidates[0]
    difference = max(abs(a - b) for a, b in
                     zip(material.diffuse_color, source_skin.diffuse_color))
    if difference > 1e-4:
        raise RuntimeError(f"Existing Skin diffuse colour differs from source on {body.name}")
    return material


def _copy_transforms(source, destination, parent):
    if source.parent_type != "OBJECT":
        raise RuntimeError("Original arm skin requires an ordinary object parent")
    destination.parent = parent
    destination.parent_type = "OBJECT"
    destination.rotation_mode = source.rotation_mode
    for field in ("location", "rotation_euler", "rotation_quaternion",
                  "rotation_axis_angle", "scale", "delta_location",
                  "delta_rotation_euler", "delta_rotation_quaternion", "delta_scale"):
        setattr(destination, field, getattr(source, field)[:])
    destination.matrix_parent_inverse = source.matrix_parent_inverse.copy()
    if _matrix_error(destination.matrix_basis, source.matrix_basis) > 1e-6:
        raise RuntimeError("Restored skin did not retain the source object transform")


def _copy_visibility(source, destination):
    """New arms must follow the existing body's JumpDown disappearance."""
    original = {field: getattr(source, field) for field in ("hide_viewport", "hide_render")}
    source_action = source.animation_data.action if source.animation_data else None
    relevant = [curve for curve in _curves(source_action) if curve.data_path in original]
    for curve in relevant:
        for key in curve.keyframe_points:
            setattr(destination, curve.data_path, bool(key.co.y))
            destination.keyframe_insert(data_path=curve.data_path, frame=key.co.x)
    if destination.animation_data and destination.animation_data.action:
        action = destination.animation_data.action
        action.name = "Graduate | restored arm skin visibility"
        for curve in _curves(action):
            source_curve = next(item for item in relevant if item.data_path == curve.data_path)
            curve.extrapolation = source_curve.extrapolation
            for key in curve.keyframe_points:
                matched = next(item for item in source_curve.keyframe_points
                               if abs(item.co.x - key.co.x) < 1e-6)
                key.interpolation = matched.interpolation
    for field, value in original.items():
        setattr(destination, field, value)
    destination.hide_set(source.hide_get())


def _remove_temporary_import(before, preserved_objects=(), preserved_meshes=()):
    """Remove only newly appended data, never run an orphan purge."""
    preserved_objects = set(preserved_objects)
    preserved_meshes = set(preserved_meshes)
    for obj in list(bpy.data.objects):
        if obj not in before["objects"] and obj not in preserved_objects:
            bpy.data.objects.remove(obj, do_unlink=True)
    # Object and mesh removal releases the appended armature actions/materials.
    for name in ("meshes", "armatures", "actions", "materials", "node_groups",
                 "textures", "images", "cameras", "lights", "collections"):
        blocks = getattr(bpy.data, name)
        for block in list(blocks):
            if block in before[name] or (name == "meshes" and block in preserved_meshes):
                continue
            if block.use_fake_user:
                block.use_fake_user = False
            if block.users == 0:
                blocks.remove(block)


def restore_hidden_forearms(source_path=None, scene_prefixes=SCENE_PREFIXES):
    """Restore the precise original arm-skin subset in the requested scenes.

    Existing objects with ROLE are kept unchanged. A partial prior restoration
    is completed without duplicates. Caller decides whether and where to save.
    The function performs all source/rig/material preflight before adding skin.
    On failure, any objects created by this invocation are rolled back.
    """
    source_path = Path(source_path or SOURCE).resolve()
    if not source_path.is_file():
        raise FileNotFoundError(source_path)
    destinations, already_present = [], []
    for prefix in scene_prefixes:
        matching = [scene for scene in bpy.data.scenes if scene.name.startswith(prefix)]
        if len(matching) != 1:
            raise RuntimeError(f"Expected one destination scene for {prefix}")
        scene = matching[0]
        existing = [obj for obj in scene.objects if obj.get("graduate_role") == ROLE]
        if len(existing) > 1:
            raise RuntimeError(f"Duplicate restored skin role in {scene.name}")
        if existing:
            already_present.append({"scene": scene.name, "object": existing[0].name})
            continue
        bodies = [obj for obj in scene.objects if obj.get("graduate_role") == BODY_ROLE]
        rigs = [obj for obj in scene.objects if obj.type == "ARMATURE"]
        if len(bodies) != 1 or len(rigs) != 1 or bodies[0].parent != rigs[0]:
            raise RuntimeError(f"Expected the original body parented to one rig in {scene.name}")
        destinations.append((scene, bodies[0], rigs[0]))
    report = {"source": str(source_path), "role": ROLE, "saved_blend": False,
              "already_present": already_present, "created": []}
    if not destinations:
        return report
    names = ("objects", "meshes", "armatures", "actions", "materials", "node_groups",
             "textures", "images", "cameras", "lights", "collections")
    before = {name: set(getattr(bpy.data, name)) for name in names}
    created = []
    succeeded = False
    try:
        with bpy.data.libraries.load(str(source_path), link=False) as (available, loaded):
            if "Skin" not in available.materials:
                raise RuntimeError("Original Male_Casual library has no exact Skin material")
            loaded.objects = list(available.objects)
            loaded.materials = ["Skin"]
        source_skin = loaded.materials[0]
        candidates = []
        for obj in loaded.objects:
            if obj is not None and obj.type == "MESH":
                selected = _source_face_ids(obj, source_skin)
                if selected:
                    candidates.append((obj, selected))
        if len(candidates) != 1:
            raise RuntimeError("Expected one original skinned mesh with deleted arm faces; "
                               f"found {[(obj.name, len(ids)) for obj, ids in candidates]}")
        original, selected = candidates[0]
        if original.data.shape_keys:
            raise RuntimeError("Original arm source unexpectedly contains shape keys")
        source_rig = original.parent
        if source_rig is None or source_rig.type != "ARMATURE":
            raise RuntimeError("Original arm source is not parented to an armature")
        source_mods = [mod for mod in original.modifiers if mod.type == "ARMATURE"]
        if len(source_mods) != 1 or source_mods[0].object != source_rig:
            raise RuntimeError("Original arm source requires exactly one matching Armature modifier")
        groups = [(group.name, group.lock_weight) for group in original.vertex_groups]
        materials = {}
        destination_modifiers = {}
        for scene, body, rig in destinations:
            for bone in source_rig.data.bones:
                target = rig.data.bones.get(bone.name)
                if target is None or _matrix_error(bone.matrix_local, target.matrix_local) > 1e-5:
                    raise RuntimeError(f"Rest bone mismatch in {scene.name}: {bone.name}")
            if (_matrix_error(body.matrix_basis, original.matrix_basis) > 1e-5
                    or _matrix_error(body.matrix_parent_inverse, original.matrix_parent_inverse) > 1e-5):
                raise RuntimeError(f"Existing body object transform differs from source in {scene.name}")
            materials[scene.name] = _destination_skin(body, source_skin)
            body_modifiers = [modifier for modifier in body.modifiers if modifier.type == "ARMATURE"]
            if len(body_modifiers) != 1 or body_modifiers[0].object != rig:
                raise RuntimeError(f"Expected one existing body Armature modifier in {scene.name}")
            destination_modifiers[scene.name] = body_modifiers[0]
        # Copying the original mesh and deleting only unselected geometry keeps
        # deform weights and UV/colour/custom layers in their original form.
        extracted = original.data.copy()
        extracted.name = ROLE + " | source subset"
        mesh = bmesh.new()
        try:
            mesh.from_mesh(extracted)
            mesh.faces.ensure_lookup_table()
            keep = set(selected)
            bmesh.ops.delete(mesh, geom=[face for face in mesh.faces if face.index not in keep],
                             context="FACES")
            bmesh.ops.delete(mesh, geom=[vertex for vertex in mesh.verts if not vertex.link_faces],
                             context="VERTS")
            for face in mesh.faces:
                face.material_index = 0
            mesh.to_mesh(extracted)
        finally:
            mesh.free()
        extracted.materials.clear()
        if len(extracted.polygons) != len(selected) or not extracted.vertices:
            raise RuntimeError("Arm skin extraction did not preserve selected faces")
        report.update(source_object=original.name, source_face_indices=selected,
                      faces_per_scene=len(extracted.polygons), vertices_per_scene=len(extracted.vertices),
                      extraction="Skin only; median z > 3.3 and 0.70 < abs(median x) < 1.90",
                      shirt_faces_restored=0, material_policy="reuse matching existing body Skin material")
        for scene, body, rig in destinations:
            data = extracted.copy()
            data.name = ROLE + " | " + scene.name.split(" ")[0]
            data.materials.append(materials[scene.name])
            obj = bpy.data.objects.new(ROLE, data)
            created.append(obj)
            scene.collection.objects.link(obj)
            obj["graduate_role"] = ROLE
            obj["Source asset"] = str(source_path)
            obj["Restoration"] = "Original hidden arm Skin faces only; exposed by free sleeve cloth."
            for name, locked in groups:
                group = obj.vertex_groups.new(name=name)
                group.lock_weight = locked
            _copy_transforms(original, obj, rig)
            modifier = obj.modifiers.new("Follow original character skeleton", "ARMATURE")
            modifier.object = rig
            # Match the current original body exactly at the shared boundary;
            # the game export may intentionally use linear skinning even if
            # the legacy file had another deformation option enabled.
            body_modifier = destination_modifiers[scene.name]
            for field in ("use_vertex_groups", "use_bone_envelopes", "use_deform_preserve_volume",
                          "vertex_group", "invert_vertex_group", "use_multi_modifier"):
                if hasattr(body_modifier, field):
                    setattr(modifier, field, getattr(body_modifier, field))
            _copy_visibility(body, obj)
            report["created"].append({"scene": scene.name, "object": obj.name,
                                      "material": materials[scene.name].name,
                                      "rig": rig.name, "vertex_group_count": len(obj.vertex_groups)})
        succeeded = True
        return report
    finally:
        _remove_temporary_import(before, created if succeeded else (),
                                 [obj.data for obj in created] if succeeded else ())
