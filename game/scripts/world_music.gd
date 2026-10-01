extends Node

signal state_changed

const CONTEXTS: Array[String] = ["world", "counseling", "admissions", "recommendations", "wordking"]
const FADE_SECONDS: float = 1.8
const SILENT_DB: float = -80.0

var manifest_path: String = "res://data/music_tracks.json"
var settings_path: String = "user://music_settings.cfg"
var music_volume: float = 0.4
var muted: bool = false
var unlocked: bool = false
var background_paused: bool = false
var requested_context: String = "world"
var context: String = ""
var missing_ids: Array[String] = []
var settings_error: int = OK

var _catalog: Dictionary = {}
var _streams: Dictionary[String, AudioStream] = {}
var _voices: Dictionary[String, AudioStreamPlayer] = {}
var _gains: Dictionary[String, float] = {}
var _fade_from: Dictionary[String, float] = {}
var _starts: Dictionary[String, int] = {}
var _fade_elapsed: float = FADE_SECONDS
var _catalog_ready: bool = false
var _preparation_enabled: bool = false
var _pending_context: String = ""
var _load_errors: Dictionary[String, String] = {}

func _ready() -> void:
	name = "WorldMusic"
	_ensure_bus()
	_load_settings()
	_load_catalog()
	_catalog_ready = true
	set_context(requested_context)
	if not OS.has_feature("web"):
		unlock()

func _ensure_bus() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		AudioServer.add_bus()
		var index: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(index, "Music")
		AudioServer.set_bus_send(index, "Master")

func _load_settings() -> void:
	if not FileAccess.file_exists(settings_path):
		_apply_bus_settings()
		return
	var settings: ConfigFile = ConfigFile.new()
	settings_error = settings.load(settings_path)
	if settings_error == OK:
		var stored_volume: Variant = settings.get_value("music", "volume", 0.4)
		if stored_volume is float or stored_volume is int:
			var value: float = float(stored_volume)
			if is_finite(value):
				music_volume = clampf(value, 0.0, 1.0)
		var stored_mute: Variant = settings.get_value("music", "muted", false)
		if stored_mute is bool:
			muted = bool(stored_mute)
	_apply_bus_settings()

func _save_settings() -> void:
	var settings: ConfigFile = ConfigFile.new()
	settings.set_value("music", "volume", music_volume)
	settings.set_value("music", "muted", muted)
	settings_error = settings.save(settings_path)

func _apply_bus_settings() -> void:
	var index: int = AudioServer.get_bus_index("Music")
	if index < 0:
		return
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(music_volume, 0.0001)))
	AudioServer.set_bus_mute(index, muted or music_volume <= 0.0)

func _load_catalog() -> void:
	if FileAccess.file_exists(manifest_path):
		var parser: JSON = JSON.new()
		if parser.parse(FileAccess.get_file_as_string(manifest_path)) == OK and parser.data is Dictionary:
			_catalog = parser.data as Dictionary
	# Validate only the small manifest here. A resource may live in a Web pack
	# that has not been downloaded yet, so exists()/load() are deliberately late.
	for context_id: String in CONTEXTS:
		var entry: Dictionary = _catalog.get(context_id, {}) as Dictionary
		if str(entry.get("path", "")).is_empty():
			missing_ids.append(context_id)
		_gains[context_id] = 0.0
		_starts[context_id] = 0

func begin_prepare_music() -> void:
	# Explicit first-frame gate: no music request competes with the initial
	# overview. Only the current context is prepared, never the whole catalog.
	if _preparation_enabled:
		return
	_preparation_enabled = true
	_queue_requested_context()

func set_context(context_id: String) -> void:
	var next_request: String = "world" if context_id.is_empty() else context_id
	var request_changed: bool = requested_context != next_request
	requested_context = next_request
	if not _catalog_ready:
		return
	_queue_requested_context()
	if request_changed:
		state_changed.emit()

func _queue_requested_context() -> void:
	if not _preparation_enabled:
		return
	var next_context: String = requested_context
	if not _catalog.has(next_context) or next_context in missing_ids:
		next_context = "world"
	if next_context in missing_ids:
		next_context = ""
	if next_context.is_empty():
		_pending_context = ""
		_activate_context("")
		return
	if _streams.has(next_context):
		_pending_context = ""
		_activate_context(next_context)
		return
	if _pending_context == next_context:
		return
	_pending_context = next_context
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		var entry: Dictionary = _catalog.get(next_context, {}) as Dictionary
		packs.call("request_resource", str(entry.get("path", "")), -10)

func _prepare_pending_stream() -> void:
	if not _preparation_enabled or _pending_context.is_empty() or background_paused:
		return
	var context_id: String = _pending_context
	var entry: Dictionary = _catalog.get(context_id, {}) as Dictionary
	var resource_path: String = str(entry.get("path", ""))
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		var pack_error: String = str(packs.call("resource_error", resource_path))
		if not pack_error.is_empty():
			if _load_errors.get(context_id, "") != pack_error:
				_load_errors[context_id] = pack_error
				state_changed.emit()
			return
		if not bool(packs.call("is_resource_ready", resource_path)):
			return
	var source: AudioStream
	if ResourceLoader.exists(resource_path):
		source = load(resource_path) as AudioStream
	if source == null or source.get_length() <= 0.0:
		missing_ids.append(context_id)
		_load_errors[context_id] = "Missing or invalid music: " + resource_path
		_pending_context = ""
		_queue_requested_context()
		state_changed.emit()
		return
	# Each call prepares at most this one stream. Duplicating resource settings
	# preserves the compressed audio data and leaves the source asset untouched.
	var stream: AudioStream = source.duplicate() as AudioStream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
		(stream as AudioStreamOggVorbis).loop_offset = 0.0
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
	_streams[context_id] = stream
	_load_errors.erase(context_id)
	_pending_context = ""
	_activate_context(context_id)

func _activate_context(context_id: String) -> void:
	if context == context_id:
		return
	context = context_id
	if unlocked:
		_start_voice(context)
		_rebase_fade()
	state_changed.emit()

func retry_pending_music() -> void:
	if _pending_context.is_empty():
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("retry_failed")
		var entry: Dictionary = _catalog.get(_pending_context, {}) as Dictionary
		packs.call("request_resource", str(entry.get("path", "")), -10)
	_load_errors.erase(_pending_context)
	state_changed.emit()

func unlock() -> void:
	if unlocked:
		return
	unlocked = true
	_start_voice(context)
	_rebase_fade()
	state_changed.emit()

func _start_voice(context_id: String) -> void:
	if context_id.is_empty() or not _streams.has(context_id):
		return
	var voice: AudioStreamPlayer = _voices.get(context_id) as AudioStreamPlayer
	if voice == null:
		voice = AudioStreamPlayer.new()
		voice.name = "Music_" + context_id
		voice.stream = _streams[context_id]
		voice.bus = "Music"
		# BGM does not need low input latency. Streaming keeps long Ogg loops
		# compressed and uses the same bus/loop behavior on native and Web.
		voice.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		voice.volume_db = SILENT_DB
		add_child(voice)
		_voices[context_id] = voice
	# A background-paused player reports playing=false while retaining its
	# playback object. Do not restart that retained stream on a context change.
	if not voice.has_stream_playback():
		voice.play()
		_starts[context_id] = int(_starts.get(context_id, 0)) + 1
	voice.stream_paused = background_paused

func _rebase_fade() -> void:
	# One gain trajectory per track allows a rapid A -> B -> C -> A change
	# without stopping a still-audible voice or restarting a fading-in track.
	_fade_from = _gains.duplicate()
	_fade_elapsed = 0.0

func _process(delta: float) -> void:
	_prepare_pending_stream()
	if not unlocked or background_paused or _fade_elapsed >= FADE_SECONDS:
		return
	_fade_elapsed = minf(_fade_elapsed + delta, FADE_SECONDS)
	var progress: float = _fade_elapsed / FADE_SECONDS
	var weight: float = progress * progress * (3.0 - 2.0 * progress)
	for context_id: String in _voices:
		var target: float = 1.0 if context_id == context else 0.0
		var gain: float = lerpf(float(_fade_from.get(context_id, 0.0)), target, weight)
		_gains[context_id] = gain
		var voice: AudioStreamPlayer = _voices[context_id]
		voice.volume_db = linear_to_db(gain) if gain > 0.0001 else SILENT_DB
		if progress >= 1.0 and target == 0.0 and voice.playing:
			voice.stop()
	if progress >= 1.0:
		state_changed.emit()

func set_music_volume(value: float) -> void:
	if not is_finite(value):
		return
	var next_volume: float = clampf(value, 0.0, 1.0)
	if is_equal_approx(next_volume, music_volume):
		return
	music_volume = next_volume
	_apply_bus_settings()
	_save_settings()
	state_changed.emit()

func set_muted(value: bool) -> void:
	if muted == value:
		return
	muted = value
	_apply_bus_settings()
	_save_settings()
	state_changed.emit()

func set_background_paused(value: bool) -> void:
	if background_paused == value:
		return
	background_paused = value
	for voice: AudioStreamPlayer in _voices.values():
		voice.stream_paused = value
	state_changed.emit()

func _exit_tree() -> void:
	for voice: AudioStreamPlayer in _voices.values():
		voice.stop()

func get_state() -> Dictionary:
	var voices: Dictionary = {}
	for context_id: String in _voices:
		var voice: AudioStreamPlayer = _voices[context_id]
		voices[context_id] = {
			"playing": voice.playing, "paused": voice.stream_paused,
			"active": voice.has_stream_playback(),
			"position": voice.get_playback_position(), "length": voice.stream.get_length(),
			"gain": float(_gains.get(context_id, 0.0)), "starts": int(_starts.get(context_id, 0))
		}
	var entry: Dictionary = _catalog.get(context, {}) as Dictionary
	var music_bus: int = AudioServer.get_bus_index("Music")
	var peak_left: float = -120.0
	var peak_right: float = -120.0
	if music_bus >= 0:
		peak_left = AudioServer.get_bus_peak_volume_left_db(music_bus, 0)
		peak_right = AudioServer.get_bus_peak_volume_right_db(music_bus, 0)
	peak_left = clampf(peak_left, -120.0, 24.0) if is_finite(peak_left) else -120.0
	peak_right = clampf(peak_right, -120.0, 24.0) if is_finite(peak_right) else -120.0
	return {
		"requested_context": requested_context, "context": context,
		"title": str(entry.get("title", "")), "path": str(entry.get("path", "")),
		"available_ids": _streams.keys(), "missing_ids": missing_ids.duplicate(),
		"pending_context": _pending_context, "preparation_enabled": _preparation_enabled,
		"load_errors": _load_errors.duplicate(),
		"fallback": not requested_context.is_empty() and context != requested_context,
		"unlocked": unlocked, "muted": muted, "volume": music_volume,
		"background_paused": background_paused, "settings_error": settings_error,
		"transitioning": unlocked and _fade_elapsed < FADE_SECONDS,
		"peak_left_db": peak_left, "peak_right_db": peak_right,
		"voices": voices
	}
