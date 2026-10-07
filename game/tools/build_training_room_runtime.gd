extends SceneTree

const OUT: String = "res://generated/training_room/"
const SOURCE: String = "res://../art/TrainingRoom/runtime_exports/"

func _initialize() -> void:
	call_deferred("build")

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
	var entries: Array[Dictionary] = []
	var light_paths: Dictionary = {}
	for node: Node in light.find_children("*", "MeshInstance3D", true, false):
		light_paths[str(light.get_path_to(node))] = node
	var materials: Dictionary = {}
	for node: Node in full.find_children("*", "MeshInstance3D", true, false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		var key: String = str(full.get_path_to(node))
		assert(light_paths.has(key), "Light/detail node paths differ: " + key)
		var light_node: MeshInstance3D = light_paths[key] as MeshInstance3D
		assert(light_node.transform.is_equal_approx(mesh_node.transform), "Light/detail transforms differ")
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
	print("TRAINING_RUNTIME_BUILD meshes=", entries.size(), " materials=", materials.size())
	light.free()
	full.free()
	quit()
