extends SceneTree

## Real shipped small-world benches with the equally scaled outdoor avatar.
const Startup = preload("res://tests/startup_fixture.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const Bench = preload("res://scripts/bench_interaction.gd")
const OUTPUT: String = "res://../deliverables/mobile-ui/scaled-avatar-bench-checks.json"
var world: Node3D
var player: PlanetPlayer
var benches: Node
var checks: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var failures: int = 0
var access_only: bool = false
var capture: bool = false
var capture_camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label+": "+str(evidence))

func run() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	access_only = OS.get_cmdline_user_args().has("--access-only")
	capture = OS.get_cmdline_user_args().has("--bench-capture")
	if capture:
		root.size = Vector2i(1280,800)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	player = world.get("player") as PlanetPlayer
	benches = world.get("benches") as Node
	world.call("set_overview",false)
	check("Production avatar becomes ready",await Startup.wait_roaming(world,self))
	(world.get("hud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	if capture:
		(world.get("hud") as CanvasLayer).visible = false
	Engine.max_fps = 0
	player.allow_test_input = true
	player.test_running = false
	player.test_direction = Vector2.ZERO
	await ticks(30)
	check("Outdoor avatar and capsule scale once while character-relative speed stays original",is_equal_approx(player.planet_radius,21.6) and is_equal_approx(player.avatar_scale,.4) and player.visual.scale.is_equal_approx(Vector3.ONE*.4) and player.global_basis.get_scale().is_equal_approx(Vector3.ONE) and is_equal_approx(player.walk_speed/player.avatar_scale,3.8))
	var seats: Array = benches.get("seats") as Array
	var authored_count: int = 0
	var districts: Dictionary = {}
	for node: Node in world.find_children("*","StaticBody3D",true,false):
		if Bench.is_bench(node as StaticBody3D): authored_count += 1
	check("Every surviving authored bench is registered",authored_count==seats.size() and seats.size()>=7,{"authored":authored_count,"registered":seats.size()})
	for seat: StaticBody3D in seats:
		var label: String = str(world.get_path_to(seat))
		var district: String = "sakura" if label.contains("SakuraGrove") else str(seat.name).get_slice("_",0)
		districts[district] = int(districts.get(district,0))+1
		var target: Dictionary = benches.call("safe_stand",seat) as Dictionary
		inventory.append({"path":label,"district":district,"scale":str(seat.global_basis.get_scale()),"safe_stand":str(target.get("point","none"))})
		check("Scaled capsule has a dry front exit: "+label,not target.is_empty())
		if target.is_empty(): continue
		var point: Vector3 = target.point
		await place(point,seat)
		check("Scaled capsule fits the bench approach: "+label,capsule_clear(player.global_position) and player.is_on_floor())
		check("Bench can be selected from its actual safe approach: "+label,benches.get("nearest")==seat,{"selected":str(benches.get("nearest")),"point":str(point)})
		if access_only or benches.get("nearest")!=seat: continue
		var capture_seat: bool = capture and district == "sakura" and capture_camera == null
		if capture_seat:
			capture_camera = Camera3D.new()
			capture_camera.near = .025
			capture_camera.fov = 50.0
			world.add_child(capture_camera)
			var frame: Transform3D = seat.global_transform.orthonormalized()
			capture_camera.global_position = frame * (Vector3(2.2,1.8,-3.2)*player.avatar_scale)
			capture_camera.look_at(frame.origin+frame.basis.y*.85*player.avatar_scale,frame.basis.y)
			capture_camera.make_current()
			await save_capture("standing")
		check("Interaction starts sitting: "+label,bool(benches.call("interact")))
		await wait_state("resting",100)
		check("Sit reaches stable rest: "+label,str(benches.get("state"))=="resting" and player.is_resting)
		var pose: RefCounted = benches.get("pose") as RefCounted
		var model: Node3D = pose.get("model") as Node3D if pose != null else null
		check("Matched small seat and avatar use the original pose scaled once: "+label,model != null and str(model.get_meta("seat_pose_asset","")).ends_with("graduate_rest.glb") and model.scale.is_equal_approx(Vector3.ONE) and model.global_basis.get_scale().is_equal_approx(Vector3.ONE*.4))
		if capture_seat:
			await save_capture("seated")
		var rest_point: Vector3 = player.global_position
		player.test_direction = Vector2(1,-1).normalized()
		player.test_running = true
		var jump_accepted: bool = player.request_jump()
		await ticks(10)
		check("Seated movement and jump remain locked: "+label,not jump_accepted and player.global_position.distance_to(rest_point)<.0001)
		player.test_direction = Vector2.ZERO
		player.test_running = false
		check("Interaction starts standing: "+label,bool(benches.call("interact")))
		await wait_state("idle",90)
		await ticks(25)
		var exit_local: Vector3 = seat.global_transform.orthonormalized().affine_inverse()*player.global_position
		check("Standing returns to clear grounded scaled movement: "+label,str(benches.get("state"))=="idle" and not player.is_resting and player.collision_mask==9 and player.is_on_floor() and capsule_clear(player.global_position) and exit_local.z<-.6*player.avatar_scale and player.global_basis.get_scale().is_equal_approx(Vector3.ONE),{"local_exit":str(exit_local),"on_floor":player.is_on_floor()})
		if capture_seat:
			await save_capture("exit")
	for district: String in ["counseling","admissions","recommendations","universities","life","wordking","sakura"]:
		check("Bench coverage remains in "+district,int(districts.get(district,0))>0,districts.get(district,0))
	if not seats.is_empty():
		await check_blocker(seats[0] as StaticBody3D)
	var output: String = OUTPUT.replace("bench-checks","bench-access-checks") if access_only else OUTPUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"inventory":inventory,"access_only":access_only,"fixture":"Actual world.tscn, every registered permanent seat, production safe_stand and .4-scale character. No obstacle removal or replacement floor. Temporary front blocker is only a rejection positive control."},"\t"))
	print("SCALED_BENCH_CHECKS seats=",seats.size()," checks=",checks.size()," failures=",failures," access_only=",access_only)
	world.free()
	await process_frame
	quit(1 if failures>0 else 0)

func save_capture(phase: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://../deliverables/mobile-ui/scaled-avatar-bench-"+phase+".png"
	check("Render capture "+phase,root.get_texture().get_image().save_png(path)==OK)

func check_blocker(seat: StaticBody3D) -> void:
	var target: Dictionary = benches.call("safe_stand",seat) as Dictionary
	if target.is_empty(): return
	await place(target.point,seat)
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.4,2.1,1.65)*player.avatar_scale
	shape_node.shape = shape
	blocker.add_child(shape_node)
	world.add_child(blocker)
	blocker.global_transform = seat.global_transform.orthonormalized()*Transform3D(Basis.IDENTITY,Vector3(0,1,-1.18)*player.avatar_scale)
	await ticks(2)
	check("A real blocked exit is rejected for the scaled character",(benches.call("safe_stand",seat) as Dictionary).is_empty() and not bool(benches.call("can_approach",seat)))
	blocker.queue_free()
	await ticks(2)

func place(point: Vector3, seat: StaticBody3D) -> void:
	player.test_direction = Vector2.ZERO
	player.teleport(point.normalized(),point.length()+.10*player.avatar_scale)
	player.heading = (seat.global_position-point).slide(point.normalized()).normalized()
	player.global_basis = Basis(player.heading.cross(point.normalized()).normalized(),point.normalized(),-player.heading)
	await ticks(30)
	world.call("update_nearest")
	benches.call("refresh_nearest")

func capsule_clear(point: Vector3) -> bool:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = .27*player.avatar_scale
	shape.height = 1.6*player.avatar_scale
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Geo.frame(point.normalized()),point+point.normalized()*.82*player.avatar_scale)
	query.collision_mask = 8
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func ticks(count: int) -> void:
	for _i: int in range(count): await physics_frame

func wait_state(expected: String, count: int) -> void:
	for _i: int in range(count):
		if str(benches.get("state"))==expected: return
		await physics_frame
