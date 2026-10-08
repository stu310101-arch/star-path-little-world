extends SceneTree

const StartupFixture: Script = preload("startup_fixture.gd")

# Native companion to measure_web_performance.cjs; measures engine counters,
# functional transitions and retained nodes using the same route before/after.
var world: Node3D
var report: Dictionary = {"samples": [], "checks": []}
var report_path: String = "user://performance_route.json"
var failures: int = 0
var span: float = 3.0

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in range(args.size() - 1):
		if args[i] == "--report":
			report_path = args[i + 1]
	if args.has("--quick"):
		span = 0.25
	call_deferred("run_route")

func run_route() -> void:
	report["engine"] = Engine.get_version_info()
	report["headless"] = DisplayServer.get_name() == "headless"
	report["rendering_method"] = RenderingServer.get_current_rendering_method()
	var start: int = Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/world.tscn") as PackedScene
	var loaded: int = Time.get_ticks_msec()
	world = packed.instantiate() as Node3D
	var instantiated: int = Time.get_ticks_msec()
	root.add_child(world)
	current_scene = world
	report["load_ms"] = loaded - start
	report["instantiate_ms"] = instantiated - loaded
	report["ready_ms"] = Time.get_ticks_msec() - instantiated
	await sample("overview")
	world.set("orbit_yaw", 1.35)
	world.set("orbit_distance", 140.0)
	await sample("overview_rotate_zoom")
	world.call("set_overview", false)
	await wait_details()
	await sample("near")
	var layout: Dictionary = world.get("layout")
	var player: Node3D = world.get("player") as Node3D
	for station: Dictionary in layout.stations:
		world.call("teleport_to", str(station.id))
		await wait_details()
		await sample("district_" + str(station.id))
		check("ground_" + str(station.id), not (player.call("ground_at", player.global_position.normalized()) as Dictionary).is_empty())
		check("player_radius_" + str(station.id), player.global_position.length() > float(layout.radius) - 0.2)
		world.call("open_station", str(station.id))
		if str(station.id) == "wordking":
			var room: Node3D = await StartupFixture.wait_room_scene(self)
			check("indoor_enter", room != null and current_scene != world)
			var transition: Node = root.get_node_or_null("TrainingRoomTransition")
			if transition != null:
				transition.call("return_to_world")
				await create_timer(0.8).timeout
			check("indoor_return_same_world", current_scene == world)
		else:
			await create_timer(1.6).timeout
			check("interaction_" + str(station.id), bool(world.get("paused")))
			world.call("resume_world", {})
		world.set("near_pitch", 1.15)
		player.call("rotate_heading", 2.6)
		await sample("camera_turn_" + str(station.id))
		world.set("near_pitch", 0.58)
	# Repeated return/unload cycles include grace time rather than counting
	# an intentionally warm district as a leak.
	for i: int in range(3):
		world.call("teleport_to", "counseling")
		await wait_details()
		await sample("repeat_near_" + str(i))
		world.call("set_overview", true)
		await create_timer(10.0).timeout
		await sample("repeat_unloaded_" + str(i))
	report["failures"] = failures
	var file: FileAccess = FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("PERFORMANCE_ROUTE_RESULT ", report_path, " failures=", failures)
	current_scene = null
	world.queue_free()
	world = null
	packed = null
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

func wait_details() -> void:
	check("roaming_preparation_ready", await StartupFixture.wait_roaming(world, self))
	var streaming: Node = world.get_node_or_null("DistrictStreaming")
	if streaming == null:
		await create_timer(0.5).timeout
		return
	var started: int = Time.get_ticks_msec()
	var player: Node3D = world.get("player") as Node3D
	while not bool(streaming.call("is_position_ready", player.global_position)):
		if Time.get_ticks_msec() - started > 60000:
			check("detail_ready_timeout", false)
			break
		await process_frame
	await physics_frame

func sample(label: String) -> void:
	var frames: Array[float] = []
	var deadline: int = Time.get_ticks_msec() + int(span * 1000.0)
	var previous: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
	frames.sort()
	var metrics: Dictionary = {
		"stage": label,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"fps": Engine.get_frames_per_second(),
		"frame_ms_median": frames[floori(frames.size() / 2.0)] if not frames.is_empty() else 0.0,
		"frame_ms_p95": frames[mini(frames.size() - 1, int(frames.size() * .95))] if not frames.is_empty() else 0.0,
		"frame_ms_max": frames.back() if not frames.is_empty() else 0.0,
	}
	var streaming: Node = world.get_node_or_null("DistrictStreaming")
	if streaming != null:
		metrics["streaming"] = streaming.call("metrics")
	var obstruction: RefCounted = world.get("camera_obstruction")
	if obstruction.has_method("stats"):
		metrics["obstruction"] = obstruction.call("stats")
	report.samples.append(metrics)
	print("PERF_SAMPLE ", JSON.stringify(metrics))

func check(label: String, passed: bool) -> void:
	report.checks.append({"test": label, "passed": passed})
	if not passed:
		failures += 1
		push_error(label)
