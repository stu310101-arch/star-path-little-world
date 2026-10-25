"""Report authored garden geometry/storage separately from rendered or PCK cost."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

from share_discussion_textures import ASSETS, ROOT, read_glb


def audit(path: Path) -> dict:
    document, _ = read_glb(path)
    mesh_triangles: list[int] = []
    mesh_surfaces: list[int] = []
    for mesh in document.get("meshes", []):
        triangles = 0
        for primitive in mesh["primitives"]:
            if primitive.get("mode", 4) != 4:
                raise ValueError("Audit expects triangle primitives")
            accessor = primitive.get("indices", primitive["attributes"]["POSITION"])
            triangles += document["accessors"][accessor]["count"] // 3
        mesh_triangles.append(triangles)
        mesh_surfaces.append(len(mesh["primitives"]))
    instances = [node["mesh"] for node in document.get("nodes", []) if "mesh" in node]
    textures = {}
    for image in document.get("images", []):
        if "uri" not in image:
            raise ValueError("Run shared texture postprocess before auditing")
        texture = (path.parent / image["uri"]).resolve()
        if not texture.is_relative_to(ASSETS.resolve()):
            raise ValueError("Texture outside asset directory")
        textures[texture.relative_to(ROOT).as_posix()] = {
            "bytes": texture.stat().st_size,
            "sha256": hashlib.sha256(texture.read_bytes()).hexdigest(),
        }
    return {
        "path": path.relative_to(ROOT).as_posix(),
        "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
        "glb_bytes": path.stat().st_size,
        "mesh_instances": len(instances),
        "unique_meshes": len(mesh_triangles),
        "instanced_triangles": sum(mesh_triangles[index] for index in instances),
        "unique_triangles": sum(mesh_triangles),
        "instanced_surfaces": sum(mesh_surfaces[index] for index in instances),
        "unique_surfaces": sum(mesh_surfaces),
        "external_textures": textures,
    }


def main() -> None:
    rows = {path.stem: audit(path) for path in sorted(ASSETS.glob("*.glb"))}
    profiles = {}
    devices = ["message_device_" + zone for zone in ("university", "major", "career", "high_school", "campus")]
    for profile, environment in (("minimum", "garden_low"), ("standard", "garden")):
        assets = [environment, *devices]
        textures = {}
        for key in assets:
            textures.update(rows[key]["external_textures"])
        profiles[profile] = {
            "asset_keys": assets,
            "glb_bytes": sum(rows[key]["glb_bytes"] for key in assets),
            "unique_texture_count": len(textures),
            "unique_texture_source_bytes": sum(row["bytes"] for row in textures.values()),
            "total_source_bytes": sum(rows[key]["glb_bytes"] for key in assets) + sum(row["bytes"] for row in textures.values()),
            "environment_triangles": rows[environment]["instanced_triangles"],
            "environment_surfaces": rows[environment]["instanced_surfaces"],
        }
    result = {
        "scope": "Authored source assets. Counts include all mesh nodes before visibility/frustum/LOD. File bytes include source GLBs and unique referenced external textures; these are not imported GPU memory or compressed WebPack download bytes.",
        "original_environment": {"glb_bytes": 69953044, "instanced_triangles": 962594, "instanced_surfaces": 127, "mesh_instances": 12, "sha256": "08169d62e9e3023d63155dcb7ce3b2c4ec0b7a130035b766f4fbaa38f0d3a7cd"},
        "assets": rows,
        "profiles": profiles,
    }
    target = ROOT / "deliverables/discussion-overhaul/performance/final-source-assets.json"
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(profiles, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
