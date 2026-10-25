extends SceneTree
func _initialize() -> void:
 call_deferred("run")
func run() -> void:
 var globe := (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
 var layout := JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
 var districts := JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
 preload("res://tools/open_freshwater_basins.gd").apply(globe,layout,districts)
 preload("res://scripts/planet_geometry.gd").save_scene(globe,"res://generated/globe.tscn")
 globe.free()
 var success: bool=preload("res://tools/streaming_world_builder.gd").new().build()
 quit(0 if success else 1)
