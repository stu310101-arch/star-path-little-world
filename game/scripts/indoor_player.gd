extends "res://scripts/planet_player.gd"

func _ready() -> void:
	super._ready()
	land_only = false
	up_direction = Vector3.UP
	previous_up = Vector3.UP

func place_at(point: Vector3, facing: Vector3 = Vector3.FORWARD) -> void:
	global_position = point
	heading = facing.slide(Vector3.UP).normalized()
	if heading.length_squared() < 0.5:
		heading = Vector3.FORWARD
	global_basis = Basis(heading.cross(Vector3.UP), Vector3.UP, -heading)
	previous_up = Vector3.UP
	up_direction = Vector3.UP
	velocity = Vector3.ZERO
	reset_jump_motion()
	jump_start_radius = point.y
	needs_settle = true
	last_safe_position = point
	finish_entry()

func rotate_heading(angle: float) -> void:
	heading = heading.rotated(Vector3.UP, angle).normalized()

func _physics_process(delta: float) -> void:
	if entering or is_resting:
		return
	if not Input.is_action_pressed("jump"):
		jump_button_held = false
	if not controls_enabled and not allow_test_input:
		cancel_jump_input()
	up_direction = Vector3.UP
	global_basis = Basis(heading.cross(Vector3.UP), Vector3.UP, -heading)
	var axis: Vector2 = Vector2.ZERO
	var running: bool = false
	if controls_enabled:
		axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		running = Input.is_action_pressed("run")
	if allow_test_input:
		axis = test_direction
		running = test_running
	var wish: Vector3 = global_basis.x * axis.x - heading * axis.y
	var speed: float = run_speed if running else walk_speed
	var old_position: Vector3 = global_position
	var grounded_before: bool = is_on_floor() and not needs_settle
	var launched: bool = false
	if jump_state == &"anticipation":
		jump_clock += delta
		if not grounded_before:
			start_falling()
		elif jump_clock >= JUMP_ANTICIPATION:
			jump_state = &"airborne"
			radial_velocity = jump_speed
			jump_start_radius = global_position.y
			jump_count += 1
			airborne_clock = 0.0
			launched = true
	elif jump_state == &"airborne":
		jump_clock += delta
	elif jump_state == &"landing":
		landing_clock += delta
		if landing_clock >= JUMP_LAND_DURATION:
			jump_state = &"grounded"
	var airborne_before: bool = jump_state == &"airborne"
	floor_snap_length = 0.0 if airborne_before else 0.5
	if grounded_before and not airborne_before:
		radial_velocity = -0.8
	else:
		radial_velocity -= gravity_strength * delta
	velocity = wish * speed + Vector3.UP * radial_velocity
	move_and_slide()
	if is_on_ceiling() and radial_velocity > 0.0:
		radial_velocity = 0.0
	if is_on_floor() and not launched and radial_velocity <= 0.0:
		needs_settle = false
		radial_velocity = 0.0
		last_safe_position = global_position
		if airborne_before:
			jump_state = &"landing"
			landing_clock = 0.0
			landing_count += 1
			flip_progress = 1.0
	elif not is_on_floor() and not airborne_before and not needs_settle:
		start_falling()
	var support: Dictionary = flat_support()
	ground_distance = global_position.y - (support.position as Vector3).y if not support.is_empty() else -1.0
	var actual_motion: Vector3 = (global_position - old_position).slide(Vector3.UP)
	var actual_speed: float = actual_motion.length() / maxf(delta, 0.001)
	if actual_speed > 0.08 and wish.length_squared() > 0.001:
		var local_motion: Vector3 = global_basis.inverse() * actual_motion
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(local_motion.x, local_motion.z), 1.0 - exp(-12.0 * delta))
	if jump_state == &"airborne":
		airborne_clock += delta
		jump_height = maxf(0.0, global_position.y - jump_start_radius)
		max_jump_height = maxf(max_jump_height, jump_height)
		advance_flip(delta, support)
	else:
		jump_height = 0.0
	update_motion_animation(delta, actual_speed, running)
	# Recover only after an actual out-of-bounds fall, never while stepping on
	# furniture or using the authored jump and landing animation.
	if global_position.y < -4.0:
		place_at(last_safe_position + Vector3.UP * 0.1, heading)

func start_falling() -> void:
	super.start_falling()
	jump_start_radius = global_position.y

func flat_support() -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.15, global_position - Vector3.UP * 4.0, collision_mask)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(Vector3.UP) < cos(floor_max_angle):
		return {}
	return hit

func advance_flip(delta: float, support: Dictionary) -> void:
	if flip_progress >= 1.0 or jump_clock <= JUMP_START_DURATION:
		return
	var remaining_time: float = maxf(JUMP_AIR_DURATION * (1.0 - flip_progress), delta)
	if not support.is_empty():
		var height: float = maxf(0.0, global_position.y - (support.position as Vector3).y)
		var contact_time: float = (radial_velocity + sqrt(radial_velocity * radial_velocity + 2.0 * gravity_strength * height)) / gravity_strength
		remaining_time = minf(remaining_time, maxf(delta, contact_time - 0.055))
	flip_progress = minf(1.0, flip_progress + (1.0 - flip_progress) * delta / remaining_time)
