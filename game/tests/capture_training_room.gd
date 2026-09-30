extends "res://tests/check_training_room.gd"

func _initialize() -> void:
	capture_images = true
	call_deferred("run")
