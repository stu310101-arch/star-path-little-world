extends RefCounted

# Offline-only resource interning. A matching source image AND every importer
# parameter must agree before a texture alias can be shared. Geometry, pixels,
# shader features and material parameters are never simplified here.
var _textures: Dictionary = {}
var _texture_inputs: Dictionary = {}
var _materials: Dictionary = {}
var _material_inputs: Dictionary = {}
var _material_keys: Dictionary = {}
var _meshes: Dictionary = {}
var _texture_aliases: Dictionary = {}
var _material_source_count: int = 0
var _material_reuses: int = 0

func canonical_texture(texture: Texture2D) -> Texture2D:
	if texture == null or not texture is CompressedTexture2D or texture.resource_local_to_scene or texture.get_script() != null:
		return texture
	var id: int = texture.get_instance_id()
	if _texture_inputs.has(id):
		return _texture_inputs[id] as Texture2D
	var source: String = texture.resource_path
	if not source.begins_with("res://assets/") or not FileAccess.file_exists(source) or not FileAccess.file_exists(source + ".import"):
		return texture
	var config: ConfigFile = ConfigFile.new()
	if config.load(source + ".import") != OK or not config.has_section("params"):
		return texture
	# Include metadata and type as well as the source and import settings. In
	# particular, normal-map processing and VRAM compression must not be merged
	# just because two source PNG files happen to contain the same bytes.
	var values: PackedStringArray = PackedStringArray([texture.get_class(), FileAccess.get_sha256(source)])
	var remap_keys: PackedStringArray = config.get_section_keys("remap")
	remap_keys.sort()
	for key: String in remap_keys:
		if key != "uid" and key != "path" and not key.begins_with("path."):
			values.append("remap/" + key + "=" + var_to_str(config.get_value("remap", key)))
	var keys: PackedStringArray = config.get_section_keys("params")
	keys.sort()
	for key: String in keys:
		values.append(key + "=" + var_to_str(config.get_value("params", key)))
	for key: StringName in texture.get_meta_list():
		values.append("metadata/" + str(key) + "=" + var_to_str(texture.get_meta(key)))
	var signature: String = str(values)
	var result: Texture2D = _textures.get(signature, texture) as Texture2D
	_textures[signature] = result
	_texture_inputs[id] = result
	if result != texture:
		_texture_aliases[source] = result.resource_path
	return result

func canonical_material(material: Material) -> Material:
	# Shader uniforms can be animated, next_pass chains can be cyclic, and
	# local-to-scene materials explicitly request independent instances. Keep
	# those identities intact rather than broadening this optimization.
	if material == null or material.get_class() != "StandardMaterial3D" or material.resource_local_to_scene or material.next_pass != null or material.get_script() != null:
		return material
	var id: int = material.get_instance_id()
	if _material_inputs.has(id):
		return _material_inputs[id] as Material
	_material_source_count += 1
	var copy: StandardMaterial3D = material.duplicate(false) as StandardMaterial3D
	for property: Dictionary in copy.get_property_list():
		var key: String = str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var value: Variant = copy.get(key)
		if value is Texture2D:
			copy.set(key, canonical_texture(value as Texture2D))
	var signature: String = _signature(copy)
	var result: Material = _materials.get(signature, copy) as Material
	if result != copy:
		_material_reuses += 1
	_materials[signature] = result
	_material_inputs[id] = result
	_material_inputs[result.get_instance_id()] = result
	_material_keys[result.get_instance_id()] = signature
	return result

func material_key(material: Material) -> String:
	if material == null:
		return "default"
	var canonical: Material = canonical_material(material)
	return str(_material_keys.get(canonical.get_instance_id(), "unique_" + str(canonical.get_instance_id())))

func _signature(material: StandardMaterial3D) -> String:
	var values: PackedStringArray = PackedStringArray()
	for property: Dictionary in material.get_property_list():
		var key: String = str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0 or key in ["resource_name", "resource_path", "resource_scene_unique_id"]:
			continue
		var value: Variant = material.get(key)
		# Unrecognized resources retain their exact identity. This includes any
		# resource-valued metadata instead of dropping it from the equality test.
		values.append(key + "=" + (str((value as Resource).get_instance_id()) if value is Resource else var_to_str(value)))
	return str(values)

func canonical_mesh(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var id: int = mesh.get_instance_id()
	if _meshes.has(id):
		return _meshes[id] as Mesh
	var materials: Array[Material] = []
	var changed: bool = false
	for surface: int in range(mesh.get_surface_count()):
		var source: Material = mesh.surface_get_material(surface)
		var replacement: Material = canonical_material(source)
		materials.append(replacement)
		changed = changed or replacement != source
	var result: Mesh = mesh
	if changed:
		# Shallow resource duplication keeps every vertex/normal/UV/LOD and blend
		# shape, and avoids mutating imported or canonical authoring resources.
		result = mesh.duplicate(false) as Mesh
		for surface: int in range(materials.size()):
			result.surface_set_material(surface, materials[surface])
	_meshes[id] = result
	return result

func canonicalize_scene(node: Node) -> void:
	if node is GeometryInstance3D:
		var geometry: GeometryInstance3D = node as GeometryInstance3D
		geometry.material_override = canonical_material(geometry.material_override)
		geometry.material_overlay = canonical_material(geometry.material_overlay)
	if node is MeshInstance3D:
		var visual: MeshInstance3D = node as MeshInstance3D
		visual.mesh = canonical_mesh(visual.mesh)
		for surface: int in range(visual.get_surface_override_material_count()):
			visual.set_surface_override_material(surface, canonical_material(visual.get_surface_override_material(surface)))
	# Keep detail MultiMesh buffers and embedded meshes untouched. Headless
	# RenderingServer buffer readback is not sufficient to clone their instance
	# data safely. Their overview copies are ordinary baked meshes and already
	# receive the same material interning through append_overview().
	for child: Node in node.get_children():
		canonicalize_scene(child)

func clear_geometry_cache() -> void:
	# Keep the tiny material/texture pool, never all district mesh copies.
	_meshes.clear()

func statistics() -> Dictionary:
	return {"standard_material_sources":_material_source_count, "standard_material_unique":_materials.size(), "standard_material_reuses":_material_reuses, "texture_aliases":_texture_aliases.duplicate()}
