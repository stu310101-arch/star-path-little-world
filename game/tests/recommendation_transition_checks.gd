extends SceneTree
## Actual room-to-hall round trip. Synthetic selection only; no private cloud data.
const Fixture = preload("res://tests/startup_fixture.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var seated: bool = false

func _initialize() -> void:
	run.call_deferred()

func check(label: String, ok: bool) -> void:
	checks.append({"test":label,"passed":ok})
	print("RECOMMENDATION_TRANSITION ", label, " ", ok)
	if not ok:
		failures += 1

func wait_scene(path: String, previous: Node, timeout: int = 45000) -> Node3D:
	var deadline: int = Time.get_ticks_msec() + timeout
	while Time.get_ticks_msec() < deadline:
		if is_instance_valid(current_scene) and current_scene != previous and current_scene.scene_file_path == path:
			return current_scene as Node3D
		await process_frame
	return null

func run() -> void:
	seated = OS.get_cmdline_user_args().has("--seated")
	var world: Node3D = load("res://scenes/world.tscn").instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.call("set_overview", false)
	check("World prepares", await Fixture.wait_roaming(world,self))
	world.call("teleport_to", "recommendations")
	check("Recommendation district prepares", await Fixture.wait_roaming(world,self))
	var player: Node3D = world.get("player") as Node3D
	var outdoor_position: Vector3 = player.global_position
	var heading: Vector3 = player.get("heading")
	var world_id: int = world.get_instance_id()
	var music: Node = world.get("music")
	world.call("open_station", "recommendations")
	var study: Node3D = await wait_scene("res://scenes/recommendation_room.tscn",world)
	check("Third station opens the authored study", study != null)
	if study == null:
		finish()
		return
	check("Study prepares", await Fixture.wait_room(study,self))
	var seat_id: String = ""
	if seated:
		var furniture: Node = study.get("seats")
		for target: Dictionary in furniture.get("targets"):
			if not str(target.get("station_view","")).is_empty():
				seat_id = str(target.id)
				break
		if seat_id.is_empty():
			seat_id = str((furniture.get("targets") as Array)[0].id)
		check("Seated visit starts on a fixed chair",bool(furniture.call("restore_fixed_seat",seat_id)))
		check("Seated return descriptor identifies the chair",str((study.call("capture_return_state") as Dictionary).seat.id)==seat_id)
	var study_id: int = study.get_instance_id()
	var study_position: Vector3 = (study.get("player") as Node3D).position
	check("Original outdoor instance is suspended", is_instance_id_valid(world_id) and not world.is_inside_tree())
	check("Study shares the existing music", study.get("music") == music)
	# Clear an invalid target before testing the valid immutable hall id.
	study.emit_signal("request_related_room","999",{})
	await process_frame
	check("Unknown hall id cannot detach the study", current_scene == study)
	study.emit_signal("request_related_room","010",{})
	study.emit_signal("request_related_room","010",{})
	var hall: Node3D = await wait_scene("res://scenes/university_hall.tscn",study)
	check("One linked university hall opens", hall != null)
	if hall == null:
		finish()
		return
	check("Hall prepares", await Fixture.wait_room(hall,self))
	await process_frame
	check("Previous study was freed", not is_instance_id_valid(study_id))
	check("Target is hall id 010, not admissions code", hall.get("initial_school_id") == "010" and (hall.get("nearest_target") as Dictionary).get("school_id","") == "010")
	check("Hall uses a return-to-recommendations action", hall.get("return_label") == "返回推薦")
	check("Hall preserves the same suspended outdoor world", is_instance_id_valid(world_id) and not world.is_inside_tree())
	check("Hall shares music", hall.get("music") == music)
	var hall_id: int = hall.get_instance_id()
	hall.call("return_to_world")
	hall.emit_signal("request_return_to_world")
	var restored: Node3D = await wait_scene("res://scenes/recommendation_room.tscn",hall)
	check("Hall return recreates recommendation room", restored != null)
	if restored == null:
		finish()
		return
	check("Restored room prepares", await Fixture.wait_room(restored,self))
	await process_frame
	check("Hall was released", not is_instance_id_valid(hall_id))
	check("Study player position restored", (restored.get("player") as Node3D).position.distance_to(study_position) < .15)
	if seated:
		var restored_seats: Node = restored.get("seats")
		check("Hall return restores the same seated interaction",bool(restored_seats.call("is_seated")) and str((restored_seats.get("active") as Dictionary).get("id",""))==seat_id)
		check("Restored seated actor does not collide with its chair",(restored.get("player") as CharacterBody3D).collision_mask==0)
		check("Restored chair accepts ordinary stand action",bool(restored_seats.call("interact")))
		await create_timer(1.2).timeout
		check("Restored chair has a clear safe exit",not bool(restored_seats.call("is_active")) and bool(restored.get("player").get("controls_enabled")))
	check("Shared music returns to recommendation context", music.get("requested_context") == "recommendations")
	restored.emit_signal("request_return_to_world")
	restored.emit_signal("request_return_to_world")
	var returned: Node3D = await wait_scene("res://scenes/world.tscn",restored)
	check("Final return restores the original outdoor identity", returned == world and world.get_instance_id() == world_id)
	check("Outdoor position restored", player.global_position.distance_to(outdoor_position) < .25)
	check("Outdoor heading restored", (player.get("heading") as Vector3).dot(heading) > .999)
	check("Outdoor camera and music restored", root.get_camera_3d() == world.get("camera") and music.get_parent() == world)
	for voice: Node in music.get_children():
		if voice is AudioStreamPlayer:
			voice.stop()
	current_scene = null
	world.queue_free()
	await process_frame
	await create_timer(.15).timeout
	finish()

func finish() -> void:
	var directory: String = ProjectSettings.globalize_path("res://../deliverables/recommendation-room")
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory.path_join("transition-seated.json" if seated else "transition.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"scope":"Actual Godot rooms; synthetic school target, no live account data."},"\t"))
	print("RECOMMENDATION_TRANSITION_DONE checks=",checks.size()," failures=",failures)
	quit(0 if failures == 0 else 1)
