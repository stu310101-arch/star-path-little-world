"""Reusable black/gold portal environment; import and call from Blender Python.

This module has no startup side effects. It neither starts Blender nor saves,
renders, clears a scene, edits a character, changes animation, or replaces a
camera. All new objects live in a dedicated, ownership-tagged collection.

Example for the graduate's original units (hat reaches approximately Z=5.2)::

    from build_void_portal import build_void_portal
    env = build_void_portal(
        bpy.context.scene, portal_y=-4, opening_width=4,
        opening_height=6.5, approach_length=9, void_depth=30,
    )

World axes: X = opening width, +Z = up, -Y = travel into the portal. The
walkway TOP is floor_z and its final edge is portal_y + 0.04 * scale.
The doorway is physically empty: the glow follows its border, with real
geometry behind it. There is no opaque portal card or floor beyond the edge.

The caller owns character motion, old studio-floor/light visibility, camera
selection, compositor glow, scene saving, and final visual validation.
"""

from __future__ import annotations

import math
import random
from typing import Any


OWNER_KEY = "void_portal_owner"


def _socket(node: Any, *names: str) -> Any:
    for name in names:
        for socket in node.inputs:
            if socket.name == name:
                return socket
    raise KeyError(f"No input {names} on {node.bl_idname}")


def _chamfered_outline(half_width: float, bottom: float, top: float, corner: float) -> list[tuple[float, float]]:
    """Counter-clockwise X/Z profile, with a genuine open center."""
    corner = min(corner, half_width * 0.75, (top - bottom) * 0.25)
    return [
        (-half_width + corner, bottom), (half_width - corner, bottom),
        (half_width, bottom + corner), (half_width, top - corner),
        (half_width - corner, top), (-half_width + corner, top),
        (-half_width, top - corner), (-half_width, bottom + corner),
    ]


def _ring_mesh_data(inner: list, outer: list, near_y: float, far_y: float) -> tuple[list, list]:
    n = len(inner)
    if len(outer) != n:
        raise ValueError("Inner and outer outlines must have the same point count")
    vertices = [(x, y, z) for y, path in ((near_y, outer), (near_y, inner), (far_y, outer), (far_y, inner)) for x, z in path]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.extend([
            (i, n + i, n + j, j),
            (2 * n + i, 2 * n + j, 3 * n + j, 3 * n + i),
            (i, j, 2 * n + j, 2 * n + i),
            (n + i, 3 * n + i, 3 * n + j, n + j),
        ])
    return vertices, faces


def _box_mesh_data(center: tuple, dimensions: tuple) -> tuple[list, list]:
    cx, cy, cz = center
    dx, dy, dz = (value / 2 for value in dimensions)
    vertices = [
        (cx - dx, cy - dy, cz - dz), (cx + dx, cy - dy, cz - dz),
        (cx + dx, cy + dy, cz - dz), (cx - dx, cy + dy, cz - dz),
        (cx - dx, cy - dy, cz + dz), (cx + dx, cy - dy, cz + dz),
        (cx + dx, cy + dy, cz + dz), (cx - dx, cy + dy, cz + dz),
    ]
    faces = [(3, 2, 1, 0), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
    return vertices, faces


def build_void_portal(
    scene: Any,
    *,
    portal_y: float = -4.0,
    floor_z: float = 0.0,
    opening_width: float = 4.0,
    opening_height: float = 6.5,
    approach_length: float = 9.0,
    void_depth: float = 30.0,
    star_count: int = 340,
    seed: int = 41,
    name: str = "VOID_PORTAL",
    set_world: bool = True,
    add_lights: bool = True,
) -> dict[str, Any]:
    """Add an environment and return object handles, markers, and camera specs.

    Parameters are in the character's current Blender units. ``set_world``
    assigns a COPY of the old World; the old data block is returned unchanged.
    Repeated calls require a fresh ``name``; existing collections are never
    cleared or silently reused. No selection, active object, frame or pose is
    changed. A camera is not created or activated by this function.
    """
    import bpy
    from mathutils import Vector

    dimensions = (opening_width, opening_height, approach_length, void_depth)
    if not all(math.isfinite(value) and value > 0 for value in dimensions):
        raise ValueError("Opening dimensions, approach_length, and void_depth must be finite and positive")
    if not math.isfinite(portal_y) or not math.isfinite(floor_z):
        raise ValueError("portal_y and floor_z must be finite")
    if not isinstance(star_count, int) or not 0 <= star_count <= 5000:
        raise ValueError("star_count must be an integer between 0 and 5000")
    if name in bpy.data.collections:
        raise ValueError(f"Collection {name!r} already exists; choose a new name to preserve existing work")
    if not name.strip():
        raise ValueError("name must not be empty")

    s = opening_height / 6.5
    if approach_length <= 0.04 * s:
        raise ValueError("approach_length must exceed 0.04 * opening_height / 6.5")
    half = opening_width / 2
    center_z = floor_z + opening_height * 0.50
    border = 0.32 * s
    depth = 0.65 * s
    owner = bpy.data.collections.new(name)
    owner[OWNER_KEY] = name
    scene.collection.children.link(owner)
    sections = {}
    for section in ("Architecture", "Void", "Lights", "Guides"):
        collection = bpy.data.collections.new(f"{name}-{section}")
        collection[OWNER_KEY] = name
        owner.children.link(collection)
        sections[section] = collection
    objects: dict[str, Any] = {}
    materials: dict[str, Any] = {}

    def material(key, color, roughness=0.5, metallic=0.0, emission=0.0):
        mat = bpy.data.materials.new(f"MAT-{name}-{key}")
        mat[OWNER_KEY] = name
        mat.diffuse_color = (*color, 1.0)
        mat.use_nodes = True
        bsdf = next(node for node in mat.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
        _socket(bsdf, "Base Color").default_value = (*color, 1.0)
        _socket(bsdf, "Metallic").default_value = metallic
        _socket(bsdf, "Roughness").default_value = roughness
        if emission:
            _socket(bsdf, "Emission Color", "Emission").default_value = (*color, 1.0)
            _socket(bsdf, "Emission Strength").default_value = emission
        materials[key] = mat
        return mat

    obsidian = material("Obsidian", (0.018, 0.023, 0.032), 0.30)
    gold = material("BrushedGold", (0.68, 0.40, 0.105), 0.31, metallic=1.0)
    floor = material("SlateFloor", (0.018, 0.025, 0.036), 0.64)
    gold_glow = material("GoldLight", (1.0, 0.50, 0.115), 0.4, emission=3.8)
    cyan_glow = material("CyanLight", (0.09, 0.57, 1.0), 0.45, emission=3.2)
    dim_glow = material("IndigoLight", (0.12, 0.16, 0.42), 0.55, emission=0.8)
    star_white = material("StarsPearl", (0.77, 0.88, 1.0), 0.8, emission=4.0)
    star_gold = material("StarsGold", (1.0, 0.66, 0.27), 0.8, emission=3.5)
    star_blue = material("StarsBlue", (0.20, 0.46, 1.0), 0.8, emission=3.5)

    # Low-cost shader variation; no image dependencies, displacement or volume.
    nodes, links = floor.node_tree.nodes, floor.node_tree.links
    bsdf = next(node for node in nodes if node.type == "BSDF_PRINCIPLED")
    coords = nodes.new("ShaderNodeTexCoord")
    noise = nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 3.8
    noise.inputs["Detail"].default_value = 2.0
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (0.008, 0.012, 0.019, 1)
    ramp.color_ramp.elements[1].color = (0.027, 0.037, 0.051, 1)
    links.new(coords.outputs["Object"], noise.inputs["Vector"])
    links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], _socket(bsdf, "Base Color"))

    def mesh(key, vertices, faces, mat, section="Architecture", bevel=0):
        data = bpy.data.meshes.new(f"MESH-{name}-{key}")
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = bpy.data.objects.new(f"GEO-{name}-{key}", data)
        obj[OWNER_KEY] = name
        sections[section].objects.link(obj)
        if mat:
            data.materials.append(mat)
        if bevel:
            modifier = obj.modifiers.new("SmallEdgeHighlights", "BEVEL")
            modifier.width = bevel
            modifier.segments = 2
        objects[key] = obj
        return obj

    def box(key, center, dims, mat, bevel=0):
        vertices, faces = _box_mesh_data(center, dims)
        return mesh(key, vertices, faces, mat, bevel=bevel)

    def curves(key, paths, radius, mat, section="Architecture", cyclic=False):
        data = bpy.data.curves.new(f"CURVE-{name}-{key}", "CURVE")
        data.dimensions = "3D"
        data.resolution_u = 1
        data.bevel_depth = radius
        data.bevel_resolution = 1
        data.use_fill_caps = True
        for path in paths:
            spline = data.splines.new("POLY")
            spline.points.add(len(path) - 1)
            for point, co in zip(spline.points, path):
                point.co = (*co, 1)
            spline.use_cyclic_u = cyclic
        data.materials.append(mat)
        obj = bpy.data.objects.new(f"GEO-{name}-{key}", data)
        obj[OWNER_KEY] = name
        sections[section].objects.link(obj)
        objects[key] = obj
        return obj

    # Thick black architecture, a physical gold frame, and two inset light lines.
    inner = _chamfered_outline(half, floor_z, floor_z + opening_height, 0.46 * s)
    outer = _chamfered_outline(half + border, floor_z - border, floor_z + opening_height + border, 0.62 * s)
    vertices, faces = _ring_mesh_data(inner, outer, portal_y + depth / 2, portal_y - depth / 2)
    frame = mesh("Frame", vertices, faces, obsidian, bevel=0.025 * s)
    frame["opening_width"] = opening_width
    frame["opening_height"] = opening_height
    frame["travel_direction"] = "-Y"
    middle = _chamfered_outline(half + border * 0.53, floor_z - border * 0.53, floor_z + opening_height + border * 0.53, 0.53 * s)
    curves("FrontGoldInlay", [[(x, portal_y + depth / 2 + 0.008 * s, z) for x, z in middle]], 0.044 * s, gold, cyclic=True)
    curves("PortalWarmEdge", [[(x, portal_y + depth / 2 + 0.024 * s, z) for x, z in inner]], 0.026 * s, gold_glow, cyclic=True)
    curves("PortalCoolEdge", [[(x, portal_y - depth / 2 - 0.01 * s, z) for x, z in inner]], 0.021 * s, cyan_glow, cyclic=True)
    for side in (-1, 1):
        box(f"Footing{side:+d}", (side * (half + border * 0.53), portal_y, floor_z - 0.20 * s), (border * 1.55, 1.2 * s, 0.4 * s), gold, 0.035 * s)
        # Gold architectural notches emphasize a constructed door rather than a flat effect.
        for index, fraction in enumerate((0.19, 0.48, 0.77)):
            box(f"FrameInset{side:+d}_{index}", (side * (half + border * 0.58), portal_y + depth / 2 + 0.018 * s, floor_z + opening_height * fraction), (0.14 * s, 0.065 * s, 0.34 * s), gold, 0.015 * s)

    # Runway ends immediately before the portal; everything behind it is empty space.
    runway_width = opening_width * 1.60
    edge_y = portal_y + 0.04 * s
    start_y = portal_y + approach_length
    runway_length = start_y - edge_y
    box("Runway", (0, (start_y + edge_y) / 2, floor_z - 0.25 * s), (runway_width, runway_length, 0.50 * s), floor, 0.045 * s)
    for side in (-1, 1):
        x = side * (runway_width / 2 - 0.13 * s)
        curves(f"RunwayEdge{side:+d}", [[(x, start_y - 0.1 * s, floor_z + 0.012 * s), (x, edge_y + 0.1 * s, floor_z + 0.012 * s)]], 0.018 * s, gold_glow)
    for index in range(1, 7):
        y = edge_y + runway_length * index / 7
        box(f"RunwaySeam{index}", (0, y, floor_z + 0.003 * s), (runway_width - 0.38 * s, 0.025 * s, 0.006 * s), obsidian)
    # Small chevrons are geometry inlays, not text or UI cards.
    for index, offset in enumerate((1.2, 3.2, 5.2)):
        if offset * s < runway_length - 0.3 * s:
            y = portal_y + offset * s
            curves(f"RunwayChevron{index}", [[(-0.20 * s, y + 0.18 * s, floor_z + 0.012 * s), (0, y, floor_z + 0.012 * s), (0.20 * s, y + 0.18 * s, floor_z + 0.012 * s)]], 0.012 * s, gold)

    # Elliptical, broken energy rings supply real parallax along the -Y axis.
    ring_objects = []
    for index, fraction in enumerate((0.055, 0.14, 0.255, 0.40, 0.58, 0.79, 1.0)):
        distance = void_depth * fraction
        rx = half * 1.14 + distance * 0.11
        rz = opening_height * 0.56 + distance * 0.11
        paths = []
        phase = index * 0.23
        for arc in range(3):
            start = phase + arc * math.tau / 3 + 0.08
            end = phase + (arc + 1) * math.tau / 3 - 0.08
            paths.append([
                (rx * math.cos(start + (end - start) * step / 26), portal_y - distance, center_z + rz * math.sin(start + (end - start) * step / 26))
                for step in range(27)
            ])
        mat = gold_glow if index in (2, 5) else cyan_glow if index % 2 == 0 else dim_glow
        ring = curves(f"VoidRing{index:02d}", paths, (0.026 + index * 0.003) * s, mat, section="Void")
        ring["depth_beyond_portal"] = distance
        ring_objects.append(ring)

    # Long, subtle curved ribbons tie the layers into a space the camera can enter.
    for strand in range(3):
        path = []
        for step in range(81):
            t = step / 80
            angle = strand * math.tau / 3 + t * 1.65
            distance = 1.5 * s + t * max(0.1, void_depth - 1.5 * s)
            rx = half * 1.32 + distance * 0.12
            rz = opening_height * 0.67 + distance * 0.10
            path.append((rx * math.cos(angle), portal_y - distance, center_z + rz * math.sin(angle)))
        curves(f"VoidRibbon{strand}", [path], 0.018 * s, dim_glow, section="Void")

    # Batch hundreds of 3-D octahedral stars into ONE mesh for low CPU overhead.
    rng = random.Random(seed)
    vertices, faces, material_indices = [], [], []
    octa_faces = [(0, 2, 4), (2, 1, 4), (1, 3, 4), (3, 0, 4), (2, 0, 5), (1, 2, 5), (3, 1, 5), (0, 3, 5)]
    for index in range(star_count):
        distance = rng.uniform(max(0.5 * s, void_depth * 0.04), void_depth * 1.65)
        angle = rng.uniform(0, math.tau)
        radial = rng.uniform(0.8, 4.8)
        x = (half + distance * 0.12) * radial * math.cos(angle)
        z = center_z + (opening_height * 0.47 + distance * 0.10) * radial * math.sin(angle)
        y = portal_y - distance
        radius = rng.uniform(0.016, 0.041) * s * (1.0 + distance / void_depth)
        if index % 19 == 0:
            radius *= 1.9
        first = len(vertices)
        vertices.extend([(x - radius, y, z), (x + radius, y, z), (x, y - radius, z), (x, y + radius, z), (x, y, z + radius), (x, y, z - radius)])
        faces.extend(tuple(first + vertex for vertex in face) for face in octa_faces)
        material_indices.extend([0 if index % 5 else 1 if index % 10 else 2] * 8)
    stars = mesh("Stars", vertices, faces, star_white, section="Void")
    stars.data.materials.append(star_gold)
    stars.data.materials.append(star_blue)
    for polygon, material_index in zip(stars.data.polygons, material_indices):
        polygon.material_index = material_index
    if hasattr(stars, "visible_shadow"):
        stars.visible_shadow = False

    previous_world = scene.world
    world = None
    if set_world:
        world = previous_world.copy() if previous_world else bpy.data.worlds.new(f"WORLD-{name}")
        world.name = f"WORLD-{name}"
        world[OWNER_KEY] = name
        world.use_nodes = True
        nodes, links = world.node_tree.nodes, world.node_tree.links
        nodes.clear()
        output = nodes.new("ShaderNodeOutputWorld")
        background = nodes.new("ShaderNodeBackground")
        background.inputs["Strength"].default_value = 0.30
        coords = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 2.0
        noise.inputs["Detail"].default_value = 2.0
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.25
        ramp.color_ramp.elements[0].color = (0.0015, 0.0025, 0.007, 1)
        ramp.color_ramp.elements[1].position = 0.80
        ramp.color_ramp.elements[1].color = (0.015, 0.033, 0.075, 1)
        links.new(coords.outputs["Normal"], noise.inputs["Vector"])
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        links.new(ramp.outputs["Color"], background.inputs["Color"])
        links.new(background.outputs["Background"], output.inputs["Surface"])
        scene.world = world

    def area_light(key, location, target, energy, color, size):
        data = bpy.data.lights.new(f"LGT-{name}-{key}", "AREA")
        data.energy = energy * s * s
        data.color = color
        data.shape = "DISK"
        data.size = size * s
        obj = bpy.data.objects.new(f"LGT-{name}-{key}", data)
        obj[OWNER_KEY] = name
        sections["Lights"].objects.link(obj)
        obj.location = location
        obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()
        objects[f"light_{key}"] = obj
        return obj

    if add_lights:
        # Neutral key keeps the black robe readable; gold and cyan are accents.
        area_light("RunwayKey", (4.2 * s, portal_y + 5.5 * s, floor_z + 8.5 * s), (0, portal_y + 2.5 * s, floor_z + 2.4 * s), 850, (1.0, 0.93, 0.82), 5.0)
        area_light("RunwayFill", (-4.0 * s, portal_y + 3.0 * s, floor_z + 4.5 * s), (0, portal_y + 2 * s, floor_z + 2.4 * s), 320, (0.65, 0.80, 1.0), 4.0)
        area_light("PortalRim", (0, portal_y - 1.0 * s, floor_z + 5.4 * s), (0, portal_y + 1.8 * s, floor_z + 2.8 * s), 580, (0.22, 0.62, 1.0), 3.0)
        area_light("VoidFill", (-3.0 * s, portal_y - min(9.0 * s, void_depth * 0.36), floor_z + 6.5 * s), (0, portal_y - min(7.0 * s, void_depth * 0.28), floor_z + 2.5 * s), 500, (0.45, 0.68, 1.0), 5.0)

    marker_positions = {
        "start": (0, portal_y + min(5.8 * s, approach_length - 0.7 * s), floor_z),
        "walk_end": (0, portal_y + 1.8 * s, floor_z),
        "takeoff": (0, portal_y + 1.8 * s, floor_z),
        "threshold": (0, portal_y, floor_z),
        "door_center": (0, portal_y, center_z),
        "jump_apex": (0, portal_y - 0.9 * s, floor_z + 0.90 * s),
        "void_float": (0, portal_y - min(8.0 * s, void_depth * 0.30), floor_z + 1.4 * s),
    }
    guides = {}
    for key, location in marker_positions.items():
        guide = bpy.data.objects.new(f"GUIDE-{name}-{key}", None)
        guide[OWNER_KEY] = name
        guide.location = location
        guide.empty_display_type = "PLAIN_AXES"
        guide.empty_display_size = 0.22 * s
        guide.hide_render = True
        sections["Guides"].objects.link(guide)
        guides[key] = guide

    camera_suggestions = {
        "quarter_side": {"location": (10 * s, portal_y + 12 * s, floor_z + 7.5 * s), "target": (0, portal_y, floor_z + 2.0 * s), "lens_mm": 42, "sensor_width_mm": 36, "use_dof": False},
        "threshold_side": {"location": (8.8 * s, portal_y + 2.0 * s, floor_z + 5.8 * s), "target": (0, portal_y - 0.5 * s, floor_z + 2.8 * s), "lens_mm": 38, "sensor_width_mm": 36, "use_dof": False},
        "inside_void": {"location": (5.0 * s, portal_y - 2.8 * s, floor_z + 5.7 * s), "target": marker_positions["void_float"], "lens_mm": 34, "sensor_width_mm": 36, "use_dof": False},
    }
    return {
        "collection": owner, "sections": sections, "objects": objects,
        "materials": materials, "rings": ring_objects, "guides": guides,
        "positions": marker_positions, "camera_suggestions": camera_suggestions,
        "previous_world": previous_world, "world": world,
        "bounds": {"portal_y": portal_y, "floor_z": floor_z, "runway_edge_y": edge_y, "runway_start_y": start_y, "opening_width": opening_width, "opening_height": opening_height, "void_depth": void_depth},
        "render_suggestion": {"engine": "CYCLES", "device": "CPU", "samples": 24, "use_denoising": True, "max_bounces": 4, "diffuse_bounces": 2, "glossy_bounces": 2, "resolution": (960, 540), "view_transform": "AgX", "compositor_glare": "Optional FOG_GLOW, threshold 1.3; inspect so the rim does not obscure the figure"},
        "integration_notes": [
            "Hide only the previously identified studio floor/lights if they interfere; this builder never edits them.",
            "The character should face and travel along -Y. The center of the door contains no surface or collision object.",
            "The walkway ends at the threshold. The void_float marker is a flight target, not a landing platform.",
            "Keep the complete hat and hands within the beveled opening when selecting the final jump trajectory.",
            "Camera coordinates are composition starting points; render and inspect the final action at its start, takeoff, threshold, and end.",
        ],
    }
