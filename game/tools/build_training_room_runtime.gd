extends SceneTree

const OUT: String = "res://generated/training_room/"
const SOURCE: String = "res://../art/TrainingRoom/runtime_exports/"
const CaptionCleanup = preload("res://tools/remove_display_caption.gd")
const IndoorOptimizer = preload("res://tools/indoor_runtime_optimizer.gd")

func _initialize() -> void:
	call_deferred("repair_backdrop" if OS.get_cmdline_user_args().has("--repair-backdrop") else "build")

func backdrop_mesh(detail: Mesh, startup: Mesh) -> Mesh:
	var result: Mesh = detail.duplicate(true) as Mesh
	assert(result.get_surface_count()==startup.get_surface_count())
	# Keep embedded boot materials. ArrayMesh.duplicate(true) can retain external
	# surface-material references and accidentally pull the deferred pack into boot.
	for surface: int in range(result.get_surface_count()):
		result.surface_set_material(surface,startup.surface_get_material(surface))
	return result

func repair_backdrop() -> void:
	# Rebuild the boot artifact from already exported detail meshes when the
	# optional Blender interchange exports are absent on this checkout.
	var light: Node3D = (load(OUT+"light.scn") as PackedScene).instantiate()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OUT+"detail_catalog.json")) as Dictionary
	var report: Array[Dictionary] = []
	for row: Dictionary in catalog.meshes:
		if not str(row.node).begins_with("SM_Backdrop_"): continue
		var node: MeshInstance3D = light.get_node(str(row.node)) as MeshInstance3D
		var before: int = node.mesh.get_faces().size()/3
		var replacement: Mesh = load(str(row.resource)) as Mesh
		node.mesh = backdrop_mesh(replacement,node.mesh)
		report.append({"node":row.node,"before_triangles":before,"after_triangles":node.mesh.get_faces().size()/3,"transform":str(node.transform)})
	own_tree(light,light)
	var packed := PackedScene.new()
	assert(packed.pack(light)==OK)
	assert(ResourceSaver.save(packed,OUT+"light.scn",ResourceSaver.FLAG_COMPRESS)==OK)
	FileAccess.open("res://../deliverables/world-correction/backdrop-repair.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BACKDROP_REPAIR ",JSON.stringify(report))
	light.free()
	quit()

func import_copy(path: String) -> Node3D:
	var document: GLTFDocument = GLTFDocument.new()
	var state: GLTFState = GLTFState.new()
	var error: Error = document.append_from_file(ProjectSettings.globalize_path(path), state)
	assert(error == OK, "Unable to import runtime room copy")
	return document.generate_scene(state) as Node3D

func own_tree(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		own_tree(child, owner_node)

func build() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT + "detail"))
	var light: Node3D = import_copy(SOURCE + "room_light.glb")
	var full: Node3D = import_copy(SOURCE + "room_detail.glb")
	for model: Node3D in [light, full]:
		var caption_mesh: MeshInstance3D = model.find_child("SM_Display_Warm_Plaster", true, false) as MeshInstance3D
		if caption_mesh != null:
			caption_mesh.mesh = CaptionCleanup.clean(caption_mesh.mesh, caption_mesh.transform)
	var entries: Array[Dictionary] = []
	var light_paths: Dictionary = {}
	for node: Node in light.find_children("*", "MeshInstance3D", true, false):
		light_paths[str(light.get_path_to(node))] = node
	var materials: Dictionary = {}
	var protected_backdrop_triangles: int = 0
	for node: Node in full.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var key: String = str(full.get_path_to(node))
		assert(light_paths.has(key), "Light/detail node paths differ: " + key)
		var light_node: MeshInstance3D = light_paths[key] as MeshInstance3D
		assert(light_node.transform.is_equal_approx(mesh_node.transform), "Light/detail transforms differ")
		# Collapsing the pleated backdrop to 18% creates thin overlapping faces
		# that shimmer until detail loading finishes. Keep this small architectural
		# group intact in the initial room; furniture still streams normally.
		if str(mesh_node.name).begins_with("SM_Backdrop_"):
			light_node.mesh = backdrop_mesh(mesh_node.mesh,light_node.mesh)
			for surface: int in range(mesh_node.mesh.get_surface_count()):
				protected_backdrop_triangles += mesh_node.mesh.surface_get_array_index_len(surface)/3
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var material: Material = mesh_node.mesh.surface_get_material(surface)
			if material == null:
				continue
			var id: int = material.get_instance_id()
			if not materials.has(id):
				var mat_path: String = OUT + "detail/material_%03d.res" % materials.size()
				assert(ResourceSaver.save(material, mat_path, ResourceSaver.FLAG_COMPRESS) == OK)
				material.take_over_path(mat_path)
				materials[id] = mat_path
		var mesh_path: String = OUT + "detail/mesh_%03d.res" % entries.size()
		assert(ResourceSaver.save(mesh_node.mesh, mesh_path, ResourceSaver.FLAG_COMPRESS) == OK)
		entries.append({"node": key, "resource": mesh_path})
	own_tree(light, light)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(light) == OK)
	assert(ResourceSaver.save(packed, OUT + "light.scn", ResourceSaver.FLAG_COMPRESS) == OK)
	var catalog: FileAccess = FileAccess.open(OUT + "detail_catalog.json", FileAccess.WRITE)
	catalog.store_string(JSON.stringify({"version": 1, "meshes": entries, "material_count": materials.size()}, "\t"))
	catalog.close()
	print("TRAINING_RUNTIME_BUILD meshes=", entries.size(), " materials=", materials.size(), " protected_backdrop_triangles=",protected_backdrop_triangles)
	light.free()
	full.free()
	IndoorOptimizer.optimize()
	quit()
