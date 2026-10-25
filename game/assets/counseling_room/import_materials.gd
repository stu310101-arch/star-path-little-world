@tool
extends EditorScenePostImport
## Canonical 2K oak / 1K fabric maps are shared across every spatial mesh instead of duplicated
## by the GLB importer. Embedded images remain available in the editable export.
const TEXTURES: String = "res://assets/counseling_room/textures/"

func _post_import(scene: Node) -> Object:
	for child: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (child as MeshInstance3D).mesh
		for index: int in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(index) as StandardMaterial3D
			if material == null:
				continue
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			var key: String = material.resource_name.trim_prefix("MAT_Counseling_")
			if key not in ["oak", "joinery", "sage", "apricot", "linen"]:
				continue
			var surface: String = key if key in ["oak", "joinery"] else "fabric"
			material.albedo_texture = load(TEXTURES + key + "_base.png") as Texture2D
			material.roughness_texture = load(TEXTURES + surface + "_rough.png") as Texture2D
			material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
			# glTF also binds the packed roughness image to metallic. These wood
			# and fabric materials are non-metallic; release that redundant map.
			material.metallic_texture = null
			material.normal_enabled = true
			material.normal_texture = load(TEXTURES + surface + "_normal.png") as Texture2D
	return scene
