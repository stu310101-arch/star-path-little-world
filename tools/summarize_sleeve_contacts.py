"""Summarize existing sleeve triangle-audit evidence without Blender.

Examples::

    python tools/summarize_sleeve_contacts.py \
        --report tools/walk-sleeve-garment-contact.json \
                 tools/run-sleeve-garment-contact.json \
        --gown-proxy art/Graduate/animation/Sleeve_ArmholeProbe.npz \
        --output tools/locomotion-sleeve-contact-summary.json

The provided NPZ's ``gown_faces`` defines retained gown polygons. Other gown
polygons are the intentionally omitted sewn-joint region. This is an explicit
geometric classification convention; it does not claim a later solver enabled
that collider. Original reports/NPZ files are read-only and their hashes appear
in the separate summary. No crossing is removed from the original evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import itertools
import json
from pathlib import Path

import numpy as np


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def _counter():
    return {"crossings": 0, "frames_with_crossings": [], "maximum_per_frame": 0,
            "maximum_intersection_segment_m": 0.0, "segment_lengths_complete": True}


def _add(counter, frame, count, maximum, lengths_known=True):
    counter["crossings"] += count
    if count:
        counter["frames_with_crossings"].append(frame)
        counter["maximum_per_frame"] = max(counter["maximum_per_frame"], count)
        counter["segment_lengths_complete"] &= lengths_known
        if maximum is not None:
            counter["maximum_intersection_segment_m"] = max(
                counter["maximum_intersection_segment_m"], maximum)


def _retained_polygons(polygons, proxy_triangles):
    retained, matched = set(), set()
    for index, polygon in enumerate(polygons):
        for triple in itertools.combinations(polygon, 3):
            canonical = tuple(sorted(triple))
            if canonical in proxy_triangles:
                retained.add(index)
                matched.add(canonical)
    if matched != proxy_triangles:
        raise ValueError("Gown proxy triangles do not match the audit's source polygon topology")
    return retained


def summarize(report_paths, gown_proxy_path):
    gown_proxy_path = Path(gown_proxy_path).resolve()
    with np.load(gown_proxy_path, allow_pickle=False) as proxy:
        triangles = proxy["gown_faces"]
        if triangles.ndim != 2 or triangles.shape[1] != 3:
            raise ValueError("Gown proxy NPZ must provide triangulated gown_faces")
        proxy_triangles = {tuple(sorted(map(int, triangle))) for triangle in triangles}
    result = {
        "classification_proxy": str(gown_proxy_path), "proxy_sha256": sha256(gown_proxy_path),
        "convention": "Proxy-retained gown faces versus omitted sewn-joint faces; no evidence filtered out",
        "reported_segment_measure": "Length of transverse triangle intersection, not penetration depth",
        "sources": [], "clips": {},
    }
    for path in report_paths:
        path = Path(path).resolve()
        evidence = json.loads(path.read_text(encoding="utf-8"))
        result["sources"].append({"path": str(path), "sha256": sha256(path)})
        for label, original in evidence["clips"].items():
            if label in result["clips"]:
                raise ValueError(f"Duplicate clip {label}; summarize each candidate separately")
            polygons = original["surfaces"]["gown"]["source_polygons"]
            retained = _retained_polygons(polygons, proxy_triangles)
            clip = {
                "scene": original["scene"], "source_blend": evidence["source_blend"],
                "surface": evidence["surface"], "frames": len(original["frames"]),
                "retained_gown_polygons": len(retained),
                "sewn_joint_polygons": len(polygons) - len(retained),
                "sewn_joint": _counter(), "retained_gown": _counter(),
                "free_self": _counter(), "left_right": _counter(),
                "pair_totals": original["pair_totals"], "per_frame": [],
            }
            for frame in original["frames"]:
                per_frame = {"frame": frame["frame"], "sewn_joint": 0, "retained_gown": 0,
                             "left_self": 0, "right_self": 0, "left_right": 0}
                gown_table = original["triangle_tables"][frame["triangle_table_ids"]["gown"]]
                category_lengths = {"sewn_joint": [], "retained_gown": []}
                category_known = {"sewn_joint": True, "retained_gown": True}
                for pair in ("left_gown", "right_gown"):
                    evidence_pair = frame["pairs"][pair]
                    pairs = evidence_pair["triangle_pairs"]
                    lengths = evidence_pair.get("intersection_segment_lengths_m")
                    if lengths is not None and len(lengths) != len(pairs):
                        raise ValueError(f"Mismatched segment-length table in {label} frame {frame['frame']}")
                    categories = ["retained_gown" if gown_table["polygon_indices"][second] in retained
                                  else "sewn_joint" for _, second in pairs]
                    for index, category in enumerate(categories):
                        per_frame[category] += 1
                        if lengths is not None:
                            category_lengths[category].append(lengths[index])
                        elif len(set(categories)) == 1:
                            # Older evidence stores one maximum per pair. It
                            # is exact for classification only if all of that
                            # pair's crossings belong to this one category.
                            category_lengths[category].append(
                                evidence_pair["maximum_intersection_segment_m"])
                        else:
                            category_known[category] = False
                for category in ("sewn_joint", "retained_gown"):
                    _add(clip[category], frame["frame"], per_frame[category],
                         max(category_lengths[category], default=0.0), category_known[category])
                self_max = 0.0
                for pair in ("left_self", "right_self", "left_right"):
                    evidence_pair = frame["pairs"][pair]
                    per_frame[pair] = evidence_pair["crossings"]
                    if pair.endswith("self"):
                        self_max = max(self_max, evidence_pair["maximum_intersection_segment_m"])
                    else:
                        _add(clip["left_right"], frame["frame"], per_frame[pair],
                             evidence_pair["maximum_intersection_segment_m"])
                _add(clip["free_self"], frame["frame"],
                     per_frame["left_self"] + per_frame["right_self"], self_max)
                clip["per_frame"].append(per_frame)
            classified = sum(clip[key]["crossings"] for key in
                             ("sewn_joint", "retained_gown", "free_self", "left_right"))
            if classified != original["total_crossings"]:
                raise ValueError(f"Classification failed to preserve all {label} crossings")
            for category in ("sewn_joint", "retained_gown", "free_self", "left_right"):
                if not clip[category]["segment_lengths_complete"]:
                    # Never label a lower bound from an older mixed-category
                    # report as the true maximum of the classified subset.
                    clip[category]["maximum_intersection_segment_m"] = None
            clip["all_reported_crossings"] = classified
            clip["requires_free_surface_review"] = any(
                clip[key]["crossings"] for key in ("retained_gown", "free_self", "left_right"))
            result["clips"][label] = clip
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", nargs="+", required=True)
    parser.add_argument("--gown-proxy", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    destination = Path(args.output).resolve()
    if destination in {Path(path).resolve() for path in args.report + [args.gown_proxy]}:
        parser.error("Output must be separate from original report/NPZ evidence")
    summary = summarize(args.report, args.gown_proxy)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(summary, indent=2), encoding="utf-8")
    for name, clip in summary["clips"].items():
        print(name, {category: clip[category]["crossings"] for category in
                     ("sewn_joint", "retained_gown", "free_self", "left_right")},
              "free_surface_review", clip["requires_free_surface_review"])
    print("SLEEVE_CONTACT_SUMMARY_SAVED", destination)
