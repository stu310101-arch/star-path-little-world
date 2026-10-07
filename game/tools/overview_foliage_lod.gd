extends RefCounted

# Export-copy only: keep original leaf geometry/colors, but omit redundant small
# disconnected leaf components at overview distance. Never run on terrain,
# buildings, rigs, or the nearby authored MultiMesh. Six extreme components keep
# the source canopy bounds; deterministic spatial ordering avoids random builds.
const KEEP_FRACTION: float = .22
const MIN_COMPONENTS: int = 32
const MAX_COMPONENT_TRIANGLES: int = 32
var cache: Dictionary = {}
var components_before: int = 0
var components_after: int = 0
var meshes_reduced: int = 0

func reduce(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	if not mesh is ArrayMesh or (mesh as ArrayMesh).get_blend_shape_count() > 0:
		return mesh
	for surface: int in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(surface) & Mesh.ARRAY_FORMAT_BONES) != 0:
			return mesh
	var key: int = mesh.get_instance_id()
	if cache.has(key):
		return cache[key] as Mesh
	var result: ArrayMesh = ArrayMesh.new()
	var changed: bool = false
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		if indices.is_empty():
			indices.resize(vertices.size())
			for i: int in range(vertices.size()):
				indices[i] = i
		var selected: PackedInt32Array = _select_components(vertices, indices)
		changed = changed or selected.size() != indices.size()
		arrays[Mesh.ARRAY_INDEX] = selected
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	cache[key] = result if changed else mesh
	if changed:
		meshes_reduced += 1
	return cache[key] as Mesh

func _root(parents: PackedInt32Array, index: int) -> int:
	var current: int = index
	while parents[current] != current:
		current = parents[current]
	return current

func _select_components(vertices: PackedVector3Array, indices: PackedInt32Array) -> PackedInt32Array:
	var parents: PackedInt32Array = PackedInt32Array()
	parents.resize(vertices.size())
	for i: int in range(vertices.size()):
		parents[i] = i
	# Weld coincident normal/UV splits for connectivity only. Render vertices and
	# their shading/UV/color data remain untouched in the selected output.
	var positions: Dictionary = {}
	for i: int in range(vertices.size()):
		var key: Vector3i = Vector3i((vertices[i] * 100000.0).round())
		if positions.has(key):
			parents[i] = _root(parents, int(positions[key]))
		else:
			positions[key] = i
	for offset: int in range(0, indices.size(), 3):
		var a: int = _root(parents, indices[offset])
		for corner: int in range(1, 3):
			var b: int = _root(parents, indices[offset + corner])
			parents[b] = a
	var groups: Dictionary = {}
	for offset: int in range(0, indices.size(), 3):
		var id: int = _root(parents, indices[offset])
		if not groups.has(id):
			groups[id] = {"indices":PackedInt32Array(), "center":Vector3.ZERO, "bounds":AABB(vertices[indices[offset]], Vector3.ZERO)}
		var group: Dictionary = groups[id]
		var group_indices: PackedInt32Array = group.indices as PackedInt32Array
		for corner: int in range(3):
			var index: int = indices[offset + corner]
			group_indices.append(index)
			group.center += vertices[index]
			group.bounds = (group.bounds as AABB).expand(vertices[index])
		group.indices = group_indices
	var leaves: Array[Dictionary] = []
	var kept: Dictionary = {}
	for id: int in groups:
		var group: Dictionary = groups[id]
		group.id = id
		group.center /= float((group.indices as PackedInt32Array).size())
		if (group.indices as PackedInt32Array).size() <= MAX_COMPONENT_TRIANGLES * 3:
			leaves.append(group)
		else:
			kept[id] = true
	if leaves.size() < MIN_COMPONENTS:
		return indices
	# Retain every extremal component, including corners that might define the
	# canopy's silhouette. Interior leaf omissions do not widen source bounds.
	for axis: int in range(3):
		var low: float = INF
		var high: float = -INF
		var low_id: int = -1
		var high_id: int = -1
		for leaf: Dictionary in leaves:
			var box: AABB = leaf.bounds as AABB
			if box.position[axis] < low:
				low = box.position[axis]
				low_id = int(leaf.id)
			if box.end[axis] > high:
				high = box.end[axis]
				high_id = int(leaf.id)
		kept[low_id] = true
		kept[high_id] = true
	# Coordinates are hashed rather than taking contiguous source face runs.
	# This retains samples throughout the entire authored crown.
	for leaf: Dictionary in leaves:
		var point: Vector3 = leaf.center as Vector3
		var bucket: int = absi(hash(Vector3i((point * 4096.0).round()))) % 10000
		if bucket < int(KEEP_FRACTION * 10000.0):
			kept[int(leaf.id)] = true
	var result: PackedInt32Array = PackedInt32Array()
	var leaf_count: int = 0
	for id: int in groups:
		if kept.has(id):
			result.append_array(groups[id].indices as PackedInt32Array)
	for leaf: Dictionary in leaves:
		if kept.has(int(leaf.id)):
			leaf_count += 1
	components_before += leaves.size()
	components_after += leaf_count
	return result

func statistics() -> Dictionary:
	return {"meshes_reduced":meshes_reduced,"leaf_components_before":components_before,"leaf_components_after":components_after,"keep_fraction":KEEP_FRACTION,"original_bounds_preserved":true}
