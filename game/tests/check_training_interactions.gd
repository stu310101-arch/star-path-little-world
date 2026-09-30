extends SceneTree

const OUTPUT: String = "res://../deliverables/training-room/"
var room: Node3D
var player: PlanetPlayer
var router: Node
var checks: Array[Dictionary] = []
var failures: int = 0
var captures: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame

func press(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	await tick(2)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	await tick(2)

func vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func approach(target: Dictionary) -> void:
	player.call("place_at", vector(target.get("approach", target.get("position", [0, .08, 0])) as Array), Vector3.FORWARD)
	await tick(16)
	router.call("refresh_nearest")

func image(label: String, yaw: float = NAN, distance: float = 3.2) -> void:
	if not captures:
		return
	if not is_nan(yaw):
		room.set("camera_yaw", yaw)
		room.set("camera_pitch", .12)
		room.set("camera_distance", distance)
	room.call("update_camera", 0.0, true)
	await tick(3)
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	var path: String = ProjectSettings.globalize_path(OUTPUT + label + ".png")
	check("Native capture: " + label, picture.save_png(path) == OK, path)

func run() -> void:
	captures = OS.get_cmdline_user_args().has("--capture")
	root.size = Vector2i(1280, 800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	room = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await tick(20)
	player = room.get("player") as PlanetPlayer
	router = room.get("interactions") as Node
	check("Live room wires the interaction router", router != null)
	if router == null:
		finish()
		return
	var layout: Dictionary = room.get("layout") as Dictionary
	var seats: Array = layout.get("seats", []) as Array
	var books: Array = layout.get("books", []) as Array
	check("All sofa, gaming and reading seats have authored metadata", seats.size() >= 12, seats.size())
	check("Thirteen individually selectable books are available", books.size() == 13, books.size())
	var seats_to_test: Array = [] if OS.get_cmdline_user_args().has("--book-smoke") else seats
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seat="):
			seats_to_test = []
			for candidate: Dictionary in seats:
				if str(candidate.id) == argument.trim_prefix("--seat="):
					seats_to_test.append(candidate)
	for raw: Variant in seats_to_test:
		var seat: Dictionary = raw as Dictionary
		await approach(seat)
		check("Seat can be approached: " + str(seat.id), str((router.get("nearest") as Dictionary).get("id", "")) == str(seat.id), router.get("nearest"))
		var seat_camera_before: Array = [room.get("camera_yaw"), room.get("camera_pitch"), room.get("camera_distance")]
		await press(KEY_E)
		check("E starts sit animation: " + str(seat.id), str(router.get("state")) == "sitting", router.get("state"))
		await tick(68)
		check("Seat finishes in actual rest pose: " + str(seat.id), str(router.get("state")) == "seated" and player.is_resting and not player.locomotion_model.visible)
		check("Seated character stays in planar frame: " + str(seat.id), player.up_direction == Vector3.UP and player.collision_mask == 0)
		var rest_pose: RefCounted = router.get("rest_pose") as RefCounted
		check("Authored sit morph reaches full pose: " + str(seat.id), is_equal_approx(float(rest_pose.get("current_amount")), 1.0))
		var seated_position: Vector3 = player.position
		await press(KEY_W)
		check("Movement does not slide a seated character: " + str(seat.id), player.position.distance_to(seated_position) < .001)
		var camera: Camera3D = room.get("camera") as Camera3D
		var camera_gap: float = camera.global_position.distance_to(player.global_position + Vector3.UP * 1.12)
		check("Seated camera stays outside the character: " + str(seat.id), camera_gap > 1.3, camera_gap)
		if str(seat.id).contains("gaming"):
			var props: Node = room.get("furniture_actions") as Node
			var screen_id: String = "computer_%02d" % int(str(seat.id).get_slice("_", 1))
			var screen: Node3D = (props.get("screens") as Dictionary).get(screen_id) as Node3D
			var screen_before: bool = screen.visible
			await press(KEY_F)
			check("Seated F toggles the matching monitor: " + str(seat.id), screen.visible != screen_before)
			await press(KEY_F)
			check("A second F restores the matching monitor: " + str(seat.id), screen.visible == screen_before)
		await image("interaction-seat-" + str(seat.id))
		if str(seat.id) == "gaming_1":
			await image("interaction-seat-gaming_1-side", float(seat.facing) + PI / 2.0, 2.8)
		if str(seat.id) == "sofa_corner":
			await image("interaction-seat-sofa_corner-side", float(seat.facing) + .60, 3.2)
		await press(KEY_E)
		await tick(64)
		check("E stands safely: " + str(seat.id), str(router.get("state")) == "idle" and not player.is_resting and player.controls_enabled and player.collision_mask == 9 and player.is_on_floor(), player.position)
		check("Standing capsule clears furniture: " + str(seat.id), bool(router.call("_capsule_clear", player.global_position + Vector3.UP * .02)))
		check("Standing restores the exploration camera: " + str(seat.id), seat_camera_before == [room.get("camera_yaw"), room.get("camera_pitch"), room.get("camera_distance")])
	if OS.get_cmdline_user_args().has("--seats-only"):
		finish()
		return
	var bookcase: Dictionary = layout.get("bookcase", {"position": [8.3, .08, 1.95]}) as Dictionary
	await approach(bookcase)
	await press(KEY_E)
	check("Bookshelf E opens selection UI", str(router.get("state")) == "selecting" and (router.get("overlay") as Control).visible)
	check("Selecting books blocks camera and movement", bool(router.call("camera_blocked")) and not player.controls_enabled and player.is_resting)
	await image("interaction-book-selection", -1.4)
	await press(KEY_ESCAPE)
	check("Escape cancels selection and restores movement", str(router.get("state")) == "idle" and player.controls_enabled, {"state": router.get("state"), "controls": player.controls_enabled, "saved_controls": router.get("saved_controls")})
	for raw: Variant in books:
		var book: Dictionary = raw as Dictionary
		await approach(bookcase)
		await press(KEY_E)
		var camera_before: Array = [room.get("camera_yaw"), room.get("camera_pitch"), room.get("camera_distance")]
		if str(book.id) == str((books[0] as Dictionary).id):
			await press(KEY_ENTER)
		else:
			router.call("select_book", str(book.id))
		check("Book enters pickup animation: " + str(book.id), str(router.get("state")) == "taking_book", router.get("state"))
		await tick(50)
		check("Book reaches reading state: " + str(book.id), str(router.get("state")) == "reading")
		var source: Node3D = router.get("selected_shelf_book") as Node3D
		var held: Node3D = router.get("held_book") as Node3D
		check("Only the selected shelf book is picked up: " + str(book.id), source != null and not source.visible and held != null and held.global_position.distance_to(player.global_position) < 1.5)
		check("Book opens and blocks movement: " + str(book.id), is_equal_approx(float(router.get("book_open_amount")), 1.0) and player.is_resting and not player.controls_enabled)
		if str(book.id) == str((books[0] as Dictionary).id):
			await image("interaction-blank-book")
			(router.get("overlay") as Control).visible = false
			await image("interaction-book-held", .25, 2.0)
			(router.get("overlay") as Control).visible = true
		await press(KEY_E)
		await tick(50)
		check("Book returns to its shelf and unlocks player: " + str(book.id), source != null and source.visible and str(router.get("state")) == "idle" and router.get("held_book") == null and player.controls_enabled)
		check("Reading restores the exploration camera: " + str(book.id), camera_before == [room.get("camera_yaw"), room.get("camera_pitch"), room.get("camera_distance")])
		if OS.get_cmdline_user_args().has("--book-smoke"):
			break
	var old_transform: Transform3D = player.global_transform
	router.call("show_inspection", "展示櫃", "六個展示位置，角色模型尚未放入。")
	check("Auxiliary inspection shares the same modal input lock", str(router.get("state")) == "inspection" and bool(router.call("camera_blocked")))
	await press(KEY_ESCAPE)
	check("Inspection closes without moving player", str(router.get("state")) == "idle" and old_transform.origin.distance_to(player.global_position) < .1)
	finish()

func finish() -> void:
	var report: Dictionary = {"checks": checks, "failures": failures, "captures": captures}
	var report_name: String = "interaction-book-checks.json" if OS.get_cmdline_user_args().has("--book-smoke") else "interaction-seat-checks.json" if OS.get_cmdline_user_args().has("--seats-only") else "interaction-checks.json"
	var file: FileAccess = FileAccess.open(OUTPUT + report_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TRAINING_INTERACTION_CHECKS ", JSON.stringify({"count": checks.size(), "failures": failures}))
	quit(1 if failures > 0 else 0)
