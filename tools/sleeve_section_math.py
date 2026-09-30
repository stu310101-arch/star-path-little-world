"""NumPy helpers for continuous sleeve sections; no Blender dependency.

Transport radial frames along a sleeve instead of choosing a fresh world-up
at every ring. Temporal filtering belongs on ring center trajectories, never
on complete rotating ring vertices: averaging those vertices shrinks cloth.
"""

from __future__ import annotations

import numpy as np


def parallel_transport_frames(tangents, initial_radial_hint):
    """Return (radials, binormals), both N x 3, for an ordered sleeve axis.

    Tangents need not be unit length, but must be finite and nonzero. The
    initial hint is projected once onto the first tangent's normal plane.
    Each following radial undergoes the minimum rotation mapping the prior
    tangent to the current tangent. No ring reselects a world-up direction.
    The returned frame is right-handed: binormal = tangent cross radial.

    An exactly reversed tangent has no unique minimal-rotation axis. In that
    singular case retain the previous radial (a pi rotation around it). A
    smooth non-reversing centerline is preferable to relying on this fallback.
    """
    tangents = np.asarray(tangents, dtype=np.float64)
    if tangents.ndim != 2 or tangents.shape[1] != 3 or len(tangents) == 0:
        raise ValueError("tangents must be a nonempty N x 3 array")
    lengths = np.linalg.norm(tangents, axis=1)
    if not np.isfinite(tangents).all() or np.any(lengths <= 1e-12):
        raise ValueError("tangents must be finite and nonzero")
    unit = tangents / lengths[:, None]
    hint = np.asarray(initial_radial_hint, dtype=np.float64)
    if hint.shape != (3,) or not np.isfinite(hint).all():
        raise ValueError("initial_radial_hint must be a finite 3-vector")
    radial = hint - unit[0] * np.dot(hint, unit[0])
    if np.linalg.norm(radial) <= 1e-12:
        # Deterministic first-ring fallback only, not a repeated world-up reset.
        hint = np.eye(3)[int(np.argmin(np.abs(unit[0])))]
        radial = hint - unit[0] * np.dot(hint, unit[0])
    radial /= np.linalg.norm(radial)
    radials = [radial.copy()]
    for previous, current in zip(unit[:-1], unit[1:]):
        cross = np.cross(previous, current)
        cosine = float(np.clip(np.dot(previous, current), -1, 1))
        if cosine > -1 + 1e-10:
            # Rodrigues in a form that remains stable near parallel tangents.
            radial = radial + np.cross(cross, radial) + np.cross(cross, np.cross(cross, radial)) / (1 + cosine)
        # At reversal, radial already lies in both tangent-normal planes.
        radial -= current * np.dot(radial, current)
        magnitude = np.linalg.norm(radial)
        if magnitude <= 1e-12:
            raise ValueError("Degenerate transported frame; centerline reverses too abruptly")
        radial /= magnitude
        radials.append(radial.copy())
    radials = np.asarray(radials)
    return radials, np.cross(unit, radials)


def periodic_lowpass_centers(centers, max_harmonic=2, transition_harmonics=1, axis=0):
    """Filter periodic center trajectories, preserving their mean position.

    Input ends one sample before a duplicated cycle endpoint. For a 24-frame,
    30 fps run, harmonics 1 and 2 correspond to 1.25 and 2.5 Hz. By default
    retain those and attenuate harmonic 3 with a raised-cosine transition.
    Use transition_harmonics=0 for a hard cutoff after max_harmonic.

    Call on center positions (F x rings x 3 or F x 3), not ring vertex XYZ.
    Section rotations and radial fabric shape require their own treatment.
    """
    centers = np.asarray(centers, dtype=np.float64)
    if centers.ndim < 2 or centers.shape[-1] != 3 or not np.isfinite(centers).all():
        raise ValueError("centers must be finite trajectories with final dimension 3")
    axis %= centers.ndim
    if axis == centers.ndim - 1 or centers.shape[axis] < 3:
        raise ValueError("axis must select at least three time samples, not XYZ")
    if not isinstance(max_harmonic, (int, np.integer)) or max_harmonic < 0:
        raise ValueError("max_harmonic must be a nonnegative integer")
    if not isinstance(transition_harmonics, (int, np.integer)) or transition_harmonics < 0:
        raise ValueError("transition_harmonics must be a nonnegative integer")
    spectrum = np.fft.rfft(centers, axis=axis)
    harmonics = np.arange(spectrum.shape[axis])
    if transition_harmonics:
        phase = np.clip((harmonics - max_harmonic) / (transition_harmonics + 1), 0, 1)
        weights = .5 + .5 * np.cos(np.pi * phase)
    else:
        weights = (harmonics <= max_harmonic).astype(np.float64)
    shape = [1] * centers.ndim
    shape[axis] = len(weights)
    return np.fft.irfft(spectrum * weights.reshape(shape), n=centers.shape[axis], axis=axis)


def ring_perimeters(points):
    """Closed-polyline lengths for arrays of shape (..., vertices, 3)."""
    points = np.asarray(points, dtype=np.float64)
    if points.ndim < 2 or points.shape[-1] != 3 or points.shape[-2] < 3 or not np.isfinite(points).all():
        raise ValueError("points must be finite rings with at least three vertices")
    return np.linalg.norm(np.roll(points, -1, axis=-2) - points, axis=-1).sum(axis=-1)


def ring_perimeter_metrics(points, reference_perimeter=None):
    """Return array-valued size metrics without assuming a circular section.

    Projected area is the magnitude of the oriented polygon area vector; it
    falls when a ring folds over itself. Perimeter alone cannot detect that.
    References may be scalars or arrays broadcastable to the perimeter shape.
    """
    points = np.asarray(points, dtype=np.float64)
    perimeter = ring_perimeters(points)
    center = points.mean(axis=-2)
    relative = points - center[..., None, :]
    radii = np.linalg.norm(relative, axis=-1)
    area_vector = .5 * np.cross(relative, np.roll(relative, -1, axis=-2)).sum(axis=-2)
    metrics = {
        "center": center,
        "perimeter": perimeter,
        "radius_min": radii.min(axis=-1),
        "radius_mean": radii.mean(axis=-1),
        "radius_max": radii.max(axis=-1),
        "projected_area": np.linalg.norm(area_vector, axis=-1),
        "area_vector": area_vector,
    }
    if reference_perimeter is not None:
        reference = np.asarray(reference_perimeter, dtype=np.float64)
        if not np.isfinite(reference).all() or np.any(reference <= 0):
            raise ValueError("reference_perimeter must be positive and finite")
        metrics["perimeter_ratio"] = perimeter / reference
    return metrics
