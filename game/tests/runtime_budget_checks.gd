extends SceneTree

const Settings = preload("res://scripts/graphics_settings.gd")
const Adaptive = preload("res://tests/adaptive_graphics_checks.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func feed(settings: Node, seconds: float, fps: float, eligible: bool = true) -> void:
	for frame: int in range(ceili(seconds * fps)):
		settings.sample_runtime_pressure(1.0 / fps, eligible)

func run() -> void:
	var original_limit: int = Engine.max_fps
	var physics: int = Engine.physics_ticks_per_second
	root.size = Vector2i(1920,1080)
	root.content_scale_size = Vector2i.ZERO
	var settings: Node = Settings.new()
	var cfg: String = "user://runtime_budget_test_%d.cfg" % Time.get_ticks_usec()
	settings.settings_path = cfg
	root.add_child(settings)
	process_frame.disconnect(settings._sample_render_frame)
	settings.set_quality_profile("standard")
	settings.set_frame_limit(60)
	feed(settings, 15.0, 30.0)
	check("Stable 30 FPS on a slower display does not trigger structural fallback", not settings.is_constrained_runtime())
	settings.sample_runtime_pressure(1.5, true)
	feed(settings, 10.0, 60.0)
	check("Single loading stall never activates the fallback", not settings.is_constrained_runtime())
	feed(settings, 30.0, 5.0, false)
	check("Background/menu stalls cannot be treated as device capacity", not settings.is_constrained_runtime())
	var world: Node3D = Adaptive.TestWorld.new()
	var hud: Node = Adaptive.TestHud.new()
	world.hud = hud
	world.add_child(hud)
	root.add_child(world)
	world.preparing_roam = true
	settings._streaming_busy = true
	check("Streaming preparation qualifies for structural relief but not resolution promotion", settings._gameplay_is_active(world, true) and not settings._gameplay_is_active(world))
	feed(settings, 7.0, 12.0)
	check("Persistent weak-device pacing triggers fallback on desktop standard", settings.is_constrained_runtime() and settings.get_state().runtime_pressure)
	check("Fallback actually caps pixels, MSAA and frame work", root.scaling_3d_scale <= 0.5 and root.msaa_3d == Viewport.MSAA_DISABLED and Engine.max_fps == 30, settings.get_state())
	check("Saved preference and physics stay intact", settings.frame_limit == 60 and Engine.physics_ticks_per_second == physics)
	feed(settings, 90.0, 60.0)
	settings._reset_adaptation(true)
	check("Recovery/scene changes cannot reload the same overwhelming workload", settings.is_constrained_runtime())
	var camera: Camera3D = Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	world.preparing_roam = false
	world.paused = true
	settings._streaming_busy = false
	check("Static reading/modal is eligible for idle saving", settings._idle_budget_eligible(world))
	for frame: int in range(300):
		settings._update_idle_budget(1.0/30.0, true)
	check("Stationary foreground reduces rendered work to 15 FPS", settings.get_state().idle_limited and Engine.max_fps == 15)
	camera.position.x += 0.1
	settings._update_idle_budget(1.0/30.0, true)
	check("Camera movement wakes active pacing immediately", not settings.get_state().idle_limited and Engine.max_fps == 30)
	for frame: int in range(300):
		settings._update_idle_budget(1.0/30.0, true)
	settings.reparent(world)
	root.remove_child(world)
	var input: InputEventKey = InputEventKey.new()
	input.keycode = KEY_W
	input.pressed = true
	root.window_input.emit(input)
	check("Root input wakes settings even when retained outside tree indoors", not settings.get_state().idle_limited and Engine.max_fps == 30)
	root.add_child(world)
	settings.reparent(root)
	settings._set_background_hidden(true, "test")
	check("Hidden page still stops the render loop", not RenderingServer.is_render_loop_enabled() and Engine.max_fps == 10)
	settings._set_background_hidden(false, "test")
	check("Returning restores the protected active limit", RenderingServer.is_render_loop_enabled() and Engine.max_fps == 30)
	world.free()
	settings.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg))
	Engine.max_fps = original_limit
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/low-end-20261021"))
	FileAccess.open("res://../deliverables/low-end-20261021/runtime-budget-checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("RUNTIME_BUDGET_CHECKS ",checks.size()," failures=",failures)
	quit(1 if failures else 0)
