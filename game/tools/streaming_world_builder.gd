extends RefCounted

# All reduction happens in this offline tool. Runtime only reads the small
# binary chunks and never loads the canonical full district/globe scenes.
const OUTPUT: String = "res://generated/streaming/"
const CHUNK_NODES: int = 80
const CHUNK_TRIANGLES: int = 45000
const Geo = preload("res://scripts/planet_geometry.gd")
const MaterialPool = preload("res://tools/streaming_material_pool.gd")
const OverviewMaterialNormalizer = preload("res://tools/overview_material_normalizer.gd")
const OverviewFoliageLOD = preload("res://tools/overview_foliage_lod.gd")
const OverviewColorBatcher = preload("res://tools/overview_color_batcher.gd")
var material_pool: RefCounted = MaterialPool.new()
var overview_materials: RefCounted = OverviewMaterialNormalizer.new()
var overview_foliage: RefCounted = OverviewFoliageLOD.new()
var overview_colors: RefCounted = OverviewColorBatcher.new()
var radius: float = 48.0
var entries: Dictionary = {}
var details: Dictionary = {}
var overview_batches: Dictionary = {}
var mesh_cache: Dictionary = {}
var indexed_mesh_cache: Dictionary = {}
var source_triangles: int = 0
var overview_triangles: int = 0
var overview_vertices: int = 0
var overview_meshes: int = 0
var protected_surface_meshes: int = 0
var protected_surface_triangles: int = 0
var collision_count: int = 0
var layout: Dictionary = {}
var build_failed: bool = false

func build() -> bool:
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var old_paths: Array[String] = []
	if FileAccess.file_exists(OUTPUT + "catalog.json"):
		var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUTPUT + "catalog.json")) as Dictionary
		for row: Dictionary in previous.get("districts", []):
			for chunk: Dictionary in row.chunks:
				old_paths.append(str(chunk.path))
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	radius = float(layout.radius)
	var neighborhood: Node3D = Node3D.new()
	neighborhood.name = "Neighborhood"
	var globe: Node3D = Node3D.new()
	globe.name = "Globe"
	for station: Dictionary in layout.stations:
		var id: String = str(station.id)
		new_entry(id, array_vector(station.normal) * radius)
		var source: Node3D = (load("res://generated/districts/" + id + ".tscn") as PackedScene).instantiate() as Node3D
		stamp_visual_keys(source, id)
		extract_collisions(source, neighborhood, Transform3D.IDENTITY, id)
		for child: Node in source.get_children():
			collect_unit(child, source.transform, id)
		source.free()
		write_chunks(id)
		mesh_cache.clear()
		indexed_mesh_cache.clear()
		overview_colors.call("clear_geometry_cache")
		print("STREAMING_DISTRICT_BUILT ", id, " chunks=", (entries[id].chunks as Array).size(), " overview_triangles=", entries[id].overview_triangles)
	var full_globe: Node3D = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	stamp_visual_keys(full_globe, "globe")
	extract_collisions(full_globe, globe, Transform3D.IDENTITY, "Globe")
	for child: Node in full_globe.get_children():
		if child.name == "EcologicalReserves":
			var tree_groups: Dictionary = {}
			for reserve_child: Node in child.get_children():
				var id: String = district_for_node(reserve_child)
				var key: String = str(reserve_child.get_meta("ecology_batch_key", ""))
				if not key.is_empty():
					if not tree_groups.has(key):
						var group: Node3D = Node3D.new()
						group.name = "Planting_" + key
						tree_groups[key] = {"node":group,"id":id}
					(tree_groups[key].node as Node3D).add_child(reserve_child.duplicate(7))
				elif str(reserve_child.name).begins_with("Reserve_"):
					for item: Node in reserve_child.get_children():
						collect_unit(item, node_transform(child) * node_transform(reserve_child), id)
				else:
					collect_unit(reserve_child, node_transform(child), id)
			for key: String in tree_groups:
				var group: Node3D = tree_groups[key].node as Node3D
				collect_unit(group, node_transform(child), str(tree_groups[key].id))
				group.free()
		elif child.name == "SakuraGrove":
			new_entry("sakura", Vector3(.75, 1.0, .85).normalized() * radius)
			for item: Node in child.get_children():
				collect_unit(item, node_transform(child), "sakura")
		elif child.name == "OceanLife":
			# One bounded animation container per original actor. Its script and
			# metadata stay intact; a distant actor is neither created nor updated.
			var actor_index: int = 0
			for actor: Node in child.get_children():
				var center: Vector3 = actor.get_meta("centre", Vector3.UP) as Vector3
				var id: String = "ocean_%02d" % actor_index
				actor_index += 1
				new_entry(id, center * radius)
				var container: Node3D = Node3D.new()
				container.name = "OceanLife_" + str(actor.name).validate_node_name()
				container.set_script(load("res://scripts/ocean_life.gd"))
				container.set_meta("radius", radius)
				container.add_child(actor.duplicate(7))
				if str(actor.get_meta("kind", "")) == "boat":
					collect_overview(actor, Transform3D.IDENTITY, id)
				collect_unit(container, Transform3D.IDENTITY, id, true)
				container.free()
		elif not child is CollisionObject3D:
			# Ocean, inter-district bridges and their safe walking surfaces are
			# permanent. They are lightweight and remain valid during traversal.
			var copy: Node = child.duplicate(7)
			strip_collisions(copy)
			overview_materials.call("normalize_scene", copy)
			globe.add_child(copy)
	full_globe.free()
	for id: String in entries:
		var target: Node3D = neighborhood if not id.begins_with("ocean_") and id != "sakura" else globe
		make_overview(id, target)
		write_chunks(id)
	save_scene(neighborhood, OUTPUT + "neighborhood_base.scn")
	save_scene(globe, OUTPUT + "globe_base.scn")
	# Keep the editable/canonical station scene intact, including its labels,
	# interaction metadata and collisions. Only the startup visual copy changes.
	var stations: Node3D = (load("res://generated/stations.tscn") as PackedScene).instantiate() as Node3D
	overview_materials.call("normalize_scene", stations)
	save_scene(stations, OUTPUT + "stations_base.scn")
	stations.free()
	neighborhood.free()
	globe.free()
	var max_nodes: int = 0
	var max_triangles: int = 0
	var max_bytes: int = 0
	var chunk_count: int = 0
	for id: String in entries:
		for chunk: Dictionary in entries[id].chunks:
			max_nodes = maxi(max_nodes, int(chunk.nodes))
			max_triangles = maxi(max_triangles, int(chunk.triangles))
			max_bytes = maxi(max_bytes, int(chunk.bytes))
			chunk_count += 1
	var catalog: Dictionary = {"version":1,"radius":radius,"districts":entries.values(),"build":{"overview_input_triangles":source_triangles,"overview_triangles":overview_triangles,"overview_vertices":overview_vertices,"protected_surface_meshes":protected_surface_meshes,"permanent_collision_bodies":collision_count,"chunk_count":chunk_count,"chunk_target_nodes":CHUNK_NODES,"chunk_target_triangles":CHUNK_TRIANGLES,"max_chunk_nodes":max_nodes,"max_chunk_mesh_triangles":max_triangles,"max_chunk_bytes":max_bytes,"material_optimization":material_pool.call("statistics")}}
	catalog.build["overview_shader_normalization"] = overview_materials.call("statistics")
	catalog.build["overview_foliage_lod"] = overview_foliage.call("statistics")
	catalog.build["overview_color_batching"] = overview_colors.call("statistics")
	catalog.build["overview_meshes"] = overview_meshes
	catalog.build["protected_surface_triangles"] = protected_surface_triangles
	if build_failed:
		return false
	var catalog_path: String = OUTPUT + "catalog.json"
	var catalog_temporary: String = temporary_path(catalog_path)
	var catalog_file: FileAccess = FileAccess.open(catalog_temporary, FileAccess.WRITE)
	if catalog_file == null:
		push_error("Cannot create generated catalog staging file: " + catalog_temporary)
		return false
	catalog_file.store_string(JSON.stringify(catalog,"\t"))
	catalog_file.close()
	if not publish_generated(catalog_temporary, catalog_path):
		return false
	var live_paths: Array[String] = []
	for row: Dictionary in entries.values():
		for chunk: Dictionary in row.chunks:
			live_paths.append(str(chunk.path))
	for path: String in old_paths:
		if path.begins_with(OUTPUT) and path.ends_with(".scn") and not live_paths.has(path):
			DirAccess.remove_absolute(path)
	print("STREAMING_BUILD_OK ", JSON.stringify(catalog.build))
	return true

func new_entry(id: String, center: Vector3) -> void:
	entries[id] = {"id":id,"center":[center.x,center.y,center.z],"chunks":[],"detail_nodes":0,"overview_triangles":0}
	details[id] = []
	overview_batches[id] = {}

func array_vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func node_transform(node: Node) -> Transform3D:
	return (node as Node3D).transform if node is Node3D else Transform3D.IDENTITY

func nearest_station(point: Vector3) -> String:
	var nearest: String = "counseling"
	var best: float = -INF
	for row: Dictionary in layout.stations:
		var score: float = point.normalized().dot(array_vector(row.normal))
		if score > best:
			best = score
			nearest = str(row.id)
	return nearest

func district_for_node(node: Node) -> String:
	var node_name: String = str(node.name)
	if node_name.begins_with("Reserve_"):
		return node_name.trim_prefix("Reserve_")
	var batch_key: String = str(node.get_meta("ecology_batch_key", ""))
	if not batch_key.is_empty():
		var parts: PackedStringArray = batch_key.split("_")
		assert(parts[-1].is_valid_int(), "Ecology batch needs a final district index: " + batch_key)
		var index: int = int(parts[-1])
		return str(layout.stations[clampi(index, 0, 5)].id)
	var placements: Array = node.get_meta("placements", []) as Array
	return nearest_station((placements[0] as Transform3D).origin if not placements.is_empty() else node_transform(node).origin)

func stamp_visual_keys(node: Node, path: String, inherited: String = "") -> void:
	var key: String = inherited
	var is_group: bool = node.has_node("Foundation") or str(node.name).begins_with("SakuraTree_") or str(node.name).begins_with("sakura_")
	if node is MeshInstance3D:
		for child: Node in node.get_children():
			if child is CollisionObject3D:
				is_group = true
				if ((child as CollisionObject3D).collision_layer & 1) != 0:
					node.set_meta("streaming_preserve_surface", true)
	if is_group and key.is_empty():
		key = path
	if not key.is_empty() and (is_group or node is CollisionObject3D):
		node.set_meta("camera_visual_group", key)
	for child: Node in node.get_children():
		stamp_visual_keys(child, path + "/" + str(child.name), key)

func extract_collisions(node: Node, target: Node3D, parent_transform: Transform3D, prefix: String) -> void:
	var transform: Transform3D = parent_transform * node_transform(node)
	if node is StaticBody3D:
		var original: StaticBody3D = node as StaticBody3D
		var body: StaticBody3D = StaticBody3D.new()
		body.name = (prefix + "_" + str(node.name)).validate_node_name()
		body.transform = transform
		body.collision_layer = original.collision_layer
		body.collision_mask = original.collision_mask
		for key: StringName in original.get_meta_list():
			body.set_meta(key, original.get_meta(key))
		for child: Node in node.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				body.add_child(child.duplicate(0))
		if body.get_child_count() > 0:
			target.add_child(body)
			collision_count += 1
		else:
			body.free()
		return
	for child: Node in node.get_children():
		extract_collisions(child, target, transform, prefix + "_" + str(node.name))

func strip_collisions(node: Node) -> void:
	for child: Node in node.get_children():
		if child is CollisionObject3D or child is CollisionShape3D:
			node.remove_child(child)
			child.free()
		else:
			strip_collisions(child)

func collect_unit(node: Node, parent_transform: Transform3D, id: String, actor: bool = false) -> void:
	if node is CollisionObject3D or node is CollisionShape3D:
		return
	var copy: Node3D = node.duplicate(7) as Node3D
	if copy == null:
		return
	copy.transform = parent_transform * node_transform(node)
	strip_collisions(copy)
	if copy.get_child_count() == 0 and not copy is VisualInstance3D:
		copy.free()
		return
	copy.set_meta("streaming_unit", true)
	if not actor:
		collect_overview(copy, Transform3D.IDENTITY, id)
	(details[id] as Array).append(copy)

func collect_overview(node: Node, parent_transform: Transform3D, id: String) -> void:
	var transform: Transform3D = parent_transform * node_transform(node)
	# Swimming animals, particles and readable text only matter nearby.
	if node.get_script() != null and node.get_script().resource_path in ["res://scripts/lake_life.gd", "res://scripts/ocean_life.gd", "res://scripts/city_traffic.gd"]:
		return
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		if mi.mesh != null:
			var extent: Vector3 = (transform * mi.get_aabb()).size
			if maxf(extent.x, maxf(extent.y, extent.z)) >= .38:
				append_overview(mi.mesh, transform, mi, id)
	elif node is MultiMeshInstance3D:
		var multi: MultiMeshInstance3D = node as MultiMeshInstance3D
		var kind: String = str(multi.get_meta("ecology_kind", multi.get_meta("aquatic_kind", "")))
		if multi.multimesh != null and not kind in ["fern", "cattail", "water_lily"] and str(multi.name) != "SettledBlossoms":
			var placements: Array = multi.get_meta("placements", []) as Array
			var overview_mesh: Mesh = multi.multimesh.mesh
			if kind in ["alder", "birch", "willow", "pine"]:
				overview_mesh = overview_foliage.call("reduce", overview_mesh) as Mesh
			for placement: Transform3D in placements:
				append_overview(overview_mesh, transform * placement, null, id, multi.multimesh.mesh)
	for child: Node in node.get_children():
		collect_overview(child, transform, id)

func material_key(material: Material) -> String:
	return str(material_pool.call("material_key", material))

func reduced_mesh(mesh: Mesh) -> Mesh:
	var key: int = mesh.get_instance_id()
	if mesh_cache.has(key):
		return mesh_cache[key] as Mesh
	var importer: ImporterMesh = ImporterMesh.new()
	for surface: int in range(mesh.get_surface_count()):
		var source_arrays: Array = mesh.surface_get_arrays(surface)
		if not source_arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or (source_arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			var indices: PackedInt32Array = PackedInt32Array()
			indices.resize((source_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for index: int in range(indices.size()):
				indices[index] = index
			source_arrays[Mesh.ARRAY_INDEX] = indices
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, source_arrays)
	importer.generate_lods(60.0, 60.0, [])
	var result: ArrayMesh = ArrayMesh.new()
	for surface: int in range(importer.get_surface_count()):
		var arrays: Array = importer.get_surface_arrays(surface)
		var original_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		var count: int = original_indices.size() if not original_indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		# Retain the established connected-geometry LOD floor. A 10% trial lost
		# tower panels and roof silhouettes in the fixed-camera comparison, so
		# new reduction is limited to the separate distant-leaf export copies.
		var selected: PackedInt32Array = original_indices
		for level: int in range(importer.get_surface_lod_count(surface)):
			var candidate: PackedInt32Array = importer.get_surface_lod_indices(surface, level)
			if candidate.size() >= maxi(18, int(count * .20)):
				selected = candidate
		arrays[Mesh.ARRAY_INDEX] = null
		if not selected.is_empty():
			arrays[Mesh.ARRAY_INDEX] = selected
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_cache[key] = result
	return result

func append_overview(mesh: Mesh, transform: Transform3D, source: MeshInstance3D, id: String, original_mesh: Mesh = null) -> void:
	if mesh == null:
		return
	# The visual ocean stays at radius 48. A decimated curved ground patch
	# can form long chords below that ocean even if its vertices stay above
	# it. Preserve ground/roads/water geometry exactly; only batch it.
	var preserve_surface: bool = source != null and preserve_surface_geometry(source, transform)
	var reduced: Mesh = indexed_source_mesh(mesh) if preserve_surface else reduced_mesh(mesh)
	if preserve_surface:
		protected_surface_meshes += 1
	var batches: Dictionary = overview_batches[id]
	for surface: int in range(mesh.get_surface_count()):
		var material: Material = source.get_active_material(surface) if source != null else mesh.surface_get_material(surface)
		var prepared: Dictionary = overview_colors.call("prepare", reduced, surface, material)
		material = prepared.material as Material
		if prepared.mesh != reduced:
			material = overview_materials.call("normalize_material", material) as Material
		material = material_pool.call("canonical_material", material) as Material
		var key: String = material_key(material)
		if not batches.has(key):
			var tool: SurfaceTool = SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			tool.set_material(material)
			batches[key] = tool
		(batches[key] as SurfaceTool).append_from(prepared.mesh as Mesh, int(prepared.surface), transform)
		source_triangles += triangle_count(original_mesh if original_mesh != null else mesh, surface)
		var triangles: int = triangle_count(reduced, surface)
		if preserve_surface:
			protected_surface_triangles += triangles
		overview_triangles += triangles
		entries[id].overview_triangles += triangles

func indexed_source_mesh(mesh: Mesh) -> Mesh:
	var id: int = mesh.get_instance_id()
	if indexed_mesh_cache.has(id):
		return indexed_mesh_cache[id] as Mesh
	var result: ArrayMesh = ArrayMesh.new()
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		# SurfaceTool batches must not mix indexed and unindexed inputs: a
		# later deindex would otherwise drop unreferenced unindexed surfaces.
		# Adding identity indices leaves every authored triangle unchanged.
		if not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			var indices: PackedInt32Array = PackedInt32Array()
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for index: int in range(indices.size()):
				indices[index] = index
			arrays[Mesh.ARRAY_INDEX] = indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	indexed_mesh_cache[id] = result
	return result

func preserve_surface_geometry(source: MeshInstance3D, transform: Transform3D) -> bool:
	if bool(source.get_meta("streaming_preserve_surface", false)):
		return true
	for child: Node in source.get_children():
		if child is CollisionObject3D and ((child as CollisionObject3D).collision_layer & 1) != 0:
			return true
	for surface: int in range(source.mesh.get_surface_count()):
		var material: ShaderMaterial = source.get_active_material(surface) as ShaderMaterial
		if material != null and material.shader != null and material.shader.resource_path in ["res://shaders/lake_water.gdshader", "res://shaders/lake_bed.gdshader", "res://shaders/freshwater.gdshader"]:
			return true
	# Also protect thin surface markings and shore strips without colliders.
	# This tests actual world-space vertices, not the AABB's empty corners.
	for surface: int in range(source.mesh.get_surface_count()):
		var vertices: PackedVector3Array = source.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for vertex: Vector3 in vertices:
			var elevation: float = (transform * vertex).length() - radius
			if elevation < -1.0 or elevation > 1.5:
				return false
	return true

func triangle_count(mesh: Mesh, surface: int) -> int:
	var arrays: Array = mesh.surface_get_arrays(surface)
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	return int((indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3.0)

func make_overview(id: String, target: Node3D) -> void:
	var overview: Node3D = Node3D.new()
	var baked_triangles: int = 0
	overview.name = "Overview_" + id
	overview.set_meta("streaming_overview_id", id)
	for key: String in overview_batches[id]:
		var tool: SurfaceTool = overview_batches[id][key] as SurfaceTool
		var visual: MeshInstance3D = MeshInstance3D.new()
		visual.name = "BakedSilhouette_" + str(overview.get_child_count())
		# append_from carries unreferenced source vertices after LOD index
		# reduction. Rebuild only referenced vertices before deduplicating.
		tool.deindex()
		tool.index()
		visual.mesh = tool.commit()
		overview_materials.call("normalize_visual", visual)
		baked_triangles += triangle_count(visual.mesh, 0)
		overview_vertices += (visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		overview.add_child(visual)
		overview_meshes += 1
	assert(baked_triangles == int(entries[id].overview_triangles), "Baking dropped authored triangles in " + id)
	target.add_child(overview)
	(overview_batches[id] as Dictionary).clear()

func unit_triangles(node: Node) -> int:
	var total: int = 0
	var mesh: Mesh = null
	if node is MeshInstance3D:
		mesh = (node as MeshInstance3D).mesh
	elif node is MultiMeshInstance3D:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
	if mesh != null:
		for surface: int in range(mesh.get_surface_count()):
			total += triangle_count(mesh, surface)
	for child: Node in node.get_children():
		total += unit_triangles(child)
	return total

func write_chunks(id: String) -> void:
	var chunk: Node3D = Node3D.new()
	var nodes: int = 0
	var triangles: int = 0
	for unit: Node3D in details[id]:
		var unit_nodes: int = 1 + unit.find_children("*", "", true, false).size()
		var unit_tris: int = unit_triangles(unit)
		if chunk.get_child_count() > 0 and (nodes + unit_nodes > CHUNK_NODES or triangles + unit_tris > CHUNK_TRIANGLES):
			write_chunk(id, chunk, nodes, triangles)
			chunk = Node3D.new()
			nodes = 0
			triangles = 0
		chunk.add_child(unit)
		nodes += unit_nodes
		triangles += unit_tris
	if chunk.get_child_count() > 0:
		write_chunk(id, chunk, nodes, triangles)
	else:
		chunk.free()
	(details[id] as Array).clear()

func write_chunk(id: String, chunk: Node3D, nodes: int, triangles: int) -> void:
	var index: int = (entries[id].chunks as Array).size()
	chunk.name = "Detail_" + id + "_" + str(index)
	chunk.set_meta("streaming_district", id)
	chunk.set_meta("camera_region", true)
	var path: String = OUTPUT + id + "_%03d.scn" % index
	save_scene(chunk, path)
	(entries[id].chunks as Array).append({"path":path,"nodes":nodes,"triangles":triangles,"bytes":FileAccess.get_file_as_bytes(path).size()})
	entries[id].detail_nodes += nodes
	chunk.free()

func save_scene(node: Node, path: String) -> void:
	material_pool.call("canonicalize_scene", node)
	set_owners(node, node)
	var packed: PackedScene = PackedScene.new()
	var temporary: String = temporary_path(path)
	if packed.pack(node) != OK or ResourceSaver.save(packed, temporary, ResourceSaver.FLAG_COMPRESS) != OK:
		build_failed = true
		push_error("Cannot save generated scene: " + path)
	else:
		# The staging filename must not assign a fresh identity to an existing
		# scene or leave its UID pointing at a short-lived publication filename.
		var uid: int = ResourceLoader.get_resource_uid(path) if FileAccess.file_exists(path) else -1
		if uid >= 0 and ResourceSaver.set_uid(temporary, uid) != OK:
			build_failed = true
			push_error("Cannot preserve generated scene UID: " + path)
		elif not publish_generated(temporary, path):
			build_failed = true
	material_pool.call("clear_geometry_cache")

func temporary_path(path: String) -> String:
	return path.get_base_dir().path_join(".building_%d_" % OS.get_process_id() + path.get_file())

func publish_generated(temporary: String, path: String) -> bool:
	# File scanners may briefly hold an existing generated file open on Windows.
	# Save to a sibling first: a failed publication must not truncate the old one.
	if FileAccess.file_exists(path) and FileAccess.get_sha256(path) == FileAccess.get_sha256(temporary):
		DirAccess.remove_absolute(temporary)
		return true
	var output: Array = []
	var python: String = "python" if OS.has_feature("windows") else "python3"
	var arguments: PackedStringArray = PackedStringArray([ProjectSettings.globalize_path("res://../tools/atomic_replace_generated.py"), ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(OUTPUT)])
	var result: int = OS.execute(python, arguments, output, true, false)
	if result != 0:
		push_error("Cannot publish generated file after bounded retries: %s. Preserved staged file: %s. %s" % [path, temporary, str(output)])
	return result == 0

func set_owners(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.scene_file_path = ""
		child.owner = scene_root
		set_owners(child, scene_root)
