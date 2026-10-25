extends SceneTree

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	var succeeded: bool = preload("res://tools/minimap_geometry_builder.gd").new().build()
	quit(0 if succeeded else 1)
