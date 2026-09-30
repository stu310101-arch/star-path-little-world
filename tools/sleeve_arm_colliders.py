"""Closed animated arm surfaces for the graduate's sleeve cloth simulation.

The visible body intentionally omits skin underneath the gown sleeves, so its
mesh alone cannot keep cloth out of the arms. These collision-only capsules
replace that missing surface; they are not exported as visible game geometry.

Call after setting the source scene frame and updating the dependency graph.
Coordinates include the rig's world/root transform and are returned in metres.
The caller owns creation and animation of Blender collision proxy objects.
"""

import math

import numpy as np


ANGULAR_SEGMENTS = 12
AXIAL_RINGS = 8

# Anatomical approximations for the existing stylized male, in real metres.
# The original skin below the sleeves is absent from the graduate blend.
# End caps extend beyond the joint, so upper/lower arm surfaces overlap even
# when the elbow bends. Keep Blender cloth's small outer collision margin in
# addition to these skin radii, rather than inflating the visible sleeve.
ARM_RADII = {
    "UpperArm.L": (0.055, 0.044),
    "LowerArm.L": (0.044, 0.030),
    "UpperArm.R": (0.055, 0.044),
    "LowerArm.R": (0.044, 0.030),
}


def _world_point(matrix, point):
    return (matrix @ np.append(np.asarray(point, dtype=np.float64), 1.0))[:3]


def _capsule_topology():
    """Two unique poles, eight rings, consistently outward triangle winding."""
    faces = []
    segments = ANGULAR_SEGMENTS
    for ring in range(AXIAL_RINGS - 1):
        lower = 1 + ring * segments
        upper = lower + segments
        for segment in range(segments):
            following = (segment + 1) % segments
            faces.append((lower + segment, lower + following, upper + following))
            faces.append((lower + segment, upper + following, upper + segment))
    last_ring = 1 + (AXIAL_RINGS - 1) * segments
    top_pole = 1 + AXIAL_RINGS * segments
    for segment in range(segments):
        following = (segment + 1) % segments
        faces.append((0, 1 + following, 1 + segment))
        faces.append((top_pole, last_ring + segment, last_ring + following))
    return tuple(faces)


CAPSULE_FACES = _capsule_topology()


def _tapered_capsule(head, tail, radial_hint, head_radius, tail_radius):
    axis = tail - head
    length = float(np.linalg.norm(axis))
    if not np.isfinite(length) or length < 1e-6:
        raise ValueError("Arm capsule requires a finite, nonzero bone length")
    axis /= length
    # Bone-local X makes corresponding vertices follow twist smoothly. A
    # fixed world-up basis would spin abruptly near a parallel arm direction.
    radial = radial_hint - axis * np.dot(radial_hint, axis)
    if np.linalg.norm(radial) < 1e-8:
        fallback = np.eye(3)[int(np.argmin(np.abs(axis)))]
        radial = fallback - axis * np.dot(fallback, axis)
    radial /= np.linalg.norm(radial)
    across = np.cross(axis, radial)
    c30 = math.sqrt(3.0) * 0.5
    # Spherical end caps, a tapered middle, and no repeated pole rings.
    ring_specs = (
        (-head_radius * c30, head_radius * 0.5),
        (-head_radius * 0.5, head_radius * c30),
        (0.0, head_radius),
        (length / 3.0, (2.0 * head_radius + tail_radius) / 3.0),
        (length * 2.0 / 3.0, (head_radius + 2.0 * tail_radius) / 3.0),
        (length, tail_radius),
        (length + tail_radius * 0.5, tail_radius * c30),
        (length + tail_radius * c30, tail_radius * 0.5),
    )
    points = [head - axis * head_radius]
    for axial, radius in ring_specs:
        center = head + axis * axial
        for segment in range(ANGULAR_SEGMENTS):
            angle = 2.0 * math.pi * segment / ANGULAR_SEGMENTS
            points.append(center + radius * (
                radial * math.cos(angle) + across * math.sin(angle)))
    points.append(tail + axis * tail_radius)
    return np.asarray(points, dtype=np.float64)


def arm_capsule_inputs(rig, scale=1.75 / 4.8):
    """Return four stable-topology collision inputs for the current arm pose.

    Returns ``{bone_name: {"points": float64[N,3], "faces": triangles}}``.
    Each capsule has 98 vertices and 192 nondegenerate triangles. ``scale``
    converts Blender model/world positions to metres; radii are already in
    metres. PoseBone.head/tail and matrix include the evaluated pose, while
    rig.matrix_world also includes an animated parent such as JumpDown root.

    The rig should have the graduate's original unit object scale. A project
    that intentionally changes character size should scale ARM_RADII too.
    """
    if not np.isfinite(scale) or scale <= 0:
        raise ValueError("Character metre scale must be positive and finite")
    world = np.asarray(rig.matrix_world, dtype=np.float64)
    inputs = {}
    for name, (head_radius, tail_radius) in ARM_RADII.items():
        bone = rig.pose.bones.get(name)
        if bone is None:
            raise KeyError("Missing sleeve collision bone: " + name)
        head = _world_point(world, bone.head) * scale
        tail = _world_point(world, bone.tail) * scale
        bone_world = world @ np.asarray(bone.matrix, dtype=np.float64)
        points = _tapered_capsule(
            head, tail, bone_world[:3, 0], head_radius, tail_radius)
        if not np.isfinite(points).all():
            raise ValueError("Non-finite sleeve collision points: " + name)
        inputs[name] = {"points": points, "faces": CAPSULE_FACES}
    return inputs
