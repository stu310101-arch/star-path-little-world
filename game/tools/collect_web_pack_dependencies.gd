extends SceneTree

# Build-time only. Enumerate dependencies without instantiating the world or
# loading the imported avatar meshes into memory. Dynamic paths are explicit:
# ResourceLoader cannot discover filenames read from JSON or passed to load().
var groups: Dictionary = {}
var graph: Dictionary = {}
var errors: Array[String] = []

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 1:
		push_error("Usage: --script res://tools/collect_web_pack_dependencies.gd -- output.json")
		quit(2)
		return
	var boot: Array[String] = ["res://scenes/world.tscn", "res://generated/streaming/catalog.json"]
	_append_files("res://scripts", boot, ["gd"])
	_append_files("res://data", boot, ["json"])
	# The pack manifest is injected by the post-export splitter, never reused
	# from a previous build in the source tree.
	boot.erase("res://data/web_packs.json")
	groups["boot"] = boot
	groups["avatar"] = ["res://assets/character/graduate.glb", "res://assets/character/graduate_jump.glb", "res://assets/character/graduate_rest.glb"]
	groups["training_room"] = ["res://scenes/training_room.tscn", "res://assets/training_room/wordking_training_room.glb", "res://assets/training_room/layout.json", "res://assets/training_room/textures/starry_night.jpg"]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	for district: Dictionary in catalog.get("districts", []):
		var paths: Array[String] = []
		for chunk: Dictionary in district.get("chunks", []):
			paths.append(str(chunk["path"]))
		var id: String = str(district["id"])
		var group: String = "district_ocean" if id.begins_with("ocean_") else "district_" + id
		if groups.has(group):
			(groups[group] as Array).append_array(paths)
		else:
			groups[group] = paths
	var tracks: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/music_tracks.json")) as Dictionary
	for key: String in tracks:
		groups["music_" + key] = [str(tracks[key]["path"])]
	for roots: Array in groups.values():
		for path: String in roots:
			_visit(path)
	_check_dynamic_literals(boot)
	var output: Dictionary = {"version": 1, "engine": Engine.get_version_info(), "groups": groups, "prerequisites": {"training_room": ["avatar"]}, "dependencies": graph, "errors": errors}
	var file: FileAccess = FileAccess.open(arguments[0], FileAccess.WRITE)
	if file == null:
		push_error("Cannot write dependency inventory: " + arguments[0])
		quit(2)
		return
	file.store_string(JSON.stringify(output, "\t", true) + "\n")
	file.close()
	print("WEB_PACK_DEPENDENCIES resources=%d groups=%d errors=%d" % [graph.size(), groups.size(), errors.size()])
	quit(0 if errors.is_empty() else 1)

func _append_files(directory: String, target: Array[String], extensions: Array[String]) -> void:
	for name: String in DirAccess.get_files_at(directory):
		if name.get_extension() in extensions:
			target.append(directory.path_join(name))
	for name: String in DirAccess.get_directories_at(directory):
		_append_files(directory.path_join(name), target, extensions)

func _check_dynamic_literals(boot: Array[String]) -> void:
	var pattern: RegEx = RegEx.new()
	pattern.compile("[\"'](res://[^\"']+)[\"']")
	for path: String in boot:
		if path.get_extension() != "gd":
			continue
		for match_value: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(path)):
			var referenced: String = match_value.get_string(1)
			if referenced == "res://data/web_packs.json" or referenced.begins_with("res://../deliverables/"):
				continue
			if not graph.has(referenced):
				errors.append("Unclassified runtime literal in %s: %s; add its dynamic root group" % [path, referenced])

func _visit(path: String) -> void:
	if graph.has(path):
		return
	var dependencies: Array[String] = []
	graph[path] = dependencies
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		errors.append("Missing source resource: " + path)
		return
	if path.get_extension() in ["json", "txt"]:
		return
	# GDScript's ResourceLoader dependency list is empty in this engine build.
	# Include literal preloads and script inheritance explicitly; ordinary load
	# string paths are owned by the dynamic root groups above.
	if path.get_extension() == "gd":
		var pattern: RegEx = RegEx.new()
		pattern.compile("(?:preload\\s*\\(\\s*|extends\\s+)[\"'](res://[^\"']+)[\"']")
		for match_value: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(path)):
			var dependency: String = match_value.get_string(1)
			if not dependencies.has(dependency):
				dependencies.append(dependency)
			_visit(dependency)
	for encoded: String in ResourceLoader.get_dependencies(path):
		var parts: PackedStringArray = encoded.split("::")
		var dependency: String = parts[parts.size() - 1]
		if dependency.begins_with("uid://"):
			var uid: int = ResourceUID.text_to_id(dependency)
			dependency = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
		if not dependency.begins_with("res://"):
			errors.append("Unresolved dependency %s of %s" % [encoded, path])
			continue
		if not dependencies.has(dependency):
			dependencies.append(dependency)
		_visit(dependency)
