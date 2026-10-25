class_name PlanetPlayer
extends CharacterBody3D

@export var planet_radius: float = 36.0
@export var walk_speed: float = 3.8
@export var run_speed: float = 6.4
@export var jump_speed: float = 7.8
@export var gravity_strength: float = 18.0
@export_range(0.1, 2.0, 0.01) var avatar_scale: float = 1.0
# Optional animation matching for test variants. The game retains its authored
# Walk/Run selection and playback limits at the original movement speeds.
@export var speed_matched_locomotion: bool = false
const WALK_CYCLE_SPEED: float = 2.2
const RUN_CYCLE_SPEED: float = 3.8
const RUN_ENTER_SPEED: float = 4.4
const RUN_EXIT_SPEED: float = 3.8
const JUMP_ANTICIPATION: float = 0.12
const JUMP_START_DURATION: float = 0.24
const JUMP_LAND_DURATION: float = 1.20
const LAND_LOCOMOTION_START: float = 0.28
const LAND_LOCOMOTION_BLEND: float = 0.18
# Sample the authored flip against flight/contact; keep the landing cloth
# running after the body has recovered and can already walk or jump again.
const JUMP_AIR_DURATION: float = 0.72
# Export copies retain the skeleton/topology and bounded cloth interpolation.
# Both remain prepared: landing samples both rigs, and loading on jump hitches.
const WALK_MODEL: String = "res://assets/character/runtime/graduate.glb"
const JUMP_MODEL: String = "res://assets/character/runtime/graduate_jump.glb"
const WEB_WALK_MODEL: String = "res://assets/character/runtime_web/graduate.glb"
const WEB_JUMP_MODEL: String = "res://assets/character/runtime_web/graduate_jump.glb"
const MOBILE_WALK_MODEL: String = "res://assets/character/runtime_mobile/graduate.glb"
const MOBILE_JUMP_MODEL: String = "res://assets/character/runtime_mobile/graduate_jump.glb"
const GraphicsProfile = preload("res://scripts/graphics_settings.gd")
# Same material values, skin and animation times; Web batches synchronized cloth
# poses into fewer surfaces. Native retains its existing resource path.
var _walk_model_path: String = MOBILE_WALK_MODEL if GraphicsProfile.is_mobile_web() or GraphicsProfile.uses_low_resources() else WEB_WALK_MODEL if OS.has_feature("web") else WALK_MODEL
var _jump_model_path: String = MOBILE_JUMP_MODEL if GraphicsProfile.is_mobile_web() or GraphicsProfile.uses_low_resources() else WEB_JUMP_MODEL if OS.has_feature("web") else JUMP_MODEL
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
var _locomotion_meshes: Array[MeshInstance3D] = []
var _jump_meshes: Array[MeshInstance3D] = []
var _locomotion_clips: Dictionary = {}
var _jump_clips: Dictionary = {}
# The world drives one preparation step per frame after presenting its overview.
# No GLB is touched by _ready(), including in exported Web packs.
var _visual_stage: int = 0
var _visual_error: String = ""
var _visual_packed: PackedScene
var _visual_operation_usec: int = 0
var _visual_max_operation_usec: int = 0
# Physics advances every clock; only the latest pose is needed for each draw.
var _animation_pose_pending: bool = false
var _animation_reset_pending: bool = false
var _animation_sample_time: float = 0.0
var animation_physics_updates: int = 0
var animation_pose_samples: int = 0
var animation_seek_calls: int = 0
# Follow-camera scenes opt in. Collision stays on the physics tick while
# this top-level pivot and the follow camera share the same displayed pose.
var render_motion: Node3D
var _render_previous: Transform3D = Transform3D.IDENTITY

func _ready() -> void:
	# Keep CharacterBody3D and its basis at unit scale. Scale the primitive
	# dimensions and visual subtree instead; interiors retain the default 1.
	avatar_scale = clampf(avatar_scale, 0.1, 2.0)
	jump_speed *= avatar_scale
	gravity_strength *= avatar_scale
	shore_margin *= avatar_scale
	collision_layer = 4
	collision_mask = 9
	floor_snap_length = 0.5 * avatar_scale
	floor_max_angle = deg_to_rad(55.0)
	floor_stop_on_slope = true
	floor_constant_speed = true
	safe_margin = 0.015 * avatar_scale
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = 0.27 * avatar_scale
	capsule.height = 1.6 * avatar_scale
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = capsule
	collision.position.y = 0.82 * avatar_scale
	add_child(collision)
	visual = Node3D.new()
	visual.name = "VisualPivot"
	add_child(visual)
	visual.rotation.y = PI
	visual.scale = Vector3.ONE * avatar_scale

func _process(_delta: float) -> void:
	if render_motion != null:
		render_motion.global_transform = get_render_transform()
	sample_motion_animation()

func enable_render_interpolation() -> void:
	if render_motion != null:
		return
	render_motion = Node3D.new()
	render_motion.name = "RenderMotion"
	render_motion.top_level = true
	add_child(render_motion)
	visual.reparent(render_motion, false)
	reset_render_interpolation()

func get_render_transform() -> Transform3D:
	if render_motion == null:
		return global_transform
	return _render_previous.interpolate_with(global_transform, Engine.get_physics_interpolation_fraction())

func get_render_heading(render_up: Vector3) -> Vector3:
	# The seated camera can orbit independently of the bench's body basis.
	# Transport its current heading to the displayed surface normal; dragging
	# stays immediate without mixing a physics position and rendered position.
	return (Quaternion(global_position.normalized(), render_up) * heading).slide(render_up).normalized()

func reset_render_interpolation() -> void:
	_render_previous = global_transform
	if render_motion != null and render_motion.is_inside_tree():
		render_motion.global_transform = global_transform

func begin_prepare_visuals() -> void:
	if _visual_stage != 0 or not _visual_error.is_empty():
		return
	_visual_stage = 1
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("request_resource", _walk_model_path, 20)
		packs.call("request_resource", _jump_model_path, 20)

func visuals_ready() -> bool:
	return _visual_stage == 6

func visuals_error() -> String:
	return _visual_error

func get_visual_preparation_state() -> Dictionary:
	return {"stage": _visual_stage, "ready": visuals_ready(), "error": _visual_error,
		"avatar_scale": avatar_scale,
		"mobile_skeletal_avatar": _walk_model_path == MOBILE_WALK_MODEL,
		"last_operation_ms": float(_visual_operation_usec) / 1000.0,
		"max_operation_ms": float(_visual_max_operation_usec) / 1000.0}

func step_prepare_visuals() -> void:
	if _visual_stage == 0 or visuals_ready() or not _visual_error.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	match _visual_stage:
		1, 3:
			var resource_path: String = _walk_model_path if _visual_stage == 1 else _jump_model_path
			var packs: Node = get_node_or_null("/root/WebPacks")
			if packs != null:
				var pack_error: String = str(packs.call("resource_error", resource_path))
				if not pack_error.is_empty():
					_visual_error = pack_error
					return
				if not bool(packs.call("is_resource_ready", resource_path)):
					return
			# load and instantiate have separate frame budgets. No threaded Web
			# feature is required, and neither operation retries every frame.
			_visual_packed = load(resource_path) as PackedScene
			if _visual_packed == null:
				_visual_error = "Unable to load avatar: " + resource_path
				return
			_visual_stage += 1
		2:
			locomotion_model = _visual_packed.instantiate() as Node3D
			_visual_packed = null
			if locomotion_model == null:
				_visual_error = "Unable to instantiate walking avatar"
				return
			visual.add_child(locomotion_model)
			locomotion_animator = locomotion_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if locomotion_animator != null:
				locomotion_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_cache_animation_parts(locomotion_model, locomotion_animator, _locomotion_meshes, _locomotion_clips)
			set_clip(&"Idle")
			_visual_stage = 3
		4:
			jump_model = _visual_packed.instantiate() as Node3D
			_visual_packed = null
			if jump_model == null:
				_visual_error = "Unable to instantiate jumping avatar"
				return
			visual.add_child(jump_model)
			jump_model.visible = false
			jump_animator = jump_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
			if jump_animator != null:
				jump_animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
			_cache_animation_parts(jump_model, jump_animator, _jump_meshes, _jump_clips)
			_visual_stage = 5
		5:
			locomotion_skeleton = find_skeleton(locomotion_model)
			jump_skeleton = find_skeleton(jump_model)
			locomotion_rig = locomotion_model.find_child("GraduateRig", true, false) as Node3D
			jump_rig = jump_model.find_child("GraduateRig", true, false) as Node3D
			if locomotion_skeleton != null and jump_skeleton != null:
				for index: int in range(jump_skeleton.get_bone_count()):
					var source_index: int = locomotion_skeleton.find_bone(jump_skeleton.get_bone_name(index))
					if source_index >= 0:
						recovery_bones.append(Vector2i(index, source_index))
			_visual_stage = 6
	_visual_operation_usec = Time.get_ticks_usec() - started
	_visual_max_operation_usec = maxi(_visual_max_operation_usec, _visual_operation_usec)

func retry_prepare_visuals() -> void:
	# A retry resumes the failed stage, retaining already prepared models.
	_visual_error = ""
	if _visual_stage in [2, 4] and _visual_packed == null:
		_visual_stage -= 1
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("request_resource", _walk_model_path, 20)
		packs.call("request_resource", _jump_model_path, 20)
	if _visual_stage == 0:
		begin_prepare_visuals()

func find_skeleton(model: Node3D) -> Skeleton3D:
	for node: Node in model.find_children("*", "Skeleton3D", true, false):
		return node as Skeleton3D
	return null

func _cache_animation_parts(model: Node3D, animation_player: AnimationPlayer, meshes: Array[MeshInstance3D], clips: Dictionary) -> void:
	meshes.clear()
	clips.clear()
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance.get_blend_shape_count() > 0:
			meshes.append(mesh_instance)
	if animation_player != null:
		for candidate: StringName in animation_player.get_animation_list():
			clips[String(candidate).get_file().to_lower()] = candidate

func set_clip(clip: StringName) -> void:
	var use_jump_model: bool = clip in [&"JumpStart", &"JumpAir", &"JumpLand"] and jump_animator != null
	animator = jump_animator if use_jump_model else locomotion_animator
	if animator == null or active_clip == clip:
		return
	var clips: Dictionary = _jump_clips if use_jump_model else _locomotion_clips
	var resolved: StringName = clips.get(String(clip).to_lower(), &"") as StringName
	if resolved == &"":
		return
	locomotion_model.visible = not use_jump_model
	if jump_model != null:
		jump_model.visible = use_jump_model
	var preserve_recovery_phase: bool = active_clip == &"JumpLand" and not use_jump_model and recovery_clip == clip
	var next_clock: float = recovery_clock if preserve_recovery_phase else 0.0
	if speed_matched_locomotion and active_clip in [&"Walk", &"Run"] and clip in [&"Walk", &"Run"]:
		# Both loops begin on left contact. Keep that phase when the analog
		# stick crosses the gait threshold instead of restarting every stride.
		var previous_length: float = maxf(animator.get_animation(animator.current_animation).length, 0.001)
		next_clock = fposmod(animation_clock, previous_length) / previous_length * animator.get_animation(resolved).length
	active_clip = clip
	animation_clock = next_clock
	animator.play(resolved)
	_animation_reset_pending = true
	_queue_animation_pose(animation_clock)
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
	if not visuals_ready() or is_resting or entering or not (controls_enabled or allow_test_input) or needs_settle or not is_on_floor():
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
	# Discard a queued airborne/landing pose on teleport, rest, or entry reset.
	_animation_pose_pending = false
	animation_clock = 0.0
	set_clip(&"Idle")
	if animator != null:
		# Repeated resets may find Idle already selected but not yet sampled.
		_animation_reset_pending = true
		_queue_animation_pose(0.0)
	# Deliberately retain the physical key latch and monotonic launch counters.

func _physics_process(delta: float) -> void:
	_render_previous = global_transform
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
		# The browser joystick applies its radial deadzone before the bridge.
		axis = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.0)
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
		if ground_at(ahead).is_empty() and solid_support_at(ahead, global_position.length() + 0.35 * avatar_scale).is_empty():
			wish = Vector3.ZERO
	var airborne_before: bool = jump_state == &"airborne"
	floor_snap_length = 0.0 if airborne_before else 0.5 * avatar_scale
	if grounded_before and not airborne_before and wish.length_squared() < 0.001:
		# Reapplying radial gravity on a triangulated slope slowly walks the
		# capsule downhill. A grounded, idle character retains its exact foothold.
		velocity = Vector3.ZERO
		radial_velocity = 0.0
	else:
		if grounded_before and not airborne_before:
			radial_velocity = -0.8 * avatar_scale
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
	var recovered: bool = false
	var support: Dictionary = solid_support_at(new_up, global_position.length() + 0.12 * avatar_scale)
	ground_distance = global_position.length() - (support.position as Vector3).length() if not support.is_empty() else -1.0
	if is_on_floor() and not needs_settle and jump_state != &"airborne":
		if not support.is_empty() or not ground_at(new_up).is_empty():
			# Never record an airborne coordinate as the shoreline recovery point.
			last_safe_position = global_position
	if land_only and ground_at(new_up).is_empty() and support.is_empty():
		if global_position.length() < planet_radius + 0.1 * avatar_scale and last_safe_position.length_squared() > 1.0:
			global_position = last_safe_position
			velocity = Vector3.ZERO
			reset_jump_motion()
			needs_settle = true
			recovered = true
			new_up = global_position.normalized()
	heading = (Quaternion(radial, new_up) * heading).slide(new_up).normalized()
	previous_up = new_up
	up_direction = new_up
	global_basis = Basis(heading.cross(new_up).normalized(), new_up, -heading)
	if recovered:
		reset_render_interpolation()
	var actual_motion: Vector3 = (global_position - old_position).slide(new_up)
	var actual_speed: float = actual_motion.length() / maxf(delta, 0.001)
	if actual_speed > 0.08 * avatar_scale and wish.length_squared() > 0.001:
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

func _locomotion_clip(actual_speed: float, running: bool, previous_clip: StringName) -> StringName:
	if actual_speed <= 0.08 * avatar_scale:
		return &"Idle"
	if not speed_matched_locomotion:
		return &"Run" if running else &"Walk"
	# A small hysteresis band prevents collision/joystick noise from switching
	# clips on every tick. Low analog input still uses a proportional walk.
	var threshold: float = (RUN_EXIT_SPEED if previous_clip == &"Run" else RUN_ENTER_SPEED) * avatar_scale
	return &"Run" if actual_speed >= threshold else &"Walk"

func _locomotion_rate(actual_speed: float, clip: StringName) -> float:
	if clip == &"Idle":
		return 0.0
	var rate: float = maxf(actual_speed, 0.0) / ((RUN_CYCLE_SPEED if clip == &"Run" else WALK_CYCLE_SPEED) * avatar_scale)
	# The fast outdoor profile must follow travelled meters even above 2.2x;
	# capping it leaves planted feet sliding while the body keeps accelerating.
	return rate if speed_matched_locomotion else minf(rate, 2.2)

func update_motion_animation(delta: float, actual_speed: float, running: bool) -> void:
	# Do not skip physics deltas when several ticks precede a rendered frame.
	# Updating tracks here would resample the same mesh multiple times per draw.
	animation_physics_updates += 1
	if jump_state == &"anticipation" or (jump_state == &"airborne" and jump_clock < JUMP_START_DURATION):
		set_clip(&"JumpStart")
	elif jump_state == &"airborne":
		set_clip(&"JumpAir")
	elif jump_state == &"landing":
		set_clip(&"JumpLand")
	else:
		var previous_gait: StringName = recovery_clip if active_clip == &"JumpLand" else active_clip
		set_clip(_locomotion_clip(actual_speed, running, previous_gait))
	if animator != null and animator.current_animation != &"":
		var clip: Animation = animator.get_animation(animator.current_animation)
		if active_clip == &"JumpStart":
			_queue_animation_pose(minf(jump_clock, clip.length))
		elif active_clip == &"JumpAir":
			_queue_animation_pose(flip_progress * clip.length)
		elif active_clip == &"JumpLand":
			_queue_animation_pose(minf(landing_clock, clip.length))
			advance_landing_locomotion(delta, actual_speed, running)
		elif active_clip != &"Idle":
			animation_clock += delta * _locomotion_rate(actual_speed, active_clip)
			_queue_animation_pose(fposmod(animation_clock, maxf(clip.length, 0.001)))

func _queue_animation_pose(sample_time: float) -> void:
	_animation_sample_time = sample_time
	_animation_pose_pending = true

func sample_motion_animation() -> void:
	# Also callable by pose-inspection fixtures whose node processing is disabled.
	# Clip changes and physics ticks overwrite the pending time until this pass.
	if not _animation_pose_pending or animator == null or animator.current_animation == &"":
		return
	_animation_pose_pending = false
	if _animation_reset_pending:
		var animated_meshes: Array[MeshInstance3D] = _jump_meshes if animator == jump_animator else _locomotion_meshes
		for mi: MeshInstance3D in animated_meshes:
			for index: int in range(mi.get_blend_shape_count()):
				mi.set_blend_shape_value(index, 0.0)
		_animation_reset_pending = false
	# Bone and authored cloth tracks still use exactly the same sampled time.
	_seek_animation_pose(animator, _animation_sample_time)
	if active_clip == &"JumpLand":
		_sample_landing_locomotion()
	animation_pose_samples += 1

func _seek_animation_pose(animation_player: AnimationPlayer, sample_time: float) -> void:
	animation_player.seek(sample_time, true)
	animation_seek_calls += 1

func advance_landing_locomotion(delta: float, actual_speed: float, running: bool) -> void:
	if landing_clock < LAND_LOCOMOTION_START or locomotion_animator == null or recovery_bones.is_empty():
		return
	var desired: StringName = _locomotion_clip(actual_speed, running, recovery_clip)
	if desired != recovery_clip:
		for candidate: StringName in locomotion_animator.get_animation_list():
			if String(candidate).get_file().to_lower() == String(desired).to_lower():
				var next_clock: float = 0.0
				if speed_matched_locomotion and recovery_clip in [&"Walk", &"Run"] and desired in [&"Walk", &"Run"]:
					var previous_length: float = maxf(locomotion_animator.get_animation(locomotion_animator.current_animation).length, 0.001)
					next_clock = fposmod(recovery_clock, previous_length) / previous_length * locomotion_animator.get_animation(candidate).length
				recovery_clip = desired
				recovery_clock = next_clock
				locomotion_animator.play(candidate)
				break
	if recovery_clip != desired:
		return
	var clip: Animation = locomotion_animator.get_animation(locomotion_animator.current_animation)
	if desired != &"Idle":
		recovery_clock = fposmod(recovery_clock + delta * _locomotion_rate(actual_speed, desired), maxf(clip.length, 0.001))

func _sample_landing_locomotion() -> void:
	if landing_clock < LAND_LOCOMOTION_START or locomotion_animator == null or recovery_bones.is_empty() or recovery_clip == &"":
		return
	_seek_animation_pose(locomotion_animator, recovery_clock)
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
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal * from_radius, normal * (planet_radius - 0.3 * avatar_scale), collision_mask)
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
	reset_render_interpolation()

func rotate_heading(angle: float) -> void:
	heading = heading.rotated(global_position.normalized(), angle).normalized()

func begin_entry() -> void:
	if not visuals_ready():
		return
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
	visual.position.y = (-0.08*sin(t/0.16*PI) if t < 0.16 else sin((t-0.16)/0.84*PI*0.7)*1.5) * avatar_scale
	var fade: float = smoothstep(0.63,1.0,t)
	for mat: StandardMaterial3D in entry_materials:
		mat.set("transparency",BaseMaterial3D.TRANSPARENCY_ALPHA if fade > 0.001 else int(mat.get_meta("original_transparency")))
		mat.albedo_color.a = 1.0-fade
	if animator != null and active_clip == &"JumpDown":
		_queue_animation_pose(minf(t*1.4,animator.get_animation(animator.current_animation).length))
	visual.visible = t < 1.0

func finish_entry() -> void:
	entering = false
	visual.position = Vector3.ZERO
	visual.visible = true
	for mat: StandardMaterial3D in entry_materials:
		mat.albedo_color.a = 1.0
		mat.set("transparency",int(mat.get_meta("original_transparency")))
	set_clip(&"Idle")
