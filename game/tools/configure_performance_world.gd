extends SceneTree

# Run after build_streaming_world.gd. Edit through Godot's PackedScene API so
# authored hierarchy, resources, lights and environment survive regeneration.
func _initialize() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	for node_name: String in ["Globe", "Neighborhood"]:
		var old: Node = world.get_node(node_name)
		var at: int = old.get_index()
		old.free()
		var file_name: String = "globe_base" if node_name == "Globe" else "neighborhood_base"
		var replacement: Node = (load("res://generated/streaming/" + file_name + ".scn") as PackedScene).instantiate()
		replacement.name = node_name
		world.add_child(replacement)
		world.move_child(replacement, at)
		replacement.owner = world
	(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(world) == OK)
	assert(ResourceSaver.save(packed, "res://scenes/world.tscn") == OK)
	world.free()
	print("PERFORMANCE_WORLD_CONFIGURED")
	quit()
