extends Node

signal state_changed

const FRAME_LIMITS: Array[int] = [30, 60, 90]
const DEFAULT_FRAME_LIMIT: int = 30
const DEFAULT_MSAA_ENABLED: bool = false
const DEFAULT_QUALITY: String = "low"
const LOW_RENDER_SIZE: Vector2 = Vector2(1280.0, 720.0)
# A small pixel reduction can cost more than it saves through the extra scaling
# pass. Only enable scaling at 0.8 or below (at least 36% fewer 3D pixels).
const LOW_SCALING_MAX_FACTOR: float = 0.8

var settings_path: String = "user://graphics_settings.cfg"
var msaa_enabled: bool = DEFAULT_MSAA_ENABLED
var frame_limit: int = DEFAULT_FRAME_LIMIT
var quality_profile: String = DEFAULT_QUALITY
var settings_error: int = OK
var _render_viewport: Viewport

func _ready() -> void:
	add_to_group("graphics_settings")
	_render_viewport = get_viewport()
	load_settings()
	apply_settings()
	_render_viewport.size_changed.connect(apply_settings)

func load_settings() -> void:
	msaa_enabled = DEFAULT_MSAA_ENABLED
	frame_limit = DEFAULT_FRAME_LIMIT
	quality_profile = DEFAULT_QUALITY
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
	if not stored_profile is String or stored_profile not in ["low", "standard"]:
		return
	quality_profile = stored_profile
	var stored_msaa: Variant = settings.get_value("graphics", "msaa_enabled", DEFAULT_MSAA_ENABLED)
	var stored_limit: Variant = settings.get_value("graphics", "frame_limit", DEFAULT_FRAME_LIMIT)
	if stored_msaa is bool:
		msaa_enabled = stored_msaa
	if stored_limit is int and stored_limit in FRAME_LIMITS:
		frame_limit = stored_limit

func apply_settings() -> void:
	# Bilinear scales the 3D buffer only; canvas/UI and physics retain their
	# original resolution/tick rate, including when the world is detached indoors.
	var viewport: Viewport = _render_viewport
	viewport.msaa_3d = Viewport.MSAA_2X if msaa_enabled else Viewport.MSAA_DISABLED
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	var render_size: Vector2 = _render_target_size()
	viewport.scaling_3d_scale = low_render_scale(render_size) if is_low_quality() else 1.0
	viewport.set_meta("graphics_quality_profile", quality_profile)
	Engine.max_fps = frame_limit

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
	return quality_profile == "low"

func set_quality_profile(value: String) -> void:
	if value not in ["low", "standard"]:
		return
	quality_profile = value
	# Frame pacing is a separate user choice; a cheaper render preset must not
	# silently reduce the selected cap while moving or turning the camera.
	msaa_enabled = not is_low_quality()
	_commit_settings()

func set_msaa_enabled(enabled: bool) -> void:
	if msaa_enabled == enabled:
		return
	msaa_enabled = enabled
	_commit_settings()

func set_frame_limit(value: int) -> void:
	if value not in FRAME_LIMITS or frame_limit == value:
		return
	frame_limit = value
	_commit_settings()

func restore_defaults() -> void:
	quality_profile = DEFAULT_QUALITY
	msaa_enabled = DEFAULT_MSAA_ENABLED
	frame_limit = DEFAULT_FRAME_LIMIT
	_commit_settings()

func _commit_settings() -> void:
	apply_settings()
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("graphics", "msaa_enabled", msaa_enabled)
	settings.set_value("graphics", "frame_limit", frame_limit)
	settings.set_value("graphics", "quality_profile", quality_profile)
	settings_error = settings.save(settings_path)
	state_changed.emit()

func get_state() -> Dictionary:
	var viewport: Viewport = _render_viewport
	var size: Vector2 = _render_target_size()
	var internal: Vector2 = size * viewport.scaling_3d_scale
	return {
		"quality_profile": quality_profile,
		"scaling_3d_scale": viewport.scaling_3d_scale,
		"ui_pixels": [int(size.x), int(size.y)],
		"internal_3d_pixels": [int(internal.x), int(internal.y)],
		"msaa_enabled": msaa_enabled,
		"frame_limit": frame_limit,
		"settings_error": settings_error,
		"persistent": OS.is_userfs_persistent(),
		"applied_msaa": viewport.msaa_3d,
		"applied_max_fps": Engine.max_fps,
	}
