extends SceneTree

const Settings = preload("res://scripts/graphics_settings.gd")
const OUTPUT: String = "res://../deliverables/performance-20261020/background-graphics-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0

class TestHud:
	extends Node
	var destination_card: Control
	func is_settings_open() -> bool:
		return false

class TestWorld:
	extends Node3D
	var startup_presented: bool = true
	var entering: bool = false
	var preparing_roam: bool = false
	var preparing_room: bool = false
	var paused: bool = false
	var account_view_open: bool = false
	var account_bridge: Node
	var streaming: Node
	var hud: Node

class TestBridge:
	extends Node
	var active: bool = false
	func is_open() -> bool:
		return active

class TestRoom:
	extends Node3D
	var ready_for_play: bool = true
	var returning: bool = false
	var detail_state: String = "ready"
	var account_bridge: Node
	var ui: Node
	var computer_games: Node
	var interactions: Node
	var native_game_dialog: Window
	var streaming: Node

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool) -> void:
	checks.append({"description": description, "passed": passed})
	if not passed:
		failures += 1
		push_error(description)

func presentation(settings: Node) -> Dictionary:
	var state: Dictionary = settings.call("get_state")
	return {
		"quality": state.quality_profile,
		"msaa": state.applied_msaa,
		"scale": state.scaling_3d_scale,
		"height": state.adaptive_height,
		"physics": Engine.physics_ticks_per_second,
	}

func run() -> void:
	var original_fps: int = Engine.max_fps
	var original_render_loop: bool = RenderingServer.is_render_loop_enabled()
	var original_msaa: Viewport.MSAA = root.msaa_3d
	var original_scale: float = root.scaling_3d_scale
	var path: String = "user://background_graphics_test_%d.cfg" % Time.get_ticks_usec()
	var world: TestWorld = TestWorld.new()
	var hud: TestHud = TestHud.new()
	world.hud = hud
	world.add_child(hud)
	root.add_child(world)
	current_scene = world
	var settings: Node = Settings.new()
	settings.set("settings_path", path)
	world.add_child(settings)
	process_frame.disconnect(settings._sample_render_frame)
	settings.call("set_quality_profile", "balanced")
	settings.call("set_frame_limit", 60)
	var before: Dictionary = presentation(settings)
	var saved_before: String = FileAccess.get_file_as_string(path)
	RenderingServer.set_render_loop_enabled(true)

	check("Ready world participates in adaptation", settings.call("_gameplay_is_active", world))
	world.account_view_open = true
	check("Account view excludes outdoor sampling even before paused is set", not settings.call("_gameplay_is_active", world))
	world.account_view_open = false
	check("Closing account restores outdoor sampling eligibility", settings.call("_gameplay_is_active", world))
	settings.call("_on_focus_exited")
	check("A visible window losing focus keeps rendering and selected FPS", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 60)
	settings.call("_on_focus_entered")

	settings.call("_set_background_hidden", true)
	check("True hidden stops render loop and caps only effective FPS", not RenderingServer.is_render_loop_enabled() and Engine.max_fps == 10 and settings.get("frame_limit") == 60)
	check("Background entry preserves resolution, AA, quality and physics rate", presentation(settings) == before)
	check("Background entry does not write user preferences", FileAccess.get_file_as_string(path) == saved_before)
	settings.call("_set_background_hidden", true)
	settings.call("_set_background_hidden", false)
	check("Repeated hidden events restore the original render loop exactly once", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 60)
	var resume_state: Dictionary = settings.call("get_state")
	var events: Array = resume_state.background_events
	check("Next foreground snapshot retains hidden and resume evidence", resume_state.background_transition_count == 2 and events.size() == 2 and events[0].hidden and not events[0].render_loop_enabled and events[0].applied_max_fps == 10 and events[0].frame_limit == 60 and not events[1].hidden and events[1].render_loop_enabled and events[1].applied_max_fps == 60)
	events[0].hidden = false
	check("Telemetry events cannot mutate the service history", (settings.call("get_state") as Dictionary).background_events[0].hidden)
	check("Resume preserves all presentation settings", presentation(settings) == before)
	check("Resume starts a warmup instead of interpreting a stall as overload", not settings.get("_sample_active") and settings.get("_last_frame_usec") == 0)

	settings.call("_set_background_hidden", true)
	settings.call("set_frame_limit", 90)
	var saved: ConfigFile = ConfigFile.new()
	saved.load(path)
	check("Changing a preference while hidden retains the idle cap", Engine.max_fps == 10 and settings.get("frame_limit") == 90)
	check("Saved FPS remains the user's choice, not the background cap", saved.get_value("graphics", "frame_limit") == 90)
	settings.call("_on_viewport_resized")
	check("Viewport resize does not re-enable rendering while hidden", not RenderingServer.is_render_loop_enabled() and Engine.max_fps == 10)
	settings.call("_set_background_hidden", false)
	check("Resume applies the latest saved FPS choice", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 90)

	var room: TestRoom = TestRoom.new()
	var bridge: TestBridge = TestBridge.new()
	room.account_bridge = bridge
	room.add_child(bridge)
	root.add_child(room)
	current_scene = room
	root.remove_child(world)
	process_frame.connect(settings._sample_render_frame)
	await process_frame
	await process_frame
	check("Detached settings service continues receiving indoor scene frames", settings.get("_active_scene_id") == room.get_instance_id() and settings.get("_last_frame_usec") > 0)
	process_frame.disconnect(settings._sample_render_frame)
	check("Ready indoor room can be sampled", settings.call("_gameplay_is_active", room))
	bridge.active = true
	check("Account bridge focus/open state excludes indoor sampling", not settings.call("_gameplay_is_active", room))
	var account_before: Dictionary = presentation(settings)
	var time_usec: int = Time.get_ticks_usec()
	for index: int in range(120 * 60):
		time_usec += 16667
		settings.call("sample_frame", time_usec, settings.call("_gameplay_is_active", room))
	check("Two minutes in account UI cannot promote adaptive resolution", presentation(settings) == account_before)
	check("Bounded account UI leaves the visible 3D background rendering", RenderingServer.is_render_loop_enabled())
	bridge.active = false
	check("Closing the room account UI restores sampling eligibility", settings.call("_gameplay_is_active", room))

	settings.call("_set_background_hidden", true)
	settings.call("_set_background_hidden", false)
	check("Hidden/resume works while its world is outside SceneTree", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 90)
	RenderingServer.set_render_loop_enabled(false)
	settings.call("_set_background_hidden", true)
	settings.call("_set_background_hidden", false)
	check("Resume respects a render loop disabled by another owner beforehand", not RenderingServer.is_render_loop_enabled())
	RenderingServer.set_render_loop_enabled(true)

	if DisplayServer.get_name() != "headless":
		await check_native_minimize(settings)
		# A real rendered-frame wait proves resume cannot strand frame_post_draw.
		var frame_seen: bool = await await_resumed_frame(settings)
		check("Real renderer emits frame_post_draw after background resume", frame_seen)

	settings.call("_set_background_hidden", true)
	world.free()
	check("Destroying the detached owning world restores render loop and FPS", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 90)
	current_scene = null
	room.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	Engine.max_fps = original_fps
	root.msaa_3d = original_msaa
	root.scaling_3d_scale = original_scale
	RenderingServer.set_render_loop_enabled(original_render_loop)
	var output: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify({
		"engine": Engine.get_version_info(),
		"renderer": DisplayServer.get_name(),
		"checks": checks,
		"failures": failures,
		"real_browser_visibility_event_tested": false,
		"scope": "Godot policy and lifecycle; real browser visibilitychange requires web QA."
	}, "\t"))
	print("BACKGROUND_GRAPHICS_CHECKS ", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)

func check_native_minimize(settings: Node) -> void:
	var previous_mode: DisplayServer.WindowMode = DisplayServer.window_get_mode()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	var deadline: int = Time.get_ticks_msec() + 3000
	while DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_MINIMIZED and Time.get_ticks_msec() < deadline:
		await process_frame
	settings.call("_refresh_visibility")
	check("Real native minimized window activates background protection", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED and settings.get("_background_hidden") and not RenderingServer.is_render_loop_enabled())
	DisplayServer.window_set_mode(previous_mode)
	deadline = Time.get_ticks_msec() + 3000
	while DisplayServer.window_get_mode() != previous_mode and Time.get_ticks_msec() < deadline:
		await process_frame
	settings.call("_refresh_visibility")
	check("Real native window restore resumes rendering and selected FPS", not settings.get("_background_hidden") and RenderingServer.is_render_loop_enabled() and Engine.max_fps == 90)

func await_resumed_frame(settings: Node) -> bool:
	var marker: Dictionary = {"drawn": false}
	var on_frame: Callable = func() -> void: marker.drawn = true
	settings.call("_set_background_hidden", true)
	await create_timer(.1).timeout
	RenderingServer.frame_post_draw.connect(on_frame, CONNECT_ONE_SHOT)
	settings.call("_set_background_hidden", false)
	var deadline: int = Time.get_ticks_msec() + 3000
	while not marker.drawn and Time.get_ticks_msec() < deadline:
		await process_frame
	if RenderingServer.frame_post_draw.is_connected(on_frame):
		RenderingServer.frame_post_draw.disconnect(on_frame)
	return marker.drawn
