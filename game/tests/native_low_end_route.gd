extends SceneTree

const Fixture: Script = preload("startup_fixture.gd")
var world: Node3D
var report: Dictionary = {"samples":[], "errors":[], "method":"Matching editor hosts unchanged exported Windows PCK with external QA script; not release executable. Deterministic rendered engine process-frame intervals, distinct from browser real-input route."}
var output: String = "user://native_low_end.json"
var capture_directory: String = ""

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(args.size() - 1):
		if args[i] == "--report":
			output = args[i + 1]
		elif args[i] == "--captures":
			capture_directory = args[i + 1]
	call_deferred("run")

func save() -> void:
	var file: FileAccess = FileAccess.open(output, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))

func wait_roaming() -> bool:
	# Return is deferred and the retained world can be detached while its old
	# overview/preparing flags already say false. Do not operate on that instance.
	var deadline: int = Time.get_ticks_msec() + 90000
	while Time.get_ticks_msec() < deadline:
		if current_scene == world and world.is_inside_tree() and not bool(world.get("paused")) and not bool(world.get("entering")):
			if not bool(world.get("overview")) and not bool(world.get("preparing_roam")):
				var player: Node3D = world.get("player") as Node3D
				if bool(player.call("visuals_ready")) and bool(world.get("streaming").call("is_position_ready", player.global_position)):
					return true
		await process_frame
	report.errors.append("Native roaming readiness timed out")
	return false

func run() -> void:
	report["engine"] = Engine.get_version_info()
	report["gpu"] = RenderingServer.get_video_adapter_name()
	report["driver"] = RenderingServer.get_video_adapter_api_version()
	report["rendering_method"] = RenderingServer.get_current_rendering_method()
	report["headless"] = DisplayServer.get_name() == "headless"
	var started: int = Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/world.tscn") as PackedScene
	report["world_load_ms"] = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	world = packed.instantiate() as Node3D
	report["instantiate_ms"] = Time.get_ticks_msec() - started
	started = Time.get_ticks_msec()
	root.add_child(world)
	current_scene = world
	report["ready_ms"] = Time.get_ticks_msec() - started
	var settings: Node = world.get("hud").get("graphics_settings") as Node
	var test_settings: String = "user://native_benchmark_%d.cfg" % Time.get_ticks_msec()
	settings.set("settings_path", test_settings)
	settings.call("set_quality_profile", "low")
	await RenderingServer.frame_post_draw
	report["first_render_ticks_ms"] = Time.get_ticks_msec()
	report["graphics"] = settings.call("get_state")
	await sample("overview")
	world.set("orbit_yaw", 1.35)
	world.set("orbit_distance", 140.0)
	await sample("overview_rotate_zoom")
	world.call("set_overview", false)
	if not await wait_roaming():
		report.errors.append("First roam timed out")
	report["first_roam_ticks_ms"] = Time.get_ticks_msec()
	await sample("near")
	Input.action_press("move_forward")
	await sample("near_moving", 2.5)
	Input.action_release("move_forward")
	var layout: Dictionary = world.get("layout")
	for station: Dictionary in layout.stations:
		world.call("teleport_to", str(station.id))
		if not await wait_roaming():
			report.errors.append("Teleport timeout " + str(station.id))
		await sample("district_" + str(station.id))
		if str(station.id) == "wordking":
			started = Time.get_ticks_msec()
			world.call("open_station", "wordking")
			var room: Node3D = await Fixture.wait_room_scene(self)
			if room == null:
				report.errors.append("Room timed out")
			else:
				report["room_light_ready_ms"] = Time.get_ticks_msec() - started
				var deadline: int = Time.get_ticks_msec() + 60000
				while str(room.get("detail_state")) != "ready" and Time.get_ticks_msec() < deadline:
					await process_frame
				report["room_full_ready_ms"] = Time.get_ticks_msec() - started
				if str(room.get("detail_state")) != "ready":
					report.errors.append("Room detail timed out")
				await sample("indoor")
				root.get_node("TrainingRoomTransition").call("return_to_world")
				await wait_roaming()
	for i: int in range(3):
		world.call("teleport_to", "counseling")
		await wait_roaming()
		world.call("set_overview", true)
		await create_timer(10.0).timeout
		await sample("repeat_unloaded_" + str(i))
	report["finished_ticks_ms"] = Time.get_ticks_msec()
	save()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_settings))
	print("NATIVE_LOW_END_RESULT ", output, " errors=", report.errors)
	quit(0 if report.errors.is_empty() else 1)

func sample(label: String, seconds: float = 8.0) -> void:
	var frames: Array[float] = []
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	var previous: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	frames.sort()
	var total: float = 0.0
	var stalls: int = 0
	for value: float in frames:
		total += value
		stalls += 1 if value > 100.0 else 0
	var row: Dictionary = {"stage":label, "frame_count":frames.size(), "fps_mean":frames.size() * 1000.0 / total,
		"p95_ms":frames[mini(frames.size()-1, ceili(frames.size()*.95)-1)], "max_ms":frames.back(), "over_100_ms":stalls,
		"engine_fps":Engine.get_frames_per_second(), "static_allocator_bytes":Performance.get_monitor(Performance.MEMORY_STATIC),
		"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0, "physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}
	if is_instance_valid(world) and world.is_inside_tree():
		row["streaming"] = world.get("streaming").call("metrics")
	report.samples.append(row)
	save()
	if not capture_directory.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(capture_directory.path_join(label + ".png"))
	print("NATIVE_SAMPLE ", JSON.stringify(row))
