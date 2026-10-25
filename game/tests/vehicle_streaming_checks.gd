extends SceneTree

const Traffic: Script = preload("res://scripts/city_traffic.gd")
var fixture: Node3D
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String,passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures+=1
		push_error(label)

func run() -> void:
	fixture = Node3D.new()
	root.add_child(fixture)
	current_scene = fixture
	var player: Node3D = Node3D.new()
	player.name = "Player"
	player.position = Vector3(10000,10000,10000)
	fixture.add_child(player)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	for district: Dictionary in catalog.districts:
		var id: String = str(district.id)
		if id.begins_with("ocean_") or id=="sakura":
			continue
		var controllers: Array[Node3D] = []
		var cars: Array[Node3D] = []
		for descriptor: Dictionary in district.chunks:
			var chunk: Node3D = (load(str(descriptor.path)) as PackedScene).instantiate() as Node3D
			for child: Node in chunk.find_children("*","Node3D",true,false):
				if child.get_script()!=Traffic:
					continue
				var actor: Node3D = child as Node3D
				actor.set_process(false)
				actor.owner = null
				for owned: Node in actor.find_children("*", "", true, false):
					owned.owner = null
				actor.get_parent().remove_child(actor)
				fixture.add_child(actor)
				controllers.append(actor)
				for car: Node in actor.get_children():
					cars.append(car as Node3D)
			chunk.free()
		check(id+" streams three cars in three independent containers",controllers.size()==3 and cars.size()==3)
		if cars.size()==3 and controllers.size()==3:
			var registered: bool = true
			var bounded: bool = true
			var routes_match: bool = true
			for car: Node3D in cars:
				registered = registered and car.is_in_group("road_vehicle")
			for actor: Node3D in controllers:
				bounded = bounded and actor.get_child_count()==1
				routes_match = routes_match and is_equal_approx(float(actor.get("route_length")),float(controllers[0].get("route_length")))
			check(id+" independently loaded cars join the common traffic fleet",registered and bounded and routes_match)
			cars[0].set_meta("progress",5.0)
			cars[1].set_meta("progress",9.0)
			cars[2].set_meta("progress",float(controllers[0].get("route_length"))*.5)
			controllers[0].call("update_traffic",1.0)
			check(id+" follows a nearby car in a separate chunk",is_equal_approx(float(cars[0].get_meta("progress")),5.0))
			cars[1].set_meta("progress",30.0)
			controllers[0].call("update_traffic",1.0)
			check(id+" moves again after the separate lead car clears",float(cars[0].get_meta("progress"))>6.5)
			cars[0].set_meta("progress",5.0)
			cars[1].set_meta("progress",9.0)
			var original_up: Vector3 = cars[1].get_meta("district_up") as Vector3
			cars[1].set_meta("district_up",-original_up)
			controllers[0].call("update_traffic",1.0)
			check(id+" ignores a car on the opposite globe face",float(cars[0].get_meta("progress"))>6.5)
			cars[1].set_meta("district_up",original_up)
		for actor: Node3D in controllers:
			actor.queue_free()
		await process_frame
		check(id+" unload removes all fleet membership",get_nodes_in_group("road_vehicle").is_empty())
	var file: FileAccess = FileAccess.open("res://../deliverables/vehicles/vehicle_streaming_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("VEHICLE_STREAMING_CHECKS ",checks.size()-failures,"/",checks.size())
	fixture.queue_free()
	await process_frame
	quit(1 if failures>0 else 0)
