extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")
const OUTPUT: String = "res://../deliverables/training-room/"

# Exercise the real room, input routing, seating animation and controls while
# recording the platform handoff instead of opening an external browser.
class FixtureRoom:
	extends "res://scripts/training_room.gd"
	var launches: Array[Dictionary] = []
	func open_computer_game(game: Dictionary) -> bool:
		if str(interactions.get("state")) != "seated" or (computer_games.call("active_game") as Dictionary) != game:
			return false
		launches.append(game.duplicate(true))
		return true

var room: FixtureRoom
var player: PlanetPlayer
var router: Node
var games: Node
var checks: Array[Dictionary] = []
var failures: int = 0
var captures: bool = false
var screenshots: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label_text: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": label_text, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(label_text + ": " + str(evidence))

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame
		await process_frame

func press(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await tick(2)
	event = InputEventKey.new()
	event.physical_keycode = key
	event.keycode = key
	event.pressed = false
	Input.parse_input_event(event)
	await tick(2)

func click_enter() -> void:
	var button: Button = games.get("enter_button") as Button
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	Input.parse_input_event(event)
	await tick(1)
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = false
	Input.parse_input_event(event)
	await tick(2)

func seat_for(seat_id: String) -> Dictionary:
	for seat: Dictionary in (room.layout.get("seats", []) as Array):
		if str(seat.get("id", "")) == seat_id:
			return seat
	return {}

func approach(seat_id: String) -> void:
	var seat: Dictionary = seat_for(seat_id)
	var at: Array = seat.get("approach", [0, .08, 0]) as Array
	player.call("place_at", Vector3(float(at[0]), float(at[1]), float(at[2])), Vector3.FORWARD)
	await tick(16)
	router.call("refresh_nearest")
	games.call("refresh_ui")
	check("Approach chooses exact chair " + seat_id, str((router.get("nearest") as Dictionary).get("id", "")) == seat_id, router.get("nearest"))

func capture(label_text: String) -> void:
	if not captures:
		return
	await tick(3)
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path(OUTPUT + label_text + ".png")
	check("Screenshot " + label_text, root.get_texture().get_image().save_png(path) == OK, path)
	screenshots.append(path)

func check_ui(label_text: String, has_game: bool) -> void:
	var panel: PanelContainer = games.get("panel") as PanelContainer
	var title: Label = games.get("title") as Label
	var button: Button = games.get("enter_button") as Button
	var hint: Label = games.get("hint") as Label
	var viewport_rect: Rect2 = root.get_visible_rect()
	check(label_text + " panel is visible and within viewport", panel.is_visible_in_tree() and viewport_rect.encloses(panel.get_global_rect()), panel.get_global_rect())
	check(label_text + " title and hint have readable nonzero size", title.size.x > 0 and title.size.y > 0 and hint.size.x > 0 and hint.size.y > 0)
	check(label_text + " enter visibility matches installed game", button.is_visible_in_tree() == has_game)
	if has_game:
		check(label_text + " button is clickable with no text overlap", not button.disabled and button.size.y >= 44 and title.get_global_rect().end.y <= button.get_global_rect().position.y and button.get_global_rect().end.y <= hint.get_global_rect().position.y, button.get_global_rect())
	else:
		check(label_text + " empty computer is clearly labeled", title.text == "尚未安裝遊戲")

func run() -> void:
	captures = OS.get_cmdline_user_args().has("--capture")
	if captures and DisplayServer.get_name() == "headless":
		push_error("Rendered Godot required for --capture")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	root.content_scale_size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	room = FixtureRoom.new()
	root.add_child(room)
	current_scene = room
	check("Room player preparation completes", await StartupFixture.wait_room(room, self))
	await tick(20)
	if captures:
		var detail_deadline: int = Time.get_ticks_msec() + 60000
		while room.detail_state not in ["ready", "error"] and Time.get_ticks_msec() < detail_deadline:
			await process_frame
		check("Authored room details are ready before screenshots", room.detail_state == "ready", room.detail_state)
	player = room.player as PlanetPlayer
	router = room.interactions
	games = room.computer_games
	check("All three authored computers have explicit assignments", (games.get("assignments") as Dictionary).size() == 3)
	check("Exactly first chair installs Go", str((games.call("game_for_seat", "gaming_1") as Dictionary).get("id", "")) == "go" and (games.call("game_for_seat", "gaming_2") as Dictionary).is_empty() and (games.call("game_for_seat", "gaming_3") as Dictionary).is_empty())
	var old_camera: Array = [room.camera_yaw, room.camera_pitch, room.camera_distance]
	await approach("gaming_1")
	check("Nearby computer announces Go before sitting", str(router.call("prompt")).contains("圍棋") and (games.get("labels") as Dictionary)["gaming_1"].visible)
	check("Entry button is hidden before sitting", not (games.get("panel") as Control).visible)
	await press(KEY_F)
	check("F cannot launch while standing", room.launches.is_empty())
	room.camera_yaw = -1.25
	room.camera_pitch = .24
	room.camera_distance = 3.5
	room.update_camera(0, true)
	await capture("computer-go-approach-1280x720")
	old_camera = [room.camera_yaw, room.camera_pitch, room.camera_distance]
	await press(KEY_E)
	check("E begins existing sit animation", str(router.get("state")) == "sitting")
	await press(KEY_F)
	check("F cannot bypass the sit animation", room.launches.is_empty())
	await tick(68)
	check("Go chair finishes seated and locks movement", str(router.get("state")) == "seated" and player.is_resting and not player.controls_enabled)
	for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = viewport_size
		root.content_scale_size = viewport_size
		await tick(4)
		check_ui("Go " + str(viewport_size), true)
		await capture("computer-go-seated-%dx%d" % [viewport_size.x, viewport_size.y])
	await press(KEY_F)
	check("Seated F requests exactly the mapped Go page", room.launches.size() == 1 and str(room.launches[0].get("url", "")) == "games/go/index.html" and bool(games.call("is_open")), room.launches)
	var seated_position: Vector3 = player.position
	await press(KEY_E)
	await press(KEY_W)
	check("Open webpage blocks standing and walking", str(router.get("state")) == "seated" and player.position.distance_to(seated_position) < .001 and bool(router.call("camera_blocked")))
	await press(KEY_ESCAPE)
	check("Escape returns to same seat without standing", not bool(games.call("is_open")) and str(router.get("state")) == "seated" and not player.controls_enabled)
	await press(KEY_ENTER)
	check("Enter launches the same game once", room.launches.size() == 2 and bool(games.call("is_open")), room.launches.size())
	await press(KEY_ESCAPE)
	await click_enter()
	check("Clicking the visible entry button launches", room.launches.size() == 3 and bool(games.call("is_open")), room.launches.size())
	await press(KEY_ESCAPE)
	room.call("_computer_game_error", "測試：無法開啟圍棋")
	check("A failed launch is visible while seated", str(router.call("prompt")) == "測試：無法開啟圍棋", router.call("prompt"))
	router.set("message_clock", 0.0)
	await press(KEY_E)
	await tick(64)
	check("E stands and restores exploration controls", str(router.get("state")) == "idle" and player.controls_enabled and not player.is_resting and player.collision_mask == 9)
	check("Standing restores the original camera", old_camera == [room.camera_yaw, room.camera_pitch, room.camera_distance])
	for seat_id: String in ["gaming_2", "gaming_3"]:
		await approach(seat_id)
		check(seat_id + " announces it has no installed game", str(router.call("prompt")).contains("尚未安裝遊戲"))
		await press(KEY_E)
		await tick(68)
		for viewport_size: Vector2i in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = viewport_size
			root.content_scale_size = viewport_size
			await tick(4)
			check_ui(seat_id + " " + str(viewport_size), false)
			if seat_id == "gaming_2":
				await capture("computer-empty-seated-%dx%d" % [viewport_size.x, viewport_size.y])
		await press(KEY_F)
		await press(KEY_ENTER)
		check(seat_id + " cannot launch another computer's game", room.launches.size() == 3 and not bool(games.call("is_open")))
		await press(KEY_E)
		await tick(64)
		check(seat_id + " stands normally", str(router.get("state")) == "idle" and player.controls_enabled)
	var report: Dictionary = {"checks": checks, "failures": failures, "screenshots": screenshots, "renderer": DisplayServer.get_name(), "launch_boundary": "Native/browser handoff replaced by recording fixture; actual HTML checked separately"}
	var output: FileAccess = FileAccess.open(OUTPUT + "computer-game-checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  "))
	output.close()
	print("TRAINING_COMPUTER_GAME_CHECKS ", JSON.stringify({"count": checks.size(), "failures": failures, "screenshots": screenshots}))
	room.queue_free()
	await tick(3)
	quit(1 if failures else 0)
