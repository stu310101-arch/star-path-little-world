class_name PlanetPlayer
extends CharacterBody3D

@export var planet_radius: float = 36.0
@export var walk_speed: float = 3.8
@export var run_speed: float = 6.4
@export var jump_speed: float = 7.8
@export var gravity_strength: float = 18.0
const JUMP_ANTICIPATION: float = 0.12
const JUMP_START_DURATION: float = 0.24
const JUMP_LAND_DURATION: float = 1.20
const LAND_LOCOMOTION_START: float = 0.28
const LAND_LOCOMOTION_BLEND: float = 0.18
# Sample the authored flip against flight/contact; keep the landing cloth
# running after the body has recovered and can already walk or jump again.
const JUMP_AIR_DURATION: float = 0.72
const JUMP_MODEL: String = "res://assets/character/graduate_jump.glb"
var heading: Vector3 = Vector3.FORWARD
var controls_enabled: bool = true
var is_resting: bool = false
var visual: Node3D
var animator: AnimationPlayer
var locomotion_model: Node3D
var locomotion_animator: AnimationPlayer
var jump_model: Node3D
var jump_animator: AnimationPlayer
var active_clip: StringName = &""
var animation_clock: float = 0.0
var previous_up: Vector3 = Vector3.UP
var test_direction: Vector2 = Vector2.ZERO
var test_running: bool = false
var allow_test_input: bool = false
var land_only: bool = true
var shore_margin: float = 0.34
var last_safe_position: Vector3 = Vector3.ZERO
var needs_settle: bool = true
var entering: bool = false
var entry_materials: Array[StandardMaterial3D] = []
var jump_state: StringName = &"grounded"
var jump_clock: float = 0.0
var jump_count: int = 0
var landing_count: int = 0
var radial_velocity: float = 0.0
var jump_height: float = 0.0
var max_jump_height: float = 0.0
var ground_distance: float = 0.0
var jump_start_radius: float = 0.0
var airborne_clock: float = 0.0
var landing_clock: float = 0.0
var jump_button_held: bool = false
var flip_progress: float = 0.0
var locomotion_skeleton: Skeleton3D
var jump_skeleton: Skeleton3D
var locomotion_rig: Node3D
var jump_rig: Node3D
var recovery_bones: Array[Vector2i] = []
var recovery_clip: StringName = &""
var recovery_clock: float = 0.0

func _ready() -> void:
	collision_layer = 4
	collision_mask = 9
	floor_snap_length = 0.5
	floor_max_angle = deg_to_rad(55.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.015
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.27
	capsule.height = 1.6
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.82
	add_child(collision)
	visual = Node3D.new()
	visual.name = "VisualPivot"
	add_child(visual)
	locomotion_model = (load("res://assets/character/graduate.glb") as PackedScene).instantiate() as Node3D
	visual.add_child(locomotion_model)
	locomotion_animator = locomotion_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	animator = locomotion_animator
	if ResourceLoader.exists(JUMP_MODEL):
		jump_model = (load(JUMP_MODEL) as PackedScene).instantiate() as Node3D
		visual.add_child(jump_model)
		jump_model.visible = false
		jump_animator = jump_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if jump_animator != null:
			jump_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if animator != null:
		animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		set_clip(&"Idle")
	if jump_model != null:
		locomotion_skeleton = find_skeleton(locomotion_model)
		jump_skeleton = find_skeleton(jump_model)
		locomotion_rig = locomotion_model.find_child("GraduateRig", true, false) as Node3D
		jump_rig = jump_model.find_child("GraduateRig", true, false) as Node3D
		if locomotion_skeleton != null and jump_skeleton != null:
			for index: int in range(jump_skeleton.get_bone_count()):
				var source_index: int = locomotion_skeleton.find_bone(jump_skeleton.get_bone_name(index))
				if source_index >= 0:
					recovery_bones.append(Vector2i(index, source_index))
	visual.rotation.y = PI

func find_skeleton(model: Node3D) -> Skeleton3D:
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null

func set_clip(clip: StringName) -> void:
	var use_jump_model: bool = clip in [&"JumpStart", &"JumpAir", &"JumpLand"] and jump_animator != null
	animator = jump_animator if use_jump_model else locomotion_animator
	if animator == null or active_clip == clip:
		return
	var resolved: StringName = &""
	for candidate: StringName in animator.get_animation_list():
		if String(candidate).get_file().to_lower() == String(clip).to_lower():
			resolved = candidate
			break
	if resolved == &"":
		return
	locomotion_model.visible = not use_jump_model
	if jump_model != null:
		jump_model.visible = use_jump_model
	# The imported animation samples bone and cloth tracks with one clock.
	var animated_model: Node3D = jump_model if use_jump_model else locomotion_model
	for node: Node in animated_model.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		for i: int in range(mi.get_blend_shape_count()):
			mi.set_blend_shape_value(i, 0.0)
	var preserve_recovery_phase: bool = active_clip == &"JumpLand" and not use_jump_model and recovery_clip == clip
	active_clip = clip
	animation_clock = recovery_clock if preserve_recovery_phase else 0.0
	animator.play(resolved)
	animator.seek(animation_clock, true)
	if clip == &"JumpLand" or not use_jump_model:
		recovery_clip = &""
		recovery_clock = 0.0

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_released("jump"):
		jump_button_held = false
	elif event.is_action_pressed("jump") and not event.is_echo():
		if not jump_button_held:
			jump_button_held = true
			request_jump()
		get_viewport().set_input_as_handled()

func request_jump() -> bool:
	if is_resting or entering or not (controls_enabled or allow_test_input) or needs_settle or not is_on_floor():
		return false
	if jump_state == &"anticipation" or jump_state == &"airborne":
		return false
	var world: Node = get_parent()
	if world != null and world.has_method("can_player_jump") and not bool(world.call("can_player_jump")):
		return false
	jump_state = &"anticipation"
	jump_clock = 0.0
	jump_height = 0.0
	airborne_clock = 0.0
	flip_progress = 0.0
	set_clip(&"JumpStart")
	return true

func cancel_jump_input() -> void:
	# Cancel a queued takeoff when a menu/view opens. An already airborne body
	# continues its collision-safe descent; a UI transition is never a teleport.
	if jump_state == &"anticipation":
		jump_state = &"grounded"
		jump_clock = 0.0
		set_clip(&"Idle")

func reset_jump_motion() -> void:
	jump_state = &"grounded"
	jump_clock = 0.0
	airborne_clock = 0.0
	landing_clock = 0.0
	radial_velocity = 0.0
	jump_height = 0.0
	ground_distance = 0.0
	jump_start_radius = global_position.length()
	flip_progress = 0.0
	recovery_clip = &""
	recovery_clock = 0.0
	# Deliberately retain the physical key latch and monotonic launch counters.

func _physics_process(delta: float) -> void:
	if entering or is_resting:
		return
	if not Input.is_action_pressed("jump"):
		jump_button_held = false
	if not controls_enabled and not allow_test_input:
		cancel_jump_input()
	var radial: Vector3 = global_position.normalized()
	if radial.length_squared() < 0.5:
		radial = Vector3.UP
	var transport: Quaternion = Quaternion(previous_up, radial)
	heading = (transport * heading).slide(radial).normalized()
	previous_up = radial
	up_direction = radial
	global_basis = Basis(heading.cross(radial).normalized(), radial, -heading)
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
			# Walking off a ledge during anticipation cannot become a midair jump.
			start_falling()
		elif jump_clock >= JUMP_ANTICIPATION:
			jump_state = &"airborne"
			radial_velocity = jump_speed
			jump_start_radius = global_position.length()
			jump_count += 1
			airborne_clock = 0.0
			launched = true
	elif jump_state == &"airborne":
		jump_clock += delta
	elif jump_state == &"landing":
		landing_clock += delta
		if landing_clock >= JUMP_LAND_DURATION:
			jump_state = &"grounded"
	# The ocean core is on another layer and never becomes permission to move.
	# Airborne movement retains the shore boundary, while top-facing solid props
	# can support the capsule just like a timber deck.
	if land_only and wish.length_squared() > 0.001:
		var ahead: Vector3 = (global_position + wish.normalized() * (speed * delta + shore_margin)).normalized()
		if ground_at(ahead).is_empty() and solid_support_at(ahead, global_position.length() + 0.35).is_empty():
			wish = Vector3.ZERO
	var airborne_before: bool = jump_state == &"airborne"
	floor_snap_length = 0.0 if airborne_before else 0.5
	if grounded_before and not airborne_before and wish.length_squared() < 0.001:
		# Reapplying radial gravity on a triangulated slope slowly walks the
		# capsule downhill. A grounded, idle character retains its exact foothold.
		velocity = Vector3.ZERO
		radial_velocity = 0.0
	else:
		if grounded_before and not airborne_before:
			radial_velocity = -0.8
		else:
			radial_velocity -= gravity_strength * delta
		var tangent: Vector3 = wish
		if grounded_before and not airborne_before and wish.length_squared() > 0.001:
			tangent = wish.slide(get_floor_normal()).normalized() * wish.length()
		velocity = tangent * speed + radial * radial_velocity
		move_and_slide()
		if is_on_ceiling() and radial_velocity > 0.0:
			radial_velocity = 0.0
		if is_on_floor() and not launched and radial_velocity <= 0.0:
			needs_settle = false
			radial_velocity = 0.0
			if airborne_before:
				jump_state = &"landing"
				landing_clock = 0.0
				landing_count += 1
				flip_progress = 1.0
		elif not is_on_floor() and not airborne_before:
			start_falling()
	var new_up: Vector3 = global_position.normalized()
	var support: Dictionary = solid_support_at(new_up, global_position.length() + 0.12)
	ground_distance = global_position.length() - (support.position as Vector3).length() if not support.is_empty() else -1.0
	if is_on_floor() and not needs_settle and jump_state != &"airborne":
		if not support.is_empty() or not ground_at(new_up).is_empty():
			# Never record an airborne coordinate as the shoreline recovery point.
			last_safe_position = global_position
	if land_only and ground_at(new_up).is_empty() and support.is_empty():
		if global_position.length() < planet_radius + 0.1 and last_safe_position.length_squared() > 1.0:
			global_position = last_safe_position
			velocity = Vector3.ZERO
			reset_jump_motion()
			needs_settle = true
			new_up = global_position.normalized()
	heading = (Quaternion(radial, new_up) * heading).slide(new_up).normalized()
	previous_up = new_up
	up_direction = new_up
	global_basis = Basis(heading.cross(new_up).normalized(), new_up, -heading)
	var actual_motion: Vector3 = (global_position - old_position).slide(new_up)
	var actual_speed: float = actual_motion.length() / maxf(delta, 0.001)
	if actual_speed > 0.08 and wish.length_squared() > 0.001:
		var local: Vector3 = global_basis.inverse() * actual_motion
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(local.x, local.z), 1.0 - exp(-12.0 * delta))
	if jump_state == &"airborne":
		airborne_clock += delta
		jump_height = maxf(0.0, global_position.length() - jump_start_radius)
		max_jump_height = maxf(max_jump_height, jump_height)
		advance_flip(delta, support)
	else:
		jump_height = 0.0
	update_motion_animation(delta, actual_speed, running)

func start_falling() -> void:
	jump_state = &"airborne"
	# A step off a model is a fall, not a second somersault or an extra launch.
	jump_clock = JUMP_START_DURATION
	airborne_clock = 0.0
	jump_start_radius = global_position.length()
	flip_progress = 1.0

func advance_flip(delta: float, support: Dictionary) -> void:
	if flip_progress >= 1.0 or jump_clock <= JUMP_START_DURATION:
		return
	var remaining_time: float = maxf(JUMP_AIR_DURATION * (1.0 - flip_progress), delta)
	if not support.is_empty():
		var height: float = maxf(0.0, global_position.length() - (support.position as Vector3).length())
		# Solve h + v*t - g*t*t/2 = 0 against the actual prop/deck below.
		# Finish the flip before an elevated landing, never loop the rotation.
		var contact_time: float = (radial_velocity + sqrt(radial_velocity * radial_velocity + 2.0 * gravity_strength * height)) / gravity_strength
		remaining_time = minf(remaining_time, maxf(delta, contact_time - 0.055))
	flip_progress = minf(1.0, flip_progress + (1.0 - flip_progress) * delta / remaining_time)

func update_motion_animation(delta: float, actual_speed: float, running: bool) -> void:
	if jump_state == &"anticipation" or (jump_state == &"airborne" and jump_clock < JUMP_START_DURATION):
		set_clip(&"JumpStart")
	elif jump_state == &"airborne":
		set_clip(&"JumpAir")
	elif jump_state == &"landing":
		set_clip(&"JumpLand")
	else:
		set_clip((&"Run" if running else &"Walk") if actual_speed > 0.08 else &"Idle")
	if animator != null and animator.current_animation != &"":
		var clip: Animation = animator.get_animation(animator.current_animation)
		if active_clip == &"JumpStart":
			animator.seek(minf(jump_clock, clip.length), true)
		elif active_clip == &"JumpAir":
			animator.seek(flip_progress * clip.length, true)
		elif active_clip == &"JumpLand":
			animator.seek(minf(landing_clock, clip.length), true)
			advance_landing_locomotion(delta, actual_speed, running)
		elif active_clip != &"Idle":
			animation_clock += delta * clampf(actual_speed / (3.8 if running else 2.2), 0.0, 2.2)
			animator.seek(fposmod(animation_clock, maxf(clip.length, 0.001)), true)

func advance_landing_locomotion(delta: float, actual_speed: float, running: bool) -> void:
	if landing_clock < LAND_LOCOMOTION_START or locomotion_animator == null or recovery_bones.is_empty():
		return
	var desired: StringName = (&"Run" if running else &"Walk") if actual_speed > 0.08 else &"Idle"
	if desired != recovery_clip:
		for candidate: StringName in locomotion_animator.get_animation_list():
			if String(candidate).get_file().to_lower() == String(desired).to_lower():
				recovery_clip = desired
				recovery_clock = 0.0
				locomotion_animator.play(candidate)
				break
	if recovery_clip != desired:
		return
	var clip: Animation = locomotion_animator.get_animation(locomotion_animator.current_animation)
	if desired != &"Idle":
		recovery_clock = fposmod(recovery_clock + delta * clampf(actual_speed / (3.8 if running else 2.2), 0.0, 2.2), maxf(clip.length, 0.001))
	locomotion_animator.seek(recovery_clock, true)
	var blend: float = smoothstep(LAND_LOCOMOTION_START, LAND_LOCOMOTION_START + LAND_LOCOMOTION_BLEND, landing_clock)
	# Both assets retain the original skeleton/rest pose. Copy only body poses;
	# JumpLand keeps sampling its own garment morphs for the entire settle.
	jump_model.transform = jump_model.transform.interpolate_with(locomotion_model.transform, blend)
	if jump_rig != null and locomotion_rig != null:
		jump_rig.transform = jump_rig.transform.interpolate_with(locomotion_rig.transform, blend)
	for pair: Vector2i in recovery_bones:
		jump_skeleton.set_bone_pose_position(pair.x, jump_skeleton.get_bone_pose_position(pair.x).lerp(locomotion_skeleton.get_bone_pose_position(pair.y), blend))
		jump_skeleton.set_bone_pose_rotation(pair.x, jump_skeleton.get_bone_pose_rotation(pair.x).slerp(locomotion_skeleton.get_bone_pose_rotation(pair.y), blend))
		jump_skeleton.set_bone_pose_scale(pair.x, jump_skeleton.get_bone_pose_scale(pair.x).lerp(locomotion_skeleton.get_bone_pose_scale(pair.y), blend))

func solid_support_at(normal: Vector3, from_radius: float) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal * from_radius, normal * (planet_radius - 0.3), collision_mask)
	query.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or (hit.normal as Vector3).dot(normal) < cos(floor_max_angle):
		return {}
	return hit

func ground_at(normal: Vector3) -> Dictionary:
	return PlanetGeometry.ground_probe(get_world_3d().direct_space_state,normal,planet_radius)

func teleport(normal: Vector3, feet_radius: float) -> void:
	if is_resting:
		get_parent().get("benches").call("cancel")
	global_position = normal.normalized() * feet_radius
	previous_up = normal.normalized()
	heading = -PlanetGeometry.frame(previous_up).z
	global_basis = PlanetGeometry.frame(previous_up)
	up_direction = previous_up
	velocity = Vector3.ZERO
	reset_jump_motion()
	last_safe_position = global_position
	needs_settle = true

func rotate_heading(angle: float) -> void:
	heading = heading.rotated(global_position.normalized(), angle).normalized()

func begin_entry() -> void:
	entering = true
	controls_enabled = false
	velocity = Vector3.ZERO
	reset_jump_motion()
	set_clip(&"JumpDown")
	if entry_materials.is_empty():
		for node: Node in locomotion_model.find_children("*","MeshInstance3D",true,false):
			var mi: MeshInstance3D = node as MeshInstance3D
			for index: int in range(mi.mesh.get_surface_count()):
				var source: StandardMaterial3D = mi.get_active_material(index) as StandardMaterial3D
				if source == null:
					continue
				var mat: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				mat.set_meta("original_transparency",mat.transparency)
				mi.set_surface_override_material(index,mat)
				entry_materials.append(mat)

func sample_entry(progress: float) -> void:
	var t: float = clampf(progress,0.0,1.0)
	visual.position.y = -0.08*sin(t/0.16*PI) if t < 0.16 else sin((t-0.16)/0.84*PI*0.7)*1.5
	var fade: float = smoothstep(0.63,1.0,t)
	for mat: StandardMaterial3D in entry_materials:
		mat.set("transparency",BaseMaterial3D.TRANSPARENCY_ALPHA if fade > 0.001 else int(mat.get_meta("original_transparency")))
		mat.albedo_color.a = 1.0-fade
	if animator != null and active_clip == &"JumpDown":
		animator.seek(minf(t*1.4,animator.get_animation(animator.current_animation).length),true)
	visual.visible = t < 1.0

func finish_entry() -> void:
	entering = false
	visual.position = Vector3.ZERO
	visual.visible = true
	for mat: StandardMaterial3D in entry_materials:
		mat.albedo_color.a = 1.0
		mat.set("transparency",int(mat.get_meta("original_transparency")))
	set_clip(&"Idle")
