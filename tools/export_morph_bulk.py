"""Bulk author the graduate exporter's exact, dense morph-weight actions.

This changes action construction only: target coordinates, sample frames,
float32 weights, linear interpolation, and glTF export options are untouched.
The Blender 5.2 action-slot and foreach_set APIs follow the installed glTF
importer (io_scene_gltf2/blender/imp/animation_utils.py).

Integration in export_graduate_godot.create_staging():
  1. Keep the existing rig/bone keyframe loop, but remove its inner
     ``for obj, values in morph_objects.values()`` keyframe-insertion loop.
  2. Replace the later morph set_linear/action-name loop with:
       from export_morph_bulk import write_morph_actions
       write_morph_actions(bpy, np, morph_objects, samples)

Call before scene.frame_set(0). Add the tools directory to sys.path when
running the exporter with Blender --python if it is not already present.
"""

from __future__ import annotations

import time


def write_morph_actions(bpy, np, morph_objects, samples):
    """Attach one layered, single-slot action to each fresh Key datablock.

    ``morph_objects`` maps role to (mesh_object, float32 sample/target array).
    ``samples`` is the exporter's original sample list, including timeline
    gaps and repeated loop endpoints. No zero keys are omitted or reduced.
    Returns construction statistics; does not change scene time or save files.
    """
    started = time.perf_counter()
    frames = np.asarray([sample["frame"] for sample in samples], dtype=np.float32)
    if frames.ndim != 1 or not len(frames):
        raise ValueError("Morph action requires at least one sample")
    if not np.isfinite(frames).all() or np.any(np.diff(frames) <= 0):
        raise ValueError("Morph sample frames must be finite and strictly increasing")

    # Resolve RNA enum values instead of assuming Blender's numeric mapping.
    linear = bpy.types.Keyframe.bl_rna.properties["interpolation"].enum_items["LINEAR"].value
    interpolations = np.full(len(frames), linear, dtype=np.int32)
    coordinates = np.empty((len(frames), 2), dtype=np.float32)
    coordinates[:, 0] = frames
    curve_count = 0

    # Validate every destination before writing any animation data. This helper
    # is for the export staging meshes, never for an existing artist action.
    prepared = []
    for role, (obj, values) in morph_objects.items():
        keys = obj.data.shape_keys
        if keys is None:
            raise ValueError(f"No shape keys on export mesh {obj.name}")
        targets = list(keys.key_blocks)[1:]
        weights = np.asarray(values, dtype=np.float32)
        if weights.shape != (len(frames), len(targets)):
            raise ValueError(f"Morph weight/target count mismatch for {role}")
        if not np.isfinite(weights).all():
            raise ValueError(f"Non-finite morph weights for {role}")
        animation = keys.animation_data
        if animation and (animation.action or len(animation.nla_tracks) or len(animation.drivers)):
            raise ValueError(f"Bulk writer requires fresh export shape-key animation: {obj.name}")
        prepared.append((role, obj, keys, targets, weights))

    for role, obj, keys, targets, weights in prepared:
        if not targets:
            continue
        action = bpy.data.actions.new("EXPORT_ONLY_" + obj.name)
        layer = action.layers.new("Export Morphs")
        strip = layer.strips.new(type="KEYFRAME")
        slot = action.slots.new(keys.id_type, obj.name)
        bag = strip.channelbags.new(slot)
        animation = keys.animation_data_create()
        animation.action = action
        animation.action_slot = slot

        for target_index, key in enumerate(targets):
            # path_from_id preserves escaping even if a shape name contains
            # quotes or backslashes. Scalar properties use array index zero.
            curve = bag.fcurves.new(data_path=key.path_from_id("value"), index=0)
            coordinates[:, 1] = weights[:, target_index]
            curve.keyframe_points.add(len(frames))
            curve.keyframe_points.foreach_set("co", coordinates.ravel())
            curve.keyframe_points.foreach_set("interpolation", interpolations)
            curve.extrapolation = "CONSTANT"
            curve.update()
            # Match the old sample loop's final un-evaluated property state;
            # the caller subsequently evaluates scene.frame_set(0).
            key.value = float(weights[-1, target_index])
            curve_count += 1

        print(
            f"EXPORT_MORPH_KEYS role={role} targets={len(targets)} "
            f"samples={len(frames)} method=bulk_fcurve",
            flush=True,
        )

    result = {
        "method": "bulk_fcurve",
        "objects": len(prepared),
        "curves": curve_count,
        "keys": curve_count * len(frames),
        "elapsedSeconds": round(time.perf_counter() - started, 3),
    }
    print(f"EXPORT_MORPH_KEYS_DONE {result}", flush=True)
    return result
