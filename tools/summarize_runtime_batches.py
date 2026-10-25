"""Read-only draw opportunity analysis of the Godot headless asset census.

Counts potential base-pass submissions, never GPU FPS. No product assets change.
"""
from __future__ import annotations
import collections
import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FOLDER = ROOT / "deliverables/render-budget"


def category(row):
    name = row["node"].lower()
    if "architecturalenvelope" in name:
        return "building_envelope"
    if "pathlantern" in name:
        return "path_lantern"
    if "fineleafstreetplanter" in name:
        return "planter"
    if any(part in name for part in ["sedan", "hatchback", "suv"]):
        return "vehicle"
    if any(part in name for part in ["fish", "shark", "boat"]):
        return "fish_or_boat"
    if "entrancewayfinding" in name:
        return "station_wayfinding"
    if "bakedsilhouette" in name:
        return "overview_batch"
    if any(part in name for part in ["contoured", "shorerock", "shallowwaterbed"]):
        return "terrain_or_shore"
    if any(part in name for part in ["sidewalk", "asphalt", "walkway", "paving", "forecourt", "promenade"]):
        return "road_or_paving"
    return "other"


def surface_groups(rows, mats, mode):
    groups = collections.defaultdict(list)
    for row in rows:
        if row["class"] != "MeshInstance3D" or row["blocked"] or row["context"]["scripts"]:
            continue
        ctx = row["context"]
        # This analysis does not alter identity-addressed or interactive meshes.
        if set(ctx["metadata"]) & {"station_id", "rest_seat", "bench_seat", "seat", "interactable",
                                   "mobile_render_mesh", "mobile_render_tiles", "mobile_surface_tiles"}:
            continue
        fade = ctx["camera_group"]
        if mode == "fade_group" and not fade:
            continue
        if mode == "chunk_cell4" and fade:
            continue
        if any(layer & 8 for layer in row["collision_layers"]) and not fade:
            continue
        branch = row["node"].split("/")[0] if row["region"] == "base" else ""
        if mode == "fade_group":
            boundary = fade
        else:
            # Refuse large ground sheets: merging those can defeat current culling.
            if max(row["world_aabb_size"]) > 4.0:
                continue
            cell = tuple(math.floor(value / 4.0) for value in row["world_center"])
            boundary = cell
        for surface, material_id in enumerate(row["materials"]):
            if row["surface_blocks"][surface]:
                continue
            material = mats.get(material_id, {})
            # Local triplanar projection changes when rebaking transforms.
            projection = row["world_transform"] if material.get("local_triplanar") else ""
            key = (row["scene"], branch, boundary, material.get("value_signature", "default"),
                   row["formats"][surface], row["draw_state"], projection)
            groups[key].append((row, surface, material_id))
    out = []
    for key, surfaces in groups.items():
        nodes = {row["node"] for row, _, _ in surfaces}
        if len(nodes) < 2:
            continue
        first = surfaces[0][0]
        min_corner = [min(r["world_aabb_position"][i] for r, _, _ in surfaces) for i in range(3)]
        max_corner = [max(r["world_aabb_position"][i] + r["world_aabb_size"][i] for r, _, _ in surfaces) for i in range(3)]
        extent = [b - a for a, b in zip(min_corner, max_corner)]
        # Cell membership by center is not enough: keep union bounds <=5m.
        if mode == "chunk_cell4" and max(extent) > 5.0:
            continue
        out.append({
            "scene": first["scene"], "region": first["region"], "mode": mode,
            "boundary": key[2], "surface_submissions": len(surfaces),
            "max_reduction_per_base_pass": len(surfaces) - 1,
            "world_union_extent_m": extent,
            "material_name": mats.get(surfaces[0][2], {}).get("name", ""),
            "shader": mats.get(surfaces[0][2], {}).get("shader", ""),
            "categories": dict(collections.Counter(category(row) for row, _, _ in surfaces)),
            "members": [{"node": row["node"], "parent": row["parent"], "surface": s}
                        for row, s, _ in surfaces],
            "status": "candidate_only_requires_original_node_fade_and_culling_equivalence",
        })
    return sorted(out, key=lambda row: -row["max_reduction_per_base_pass"])


def main():
    p = json.loads((FOLDER / "runtime-batching-audit.json").read_text(encoding="utf-8-sig"))
    mats, rows = p["materials"], p["runtime_meshes"]
    live_ids = {identity for row in rows for identity in row["materials"] if identity != "default"}
    by_shader = collections.defaultdict(lambda: {"material_ids": set(), "shader_ids": set(),
                                                 "code_hashes": set(), "surfaces": 0})
    usage = collections.defaultdict(list)
    categories = collections.defaultdict(lambda: {"nodes": 0, "surfaces": 0, "ids": set(), "values": set(), "parents": []})
    for row in rows:
        cat = categories[category(row)]
        cat["nodes"] += 1
        cat["surfaces"] += row["surfaces"]
        cat["ids"].update(row["materials"])
        cat["values"].update(mats[i]["value_signature"] for i in row["materials"] if i != "default")
        if len(cat["parents"]) < 8:
            cat["parents"].append({"scene": row["scene"], "parent": row["parent"], "node": row["node"]})
        for surface, identity in enumerate(row["materials"]):
            if identity == "default":
                continue
            mat = mats[identity]
            usage[mat["value_signature"]].append((row, surface, identity))
            if mat["class"] == "ShaderMaterial":
                shader = by_shader[mat["shader"]]
                shader["material_ids"].add(identity)
                shader["shader_ids"].add(mat.get("shader_id"))
                shader["code_hashes"].add(mat.get("shader_code_sha256"))
                shader["surfaces"] += 1
    ranked = []
    for sig, uses in usage.items():
        first = mats[uses[0][2]]
        identities = {i for _, _, i in uses}
        ranked.append({
            "name": first["name"], "class": first["class"], "shader": first["shader"],
            "surface_submissions": len(uses), "material_identities": len(identities),
            "distinct_nodes": len({(r["scene"], r["node"]) for r, _, _ in uses}),
            "distinct_fade_groups": len({r["context"]["camera_group"] for r, _, _ in uses}),
            "categories": dict(collections.Counter(category(r) for r, _, _ in uses)),
            "members_sample": [{"scene": r["scene"], "parent": r["parent"], "node": r["node"], "surface": s}
                               for r, s, _ in uses[:10]],
        })
    fade = surface_groups(rows, mats, "fade_group")
    cells = surface_groups(rows, mats, "chunk_cell4")
    result = {
        "date": p["date"],
        "scope": "Asset submissions only; no GPU measurement; overview and detail totals are mutually exclusive in gameplay",
        "source_unchanged": p["source_files_unchanged"],
        "runtime_material_ids_including_hidden": p["stages"]["runtime"]["unique_material_identities"],
        "runtime_visible_material_ids": len(live_ids),
        "runtime_unique_values_including_hidden": p["stages"]["runtime"]["value_unique_materials"],
        "runtime_redundant_ids": p["stages"]["runtime"]["redundant_material_identities"],
        "runtime_replace_counts": p["runtime_replace_counts"],
        "material_resource_reuse_draw_saving": 0,
        "shader_resources": {
            key: {"material_identities": len(v["material_ids"]), "shader_resource_identities": len(v["shader_ids"]),
                  "distinct_shader_code_hashes": len(v["code_hashes"]), "surface_submissions": v["surfaces"]}
            for key, v in by_shader.items()
        },
        "categories": {key: {"nodes": v["nodes"], "surface_submissions": v["surfaces"],
                            "material_identities": len(v["ids"]), "material_values": len(v["values"]),
                            "parent_examples": v["parents"]} for key, v in categories.items()},
        "top_repeated_material_draws": sorted(ranked, key=lambda row: -row["surface_submissions"])[:35],
        "same_mesh_surface_reduction": p["same_mesh_max_base_pass_reduction"],
        "same_parent_small_prop_candidates": len(p["sibling_candidates"]),
        "same_parent_by_region": dict(collections.Counter(r["region"] for r in p["sibling_candidates"])),
        "fade_group_candidates": fade,
        "fade_group_max_reduction_per_base_pass": sum(r["max_reduction_per_base_pass"] for r in fade),
        "chunk_cell4_candidates": cells,
        "chunk_cell4_max_reduction_per_base_pass": sum(r["max_reduction_per_base_pass"] for r in cells),
        "warning": "The 85 small-parent candidates overlap 4m-cell candidates. Do not add their reductions. "
                   "Material reuse is a resource/state-management opportunity, not measured FPS or guaranteed uniform-upload saving.",
    }
    (FOLDER / "runtime-batching-summary.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: result[key] for key in ["runtime_redundant_ids", "shader_resources",
          "same_mesh_surface_reduction", "same_parent_small_prop_candidates",
          "fade_group_max_reduction_per_base_pass", "chunk_cell4_max_reduction_per_base_pass"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
