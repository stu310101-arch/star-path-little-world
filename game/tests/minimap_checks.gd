extends SceneTree

const Minimap = preload("res://scripts/world_minimap.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Ecology = preload("res://tools/ecology_world.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func check(title: String, passed: bool, detail: String = "") -> void:
	checks.append({"name": title, "passed": passed, "detail": detail})
	if not passed:
		failures += 1

func _initialize() -> void:
	var minimap: Control = Minimap.new() as Control
	minimap.size = Vector2(224, 180)
	var ecology: RefCounted = Ecology.new() as RefCounted
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for index: int in range(districts.size()):
		var district: Dictionary = districts[index]
		var coast: PackedVector2Array = minimap.call("coastline", district, index)
		var contours: Array[PackedVector2Array] = minimap.call("water_contours", district, coast)
		var filled_area: float = 0.0
		var all_inside: bool = true
		for contour: PackedVector2Array in contours:
			for j: int in range(contour.size()):
				filled_area += contour[j].cross(contour[(j + 1) % contour.size()]) * .5
				all_inside = all_inside and float(ecology.call("edge_distance", contour[j], district, index)) > -.12
		check("Water has bounded filled area " + str(index), absf(filled_area) > 10.0)
		check("Water contours stay inside real coast " + str(index), all_inside)
		var samples_match: bool = true
		var wet_samples: int = 0
		for x: int in range(-40, 41, 2):
			for y: int in range(-40, 41, 2):
				var point: Vector2 = Vector2(x, y)
				var water_distance: float = float(ecology.call("water_distance", point, district))
				var edge_distance: float = float(ecology.call("edge_distance", point, district, index))
				if absf(water_distance) < .4 or absf(edge_distance) < .4:
					continue
				var covered: bool = false
				for contour: PackedVector2Array in contours:
					covered = covered or Geometry2D.is_point_in_polygon(point, contour)
				var should_cover: bool = water_distance < 0.0 and edge_distance > 0.0
				if should_cover:
					wet_samples += 1
				samples_match = samples_match and covered == should_cover
		check("Minimap water matches terrain samples " + str(index), samples_match and wet_samples > 3, str(wet_samples))
	# The player's position remains at the centre; turning changes the arrow,
	# never the map reference, including at all six district axes.
	for up: Vector3 in Routes.directions():
		minimap.set("frame_ready", false)
		minimap.call("update_map_frame", up)
		var forward: Vector3 = minimap.get("map_forward") as Vector3
		var right: Vector3 = minimap.get("map_right") as Vector3
		var projected: Vector2 = minimap.call("project_point", up)
		check("Centred at axis " + str(up), projected.distance_to(minimap.size * .5) < .001)
		var directions_correct: bool = true
		for quarter: int in range(4):
			var direction: Vector3 = forward.rotated(up, -float(quarter) * PI * .5)
			var arrow: Vector2 = minimap.call("direction_on_map", direction)
			var expected: Vector2 = Vector2.UP.rotated(float(quarter) * PI * .5)
			directions_correct = directions_correct and arrow.distance_to(expected) < .001
			minimap.call("update_map_frame", up)
		check("Arrow turns through all four bearings " + str(up), directions_correct)
		check("Turning preserves map frame " + str(up), forward.distance_to(minimap.get("map_forward") as Vector3) < .001 and right.distance_to(minimap.get("map_right") as Vector3) < .001)
	minimap.set("frame_ready", false)
	minimap.call("update_map_frame", Vector3.UP)
	var previous_up: Vector3 = Vector3.UP
	var previous_forward: Vector3 = minimap.get("map_forward") as Vector3
	var minimum_dot: float = 1.0
	var tangent_error: float = 0.0
	var arrow_error: float = 0.0
	for step: int in range(1, 721):
		var up: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, TAU * float(step) / 720.0)
		var transported: Vector3 = Quaternion(previous_up, up) * previous_forward
		minimap.call("update_map_frame", up)
		var forward: Vector3 = minimap.get("map_forward") as Vector3
		minimum_dot = minf(minimum_dot, forward.dot(previous_forward))
		tangent_error = maxf(tangent_error, absf(forward.dot(up)))
		var arrow: Vector2 = minimap.call("direction_on_map", transported)
		arrow_error = maxf(arrow_error, arrow.distance_to(Vector2.UP))
		previous_up = up
		previous_forward = forward
	check("Full sphere map transport has no pole flips", minimum_dot > .999)
	check("Transport remains tangent and normalized", tangent_error < .00001 and absf(previous_forward.length() - 1.0) < .00001)
	check("Transported model direction preserves arrow bearing", arrow_error < .001)
	minimap.free()
	print(JSON.stringify({"passed": failures == 0, "failed": failures, "checks": checks}))
	quit(0 if failures == 0 else 1)
