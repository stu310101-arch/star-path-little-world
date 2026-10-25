extends Node

## Preserves one outdoor world while an independently loaded interior is active.
var room_scene_path: String = ""
var room_music_context: String = "world"
var last_error: String = ""

var suspended_world: Node3D
var room: Node3D
var return_token: Dictionary = {}
var shared_music: Node
var returning: bool = false
var suspended_streaming: Node
var related_origin: Dictionary = {}
var switching_room: bool = false
const UNIVERSITY_SCENE: String = "res://scenes/university_hall.tscn"

func open_from_world(source: Node3D, token: Dictionary, scene_path: String = "", music_context: String = "") -> bool:
	if suspended_world != null or room != null or returning:
		return false
	last_error = ""
	var target: String = room_scene_path if scene_path.is_empty() else scene_path
	var context: String = room_music_context if music_context.is_empty() else music_context
	if not is_instance_valid(source) or not source.is_inside_tree() or target.is_empty() or not ResourceLoader.exists(target):
		last_error = "無法開啟室內空間，請重試。"
		return false
	var packed: PackedScene = load(target) as PackedScene
	if packed == null:
		last_error = "室內場景讀取失敗，請重試。"
		return false
	var instance: Node = packed.instantiate()
	var candidate: Node3D = instance as Node3D
	if candidate == null or not candidate.has_signal("request_return_to_world"):
		if instance != null:
			instance.free()
		last_error = "室內場景缺少返回出口。"
		return false
	suspended_world = source
	return_token = token.duplicate(true)
	room = candidate
	room_scene_path = target
	room_music_context = context
	_wire_room(room)
	suspended_streaming = source.get("streaming") as Node
	if suspended_streaming != null and suspended_streaming.has_method("set_interior_active"):
		suspended_streaming.call("set_interior_active", true)
	shared_music = source.get("music") as Node
	if is_instance_valid(shared_music):
		move_music(self)
		shared_music.call("set_context", context)
		if room.has_method("set_shared_music"):
			room.call("set_shared_music", shared_music)
	# Retain the actual world instance, including NPCs, camera and exploration
	# state. Removing it also removes its lights, physics and input handlers.
	get_tree().current_scene = null
	source.get_parent().remove_child(source)
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("INDOOR_ENTERED scene=", room_scene_path, " world_instance=", suspended_world.get_instance_id())
	return true

func _wire_room(candidate: Node3D) -> void:
	candidate.set("graphics_settings", get_tree().get_first_node_in_group("graphics_settings"))
	candidate.connect("request_return_to_world", _room_return_requested.bind(candidate.get_instance_id()))
	if candidate.has_signal("request_related_room"):
		candidate.connect("request_related_room", _visit_university.bind(candidate.get_instance_id()))

func _room_return_requested(instance_id: int) -> void:
	if returning or switching_room or not is_instance_valid(room) or room.get_instance_id() != instance_id:
		return
	if related_origin.is_empty():
		return_to_world()
	else:
		switching_room = true
		_restore_related.call_deferred()

func _visit_university(school_id: String, state: Dictionary, instance_id: int) -> void:
	if returning or switching_room or not related_origin.is_empty() or not is_instance_valid(room) or room.get_instance_id() != instance_id:
		return
	if school_id.length() != 3 or not school_id.is_valid_int() or int(school_id) < 1 or int(school_id) > 138:
		last_error = "校園導覽資料尚未確認。"
		return
	var saved: Dictionary = room.call("capture_return_state") if room.has_method("capture_return_state") else state
	# Keep only a state descriptor, never a second live room or another outdoor world.
	related_origin = {"scene":room_scene_path,"music":room_music_context,"state":saved.duplicate(true)}
	switching_room = true
	_open_related.call_deferred(school_id)

func _open_related(school_id: String) -> void:
	if returning:
		return
	var candidate: Node3D = _related_candidate(UNIVERSITY_SCENE)
	if candidate == null:
		related_origin.clear()
		switching_room = false
		return
	candidate.set("initial_school_id", school_id)
	candidate.set("return_label", "返回推薦")
	_replace_room(candidate, UNIVERSITY_SCENE, "universities")

func _restore_related() -> void:
	if returning or related_origin.is_empty():
		return
	var target: String = str(related_origin.scene)
	var candidate: Node3D = _related_candidate(target)
	if candidate == null:
		switching_room = false
		# The hall has already disabled movement for its return action.
		if is_instance_valid(room):
			room.set("returning", false)
			if room.has_method("_modal_changed"):
				room.call("_modal_changed", false)
		return
	if candidate.has_method("restore_return_state"):
		candidate.call("restore_return_state", related_origin.state)
	var context: String = str(related_origin.music)
	related_origin.clear()
	_replace_room(candidate, target, context)

func _related_candidate(path: String) -> Node3D:
	if not ResourceLoader.exists(path):
		last_error = "室內場景暫時無法開啟，請重試。"
		return null
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		last_error = "室內場景讀取失敗，請重試。"
		return null
	var instance: Node = packed.instantiate()
	if not instance is Node3D or not instance.has_signal("request_return_to_world"):
		instance.free()
		last_error = "室內場景缺少返回出口。"
		return null
	return instance as Node3D

func _replace_room(candidate: Node3D, target: String, context: String) -> void:
	_wire_room(candidate)
	if is_instance_valid(shared_music):
		shared_music.call("set_context", context)
		if candidate.has_method("set_shared_music"):
			candidate.call("set_shared_music", shared_music)
	get_tree().current_scene = null
	if is_instance_valid(room):
		if room.get_parent() != null:
			room.get_parent().remove_child(room)
		room.queue_free()
	room = candidate
	room_scene_path = target
	room_music_context = context
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	switching_room = false
	last_error = ""
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func return_to_world() -> void:
	if returning or not is_instance_valid(suspended_world):
		return
	returning = true
	related_origin.clear()
	call_deferred("finish_return")

func finish_return() -> void:
	var tree: SceneTree = get_tree()
	tree.current_scene = null
	if is_instance_valid(room):
		if room.get_parent() != null:
			room.get_parent().remove_child(room)
		room.queue_free()
		room = null
	if is_instance_valid(suspended_streaming) and suspended_streaming.has_method("set_interior_active"):
		suspended_streaming.call("set_interior_active", false)
	tree.root.add_child(suspended_world)
	tree.current_scene = suspended_world
	if is_instance_valid(shared_music):
		move_music(suspended_world)
	suspended_world.call("resume_world", return_token)
	var world_camera: Camera3D = suspended_world.get("camera") as Camera3D
	if world_camera != null:
		world_camera.make_current()
	suspended_world.call("update_camera", 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("INDOOR_RETURNED scene=", room_scene_path, " world_instance=", suspended_world.get_instance_id())
	suspended_world = null
	queue_free()

func _process(_delta: float) -> void:
	# The world is detached, so its normal process loop cannot release details.
	# Keep the one-chunk release budget while the lightweight room is playable.
	if not returning and is_instance_valid(suspended_streaming) and suspended_streaming.has_method("step_suspended_release"):
		suspended_streaming.call("step_suspended_release")

func move_music(destination: Node) -> void:
	# AudioStreamPlayer stops when removed from the tree; preserve the existing
	# voices and cursor positions while moving the one shared music controller.
	var playback: Array[Dictionary] = []
	for child: Node in shared_music.get_children():
		var voice: AudioStreamPlayer = child as AudioStreamPlayer
		if voice != null and voice.has_stream_playback():
			playback.append({"voice":voice, "position":voice.get_playback_position(), "paused":voice.stream_paused})
	shared_music.reparent(destination)
	for record: Dictionary in playback:
		var voice: AudioStreamPlayer = record.voice as AudioStreamPlayer
		voice.play(float(record.position))
		voice.stream_paused = bool(record.paused)

func _notification(what: int) -> void:
	if not is_instance_valid(shared_music):
		return
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		shared_music.call("set_background_paused", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		shared_music.call("set_background_paused", false)

func _exit_tree() -> void:
	# An ordinary app exit while indoors must also release the detached world.
	if is_instance_valid(suspended_world) and suspended_world.get_parent() == null:
		suspended_world.free()
		suspended_world = null
