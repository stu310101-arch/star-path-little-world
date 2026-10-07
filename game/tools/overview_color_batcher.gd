extends RefCounted

# Compatibility multiplies albedo * texture * interpolated vertex color before
# the fragment sRGB-to-linear conversion. Moving a constant opaque albedo into
# the vertex channel therefore commutes with interpolation. Keep sRGB vertex
# conversion paths and transparent/custom materials untouched. ArrayMesh stores
# colors as RGBA8, so the added quantization is bounded by 1/255 per channel.
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var baked_surfaces: int = 0
var baked_vertices: int = 0

func prepare(mesh: Mesh, surface: int, material: Material) -> Dictionary:
	if material == null or material.get_class() != "StandardMaterial3D" or material.resource_local_to_scene or material.next_pass != null or material.get_script() != null:
		return {"mesh":mesh,"surface":surface,"material":material}
	var source: StandardMaterial3D = material as StandardMaterial3D
	if source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or (source.vertex_color_use_as_albedo and source.vertex_color_is_srgb):
		return {"mesh":mesh,"surface":surface,"material":material}
	for component: float in [source.albedo_color.r, source.albedo_color.g, source.albedo_color.b, source.albedo_color.a]:
		if component < 0.0 or component > 1.0:
			return {"mesh":mesh,"surface":surface,"material":material}
	var key: String = "%d:%d:%d" % [mesh.get_instance_id(), surface, material.get_instance_id()]
	if _surfaces.has(key):
		return _surfaces[key] as Dictionary
	var arrays: Array = mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] as PackedColorArray if arrays[Mesh.ARRAY_COLOR] is PackedColorArray else PackedColorArray()
	if not source.vertex_color_use_as_albedo or colors.is_empty():
		colors = PackedColorArray()
		colors.resize(vertices.size())
		colors.fill(source.albedo_color)
	else:
		colors = colors.duplicate()
		for index: int in range(colors.size()):
			colors[index] *= source.albedo_color
	arrays[Mesh.ARRAY_COLOR] = colors
	var result: ArrayMesh = ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material_id: int = material.get_instance_id()
	if not _materials.has(material_id):
		var copy: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
		copy.albedo_color = Color.WHITE
		copy.vertex_color_use_as_albedo = true
		copy.vertex_color_is_srgb = false
		_materials[material_id] = copy
	var row: Dictionary = {"mesh":result,"surface":0,"material":_materials[material_id]}
	_surfaces[key] = row
	baked_surfaces += 1
	baked_vertices += vertices.size()
	return row

func clear_geometry_cache() -> void:
	_surfaces.clear()

func statistics() -> Dictionary:
	return {"baked_surfaces":baked_surfaces,"baked_vertices":baked_vertices,"max_added_color_error":1.0/255.0,"scope":"opaque Compatibility static overview copies"}
