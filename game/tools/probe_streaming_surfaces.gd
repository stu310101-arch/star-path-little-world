extends SceneTree

const Builder = preload("res://tools/streaming_world_builder.gd")
var builder: RefCounted
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	builder = Builder.new()
	var paths: Array[String] = ["res://generated/globe.tscn"]
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	for district: Dictionary in layout.stations:
		paths.append("res://generated/districts/" + str(district.id) + ".tscn")
	for path: String in paths:
		var scene: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		probe(scene, Transform3D.IDENTITY, path)
		scene.free()
	var report: Dictionary = {"source":"current workspace canonical scenes, same offline LOD function","ocean_radius":48.0,"samples":"triangle centroid and edge midpoints","surfaces":rows}
	FileAccess.open("res://../deliverables/performance/streaming-surface-probe.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	var failed: int = 0
	for row: Dictionary in rows:
		if int(row.lod_below_ocean) > int(row.original_below_ocean):
			failed += 1
			print("LOD_SURFACE_SUBMERGED ", JSON.stringify(row))
	print("STREAMING_SURFACE_PROBE surfaces=", rows.size(), " new_submerged_surfaces=", failed)
	quit()

func probe(node: Node, parent_transform: Transform3D, path: String) -> void:
	var transform: Transform3D = parent_transform * ((node as Node3D).transform if node is Node3D else Transform3D.IDENTITY)
	if node is MeshInstance3D:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var walkable: bool = false
		for child: Node in node.get_children():
			if child is CollisionObject3D and ((child as CollisionObject3D).collision_layer & 1) != 0:
				walkable = true
		if walkable and mesh_node.mesh != null:
			var original: Dictionary = sample_mesh(mesh_node.mesh, transform)
			var protected_surface: bool = bool(builder.call("preserve_surface_geometry", mesh_node, transform))
			var reduced: Mesh = builder.call("indexed_source_mesh", mesh_node.mesh) as Mesh if protected_surface else builder.call("reduced_mesh", mesh_node.mesh) as Mesh
			var simplified: Dictionary = sample_mesh(reduced, transform)
			rows.append({"path":path,"protected_surface":protected_surface,"same_triangle_count":original.triangles == simplified.triangles,"original_triangles":original.triangles,"lod_triangles":simplified.triangles,"original_min_radius":original.minimum,"lod_min_radius":simplified.minimum,"original_below_ocean":original.below,"lod_below_ocean":simplified.below})
	for child: Node in node.get_children():
		probe(child, transform, path + "/" + str(child.name))

func sample_mesh(mesh: Mesh, transform: Transform3D) -> Dictionary:
	var minimum: float = INF
	var below: int = 0
	var triangles: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = indices.size() if not indices.is_empty() else vertices.size()
		for index: int in range(0, count, 3):
			var a: Vector3 = transform * vertices[indices[index] if not indices.is_empty() else index]
			var b: Vector3 = transform * vertices[indices[index + 1] if not indices.is_empty() else index + 1]
			var c: Vector3 = transform * vertices[indices[index + 2] if not indices.is_empty() else index + 2]
			var min_sample: float = minf(((a + b + c) / 3.0).length(), minf(((a + b) * .5).length(), minf(((b + c) * .5).length(), ((c + a) * .5).length())))
			minimum = minf(minimum, min_sample)
			if min_sample < 47.999:
				below += 1
			triangles += 1
	return {"minimum":minimum,"below":below,"triangles":triangles}
