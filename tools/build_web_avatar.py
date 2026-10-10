"""Batch the runtime avatar by identical material, preserving authored motion.

Web-only export copies. All meshes must share the same skin, parent and identity
transform. LINEAR cloth channels must share key times within each clip. Their
evaluated poses are combined into one synchronized pair of active blend shapes,
so batching does not multiply the active deformation passes. No decimation,
material conversion, animation resampling or bone-track changes are permitted.
"""
from __future__ import annotations

import copy
import hashlib
import json
import os
from pathlib import Path
import re

os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")
os.environ.setdefault("OMP_NUM_THREADS", "1")
import numpy as np

from prune_gameplay_jump_morph_noise import GLB, compact, sha

ROOT = Path(__file__).resolve().parents[1]
DTYPES = {5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}
COMPONENTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def array(src, index):
    spec = src.doc["accessors"][index]
    if "sparse" in spec or "bufferView" not in spec:
        return np.asarray(src.accessor(index), dtype=DTYPES[spec["componentType"]])
    view = src.doc["bufferViews"][spec["bufferView"]]
    dtype = np.dtype(DTYPES[spec["componentType"]])
    width = COMPONENTS[spec["type"]]
    return np.ndarray((spec["count"], width), dtype=dtype, buffer=src.raw,
                      offset=src.base + view.get("byteOffset", 0) + spec.get("byteOffset", 0),
                      strides=(view.get("byteStride", width * dtype.itemsize), dtype.itemsize)).copy()


def derive(source, target):
    source_hash = sha(source)
    src = GLB(source)
    doc = copy.deepcopy(src.doc)
    assert not doc.get("extensionsRequired") and not doc.get("images")
    parents = {child: i for i, node in enumerate(doc["nodes"]) for child in node.get("children", [])}
    mesh_nodes = {node["mesh"]: i for i, node in enumerate(doc["nodes"]) if "mesh" in node}
    assert len(mesh_nodes) == len(doc["meshes"]) == sum("mesh" in node for node in doc["nodes"]), "Shared mesh instances require separate review"
    parent_set, skin_set = set(), set()
    for mi, ni in mesh_nodes.items():
        node = doc["nodes"][ni]
        assert "matrix" not in node
        assert node.get("translation", [0, 0, 0]) == [0, 0, 0]
        assert node.get("rotation", [0, 0, 0, 1]) == [0, 0, 0, 1]
        assert node.get("scale", [1, 1, 1]) == [1, 1, 1]
        assert not any(node.get("weights", doc["meshes"][mi].get("weights", [])))
        parent_set.add(parents[ni]); skin_set.add(node["skin"])
    assert len(parent_set) == len(skin_set) == len(doc["skins"]) == 1
    # Leave original node indices/names intact for every skeletal channel.
    node_index = len(doc["nodes"])
    doc["nodes"].append({"name": "WebGraduateBatched", "mesh": 0, "skin": next(iter(skin_set))})
    doc["nodes"][next(iter(parent_set))]["children"].append(node_index)
    for ni in mesh_nodes.values():
        for key in ("mesh", "skin", "weights"):
            doc["nodes"][ni].pop(key, None)

    additions = {}
    def add(values, kind="SCALAR", component=5126):
        values = np.asarray(values, dtype=DTYPES[component])
        raw = values.tobytes()
        vi = len(doc["bufferViews"])
        doc["bufferViews"].append({"buffer": 0, "byteOffset": 0, "byteLength": len(raw)})
        additions[vi] = raw
        spec = {"bufferView": vi, "componentType": component, "count": values.size // COMPONENTS[kind], "type": kind}
        if kind in ("VEC3", "SCALAR") and values.size:
            shaped = values.reshape(-1, COMPONENTS[kind])
            spec.update(min=shaped.min(axis=0).tolist(), max=shaped.max(axis=0).tolist())
        doc["accessors"].append(spec)
        return len(doc["accessors"]) - 1

    groups = {}
    mapping = []
    for mi, mesh in enumerate(src.doc["meshes"]):
        for pi, primitive in enumerate(mesh["primitives"]):
            assert primitive.get("mode", 4) == 4 and not primitive.get("extensions")
            assert set(primitive["attributes"]) in ({"POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0"}, {"POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0", "JOINTS_1", "WEIGHTS_1"})
            material = primitive["material"]
            group = groups.setdefault(material, {"parts": [], "vertices": 0})
            count = src.doc["accessors"][primitive["attributes"]["POSITION"]]["count"]
            row = {"mesh": mi, "primitive": pi, "material": material,
                   "offset": group["vertices"], "vertices": count}
            mapping.append(row)
            group["parts"].append(row)
            group["vertices"] += count

    # Each clip contributes exact existing key samples, shared across materials.
    clips = []
    for ai, animation in enumerate(src.doc["animations"]):
        channels, common_times = {}, None
        for channel in animation["channels"]:
            ni = channel["target"]["node"]
            if channel["target"]["path"] != "weights":
                assert ni not in mesh_nodes.values(), "Animated mesh transforms cannot be batched"
                continue
            mi = src.doc["nodes"][ni]["mesh"]
            sampler = animation["samplers"][channel["sampler"]]
            assert sampler.get("interpolation", "LINEAR") == "LINEAR"
            times = array(src, sampler["input"])
            assert common_times is None or np.array_equal(common_times, times), "Cloth key times changed; review batching"
            common_times = times
            count = len(src.doc["meshes"][mi]["primitives"][0]["targets"])
            channels[mi] = array(src, sampler["output"]).reshape(-1, count)
        assert common_times is not None
        clips.append({"index": ai, "name": animation["name"], "times": common_times, "weights": channels})

    total_samples = sum(len(c["times"]) for c in clips)
    pose_blocks = []
    for material, group in groups.items():
        block = np.zeros((total_samples, group["vertices"], 6), dtype=np.float32)
        for row in group["parts"]:
            mi, pi, offset, count = row["mesh"], row["primitive"], row["offset"], row["vertices"]
            primitive = src.doc["meshes"][mi]["primitives"][pi]
            targets = primitive.get("targets", [])
            if not targets:
                continue
            shapes = np.zeros((len(targets), count, 6), dtype=np.float32)
            for ti, morph in enumerate(targets):
                assert not set(morph) - {"POSITION", "NORMAL"}
                for semantic, start in (("POSITION", 0), ("NORMAL", 3)):
                    if semantic in morph:
                        shapes[ti, :, start:start + 3] = array(src, morph[semantic])
            start = 0
            for clip in clips:
                frames = len(clip["times"])
                if mi in clip["weights"]:
                    block[start:start + frames, offset:offset + count] = (clip["weights"][mi] @ shapes.reshape(len(targets), -1)).reshape(frames, count, 6)
                start += frames
        pose_blocks.append(block)

    # Identical/zero poses share storage exactly, without an error threshold.
    unique, samples, hashes = [], [], {}
    for i in range(total_samples):
        if not any(np.any(block[i]) for block in pose_blocks):
            samples.append(-1)
            continue
        key = hashlib.sha256(b"".join(block[i].tobytes() for block in pose_blocks)).digest()
        if key not in hashes:
            hashes[key] = len(unique); unique.append(i)
        samples.append(hashes[key])
    primitives = []
    for surface, ((material, group), block) in enumerate(zip(groups.items(), pose_blocks)):
        attributes, indices = {}, []
        semantics = {key for r in group["parts"] for key in src.doc["meshes"][r["mesh"]]["primitives"][r["primitive"]]["attributes"]}
        for semantic in sorted(semantics):
            old_ids = [src.doc["meshes"][r["mesh"]]["primitives"][r["primitive"]]["attributes"].get(semantic) for r in group["parts"]]
            specs = [src.doc["accessors"][i] for i in old_ids if i is not None]
            assert all(s["type"] == specs[0]["type"] and s["componentType"] == specs[0]["componentType"] and not s.get("normalized") for s in specs)
            values = [array(src, i) if i is not None else np.zeros((r["vertices"], COMPONENTS[specs[0]["type"]]), dtype=DTYPES[specs[0]["componentType"]]) for i, r in zip(old_ids, group["parts"])]
            attributes[semantic] = add(np.concatenate(values), specs[0]["type"], specs[0]["componentType"])
        for row in group["parts"]:
            primitive = src.doc["meshes"][row["mesh"]]["primitives"][row["primitive"]]
            indices.append(array(src, primitive["indices"]).astype(np.uint32) + row["offset"])
            row["surface"] = surface
        targets = [{"POSITION": add(block[i, :, :3], "VEC3"), "NORMAL": add(block[i, :, 3:], "VEC3")} for i in unique]
        primitives.append({"attributes": attributes, "indices": add(np.concatenate(indices), component=5125), "material": material, "targets": targets})
    doc["meshes"] = [{"name": "WebGraduateBatched", "primitives": primitives, "weights": [0.] * len(unique),
                      "extras": {"targetNames": [f"pose_{i:03d}" for i in range(len(unique))]}}]
    start = 0
    for clip in clips:
        animation = doc["animations"][clip["index"]]
        old_samplers = animation["samplers"]
        animation["channels"] = [c for c in animation["channels"] if c["target"]["path"] != "weights"]
        animation["samplers"] = []
        for channel in animation["channels"]:
            sampler = old_samplers[channel["sampler"]]
            channel["sampler"] = len(animation["samplers"])
            animation["samplers"].append(sampler)
        weights = np.zeros((len(clip["times"]), len(unique)), dtype=np.float32)
        for key in range(len(weights)):
            pose = samples[start + key]
            if pose >= 0:
                weights[key, pose] = 1
        animation["channels"].append({"sampler": len(animation["samplers"]), "target": {"node": node_index, "path": "weights"}})
        animation["samplers"].append({"input": add(clip["times"]), "output": add(weights), "interpolation": "LINEAR"})
        start += len(clip["times"])

    target.parent.mkdir(parents=True, exist_ok=True)
    compact(doc, src, additions, target)
    # Validate the serialized output, including per-source vertex/triangle mapping.
    out = GLB(target)
    assert out.doc["materials"] == src.doc["materials"] and out.doc["skins"] != []
    assert out.doc["skins"][0]["joints"] == src.doc["skins"][0]["joints"]
    assert np.array_equal(array(out, out.doc["skins"][0]["inverseBindMatrices"]), array(src, src.doc["skins"][0]["inverseBindMatrices"]))
    for row in mapping:
        before = src.doc["meshes"][row["mesh"]]["primitives"][row["primitive"]]
        after = out.doc["meshes"][0]["primitives"][row["surface"]]
        for semantic, index in before["attributes"].items():
            assert np.array_equal(array(src, index), array(out, after["attributes"][semantic])[row["offset"]:row["offset"] + row["vertices"]])
    for material, group in groups.items():
        index_parts = []
        for row in group["parts"]:
            primitive = src.doc["meshes"][row["mesh"]]["primitives"][row["primitive"]]
            index_parts.append(array(src, primitive["indices"]).astype(np.uint32) + row["offset"])
        after = out.doc["meshes"][0]["primitives"][group["parts"][0]["surface"]]
        assert after["material"] == material
        assert np.array_equal(np.concatenate(index_parts), array(out, after["indices"]))
    for before, after in zip(src.doc["animations"], out.doc["animations"]):
        bc = [c for c in before["channels"] if c["target"]["path"] != "weights"]
        ac = [c for c in after["channels"] if c["target"]["path"] != "weights"]
        assert len(bc) == len(ac)
        for b, a in zip(bc, ac):
            assert b["target"] == a["target"]
            bs, ass = before["samplers"][b["sampler"]], after["samplers"][a["sampler"]]
            assert bs.get("interpolation", "LINEAR") == ass.get("interpolation", "LINEAR")
            for field in ("input", "output"):
                assert np.array_equal(array(src, bs[field]), array(out, ass[field]))
    for surface, block in enumerate(pose_blocks):
        targets = out.doc["meshes"][0]["primitives"][surface]["targets"]
        for source_sample, pose in enumerate(samples):
            if pose < 0:
                assert not np.any(block[source_sample])
            else:
                for semantic, start in (("POSITION", 0), ("NORMAL", 3)):
                    assert np.array_equal(array(out, targets[pose][semantic]), block[source_sample, :, start:start + 3])
    source_resource = "res://" + source.relative_to(ROOT / "game").as_posix()
    target_resource = "res://" + target.relative_to(ROOT / "game").as_posix()
    import_path = target.with_name(target.name + ".import")
    if not import_path.exists():
        settings = source.with_name(source.name + ".import").read_text(encoding="utf-8")
        settings = re.sub(r"^uid=.*\n", "", settings, flags=re.M)
        settings = settings.replace(source_resource, target_resource).replace(hashlib.md5(source_resource.encode()).hexdigest(), hashlib.md5(target_resource.encode()).hexdigest())
        import_path.write_text(settings, encoding="utf-8")
    report = {"source": source.relative_to(ROOT).as_posix(), "source_sha256": source_hash,
              "output": target.relative_to(ROOT).as_posix(), "output_sha256": sha(target),
              "source_bytes": source.stat().st_size, "output_bytes": target.stat().st_size,
              "surfaces_before": len(mapping), "surfaces_after": len(groups), "shared_poses": len(unique),
              "clips": [{"name": c["name"], "keys": len(c["times"])} for c in clips],
              "source_to_output": mapping, "validated": "Exact base attributes, triangles, material values, bone channels/times, skin bind matrices and float32 evaluated cloth key poses. LINEAR curves retain original times; intermediate poses are their same interpolation (subject to floating point rounding). Actual imported/rendered validation is separate."}
    out.close(); src.close()
    assert sha(source) == source_hash
    return report


if __name__ == "__main__":
    folder = ROOT / "game/assets/character"
    rows = [derive(folder / "runtime" / name, folder / "runtime_web" / name) for name in ("graduate.glb", "graduate_jump.glb")]
    (folder / "runtime_web/derivation.json").write_text(json.dumps(rows, indent=2) + "\n", encoding="utf-8")
    print(json.dumps([{k: r[k] for k in ("output", "source_bytes", "output_bytes", "surfaces_before", "surfaces_after", "shared_poses")} for r in rows]))
