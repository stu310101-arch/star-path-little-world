"""Read-only preservation checks for the isolated graduate sleeve change.

Run this script in Blender. It never saves or edits a blend file on disk.

Before the sleeve change::
    blender -b art/Graduate/Male_Graduate_BeforeSleevePhysics.blend \
        --python-exit-code 1 --python tools/validate_sleeve_cloth.py -- \
        --mode snapshot --output tools/sleeve-preservation-before.json

After the sleeve change::
    blender -b art/Graduate/Male_Graduate_GameReady.blend \
        --python-exit-code 1 --python tools/validate_sleeve_cloth.py -- \
        --mode compare --baseline tools/sleeve-preservation-before.json \
        --output tools/sleeve-preservation-comparison.json

All character meshes except the two explicit sleeve roles are fingerprinted.
Scene, viewport, render, and custom-property metadata are intentionally ignored.
Animation is read through Blender 5.2's layered action channel bags. Object
values are sampled at frame 1 in both files to avoid current-frame differences.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np


ROOT = Path(__file__).resolve().parents[1]
SCENES = (("Walk", "01_WALK"), ("Run", "02_RUN"), ("JumpDown", "03_JUMP"))
SLEEVE_ROLES = ("02 | Bell sleeve L", "02 | Bell sleeve R")
VERSION = 1


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=True, allow_nan=False).encode()).hexdigest()


def array_digest(collection, field, width, dtype):
    values = np.empty(len(collection) * width, dtype=dtype)
    collection.foreach_get(field, values)
    if values.dtype.kind == "f" and not np.isfinite(values).all():
        raise ValueError(f"Non-finite {field} data")
    return {"count": len(collection), "width": width,
            "sha256": hashlib.sha256(values.tobytes()).hexdigest()}


def id_reference(value):
    if value is None:
        return None
    if isinstance(value, bpy.types.Object):
        role = value.get("graduate_role")
        if role:
            return {"type": "Object", "role": role, "name": value.name}
    return {"type": value.bl_rna.identifier, "name": value.name}


def plain(value):
    if value is None or isinstance(value, (bool, int, float, str)):
        return value
    if isinstance(value, bpy.types.ID):
        return id_reference(value)
    if isinstance(value, set):
        return sorted(value)
    try:
        return [plain(item) for item in value]
    except TypeError:
        return None


def rna_settings(value, depth=1):
    """Persist writable settings, excluding runtime evaluation and selection."""
    result = {"rna_type": value.bl_rna.identifier}
    ignored = {"rna_type", "name", "is_active", "is_override_data", "select",
               "show_expanded", "execution_time", "persistent_uid"}
    for prop in value.bl_rna.properties:
        key = prop.identifier
        if key in ignored or prop.is_readonly:
            continue
        try:
            item = getattr(value, key)
            if prop.type in {"BOOLEAN", "INT", "FLOAT", "STRING", "ENUM"}:
                result[key] = plain(item)
            elif prop.type == "POINTER":
                if item is None or isinstance(item, bpy.types.ID):
                    result[key] = plain(item)
                elif depth:
                    result[key] = rna_settings(item, depth - 1)
        except (AttributeError, TypeError, ValueError, RuntimeError):
            # Dynamic RNA settings not available for the current modifier mode.
            continue
    return result


def action_curves(action):
    if action is None:
        return []
    if hasattr(action, "layers"):
        return [curve for layer in action.layers for strip in layer.strips
                for bag in strip.channelbags for curve in bag.fcurves]
    return list(action.fcurves)


def curve_data(curve):
    keys = []
    for key in curve.keyframe_points:
        item = {"co": list(key.co), "handle_left": list(key.handle_left),
                "handle_right": list(key.handle_right),
                "interpolation": key.interpolation,
                "handle_left_type": key.handle_left_type,
                "handle_right_type": key.handle_right_type}
        for attr in ("easing", "amplitude", "back", "period", "type"):
            if hasattr(key, attr):
                item[attr] = getattr(key, attr)
        keys.append(item)
    result = {"path": curve.data_path, "index": curve.array_index,
              "extrapolation": curve.extrapolation, "mute": curve.mute,
              "keys": keys,
              "samples": [list(point.co) for point in curve.sampled_points],
              "modifiers": [rna_settings(modifier) for modifier in curve.modifiers]}
    if curve.driver is not None:
        driver = curve.driver
        result["driver"] = {"type": driver.type, "expression": driver.expression,
                            "use_self": driver.use_self,
                            "variables": [{"name": variable.name, "type": variable.type,
                                           "targets": [rna_settings(target) for target in variable.targets]}
                                          for variable in driver.variables]}
    return result


def action_data(action):
    if action is None:
        return None
    layers = []
    if hasattr(action, "layers"):
        for layer in action.layers:
            strips = []
            for strip in layer.strips:
                bags = [{"slot_handle": bag.slot_handle,
                         "curves": [curve_data(curve) for curve in bag.fcurves]}
                        for bag in strip.channelbags]
                strips.append({"type": strip.type, "channelbags": bags})
            layers.append({"name": layer.name, "strips": strips})
    result = {"name": action.name, "layers": layers}
    if not layers:
        result["curves"] = [curve_data(curve) for curve in action_curves(action)]
    return result


def animation_data(block):
    animation = block.animation_data
    if animation is None:
        return None
    result = {"action": action_data(animation.action),
              "settings": {key: plain(getattr(animation, key))
                           for key in ("action_blend_type", "action_extrapolation",
                                       "action_influence", "use_nla") if hasattr(animation, key)},
              "drivers": [curve_data(curve) for curve in animation.drivers], "nla": []}
    for track in animation.nla_tracks:
        result["nla"].append({"name": track.name, "mute": track.mute,
                              "is_solo": track.is_solo,
                              "strips": [{"settings": rna_settings(strip),
                                          "action": action_data(strip.action)}
                                         for strip in track.strips]})
    return result


def weights_data(obj, canonical=False):
    groups = {group.index: group.name for group in obj.vertex_groups}
    if canonical:
        # The group indices can differ between independently refined meshes.
        # Deformation depends on the named weights, not insertion order.
        return {'groups': sorted(groups.values()),
                'vertices': [sorted((groups[w.group], w.weight) for w in v.groups)
                             for v in obj.data.vertices]}
    return {"groups": [group.name for group in obj.vertex_groups],
            "vertices": [[(groups[weight.group], weight.weight) for weight in vertex.groups]
                         for vertex in obj.data.vertices]}


def topology_data(mesh):
    return {"vertices": len(mesh.vertices),
            "edges": array_digest(mesh.edges, "vertices", 2, np.int32),
            "loops": array_digest(mesh.loops, "vertex_index", 1, np.int32),
            "polygon_starts": array_digest(mesh.polygons, "loop_start", 1, np.int32),
            "polygon_sizes": array_digest(mesh.polygons, "loop_total", 1, np.int32)}


def material_data(material):
    if material is None:
        return None
    result = {"name": material.name, "settings": rna_settings(material, depth=0)}
    tree = material.node_tree
    if tree:
        result["nodes"] = [{"name": node.name, "type": node.bl_idname,
                            "settings": rna_settings(node, depth=0),
                            "inputs": [(socket.identifier, plain(socket.default_value))
                                       for socket in node.inputs if hasattr(socket, "default_value")]}
                           for node in tree.nodes]
        result["links"] = sorted((link.from_node.name, link.from_socket.identifier,
                                   link.to_node.name, link.to_socket.identifier)
                                  for link in tree.links)
        result["animation"] = animation_data(tree)
    return result


def object_components(obj):
    transform = {key: plain(getattr(obj, key)) for key in
                 ("location", "rotation_mode", "rotation_euler", "rotation_quaternion",
                  "rotation_axis_angle", "scale", "delta_location", "delta_rotation_euler",
                  "delta_rotation_quaternion", "delta_scale", "matrix_parent_inverse")}
    transform.update(parent=id_reference(obj.parent), parent_type=obj.parent_type,
                     parent_bone=obj.parent_bone)
    return {"object_transform": digest(transform),
            "object_action": digest(animation_data(obj)),
            "constraints": digest([rna_settings(constraint) for constraint in obj.constraints])}


def mesh_components(obj):
    mesh = obj.data
    result = object_components(obj)
    result.update(topology=digest(topology_data(mesh)),
                  positions=digest(array_digest(mesh.vertices, "co", 3, np.float32)),
                  weights=digest(weights_data(obj)),
                  material_indices=digest(array_digest(mesh.polygons, "material_index", 1, np.int32)),
                  smooth_faces=digest([face.use_smooth for face in mesh.polygons]),
                  modifiers=digest([rna_settings(modifier, depth=2) for modifier in obj.modifiers]),
                  materials=digest([material_data(slot.material) for slot in obj.material_slots]),
                  mesh_action=digest(animation_data(mesh)))
    keys = mesh.shape_keys
    key_data = None
    if keys:
        key_data = {"use_relative": keys.use_relative, "animation": animation_data(keys),
                    "keys": [{"name": key.name, "positions": array_digest(key.data, "co", 3, np.float32),
                              "relative_key": key.relative_key.name if key.relative_key else None,
                              "vertex_group": key.vertex_group, "mute": key.mute,
                              "interpolation": key.interpolation, "slider_min": key.slider_min,
                              "slider_max": key.slider_max}
                             for key in keys.key_blocks]}
    result["shape_keys"] = digest(key_data)
    return result


def rig_components(rig):
    result = object_components(rig)
    bones = []
    for bone in rig.data.bones:
        entry = {"name": bone.name, "parent": bone.parent.name if bone.parent else None,
                 "matrix_local": plain(bone.matrix_local), "head_local": plain(bone.head_local),
                 "tail_local": plain(bone.tail_local), "settings": rna_settings(bone)}
        bones.append(entry)
    result["rest_bones"] = digest(bones)
    result["armature_action"] = digest(animation_data(rig.data))
    result["pose_settings"] = digest([{"name": bone.name, "rotation_mode": bone.rotation_mode,
                                       "constraints": [rna_settings(item) for item in bone.constraints],
                                       "ik": {key: plain(getattr(bone, key)) for key in
                                              ("ik_stiffness_x", "ik_stiffness_y", "ik_stiffness_z",
                                               "use_ik_limit_x", "use_ik_limit_y", "use_ik_limit_z",
                                               "ik_min_x", "ik_min_y", "ik_min_z",
                                               "ik_max_x", "ik_max_y", "ik_max_z")}}
                                      for bone in rig.pose.bones])
    return result


def sleeve_summary(obj):
    keys = obj.data.shape_keys
    action = keys.animation_data.action if keys and keys.animation_data else None
    curves = action_curves(action)
    animated = [curve for curve in curves if curve.data_path.endswith(".value")
                and len(curve.keyframe_points) > 1]
    return {"object": obj.name, "vertices": len(obj.data.vertices),
            "polygons": len(obj.data.polygons),
            "topology": digest(topology_data(obj.data)),
            "material_indices": digest(array_digest(obj.data.polygons, "material_index", 1, np.int32)),
            "material_slots": [slot.material.name if slot.material else None for slot in obj.material_slots],
            "weights": digest(weights_data(obj, canonical=True)),
            "shape_keys": len(keys.key_blocks) if keys else 0,
            "animated_shape_curves": len(animated),
            "live_cloth_modifiers": [modifier.name for modifier in obj.modifiers if modifier.type == "CLOTH"]}


def snapshot():
    scenes = {}
    for label, prefix in SCENES:
        matches = [scene for scene in bpy.data.scenes if scene.name.startswith(prefix)]
        if len(matches) != 1:
            raise ValueError(f"Expected one {prefix} scene, found {len(matches)}")
        scene = matches[0]
        if bpy.context.window:
            bpy.context.window.scene = scene
        scene.frame_set(1)
        bpy.context.view_layer.update()
        roles = {}
        for obj in scene.objects:
            role = obj.get("graduate_role")
            if obj.type != "MESH" or not role or role == "Studio floor" or obj.get("preview_fx"):
                continue
            if role in roles:
                raise ValueError(f"Duplicate graduate role {role} in {label}")
            roles[role] = obj
        rigs = [obj for obj in scene.objects if obj.type == "ARMATURE" and not obj.get("preview_fx")]
        if len(rigs) != 1:
            raise ValueError(f"Expected one rig in {label}, found {len(rigs)}")
        for role in SLEEVE_ROLES:
            if role not in roles:
                raise ValueError(f"Missing sleeve {role} in {label}")
        scenes[label] = {"meshes": {role: mesh_components(obj) for role, obj in sorted(roles.items())
                                    if role not in SLEEVE_ROLES},
                         "rig": rig_components(rigs[0]),
                         "roots": {obj.name: object_components(obj) for obj in scene.objects
                                   if obj.get("graduate_root")},
                         "sleeves": {role: sleeve_summary(roles[role]) for role in SLEEVE_ROLES}}
        print(f"PRESERVATION_SNAPSHOT {label} meshes={len(scenes[label]['meshes'])}", flush=True)
    return {"version": VERSION, "source": str(Path(bpy.data.filepath).resolve()),
            "excluded_roles": list(SLEEVE_ROLES), "scenes": scenes}


def recursive_differences(before, after, prefix=""):
    differences = []
    if isinstance(before, dict) and isinstance(after, dict):
        for key in sorted(before.keys() | after.keys()):
            path = f"{prefix}/{key}"
            if key not in before:
                differences.append({"path": path, "change": "added"})
            elif key not in after:
                differences.append({"path": path, "change": "removed"})
            else:
                differences.extend(recursive_differences(before[key], after[key], path))
    elif before != after:
        differences.append({"path": prefix, "change": "modified", "before": before, "after": after})
    return differences


def compare(baseline, current):
    if baseline.get("version") != VERSION or baseline.get("excluded_roles") != list(SLEEVE_ROLES):
        raise ValueError("Baseline schema or excluded roles do not match this validator")
    before = {name: {key: value for key, value in scene.items() if key != "sleeves"}
              for name, scene in baseline["scenes"].items()}
    after = {name: {key: value for key, value in scene.items() if key != "sleeves"}
             for name, scene in current["scenes"].items()}
    differences = recursive_differences(before, after)
    sleeve_errors = []
    for role in SLEEVE_ROLES:
        reference = current["scenes"]["Walk"]["sleeves"][role]
        for name, scene in current["scenes"].items():
            sleeve = scene["sleeves"][role]
            for key in ("topology", "material_indices", "material_slots", "weights"):
                if sleeve[key] != reference[key]:
                    sleeve_errors.append(f"{name}/{role}: {key} differs from Walk")
            if sleeve["live_cloth_modifiers"]:
                sleeve_errors.append(f"{name}/{role}: live Cloth modifier remains")
            if sleeve["shape_keys"] <= 1 or sleeve["animated_shape_curves"] == 0:
                sleeve_errors.append(f"{name}/{role}: no baked animated sleeve shape keys")
    return {"ok": not differences and not sleeve_errors,
            "baseline_source": baseline["source"], "current_source": current["source"],
            "preserved_nonsleeve_meshes": sum(len(scene["meshes"]) for scene in current["scenes"].values()),
            "differences": differences, "sleeve_errors": sleeve_errors,
            "sleeves": {name: scene["sleeves"] for name, scene in current["scenes"].items()}}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=("snapshot", "compare"), required=True)
    parser.add_argument("--baseline", type=Path, default=ROOT / "tools/sleeve-preservation-before.json")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    current = snapshot()
    result = current if args.mode == "snapshot" else compare(json.loads(args.baseline.read_text(encoding="utf-8")), current)
    output = args.output or ROOT / ("tools/sleeve-preservation-before.json" if args.mode == "snapshot"
                                   else "tools/sleeve-preservation-comparison.json")
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    if args.mode == "compare" and not result["ok"]:
        print(json.dumps({"differences": result["differences"], "sleeve_errors": result["sleeve_errors"]},
                         ensure_ascii=True, indent=2), flush=True)
        raise AssertionError(f"Sleeve preservation validation failed; see {output}")
    print(f"SLEEVE_PRESERVATION_{args.mode.upper()}_OK {output}", flush=True)


if __name__ == "__main__":
    main()
