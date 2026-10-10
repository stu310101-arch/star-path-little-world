extends Node

# Opt-in runtime measurements; no per-frame JS bridge or world-tree traversal.
const SAMPLE_SECONDS: float = 1.0
var enabled: bool = false
var clock: float = 0.0
var frames: int = 0
var frame_sum: float = 0.0
var worst_frame_ms: float = 0.0
var latest: Dictionary = {}
var frame_samples: Array[float] = []

func _ready() -> void:
	enabled = OS.get_cmdline_user_args().has("--performance")
	if OS.has_feature("web"):
		enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	set_process(enabled)

func _process(delta: float) -> void:
	frames += 1
	frame_sum += delta
	worst_frame_ms = maxf(worst_frame_ms, delta * 1000.0)
	frame_samples.append(delta * 1000.0)
	clock += delta
	if clock < SAMPLE_SECONDS:
		return
	latest = snapshot()
	latest["frame_ms_mean"] = frame_sum * 1000.0 / maxi(frames, 1)
	latest["frame_ms_max"] = worst_frame_ms
	frame_samples.sort()
	latest["frame_ms_p95"] = frame_samples[mini(frame_samples.size() - 1, ceili(frame_samples.size() * 0.95) - 1)]
	var stalls: int = 0
	for value: float in frame_samples:
		if value > 100.0:
			stalls += 1
	latest["frames_over_100_ms"] = stalls
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.planetPerformance = " + JSON.stringify(latest) + ";")
	clock = 0.0
	frames = 0
	frame_sum = 0.0
	worst_frame_ms = 0.0
	frame_samples.clear()

func snapshot() -> Dictionary:
	var world: Node = get_parent()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var buttons: Array[Dictionary] = []
	for node: Node in (world.get("hud") as Node).find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_visible_in_tree():
			var point: Vector2 = button.global_position + button.size * .5
			var clipped: bool = not Rect2(Vector2.ZERO, viewport_size).has_point(point)
			var ancestor: Node = button.get_parent()
			while ancestor != null:
				if ancestor is Control and (ancestor as Control).clip_contents:
					clipped = clipped or not (ancestor as Control).get_global_rect().has_point(point)
				ancestor = ancestor.get_parent()
			var center: Vector2 = point / viewport_size
			buttons.append({"name": str(button.name), "text": button.text, "center": [center.x, center.y], "visible": not clipped})
	var actor: Node3D = world.get("player") as Node3D
	var heading: Vector3 = actor.get("heading") as Vector3
	return {
		"ticks_ms": Time.get_ticks_msec(),
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"overview": world.get("overview"),
		"preparing_roam": world.get("preparing_roam"),
		"avatar": actor.call("get_visual_preparation_state"),
		"animation": {"physics_updates": actor.get("animation_physics_updates"), "pose_samples": actor.get("animation_pose_samples"), "seek_calls": actor.get("animation_seek_calls")},
		"packs": get_node("/root/WebPacks").call("get_status"),
		"nearest_id": world.get("nearest_id"),
		"settings_open": world.get("hud").call("is_settings_open"),
		"destinations_open": (world.get("hud").get("destination_card") as Control).visible,
		"player": {"position": [actor.position.x, actor.position.y, actor.position.z], "heading": [heading.x, heading.y, heading.z], "overview": world.get("overview"), "paused": world.get("paused"), "entering": world.get("entering"), "jump_count": actor.get("jump_count"), "landing_count": actor.get("landing_count")},
		"buttons": buttons,
		"streaming": world.get("streaming").call("metrics"),
		"minimap": world.get("hud").get("minimap").call("metrics"),
		"obstruction": world.get("camera_obstruction").call("stats"),
		"graphics": world.get("hud").get("graphics_settings").call("get_state"),
	}
