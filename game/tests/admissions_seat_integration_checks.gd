extends SceneTree
const Room = preload("res://scripts/admissions_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
var failures: int = 0
var checks: int = 0
var returns: int = 0
var captures: bool = false

class Account:
	extends Node
	signal closed
	var views: Array[String] = []
	var last_error: String = ""
	func open_view(view: String) -> bool:
		views.append(view)
		return true
	func close_view() -> void:
		closed.emit()

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks += 1
	if not passed:
		failures += 1
	print("SEAT_INTEGRATION ",label," passed=",passed," evidence=",evidence)

func tick(count: int) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await tick(2)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await tick(2)

func run() -> void:
	captures = OS.get_cmdline_user_args().has("--capture")
	Engine.max_fps = 60
	root.size = Vector2i(1440,900)
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var room := Room.new()
	root.add_child(room)
	current_scene = room
	room.request_return_to_world.connect(func() -> void: returns += 1)
	check("Production room and avatar finish loading",await Startup.wait_room(room,self))
	if not room.ready_for_play:
		quit(1)
		return
	await tick(10)
	var seats: Node = room.seats
	var player: PlanetPlayer = room.player as PlanetPlayer
	check("Six chairs and two sofa positions are registered",seats.targets.size()==8,seats.targets.size())
	var directory: String = ProjectSettings.globalize_path("res://../deliverables/admissions-room/seats/")
	if captures:
		DirAccess.make_dir_recursive_absolute(directory)
	for index: int in range(seats.targets.size()):
		var seat: Dictionary = seats.targets[index]
		var id: String = str(seat.id)
		var stand: Vector3 = seat.point as Vector3
		var cushion: Vector3 = seats._vector(seat.seat_point)
		var outward: Vector3 = (stand-cushion).slide(Vector3.UP).normalized()
		var start: Vector3 = stand+outward*.45
		check(id+" approach and stand have clear grounded capsules",seats._capsule_clear(start) and seats._capsule_clear(stand),start)
		player.place_at(start,-outward)
		await tick(8)
		player.allow_test_input = true
		player.test_direction = Vector2(0,-1)
		await tick(6)
		player.allow_test_input = false
		player.test_direction = Vector2.ZERO
		await tick(2)
		check(id+" physics walk reaches unified interaction",player.position.distance_to(start)>.25 and str(room.nearest.get("id",""))==id,{"end":player.position,"selected":room.nearest.get("id","")})
		if index % 2 == 0:
			await key(KEY_E)
		else:
			room.action_button.pressed.emit()
		await create_timer(1.2).timeout
		check(id+" keyboard or touch action reaches authored seat",seats.is_seated() and player.is_resting and player.position.distance_to(cushion-Vector3.UP*.52)<.01,player.position)
		if not seats.is_seated():
			continue
		check(id+" seated HUD offers safe stand",not room.action_button.disabled and room.action_button.text.contains("起身") and not room.can_player_jump())
		check(id+" initial seat orbit keeps a useful camera distance",room.camera.global_position.distance_to(player.global_position+Vector3.UP*1.15)>2.5,room.camera.global_position)
		var heading: Vector3 = player.heading
		room.touch_look(Vector2(35,10))
		check(id+" seated touch orbit preserves actor heading",player.heading.is_equal_approx(heading))
		if captures:
			await tick(4)
			await RenderingServer.frame_post_draw
			check(id+" real seat capture",root.get_texture().get_image().save_png(directory+id+".png")==OK)
		if seat.has("station_view"):
			check(id+" associated desk has visible touch target",room.seated_workbench_button.visible)
			if index % 2 == 0:
				await key(KEY_F)
			else:
				room.seated_workbench_button.pressed.emit()
			await create_timer(.5).timeout
			check(id+" workstation opens while actor stays seated",room.account_bridge.is_open() and account.views.back()==str(seat.station_view) and player.is_resting)
			await key(KEY_ESCAPE)
			check(id+" modal returns to seated state",not room.account_bridge.is_open() and seats.is_seated() and not player.controls_enabled and returns==0)
		else:
			check(id+" lounge has no unrelated desk shortcut",not room.seated_workbench_button.visible)
		if index % 2 == 0:
			await key(KEY_ESCAPE)
		else:
			room.action_button.pressed.emit()
		await create_timer(1.0).timeout
		check(id+" Esc or touch stands in safe aisle",not seats.is_active() and player.controls_enabled and not player.is_resting and player.collision_mask==9 and seats._capsule_clear(player.position) and returns==0,player.position)
		await tick(4)
	room.queue_free()
	account.queue_free()
	await process_frame
	print("SEAT_INTEGRATION_CHECKS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
