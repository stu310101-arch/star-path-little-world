extends SceneTree

const Architecture = preload("res://scripts/world_architecture.gd")
var failures: int = 0
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, valid: bool, evidence: Variant = null) -> void:
	rows.append({"test":label,"passed":valid,"evidence":evidence})
	if not valid:
		failures += 1
		push_error(label+": "+str(evidence))

func run() -> void:
	var kit: RefCounted = Architecture.new()
	var total: int = 0
	var district_palettes: Dictionary = {}
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for district: Dictionary in districts:
		var id: String = str(district.station)
		var scene: Node3D = (load("res://generated/districts/"+id+".tscn") as PackedScene).instantiate() as Node3D
		root.add_child(scene)
		var originals: Dictionary = {}
		for body: Node in scene.find_children("*","CollisionShape3D",true,false):
			originals[body.get_instance_id()] = {"shape":body.shape,"transform":body.global_transform}
		kit.call("apply",scene)
		var count: int = scene.find_children("ArchitecturalEnvelope","MeshInstance3D",true,false).size()
		total += count
		check("Every authored building has new architecture: "+id,count == district.urban_buildings.size(),count)
		check("Replacement is idempotent: "+id,int(kit.call("apply",scene)) == 0)
		var collision_unchanged: bool = scene.find_children("*","CollisionShape3D",true,false).size() == originals.size()
		for body: Node in scene.find_children("*","CollisionShape3D",true,false):
			var expected: Dictionary = originals.get(body.get_instance_id(),{})
			collision_unchanged = collision_unchanged and not expected.is_empty() and expected.shape == body.shape and (expected.transform as Transform3D).is_equal_approx(body.global_transform)
		check("Existing collision and navigation remain exact: "+id,collision_unchanged)
		var shell_valid: bool = true
		var roofs_visible: bool = true
		var triangle_count: int = 0
		for child: Node in scene.find_children("ArchitecturalEnvelope","MeshInstance3D",true,false):
			var mesh: Mesh = child.mesh as Mesh
			if not district_palettes.has(id):
				district_palettes[id] = (mesh.surface_get_material(0) as StandardMaterial3D).albedo_color.to_html()
			var expected: Vector3 = child.get_meta("world_architecture_envelope") as Vector3
			# The wall envelope excludes projecting shutters and sun shades.
			# Test those against the actual authored foundation footprint.
			var parcel: Vector3 = ((child.get_parent().get_node("Foundation") as MeshInstance3D).mesh as BoxMesh).size
			var bounds: AABB = mesh.get_aabb()
			triangle_count += mesh.get_faces().size()/3
			if str(child.get_meta("architecture_family")) == "slate_roof_residence":
				var faces: PackedVector3Array = mesh.get_faces()
				var slopes: int = 0
				for vertex: int in range(0,faces.size(),3):
					var a: Vector3 = faces[vertex]
					var b: Vector3 = faces[vertex+1]
					var c: Vector3 = faces[vertex+2]
					if maxf(a.y,maxf(b.y,c.y)) > expected.y-.04 and minf(a.y,minf(b.y,c.y)) < expected.y-.3 and (b-a).cross(c-a).length() > .02:
						slopes += 1
				roofs_visible = roofs_visible and slopes >= 6
			shell_valid = shell_valid and mesh.get_surface_count() == 5 and bounds.position.y >= -.01 and bounds.end.y <= expected.y+.01 and bounds.position.x >= -parcel.x*.5 and bounds.end.x <= parcel.x*.5 and bounds.position.z >= -parcel.z*.5 and bounds.end.z <= parcel.z*.5
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				shell_valid = shell_valid and tangents.size() == vertices.size()*4
				for point: Vector3 in vertices: shell_valid = shell_valid and point.is_finite()
		check("Connected finite architecture remains within the authored parcel: "+id,shell_valid,{"triangles":triangle_count,"buildings":count})
		check("Residential roof slopes are indexed renderable faces: "+id,roofs_visible)
		scene.free()
	var distinct_colors: Dictionary = {}
	for color: String in district_palettes.values(): distinct_colors[color] = true
	check("All six nearby districts retain distinct facade palettes",distinct_colors.size()==6,district_palettes)
	# Ensure the actual streaming path retains the building metadata.
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	var streamed: int = 0
	for district: Dictionary in catalog.districts:
		if str(district.id) not in ["counseling","admissions","recommendations","universities","life","wordking"]: continue
		for chunk: Dictionary in district.chunks:
			var scene: Node3D = (load(str(chunk.path)) as PackedScene).instantiate() as Node3D
			kit.call("apply",scene)
			streamed += scene.find_children("ArchitecturalEnvelope","MeshInstance3D",true,false).size()
			scene.free()
	check("Shipped streamed chunks expose every building to the architecture pass",streamed == total,{"streamed":streamed,"authored":total})
	var output: String = "res://../deliverables/world-revision/architecture-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"buildings":total,"checks":rows},"\t"))
	print("ARCHITECTURE_CHECKS buildings=",total," checks=",rows.size()," failures=",failures)
	quit(1 if failures>0 else 0)
