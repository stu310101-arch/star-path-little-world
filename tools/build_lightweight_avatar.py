"""Derive error-bounded runtime GLBs; never overwrite authored character assets.

Requires NumPy. Bone tracks, key times, topology, materials and skinning are
preserved. A small linear cloth basis replaces dense per-frame morph caches.
Every source animation key (including default weights) is checked. Since both
weight curves remain LINEAR at identical times, the vector error between keys
cannot exceed the larger endpoint bound. Unit skin scales preserve that bound.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import re

# Do not compete for all laptop cores during an offline export.
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
import numpy as np

from prune_gameplay_jump_morph_noise import GLB, compact, sha

ROOT = Path(__file__).resolve().parents[1]
SCALE = 1.75 / 4.8


def add_accessor(doc, additions, values, kind="SCALAR"):
    data = np.asarray(values, dtype="<f4")
    components = {"SCALAR": 1, "VEC3": 3}[kind]
    raw = data.tobytes()
    view = len(doc["bufferViews"])
    doc["bufferViews"].append({"buffer": 0, "byteOffset": 0, "byteLength": len(raw)})
    additions[view] = raw
    accessor = {"bufferView": view, "componentType": 5126,
                "count": data.size // components, "type": kind}
    if kind == "VEC3":
        accessor.update(min=data.reshape(-1, 3).min(axis=0).tolist(),
                        max=data.reshape(-1, 3).max(axis=0).tolist())
    doc["accessors"].append(accessor)
    return len(doc["accessors"]) - 1


def array(src, index):
    return np.asarray(src.accessor(index), dtype=np.float32)


def derive(source: Path, target: Path, metres: float, normals: float, method: str):
    src = GLB(source)
    doc = copy.deepcopy(src.doc)
    assert not doc.get("extensionsRequired"), "Review required GLB extensions before deriving a runtime copy"
    # A legal GLB may share an animation sampler between multiple mesh channels.
    # Give each channel its own descriptor before changing its weight dimensions.
    for animation in doc.get("animations", []):
        samplers = animation["samplers"]
        animation["samplers"] = [copy.deepcopy(samplers[c["sampler"]]) for c in animation["channels"]]
        for index, channel in enumerate(animation["channels"]):
            channel["sampler"] = index
    additions, rows = {}, []
    protected = {"materials": copy.deepcopy(doc.get("materials")),
                 "skins": copy.deepcopy(doc.get("skins"))}
    bone_samples = []
    for animation in src.doc.get("animations", []):
        for channel in animation["channels"]:
            if channel["target"]["path"] != "weights":
                sampler = animation["samplers"][channel["sampler"]]
                bone_samples.append((animation["name"], copy.deepcopy(channel["target"]),
                                     array(src, sampler["input"]), array(src, sampler["output"])))
                if channel["target"]["path"] == "scale":
                    scale_values = array(src, sampler["output"])
                    expected_scale = SCALE if doc["nodes"][channel["target"]["node"]].get("name") == "Graduate" else 1.0
                    assert np.max(np.abs(scale_values - expected_scale)) < 1e-5
    for mi, mesh in enumerate(doc["meshes"]):
        source_mesh = src.doc["meshes"][mi]
        count = len(source_mesh["primitives"][0].get("targets", []))
        if not count:
            continue
        blocks, specs = [], []
        offset = 0
        for pi, primitive in enumerate(source_mesh["primitives"]):
            assert len(primitive.get("targets", [])) == count
            vertices = src.doc["accessors"][primitive["attributes"]["POSITION"]]["count"]
            for semantic, divisor in [("POSITION", metres / SCALE), ("NORMAL", normals)]:
                data = np.stack([array(src, item[semantic]) if semantic in item
                                 else np.zeros((vertices, 3), dtype=np.float32)
                                 for item in primitive["targets"]])
                block = data.reshape(count, -1) / divisor
                blocks.append(block)
                specs.append((pi, semantic, offset, offset + vertices * 3, divisor))
                offset += vertices * 3
        targets = np.concatenate(blocks, axis=1)
        del blocks
        channels, samples = [], []
        for ai, animation in enumerate(src.doc.get("animations", [])):
            for ci, channel in enumerate(animation["channels"]):
                if channel["target"]["path"] != "weights" or src.doc["nodes"][channel["target"]["node"]].get("mesh") != mi:
                    continue
                sampler = animation["samplers"][channel["sampler"]]
                assert sampler.get("interpolation", "LINEAR") == "LINEAR"
                weights = array(src, sampler["output"]).reshape(-1, count)
                start = sum(len(v) for v in samples)
                samples.append(weights)
                channels.append((ai, ci, start, start + len(weights)))
        defaults = [(mesh, "weights", source_mesh.get("weights", [0.] * count))]
        defaults.extend((doc["nodes"][ni], "weights", n["weights"])
                        for ni, n in enumerate(src.doc["nodes"])
                        if n.get("mesh") == mi and "weights" in n)
        defaults_start = sum(len(v) for v in samples)
        samples.append(np.array([value for _, _, value in defaults], dtype=np.float32))
        weights = np.concatenate(samples)
        evaluated = weights @ targets
        del weights, targets, samples
        def row_errors(difference):
            result = np.zeros(len(difference), dtype=np.float32)
            for _, _, lo, hi, _ in specs:
                result = np.maximum(result, np.linalg.norm(difference[:, lo:hi].reshape(len(difference), -1, 3), axis=2).max(axis=1))
            return result
        basis, sample_weights, hashes = [], [{} for _ in range(len(evaluated))], {}
        def pose_index(sample_index):
            pose = evaluated[sample_index]
            # Tiny numerical cache noise is not meaningful cloth motion.
            if row_errors(pose[None, :])[0] <= 0.10:
                return -1
            digest = hashlib.sha256(pose.tobytes()).digest()
            if digest not in hashes:
                hashes[digest] = len(basis)
                basis.append(pose.copy())
            return hashes[digest]
        if float(row_errors(evaluated).max()) > 0.90:
            for ai, ci, start, end in channels:
                channel = src.doc["animations"][ai]["channels"][ci]
                sampler = src.doc["animations"][ai]["samplers"][channel["sampler"]]
                times = array(src, sampler["input"]).ravel()
                selected = {0, end - start - 1}
                pending = [(0, end - start - 1)]
                while pending:
                    lower, upper = pending.pop()
                    if upper - lower <= 1:
                        continue
                    alpha = (times[lower + 1:upper] - times[lower]) / max(float(times[upper] - times[lower]), 1e-20)
                    predicted = evaluated[start + lower][None, :] * (1 - alpha[:, None]) + evaluated[start + upper][None, :] * alpha[:, None]
                    difference = evaluated[start + lower + 1:start + upper] - predicted
                    error = row_errors(difference)
                    worst = int(np.argmax(error))
                    if float(error[worst]) > 0.85:
                        middle = lower + worst + 1
                        selected.add(middle)
                        pending.extend([(lower, middle), (middle, upper)])
                selected = sorted(selected)
                for lower, upper in zip(selected, selected[1:]):
                    lower_pose, upper_pose = pose_index(start + lower), pose_index(start + upper)
                    for frame in range(lower, upper + 1):
                        alpha = float((times[frame] - times[lower]) / max(float(times[upper] - times[lower]), 1e-20))
                        if lower_pose >= 0:
                            sample_weights[start + frame][lower_pose] = 1 - alpha
                        if upper_pose >= 0:
                            sample_weights[start + frame][upper_pose] = sample_weights[start + frame].get(upper_pose, 0) + alpha
                if len(selected) == 1:
                    index = pose_index(start)
                    if index >= 0:
                        sample_weights[start][index] = 1
            for sample_index in range(defaults_start, len(evaluated)):
                index = pose_index(sample_index)
                if index >= 0:
                    sample_weights[sample_index][index] = 1
        if method == "pca":
            # Experimental alternative measured against authored sampling before
            # choosing a release. More active targets can cost more GLES3 passes.
            gram = evaluated.astype(np.float64) @ evaluated.T.astype(np.float64)
            eigenvalues, vectors = np.linalg.eigh(gram)
            order = np.argsort(eigenvalues)[::-1]
            eigenvalues, vectors = eigenvalues[order], vectors[:, order]
            basis, columns = [], []
            residual = evaluated.copy()
            for vi in range(len(eigenvalues)):
                if float(row_errors(residual).max()) <= 0.85:
                    break
                if eigenvalues[vi] <= 1e-10:
                    continue
                coefficient = vectors[:, vi] * np.sqrt(eigenvalues[vi])
                shape = vectors[:, vi] @ evaluated / np.sqrt(eigenvalues[vi])
                magnitude = max(float(np.abs(coefficient).max()), 1e-20)
                shape = (shape * magnitude).astype(np.float32)
                coefficient = (coefficient / magnitude).astype(np.float32)
                basis.append(shape)
                columns.append(coefficient)
                residual -= coefficient[:, None] * shape[None, :]
            coefficients = np.stack(columns, axis=1) if basis else np.zeros((len(evaluated), 0), dtype=np.float32)
        else:
            coefficients = np.zeros((len(evaluated), len(basis)), dtype=np.float32)
            for sample_index, values in enumerate(sample_weights):
                for index, value in values.items():
                    coefficients[sample_index, index] = value
            assert np.max(np.count_nonzero(coefficients, axis=1), initial=0) <= 2
        n = len(basis)
        reconstructed = coefficients @ np.stack(basis) if n else np.zeros_like(evaluated)
        residual = evaluated - reconstructed
        measured = [float(np.linalg.norm(residual[:, lo:hi].reshape(len(residual), -1, 3), axis=2).max())
                    for _, _, lo, hi, _ in specs]
        assert max(measured, default=0) <= 1.0, (source.name, mi, measured)
        for primitive in mesh["primitives"]:
            primitive.pop("targets", None)
            if n:
                primitive["targets"] = [{} for _ in range(n)]
        for pi, semantic, lo, hi, divisor in specs:
            for bi, shape in enumerate(basis):
                mesh["primitives"][pi]["targets"][bi][semantic] = add_accessor(doc, additions, shape[lo:hi].reshape(-1, 3) * divisor, "VEC3")
        mesh.setdefault("extras", {})["targetNames"] = [f"RuntimeCloth_{i:02d}" for i in range(n)]
        for di, (mapping, key, _) in enumerate(defaults):
            if n:
                mapping[key] = coefficients[defaults_start + di].tolist()
            else:
                mapping.pop(key, None)
        for ai, ci, start, end in channels:
            channel = doc["animations"][ai]["channels"][ci]
            if n:
                sampler = doc["animations"][ai]["samplers"][channel["sampler"]]
                sampler["output"] = add_accessor(doc, additions, coefficients[start:end])
            else:
                channel["_remove"] = True
        positional = [e * metres for e, spec in zip(measured, specs) if spec[1] == "POSITION"]
        normal = [e * normals for e, spec in zip(measured, specs) if spec[1] == "NORMAL"]
        rows.append({"mesh": source_mesh.get("name"), "targets_before": count, "targets_after": n,
                     "max_position_error_metres": max(positional, default=0),
                     "max_normal_delta_error": max(normal, default=0), "sample_count": len(evaluated),
                     "maximum_active_targets": int(np.max(np.count_nonzero(coefficients, axis=1), initial=0))})
        print(json.dumps(rows[-1]), flush=True)
        del evaluated, reconstructed, residual, basis, coefficients
    for animation in doc.get("animations", []):
        channels, samplers = [], []
        for channel in animation["channels"]:
            if channel.pop("_remove", False):
                continue
            sampler = animation["samplers"][channel["sampler"]]
            channel["sampler"] = len(samplers)
            channels.append(channel)
            samplers.append(sampler)
        animation["channels"], animation["samplers"] = channels, samplers
    assert doc.get("materials") == protected["materials"]
    assert doc.get("skins") == protected["skins"]
    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(".tmp")
    compact(doc, src, additions, temporary)
    check = GLB(temporary)
    bi = 0
    for animation in check.doc["animations"]:
        for channel in animation["channels"]:
            if channel["target"]["path"] == "weights":
                continue
            sampler = animation["samplers"][channel["sampler"]]
            name, target_node, times, values = bone_samples[bi]
            assert name == animation["name"] and target_node == channel["target"]
            assert np.array_equal(times, array(check, sampler["input"]))
            assert np.array_equal(values, array(check, sampler["output"]))
            bi += 1
    # Verify original mesh attributes / topology byte-values after compaction.
    for old, new in zip(src.doc["meshes"], check.doc["meshes"]):
        for op, np_ in zip(old["primitives"], new["primitives"]):
            assert op.get("material") == np_.get("material")
            for semantic, index in op["attributes"].items():
                assert np.array_equal(array(src, index), array(check, np_["attributes"][semantic]))
            assert np.array_equal(array(src, op["indices"]), array(check, np_["indices"]))
    check.close()
    src.close()
    os.replace(temporary, target)
    import_path = target.with_name(target.name + ".import")
    if not import_path.exists():
        # Preserve the project's no-tangent/no-generated-LOD import policy for a
        # fresh checkout or experimental variant; never duplicate an asset UID.
        original_resource = "res://" + source.relative_to(ROOT / "game").as_posix()
        derived_resource = "res://" + target.relative_to(ROOT / "game").as_posix()
        settings = source.with_name(source.name + ".import").read_text(encoding="utf8")
        settings = re.sub(r"^uid=.*\n", "", settings, flags=re.MULTILINE)
        settings = settings.replace(original_resource, derived_resource)
        settings = settings.replace(hashlib.md5(original_resource.encode()).hexdigest(), hashlib.md5(derived_resource.encode()).hexdigest())
        import_path.write_text(settings, encoding="utf8")
    return {"source": str(source.relative_to(ROOT)), "source_sha256": sha(source),
            "output": str(target.relative_to(ROOT)), "output_sha256": sha(target),
            "source_bytes": source.stat().st_size, "output_bytes": target.stat().st_size,
            "position_tolerance_metres": metres, "normal_delta_tolerance": normals,
            "triangles": sum(src.doc["accessors"][p["indices"]]["count"] // 3 for m in src.doc["meshes"] for p in m["primitives"]),
            "vertices": sum(src.doc["accessors"][p["attributes"]["POSITION"]]["count"] for m in src.doc["meshes"] for p in m["primitives"]),
            "bone_tracks_and_times_exact": True, "mesh_topology_attributes_materials_exact": True,
            "targets_before": sum(x["targets_before"] for x in rows),
            "targets_after": sum(x["targets_after"] for x in rows), "meshes": rows}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--position-error-mm", type=float, default=2.0)
    parser.add_argument("--normal-error", type=float, default=0.05)
    parser.add_argument("--method", choices=["authored", "pca"], default="authored")
    args = parser.parse_args()
    folder = ROOT / "game/assets/character"
    sources = [folder / "graduate.glb", folder / "graduate_jump.glb"]
    preserved = {str(p.relative_to(ROOT)): sha(p) for p in sources + [folder / "graduate_rest.glb"]}
    output_folder = "runtime" if args.method == "authored" else "runtime_pca"
    rows = [derive(p, folder / output_folder / p.name, args.position_error_mm / 1000, args.normal_error, args.method) for p in sources]
    assert all(sha(ROOT / p) == digest for p, digest in preserved.items())
    report = {"method": "Adaptive authored cloth pose sampling and exact duplicate pose sharing; at most two active morphs per mesh. Original animation times and skeletal tracks retained." if args.method == "authored" else "Experimental PCA cloth basis with signed weights. Original animation times and skeletal tracks retained. Benchmark and render validation required before release.",
              "interpolation_bound": "LINEAR morph curves share the original key times; intermediate vector error is bounded by endpoint errors. Root scale is included; skin scale tracks are checked as unity.",
              "originals_preserved": preserved, "assets": rows}
    (folder / output_folder / "derivation.json").write_text(json.dumps(report, indent=2), encoding="utf8")
    print("LIGHTWEIGHT_AVATAR " + json.dumps([{k: r[k] for k in ["output", "source_bytes", "output_bytes", "targets_before", "targets_after"]} for r in rows]))


if __name__ == "__main__":
    main()
