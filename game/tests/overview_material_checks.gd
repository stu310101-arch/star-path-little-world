extends SceneTree

const Normalizer = preload("res://tools/overview_material_normalizer.gd")
var checks: int = 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		push_error(message)

func triangle(material: Material, colors: bool = true, lod: bool = false) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN])
	if colors:
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(1, 0, 0, .2), Color(0, 1, 0, .6), Color(0, 0, 1, .8)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	if lod:
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 2, 1, 0])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {1.0: PackedInt32Array([0, 1, 2])} if lod else {})
	mesh.surface_set_material(0, material)
	return mesh

func run() -> void:
	var normalizer: RefCounted = Normalizer.new()
	var source: StandardMaterial3D = StandardMaterial3D.new()
	source.albedo_color = Color(.3, .5, .7, .8)
	source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	source.cull_mode = BaseMaterial3D.CULL_DISABLED
	source.roughness = .7
	source.metallic = .25
	source.vertex_color_is_srgb = true
	source.emission = Color.RED # Ignored source fields must remain ignored.
	source.emission_energy_multiplier = 3.0
	source.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	source.emission_on_uv2 = true
	source.emission_texture = ImageTexture.create_from_image(Image.create(2, 2, false, Image.FORMAT_RGBA8))
	var source_mesh: ArrayMesh = triangle(source)
	var before: Array = source_mesh.surface_get_arrays(0)
	var visual: MeshInstance3D = MeshInstance3D.new()
	visual.mesh = source_mesh
	normalizer.call("normalize_visual", visual)
	var material: StandardMaterial3D = visual.get_active_material(0) as StandardMaterial3D
	check(visual.mesh != source_mesh and material != source, "Overview owns new mesh and material resources")
	check(material.vertex_color_use_as_albedo and material.emission_enabled, "Target variants share color and emission flags")
	check(material.emission == Color.BLACK and material.emission_energy_multiplier == 0.0 and material.emission_texture == null, "Inactive emission is exactly zero without its ignored source texture")
	check(not source.vertex_color_use_as_albedo and not source.emission_enabled and source.emission_texture != null, "Detailed/authoring material remains untouched")
	var allowed: Array[String] = ["vertex_color_use_as_albedo", "emission_enabled", "emission", "emission_energy_multiplier", "emission_texture", "emission_operator", "emission_on_uv2", "resource_path", "resource_scene_unique_id"]
	for property: Dictionary in source.get_property_list():
		var key: String = str(property.name)
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0 and not key in allowed:
			check(material.get(key) == source.get(key), "Render property preserved: " + key)
	var after: Array = visual.mesh.surface_get_arrays(0)
	for slot: int in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
		check(before[slot] == after[slot], "Overview preserves geometry array " + str(slot))
	check(source_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == before[Mesh.ARRAY_COLOR], "Original ignored colors remain untouched")
	for color: Color in after[Mesh.ARRAY_COLOR]:
		check(color == Color.WHITE, "Ignored vertex RGBA becomes neutral white")
	var tinted: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	tinted.vertex_color_use_as_albedo = true
	tinted.emission_enabled = true
	var tinted_mesh: ArrayMesh = triangle(tinted)
	var colored: MeshInstance3D = MeshInstance3D.new()
	colored.mesh = tinted_mesh
	normalizer.call("normalize_visual", colored)
	var colored_material: StandardMaterial3D = colored.get_active_material(0) as StandardMaterial3D
	check(colored.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == tinted_mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR], "Effective vertex RGBA is retained exactly")
	check(colored_material.emission == tinted.emission and colored_material.emission_energy_multiplier == tinted.emission_energy_multiplier and colored_material.emission_texture == tinted.emission_texture and colored_material.emission_operator == tinted.emission_operator and colored_material.emission_on_uv2 == tinted.emission_on_uv2, "Enabled emission retains color, texture, intensity and mode")
	var plain: MeshInstance3D = MeshInstance3D.new()
	plain.mesh = triangle(source, false)
	normalizer.call("normalize_visual", plain)
	check((plain.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray).size() == 3, "Missing vertex color receives explicit neutral data")
	var lod: MeshInstance3D = MeshInstance3D.new()
	var lod_mesh: ArrayMesh = triangle(source, true, true)
	lod.mesh = lod_mesh
	normalizer.call("normalize_visual", lod)
	check(lod.mesh == lod_mesh, "Authored LOD meshes are excluded rather than losing LOD data")
	var overlay: MeshInstance3D = MeshInstance3D.new()
	overlay.mesh = source_mesh
	overlay.material_overlay = tinted
	normalizer.call("normalize_visual", overlay)
	check(overlay.mesh == source_mesh, "Overlay inputs cannot be changed by color normalization")
	var chained: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	chained.next_pass = tinted
	check(normalizer.call("normalize_material", chained) == chained, "Next-pass input identity is retained")
	var local: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	local.resource_local_to_scene = true
	check(normalizer.call("normalize_material", local) == local, "Local-to-scene materials are excluded")
	var custom: ShaderMaterial = ShaderMaterial.new()
	check(normalizer.call("normalize_material", custom) == custom, "Custom water and other shaders are excluded")
	var multi: MultiMeshInstance3D = MultiMeshInstance3D.new()
	multi.multimesh = MultiMesh.new()
	multi.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multi.multimesh.mesh = source_mesh
	multi.multimesh.instance_count = 1
	normalizer.call("normalize_scene", multi)
	check(multi.multimesh.mesh == source_mesh and multi.multimesh.mesh.surface_get_material(0) == source, "MultiMesh resources remain untouched")
	var packed: PackedScene = PackedScene.new()
	check(packed.pack(visual) == OK, "Normalized visual can be packed")
	var restored: MeshInstance3D = packed.instantiate() as MeshInstance3D
	check((restored.get_active_material(0) as StandardMaterial3D).emission_energy_multiplier == 0.0, "Neutral emission survives scene packing")
	check(restored.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] == after[Mesh.ARRAY_COLOR], "Neutral vertex colors survive scene packing")
	for primitive: PrimitiveMesh in [CylinderMesh.new(), TorusMesh.new(), SphereMesh.new()]:
		var station_visual: MeshInstance3D = MeshInstance3D.new()
		station_visual.mesh = primitive
		station_visual.material_override = source
		var vertices: PackedVector3Array = primitive.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		normalizer.call("normalize_visual", station_visual)
		check(station_visual.mesh != primitive, "Station primitive receives an independent mesh: " + primitive.get_class())
		check(station_visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] == vertices, "Station primitive vertices remain exact: " + primitive.get_class())
		check(station_visual.mesh.get_aabb().is_equal_approx(primitive.get_aabb()) and (station_visual.mesh as ArrayMesh).custom_aabb == primitive.get_aabb(), "Station primitive culling bounds are preserved: " + primitive.get_class())
		check((station_visual.get_active_material(0) as StandardMaterial3D).vertex_color_use_as_albedo, "Station material flags normalized: " + primitive.get_class())
		station_visual.free()
	for node: Node in [visual, colored, plain, lod, overlay, multi, restored]:
		node.free()
	print("OVERVIEW_MATERIAL_CHECKS ", checks - failures.size(), "/", checks, " failures=", failures, " stats=", JSON.stringify(normalizer.call("statistics")))
	quit(0 if failures.is_empty() else 1)
