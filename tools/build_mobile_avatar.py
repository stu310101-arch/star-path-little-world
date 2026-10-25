"""Create mobile-only skeletal avatar copies without per-frame cloth morphs.

The existing base garment is already skinned to the authored skeleton. Keep
that neutral garment shape on mobile, retaining all original mesh attributes,
triangles, materials, joints, bind poses and non-morph animation samples.
Native and desktop Web assets are read-only inputs. This intentionally removes
secondary cloth flutter, not the walking, running, jump or landing motion.
"""
from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path

from prune_gameplay_jump_morph_noise import GLB, compact, sha

ROOT = Path(__file__).resolve().parents[1]


def bone_channels(doc, animation):
    return [(c, animation["samplers"][c["sampler"]])
            for c in animation["channels"] if c["target"]["path"] != "weights"]


def derive(source: Path, target: Path) -> dict:
    if source.resolve() == target.resolve():
        raise ValueError("Mobile export must not overwrite its source")
    source_hash = sha(source)
    src = GLB(source)
    try:
        doc = copy.deepcopy(src.doc)
        assert not doc.get("extensionsRequired"), "Review required extensions before stripping morphs"
        mesh_nodes = [node for node in doc["nodes"] if "mesh" in node]
        assert mesh_nodes and all("skin" in node for node in mesh_nodes), "Every mesh must retain skeletal deformation"
        assert all(not any(node.get("weights", [])) for node in mesh_nodes), "Bake nonzero default morph weights before export"
        assert all(not any(mesh.get("weights", [])) for mesh in doc["meshes"]), "Base garment must be the default pose"
        removed_targets = sum(len(mesh["primitives"][0].get("targets", [])) for mesh in doc["meshes"])
        removed_tracks = 0
        for mesh in doc["meshes"]:
            mesh.pop("weights", None)
            if "extras" in mesh:
                mesh["extras"].pop("targetNames", None)
            for primitive in mesh["primitives"]:
                assert {"POSITION", "JOINTS_0", "WEIGHTS_0"} <= primitive["attributes"].keys()
                primitive.pop("targets", None)
        for node in doc["nodes"]:
            node.pop("weights", None)
        for animation in doc["animations"]:
            old_samplers = animation["samplers"]
            channels, samplers = [], []
            for channel in animation["channels"]:
                if channel["target"]["path"] == "weights":
                    removed_tracks += 1
                    continue
                sampler = copy.deepcopy(old_samplers[channel["sampler"]])
                channel["sampler"] = len(samplers)
                samplers.append(sampler)
                channels.append(channel)
            animation["channels"] = channels
            animation["samplers"] = samplers
        target.parent.mkdir(parents=True, exist_ok=True)
        compact(doc, src, {}, target)
        out = GLB(target)
        try:
            assert out.doc.get("materials") == src.doc.get("materials")
            assert len(out.doc["nodes"]) == len(src.doc["nodes"])
            for before, after in zip(src.doc["nodes"], out.doc["nodes"]):
                expected = copy.deepcopy(before)
                expected.pop("weights", None)
                assert after == expected, "Node transforms, hierarchy and skin selection must be exact"
            triangles = vertices = surfaces = 0
            for before, after in zip(src.doc["meshes"], out.doc["meshes"]):
                assert len(before["primitives"]) == len(after["primitives"])
                assert "weights" not in after
                for bp, ap in zip(before["primitives"], after["primitives"]):
                    assert "targets" not in ap and bp.get("material") == ap.get("material")
                    assert bp.get("mode", 4) == ap.get("mode", 4) == 4
                    assert bp["attributes"].keys() == ap["attributes"].keys()
                    for name, accessor in bp["attributes"].items():
                        assert src.accessor(accessor) == out.accessor(ap["attributes"][name]), name
                    assert src.accessor(bp["indices"]) == out.accessor(ap["indices"])
                    triangles += out.doc["accessors"][ap["indices"]]["count"] // 3
                    vertices += out.doc["accessors"][ap["attributes"]["POSITION"]]["count"]
                    surfaces += 1
            for before, after in zip(src.doc["skins"], out.doc["skins"]):
                assert {k: v for k, v in before.items() if k != "inverseBindMatrices"} == {k: v for k, v in after.items() if k != "inverseBindMatrices"}
                assert src.accessor(before["inverseBindMatrices"]) == out.accessor(after["inverseBindMatrices"])
            preserved_channels = 0
            clips = []
            assert len(src.doc["animations"]) == len(out.doc["animations"])
            for before, after in zip(src.doc["animations"], out.doc["animations"]):
                assert before["name"] == after["name"]
                bc, ac = bone_channels(src.doc, before), bone_channels(out.doc, after)
                assert len(bc) == len(ac)
                assert len(ac) == len(after["channels"])
                for (bch, bs), (ach, ass) in zip(bc, ac):
                    assert bch["target"] == ach["target"]
                    assert bs.get("interpolation", "LINEAR") == ass.get("interpolation", "LINEAR")
                    for semantic in ["input", "output"]:
                        assert src.accessor(bs[semantic]) == out.accessor(ass[semantic]), before["name"]
                    preserved_channels += 1
                clips.append(before["name"])
        finally:
            out.close()
    finally:
        src.close()
    assert source_hash == sha(source), "Read-only source changed"
    return {"source": str(source.relative_to(ROOT)), "output": str(target.relative_to(ROOT)),
            "source_sha256": source_hash, "output_sha256": sha(target),
            "source_bytes": source.stat().st_size, "output_bytes": target.stat().st_size,
            "triangles": triangles, "vertices": vertices, "surfaces": surfaces,
            "removed_morph_targets": removed_targets, "removed_morph_tracks": removed_tracks,
            "preserved_bone_channels": preserved_channels, "clips": clips,
            "all_base_attributes_indices_materials_skin_and_bone_samples_exact": True,
            "visual_tradeoff": "Neutral skinned garment retains body motion; secondary cloth flutter is omitted on mobile."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "game/assets/character/runtime_web")
    parser.add_argument("--output", type=Path, default=ROOT / "game/assets/character/runtime_mobile")
    parser.add_argument("--report", type=Path, default=ROOT / "deliverables/mobile-optimization/avatar-assets.json")
    args = parser.parse_args()
    rows = [derive(args.source / name, args.output / name) for name in ["graduate.glb", "graduate_jump.glb"]]
    result = {"mode": "mobile_skeletal_only", "assets": rows,
              "source_bytes": sum(row["source_bytes"] for row in rows),
              "output_bytes": sum(row["output_bytes"] for row in rows),
              "note": "File and deformation-work reductions, not a measured phone FPS claim. Original sources remain untouched."}
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
