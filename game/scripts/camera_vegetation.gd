extends RefCounted

const SpatialIndex = preload("res://scripts/camera_spatial_index.gd")
const TREE_KINDS: Array[String] = ["alder","birch","willow","pine"]
const RAY_OFFSET: float = .30

var _world_id: int = 0
var _batches: Dictionary = {}
var _node_batches: Dictionary = {}
var _regions: Dictionary = {}
var _trees: Dictionary = {}
var _grid: RefCounted = SpatialIndex.new()
var _next_tree_id: int = 1
var _active: bool = true
var _hidden_batches: Dictionary = {}
var _next_hidden: Dictionary = {}
var _offsets: Array[Vector3] = [Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO,Vector3.ZERO]
var candidate_count: int = 0
var transform_writes: int = 0
var bounds_rebuilds: int = 0
var decision_usec: int = 0

# Called by the camera controller only on its 0.1 s decision tick. Keeping this
# method independent also makes the exact MultiMesh contract testable headlessly.
func update(world: Node3D,camera: Camera3D,aim: Vector3) -> void:
	if not is_instance_valid(world) or not is_instance_valid(camera):
		reset()
		return
	if not _active:
		return
	if _world_id != world.get_instance_id():
		if _world_id != 0:
			reset()
		_world_id = world.get_instance_id()
		register_region(world)
	var started: int = Time.get_ticks_usec()
	_refresh_regions()
	var eye: Vector3 = camera.global_position
	_offsets[1] = camera.global_basis.x.normalized()*RAY_OFFSET
	_offsets[2] = -_offsets[1]
	_offsets[3] = camera.global_basis.y.normalized()*RAY_OFFSET
	_offsets[4] = -_offsets[3]
	_next_hidden.clear()
	var candidates: Array[int] = _grid.call("query",eye,aim,RAY_OFFSET)
	candidate_count = 0
	for id: int in candidates:
		var tree: Dictionary = _trees[id]
		if not _batch_visible(_batches[tree.batch]):
			continue
		candidate_count += 1
		if _blocks_view(tree.bounds as AABB,eye,aim,_offsets):
			var key: String = tree.batch
			if not _next_hidden.has(key):
				_next_hidden[key] = {}
			_next_hidden[key][int(tree.index)] = true
	# Only changed batches are compacted; distant batches aren't traversed.
	for key: String in _hidden_batches:
		if not _next_hidden.has(key) and _batches.has(key):
			_set_hidden(_batches[key],{})
	for key: String in _next_hidden:
		_set_hidden(_batches[key],_next_hidden[key])
	var previous: Dictionary = _hidden_batches
	_hidden_batches = _next_hidden
	_next_hidden = previous
	decision_usec = Time.get_ticks_usec()-started

func set_active(value: bool) -> void:
	if value == _active:
		return
	_active = value
	if not value:
		for key: String in _hidden_batches:
			if _batches.has(key):
				_set_hidden(_batches[key],{})
		_hidden_batches.clear()

func reset() -> void:
	for key: String in _batches:
		_set_hidden(_batches[key],{})
	for region: Dictionary in _regions.values():
		_disconnect_region(region)
	_batches.clear()
	_node_batches.clear()
	_regions.clear()
	_trees.clear()
	_grid.call("clear")
	_hidden_batches.clear()
	_next_hidden.clear()
	_world_id = 0
	_active = true
	candidate_count = 0

func register_region(region_root: Node) -> void:
	if not is_instance_valid(region_root) or _regions.has(region_root.get_instance_id()):
		return
	# Preserve chunk ownership when the existing world re-enters the tree
	# after an indoor scene and no new chunk_added signals are emitted.
	for child_root: Node in region_root.find_children("*", "Node3D", true, false):
		if bool(child_root.get_meta("camera_region", false)):
			register_region(child_root)
	var region_id: int = region_root.get_instance_id()
	var region: Dictionary = {"root":weakref(region_root),"keys":[],"transform":_root_transform(region_root),"dirty":false,"signals":[]}
	_regions[region_id] = region
	var nodes: Array[Node] = region_root.find_children("*","MultiMeshInstance3D",true,false)
	if region_root is MultiMeshInstance3D:
		nodes.append(region_root)
	for candidate: Node in nodes:
		var node: MultiMeshInstance3D = candidate as MultiMeshInstance3D
		var kind: String = str(node.get_meta("ecology_kind",""))
		var key: String = str(node.get_meta("ecology_batch_key",""))
		if kind not in TREE_KINDS or key.is_empty() or node.multimesh == null or node.multimesh.mesh == null:
			continue
		# Do not collect descendants already registered by the streaming manager.
		if _node_batches.has(node.get_instance_id()):
			continue
		var placements: Array = (node.get_meta("placements",[]) as Array).duplicate()
		if placements.is_empty() or placements.size() != node.multimesh.instance_count:
			continue
		if _batches.has(key) and int(_batches[key].region) != region_id:
			key += "@"+str(region_id)
		if not _batches.has(key):
			var all_indices: PackedInt32Array = PackedInt32Array()
			for index: int in range(placements.size()):
				all_indices.append(index)
			_batches[key] = {"region":region_id,"count":placements.size(),"nodes":[],"visible":all_indices,"hidden":{},"tree_ids":[]}
			(region.keys as Array).append(key)
		var batch: Dictionary = _batches[key]
		if placements.size() != int(batch.count):
			continue
		var colors: Array[Color] = []
		var custom: Array[Color] = []
		for index: int in range(placements.size()):
			if node.multimesh.use_colors:
				colors.append(node.multimesh.get_instance_color(index))
			if node.multimesh.use_custom_data:
				custom.append(node.multimesh.get_instance_custom_data(index))
		(batch.nodes as Array).append({"node":weakref(node),"id":node.get_instance_id(),"placements":placements,"colors":colors,"custom":custom,"mesh_bounds":node.multimesh.mesh.get_aabb(),"order":(batch.visible as PackedInt32Array).duplicate(),"original_visible":node.multimesh.visible_instance_count})
		_node_batches[node.get_instance_id()] = key
		var callback: Callable = _mark_dirty.bind(region_id)
		if not node.multimesh.mesh.changed.is_connected(callback):
			node.multimesh.mesh.changed.connect(callback)
			(region.signals as Array).append({"resource":weakref(node.multimesh.mesh),"callback":callback})
	for key: String in region.keys:
		_rebuild_batch(key)

func unregister_region(region_root: Node) -> void:
	if is_instance_valid(region_root):
		_remove_region(region_root.get_instance_id())

# Scene placement/mesh edits are explicit invalidation points. Streaming calls
# registration after all authored transforms are assigned, before first use.
func invalidate(region_root: Node = null) -> void:
	for region_id: int in _regions:
		var region: Dictionary = _regions[region_id]
		var cached_root: Node = (region.root as WeakRef).get_ref() as Node
		if region_root == null or cached_root == region_root or (is_instance_valid(cached_root) and (cached_root.is_ancestor_of(region_root) or region_root.is_ancestor_of(cached_root))):
			region.dirty = true

func _refresh_regions() -> void:
	for region_id: int in _regions.keys():
		var region: Dictionary = _regions[region_id]
		var region_root: Node = (region.root as WeakRef).get_ref() as Node
		if not is_instance_valid(region_root):
			_remove_region(region_id)
			continue
		var current: Transform3D = _root_transform(region_root)
		if bool(region.dirty) or current != (region.transform as Transform3D):
			for key: String in region.keys:
				_rebuild_batch(key)
			region.transform = current
			region.dirty = false

func _rebuild_batch(key: String) -> void:
	var batch: Dictionary = _batches[key]
	for id: int in batch.tree_ids:
		_grid.call("remove",id)
		_trees.erase(id)
	(batch.tree_ids as Array).clear()
	var placement_changed: bool = false
	for record: Dictionary in batch.nodes:
		var node: MultiMeshInstance3D = (record.node as WeakRef).get_ref() as MultiMeshInstance3D
		if is_instance_valid(node) and node.multimesh != null and node.multimesh.mesh != null:
			record.mesh_bounds = node.multimesh.mesh.get_aabb()
			record.global = node.global_transform
			# Metadata is the canonical, un-compacted instance data.
			var authored: Array = node.get_meta("placements",record.placements) as Array
			if authored != (record.placements as Array) and authored.size() == int(batch.count):
				record.placements = authored.duplicate()
				# The source matrices changed, so the previous source-index match
				# no longer proves the corresponding render slot is up to date.
				var order: PackedInt32Array = record.order
				order.fill(-1)
				record.order = order
				placement_changed = true
	if placement_changed:
		_apply(batch,batch.visible as PackedInt32Array)
	for index: int in range(int(batch.count)):
		var has_bounds: bool = false
		var bounds: AABB = AABB()
		for record: Dictionary in batch.nodes:
			var node: MultiMeshInstance3D = (record.node as WeakRef).get_ref() as MultiMeshInstance3D
			if not is_instance_valid(node) or index >= (record.placements as Array).size():
				continue
			var box: AABB = (record.global as Transform3D)*(record.placements[index] as Transform3D)*(record.mesh_bounds as AABB)
			bounds = bounds.merge(box) if has_bounds else box
			has_bounds = true
		if has_bounds:
			var id: int = _next_tree_id
			_next_tree_id += 1
			_trees[id] = {"batch":key,"index":index,"bounds":bounds}
			(batch.tree_ids as Array).append(id)
			_grid.call("insert",id,bounds)
			bounds_rebuilds += 1

func _set_hidden(batch: Dictionary, hidden: Dictionary) -> void:
	if hidden == (batch.hidden as Dictionary):
		return
	var visible: PackedInt32Array = PackedInt32Array()
	for index: int in range(int(batch.count)):
		if not hidden.has(index):
			visible.append(index)
	_apply(batch,visible)
	batch.visible = visible
	batch.hidden = hidden.duplicate()

func _apply(batch: Dictionary,visible: PackedInt32Array) -> void:
	for record: Dictionary in batch.nodes:
		var node: MultiMeshInstance3D = (record.node as WeakRef).get_ref() as MultiMeshInstance3D
		if not is_instance_valid(node) or node.multimesh == null:
			continue
		var placements: Array = record.placements
		var order: PackedInt32Array = record.order
		# A caller may deliberately show only a prefix of a MultiMesh. Preserve
		# that limit; compaction must never reveal authored hidden instances.
		var original_count: int = int(record.original_visible)
		var visible_count: int = 0
		for source: int in visible:
			if original_count >= 0 and source >= original_count:
				continue
			var destination: int = visible_count
			visible_count += 1
			if order[destination] == source:
				continue
			node.multimesh.set_instance_transform(destination,placements[source] as Transform3D)
			if node.multimesh.use_colors:
				node.multimesh.set_instance_color(destination,record.colors[source] as Color)
			if node.multimesh.use_custom_data:
				node.multimesh.set_instance_custom_data(destination,record.custom[source] as Color)
			order[destination] = source
			transform_writes += 1
		record.order = order
		node.multimesh.visible_instance_count = original_count if visible.size() == int(batch.count) else visible_count

func _remove_region(region_id: int) -> void:
	if not _regions.has(region_id):
		return
	var region: Dictionary = _regions[region_id]
	for key: String in region.keys:
		var batch: Dictionary = _batches[key]
		_set_hidden(batch,{})
		for id: int in batch.tree_ids:
			_grid.call("remove",id)
			_trees.erase(id)
		for record: Dictionary in batch.nodes:
			_node_batches.erase(int(record.id))
		_batches.erase(key)
		_hidden_batches.erase(key)
		_next_hidden.erase(key)
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

func _root_transform(region_root: Node) -> Transform3D:
	return (region_root as Node3D).global_transform if region_root is Node3D else Transform3D.IDENTITY

func _blocks_view(bounds: AABB,eye: Vector3,aim: Vector3,offsets: Array[Vector3]) -> bool:
	if bounds.has_point(eye):
		return true
	for offset: Vector3 in offsets:
		if bounds.intersects_segment(eye+offset,aim+offset) != null:
			return true
	return false

func _batch_visible(batch: Dictionary) -> bool:
	for record: Dictionary in batch.nodes:
		var node: MultiMeshInstance3D = (record.node as WeakRef).get_ref() as MultiMeshInstance3D
		if is_instance_valid(node) and node.is_visible_in_tree():
			return true
	return false
