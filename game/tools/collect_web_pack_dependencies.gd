extends SceneTree

# Build-time only. Enumerate dependencies without instantiating the world or
# loading the imported avatar meshes into memory. Dynamic paths are explicit:
# ResourceLoader cannot discover filenames read from JSON or passed to load().
var groups: Dictionary = {}
var graph: Dictionary = {}
var errors: Array[String] = []
var mobile_export: bool = false
var native_export: bool = false

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	mobile_export = arguments.has("--mobile")
	native_export = arguments.has("--native")
	if arguments.size() != (2 if mobile_export or native_export else 1):
		push_error("Usage: --script res://tools/collect_web_pack_dependencies.gd -- output.json [--mobile]")
		quit(2)
		return
	var boot: Array[String] = ["res://scenes/login_entry.tscn", "res://scenes/training_room.tscn", "res://scenes/university_hall.tscn", "res://scenes/admissions_room.tscn", "res://scenes/counseling_room.tscn", "res://scenes/recommendation_room.tscn", "res://scenes/discussion_garden.tscn"]
	_append_files("res://scripts", boot, ["gd"])
	boot.erase("res://scripts/world_art_direction.gd")
	_append_files("res://data", boot, ["json"])
	# Architecture's dynamic material filenames are also used outside the hall.
	for kind: String in ["stone","stone_dark","plaster"]:
		for channel: String in ["base","rough","normal"]:
			boot.append("res://assets/university_hall/textures/%s_%s.png" % [kind,channel])
	# The pack manifest is injected by the post-export splitter, never reused
	# from a previous build in the source tree.
	boot.erase("res://data/web_packs.json")
	groups["boot"] = boot
	groups["world_full"] = ["res://scenes/world.tscn", "res://generated/streaming/catalog.json", "res://scripts/world_art_direction.gd"]
	groups["world_low"] = ["res://scenes/world_low.tscn", "res://generated/low/streaming/catalog.json"]
	groups["university_low"] = ["res://generated/low/university/atrium.scn", "res://generated/low/university/gallery.scn", "res://generated/low/university/exhibit_kit.scn", "res://generated/low/university/feature_book.scn", "res://generated/low/university/layout.json"]
	groups["discussion_pack_low"] = ["res://generated/low/discussion/garden.scn", "res://generated/low/discussion/device.scn", "res://generated/low/discussion/layout.json"]
	# Matching outdoor/indoor actors use the original pose. Keep the alternate
	# low-seat pose classified while BenchPose retains that dynamic fallback.
	groups["avatar_common"] = ["res://assets/character/graduate_rest.glb", "res://assets/character/graduate_rest_small.glb"]
	groups["avatar_low"] = ["res://assets/character/runtime_mobile/graduate.glb", "res://assets/character/runtime_mobile/graduate_jump.glb"]
	groups["avatar"] = []
	# Desktop texture fallback on a phone also selects the light avatar. The
	# ETC2 mobile export excludes the large desktop cloth assets altogether.
	if not mobile_export:
		groups["avatar"].append_array(["res://assets/character/runtime/graduate.glb", "res://assets/character/runtime/graduate_jump.glb"] if native_export else ["res://assets/character/runtime_web/graduate.glb", "res://assets/character/runtime_web/graduate_jump.glb"])
		# A phone that needs S3TC still keeps the existing mobile actor choice.
		if not native_export:
			groups["avatar_mobile"] = groups["avatar_low"].duplicate()
	else:
		groups["avatar"] = groups["avatar_low"].duplicate()
	if native_export:
		boot.append_array(["res://addons/godot_wry/WRY.gdextension", "res://web_games/native_go.html", "res://web_games/go/index.html"])
	groups["font_fallback"] = ["res://assets/fonts/web/NotoSansTC-full.ttf"]
	var interior: Array[String] = ["res://generated/training_room/light.scn", "res://assets/training_room/layout.json", "res://generated/training_room/detail_catalog.json", "res://assets/exhibits/furina/furina_splendor.glb"]
	_append_files("res://generated/training_room/detail", interior, ["res"])
	groups["training_room"] = interior
	# Keep legacy art sources in the project without shipping unused exhibits.
	# Imported mesh dependencies bring in only the canonical textures they use.
	var university: Array[String] = [
		"res://assets/university_hall/atrium.glb",
		"res://assets/university_hall/gallery.glb",
		"res://assets/university_hall/exhibit_kit.glb",
		"res://assets/university_hall/feature_book.glb",
		"res://assets/university_hall/layout.json"
	]
	groups["university_hall"] = university
	# The room script stays in boot; authored meshes/layout load on entry.
	groups["admissions_low"] = ["res://generated/low/admissions/studio.scn", "res://generated/low/admissions/layout.json"]
	groups["training_low"] = ["res://generated/low/training/room.scn", "res://generated/low/training/layout.json"]
	groups["admissions_room"] = ["res://assets/admissions_room/admissions_studio.glb", "res://assets/admissions_room/layout.json"]
	# Full room remains deferred; low uses a separate, installed art copy.
	groups["counseling_room"] = ["res://assets/counseling_room/counseling_room.glb", "res://assets/counseling_room/layout.json"]
	groups["counseling_low"] = ["res://generated/low/counseling/room.scn", "res://generated/low/counseling/layout.json"]
	groups["recommendation_room"] = ["res://assets/recommendation_room/recommendation_room.glb", "res://assets/recommendation_room/layout.json"]
	groups["recommendation_low"] = ["res://generated/low/recommendation/recommendation_room.glb", "res://generated/low/recommendation/layout.json"]
	# The minimum profile must never download the standard geometry. Shared
	# devices/layout remain a third pack; image dependencies deduplicate normally.
	groups["discussion_common"] = ["res://assets/discussion_garden/message_device.glb", "res://assets/discussion_garden/layout.json"]
	groups["discussion_garden"] = ["res://assets/discussion_garden/garden.glb"]
	groups["discussion_garden_low"] = ["res://assets/discussion_garden/garden_low.glb"]
	var garden_layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/discussion_garden/layout.json")) as Dictionary
	for zone: Dictionary in garden_layout.get("zones", []):
		var device: String = str(zone.get("device_model", "message_device.glb"))
		if not device.begins_with("res://"):
			device = "res://assets/discussion_garden/".path_join(device)
		if device not in groups["discussion_common"]:
			groups["discussion_common"].append(device)
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
	var common: Array[String] = ["avatar_common", "font_fallback"]
	for key: String in groups:
		if key.begins_with("music_"):
			common.append(key)
	var full_groups: Array[String] = ["world_full", "avatar", "admissions_room", "training_room", "university_hall", "discussion_common", "discussion_garden", "discussion_garden_low"]
	if groups.has("avatar_mobile"):
		full_groups.append("avatar_mobile")
	for key: String in groups:
		if key.begins_with("district_"):
			full_groups.append(key)
	var low_groups: Array[String] = ["world_low", "avatar_low", "university_low", "discussion_pack_low", "admissions_low", "training_low", "counseling_low"]
	var profiles: Dictionary = {"full":common + full_groups, "low":common + low_groups}
	var output: Dictionary = {"version": 1, "engine": Engine.get_version_info(), "groups": groups, "profiles":profiles, "shared_on_demand":["counseling_room", "recommendation_room", "recommendation_low"], "prerequisites": {"discussion_garden":["discussion_common"], "discussion_garden_low":["discussion_common"]}, "dependencies": graph, "errors": errors}
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
			# save_scene() is a build-tool helper in the shared geometry module;
			# canonical masters are intentionally excluded from the game export.
			if path == "res://scripts/planet_geometry.gd" and referenced in ["res://generated/globe.tscn","res://generated/globe.scn"]:
				continue
			if path == "res://scripts/world_architecture.gd" and referenced == "res://assets/university_hall/textures/":
				continue # Concrete material filenames are explicit boot roots above.
			# These two literals are selected only by the native branch. Web has
			# separately classified copies and deliberately excludes native meshes.
			if not native_export and path == "res://scripts/planet_player.gd" and referenced in ["res://assets/character/runtime/graduate.glb", "res://assets/character/runtime/graduate_jump.glb"]:
				continue
			if native_export and path == "res://scripts/planet_player.gd" and referenced in ["res://assets/character/runtime_web/graduate.glb", "res://assets/character/runtime_web/graduate_jump.glb"]:
				continue
			if mobile_export and path == "res://scripts/planet_player.gd" and referenced in ["res://assets/character/runtime_web/graduate.glb", "res://assets/character/runtime_web/graduate_jump.glb"]:
				continue
			# This host is guarded by the Windows feature check. Browser Go is
			# delivered separately by package_training_games, without native WRY.
			if path == "res://scripts/native_computer_game.gd" and referenced in ["res://addons/godot_wry/WRY.gdextension", "res://web_games/native_go.html", "res://web_games/go/index.html"]:
				continue
			if path == "res://scripts/account_native_host.gd" and referenced == "res://addons/godot_wry/WRY.gdextension":
				continue # Account WebView is Windows-only; Web uses a lazy same-origin iframe.
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
