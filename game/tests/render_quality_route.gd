extends SceneTree

# Real Compatibility render evidence, not a mobile hardware simulation.
const Fixture = preload("res://tests/startup_fixture.gd")
var world: Node3D
var settings: Node
var label: String = "before"
var profile: String = "mobile"
var indoor_only: bool = false
var output: String
var report: Dictionary = {"samples": [], "errors": []}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		label = args[0]
	if args.size() > 1:
		profile = args[1]
	indoor_only = args.has("--indoor-only")
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	output = ProjectSettings.globalize_path("res://../deliverables/render-quality/" + label)
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	report.merge({"engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "profile": profile, "method": "Windows native Compatibility, real rendered frames; not iPhone/Safari performance", "viewport": [1280, 800]})
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	settings = world.get("hud").get("graphics_settings") as Node
	settings.set("settings_path", "user://render_quality_fixture.cfg")
	settings.call("set_quality_profile", profile)
	settings.call("set_frame_limit", 30)
	if not indoor_only:
		await create_timer(40.0 if profile == "balanced" else 2.0).timeout
		await sample("overview")
		for index: int in [0, 1, 2, 3, 4, 5]:
			world.call("setup_water_review", index, false)
			if not await Fixture.wait_roaming(world, self):
				report.errors.append("roam_" + str(index))
			await create_timer(2.0).timeout
			await sample("waterfront_" + str(index))
	else:
		await create_timer(2.0).timeout
	world.call("teleport_to", "wordking")
	await Fixture.wait_roaming(world, self)
	world.call("open_station", "wordking")
	var room: Node3D = await Fixture.wait_room_scene(self)
	if room != null:
		var deadline: int = Time.get_ticks_msec() + 60000
		while str(room.get("detail_state")) != "ready" and Time.get_ticks_msec() < deadline:
			await process_frame
		print("RENDER_QUALITY_INDOOR_GATE ", sampling_debug())
		if indoor_only:
			# Native automation may launch without foreground focus. Request it
			# through the real Window so the production focus signal is tested.
			root.grab_focus()
			await process_frame
			await process_frame
			print("RENDER_QUALITY_INDOOR_FOCUS_REQUEST ", sampling_debug())
		await create_timer(40.0 if profile == "balanced" else 2.0).timeout
		await sample("indoor")
		root.get_node("TrainingRoomTransition").call("return_to_world")
		await create_timer(2.0).timeout
		await sample("returned")
	else:
		report.errors.append("indoor timed out")
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://render_quality_fixture.cfg"))
	current_scene = null
	world.queue_free()
	await process_frame
	await process_frame
	print("RENDER_QUALITY_ROUTE ", label, " errors=", report.errors)
	quit(0 if report.errors.is_empty() else 1)

func sample(stage: String) -> void:
	var frames: Array[float] = []
	var deadline: int = Time.get_ticks_msec() + 2000
	var previous: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	frames.sort()
	var total: float = 0.0
	for value: float in frames:
		total += value
	await RenderingServer.frame_post_draw
	var row: Dictionary = {"stage": stage, "frames": frames.size(), "fps_mean": 1000.0 * frames.size() / total, "p95_ms": frames[mini(frames.size()-1, ceili(frames.size() * .95)-1)], "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "render_buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED), "render_texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED), "static_allocator_bytes": Performance.get_monitor(Performance.MEMORY_STATIC), "graphics": settings.call("get_state")}
	row["sampling_debug"] = sampling_debug()
	root.get_texture().get_image().save_png(output.path_join(stage + ".png"))
	report.samples.append(row)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RENDER_QUALITY_SAMPLE ", stage, " ", row.fps_mean)

func sampling_debug() -> Dictionary:
	var scene: Node = current_scene
	var debug: Dictionary = {
		"focused": settings.get("_focused"),
		"page_visible": settings.get("_page_visible"),
		"window_focused": DisplayServer.window_is_focused(),
		"tree_paused": paused,
		"settings_inside_tree": settings.is_inside_tree(),
		"tick_signal_connected": is_connected("process_frame", Callable(settings, "_sample_render_frame")),
		"current_scene": str(scene.get_path()) if is_instance_valid(scene) else "none",
		"active_scene_id": settings.get("_active_scene_id"),
		"scene_id": scene.get_instance_id() if is_instance_valid(scene) else 0,
		"gameplay_gate": settings.call("_gameplay_is_active", scene),
		"streaming_busy": settings.get("_streaming_busy"),
		"warmup_seconds": settings.get("_resolution_cooldown"),
		"window_seconds": settings.get("_window_seconds"),
		"last_frame_age_ms": float(Time.get_ticks_usec() - int(settings.get("_last_frame_usec"))) / 1000.0,
	}
	if not is_instance_valid(scene):
		return debug
	if scene.get("ready_for_play") != null:
		var interactions: Node = scene.get("interactions") as Node
		var games: Node = scene.get("computer_games") as Node
		var dialog: Window = scene.get("native_game_dialog") as Window
		debug["room"] = {
			"ready_for_play": scene.get("ready_for_play"),
			"detail_state": scene.get("detail_state"),
			"returning": scene.get("returning"),
			"interaction_state": interactions.get("state") if is_instance_valid(interactions) else "none",
			"camera_blocked": interactions.call("camera_blocked") if is_instance_valid(interactions) else false,
			"game_open": games.call("is_open") if is_instance_valid(games) else false,
			"native_dialog_visible": dialog.visible if is_instance_valid(dialog) else false,
		}
	else:
		var hud: Node = scene.get("hud") as Node
		var destinations: Control = hud.get("destination_card") as Control if is_instance_valid(hud) else null
		debug["world"] = {
			"startup_presented": scene.get("startup_presented"),
			"entering": scene.get("entering"),
			"preparing_roam": scene.get("preparing_roam"),
			"preparing_room": scene.get("preparing_room"),
			"paused": scene.get("paused"),
			"settings_open": hud.call("is_settings_open") if is_instance_valid(hud) else false,
			"destinations_open": destinations.visible if is_instance_valid(destinations) else false,
		}
	return debug
