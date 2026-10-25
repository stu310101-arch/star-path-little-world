extends SceneTree

const Civic = preload("res://tools/refine_civic_plazas.gd")
var failures: Array[String] = []
var checks: int = 0

func _initialize() -> void: call_deferred("run")

func record(passed: bool,label: String) -> void:
	checks+=1
	if not passed:
		failures.append(label)
		push_error(label)

func foliage_vertices(mesh: Mesh) -> int:
	var result: int = 0
	for i: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(i)
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		if indices.is_empty():
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for j: int in range(indices.size()): indices[j]=j
		for index: int in indices:
			var c: Color = colors[index]
			if c.g-c.r>.06 and c.r-c.b>.02: result+=1
	return result

func run() -> void:
	# Execute the generator. A --check-only parse cannot catch Variant-to-typed
	# array conversion failures inside conditional expressions at runtime.
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	Civic.planter(st,Transform3D.IDENTITY,Color.WHITE)
	var fresh: Mesh = st.commit()
	record(foliage_vertices(fresh)==1620,"Fresh planter emits all 45 double-sided bending leaves")
	record(fresh.get_aabb().end.y>.86 and fresh.get_aabb().end.y<.88,"Fresh foliage rises visibly above the 0.46 m soil level")
	var expected: Dictionary = {}
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
	for row: Dictionary in report.civic_refinements: expected[str(row.station)] = int(row.planters)*1620
	for id: String in ["counseling","admissions","recommendations","universities","life","wordking"]:
		var scene: Node3D = (load("res://generated/districts/"+id+".tscn") as PackedScene).instantiate() as Node3D
		var visual: MeshInstance3D = scene.get_node_or_null("CivicFurniture") as MeshInstance3D
		var leaves: int = foliage_vertices(visual.mesh) if visual!=null else 0
		record(leaves==int(expected[id]),"Authored civic foliage matches every deliberately placed planter: "+id)
		scene.free()
	if not OS.get_cmdline_user_args().has("--source-only"):
		var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
		for district: Dictionary in catalog.districts:
			if str(district.id) not in ["counseling","admissions","recommendations","universities","life","wordking"]:continue
			var leaves: int = 0
			for chunk: Dictionary in district.chunks:
				var scene: Node3D = (load(str(chunk.path)) as PackedScene).instantiate() as Node3D
				for visual: MeshInstance3D in scene.find_children("*","MeshInstance3D",true,false):
					if str(visual.get_meta("authored_surface",visual.name))=="CivicFurniture":leaves+=foliage_vertices(visual.mesh)
				scene.free()
			record(leaves==int(expected[str(district.id)]),"Shipped civic furniture retains authored foliage: "+str(district.id))
	print("CIVIC_FOLIAGE_CHECKS checks=",checks," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
