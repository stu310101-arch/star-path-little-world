extends SceneTree

const Traffic = preload("res://scripts/city_traffic.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var fixture: Node3D
var player: Node3D
var measurements: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func model_bounds(model: Node3D) -> AABB:
	var result: AABB
	var first: bool = true
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh: MeshInstance3D = child as MeshInstance3D
		var box: AABB = (model.global_transform.affine_inverse()*mesh.global_transform)*mesh.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

func triangle_count(model: Node3D) -> int:
	var count: int = 0
	for child: Node in model.find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = (child as MeshInstance3D).mesh
		for index: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			count += indices.size()/3 if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()/3
	return count

func add_car(traffic: Node3D, key: String) -> Node3D:
	var car: Node3D = Node3D.new()
	car.name = "Vehicle"
	car.set_meta("district_up",Vector3.UP)
	car.set_meta("progress",8.0)
	car.set_meta("speed",1.65)
	car.set_meta("vehicle_length",4.78 if key!="hatchback" else 4.24)
	car.set_meta("wheel_radius",.355 if key=="suv" else (.315 if key=="hatchback" else .325))
	car.set_meta("wheelbase",2.78 if key=="suv" else (2.5 if key=="hatchback" else 2.8))
	car.set_meta("track",1.744 if key=="suv" else (1.644 if key=="hatchback" else 1.674))
	traffic.add_child(car)
	# This fixture inserts actors after _ready; baked actors are enrolled by
	# the production controller when their individual streaming chunk enters.
	car.add_to_group("road_vehicle")
	var visual: Node3D = (load("res://assets/vehicles/"+key+".glb") as PackedScene).instantiate() as Node3D
	car.add_child(visual)
	var box: AABB = model_bounds(visual)
	visual.position = -Vector3(box.get_center().x,box.position.y,box.get_center().z)
	return car

func run() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	current_scene = fixture
	player = Node3D.new()
	player.name = "Player"
	fixture.add_child(player)
	player.position = Vector3(10000,10000,10000)
	var total: int = 0
	for key: String in ["sedan","hatchback","suv"]:
		var model: Node3D = (load("res://assets/vehicles/"+key+".glb") as PackedScene).instantiate() as Node3D
		fixture.add_child(model)
		var box: AABB = model_bounds(model)
		var triangles: int = triangle_count(model)
		total += triangles
		var wheels: Array[Node] = model.find_children("wheel-*","Node3D",true,false)
		var material_names: Array[String] = []
		for child: Node in model.find_children("*","MeshInstance3D",true,false):
			var mesh: Mesh = (child as MeshInstance3D).mesh
			for surface: int in range(mesh.get_surface_count()):
				var material: Material = mesh.surface_get_material(surface)
				if material!=null and material.resource_name not in material_names:
					material_names.append(material.resource_name)
		check(key+" keeps full road-vehicle dimensions in meters including mirrors",box.size.z>3.9 and box.size.z<5.0 and box.size.x>1.75 and box.size.x<2.5 and box.size.y>1.35 and box.size.y<1.85)
		check(key+" import retains applied unit scale",model.scale.is_equal_approx(Vector3.ONE))
		check(key+" tire contacts start at the ground origin",absf(box.position.y)<.006)
		check(key+" has four separately turning wheel pivots",wheels.size()==4)
		var axle_orientation: bool = true
		for wheel: Node in wheels:
			var pivot: Node3D = wheel as Node3D
			axle_orientation = axle_orientation and absf(pivot.basis.x.dot(Vector3.RIGHT))>.999
			axle_orientation = axle_orientation and ((pivot.position.z>0.0)==str(pivot.name).contains("front"))
		check(key+" front wheels and spin axes use production +Z forward",axle_orientation)
		check(key+" retains separate steel paint glass rubber alloy and lamps",material_names.has("MAT_Paint_"+key) and material_names.has("MAT_Glass_SmokedReflective") and material_names.has("MAT_Rubber_Tire") and material_names.has("MAT_Alloy_BrushedAluminium") and material_names.has("MAT_Lamp_WhiteLED") and material_names.has("MAT_Lamp_RubyLens"))
		var low: Node3D = (load("res://assets/vehicles/"+key+"_lod1.glb") as PackedScene).instantiate() as Node3D
		fixture.add_child(low)
		var low_triangles: int = triangle_count(low)
		check(key+" LOD1 cuts triangles while preserving vehicle bounds",low_triangles<triangles*.6 and model_bounds(low).size.distance_to(box.size)<.03)
		measurements[key]={"dimensions":var_to_str(box.size),"triangles":triangles,"lod1_triangles":low_triangles,"materials":material_names}
		model.queue_free()
		low.queue_free()
	check("All three imported LOD0 vehicles stay within 80000 triangles",total<=80000)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	for normal: Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT,Vector3.BACK,Vector3.DOWN]:
		var traffic: Node3D = Node3D.new()
		traffic.set_script(Traffic)
		traffic.set_meta("radius",float(layout.radius))
		traffic.set_meta("route_points",PackedVector2Array([Vector2(-14,-15),Vector2(14,-15),Vector2(14,15),Vector2(-14,15)]))
		fixture.add_child(traffic)
		traffic.set_process(false)
		var car: Node3D = add_car(traffic,"sedan")
		car.set_meta("district_up",normal)
		traffic.call("update_traffic",0.0)
		var wheels: Array[Node] = car.find_children("wheel-*","Node3D",true,false)
		var wheel_before: Basis = (wheels[0] as Node3D).basis
		traffic.call("update_traffic",2.0)
		check("Traffic drives 3.3 m and turns all real wheels on normal "+str(normal),is_equal_approx(float(car.get_meta("progress")),11.3) and not (wheels[0] as Node3D).basis.is_equal_approx(wheel_before))
		var ahead: Vector3 = Geo.surface(normal,traffic.call("sample_route",11.45) as Vector2,float(layout.radius))
		check("Vehicle nose follows route and local gravity "+str(normal),car.basis.z.dot((ahead-car.position).slide(car.basis.y).normalized())>.999 and car.basis.y.dot(car.position.normalized())>.9999)
		var max_contact_error: float = 0.0
		for x: float in [-.837,.837]:
			for z: float in [-1.4,1.4]:
				max_contact_error = maxf(max_contact_error,absf((car.transform*Vector3(x,0,z)).length()-(float(layout.radius)+.285)))
		check("All four tire contacts follow the curved road within 5 mm "+str(normal),max_contact_error<.005)
		var probe_distance: float = 11.3+maxf(2.0,float(car.get_meta("vehicle_length"))*.5+.7)
		player.position = Geo.surface(normal,traffic.call("sample_route",probe_distance) as Vector2,float(layout.radius)+.4)
		traffic.call("update_traffic",1.0)
		check("Full-size vehicle yields to the player ahead "+str(normal),is_equal_approx(float(car.get_meta("progress")),11.3))
		player.position = Vector3(10000,10000,10000)
		var lead: Node3D = add_car(traffic,"suv")
		lead.set_meta("district_up",normal)
		lead.set_meta("progress",16.5)
		traffic.call("update_traffic",.1)
		check("Headway accounts for full vehicle body lengths "+str(normal),is_equal_approx(float(car.get_meta("progress")),11.3))
		traffic.queue_free()
		await process_frame
	var output: String = ProjectSettings.globalize_path("res://../deliverables/vehicles/vehicle_checks.json")
	var file: FileAccess = FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements,"total_triangles":total,"radius":layout.radius},"\t"))
	print("VEHICLE_CHECKS ",checks.size()-failures,"/",checks.size()," total triangles ",total)
	fixture.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
