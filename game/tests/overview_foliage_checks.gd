extends SceneTree

const Reducer = preload("res://tools/overview_foliage_lod.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func referenced_bounds(mesh: Mesh) -> AABB:
	var first: bool = true
	var result: AABB = AABB()
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		for index: int in indices:
			result = AABB(vertices[index], Vector3.ZERO) if first else result.expand(vertices[index])
			first = false
	return result

func run() -> void:
	var tool: SurfaceTool = SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(160):
		var center: Vector3 = Vector3(sin(index * 2.399), float(index) / 30.0, cos(index * 2.399))
		var triangle: Array[Vector3] = [center + Vector3(-.04, 0, -.04), center + Vector3(.04, 0, -.04), center + Vector3(.04, 0, .04), center + Vector3(-.04, 0, .04)]
		for corner: int in [0,1,2,0,2,3]:
			tool.set_color(Color(.2 + index * .003, .5, .15))
			tool.set_normal(Vector3.UP)
			tool.add_vertex(triangle[corner])
	tool.index()
	var source: Mesh = tool.commit()
	var before: Array = source.surface_get_arrays(0)
	var reducer: RefCounted = Reducer.new()
	var output: Mesh = reducer.call("reduce", source) as Mesh
	var after: Array = output.surface_get_arrays(0)
	check(output != source, "Many tiny disconnected leaves should get a far-only copy")
	check((after[Mesh.ARRAY_INDEX] as PackedInt32Array).size() < floori((before[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 2.0), "Far canopy triangle count is substantially reduced")
	check(referenced_bounds(source).is_equal_approx(referenced_bounds(output)), "Six source canopy extrema must survive referenced geometry compaction")
	check(before == source.surface_get_arrays(0), "Source geometry, colors and indices must remain untouched")
	check(after[Mesh.ARRAY_VERTEX] == before[Mesh.ARRAY_VERTEX] and after[Mesh.ARRAY_COLOR] == before[Mesh.ARRAY_COLOR], "Selected leaves retain authored positions and colors")
	check(reducer.call("reduce", source) == output, "Repeated instances reuse one reduced mesh")
	var second: Mesh = Reducer.new().call("reduce", source) as Mesh
	check(second.surface_get_arrays(0)[Mesh.ARRAY_INDEX] == after[Mesh.ARRAY_INDEX], "Separate builds select identical leaves")
	var box: Mesh = BoxMesh.new()
	check(reducer.call("reduce", box) == box, "Connected solid geometry is never leaf-decimated")
	for kind: String in ["alder", "birch", "willow", "pine"]:
		var model: Node = (load("res://assets/ecology/" + kind + ".glb") as PackedScene).instantiate()
		for visual: Node in model.find_children("*", "MeshInstance3D", true, false):
			var original: Mesh = (visual as MeshInstance3D).mesh
			var lod: Mesh = reducer.call("reduce", original) as Mesh
			check(referenced_bounds(original).is_equal_approx(referenced_bounds(lod)), kind + " referenced canopy bounds remain identical")
		model.free()
	print("OVERVIEW_FOLIAGE_CHECKS checks=",checks," failures=",failures," stats=",JSON.stringify(reducer.call("statistics")))
	quit(0 if failures == 0 else 1)
