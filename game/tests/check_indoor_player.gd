extends SceneTree

const IndoorPlayer = preload("res://scripts/indoor_player.gd")
var failures: int = 0
var checks: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String, passed: bool) -> void:
	checks.append({"test":label, "passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func solid(parent: Node3D, at: Vector3, size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 1
	var collider: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	body.position = at

func run_checks() -> void:
	for action: String in ["jump", "move_left", "move_right", "move_forward", "move_back", "run"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var room: Node3D = Node3D.new()
	root.add_child(room)
	current_scene = room
	solid(room, Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	solid(room, Vector3(0, 1.5, -2), Vector3(20, 3, 0.2))
	var player: PlanetPlayer = IndoorPlayer.new() as PlanetPlayer
	room.add_child(player)
	player.call("place_at", Vector3(4, 0.1, 4), Vector3.FORWARD)
	player.allow_test_input = true
	for frame: int in range(30):
		await physics_frame
	check("Planar controller settles away from origin", player.is_on_floor() and absf(player.position.y) < 0.05)
	check("Planar up stays vertical", player.global_basis.y.is_equal_approx(Vector3.UP))
	check("Arrival settles without playing a landing", player.active_clip == &"Idle" and player.landing_count == 0)
	var before: Vector3 = player.position
	player.test_direction = Vector2(0, -1)
	for frame: int in range(30):
		await physics_frame
	player.test_direction = Vector2.ZERO
	check("WASD moves along heading", player.position.z < before.z - 1.5 and absf(player.position.x - before.x) < 0.01)
	var previous_landings: int = player.landing_count
	var accepted: bool = player.request_jump()
	for frame: int in range(145):
		await physics_frame
	check("Authored jump launches and lands once", accepted and player.jump_count == 1 and player.landing_count == previous_landings + 1 and player.is_on_floor())
	check("Jump height uses floor rather than planet radius", player.max_jump_height > 1.4 and player.max_jump_height < 1.9)
	check("Landing returns to ordinary animation", player.active_clip == &"Idle")
	player.test_direction = Vector2(0, -1)
	for frame: int in range(120):
		await physics_frame
	player.test_direction = Vector2.ZERO
	check("Solid wall blocks walking", player.position.z > -1.7 and player.position.z < -1.5)
	player.call("rotate_heading", PI / 2.0)
	before = player.position
	player.test_direction = Vector2(0, -1)
	for frame: int in range(30):
		await physics_frame
	check("Rotated camera heading redirects movement", player.position.x < before.x - 1.5 and absf(player.position.z - before.z) < 0.02)
	player.test_direction = Vector2.ZERO
	player.controls_enabled = false
	player.allow_test_input = false
	for frame: int in range(2):
		await physics_frame
	check("Disabled controls reject jump", not player.request_jump())
	print("INDOOR_PLAYER_CHECKS ", JSON.stringify({"checks":checks, "failures":failures}))
	quit(1 if failures > 0 else 0)
