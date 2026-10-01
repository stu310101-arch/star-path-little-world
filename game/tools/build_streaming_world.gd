extends SceneTree

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	preload("res://tools/streaming_world_builder.gd").new().build()
	quit()
