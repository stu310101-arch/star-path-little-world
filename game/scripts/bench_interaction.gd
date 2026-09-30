extends Node

# Both individual garden benches and batched civic benches share this authored
# collision proxy. Inspect the proxy as well as metadata: old packed scenes have
# auto-generated names for the second civic bench.
const SEAT_SIZE := Vector3(1.58, .85, .53)
const SEAT_CENTRE := Vector3(0, .48, .04)
const SIT_DURATION: float = 1.05
const STAND_DURATION: float = .90
var world: Node3D
var player: PlanetPlayer
var seats: Array[StaticBody3D] = []
var nearest: StaticBody3D
var active: StaticBody3D
var state: StringName = &"idle"
var clock: float = 0.0
var rest_clock: float = 0.0
var start_position: Vector3
var exit_position: Vector3
var seat_transform: Transform3D
var start_visual_rotation: Quaternion
var saved_mask: int = 9
var pose: RefCounted

func _ready() -> void:
	world = get_parent() as Node3D
	player = world.get("player") as PlanetPlayer
	for node: Node in world.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if is_bench(body):
			seats.append(body)
	print("BENCHES_READY count=", seats.size())

static func is_bench(body: StaticBody3D) -> bool:
	if body.has_meta("rest_seat"):
		return bool(body.get_meta("rest_seat"))
	if body.collision_layer != 8:
		return false
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is BoxShape3D:
			var shape := child as CollisionShape3D
			if (shape.shape as BoxShape3D).size.is_equal_approx(SEAT_SIZE) and shape.position.is_equal_approx(SEAT_CENTRE):
				return true
	return false

func available() -> bool:
	if bool(world.get("overview")) or bool(world.get("paused")) or bool(world.get("entering")):
		return false
	var destinations: Control = world.get("hud").get("destination_card") as Control
	return destinations == null or not destinations.visible

func front_point(seat: StaticBody3D, distance: float = .95) -> Vector3:
	return seat.to_global(Vector3(0, 0, -distance))

func safe_stand(seat: StaticBody3D) -> Dictionary:
	# Prefer the centre of the open front. Other candidates remain in front of
	# the same bench, never behind its back or across a perimeter railing.
	for offset: Vector3 in [Vector3(0,0,-.95), Vector3(-.42,0,-1.08), Vector3(.42,0,-1.08), Vector3(0,0,-1.35)]:
		var raw: Vector3 = seat.to_global(offset)
		var hit: Dictionary = player.ground_at(raw.normalized())
		if hit.is_empty():
			continue
		var point: Vector3 = (hit.position as Vector3) + raw.normalized() * .025
		if absf(point.length() - seat.global_position.length()) > .35:
			continue
		if not capsule_clear(point):
			continue
		var from: Vector3 = seat.to_global(Vector3(0,.85,-.30))
		var to: Vector3 = point + point.normalized() * .85
		var query := PhysicsRayQueryParameters3D.create(from, to, 8)
		query.exclude = [seat.get_rid(), player.get_rid()]
		if player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			return {"point":point}
	return {}

func capsule_clear(point: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(PlanetGeometry.frame(point.normalized()), point + point.normalized() * .84)
	query.collision_mask = 8
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func can_approach(seat: StaticBody3D) -> bool:
	var local: Vector3 = seat.to_local(player.global_position)
	if local.z > -.34 or absf(local.x) > 1.15 or local.length() > 1.85:
		return false
	var target: Dictionary = safe_stand(seat)
	if target.is_empty():
		return false
	# A swept capsule rules out sitting through a fence or adjoining furniture.
	var capsule := CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(player.global_basis, player.global_position + player.up_direction * .84)
	query.motion = (target.point as Vector3) - player.global_position
	query.collision_mask = 8
	query.exclude = [player.get_rid()]
	var motion: PackedFloat32Array = player.get_world_3d().direct_space_state.cast_motion(query)
	return motion.size() == 2 and motion[0] > .99

func refresh_nearest() -> void:
	nearest = null
	if state != &"idle" or not available() or player.needs_settle or player.jump_state != &"grounded":
		return
	var distance: float = 1.85
	for seat: StaticBody3D in seats:
		var candidate: float = seat.global_position.distance_to(player.global_position)
		if candidate < distance and can_approach(seat):
			nearest = seat
			distance = candidate

func interact() -> bool:
	if not available():
		return false
	if state == &"resting":
		var standing_target: Dictionary = safe_stand(active)
		if standing_target.is_empty():
			return false
		exit_position = standing_target.point
		state = &"standing"
		clock = 0.0
		return true
	if state != &"idle":
		return false
	refresh_nearest()
	if nearest == null:
		return false
	var target: Dictionary = safe_stand(nearest)
	if target.is_empty():
		return false
	if pose == null:
		pose = load("res://scripts/bench_pose.gd").new() as RefCounted
		pose.call("configure", player.visual, player.locomotion_model)
	active = nearest
	nearest = null
	seat_transform = active.global_transform.orthonormalized()
	start_position = player.global_position
	exit_position = target.point
	player.reset_jump_motion()
	player.set_clip(&"Idle")
	start_visual_rotation = player.global_basis.get_rotation_quaternion() * player.visual.quaternion
	player.is_resting = true
	player.velocity = Vector3.ZERO
	saved_mask = player.collision_mask
	player.collision_mask = 0
	state = &"sitting"
	clock = 0.0
	rest_clock = 0.0
	pose.call("set_amount", 0.0, 0.0)
	return true

func _physics_process(delta: float) -> void:
	if state == &"idle":
		return
	clock += delta
	rest_clock += delta
	var amount: float = 1.0
	var feet: Vector3 = seat_transform.origin
	if state == &"sitting":
		var progress: float = clampf(clock / SIT_DURATION, 0, 1)
		amount = smoothstep(.12, 1.0, progress)
		feet = start_position.lerp(seat_transform.origin, smoothstep(0, 1, progress))
		if progress >= 1:
			state = &"resting"
	elif state == &"standing":
		var progress: float = clampf(clock / STAND_DURATION, 0, 1)
		amount = 1.0 - smoothstep(0, 1, progress)
		feet = seat_transform.origin.lerp(exit_position, smoothstep(0, 1, progress))
		if progress >= 1:
			player.global_position = exit_position
			cancel()
			player.last_safe_position = exit_position
			player.needs_settle = true
			return
	player.global_transform = Transform3D(seat_transform.basis, feet)
	player.up_direction = feet.normalized()
	player.previous_up = player.up_direction
	# Camera heading remains free while the seated body stays with the bench.
	var facing: Quaternion = seat_transform.basis.get_rotation_quaternion() * Quaternion(Vector3.UP, PI)
	var turn: float = smoothstep(0, .35, clock / SIT_DURATION) if state == &"sitting" else 1.0
	player.visual.quaternion = seat_transform.basis.get_rotation_quaternion().inverse() * start_visual_rotation.slerp(facing, turn)
	pose.call("set_amount", amount, rest_clock)

func cancel() -> void:
	if state == &"idle":
		return
	pose.call("finish")
	player.is_resting = false
	player.collision_mask = saved_mask
	player.velocity = Vector3.ZERO
	player.reset_jump_motion()
	player.active_clip = &""
	player.set_clip(&"Idle")
	# Preserve the actual body facing when rejoining the ordinary camera frame.
	var facing: Vector3 = -seat_transform.basis.z
	var up: Vector3 = player.global_position.normalized()
	player.heading = player.heading.slide(up).normalized()
	player.global_basis = Basis(player.heading.cross(up).normalized(), up, -player.heading)
	var local_facing: Vector3 = player.global_basis.inverse() * facing
	player.visual.rotation = Vector3(0, atan2(local_facing.x, local_facing.z), 0)
	state = &"idle"
	active = null
	nearest = null

func prompt() -> String:
	match state:
		&"sitting": return "正在坐下…"
		&"resting": return "E  起身繼續探索"
		&"standing": return "正在起身…"
	return "E  坐下休息" if nearest != null else ""
