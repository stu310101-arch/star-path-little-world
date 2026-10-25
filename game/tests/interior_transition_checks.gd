extends SceneTree

const Fixture: Script = preload("res://tests/startup_fixture.gd")
const Transition: Script = preload("res://scripts/indoor_transition.gd")
const TrainingTransition: Script = preload("res://scripts/training_room_transition.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks += 1
	print("INTERIOR_TRANSITION_CHECK ", label, " passed=", passed)
	if not passed:
		failures += 1

func _run() -> void:
	var legacy: Node = TrainingTransition.new()
	check("Training compatibility defaults remain available", legacy.get("room_scene_path") == TrainingTransition.ROOM_SCENE and legacy.get("room_music_context") == "wordking")
	legacy.free()
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	var world_id: int = world.get_instance_id()
	var player: Node3D = world.get("player") as Node3D
	var music: Node = world.get("music") as Node
	var music_id: int = music.get_instance_id()
	var settings: Node = get_first_node_in_group("graphics_settings")
	var streaming: Node = world.get("streaming") as Node
	if OS.get_cmdline_user_args().has("--constrained"):
		# Exercise the production budget policy without changing the user's
		# saved preferences or relying on the desktop's default preset.
		settings.set("quality_profile", "mobile")
		settings.call("apply_settings")
		settings.emit_signal("state_changed")
		check("Constrained fixture disables outdoor detail before roaming", bool(streaming.call("metrics").constrained_runtime))
	var probe: Node = Transition.new()
	root.add_child(probe)
	check("A missing scene fails before detaching the world", not bool(probe.call("open_from_world", world, {}, "res://scenes/no_such_interior.tscn", "world")))
	check("A failed scene leaves current world and music intact", current_scene == world and music.get_parent() == world and world.is_inside_tree())
	check("A scene without a return signal is rejected", not bool(probe.call("open_from_world", world, {}, "res://scenes/world.tscn", "world")))
	check("Invalid scene reports a recoverable error", not str(probe.get("last_error")).is_empty())
	probe.free()
	world.call("set_overview", false)
	check("World becomes playable", await Fixture.wait_roaming(world, self))
	for cycle: int in range(4):
		var station: String = "wordking" if cycle % 2 == 0 else "universities"
		var expected: String = "res://scenes/training_room.tscn" if station == "wordking" else "res://scenes/university_hall.tscn"
		world.call("teleport_to", station)
		check("Destination prepares before entry: " + station, await Fixture.wait_roaming(world, self))
		var position: Vector3 = player.global_position
		var heading: Vector3 = player.get("heading") as Vector3
		world.call("open_station", station)
		var deadline: int = Time.get_ticks_msec() + 30000
		while current_scene == world and Time.get_ticks_msec() < deadline:
			await process_frame
		var room: Node3D = current_scene as Node3D
		check("Station opens its independent room: " + station, room != null and room != world and room.scene_file_path == expected)
		if room == null or room == world:
			quit(1)
			return
		var room_id: int = room.get_instance_id()
		check("Outdoor world is detached and preserved", is_instance_id_valid(world_id) and not world.is_inside_tree())
		check("Room uses the same music controller", room.get("music") == music and music.get_instance_id() == music_id)
		check("Music context follows the selected destination", music.get("requested_context") == station)
		check("Room receives shared graphics settings", room.get("graphics_settings") == settings)
		check("Streaming enters suspended release mode", bool(streaming.get("_interior_active")))
		check("Outdoor player cannot move indoors", not bool(player.get("controls_enabled")))
		if cycle >= 2:
			check("Interior finishes preparation: " + station, await Fixture.wait_room(room, self))
		# The first two cycles return while interior preparation is pending.
		# Double emission must schedule exactly one world restoration.
		room.emit_signal("request_return_to_world")
		room.emit_signal("request_return_to_world")
		deadline = Time.get_ticks_msec() + 15000
		while current_scene != world and Time.get_ticks_msec() < deadline:
			await process_frame
		check("Return restores original world identity", current_scene == world and world.get_instance_id() == world_id)
		check("Return restores position", player.global_position.distance_to(position) < .25)
		check("Return restores heading", (player.get("heading") as Vector3).dot(heading) > .999)
		check("Return restores camera", root.get_camera_3d() == world.get("camera"))
		check("Return restores music parent", music.get_parent() == world and music.get_instance_id() == music_id)
		check("Return clears suspended streaming", not bool(streaming.get("_interior_active")))
		if OS.get_cmdline_user_args().has("--constrained"):
			check("Constrained return is ready without optional outdoor chunks", bool(streaming.call("is_position_ready", player.global_position)) and int(streaming.call("metrics").loaded_chunks) == 0)
		check("Return enables player controls", bool(player.get("controls_enabled")))
		await process_frame
		await process_frame
		check("Interior is released after return", not is_instance_id_valid(room_id))
		check("Transition helper is released after return", root.get_node_or_null("IndoorTransition") == null and root.get_node_or_null("TrainingRoomTransition") == null)
	current_scene = null
	# AudioServer releases Ogg playback on its own mix thread. Stop test music
	# before tree teardown, then allow that release to finish before quit().
	for child: Node in music.get_children():
		if child is AudioStreamPlayer:
			(child as AudioStreamPlayer).stop()
	world.queue_free()
	await process_frame
	await create_timer(.15).timeout
	print("INTERIOR_TRANSITION_CHECKS checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
