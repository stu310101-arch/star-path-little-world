extends "res://tests/render_submission_probe.gd"

## Native/Web throughput diagnostic; native also captures pixel parity images.
## Static 3D scene, no changes to product settings, no geometry reductions.
var minimap: Control
var player: Node3D
var origin_transform: Transform3D
var origin_heading: Vector3
var origin_map_frame: Dictionary
var motion_seconds: float = 4.0

func run() -> void:
	tree = get_tree()
	viewport = tree.root
	if OS.get_cmdline_user_args().has("--parse-only"):
		tree.quit()
		return
	if DisplayServer.get_name() == "headless":
		push_error("This diagnostic requires a real renderer.")
		tree.quit(1)
		return
	output = ProjectSettings.globalize_path("res://../deliverables/render-budget/" + option("label", "minimap-cache-native"))
	if not OS.has_feature("web"):
		DirAccess.make_dir_recursive_absolute(output)
	sample_ms = 1500
	motion_seconds = float(option("motion-seconds", "4"))
	report = {"errors": [], "runs": [], "captures": [], "status": "initializing",
		"method": "Same-process Compatibility cache A/B/A, world simulation frozen. A=direct original draw calls, B=texture cache. Full 3D scale1/MSAA2x. Moving test repeats the same elapsed-time player/map path with standard-profile 20Hz refresh; body physics disabled.",
		"web": OS.has_feature("web"),
		"limits": "Native desktop throughput and synthetic 1.5x logical scale are not phone/device-DPI performance. Browser VSync may cap frame cadence. Root/subviewport timers can lag draw/rebuild counters; frame-time distributions include the whole frame. A zero GPU timer is unavailable."}
	viewport.size = Vector2i(1280, 800)
	viewport.gui_disable_input = true
	if not OS.has_feature("web"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	viewport.add_child(world)
	tree.current_scene = world
	settings = world.get("graphics_settings") as Node
	settings.set("settings_path", "user://render_submission_probe.cfg")
	var adaptive: Callable = Callable(settings, "_sample_render_frame")
	if tree.process_frame.is_connected(adaptive):
		tree.process_frame.disconnect(adaptive)
	settings.call("set_quality_profile", "standard")
	settings.call("set_msaa_enabled", true)
	settings.call("set_frame_limit", 90)
	pin_pixels()
	world.set_process_input(false)
	world.set_process_unhandled_input(false)
	world.call("setup_water_review", 0, false)
	if not await Fixture.wait_roaming(world, tree):
		report.errors.append("Roaming preparation failed")
		finish()
		return
	await tree.create_timer(1.5).timeout
	world.process_mode = Node.PROCESS_MODE_DISABLED
	pin_pixels()
	player = world.get("player") as Node3D
	minimap = (world.get("hud") as Node).get("minimap") as Control
	if not minimap.has_method("set_texture_cache_enabled"):
		report.errors.append("Minimap cache API unavailable")
		finish()
		return
	var cache_viewport: SubViewport = minimap.get("_cache_viewport") as SubViewport
	RenderingServer.viewport_set_measure_render_time(cache_viewport.get_viewport_rid(), true)
	origin_transform = player.global_transform
	origin_heading = player.get("heading") as Vector3
	origin_map_frame = {"centre_up": minimap.get("centre_up"), "map_forward": minimap.get("map_forward"), "map_right": minimap.get("map_right")}
	report.gpu = RenderingServer.get_video_adapter_name()
	report.renderer = RenderingServer.get_current_rendering_method()
	for moving: bool in [false, true]:
		var row: Dictionary = {"mode": "moving" if moving else "stationary", "phases": []}
		for phase_label: String in ["direct_A0", "cache_B", "direct_A1"]:
			reset_path()
			minimap.call("set_texture_cache_enabled", phase_label == "cache_B")
			minimap.call("refresh")
			await tree.create_timer(.35).timeout
			row.phases.append(await cache_sample(phase_label, moving))
		report.runs.append(row)
		save_report()
	if OS.has_feature("web"):
		finish()
		return
	reset_path()
	for layout: Dictionary in [
		{"name": "native", "physical": Vector2i(1280, 800), "logical": Vector2i(1280, 800)},
		{"name": "resized", "physical": Vector2i(1440, 900), "logical": Vector2i(1440, 900)},
		{"name": "hidpi_1_5", "physical": Vector2i(1920, 1200), "logical": Vector2i(1280, 800)},
	]:
		viewport.size = layout.physical
		viewport.content_scale_size = layout.logical
		viewport.scaling_3d_scale = 1.0
		viewport.msaa_3d = Viewport.MSAA_2X
		await tree.process_frame
		await tree.process_frame
		for enabled: bool in [false, true]:
			minimap.call("set_texture_cache_enabled", enabled)
			minimap.call("refresh")
			await tree.process_frame
			await tree.process_frame
			await tree.process_frame
			await RenderingServer.frame_post_draw
			var image: Image = viewport.get_texture().get_image()
			var transform: Transform2D = viewport.get_final_transform() * minimap.get_global_transform_with_canvas()
			var rectangle: Rect2i = Rect2i(Rect2(transform.origin.floor(), ((transform * minimap.size).ceil() - transform.origin.floor()))).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
			var label: String = str(layout.name) + ("_cached" if enabled else "_direct")
			image.get_region(rectangle).save_png(output.path_join(label + ".png"))
			report.captures.append({"name": label, "file": label + ".png", "rect": [rectangle.position.x, rectangle.position.y, rectangle.size.x, rectangle.size.y],
				"physical": [viewport.size.x, viewport.size.y], "logical": [viewport.content_scale_size.x, viewport.content_scale_size.y],
				"physical_transform": str(transform), "cache": minimap.call("metrics"), "msaa3d": viewport.msaa_3d, "scale3d": viewport.scaling_3d_scale})
			save_report()
	finish()

func reset_path() -> void:
	player.global_transform = origin_transform
	player.set("heading", origin_heading)
	for key: String in origin_map_frame:
		minimap.set(key, origin_map_frame[key])
	minimap.set("_cartography_dirty", true)
	minimap.call("refresh")

func cache_sample(label: String, moving: bool) -> Dictionary:
	var values: Dictionary = {"frame": [], "gpu": [], "render_cpu": [], "draws": [], "primitives": [], "map_refresh_cpu_us": [], "redraw_frame": [], "steady_frame": []}
	var foreground_start: Dictionary = browser_foreground()
	var stalled_frames: int = 0
	var before: Dictionary = minimap.call("metrics")
	var previous_rebuilds: int = int(before.texture_cache_rebuilds)
	var previous_map_draws: int = int(before.map_draws)
	var update_frames: Array[Dictionary] = []
	var started_usec: int = Time.get_ticks_usec()
	var duration_ms: int = int(motion_seconds * 1000.0) if moving else sample_ms
	var deadline: int = Time.get_ticks_msec() + duration_ms
	var previous: int = Time.get_ticks_usec()
	var next_refresh_seconds: float = 0.0
	var refresh_count: int = 0
	var index: int = 0
	var initial_normal: Vector3 = origin_transform.origin.normalized()
	var tangent: Vector3 = Vector3.UP.cross(initial_normal).normalized()
	if tangent.length_squared() < .5:
		tangent = Vector3.RIGHT.cross(initial_normal).normalized()
	while Time.get_ticks_msec() < deadline:
		var refresh_usec: int = 0
		var elapsed: float = float(Time.get_ticks_usec() - started_usec) / 1000000.0
		if moving and elapsed >= next_refresh_seconds:
			# Same four-second path and 20Hz production cadence independent of
			# uncapped FPS. A faster cache must not move the player faster.
			while next_refresh_seconds <= elapsed:
				next_refresh_seconds += .05
			player.global_position = (initial_normal + tangent * sin(elapsed * 1.8) * .02).normalized() * origin_transform.origin.length()
			var started: int = Time.get_ticks_usec()
			minimap.call("refresh")
			refresh_usec = Time.get_ticks_usec() - started
			refresh_count += 1
		await tree.process_frame
		var now: int = Time.get_ticks_usec()
		values.frame.append(float(now - previous) / 1000.0)
		if float(values.frame[-1]) > 250.0:
			stalled_frames += 1
		previous = now
		values.gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(viewport.get_viewport_rid()))
		values.render_cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(viewport.get_viewport_rid()))
		values.draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		values.primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if refresh_usec > 0:
			values.map_refresh_cpu_us.append(refresh_usec)
		var metrics: Dictionary = minimap.call("metrics")
		var rebuilds: int = int(metrics.texture_cache_rebuilds)
		var map_draws: int = int(metrics.map_draws)
		if map_draws != previous_map_draws:
			var cache_viewport: SubViewport = minimap.get("_cache_viewport") as SubViewport
			update_frames.append({"frame": index, "frame_ms": values.frame[-1], "last_map_draw_ms": metrics.last_draw_ms, "root_render_cpu_ms": values.render_cpu[-1], "root_gpu_ms": values.gpu[-1],
				"cache_rebuilt": rebuilds != previous_rebuilds,
				"cache_render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(cache_viewport.get_viewport_rid()),
				"cache_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(cache_viewport.get_viewport_rid()),
				"timer_scope": "Viewport timers may lag the observed rebuild counter. Do not sum a stale disabled-subviewport timer into every frame."})
			values.redraw_frame.append(values.frame[-1])
		else:
			values.steady_frame.append(values.frame[-1])
		previous_rebuilds = rebuilds
		previous_map_draws = map_draws
		index += 1
	var row: Dictionary = {"phase": label, "moving": moving, "frames": index, "duration_seconds": float(Time.get_ticks_usec() - started_usec) / 1000000.0, "refresh_calls": refresh_count, "refresh_cadence_seconds": .05 if moving else null,
		"cache_before": before, "cache_after": minimap.call("metrics"), "cartography_update_frames": update_frames,
		"viewport": [viewport.size.x, viewport.size.y], "scale": viewport.scaling_3d_scale, "msaa": viewport.msaa_3d,
		"foreground_start": foreground_start, "foreground_end": browser_foreground(), "frames_over_250ms": stalled_frames, "invalid_reasons": []}
	if OS.has_feature("web"):
		if bool(foreground_start.get("hidden", true)) or bool(row.foreground_end.get("hidden", true)):
			row.invalid_reasons.append("browser_document_hidden")
		if not bool(foreground_start.get("focused", false)) or not bool(row.foreground_end.get("focused", false)):
			row.invalid_reasons.append("browser_document_not_focused")
		if stalled_frames > 0:
			row.invalid_reasons.append("frames_over_250ms_possible_throttling_or_stall")
	row.timing_valid = row.invalid_reasons.is_empty()
	for key: String in values:
		var samples: Array = values[key]
		samples.sort()
		row[key + "_median"] = samples[samples.size() / 2] if not samples.is_empty() else null
		row[key + "_p95"] = samples[mini(samples.size() - 1, ceili(samples.size() * .95) - 1)] if not samples.is_empty() else null
	row.gpu_timer_available = float(row.gpu_median) > 0.0
	if not row.gpu_timer_available:
		row.gpu_median = null
		row.gpu_p95 = null
	print("MAP_CACHE_PHASE ", label, " moving=", moving, " frame=", row.frame_median, " p95=", row.frame_p95, " draws=", row.draws_median, " updates=", update_frames.size())
	return row
