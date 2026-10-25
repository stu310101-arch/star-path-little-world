extends SceneTree

# Same production camera positions and viewport before/after; uncapped native
# Compatibility throughput is diagnostic, not a claim about Web or phones.
const Fixture = preload("res://tests/startup_fixture.gd")
var world: Node3D
var settings: Node
var output: String
var profile: String = "standard"
var mobile_policy: bool = false
var report: Dictionary = {"samples": [], "errors": []}

func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var label: String = args[0] if args.size() > 0 else "probe"
	profile = args[1] if args.size() > 1 else "standard"
	mobile_policy = args.has("--mobile-policy")
	output = ProjectSettings.globalize_path("res://../deliverables/render-budget/" + label)
	DirAccess.make_dir_recursive_absolute(output)
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	# Desktop input must not open a HUD modal during the fixed-view sample.
	root.gui_disable_input = true
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	report.merge({"engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "profile": profile,
		"viewport": [1280, 800], "mobile_policy": mobile_policy,
		"method": "uncapped native Compatibility fixed views; not Web/mobile FPS"})
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	settings = world.get("graphics_settings") as Node
	settings.set("settings_path", "user://render_budget_fixture.cfg")
	settings.set("_mobile_web", mobile_policy)
	settings.call("set_quality_profile", profile)
	settings.call("set_frame_limit", 90)
	Engine.max_fps = 0
	await create_timer(2.0).timeout
	await sample("overview")
	for index: int in range(6):
		world.call("setup_water_review", index, false)
		if not await Fixture.wait_roaming(world, self):
			report.errors.append("roam_" + str(index))
		await create_timer(2.0).timeout
		await sample("waterfront_" + str(index))
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://render_budget_fixture.cfg"))
	current_scene = null
	world.queue_free()
	await process_frame
	await process_frame
	print("RENDER_BUDGET_DONE ", output, " errors=", report.errors)
	quit(0 if report.errors.is_empty() else 1)

func sample(stage: String) -> void:
	var frames: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var deadline: int = Time.get_ticks_msec() + 2500
	var previous: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frames.append(float(now - previous) / 1000.0)
		previous = now
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
	frames.sort()
	gpu.sort()
	cpu.sort()
	await RenderingServer.frame_post_draw
	var row: Dictionary = {
		"stage": stage, "frames": frames.size(), "median_ms": frames[frames.size() / 2],
		"p95_ms": frames[mini(frames.size() - 1, ceili(frames.size() * .95) - 1)],
		"gpu_median_ms": gpu[gpu.size() / 2], "render_cpu_median_ms": cpu[cpu.size() / 2],
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"render_texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"graphics": settings.call("get_state"), "streaming": world.get("streaming").call("metrics"),
		"camera_transform": str(root.get_camera_3d().global_transform),
		"account_view_open": bool(world.get("account_view_open")),
	}
	root.get_texture().get_image().save_png(output.path_join(stage + ".png"))
	report.samples.append(row)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("RENDER_BUDGET_SAMPLE ", stage, " ", row.median_ms, "ms draws=", row.draw_calls, " tris=", row.primitives)
