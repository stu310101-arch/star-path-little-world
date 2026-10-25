extends Node

signal state_changed

const FRAME_LIMITS: Array[int] = [30, 60, 90]
const DEFAULT_FRAME_LIMIT: int = 30
const DEFAULT_WEB_FRAME_LIMIT: int = 60
const DEFAULT_MOBILE_WEB_FRAME_LIMIT: int = 30
const DEFAULT_MSAA_ENABLED: bool = false
const DEFAULT_QUALITY: String = "low"
const LOW_RENDER_SIZE: Vector2 = Vector2(1280.0, 720.0)
const MOBILE_RENDER_SIZE: Vector2 = Vector2(960.0, 540.0)
const MOBILE_WEB_RENDER_SIZE: Vector2 = Vector2(768.0, 432.0)
const QUALITY_PROFILES: Array[String] = ["mobile", "balanced", "low", "standard"]
const ADAPTIVE_HEIGHTS: Array[int] = [432, 540, 630, 720]
const MOBILE_ADAPTIVE_HEIGHTS: Array[int] = [320, 360, 432]
const MOBILE_POLICY_VERSION: int = 1
const ADAPTIVE_START_LEVEL: int = 1
const ADAPTIVE_WARMUP_SECONDS: float = 4.0
const ADAPTIVE_CHANGE_COOLDOWN: float = 6.0
const ADAPTIVE_PROMOTION_RETRY: float = 60.0
const BACKGROUND_FRAME_LIMIT: int = 10
const IDLE_FRAME_LIMIT: int = 15
const CONSTRAINED_FRAME_LIMIT: int = 30
const IDLE_DELAY: float = 8.0
const RUNTIME_OVERLOAD_SECONDS: float = 6.0
# A small pixel reduction can cost more than it saves through the extra scaling
# pass. Only enable scaling at 0.8 or below (at least 36% fewer 3D pixels).
const LOW_SCALING_MAX_FACTOR: float = 0.8

var settings_path: String = "user://graphics_settings.cfg"
var msaa_enabled: bool = DEFAULT_MSAA_ENABLED
var frame_limit: int = DEFAULT_FRAME_LIMIT
var quality_profile: String = DEFAULT_QUALITY
var settings_error: int = OK
var _render_viewport: Viewport
var _mobile_web: bool = false
var _scene_tree: SceneTree
var _focused: bool = true
var _page_visible: bool = true
var _background_hidden: bool = false
var _render_loop_before_background: bool = true
var _visibility_document: JavaScriptObject
var _visibility_callback: JavaScriptObject
var _background_transition_count: int = 0
var _background_events: Array[Dictionary] = []
var _visibility_clock: float = 0.0
var _streaming_clock: float = 0.0
var _streaming_busy: bool = false
var _display_refresh_hz: float = 60.0
var _active_scene_id: int = 0
var _adaptive_level: int = ADAPTIVE_START_LEVEL
var _last_frame_usec: int = 0
var _window_seconds: float = 0.0
var _window_frames: int = 0
var _window_late_frames: int = 0
var _stable_seconds: float = 0.0
var _slow_seconds: float = 0.0
var _resolution_cooldown: float = ADAPTIVE_WARMUP_SECONDS
var _promotion_cooldown: float = 0.0
var _measured_fps: float = 0.0
var _frame_budget_ratio: float = 0.0
var _pacing_status: String = "warming"
var _sample_active: bool = false
var _severe_stall_seconds: float = 0.0
var _severe_stall_frames: int = 0
var _runtime_pressure: bool = false
var _runtime_window_seconds: float = 0.0
var _runtime_window_frames: int = 0
var _runtime_late_seconds: float = 0.0
var _idle_seconds: float = 0.0
var _idle_limited: bool = false
var _budget_camera: Transform3D = Transform3D.IDENTITY
var _budget_camera_valid: bool = false
var _mobile_resolution_ceiling: int = MOBILE_ADAPTIVE_HEIGHTS.size() - 1

func _ready() -> void:
	add_to_group("graphics_settings")
	_render_viewport = get_viewport()
	_scene_tree = get_tree()
	_mobile_web = is_mobile_web()
	_configure_mobile_window()
	_adaptive_level = _adaptive_start_level()
	if DisplayServer.get_name() != "headless":
		var reported_refresh: float = DisplayServer.screen_get_refresh_rate()
		if reported_refresh > 0.0:
			_display_refresh_hz = reported_refresh
	load_settings()
	apply_settings()
	_render_viewport.size_changed.connect(_on_viewport_resized)
	# This signal remains connected when the world and its HUD leave the tree
	# for an indoor visit. Node._process would stop during that entire visit.
	_scene_tree.process_frame.connect(_sample_render_frame)
	_scene_tree.root.focus_entered.connect(_on_focus_entered)
	_scene_tree.root.focus_exited.connect(_on_focus_exited)
	_scene_tree.root.window_input.connect(_input)
	_setup_visibility_events()

func _setup_visibility_events() -> void:
	if OS.has_feature("web"):
		_visibility_document = JavaScriptBridge.get_interface("document")
		_visibility_callback = JavaScriptBridge.create_callback(_on_document_visibility_changed)
		_visibility_document.addEventListener("visibilitychange", _visibility_callback)
	_refresh_visibility()

func _on_document_visibility_changed(_arguments: Array) -> void:
	# Visibility events still arrive when the browser suspends requestAnimationFrame.
	# Restore rendering here, before relying on another game frame or frame_post_draw.
	_refresh_visibility()

func _refresh_visibility() -> void:
	if OS.has_feature("web") and _visibility_document != null:
		var hidden: bool = bool(_visibility_document.hidden)
		_page_visible = not hidden and bool(_visibility_document.hasFocus())
		_set_background_hidden(hidden, "document.hidden")
	elif not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		var hidden: bool = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
		_page_visible = not hidden
		_set_background_hidden(hidden, "native.minimized")

func _set_background_hidden(hidden: bool, reason: String = "explicit") -> void:
	if _background_hidden == hidden:
		return
	_background_hidden = hidden
	if hidden:
		_render_loop_before_background = RenderingServer.is_render_loop_enabled()
		RenderingServer.set_render_loop_enabled(false)
	else:
		RenderingServer.set_render_loop_enabled(_render_loop_before_background)
	_apply_frame_limit()
	_reset_adaptation(false)
	_background_transition_count += 1
	# Foreground-only telemetry cannot publish while rAF is suspended. Keep a
	# bounded event trail for its next snapshot; no extra per-frame JS calls.
	_background_events.append({
		"ticks_ms": Time.get_ticks_msec(),
		"reason": reason,
		"hidden": hidden,
		"applied_max_fps": Engine.max_fps,
		"frame_limit": frame_limit,
		"render_loop_enabled": RenderingServer.is_render_loop_enabled(),
	})
	if _background_events.size() > 8:
		_background_events.pop_front()

func _apply_frame_limit() -> void:
	# This is a temporary execution budget, never a saved quality/FPS preference.
	var active_limit: int = mini(frame_limit, CONSTRAINED_FRAME_LIMIT) if is_constrained_runtime() else frame_limit
	Engine.max_fps = mini(active_limit, BACKGROUND_FRAME_LIMIT) if _background_hidden else mini(active_limit, IDLE_FRAME_LIMIT) if _idle_limited else active_limit

func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion or event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		note_activity()

func note_activity() -> void:
	_idle_seconds = 0.0
	if _idle_limited:
		_idle_limited = false
		_apply_frame_limit()

func _update_idle_budget(elapsed: float, gameplay: bool) -> void:
	# Track the actual view, also while this service is retained outside the tree
	# during indoor visits. Moving/touch input returns to the user's cap immediately.
	var camera: Camera3D = _render_viewport.get_camera_3d()
	var moved: bool = not _budget_camera_valid
	if is_instance_valid(camera):
		var pose: Transform3D = camera.global_transform
		moved = moved or not pose.is_equal_approx(_budget_camera)
		_budget_camera = pose
		_budget_camera_valid = true
	if not is_constrained_runtime() or not gameplay or moved:
		note_activity()
		return
	_idle_seconds += minf(elapsed, 0.25)
	if _idle_seconds >= IDLE_DELAY and not _idle_limited:
		_idle_limited = true
		_apply_frame_limit()

func sample_runtime_pressure(elapsed: float, eligible: bool) -> void:
	# Device-independent escape from CPU/geometry overload. A single loading
	# stall never qualifies; persistent foreground misses must span many frames.
	# Keep relief for this session so recovering FPS cannot reload the same cost.
	if _runtime_pressure or not eligible or elapsed <= 0.0:
		_runtime_window_seconds = 0.0
		_runtime_window_frames = 0
		_runtime_late_seconds = 0.0
		return
	_runtime_window_seconds += minf(elapsed, 0.5)
	_runtime_window_frames += 1
	if _runtime_window_seconds < 1.0:
		return
	var average: float = _runtime_window_seconds / float(_runtime_window_frames)
	var budget: float = maxf(1.0 / effective_frame_target(frame_limit, _display_refresh_hz), 1.0 / 30.0)
	_runtime_late_seconds = _runtime_late_seconds + _runtime_window_seconds if average > budget * 1.35 else 0.0
	_runtime_window_seconds = 0.0
	_runtime_window_frames = 0
	if _runtime_late_seconds >= RUNTIME_OVERLOAD_SECONDS:
		_runtime_pressure = true
		apply_settings()
		state_changed.emit()

func _notification(what: int) -> void:
	if what != NOTIFICATION_PREDELETE:
		return
	# _exit_tree also runs when the whole outdoor world is retained indoors.
	# Only destruction releases this root-window service and its browser listener.
	if _visibility_document != null and _visibility_callback != null:
		_visibility_document.removeEventListener("visibilitychange", _visibility_callback)
	if is_instance_valid(_scene_tree) and _scene_tree.root.window_input.is_connected(_input):
		_scene_tree.root.window_input.disconnect(_input)
	if _background_hidden:
		_set_background_hidden(false, "service_destroyed")

func _configure_mobile_window() -> void:
	if not _mobile_web:
		return
	# Expand the logical canvas to the device aspect ratio instead of fitting
	# the desktop's 16:10 game into a narrow strip on a portrait phone.
	var window: Window = _scene_tree.root
	window.content_scale_size = Vector2i(960, 600)
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND

func load_settings() -> void:
	if get_node("/root/ResourceProfile").call("is_low"):
		settings_path = "user://graphics_settings_low_resources.cfg"
	msaa_enabled = DEFAULT_MSAA_ENABLED
	frame_limit = default_frame_limit(_mobile_web)
	quality_profile = default_quality_profile(_mobile_web)
	msaa_enabled = not is_low_quality()
	settings_error = OK
	if not FileAccess.file_exists(settings_path):
		return
	var settings: ConfigFile = ConfigFile.new()
	settings_error = settings.load(settings_path)
	if settings_error != OK:
		return
	# Migrate old AA/FPS-only files once to the newly requested safe preset.
	# They are not evidence that the user selected the new standard profile.
	var stored_profile: Variant = settings.get_value("graphics", "quality_profile", "")
	if not stored_profile is String or stored_profile not in QUALITY_PROFILES:
		return
	# The old mobile preset could promote itself to 720p and retained desktop
	# quality choices. Apply the new mobile baseline once, including returning
	# players; choices saved after this migration remain explicit preferences.
	if _mobile_web and settings.get_value("graphics", "mobile_policy_version", 0) != MOBILE_POLICY_VERSION:
		_save_settings()
		return
	quality_profile = stored_profile
	# Missing or malformed AA settings inherit the saved profile's preset,
	# including low-quality files loaded under the native standard default.
	msaa_enabled = not is_low_quality()
	var stored_msaa: Variant = settings.get_value("graphics", "msaa_enabled", msaa_enabled)
	var stored_limit: Variant = settings.get_value("graphics", "frame_limit", frame_limit)
	if stored_msaa is bool:
		msaa_enabled = stored_msaa
	if stored_limit is int and stored_limit in FRAME_LIMITS:
		frame_limit = stored_limit

func apply_settings() -> void:
	# Bilinear scales the 3D buffer only; canvas/UI and physics retain their
	# original resolution/tick rate, including when the world is detached indoors.
	var viewport: Viewport = _render_viewport
	viewport.msaa_3d = Viewport.MSAA_2X if msaa_enabled and not is_constrained_runtime() else Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_apply_render_scale()
	viewport.set_meta("graphics_quality_profile", quality_profile)
	_apply_frame_limit()
	# The sun is shared by overview and roaming. Its shadow map is reserved for
	# full-detail mode; cheaper presets keep the same authored lighting.
	var scene: Node = null
	if get_parent() is CanvasLayer and get_parent().get_parent() is Node3D:
		scene = get_parent().get_parent()
	elif is_inside_tree():
		scene = get_tree().current_scene
	var sun: DirectionalLight3D = scene.get_node_or_null("Sun") as DirectionalLight3D if scene != null else null
	if sun != null:
		sun.shadow_enabled = quality_profile == "standard" and not is_constrained_runtime()
		sun.directional_shadow_max_distance = 48.0
		sun.directional_shadow_split_1 = 0.3
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS

static func is_mobile_web() -> bool:
	if not OS.has_feature("web"):
		return false
	if OS.has_feature("web_mobile"):
		return true
	return bool(JavaScriptBridge.eval("window.LittleWorldMobileMode === true || (/iPhone|iPad|iPod|Android/i.test(navigator.userAgent) && navigator.maxTouchPoints > 0) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1) || (navigator.maxTouchPoints > 0 && matchMedia('(any-pointer: coarse)').matches)"))

static func default_quality_profile(mobile_web: bool) -> String:
	if uses_low_resources():
		return "mobile" if mobile_web else "low"
	return "balanced" if mobile_web else DEFAULT_QUALITY if OS.has_feature("low_end") else "standard"

static func uses_low_resources() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var resources: Node = tree.root.get_node_or_null("ResourceProfile") if tree != null else null
	return resources != null and bool(resources.call("is_low"))

static func default_frame_limit(mobile_web: bool) -> int:
	return DEFAULT_MOBILE_WEB_FRAME_LIMIT if mobile_web else DEFAULT_WEB_FRAME_LIMIT if OS.has_feature("web") else DEFAULT_FRAME_LIMIT

func _render_target_size() -> Vector2:
	# In canvas_items mode ViewportTexture.get_size() applies stretch to the
	# already physical viewport size. Use the logical canvas and its transform
	# once, including the authored aspect-ratio bars, instead of counting it twice.
	return (_render_viewport.get_visible_rect().size * _render_viewport.get_stretch_transform().get_scale()).round()

static func low_render_scale(size: Vector2) -> float:
	if size.x <= 0.0 or size.y <= 0.0:
		return 1.0
	var target_scale: float = clampf(minf(LOW_RENDER_SIZE.x / size.x, LOW_RENDER_SIZE.y / size.y), 0.1, 1.0)
	return target_scale if target_scale <= LOW_SCALING_MAX_FACTOR else 1.0

func is_low_quality() -> bool:
	return quality_profile in ["mobile", "balanced", "low"]

func is_mobile_performance_profile() -> bool:
	return is_constrained_runtime()

func is_constrained_runtime() -> bool:
	return _runtime_pressure or quality_profile == "mobile" or (_mobile_web and is_low_quality())

func set_quality_profile(value: String) -> void:
	if value not in QUALITY_PROFILES:
		return
	quality_profile = value
	note_activity()
	# Frame pacing is a separate user choice; a cheaper render preset must not
	# silently reduce the selected cap while moving or turning the camera.
	msaa_enabled = not is_low_quality()
	_reset_adaptation(true)
	_commit_settings()

func set_msaa_enabled(enabled: bool) -> void:
	if msaa_enabled == enabled:
		return
	msaa_enabled = enabled
	_reset_adaptation(false)
	_commit_settings()

func set_frame_limit(value: int) -> void:
	if value not in FRAME_LIMITS or frame_limit == value:
		return
	frame_limit = value
	_reset_adaptation(false)
	_commit_settings()

func restore_defaults() -> void:
	quality_profile = default_quality_profile(_mobile_web)
	msaa_enabled = not is_low_quality()
	frame_limit = default_frame_limit(_mobile_web)
	_reset_adaptation(true)
	_commit_settings()

func _commit_settings() -> void:
	apply_settings()
	_save_settings()
	state_changed.emit()

func _save_settings() -> void:
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("graphics", "msaa_enabled", msaa_enabled)
	settings.set_value("graphics", "frame_limit", frame_limit)
	settings.set_value("graphics", "quality_profile", quality_profile)
	if _mobile_web:
		settings.set_value("graphics", "mobile_policy_version", MOBILE_POLICY_VERSION)
	settings_error = settings.save(settings_path)

func get_state() -> Dictionary:
	var viewport: Viewport = _render_viewport
	var size: Vector2 = _render_target_size()
	var internal: Vector2 = size * viewport.scaling_3d_scale
	return {
		"quality_profile": quality_profile,
		"mobile_web": _mobile_web,
		"mobile_performance_profile": is_mobile_performance_profile(),
		"constrained_runtime": is_constrained_runtime(),
		"runtime_pressure": _runtime_pressure,
		"idle_limited": _idle_limited,
		"scaling_3d_scale": viewport.scaling_3d_scale,
		"ui_pixels": [int(size.x), int(size.y)],
		"internal_3d_pixels": [roundi(internal.x), roundi(internal.y)],
		"msaa_enabled": msaa_enabled,
		"frame_limit": frame_limit,
		"settings_error": settings_error,
		"persistent": OS.is_userfs_persistent(),
		"applied_msaa": viewport.msaa_3d,
		"applied_max_fps": Engine.max_fps,
		"background_hidden": _background_hidden,
		"render_loop_enabled": RenderingServer.is_render_loop_enabled(),
		"background_transition_count": _background_transition_count,
		"background_events": _background_events.duplicate(true),
		"sampling_window_focused": _focused,
		"sampling_page_eligible": _page_visible,
		"adaptive_enabled": quality_profile == "balanced",
		"adaptive_height": _adaptive_heights()[_adaptive_level],
		"adaptive_max_height": _adaptive_heights()[_mobile_resolution_ceiling] if _mobile_web else _adaptive_heights().back(),
		"effective_target_fps": effective_frame_target(mini(frame_limit, CONSTRAINED_FRAME_LIMIT) if is_constrained_runtime() else frame_limit, _display_refresh_hz),
		"recent_gameplay_fps": _measured_fps,
		"frame_budget_ratio": _frame_budget_ratio,
		"pacing_status": _pacing_status,
		"sampling_gameplay": _sample_active,
		"promotion_cooldown_seconds": _promotion_cooldown,
	}

func _apply_render_scale() -> void:
	var render_size: Vector2 = _render_target_size()
	if _runtime_pressure and quality_profile in ["standard", "low"]:
		_render_viewport.scaling_3d_scale = capped_render_scale(render_size, mobile_render_cap(render_size, MOBILE_WEB_RENDER_SIZE.y) if _mobile_web else MOBILE_RENDER_SIZE)
	elif quality_profile == "balanced":
		var height: float = float(_adaptive_heights()[_adaptive_level])
		var cap: Vector2 = mobile_render_cap(render_size, height) if _mobile_web else Vector2(height * 16.0 / 9.0, height)
		_render_viewport.scaling_3d_scale = capped_render_scale(render_size, cap)
	elif quality_profile == "mobile":
		var cap: Vector2 = mobile_render_cap(render_size, MOBILE_WEB_RENDER_SIZE.y) if _mobile_web else MOBILE_RENDER_SIZE
		_render_viewport.scaling_3d_scale = capped_render_scale(render_size, cap)
	else:
		_render_viewport.scaling_3d_scale = low_render_scale(render_size) if is_low_quality() else 1.0

func _adaptive_heights() -> Array[int]:
	return MOBILE_ADAPTIVE_HEIGHTS if _mobile_web else ADAPTIVE_HEIGHTS

func _adaptive_start_level() -> int:
	return _mobile_resolution_ceiling if _mobile_web else ADAPTIVE_START_LEVEL

static func mobile_render_cap(size: Vector2, short_edge: float) -> Vector2:
	# Rotate the same pixel budget with the device; a portrait phone should
	# not be restricted to a 432px long edge while landscape gets 768px.
	return Vector2(short_edge, short_edge * 16.0 / 9.0) if size.y > size.x else Vector2(short_edge * 16.0 / 9.0, short_edge)

static func capped_render_scale(size: Vector2, cap: Vector2) -> float:
	return minf(1.0, minf(cap.x / maxf(size.x, 1.0), cap.y / maxf(size.y, 1.0)))

static func effective_frame_target(chosen_limit: int, display_refresh_hz: float) -> float:
	# A 90 FPS preference on a 60 Hz display must not look like GPU overload.
	return minf(float(chosen_limit), display_refresh_hz if display_refresh_hz > 0.0 else 60.0)

func _on_viewport_resized() -> void:
	_reset_adaptation(false)
	apply_settings()

func _on_focus_entered() -> void:
	_focused = true
	_refresh_visibility()
	_reset_adaptation(false)

func _on_focus_exited() -> void:
	_focused = false
	# A focused iframe/WebView or another visible window is not proof of occlusion.
	# Only document.hidden / an actually minimized native window may stop rendering.
	_refresh_visibility()
	_reset_adaptation(false)

func _reset_adaptation(reset_level: bool) -> void:
	if reset_level:
		_adaptive_level = _adaptive_start_level()
		_promotion_cooldown = 0.0
	_last_frame_usec = 0
	_window_seconds = 0.0
	_window_frames = 0
	_window_late_frames = 0
	_stable_seconds = 0.0
	_slow_seconds = 0.0
	_resolution_cooldown = ADAPTIVE_WARMUP_SECONDS
	_sample_active = false
	_severe_stall_seconds = 0.0
	_severe_stall_frames = 0

func _sample_render_frame() -> void:
	var now_usec: int = Time.get_ticks_usec()
	var elapsed: float = maxf(0.0, float(now_usec - _last_frame_usec) / 1000000.0) if _last_frame_usec > 0 else 0.0
	_visibility_clock += elapsed
	if _visibility_clock >= 0.5:
		_visibility_clock = 0.0
		_refresh_visibility()
	var scene: Node = _scene_tree.current_scene
	var scene_id: int = scene.get_instance_id() if is_instance_valid(scene) else 0
	if scene_id != _active_scene_id:
		_active_scene_id = scene_id
		_streaming_clock = 0.5
		_streaming_busy = false
		_reset_adaptation(true)
		_measured_fps = 0.0
		_pacing_status = "warming"
		_apply_render_scale()
	_streaming_clock += elapsed
	if _streaming_clock >= 0.5:
		_streaming_clock = 0.0
		var streaming: Node = scene.get("streaming") as Node if is_instance_valid(scene) else null
		_streaming_busy = is_instance_valid(streaming) and int((streaming.call("metrics") as Dictionary).get("pending_regions", 0)) > 0
	var foreground: bool = _focused and _page_visible and not _background_hidden and not _scene_tree.paused
	var gameplay: bool = foreground and _gameplay_is_active(scene)
	_update_idle_budget(elapsed, foreground and _idle_budget_eligible(scene))
	# Streaming stalls are precisely where a weak device needs the lighter
	# scene. Ignore loading for resolution trials, but not for structural relief.
	var pressure_eligible: bool = foreground and _gameplay_is_active(scene, true) and not _idle_limited
	sample_runtime_pressure(elapsed, pressure_eligible)
	sample_frame(now_usec, gameplay and not _idle_limited)

func _idle_budget_eligible(scene: Node) -> bool:
	if not is_instance_valid(scene):
		return false
	if scene.get("startup_presented") != null:
		return bool(scene.get("startup_presented")) and not bool(scene.get("entering")) and not bool(scene.get("preparing_roam")) and not bool(scene.get("preparing_room")) and not _streaming_busy
	if scene.get("ready_for_play") != null:
		return bool(scene.get("ready_for_play")) and not bool(scene.get("returning")) and str(scene.get("detail_state")) in ["ready", "error"]
	return false

func _gameplay_is_active(scene: Node, allow_streaming: bool = false) -> bool:
	if not is_instance_valid(scene):
		return false
	var account_view_open: Variant = scene.get("account_view_open")
	if account_view_open is bool and account_view_open:
		return false
	var account_bridge: Node = scene.get("account_bridge") as Node
	if is_instance_valid(account_bridge) and account_bridge.has_method("is_open") and bool(account_bridge.call("is_open")):
		return false
	# Both scene types explicitly advertise their readiness. Menus, entry
	# animations and resource preparation must never be counted as headroom.
	if scene.get("startup_presented") != null:
		if not bool(scene.get("startup_presented")) or bool(scene.get("entering")) or (bool(scene.get("preparing_roam")) and not allow_streaming) or bool(scene.get("preparing_room")) or bool(scene.get("paused")):
			return false
		var hud: Node = scene.get("hud") as Node
		var destinations: Control = hud.get("destination_card") as Control if is_instance_valid(hud) else null
		return (allow_streaming or not _streaming_busy) and (not is_instance_valid(hud) or not bool(hud.call("is_settings_open"))) and (not is_instance_valid(destinations) or not destinations.visible)
	if scene.get("ready_for_play") != null:
		if not bool(scene.get("ready_for_play")) or bool(scene.get("returning")) or str(scene.get("detail_state")) not in ["ready", "error"]:
			return false
		var reader: Node = scene.get("ui") as Node
		if is_instance_valid(reader) and reader.has_method("is_open") and bool(reader.call("is_open")):
			return false
		var games: Node = scene.get("computer_games") as Node
		var interactions: Node = scene.get("interactions") as Node
		var dialog: Window = scene.get("native_game_dialog") as Window
		return (not is_instance_valid(games) or not bool(games.call("is_open"))) and (not is_instance_valid(interactions) or not bool(interactions.call("camera_blocked"))) and (not is_instance_valid(dialog) or not dialog.visible)
	return false

func sample_frame(now_usec: int, gameplay_active: bool) -> void:
	# Use elapsed real time, never Godot's capped/smoothed process delta. This
	# also provides a deterministic seam for testing frame pacing at every cap.
	var elapsed: float = float(now_usec - _last_frame_usec) / 1000000.0 if _last_frame_usec > 0 else 0.0
	_last_frame_usec = now_usec
	_sample_active = gameplay_active
	if not gameplay_active or elapsed <= 0.0 or elapsed > 0.25:
		_window_seconds = 0.0
		_window_frames = 0
		_window_late_frames = 0
		_stable_seconds = 0.0
		_slow_seconds = 0.0
		_resolution_cooldown = maxf(_resolution_cooldown, ADAPTIVE_WARMUP_SECONDS)
		if gameplay_active and elapsed > 0.25:
			# A single loading hiccup cannot change quality. Repeated severe
			# foreground stalls still need relief, even below four frames/sec.
			_severe_stall_seconds += minf(elapsed, 1.0)
			_severe_stall_frames += 1
			if _severe_stall_seconds >= 3.0 and _severe_stall_frames >= 4:
				_measured_fps = 1.0 / elapsed
				_frame_budget_ratio = elapsed * effective_frame_target(mini(frame_limit, CONSTRAINED_FRAME_LIMIT) if is_constrained_runtime() else frame_limit, _display_refresh_hz)
				_pacing_status = "overloaded"
				if quality_profile == "balanced" and _adaptive_level > 0:
					_adaptive_level -= 1
					_promotion_cooldown = ADAPTIVE_PROMOTION_RETRY
					_change_adaptive_resolution()
				_severe_stall_seconds = 0.0
				_severe_stall_frames = 0
		else:
			_severe_stall_seconds = 0.0
			_severe_stall_frames = 0
		return
	_severe_stall_seconds = 0.0
	_severe_stall_frames = 0
	_resolution_cooldown = maxf(0.0, _resolution_cooldown - elapsed)
	_promotion_cooldown = maxf(0.0, _promotion_cooldown - elapsed)
	var budget: float = 1.0 / effective_frame_target(mini(frame_limit, CONSTRAINED_FRAME_LIMIT) if is_constrained_runtime() else frame_limit, _display_refresh_hz)
	_window_seconds += elapsed
	_window_frames += 1
	if elapsed > budget * 1.15:
		_window_late_frames += 1
	if _window_seconds < 1.0:
		return
	_measured_fps = float(_window_frames) / _window_seconds
	_frame_budget_ratio = (_window_seconds / float(_window_frames)) / budget
	var late_fraction: float = float(_window_late_frames) / float(_window_frames)
	var stable: bool = _frame_budget_ratio <= 1.06 and late_fraction <= 0.05
	# Godot's Web limiter skips early requestAnimationFrame callbacks. At a
	# 30 FPS cap this can alternate 16.7/50 ms while still delivering 30 FPS.
	# Uneven but on-target pacing is mixed; lower resolution only when the
	# average also misses the budget, since scaling cannot fix limiter jitter.
	var overloaded: bool = _frame_budget_ratio > 1.15 or (late_fraction > 0.25 and _frame_budget_ratio > 1.06)
	_pacing_status = "overloaded" if overloaded else "stable" if stable else "mixed"
	if quality_profile == "balanced" and _resolution_cooldown <= 0.0:
		_stable_seconds = _stable_seconds + _window_seconds if stable else 0.0
		_slow_seconds = _slow_seconds + _window_seconds if overloaded else 0.0
		var slow_threshold: float = 2.0 if _mobile_web else 3.0
		var stable_threshold: float = 30.0 if _mobile_web else 12.0
		if _slow_seconds >= slow_threshold and _adaptive_level > 0:
			_adaptive_level -= 1
			_promotion_cooldown = ADAPTIVE_PROMOTION_RETRY
			_change_adaptive_resolution()
		elif _stable_seconds >= stable_threshold and _promotion_cooldown <= 0.0 and _adaptive_level < (_mobile_resolution_ceiling if _mobile_web else _adaptive_heights().size() - 1):
			# Capped presentation proves stable pacing, not unused GPU time.
			# Trial one small increase, then back off for a minute if it fails.
			_adaptive_level += 1
			_change_adaptive_resolution()
	_window_seconds = 0.0
	_window_frames = 0
	_window_late_frames = 0

func _change_adaptive_resolution() -> void:
	if _mobile_web:
		# Stable capped FPS does not prove thermal headroom. Once a phone slows,
		# retain that lighter budget across room changes until the next session.
		_mobile_resolution_ceiling = mini(_mobile_resolution_ceiling, _adaptive_level)
	_stable_seconds = 0.0
	_slow_seconds = 0.0
	_resolution_cooldown = ADAPTIVE_CHANGE_COOLDOWN
	_apply_render_scale()
