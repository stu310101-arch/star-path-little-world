extends SceneTree

const Minimap = preload("res://scripts/world_minimap.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Geo = preload("res://scripts/planet_geometry.gd")

func contains_point(point: Vector2, polygon: PackedVector2Array) -> bool:
	# Independent horizontal-ray coverage oracle. Geometry2D's long diagonal
	# ray can count an almost coincident vertex twice on these narrow curves.
	var inside: bool = false
	for index: int in range(polygon.size()):
		var a: Vector2 = polygon[index]
		var b: Vector2 = polygon[(index + 1) % polygon.size()]
		if (a.y > point.y) != (b.y > point.y):
			var crossing_x: float = float(a.x) + (float(point.y) - float(a.y)) * (float(b.x) - float(a.x)) / (float(b.y) - float(a.y))
			if float(point.x) < crossing_x:
				inside = not inside
	return inside

func _initialize() -> void:
	var minimap: Control = Minimap.new() as Control
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var radius: float = float(layout.radius)
	minimap.set("radius", radius)
	minimap.size = Vector2(224, 180)
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var patches: Array[Dictionary] = []
	var directions: Array[Vector3] = Routes.directions()
	for i: int in range(data.size()):
		patches.append(minimap.call("build_patch", data[i], i, directions[i]))
	patches.append(minimap.call("build_sakura_patch"))
	var samples: Array[Vector3] = []
	for edge: Vector2i in Routes.bridge_edges():
		for step: int in range(41):
			samples.append(directions[edge.x].slerp(directions[edge.y], float(step) / 40.0))
	# Cover the inhabited archipelago and shore approaches at the current scale.
	for patch: Dictionary in patches:
		for x: float in [-36.0, -18.0, 0.0, 18.0, 36.0]:
			for z: float in [-36.0, -18.0, 0.0, 18.0, 36.0]:
				samples.append(Geo.surface(patch.up as Vector3, Vector2(x,z), radius).normalized())
	if OS.get_cmdline_user_args().has("--focused"):
		samples.assign([directions[0].slerp(directions[1], .525)])
	var raw_failures: int = 0
	var clipped_failures: int = 0
	var coverage_failures: int = 0
	var tested: int = 0
	var clipped_tested: int = 0
	var coverage_tested: int = 0
	# Rotating the transported frame and changing scale must not cause a
	# triangulation failure at a bridge, pole, offscreen edge, or adjacent island.
	for dimensions: Vector2 in [Vector2(224, 180), Vector2(280, 224)]:
		minimap.size = dimensions
		for sample: Vector3 in samples:
			minimap.set("frame_ready", false)
			minimap.call("update_map_frame", sample)
			var reference: Vector3 = minimap.get("map_forward") as Vector3
			for rotation_angle: float in [0.0, .71, 1.57]:
				var forward: Vector3 = reference.rotated(sample, rotation_angle)
				minimap.set("map_forward", forward)
				minimap.set("map_right", forward.cross(sample).normalized())
				for patch: Dictionary in patches:
					if sample.dot(patch.up as Vector3) < .35:
						continue
					var polygons: Array[PackedVector3Array] = [patch.coast]
					for water: Dictionary in patch.water:
						polygons.append(water.points)
						polygons.append_array(water.inner)
					for polygon: PackedVector3Array in polygons:
						var projected: PackedVector2Array = minimap.call("project_line", polygon)
						tested += 1
						if Geometry2D.triangulate_polygon(projected).is_empty():
							raw_failures += 1
						var pieces: Array[PackedVector2Array] = minimap.call("project_polygons", polygon)
						for piece: PackedVector2Array in pieces:
							clipped_tested += 1
							var indices: PackedInt32Array = minimap.call("triangulate_surface", piece)
							if indices.is_empty():
								clipped_failures += 1
								if clipped_failures < 4:
									print("CLIPPED_FAIL sample=", sample, " patch=", patch.name, " points=", piece)
						# Verify clipping/cleanup did not simply discard visible water.
						for x: float in [.08, .5, .92]:
							for y: float in [.08, .5, .92]:
								var probe: Vector2 = dimensions * Vector2(x, y)
								var expected: bool = contains_point(probe, projected)
								var covered: bool = false
								for piece: PackedVector2Array in pieces:
									covered = covered or contains_point(probe, piece)
								coverage_tested += 1
								if covered != expected:
									coverage_failures += 1
									if coverage_failures < 4:
										var edge_distance: float = INF
										for index: int in range(projected.size()):
											edge_distance = minf(edge_distance, probe.distance_to(Geometry2D.get_closest_point_to_segment(probe, projected[index], projected[(index + 1) % projected.size()])))
										print("COVERAGE_FAIL sample=", sample, " patch=", patch.name, " point=", probe, " edge_distance=", edge_distance, " expected=", expected)
	var failures: int = raw_failures + clipped_failures + coverage_failures
	print(JSON.stringify({"passed": failures == 0, "samples": samples.size(), "projected_surfaces": tested, "clipped_surfaces": clipped_tested, "coverage_probes": coverage_tested, "raw_triangulation_failures": raw_failures, "clipped_triangulation_failures": clipped_failures, "coverage_failures": coverage_failures}))
	minimap.free()
	quit(0 if failures == 0 else 1)
