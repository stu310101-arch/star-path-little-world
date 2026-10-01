extends Node

signal chunk_added(root: Node3D)
signal chunk_removing(root: Node3D)
signal district_ready(id: String)

# Chord distances on the radius-48 globe, shared across Web and native builds.
# A 12 m hysteresis band and grace period prevent boundary thrashing.
const CATALOG: String = "res://generated/streaming/catalog.json"
const LOAD_DISTANCE: float = 45.0
const ACTIVE_DISTANCE: float = 38.0
const UNLOAD_DISTANCE: float = 57.0
const UNLOAD_DELAY: float = 4.0
const CONTEXT_INTERVAL: float = .15
const OVERVIEW_DETAIL_CAMERA_ALTITUDE: float = 70.0
const PIN_SECONDS: float = 20.0
var _world: Node3D
var _regions: Dictionary = {}
var _clock: float = 0.0
var _context_clock: float = 0.0
var _pending_scene: PackedScene
var _pending_id: String = ""
var _pending_path: String = ""
var _pin_position: Vector3 = Vector3.ZERO
var _pin_until: float = -1.0
var _actor_state: Dictionary = {}
var _last_operation_ms: float = 0.0
var _max_operation_ms: float = 0.0
var _loaded_count: int = 0
var _operation_count: int = 0
var _overview: bool = true
var _radius: float = 48.0

func configure(world: Node3D, catalog_path: String = CATALOG) -> void:
	_world = world
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path)) as Dictionary
	_radius = float(catalog.get("radius", 48.0))
	for row: Dictionary in catalog.get("districts", []):
		var center: Array = row.center as Array
		_regions[str(row.id)] = {"center":Vector3(center[0],center[1],center[2]),"chunks":row.chunks,"roots":[],"next":0,"wanted":false,"requested":false,"active":false,"outside_since":0.0,"ready":false,"overview":null,"failed":false,"priority":INF}
	for container_name: String in ["Globe", "Neighborhood"]:
		var container: Node = world.get_node_or_null(container_name)
		if container == null:
			continue
		for child: Node in container.get_children():
			var id: String = str(child.get_meta("streaming_overview_id", ""))
			if _regions.has(id):
				_regions[id].overview = child

func pin_position(point: Vector3) -> void:
	_pin_position = point
	_pin_until = _clock + PIN_SECONDS
	_context_clock = CONTEXT_INTERVAL
	for id: String in _required_ids(point):
		_regions[id].wanted = true
		_regions[id].requested = true
		_regions[id].priority = -100.0 + point.distance_to(_regions[id].center as Vector3)

func is_position_ready(point: Vector3) -> bool:
	for id: String in _required_ids(point):
		if not bool(_regions[id].ready):
			return false
	return true

func _required_ids(point: Vector3) -> Array[String]:
	var result: Array[String] = []
	var nearest: String = ""
	var distance: float = INF
	for id: String in _regions:
		var d: float = point.distance_to(_regions[id].center as Vector3)
		if d <= ACTIVE_DISTANCE:
			result.append(id)
		if not id.begins_with("ocean_") and d < distance:
			distance = d
			nearest = id
	if not nearest.is_empty() and not result.has(nearest):
		result.append(nearest)
	return result

func update_context(overview: bool, player_position: Vector3, camera_position: Vector3, target: Vector3, delta: float) -> void:
	_clock += delta
	_context_clock += delta
	if _overview != overview:
		_context_clock = CONTEXT_INTERVAL
		if overview:
			_pin_until = -1.0
	_overview = overview
	if _context_clock >= CONTEXT_INTERVAL:
		_context_clock = 0.0
		_refresh_context(player_position, camera_position, target)
	# Web uses the existing single-thread export. Binary chunks bound each
	# synchronous engine operation; load and instantiate occur on separate
	# frames. This is scheduling local PCK resources, not network streaming.
	_step()

func _refresh_context(player_position: Vector3, camera_position: Vector3, _target: Vector3) -> void:
	var close_overview: bool = _overview and camera_position.length() - _radius <= OVERVIEW_DETAIL_CAMERA_ALTITUDE
	var focus: Vector3 = camera_position.normalized() * _radius if close_overview else player_position
	var pinned: Array[String] = []
	if _clock < _pin_until:
		pinned = _required_ids(_pin_position)
	var required: Array[String] = []
	if not _overview:
		required = _required_ids(focus)
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		var distance: float = focus.distance_to(region.center as Vector3)
		var pin: bool = pinned.has(id)
		var eligible: bool = not _overview or close_overview
		var wanted: bool = pin or (eligible and (distance < LOAD_DISTANCE or required.has(id)))
		region.requested = wanted
		if wanted:
			region.wanted = true
			region.outside_since = _clock
		elif not eligible or distance > UNLOAD_DISTANCE:
			if _clock - float(region.outside_since) >= UNLOAD_DELAY:
				region.wanted = false
		else:
			# Time spent in the hysteresis band is retention, not unload grace.
			# Start the delay only after crossing the outer boundary.
			region.outside_since = _clock
		region.priority = distance - (100.0 if pin else 0.0)
		var active_distance: float = LOAD_DISTANCE if bool(region.active) else ACTIVE_DISTANCE
		var active: bool = eligible and distance <= active_distance and bool(region.ready)
		_set_active(region, active)

func _set_active(region: Dictionary, active: bool) -> void:
	region.active = active
	var silhouette: Node3D = region.overview as Node3D
	if is_instance_valid(silhouette):
		silhouette.visible = not active
	for chunk: Node3D in region.roots:
		chunk.visible = active
		chunk.process_mode = Node.PROCESS_MODE_INHERIT if active and not _overview else Node.PROCESS_MODE_DISABLED

func _step() -> void:
	var started: int = Time.get_ticks_usec()
	if _pending_scene != null:
		var region: Dictionary = _regions[_pending_id]
		if bool(region.wanted) and bool(region.requested):
			var chunk: Node3D = _pending_scene.instantiate() as Node3D
			if chunk != null:
				chunk.set_meta("camera_region", true)
				chunk.visible = false
				chunk.process_mode = Node.PROCESS_MODE_DISABLED
				_world.add_child(chunk)
				_restore_actor_state(chunk, _pending_path)
				(region.roots as Array).append(chunk)
				region.next += 1
				_loaded_count += 1
				chunk_added.emit(chunk)
				if int(region.next) == (region.chunks as Array).size():
					region.ready = true
					_context_clock = CONTEXT_INTERVAL
					district_ready.emit(_pending_id)
			else:
				region.failed = true
		_pending_scene = null
		_pending_id = ""
		_pending_path = ""
		_record_operation(started)
		return
	# Release one chunk per frame too; avoid freeing a whole district in one
	# operation. Camera indexes receive a removal signal before nodes die.
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		if not bool(region.wanted) and not (region.roots as Array).is_empty():
			_set_active(region, false)
			region.ready = false
			var roots: Array = region.roots as Array
			var chunk: Node3D = roots.pop_back() as Node3D
			var index: int = roots.size()
			_store_actor_state(chunk, str(region.chunks[index].path))
			chunk_removing.emit(chunk)
			chunk.queue_free()
			region.next = roots.size()
			_loaded_count -= 1
			_record_operation(started)
			return
	var best_id: String = ""
	var priority: float = INF
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		if bool(region.requested) and not bool(region.ready) and not bool(region.failed) and float(region.priority) < priority:
			best_id = id
			priority = float(region.priority)
	if best_id.is_empty():
		return
	var best: Dictionary = _regions[best_id]
	if int(best.next) >= (best.chunks as Array).size():
		best.ready = true
		district_ready.emit(best_id)
		return
	_pending_id = best_id
	_pending_path = str(best.chunks[int(best.next)].path)
	_pending_scene = ResourceLoader.load(_pending_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	if _pending_scene == null:
		best.failed = true
		push_error("Unable to load streaming chunk: " + _pending_path)
	_record_operation(started)

func _record_operation(started: int) -> void:
	_last_operation_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_max_operation_ms = maxf(_max_operation_ms, _last_operation_ms)
	_operation_count += 1

func _store_actor_state(chunk: Node3D, path: String) -> void:
	var state: Dictionary = {}
	for node: Node in chunk.find_children("*", "Node3D", true, false):
		var saved: Dictionary = {}
		if node.get_script() != null and node.get_script().resource_path in ["res://scripts/lake_life.gd", "res://scripts/ocean_life.gd", "res://scripts/city_traffic.gd"]:
			saved.elapsed = float(node.get("elapsed"))
		if node.has_meta("progress"):
			saved.progress = float(node.get_meta("progress"))
		if str(node.name).begins_with("wheel-"):
			saved.wheel_rotation = (node as Node3D).rotation.x
		if not saved.is_empty():
			state[str(chunk.get_path_to(node))] = saved
	# Only scalar animation phases persist; no node or resource references.
	if not state.is_empty():
		_actor_state[path] = state

func _restore_actor_state(chunk: Node3D, path: String) -> void:
	var state: Dictionary = _actor_state.get(path, {}) as Dictionary
	for node_path: String in state:
		var actor: Node = chunk.get_node_or_null(NodePath(node_path))
		if actor != null:
			var saved: Dictionary = state[node_path] as Dictionary
			if saved.has("elapsed"):
				actor.set("elapsed", float(saved.elapsed))
			if saved.has("progress"):
				actor.set_meta("progress", float(saved.progress))
			if saved.has("wheel_rotation"):
				(actor as Node3D).rotation.x = float(saved.wheel_rotation)
	for node_path: String in state:
		var actor: Node = chunk.get_node_or_null(NodePath(node_path))
		if actor == null:
			continue
		if actor.has_method("update_life"):
			actor.call("update_life", float(actor.get("elapsed")))
		elif actor.has_method("update_traffic"):
			actor.call("update_traffic", 0.0)

func metrics() -> Dictionary:
	var ready_count: int = 0
	var active_count: int = 0
	var ready_districts: int = 0
	var pending_count: int = 0
	var loaded_nodes: int = 0
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		if bool(region.ready):
			ready_count += 1
			if id != "sakura" and not id.begins_with("ocean_"):
				ready_districts += 1
		if bool(region.active):
			active_count += 1
		if bool(region.requested) and not bool(region.ready):
			pending_count += 1
		for index: int in range((region.roots as Array).size()):
			loaded_nodes += int(region.chunks[index].nodes)
	return {"ready_districts":ready_districts,"ready_regions":ready_count,"active_regions":active_count,"pending_regions":pending_count,"loaded_chunks":_loaded_count,"detail_nodes":loaded_nodes,"last_operation_ms":_last_operation_ms,"max_operation_ms":_max_operation_ms,"operations":_operation_count,"saved_animation_groups":_actor_state.size()}
