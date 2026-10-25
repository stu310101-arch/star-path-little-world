extends SceneTree

const SHADERS: Array[String] = [
	"res://shaders/world_surface.gdshader", "res://shaders/freshwater.gdshader",
	"res://shaders/lake_bed.gdshader", "res://shaders/lake_water.gdshader",
]
var report: Dictionary = {"surfaces": [], "totals": {}}
var examined: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var paths: Array[String] = [
		"res://generated/streaming/globe_base.scn",
		"res://generated/streaming/neighborhood_base.scn",
		"res://generated/streaming/stations_base.scn",
	]
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json"))
	for region: Dictionary in catalog.districts:
		for chunk: Dictionary in region.chunks:
			paths.append(str(chunk.path))
	for path: String in paths:
		var scene: Node = (load(path) as PackedScene).instantiate()
		visit(scene, path)
		scene.free()
	var folder: String = ProjectSettings.globalize_path("res://../deliverables/render-budget")
	DirAccess.make_dir_recursive_absolute(folder)
	FileAccess.open(folder.path_join("surface-winding.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("SURFACE_WINDING ", JSON.stringify(report.totals))
	quit()

func visit(node: Node, path: String) -> void:
	if node is MeshInstance3D:
		var visual: MeshInstance3D = node as MeshInstance3D
		if visual.mesh != null:
			for surface: int in range(visual.mesh.get_surface_count()):
				var material: ShaderMaterial = visual.get_active_material(surface) as ShaderMaterial
				if material == null or material.shader == null or material.shader.resource_path not in SHADERS:
					continue
				var key: String = str(visual.mesh.get_instance_id()) + ":" + str(surface)
				if examined.has(key):
					continue
				examined[key] = visual.mesh
				var arrays: Array = visual.mesh.surface_get_arrays(surface)
				var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
				if indices.is_empty():
					indices.resize(points.size())
					for i: int in indices.size():
						indices[i] = i
				var front: int = 0
				var reversed: int = 0
				var degenerate: int = 0
				for i: int in range(0, indices.size(), 3):
					var a: int = indices[i]
					var b: int = indices[i + 1]
					var c: int = indices[i + 2]
					var cross: Vector3 = (points[c] - points[a]).cross(points[b] - points[a])
					if cross.length_squared() < 1e-18:
						degenerate += 1
					elif cross.dot(normals[a] + normals[b] + normals[c]) > 0:
						front += 1
					else:
						reversed += 1
				var shader: String = material.shader.resource_path
				report.surfaces.append({"scene": path, "node": str(node.name), "shader": shader,
					"front": front, "reversed": reversed, "degenerate": degenerate})
				if not report.totals.has(shader):
					report.totals[shader] = {"front": 0, "reversed": 0, "degenerate": 0}
				report.totals[shader].front += front
				report.totals[shader].reversed += reversed
				report.totals[shader].degenerate += degenerate
	for child: Node in node.get_children():
		visit(child, path)
