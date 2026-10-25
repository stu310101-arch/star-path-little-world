extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Minimap = preload("res://scripts/world_minimap.gd")
const Streamer = preload("res://scripts/district_streaming.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

class CameraHarness:
	extends "res://scripts/world.gd"
	func _ready() -> void:
		pass
	func _process(_delta: float) -> void:
		pass

func check(title: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": title, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(title + ": " + str(evidence))

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var radius: float = float(layout.radius)
	var world: CameraHarness = CameraHarness.new()
	world.layout = layout
	# The harness skips production _ready(), which normally derives this from
	# the current layout instead of retaining the old 600 m world's distance.
	world.orbit_distance = radius * world.OVERVIEW_DISTANCE
	root.add_child(world)
	world.camera = Camera3D.new()
	world.add_child(world.camera)
	world.camera.fov = 42.0
	world.camera.near = .1
	world.camera.far = 1000.0
	root.size = Vector2i(1280,800)
	await process_frame
	world.update_camera(0.0)
	check("Overview targets the center of the complete globe", world.camera_aim.length() < .01, world.camera_aim)
	check("Overview frames the whole planet at its configured scale", absf(world.camera.global_position.distance_to(world.camera_aim) - radius*world.OVERVIEW_DISTANCE) < .01)
	var directions: Array[Vector3] = []
	for row: Dictionary in layout.stations:
		var normal: Array = row.normal
		directions.append(Vector3(normal[0],normal[1],normal[2]).normalized())
	var all_visible: bool = true
	var viewport: Rect2 = world.get_viewport().get_visible_rect().grow(-12)
	var missed: Array[Vector2] = []
	var map: Control = Minimap.new() as Control
	map.set("radius",radius)
	map.size = Vector2(224,180)
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for index: int in range(directions.size()):
		var up: Vector3 = directions[index]
		var coast: PackedVector2Array = map.call("coastline",districts[index],index)
		for offset: Vector2 in coast:
			var at: Vector3 = Geo.surface(up,offset,radius)
			var projected: Vector2 = world.camera.unproject_position(at)
			var visible_point: bool = not world.camera.is_position_behind(at) and viewport.has_point(projected)
			all_visible = all_visible and visible_point
			if not visible_point:
				missed.append(projected)
	check("Default overview frames the projected bounds of every hemisphere", all_visible,{"viewport":viewport,"missed":missed})
	var minimum_altitude: float = INF
	var minimum_aim_dot: float = 1.0
	for pitch: float in [-10.0,.55,.9,1.35,10.0]:
		for distance: float in [1.0,130.0,290.0,380.0,9000.0]:
			for quarter: int in range(4):
				world.orbit_pitch = pitch
				world.orbit_distance = distance
				world.orbit_yaw = quarter * PI * .5
				world.update_camera(0.0)
				minimum_altitude = minf(minimum_altitude,world.camera.global_position.length()-radius)
				minimum_aim_dot = minf(minimum_aim_dot,(-world.camera.global_basis.z).dot(world.camera.global_position.direction_to(world.camera_aim)))
				if world.orbit_distance < radius*world.OVERVIEW_MIN_DISTANCE or world.orbit_distance > radius*world.OVERVIEW_MAX_DISTANCE:
					minimum_altitude = -INF
	check("Orbit and zoom extremes keep the eye above every island", minimum_altitude > 60, minimum_altitude)
	check("Every orbit orientation looks at the globe center", minimum_aim_dot > .99999, minimum_aim_dot)

	for index: int in range(directions.size()):
		var up: Vector3 = directions[index]
		map.set("frame_ready",false)
		map.call("update_map_frame",up)
		var largest_error: float = 0.0
		for meters: float in [.01,.05,.1,.25,.5,1.0,10.0]:
			var point: Vector3 = Geo.surface(up,Vector2(meters,0),radius).normalized()
			var actual: float = (map.call("project_point",point) as Vector2).distance_to(map.size*.5)
			var expected: float = atan(meters/radius)*radius*float(map.call("map_scale"))
			largest_error = maxf(largest_error,absf(actual-expected))
		check("Sub-meter movement projects without snapping in district " + str(index),largest_error < .003,largest_error)
	map.free()

	var streamer: Node = Streamer.new() as Node
	world.add_child(streamer)
	streamer.set("_world",world)
	streamer.set("_radius",radius)
	streamer.set("_overview",false)
	var regions: Dictionary = {}
	for index: int in range(directions.size()):
		regions[str(index)] = {"center":directions[index]*radius,"chunks":[],"roots":[],"next":0,"wanted":false,"requested":false,"active":false,"outside_since":0.0,"ready":true,"overview":null,"failed":false,"priority":INF}
	streamer.set("_regions",regions)
	for index: int in range(directions.size()):
		var point: Vector3 = directions[index]*radius
		var required: Array = streamer.call("_required_ids",point)
		streamer.call("_refresh_context",point,point+Vector3.UP*5,point)
		var active: Array[String] = []
		for id: String in regions:
			if bool(regions[id].active):
				active.append(id)
		check("District streaming activates only the nearby region " + str(index),required == [str(index)] and active == [str(index)],{"required":required,"active":active})
	streamer.set("_overview",true)
	# Camera altitude is radial. An unnormalized 80 m lateral offset would put
	# this 200 m world's fixture above the intended 70 m close-view threshold.
	var close_eye: Vector3 = Vector3(80, radius + 60, 0).normalized() * (radius + 60)
	streamer.call("_refresh_context",directions[1]*radius,close_eye,directions[0]*radius)
	check("Close overview activates the viewed district instead of the district under its eye",bool(regions["0"].active) and not bool(regions["1"].active))
	world.free()
	var output: Dictionary = {"passed":failures==0,"failed":failures,"checks":checks}
	FileAccess.open("res://tests/archipelago_navigation_results.json",FileAccess.WRITE).store_string(JSON.stringify(output,"\t"))
	print("ARCHIPELAGO_NAVIGATION_CHECKS ",checks.size()," failures=",failures)
	quit(0 if failures==0 else 1)
