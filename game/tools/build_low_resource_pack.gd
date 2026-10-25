extends SceneTree
## Build separate export copies. Canonical scenes and Blender masters are read-only.
const Builder = preload("res://tools/streaming_world_builder.gd")
const LowArt = preload("res://scripts/low_world_art.gd")
const OUTPUT: String = "res://generated/low/"
var meshes: Dictionary = {}
var materials: Dictionary = {}
var textures: Dictionary = {}
var foliage: RefCounted = preload("res://tools/overview_foliage_lod.gd").new()
var _source_references: Array[Resource] = []
var report: Dictionary = {"version":3,"removed_buildings":0,"retained_buildings":0,"retained_landscape_trees":0,"removed_decor_nodes":0,"texture_limit":256,"campus_miniatures":true,"campus_modules_per_exhibit":4,"message_devices":40,"simplification_target":0.5,"eligible_triangles_before":0,"eligible_triangles_after":0,"reduced_meshes":0,"walkable_collision_changed":false,"removed_features":["sakura_grove"],"reduced_features":["trees","secondary_buildings","ships","fish","water_tessellation","micro_decoration"]}

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	if OS.get_cmdline_user_args().has("--recommendation-only"):
		report = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "manifest.json")) as Dictionary
		_record_recommendation()
		_write_json(OUTPUT + "manifest.json", report)
		print("LOW_RECOMMENDATION_BUILD_OK ", JSON.stringify(report["recommendation_scenery"]))
		quit()
		return
	if OS.get_cmdline_user_args().has("--counseling-only"):
		report = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "manifest.json")) as Dictionary
		_build_counseling()
		_write_json(OUTPUT + "manifest.json", report)
		print("LOW_COUNSELING_BUILD_OK ", JSON.stringify(report["counseling_scenery"]))
		quit()
		return
	foliage.set("keep_fraction",.35)
	var builder: RefCounted = Builder.new()
	builder.set("output_directory", OUTPUT + "streaming/")
	builder.set("base_only", true)
	builder.set("low_builder", self)
	builder.set("art_direction", LowArt.new())
	if not builder.call("build"):
		quit(1)
		return
	_build_hall()
	_build_garden()
	_build_admissions()
	_build_training()
	_build_counseling()
	_record_recommendation()
	report["foliage"] = foliage.call("statistics")
	_write_json(OUTPUT + "manifest.json", report)
	for frame: int in range(8):
		await process_frame
	_source_references.clear()
	for frame: int in range(8):
		await process_frame
	print("LOW_RESOURCE_BUILD_OK ", JSON.stringify(report))
	quit()

func _record_recommendation() -> void:
	# This room's paired Blender exports already share a layout and enforce the
	# low geometry/texture budget. Never simplify the canonical master in-place.
	var path: String = "res://../art/RecommendationRoom/export-report.json"
	assert(FileAccess.file_exists(path), "Run tools/build_recommendation_room.py with Blender first")
	var authored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	assert(FileAccess.file_exists(OUTPUT + "recommendation/recommendation_room.glb"))
	assert(FileAccess.file_exists(OUTPUT + "recommendation/layout.json"))
	report["recommendation_scenery"] = (authored.low as Dictionary).duplicate(true)
	report["recommendation_scenery"]["source_sha256"] = FileAccess.get_sha256("res://../art/RecommendationRoom/RecommendationRoom.blend")

func prune(root: Node) -> void:
	# Each canonical urban district contains eight decorative building wrappers.
	# Keep five of eight authored buildings, preserving architectural variety.
	var planting: Dictionary = {}
	_collect_planting(root, Transform3D.IDENTITY, planting)
	var building_index: int = 0
	for child: Node in root.get_children():
		if child.has_node("Foundation"):
			building_index += 1
			if building_index > 5:
				report.removed_buildings += 1
				root.remove_child(child)
				child.free()
				continue
			report.retained_buildings += 1
	_prune(root)
	_restore_planting(root, planting)
	_flatten(root)

func _collect_planting(node: Node, parent_transform: Transform3D, planting: Dictionary) -> void:
	if node.name == "SakuraGrove":
		return
	var at: Transform3D = parent_transform * (node.transform if node is Node3D else Transform3D.IDENTITY)
	# Reuse safe, authored trunk locations, never arbitrary points on roads/water.
	if node is CollisionObject3D and node.has_meta("species") and node.has_meta("district_index"):
		var district: int = int(node.get_meta("district_index"))
		if not planting.has(district):
			planting[district] = []
		(planting[district] as Array).append({"transform":at,"kind":str(node.get_meta("species"))})
	for child: Node in node.get_children():
		_collect_planting(child, at, planting)

func _restore_planting(root: Node, planting: Dictionary) -> void:
	var reserve: Node = root.get_node_or_null("EcologicalReserves")
	if reserve == null:
		return
	for district: int in planting:
		var candidates: Array = planting[district]
		var count: int = mini(18, candidates.size())
		for index: int in range(count):
			var candidate: Dictionary = candidates[index * candidates.size() / count]
			var original: Transform3D = candidate.transform
			var tree: Node3D = Node3D.new()
			tree.name = "LowScenicTree_%d_%d" % [district,index]
			reserve.add_child(tree)
			tree.transform = original
			var authored: Node3D = (load("res://assets/vegetation_rebuilt/" + str(candidate.kind) + ".glb") as PackedScene).instantiate() as Node3D
			for part: MeshInstance3D in authored.find_children("*","MeshInstance3D",true,false):
				part.mesh = foliage.call("reduce",part.mesh) as Mesh
			tree.add_child(authored)
			var body: StaticBody3D = StaticBody3D.new()
			body.name = "LowTrunkCollider"
			body.collision_layer = 8
			body.collision_mask = 0
			tree.add_child(body)
			var collider: CollisionShape3D = CollisionShape3D.new()
			var shape: BoxShape3D = BoxShape3D.new()
			shape.size = Vector3(.35,1.8,.35)
			collider.shape = shape
			collider.position.y = .9
			body.add_child(collider)
			report.retained_landscape_trees += 1

func _prune(node: Node) -> void:
	for child: Node in node.get_children():
		var label: String = str(child.name).to_lower()
		var script_path: String = child.get_script().resource_path if child.get_script() != null else ""
		if script_path in ["res://scripts/ocean_life.gd", "res://scripts/lake_life.gd"]:
			_thin_water_life(child)
			continue
		var remove: bool = label in ["sakuragrove", "citytraffic"] or child is MultiMeshInstance3D or child is GPUParticles3D or child is CPUParticles3D
		remove = remove or child.has_meta("ecology_kind") or "trunk" in label or (child is CollisionObject3D and "tree" in label)
		remove = remove or script_path == "res://scripts/city_traffic.gd"
		# Surface meshes are the walkable land/roads/water and always survive.
		if not child.has_meta("authored_surface") and not child is CollisionObject3D:
			for word: String in ["tree", "fern", "cattail", "flower", "bush", "petal", "streetlight"]:
				remove = remove or word in label
		if remove:
			report.removed_decor_nodes += 1
			# Clear shader overrides before Dummy rendering releases their RIDs.
			_clear_render_materials(child)
			node.remove_child(child)
			child.queue_free()
		else:
			_prune(child)

func _thin_water_life(node: Node) -> void:
	var kept: Dictionary = {}
	var seen: Dictionary = {}
	# A few boats and small fish groups keep the water alive at a lower update rate.
	for actor: Node in node.get_children():
		var kind: String = str(actor.get_meta("kind", "fish"))
		seen[kind] = int(seen.get(kind,0)) + 1
		var limit: int = 2 if kind == "boat" else 6
		var retain: bool = not actor is MultiMeshInstance3D and kind in ["boat","fish"] and int(kept.get(kind,0)) < limit and int(seen[kind]) % 3 == 1
		if retain:
			kept[kind] = int(kept.get(kind,0)) + 1
		else:
			_clear_render_materials(actor)
			node.remove_child(actor)
			actor.queue_free()
	# Avoid the full builder's per-actor streaming split: these few actors remain
	# in the small base scene with the original motion/placement script.
	node.name = "Low" + str(node.name)
	node.set("quality_update_interval", .15)
	var counts: Dictionary = report.get("water_life", {})
	for kind: String in seen:
		var row: Dictionary = counts.get(kind,{"before":0,"retained":0})
		row.before += int(seen[kind])
		row.retained += int(kept.get(kind,0))
		counts[kind] = row
	report["water_life"] = counts

func _clear_render_materials(node: Node) -> void:
	if node is GeometryInstance3D:
		if (node as GeometryInstance3D).material_override != null:
			_source_references.append((node as GeometryInstance3D).material_override)
		if (node as GeometryInstance3D).material_overlay != null:
			_source_references.append((node as GeometryInstance3D).material_overlay)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			_source_references.append((node as MeshInstance3D).mesh)
			(node as MeshInstance3D).mesh = null
		if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			_source_references.append((node as MultiMeshInstance3D).multimesh)
			(node as MultiMeshInstance3D).multimesh = null
		(node as GeometryInstance3D).material_override = StandardMaterial3D.new()
		(node as GeometryInstance3D).material_overlay = null
	for child: Node in node.get_children():
		_clear_render_materials(child)

func _flat(source: Material) -> StandardMaterial3D:
	var key: int = source.get_instance_id() if source != null else 0
	if materials.has(key):
		return materials[key] as StandardMaterial3D
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.resource_name = source.resource_name if source != null else "MAT_Low_Palette"
	material.roughness = .95
	if source is StandardMaterial3D:
		var original: StandardMaterial3D = source as StandardMaterial3D
		material.albedo_color = original.albedo_color
		material.vertex_color_use_as_albedo = original.vertex_color_use_as_albedo
		material.vertex_color_is_srgb = original.vertex_color_is_srgb
		material.cull_mode = original.cull_mode
		material.roughness = original.roughness
		material.metallic = original.metallic
		material.transparency = original.transparency
		material.alpha_scissor_threshold = original.alpha_scissor_threshold
		material.shading_mode = original.shading_mode
		material.emission_enabled = original.emission_enabled
		material.emission = original.emission
		material.emission_energy_multiplier = minf(original.emission_energy_multiplier,1)
		material.uv1_scale = original.uv1_scale
		material.uv1_offset = original.uv1_offset
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		if original.albedo_texture != null:
			material.albedo_texture = _small_texture(original.albedo_texture,512 if "Starry_Night" in original.resource_name else 256)
	elif source is ShaderMaterial:
		var shader_path: String = (source as ShaderMaterial).shader.resource_path
		material.albedo_color = Color("4b8e9c") if "water" in shader_path or "ocean" in shader_path else Color("688367")
		if "water" in shader_path or "ocean" in shader_path:
			material.albedo_color.a = .65
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.roughness = .35
	materials[key] = material
	return material

func _small_texture(source: Texture2D, limit: int) -> Texture2D:
	var key: String = str(source.get_instance_id()) + ":" + str(limit)
	if textures.has(key):
		return textures[key] as Texture2D
	var bitmap: Image = source.get_image()
	if bitmap == null:
		return null
	if bitmap.is_compressed():
		bitmap.decompress()
	var factor: float = minf(1,float(limit)/maxi(bitmap.get_width(),bitmap.get_height()))
	bitmap.resize(maxi(1,roundi(bitmap.get_width()*factor)),maxi(1,roundi(bitmap.get_height()*factor)),Image.INTERPOLATE_LANCZOS)
	bitmap.generate_mipmaps()
	var texture: ImageTexture = ImageTexture.create_from_image(bitmap)
	textures[key] = texture
	return texture

func _flatten(node: Node) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var instance: MeshInstance3D = node as MeshInstance3D
		var source: Mesh = instance.mesh
		if str(instance.name).to_lower() == "ocean":
			var sphere: SphereMesh = SphereMesh.new()
			var original_radius: float = source.get_faces()[0].length()
			sphere.radius = original_radius
			sphere.height = sphere.radius*2
			sphere.radial_segments = 96
			sphere.rings = 48
			sphere.material = _flat(instance.get_active_material(0))
			report["ocean_triangles"] = {"before":source.get_faces().size()/3,"after":sphere.get_faces().size()/3,"radius_before":original_radius,"radius_after":sphere.radius}
			instance.material_override = null
			instance.mesh = sphere
			source = sphere
		var reduce: bool = not instance.has_meta("authored_surface") and not instance.has_meta("low_preserve_geometry")
		for child: Node in instance.get_children():
			if child is CollisionObject3D and ((child as CollisionObject3D).collision_layer & 1) != 0:
				reduce = false
		var key: String = str(source.get_instance_id()) + ":" + str(reduce)
		for index: int in range(source.get_surface_count()):
			key += ":" + str(instance.get_active_material(index).get_instance_id() if instance.get_active_material(index) != null else 0)
		if not meshes.has(key):
			var mesh: ArrayMesh = ArrayMesh.new()
			for index: int in range(source.get_surface_count()):
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, source.surface_get_arrays(index))
				mesh.surface_set_material(index, _flat(instance.get_active_material(index)))
			meshes[key] = _reduce(mesh) if reduce else mesh
		instance.material_override = null
		instance.material_overlay = null
		instance.mesh = meshes[key] as Mesh
		for index: int in range(instance.mesh.get_surface_count()):
			instance.set_surface_override_material(index, null)
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_flatten(child)

func _reduce(source: ArrayMesh) -> ArrayMesh:
	var importer: ImporterMesh = ImporterMesh.new()
	for surface: int in range(source.get_surface_count()):
		var arrays: Array = source.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		if indices.is_empty():
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for index: int in range(indices.size()):
				indices[index] = index
		arrays[Mesh.ARRAY_INDEX] = indices
		# Preserve UVs and authored colours; only the normal-map tangent data goes.
		arrays[Mesh.ARRAY_TANGENT] = null
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, source.surface_get_material(surface))
	importer.generate_lods(80.0, 80.0, [])
	var result: ArrayMesh = ArrayMesh.new()
	var before: int = 0
	var after: int = 0
	for surface: int in range(importer.get_surface_count()):
		var arrays: Array = importer.get_surface_arrays(surface)
		var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var selected: PackedInt32Array = original
		for level: int in range(importer.get_surface_lod_count(surface)):
			var candidate: PackedInt32Array = importer.get_surface_lod_indices(surface, level)
			if candidate.size() >= maxi(18, original.size() / 2) and candidate.size() < selected.size():
				selected = candidate
		arrays[Mesh.ARRAY_INDEX] = selected
		var temporary: ArrayMesh = ArrayMesh.new()
		temporary.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var tool: SurfaceTool = SurfaceTool.new()
		tool.create_from(temporary, 0)
		tool.deindex()
		tool.index()
		tool.set_material(source.surface_get_material(surface))
		tool.commit(result)
		before += original.size() / 3
		after += selected.size() / 3
	report.eligible_triangles_before += before
	report.eligible_triangles_after += after
	if after < before:
		report.reduced_meshes += 1
	return result

func _save(root: Node3D, path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_own(root, root)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(root) == OK)
	assert(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK)
	root.free()

func _own(node: Node, root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = root
		_own(child, root)

func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t") + "\n")
	file.close()

func _build_hall() -> void:
	for kind: String in ["atrium", "gallery", "exhibit_kit", "feature_book"]:
		var model: Node3D = (load("res://assets/university_hall/" + kind + ".glb") as PackedScene).instantiate() as Node3D
		_flatten(model)
		_save(model,OUTPUT + "university/" + kind + ".scn")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/university_hall/layout.json")) as Dictionary
	layout["low_resources"] = true
	_write_json(OUTPUT + "university/layout.json",layout)

func _import_blender(kind: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = document.append_from_file(ProjectSettings.globalize_path("res://../art/LowResources/runtime_exports/" + kind + ".glb"),state)
	assert(error == OK, "Run tools/export_low_art.py with Blender before building the low pack")
	var model: Node3D = document.generate_scene(state) as Node3D
	_flatten(model)
	return model

func _build_garden() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/discussion_garden/layout.json")) as Dictionary
	layout["low_resources"] = true
	var export_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../art/LowResources/runtime_exports/report.json")) as Dictionary
	var removed_trees: Array = export_report.garden.get("removed_tree_positions",[])
	layout.colliders = (layout.colliders as Array).filter(func(row: Dictionary) -> bool:
		if str(row.name).begins_with("LearningGrove_EastCabin") or str(row.name).begins_with("Maker_East"):
			return false
		if "Trunk" in str(row.name):
			for point: Array in removed_trees:
				if Vector2(point[0]-row.center[0],point[2]-row.center[2]).length() < .85:
					return false
		return true)
	_save(_import_blender("garden"),OUTPUT + "discussion/garden.scn")
	_write_json(OUTPUT + "discussion/layout.json",layout)
	var device: Node3D = (load("res://assets/discussion_garden/message_device.glb") as PackedScene).instantiate() as Node3D
	_flatten(device)
	_save(device,OUTPUT + "discussion/device.scn")
	report["discussion_scenery"] = export_report.garden

func _build_admissions() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/admissions_room/layout.json")) as Dictionary
	layout["low_resources"] = true
	layout.colliders = (layout.colliders as Array).filter(func(row: Dictionary) -> bool: return str(row.id) != "PassportPlant")
	_save(_import_blender("admissions"),OUTPUT + "admissions/studio.scn")
	_write_json(OUTPUT + "admissions/layout.json",layout)
	var export_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../art/LowResources/runtime_exports/report.json")) as Dictionary
	report["admissions_scenery"] = export_report.admissions

func _build_training() -> void:
	var model: Node3D = (load("res://generated/training_room/light.scn") as PackedScene).instantiate() as Node3D
	var removed: int = 0
	for node: Node in model.get_children():
		var label: String = str(node.name)
		if label.begins_with("SM_Display_") or label.begins_with("CABINET_DOOR_") or label.begins_with("SOCKET_Genshin_") or label.begins_with("SM_Inlays_") or label == "DECOR_Botanical":
			model.remove_child(node)
			node.free()
			removed += 1
	# The existing startup meshes already have a careful furniture LOD. Keep its
	# silhouettes, readable painting, books, computers and seats; lower textures only.
	for node: Node in model.find_children("*","MeshInstance3D",true,false):
		node.set_meta("low_preserve_geometry",true)
	_flatten(model)
	_save(model,OUTPUT + "training/room.scn")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/training_room/layout.json")) as Dictionary
	layout["low_resources"] = true
	layout.colliders = (layout.colliders as Array).filter(func(row: Dictionary) -> bool: return str(row.name) != "Genshin_Cabinet")
	layout.decor_targets = (layout.decor_targets as Array).filter(func(row: Dictionary) -> bool: return str(row.id) != "botanical_wall")
	layout.cabinet_doors = []
	layout.empty_display_sockets = []
	_write_json(OUTPUT + "training/layout.json",layout)
	report["training_scenery"] = {"removed_decor_groups":removed,"computers_retained":layout.computers.size(),"readable_books_retained":layout.books.size(),"decor_targets_retained":layout.decor_targets.size()}

func _build_counseling() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/counseling_room/layout.json")) as Dictionary
	layout["low_resources"] = true
	var model: Node3D = _import_blender("counseling")
	var triangles: int = 0
	for part: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		triangles += part.mesh.get_faces().size() / 3
	_save(model, OUTPUT + "counseling/room.scn")
	_write_json(OUTPUT + "counseling/layout.json", layout)
	var exports: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../art/LowResources/runtime_exports/report.json")) as Dictionary
	var scenery: Dictionary = (exports.counseling as Dictionary).duplicate(true)
	scenery["runtime_triangles"] = triangles
	scenery["texture_limit"] = 256
	scenery["source_revision"] = layout.get("revision", "")
	scenery["seats_retained"] = (layout.get("interactables", []) as Array).filter(func(row: Dictionary) -> bool: return row.get("kind", "") == "seat").size()
	scenery["stations_retained"] = (layout.stations as Array).size()
	scenery["colliders_retained"] = (layout.colliders as Array).size()
	report["counseling_scenery"] = scenery
