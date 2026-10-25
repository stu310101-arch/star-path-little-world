extends SceneTree

const Room = preload("res://scripts/admissions_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const OUTPUT: String = "res://../deliverables/admissions-room/"

class FixtureAccount:
	extends Node
	signal closed
	var views: Array[String] = []
	var last_error: String = ""
	func open_view(view: String) -> bool:
		views.append(view)
		return true
	func close_view() -> void:
		closed.emit()

var room: Node3D
var account: FixtureAccount
var checks: Array[Dictionary] = []
var failures: int = 0
var returns: int = 0
var screenshots: Array[String] = []
var captures: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(label_text: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label_text, "passed":passed, "evidence":evidence})
	if not passed:
		failures += 1
		push_error(label_text + ": " + str(evidence))

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await tick(2)
	event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await tick(2)

func capture(label_text: String) -> void:
	if not captures:
		return
	await tick(3)
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(OUTPUT + label_text + ".png")
	check("Capture " + label_text, root.get_texture().get_image().save_png(path) == OK)
	screenshots.append(path)

func run() -> void:
	captures = OS.get_cmdline_user_args().has("--capture")
	Engine.max_fps = 60
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	account = FixtureAccount.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	room = Room.new()
	root.add_child(room)
	current_scene = room
	room.connect("request_return_to_world", func() -> void: returns += 1)
	check("The real shared avatar finishes preparation", await Startup.wait_room(room, self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	await tick(20)
	var player: CharacterBody3D = room.get("player") as CharacterBody3D
	var camera: Camera3D = room.get("camera") as Camera3D
	var bridge: Node = room.get("account_bridge") as Node
	check("Avatar stands on collidable floor", player.is_on_floor() and absf(player.position.y) < .15, player.position)
	check("Six distinct destinations exist", (room.get("stations") as Array).size() == 6)
	check("Empty aisle does not activate remote desks", (room.call("nearest_station", Vector3(3.3, .05, 1)) as Dictionary).is_empty())
	var mesh_count: int = 0
	var triangle_count: int = 0
	var art: Node3D = room.get("room_model") as Node3D
	check("Authored studio GLB is loaded", art != null and str(room.get("detail_state")) == "ready")
	for child: Node in art.find_children("*", "MeshInstance3D", true, false):
		if child is MeshInstance3D:
			mesh_count += 1
			var mesh: Mesh = (child as MeshInstance3D).mesh
			for surface: int in range(mesh.get_surface_count()):
				var arrays: Array = mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				triangle_count += (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3 if indices.is_empty() else indices.size() / 3
	check("Authored studio contains visible geometry", mesh_count > 0 and triangle_count > 0, {"meshes":mesh_count,"triangles":triangle_count})
	await capture("entrance")
	# Walk real physics through the aisle; do not teleport this movement check.
	var start: Vector3 = player.position
	player.set("allow_test_input", true)
	player.set("test_direction", Vector2(0, -1))
	await tick(55)
	player.set("allow_test_input", false)
	check("Shared player walks freely down central aisle", player.position.z < start.z - 2.5 and player.is_on_floor(), player.position)
	var touch_router: Node = root.get_node("WebTouch")
	var touch_start: Vector3 = player.position
	touch_router.call("_touch", ["axis", 0.0, -1.0])
	await tick(15)
	touch_router.call("reset_input")
	check("Existing mobile joystick callback moves actual indoor player", player.position.z < touch_start.z - .3, player.position - touch_start)
	await capture("central-aisle")
	for station: Dictionary in room.get("stations") as Array:
		if str(station.view) == "exit":
			continue
		var focus: Dictionary = room.call("get_account_focus", str(station.view)) as Dictionary
		var facing: Vector3 = ((focus.focus_target as Vector3) - (station.point as Vector3)).slide(Vector3.UP).normalized()
		player.call("place_at", station.point as Vector3, facing)
		room.set("camera_yaw", atan2(-facing.x, -facing.z))
		room.call("update_camera", 0.0, true)
		await tick(8)
		room.call("refresh_nearest")
		check("Nearest desk selects " + str(station.view), str((room.get("nearest") as Dictionary).get("view", "")) == str(station.view))
		var before: Transform3D = player.global_transform
		var heading: Vector3 = player.get("heading") as Vector3
		var yaw_before: float = float(room.get("camera_yaw"))
		await capture(str(station.view))
		var previous_launches: int = account.views.size()
		await key(KEY_E)
		var deadline: int = Time.get_ticks_msec() + 5000
		while account.views.size() == previous_launches and Time.get_ticks_msec() < deadline:
			await tick(1)
		check("E launches exact view " + str(station.view), bool(bridge.call("is_open")) and account.views.back() == str(station.view))
		check("Account modal freezes player and hides room HUD", player.process_mode == Node.PROCESS_MODE_DISABLED and not (room.get("hud") as CanvasLayer).visible)
		var camera_before: Transform3D = camera.global_transform
		touch_router.call("_touch", ["look", 100.0, 50.0])
		room.call("update_camera", 1.0)
		check("Mobile look and room camera cannot move behind modal", is_equal_approx(float(room.get("camera_yaw")), yaw_before) and camera.global_transform.is_equal_approx(camera_before))
		await key(KEY_ESCAPE)
		check("Esc restores room without returning outside", not bool(bridge.call("is_open")) and returns == 0)
		check("Closing restores player position and direction", player.global_transform.is_equal_approx(before) and (player.get("heading") as Vector3).is_equal_approx(heading))
		check("Closing restores controls and visible HUD", bool(player.get("controls_enabled")) and (room.get("hud") as CanvasLayer).visible)
	touch_router.call("_touch", ["action", "interact", true])
	var previous_launches: int = account.views.size()
	var deadline: int = Time.get_ticks_msec() + 5000
	while account.views.size() == previous_launches and Time.get_ticks_msec() < deadline:
		await tick(1)
	touch_router.call("_touch", ["action", "interact", false])
	check("Existing mobile action callback opens approached account kiosk", bool(bridge.call("is_open")) and account.views.back() == "account")
	bridge.call("close_view")
	await tick(2)
	check("Metadata generates physical furniture colliders", get_nodes_in_group("admissions_room_collision").size() == (room.get("layout") as Dictionary).colliders.size())
	# UI shape is checked in both portrait and narrow landscape dimensions.
	room.set_meta("force_touch_controls", true)
	for viewport: Vector2i in [Vector2i(390, 844), Vector2i(844, 390)]:
		root.content_scale_size = Vector2i(960, 600)
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		root.size = viewport
		await tick(3)
		var button: Button = room.get("action_button") as Button
		var physical_scale: float = float(viewport.x) / root.get_visible_rect().size.x
		var ui: Control = room.get("ui_root") as Control
		check("Touch action stays inside " + str(viewport), root.get_visible_rect().encloses(button.get_global_rect()) and button.size.y * ui.scale.y * physical_scale >= 44, button.get_global_rect())
		check("Mobile HUD stays at physical CSS size " + str(viewport), is_equal_approx(ui.scale.x * physical_scale, 1.0), ui.scale.x * physical_scale)
		check("Touch mode uses tap wording instead of keyboard hint", not button.text.contains("E ·"), button.text)
		await capture("mobile-%dx%d" % [viewport.x, viewport.y])
	root.size = Vector2i(1440, 900)
	root.content_scale_size = Vector2i(1440, 900)
	player.call("place_at", Room.EXIT, Vector3.BACK)
	await tick(4)
	await key(KEY_E)
	check("Entrance exit emits transition once", returns == 1 and bool(room.get("returning")))
	var report: Dictionary = {"checks":checks, "failures":failures, "screenshots":screenshots, "renderer":DisplayServer.get_name(), "art":{"meshes":mesh_count,"triangles":triangle_count}, "auth_boundary":"Real room + bridge; account transport fixture prevents live login/network."}
	FileAccess.open(OUTPUT + "checks.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("ADMISSIONS_ROOM_CHECKS ", JSON.stringify({"count":checks.size(), "failures":failures, "art":report.art}))
	room.queue_free()
	account.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
