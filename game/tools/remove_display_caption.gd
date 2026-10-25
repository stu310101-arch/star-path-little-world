extends RefCounted
## Caption triangles were batched with warm plaster. These measured bounds isolate
## the Chinese subtitle in both legacy light/detail meshes; English title stays.
static func clean(source: Mesh, mesh_transform: Transform3D) -> ArrayMesh:
	var bounds: AABB = AABB(Vector3(7.393, 2.913, -3.767), Vector3(.23, .099, .686))
	var result: ArrayMesh = ArrayMesh.new()
	var removed: int = 0
	for surface: int in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index: int in range(vertices.size()):
				indices.append(index)
		var kept: PackedInt32Array = PackedInt32Array()
		for index: int in range(0, indices.size(), 3):
			var inside: bool = true
			for corner: int in range(3):
				inside = inside and bounds.has_point(mesh_transform * vertices[indices[index + corner]])
			if inside:
				removed += 1
			else:
				kept.append_array(indices.slice(index, index + 3))
		arrays[Mesh.ARRAY_INDEX] = kept
		if not kept.is_empty():
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			result.surface_set_material(result.get_surface_count() - 1, source.surface_get_material(surface))
	print("DISPLAY_CAPTION_REMOVED triangles=", removed)
	return result
