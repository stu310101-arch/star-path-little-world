"""Export the prepared graduate as ONE character-only GLB for Godot.

Run in Blender against Male_Graduate_GameReady.blend, after coordination:
    blender --background Male_Graduate_GameReady.blend --python-exit-code 1 \
        --python tools/export_graduate_godot.py --

Produces art/Graduate/Godot/assets/graduate.glb with Walk, Run, JumpDown and Idle.
Source scenes are sampled; a temporary scene receives baked bone transforms
and common, exact per-frame morphs. Fully evaluated surfaces are unskinned
before morph caching, preserving Solidify/Bevel geometry. The glTF SCENE
mode exports only that staging scene, so unrelated source actions never enter
the asset. The single baked animation is split into the four named clips.

The source .blend is NEVER saved. Cameras, lights, studio, environments and
objects tagged preview_fx are excluded. Blender visibility animation is not
part of glTF; Godot owns flash at 1.3s and hide at 1.333333s in JumpDown.

Scale contract: body height 4.8 source units -> 1.75m, applied exactly once to
the export root. The hat extends above the 1.75m body. Blender -Y forward
becomes Godot +Z under the standard glTF Y-up conversion.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import json
import math
import os
from pathlib import Path
import re
import struct
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[1]
FPS = 30
CLIP_FPS = {"Walk": 30, "Run": 30, "JumpDown": 30, "Idle": 56}
CLIPS = (("Walk", "01_WALK", 36), ("Run", "02_RUN", 24), ("JumpDown", "03_JUMP", 72), ("Idle", "04_IDLE", 120))
COMPONENT_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def action_curves(action):
    if action is None:
        return []
    if hasattr(action, "layers"):
        return [curve for layer in action.layers for strip in layer.strips for bag in strip.channelbags for curve in bag.fcurves]
    return list(action.fcurves)


def set_linear(id_block):
    if id_block.animation_data and id_block.animation_data.action:
        for curve in action_curves(id_block.animation_data.action):
            for key in curve.keyframe_points:
                key.interpolation = "LINEAR"


def role_map(scene):
    meshes = {}
    for obj in scene.objects:
        role = obj.get("graduate_role")
        if obj.type != "MESH" or not role or role == "Studio floor" or obj.get("preview_fx"):
            continue
        if role in meshes:
            raise ValueError(f"Duplicate graduate_role {role!r} in {scene.name}")
        meshes[role] = obj
    if not meshes or "01 | Pleated bachelor gown" not in meshes:
        raise ValueError(f"No complete graduate character in {scene.name}")
    rigs = [obj for obj in scene.objects if obj.type == "ARMATURE" and not obj.get("preview_fx")]
    if len(rigs) != 1:
        raise ValueError(f"Expected one character rig in {scene.name}, found {len(rigs)}")
    return rigs[0], meshes


def topology_signature(mesh):
    return (
        len(mesh.vertices),
        tuple(tuple(polygon.vertices) for polygon in mesh.polygons),
        tuple(polygon.material_index for polygon in mesh.polygons),
    )


def skin_weights(obj, mesh, bone_names, np):
    indices = {name: index for index, name in enumerate(bone_names)}
    groups = {group.index: indices[group.name] for group in obj.vertex_groups if group.name in indices}
    weights = np.zeros((len(mesh.vertices), len(bone_names)), dtype=np.float64)
    for vertex in mesh.vertices:
        for group in vertex.groups:
            if group.group in groups:
                weights[vertex.index, groups[group.group]] += group.weight
    sums = weights.sum(axis=1)
    weighted = sums > 1e-8
    weights[weighted] /= sums[weighted, None]
    return weights, weighted


def sample_sources(bpy, np):
    """Read evaluated source geometry and poses without retaining evaluated meshes."""
    templates, samples, report = {}, [], []
    common_roles, common_bones, common_rest = None, None, None
    first_rig = None
    timeline_start = 0
    segments = []
    for label, prefix, period in CLIPS:
        found = [scene for scene in bpy.data.scenes if scene.name.startswith(prefix)]
        if len(found) != 1:
            raise ValueError(f"Expected exactly one {prefix} scene; found {[scene.name for scene in found]}")
        scene = found[0]
        if bpy.context.window:
            bpy.context.window.scene = scene
        rig, meshes = role_map(scene)
        roles = sorted(meshes)
        bone_names = [bone.name for bone in rig.data.bones]
        rest = np.asarray([np.asarray(rig.data.bones[name].matrix_local) for name in bone_names])
        if common_roles is None:
            common_roles, common_bones, common_rest = roles, bone_names, rest
            first_rig = rig
        elif roles != common_roles or bone_names != common_bones or not np.allclose(rest, common_rest, atol=1e-5):
            raise ValueError(f"Character roles, skeleton or bind pose differ in {scene.name}; cannot share a GLB")
        inverse_rest = np.linalg.inv(rest)
        original_frame, original_subframe = scene.frame_current, scene.frame_subframe
        hidden = [(obj, obj.hide_render, obj.hide_viewport, obj.hide_get()) for obj in [rig, *meshes.values()]]
        muted = []
        for obj in [rig, *meshes.values()]:
            action = obj.animation_data.action if obj.animation_data else None
            for curve in action_curves(action):
                if curve.data_path in ("hide_render", "hide_viewport"):
                    muted.append((curve, curve.mute))
                    curve.mute = True
        source_fps = scene.render.fps / scene.render.fps_base
        if abs(source_fps - CLIP_FPS[label]) > 1e-5:
            raise ValueError(f"Unexpected source timing for {label}: {source_fps} fps")
        segments.append({"name": label, "startFrame": timeline_start, "endFrame": timeline_start + period, "duration": period / source_fps, "fps": source_fps, "loop": label != "JumpDown"})
        try:
            for offset in range(period + 1):
                # Duplicate the first loop pose at its endpoint; hold the one-shot's last pose.
                source_frame = offset + 1 if offset < period else (1 if label != "JumpDown" else period)
                scene.frame_set(source_frame)
                for obj, *_ in hidden:
                    obj.hide_render = False
                    obj.hide_viewport = False
                    obj.hide_set(False)
                bpy.context.view_layer.update()
                depsgraph = bpy.context.evaluated_depsgraph_get()
                evaluated_rig = rig.evaluated_get(depsgraph)
                rig_world = evaluated_rig.matrix_world.copy()
                if abs(rig_world.determinant()) < 1e-8:
                    raise ValueError(f"Singular character root transform in {scene.name}, frame {source_frame}")
                bone_pose = {name: evaluated_rig.pose.bones[name].matrix.copy() for name in bone_names}
                bone_deformation = np.asarray([np.asarray(bone_pose[name]) for name in bone_names]) @ inverse_rest
                captured = {"frame": timeline_start + offset, "clip": label, "sourceFrame": source_frame, "rigWorld": rig_world, "bones": bone_pose, "meshes": {}}
                for role in roles:
                    obj = meshes[role]
                    armatures = [modifier for modifier in obj.modifiers if modifier.type == "ARMATURE" and modifier.show_viewport]
                    if len(armatures) > 1 or any(modifier.object != rig or modifier.use_deform_preserve_volume for modifier in armatures):
                        raise ValueError(f"Unsupported armature/deformation setup on {obj.name}; source needs linear blend skinning")
                    evaluated = obj.evaluated_get(depsgraph)
                    evaluated_mesh = evaluated.to_mesh(preserve_all_data_layers=True, depsgraph=depsgraph)
                    try:
                        signature = topology_signature(evaluated_mesh)
                        weights, weighted = skin_weights(obj, evaluated_mesh, bone_names, np)
                        if role not in templates:
                            maximum_influences = int(np.max(np.count_nonzero(weights > 1e-7, axis=1), initial=0))
                            if maximum_influences > 8:
                                raise ValueError(f"{maximum_influences} bone influences on {role}; exceeds Godot's eight-influence asset path")
                            data = bpy.data.meshes.new_from_object(evaluated, preserve_all_data_layers=True, depsgraph=depsgraph)
                            data.name = "EXPORT_TEMPLATE_" + re.sub(r"[^A-Za-z0-9]+", "_", role)
                            templates[role] = {"data": data, "signature": signature, "weights": weights, "groups": [group.name for group in obj.vertex_groups], "maximumInfluences": maximum_influences}
                        elif signature != templates[role]["signature"] or not np.allclose(weights, templates[role]["weights"], atol=1e-6):
                            raise ValueError(f"Topology or vertex weights changed for {role} in {scene.name}, frame {source_frame}")
                        points = np.empty(len(evaluated_mesh.vertices) * 3, dtype=np.float64)
                        evaluated_mesh.vertices.foreach_get("co", points)
                        points = points.reshape(-1, 3)
                        mesh_to_rig = np.asarray(rig_world.inverted() @ evaluated.matrix_world)
                        posed = np.c_[points, np.ones(len(points))] @ mesh_to_rig.T
                        deformation = np.einsum("vb,bij->vij", weights, bone_deformation)
                        deformation[~weighted] = np.eye(4)
                        try:
                            inverse_deformation = np.linalg.inv(deformation)
                        except np.linalg.LinAlgError as error:
                            raise ValueError(f"Singular skinning transform on {role} in {scene.name}, frame {source_frame}") from error
                        unskinned = np.einsum("vij,vj->vi", inverse_deformation, posed)[:, :3]
                        if not np.isfinite(unskinned).all():
                            raise ValueError(f"Non-finite evaluated surface on {role}")
                        captured["meshes"][role] = unskinned.astype(np.float32)
                    finally:
                        evaluated.to_mesh_clear()
                samples.append(captured)
                if offset % 12 == 0 or offset == period:
                    print(f"EXPORT_SAMPLE clip={label} source_frame={source_frame} sample={offset+1}/{period+1}", flush=True)
        finally:
            for curve, was_muted in muted:
                curve.mute = was_muted
            scene.frame_set(original_frame, subframe=original_subframe)
            for obj, hide_render, hide_viewport, hide_set in hidden:
                obj.hide_render, obj.hide_viewport = hide_render, hide_viewport
                obj.hide_set(hide_set)
        report.append({"scene": scene.name, "clip": label, "sourceFrames": period, "samplesIncludingEndpoint": period + 1, "activeRigAction": rig.animation_data.action.name if rig.animation_data and rig.animation_data.action else None, "meshes": len(roles)})
        timeline_start += period + 2
    return templates, samples, segments, first_rig, report


def cache_morphs(positions, np, max_targets=0):
    """Lossless with respect to the sampled float32 geometry, including holds.

    One cache shape is active at each key, at most two during ordinary linear
    playback (four when blending clips). Byte-identical poses share a target.
    Godot has no documented 60-target cap, so no arbitrary cap is imposed.
    """
    basis = np.asarray(positions[0], dtype=np.float32).copy()
    lookup = {basis.tobytes(): -1}
    targets, assignments = [], []
    for positions_at_frame in positions:
        values = np.asarray(positions_at_frame, dtype=np.float32)
        encoded = values.tobytes()
        if encoded not in lookup:
            lookup[encoded] = len(targets)
            targets.append(values.copy())
        assignments.append(lookup[encoded])
    if max_targets and len(targets) > max_targets:
        raise ValueError(f"Exact cache needs {len(targets)} morph targets; explicitly configured cap is {max_targets}")
    weights = np.zeros((len(positions), len(targets)), dtype=np.float32)
    for index, assignment in enumerate(assignments):
        if assignment >= 0:
            weights[index, assignment] = 1.0
    return basis, targets, weights, {
        "strategy": "exact_float32_frame_cache", "targets": len(targets),
        "samples": len(positions), "uniquePoses": len(lookup),
        "maxPreSkinError": 0.0, "rmsError": 0.0,
        "maxActiveTargetsAtKeys": 1 if targets else 0,
        "maxActiveTargetsDuringLinearPlayback": min(2, len(targets)),
    }


def create_staging(bpy, np, templates, samples, first_rig, scale, max_targets):
    from mathutils import Matrix
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from export_morph_bulk import write_morph_actions

    scene = bpy.data.scenes.new("EXPORT_ONLY_Graduate_Godot")
    bpy.context.window.scene = scene
    scene.render.fps, scene.render.fps_base = FPS, 1.0
    scene.frame_start, scene.frame_end = 0, samples[-1]["frame"]
    root = bpy.data.objects.new("Graduate", None)
    scene.collection.objects.link(root)
    root.scale = (scale,) * 3
    rig = first_rig.copy()
    rig.data = first_rig.data.copy()
    rig.name = "GraduateRig"
    rig.animation_data_clear()
    rig.parent = root
    rig.matrix_parent_inverse = Matrix.Identity(4)
    rig.matrix_basis = Matrix.Identity(4)
    rig.hide_render = False
    rig.hide_viewport = False
    scene.collection.objects.link(rig)
    rig.hide_set(False)
    for constraint in list(rig.constraints):
        rig.constraints.remove(constraint)
    for bone in rig.pose.bones:
        for constraint in list(bone.constraints):
            bone.constraints.remove(constraint)
        bone.rotation_mode = "QUATERNION"
        bone.matrix_basis = Matrix.Identity(4)
    report = []
    morph_objects = {}
    for index, role in enumerate(sorted(templates)):
        template = templates[role]
        basis, targets, values, fit = cache_morphs([sample["meshes"][role] for sample in samples], np, max_targets)
        data = template["data"].copy()
        data.vertices.foreach_set("co", np.asarray(basis, dtype=np.float32).ravel())
        data.update()
        obj = bpy.data.objects.new(f"GraduateMesh_{index:02d}_" + re.sub(r"[^A-Za-z0-9]+", "_", role).strip("_"), data)
        scene.collection.objects.link(obj)
        obj.parent = rig
        obj.matrix_basis = Matrix.Identity(4)
        for group_name in template["groups"]:
            obj.vertex_groups.new(name=group_name)
        armature = obj.modifiers.new("BakedCharacterSkin", "ARMATURE")
        armature.object = rig
        armature.use_deform_preserve_volume = False
        if targets:
            obj.shape_key_add(name="Basis")
            for target_index, target in enumerate(targets):
                key = obj.shape_key_add(name=f"Cloth_Cache_{target_index+1:03d}")
                key.data.foreach_set("co", np.asarray(target, dtype=np.float32).ravel())
                key.slider_min, key.slider_max = 0.0, 1.0
            morph_objects[role] = obj, values
        fit.update({"role": role, "vertices": len(data.vertices), "maximumBoneInfluences": template["maximumInfluences"], "maxPreSkinErrorMeters": fit["maxPreSkinError"] * scale})
        report.append(fit)
        print(f"EXPORT_MORPH role={role} targets={fit['targets']} max_error_m={fit['maxPreSkinErrorMeters']:.8f}", flush=True)
    previous_quaternions = {}
    for sample_index, sample in enumerate(samples):
        frame = sample["frame"]
        rig.rotation_mode = "QUATERNION"
        rig.matrix_basis = sample["rigWorld"]
        if "__rig__" in previous_quaternions and rig.rotation_quaternion.dot(previous_quaternions["__rig__"]) < 0:
            rig.rotation_quaternion.negate()
        previous_quaternions["__rig__"] = rig.rotation_quaternion.copy()
        for path in ("location", "rotation_quaternion", "scale"):
            rig.keyframe_insert(path, frame=frame)
        for bone in rig.pose.bones:
            kwargs = {"invert": True}
            if bone.parent:
                kwargs.update(parent_matrix=sample["bones"][bone.parent.name], parent_matrix_local=bone.parent.bone.matrix_local)
            bone.matrix_basis = bone.bone.convert_local_to_pose(sample["bones"][bone.name], bone.bone.matrix_local, **kwargs)
            if bone.name in previous_quaternions and bone.rotation_quaternion.dot(previous_quaternions[bone.name]) < 0:
                bone.rotation_quaternion.negate()
            previous_quaternions[bone.name] = bone.rotation_quaternion.copy()
            for path in ("location", "rotation_quaternion", "scale"):
                bone.keyframe_insert(path, frame=frame, group=bone.name)
    set_linear(rig)
    rig.animation_data.action.name = "EXPORT_ONLY_ThreeClips"
    write_morph_actions(bpy, np, morph_objects, samples)
    scene.frame_set(0)
    for obj in scene.objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = rig
    return scene, report


def read_glb(path):
    raw = Path(path).read_bytes()
    magic, version, length = struct.unpack_from("<4sII", raw, 0)
    if magic != b"glTF" or version != 2 or length != len(raw):
        raise ValueError("Invalid GLB header")
    document, binary = None, b""
    offset = 12
    while offset < len(raw):
        size, chunk_type = struct.unpack_from("<II", raw, offset)
        offset += 8
        chunk = raw[offset:offset + size]
        offset += size
        if chunk_type == 0x4E4F534A:
            document = json.loads(chunk.decode("utf-8"))
        elif chunk_type == 0x004E4942:
            binary = chunk
    if document is None:
        raise ValueError("GLB has no JSON chunk")
    return document, bytearray(binary)


def write_glb(path, document, binary):
    document["buffers"] = [{"byteLength": len(binary)}]
    json_chunk = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    json_chunk += b" " * (-len(json_chunk) % 4)
    binary += b"\x00" * (-len(binary) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    Path(path).write_bytes(struct.pack("<4sII", b"glTF", 2, total) + struct.pack("<II", len(json_chunk), 0x4E4F534A) + json_chunk + struct.pack("<II", len(binary), 0x004E4942) + binary)


def accessor_values(document, binary, index, np):
    accessor = document["accessors"][index]
    if accessor["componentType"] != 5126 or "sparse" in accessor:
        raise ValueError("Animation splitting expects nonsparse FLOAT accessors")
    view = document["bufferViews"][accessor["bufferView"]]
    components = COMPONENT_COUNTS[accessor["type"]]
    offset = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    stride = view.get("byteStride", components * 4)
    return np.ndarray((accessor["count"], components), dtype="<f4", buffer=binary, offset=offset, strides=(stride, 4)).copy()


def append_accessor(document, binary, values, kind, np, limits=False):
    values = np.asarray(values, dtype="<f4").reshape(-1, COMPONENT_COUNTS[kind])
    binary += b"\x00" * (-len(binary) % 4)
    data = values.tobytes()
    view_index = len(document.setdefault("bufferViews", []))
    document["bufferViews"].append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data)})
    binary += data
    accessor = {"bufferView": view_index, "componentType": 5126, "count": len(values), "type": kind}
    if limits:
        accessor["min"], accessor["max"] = values.min(axis=0).tolist(), values.max(axis=0).tolist()
    index = len(document.setdefault("accessors", []))
    document["accessors"].append(accessor)
    return index


def split_animations(path, segments, np):
    document, binary = read_glb(path)
    animations = document.get("animations", [])
    if len(animations) != 1:
        raise ValueError(f"SCENE export should produce exactly one animation, got {len(animations)}")
    baked = animations[0]
    split = []
    for segment in segments:
        samplers = []
        start, end = segment["startFrame"] / FPS, segment["endFrame"] / FPS
        for sampler in baked["samplers"]:
            times = accessor_values(document, binary, sampler["input"], np).ravel()
            output = accessor_values(document, binary, sampler["output"], np)
            if len(output) % len(times):
                raise ValueError("Unexpected sampled animation output count")
            chosen = np.flatnonzero((times >= start - 1e-5) & (times <= end + 1e-5))
            if len(chosen) != segment["endFrame"] - segment["startFrame"] + 1:
                raise ValueError(f"Incomplete baked sampling for {segment['name']}: {len(chosen)} time keys")
            local_times = (times[chosen] - start) * FPS / segment["fps"]
            local_times[0], local_times[-1] = 0, segment["duration"]
            grouped = output.reshape(len(times), -1)
            selected = grouped[chosen].reshape(-1, output.shape[1])
            kind = document["accessors"][sampler["output"]]["type"]
            samplers.append({
                "input": append_accessor(document, binary, local_times, "SCALAR", np, limits=True),
                "output": append_accessor(document, binary, selected, kind, np),
                "interpolation": sampler.get("interpolation", "LINEAR"),
            })
        split.append({"name": segment["name"], "channels": baked["channels"], "samplers": samplers, "extras": {"loop": segment["loop"], "fps": segment["fps"]}})
    document["animations"] = split
    document.setdefault("asset", {}).setdefault("extras", {}).update({
        "bodyHeightMeters": 1.75, "forwardAxis": "+Z", "sourceForwardAxis": "-Y",
        "jumpFlashSeconds": 1.3, "jumpHideSeconds": 40 / 30,
        "visibilityAndParticles": "Runtime Godot events; not part of the GLB",
    })
    write_glb(path, document, binary)


def validate_glb(path, np, max_targets):
    document, binary = read_glb(path)
    if document.get("cameras") or "KHR_lights_punctual" in document.get("extensions", {}):
        raise ValueError("Camera/light leaked into the character asset")
    if len(document.get("scenes", [])) != 1:
        raise ValueError("Expected one exported scene")
    names = [animation.get("name") for animation in document.get("animations", [])]
    if names != [clip[0] for clip in CLIPS]:
        raise ValueError(f"Incorrect clips: {names}")
    primitives, morph_meshes = 0, {}
    for index, mesh in enumerate(document.get("meshes", [])):
        counts = {len(primitive.get("targets", [])) for primitive in mesh["primitives"]}
        if len(counts) != 1 or (max_targets and max(counts) > max_targets):
            raise ValueError(f"Inconsistent/excessive morph targets on {mesh.get('name')}: {counts}")
        count = next(iter(counts))
        if count:
            morph_meshes[index] = count
        primitives += len(mesh["primitives"])
    morph_nodes = {index for index, node in enumerate(document["nodes"]) if node.get("mesh") in morph_meshes}
    if not morph_nodes or not document.get("skins"):
        raise ValueError("Missing physical morphs or skeleton")
    clips = []
    for animation, (_, _, period) in zip(document["animations"], CLIPS):
        targets = {channel["target"]["node"] for channel in animation["channels"] if channel["target"]["path"] == "weights"}
        if not morph_nodes.issubset(targets):
            raise ValueError(f"Missing cloth weight tracks in {animation['name']}: {morph_nodes-targets}")
        for sampler in animation["samplers"]:
            times = accessor_values(document, binary, sampler["input"], np).ravel()
            values = accessor_values(document, binary, sampler["output"], np)
            if not np.isfinite(times).all() or not np.isfinite(values).all() or np.any(np.diff(times) <= 0):
                raise ValueError(f"Invalid animation samples in {animation['name']}")
            if abs(float(times[0])) > 1e-5 or abs(float(times[-1]) - period / CLIP_FPS[animation["name"]]) > 1e-5:
                raise ValueError(f"Incorrect duration in {animation['name']}")
        clips.append({"name": animation["name"], "durationSeconds": period / CLIP_FPS[animation["name"]], "morphChannels": len(targets), "channels": len(animation["channels"])})
    return {"file": str(path), "sizeBytes": Path(path).stat().st_size, "scenes": 1, "meshes": len(document.get("meshes", [])), "primitives": primitives, "skins": len(document["skins"]), "morphMeshes": len(morph_meshes), "maxTargetsPerPrimitive": max(morph_meshes.values()), "animations": clips, "noCamerasOrLights": True}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--output", type=Path, default=ROOT / "art" / "Graduate" / "Godot" / "assets" / "graduate.glb")
    parser.add_argument("--max-morph-targets", type=int, default=0, help="Optional explicit cap; 0 preserves all exact cache targets")
    parser.add_argument("--scale", type=float, default=1.75 / 4.8)
    if argv is None:
        argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    args = parser.parse_args(argv)
    if args.max_morph_targets < 0 or args.scale <= 0:
        parser.error("Use a nonnegative morph cap (0 means unlimited) and positive scale")
    os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
    os.environ.setdefault("OMP_NUM_THREADS", "1")
    import bpy
    import numpy as np

    output = args.output.expanduser().resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    templates, samples, segments, source_rig, sources = sample_sources(bpy, np)
    scene, morph_report = create_staging(bpy, np, templates, samples, source_rig, args.scale, args.max_morph_targets)
    with tempfile.TemporaryDirectory(prefix=".graduate-export-", dir=output.parent) as stage_dir:
        temporary = Path(stage_dir) / "graduate.glb"
        options = {
            "filepath": str(temporary), "export_format": "GLB",
            "use_selection": True, "use_active_scene": True,
            "export_cameras": False, "export_lights": False, "export_extras": False,
            "export_yup": True, "export_apply": False, "export_materials": "EXPORT",
            "export_animations": True, "export_animation_mode": "SCENE",
            "export_anim_scene_split_object": False, "export_anim_slide_to_zero": False,
            "export_force_sampling": True, "export_frame_step": 1,
            "export_bake_animation": True, "export_anim_single_armature": False,
            "export_optimize_animation_size": False,
            "export_optimize_animation_keep_anim_armature": True,
            "export_optimize_animation_keep_anim_object": True,
            "export_skins": True, "export_def_bones": True,
            "export_rest_position_armature": True, "export_armature_object_remove": False,
            "export_morph": True, "export_morph_normal": True,
            "export_morph_tangent": False, "export_morph_animation": True,
            "export_morph_reset_sk_data": False, "export_current_frame": True,
            "export_influence_nb": 8, "export_all_influences": False,
        }
        supported = {prop.identifier for prop in bpy.ops.export_scene.gltf.get_rna_type().properties}
        unknown = set(options) - supported
        if unknown:
            raise RuntimeError(f"Installed glTF exporter lacks required options: {sorted(unknown)}")
        result = bpy.ops.export_scene.gltf(**options)
        if "FINISHED" not in result:
            raise RuntimeError(f"glTF export did not finish: {result}")
        split_animations(temporary, segments, np)
        validation = validate_glb(temporary, np, args.max_morph_targets)
        validation["file"] = str(output)
        report = {
            "generatedAtUtc": datetime.now(timezone.utc).isoformat(),
            "sourceBlend": bpy.data.filepath, "sources": sources,
            "scaleAppliedOnceAtRoot": args.scale,
            "sourceBodyHeight": 4.8, "bodyHeightMeters": 4.8 * args.scale,
            "sourceForward": "-Y", "godotForward": "+Z", "godotUp": "+Y",
            "morphStrategy": "Exact float32 frame cache from fully evaluated, inverse-skinned surfaces; shared targets across all clips; byte-identical poses deduplicated; at most two active targets during ordinary playback; no external cloth cache",
            "morphApproximationErrorMeters": 0.0,
            "morphMeshes": morph_report, "glb": validation,
            "runtimeEvents": {"JumpDown": {"flashSeconds": 1.3, "hideSeconds": 40 / 30}},
            "validationLimit": "Structural and per-sampled-vertex pre-skin error checks; Godot playback/performance and visual inspection remain required.",
        }
        temporary.replace(output)
        report_path = output.with_name("graduate-export-validation.json")
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print("GRADUATE_GODOT_EXPORT_DONE " + json.dumps(validation), flush=True)


if __name__ == "__main__":
    main()
