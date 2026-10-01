extends SceneTree

# Run from an empty directory, not the game checkout, so a missing exported
# resource cannot silently fall back to the imported development project.
var failures: Array[String] = []
var loaded_count: int = 0

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.size() != 2:
		push_error("Usage: --script validate_web_packs.gd -- absolute_web_folder dependency_inventory.json")
		quit(2)
		return
	var folder: String = arguments[0]
	var side_manifest: String = FileAccess.get_file_as_string(folder.path_join("index.packs.json"))
	var manifest: Dictionary = JSON.parse_string(side_manifest) as Dictionary
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(arguments[1])) as Dictionary
	if not ProjectSettings.load_resource_pack(folder.path_join("index.pck"), true):
		push_error("Godot could not mount the boot PCK")
		quit(1)
		return
	if FileAccess.get_file_as_string("res://data/web_packs.json") != side_manifest:
		failures.append("Embedded and side pack manifests differ")
	for pack_id: String in (manifest.get("packs", {}) as Dictionary):
		var entry: Dictionary = manifest["packs"][pack_id] as Dictionary
		var path: String = folder.path_join(str(entry["url"]))
		if FileAccess.get_sha256(path) != str(entry["sha256"]):
			failures.append("SHA-256 differs: " + pack_id)
		if not ProjectSettings.load_resource_pack(path, true):
			failures.append("Godot could not mount: " + pack_id)
	# --main-pack must also point at the boot PCK so Godot populates the exported
	# script class cache before parsing compiled runtime scripts. Every resource
	# is decoded one at a time, without instantiating scenes or running gameplay.
	var dependencies: Dictionary = inventory["dependencies"] as Dictionary
	for path: String in dependencies:
		var extension: String = path.get_extension()
		if extension in ["json", "txt"]:
			if not FileAccess.file_exists(path):
				failures.append("Raw resource missing: " + path)
			continue
		if not ResourceLoader.exists(path):
			failures.append("Imported/remapped resource missing: " + path)
			continue
		var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resource == null:
			failures.append("Godot could not decode: " + path)
		elif resource is GDScript and not (resource as GDScript).can_instantiate():
			failures.append("Compiled script is not valid: " + path)
		else:
			loaded_count += 1
		resource = null
		await process_frame
	print("WEB_PACK_VALIDATION " + JSON.stringify({"packs": (manifest["packs"] as Dictionary).size() + 1, "source_resources": dependencies.size(), "decoded_imports": loaded_count, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
