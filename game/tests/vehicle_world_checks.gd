extends SceneTree

var failures: int = 0
var checks: Array[Dictionary] = []
var fixture: Node3D
var rows: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func run() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	current_scene = fixture
	var player: Node3D = Node3D.new()
	player.name = "Player"
	player.position = Vector3(10000,10000,10000)
	fixture.add_child(player)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var count: int = 0
	for station: Dictionary in layout.stations:
		var id: String = station.id
		var district: Node3D = (load("res://generated/districts/"+id+".tscn") as PackedScene).instantiate() as Node3D
		fixture.add_child(district)
		var traffic: Node3D = district.find_child("CityTraffic",true,false) as Node3D
		check(id+" has all three authored car variants in its actual scene",traffic!=null and traffic.get_child_count()==3)
		if traffic==null:
			district.queue_free()
			await process_frame
			continue
		traffic.set_process(false)
		check(id+" baked traffic uses the current world radius",is_equal_approx(float(traffic.get_meta("radius")),float(layout.radius)))
		for child: Node in traffic.get_children():
			var car: Node3D = child as Node3D
			var model: String = str(car.get_meta("vehicle_model","legacy"))
			count += 1
			var wheels: Array[Node] = car.find_children("wheel-*","Node3D",true,false)
			check(id+"/"+str(car.name)+" replaces the old mini car with an original full-size model",model in ["sedan","hatchback","suv"] and float(car.get_meta("vehicle_length",0))>3.9 and wheels.size()==4)
			if wheels.size()!=4 or model=="legacy":
				continue
			var maximum: float = 0.0
			var radius: float = float(layout.radius)
			var wheel_radius: float = float(car.get_meta("wheel_radius"))
			for sample: int in range(36):
				car.set_meta("progress",float(sample)*float(traffic.get("route_length"))/36.0)
				traffic.call("update_traffic",0.0)
				for wheel: Node in wheels:
					var bottom: Vector3 = (wheel as Node3D).global_position-car.global_basis.y*(wheel_radius*1.004+.0024)
					maximum = maxf(maximum,absf(bottom.length()-(radius+.285)))
			check(id+"/"+model+" actual imported tire contacts stay on road over the complete route",maximum<.01)
			rows.append({"district":id,"model":model,"maximum_contact_error_m":maximum,"wheel_nodes":wheels.size(),"length_m":car.get_meta("vehicle_length")})
		district.queue_free()
		await process_frame
	check("All eighteen world cars were inspected",count==18)
	var file: FileAccess = FileAccess.open("res://../deliverables/vehicles/vehicle_world_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cars":rows,"samples_per_car":36},"\t"))
	print("VEHICLE_WORLD_CHECKS ",checks.size()-failures,"/",checks.size())
	fixture.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
