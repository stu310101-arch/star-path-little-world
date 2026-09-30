"""Editable WordKing projector prop for the Blender training-room source scene.

No import-time work.  Call build_device(collection, materials, font) after creating
the shared material palette.  All geometry is in metres and owned by one root.
"""

import math

import bpy


def build_device(collection, materials, font):
    """Build the single reference projector, facing -Y, and return its root."""
    root = bpy.data.objects.new("ROOT-WordKing_training_device_01", None)
    collection.objects.link(root)
    root.location = (0.65, 0.8, 0.0)
    root.empty_display_type = "CIRCLE"
    root.empty_display_size = 0.92
    root["device_type"] = "wordking_training"
    root["device_count"] = 1
    root["front_axis"] = "-Y"
    root["design_note"] = "One authored device; additional device content is pending."

    def own(name, data, material):
        obj = bpy.data.objects.new("GEO-WK-" + name, data)
        collection.objects.link(obj)
        obj.parent = root
        if material is not None:
            obj.data.materials.append(materials[material])
        return obj

    def mesh(name, vertices, faces, material, smooth=False):
        data = bpy.data.meshes.new("MESH-WK-" + name)
        data.from_pydata(vertices, [], faces)
        data.update()
        obj = own(name, data, material)
        for polygon in data.polygons:
            polygon.use_smooth = smooth
        return obj

    def lathe(name, profile, material, segments=64):
        # Open radial profiles deliberately preserve the separate lens aperture.
        # A radius-zero row is one true pole, never a ring of coincident points.
        vertices = []
        rows = []
        for r, z in profile:
            if abs(r) < 1e-9:
                rows.append([len(vertices)])
                vertices.append((0.0, 0.0, z))
            else:
                row = []
                for n in range(segments):
                    row.append(len(vertices))
                    a = math.tau * n / segments
                    vertices.append((r * math.cos(a), r * math.sin(a), z))
                rows.append(row)
        faces = []
        for lower, upper in zip(rows, rows[1:]):
            if len(lower) == len(upper) == 1:
                continue
            for n in range(segments):
                nxt = (n + 1) % segments
                if len(lower) == 1:
                    faces.append((lower[0], upper[nxt], upper[n]))
                elif len(upper) == 1:
                    faces.append((lower[n], lower[nxt], upper[0]))
                else:
                    faces.append((lower[n], lower[nxt], upper[nxt], upper[n]))
        return mesh(name, vertices, faces, material, smooth=True)

    def paths(name, lines, material, radius=0.006, cyclic=False):
        curve = bpy.data.curves.new("CURVE-WK-" + name, "CURVE")
        curve.dimensions = "3D"
        curve.resolution_u = 1
        curve.bevel_depth = radius
        curve.bevel_resolution = 0
        for points in lines:
            spline = curve.splines.new("POLY")
            spline.points.add(len(points) - 1)
            for point, xyz in zip(spline.points, points):
                point.co = (*xyz, 1.0)
            spline.use_cyclic_u = cyclic
        return own(name, curve, material)

    def ring(name, radius, z, material="blue", thickness=0.009):
        points = [(radius * math.cos(n * math.tau / 64),
                   radius * math.sin(n * math.tau / 64), z) for n in range(64)]
        return paths(name, [points], material, thickness, cyclic=True)

    def box(name, location, size, material, bevel=0.0, rotation_z=0.0, rotation_y=0.0):
        x, y, z = (v / 2 for v in size)
        vertices = [(-x, -y, -z), (x, -y, -z), (x, y, -z), (-x, y, -z),
                    (-x, -y, z), (x, -y, z), (x, y, z), (-x, y, z)]
        faces = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                 (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        obj = mesh(name, vertices, faces, material)
        obj.location = location
        obj.rotation_euler.y = rotation_y
        obj.rotation_euler.z = rotation_z
        if bevel:
            modifier = obj.modifiers.new("Small manufactured edge bevel", "BEVEL")
            modifier.width = bevel
            modifier.segments = 2
        return obj

    def text(name, body, position, size, material, tracking=1.0):
        data = bpy.data.curves.new("TEXT-WK-" + name, "FONT")
        data.body = body
        data.align_x = "CENTER"
        data.align_y = "CENTER"
        data.size = size
        data.space_character = tracking
        data.resolution_u = 3
        data.extrude = 0.0005
        if font is not None:
            data.font = font
        obj = own(name, data, material)
        obj.location = position
        obj.rotation_euler.x = math.pi / 2
        return obj

    # Circular body: rolled undercut, dark seam, sloping metal shoulder and lens.
    lathe("Rubber_foot", [(0, 0.025), (0.79, 0.025), (0.845, 0.045),
                          (0.85, 0.085), (0.81, 0.095), (0, 0.095)], "black")
    lathe("Lower_brushed_shell", [(0.82, 0.075), (0.87, 0.09), (0.895, 0.12),
                                  (0.9, 0.19), (0.89, 0.205), (0.84, 0.205)], "metal")
    lathe("Blue_luminous_seam", [(0.885, 0.2), (0.902, 0.211),
                                 (0.902, 0.227), (0.885, 0.235)], "blue")
    lathe("Upper_chamfered_housing", [(0.884, 0.227), (0.9, 0.245),
                                      (0.894, 0.28), (0.876, 0.303),
                                      (0.786, 0.405), (0.74, 0.449),
                                      (0.7, 0.461), (0.647, 0.461),
                                      (0.627, 0.449), (0.627, 0.424)], "metal")
    lathe("Lens_chrome_bezel", [(0.615, 0.427), (0.63, 0.452),
                                (0.645, 0.469), (0.669, 0.473),
                                (0.682, 0.465), (0.689, 0.451)], "chrome")
    lathe("Inset_lens_black", [(0, 0.45), (0.602, 0.45),
                               (0.612, 0.455), (0.604, 0.469), (0, 0.469)], "black")
    ring("Outer_base_edge", 0.872, 0.106, "chrome", 0.007)
    ring("Lens_outer_ring", 0.593, 0.477, "blue", 0.011)
    ring("Lens_middle_ring", 0.476, 0.479, "cyan", 0.008)
    ring("Lens_inner_ring", 0.358, 0.481, "blue", 0.007)
    ring("Lens_core_ring", 0.23, 0.483, "cyan", 0.009)
    lathe("Central_optic", [(0, 0.476), (0.155, 0.476),
                            (0.175, 0.485), (0.15, 0.493), (0, 0.493)], "cyan", 48)

    # Sparse manufactured details, each editable; rear vents do not cover logo.
    for i in range(8):
        a = (i + 0.5) * math.tau / 8
        fastener = lathe("Fastener_%02d" % (i + 1),
                         [(0, 0), (0.018, 0), (0.021, 0.008),
                          (0.018, 0.014), (0, 0.014)], "chrome", 8)
        fastener.location = (0.706 * math.cos(a), 0.706 * math.sin(a), 0.449)
        box("Fastener_slot_%02d" % (i + 1),
            (0.706 * math.cos(a), 0.706 * math.sin(a), 0.464),
            (0.023, 0.006, 0.002), "black", rotation_z=a)
    # Match the .876/.303 -> .786/.405 shell segment; expose only 2 mm of each
    # inset vent above that sloping surface instead of leaving horizontal fins.
    vent_slope = math.atan2(0.102, 0.09)
    vent_shell_radius = 0.809
    vent_shell_z = 0.303 + (0.876 - vent_shell_radius) * (0.102 / 0.09)
    vent_embed = 0.015 / 2 - 0.002
    vent_radius = vent_shell_radius - math.sin(vent_slope) * vent_embed
    vent_z = vent_shell_z - math.cos(vent_slope) * vent_embed
    for i in range(12):
        a = math.radians(-20 + i * 20)
        box("Radial_vent_%02d" % (i + 1),
            (vent_radius * math.cos(a), vent_radius * math.sin(a), vent_z),
            (0.07, 0.024, 0.015), "black", 0.004, a, vent_slope)
    for side in (-1, 1):
        box("Shoulder_insert_%s" % side, (side * 0.752, 0.0, 0.419),
            (0.048, 0.21, 0.032), "chrome", 0.013)
        box("Shoulder_blue_status_%s" % side, (side * 0.752, -0.003, 0.438),
            (0.023, 0.126, 0.009), "blue", 0.007)

    # Power switch is physically mounted on the forward side of the shell.
    badge = lathe("Front_power_badge", [(0, -0.022), (0.126, -0.022),
                                        (0.144, 0), (0.132, 0.025),
                                        (0, 0.025)], "black", 40)
    badge.location = (0.0, -0.875, 0.24)
    badge.rotation_euler.x = math.pi / 2
    badge_outer = [(0.123 * math.cos(t * math.tau / 48), -0.905,
                    0.24 + 0.123 * math.sin(t * math.tau / 48)) for t in range(48)]
    paths("Power_badge_ring", [badge_outer], "blue", 0.006, True)
    # Arc runs from upper-right around the bottom to upper-left, leaving top gap.
    power_arc = [(0.070 * math.sin(math.radians(45 + t * 270 / 36)),
                  -0.912, 0.24 + 0.070 * math.cos(math.radians(45 + t * 270 / 36)))
                 for t in range(37)]
    paths("Power_symbol", [power_arc, [(0, -0.914, 0.332), (0, -0.914, 0.248)]],
          "cyan", 0.008)
    text("Shell_mark", "GAME ON", (0, -0.83, 0.39), 0.064, "white", 1.2)

    # Reference silhouette: broad trapezoid hologram above a focused emitter.
    panel_y = 0.035
    corners = [(-0.8, panel_y, 1.35), (0.8, panel_y, 1.35),
               (1.1, panel_y, 2.55), (-1.1, panel_y, 2.55)]
    panel = mesh("Hologram_transparent_trapezoid", corners, [(0, 1, 2, 3)], "hologram")
    panel["visual_only"] = True
    paths("Hologram_cyan_border", [[(x, panel_y - 0.012, z) for x, y, z in corners]],
          "cyan", 0.009, True)
    # One multi-spline object keeps the fine geometric grid inexpensive/editable.
    grid_lines = []
    for row in range(1, 15):
        z = 1.35 + row * 1.2 / 15
        extent = 0.8 + (z - 1.35) * 0.25
        grid_lines.append([(-extent, panel_y - 0.005, z), (extent, panel_y - 0.005, z)])
    for col in range(-13, 14):
        x = col * 0.075
        z0 = max(1.35, 1.35 + (abs(x) - 0.8) / 0.25)
        if z0 < 2.55:
            grid_lines.append([(x, panel_y - 0.005, z0), (x, panel_y - 0.005, 2.55)])
    paths("Hologram_fine_grid", grid_lines, "grid", 0.0011)
    # Projector fan: faint triangular field with a few crisp cyan rays.
    mesh("Projection_light_field", [(-0.13, 0.0, 0.495), (0.13, 0.0, 0.495),
                                     (0.8, panel_y, 1.35), (-0.8, panel_y, 1.35)],
         [(0, 1, 2, 3)], "hologram")
    rays = []
    for i in range(9):
        frac = (i - 4) / 4
        rays.append([(frac * 0.11, -0.008, 0.495),
                     (frac * 0.8, panel_y - 0.014, 1.35)])
    paths("Projection_ray_fan", rays, "grid", 0.002)
    paths("Projection_two_edge_rays", [rays[0], rays[-1]], "blue", 0.003)

    # Legible central logotype and deliberately geometric crown, as reference.
    text("Main_Chinese_logotype", "單字王", (0, panel_y - 0.034, 1.91), 0.35, "cyan", 1.1)
    text("Training_subline", "WORDKING  /  TRAINING", (0, panel_y - 0.034, 1.50),
         0.064, "cyan", 1.18)
    crown = [(-0.235, 2.33), (-0.20, 2.18), (0.20, 2.18), (0.235, 2.33),
             (0.12, 2.25), (0.0, 2.41), (-0.12, 2.25)]
    mesh("Crown_icon", [(x, panel_y - 0.035, z) for x, z in crown],
         [tuple(range(len(crown)))], "cyan")
    paths("Crown_cross", [[(0, panel_y - 0.041, 2.445), (0, panel_y - 0.041, 2.505)],
                          [(-0.027, panel_y - 0.041, 2.475),
                           (0.027, panel_y - 0.041, 2.475)]], "white", 0.008)
    # Corner UI brackets and segmented bars share one editable curve object.
    brackets = []
    for s in (-1, 1):
        brackets.extend([
            [(s * 0.77, -0.015, 2.50), (s * 1.025, -0.015, 2.50),
             (s * 0.995, -0.015, 2.38)],
            [(s * 0.5, -0.015, 1.405), (s * 0.76, -0.015, 1.405),
             (s * 0.80, -0.015, 1.53)],
        ])
        for i in range(5):
            brackets.append([(s * (0.80 + i * 0.034), -0.017, 2.45),
                             (s * (0.80 + i * 0.034), -0.017, 2.48)])
    paths("Hologram_corner_interface", brackets, "blue", 0.004)
    status_dots = []
    for i in range(7):
        status_dots.append([(0.048 * (i - 3) + 0.008 * math.cos(t * math.tau / 12),
                             -0.016, 1.402 + 0.008 * math.sin(t * math.tau / 12))
                            for t in range(12)])
    paths("Hologram_seven_status_dots", status_dots, "cyan", 0.002, True)
    return root
