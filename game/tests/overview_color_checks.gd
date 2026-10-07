extends SceneTree

const Batcher = preload("res://tools/overview_color_batcher.gd")
const Normalizer = preload("res://tools/overview_material_normalizer.gd")
const MaterialPool = preload("res://tools/streaming_material_pool.gd")
var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func run() -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for point: Vector3 in [Vector3.ZERO, Vector3.RIGHT, Vector3.UP]:
		tool.set_color(Color(.2 + point.x * .6,.6 + point.y * .3,.4,.7))
		tool.set_normal(Vector3.FORWARD)
		tool.add_vertex(point)
	tool.index()
	var mesh: Mesh = tool.commit()
	var source_arrays: Array = mesh.surface_get_arrays(0)
	var source_colors: PackedColorArray = source_arrays[Mesh.ARRAY_COLOR] as PackedColorArray
	var source: StandardMaterial3D = StandardMaterial3D.new()
	source.albedo_color = Color(.37,.72,.89,.55)
	source.vertex_color_use_as_albedo = true
	source.vertex_color_is_srgb = false
	source.roughness = .61
	var batcher: RefCounted = Batcher.new()
	var first: Dictionary = batcher.call("prepare", mesh, 0, source)
	var baked: Mesh = first.mesh as Mesh
	var colors: PackedColorArray = baked.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	for index: int in range(colors.size()):
		var expected: Color = source_colors[index] * source.albedo_color
		for channel: int in range(4):
			check(absf(colors[index][channel] - expected[channel]) <= 1.0/255.0 + .000001, "Baked RGBA differs by at most one RGBA8 step")
	check((first.material as StandardMaterial3D).roughness == source.roughness, "PBR properties remain unchanged")
	check((first.material as StandardMaterial3D).albedo_color == Color.WHITE, "Albedo now comes from the vertex channel")
	check(mesh.surface_get_arrays(0) == source_arrays and source.albedo_color == Color(.37,.72,.89,.55), "Source mesh and material are untouched")
	var other: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	other.albedo_color = Color(.8,.2,.3,1)
	var second: Dictionary = batcher.call("prepare", mesh, 0, other)
	var normalizer: RefCounted = Normalizer.new()
	var pool: RefCounted = MaterialPool.new()
	var a: Material = normalizer.call("normalize_material", first.material) as Material
	var b: Material = normalizer.call("normalize_material", second.material) as Material
	check(pool.call("material_key", a) == pool.call("material_key", b), "Otherwise identical colored materials can share an overview batch")
	other.roughness = .2
	var different: Dictionary = Batcher.new().call("prepare", mesh, 0, other)
	check(pool.call("material_key", a) != pool.call("material_key", normalizer.call("normalize_material", different.material)), "Different PBR state does not merge")
	var ignored: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	ignored.vertex_color_use_as_albedo = false
	var flat: Dictionary = batcher.call("prepare", mesh, 0, ignored)
	var flat_colors: PackedColorArray = (flat.mesh as Mesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
	check(flat_colors[0] == flat_colors[1] and flat_colors[1] == flat_colors[2], "Originally ignored vertex colors remain ignored")
	var srgb: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	srgb.vertex_color_is_srgb = true
	check((batcher.call("prepare", mesh, 0, srgb) as Dictionary).mesh == mesh, "sRGB vertex conversion paths are conservatively excluded")
	var transparent: StandardMaterial3D = source.duplicate(false) as StandardMaterial3D
	transparent.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	check((batcher.call("prepare", mesh, 0, transparent) as Dictionary).mesh == mesh, "Transparent materials retain their original alpha path")
	print("OVERVIEW_COLOR_CHECKS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
