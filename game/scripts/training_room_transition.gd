extends Node

const ROOM_SCENE: String = "res://scenes/training_room.tscn"

var suspended_world: Node3D
var room: Node3D
var return_token: Dictionary = {}
var shared_music: Node
var returning: bool = false

func open_from_world(source: Node3D, token: Dictionary) -> bool:
	if suspended_world != null or room != null:
		return false
	var packed: PackedScene = load(ROOM_SCENE) as PackedScene
	if packed == null:
		push_error("Unable to load the training room.")
		return false
	var candidate: Node3D = packed.instantiate() as Node3D
	if candidate == null or not candidate.has_signal("request_return_to_world"):
		if candidate != null:
			candidate.free()
		push_error("Training room must expose request_return_to_world.")
		return false
	suspended_world = source
	return_token = token.duplicate(true)
	room = candidate
	room.connect("request_return_to_world", return_to_world)
	shared_music = source.get("music") as Node
	if shared_music != null:
		move_music(self)
		shared_music.call("set_context", "wordking")
		if room.has_method("set_shared_music"):
			room.call("set_shared_music", shared_music)
	# Retain the actual world instance, including NPCs, camera and exploration
	# state. Removing it also removes its lights, physics and input handlers.
	get_tree().current_scene = null
	source.get_parent().remove_child(source)
	get_tree().root.add_child(room)
	get_tree().current_scene = room
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("TRAINING_ROOM_ENTERED world_instance=", suspended_world.get_instance_id())
	return true

func return_to_world() -> void:
	if returning or suspended_world == null:
		return
	returning = true
	call_deferred("finish_return")

func finish_return() -> void:
	var tree: SceneTree = get_tree()
	tree.current_scene = null
	if is_instance_valid(room):
		if room.get_parent() != null:
			room.get_parent().remove_child(room)
		room.queue_free()
		room = null
	tree.root.add_child(suspended_world)
	tree.current_scene = suspended_world
	if shared_music != null:
		move_music(suspended_world)
	suspended_world.call("resume_world", return_token)
	var world_camera: Camera3D = suspended_world.get("camera") as Camera3D
	if world_camera != null:
		world_camera.make_current()
	suspended_world.call("update_camera", 0.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("TRAINING_ROOM_RETURNED world_instance=", suspended_world.get_instance_id())
	suspended_world = null
	queue_free()

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
