extends SceneTree
## Run from an empty directory with --main-pack=<the generated boot pack>.
var failures: Array[String] = []
var mounted: Array[String] = []
func _initialize() -> void: run.call_deferred()
func mount_pack(id: String, manifest: Dictionary, folder: String) -> void:
	if id in mounted: return
	var record: Dictionary = manifest.packs[id]
	for dependency: String in record.dependencies: mount_pack(dependency,manifest,folder)
	if not ProjectSettings.load_resource_pack(folder.path_join(record.url),true): failures.append("Could not mount "+id)
	mounted.append(id)
func run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size()!=3:
		push_error("Expected split export directory, inventory JSON, output JSON")
		quit(2)
		return
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0].path_join("index.packs.json")))
	var inventory: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[1]))
	mount_pack("discussion_garden_low",manifest,args[0])
	if "discussion_garden" in mounted: failures.append("Standard geometry pack was mounted")
	if ResourceLoader.exists("res://assets/discussion_garden/garden.glb"): failures.append("Standard scene unexpectedly readable from minimum closure")
	var pending: Array = inventory.groups.discussion_garden_low.duplicate()
	pending.append_array(inventory.groups.discussion_common)
	var decoded: Array[String] = []
	while not pending.is_empty():
		var path: String = str(pending.pop_back())
		if path in decoded: continue
		decoded.append(path)
		pending.append_array(inventory.dependencies[path])
		if path.get_extension()=="json":
			if not FileAccess.file_exists(path): failures.append("Missing "+path)
		else:
			var resource: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
			if resource==null: failures.append("Cannot decode "+path)
		await process_frame
	var report: Dictionary = {"mounted":mounted,"decoded_count":decoded.size(),"decoded":decoded,"standard_available":ResourceLoader.exists("res://assets/discussion_garden/garden.glb"),"failures":failures}
	var file := FileAccess.open(args[2],FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DISCUSSION_PACK_CLOSURE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
