extends RefCounted
## Offline tool only; invoked after training-runtime generation, never gameplay.

const DIRECTORY: String = "res://generated/training_room/"
const REPORT_DIRECTORY: String = "res://../deliverables/graphics-performance/"
const WORK_DIRECTORY: String = "res://../build/indoor-optimizer/"

static func optimize(write: bool = true) -> Dictionary:
	var boot_path: String = DIRECTORY + "light.scn"
	var boot: Node3D = (ResourceLoader.load(boot_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	assert(boot != null, "Training startup scene missing")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "detail_catalog.json"))
	var records: Array[Dictionary] = []
	var resources: Dictionary = {}
	var surfaces: Array[Dictionary] = []
	for node: Node in boot.find_children("*", "MeshInstance3D", true, false):
		var instance: MeshInstance3D = node as MeshInstance3D
		var key: String = "boot:" + str(boot.get_path_to(node))
		resources[key] = {"mesh": instance.mesh, "instance": instance, "path": "", "transform": _relative_transform(instance, boot)}
	for row: Dictionary in catalog.meshes:
		var instance: MeshInstance3D = boot.get_node(str(row.node)) as MeshInstance3D
		var key: String = "detail:" + str(row.node)
		resources[key] = {"mesh": ResourceLoader.load(str(row.resource), "", ResourceLoader.CACHE_MODE_IGNORE), "instance": null, "path": str(row.resource), "transform": _relative_transform(instance, boot)}
	for key: String in resources:
		var record: Dictionary = resources[key]
		var mesh: ArrayMesh = record.mesh as ArrayMesh
		assert(mesh != null, "Only static ArrayMesh resources are permitted")
		assert(mesh.get_blend_shape_count() == 0, "Animated mesh is out of scope")
		for surface: int in range(mesh.get_surface_count()):
			assert(mesh.surface_get_primitive_type(surface) == Mesh.PRIMITIVE_TRIANGLES)
			var arrays: Array = mesh.surface_get_arrays(surface)
			assert((arrays[Mesh.ARRAY_BONES] == null or (arrays[Mesh.ARRAY_BONES] as PackedInt32Array).is_empty()), "Skinned mesh is out of scope")
			var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if indices.is_empty():
				for i: int in range(points.size()):
					indices.append(i)
			var positions: Array = []
			var world_positions: Array = []
			for point: Vector3 in points:
				positions.append([point.x, point.y, point.z])
				var world: Vector3 = (record.transform as Transform3D) * point
				world_positions.append([world.x, world.y, world.z])
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			var material_key: String = ""
			if material != null:
				material_key = str(material.get_instance_id())
			surfaces.append({"key": key + ":" + str(surface), "node": key.get_slice(":", 1).get_file(), "positions": positions, "indices": Array(indices), "world_positions": world_positions,
				"material_name": material.resource_name if material != null else "", "material_key": material_key,
				"opaque": material != null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED})
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIRECTORY))
	var dump_path: String = ProjectSettings.globalize_path(WORK_DIRECTORY + "runtime-input.json")
	var plan_path: String = ProjectSettings.globalize_path(WORK_DIRECTORY + "runtime-plan.json")
	FileAccess.open(dump_path, FileAccess.WRITE).store_string(JSON.stringify({"surfaces": surfaces}))
	var output: Array = []
	var code: int = OS.execute("python", [ProjectSettings.globalize_path("res://../tools/optimize_indoor_geometry.py"), "--runtime-plan", dump_path, "--plan-output", plan_path], output, true)
	assert(code == 0, "Offline geometry planner failed: " + str(output))
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var plans: Dictionary = {}
	for row: Dictionary in plan.surfaces:
		plans[str(row.key)] = row
	var modified_materials: Dictionary = {}
	var boot_changed: bool = false
	for key: String in resources:
		var record: Dictionary = resources[key]
		var original: ArrayMesh = record.mesh as ArrayMesh
		assert(original.shadow_mesh == null, "Preserve authored shadow meshes; optimizer needs explicit support")
		var changed: bool = false
		var replacement := ArrayMesh.new()
		var rebuilt_surfaces: Array = []
		for surface: int in range(original.get_surface_count()):
			var row: Dictionary = plans[key + ":" + str(surface)]
			var arrays: Array = original.surface_get_arrays(surface)
			var material: StandardMaterial3D = original.surface_get_material(surface) as StandardMaterial3D
			var culled: bool = material != null and str(row.material_key) in plan.safe_material_keys and material.cull_mode != BaseMaterial3D.CULL_BACK
			changed = changed or int(row.before) != int(row.after) or culled
			# Runtime interchange GLBs are imported directly without generated LODs.
			# Fail closed if the generator changes this contract in the future.
			var raw_surfaces: Array = original.get("_surfaces")
			assert(not (raw_surfaces[surface] as Dictionary).has("lods") or (raw_surfaces[surface].lods as Array).is_empty(), "Preserve LOD resources; optimizer needs explicit support")
			# Retain the engine's encoded vertex/attribute buffers exactly. A
			# decode/recompress roundtrip can change quantized normals/tangents.
			var raw: Dictionary = (raw_surfaces[surface] as Dictionary).duplicate()
			var old_indices: PackedByteArray = raw.get("index_data", PackedByteArray())
			var old_count: int = int(raw.get("index_count", 0))
			assert(old_count > 0 and old_indices.size() % old_count == 0)
			var bytes_per_index: int = old_indices.size() / old_count
			assert(bytes_per_index in [2, 4], "Unexpected engine index encoding")
			var encoded := StreamPeerBuffer.new()
			for index: float in row.indices:
				if bytes_per_index == 2:
					encoded.put_u16(int(index))
				else:
					encoded.put_u32(int(index))
			raw["index_data"] = encoded.data_array
			raw["index_count"] = row.indices.size()
			if culled:
				if not modified_materials.has(str(row.material_key)):
					var copy: StandardMaterial3D = material.duplicate() as StandardMaterial3D
					copy.cull_mode = BaseMaterial3D.CULL_BACK
					modified_materials[str(row.material_key)] = copy
				material = modified_materials[str(row.material_key)] as StandardMaterial3D
			raw["material"] = material
			rebuilt_surfaces.append(raw)
			records.append({"key": str(row.key), "before": int(row.before), "after": int(row.after), "removed": row.removed, "backface_culling_enabled": culled, "cull_reason": row.cull_reason})
		replacement.set("_surfaces", rebuilt_surfaces)
		assert(replacement.get_surface_count() == original.get_surface_count())
		for surface: int in range(original.get_surface_count()):
			var before_arrays: Array = original.surface_get_arrays(surface)
			var after_arrays: Array = replacement.surface_get_arrays(surface)
			for attribute: int in range(Mesh.ARRAY_MAX):
				if attribute != Mesh.ARRAY_INDEX:
					assert(var_to_bytes(before_arrays[attribute]) == var_to_bytes(after_arrays[attribute]), "Vertex attribute changed")
		if changed and write:
			if record.instance != null:
				(record.instance as MeshInstance3D).mesh = replacement
				boot_changed = true
			else:
				var path: String = str(record.path)
				record["source_sha256"] = FileAccess.get_sha256(path)
				assert(ResourceSaver.save(replacement, path, ResourceSaver.FLAG_COMPRESS) == OK)
				record["output_sha256"] = FileAccess.get_sha256(path)
	if write and boot_changed:
		var packed := PackedScene.new()
		assert(packed.pack(boot) == OK)
		var before_hash: String = FileAccess.get_sha256(boot_path)
		assert(ResourceSaver.save(packed, boot_path, ResourceSaver.FLAG_COMPRESS) == OK)
		resources["boot-file"] = {"path": boot_path, "source_sha256": before_hash, "output_sha256": FileAccess.get_sha256(boot_path)}
	var files: Array = []
	for record: Dictionary in resources.values():
		if record.has("source_sha256"):
			files.append({"path": record.path, "source_sha256": record.source_sha256, "output_sha256": record.output_sha256})
	var report: Dictionary = {"engine": Engine.get_version_info().string, "written": write, "surfaces": records, "files": files, "collision_or_transforms_modified": false}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(REPORT_DIRECTORY))
	FileAccess.open(REPORT_DIRECTORY + ("training-optimization.json" if write else "training-dry-run.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	boot.free()
	return report

static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != root:
		if parent is Node3D:
			result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return result
