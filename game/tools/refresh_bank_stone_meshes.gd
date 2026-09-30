extends SceneTree

# Replace only embedded copies of this one art asset. Keep authored transforms,
# all vegetation, terrain, water, structures and collision resources unchanged.
const OUTPUT: String = "res://../deliverables/lake-bank-revision/asset-checks.json"

func _initialize() -> void:
	call_deferred("run")

func is_bank_stone(node: Node) -> bool:
	return node is MultiMeshInstance3D and (str(node.get_meta("ecology_kind", "")) == "bank_stones" or str(node.get_meta("aquatic_kind", "")) == "bank_stones")

func fingerprint(node: Node, prefix: String = "") -> Array:
	var path: String = prefix + "/" + str(node.name)
	var result: Array = [[path, node.get_class()]]
	if node is Node3D:
		result.append(str((node as Node3D).transform))
	if node is GeometryInstance3D:
		result.append((node as GeometryInstance3D).cast_shadow)
	if node is MeshInstance3D:
		result.append(hash((node as MeshInstance3D).mesh.get_faces()))
	if node is MultiMeshInstance3D:
		var instance: MultiMeshInstance3D = node as MultiMeshInstance3D
		result.append(hash(instance.get_meta("placements", [])))
		if not is_bank_stone(node):
			result.append(hash(instance.multimesh.mesh.get_faces()))
	if node is CollisionObject3D:
		result.append([(node as CollisionObject3D).collision_layer, (node as CollisionObject3D).collision_mask])
	if node is CollisionShape3D:
		var shape: Shape3D = (node as CollisionShape3D).shape
		result.append([shape.get_class(), hash(shape.get_debug_mesh().get_faces())])
	for child: Node in node.get_children():
		result.append_array(fingerprint(child, path))
	return result

func run() -> void:
	var scene_path: String = "res://generated/globe.tscn"
	var globe: Node3D = (load(scene_path) as PackedScene).instantiate() as Node3D
	var before: Array = fingerprint(globe)
	var asset: Node3D = (load("res://assets/ecology/bank_stones.glb") as PackedScene).instantiate() as Node3D
	var source: MeshInstance3D = asset.find_child("GEO*", true, false) as MeshInstance3D
	assert(source != null and source.transform.is_equal_approx(Transform3D.IDENTITY))
	var mesh: Mesh = source.mesh.duplicate() as Mesh
	for index: int in range(mesh.get_surface_count()):
		var mat: StandardMaterial3D = source.get_active_material(index).duplicate() as StandardMaterial3D
		mat.vertex_color_use_as_albedo = true
		mat.albedo_color = Color.WHITE
		mat.cull_mode = BaseMaterial3D.CULL_BACK
		mat.roughness = .93
		mesh.surface_set_material(index, mat)
	var replaced: Array[String] = []
	var placements: int = 0
	var radial_bounds: Array[Dictionary] = []
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var radius: float = float(layout.radius)
	var stone_vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for node: Node in globe.find_children("*", "MultiMeshInstance3D", true, false):
		if is_bank_stone(node):
			var instance: MultiMeshInstance3D = node as MultiMeshInstance3D
			# Like the world builder, persist placements as metadata. The native
			# ecology_instances script uploads them into a fresh renderer buffer.
			instance.multimesh = MultiMesh.new()
			instance.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			instance.multimesh.mesh = mesh
			replaced.append(str(globe.get_path_to(instance)))
			placements += (instance.get_meta("placements") as Array).size()
			for placement: Transform3D in instance.get_meta("placements"):
				var minimum: float = INF
				var maximum: float = -INF
				for vertex: Vector3 in stone_vertices:
					var elevation: float = (placement * vertex).length() - radius
					minimum = minf(minimum, elevation)
					maximum = maxf(maximum, elevation)
				assert(minimum < .02 and maximum > .1 and maximum < .65, "Stone floated above its bank or exceeded human-scale height")
				radial_bounds.append({"buried_base":minimum,"top":maximum})
	assert(replaced.size() == 12)
	assert(before == fingerprint(globe), "Unrelated geometry, transforms, placement or collision changed")
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(globe) == OK)
	assert(ResourceSaver.save(packed, scene_path) == OK)
	var verified: Node3D = (ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate() as Node3D
	assert(before == fingerprint(verified), "Saved world does not preserve collision or unaffected geometry")
	var report: Dictionary = {"passed":true,"replaced_batches":replaced,"preserved_placements":placements,"unaffected_geometry_and_collisions_identical":true,"all_stones_grounded":true,"placement_elevations":radial_bounds,"stone_bounds":str(mesh.get_aabb()),"stone_triangles":int(mesh.get_faces().size()/3.0)}
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("BANK_STONE_MESH_PATCH_OK ", JSON.stringify(report))
	verified.free()
	asset.free()
	globe.free()
	quit()
