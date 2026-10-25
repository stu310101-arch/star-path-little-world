@tool
extends EditorScenePostImport
## Preserve the old palette where present; the library revision uses real PBR
## maps. Rebind its maps to canonical PNG resources so thirteen GLBs do not keep
## thirteen separate copies of shared wood/stone/leather textures in memory.

func _post_import(scene: Node) -> Object:
	_apply_palette(scene)
	return scene

func _apply_palette(node: Node) -> void:
	if node is MeshInstance3D:
		var instance: MeshInstance3D = node as MeshInstance3D
		if String(instance.name).ends_with("_Floor"):
			# Only the two-triangle floor is exempt from automatic LOD. Copying
			# with an empty LOD dictionary preserves all architecture LODs.
			var flat_floor: ArrayMesh = ArrayMesh.new()
			for floor_index: int in range(instance.mesh.get_surface_count()):
				flat_floor.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, instance.mesh.surface_get_arrays(floor_index), [], {})
				flat_floor.surface_set_material(floor_index, instance.mesh.surface_get_material(floor_index))
			instance.mesh = flat_floor
		for index: int in range(instance.mesh.get_surface_count()):
			var material: StandardMaterial3D = instance.mesh.surface_get_material(index) as StandardMaterial3D
			if material != null:
				var arrays: Array = instance.mesh.surface_get_arrays(index)
				var colors: Variant = arrays[Mesh.ARRAY_COLOR]
				if colors is PackedColorArray and not (colors as PackedColorArray).is_empty():
					material.vertex_color_use_as_albedo = true
					material.vertex_color_is_srgb = false
				var family: String = material.resource_name.trim_prefix("MAT_University_Library_")
				if material.resource_name.begins_with("MAT_University_Library_"):
					material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
					_share_texture(material, family, "base", "albedo_texture")
					_share_texture(material, family, "normal", "normal_texture")
					_share_texture(material, family, "rough", "roughness_texture")
	for child: Node in node.get_children():
		_apply_palette(child)

func _share_texture(material: StandardMaterial3D, family: String, suffix: String, property: String) -> void:
	var path: String = "res://assets/university_hall/textures/%s_%s.png" % [family, suffix]
	if not FileAccess.file_exists(path + ".import"):
		return
	var texture: Texture2D = load(path) as Texture2D
	if texture != null:
		material.set(property, texture)
		if suffix == "rough":
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			# GLTF combines dielectric roughness and metal in one image. The
			# canonical roughness raster is grey; retain metallic scalar zero.
			material.metallic_texture = null
