@tool
extends EditorScenePostImport
## Bind both profiles to canonical textures; embedded GLB extraction is not a runtime dependency.
func _post_import(scene: Node) -> Object:
	var textures: String = "res://generated/low/recommendation/textures/" if get_source_file().contains("/generated/low/") else "res://assets/recommendation_room/textures/"
	for node: Node in scene.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var key: String = material.resource_name.trim_prefix("MAT_Recommendation_").split(".")[0]
			if key == "walnut":
				material.albedo_texture=load(textures+"joinery_base.png") as Texture2D
			elif key == "floor":
				material.albedo_texture=load(textures+"oak_base.png") as Texture2D
	return scene
