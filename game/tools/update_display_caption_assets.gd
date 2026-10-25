extends SceneTree
const Cleanup = preload("res://tools/remove_display_caption.gd")

func _initialize() -> void:
	var path: String = "res://generated/training_room/light.scn"
	var scene: Node3D = load(path).instantiate() as Node3D
	var node: MeshInstance3D = scene.find_child("SM_Display_Warm_Plaster", true, false) as MeshInstance3D
	node.mesh = Cleanup.clean(node.mesh, node.transform)
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(scene) == OK)
	assert(ResourceSaver.save(packed, path, ResourceSaver.FLAG_COMPRESS) == OK)
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/training_room/detail_catalog.json"))
	for row: Dictionary in catalog.meshes:
		if str(row.node) == "SM_Display_Warm_Plaster":
			var source: Mesh = load(str(row.resource)) as Mesh
			assert(ResourceSaver.save(Cleanup.clean(source, node.transform), str(row.resource), ResourceSaver.FLAG_COMPRESS) == OK)
	scene.free()
	quit()
