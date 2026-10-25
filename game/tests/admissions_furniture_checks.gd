extends SceneTree

const Furniture = preload("res://scripts/admissions_furniture_interaction.gd")
const IndoorPlayer = preload("res://scripts/indoor_player.gd")
const CameraRig = preload("res://scripts/admissions_camera_rig.gd")
var checks: int = 0
var failures: int = 0

class Room:
	extends Node3D
	var camera_yaw: float = .7
	var camera_pitch: float = .32
	var camera_distance: float = 4.1
	var camera_rig: Node
	var modal: bool = false
	var opened_view: String = ""
	func _modal_open() -> bool:
		return modal
	func open_station(view: String) -> void:
		opened_view = view
		modal = true

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks += 1
	if not passed:
		failures += 1
	print("FURNITURE_CHECK ", label, " passed=", passed, " evidence=", evidence)

func box(room: Node3D, id: String, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = id
	body.position = at
	body.collision_layer = 1
	body.collision_mask = 4
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	room.add_child(body)
	return body

func run() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "run", "jump", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var room := Room.new()
	root.add_child(room)
	box(room, "Floor", Vector3(0,-.1,0), Vector3(12,.2,12))
	var chair := box(room, "Chair", Vector3(0,.4,0), Vector3(.7,.8,.7))
	var player := IndoorPlayer.new()
	room.add_child(player)
	player.locomotion_model = Node3D.new()
	player.visual.add_child(player.locomotion_model)
	player.enable_render_interpolation()
	player.place_at(Vector3(0,.06,-2.4),Vector3.BACK)
	var camera := Camera3D.new()
	room.add_child(camera)
	room.camera_rig = CameraRig.new()
	room.add_child(room.camera_rig)
	room.camera_rig.configure(room,camera,player,AABB(Vector3(-6,0,-6),Vector3(12,5,12)))
	var seats := Furniture.new()
	room.add_child(seats)
	var layout := {"interactables":[{"id":"desk_seat","kind":"seat","title":"工作椅","seat_point":[0,.555,0],"stand_point":[0,.06,-1],"facing":0.0,"radius":1.0,"collider_id":"Chair","station_view":"general"},{"id":"invalid","kind":"seat","seat_point":[0,0],"stand_point":[0,0,0]}]}
	seats.configure(room,player,layout)
	check("Malformed anchors never become interactions",seats.targets.size()==1)
	await physics_frame
	await physics_frame
	player.allow_test_input = true
	player.test_direction = Vector2(0,-1)
	var start: Vector3 = player.global_position
	for tick: int in range(22):
		await physics_frame
	player.test_direction = Vector2.ZERO
	player.allow_test_input = false
	check("Actual physics walking reaches the chair approach",player.global_position.distance_to(start)>.65 and not seats.nearest_target(player.global_position).is_empty(),player.global_position)
	var target: Dictionary = seats.prefer_target({})
	check("Empty workstation selection can choose a chair",target.get("kind")=="seat")
	var close_station := {"point":player.global_position,"view":"general"}
	check("Chair wins a workstation tie at its exact entry anchor",seats.prefer_target(close_station).get("kind","")=="seat")
	var camera_values := Vector3(room.camera_yaw,room.camera_pitch,room.camera_distance)
	Input.action_press("move_forward")
	check("Shared interaction starts sitting",seats.interact(target))
	check("Seat immediately stops movement and held touch input",player.is_resting and not player.controls_enabled and player.collision_mask==0 and not Input.is_action_pressed("move_forward"))
	await create_timer(1.2).timeout
	check("Delivered seat pose reaches the cushion",seats.is_seated() and player.position.is_equal_approx(Vector3(0,.035,0)) and is_equal_approx(float(seats.rest_pose.get("current_amount")),1.0),player.position)
	var seated_position: Vector3 = player.global_position
	Input.action_press("move_forward")
	await create_timer(.1).timeout
	check("Walking input cannot move a seated character",player.global_position.is_equal_approx(seated_position))
	check("Only active chair proxy is excluded from camera sweep",room.camera_rig._query.exclude.has(chair.get_rid()) and room.camera_rig._query.exclude.size()==2)
	check("Seated workstation action keeps the associated desk",seats.open_workbench() and room.opened_view=="general")
	var clock_before: float = seats.clock
	await create_timer(.1).timeout
	check("Account modal pauses furniture controller",is_equal_approx(clock_before,seats.clock) and not seats.handle_cancel())
	room.modal = false
	var blocker := box(room,"BlockedAisle",Vector3(0,.9,-1.3),Vector3(2,1.8,1.6))
	await physics_frame
	await physics_frame
	check("Blocked exit retains seated pose safely",seats.interact() and seats.is_seated() and seats.status_text().contains("擋住"))
	blocker.queue_free()
	await physics_frame
	await physics_frame
	check("Esc starts standing without leaving room",seats.handle_cancel() and seats.is_transitioning())
	await create_timer(1.0).timeout
	check("Standing restores controls collision and posture",not seats.is_active() and player.controls_enabled and player.collision_mask==9 and not player.is_resting and player.locomotion_model.visible)
	check("Standing restores camera orbit and removes seat exclusion",Vector3(room.camera_yaw,room.camera_pitch,room.camera_distance).is_equal_approx(camera_values) and room.camera_rig._query.exclude.size()==1)
	check("Safe stand uses authored clear aisle",player.position.distance_to(Vector3(0,0,-1))<.1 and seats._capsule_clear(player.position),player.position)
	check("Esc becomes available to room after standing",not seats.handle_cancel())
	player.needs_settle = false
	check("Second sitting reuses the pose",seats.interact(seats.nearest_target(player.position)))
	await create_timer(.15).timeout
	seats.reset()
	check("Room return during sit cleans up controls and pose",not seats.is_active() and player.controls_enabled and not player.is_resting and player.locomotion_model.visible)
	room.queue_free()
	await process_frame
	print("FURNITURE_CHECKS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
