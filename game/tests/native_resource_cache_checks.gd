extends SceneTree
const Packs = preload("res://scripts/web_packs.gd")
var failures: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, value: bool) -> void:
	print("NATIVE_RESOURCE_CHECK ",label," ",value)
	if not value:
		failures += 1
func run() -> void:
	var folder: String = "user://qa-resource-cache-%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(folder.path_join("packs"))
	DirAccess.make_dir_recursive_absolute(folder.path_join("installed"))
	var manifest: Dictionary = {"packs":{},"profiles":{"low":["common","low"],"full":["common","full","room_shared"]},"shared_on_demand":["counseling_room","room_shared"],"resources":{"res://qa-counseling-room.glb":"counseling_room"}}
	for id: String in ["common","low","full","counseling_room","room_shared"]:
		var source: String = folder.path_join(id + ".json")
		var file: FileAccess = FileAccess.open(source,FileAccess.WRITE)
		file.store_string(JSON.stringify({"fixture":id}))
		file.close()
		var path: String = folder.path_join("packs/" + id + ".pck")
		var packer: PCKPacker = PCKPacker.new()
		assert(packer.pck_start(ProjectSettings.globalize_path(path)) == OK)
		assert(packer.add_file("res://qa-resource-%d-%s.json" % [OS.get_process_id(),id],source) == OK)
		assert(packer.flush() == OK)
		var input: FileAccess = FileAccess.open(path,FileAccess.READ)
		manifest.packs[id] = {"url":"packs/" + id + ".pck","bytes":input.get_length(),"sha256":FileAccess.get_sha256(path),"dependencies":[],"startup":false}
		input.close()
	manifest.packs.counseling_room.dependencies = ["room_shared"]
	var service: Node = Packs.new()
	root.add_child(service)
	service.set("_native_directory",ProjectSettings.globalize_path(folder))
	service.call("configure",manifest,"",ProjectSettings.globalize_path(folder.path_join("installed")))
	service.call("select_profile","low")
	service.call("start_all_downloads")
	await wait_profile(service,"low")
	check("first installation caches only chosen profile",service.call("profile_cached","low") and not service.call("profile_cached","full"))
	check("optional room is not installed during entry",not FileAccess.file_exists(folder.path_join("installed/counseling_room.pck")) and not FileAccess.file_exists(folder.path_join("installed/room_shared.pck")))
	service.call("request_resource","res://qa-counseling-room.glb",100)
	var deadline: int = Time.get_ticks_msec() + 10000
	while not service.call("is_resource_ready","res://qa-counseling-room.glb") and Time.get_ticks_msec() < deadline:
		await process_frame
	check("entering optional room caches its complete closure",service.call("is_resource_ready","res://qa-counseling-room.glb") and FileAccess.file_exists(folder.path_join("installed/room_shared.pck")))
	service.call("request_profile","full")
	await wait_profile(service,"full")
	check("both profiles can be retained",service.call("profile_cached","low") and service.call("profile_cached","full"))
	service.call("delete_cached_profile","low","full")
	check("deleting low preserves full and common bytes",not service.call("profile_cached","low") and service.call("profile_cached","full"))
	service.call("request_profile","low")
	await wait_profile(service,"low")
	check("deleted profile can be installed again",service.call("profile_cached","low"))
	service.call("delete_cached_profile","full","low")
	check("deleting full preserves low and common bytes",not service.call("profile_cached","full") and service.call("profile_cached","low"))
	check("deleting full retains fetched shared room and dependency",FileAccess.file_exists(folder.path_join("installed/counseling_room.pck")) and FileAccess.file_exists(folder.path_join("installed/room_shared.pck")) and service.call("is_resource_ready","res://qa-counseling-room.glb"))
	service.queue_free()
	await process_frame
	print("NATIVE_RESOURCE_CACHE_RESULTS failures=",failures)
	quit(1 if failures else 0)
func wait_profile(service: Node, profile: String) -> void:
	var deadline: int = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		var state: Dictionary = service.call("profile_progress",profile)
		if bool(state.ready):
			return
		if not str(state.error).is_empty():
			check(str(state.error),false)
			return
		await process_frame
	check("profile completes within test deadline",false)
