extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const Routes = preload("res://scripts/world_routes.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name": title, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		push_error(title + " " + str(detail))

func run() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	world.set_process(false)
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	if player == null:
		check("Actual world initializes its player", false)
		world.free()
		quit(1)
		return
	player.set_physics_process(false)
	var map: Control = (world.get("hud") as CanvasLayer).get("minimap") as Control
	map.set_process(false)
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var layout: Dictionary = world.get("layout") as Dictionary
	var directions: Array[Vector3] = Routes.directions()
	var patches: Array = map.get("patches") as Array
	var geometry: Dictionary = map.call("built_geometry") as Dictionary
	check("Baked footprints belong to the current district plan", str(geometry.get("districts_sha256", "")) == FileAccess.get_sha256("res://data/districts.json"))
	var authoring_radius: float = float(layout.get("authoring_radius",layout.radius))
	check("Baked footprints use the current world layout and authoring radius", str(geometry.get("layout_sha256", "")) == FileAccess.get_sha256("res://data/world_layout.json") and float(geometry.get("radius",0)) == authoring_radius)
	for node_name: String in ["Globe", "Neighborhood", "Stations"]:
		var node: Node3D = world.get_node(node_name) as Node3D
		check("Actual scene shares planet coordinates: " + node_name, node.global_transform.is_equal_approx(Transform3D.IDENTITY), node.global_transform)
	var landmark_rows: Array = map.get("landmarks") as Array
	var buttons: Array = (world.get("hud") as CanvasLayer).get("station_buttons") as Array
	var buildings_checked: int = 0
	var boardwalk_segments: int = 0
	var boardwalk_floor_matches: int = 0
	for index: int in range(data.size()):
		var row: Dictionary = data[index]
		var id: String = str(row.station)
		var station: Node3D = world.get_node("Stations/" + id) as Node3D
		var config: Dictionary = layout.stations[index]
		var marker: Dictionary = landmark_rows[index]
		var label: Label3D = station.get_node("StationLabel") as Label3D
		check("Station IDs agree across plan, scene and marker: " + id, str(config.id) == id and str(station.get_meta("station_id")) == id and str(marker.station_id) == id)
		check("Visible label, destination and minimap number agree: " + id, label.text == "%02d\n%s\n入口" % [index + 1, config.label] and str(station.get_meta("label")) == str(config.label) and str(marker.number) == str(index + 1) and str(marker.label) == str(config.label) and (buttons[index] as Button).text.begins_with("%02d    %s" % [index + 1, config.label]), label.text)
		check("Marker points at the actual global station: " + id, (marker.point as Vector3).distance_to(station.global_position.normalized()) < .000001)
		check("Actual station belongs to the named map region: " + id, str(map.call("station_at", station.global_position.normalized())) == id and str(map.call("location_at", station.global_position.normalized())) == str(row.theme))
		# Exercise the same public action used by the destination button and keys.
		world.call("teleport_to", id)
		map.call("refresh")
		world.call("update_nearest")
		check("Destination action arrives beside its real station: " + id, player.global_position.distance_to(station.global_position) < 3.2 and str(world.get("nearest_id")) == id, player.global_position.distance_to(station.global_position))
		var arrival: Marker3D = station.get_node_or_null("Arrival") as Marker3D
		check("Destination uses its actual authored arrival bay: " + id, arrival != null and player.global_position.distance_to(arrival.global_position) < .001)
		check("Teleport HUD region and centred arrow match destination: " + id, str(map.get("current_location")) == str(row.theme) and (map.call("project_point", player.global_position.normalized()) as Vector2).distance_to(map.size * .5) < .001)
		var source: Node3D = (load("res://generated/districts/" + id + ".tscn") as PackedScene).instantiate() as Node3D
		var patch: Dictionary = patches[index]
		var building_points: Array = patch.buildings
		var foundation_matches: int = 0
		for child: Node in source.get_children():
			var slab: MeshInstance3D = child.get_node_or_null("Foundation") as MeshInstance3D
			if slab == null:
				continue
			var parent: Node3D = child as Node3D
			var transform: Transform3D = source.transform * parent.transform * slab.transform
			var bounds: AABB = slab.mesh.get_aabb()
			var corners_match: bool = true
			for x: float in [bounds.position.x, bounds.end.x]:
				for z: float in [bounds.position.z, bounds.end.z]:
					var actual: Vector3 = (transform * Vector3(x, bounds.end.y, z)).normalized()
					var nearest: float = INF
					for building: Dictionary in building_points:
						for point: Vector3 in building.points:
							nearest = minf(nearest, actual.distance_to(point))
					corners_match = corners_match and nearest < .00001
			if corners_match:
				foundation_matches += 1
		check("Map footprints use every actual foundation corner: " + id, foundation_matches == row.urban_buildings.size(), foundation_matches)
		buildings_checked += foundation_matches
		var expected_wet: int = 0
		var mapped_wet: int = 0
		for path: Array in Routes.district_paths(row, authoring_radius):
			var samples: Array[Dictionary] = Waterfront.samples(directions[index], path, row, authoring_radius)
			for j: int in range(samples.size() - 1):
				if bool(samples[j].wet):
					expected_wet += 1
		for line: PackedVector3Array in patch.boardwalks:
			mapped_wet += line.size() - 1
			for segment: int in range(line.size() - 1):
				var middle: Vector3 = line[segment].slerp(line[segment + 1], .5).normalized()
				if has_timber_floor(world,middle,float(layout.radius)):
					boardwalk_floor_matches += 1
				else:
					print("MAP_SPAN_MISMATCH ",id," normal=",middle)
		check("All real timber spans are marked as bridges: " + id, mapped_wet == expected_wet, {"world_spans": expected_wet, "map_spans": mapped_wet})
		boardwalk_segments += mapped_wet
		if source.has_node("Marina"):
			var marina: Node3D = source.get_node("Marina") as Node3D
			var polygons: Array = marina.get_meta("map_polygons", [])
			var mapped: Array = map.get("platforms") as Array
			var matches: bool = false
			for polygon: PackedVector3Array in polygons:
				for drawn: PackedVector3Array in mapped:
					if polygon.size() != drawn.size():
						continue
					var same: bool = true
					for j: int in range(polygon.size()):
						same = same and polygon[j].distance_to(drawn[j]) < .000001
					matches = matches or same
			check("Marina retains its exact footprint before any detail chunks load", matches and world.find_children("Marina", "Node3D", true, false).is_empty())
		source.free()
	check("Every map timber span lies on a real boardwalk collider in world.tscn", boardwalk_floor_matches == boardwalk_segments and boardwalk_segments > 0, {"mapped": boardwalk_segments, "actual_colliders": boardwalk_floor_matches})
	var output: Dictionary = {"passed": failures == 0, "failed": failures, "buildings_checked": buildings_checked, "boardwalk_segments": boardwalk_segments, "boardwalk_floor_matches": boardwalk_floor_matches, "checks": checks}
	var file: FileAccess = FileAccess.open("res://tests/minimap_world_alignment_results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print(JSON.stringify(output))
	world.free()
	quit(0 if failures == 0 else 1)

func has_timber_floor(world: Node3D, normal: Vector3, radius: float) -> bool:
	# A ray exactly on a float32 triangle edge can pass through the deck and
	# hit the bank below. Confirm nearby real deck faces within 1 mm as well.
	var frame: Basis = Geo.frame(normal)
	for offset: Vector3 in [Vector3.ZERO,frame.x*.001,-frame.x*.001,frame.z*.001,-frame.z*.001]:
		var n: Vector3 = (normal*radius+offset).normalized()
		var hit: Dictionary = Geo.ground_probe(world.get_world_3d().direct_space_state,n,radius)
		if not hit.is_empty() and "TimberBoardwalk" in str((hit.collider as Node).name): return true
	return false
