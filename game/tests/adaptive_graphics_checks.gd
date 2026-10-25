extends SceneTree

const SettingsScript = preload("res://scripts/graphics_settings.gd")
var failures: int = 0
var checks: int = 0
var simulated_usec: int = 1000000

class TestSettings:
	extends "res://scripts/graphics_settings.gd"
	var observed_frames: int = 0
	func _sample_render_frame() -> void:
		observed_frames += 1
		super._sample_render_frame()

class TestHud:
	extends Node
	var opened: bool = false
	var destination_card: Control
	func is_settings_open() -> bool:
		return opened

class TestWorld:
	extends Node3D
	var startup_presented: bool = true
	var entering: bool = false
	var preparing_roam: bool = false
	var preparing_room: bool = false
	var paused: bool = false
	var hud: Node
	var streaming: Node

class TestStreaming:
	extends Node
	var pending_regions: int = 0
	func metrics() -> Dictionary:
		return {"pending_regions": pending_regions}

class TestRoom:
	extends Node3D
	var ready_for_play: bool = true
	var returning: bool = false
	var detail_state: String = "ready"
	var computer_games: Node
	var interactions: Node
	var native_game_dialog: Window

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error(description + ": " + str(evidence))

func feed(settings: Node, seconds: float, fps: float, active: bool = true) -> void:
	var step_usec: int = int(round(1000000.0 / fps))
	for frame: int in range(int(ceil(seconds * fps))):
		simulated_usec += step_usec
		settings.call("sample_frame", simulated_usec, active)

func height(settings: Node) -> int:
	return int((settings.call("get_state") as Dictionary).adaptive_height)

func restart(settings: Node, limit: int, refresh_hz: float) -> void:
	settings.call("set_quality_profile", "balanced")
	settings.call("set_frame_limit", limit)
	settings.set("_display_refresh_hz", refresh_hz)
	simulated_usec += 1000000
	settings.call("sample_frame", simulated_usec, true)

func run() -> void:
	var original_fps: int = Engine.max_fps
	var physics_ticks: int = Engine.physics_ticks_per_second
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1920, 1080)
	var settings: TestSettings = TestSettings.new()
	var path: String = "user://adaptive_graphics_test_%d.cfg" % Time.get_ticks_usec()
	settings.settings_path = path
	root.add_child(settings)
	process_frame.disconnect(settings._sample_render_frame)
	await process_frame
	for pair: Vector2 in [Vector2(30, 60), Vector2(60, 60), Vector2(90, 60), Vector2(90, 90)]:
		var cap: int = int(pair.x)
		var refresh_hz: float = pair.y
		var paced_fps: float = minf(float(cap), refresh_hz)
		restart(settings, cap, refresh_hz)
		check("Balanced starts at 540p with no MSAA / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) == 540 and root.msaa_3d == Viewport.MSAA_DISABLED and settings.is_low_quality())
		feed(settings, 11.0, paced_fps)
		check("Short stable period never promotes / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) == 540)
		feed(settings, 8.0, paced_fps)
		check("Sustained paced gameplay trials 630p / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) == 630, settings.get_state())
		feed(settings, 22.0, paced_fps)
		check("Stable gameplay reaches bounded 720p / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) == 720 and root.scaling_3d_scale <= 2.0 / 3.0 + 0.0001)
		feed(settings, 15.0, paced_fps * 0.70)
		check("Sustained dropped frames reduce resolution / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) <= 540)
		feed(settings, 25.0, paced_fps)
		check("Failed promotion stays blocked for a minute / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) <= 540)
		feed(settings, 50.0, paced_fps * 0.65)
		check("Long overload stops at 432p / cap %d Hz %.0f" % [cap, refresh_hz], height(settings) == 432)
		check("Adaptation keeps selected FPS and physics / cap %d Hz %.0f" % [cap, refresh_hz], Engine.max_fps == cap and Engine.physics_ticks_per_second == physics_ticks)
	restart(settings, 30, 60.0)
	# Browser rAF callbacks straddling the limiter deadline can produce short
	# and long frame pairs with an average of exactly the requested 30 FPS.
	for pair: int in range(900):
		for interval_usec: int in [16667, 50000]:
			simulated_usec += interval_usec
			settings.sample_frame(simulated_usec, true)
	check("30 FPS browser limiter jitter neither raises nor lowers quality", height(settings) == 540 and settings.get_state().pacing_status == "mixed", settings.get_state())
	feed(settings, 10.0, 20.0)
	check("Real sustained 20 FPS at a 30 FPS cap still lowers quality", height(settings) == 432, settings.get_state())
	restart(settings, 30, 60.0)
	feed(settings, 10.0, 30.0)
	simulated_usec += 1500000
	settings.sample_frame(simulated_usec, true)
	feed(settings, 10.0, 30.0)
	check("An isolated loading stall clears promotion evidence instead of changing resolution", height(settings) == 540)
	feed(settings, 50.0, 15.0, false)
	check("Background and menu samples never lower resolution", height(settings) == 540)
	feed(settings, 10.0, 30.0)
	check("Resuming needs fresh stable samples", height(settings) == 540)
	feed(settings, 8.0, 30.0)
	check("Adaptation resumes after gameplay settles", height(settings) == 630)
	feed(settings, 8.0, 2.0)
	check("Repeated severe foreground stalls below four FPS still reduce resolution", height(settings) == 432)
	restart(settings, 30, 60.0)
	feed(settings, 19.0, 30.0)
	root.size = Vector2i(844, 390)
	await process_frame
	var resized: Dictionary = settings.get_state()
	check("Resize never supersamples a smaller display", root.scaling_3d_scale == 1.0 and resized.internal_3d_pixels == [844, 390], resized)
	root.size = Vector2i(390, 844)
	await process_frame
	resized = settings.get_state()
	check("Portrait resizing caps actual height and keeps aspect ratio", resized.internal_3d_pixels[1] <= 630 and root.scaling_3d_scale <= 1.0, resized)
	for fixed_profile: String in ["mobile", "low", "standard"]:
		settings.set_quality_profile(fixed_profile)
		var fixed_scale: float = root.scaling_3d_scale
		feed(settings, 80.0, 10.0)
		check("Fixed %s profile ignores adaptive load" % fixed_profile, is_equal_approx(root.scaling_3d_scale, fixed_scale))
	settings.set("_mobile_web", true)
	root.size = Vector2i(1920, 1080)
	restart(settings, 30, 60.0)
	check("Mobile balanced starts at its conservative 432p maximum", height(settings) == 432 and settings.get_state().adaptive_max_height == 432 and root.msaa_3d == Viewport.MSAA_DISABLED, settings.get_state())
	feed(settings, 90.0, 30.0)
	check("Stable capped mobile play never inflates rendering past 432p", height(settings) == 432 and settings.get_state().internal_3d_pixels == [768, 432], settings.get_state())
	feed(settings, 6.0, 20.0)
	check("Sustained mobile slowdown reduces the 3D workload to 360p", height(settings) == 360, settings.get_state())
	feed(settings, 30.0, 12.0)
	check("Severe mobile overload can reach the 320p floor", height(settings) == 320, settings.get_state())
	feed(settings, 25.0, 30.0)
	check("Short recovery does not immediately raise mobile load", height(settings) == 320)
	feed(settings, 110.0, 30.0)
	check("Long mobile recovery keeps the reduced session budget instead of reheating", height(settings) == 320 and Engine.max_fps == 30 and Engine.physics_ticks_per_second == physics_ticks, settings.get_state())
	settings.set("_mobile_web", false)
	restart(settings, 30, 60.0)
	var world: TestWorld = TestWorld.new()
	var hud: TestHud = TestHud.new()
	world.hud = hud
	var destinations: Control = Control.new()
	destinations.visible = false
	hud.destination_card = destinations
	hud.add_child(destinations)
	var streaming: TestStreaming = TestStreaming.new()
	world.streaming = streaming
	world.add_child(streaming)
	world.add_child(hud)
	root.add_child(world)
	current_scene = world
	settings._sample_render_frame()
	check("Ready outdoor scene enables sampling", settings.get_state().sampling_gameplay)
	hud.opened = true
	settings._sample_render_frame()
	check("Settings menu suspends sampling", not settings.get_state().sampling_gameplay)
	hud.opened = false
	destinations.visible = true
	settings._sample_render_frame()
	check("Destination menu suspends sampling", not settings.get_state().sampling_gameplay)
	destinations.visible = false
	streaming.pending_regions = 1
	settings._streaming_clock = 0.5
	settings._sample_render_frame()
	check("Pending streaming suspends sampling", not settings.get_state().sampling_gameplay)
	streaming.pending_regions = 0
	settings._streaming_clock = 0.5
	world.preparing_room = true
	settings._sample_render_frame()
	check("Resource preparation suspends sampling", not settings.get_state().sampling_gameplay)
	world.preparing_room = false
	settings._on_focus_exited()
	settings._sample_render_frame()
	check("Focus loss suspends sampling", not settings.get_state().sampling_gameplay)
	settings._on_focus_entered()
	settings._page_visible = false
	settings._sample_render_frame()
	check("Hidden browser document suspends sampling", not settings.get_state().sampling_gameplay)
	settings._page_visible = true
	settings._sample_render_frame()
	check("Visible focused gameplay resumes sampling", settings.get_state().sampling_gameplay)
	var room: TestRoom = TestRoom.new()
	root.add_child(room)
	settings.reparent(world)
	current_scene = null
	root.remove_child(world)
	current_scene = room
	process_frame.connect(settings._sample_render_frame)
	var before: int = settings.observed_frames
	await process_frame
	await process_frame
	check("Detached service still receives frame ticks indoors", settings.observed_frames > before and settings.get_state().sampling_gameplay)
	check("Scene transition restarts a safe 540p trial", height(settings) == 540)
	room.detail_state = "loading"
	await process_frame
	await process_frame
	check("Indoor detail loading suspends adaptation", not settings.get_state().sampling_gameplay)
	room.detail_state = "ready"
	room.returning = true
	await process_frame
	await process_frame
	check("Indoor return transition suspends adaptation", not settings.get_state().sampling_gameplay)
	current_scene = null
	root.add_child(world)
	settings.reparent(root)
	world.free()
	room.free()
	settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Engine.max_fps = original_fps
	print("ADAPTIVE_GRAPHICS_CHECKS ", checks, " failures=", failures)
	quit(1 if failures > 0 else 0)
