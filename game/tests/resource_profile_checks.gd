extends SceneTree
var failures: Array[String] = []
var checks: int = 0
class Service:
	extends Node
	signal closed
	signal failed(message: String)
	signal state_changed(user: Dictionary)
	signal forum_message(packet: Dictionary)
	signal progress_message(packet: Dictionary)
	var user: Dictionary = {}
	var opened: bool = false
	var last_error: String = ""
	func request_forum(_command: Dictionary) -> bool:
		return true
	func request_forum_page(_command: Dictionary) -> bool:
		return true
	func request_progress(_command: Dictionary) -> bool:
		return true
	func close_view() -> void:
		closed.emit()

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	print("RESOURCE_CHECK ", label, " ", passed)
	if not passed:
		failures.append(label)

func run() -> void:
	var service: Node = Service.new()
	service.name = "StarPathAccount"
	root.add_child(service)
	var resources: Node = root.get_node("ResourceProfile")
	resources.set("profile", "low")
	var world: Node3D = (load(str(resources.call("world_path"))) as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await process_frame
	check("low world retains all six functional portals", world.get_node("Stations").get_child_count() == 6)
	check("low world disables detail downloads", bool(world.get("streaming").get("_constrained_runtime")))
	check("low world removes the blossom district while retaining six main regions", not world.get("streaming").get("_regions").has("sakura") and world.get("streaming").get("_regions").size() == 6)
	check("low uses separate rendering preferences", str(world.get("graphics_settings").get("settings_path")).ends_with("graphics_settings_low_resources.cfg"))
	for id: String in ["counseling","admissions","recommendations","universities","life","wordking"]:
		world.call("teleport_to", id)
		await process_frame
		check("functional destination " + id, world.get("player").global_position.is_finite())
	await _capture("low-world")
	world.queue_free()
	await process_frame
	var hall: Node3D = (load("res://scenes/university_hall.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hall)
	current_scene = hall
	await _wait_ready(hall)
	check("low university hall is playable", bool(hall.get("ready_for_play")))
	check("all 138 university records retained", hall.get("catalog").get("entries").size() == 138)
	hall.call("show_region", "north")
	await process_frame
	var space: Node3D = hall.get("space")
	var miniatures: Array[Node] = space.find_children("Diorama", "Node3D", true, false)
	check("low exhibits retain up to four authored campus models", not miniatures.is_empty() and miniatures.all(func(node: Node) -> bool: return node.get_child_count() >= 1 and node.get_child_count() <= 4))
	check("low exhibit interaction targets retained", space.get("targets").size() >= 48)
	check("no missing low exhibit resources", space.get("exhibit_errors").is_empty())
	await _capture("low-university")
	hall.queue_free()
	await process_frame
	var garden: Node3D = (load("res://scenes/discussion_garden.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(garden)
	current_scene = garden
	await _wait_ready(garden)
	check("low discussion garden is playable", bool(garden.get("ready_for_play")))
	check("low garden retains five discussion zones", garden.get("zones").size() == 5)
	var devices: int = 0
	for zone: Dictionary in garden.get("zones").values():
		devices += zone.devices.size()
	check("all forty message devices retained", devices == 40)
	check("low garden reads its own collider layout", bool(garden.get("layout").get("low_resources", false)))
	var garden_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/low/discussion/layout.json")) as Dictionary
	var original_garden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/discussion_garden/layout.json")) as Dictionary
	check("authored message locations and navigation remain unchanged", _same_data(garden_layout.zones,original_garden.zones) and _same_data(garden_layout.navigation,original_garden.navigation))
	check("removed secondary buildings have no invisible colliders", (garden_layout.colliders as Array).all(func(row: Dictionary) -> bool: return not str(row.name).begins_with("Maker_East") and not str(row.name).begins_with("LearningGrove_EastCabin")))
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/low/manifest.json")) as Dictionary
	check("balanced outdoor scenery retains 108 authored trees and 30 buildings", manifest.retained_landscape_trees == 108 and manifest.retained_buildings == 30)
	for kind: String in ["boat","fish"]:
		var life: Dictionary = manifest.get("water_life",{}).get(kind,{})
		check("water retains a reduced number of " + kind, int(life.get("retained",0)) > 0 and int(life.get("retained",0)) < int(life.get("before",0)))
	check("ocean tessellation reduced without changing its radius", int(manifest.get("ocean_triangles",{}).get("after",0)) < int(manifest.get("ocean_triangles",{}).get("before",0)))
	await _capture("low-discussion")
	garden.queue_free()
	await process_frame
	for path: String in ["admissions_room","training_room"]:
		var room: Node3D = (load("res://scenes/"+path+".tscn") as PackedScene).instantiate() as Node3D
		root.add_child(room)
		current_scene = room
		await _wait_ready(room)
		check(path+" low variant is playable",bool(room.get("ready_for_play")))
		var room_layout: Dictionary = room.get("layout")
		check(path+" reads independent low layout",bool(room_layout.get("low_resources",false)))
		if path == "training_room":
			check("all three training computers retained",room_layout.computers.size()==3 and (room.get("furniture_actions").get("screens") as Dictionary).size()==3)
			check("all thirteen readable books retained",room_layout.books.size()==13)
			check("training painting and seating retained",room.get("room_model").find_child("PAINTING_StarryNight",true,false)!=null and not room_layout.seats.is_empty())
		else:
			check("all six admissions actions retained",room.get("stations").size()==6)
			check("all eight admissions seats retained",room.get("seats").get("targets").size()==8)
		await _capture("low-"+path)
		room.queue_free()
		await process_frame
	resources.set("profile", "full")
	check("full world still uses original scene", resources.call("world_path") == "res://scenes/world.tscn")
	print("RESOURCE_PROFILE_RESULTS ", JSON.stringify({"checks":checks,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _wait_ready(room: Node) -> void:
	var deadline: int = Time.get_ticks_msec() + 90000
	while not bool(room.get("ready_for_play")) and Time.get_ticks_msec() < deadline:
		if str(room.get("detail_state")) == "error":
			check("room has no loading error: " + str(room.get("detail_error")), false)
			return
		await process_frame

func _same_data(a: Variant, b: Variant) -> bool:
	if (a is float or a is int) and (b is float or b is int):
		return absf(float(a)-float(b)) < .000001
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index: int in range(a.size()):
			if not _same_data(a[index],b[index]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same_data(a[key],b[key]):
				return false
		return true
	return a == b

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path("res://../deliverables/resource-packs/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	root.get_texture().get_image().save_png(path)
