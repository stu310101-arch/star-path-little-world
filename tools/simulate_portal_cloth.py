"""Bake real-size, non-looping portal cloth without changing Walk or Run.

Run in the authored portal file, for example:
  blender -b Male_Graduate_Portal_Authored.blend -t 4 --python this_file -- --quality 16

Use --warmup-test for a diagnostic NPZ only. A shorter --end requires a separate
--output and creates a probe, never an apparently complete portal deliverable.
The script deliberately does not start another Blender process.
"""
import argparse
import json
import sys
from pathlib import Path

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.geometry import barycentric_transform, closest_point_on_tri

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from cloth_surface_helpers import (  # noqa: E402
    body_surface_positions,
    closed_body_topology,
    enforce_body_clearance,
)

OUT = ROOT / "art" / "Graduate"
ANIM = OUT / "animation"
SCALE = 1.75 / 4.8
GOWN_ROLE = "01 | Pleated bachelor gown"
BODY_ROLE = "Graduate | original face, hands and trousers"


def fcurves(action):
    if action is None:
        return []
    return [fc for layer in action.layers for strip in layer.strips
            for bag in strip.channelbags for fc in bag.fcurves]


def evaluated_points(obj, scale=SCALE):
    """Return actual world points; caller hides topology-changing modifiers."""
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    result = np.asarray([(evaluated.matrix_world @ v.co)[:] for v in mesh.vertices],
                        dtype=np.float64) * scale
    evaluated.to_mesh_clear()
    return result


def evaluated_faces(obj):
    evaluated = obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
    mesh = evaluated.to_mesh()
    result = [tuple(p.vertices) for p in mesh.polygons]
    evaluated.to_mesh_clear()
    return result


class SkinBinding:
    """Linear skinning in world space, including mesh, rig and root transforms.

    Armature deformation is A * skin * inverse(A) * O. The older locomotion
    scripts could use skin alone because their object and rig matrices were
    identity. Portal root translation makes that shortcut invalid.
    """

    def __init__(self, obj, rig):
        self.obj, self.rig = obj, rig
        mods = [m for m in obj.modifiers if m.type == "ARMATURE" and m.show_viewport]
        if len(mods) > 1 or (mods and mods[0].object != rig):
            raise RuntimeError("Unsupported armature stack on " + obj.name)
        self.deforms = bool(mods)
        if mods and mods[0].use_deform_preserve_volume:
            raise RuntimeError("Portal inverse LBS requires Preserve Volume disabled on " + obj.name)
        self.rest_inverse = {b.name: b.matrix_local.inverted() for b in rig.data.bones
                             if b.use_deform}
        self.signatures = []
        for vertex in obj.data.vertices:
            weights = []
            if self.deforms:
                for group in vertex.groups:
                    name = obj.vertex_groups[group.group].name
                    if name in self.rest_inverse and group.weight > 0:
                        weights.append((name, group.weight))
            total = sum(w for _, w in weights)
            self.signatures.append(tuple((n, w / total) for n, w in weights) if total else ())

    def world_matrices(self, inverse=False):
        armature = self.rig.matrix_world.copy()
        object_in_armature = armature.inverted_safe() @ self.obj.matrix_world
        bone_matrices = {name: self.rig.pose.bones[name].matrix @ inv
                         for name, inv in self.rest_inverse.items()}
        cache = {}
        for signature in set(self.signatures):
            if not signature:
                matrix = self.obj.matrix_world.copy()
            else:
                skin = Matrix([[0.0] * 4 for _ in range(4)])
                for name, weight in signature:
                    bone = bone_matrices[name]
                    for row in range(4):
                        for col in range(4):
                            skin[row][col] += bone[row][col] * weight
                matrix = armature @ skin @ object_in_armature
            cache[signature] = matrix.inverted_safe() if inverse else matrix
        return [cache[s] for s in self.signatures]

    def inverse_points(self, world_metres):
        return [m @ Vector(p / SCALE) for m, p in zip(self.world_matrices(True), world_metres)]


def set_mesh_basis(obj, coords):
    obj.shape_key_clear()
    for vertex, co in zip(obj.data.vertices, coords):
        vertex.co = co
    obj.data.update()


def bake_keys(obj, samples, start, label):
    """One-shot triangular key influence; hold endpoints, no Cycles modifier."""
    obj.shape_key_clear()
    obj.shape_key_add(name="Basis")
    for i, coords in enumerate(samples):
        key = obj.shape_key_add(name="%s_%04d" % (label, start + i))
        for point, co in zip(key.data, coords):
            point.co = co
        frame = start + i
        times = [(frame, 1.0)]
        if i:
            times.insert(0, (frame - 1, 0.0))
        if i + 1 < len(samples):
            times.append((frame + 1, 0.0))
        for keyframe, value in times:
            key.value = value
            key.keyframe_insert("value", frame=keyframe)
        key.value = 0
    action = obj.data.shape_keys.animation_data.action
    action.name = label
    action.use_fake_user = True
    for curve in fcurves(action):
        curve.extrapolation = "CONSTANT"
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"


def add_proxy(sim, name, positions, polygons):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(positions, [], polygons)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    sim.collection.objects.link(obj)
    return obj


def animate_proxy(obj, inputs, warmup):
    """Hold input 0 during pre-roll; then play every authored sample once."""
    obj.shape_key_add(name="Basis")
    for i, points in enumerate(inputs):
        key = obj.shape_key_add(name="Input_%04d" % i)
        for dst, co in zip(key.data, points):
            dst.co = co
        frame = warmup + i + 1
        times = [(frame, 1.0)]
        if i == 0:
            times.insert(0, (1, 1.0))
        else:
            times.insert(0, (frame - 1, 0.0))
        if i + 1 < len(inputs):
            times.append((frame + 1, 0.0))
        for f, value in times:
            key.value = value
            key.keyframe_insert("value", frame=f)
        key.value = 0
    for curve in fcurves(obj.data.shape_keys.animation_data.action):
        curve.extrapolation = "CONSTANT"
        for key in curve.keyframe_points:
            key.interpolation = "LINEAR"


def add_collision(obj):
    obj.modifiers.new("One-shot cloth contact", "COLLISION")
    obj.collision.thickness_outer = .0025
    obj.collision.thickness_inner = .002
    obj.collision.cloth_friction = .2


def make_stole_anchors(gown, initial_gown, stoles, initial_stoles, source_rest):
    gown.data.calc_loop_triangles()
    triangles = [tuple(t.vertices) for t in gown.data.loop_triangles]
    world = [Vector(p) for p in initial_gown]
    anchors = {}
    for obj in stoles:
        local = {}
        for index, values in enumerate(initial_stoles[obj]):
            if source_rest[obj][index][2] > 3.81:
                continue
            point = Vector(values)
            best = None
            for ids in triangles:
                a, b, c = [world[j] for j in ids]
                if (b-a).cross(c-a).length_squared < 1e-18:
                    continue
                closest = closest_point_on_tri(point, a, b, c)
                distance = (point - closest).length_squared
                if best is None or distance < best[0]:
                    best = distance, ids, closest
            if best is None:
                raise RuntimeError("No valid gown triangle for stole binding")
            _, ids, closest = best
            a, b, c = [world[j] for j in ids]
            bary = barycentric_transform(closest, a, b, c,
                                         Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)))
            signed_gap = (point - closest).dot((b-a).cross(c-a).normalized())
            # A stole belongs on the exterior of the consistently oriented
            # gown surface, even if its old binding initially sits inside it.
            gap = max(.025 * SCALE, abs(signed_gap))
            local[index] = ids, bary, gap
        anchors[obj] = local
    return anchors


def simulate_portal(scene_name="03_PORTAL", warmup=25, quality=16,
                    frame_end=None, output=None, warmup_test=False,
                    artifact_prefix="portal", action_prefix="Graduate_Portal", display_name="Portal"):
    scene = next((s for s in bpy.data.scenes if s.name.startswith(scene_name)), None)
    if scene is None:
        raise RuntimeError("Open the authored one-shot file first: scene " + scene_name + " is absent")
    if not artifact_prefix.replace("_", "").isalnum():
        raise ValueError("Artifact prefix must contain only letters, digits and underscores")
    event = artifact_prefix.upper() + "_CLOTH"
    bpy.context.window.scene = scene
    start, end = scene.frame_start, min(frame_end or scene.frame_end, scene.frame_end)
    if end < start or warmup < 1 or quality < 4:
        raise ValueError("Invalid frame range, warmup, or quality")
    if end != scene.frame_end and output is None and not warmup_test:
        raise ValueError("A partial probe requires --output to a separate candidate file")
    target = Path(output).resolve() if output else OUT / "Male_Graduate_Portal.blend"
    ANIM.mkdir(parents=True, exist_ok=True)
    rig = next(o for o in scene.objects if o.type == "ARMATURE")
    gown = next(o for o in scene.objects if o.get("graduate_role") == GOWN_ROLE)
    body = next(o for o in scene.objects if o.get("graduate_role") == BODY_ROLE)
    stoles = [o for o in scene.objects if "stole" in o.get("graduate_role", "").lower()]
    garment_objects = [gown] + stoles
    for obj in garment_objects:
        if any(obj.name in other.objects for other in bpy.data.scenes if other != scene):
            raise RuntimeError("One-shot scene shares an object with another scene: " + obj.name + "; use FULL_COPY")
        obj.data = obj.data.copy()
    initial_hidden = rig.hide_get()
    rig.hide_set(False)
    # Capture only the deforming surface, not a Solidify duplicate. Other
    # modifiers are restored before saving and never altered in Walk or Run.
    modifier_states = [(m, m.show_viewport) for obj in garment_objects for m in obj.modifiers
                       if m.type != "ARMATURE"]
    for modifier, _ in modifier_states:
        modifier.show_viewport = False
    scene.frame_set(start)
    bpy.context.view_layer.update()
    source_rest = {o: np.asarray([v.co[:] for v in o.data.vertices]) for o in garment_objects}
    initial = {o: evaluated_points(o) for o in garment_objects}
    if any(len(initial[o]) != len(o.data.vertices) for o in garment_objects):
        raise RuntimeError("Garment topology changed before the cloth capture")
    faces = [tuple(p.vertices) for p in gown.data.polygons]
    if any(len(f) != 4 for f in faces):
        raise RuntimeError("The corrected graduation gown must retain its quad cloth topology")
    fixed = source_rest[gown][:, 2] >= 2.65
    body_ids, body_faces = closed_body_topology(body)
    initial_body = body_surface_positions(body, body_ids, SCALE, margin=.004)
    initial[gown], initial_contact = enforce_body_clearance(
        initial[gown], initial_body, body_faces, fixed, faces)
    bindings = {o: SkinBinding(o, rig) for o in garment_objects}
    rest_points = {o: bindings[o].inverse_points(initial[o]) for o in garment_objects}
    for obj in garment_objects:
        set_mesh_basis(obj, rest_points[obj])
    bpy.context.view_layer.update()
    initial_mapping_error = max(float(np.linalg.norm(evaluated_points(o) - initial[o], axis=1).max())
                                for o in garment_objects)
    if initial_mapping_error > .0002:
        raise RuntimeError("Unsupported deformation: initial inverse-skin error %.6f m" % initial_mapping_error)
    anchors = make_stole_anchors(gown, initial[gown], stoles, initial, source_rest)

    environment = [o for o in scene.objects if o.type == "MESH" and
                   (o.get(artifact_prefix + "_cloth_collider") or o.get("cloth_collider"))]
    environment_faces = {o: evaluated_faces(o) for o in environment}
    environment_counts = {o: len(evaluated_points(o)) for o in environment}
    environment_inputs = {o: [] for o in environment}
    cloth_inputs, body_inputs = [], []
    for frame in range(start, end + 1):
        scene.frame_set(frame)
        bpy.context.view_layer.update()
        cloth_inputs.append(evaluated_points(gown))
        body_inputs.append(body_surface_positions(body, body_ids, SCALE, margin=.004))
        for obj in environment:
            points = evaluated_points(obj)
            if len(points) != environment_counts[obj]:
                raise RuntimeError("Animated collider topology is unsupported: " + obj.name)
            environment_inputs[obj].append(points)
    cloth_inputs = np.asarray(cloth_inputs, dtype=np.float32)
    body_inputs = np.asarray(body_inputs, dtype=np.float32)
    scene.frame_set(start)

    sim = bpy.data.scenes.new("TEMP | " + display_name + " true-size one-shot cloth")
    sim.render.fps = scene.render.fps
    sim.render.fps_base = scene.render.fps_base
    sim.gravity = (0, 0, -9.81)
    sim.frame_start, sim.frame_end = 1, warmup + end - start + 1
    bpy.context.window.scene = sim
    cloth = add_proxy(sim, "GEO-" + display_name + " cloth physics in metres", initial[gown], faces)
    collider = add_proxy(sim, "GEO-" + display_name + " actual body collision", body_inputs[0], body_faces)
    animate_proxy(cloth, cloth_inputs, warmup)
    animate_proxy(collider, body_inputs, warmup)
    add_collision(collider)
    for obj in environment:
        proxy = add_proxy(sim, "GEO-" + display_name + " contact " + obj.name,
                          environment_inputs[obj][0], environment_faces[obj])
        if all(np.array_equal(environment_inputs[obj][0], p) for p in environment_inputs[obj][1:]):
            pass
        else:
            animate_proxy(proxy, environment_inputs[obj], warmup)
        add_collision(proxy)
    pin = cloth.vertex_groups.new(name="Upper torso and graduated waist pin")
    hem = cloth.vertex_groups.new(name="Double folded sewn hem")
    for index, z in enumerate(source_rest[gown][:, 2]):
        weight = min(1, max(0, (z - 2.20) / .45))
        weight = weight * weight * (3 - 2 * weight)
        if weight:
            pin.add([index], weight, "REPLACE")
        strength = min(1, max(0, (1.40 - z) / .20))
        if strength:
            hem.add([index], strength, "REPLACE")
    modifier = cloth.modifiers.new("One-shot academic fabric physics", "CLOTH")
    settings = modifier.settings
    settings.quality = quality
    settings.mass = .70 / len(gown.data.vertices)
    settings.air_damping = .003
    settings.tension_stiffness = settings.compression_stiffness = 25
    settings.shear_stiffness, settings.bending_stiffness = 10, .08
    settings.tension_damping = settings.compression_damping = settings.shear_damping = .4
    settings.bending_damping = .003
    settings.vertex_group_mass, settings.pin_stiffness = pin.name, 1
    settings.use_dynamic_mesh = False
    if hasattr(settings, "bending_model"):
        settings.bending_model = "ANGULAR"
    settings.vertex_group_bending = hem.name
    settings.bending_stiffness_max = .22
    contacts = modifier.collision_settings
    contacts.use_collision = contacts.use_self_collision = True
    contacts.distance_min, contacts.collision_quality, contacts.friction = .0035, 8, .2
    contacts.self_distance_min, contacts.self_friction = .0025, .2
    modifier.point_cache.frame_start, modifier.point_cache.frame_end = 1, sim.frame_end
    print(event + "_INITIAL", json.dumps({"start": start, "end": end, "warmup": warmup,
          "vertices": len(gown.data.vertices), "initial_contact": initial_contact,
          "inverse_skin_error_m": initial_mapping_error, "extra_colliders": [o.name for o in environment]}), flush=True)
    captured = []
    for frame in range(1, sim.frame_end + 1):
        sim.frame_set(frame)
        bpy.context.view_layer.update()
        points = evaluated_points(cloth, scale=1).astype(np.float32)
        index = max(0, frame - warmup - 1)
        if not np.isfinite(points).all() or np.linalg.norm(points - cloth_inputs[index].mean(axis=0), axis=1).max() > 10:
            raise RuntimeError(display_name + " cloth became unstable at simulation frame " + str(frame))
        if frame > warmup:
            captured.append(points.copy())
        if frame % 15 == 0 or frame == sim.frame_end:
            print(event + "_FRAME", frame, sim.frame_end,
                  "WORLD_MIN_Z_M", float(points[:, 2].min()), flush=True)
        if warmup_test and frame == warmup:
            np.savez_compressed(ANIM / (artifact_prefix + "_cloth_warmup_test.npz"), points=points,
                                initial=initial[gown], body=body_inputs[0], body_faces=body_faces,
                                cloth_faces=faces)
            print(event + "_WARMUP_TEST_DONE", flush=True)
            return None
    raw = np.asarray(captured, dtype=np.float32)
    physical = raw.copy()
    physical[:, fixed] = cloth_inputs[:, fixed]
    clearance = []
    for index in range(len(physical)):
        physical[index], result = enforce_body_clearance(
            physical[index], body_inputs[index], body_faces, fixed, faces)
        clearance.append({"frame": start + index, **result})
        if (index + 1) % 15 == 0:
            print(event + "_CLEARANCE", index + 1, len(physical), flush=True)
    np.savez_compressed(ANIM / (artifact_prefix + "_physical_cloth.npz"), raw=raw, physical=physical,
                        inputs=cloth_inputs, body_vertices=body_inputs, body_faces=body_faces,
                        cloth_faces=faces, start=start, scale=SCALE)

    bpy.context.window.scene = scene
    gown_samples = []
    stole_samples = {o: [] for o in stoles}
    for index, points in enumerate(physical):
        scene.frame_set(start + index)
        bpy.context.view_layer.update()
        gown_samples.append(bindings[gown].inverse_points(points))
        world = [Vector(p) for p in points]
        for obj in stoles:
            inverse = bindings[obj].world_matrices(inverse=True)
            coords = [co.copy() for co in rest_points[obj]]
            for vertex, (ids, bary, gap) in anchors[obj].items():
                a, b, c = [world[i] for i in ids]
                normal = (b-a).cross(c-a).normalized()
                surface_point = a*bary.x + b*bary.y + c*bary.z + normal*gap
                coords[vertex] = inverse[vertex] @ (surface_point / SCALE)
            stole_samples[obj].append(coords)
    bake_keys(gown, gown_samples, start, action_prefix + "_PhysicalGown")
    for obj, samples in stole_samples.items():
        bake_keys(obj, samples, start, action_prefix + "_Physical_" + obj.name)
    # Check actual Blender evaluation, rather than accepting algebra alone.
    errors = []
    for index in range(len(physical)):
        scene.frame_set(start + index)
        bpy.context.view_layer.update()
        delta = evaluated_points(gown) - physical[index]
        errors.append(float(np.linalg.norm(delta, axis=1).max()))
    if max(errors) > .0002:
        raise RuntimeError("Baked one-shot world-space validation failed: %.6f m" % max(errors))
    for mod, visible in modifier_states:
        mod.show_viewport = visible
    scene["Cloth"] = ("Short black gown; real-size, one-shot gravity and body collision solve. "
                       "Free lower hem, upper torso pins, inverse world-skin shape-key bake; no external cache.")
    scene["Cloth simulation scale"] = SCALE
    scene["Cloth baked frame range"] = [start, end]
    scene.frame_set(start)
    rig.hide_set(initial_hidden)
    temporary_meshes = [o.data for o in sim.objects if o.type == "MESH"]
    temporary_actions = [m.shape_keys.animation_data.action for m in temporary_meshes
                         if m.shape_keys and m.shape_keys.animation_data]
    for obj in list(sim.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.scenes.remove(sim)
    for mesh in temporary_meshes:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)
    for action in temporary_actions:
        if action.users == 0:
            bpy.data.actions.remove(action)
    residual_vertices = sum(r["remaining_inside_vertices"] for r in clearance)
    residual_centres = sum(r["remaining_inside_centres"] for r in clearance)
    report = {"scene": scene.name, "frame_start": start, "frame_end": end,
              "scene_frame_end": scene.frame_end, "frames": len(physical), "warmup_frames": warmup,
              "quality": quality, "scale": SCALE, "gravity_m_s2": [0, 0, -9.81],
              "total_gown_mass_kg": .7, "vertices": len(gown.data.vertices), "looping": False,
              "initial_contact": initial_contact, "initial_inverse_skin_error_m": initial_mapping_error,
              "baked_world_space_max_error_m": max(errors), "body_clearance_by_frame": clearance,
              "remaining_inside_vertices_total": residual_vertices,
              "remaining_inside_centres_total": residual_centres,
              "maximum_body_clearance_correction_m": max(r["max_correction_m"] for r in clearance),
              "maximum_remaining_penetration_m": max(r["max_remaining_penetration_m"] for r in clearance),
              "extra_colliders": [o.name for o in environment],
              "source_file": bpy.data.filepath, "output_file": str(target),
              "status": "candidate - needs visual review" if end == scene.frame_end else "partial probe only"}
    (ANIM / (artifact_prefix + "-cloth-validation.json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
    target.parent.mkdir(parents=True, exist_ok=True)
    bpy.context.preferences.filepaths.save_version = 0
    bpy.ops.wm.save_as_mainfile(filepath=str(target))
    print(event + "_SAVED", json.dumps(report), flush=True)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scene", default="03_PORTAL")
    parser.add_argument("--warmup", type=int, default=25)
    parser.add_argument("--quality", type=int, default=16)
    parser.add_argument("--end", type=int)
    parser.add_argument("--output")
    parser.add_argument("--warmup-test", action="store_true")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])
    simulate_portal(args.scene, args.warmup, args.quality, args.end, args.output, args.warmup_test)
