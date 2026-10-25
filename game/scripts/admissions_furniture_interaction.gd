extends Node
## Seat interaction shares the delivered rest pose with the training room.
## Layout anchors, not art mesh bounds, determine entry, posture and safe exit.

const RestPose = preload("res://scripts/bench_pose.gd")
const SIT_SECONDS: float = 1.05
const STAND_SECONDS: float = .9
const CHAIR_SPEED: float = 2.6
const CHAIR_CLEARANCE: float = .02
const DESK_VIEWS: Array[String] = ["general", "special", "apcs", "interest_high1", "interest_high3", "data", "recommendations", "compare"]
var room: Node3D
var player: PlanetPlayer
var targets: Array[Dictionary] = []
var active: Dictionary = {}
var state: StringName = &"idle"
var clock: float = 0.0
var rest_pose: RefCounted
var saved_controls: bool = true
var saved_mask: int = 9
var saved_position: Vector3
var saved_basis: Basis
var saved_visual: Quaternion
var saved_heading: Vector3
var seat_basis: Basis
var seat_feet: Vector3
var exit_position: Vector3
var seat_camera: Dictionary = {}
var message: String = ""
var message_seconds: float = 0.0
var movable_seats: Dictionary = {}

func configure(owner_room: Node3D, actor: CharacterBody3D, metadata: Dictionary) -> void:
	room = owner_room
	player = actor as PlanetPlayer
	targets.clear()
	movable_seats.clear()
	for value: Variant in metadata.get("interactables", []):
		if not value is Dictionary:
			continue
		var target: Dictionary = (value as Dictionary).duplicate(true)
		if str(target.get("kind", "")) != "seat" or str(target.get("id", "")).is_empty():
			continue
		var seat: Vector3 = _vector(target.get("seat_point"))
		var stand: Vector3 = _vector(target.get("stand_point"))
		var facing: float = float(target.get("facing", 0.0))
		var radius: float = float(target.get("radius", 1.05))
		if not seat.is_finite() or not stand.is_finite() or not is_finite(facing) or not is_finite(radius) or radius <= 0:
			continue
		target["point"] = stand
		target["title"] = str(target.get("title", "座椅"))
		target["radius"] = radius
		targets.append(target)

func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)

func is_active() -> bool:
	return state != &"idle"

func is_seated() -> bool:
	return state == &"seated"

func is_transitioning() -> bool:
	return state in [&"sitting", &"standing"]

func capture_fixed_seat() -> Dictionary:
	if not is_seated() or bool(active.get("movable",false)):
		return {}
	return {"id":str(active.id),"stand_point":exit_position,"heading":saved_heading}

func restore_fixed_seat(seat_id: String) -> bool:
	if is_active() or not is_instance_valid(player):
		return false
	for target: Dictionary in targets:
		if str(target.id) != seat_id or bool(target.get("movable",false)):
			continue
		var safe: Dictionary = _safe_stand(target)
		if safe.is_empty():
			return false
		player.call("place_at",safe.point,player.heading)
		active = target.duplicate(true)
		exit_position = safe.point
		_begin_sitting()
		clock = SIT_SECONDS
		_update_seat()
		return true
	return false

func _modal_open() -> bool:
	return is_instance_valid(room) and room.has_method("_modal_open") and bool(room.call("_modal_open"))

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _collider(target: Dictionary) -> CollisionObject3D:
	var id: String = str(target.get("collider_id", ""))
	if id.is_empty():
		return null
	return room.get_node_or_null(NodePath(id.validate_node_name())) as CollisionObject3D

func nearest_target(at: Vector3) -> Dictionary:
	if is_active() or player == null or player.needs_settle or player.jump_state != &"grounded":
		return {}
	var chosen: Dictionary = {}
	var best: float = INF
	for target: Dictionary in targets:
		var stand: Vector3 = target.point as Vector3
		var distance: float = _horizontal_distance(at, stand)
		if distance > float(target.radius) or distance >= best or absf(at.y - stand.y) > .7:
			continue
		var seat: Vector3 = _vector(target.seat_point)
		var entry: Vector3 = (stand - seat).slide(Vector3.UP).normalized()
		if entry.dot((at - seat).slide(Vector3.UP)) < .15:
			continue
		var query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .85, stand + Vector3.UP * .85, saved_mask)
		query.exclude = [player.get_rid()]
		var body: CollisionObject3D = _collider(target)
		if body != null:
			query.exclude.append(body.get_rid())
		if not room.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
			continue
		chosen = target
		best = distance
	return chosen

func prefer_target(station: Dictionary) -> Dictionary:
	if player == null:
		return station
	var seat: Dictionary = nearest_target(player.global_position)
	if seat.is_empty():
		return station
	if station.is_empty() or _horizontal_distance(player.global_position, seat.point as Vector3) <= _horizontal_distance(player.global_position, station.point as Vector3) + .15:
		return seat
	return station

func associated_view() -> String:
	var view: String = str(active.get("station_view", ""))
	return view if is_seated() and view in DESK_VIEWS else ""

func open_workbench() -> bool:
	var view: String = associated_view()
	if view.is_empty() or _modal_open():
		return false
	room.call("open_station", view)
	return true

func status_text() -> String:
	if message_seconds > 0:
		return message
	match state:
		&"sitting": return "正在坐下…"
		&"standing": return "正在起身…"
		&"seated":
			if movable_seats.has(str(active.get("id", ""))):
				return "WASD 慢速移動木椅・E 起身・拖曳環顧"
			return "已坐下・可拖曳環顧四周"
	return ""

func handle_cancel() -> bool:
	if not is_active() or _modal_open():
		return false
	interact()
	return true

func interact(target: Dictionary = {}) -> bool:
	if _modal_open():
		return false
	if is_transitioning():
		return true
	if is_seated():
		var safe: Dictionary = _safe_stand(active)
		if safe.is_empty():
			message = "通道暫時被擋住，請稍後再起身"
			message_seconds = 2.5
			return true
		exit_position = safe.point as Vector3
		state = &"standing"
		clock = 0.0
		_release_inputs()
		return true
	var nearest: Dictionary = nearest_target(player.global_position)
	if nearest.is_empty() or (not target.is_empty() and str(target.get("id", "")) != str(nearest.id)):
		return false
	var safe: Dictionary = _safe_stand(nearest)
	if safe.is_empty():
		message = "請由座椅旁的通道接近"
		message_seconds = 2.5
		return false
	active = nearest.duplicate(true)
	exit_position = safe.point as Vector3
	_begin_sitting()
	return true

func _safe_stand(seat: Dictionary) -> Dictionary:
	var anchor: Vector3 = _vector(seat.stand_point)
	var outward: Vector3 = (anchor - _vector(seat.seat_point)).slide(Vector3.UP).normalized()
	var side: Vector3 = outward.cross(Vector3.UP)
	for offset: Vector3 in [Vector3.ZERO, outward * .3, side * .35, -side * .35, outward * .55]:
		var candidate: Vector3 = anchor + offset
		if _capsule_clear(candidate):
			return {"point":candidate}
	# A moved chair may have its original approach against a wall. The other
	# sides remain valid exits when there is enough standing room and floor.
	if bool(seat.get("movable", false)):
		var center: Vector3 = _vector(seat.seat_point)
		center.y = anchor.y
		for offset: Vector3 in [side * .85, -side * .85, -outward * .95]:
			var candidate: Vector3 = center + offset
			if _capsule_clear(candidate):
				return {"point":candidate}
	return {}

func _capsule_clear(at: Vector3) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = .275
	capsule.height = 1.6
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * .84)
	query.collision_mask = saved_mask
	query.exclude = [player.get_rid()]
	var space: PhysicsDirectSpaceState3D = room.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return false
	var floor_query := PhysicsRayQueryParameters3D.create(at + Vector3.UP * .15, at - Vector3.UP * .3, saved_mask)
	floor_query.exclude = [player.get_rid()]
	var floor_hit: Dictionary = space.intersect_ray(floor_query)
	return not floor_hit.is_empty() and (floor_hit.normal as Vector3).dot(Vector3.UP) > .7

func _begin_sitting() -> void:
	saved_controls = player.controls_enabled
	saved_mask = player.collision_mask
	saved_position = player.global_position
	saved_basis = player.global_basis
	saved_visual = player.visual.quaternion
	saved_heading = player.heading
	player.reset_jump_motion()
	player.set_clip(&"Idle")
	player.is_resting = true
	player.controls_enabled = false
	player.velocity = Vector3.ZERO
	player.collision_mask = 0
	_release_inputs()
	seat_basis = Basis(Vector3.UP, float(active.get("facing", 0)))
	seat_feet = _vector(active.seat_point) - Vector3.UP * .52 + seat_basis.z * float(active.get("pose_forward", 0.0))
	_prepare_movable_seat()
	seat_camera = {"camera_yaw":room.get("camera_yaw"), "camera_pitch":room.get("camera_pitch"), "camera_distance":room.get("camera_distance")}
	room.set("camera_pitch", .26)
	room.set("camera_distance", 3.4)
	var body: CollisionObject3D = _collider(active)
	var exclusions: Array[RID] = []
	if body != null:
		exclusions.append(body.get_rid())
	_set_camera_exclusions(exclusions)
	room.set("camera_yaw", _seat_camera_yaw(float(active.get("facing", 0)) + PI - .45))
	if rest_pose == null:
		rest_pose = RestPose.new() as RefCounted
		rest_pose.call("configure", player.visual, player.locomotion_model)
	state = &"sitting"
	clock = 0.0
	rest_pose.call("set_amount", 0.0)

func _seat_camera_yaw(preferred: float) -> float:
	var rig: Node = room.get("camera_rig") as Node
	if rig == null or not rig.has_method("safe_position"):
		return preferred
	var aim: Vector3 = seat_feet + Vector3.UP * 1.15
	var best_yaw: float = preferred
	var best_distance: float = 0.0
	# Back-wall seats need a side/rear angle rather than a lens pushed into
	# the avatar. Prefer the familiar rear view when it has enough space.
	for offset: float in [0.0, .7, -.7, 1.2, -1.2, 1.65, -1.65]:
		var yaw: float = preferred + offset
		var desired: Vector3 = aim + Vector3(sin(yaw) * cos(.26), sin(.26), cos(yaw) * cos(.26)) * 3.4
		var safe: Vector3 = rig.call("safe_position", aim, desired) as Vector3
		var distance: float = aim.distance_to(safe)
		if distance > best_distance:
			best_distance = distance
			best_yaw = yaw
		if distance >= 3.15:
			return yaw
	return best_yaw

func _set_camera_exclusions(exclusions: Array[RID]) -> void:
	var rig: Node = room.get("camera_rig") as Node
	if rig != null and rig.has_method("set_extra_exclusions"):
		rig.call("set_extra_exclusions", exclusions)

func _prepare_movable_seat() -> void:
	var id: String = str(active.get("id", ""))
	if not bool(active.get("movable", false)) or movable_seats.has(id):
		return
	var body: CollisionObject3D = _collider(active)
	var visual_name: String = str(active.get("visual_node", ""))
	var visual: Node3D = room.find_child(visual_name, true, false) as Node3D if not visual_name.is_empty() else null
	if body == null or visual == null:
		return
	var shapes: Array[CollisionShape3D] = []
	for child: Node in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			shapes.append(child as CollisionShape3D)
	if shapes.is_empty():
		return
	# The exported chair vertices are authored in room space. Preserve both
	# origins rather than snapping the mesh origin onto its collision body.
	movable_seats[id] = {"body":body, "visual":visual, "shapes":shapes,
		"body_transform":body.global_transform, "visual_transform":visual.global_transform,
		"offset":Vector3.ZERO}

func _physics_process(delta: float) -> void:
	if player == null or not is_seated() or _modal_open():
		return
	var id: String = str(active.get("id", ""))
	if not movable_seats.has(id):
		return
	var axis: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
	if axis.is_zero_approx():
		return
	var data: Dictionary = movable_seats[id]
	if not is_instance_valid(data.body) or not is_instance_valid(data.visual):
		return
	var speed: float = float(active.get("movement_speed", CHAIR_SPEED))
	if not is_finite(speed) or speed <= 0:
		speed = CHAIR_SPEED
	speed = minf(speed, player.walk_speed * .9)
	var yaw: float = float(room.get("camera_yaw"))
	var wish: Vector3 = Basis(Vector3.UP, yaw) * Vector3(axis.x, 0, axis.y)
	var motion: Vector3 = wish * speed * delta
	var safe_motion: Vector3 = _chair_safe_motion(data, motion)
	if safe_motion.is_zero_approx():
		return
	_move_chair(data, safe_motion)

func _chair_safe_motion(data: Dictionary, motion: Vector3) -> Vector3:
	var body: CollisionObject3D = data.body as CollisionObject3D
	var excluded: Array[RID] = [player.get_rid(), body.get_rid()]
	var space: PhysicsDirectSpaceState3D = room.get_world_3d().direct_space_state
	var fraction: float = 1.0
	for collision: CollisionShape3D in data.shapes:
		var shape: Shape3D = collision.shape
		var transform: Transform3D = collision.global_transform
		# Lift the bottom of floor-resting boxes a little, keeping their top
		# and horizontal extent. Floor contact must not stop horizontal casts.
		if shape is BoxShape3D:
			var box: BoxShape3D = shape.duplicate() as BoxShape3D
			box.size.y = maxf(.01, box.size.y - CHAIR_CLEARANCE)
			transform.origin.y += CHAIR_CLEARANCE * .5
			shape = box
		fraction = minf(fraction, _sweep_fraction(space, shape, transform, motion, excluded))
	# Keep the seated person's upper body clear as well as the wooden frame.
	var occupant := CapsuleShape3D.new()
	occupant.radius = .3
	occupant.height = 1.6
	var occupant_transform := Transform3D(Basis.IDENTITY, seat_feet + Vector3.UP * .84)
	fraction = minf(fraction, _sweep_fraction(space, occupant, occupant_transform, motion, excluded))
	var safe_motion: Vector3 = motion * fraction
	if safe_motion.is_zero_approx():
		return Vector3.ZERO
	# Each corner must retain floor support; a movable seat cannot cross a
	# doorway ledge or be pushed out of the room even if no wall is present.
	var center: Vector3 = seat_feet + safe_motion
	for corner: Vector3 in [Vector3(-.24, 0, -.25), Vector3(.24, 0, -.25), Vector3(-.24, 0, .25), Vector3(.24, 0, .25)]:
		var point: Vector3 = center + corner
		var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * .2, point - Vector3.UP * .12, saved_mask)
		query.exclude = excluded
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < .9 or absf((hit.position as Vector3).y - (seat_feet.y + .02)) > .06:
			return Vector3.ZERO
	return safe_motion

func _sweep_fraction(space: PhysicsDirectSpaceState3D, shape: Shape3D, transform: Transform3D, motion: Vector3, excluded: Array[RID]) -> float:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = transform
	query.motion = motion
	query.margin = .003
	query.collision_mask = saved_mask
	query.exclude = excluded
	var result: PackedFloat32Array = space.cast_motion(query)
	if result.size() != 2:
		return 0.0
	return clampf(result[0], 0.0, 1.0)

func _move_chair(data: Dictionary, motion: Vector3) -> void:
	data.offset = (data.offset as Vector3) + motion
	var body_transform: Transform3D = data.body_transform as Transform3D
	var visual_transform: Transform3D = data.visual_transform as Transform3D
	body_transform.origin += data.offset as Vector3
	visual_transform.origin += data.offset as Vector3
	(data.body as Node3D).global_transform = body_transform
	(data.visual as Node3D).global_transform = visual_transform
	active.seat_point = _vector(active.seat_point) + motion
	active.stand_point = _vector(active.stand_point) + motion
	active.point = _vector(active.stand_point)
	for target: Dictionary in targets:
		if str(target.id) == str(active.id):
			target.seat_point = active.seat_point
			target.stand_point = active.stand_point
			target.point = active.point
			break
	seat_feet += motion
	exit_position += motion
	player.global_transform = Transform3D(seat_basis, seat_feet)
	player.reset_render_interpolation()

func _process(delta: float) -> void:
	if player == null or _modal_open():
		return
	message_seconds = maxf(0.0, message_seconds - delta)
	if not is_active():
		return
	clock += delta
	_update_seat()

func _update_seat() -> void:
	var amount: float = 1.0
	var point: Vector3 = seat_feet
	if state == &"sitting":
		var progress: float = clampf(clock / SIT_SECONDS, 0, 1)
		amount = smoothstep(.12, 1, progress)
		point = saved_position.lerp(seat_feet, smoothstep(0, 1, progress))
		if progress >= 1:
			state = &"seated"
	elif state == &"standing":
		var progress: float = clampf(clock / STAND_SECONDS, 0, 1)
		amount = 1.0 - smoothstep(0, 1, progress)
		point = seat_feet.lerp(exit_position, smoothstep(0, 1, progress))
		if progress >= 1:
			_finish_standing()
			return
	player.global_transform = Transform3D(seat_basis, point)
	player.reset_render_interpolation()
	player.up_direction = Vector3.UP
	player.previous_up = Vector3.UP
	var turn: float = smoothstep(0, .38, clock / SIT_SECONDS) if state == &"sitting" else 1.0
	var original: Quaternion = saved_basis.get_rotation_quaternion() * saved_visual
	player.visual.quaternion = seat_basis.get_rotation_quaternion().inverse() * original.slerp(seat_basis.get_rotation_quaternion(), turn)
	rest_pose.call("set_amount", amount, clock)

func _finish_standing() -> void:
	if rest_pose != null:
		rest_pose.call("finish")
	for property: String in seat_camera:
		room.set(property, seat_camera[property])
	seat_camera.clear()
	_set_camera_exclusions([])
	player.call("place_at", exit_position, saved_heading)
	var facing: Vector3 = player.global_basis.inverse() * seat_basis.z
	player.visual.rotation = Vector3(0, atan2(facing.x, facing.z), 0)
	player.is_resting = false
	player.controls_enabled = saved_controls
	player.collision_mask = saved_mask
	player.velocity = Vector3.ZERO
	player.reset_jump_motion()
	player.active_clip = &""
	player.set_clip(&"Idle")
	player.needs_settle = true
	player.last_safe_position = player.global_position
	player.reset_render_interpolation()
	_release_inputs()
	state = &"idle"
	active = {}
	message_seconds = 0.0

func _release_inputs() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "jump", "run", "interact"]:
		if InputMap.has_action(action):
			Input.action_release(action)

func reset() -> void:
	if not is_active() or not is_instance_valid(player):
		return
	var safe: Dictionary = _safe_stand(active)
	exit_position = safe.get("point", saved_position) as Vector3
	_finish_standing()

func _exit_tree() -> void:
	if rest_pose != null and is_instance_valid(rest_pose.get("model")) and is_instance_valid(rest_pose.get("walking_model")):
		rest_pose.call("finish")
