extends "res://scripts/indoor_transition.gd"
## Compatibility entrypoint for existing training-room callers and fixtures.

const ROOM_SCENE: String = "res://scenes/training_room.tscn"

func _init() -> void:
	room_scene_path = ROOM_SCENE
	room_music_context = "wordking"
