extends SceneTree
const Architecture = preload("res://scripts/discussion_architecture.gd")

func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/discussion_garden/layout.json"))
	var scene: PackedScene = load("res://assets/discussion_garden/garden.glb")
	var art := scene.instantiate() as Node3D
	root.add_child(art)
	var source_meshes := art.find_children("SM_Zone_major*", "MeshInstance3D", true, false)
	var brackets: MeshInstance3D = Architecture.build(art, layout)
	assert(brackets != null)
	assert(brackets.mesh.get_surface_count() == 1)
	assert(brackets.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == 384)
	assert(Architecture.build(art, layout) == brackets)
	assert(brackets.get_active_material(0).resource_name == "MAT_Garden_PaletteMetal")
	var checks: Array = []
	for pair: Vector2 in [Vector2(-9.65, -9.68), Vector2(3.35, 2.98)]:
		for side: float in [-1.0, 1.0]:
			var bottom := brackets.transform * Vector3(side * 5.0, 3.52, pair.y)
			var top := brackets.transform * Vector3(side * 4.94, 4.85, pair.x)
			var pier := ""
			for collider: Dictionary in layout["colliders"]:
				if not str(collider["name"]).begins_with("Maker_") or not str(collider["name"]).ends_with("_Pier"):
					continue
				var c: Array = collider["center"]
				var s: Array = collider["size"]
				var delta := Basis(Vector3.UP, float(collider["rotation_y"])).inverse() * (bottom - Vector3(c[0], c[1], c[2]))
				if abs(delta.x) <= float(s[0]) / 2 and abs(delta.y) <= float(s[1]) / 2 and abs(delta.z) <= float(s[2]) / 2:
					pier = collider["name"]
					break
			assert(not pier.is_empty(), "Lower endpoint is unsupported")
			var closest := INF
			for node: Node in source_meshes:
				var instance := node as MeshInstance3D
				for surface: int in range(instance.mesh.get_surface_count()):
					var material := instance.get_active_material(surface)
					if material.resource_name != "MAT_Garden_PaletteMetal":
						continue
					var vertices: PackedVector3Array = instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					for vertex: Vector3 in vertices:
						closest = minf(closest, (instance.transform * vertex).distance_to(top))
			assert(closest < 0.067, "Upper endpoint does not touch the actual exported steel beam")
			checks.append({"pier": pier, "beamVertexDistance": closest, "bottom": str(bottom), "top": str(top)})
	var report := {"passed": true, "triangles": 128, "surfaces": 1, "reusedMaterial": brackets.get_active_material(0).resource_name, "contacts": checks}
	var report_path := ProjectSettings.globalize_path("res://").path_join("../art/DiscussionGarden/truss-bracket-qa.json").simplify_path()
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n")
	file.close()
	print("BRACKET_QA " + JSON.stringify(report))
	art.free()
	quit()
