extends SceneTree

## Read-only asset census. No scenes/resources are saved and no renderer is used.
## Replays the same shared WorldArtDirection.apply() call as world.gd on the
## actual shipped streaming bases/chunks, without running gameplay scripts.
const ArtDirection = preload("res://scripts/world_art_direction.gd")
const OUTPUT: String = "res://../deliverables/render-budget/runtime-batching-audit.json"
const BASES: Array[String] = [
	"res://generated/streaming/globe_base.scn",
	"res://generated/streaming/neighborhood_base.scn",
	"res://generated/streaming/stations_base.scn",
]
const DRAW_PROPERTIES: Array[String] = [
	"layers", "cast_shadow", "gi_mode", "transparency", "lod_bias",
	"visibility_range_begin", "visibility_range_end", "visibility_range_begin_margin",
	"visibility_range_end_margin", "visibility_range_fade_mode", "extra_cull_margin",
	"ignore_occlusion_culling", "sorting_offset", "sorting_use_aabb_center",
]
var art: RefCounted = ArtDirection.new()
var materials: Dictionary = {}
var material_refs: Array[Material] = []
var stages: Dictionary = {}
var scenes: Array[Dictionary] = []
var same_mesh: Array[Dictionary] = []
var siblings: Array[Dictionary] = []
var post_rows: Array[Dictionary] = []
var serialized_material_signatures: Dictionary = {}
var audit_scene_path: String
var current_region: String

func _initialize() -> void:
	call_deferred("run")

func new_stage() -> Dictionary:
	return {"mesh_nodes": 0, "multimesh_nodes": 0, "visible_surface_submissions": 0,
		"hidden_surface_submissions": 0, "material_ids": {}, "material_uses": {}}

func resource_key(resource: Resource, semantic: bool) -> String:
	if semantic and not resource.resource_path.is_empty() and not "::" in resource.resource_path and resource.get_script() == null:
		return resource.get_class() + ":" + resource.resource_path
	return resource.get_class() + ":id:" + str(resource.get_instance_id())

func material_signature(material: Material, semantic: bool) -> String:
	var values: PackedStringArray = [material.get_class()]
	for property: Dictionary in material.get_property_list():
		var key: String = str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or key in ["resource_name", "resource_path", "resource_scene_unique_id"]:
			continue
		var value: Variant = material.get(key)
		values.append(key + "=" + (resource_key(value as Resource, semantic) if value is Resource else var_to_str(value)))
	values.sort()
	return str(values).sha256_text()

func material_id(material: Material) -> String:
	if material == null:
		return "default"
	var id: String = str(material.get_instance_id())
	if materials.has(id):
		return id
	material_refs.append(material)
	var shader: String = material.shader.resource_path if material is ShaderMaterial and material.shader != null else ""
	materials[id] = {"id": id, "class": material.get_class(), "name": material.resource_name,
		"path": material.resource_path, "exact_signature": material_signature(material, false),
		"value_signature": material_signature(material, true), "shader": shader,
		"local_to_scene": material.resource_local_to_scene, "script": material.get_script() != null,
		"next_pass": material.next_pass != null}
	if material is ShaderMaterial and material.shader != null:
		materials[id]["shader_id"] = str(material.shader.get_instance_id())
		materials[id]["shader_code_sha256"] = material.shader.code.sha256_text()
	if material is StandardMaterial3D:
		var standard: StandardMaterial3D = material as StandardMaterial3D
		materials[id]["transparency"] = standard.transparency
		materials[id]["local_triplanar"] = (standard.uv1_triplanar and not standard.uv1_world_triplanar) or (standard.uv2_triplanar and not standard.uv2_world_triplanar)
		materials[id]["albedo_texture"] = standard.albedo_texture.resource_path if standard.albedo_texture != null else ""
	return id

func context(node: Node, root: Node) -> Dictionary:
	var visible: bool = true
	var scripts: PackedStringArray = []
	var camera_group: String = ""
	var metadata: PackedStringArray = []
	var cursor: Node = node
	while cursor != null:
		if cursor is Node3D:
			visible = visible and (cursor as Node3D).visible
		if cursor.get_script() != null:
			scripts.append(str(cursor.get_script().resource_path))
		if camera_group.is_empty() and cursor.has_meta("camera_visual_group"):
			camera_group = str(cursor.get_meta("camera_visual_group"))
		for key: StringName in cursor.get_meta_list():
			var text: String = str(key)
			if text in ["bench_seat", "rest_seat", "seat", "interactable", "station_id", "camera_visual_group", "streaming_overview_id", "mobile_render_mesh", "mobile_surface_tiles", "mobile_render_tiles"]:
				metadata.append(text)
		if cursor == root:
			break
		cursor = cursor.get_parent()
	return {"visible": visible, "scripts": scripts, "camera_group": camera_group, "metadata": metadata}

func world_transform(node: Node, root: Node) -> Transform3D:
	var result: Transform3D = Transform3D.IDENTITY
	var cursor: Node = node
	while cursor != null:
		if cursor is Node3D:
			result = (cursor as Node3D).transform * result
		if cursor == root:
			break
		cursor = cursor.get_parent()
	return result

func vector(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func plain_mesh_reason(visual: MeshInstance3D) -> String:
	var mesh: Mesh = visual.mesh
	if visual.skin != null or visual.material_overlay != null or mesh.get_script() != null:
		return "skin_overlay_or_mesh_script"
	if mesh is ArrayMesh:
		if mesh.get_blend_shape_count() > 0 or mesh.shadow_mesh != null:
			return "blend_shape_or_shadow_mesh"
		for surface: Dictionary in mesh.get("_surfaces") as Array:
			if surface.has("lods") and not (surface.lods as Array).is_empty():
				return "authored_lods"
	else:
		if not mesh is PrimitiveMesh or mesh is PointMesh:
			return "unsupported_mesh"
	var unsupported: int = Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3
	for surface: int in range(mesh.get_surface_count()):
		if mesh is ArrayMesh and mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			return "non_triangles"
		if (mesh_format(mesh, surface) & unsupported) != 0:
			return "custom_channels_or_skin"
	return ""

func mesh_format(mesh: Mesh, surface: int) -> int:
	if mesh is ArrayMesh:
		return (mesh as ArrayMesh).surface_get_format(surface)
	var arrays: Array = mesh.surface_get_arrays(surface)
	var format: int = 0
	for index: int in range(arrays.size()):
		if arrays[index] != null and arrays[index].size() > 0:
			format |= 1 << index
	return format

func material_merge_reason(material: Material) -> String:
	if material == null:
		return ""
	if material.resource_local_to_scene or material.get_script() != null or material.next_pass != null:
		return "material_identity_contract"
	if material is StandardMaterial3D:
		if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or material.billboard_mode != BaseMaterial3D.BILLBOARD_DISABLED:
			return "transparent_or_billboard"
		return ""
	if material is ShaderMaterial and material.shader != null and material.shader.resource_path in [
		"res://shaders/world_surface.gdshader", "res://shaders/world_surface_mobile.gdshader",
	]:
		return ""
	return "custom_shader_not_reviewed"

func draw_signature(visual: MeshInstance3D) -> String:
	var values: PackedStringArray = []
	for key: String in DRAW_PROPERTIES:
		values.append(key + "=" + var_to_str(visual.get(key)))
	return str(values)

func inspect(root: Node, stage_name: String) -> Dictionary:
	var summary: Dictionary = new_stage()
	var nodes: Array[Node] = [root]
	nodes.append_array(root.find_children("*", "Node", true, false))
	var sibling_groups: Dictionary = {}
	for node: Node in nodes:
		var mesh: Mesh
		var visual: MeshInstance3D = node as MeshInstance3D
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		if visual != null:
			mesh = visual.mesh
			summary.mesh_nodes += 1
		elif multi != null and multi.multimesh != null:
			mesh = multi.multimesh.mesh
			summary.multimesh_nodes += 1
		if mesh == null:
			continue
		var state: Dictionary = context(node, root)
		var node_path: String = str(root.get_path_to(node))
		var groups: Dictionary = {}
		var reason: String = plain_mesh_reason(visual) if visual != null else "multimesh"
		var formats: Array[int] = []
		var material_list: Array[String] = []
		for index: int in range(mesh.get_surface_count()):
			var material: Material = visual.get_active_material(index) if visual != null else (multi.material_override if multi.material_override != null else mesh.surface_get_material(index))
			var id: String = material_id(material)
			material_list.append(id)
			summary.material_ids[id] = true
			summary.material_uses[id] = int(summary.material_uses.get(id, 0)) + 1
			summary["visible_surface_submissions" if state.visible else "hidden_surface_submissions"] += 1
			if not state.visible or stage_name != "runtime":
				continue
			var format: int = mesh_format(mesh, index)
			formats.append(format)
			var material_key: String = "default" if id == "default" else str(materials[id].value_signature)
			var key: String = material_key + ":" + str(format)
			if not groups.has(key):
				groups[key] = {"surfaces": [], "material_ids": {}, "material": material_key, "blocked": material_merge_reason(material)}
			groups[key].surfaces.append(index)
			groups[key].material_ids[id] = true
		if stage_name != "runtime" or not state.visible:
			continue
		var row: Dictionary = {"scene": audit_scene_path, "region": current_region, "node": node_path,
			"parent": str(root.get_path_to(node.get_parent())) if node != root else "",
			"surfaces": mesh.get_surface_count(), "materials": material_list,
			"formats": formats, "context": state, "blocked": reason,
			"class": node.get_class(), "mesh_path": mesh.resource_path}
		if visual != null:
			var transform: Transform3D = world_transform(visual, root)
			var bounds: AABB = transform * visual.get_aabb()
			var collider_layers: Array[int] = []
			for collider: Node in visual.find_children("*", "CollisionObject3D", true, false):
				collider_layers.append((collider as CollisionObject3D).collision_layer)
			var surface_blocks: Array[String] = []
			for surface: int in range(mesh.get_surface_count()):
				surface_blocks.append(material_merge_reason(visual.get_active_material(surface)))
			row["world_center"] = vector(bounds.get_center())
			row["world_aabb_position"] = vector(bounds.position)
			row["world_aabb_size"] = vector(bounds.size)
			row["world_transform"] = var_to_str(transform)
			row["draw_state"] = draw_signature(visual)
			row["surface_blocks"] = surface_blocks
			row["collision_layers"] = collider_layers
			row["has_children"] = visual.get_child_count() > 0
		post_rows.append(row)
		if visual == null:
			continue
		for group: Dictionary in groups.values():
			if group.surfaces.size() < 2:
				continue
			var blocked: String = reason if not reason.is_empty() else str(group.blocked)
			if not state.scripts.is_empty():
				blocked = "scripted_ancestor"
			same_mesh.append({"scene": audit_scene_path, "region": current_region, "node": node_path,
				"surfaces": group.surfaces, "material_ids": group.material_ids.keys(),
				"candidate_draw_reduction_per_pass": group.surfaces.size() - 1,
				"blocked": blocked, "visibility_boundary_unchanged": true,
				"transform_and_uv_coordinates_unchanged": true})
		# Conservative sibling opportunities only: no script ancestry, no child
		# nodes (collision/interaction retained separately), one opaque surface.
		if mesh.get_surface_count() != 1 or not reason.is_empty() or not state.scripts.is_empty() or node.get_child_count() > 0 or node == root:
			continue
		var material: Material = visual.get_active_material(0)
		if not material_merge_reason(material).is_empty():
			continue
		var id: String = material_list[0]
		var material_key: String = "default" if id == "default" else str(materials[id].value_signature)
		# A transformed local triplanar mesh would change its texture mapping.
		# Require the complete local transform to match in that case.
		var triplanar: String = var_to_str(visual.transform) if id != "default" and bool(materials[id].get("local_triplanar", false)) else ""
		var sibling_key: String = row.parent + "|" + str(state.camera_group) + "|" + material_key + "|" + str(formats[0]) + "|" + draw_signature(visual) + "|" + triplanar
		if not sibling_groups.has(sibling_key):
			sibling_groups[sibling_key] = {"scene": audit_scene_path, "region": current_region,
				"parent": row.parent, "camera_group": state.camera_group, "nodes": [],
				"bounds": AABB(), "material_ids": {}, "local_triplanar": not triplanar.is_empty()}
		var group: Dictionary = sibling_groups[sibling_key]
		group.nodes.append(node_path)
		group.material_ids[id] = true
		var box: AABB = visual.transform * visual.get_aabb()
		group.bounds = box if group.nodes.size() == 1 else (group.bounds as AABB).merge(box)
	for group: Dictionary in sibling_groups.values():
		if group.nodes.size() < 2:
			continue
		var bounds: AABB = group.bounds
		group.erase("bounds")
		group["parent_space_extent"] = [bounds.size.x, bounds.size.y, bounds.size.z]
		group["material_ids"] = group.material_ids.keys()
		group["candidate_draw_reduction_per_pass"] = group.nodes.size() - 1
		group["status"] = "conditional_same_parent_not_automatically_safe"
		group["remaining_checks"] = [
			"retain named source anchors and per-object camera-fade behavior",
			"preserve permanent collision nodes and interaction metadata",
			"retain geometry transforms normals tangents UVs and material state",
			"bound merged AABB so planet/frustum culling does not regress",
		]
		siblings.append(group)
	var stage: Dictionary = stages[stage_name]
	for key: String in ["mesh_nodes", "multimesh_nodes", "visible_surface_submissions", "hidden_surface_submissions"]:
		stage[key] += summary[key]
	for id: String in summary.material_ids:
		stage.material_ids[id] = true
		stage.material_uses[id] = int(stage.material_uses.get(id, 0)) + int(summary.material_uses[id])
	summary["unique_material_identities"] = summary.material_ids.size()
	summary.erase("material_ids")
	summary.erase("material_uses")
	return summary

func duplicate_groups(stage: Dictionary, signature: String) -> Array[Dictionary]:
	var groups: Dictionary = {}
	for id: String in stage.material_ids:
		if id == "default":
			continue
		var row: Dictionary = materials[id]
		var key: String = str(row[signature])
		if not groups.has(key):
			groups[key] = {"identities": [], "surfaces": 0, "class": row["class"], "name": row.name, "shader": row.shader, "signature": key}
		groups[key].identities.append(id)
		groups[key].surfaces += int(stage.material_uses[id])
	var results: Array[Dictionary] = []
	for group: Dictionary in groups.values():
		if group.identities.size() > 1:
			group["redundant_identities"] = group.identities.size() - 1
			results.append(group)
	results.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.redundant_identities) > int(b.redundant_identities))
	return results

func run() -> void:
	stages = {"serialized": new_stage(), "runtime": new_stage()}
	var files: Array[Dictionary] = []
	for path: String in BASES:
		files.append({"path": path, "region": "base"})
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	for region: Dictionary in catalog.districts:
		for chunk: Dictionary in region.chunks:
			files.append({"path": str(chunk.path), "region": str(region.id)})
	var source_hashes: Dictionary = {}
	for file: Dictionary in files:
		audit_scene_path = str(file.path)
		current_region = str(file.region)
		source_hashes[audit_scene_path] = FileAccess.get_sha256(audit_scene_path)
		var packed: PackedScene = load(audit_scene_path) as PackedScene
		assert(packed != null)
		var scene: Node3D = packed.instantiate() as Node3D
		var before: Dictionary = inspect(scene, "serialized")
		art.call("apply", scene)
		var after: Dictionary = inspect(scene, "runtime")
		scenes.append({"scene": audit_scene_path, "region": current_region, "serialized": before, "runtime": after})
		scene.free()
		if scenes.size() % 12 == 0:
			print("RUNTIME_BATCH_AUDIT_PROGRESS ", scenes.size(), "/", files.size())
	var output_stages: Dictionary = {}
	for key: String in stages:
		var stage: Dictionary = stages[key]
		var exact: Array[Dictionary] = duplicate_groups(stage, "exact_signature")
		var values: Array[Dictionary] = duplicate_groups(stage, "value_signature")
		var redundant: int = 0
		for group: Dictionary in values:
			redundant += int(group.redundant_identities)
		output_stages[key] = {"mesh_nodes": stage.mesh_nodes, "multimesh_nodes": stage.multimesh_nodes,
			"visible_surface_submissions": stage.visible_surface_submissions,
			"hidden_surface_submissions": stage.hidden_surface_submissions,
			"unique_material_identities": stage.material_ids.size(), "redundant_material_identities": redundant,
			"value_unique_materials": stage.material_ids.size() - redundant,
			"exact_resource_duplicates": exact, "equal_external_resource_duplicates": values}
	var safe_reduction: int = 0
	var safe_groups: int = 0
	for group: Dictionary in same_mesh:
		if str(group.blocked).is_empty():
			safe_reduction += int(group.candidate_draw_reduction_per_pass)
			safe_groups += 1
	var source_unchanged: bool = true
	for path: String in source_hashes:
		source_unchanged = source_unchanged and FileAccess.get_sha256(path) == str(source_hashes[path])
	assert(source_unchanged)
	var report: Dictionary = {
		"date": "2026-10-20", "engine": Engine.get_version_info().string, "headless": true,
		"scope": "Actual streaming base scenes plus every catalog chunk; same shared runtime WorldArtDirection.apply replayed on transient instances",
		"limitations": [
			"Asset census is not a GPU draw measurement; all regions and both overview/detail representations are included",
			"One visible mesh surface is one potential base-pass submission; shadow/light/depth passes and engine batching are not inferred",
			"Material identity reuse alone does not reduce the number of geometry surfaces/draws",
			"No animation scripts, gameplay transitions, camera fade or mobile profile mutations executed",
			"Cross-node candidates remain conditional until camera fade, planet culling and interaction anchors are preserved",
		],
		"source_files_unchanged": source_unchanged, "source_sha256": source_hashes,
		"runtime_replace_counts": {"architecture": art.architecture.building_count, "planters": art.street_furniture.planter_count, "stations": art.street_furniture.station_count},
		"stages": output_stages, "scenes": scenes, "materials": materials,
		"same_mesh_candidates": same_mesh, "same_mesh_eligible_groups": safe_groups,
		"same_mesh_max_base_pass_reduction": safe_reduction, "sibling_candidates": siblings,
		"runtime_meshes": post_rows,
	}
	var folder: String = ProjectSettings.globalize_path(OUTPUT).get_base_dir()
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RUNTIME_BATCH_AUDIT_DONE ", JSON.stringify({"scenes": scenes.size(), "material_ids": output_stages.runtime.unique_material_identities,
		"value_materials": output_stages.runtime.value_unique_materials, "same_mesh_eligible": safe_groups,
		"same_mesh_reduction": safe_reduction, "sibling_groups": siblings.size(), "source_files_unchanged": source_unchanged}))
	quit()
