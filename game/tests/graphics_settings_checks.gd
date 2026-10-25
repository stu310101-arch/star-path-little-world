extends SceneTree

const SettingsScript = preload("res://scripts/graphics_settings.gd")
const OUTPUT: String = "res://../deliverables/performance/graphics-settings-tests.json"
var checks: Array[Dictionary] = []
var failures: int = 0

class HudHarness:
	extends "res://scripts/world_hud.gd"
	func _ready() -> void:
		pass

class TestActor:
	extends Node
	var controls_enabled: bool = true
	var jump_cancels: int = 0
	func cancel_jump_input() -> void:
		jump_cancels += 1

class TestWorld:
	extends Node3D
	var player: Node
	var overview: bool = false
	var paused: bool = false
	var entering: bool = false
	var preparing_roam: bool = false
	var preparing_room: bool = false
	var dragging_view: bool = true
	func finish_view_drag() -> void:
		dragging_view = false

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": description, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(description + ": " + str(evidence))

func new_settings(path: String) -> Node:
	var settings: Node = SettingsScript.new() as Node
	settings.set("settings_path", path)
	root.add_child(settings)
	return settings

func run() -> void:
	var original_fps: int = Engine.max_fps
	var original_msaa: Viewport.MSAA = root.msaa_3d
	var physics_ticks: int = Engine.physics_ticks_per_second
	var test_path: String = "user://graphics_settings_test_%d.cfg" % Time.get_ticks_usec()
	var settings: Node = new_settings(test_path)
	var expected_native_profile: String = "low" if OS.has_feature("low_end") else "standard"
	var expected_native_msaa: Viewport.MSAA = Viewport.MSAA_DISABLED if OS.has_feature("low_end") else Viewport.MSAA_2X
	check("Fresh native settings use standard with AA; low-end export keeps its low preset", settings.get("quality_profile") == expected_native_profile and root.msaa_3d == expected_native_msaa and Engine.max_fps == 30, settings.call("get_state"))
	check("Fresh mobile web uses adaptive balanced at 30 FPS", SettingsScript.default_quality_profile(true) == "balanced" and SettingsScript.default_frame_limit(true) == 30)
	var mobile_path: String = "user://mobile_graphics_settings_test_%d.cfg" % Time.get_ticks_usec()
	var legacy_mobile: ConfigFile = ConfigFile.new()
	legacy_mobile.set_value("graphics", "quality_profile", "standard")
	legacy_mobile.set_value("graphics", "frame_limit", 90)
	legacy_mobile.set_value("graphics", "msaa_enabled", true)
	legacy_mobile.save(mobile_path)
	var mobile_settings: Node = new_settings(mobile_path)
	mobile_settings.set("_mobile_web", true)
	mobile_settings.call("load_settings")
	mobile_settings.call("_reset_adaptation", true)
	mobile_settings.call("apply_settings")
	var migrated: Dictionary = mobile_settings.call("get_state")
	check("Legacy mobile preferences migrate once to 432p / 30 FPS without AA", migrated.quality_profile == "balanced" and migrated.adaptive_height == 432 and migrated.adaptive_max_height == 432 and migrated.frame_limit == 30 and not migrated.msaa_enabled and migrated.mobile_performance_profile, migrated)
	var saved_mobile: ConfigFile = ConfigFile.new()
	saved_mobile.load(mobile_path)
	check("Mobile migration is persisted so later choices are retained", saved_mobile.get_value("graphics", "mobile_policy_version", 0) == SettingsScript.MOBILE_POLICY_VERSION)
	mobile_settings.call("set_quality_profile", "standard")
	mobile_settings.call("set_frame_limit", 60)
	mobile_settings.call("load_settings")
	mobile_settings.call("apply_settings")
	var deliberate: Dictionary = mobile_settings.call("get_state")
	check("New deliberate mobile quality and FPS overrides survive reload", deliberate.quality_profile == "standard" and deliberate.frame_limit == 60 and deliberate.msaa_enabled and not deliberate.mobile_performance_profile, deliberate)
	mobile_settings.call("restore_defaults")
	var reset_mobile: Dictionary = mobile_settings.call("get_state")
	check("Restoring mobile defaults reapplies the safe baseline", reset_mobile.quality_profile == "balanced" and reset_mobile.adaptive_height == 432 and reset_mobile.frame_limit == 30 and reset_mobile.mobile_performance_profile, reset_mobile)
	mobile_settings.call("set_quality_profile", "mobile")
	mobile_settings.call("set_frame_limit", 90)
	var fixed_mobile: Dictionary = mobile_settings.call("get_state")
	check("Fixed mobile quality also respects the 432p budget", fixed_mobile.internal_3d_pixels[1] <= 432, fixed_mobile)
	check("Mobile stores the 90 FPS preference while applying the 30 FPS budget", fixed_mobile.frame_limit == 90 and fixed_mobile.applied_max_fps == 30 and fixed_mobile.constrained_runtime, fixed_mobile)
	mobile_settings.call("load_settings")
	mobile_settings.call("apply_settings")
	var reloaded_mobile: Dictionary = mobile_settings.call("get_state")
	check("Reload retains mobile preference and effective budget separately", reloaded_mobile.frame_limit == 90 and reloaded_mobile.applied_max_fps == 30, reloaded_mobile)
	mobile_settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(mobile_path))
	settings.call("apply_settings")
	var scale_cases: Array[Dictionary] = [
		{"size": Vector2(640, 360), "expected": 1.0},
		{"size": Vector2(1280, 800), "expected": 1.0},
		{"size": Vector2(1366, 768), "expected": 1.0},
		{"size": Vector2(1599, 899), "expected": 1.0},
		{"size": Vector2(1600, 900), "expected": 0.8},
		{"size": Vector2(1601, 901), "expected": 720.0 / 901.0},
		{"size": Vector2(1920, 1080), "expected": 2.0 / 3.0},
		{"size": Vector2(0, 1080), "expected": 1.0},
	]
	for scale_case: Dictionary in scale_cases:
		var render_size: Vector2 = scale_case.size as Vector2
		var expected_scale: float = float(scale_case.expected)
		var actual_scale: float = SettingsScript.low_render_scale(render_size)
		check("Low profile scaling policy at %s" % str(render_size), is_equal_approx(actual_scale, expected_scale), {"expected": expected_scale, "actual": actual_scale})
	# Keep the production canvas_items stretch enabled: the former fixture only
	# used an unstretched root and missed the double-applied texture stretch.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1440, 900)
	root.size = Vector2i(1280, 800)
	for frame: int in range(4):
		await process_frame
	for repeat: int in range(3):
		settings.call("apply_settings")
	var physical_state: Dictionary = settings.call("get_state")
	check("Stretched 1280x800 canvas keeps native 3D and UI instead of marginal scaling", physical_state.ui_pixels == [1280, 800] and physical_state.internal_3d_pixels == [1280, 800] and root.scaling_3d_scale == 1.0, physical_state)
	settings.call("set_quality_profile", "standard")
	check("Standard profile restores original 3D scale and AA without raising the frame cap", root.scaling_3d_scale == 1.0 and root.msaa_3d == Viewport.MSAA_2X and Engine.max_fps == 30)
	for limit: int in [30, 60, 90]:
		settings.call("set_frame_limit", limit)
		check("Frame limit applies %d without changing physics" % limit, Engine.max_fps == limit and Engine.physics_ticks_per_second == physics_ticks)
		for profile: String in ["mobile", "balanced", "low", "standard"]:
			var expected_applied: int = mini(limit, 30) if profile == "mobile" else limit
			settings.call("set_quality_profile", profile)
			var switched: Dictionary = settings.call("get_state")
			check("Switching to %s preserves %d FPS preference and applies its runtime budget" % [profile, limit], switched.quality_profile == profile and switched.frame_limit == limit and Engine.max_fps == expected_applied and switched.applied_max_fps == expected_applied and Engine.physics_ticks_per_second == physics_ticks, switched)
			settings.free()
			settings = new_settings(test_path)
			var restored: Dictionary = settings.call("get_state")
			check("Saved %s / %d FPS survives reconstruction with its effective budget" % [profile, limit], restored.quality_profile == profile and restored.frame_limit == limit and Engine.max_fps == expected_applied and restored.applied_max_fps == expected_applied and restored.msaa_enabled == (profile == "standard"), restored)
	settings.call("set_msaa_enabled", false)
	check("MSAA can be disabled on live viewport", root.msaa_3d == Viewport.MSAA_DISABLED)
	settings.free()
	settings = new_settings(test_path)
	check("Saved 90 FPS and MSAA off survive service reconstruction", Engine.max_fps == 90 and root.msaa_3d == Viewport.MSAA_DISABLED)
	settings.call("set_frame_limit", 0)
	settings.call("set_frame_limit", 120)
	check("Unsupported runtime frame limits are rejected", Engine.max_fps == 90)
	settings.free()
	var invalid: ConfigFile = ConfigFile.new()
	invalid.set_value("graphics", "msaa_enabled", "false")
	invalid.set_value("graphics", "frame_limit", 60.0)
	invalid.set_value("graphics", "quality_profile", "low")
	invalid.save(test_path)
	settings = new_settings(test_path)
	check("Malformed AA inherits the saved low profile and malformed FPS falls back independently", root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 30)
	settings.free()
	invalid.set_value("graphics", "quality_profile", "standard")
	invalid.save(test_path)
	settings = new_settings(test_path)
	check("Malformed AA inherits the saved standard profile", root.msaa_3d == Viewport.MSAA_2X and Engine.max_fps == 30)
	settings.free()
	invalid.erase_section_key("graphics", "msaa_enabled")
	invalid.save(test_path)
	settings = new_settings(test_path)
	check("Missing AA inherits the saved standard profile", root.msaa_3d == Viewport.MSAA_2X and Engine.max_fps == 30)
	settings.free()
	invalid.set_value("graphics", "msaa_enabled", false)
	invalid.set_value("graphics", "frame_limit", 144)
	invalid.save(test_path)
	settings = new_settings(test_path)
	check("Invalid stored limit falls back independently of valid AA choice", root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 30)
	settings.call("restore_defaults")
	check("Restore defaults applies and saves the native preset successfully", root.msaa_3d == expected_native_msaa and Engine.max_fps == 30 and settings.get("quality_profile") == expected_native_profile and int(settings.get("settings_error")) == OK)
	var world: TestWorld = TestWorld.new()
	var actor: TestActor = TestActor.new()
	world.player = actor
	world.add_child(actor)
	root.add_child(world)
	var hud: HudHarness = HudHarness.new()
	hud.world = world
	hud.graphics_settings = settings
	hud.settings_button = hud.button("畫面設定")
	hud.settings_button.focus_mode = Control.FOCUS_ALL
	hud.destination_card = PanelContainer.new()
	hud.destination_toggle = hud.button("選擇目的地")
	root.add_child(hud)
	var screen: Control = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(screen)
	screen.add_child(hud.settings_button)
	screen.add_child(hud.destination_card)
	screen.add_child(hud.destination_toggle)
	hud.call("_build_graphics_settings", screen)
	hud.open_graphics_settings()
	check("Open settings cancels drag/jump and disables movement", hud.is_settings_open() and not world.dragging_view and not actor.controls_enabled and actor.jump_cancels == 1)
	for size_value: Vector2i in [Vector2i(1280, 800), Vector2i(390, 844), Vector2i(844, 390)]:
		root.content_scale_size = Vector2i.ZERO
		root.size = size_value
		hud.call("_resize_graphics_settings")
		for frame: int in range(4):
			await process_frame
		var viewport_rect: Rect2 = root.get_visible_rect()
		var panel_rect: Rect2 = hud.settings_panel.get_global_rect()
		check("Settings panel stays within %dx%d viewport" % [size_value.x, size_value.y], viewport_rect.encloses(panel_rect), {"viewport": str(viewport_rect), "panel": str(panel_rect)})
		var toggle_rect: Rect2 = hud.msaa_button.get_global_rect()
		check("MSAA toggle fits panel width at %dx%d" % [size_value.x, size_value.y], toggle_rect.position.x >= panel_rect.position.x and toggle_rect.end.x <= panel_rect.end.x, str(toggle_rect))
		var close_button: Button = hud.settings_panel.find_child("CloseGraphicsSettings", true, false) as Button
		var close_rect: Rect2 = close_button.get_global_rect()
		check("Close action remains visible outside scroll area at %dx%d" % [size_value.x, size_value.y], viewport_rect.encloses(close_rect) and close_rect.position.y >= hud.settings_scroll.get_global_rect().end.y, str(close_rect))
		var last_end: float = -1.0
		var separated: bool = true
		for choice: Button in hud.frame_buttons:
			var rect: Rect2 = choice.get_global_rect()
			separated = separated and rect.position.x > last_end and rect.end.x <= panel_rect.end.x
			last_end = rect.end.x
		check("Frame choices do not overlap at %dx%d" % [size_value.x, size_value.y], separated)
		var quality_fit: bool = hud.quality_buttons.size() == 4
		for first: int in range(hud.quality_buttons.size()):
			var first_rect: Rect2 = hud.quality_buttons[first].get_global_rect()
			quality_fit = quality_fit and first_rect.position.x >= panel_rect.position.x and first_rect.end.x <= panel_rect.end.x
			for second: int in range(first + 1, hud.quality_buttons.size()):
				quality_fit = quality_fit and not first_rect.intersects(hud.quality_buttons[second].get_global_rect())
		check("Four quality choices fit without overlap at %dx%d" % [size_value.x, size_value.y], quality_fit)
	check("Settings report actual resolution and recent gameplay pacing", "目前 3D" in hud.settings_performance.text and "最近遊玩" in hud.settings_performance.text)
	hud.frame_buttons[0].pressed.emit()
	check("30 FPS UI button applies its own value", Engine.max_fps == 30 and hud.frame_buttons[0].button_pressed and not hud.frame_buttons[2].button_pressed)
	hud.frame_buttons[2].pressed.emit()
	check("90 FPS UI button applies its own value", Engine.max_fps == 90 and hud.frame_buttons[2].button_pressed and not hud.frame_buttons[0].button_pressed)
	for choice: Button in hud.quality_buttons:
		choice.pressed.emit()
		var expected_applied: int = 30 if str(choice.get_meta("quality_profile")) == "mobile" else 90
		check("%s UI retains the 90 FPS preference while displaying the applied budget" % choice.name, Engine.max_fps == expected_applied and hud.frame_buttons[2].button_pressed and not hud.frame_buttons[0].button_pressed and str(settings.get("quality_profile")) == str(choice.get_meta("quality_profile")) and ("目前實際上限：%d FPS（偏好 90）" % expected_applied) in hud.settings_performance.text, hud.settings_performance.text)
	settings.set("_runtime_pressure", true)
	settings.call("apply_settings")
	settings.emit_signal("state_changed")
	check("Runtime protection keeps preferred 90 selected and explains the actual 30 FPS cap", Engine.max_fps == 30 and hud.frame_buttons[2].button_pressed and "目前實際上限：30 FPS（偏好 90）" in hud.settings_performance.text and "已啟用效能保護" in hud.settings_performance.text, hud.settings_performance.text)
	check("MSAA label distinguishes the saved preference from temporary protection", bool(settings.get("msaa_enabled")) and root.msaa_3d == Viewport.MSAA_DISABLED and hud.msaa_button.text == "MSAA：偏好開啟（目前省電關閉）")
	settings.set("_idle_limited", true)
	settings.call("_apply_frame_limit")
	hud.call("_refresh_graphics_performance", settings.call("get_state"))
	check("Idle display reports 15 FPS separately from the preferred 90", Engine.max_fps == 15 and "目前實際上限：15 FPS（偏好 90）" in hud.settings_performance.text and "閒置省電" in hud.settings_performance.text, hud.settings_performance.text)
	settings.call("note_activity")
	check("Activity exits idle while retaining the protective 30 FPS cap", Engine.max_fps == 30 and settings.get("frame_limit") == 90)
	settings.set("_runtime_pressure", false)
	settings.call("apply_settings")
	settings.emit_signal("state_changed")
	hud.msaa_button.button_pressed = false
	hud.msaa_button.pressed.emit()
	check("MSAA UI toggle updates viewport and label", root.msaa_3d == Viewport.MSAA_DISABLED and hud.msaa_button.text == "MSAA：關閉")
	var escape: InputEventAction = InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	root.push_input(escape)
	check("Escape closes settings and restores roaming controls", not hud.is_settings_open() and actor.controls_enabled)
	check("Closing settings releases GUI focus for jump and view keys", root.gui_get_focus_owner() == null)
	world.overview = true
	actor.controls_enabled = false
	hud.open_graphics_settings()
	hud.close_graphics_settings()
	check("Closing in overview never enables movement", not actor.controls_enabled)
	world.overview = false
	world.paused = true
	hud.open_graphics_settings()
	hud.close_graphics_settings()
	check("Closing while an interaction is paused preserves disabled controls", not actor.controls_enabled)
	world.entering = true
	hud.open_graphics_settings()
	check("Opening during an entry transition is ignored", not hud.is_settings_open())
	settings.set("settings_path", "user://missing_graphics_settings_directory/blocked.cfg")
	settings.call("set_frame_limit", 30)
	check("A save failure still applies settings and explains failure in UI", Engine.max_fps == 30 and int(settings.get("settings_error")) != OK and "無法儲存" in hud.settings_status.text)
	# Indoor transitions temporarily detach the complete world from the same
	# root Window. Applied render state must survive that tree transition.
	settings.reparent(world)
	hud.reparent(world)
	root.remove_child(world)
	check("Shared root viewport retains settings while world is suspended indoors", root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 30)
	hud.settings_panel.custom_minimum_size.x = 0.0
	root.size_changed.emit()
	check("Detached HUD handles viewport resize without a scene-tree viewport lookup", hud.settings_panel.custom_minimum_size.x > 0.0)
	root.add_child(world)
	settings.reparent(root)
	hud.reparent(root)
	check("Returning the world retains the selected rendering values", root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 30)
	world.entering = false
	world.paused = false
	if OS.get_cmdline_user_args().has("--capture-settings"):
		settings.set("settings_path", test_path)
		settings.call("restore_defaults")
		hud.open_graphics_settings()
		for capture_size: Vector2i in [Vector2i(1280, 800), Vector2i(390, 844), Vector2i(844, 390)]:
			root.size = capture_size
			hud.call("_resize_graphics_settings")
			for frame: int in range(4):
				await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../deliverables/performance/graphics-settings-%dx%d.png" % [capture_size.x, capture_size.y])
	var output_path: String = ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	output.store_string(JSON.stringify({"engine": Engine.get_version_info(), "failures": failures, "checks": checks}, "\t"))
	output.close()
	hud.free()
	world.free()
	settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))
	Engine.max_fps = original_fps
	root.msaa_3d = original_msaa
	print("GRAPHICS_SETTINGS_CHECKS ", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
