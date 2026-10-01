extends Node

signal state_changed

const FRAME_LIMITS: Array[int] = [30, 60, 90]
const DEFAULT_FRAME_LIMIT: int = 60
const DEFAULT_MSAA_ENABLED: bool = true

var settings_path: String = "user://graphics_settings.cfg"
var msaa_enabled: bool = DEFAULT_MSAA_ENABLED
var frame_limit: int = DEFAULT_FRAME_LIMIT
var settings_error: int = OK

func _ready() -> void:
	load_settings()
	apply_settings()

func load_settings() -> void:
	msaa_enabled = DEFAULT_MSAA_ENABLED
	frame_limit = DEFAULT_FRAME_LIMIT
	settings_error = OK
	if not FileAccess.file_exists(settings_path):
		return
	var settings: ConfigFile = ConfigFile.new()
	settings_error = settings.load(settings_path)
	if settings_error != OK:
		return
	var stored_msaa: Variant = settings.get_value("graphics", "msaa_enabled", DEFAULT_MSAA_ENABLED)
	var stored_limit: Variant = settings.get_value("graphics", "frame_limit", DEFAULT_FRAME_LIMIT)
	if stored_msaa is bool:
		msaa_enabled = stored_msaa
	if stored_limit is int and stored_limit in FRAME_LIMITS:
		frame_limit = stored_limit

func apply_settings() -> void:
	# These affect rendering only. Keep physics ticks, renderer, texture quality,
	# resolution and display synchronization unchanged on every platform.
	get_viewport().msaa_3d = Viewport.MSAA_2X if msaa_enabled else Viewport.MSAA_DISABLED
	Engine.max_fps = frame_limit

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
	msaa_enabled = DEFAULT_MSAA_ENABLED
	frame_limit = DEFAULT_FRAME_LIMIT
	_commit_settings()

func _commit_settings() -> void:
	apply_settings()
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("graphics", "msaa_enabled", msaa_enabled)
	settings.set_value("graphics", "frame_limit", frame_limit)
	settings_error = settings.save(settings_path)
	state_changed.emit()

func get_state() -> Dictionary:
	return {
		"msaa_enabled": msaa_enabled,
		"frame_limit": frame_limit,
		"settings_error": settings_error,
		"persistent": OS.is_userfs_persistent(),
		"applied_msaa": get_viewport().msaa_3d,
		"applied_max_fps": Engine.max_fps,
	}
