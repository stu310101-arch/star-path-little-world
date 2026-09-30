"""Save a separate two-sided fabric candidate; do not run collision audits.

Example: blender --background CURRENT.blend --python-exit-code 1
  --python tools/prepare_regalia_thin_fabric.py -- --output NEW.blend

Only garment roles 01, 02, 03 and 05 lose Solidify. All other modifiers,
authored mesh/shape data, rig actions and scene timing are preserved.
"""
from pathlib import Path
import argparse
import hashlib
import json
import sys

import bpy
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from export_graduate_godot import action_curves, role_map

SCENES = ("01_WALK", "02_RUN", "03_JUMP", "04_IDLE")
FABRIC = ("01 |", "02 |", "03 |", "05 |")


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode("utf-8")).hexdigest()


def properties(block):
    """Serializable scalar/array and pointer metadata for Blender RNA."""
    result = {}
    for prop in block.bl_rna.properties:
        key = prop.identifier
        if key == "rna_type" or prop.type == "COLLECTION":
            continue
        value = getattr(block, key)
        if prop.type == "POINTER":
            result[key] = getattr(value, "name", None) if value is not None else None
        elif getattr(prop, "is_array", False):
            result[key] = list(value)
        elif isinstance(value, set):
            result[key] = sorted(value)
        else:
            result[key] = value
    return result


def mesh_hash(obj):
    h = hashlib.sha256()
    array = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
    obj.data.vertices.foreach_get("co", array)
    h.update(array.tobytes())
    h.update(json.dumps([tuple(p.vertices) for p in obj.data.polygons]).encode())
    if obj.data.shape_keys:
        for key in obj.data.shape_keys.key_blocks:
            h.update(key.name.encode())
            key.data.foreach_get("co", array)
            h.update(array.tobytes())
    return h.hexdigest()


def material_slots(obj):
    return [{"slot": i, "link": slot.link,
             "material": slot.material.name if slot.material else None,
             "use_backface_culling": slot.material.use_backface_culling if slot.material else None}
            for i, slot in enumerate(obj.material_slots)]


def authoring_snapshot(scenes):
    actions = {}
    for action in bpy.data.actions:
        curves = []
        for curve in action_curves(action):
            curves.append({"path": curve.data_path, "index": curve.array_index,
                           "extrapolation": curve.extrapolation, "mute": curve.mute,
                           "keys": [[*key.co, *key.handle_left, *key.handle_right,
                                     key.interpolation, key.handle_left_type, key.handle_right_type]
                                    for key in curve.keyframe_points],
                           "modifiers": [properties(m) for m in curve.modifiers]})
        actions[action.name] = digest(curves)
    rigs, timing = {}, {}
    for scene in scenes:
        rig, _ = role_map(scene)
        rigs[scene.name] = {"name": rig.name,
                           "action": rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None,
                           "matrix_world": [list(row) for row in rig.matrix_world],
                           "bones": [{"name": b.name, "parent": b.parent.name if b.parent else None,
                                      "matrix_local": [list(row) for row in b.matrix_local],
                                      "use_deform": b.use_deform} for b in rig.data.bones]}
        timing[scene.name] = {"start": scene.frame_start, "end": scene.frame_end,
                              "fps": scene.render.fps, "fps_base": scene.render.fps_base,
                              "current": scene.frame_current, "subframe": scene.frame_subframe}
    return {"actions": actions, "rigs": rigs, "timing": timing}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    if not bpy.data.filepath:
        parser.error("Load the current graduate .blend before running this script")
    source, output = Path(bpy.data.filepath).resolve(), args.output.resolve()
    if source == output or output.suffix.lower() != ".blend":
        parser.error("--output must be a distinct .blend path")
    report_path = args.report.resolve() if args.report else output.with_suffix(".conversion.json")
    if report_path in (source, output):
        parser.error("Report path must be distinct from both assets")
    scenes = []
    for prefix in SCENES:
        matches = [s for s in bpy.data.scenes if s.name.startswith(prefix)]
        if len(matches) != 1:
            raise ValueError(f"Expected exactly one {prefix} scene")
        scenes.append(matches[0])
    targets = set()
    for scene in scenes:
        _, meshes = role_map(scene)
        targets.update(obj for role, obj in meshes.items() if role.startswith(FABRIC))
    report = {"source": str(source), "output": str(output), "complete": False,
              "roles": list(FABRIC), "objects": {}, "copied_materials": [],
              "audit_performed": False, "method": "Remove fabric Solidify only; double-sided fabric materials"}
    before = authoring_snapshot(scenes)
    original_meshes = {obj: mesh_hash(obj) for obj in targets}
    original_materials = {obj: material_slots(obj) for obj in targets}
    all_other_modifiers = {obj.name: [properties(m) for m in obj.modifiers]
                           for obj in bpy.data.objects if obj not in targets}
    # A shared material may also belong to caps or metal bars. Copy only when
    # a culling change is needed, so those non-fabric objects stay untouched.
    nonfabric_materials = {slot.material for obj in bpy.data.objects if obj not in targets
                           for slot in obj.material_slots if slot.material}
    replacements = {}
    for obj in sorted(targets, key=lambda obj: obj.name):
        entry = {"role": obj["graduate_role"], "modifiers_before": [properties(m) for m in obj.modifiers],
                 "materials_before": original_materials[obj], "removed_solidify": []}
        for modifier in list(obj.modifiers):
            if modifier.type == "SOLIDIFY":
                entry["removed_solidify"].append(modifier.name)
                obj.modifiers.remove(modifier)
        for slot in obj.material_slots:
            material = slot.material
            if not material or not material.use_backface_culling:
                continue
            if material in nonfabric_materials:
                if material not in replacements:
                    replacement = material.copy()
                    replacement.name = material.name + " | two-sided fabric"
                    replacements[material] = replacement
                    report["copied_materials"].append({"from": material.name, "to": replacement.name})
                # Object-linked material override avoids changing a shared mesh.
                slot.link = "OBJECT"
                slot.material = replacements[material]
                material = slot.material
            material.use_backface_culling = False
        entry["modifiers_after"] = [properties(m) for m in obj.modifiers]
        entry["materials_after"] = material_slots(obj)
        if [m for m in entry["modifiers_before"] if m["type"] != "SOLIDIFY"] != entry["modifiers_after"]:
            raise AssertionError("A non-Solidify modifier changed: " + obj.name)
        if original_meshes[obj] != mesh_hash(obj):
            raise AssertionError("Authored geometry or shape keys changed: " + obj.name)
        report["objects"][obj.name] = entry
    after = authoring_snapshot(scenes)
    if before != after:
        raise AssertionError("Rig, action or timing preservation check failed")
    if all_other_modifiers != {obj.name: [properties(m) for m in obj.modifiers]
                              for obj in bpy.data.objects if obj not in targets}:
        raise AssertionError("A non-fabric modifier changed")
    report.update({"authoring_before": before, "authoring_after": after,
                   "rig_actions_timing_preserved": True, "authored_mesh_and_shape_keys_preserved": True,
                   "other_modifiers_preserved": True, "removed_solidify_count": sum(
                       len(entry["removed_solidify"]) for entry in report["objects"].values())})
    output.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(output))
    report["complete"] = True
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("REGALIA_THIN_FABRIC_SAVED", str(output), "removed", report["removed_solidify_count"], flush=True)


if __name__ == "__main__":
    main()
