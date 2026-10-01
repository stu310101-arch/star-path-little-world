extends RefCounted

const Vegetation = preload("res://scripts/camera_vegetation.gd")
const SpatialIndex = preload("res://scripts/camera_spatial_index.gd")

# Tunables shared by every platform. The camera itself and material fades still
# advance every rendered frame; only visibility decisions use this interval.
var decision_interval: float = .1
var immediate_move_distance: float = 1.5
var immediate_turn_cosine: float = .94
var fade_speed: float = 5.0
var vegetation: RefCounted = Vegetation.new()
var faded: Dictionary = {}
var indexed_world: int = 0
var candidate_count: int = 0
var decision_usec: int = 0
var decision_count: int = 0
var bounds_rebuilds: int = 0
var _regions: Dictionary = {}
var _groups: Dictionary = {}
var _group_keys: Dictionary = {}
var _mesh_groups: Dictionary = {}
var _material_cache: Dictionary = {}
var _obstructing: Dictionary = {}
var _grid: RefCounted = SpatialIndex.new()
var _active: bool = true
var _force: bool = true
var _elapsed: float = 0.0
var _last_eye: Vector3 = Vector3.INF
var _last_aim: Vector3 = Vector3.INF
var _last_forward: Vector3 = Vector3.ZERO
var _ray_offsets: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var _excluded: Array[RID] = []
var _query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.new()

func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	vegetation.call("set_active",value)
	if not value:
		_restore_faded()
		_obstructing.clear()
	else:
		force_update()

func force_update() -> void:
	_force = true

func reset() -> void:
	_restore_faded()
	vegetation.call("reset")
	for region: Dictionary in _regions.values():
		_disconnect_region(region)
	_regions.clear()
	_groups.clear()
	_group_keys.clear()
	_mesh_groups.clear()
	_material_cache.clear()
	_obstructing.clear()
	_grid.call("clear")
	indexed_world = 0
	_active = true
	_force = true
	_last_eye = Vector3.INF
	candidate_count = 0

func update(world: Node3D,camera: Camera3D,aim: Vector3,delta: float) -> void:
	if not is_instance_valid(world) or not is_instance_valid(camera):
		return
	# Overview must not even discover descendants on its first frame.
	if not _active:
		return
	if indexed_world != world.get_instance_id():
		if indexed_world != 0:
			reset()
		indexed_world = world.get_instance_id()
		register_region(world)
	_elapsed += delta
	var eye: Vector3 = camera.global_position
	var forward: Vector3 = -camera.global_basis.z
	var moved: bool = eye.distance_squared_to(_last_eye) > immediate_move_distance*immediate_move_distance or aim.distance_squared_to(_last_aim) > immediate_move_distance*immediate_move_distance
	var turned: bool = forward.dot(_last_forward) < immediate_turn_cosine
	if _force or _elapsed >= decision_interval or moved or turned:
		var started: int = Time.get_ticks_usec()
		_refresh_regions()
		_decide(world,camera,aim)
		vegetation.call("update",world,camera,aim)
		candidate_count += int(vegetation.get("candidate_count"))
		decision_usec = Time.get_ticks_usec()-started
		decision_count += 1
		_elapsed = 0.0
		_force = false
		_last_eye = eye
		_last_aim = aim
		_last_forward = forward
	_animate_fades(delta)

func register_region(region_root: Node) -> void:
	if not is_instance_valid(region_root) or _regions.has(region_root.get_instance_id()):
		return
	# Returning from an interior reattaches the same world without rerunning
	# _ready/chunk_added. Reconstruct each streamed chunk's ownership before
	# the fallback world scan so future chunk unloads release exactly its data.
	var nodes: Array[Node] = region_root.find_children("*","Node3D",true,false)
	for child_root: Node in nodes:
		if bool(child_root.get_meta("camera_region", false)):
			register_region(child_root)
	vegetation.call("register_region",region_root)
	var region_id: int = region_root.get_instance_id()
	var region: Dictionary = {"root":weakref(region_root),"groups":[],"transform":_root_transform(region_root),"dirty":false,"signals":[]}
	_regions[region_id] = region
	if region_root is Node3D:
		nodes.append(region_root)
	for candidate: Node in nodes:
		var canopy: bool = str(candidate.name).begins_with("SakuraTree_") or str(candidate.name).begins_with("sakura_")
		if not canopy and not candidate.has_node("Foundation") and not candidate.has_meta("camera_visual_group"):
			continue
		var id: int = candidate.get_instance_id()
		if _groups.has(id):
			continue
		var members: Array[WeakRef] = []
		var member_ids: Array[int] = []
		var mesh_nodes: Array[Node] = candidate.find_children("*","MeshInstance3D",true,false)
		if candidate is MeshInstance3D:
			mesh_nodes.append(candidate)
		for mesh_node: Node in mesh_nodes:
			var mesh: MeshInstance3D = mesh_node as MeshInstance3D
			# Imported canopy roots can also use the sakura_ prefix. Their
			# enclosing authored tree group already owns the complete silhouette.
			if mesh.mesh == null or _mesh_groups.has(mesh.get_instance_id()):
				continue
			members.append(weakref(mesh))
			member_ids.append(mesh.get_instance_id())
			_mesh_groups[mesh.get_instance_id()] = id
			var callback: Callable = _mark_dirty.bind(region_id)
			if not mesh.mesh.changed.is_connected(callback):
				mesh.mesh.changed.connect(callback)
				(region.signals as Array).append({"resource":weakref(mesh.mesh),"callback":callback})
		if members.is_empty():
			continue
		var visual_key: String = str(candidate.get_meta("camera_visual_group", ""))
		_groups[id] = {"root":weakref(candidate),"members":members,"member_ids":member_ids,"canopy":canopy,"boxes":[],"region":region_id,"key":visual_key}
		if not visual_key.is_empty():
			_group_keys[visual_key] = id
		(region.groups as Array).append(id)
		_rebuild_group(id)
	force_update()

func unregister_region(region_root: Node) -> void:
	if not is_instance_valid(region_root):
		return
	vegetation.call("unregister_region",region_root)
	_remove_region(region_root.get_instance_id())
	force_update()

func invalidate(region_root: Node = null) -> void:
	vegetation.call("invalidate",region_root)
	for region_id: int in _regions:
		var region: Dictionary = _regions[region_id]
		var cached_root: Node = (region.root as WeakRef).get_ref() as Node
		if region_root == null or cached_root == region_root or (is_instance_valid(cached_root) and (cached_root.is_ancestor_of(region_root) or region_root.is_ancestor_of(cached_root))):
			region.dirty = true
	force_update()

func stats() -> Dictionary:
	return {"candidates":candidate_count,"decision_usec":decision_usec,"decisions":decision_count,"cached_groups":_groups.size(),"cached_trees":(vegetation.get("_trees") as Dictionary).size(),"bounds_rebuilds":bounds_rebuilds+int(vegetation.get("bounds_rebuilds")),"multimesh_transform_writes":int(vegetation.get("transform_writes")),"faded_meshes":faded.size(),"active":_active}

func _decide(world: Node3D,camera: Camera3D,aim: Vector3) -> void:
	_obstructing.clear()
	var eye: Vector3 = camera.global_position
	var upper_aim: Vector3 = aim+camera.global_basis.y*.35
	var candidates: Array[int] = _grid.call("query",eye,upper_aim,.36)
	candidate_count = 0
	for group_id: int in candidates:
		var group: Dictionary = _groups[group_id]
		if not _group_visible(group):
			continue
		candidate_count += 1
		for box: Dictionary in group.boxes:
			var local_eye: Vector3 = (box.inverse as Transform3D)*eye
			var bounds: AABB = box.bounds
			var blocked: bool = bounds.grow(.12).has_point(local_eye)
			if bool(group.canopy) and not blocked:
				blocked = bounds.intersects_segment(local_eye,(box.inverse as Transform3D)*aim) != null or bounds.intersects_segment(local_eye,(box.inverse as Transform3D)*upper_aim) != null
			if blocked:
				_mark_group(group)
				break
	_ray_offsets[1] = camera.global_basis.x*.24
	_ray_offsets[2] = -_ray_offsets[1]
	_ray_offsets[3] = camera.global_basis.y*.35
	_query.collision_mask = 8
	_query.hit_from_inside = true
	_query.hit_back_faces = true
	for offset: Vector3 in _ray_offsets:
		_excluded.clear()
		_query.from = eye
		_query.to = aim+offset
		for step: int in range(6):
			_query.exclude = _excluded
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(_query)
			if hit.is_empty():
				break
			var collider: CollisionObject3D = hit.collider as CollisionObject3D
			if not is_instance_valid(collider):
				break
			_excluded.append(collider.get_rid())
			# Streaming keeps collision resident while visual detail may unload.
			# Its stable authored key reconnects the body to a currently live
			# complete building/tree silhouette without retaining node references.
			var visual_key: String = str(collider.get_meta("camera_visual_group", ""))
			if _group_keys.has(visual_key):
				_mark_group(_groups[_group_keys[visual_key]])
				continue
			var parent: Node = collider.get_parent()
			if parent is MeshInstance3D:
				var mesh_id: int = parent.get_instance_id()
				if _mesh_groups.has(mesh_id):
					_mark_group(_groups[_mesh_groups[mesh_id]])
				else:
					_mark_mesh(parent as MeshInstance3D)
			elif is_instance_valid(parent) and _groups.has(parent.get_instance_id()):
				_mark_group(_groups[parent.get_instance_id()])

func _mark_group(group: Dictionary) -> void:
	if not _group_visible(group):
		return
	for member_ref: WeakRef in group.members:
		var mesh: MeshInstance3D = member_ref.get_ref() as MeshInstance3D
		if is_instance_valid(mesh):
			_mark_mesh(mesh)

func _group_visible(group: Dictionary) -> bool:
	var group_root: Node3D = (group.root as WeakRef).get_ref() as Node3D
	if not is_instance_valid(group_root):
		return false
	# A standalone railing may itself be the group's mesh. Its own temporary
	# fade visibility must not make the next decision restore and re-hide it.
	if faded.has(group_root.get_instance_id()):
		var parent_3d: Node3D = group_root.get_parent_node_3d()
		return bool(faded[group_root.get_instance_id()].visible) and (parent_3d == null or parent_3d.is_visible_in_tree())
	return group_root.is_visible_in_tree()

func _mark_mesh(mesh: MeshInstance3D) -> void:
	add_mesh(mesh)
	_obstructing[mesh.get_instance_id()] = true

func add_mesh(mesh: MeshInstance3D) -> void:
	var id: int = mesh.get_instance_id()
	if faded.has(id) or mesh.mesh == null:
		return
	var record: Dictionary
	if _material_cache.has(id):
		record = _material_cache[id]
	else:
		record = {"mesh":weakref(mesh),"visible":mesh.visible,"override":mesh.material_override,"surfaces":[],"materials":[],"alpha":[],"opacity":1.0}
		for slot: int in range(mesh.mesh.get_surface_count()):
			record.surfaces.append(mesh.get_surface_override_material(slot))
			var original: BaseMaterial3D = mesh.get_active_material(slot) as BaseMaterial3D
			if original == null:
				return
			var material: BaseMaterial3D = original.duplicate() as BaseMaterial3D
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			record.materials.append(material)
			record.alpha.append(original.albedo_color.a)
		_material_cache[id] = record
	record.opacity = 1.0
	mesh.material_override = null
	for slot: int in range((record.materials as Array).size()):
		mesh.set_surface_override_material(slot,record.materials[slot] as Material)
	faded[id] = record

func restore_record(record: Dictionary) -> void:
	var mesh: MeshInstance3D = (record.mesh as WeakRef).get_ref() as MeshInstance3D
	if not is_instance_valid(mesh):
		return
	mesh.material_override = record.override as Material
	mesh.visible = bool(record.visible)
	for slot: int in range((record.surfaces as Array).size()):
		mesh.set_surface_override_material(slot,record.surfaces[slot] as Material)

func _animate_fades(delta: float) -> void:
	for id: int in faded.keys():
		var record: Dictionary = faded[id]
		var mesh: MeshInstance3D = (record.mesh as WeakRef).get_ref() as MeshInstance3D
		if not is_instance_valid(mesh):
			faded.erase(id)
			_material_cache.erase(id)
			continue
		var target: float = 0.0 if _obstructing.has(id) else 1.0
		var opacity: float = move_toward(float(record.opacity),target,delta*fade_speed)
		if not is_equal_approx(opacity,float(record.opacity)):
			record.opacity = opacity
			mesh.visible = bool(record.visible) and opacity > .001
			for slot: int in range((record.materials as Array).size()):
				var material: BaseMaterial3D = record.materials[slot] as BaseMaterial3D
				var tint: Color = material.albedo_color
				tint.a = float(record.alpha[slot])*opacity
				material.albedo_color = tint
		if is_equal_approx(opacity,1.0):
			restore_record(record)
			faded.erase(id)

func _restore_faded() -> void:
	for record: Dictionary in faded.values():
		restore_record(record)
	faded.clear()

func _rebuild_group(id: int) -> void:
	var group: Dictionary = _groups[id]
	(group.boxes as Array).clear()
	var bounds: AABB = AABB()
	var has_bounds: bool = false
	for member_ref: WeakRef in group.members:
		var mesh: MeshInstance3D = member_ref.get_ref() as MeshInstance3D
		if not is_instance_valid(mesh) or mesh.mesh == null:
			continue
		var local_box: AABB = mesh.get_aabb()
		var global_box: AABB = mesh.global_transform*local_box.grow(.12)
		(group.boxes as Array).append({"bounds":local_box,"inverse":mesh.global_transform.affine_inverse()})
		bounds = bounds.merge(global_box) if has_bounds else global_box
		has_bounds = true
		bounds_rebuilds += 1
	if has_bounds:
		_grid.call("insert",id,bounds)
	else:
		_grid.call("remove",id)
	# A mesh/resource replacement is an explicit invalidate() operation, as are
	# changes to interior child transforms. Rebuild its material copy next use.
	for mesh_id: int in group.member_ids:
		if faded.has(mesh_id):
			restore_record(faded[mesh_id])
			faded.erase(mesh_id)
		_material_cache.erase(mesh_id)

func _refresh_regions() -> void:
	for region_id: int in _regions.keys():
		var region: Dictionary = _regions[region_id]
		var region_root: Node = (region.root as WeakRef).get_ref() as Node
		if not is_instance_valid(region_root):
			_remove_region(region_id)
			continue
		var current: Transform3D = _root_transform(region_root)
		if bool(region.dirty) or current != (region.transform as Transform3D):
			for id: int in region.groups:
				_rebuild_group(id)
			region.transform = current
			region.dirty = false
	# Dynamic ray-hit meshes have no registered region; release freed references.
	for mesh_id: int in _material_cache.keys():
		var record: Dictionary = _material_cache[mesh_id]
		if not is_instance_valid((record.mesh as WeakRef).get_ref()):
			_material_cache.erase(mesh_id)

func _remove_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var region: Dictionary = _regions[region_id]
	for id: int in region.groups:
		var group: Dictionary = _groups[id]
		if _group_keys.get(str(group.key), 0) == id:
			_group_keys.erase(str(group.key))
		for mesh_id: int in group.member_ids:
			if faded.has(mesh_id):
				restore_record(faded[mesh_id])
			faded.erase(mesh_id)
			_material_cache.erase(mesh_id)
			_mesh_groups.erase(mesh_id)
			_obstructing.erase(mesh_id)
		_grid.call("remove",id)
		_groups.erase(id)
	_disconnect_region(region)
	_regions.erase(region_id)

func _disconnect_region(region: Dictionary) -> void:
	for record: Dictionary in region.signals:
		var resource: Resource = (record.resource as WeakRef).get_ref() as Resource
		var callback: Callable = record.callback
		if is_instance_valid(resource) and resource.changed.is_connected(callback):
			resource.changed.disconnect(callback)

func _mark_dirty(region_id: int) -> void:
	if _regions.has(region_id):
		_regions[region_id].dirty = true
	force_update()

func _root_transform(region_root: Node) -> Transform3D:
	return (region_root as Node3D).global_transform if region_root is Node3D else Transform3D.IDENTITY
