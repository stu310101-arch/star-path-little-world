"""Isolated Blender 5.2 smoke test: legacy vs bulk exact morph animation.

Run only after coordinating with other Blender work:
    blender --background --factory-startup --python-exit-code 1 \
        --python tools/smoke_export_morph_bulk.py

Creates only temporary in-memory meshes plus two temporary GLBs; does not
open or save the character blend, modify the source exporter, or leave output
files. Checks layered slots, dense keys, interpolation across timeline gaps,
evaluated surface positions, and the actual glTF weight-sampler payload.
"""

from __future__ import annotations

import json
from pathlib import Path
import struct
import sys
import tempfile

import bpy
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from export_morph_bulk import write_morph_actions


def action_curves(keys):
    animation = keys.animation_data
    action = animation.action
    assert animation.action_slot is not None
    assert animation.action_slot.target_id_type == keys.id_type
    return [curve for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for curve in bag.fcurves]


def mesh_object(scene, name):
    data = bpy.data.meshes.new(name)
    data.from_pydata([(0, 0, 0), (1, 0, 0), (1, 1, 0), (0, 1, 0)], [], [(0, 1, 2, 3)])
    obj = bpy.data.objects.new(name, data)
    scene.collection.objects.link(obj)
    obj.shape_key_add(name="Basis")
    for index, key_name in enumerate(('Cache_001', 'Cache_"quoted"', 'Cache_\\slash')):
        key = obj.shape_key_add(name=key_name)
        key.data[index].co.z = (index + 1) * 0.125
    return obj


def read_glb(path):
    raw = Path(path).read_bytes()
    magic, version, size = struct.unpack_from("<4sII", raw)
    assert magic == b"glTF" and version == 2 and size == len(raw)
    cursor, document, binary = 12, None, None
    while cursor < len(raw):
        length, kind = struct.unpack_from("<II", raw, cursor)
        cursor += 8
        payload = raw[cursor:cursor + length]
        cursor += length
        if kind == 0x4E4F534A:
            document = json.loads(payload)
        elif kind == 0x004E4942:
            binary = payload
    return document, binary


def weights_payload(path):
    document, binary = read_glb(path)
    animations = document.get("animations", [])
    assert len(animations) == 1, "Smoke export must contain one animation"
    animation = animations[0]
    channels = [channel for channel in animation["channels"] if channel["target"]["path"] == "weights"]
    assert len(channels) == 1, "Smoke export must contain one morph channel"
    sampler = animation["samplers"][channels[0]["sampler"]]
    payloads = []
    for name in ("input", "output"):
        accessor = document["accessors"][sampler[name]]
        assert accessor["componentType"] == 5126 and accessor["type"] == "SCALAR"
        assert "sparse" not in accessor
        view = document["bufferViews"][accessor["bufferView"]]
        offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
        stride = view.get("byteStride", 4)
        array = np.ndarray((accessor["count"],), dtype="<f4", buffer=binary,
                           offset=offset, strides=(stride,)).copy()
        payloads.append(array)
    return sampler.get("interpolation", "LINEAR"), payloads


def main():
    scene = bpy.data.scenes.new("BULK_MORPH_SMOKE")
    bpy.context.window.scene = scene
    scene.render.fps = 30
    scene.frame_start, scene.frame_end = 0, 6
    legacy = mesh_object(scene, "Legacy")
    bulk = mesh_object(scene, "Bulk")
    frames = [0, 1, 2, 4, 5, 6]
    samples = [{"frame": frame} for frame in frames]
    weights = np.asarray([[0, 0, 0], [1, 0, 0], [0, 1, 0],
                          [0, 0, 1], [0.25, 0.5, 0.25], [0, 0, 0]], dtype=np.float32)
    for row, frame in zip(weights, frames):
        for key, value in zip(list(legacy.data.shape_keys.key_blocks)[1:], row):
            key.value = float(value)
            key.keyframe_insert("value", frame=frame)
    for curve in action_curves(legacy.data.shape_keys):
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"
    result = write_morph_actions(bpy, np, {"Smoke": (bulk, weights)}, samples)
    assert result["curves"] == 3 and result["keys"] == 18

    old_curves = {curve.data_path: curve for curve in action_curves(legacy.data.shape_keys)}
    new_curves = {curve.data_path: curve for curve in action_curves(bulk.data.shape_keys)}
    assert old_curves.keys() == new_curves.keys()
    for path in old_curves:
        old, new = old_curves[path], new_curves[path]
        old_co, new_co = np.empty(12, dtype=np.float32), np.empty(12, dtype=np.float32)
        old.keyframe_points.foreach_get("co", old_co)
        new.keyframe_points.foreach_get("co", new_co)
        assert np.array_equal(old_co, new_co), f"Dense key mismatch: {path}"
        assert all(key.interpolation == "LINEAR" for key in new.keyframe_points)
        for frame in np.arange(-0.5, 7.01, 0.125):
            assert old.evaluate(float(frame)) == new.evaluate(float(frame)), f"Interpolation mismatch: {path}, {frame}"

    for frame in np.arange(0, 6.01, 0.125):
        scene.frame_set(int(frame), subframe=float(frame) % 1)
        depsgraph = bpy.context.evaluated_depsgraph_get()
        old_eval, new_eval = legacy.evaluated_get(depsgraph), bulk.evaluated_get(depsgraph)
        old_points = np.asarray([tuple(vertex.co) for vertex in old_eval.data.vertices], dtype=np.float32)
        new_points = np.asarray([tuple(vertex.co) for vertex in new_eval.data.vertices], dtype=np.float32)
        assert np.array_equal(old_points, new_points), f"Evaluated surface mismatch: frame {frame}"

    # Force the same SCENE sampling path used by the graduate exporter, then
    # compare FLOAT payloads rather than filenames, object names, or JSON order.
    with tempfile.TemporaryDirectory(prefix="graduate-bulk-morph-smoke-") as folder:
        paths = []
        for obj in (legacy, bulk):
            for other in scene.objects:
                other.select_set(False)
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            scene.frame_set(0)
            path = Path(folder) / (obj.name + ".glb")
            export_result = bpy.ops.export_scene.gltf(
                filepath=str(path), export_format="GLB", use_selection=True,
                use_active_scene=True, export_cameras=False, export_lights=False,
                export_animations=True, export_animation_mode="SCENE",
                export_anim_scene_split_object=False, export_anim_slide_to_zero=False,
                export_force_sampling=True, export_frame_step=1,
                export_bake_animation=True, export_optimize_animation_size=False,
                export_optimize_animation_keep_anim_object=True,
                export_morph=True, export_morph_normal=True,
                export_morph_animation=True, export_morph_reset_sk_data=False,
            )
            assert "FINISHED" in export_result
            paths.append(path)
        old_mode, old_values = weights_payload(paths[0])
        new_mode, new_values = weights_payload(paths[1])
        assert old_mode == new_mode == "LINEAR"
        assert all(np.array_equal(old, new) for old, new in zip(old_values, new_values)), "glTF sampled morph payload differs"

    print("BULK_MORPH_SMOKE_PASS " + json.dumps({
        "denseKeysEqual": True, "subframeEvaluationEqual": True,
        "evaluatedSurfacesEqual": True, "gltfWeightSamplersEqual": True,
        "samples": len(frames), "targets": 3,
    }), flush=True)


if __name__ == "__main__":
    main()
