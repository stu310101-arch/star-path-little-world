extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Minimap = preload("res://scripts/world_minimap.gd")
const SakuraRoutes = preload("res://scripts/sakura_routes.gd")
var failures: int = 0
var checks: Array[Dictionary] = []

func check(title: String, passed: bool) -> void:
	checks.append({"name": title, "passed": passed})
	if not passed:
		failures += 1

func contains_anchor(points: PackedVector3Array, expected: Vector3) -> bool:
	for point: Vector3 in points:
		if point.distance_to(expected) < .00001:
			return true
	return false

func _initialize() -> void:
	var minimap: Control = Minimap.new() as Control
	minimap.size = Vector2(224, 180)
	var up: Vector3 = SakuraRoutes.grove_up()
	for radius: float in [48.0, 64.0]:
		minimap.set("radius", radius)
		var patch: Dictionary = minimap.call("build_sakura_patch")
		var paths: Array = patch.paths
		var sources: Array = SakuraRoutes.paths(radius)
		var suffix: String = " radius=" + str(radius)
		check("Map path count matches authored routes" + suffix, paths.size() == sources.size())
		check("Map has the current layout version" + suffix, int(patch.layout_version) == SakuraRoutes.LAYOUT_VERSION)
		check("Map path width matches actual paving" + suffix, is_equal_approx(float(patch.path_width), SakuraRoutes.WIDTH))
		for index: int in range(sources.size()):
			var source: Array = sources[index]
			var rendered: PackedVector3Array = paths[index]
			var all_match: bool = true
			for source_point: Array in source:
				var expected: Vector3 = Geo.surface(up, Vector2(float(source_point[0]), float(source_point[1])), radius).normalized()
				all_match = all_match and contains_anchor(rendered, expected)
			check("Every authored route anchor appears on map " + str(index) + suffix, all_match)
			var should_close: bool = (source[0] as Array) == (source[-1] as Array)
			check("Map preserves route closure " + str(index) + suffix, (rendered[0].distance_to(rendered[-1]) < .00001) == should_close)
		var bridge: PackedVector3Array = minimap.call("sakura_connection")
		var entry: PackedVector3Array = paths[0]
		check("Bridge map starts at actual town landing" + suffix, bridge[0].distance_to(SakuraRoutes.town_endpoint(radius)) < .00001)
		check("Bridge map ends at actual garden entrance" + suffix, bridge[-1].distance_to(SakuraRoutes.bridge_finish()) < .00001)
		check("Bridge and garden map routes meet exactly" + suffix, bridge[-1].distance_to(entry[0]) < .00001)
		check("Garden entry joins closed loop" + suffix, contains_anchor(paths[1], entry[-1]))
		var coast: PackedVector3Array = patch.coast
		var coast_matches: bool = true
		for point: Vector2 in SakuraRoutes.island_outline():
			coast_matches = coast_matches and contains_anchor(coast, Geo.surface(up, point, radius).normalized())
		check("Map coastline follows authored island" + suffix, coast_matches)
	minimap.set("radius", 48.0)
	minimap.call("build_sakura_cartography")
	var actual_platforms: Array = minimap.get("platforms")
	var authored_platforms: Array[PackedVector2Array] = SakuraRoutes.platforms()
	check("Map includes exactly the authored viewing platforms", actual_platforms.size() == authored_platforms.size())
	for index: int in range(authored_platforms.size()):
		var anchors_match: bool = true
		for point: Vector2 in authored_platforms[index]:
			anchors_match = anchors_match and contains_anchor(actual_platforms[index], Geo.surface(up, point, 48.0).normalized())
		check("Viewing platform shape matches authoring " + str(index), anchors_match)
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, 7), Vector2(8, 0), Vector2(-8, 0)]:
			minimap.call("update_map_frame", Geo.surface(up, offset, 48.0).normalized())
			var pieces: Array[PackedVector2Array] = minimap.call("project_polygons", actual_platforms[index])
			var valid: bool = not pieces.is_empty()
			for piece: PackedVector2Array in pieces:
				var indices: PackedInt32Array = minimap.call("triangulate_surface", piece)
				valid = valid and not indices.is_empty()
			check("Viewing platform projects from garden position " + str(index) + " " + str(offset), valid)
	minimap.free()
	print(JSON.stringify({"passed": failures == 0, "failed": failures, "checks": checks}))
	quit(0 if failures == 0 else 1)
