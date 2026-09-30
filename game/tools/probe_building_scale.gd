extends SceneTree

func bounds(node: Node, acc: Transform3D = Transform3D.IDENTITY) -> AABB:
	var spatial: Node3D = node as Node3D
	var transform: Transform3D = acc * spatial.transform if spatial != null else acc
	var result: AABB = AABB()
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null:
		result = transform * instance.get_aabb()
	for child: Node in node.get_children():
		var sub: AABB = bounds(child, transform)
		if sub.size.length_squared() > .0001:
			result = result.merge(sub) if result.size.length_squared() > .0001 else sub
	return result

func mesh_parts(node: Node, acc: Transform3D = Transform3D.IDENTITY) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var spatial: Node3D = node as Node3D
	var transform: Transform3D = acc * spatial.transform if spatial != null else acc
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null:
		for index: int in range(instance.mesh.get_surface_count()):
			var material: Material = instance.get_active_material(index)
			var arrays: Array = instance.mesh.surface_get_arrays(index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var positions: Array = []
			var colors: Array = []
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var standard: StandardMaterial3D = material as StandardMaterial3D
			var texture_image: Image = standard.albedo_texture.get_image() if standard != null and standard.albedo_texture != null else null
			if texture_image != null and texture_image.is_compressed():
				texture_image.decompress()
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			for vertex_index: int in range(vertices.size()):
				var vertex: Vector3 = vertices[vertex_index]
				var point: Vector3 = transform * vertex
				positions.append([point.x, point.y, point.z])
				var color: Color = standard.albedo_color if standard != null else Color.WHITE
				if texture_image != null and uv.size() > vertex_index:
					color *= texture_image.get_pixel(clampi(roundi(uv[vertex_index].x * (texture_image.get_width() - 1)), 0, texture_image.get_width() - 1), clampi(roundi(uv[vertex_index].y * (texture_image.get_height() - 1)), 0, texture_image.get_height() - 1))
				colors.append([color.r, color.g, color.b])
			result.append({"node": str(instance.name), "material": str(material.resource_name) if material != null else "", "vertices": positions, "colors": colors, "indices": Array(indices)})
	for child: Node in node.get_children():
		result.append_array(mesh_parts(child, transform))
	return result

func _initialize() -> void:
	var output: Array[Dictionary] = []
	for folder: String in ["commercial/Models/GLB format", "suburban/Models/GLB format", "suburban-edited", "modular/Models/GLB format"]:
		var directory: DirAccess = DirAccess.open("res://assets/kenney/" + folder)
		for file_name: String in directory.get_files():
			if folder.begins_with("modular/") and not file_name.begins_with("building-sample-"):
				continue
			if not file_name.ends_with(".glb") or not (file_name.begins_with("building-") or file_name.begins_with("house-")):
				continue
			var resource_path: String = "res://assets/kenney/" + folder + "/" + file_name
			var packed: PackedScene = load(resource_path) as PackedScene
			var model: Node3D = packed.instantiate() as Node3D
			var box: AABB = bounds(model)
			output.append({"asset": folder + "/" + file_name, "size": [box.size.x, box.size.y, box.size.z], "min": [box.position.x, box.position.y, box.position.z], "parts": mesh_parts(model)})
			model.free()
	var file: FileAccess = FileAccess.open("res://../deliverables/building-scale-source-probe.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output))
	print("BUILDING_SCALE_SOURCE_PROBE models=", output.size())
	quit()
