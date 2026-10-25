extends Node

## Volume-safe indoor follow/focus camera. Camera-only blockers use layer 256;
## the player uses layer 4 and must never collide with hanging camera proxies.
const CAMERA_MASK: int = 1 | 256
const LENS_RADIUS: float = .18
const FOCUS_SECONDS: float = .34
var room: Node3D
var camera: Camera3D
var player: CharacterBody3D
var bounds: AABB
var mask: int = CAMERA_MASK
var _shape := SphereShape3D.new()
var _query := PhysicsShapeQueryParameters3D.new()
var _last_aim: Vector3
var _has_aim: bool = false
var _generation: int = 0
var _focusing: bool = false

func configure(owner_room: Node3D, view_camera: Camera3D, actor: CharacterBody3D, enclosure: AABB, camera_mask: int = CAMERA_MASK) -> void:
	room = owner_room
	camera = view_camera
	player = actor
	bounds = enclosure.grow(-LENS_RADIUS)
	mask = camera_mask
	_shape.radius = LENS_RADIUS
	_query.shape = _shape
	_query.collision_mask = mask
	_query.collide_with_areas = false
	_query.exclude = [player.get_rid()]
	reset_follow()

func reset_follow() -> void:
	_generation += 1
	_focusing = false
	_has_aim = false

func set_extra_exclusions(bodies: Array[RID]) -> void:
	# Seated actors occupy their authored chair proxy. Ignore that one proxy
	# while keeping walls, tables and overhead blockers in the lens sweep.
	var exclusions: Array[RID] = [player.get_rid()]
	for body: RID in bodies:
		if body.is_valid() and body not in exclusions:
			exclusions.append(body)
	_query.exclude = exclusions
	_has_aim = false

func _inside(point: Vector3) -> Vector3:
	return point.clamp(bounds.position, bounds.end)

func safe_position(aim: Vector3, desired: Vector3) -> Vector3:
	var start: Vector3 = _inside(aim)
	var motion: Vector3 = _inside(desired) - start
	if motion.length_squared() < .0001:
		return start
	_query.transform = Transform3D(Basis.IDENTITY, start)
	_query.motion = motion
	var space: PhysicsDirectSpaceState3D = room.get_world_3d().direct_space_state
	var fractions: PackedFloat32Array = space.cast_motion(_query)
	var fraction: float = fractions[0] if fractions.size() == 2 else 0.0
	# Pull in immediately on obstruction. Reserve a small contact margin so
	# smoothing and the near plane cannot put the lens through thin geometry.
	if fraction < 1.0:
		fraction = maxf(0.0, fraction - .025 / motion.length())
	var result: Vector3 = start + motion * fraction
	_query.motion = Vector3.ZERO
	for attempt: int in range(12):
		_query.transform.origin = result
		if space.intersect_shape(_query, 1).is_empty():
			return result
		fraction *= .8
		result = start + motion * fraction
	return result

func follow(aim: Vector3, desired: Vector3, delta: float, snap: bool = false) -> void:
	if _focusing or not is_instance_valid(camera):
		return
	var target: Vector3 = safe_position(aim, desired)
	var previous: Vector3 = camera.global_position
	if _has_aim and not snap:
		previous += aim - _last_aim
	var next: Vector3 = target if snap else previous.lerp(target, 1.0 - exp(-delta * 12.0))
	# Recheck AFTER interpolation. Otherwise a newly blocked arm remains
	# inside the wall/lamp for several frames while easing toward safety.
	camera.global_position = safe_position(aim, next)
	if camera.global_position.distance_squared_to(aim) > .001:
		camera.look_at(aim, Vector3.UP)
	_last_aim = aim
	_has_aim = true

func focus_to(data: Dictionary) -> bool:
	if not data.get("focus_camera") is Vector3 or not data.get("focus_target") is Vector3 or not is_instance_valid(camera):
		return false
	var desired: Vector3 = data.focus_camera as Vector3
	var target: Vector3 = data.focus_target as Vector3
	if not desired.is_finite() or not target.is_finite() or desired.distance_squared_to(target) < .01:
		return false
	reset_follow()
	_focusing = true
	var generation: int = _generation
	var start: Transform3D = camera.global_transform
	var initial_fov: float = camera.fov
	var position: Vector3 = safe_position(target, desired)
	if position.distance_squared_to(target) < .01:
		_focusing = false
		return false
	var target_basis: Basis = Basis.looking_at(target - position, Vector3.UP)
	var fov: float = clampf(float(data.get("fov", 48.0)), 35.0, 75.0)
	var elapsed: float = 0.0
	while elapsed < FOCUS_SECONDS:
		await get_tree().process_frame
		if generation != _generation or not is_instance_valid(camera):
			return false
		elapsed += get_process_delta_time()
		var weight: float = smoothstep(0.0, FOCUS_SECONDS, elapsed)
		camera.global_position = safe_position(target, start.origin.lerp(position, weight))
		camera.global_basis = start.basis.slerp(target_basis, weight)
		camera.fov = lerpf(initial_fov, fov, weight)
	_focusing = false
	_has_aim = false
	return true

func _exit_tree() -> void:
	reset_follow()
