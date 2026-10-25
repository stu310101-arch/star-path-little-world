extends SceneTree
const OUT: String="res://../build/legacy-render/"
func _initialize() -> void: call_deferred("run")
func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	var paths: Array[String]=["globe_base.scn","neighborhood_base.scn","stations_base.scn"]
	var catalog: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	for row: Dictionary in catalog.districts:
		for chunk: Dictionary in row.chunks: paths.append(str(chunk.path).get_file())
	for filename: String in paths:
		var scene: Node=(load("res://generated/streaming/"+filename) as PackedScene).instantiate()
		strip(scene,scene)
		var packed: PackedScene=PackedScene.new()
		assert(packed.pack(scene)==OK)
		assert(ResourceSaver.save(packed,OUT+filename,ResourceSaver.FLAG_COMPRESS)==OK)
		scene.free()
	var source: String=FileAccess.get_file_as_string("res://scenes/world.tscn")
	source=source.replace("res://generated/streaming/",OUT)
	FileAccess.open(OUT+"world.tscn",FileAccess.WRITE).store_string(source)
	print("LEGACY_RENDER_GEOMETRY_STAGED ",paths.size())
	quit()
func strip(node: Node, owner_node: Node) -> void:
	for key: StringName in node.get_meta_list():
		if str(key).begins_with("mobile_render_"): node.remove_meta(key)
	if node!=owner_node:
		node.scene_file_path=""
		node.owner=owner_node
	for child: Node in node.get_children(): strip(child,owner_node)
