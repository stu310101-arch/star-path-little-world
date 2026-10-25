extends RefCounted

# These flags are authored by the facade/furniture replacement tools. They
# identify obsolete source models kept for editing, never gameplay visibility.
# Run only on export copies, after permanent colliders have been extracted.
const SOURCE_FLAGS: Array[StringName] = [
	&"world_architecture_source_preserved",
	&"street_furniture_source_preserved",
]
var removed_nodes: int = 0
var removed_triangles: int = 0

func is_authoring_only(node: Node) -> bool:
	if not node is Node3D or (node as Node3D).visible or node.get_script() != null:
		return false
	for flag: StringName in SOURCE_FLAGS:
		if bool(node.get_meta(flag, false)):
			return true
	return false

func record_removed(node: Node) -> void:
	removed_nodes += 1
	var mesh: Mesh
	var copies: int = 1
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		var multi: MultiMesh = (node as MultiMeshInstance3D).multimesh
		mesh = multi.mesh
		copies = multi.instance_count
	if mesh != null:
		for surface: int in range(mesh.get_surface_count()):
			if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
				continue
			var arrays: Array = mesh.surface_get_arrays(surface)
			var count: int = (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else 0
			if count == 0:
				count = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			removed_triangles += count / 3 * copies
	for child: Node in node.get_children():
		record_removed(child)

func prune_copy(root: Node) -> void:
	for child: Node in root.get_children():
		if is_authoring_only(child):
			record_removed(child)
			root.remove_child(child)
			child.free()
		else:
			prune_copy(child)

func statistics() -> Dictionary:
	return {"removed_nodes": removed_nodes, "removed_instanced_triangles": removed_triangles,
		"scope": "explicitly marked obsolete hidden facade/furniture source copies",
		"editable_sources_preserved": true, "permanent_collision_preserved": true}
