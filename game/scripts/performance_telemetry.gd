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
var _last_frame_usec: int = 0
var _foreground: bool = true
var _browser_document: JavaScriptObject
var _browser_window: JavaScriptObject
var _browser_state_callback: JavaScriptObject
var _renderer_metadata: Dictionary = {}

func renderer_metadata() -> Dictionary:
	# Static adapter queries run once, only when opt-in telemetry takes a snapshot.
	# Web vendors may mask adapter names; an unavailable name is not proof of a
	# different GPU. No WebGL readback or per-frame JS is needed for this report.
	if _renderer_metadata.is_empty():
		_renderer_metadata = {
			"method": RenderingServer.get_current_rendering_method(),
			"driver": RenderingServer.get_current_rendering_driver_name(),
			"adapter_name": RenderingServer.get_video_adapter_name(),
			"adapter_vendor": RenderingServer.get_video_adapter_vendor(),
			"adapter_api_version": RenderingServer.get_video_adapter_api_version(),
			"adapter_type": RenderingServer.get_video_adapter_type(),
			"display_server": DisplayServer.get_name(),
			"os": OS.get_name(),
			"web": OS.has_feature("web"),
			"debug_build": OS.is_debug_build(),
			"adapter_identity_scope": "engine_reported; web privacy masking and headless empty names are possible",
		}
	return _renderer_metadata.duplicate()

func _enter_tree() -> void:
	_reset_measurement()
	# The outdoor world is detached while indoors, then reattached without
	# another _ready(). Do not count that interval as a slow outdoor frame.
	if enabled:
		_connect_browser_events()

func _ready() -> void:
	enabled = OS.get_cmdline_user_args().has("--performance")
	if OS.has_feature("web"):
		enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	set_process(enabled)
	if enabled:
		_connect_browser_events()

func _exit_tree() -> void:
	_reset_measurement()
	if not latest.is_empty():
		latest["frame_sample_valid"] = false
		latest["sampling_foreground"] = false
		_publish()
	if _browser_state_callback != null:
		_browser_document.removeEventListener("visibilitychange", _browser_state_callback)
		for event_name: String in ["focus", "blur", "pageshow", "pagehide"]:
			_browser_window.removeEventListener(event_name, _browser_state_callback)
	_browser_state_callback = null
	_browser_document = null
	_browser_window = null

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_foreground(false)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_set_foreground(not bool(_browser_document.hidden) if _browser_document != null else true)

func _connect_browser_events() -> void:
	if not OS.has_feature("web") or _browser_state_callback != null:
		return
	_browser_document = JavaScriptBridge.get_interface("document")
	_browser_window = JavaScriptBridge.get_interface("window")
	_browser_state_callback = JavaScriptBridge.create_callback(_on_browser_state_changed)
	_browser_document.addEventListener("visibilitychange", _browser_state_callback)
	for event_name: String in ["focus", "blur", "pageshow", "pagehide"]:
		_browser_window.addEventListener(event_name, _browser_state_callback)
	_on_browser_state_changed([])

func _on_browser_state_changed(arguments: Array) -> void:
	var event_name: String = str(arguments[0].type) if not arguments.is_empty() else ""
	_set_foreground(event_name not in ["blur", "pagehide"] and not bool(_browser_document.hidden) and bool(_browser_document.hasFocus()))

func _set_foreground(value: bool) -> void:
	_foreground = value
	_reset_measurement()
	if not latest.is_empty():
		latest["frame_sample_valid"] = false
		latest["sampling_foreground"] = value
		_publish()

func _reset_measurement() -> void:
	_last_frame_usec = 0
	clock = 0.0
	frames = 0
	frame_sum = 0.0
	worst_frame_ms = 0.0
	frame_samples.clear()

func _process(_delta: float) -> void:
	_record_frame(Time.get_ticks_usec())

func _record_frame(now_usec: int) -> void:
	if not _foreground:
		return
	if _last_frame_usec == 0:
		_last_frame_usec = now_usec
		return
	# _process(delta) can be smoothed and capped by Godot. A monotonic clock
	# retains real loading stalls and measures delivered frame intervals.
	var elapsed: float = float(now_usec - _last_frame_usec) / 1000000.0
	_last_frame_usec = now_usec
	if elapsed <= 0.0:
		return
	frames += 1
	frame_sum += elapsed
	worst_frame_ms = maxf(worst_frame_ms, elapsed * 1000.0)
	frame_samples.append(elapsed * 1000.0)
	clock += elapsed
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
	latest["frame_sample_valid"] = true
	latest["sampling_foreground"] = true
	latest["frame_intervals"] = frames
	latest["frame_sample_window_ms"] = clock * 1000.0
	latest["frame_time_source"] = "monotonic_clock_foreground_intervals"
	_publish()
	_reset_measurement()
	_last_frame_usec = now_usec

func _publish() -> void:
	if enabled and OS.has_feature("web"):
		JavaScriptBridge.eval("window.planetPerformance = " + JSON.stringify(latest) + "; document.getElementById('canvas')?.setAttribute('data-performance', JSON.stringify(window.planetPerformance));")

func snapshot() -> Dictionary:
	var world: Node = get_parent()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var buttons: Array[Dictionary] = []
	for node: Node in (world.get("hud") as Node).find_children("*", "Button", true, false):
		var button: Button = node as Button
		# The form has dedicated geometry-only diagnostics. Generic button text
		# could otherwise include a selected academic group or a record title.
		var private_form: bool = false
		var form_ancestor: Node = button
		while form_ancestor != null:
			var ancestor_script: Script = form_ancestor.get_script() as Script
			if ancestor_script != null and ancestor_script.resource_path == "res://scripts/interest_panel.gd":
				private_form = true
				break
			form_ancestor = form_ancestor.get_parent()
		if private_form:
			continue
		if button.is_visible_in_tree():
			var point: Vector2 = button.get_global_transform_with_canvas() * (button.size * .5)
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
	var minimap_control: Control = world.get("hud").get("minimap") as Control
	var minimap_center: Vector2 = (minimap_control.global_position + minimap_control.size * .5) / viewport_size
	var graphics: Dictionary = world.get("hud").get("graphics_settings").call("get_state")
	return {
		"ticks_ms": Time.get_ticks_msec(),
		"world_instance": world.get_instance_id(),
		"music_instance": (world.get("music") as Node).get_instance_id(),
		"viewport": [viewport_size.x, viewport_size.y],
		"renderer": renderer_metadata(),
		# Reuse the normal 1 Hz settings snapshot, so resize/profile changes
		# remain current without extra engine queries or stale cached dimensions.
		"render_target": {
			"ui_pixels": graphics.get("ui_pixels", [viewport_size.x, viewport_size.y]),
			"internal_3d_pixels": graphics.get("internal_3d_pixels", []),
			"scale": graphics.get("scaling_3d_scale", 1.0),
			"msaa": graphics.get("applied_msaa", 0),
		},
		"fps": Engine.get_frames_per_second(),
		"process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"static_memory_bytes": Performance.get_monitor(Performance.MEMORY_STATIC),
		"static_memory_available": OS.is_debug_build(),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"resources": Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_buffer_bytes": Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"render_texture_bytes": Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED),
		"render_video_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
		# Release exports report zero for MEMORY_STATIC. Render counters describe
		# engine allocations (video includes buffers/textures), not browser RSS,
		# JS/MEMFS/WASM capacity or the device's available memory.
		"memory_measurement_scope": "godot_counters_not_browser_process_ram",
		"render_video_includes_buffers_and_textures": true,
		"overview": world.get("overview"),
		"preparing_roam": world.get("preparing_roam"),
		"avatar": actor.call("get_visual_preparation_state"),
		"animation": {"physics_updates": actor.get("animation_physics_updates"), "pose_samples": actor.get("animation_pose_samples"), "seek_calls": actor.get("animation_seek_calls")},
		"packs": get_node("/root/WebPacks").call("get_status"),
		"nearest_id": world.get("nearest_id"),
		"settings_open": world.get("hud").call("is_settings_open"),
		"full_map_open": world.get("hud").call("is_full_map_open"),
		"minimap_button": [minimap_center.x, minimap_center.y],
		"planet_radius": actor.get("planet_radius"),
		"walk_speed": actor.get("walk_speed"),
		"run_speed": actor.get("run_speed"),
		"avatar_scale": actor.get("avatar_scale"),
		"destinations_open": (world.get("hud").get("destination_card") as Control).visible,
		"player": {"position": [actor.position.x, actor.position.y, actor.position.z], "heading": [heading.x, heading.y, heading.z], "overview": world.get("overview"), "paused": world.get("paused"), "entering": world.get("entering"), "jump_count": actor.get("jump_count"), "landing_count": actor.get("landing_count")},
		"buttons": buttons,
		"streaming": world.get("streaming").call("metrics"),
		"minimap": world.get("hud").get("minimap").call("metrics"),
		"obstruction": world.get("camera_obstruction").call("stats"),
		"graphics": graphics,
	}
