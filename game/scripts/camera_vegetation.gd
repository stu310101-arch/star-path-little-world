extends RefCounted

const TREE_KINDS: Array[String]=["alder","birch","willow","pine"]
const RAY_OFFSET: float=.30

var _world_id: int=0
var _batches: Dictionary={}

func update(world: Node3D,camera: Camera3D,aim: Vector3) -> void:
	if not is_instance_valid(world) or not is_instance_valid(camera):
		reset()
		return
	if _world_id!=world.get_instance_id():
		reset()
		_collect(world)
	var eye: Vector3=camera.global_position
	var right: Vector3=camera.global_basis.x.normalized()*RAY_OFFSET
	var vertical: Vector3=camera.global_basis.y.normalized()*RAY_OFFSET
	var offsets: Array[Vector3]=[Vector3.ZERO,right,-right,vertical,-vertical]
	for key: String in _batches:
		var batch: Dictionary=_batches[key]
		var visible: PackedInt32Array=PackedInt32Array()
		for index: int in range(int(batch.count)):
			var has_bounds: bool=false
			var bounds: AABB=AABB()
			for record: Dictionary in batch.nodes:
				var node: MultiMeshInstance3D=(record.node as WeakRef).get_ref() as MultiMeshInstance3D
				if not is_instance_valid(node):
					continue
				var placements: Array=record.placements as Array
				var placement: Transform3D=placements[index] as Transform3D
				var box: AABB=node.global_transform*placement*(record.mesh_bounds as AABB)
				bounds=bounds.merge(box) if has_bounds else box
				has_bounds=true
			if not has_bounds or not _blocks_view(bounds,eye,aim,offsets):
				visible.append(index)
		if visible!=(batch.visible as PackedInt32Array):
			_apply(batch,visible)
			batch.visible=visible

func reset() -> void:
	for key: String in _batches:
		var batch: Dictionary=_batches[key]
		for record: Dictionary in batch.nodes:
			_restore(record)
	_batches.clear()
	_world_id=0

func _collect(world: Node3D) -> void:
	_world_id=world.get_instance_id()
	for candidate: Node in world.find_children("*","MultiMeshInstance3D",true,false):
		var node: MultiMeshInstance3D=candidate as MultiMeshInstance3D
		var kind: String=str(node.get_meta("ecology_kind",""))
		var key: String=str(node.get_meta("ecology_batch_key",""))
		if kind not in TREE_KINDS or key.is_empty() or node.multimesh==null or node.multimesh.mesh==null:
			continue
		var placements: Array=(node.get_meta("placements",[]) as Array).duplicate()
		if placements.is_empty():
			continue
		if not _batches.has(key):
			var all_indices: PackedInt32Array=PackedInt32Array()
			for index: int in range(placements.size()):
				all_indices.append(index)
			_batches[key]={"count":placements.size(),"nodes":[],"visible":all_indices}
		var batch: Dictionary=_batches[key]
		# The shared key means each index is one tree across all its mesh parts.
		# A mismatched resource cannot safely participate in that contract.
		if placements.size()!=int(batch.count):
			continue
		(batch.nodes as Array).append({"node":weakref(node),"placements":placements,"mesh_bounds":node.multimesh.mesh.get_aabb()})

func _blocks_view(bounds: AABB,eye: Vector3,aim: Vector3,offsets: Array[Vector3]) -> bool:
	if bounds.has_point(eye):
		return true
	# Parallel shoulder/head rays cover a small body-width window, not the
	# whole screen. Trees beyond the aim point remain part of the background.
	for offset: Vector3 in offsets:
		if bounds.intersects_segment(eye+offset,aim+offset)!=null:
			return true
	return false

func _apply(batch: Dictionary,visible: PackedInt32Array) -> void:
	for record: Dictionary in batch.nodes:
		var node: MultiMeshInstance3D=(record.node as WeakRef).get_ref() as MultiMeshInstance3D
		if not is_instance_valid(node) or node.multimesh==null:
			continue
		if visible.size()==int(batch.count):
			_restore(record)
			continue
		var placements: Array=record.placements as Array
		# Keep the original matrices intact in metadata. Compact only the live
		# visible prefix; never use zero scales or distant placeholder positions.
		for destination: int in range(visible.size()):
			node.multimesh.set_instance_transform(destination,placements[visible[destination]] as Transform3D)
		node.multimesh.visible_instance_count=visible.size()

func _restore(record: Dictionary) -> void:
	var node: MultiMeshInstance3D=(record.node as WeakRef).get_ref() as MultiMeshInstance3D
	if not is_instance_valid(node) or node.multimesh==null:
		return
	var placements: Array=record.placements as Array
	for index: int in range(placements.size()):
		node.multimesh.set_instance_transform(index,placements[index] as Transform3D)
	node.multimesh.visible_instance_count=-1
