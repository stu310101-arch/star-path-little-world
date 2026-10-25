extends SceneTree

const Player = preload("res://scripts/planet_player.gd")
const Indoor = preload("res://scripts/indoor_player.gd")
const OUTPUT: String = "res://../deliverables/mobile-smooth-screen/avatar-scale-checks.json"
var checks: Array[Dictionary] = []
var jumps: Array[Dictionary] = []
var failures: int = 0
var stage: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+str(detail))

func actor(value: float, script: Script = Player) -> PlanetPlayer:
	var body: PlanetPlayer = script.new()
	body.avatar_scale = value
	body.planet_radius = 24
	body.allow_test_input = true
	body.controls_enabled = false
	body.land_only = false
	body._walk_model_path = Player.MOBILE_WALK_MODEL
	body._jump_model_path = Player.MOBILE_JUMP_MODEL
	stage.add_child(body)
	body.begin_prepare_visuals()
	for step: int in range(5):body.step_prepare_visuals()
	return body

func run() -> void:
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	Engine.max_fps = 0
	for action: String in ["move_left","move_right","move_forward","move_back","run","jump"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
	stage = Node3D.new()
	root.add_child(stage)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var collider := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 24
	collider.shape = sphere
	ground.add_child(collider)
	stage.add_child(ground)
	var full := actor(1.0)
	var small := actor(.4)
	var indoor := actor(1.0,Indoor)
	indoor.set_physics_process(false)
	check("Both outdoor comparisons prepare shipped skeletal animation assets",full.visuals_ready() and small.visuals_ready())
	var capsule: CollisionShape3D = small.get_child(0) as CollisionShape3D
	check("Small body stays unit scale with independently scaled collision primitive",small.global_basis.get_scale().is_equal_approx(Vector3.ONE) and capsule.scale.is_equal_approx(Vector3.ONE) and is_equal_approx((capsule.shape as CapsuleShape3D).radius,.108) and is_equal_approx((capsule.shape as CapsuleShape3D).height,.64) and is_equal_approx(capsule.position.y,.328))
	check("Both delivered outdoor animation rigs inherit exactly .4 visual scale",small.visual.scale.is_equal_approx(Vector3.ONE*.4) and small.locomotion_model.global_basis.get_scale().is_equal_approx(Vector3.ONE*.4) and small.jump_model.global_basis.get_scale().is_equal_approx(Vector3.ONE*.4))
	check("Jump speed, gravity and collision clearances scale together",is_equal_approx(small.jump_speed,3.12) and is_equal_approx(small.gravity_strength,7.2) and is_equal_approx(small.safe_margin,.006) and is_equal_approx(small.floor_snap_length,.2) and is_equal_approx(small.shore_margin,.136))
	var indoor_capsule: CapsuleShape3D = (indoor.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
	check("Indoor controller keeps original size and vertical motion",indoor.avatar_scale==1 and indoor.visual.scale.is_equal_approx(Vector3.ONE) and is_equal_approx(indoor_capsule.radius,.27) and is_equal_approx(indoor_capsule.height,1.6) and is_equal_approx(indoor.jump_speed,7.8) and is_equal_approx(indoor.gravity_strength,18))
	check("All controllers retain original horizontal travel speed",small.walk_speed==3.8 and small.run_speed==6.4 and indoor.walk_speed==3.8 and indoor.run_speed==6.4)
	for up: Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,Vector3.DOWN,Vector3.LEFT,Vector3.BACK]:
		full.teleport(-up,24.05)
		small.teleport(up,24.02)
		await ticks(35)
		check("Both scaled and original controllers settle: "+str(up),small.is_on_floor() and full.is_on_floor())
		full.max_jump_height = 0
		small.max_jump_height = 0
		var full_count: int = full.landing_count
		var small_count: int = small.landing_count
		check("Scaled character starts the original jump action: "+str(up),full.request_jump() and small.request_jump())
		var full_air: int = 0
		var small_air: int = 0
		var clips: Array[String] = []
		var rejected_air_jump: bool = false
		for tick: int in range(160):
			await physics_frame
			if full.jump_state==&"airborne":full_air += 1
			if small.jump_state==&"airborne":
				small_air += 1
				if small_air==10:rejected_air_jump = not small.request_jump()
			if not clips.has(str(small.active_clip)):clips.append(str(small.active_clip))
			if small.landing_count>small_count and full.landing_count>full_count and small.jump_state==&"grounded":break
		var row: Dictionary = {"up":str(up),"full_peak_m":full.max_jump_height,"small_peak_m":small.max_jump_height,"peak_ratio":small.max_jump_height/maxf(full.max_jump_height,.001),"full_air_ticks":full_air,"small_air_ticks":small_air,"small_clips":clips}
		jumps.append(row)
		check("Jump height scales to .4 while hang time stays unchanged: "+str(up),absf(float(row.peak_ratio)-.4)<.02 and absi(small_air-full_air)<=2,row)
		check("Original start, flip and landing clips complete once: "+str(up),clips.has("JumpStart") and clips.has("JumpAir") and clips.has("JumpLand") and small.landing_count==small_count+1 and is_equal_approx(small.flip_progress,1.0) and rejected_air_jump,row)
		check("Scaled jump returns grounded with upright unit body and .4 visuals: "+str(up),small.is_on_floor() and small.jump_state==&"grounded" and small.global_basis.get_scale().is_equal_approx(Vector3.ONE) and small.global_basis.y.dot(small.global_position.normalized())>.999 and small.visual.scale.is_equal_approx(Vector3.ONE*.4))
	for running: bool in [false,true]:
		small.teleport(Vector3.UP,24.02)
		await ticks(30)
		var before: Vector3 = small.global_position
		small.test_direction = Vector2(0,-1)
		small.test_running = running
		await ticks(60)
		var travel: float = before.normalized().angle_to(small.global_position.normalized())*24
		var expected: float = small.run_speed if running else small.walk_speed
		check("Scaled character retains actual "+("running" if running else "walking")+" travel speed",absf(travel-expected)<.13,{"travel_1s_m":travel,"expected_m":expected,"clip":str(small.active_clip)})
		small.test_direction = Vector2.ZERO
	check("Scaled locomotion retains the 2.2x pose sampling cap",is_equal_approx(small._locomotion_rate(small.walk_speed,&"Walk"),2.2) and is_equal_approx(small._locomotion_rate(small.run_speed,&"Run"),2.2))
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"jumps":jumps,"scope":"Actual production controllers and shipped skeletal assets on R24 collision sphere; 1/60 simulated physics step (2x wall-clock acceleration). No body-transform scaling, no phone FPS claim."},"\t"))
	print("OUTDOOR_AVATAR_SCALE_CHECKS checks=",checks.size()," failures=",failures)
	stage.free()
	await process_frame
	quit(1 if failures>0 else 0)

func ticks(count: int) -> void:
	for tick: int in range(count):await physics_frame
