extends SceneTree

# Exercise the real controller at mismatched render/physics rates, including
# collisions, rather than claiming native timings represent phone GPU speed.
const Player = preload("res://scripts/planet_player.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const OUTPUT: String = "res://../deliverables/mobile-optimization/player-render-motion-checks.json"

class Sampler:
	extends Node
	var player: PlanetPlayer
	var rows: Array[Dictionary] = []
	var enabled: bool = false
	func _process(delta: float) -> void:
		if enabled:
			rows.append({"delta":delta,"raw":player.global_position,"render":player.render_motion.global_position})

class EmptyPose:
	extends RefCounted
	func finish() -> void:
		pass

var checks: Array[Dictionary] = []
var failures: int = 0
var timing: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+str(detail))

func run() -> void:
	Engine.max_fps = 90
	Engine.physics_ticks_per_second = 60
	for action: String in ["move_left","move_right","move_forward","move_back","run","jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var fixture := Node3D.new()
	root.add_child(fixture)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 24.0
	shape_node.shape = sphere
	ground.add_child(shape_node)
	fixture.add_child(ground)
	var player: PlanetPlayer = Player.new()
	player.planet_radius = 24.0
	player.avatar_scale = .4
	player.land_only = false
	player.allow_test_input = true
	fixture.add_child(player)
	check("Interpolation is opt-in; ordinary controllers retain their hierarchy",player.render_motion==null and player.visual.get_parent()==player)
	player.enable_render_interpolation()
	player.enable_render_interpolation()
	player.teleport(Vector3.UP,24.05)
	var sampler := Sampler.new()
	sampler.player = player
	sampler.process_priority = 100
	fixture.add_child(sampler)
	await create_timer(.6).timeout
	check("Scaled capsule settles on the physical R24 sphere",player.is_on_floor() and not player.needs_settle)
	player.test_direction = Vector2(0,-1)
	await create_timer(.3).timeout
	sampler.enabled = true
	await create_timer(3.0).timeout
	sampler.enabled = false
	timing = measure(sampler.rows)
	check("90Hz rendering exposes duplicate raw 60Hz movement frames",int(timing.raw_zero_motion_frames)>20,timing)
	check("Render interpolation eliminates repeated positions during walking",int(timing.render_zero_motion_frames)==0,timing)
	check("Rendered step error falls by at least 80 percent",float(timing.render_mean_step_error_m)<float(timing.raw_mean_step_error_m)*.2,timing)
	check("Interpolation leaves original movement speed intact",absf(float(timing.raw_distance_m)/float(timing.seconds)-3.8)<.05,timing)
	check("Only the visual subtree moves to a top-level render pivot",player.visual.get_parent()==player.render_motion and player.render_motion.top_level and player.get_child_count()==2)
	var collider: CollisionShape3D = player.get_child(0) as CollisionShape3D
	check("Capsule and visual scale together while body/render transforms stay unit",collider!=null and is_equal_approx((collider.shape as CapsuleShape3D).radius,.27*player.avatar_scale) and is_equal_approx((collider.shape as CapsuleShape3D).height,1.6*player.avatar_scale) and player.visual.scale.is_equal_approx(Vector3.ONE*player.avatar_scale) and player.global_basis.get_scale().is_equal_approx(Vector3.ONE) and player.render_motion.global_basis.get_scale().is_equal_approx(Vector3.ONE))
	player.set_physics_process(false)
	player.teleport(Vector3.RIGHT,24.3)
	check("Teleport resets displayed position immediately within the same frame",player.get_render_transform().origin.distance_to(player.global_position)<.00001 and player.render_motion.global_position.distance_to(player.global_position)<.00001)
	await process_frame
	check("Teleport leaves no following-frame interpolation streak",player.get_render_transform().origin.distance_to(player.global_position)<.00001)
	fixture.remove_child(player)
	fixture.add_child(player)
	check("Detached and restored outdoor avatar retains its reset render frame",player.render_motion.global_position.distance_to(player.global_position)<.00001)
	fixture.free()
	await process_frame
	await check_world_camera_and_reset()
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"timing":timing,"scope":"Real 0.4-scale PlanetPlayer collision on a physical R24 sphere, 3.8m/s, 60Hz physics and requested 90Hz native headless rendering. Separately checks the shipped world's camera, return teleport and bench reset. Not a phone FPS measurement."},"\t"))
	print("PLAYER_RENDER_MOTION_CHECKS checks=",checks.size()," failures=",failures," timing=",JSON.stringify(timing))
	quit(1 if failures>0 else 0)

func measure(rows: Array[Dictionary]) -> Dictionary:
	var raw_error: float = 0.0
	var render_error: float = 0.0
	var raw_zeros: int = 0
	var render_zeros: int = 0
	var total_time: float = 0.0
	var raw_distance: float = 0.0
	for index: int in range(1,rows.size()):
		var delta: float = float(rows[index].delta)
		var raw_step: float = (rows[index].raw as Vector3).distance_to(rows[index-1].raw)
		var render_step: float = (rows[index].render as Vector3).distance_to(rows[index-1].render)
		raw_error += absf(raw_step-3.8*delta)
		render_error += absf(render_step-3.8*delta)
		raw_distance += raw_step
		total_time += delta
		if raw_step<.000001:raw_zeros += 1
		if render_step<.000001:render_zeros += 1
	var count: int = maxi(rows.size()-1,1)
	return {"samples":rows.size(),"raw_zero_motion_frames":raw_zeros,"render_zero_motion_frames":render_zeros,"raw_mean_step_error_m":raw_error/count,"render_mean_step_error_m":render_error/count,"raw_distance_m":raw_distance,"seconds":total_time,"physics_hz":60,"requested_render_cap":90}

func check_world_camera_and_reset() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	world.set("startup_presented",true)
	world.set("overview",false)
	var player: PlanetPlayer = world.get("player")
	player.set_physics_process(false)
	check("Shipped outdoor world enables local render interpolation",player.render_motion!=null and not physics_interpolation)
	check("World shrinks spacing while retaining original character-relative speeds",is_equal_approx(player.planet_radius,21.6) and is_equal_approx(player.walk_speed/player.avatar_scale,3.8) and is_equal_approx(player.run_speed/player.avatar_scale,6.4) and is_equal_approx(player.avatar_scale,.4))
	var up: Vector3 = Vector3(1,1,.4).normalized()
	player.teleport(up,24.2)
	player.set("_render_previous",Transform3D(Geo.frame(Vector3.UP),Vector3.UP*24.2))
	var frame: Transform3D = player.get_render_transform()
	world.call("update_camera",.016)
	var aim: Vector3 = world.get("camera_aim")
	check("Actual follow camera targets the same interpolated position at scaled avatar height",aim.distance_to(frame.origin+frame.origin.normalized()*player.avatar_scale)<.00001)
	var heading_before: Vector3 = player.get_render_heading(frame.origin.normalized())
	player.rotate_heading(.4)
	var heading_after: Vector3 = player.get_render_heading(frame.origin.normalized())
	check("Camera dragging stays immediate in the displayed tangent plane",absf(heading_before.angle_to(heading_after)-.4)<.0001 and absf(heading_after.dot(frame.origin.normalized()))<.0001)
	world.call("resume_world",{"position":Vector3.LEFT*24.3,"heading":Vector3.FORWARD})
	check("Return from an indoor scene resets both render endpoints",player.get_render_transform().origin.distance_to(player.global_position)<.00001)
	var benches: Node = world.get("benches")
	benches.set("pose",EmptyPose.new())
	benches.set("state",&"resting")
	benches.set("seat_transform",player.global_transform)
	player.is_resting = true
	player.set("_render_previous",Transform3D(Basis.IDENTITY,Vector3.UP*24.3))
	benches.call("cancel")
	check("Standing or cancelling a seat resets both render endpoints",not player.is_resting and player.get_render_transform().origin.distance_to(player.global_position)<.00001)
	world.free()
	await process_frame
