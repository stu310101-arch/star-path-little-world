extends RefCounted

## Diagnostic only. Use while the caller freezes gameplay/fade/quality updates.
## Call apply() on each script-free world container, not on scripted world.gd.
## No Mesh, material, texture, collision, transform or production resource writes.
var _canonical: Dictionary = {}
var _sources: Dictionary = {}
var _records: Dictionary = {}
var _counters: Dictionary = {}

func _init() -> void:
	_reset_counters()

func _reset_counters() -> void:
	_counters = {"visited_meshes": 0, "eligible_meshes": 0, "changed_meshes": 0,
		"surface_rebindings": 0, "scripted_branches_skipped": 0,
		"hidden_branches_skipped": 0, "unsupported_meshes_skipped": 0,
		"unsupported_material_meshes_skipped": 0, "restored_meshes": 0,
		"restore_mesh_identity_mismatches": 0, "freed_meshes": 0}

func _value_key(value: Variant) -> String:
	if value is Object:
		return "object_identity:" + str(value.get_instance_id()) if is_instance_valid(value) else "null_object"
	if value is Array:
		var parts: PackedStringArray = []
		for item: Variant in value:
			parts.append(_value_key(item))
		return "array:" + var_to_bytes(parts).hex_encode()
	if value is Dictionary:
		var parts: PackedStringArray = []
		for key: Variant in value:
			parts.append(_value_key(key) + "=" + _value_key(value[key]))
		parts.sort()
		return "dictionary:" + var_to_bytes(parts).hex_encode()
	# Binary scalar encoding avoids rounding distinct float uniforms to text.
	return var_to_bytes(value).hex_encode()

func _signature(material: StandardMaterial3D) -> String:
	var values: PackedStringArray = []
	for property: Dictionary in material.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) != 0:
			var key: String = str(property.name)
			values.append(key + "=" + _value_key(material.get(key)))
	values.sort()
	# Retain the complete signature as key; no hash-collision equality shortcut.
	return str(values)

func _supported(material: Material) -> bool:
	return material is StandardMaterial3D and material.get_class() == "StandardMaterial3D" \
		and not material.resource_local_to_scene and material.get_script() == null \
		and material.next_pass == null and material.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED \
		and material.billboard_mode == BaseMaterial3D.BILLBOARD_DISABLED

func _intern(material: StandardMaterial3D) -> Material:
	var id: int = material.get_instance_id()
	if _sources.has(id):
		return _sources[id] as Material
	var signature: String = _signature(material)
	if not _canonical.has(signature):
		_canonical[signature] = material
	var canonical: Material = _canonical[signature] as Material
	_sources[id] = canonical
	return canonical

func apply(root: Node) -> Dictionary:
	if root != null:
		_visit(root)
	return stats()

func _visit(node: Node) -> void:
	if node.get_script() != null:
		_counters.scripted_branches_skipped += 1
		return
	if node is Node3D and not (node as Node3D).visible:
		_counters.hidden_branches_skipped += 1
		return
	if node is MeshInstance3D:
		_inspect(node as MeshInstance3D)
	# MultiMesh resources and buffers intentionally remain untouched.
	for child: Node in node.get_children():
		_visit(child)

func _inspect(visual: MeshInstance3D) -> void:
	var id: int = visual.get_instance_id()
	if _records.has(id):
		return
	_counters.visited_meshes += 1
	if visual.mesh == null or visual.skin != null or visual.material_overlay != null \
		or visual.mesh.get_script() != null or visual.transparency != 0.0:
		_counters.unsupported_meshes_skipped += 1
		return
	var active: Array[Material] = []
	var original_overrides: Array[Material] = []
	for surface: int in range(visual.mesh.get_surface_count()):
		var material: Material = visual.get_active_material(surface)
		if not _supported(material):
			_counters.unsupported_material_meshes_skipped += 1
			return
		active.append(material)
		original_overrides.append(visual.get_surface_override_material(surface))
	_counters.eligible_meshes += 1
	var replacements: Array[Material] = []
	var rebindings: int = 0
	for material: Material in active:
		var canonical: Material = _intern(material as StandardMaterial3D)
		replacements.append(canonical)
		rebindings += int(canonical != material)
	if rebindings == 0:
		return
	_records[id] = {"visual": weakref(visual), "mesh": visual.mesh,
		"material_override": visual.material_override, "surface_overrides": original_overrides}
	visual.material_override = null
	for surface: int in range(replacements.size()):
		visual.set_surface_override_material(surface, replacements[surface])
	_counters.changed_meshes += 1
	_counters.surface_rebindings += rebindings

func stats() -> Dictionary:
	var result: Dictionary = _counters.duplicate()
	result["source_material_identities"] = _sources.size()
	result["canonical_material_identities"] = _canonical.size()
	result["redundant_material_identities"] = _sources.size() - _canonical.size()
	result["pending_restore_meshes"] = _records.size()
	result["mesh_resources_changed"] = false
	result["comparison"] = "Every stored property, including names/metadata; nested resources retain exact identity"
	result["scope"] = "Visible script-free MeshInstance3D branches, opaque immutable StandardMaterial3D only"
	return result

func restore() -> Dictionary:
	for record: Dictionary in _records.values():
		var visual: MeshInstance3D = (record.visual as WeakRef).get_ref() as MeshInstance3D
		if visual == null:
			_counters.freed_meshes += 1
			continue
		# A changed mesh indicates the A/B caller did not freeze scene mutation.
		# Never apply stale surface slots to unrelated replacement geometry.
		if visual.mesh != record.mesh:
			_counters.restore_mesh_identity_mismatches += 1
			continue
		visual.material_override = record.material_override as Material
		for surface: int in range((record.surface_overrides as Array).size()):
			visual.set_surface_override_material(surface, record.surface_overrides[surface] as Material)
		_counters.restored_meshes += 1
	_records.clear()
	var result: Dictionary = stats()
	_canonical.clear()
	_sources.clear()
	_reset_counters()
	return result
