extends SceneTree

const Pool = preload("res://tools/streaming_material_pool.gd")
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func _initialize() -> void:
	call_deferred("run")

func triangle(material: Material) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.RED, Color.GREEN, Color.BLUE])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	return mesh

func run() -> void:
	var pool: RefCounted = Pool.new()
	var original: StandardMaterial3D = StandardMaterial3D.new()
	original.albedo_color = Color(.4, .6, .8, 1.0)
	original.roughness = .63
	original.vertex_color_use_as_albedo = true
	original.resource_name = "Original authoring material"
	var equal: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	equal.resource_name = "Another descriptive name"
	var canonical: Material = pool.call("canonical_material", original) as Material
	check(canonical != original, "Build interning does not mutate the source material")
	check(pool.call("canonical_material", equal) == canonical, "Equal render properties share one output material")
	check(original.resource_name == "Original authoring material", "Authoring material name remains untouched")
	for property: String in ["roughness", "transparency", "vertex_color_use_as_albedo", "texture_filter", "cull_mode", "emission_enabled"]:
		var changed: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
		match property:
			"roughness": changed.roughness = .15
			"transparency": changed.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			"vertex_color_use_as_albedo": changed.vertex_color_use_as_albedo = false
			"texture_filter": changed.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			"cull_mode": changed.cull_mode = BaseMaterial3D.CULL_DISABLED
			"emission_enabled": changed.emission_enabled = true
		check(pool.call("canonical_material", changed) != canonical, "Different " + property + " stays separate")
	var local: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	local.resource_local_to_scene = true
	check(pool.call("canonical_material", local) == local, "Local-to-scene material identity is preserved")
	var chained: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	chained.next_pass = equal
	check(pool.call("canonical_material", chained) == chained, "Next-pass chain identity is preserved")
	var tagged: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	tagged.set_meta("gameplay_marker", "different")
	check(pool.call("canonical_material", tagged) != canonical, "Resource metadata is not discarded")
	var shader_material: ShaderMaterial = ShaderMaterial.new()
	shader_material.shader = Shader.new()
	shader_material.shader.code = "shader_type spatial; void fragment() { ALBEDO = vec3(0.5); }"
	check(pool.call("canonical_material", shader_material) == shader_material, "Custom shader identities are preserved")
	var texture_a: Texture2D = load("res://assets/scenery/sakura_0_sakura-atlas.png") as Texture2D
	var texture_b: Texture2D = load("res://assets/scenery/sakura_1_sakura-atlas.png") as Texture2D
	var texture_other: Texture2D = load("res://assets/scenery/fishing_boat_colormap.png") as Texture2D
	check(texture_a != texture_b, "Fixture starts with separate imported texture aliases")
	check(pool.call("canonical_texture", texture_a) == pool.call("canonical_texture", texture_b), "Byte-identical atlas with equal import settings shares one texture")
	check(pool.call("canonical_texture", texture_other) != pool.call("canonical_texture", texture_a), "Different image data stays separate")
	var image: Image = Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var mutable_texture_a: ImageTexture = ImageTexture.create_from_image(image)
	var mutable_texture_b: ImageTexture = ImageTexture.create_from_image(image)
	check(pool.call("canonical_texture", mutable_texture_a) != pool.call("canonical_texture", mutable_texture_b), "Mutable image textures are not deduplicated")
	var textured_a: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	var textured_b: StandardMaterial3D = original.duplicate(false) as StandardMaterial3D
	textured_a.albedo_texture = texture_a
	textured_b.albedo_texture = texture_b
	check(pool.call("canonical_material", textured_a) == pool.call("canonical_material", textured_b), "Identical texture aliases no longer split overview material batches")
	check(textured_b.albedo_texture == texture_b, "Source material still references its original texture")
	var source_mesh: ArrayMesh = triangle(textured_b)
	var before: Array = source_mesh.surface_get_arrays(0)
	var scene: Node3D = Node3D.new()
	var single: MeshInstance3D = MeshInstance3D.new()
	single.name = "Single"
	single.mesh = source_mesh
	scene.add_child(single)
	single.owner = scene
	var source_multi: MultiMesh = MultiMesh.new()
	source_multi.transform_format = MultiMesh.TRANSFORM_3D
	source_multi.use_colors = true
	source_multi.use_custom_data = true
	source_multi.instance_count = 2
	source_multi.visible_instance_count = 1
	source_multi.mesh = source_mesh
	source_multi.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(1, 2, 3)))
	source_multi.set_instance_color(0, Color(.2, .4, .6, .8))
	source_multi.set_instance_custom_data(0, Color(.1, .3, .5, .7))
	var multi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multi.name = "Multi"
	multi.multimesh = source_multi
	scene.add_child(multi)
	multi.owner = scene
	pool.call("canonicalize_scene", scene)
	check(single.mesh != source_mesh and source_mesh.surface_get_material(0) == textured_b, "Mesh duplication preserves the authoring mesh/material")
	var after: Array = single.mesh.surface_get_arrays(0)
	for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_COLOR, Mesh.ARRAY_INDEX]:
		check(before[slot] == after[slot], "Canonicalization preserves geometry array " + str(slot))
	check(multi.multimesh == source_multi and source_multi.mesh == source_mesh, "Detail MultiMesh buffer and embedded mesh remain untouched")
	check(multi.multimesh.mesh.surface_get_material(0) == textured_b, "Detail MultiMesh embedded material remains untouched")
	check(multi.multimesh.visible_instance_count == 1, "MultiMesh visible prefix is preserved")
	check(multi.multimesh.get_instance_transform(0) == source_multi.get_instance_transform(0), "MultiMesh transform is preserved")
	check(multi.multimesh.get_instance_color(0) == source_multi.get_instance_color(0), "MultiMesh color is preserved")
	check(multi.multimesh.get_instance_custom_data(0) == source_multi.get_instance_custom_data(0), "MultiMesh custom data is preserved")
	var packed: PackedScene = PackedScene.new()
	check(packed.pack(scene) == OK, "Canonical output can be packed")
	var path: String = "user://streaming_material_fixture.scn"
	check(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK, "Canonical output can be saved")
	var reloaded: PackedScene = ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored: Node3D = reloaded.instantiate() as Node3D
	var restored_single: MeshInstance3D = restored.get_node("Single") as MeshInstance3D
	var restored_multi: MultiMeshInstance3D = restored.get_node("Multi") as MultiMeshInstance3D
	check(restored_multi.multimesh.instance_count == source_multi.instance_count, "Detail MultiMesh instance count survives serialization")
	check(restored_single.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == before[Mesh.ARRAY_VERTEX], "Serialized geometry retains the same vertices")
	var restored_material: StandardMaterial3D = restored_single.mesh.surface_get_material(0) as StandardMaterial3D
	check(restored_material.albedo_texture.resource_path == texture_a.resource_path, "Canonical material texture survives serialization")
	restored.free()
	scene.free()
	DirAccess.remove_absolute(path)
	pool.call("clear_geometry_cache")
	print("STREAMING_MATERIAL_CHECKS_OK checks=", checks, " stats=", JSON.stringify(pool.call("statistics")))
	quit()
