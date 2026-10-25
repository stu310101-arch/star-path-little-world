extends RefCounted
## Warm this player's existing avatar choices without modifying the shared player
## or choosing different art. Retained PackedScenes make its later load() a cache hit.
const LoadReaper = preload("res://scripts/university_load_reaper.gd")
var paths: Array[String] = []
var error: String = ""
var pending_path: String = ""
var _index: int = 0
var _retained: Array[PackedScene] = []
var _tree: SceneTree
var _cancelled: bool = false
var _last_step_usec: int = 0
var _max_step_usec: int = 0

func configure(player: Node, tree: SceneTree) -> void:
	_tree = tree
	for key: String in ["_walk_model_path","_jump_model_path"]:
		var path: String = str(player.get(key))
		if not path.is_empty() and path not in paths: paths.append(path)
	var packs: Node = tree.root.get_node_or_null("WebPacks")
	if packs != null:
		for path: String in paths: packs.call("request_resource",path,20)

func step() -> bool:
	if _cancelled or not error.is_empty(): return false
	if _index >= paths.size(): return true
	var started: int = Time.get_ticks_usec()
	var result: bool = _step_load()
	_last_step_usec = Time.get_ticks_usec()-started
	_max_step_usec = maxi(_max_step_usec,_last_step_usec)
	return result

func _step_load() -> bool:
	var path: String = paths[_index]
	var packs: Node = _tree.root.get_node_or_null("WebPacks") if _tree != null else null
	if packs != null:
		var pack_error: String = str(packs.call("resource_error",path))
		if not pack_error.is_empty():
			error = pack_error
			return false
		if not bool(packs.call("is_resource_ready",path)): return false
	if pending_path.is_empty():
		if ResourceLoader.has_cached(path):
			var cached: PackedScene = ResourceLoader.load(path,"PackedScene",ResourceLoader.CACHE_MODE_REUSE) as PackedScene
			if cached != null:
				_retained.append(cached)
				_index += 1
				return _index >= paths.size()
		if ResourceLoader.load_threaded_request(path,"PackedScene",false,ResourceLoader.CACHE_MODE_REUSE) != OK:
			error = "角色模型無法開始載入。"
			return false
		pending_path = path
		return false
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS: return false
	if status in [ResourceLoader.THREAD_LOAD_FAILED,ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		if status == ResourceLoader.THREAD_LOAD_FAILED: ResourceLoader.load_threaded_get(path)
		pending_path = ""
		error = "角色模型載入失敗，請重試。"
		return false
	var loaded: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	pending_path = ""
	if loaded == null:
		error = "角色模型內容無效。"
		return false
	_retained.append(loaded)
	_index += 1
	return _index >= paths.size()

func retry() -> void:
	error = ""
	_cancelled = false
	var packs: Node = _tree.root.get_node_or_null("WebPacks") if _tree != null else null
	if packs != null and _index < paths.size(): packs.call("retry_resource",paths[_index])

func release_completed() -> void:
	_retained.clear()

func cancel() -> void:
	_cancelled = true
	if not pending_path.is_empty() and _tree != null:
		var reaper: Node = LoadReaper.new()
		reaper.name = "DiscussionAvatarPendingLoad"
		reaper.process_mode = Node.PROCESS_MODE_ALWAYS
		reaper.set("path",pending_path)
		_tree.root.call_deferred("add_child",reaper)
		pending_path = ""
	_retained.clear()

func metrics() -> Dictionary:
	return {"paths":paths.duplicate(),"completed":_index,"retained":_retained.size(),"pending":pending_path,"last_step_usec":_last_step_usec,"max_step_usec":_max_step_usec,"cancelled":_cancelled,"error":error}
