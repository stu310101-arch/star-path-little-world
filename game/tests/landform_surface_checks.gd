extends SceneTree

## Regression for the visibly jagged grass/rock triangle boundaries. This
## inspects the shipped mesh, or builds only terrain in memory with --source-only.
const Ecology = preload("res://tools/ecology_world.gd")
const Landforms = preload("res://tools/world_landforms.gd")
const Routes = preload("res://scripts/world_routes.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var source_only: bool = OS.get_cmdline_user_args().has("--source-only")
	var globe: Node3D
	if not source_only:
		globe = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	var report: Dictionary = {"source_only":source_only,"districts":[]}
	for index: int in range(districts.size()):
		var data: Dictionary = districts[index]
		var values: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(values[0],values[1],values[2])
		var field: RefCounted = Landforms.new()
		field.call("configure",data,index,float(layout.radius),up)
		var reserve: Node3D
		var temporary: Node3D
		if source_only:
			temporary = Node3D.new()
			var ecology: RefCounted = Ecology.new()
			ecology.set("parent",temporary)
			ecology.set("radius",float(layout.radius))
			ecology.set("batch_district",index)
			ecology.set("landforms",field)
			ecology.set("district_routes",Routes.district_paths(data,float(layout.radius)))
			ecology.call("terrain",up,data,index)
			reserve = temporary.get_child(0) as Node3D
		else:
			reserve = globe.get_node("EcologicalReserves/Reserve_"+str(data.station)) as Node3D
		if reserve.has_node("NaturalRockBankSlopes"):
			failures.append(str(data.station)+": per-triangle material split remains")
		var points: PackedVector3Array=[]
		var normals: PackedVector3Array=[]
		var masks: PackedVector2Array=[]
		var chunk_count: int=0
		var max_chunk_triangles: int=0
		for child: Node in reserve.get_children():
			if not child is MeshInstance3D or not str(child.name).begins_with("ContouredBanksAndGround"): continue
			var ground: MeshInstance3D=child as MeshInstance3D
			chunk_count+=1
			if ground.mesh.get_surface_count()!=1:
				failures.append(str(data.station)+": dry terrain is not one continuous material surface")
			var arrays: Array=ground.mesh.surface_get_arrays(0)
			points.append_array(arrays[Mesh.ARRAY_VERTEX])
			normals.append_array(arrays[Mesh.ARRAY_NORMAL])
			if arrays[Mesh.ARRAY_TEX_UV2] is PackedVector2Array: masks.append_array(arrays[Mesh.ARRAY_TEX_UV2])
			max_chunk_triangles=maxi(max_chunk_triangles,(arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3)
		if max_chunk_triangles>40000: failures.append(str(data.station)+": single terrain chunk exceeds streaming budget")
		if points.size()/3>150000: failures.append(str(data.station)+": biome terrain exceeds triangle budget")
		var shared: Dictionary = {}
		var smooth_soil: int = 0
		var smooth_rock: int = 0
		var mismatches: int = 0
		if masks.size()!=points.size():
			failures.append(str(data.station)+": missing per-vertex blend channels")
		else:
			for vertex: int in range(points.size()):
				var key: Vector3i = Vector3i((points[vertex]*10000.0).round())
				var mask: Vector2 = masks[vertex]
				if shared.has(key):
					var previous: Dictionary = shared[key]
					if mask.distance_to(previous.mask)>.002 or normals[vertex].distance_to(previous.normal)>.002:
						mismatches+=1
				else:
					shared[key]={"mask":mask,"normal":normals[vertex]}
				if mask.x>.05 and mask.x<.95:
					smooth_soil+=1
				if mask.y>.05 and mask.y<.63:
					smooth_rock+=1
			if mismatches>0:
				failures.append(str(data.station)+": mismatched mask/normal at shared ground vertices")
			if smooth_soil<100 or smooth_rock<20:
				failures.append(str(data.station)+": missing broad smooth shoreline transition")
		report.districts.append({"station":data.station,"vertices":points.size(),"chunks":chunk_count,"max_chunk_triangles":max_chunk_triangles,"unique_positions":shared.size(),"soil_transition_vertices":smooth_soil,"rock_transition_vertices":smooth_rock,"seam_mismatches":mismatches})
		print("LANDFORM_SURFACE ",JSON.stringify(report.districts[-1]))
		if temporary!=null:
			temporary.free()
	if globe!=null:
		globe.free()
	report["passed"]=failures.is_empty()
	report["failures"]=failures
	var output: String = ProjectSettings.globalize_path("res://../deliverables/world-redesign/landform-surface-"+("source" if source_only else "baked")+"-checks.json")
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("LANDFORM_SURFACE_CHECKS failures=",failures.size())
	for failure: String in failures:
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
