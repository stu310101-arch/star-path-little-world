extends RefCounted

# Offline-only normalization of static overview/permanent visual copies. The
# renderer keeps its original StandardMaterial3D lighting and pipeline modes.
# Two inactive features become neutral inputs so fewer shader variants are needed.
var _materials: Dictionary = {}
var material_count: int = 0
var mesh_count: int = 0
var whitened_surfaces: int = 0
var skipped_meshes: int = 0

func normalize_material(material: Material) -> Material:
	if material == null or material.get_class() != "StandardMaterial3D" or material.resource_local_to_scene or material.next_pass != null or material.get_script() != null:
		return material
	var id: int = material.get_instance_id()
	if _materials.has(id):
		return _materials[id] as Material
	var source: StandardMaterial3D = material as StandardMaterial3D
	var result: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	result.vertex_color_use_as_albedo = true
	if not source.emission_enabled:
		result.emission_enabled = true
		result.emission = Color.BLACK
		result.emission_energy_multiplier = 0.0
		result.emission_texture = null
		# These inactive source options have no visual effect. Use the same
		# default emission path as the existing glowing station materials.
		result.emission_operator = BaseMaterial3D.EMISSION_OP_ADD
		result.emission_on_uv2 = false
	_materials[id] = result
	material_count += 1
	return result

func normalize_scene(node: Node) -> void:
	# This is not an animation or gameplay-material conversion tool.
	if node.get_script() != null or node is AnimationPlayer or node is AnimationTree:
		return
	if node is MeshInstance3D:
		normalize_visual(node as MeshInstance3D)
	# MultiMesh data is deliberately never rewritten. Baked overview copies of
	# its geometry are ordinary MeshInstance3D nodes and take the path above.
	for child: Node in node.get_children():
		normalize_scene(child)

func normalize_visual(visual: MeshInstance3D) -> void:
	var mesh: Mesh = visual.mesh
	if mesh == null:
		return
	if visual.skin != null or visual.material_overlay != null or mesh.get_script() != null or not _plain_static_mesh(mesh):
		skipped_meshes += 1
		return
	var materials: Array[Material] = []
	var originals: Array[Material] = []
	var changed: bool = false
	for surface: int in range(mesh.get_surface_count()):
		var original: Material = visual.get_active_material(surface)
		var replacement: Material = normalize_material(original)
		originals.append(original)
		materials.append(replacement)
		changed = changed or replacement != original
	if not changed:
		return
	var result: ArrayMesh = ArrayMesh.new()
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if materials[surface] != originals[surface]:
			var original: StandardMaterial3D = originals[surface] as StandardMaterial3D
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
			if not original.vertex_color_use_as_albedo or colors.is_empty():
				# Replace every ignored RGBA value, including alpha. Merely enabling
				# vertex color would tint meshes carrying unused imported colors.
				colors = PackedColorArray()
				colors.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
				colors.fill(Color.WHITE)
				arrays[Mesh.ARRAY_COLOR] = colors
				whitened_surfaces += 1
		var flags: int = (mesh as ArrayMesh).surface_get_format(surface) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES if mesh is ArrayMesh else 0
		var primitive: Mesh.PrimitiveType = (mesh as ArrayMesh).surface_get_primitive_type(surface) if mesh is ArrayMesh else Mesh.PRIMITIVE_TRIANGLES
		result.add_surface_from_arrays(primitive, arrays, [], {}, flags)
		result.surface_set_material(surface, materials[surface])
		if mesh is ArrayMesh:
			result.surface_set_name(surface, (mesh as ArrayMesh).surface_get_name(surface))
	result.custom_aabb = mesh.get_aabb()
	visual.mesh = result
	visual.material_override = null
	for surface: int in range(visual.get_surface_override_material_count()):
		visual.set_surface_override_material(surface, null)
	mesh_count += 1

func _plain_static_mesh(mesh: Mesh) -> bool:
	if mesh is ArrayMesh:
		var array_mesh: ArrayMesh = mesh as ArrayMesh
		if array_mesh.get_blend_shape_count() > 0 or array_mesh.shadow_mesh != null:
			return false
		# ArrayMesh exposes serialized LOD records through this storage property;
		# rebuilding one would otherwise silently discard its authored LODs.
		var surfaces: Array = array_mesh.get("_surfaces") as Array
		for surface: Dictionary in surfaces:
			if surface.has("lods") and not (surface.lods as Array).is_empty():
				return false
	else:
		# Built-in solid primitives have triangle surfaces and no skin/custom
		# channels; unlike ArrayMesh they do not expose surface_get_format().
		return mesh is PrimitiveMesh and not mesh is PointMesh
	var unsupported: int = Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS | Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 | Mesh.ARRAY_FORMAT_CUSTOM3
	for surface: int in range(mesh.get_surface_count()):
		if (mesh.surface_get_format(surface) & unsupported) != 0:
			return false
	return true

func statistics() -> Dictionary:
	return {"normalized_materials":material_count, "normalized_meshes":mesh_count, "neutral_color_surfaces":whitened_surfaces, "skipped_complex_meshes":skipped_meshes}
