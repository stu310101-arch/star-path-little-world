extends Node
## Three independent, pivoted clips. No physics, particles or per-frame mesh work.
const PARTS: Array[Dictionary] = [
	{"name":"OrreryOuterRing","axis":Vector3.FORWARD,"speed":.13},
	{"name":"OrreryInnerRing","axis":Vector3.RIGHT,"speed":-.21},
	{"name":"OrreryOrbit","axis":Vector3.UP,"speed":.27},
]
const SETTINGS_PATH: String = "user://recommendation_visuals.cfg"
var players: Dictionary = {}
var motion_enabled: bool = true
var low_quality: bool = false
var presentation_active: bool = false
var focused: bool = true
var browser_reduced_motion: bool = false
var browser_hidden: bool = false
var visibility_clock: float = 0.0

func _ready() -> void:
	var settings: ConfigFile = ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		motion_enabled = bool(settings.get_value("orrery","motion_enabled",true))
	_refresh_browser_preferences()

func configure(model: Node3D, low: bool) -> void:
	low_quality = low
	for spec: Dictionary in PARTS:
		var part: Node3D = model.find_child(str(spec.name),true,false) as Node3D
		if part == null:
			push_warning("Recommendation orrery pivot missing: "+str(spec.name))
			continue
		var animation: Animation = Animation.new()
		var duration: float = TAU / absf(float(spec.speed))
		animation.length = duration
		animation.loop_mode = Animation.LOOP_LINEAR
		var track: int = animation.add_track(Animation.TYPE_VALUE)
		animation.track_set_path(track,NodePath(".:quaternion"))
		var original: Quaternion = part.quaternion
		# Quarter-turn keys preserve the intended full orbit under quaternion slerp.
		for key: int in range(9):
			var fraction: float = float(key)/8.0
			animation.track_insert_key(track,duration*fraction,original*Quaternion(spec.axis,TAU*fraction*signf(float(spec.speed))))
		var library: AnimationLibrary = AnimationLibrary.new()
		library.add_animation("orbit",animation)
		var player: AnimationPlayer = AnimationPlayer.new()
		player.name = "OrreryMotion"
		part.add_child(player)
		player.add_animation_library("",library)
		player.play("orbit")
		player.pause()
		players[spec.name] = player
	_update_playback()

func set_motion_enabled(value: bool, persist: bool = true) -> void:
	motion_enabled = value
	if persist:
		var settings: ConfigFile = ConfigFile.new()
		settings.set_value("orrery","motion_enabled",value)
		settings.save(SETTINGS_PATH)
	_update_playback()

func set_presentation_active(value: bool) -> void:
	if presentation_active == value:
		return
	presentation_active = value
	_update_playback()

func set_low_quality(value: bool) -> void:
	if low_quality == value:
		return
	low_quality = value
	_update_playback()

func _update_playback() -> void:
	var enabled: bool = motion_enabled and presentation_active and focused and not browser_reduced_motion and not browser_hidden
	for name_value: String in players:
		var player: AnimationPlayer = players[name_value]
		if not is_instance_valid(player):
			continue
		var active: bool = enabled and not (low_quality and name_value=="OrreryInnerRing")
		if active and not player.is_playing():
			player.play()
		elif not active and player.is_playing():
			player.pause()

func _refresh_browser_preferences() -> void:
	if OS.has_feature("web"):
		browser_reduced_motion = bool(JavaScriptBridge.eval("window.matchMedia('(prefers-reduced-motion: reduce)').matches"))
		browser_hidden = bool(JavaScriptBridge.eval("document.hidden"))
	_update_playback()

func _process(delta: float) -> void:
	if not OS.has_feature("web"):
		return
	visibility_clock += delta
	if visibility_clock >= .5:
		visibility_clock = 0.0
		_refresh_browser_preferences()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		focused = false
		_update_playback()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		focused = true
		_refresh_browser_preferences()

func get_state() -> Dictionary:
	var parts: Dictionary = {}
	for name_value: String in players:
		var player: AnimationPlayer = players[name_value]
		if is_instance_valid(player):
			parts[name_value] = {"playing":player.is_playing(),"phase":player.current_animation_position}
	return {"motion_enabled":motion_enabled,"reduced_motion":browser_reduced_motion,"low_quality":low_quality,"parts":parts}
