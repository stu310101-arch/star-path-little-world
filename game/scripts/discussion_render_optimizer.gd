extends Node3D
## Batch only immutable visual meshes. Each message device keeps its own script,
## thread, collider and label; render batching never combines interaction state.
var _sources: Array[Dictionary] = []
var _batches: Array[MultiMeshInstance3D] = []
var _configured: bool = false
var _stats: Dictionary = {"source_meshes":0,"source_surfaces":0,"batches":0,"batch_surfaces":0,"instances":0,"configure_usec":0}

func configure(garden: Node3D) -> void:
	if _configured:
		return
	_configured = true
	var started: int = Time.get_ticks_usec()
	var zones: Dictionary = garden.get("zones")
	for zone_id: String in zones:
		var zone: Dictionary = zones[zone_id]
		var groups: Dictionary = {}
		for device: Node3D in zone.get("devices",[]):
			for candidate: Node in device.find_children("*","MeshInstance3D",true,false):
				var visual: MeshInstance3D = candidate as MeshInstance3D
				if visual.mesh == null or visual.skin != null or not visual.visible or visual.get_script() != null:
					continue
				var key: String = _render_key(visual)
				if not groups.has(key): groups[key] = []
				groups[key].append(visual)
		for key: String in groups:
			var members: Array = groups[key]
			if members.size() < 2: continue
			_create_batch(zone_id,members)
	_stats.batches = _batches.size()
	_stats.configure_usec = Time.get_ticks_usec()-started

func _render_key(visual: MeshInstance3D) -> String:
	var key: String = str(visual.mesh.get_instance_id())+":"+str(visual.layers)+":"+str(visual.cast_shadow)+":"+str(visual.transparency)
	key += ":"+str(visual.material_overlay.get_instance_id() if visual.material_overlay != null else 0)
	for surface: int in range(visual.mesh.get_surface_count()):
		var material: Material = visual.get_active_material(surface)
		key += ":"+str(material.get_instance_id() if material != null else 0)
	return key

func _create_batch(zone_id: String, members: Array) -> void:
	var first: MeshInstance3D = members[0] as MeshInstance3D
	# Share mesh data unless a per-instance override actually needs baking into a
	# private mesh. Imported devices use their authored surface materials directly.
	var mesh: Mesh = first.mesh
	var overridden: bool = first.material_override != null
	for surface: int in range(mesh.get_surface_count()):
		overridden = overridden or first.get_surface_override_material(surface) != null
	if overridden:
		mesh = mesh.duplicate() as Mesh
		for surface: int in range(mesh.get_surface_count()): mesh.surface_set_material(surface,first.get_active_material(surface))
	var center: Vector3 = Vector3.ZERO
	for member: MeshInstance3D in members: center += member.global_transform * member.get_aabb().get_center()
	center /= float(members.size())
	var batch := MultiMeshInstance3D.new()
	batch.name = "DeviceBatch_"+zone_id+"_"+str(_batches.size())
	add_child(batch)
	batch.global_position = center
	batch.cast_shadow = first.cast_shadow
	batch.layers = first.layers
	batch.material_overlay = first.material_overlay
	batch.transparency = first.transparency
	batch.lod_bias = first.lod_bias
	batch.visibility_range_end = 64.0
	batch.visibility_range_end_margin = 5.0
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = mesh
	multimesh.instance_count = members.size()
	var bounds: AABB
	var placements: Array[Transform3D] = []
	var to_batch: Transform3D = batch.global_transform.affine_inverse()
	for index: int in range(members.size()):
		var member: MeshInstance3D = members[index] as MeshInstance3D
		var placement: Transform3D = to_batch * member.global_transform
		multimesh.set_instance_transform(index,placement)
		placements.append(placement)
		var box: AABB = placement * member.get_aabb()
		bounds = box if index == 0 else bounds.merge(box)
		_sources.append({"node":weakref(member),"visible":member.visible})
		member.visible = false
		_stats.source_meshes += 1
		_stats.source_surfaces += member.mesh.get_surface_count()
		_stats.instances += 1
	multimesh.custom_aabb = bounds
	batch.multimesh = multimesh
	batch.set_meta("discussion_zone",zone_id)
	batch.set_meta("placements",placements)
	_batches.append(batch)
	_stats.batch_surfaces += mesh.get_surface_count()

func metrics() -> Dictionary:
	return _stats.duplicate(true)

func restore() -> void:
	for record: Dictionary in _sources:
		var source: MeshInstance3D = (record.node as WeakRef).get_ref() as MeshInstance3D
		if is_instance_valid(source): source.visible = bool(record.visible)
	_sources.clear()
	for batch: MultiMeshInstance3D in _batches:
		if is_instance_valid(batch): batch.queue_free()
	_batches.clear()
	_configured = false
	_stats = {"source_meshes":0,"source_surfaces":0,"batches":0,"batch_surfaces":0,"instances":0,"configure_usec":0}
