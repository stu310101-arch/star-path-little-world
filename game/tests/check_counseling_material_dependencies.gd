extends SceneTree

const MODEL: String = "res://assets/counseling_room/counseling_room.glb"
const TEXTURES: String = "res://assets/counseling_room/textures/"
const EXPECTED_MAPS: Array[String] = ["oak_base.png","oak_normal.png","oak_rough.png","joinery_base.png","joinery_normal.png","joinery_rough.png","sage_base.png","apricot_base.png","linen_base.png","fabric_normal.png","fabric_rough.png"]
const PBR_KEYS: Array[String] = ["oak","joinery","linen","sage","apricot"]
var failures: Array[String] = []
var output: String = "res://../deliverables/counseling-room/r8/material-dependencies.json"

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--output"):
		output = arguments[arguments.find("--output")+1]
	var dependencies: PackedStringArray = ResourceLoader.get_dependencies(MODEL)
	var paths: Array[String] = []
	for encoded: String in dependencies:
		var path: String = encoded.split("::")[-1]
		paths.append(path)
		check(path.begins_with(TEXTURES), "Unexpected exported model dependency: " + path)
	check(paths.size() == EXPECTED_MAPS.size(), "The complete studio must depend on its 11 canonical texture maps")
	for file_name: String in EXPECTED_MAPS:
		check(paths.has(TEXTURES+file_name), "Missing canonical model dependency: " + file_name)
	var packed: PackedScene = load(MODEL) as PackedScene
	var room: Node = packed.instantiate()
	var seen: Dictionary = {}
	var textures: Array[Dictionary] = []
	var pbr_materials: int = 0
	var pbr_keys_seen: Array[String] = []
	var textured_surfaces: int = 0
	var uv_surfaces: Array[Dictionary] = []
	for node: Node in room.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if material == null:
				continue
			var key: String = material.resource_name.trim_prefix("MAT_Counseling_")
			if key in PBR_KEYS:
				textured_surfaces += 1
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
				var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array
				check(uvs.size()==vertices.size() and tangents.size()==vertices.size()*4, "PBR surface lacks UVs or normal-map tangents: " + str(node.name) + "/" + key)
				var uv_bounds: Rect2 = Rect2(uvs[0],Vector2.ZERO) if not uvs.is_empty() else Rect2()
				for uv: Vector2 in uvs: uv_bounds=uv_bounds.expand(uv)
				# Meter-scaled UVs on 0.9 mm stitching legitimately span less
				# than .01. Reject degenerate axes, not physically small details.
				uv_surfaces.append({"mesh":str(node.name),"material":key,"vertices":vertices.size(),"uv_count":uvs.size(),"tangent_count":tangents.size(),"uv_min":[uv_bounds.position.x,uv_bounds.position.y],"uv_extent":[uv_bounds.size.x,uv_bounds.size.y]})
				check(uv_bounds.size.x>1e-6 and uv_bounds.size.y>1e-6, "PBR surface collapses to one texture coordinate: " + str(node.name) + "/" + key)
			if seen.has(material):
				continue
			seen[material] = true
			if key in PBR_KEYS:
				pbr_materials += 1
				pbr_keys_seen.append(key)
				check(material.albedo_texture != null and material.roughness_texture != null and material.normal_texture != null, "Missing PBR maps: " + key)
				var stem: String = key if key in ["oak","joinery"] else "fabric"
				for pair: Array in [["albedo_texture",key+"_base.png"],["roughness_texture",stem+"_rough.png"],["normal_texture",stem+"_normal.png"]]:
					var texture: Texture2D = material.get(pair[0]) as Texture2D
					check(texture!=null and texture.resource_path==TEXTURES+str(pair[1]), "Wrong canonical PBR assignment: " + key + "/" + str(pair[0]))
				check(material.normal_enabled, "Disabled normal map: " + key)
				check(material.metallic_texture == null, "Obsolete embedded metallic texture: " + key)
				check(material.roughness_texture_channel == BaseMaterial3D.TEXTURE_CHANNEL_RED, "Wrong roughness channel: " + key)
			for property: Dictionary in material.get_property_list():
				var value: Variant = material.get(property.name)
				if value is Texture2D:
					var path: String = (value as Texture2D).resource_path
					textures.append({"material": material.resource_name, "property": property.name, "path": path})
					check(path.begins_with(TEXTURES), "Material still uses an extracted GLB texture: " + path)
					var expected: int = 2048 if path.get_file().begins_with("oak_") or path.get_file().begins_with("joinery_") else 1024
					check((value as Texture2D).get_width()==expected and (value as Texture2D).get_height()==expected, "Incorrect canonical texture dimensions: " + path)
	for key: String in PBR_KEYS: check(key in pbr_keys_seen, "Missing authored PBR material: " + key)
	check(pbr_materials == PBR_KEYS.size() and textures.size() == PBR_KEYS.size()*3, "Expected five shared PBR materials using fifteen map references")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/counseling_room/layout.json"))
	var report: Dictionary = {"revision":layout.revision,"model": MODEL, "dependencies": paths, "pbr_materials": pbr_materials, "texture_references": textures, "textured_surfaces":textured_surfaces,"uv_surfaces":uv_surfaces,"uv_validation":"Both UV axes must exceed 1e-6 and UV/tangent counts must match vertices. The former .01 extent threshold incorrectly rejected meter-scaled UVs on 18 mm handle attachment stitches; no model or texture scale was changed to satisfy the test.","failures": failures,"scope":"Canonical dependency, semantic map assignments, UV/tangent and imported resolution validation. Rendered material quality is reviewed separately; counts do not establish art quality."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t") + "\n")
	file.close()
	print("COUNSELING_MATERIAL_DEPENDENCIES maps=%d references=%d failures=%d" % [paths.size(), textures.size(), failures.size()])
	room.free()
	quit(0 if failures.is_empty() else 1)

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)
