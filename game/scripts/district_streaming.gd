extends Node

signal chunk_added(root: Node3D)
signal chunk_removing(root: Node3D)
signal district_ready(id: String)

# Authored metre distances, converted to physical metres by _outdoor_scale.
# A 12 m hysteresis band and grace period prevent boundary thrashing.
const CATALOG: String = "res://generated/streaming/catalog.json"
const Routes = preload("res://scripts/world_routes.gd")
const OutdoorScale = preload("res://scripts/outdoor_scale.gd")
const MobileRenderQuality = preload("res://scripts/mobile_render_quality.gd")
const LOAD_DISTANCE: float = 45.0
const ACTIVE_DISTANCE: float = 38.0
const UNLOAD_DISTANCE: float = 57.0
const UNLOAD_DELAY: float = 4.0
const CONTEXT_INTERVAL: float = .15
const OVERVIEW_DETAIL_CAMERA_ALTITUDE: float = 70.0
const PIN_SECONDS: float = 20.0
const LOW_LOAD_DISTANCE: float = 33.0
const LOW_ACTIVE_DISTANCE: float = 27.0
const LOW_UNLOAD_DISTANCE: float = 45.0
const LOW_ANIMATION_INTERVAL: float = .10
const LOW_UNDERSTORY_FRACTION: int = 60
const PREFETCH_MARGIN: float = 12.0
const ANIMATED_SCRIPTS: Array[String] = ["res://scripts/lake_life.gd", "res://scripts/ocean_life.gd", "res://scripts/city_traffic.gd"]
var _world: Node3D
var _regions: Dictionary = {}
var _district_specs: Dictionary = {}
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
var _authoring_radius: float = 48.0
var _outdoor_scale: float = 1.0
var _low_quality: bool = false
var _constrained_runtime: bool = false
var _interior_active: bool = false
var _quality_settings: Node
var _mobile_render: RefCounted = MobileRenderQuality.new()

func configure(world: Node3D, catalog_path: String = CATALOG) -> void:
	_world = world
	if get_node("/root/ResourceProfile").call("is_low"):
		catalog_path = "res://generated/low/streaming/catalog.json"
		_constrained_runtime = true
	_quality_settings = get_tree().get_first_node_in_group("graphics_settings")
	if _quality_settings == null:
		_quality_settings = get_node_or_null("/root/GraphicsSettings")
	if _quality_settings != null and _quality_settings.has_method("is_low_quality"):
		_quality_settings.connect("state_changed", _refresh_quality)
		_refresh_quality()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog_path)) as Dictionary
	_radius = float(catalog.get("radius", 48.0))
	_authoring_radius = OutdoorScale.authored_radius(catalog)
	_outdoor_scale = OutdoorScale.factor(catalog)
	_mobile_render.call("configure",world,_radius)
	_refresh_mobile_render()
	for district: Dictionary in JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array:
		_district_specs[str(district.station)] = district
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

func _refresh_quality() -> void:
	set_constrained_runtime(bool(get_node("/root/ResourceProfile").call("is_low")) or (_quality_settings.has_method("is_constrained_runtime") and bool(_quality_settings.call("is_constrained_runtime"))))
	set_low_quality(bool(_quality_settings.call("is_low_quality")))
	_refresh_mobile_render()

func set_constrained_runtime(enabled: bool) -> void:
	if _constrained_runtime == enabled:
		return
	_constrained_runtime = enabled
	_context_clock = CONTEXT_INTERVAL
	if enabled:
		# Permanent bases already contain walkable surfaces, collision, seats,
		# buildings and vegetation. Roam through those baked batches directly:
		# never download or instantiate an entire detail district just to enter.
		# Existing detail is hidden immediately, then released one chunk/frame.
		_suspend_outdoor_details()

func _refresh_mobile_render() -> void:
	var mobile: bool=_quality_settings!=null and _quality_settings.has_method("is_mobile_performance_profile") and bool(_quality_settings.call("is_mobile_performance_profile"))
	if bool(_mobile_render.get("enabled")) == mobile:
		return
	_mobile_render.call("set_enabled",mobile)
	for region: Dictionary in _regions.values():
		for chunk: Node3D in region.roots:
			if _constrained_runtime:
				continue
			_mobile_render.call("apply_meshes",chunk)
			_mobile_render.call("apply_materials",chunk)

func set_low_quality(enabled: bool) -> void:
	if _low_quality == enabled:
		return
	_low_quality = enabled
	_context_clock = CONTEXT_INTERVAL
	for region: Dictionary in _regions.values():
		for chunk: Node3D in region.roots:
			if not _constrained_runtime:
				_apply_chunk_quality(chunk)
	if _interior_active and (_low_quality or _constrained_runtime):
		_suspend_outdoor_details()

func _apply_chunk_quality(chunk: Node3D) -> void:
	# Build once per new chunk / quality change, never scan the world per frame.
	for actor: Node in chunk.find_children("*", "", true, false):
		if actor.get_script() != null and actor.get_script().resource_path in ANIMATED_SCRIPTS:
			actor.set("quality_update_interval", LOW_ANIMATION_INTERVAL if _low_quality else 0.0)
		if actor is MultiMeshInstance3D and str(actor.get_meta("ecology_kind", actor.get_meta("aquatic_kind", ""))) in ["fern", "cattail", "water_lily"]:
			_apply_understory_density(actor as MultiMeshInstance3D)

func _apply_understory_density(node: MultiMeshInstance3D) -> void:
	# Tree batches belong to the obstruction controller and are never modified
	# here. Noncolliding understory uses a compact visible prefix, with exact
	# authored transforms restored when quality changes back to standard.
	if node.multimesh == null or (node.has_meta("quality_density_low") and bool(node.get_meta("quality_density_low")) == _low_quality):
		return
	var placements: Array = node.get_meta("placements", []) as Array
	if placements.size() != node.multimesh.instance_count:
		return
	if not node.has_meta("quality_original_visible"):
		node.set_meta("quality_original_visible", node.multimesh.visible_instance_count)
	var original_visible: int = int(node.get_meta("quality_original_visible"))
	var limit: int = placements.size() if original_visible < 0 else mini(original_visible, placements.size())
	var visible_count: int = 0
	for index: int in range(placements.size()):
		if _low_quality and (index >= limit or (index * 73) % 100 >= LOW_UNDERSTORY_FRACTION):
			continue
		node.multimesh.set_instance_transform(visible_count, placements[index] as Transform3D)
		visible_count += 1
	node.multimesh.visible_instance_count = visible_count if _low_quality else original_visible
	node.set_meta("quality_density_low", _low_quality)

func set_interior_active(active: bool) -> void:
	_interior_active = active
	_context_clock = CONTEXT_INTERVAL
	if active and (_low_quality or _constrained_runtime):
		_suspend_outdoor_details()

func _suspend_outdoor_details() -> void:
	clear_pin()
	_pending_scene = null
	_pending_id = ""
	_pending_path = ""
	for region: Dictionary in _regions.values():
		region.wanted = false
		region.requested = false
		_set_active(region, false)

func step_suspended_release() -> void:
	# The indoor transition may retain the outdoor world outside SceneTree.
	# Release one detail chunk per caller frame while preserving scalar state.
	if _interior_active and (_low_quality or _constrained_runtime):
		_step()

func is_interior_release_complete() -> bool:
	return _loaded_count == 0 and _pending_scene == null

func pin_position(point: Vector3) -> void:
	if _constrained_runtime:
		return
	_pin_position = point
	_pin_until = _clock + PIN_SECONDS
	_context_clock = CONTEXT_INTERVAL
	for id: String in _required_ids(point):
		_regions[id].wanted = true
		_regions[id].requested = true
		_regions[id].priority = -100.0 + point.distance_to(_regions[id].center as Vector3)

func clear_pin() -> void:
	_pin_until = -1.0
	_pin_position = Vector3.ZERO
	_context_clock = CONTEXT_INTERVAL

func is_position_ready(point: Vector3) -> bool:
	if _constrained_runtime:
		return true
	for id: String in _required_ids(point):
		if not bool(_regions[id].ready):
			return false
	return true

func _required_ids(point: Vector3) -> Array[String]:
	var result: Array[String] = []
	if _constrained_runtime:
		return result
	var nearest: String = ""
	var distance: float = INF
	for id: String in _regions:
		var d: float = _region_distance(id,point)
		if d <= (LOW_ACTIVE_DISTANCE if _low_quality else ACTIVE_DISTANCE) * _outdoor_scale:
			result.append(id)
		if not id.begins_with("ocean_") and d < distance:
			distance = d
			nearest = id
	if not nearest.is_empty() and not result.has(nearest):
		result.append(nearest)
	return result

func _region_distance(id: String, point: Vector3) -> float:
	var center: Vector3 = _regions[id].center as Vector3
	if _district_specs.has(id):
		var normal: Vector3 = point.normalized()
		var up: Vector3 = center.normalized()
		if normal.dot(up) > .55:
			var local: Vector2 = Routes.local_point(normal,up,_authoring_radius)
			return maxf(0.0,-Routes.coast_distance(local,_district_specs[id],Routes.IDS.find(id))) * _outdoor_scale
	return point.distance_to(center)

func update_context(overview: bool, player_position: Vector3, camera_position: Vector3, target: Vector3, delta: float) -> void:
	_clock += delta
	_context_clock += delta
	if _overview != overview:
		_context_clock = CONTEXT_INTERVAL
		if overview:
			clear_pin()
	_overview = overview
	if _context_clock >= CONTEXT_INTERVAL:
		_context_clock = 0.0
		_refresh_context(player_position, camera_position, target)
	_mobile_render.call("update_visibility",camera_position,overview)
	# Web uses the existing single-thread export. Binary chunks bound each
	# synchronous engine operation; load and instantiate occur on separate
	# frames, only after the Web resource pack has downloaded and mounted.
	_step()

func _refresh_context(player_position: Vector3, camera_position: Vector3, target: Vector3) -> void:
	if _constrained_runtime:
		return
	if _interior_active and _low_quality:
		_suspend_outdoor_details()
		return
	var load_distance: float = (LOW_LOAD_DISTANCE if _low_quality else LOAD_DISTANCE) * _outdoor_scale
	var unload_distance: float = (LOW_UNLOAD_DISTANCE if _low_quality else UNLOAD_DISTANCE) * _outdoor_scale
	# The optimized far representation is always used for low-profile overview.
	var close_overview: bool = not _low_quality and _overview and camera_position.length() - _radius <= OVERVIEW_DETAIL_CAMERA_ALTITUDE * _outdoor_scale
	# A close overview loads the district being viewed, not the land beneath an
	# obliquely orbiting eye. Roaming always follows the player's meter position.
	var focus: Vector3 = (target.normalized() if not target.is_zero_approx() else camera_position.normalized()) * _radius if close_overview else player_position
	var pinned: Array[String] = []
	if _clock < _pin_until:
		pinned = _required_ids(_pin_position)
	var required: Array[String] = []
	var packs: Node = get_node_or_null("/root/WebPacks")
	if not _overview:
		required = _required_ids(focus)
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		var distance: float = _region_distance(id,focus)
		var pin: bool = pinned.has(id)
		var eligible: bool = not _overview or close_overview
		# Fetch nearby districts before their existing detail activation boundary.
		# Colliders stay in the permanent boot world, so slow/offline downloads
		# cannot remove ground or allow passage through authored obstacles.
		if packs != null and eligible and distance < load_distance + PREFETCH_MARGIN * _outdoor_scale:
			for chunk: Dictionary in region.chunks:
				packs.call("request_resource", str(chunk.path), -20 - int(distance))
		var wanted: bool = pin or (eligible and (distance < load_distance or required.has(id)))
		region.requested = wanted
		if wanted:
			region.wanted = true
			region.outside_since = _clock
		elif not eligible or distance > unload_distance:
			if _clock - float(region.outside_since) >= UNLOAD_DELAY:
				region.wanted = false
		else:
			# Time spent in the hysteresis band is retention, not unload grace.
			# Start the delay only after crossing the outer boundary.
			region.outside_since = _clock
		region.priority = distance - (100.0 if pin else 0.0)
		var active_distance: float = load_distance if bool(region.active) else (LOW_ACTIVE_DISTANCE if _low_quality else ACTIVE_DISTANCE) * _outdoor_scale
		var active: bool = eligible and distance <= active_distance and bool(region.ready)
		_set_active(region, active)

func _set_active(region: Dictionary, active: bool) -> void:
	active = active and not _constrained_runtime
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
				# Saved chunks already carry this transform. Idempotence also keeps
				# tooling-created authored chunks safe before any actor's _ready.
				OutdoorScale.apply_to_root(chunk, _outdoor_scale)
				chunk.set_meta("camera_region", true)
				chunk.visible = false
				chunk.process_mode = Node.PROCESS_MODE_DISABLED
				_world.add_child(chunk)
				_mobile_render.call("apply_meshes",chunk)
				_restore_actor_state(chunk, _pending_path)
				_apply_chunk_quality(chunk)
				(region.roots as Array).append(chunk)
				region.next += 1
				_loaded_count += 1
				chunk_added.emit(chunk)
				_mobile_render.call("apply_materials",chunk)
				_mobile_render.call("register_chunk",chunk)
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
			_mobile_render.call("unregister_chunk",chunk)
			chunk.queue_free()
			region.next = roots.size()
			_loaded_count -= 1
			_record_operation(started)
			return
	if _constrained_runtime or (_interior_active and _low_quality):
		# Once drained, the detached world has no absolute SceneTree paths.
		return
	var best_id: String = ""
	var priority: float = INF
	var packs: Node = get_node_or_null("/root/WebPacks")
	for id: String in _regions:
		var region: Dictionary = _regions[id]
		if bool(region.requested) and not bool(region.ready) and not bool(region.failed) and float(region.priority) < priority:
			if packs != null and int(region.next) < (region.chunks as Array).size():
				var path: String = str(region.chunks[int(region.next)].path)
				packs.call("request_resource", path, 50 - int(region.priority))
				if not bool(packs.call("is_resource_ready", path)):
					continue
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

func position_error(point: Vector3) -> String:
	var packs: Node = get_node_or_null("/root/WebPacks")
	for id: String in _required_ids(point):
		var region: Dictionary = _regions[id]
		if bool(region.failed):
			return "區域建立失敗，請重試。"
		if packs != null:
			for chunk: Dictionary in region.chunks:
				var message: String = str(packs.call("resource_error", str(chunk.path)))
				if not message.is_empty():
					return message
	return ""

func retry_failed() -> void:
	for region: Dictionary in _regions.values():
		region.failed = false

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
	var result: Dictionary={"ready_districts":ready_districts,"ready_regions":ready_count,"active_regions":active_count,"pending_regions":pending_count,"loaded_chunks":_loaded_count,"detail_nodes":loaded_nodes,"last_operation_ms":_last_operation_ms,"max_operation_ms":_max_operation_ms,"operations":_operation_count,"saved_animation_groups":_actor_state.size(),"low_quality":_low_quality,"constrained_runtime":_constrained_runtime,"interior_active":_interior_active}
	result.merge(_mobile_render.call("metrics") as Dictionary)
	return result
