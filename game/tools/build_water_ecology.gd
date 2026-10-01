extends SceneTree

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	var globe: Node3D = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	# Do not enter the tree: runtime MultiMesh buffers must remain represented
	# by their existing placement metadata while using the dummy renderer.
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var report: Dictionary = preload("res://tools/water_ecology.gd").apply(globe,layout,districts)
	preload("res://scripts/planet_geometry.gd").save_scene(globe,"res://generated/globe.tscn")
	var build_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
	build_report["aquatic_habitats"]=report
	FileAccess.open("res://generated/build_report.json",FileAccess.WRITE).store_string(JSON.stringify(build_report,"\t"))
	globe.free()
	preload("res://tools/streaming_world_builder.gd").new().build()
	print("WATER_ECOLOGY_BUILT "+JSON.stringify(report))
	quit()
