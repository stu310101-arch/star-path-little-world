extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

const Geo = preload("res://scripts/planet_geometry.gd")
const PlayerScript = preload("res://scripts/planet_player.gd")
const RADIUS: float = 48.0
const FLOOR_HEIGHT: float = .26
const DT: float = 1.0 / 60.0
const OUTPUT: String = "res://../deliverables/jump-physics-checks.json"

var arena: Node3D
var fixture: Node3D
var player: CharacterBody3D
var checks: Array[Dictionary] = []
var traces: Dictionary = {}
var failures: int = 0
var fixture_up: Vector3 = Vector3.UP

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func run() -> void:
	Engine.physics_ticks_per_second = 60
	for action: String in ["move_left","move_right","move_forward","move_back","run","jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var jump_key: InputEventKey = InputEventKey.new()
	jump_key.physical_keycode = KEY_SPACE
	InputMap.action_add_event("jump",jump_key)
	arena = Node3D.new()
	arena.name = "JumpPhysicsFixture"
	root.add_child(arena)
	current_scene = arena
	player = PlayerScript.new() as CharacterBody3D
	player.set("planet_radius",RADIUS)
	arena.add_child(player)
	check("Jump fixture prepares original character animations", await StartupFixture.prepare_player(player, self))
	player.set("allow_test_input",true)
	player.set("controls_enabled",true)
	check("Runtime exposes actual jump state and launch counters",has_property("jump_state") and has_property("jump_count") and has_property("landing_count"))
	if failures > 0:
		finish()
		return
	for up: Vector3 in [Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT,Vector3.BACK,Vector3.DOWN]:
		await prepare(up)
		var label: String = "ground_jump_" + str(up)
		var before_count: int = int(player.get("jump_count"))
		press_jump()
		var rows: Array[Dictionary] = await trace(145,1)
		traces[label] = rows
		check(label + " rises under radial gravity and lands",peak(rows)>1.35 and peak(rows)<2.0 and player.is_on_floor(),summary(rows))
		check(label + " launches exactly once",int(player.get("jump_count"))-before_count==1)
		check(label + " keeps tangent frame finite and feet above floor",valid_frames(rows),summary(rows))
		check(label + " has anticipation airborne and landing phases",states_include(rows,["anticipation","airborne","landing"]),state_names(rows))
		check(label + " animates airborne motion and returns to grounded Idle",animated_air(rows) and str(player.get("jump_state"))=="grounded" and str(player.get("active_clip"))=="Idle",summary(rows))
		var pose_result: Dictionary = flip_evidence(rows)
		check(label + " performs one complete forward somersault in world space",bool(pose_result.complete_forward_flip),pose_result)
		check(label + " has an inverted airborne pose with head above the ground",bool(pose_result.inverted_airborne) and float(pose_result.minimum_air_head_clearance)>.03,pose_result)
		check(label + " lands upright and restores the visual pivot",bool(pose_result.upright_landing) and pivot_reset(),pose_result)
		check(label + " keeps landing cloth visible for its full settle",settle_evidence(rows),summary(rows))
	await landing_recovery_test()
	await repeat_during_recovery_test()
	await prepare(Vector3.UP)
	var held_before: int = int(player.get("jump_count"))
	press_jump()
	var held_rows: Array[Dictionary] = await trace(190,-1)
	check("Holding Space through landing does not auto-repeat",int(player.get("jump_count"))-held_before==1 and player.is_on_floor(),summary(held_rows))
	traces["held_space"] = held_rows
	release_jump()
	await tick(2)
	press_jump()
	await trace(145,1)
	check("Releasing and pressing Space starts a new grounded jump",int(player.get("jump_count"))-held_before==2)
	await prepare(Vector3.UP)
	var double_before: int = int(player.get("jump_count"))
	press_jump()
	var double_rows: Array[Dictionary] = await trace(25,1)
	var pre_second_velocity: float = radial_velocity()
	press_jump()
	double_rows.append_array(await trace(120,1))
	check("Second airborne Space press cannot double jump",int(player.get("jump_count"))-double_before==1 and peak(double_rows)<2.0,summary(double_rows))
	check("Airborne second press does not inject an upward velocity spike",float(double_rows[26].radial_velocity)<pre_second_velocity+.3,{"before":pre_second_velocity,"after":double_rows[26].radial_velocity})
	traces["no_double_jump"] = double_rows
	await prepare(Vector3.UP)
	var echo_before: int = int(player.get("jump_count"))
	var echo_event: InputEventKey = InputEventKey.new()
	echo_event.physical_keycode = KEY_SPACE
	echo_event.pressed = true
	echo_event.echo = true
	Input.parse_input_event(echo_event)
	await tick(30)
	check("OS key-repeat echo alone never starts a jump",int(player.get("jump_count"))==echo_before)
	release_jump()
	for height: float in [1.0,1.2]:
		await obstacle_test(height)
	await tall_wall_test()
	await low_prop_test()
	await step_off_test()
	await disabled_controls_test()
	finish()

func has_property(property_name: String) -> bool:
	for row: Dictionary in player.get_property_list():
		if str(row.name)==property_name:
			return true
	return false

func prepare(up: Vector3, start: Vector2 = Vector2.ZERO) -> void:
	release_jump()
	player.set_physics_process(false)
	if fixture != null:
		fixture.free()
	fixture_up = up
	fixture = Node3D.new()
	fixture.name = "SphericalFloorAndObstacles"
	arena.add_child(fixture)
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: int in range(-20,20):
		for z: int in range(-20,20):
			var a: Vector3 = Geo.surface(up,Vector2(x,z)*.5,RADIUS+FLOOR_HEIGHT)
			var b: Vector3 = Geo.surface(up,Vector2(x+1,z)*.5,RADIUS+FLOOR_HEIGHT)
			var c: Vector3 = Geo.surface(up,Vector2(x+1,z+1)*.5,RADIUS+FLOOR_HEIGHT)
			var d: Vector3 = Geo.surface(up,Vector2(x,z+1)*.5,RADIUS+FLOOR_HEIGHT)
			Geo.triangle(st,a,b,c,Color.WHITE)
			Geo.triangle(st,a,c,d,Color.WHITE)
	Geo.mesh_node(fixture,"MeasuredSphericalGround",st.commit(),null,true)
	player.set("test_direction",Vector2.ZERO)
	player.set("test_running",false)
	player.set("controls_enabled",true)
	player.set("land_only",true)
	var normal: Vector3 = Geo.surface(up,start,RADIUS).normalized()
	player.call("teleport",normal,RADIUS+.65)
	player.set("heading",(-Geo.frame(up).z).slide(normal).normalized())
	player.set_physics_process(true)
	await tick(32)
	check("Fixture begins settled " + str(up) + " " + str(start),player.is_on_floor() and not bool(player.get("needs_settle")))

func add_box(label: String, offset: Vector2, size: Vector3, layer: int = 8) -> StaticBody3D:
	var normal: Vector3 = Geo.surface(fixture_up,offset,RADIUS).normalized()
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label
	body.collision_layer = layer
	body.collision_mask = 0
	fixture.add_child(body)
	body.global_transform = Transform3D(Basis(Quaternion(fixture_up,normal))*Geo.frame(fixture_up),normal*(RADIUS+FLOOR_HEIGHT+size.y*.5))
	var collision: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func obstacle_test(height: float) -> void:
	await prepare(Vector3.UP,Vector2(0,2.0))
	add_box("MeasuredRail",Vector2.ZERO,Vector3(6.0,height,.14))
	await tick(2)
	player.set("test_direction",Vector2(0,-1))
	await tick(50)
	check("Walking cannot pass the actual " + str(height) + "m rail",local_point().y>.3,local_point().y)
	player.set("test_direction",Vector2.ZERO)
	player.call("teleport",Geo.surface(fixture_up,Vector2(0,2.0),RADIUS).normalized(),RADIUS+.65)
	await tick(32)
	player.set("test_direction",Vector2(0,-1))
	press_jump()
	var rows: Array[Dictionary] = await trace(145,1,75)
	traces["rail_"+str(height)] = rows
	var cross_height: float = INF
	for row: Dictionary in rows:
		if absf(float(row.local_z))<.2:
			cross_height=minf(cross_height,float(row.height))
	check("Jump clears " + str(height) + "m rail with real collision enabled",local_point().y<-.7 and player.is_on_floor(),{"finish":local_point().y,"cross_height":cross_height,"summary":summary(rows)})
	check("Feet clear the rail top during crossing",cross_height!=INF and cross_height>height-.03,{"rail_height":height,"measured_foot_height":cross_height})

func tall_wall_test() -> void:
	await prepare(Vector3.RIGHT,Vector2(0,2.0))
	add_box("ThreeMetreWall",Vector2.ZERO,Vector3(6,3,.2))
	await tick(2)
	player.set("test_direction",Vector2(0,-1))
	press_jump()
	var rows: Array[Dictionary] = await trace(145,1,90)
	traces["tall_wall"] = rows
	check("A 3m wall still blocks a jumping capsule on a side island",local_point().y>.33 and player.is_on_floor(),summary(rows))
	var no_penetration: bool = true
	for row: Dictionary in rows:
		no_penetration = no_penetration and float(row.local_z)>.32
	check("No frame tunnels through the tall wall",no_penetration)

func low_prop_test() -> void:
	await prepare(Vector3.DOWN,Vector2(0,2.0))
	add_box("LowPropTop",Vector2.ZERO,Vector3(3,.75,2.4))
	await tick(2)
	player.set("test_direction",Vector2(0,-1))
	press_jump()
	var rows: Array[Dictionary] = await trace(150,1,38)
	traces["low_prop_landing"] = rows
	var altitude: float = player.global_position.length()-RADIUS-FLOOR_HEIGHT
	check("Landing can stay grounded on a layer8 low prop",player.is_on_floor() and altitude>.7 and altitude<.86 and str(player.get("jump_state"))=="grounded",summary(rows))
	check("Early contact with a raised prop already has feet below the head",bool(flip_evidence(rows).upright_landing),flip_evidence(rows))
	var landed: Vector3 = player.global_position
	await tick(60)
	check("Standing on a low prop does not sink or drift",player.is_on_floor() and player.global_position.distance_to(landed)<.003,player.global_position.distance_to(landed))
	var before: int = int(player.get("jump_count"))
	press_jump()
	await trace(145,1)
	check("A grounded low prop supports another intentional jump",int(player.get("jump_count"))-before==1 and player.is_on_floor())

func step_off_test() -> void:
	await prepare(Vector3.UP,Vector2.ZERO)
	add_box("RaisedWalkway",Vector2.ZERO,Vector3(3,.85,2.0))
	player.call("teleport",fixture_up,RADIUS+FLOOR_HEIGHT+1.15)
	await tick(40)
	check("Step-off begins on the raised surface",player.is_on_floor() and player.global_position.length()>RADIUS+.95)
	var before: int = int(player.get("jump_count"))
	player.set("test_direction",Vector2(0,-1))
	var rows: Array[Dictionary] = await trace(145,-1,55)
	traces["step_off"] = rows
	var fell: bool = false
	for row: Dictionary in rows:
		fell = fell or (not bool(row.grounded) and float(row.radial_velocity)<-.2)
	check("Walking off a step enters a natural fall without launching",fell and int(player.get("jump_count"))==before,summary(rows))
	check("Step-off lands on lower ground and recovers locomotion",player.is_on_floor() and player.global_position.length()<RADIUS+.4 and str(player.get("jump_state"))=="grounded",summary(rows))

func disabled_controls_test() -> void:
	await prepare(Vector3.UP)
	player.set("controls_enabled",false)
	player.set("allow_test_input",false)
	var before: int = int(player.get("jump_count"))
	press_jump()
	await trace(60,1)
	check("Disabled production controls reject Space",int(player.get("jump_count"))==before and player.is_on_floor())
	player.set("controls_enabled",true)
	player.set("allow_test_input",true)
	press_jump()
	await trace(25,1)
	player.call("teleport",Vector3.UP,RADIUS+.65)
	await tick(100)
	check("Teleport clears in-flight state and returns to ground",player.is_on_floor() and str(player.get("jump_state"))=="grounded")

func landing_recovery_test() -> void:
	await prepare(Vector3.UP)
	press_jump()
	var rows: Array[Dictionary] = []
	var moving_start: Vector3 = Vector3.ZERO
	var moving: bool = false
	for frame: int in range(165):
		if frame == 1:
			release_jump()
		if not moving and str(player.get("jump_state")) == "landing" and float(player.get("landing_clock")) >= .32:
			moving = true
			moving_start = player.global_position
			player.set("test_direction",Vector2(0,-1))
		await physics_frame
		rows.append(snapshot(frame))
	traces["moving_landing_recovery"] = rows
	var matched_samples: int = 0
	var largest_gap: float = .0
	var last_recovery: Dictionary = {}
	var first_walk: Dictionary = {}
	for row: Dictionary in rows:
		if str(row.state) == "landing" and float(row.landing_clock) > .50:
			matched_samples += 1
			largest_gap = maxf(largest_gap,float(row.recovery_pose_error))
			last_recovery = row
		elif not last_recovery.is_empty() and str(row.clip) == "Walk" and first_walk.is_empty():
			first_walk = row
	check("Walking remains responsive while the landing hem continues settling",moving and player.global_position.distance_to(moving_start)>2.0 and settle_evidence(rows),summary(rows))
	check("Recovery skeleton follows the live walk pose without freezing the legs",matched_samples>25 and largest_gap<.0001,{"matched_samples":matched_samples,"maximum_pose_error":largest_gap})
	var phase_error: float = INF
	if not first_walk.is_empty():
		var animator: AnimationPlayer = player.get("locomotion_animator") as AnimationPlayer
		var length_value: float = animator.get_animation(animator.current_animation).length
		var advance: float = fposmod(float(first_walk.animation_position)-float(last_recovery.recovery_clock),length_value)
		phase_error = absf(advance-DT*clampf(3.8/2.2,0.0,2.2))
	check("Visible handoff preserves walk phase and finishes with one model",phase_error<.015 and not bool(first_walk.get("jump_model_visible",true)) and bool(first_walk.get("locomotion_model_visible",false)),{"phase_error":phase_error,"before":last_recovery,"after":first_walk})
	player.set("test_direction",Vector2.ZERO)
	await tick(2)

func repeat_during_recovery_test() -> void:
	await prepare(Vector3.UP)
	var before: int = int(player.get("jump_count"))
	press_jump()
	await trace(100,1)
	check("First jump is grounded but still settling before deliberate repeat",player.is_on_floor() and str(player.get("jump_state"))=="landing" and str(player.get("active_clip"))=="JumpLand")
	press_jump()
	var rows: Array[Dictionary] = await trace(145,1)
	traces["repeat_during_recovery"] = rows
	check("A fresh grounded Space press interrupts cloth recovery with exactly one new jump",int(player.get("jump_count"))==before+2 and player.is_on_floor() and str(player.get("active_clip"))=="Idle",summary(rows))
	check("A repeated jump still performs one complete forward rotation",bool(flip_evidence(rows).complete_forward_flip),flip_evidence(rows))

func settle_evidence(rows: Array[Dictionary]) -> bool:
	var first: float = INF
	var last: float = -INF
	var latest_sample: float = .0
	for row: Dictionary in rows:
		if str(row.state) == "landing":
			if str(row.clip) != "JumpLand" or not bool(row.jump_model_visible) or bool(row.locomotion_model_visible):
				return false
			first = minf(first,float(row.seconds))
			last = maxf(last,float(row.seconds))
			latest_sample = maxf(latest_sample,float(row.animation_position))
	return last-first>1.15 and latest_sample>1.15

func press_jump() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"jump"
	event.pressed = true
	Input.parse_input_event(event)

func release_jump() -> void:
	var event: InputEventAction = InputEventAction.new()
	event.action = &"jump"
	event.pressed = false
	Input.parse_input_event(event)

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame

func trace(frames: int, release_at: int = -1, stop_at: int = -1) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for frame: int in range(frames):
		if frame==release_at:
			release_jump()
		if frame==stop_at:
			player.set("test_direction",Vector2.ZERO)
		await physics_frame
		rows.append(snapshot(frame))
	return rows

func radial_velocity() -> float:
	return player.velocity.dot(player.global_position.normalized())

func local_point() -> Vector2:
	var axes: Basis = Geo.frame(fixture_up)
	var normal: Vector3 = player.global_position.normalized()
	return Vector2(normal.dot(axes.x),normal.dot(axes.z))*RADIUS/normal.dot(fixture_up)

func snapshot(frame: int) -> Dictionary:
	# This fixture inspects every physics step, including steps between rendered
	# frames. Flush the pending visual pose before comparing bone positions.
	# animation_sampling_checks separately verifies the production render cadence.
	player.call("sample_motion_animation")
	var animator: AnimationPlayer = player.get("animator") as AnimationPlayer
	return {"frame":frame,"seconds":frame*DT,"height":player.global_position.length()-RADIUS-FLOOR_HEIGHT,"position":[player.position.x,player.position.y,player.position.z],"local_z":local_point().y,"radial_velocity":radial_velocity(),"grounded":player.is_on_floor(),"state":str(player.get("jump_state")),"clip":str(player.get("active_clip")),"animation_clock":float(player.get("animation_clock")),"animation_position":animator.current_animation_position if animator!=null else -1.0,"jump_count":int(player.get("jump_count")),"finite":player.global_transform.is_finite() and player.velocity.is_finite(),"pose":measure_pose(),"landing_clock":float(player.get("landing_clock")),"recovery_clock":float(player.get("recovery_clock")),"recovery_pose_error":recovery_pose_error(),"jump_model_visible":(player.get("jump_model") as Node3D).visible,"locomotion_model_visible":(player.get("locomotion_model") as Node3D).visible}

func recovery_pose_error() -> float:
	if str(player.get("jump_state")) != "landing" or float(player.get("landing_clock")) < .50:
		return .0
	var source: Skeleton3D = player.get("locomotion_skeleton") as Skeleton3D
	var target: Skeleton3D = player.get("jump_skeleton") as Skeleton3D
	if source == null or target == null:
		return INF
	var largest: float = .0
	for bone_name: String in ["Head","Hips","Foot.L","Foot.R"]:
		var source_index: int = source.find_bone(bone_name)
		var target_index: int = target.find_bone(bone_name)
		if source_index < 0 or target_index < 0:
			return INF
		var source_point: Vector3 = source.to_global(source.get_bone_global_pose(source_index).origin)
		var target_point: Vector3 = target.to_global(target.get_bone_global_pose(target_index).origin)
		largest = maxf(largest,source_point.distance_to(target_point))
	return largest

func measure_pose() -> Dictionary:
	var model: Node3D = player.get("jump_model") as Node3D
	if model == null or not model.visible:
		model = player.get("locomotion_model") as Node3D
	if model == null:
		return {"valid":false}
	var skeleton: Skeleton3D = model.find_child("*",true,false) as Skeleton3D
	for candidate: Node in model.find_children("*","Skeleton3D",true,false):
		skeleton = candidate as Skeleton3D
		break
	if skeleton == null:
		return {"valid":false}
	var bones: Dictionary = {}
	for bone_name: String in ["Head","Hips","Foot.L","Foot.R"]:
		var index: int = skeleton.find_bone(bone_name)
		if index < 0:
			return {"valid":false,"missing":bone_name}
		bones[bone_name] = skeleton.to_global(skeleton.get_bone_global_pose(index).origin)
	var head: Vector3 = bones["Head"]
	var hips: Vector3 = bones["Hips"]
	var foot_l: Vector3 = bones["Foot.L"]
	var foot_r: Vector3 = bones["Foot.R"]
	var feet: Vector3 = (foot_l+foot_r)*.5
	var radial: Vector3 = player.global_position.normalized()
	var forward: Vector3 = player.get("heading") as Vector3
	var trunk: Vector3 = (head-hips).normalized()
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(head.normalized()*(RADIUS+4.5),head.normalized()*(RADIUS-.5),9)
	query.exclude = [player.get_rid()]
	var ground: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
	var head_clearance: float = head.length()-(ground.position as Vector3).length() if not ground.is_empty() else -INF
	return {"valid":true,"trunk_pitch":atan2(trunk.dot(forward),trunk.dot(radial)),"head_above_feet":(head-feet).dot(radial),"head_clearance":head_clearance,"left_foot_radius":foot_l.length(),"right_foot_radius":foot_r.length(),"head":[head.x,head.y,head.z],"feet":[feet.x,feet.y,feet.z]}

func flip_evidence(rows: Array[Dictionary]) -> Dictionary:
	var total: float = .0
	var previous: float = .0
	var started: bool = false
	var valid: bool = true
	var inverted: bool = false
	var upright: bool = true
	var landed_samples: int = 0
	var head_minimum: float = INF
	for row: Dictionary in rows:
		var pose: Dictionary = row.pose
		valid = valid and bool(pose.get("valid",false))
		if not bool(pose.get("valid",false)):
			continue
		var angle: float = float(pose.trunk_pitch)
		if started:
			total += wrapf(angle-previous,-PI,PI)
		previous = angle
		started = true
		if str(row.state)=="airborne":
			inverted = inverted or float(pose.head_above_feet)<-.2
			head_minimum = minf(head_minimum,float(pose.head_clearance))
		if str(row.state)=="landing":
			landed_samples += 1
			upright = upright and float(pose.head_above_feet)>.45 and cos(angle)>.35
	return {"valid":valid,"total_forward_pitch_degrees":rad_to_deg(total),"complete_forward_flip":valid and total>5.4 and total<7.2,"inverted_airborne":inverted,"minimum_air_head_clearance":head_minimum,"upright_landing":valid and upright and landed_samples>0,"landing_samples":landed_samples}

func pivot_reset() -> bool:
	var visual: Node3D = player.get("visual") as Node3D
	return visual.position.length()<.01 and absf(visual.rotation.x)<.01 and absf(visual.rotation.z)<.01

func peak(rows: Array[Dictionary]) -> float:
	var result: float = -INF
	for row: Dictionary in rows:
		result = maxf(result,float(row.height))
	return result

func valid_frames(rows: Array[Dictionary]) -> bool:
	for row: Dictionary in rows:
		if not bool(row.finite) or float(row.height)<-.04:
			return false
	return true

func state_names(rows: Array[Dictionary]) -> Array[String]:
	var result: Array[String] = []
	for row: Dictionary in rows:
		if not result.has(str(row.state)):
			result.append(str(row.state))
	return result

func states_include(rows: Array[Dictionary], expected: Array[String]) -> bool:
	var states: Array[String] = state_names(rows)
	for state: String in expected:
		if not states.has(state):
			return false
	return true

func animated_air(rows: Array[Dictionary]) -> bool:
	var samples: Array[float] = []
	for row: Dictionary in rows:
		if str(row.state)=="airborne":
			if str(row.clip) in ["Idle","Walk","Run",""]:
				return false
			samples.append(float(row.animation_position))
	if samples.size()<6:
		return false
	return samples.max()-samples.min()>.15

func summary(rows: Array[Dictionary]) -> Dictionary:
	return {"peak_feet_m":peak(rows),"states":state_names(rows),"end":rows[-1] if not rows.is_empty() else {}}

func finish() -> void:
	release_jump()
	var file: FileAccess = FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures==0,"checks":checks,"failures":failures,"traces":traces,"physics_hz":60,"fixture":"actual runtime PlanetPlayer on a 48m-radius collision patch; no manual physics/animation sampling and no world geometry loaded"},"\t"))
	print("JUMP_PHYSICS_CHECKS checks=",checks.size()," failures=",failures)
	quit(1 if failures>0 else 0)
