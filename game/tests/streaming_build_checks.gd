extends SceneTree

var checks: int = 0
var dependencies: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func inspect_dependencies(path: String) -> void:
	if dependencies.has(path):
		return
	dependencies[path] = true
	for dependency: String in ResourceLoader.get_dependencies(path):
		var parts: PackedStringArray = dependency.split("::")
		var resolved: String = parts[-1]
		check(not resolved in ["res://generated/globe.tscn", "res://generated/neighborhood.tscn"] and not resolved.begins_with("res://generated/districts/"), "Eager canonical scene dependency: " + resolved)
		check(not resolved.ends_with(".glb"), "Full imported scene dependency: " + resolved)
		if resolved.begins_with("res://") and ResourceLoader.exists(resolved):
			inspect_dependencies(resolved)

func run() -> void:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	check(int(catalog.build.max_chunk_nodes) <= 80, "A chunk exceeded its node budget")
	check(int(catalog.build.max_chunk_mesh_triangles) <= 45000, "A chunk exceeded its geometry budget")
	check(int(catalog.build.max_chunk_bytes) <= 2 * 1024 * 1024, "A compressed binary chunk exceeded 2 MiB")
	check(int(catalog.build.overview_triangles) < int(catalog.build.overview_input_triangles), "Overview geometry was not reduced")
	check(int(catalog.build.overview_vertices) <= int(catalog.build.overview_triangles) * 3, "Overview retained unreferenced high-detail vertices")
	check(int(catalog.build.protected_surface_meshes) >= 194, "Walkable terrain and shore surfaces must retain their curved source geometry")
	var district_count: int = 0
	var chunk_count: int = 0
	for row: Dictionary in catalog.districts:
		if str(row.id) != "sakura" and not str(row.id).begins_with("ocean_"):
			district_count += 1
		for chunk: Dictionary in row.chunks:
			chunk_count += 1
			var path: String = str(chunk.path)
			check(FileAccess.file_exists(path), "Missing generated chunk: " + path)
			check(FileAccess.get_file_as_bytes(path).size() == int(chunk.bytes), "Chunk size does not match catalog: " + path)
			inspect_dependencies(path)
	check(district_count == 6, "All six districts must be preserved")
	check(chunk_count == int(catalog.build.chunk_count), "Chunk count does not match catalog")
	var baked_triangles: int = 0
	for base: String in ["globe_base.scn", "neighborhood_base.scn"]:
		var path: String = "res://generated/streaming/" + base
		inspect_dependencies(path)
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		for node: Node in scene.find_children("*", "", true, false):
			check(not node.has_meta("streaming_district"), "Base instantiated a detail chunk")
			check(node.get_script() == null, "Overview has a running script: " + str(node.name))
			if node is MeshInstance3D and node.get_parent().has_meta("streaming_overview_id"):
				var mesh: Mesh = (node as MeshInstance3D).mesh
				for surface: int in range(mesh.get_surface_count()):
					var arrays: Array = mesh.surface_get_arrays(surface)
					var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
					baked_triangles += int((indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0)
		scene.free()
	check(baked_triangles == int(catalog.build.overview_triangles), "Baking retained every selected source triangle, including originally unindexed island ground")
	print("STREAMING_BUILD_CHECKS_OK checks=", checks, " chunks=", chunk_count, " dependencies=", dependencies.size())
	quit()
