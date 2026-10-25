extends SceneTree
## Walk the authored studio continuously with the real character physics.
## Capture mode samples the actual renderer; lens overlap is checked each frame.
const Room = preload("res://scripts/admissions_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const OUTPUT: String = "res://../deliverables/admissions-room/studio-walk/"

class FixtureAccount:
	extends Node
	signal closed
	var last_error: String = ""
	func open_view(_view: String) -> bool:
		return true
	func close_view() -> void:
		closed.emit()

var room: Node3D
var player: CharacterBody3D
var camera: Camera3D
var failures: int = 0
var checks: Array[Dictionary] = []
var images: Array[String] = []
var capture_enabled: bool = false
var frame_count: int = 0
var overlap_count: int = 0
var first_overlap: Dictionary = {}
var travelled: float = 0.0
var last_position: Vector3
var lens_shape: SphereShape3D
var lens_query: PhysicsShapeQueryParameters3D

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":title,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(title + ": " + str(evidence))

func tick() -> void:
	await physics_frame
	await process_frame
	frame_count += 1
	travelled += player.position.distance_to(last_position)
	last_position = player.position
	lens_query.transform = Transform3D(Basis.IDENTITY, camera.global_position)
	var hits: Array[Dictionary] = room.get_world_3d().direct_space_state.intersect_shape(lens_query, 4)
	if not hits.is_empty():
		overlap_count += 1
		if first_overlap.is_empty():
			first_overlap = {"frame":frame_count,"camera":camera.global_position,"player":player.position,"body":str((hits[0].collider as Node).name)}

func capture(label_text: String) -> void:
	if not capture_enabled:
		return
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(OUTPUT + "%04d-%s.png" % [frame_count, label_text])
	check("Save " + label_text, root.get_texture().get_image().save_png(path) == OK)
	images.append(path)

func walk_to(target: Vector3, label_text: String) -> bool:
	player.set("allow_test_input", true)
	var arrived: bool = false
	for frame: int in range(600):
		var remaining: Vector3 = (target - player.position).slide(Vector3.UP)
		if remaining.length() < .23:
			arrived = true
			break
		var direction: Vector3 = remaining.normalized()
		var desired_yaw: float = atan2(-direction.x, -direction.z)
		var yaw: float = lerp_angle(float(room.get("camera_yaw")), desired_yaw, .075)
		room.set("camera_yaw", yaw)
		# Character motion follows the route; the viewing yaw eases independently.
		# This avoids accumulating a stale basis while awaiting captured frames.
		player.set("heading", direction)
		player.set("test_direction", Vector2(0, -1))
		await tick()
		if frame % 30 == 0:
			await capture(label_text + "-walking")
	player.set("test_direction", Vector2.ZERO)
	player.set("allow_test_input", false)
	for frame: int in range(10):
		await tick()
	check("Continuous walk reaches " + label_text, arrived, {"position":player.position,"target":target})
	await capture(label_text + "-arrived")
	return arrived

func station(view: String) -> Dictionary:
	for row: Dictionary in room.get("stations") as Array:
		if str(row.view) == view:
			return row
	return {}

func orbit_station(view: String) -> void:
	var row: Dictionary = station(view)
	var focus: Dictionary = room.call("get_account_focus", view) as Dictionary
	var facing: Vector3 = ((focus.focus_target as Vector3) - player.position).slide(Vector3.UP).normalized()
	var nominal_yaw: float = atan2(-facing.x, -facing.z)
	for yaw_offset: float in [0.0, PI * .5, PI, -PI * .5]:
		for pitch: float in [-.08, .24, .66]:
			for distance: float in [2.2, 3.8, 6.5]:
				room.set("camera_yaw", nominal_yaw + yaw_offset)
				room.set("camera_pitch", pitch)
				room.set("camera_distance", distance)
				room.call("update_camera", 0, true)
				await tick()
	room.set("camera_yaw", nominal_yaw)
	room.set("camera_pitch", .24)
	room.set("camera_distance", 3.8)
	room.call("update_camera", 0, true)
	room.call("refresh_nearest")
	check("Walk selects intended workbench " + view, str((room.get("nearest") as Dictionary).get("view", "")) == view, room.get("nearest"))
	await capture(view + "-gameplay")
	check("Station anchor is within room enclosure " + view, (room.get("room_bounds") as AABB).has_point(row.point as Vector3))

func jump_clearance() -> void:
	var before: int = int(player.get("jump_count"))
	room.set("camera_pitch", .66)
	room.set("camera_distance", 6.5)
	var touch: Node = root.get_node("WebTouch")
	touch.call("_touch", ["action", "jump", true])
	await tick()
	touch.call("_touch", ["action", "jump", false])
	for frame: int in range(150):
		await tick()
		if frame in [12, 24, 36, 60]:
			await capture("jump-clearance")
	check("Actual jump preserves camera and ceiling clearance", int(player.get("jump_count")) == before + 1 and player.is_on_floor())
	room.set("camera_pitch", .24)
	room.set("camera_distance", 3.8)

func run() -> void:
	capture_enabled = OS.get_cmdline_user_args().has("--capture")
	Engine.max_fps = 60
	root.size = Vector2i(1440, 900)
	root.content_scale_size = root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var account: FixtureAccount = FixtureAccount.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	room = Room.new()
	root.add_child(room)
	current_scene = room
	if not await Startup.wait_room(room, self):
		quit(1)
		return
	player = room.get("player") as CharacterBody3D
	camera = room.get("camera") as Camera3D
	last_position = player.position
	lens_shape = SphereShape3D.new()
	lens_shape.radius = .16
	lens_query = PhysicsShapeQueryParameters3D.new()
	lens_query.shape = lens_shape
	lens_query.collision_mask = 257
	lens_query.exclude = [player.get_rid()]
	for frame: int in range(20):
		await tick()
	await capture("entrance")
	# The central route remains traversable; workbench approaches come from the
	# exact exported Blender layout instead of obsolete coordinates in a test.
	var routes: Array[Dictionary] = [
		{"name":"central-entry","point":Vector3(0, .06, 2)},
		{"name":"general","point":station("general").point},
		{"name":"central-return","point":Vector3(0, .06, .5)},
		{"name":"special","point":station("special").point},
		{"name":"central-right","point":Vector3(1.7, .06, .5)},
		{"name":"apcs","point":station("apcs").point},
		{"name":"entry-right","point":Vector3(2.4, .06, 2.8)},
		{"name":"scores","point":station("scores").point},
		{"name":"account","point":station("account").point},
		{"name":"exit-aisle","point":Vector3(0, .06, 4.4)},
		{"name":"exit","point":station("exit").point}
	]
	for row: Dictionary in routes:
		if not await walk_to(row.point as Vector3, str(row.name)):
			break
		if str(row.name) == "central-entry":
			await jump_clearance()
		if str(row.name) in ["general", "special", "apcs", "scores", "account"]:
			await orbit_station(str(row.name))
	check("Camera lens stays outside all geometry throughout walk and orbit", overlap_count == 0, {"overlap_frames":overlap_count,"frames":frame_count,"first":first_overlap})
	check("Review covers physical movement rather than teleport snapshots", travelled > 25.0, travelled)
	var report: Dictionary = {"checks":checks,"failures":failures,"travelled_m":travelled,"frames":frame_count,"overlap_frames":overlap_count,"screenshots":images,"renderer":DisplayServer.get_name()}
	FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ADMISSIONS_STUDIO_WALK ", JSON.stringify({"checks":checks.size(),"failures":failures,"travelled_m":travelled,"frames":frame_count,"overlap_frames":overlap_count}))
	room.queue_free()
	account.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
