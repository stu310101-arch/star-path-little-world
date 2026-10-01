extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Timber = preload("res://scripts/waterfront_routes.gd")
const OUTPUT: String = "res://../deliverables/jump-world/"

var world: Node3D
var player: CharacterBody3D
var camera: Camera3D
var radius: float = 48.0
var checks: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var images: Array[Dictionary] = []
var failures: int = 0
var capture: bool = false
var portal_requests: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label+": "+str(evidence))

func run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture-jump")
	if capture and DisplayServer.get_name()=="headless":
		push_error("--capture-jump requires the native renderer, without --headless")
		quit(1)
		return
	Engine.physics_ticks_per_second = 60
	root.size = Vector2i(1440,900)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	player = world.get("player") as CharacterBody3D
	camera = world.get("camera") as Camera3D
	radius = float((world.get("layout") as Dictionary).radius)
	world.connect("request_open_station",on_portal)
	world.call("set_overview",false)
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	player.set("allow_test_input",true)
	player.set("test_direction",Vector2.ZERO)
	player.set("test_running",false)
	await tick(35)
	var crossing: Dictionary = find_existing_rail_crossing()
	check("Find an existing world rail with solid collision and dry full-width landing",not crossing.is_empty(),serialise_crossing(crossing))
	if not crossing.is_empty():
		await rail_jump(crossing)
	await shore_safety()
	await world_input_gates()
	await portal_unchanged()
	var result: Dictionary = {"passed":failures==0,"failures":failures,"checks":checks,"crossing":serialise_crossing(crossing),"trace":frames,"images":images,"notes":"Existing generated scene and real player input/physics. No temporary obstacle, floor, scene hiding, manual animation seek, or airborne teleport. Captures only pause between actual physics ticks; two cameras see the same pose."}
	var file: FileAccess = FileAccess.open(OUTPUT+"check-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("JUMP_WORLD_CHECKS checks=",checks.size()," failures=",failures," images=",images.size())
	quit(1 if failures>0 else 0)

func find_existing_rail_crossing() -> Dictionary:
	# Prefer the real Sakura town causeway: near its land end both sides of a
	# railing can be dry ground. Never demonstrate jumping into the sea.
	var bridge: Node3D = world.find_child("SakuraBridge",true,false) as Node3D
	if bridge != null:
		var normals: Array[Vector3] = [Plan.town_endpoint(radius),Plan.bridge_start(),Plan.bridge_finish(),Plan.grove_up()]
		var sides: Array[Vector3] = Geo.path_sides(normals)
		var first: float = float(bridge.get_meta("town_guardrail_start_fraction",.0))
		for i: int in range(24):
			var t: float = lerpf(first+.012,.97,float(i)/23.0)
			var sample: Dictionary = {"normal":normals[0].slerp(normals[1],t).normalized(),"side":sides[0].lerp(sides[1],t)}
			for sign_value: float in [-1.0,1.0]:
				var candidate: Dictionary = validate_crossing(sample,sign_value,1.35,"Sakura town causeway")
				if not candidate.is_empty():
					return candidate
	# Secondary real-world candidates come from the same shared waterfront
	# geometry data as the generated rails. Physics, not data alone, selects one.
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for index: int in range(data.size()):
		var up: Vector3 = Routes.directions()[index]
		var info: Dictionary = data[index]
		for path: Array in Routes.district_paths(info,radius):
			var route: Array[Dictionary] = Timber.samples(up,path,info,radius)
			for i: int in range(2,route.size()-2,3):
				if not bool(route[i].wet):
					continue
				for sign_value: float in [-1.0,1.0]:
					var candidate: Dictionary = validate_crossing(route[i],sign_value,1.035,str(info.station)+" boardwalk")
					if not candidate.is_empty():
						return candidate
	return {}

func validate_crossing(sample: Dictionary, sign_value: float, rail_offset: float, location: String) -> Dictionary:
	var side: Vector3 = (sample.side as Vector3).normalized()*sign_value
	var actual_rail_offset: float = rail_offset*(sample.side as Vector3).length()
	var center: Vector3 = sample.normal as Vector3
	# Put the rail 1.9m ahead of takeoff, where an ordinary walking jump reaches
	# useful clearance. The destination lies beyond the rail on measured land.
	var start: Vector3 = (center*radius+side*(actual_rail_offset-1.9)).normalized()
	var finish: Vector3 = (center*radius+side*(actual_rail_offset+1.65)).normalized()
	var forward: Vector3 = (finish-start).slide(start).normalized()
	var transverse: Vector3 = forward.cross(start).normalized()
	for i: int in range(16):
		var point: Vector3 = start.slerp(finish,float(i)/15.0)
		for lane: float in [-.32,0.0,.32]:
			var n: Vector3 = (point*radius+transverse*lane).normalized()
			if (player.call("ground_at",n) as Dictionary).is_empty():
				return {}
	var hit: Dictionary = {}
	for height: float in [.69,.72,1.21,1.23]:
		var ray: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(start*(radius+height),finish*(radius+height),8)
		ray.exclude = [player.get_rid()]
		hit = player.get_world_3d().direct_space_state.intersect_ray(ray)
		if not hit.is_empty() and str((hit.collider as Node).get_path()).contains("Rail"):
			break
	if hit.is_empty() or not str((hit.collider as Node).get_path()).contains("Rail"):
		return {}
	var start_ground: Dictionary = player.call("ground_at",start) as Dictionary
	var finish_ground: Dictionary = player.call("ground_at",finish) as Dictionary
	if not clear_capsule(start_ground.position as Vector3) or not clear_capsule(finish_ground.position as Vector3):
		return {}
	var contact_normal: Vector3 = (hit.position as Vector3).normalized()
	var contact_lateral: float = contact_normal.dot(side)*radius/contact_normal.dot(center)
	return {"start":start,"finish":finish,"center":center,"side":side,"rail_offset":actual_rail_offset,"rail_contact_lateral":contact_lateral,"rail_contact":hit.position,"rail_path":str((hit.collider as Node).get_path()),"location":location,"ground_start":str((start_ground.collider as Node).get_path()),"ground_finish":str((finish_ground.collider as Node).get_path())}

func clear_capsule(ground_position: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 8
	query.exclude = [player.get_rid()]
	query.transform = Transform3D(Geo.frame(ground_position.normalized()),ground_position+ground_position.normalized()*.84)
	return player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func stage(crossing: Dictionary) -> void:
	release_jump()
	player.set("test_direction",Vector2.ZERO)
	player.call("teleport",crossing.start,radius+.65)
	player.set("heading",((crossing.finish as Vector3)-(crossing.start as Vector3)).slide(crossing.start as Vector3).normalized())
	(player.get("visual") as Node3D).rotation.y = PI
	await tick(35)

func rail_jump(crossing: Dictionary) -> void:
	await stage(crossing)
	check("Existing-rail launch position is grounded",player.is_on_floor())
	player.set("test_direction",Vector2(0,-1))
	await tick(48)
	var walked_lateral: float = lateral(crossing)
	# The approach widens toward town, so its real collision face does not sit
	# at the bridge centre-line's nominal width. Measure the actual ray hit.
	check("Walking is blocked by this exact world rail",walked_lateral<float(crossing.rail_contact_lateral)-.2,{"lateral":walked_lateral,"rail_contact":crossing.rail_contact_lateral,"nominal_offset":crossing.rail_offset})
	await stage(crossing)
	await capture_phase("01-standing")
	var before: int = int(player.get("jump_count"))
	var phase_names: Array[String] = []
	var continuous_dry: bool = true
	var maximum_height: float = .0
	var base: float = player.global_position.length()
	player.set("test_direction",Vector2(0,-1))
	press_jump()
	for frame: int in range(160):
		if frame==2:
			release_jump()
		await physics_frame
		var phase: String = str(player.get("jump_state"))
		var flip: float = float(player.get("flip_progress"))
		var height: float = player.global_position.length()-base
		maximum_height = maxf(maximum_height,height)
		continuous_dry = continuous_dry and not (player.call("ground_at",player.global_position.normalized()) as Dictionary).is_empty()
		frames.append({"frame":frame,"seconds":frame/60.0,"state":phase,"flip_progress":flip,"height":height,"radial_velocity":player.velocity.dot(player.global_position.normalized()),"lateral":lateral(crossing),"grounded":player.is_on_floor(),"position":vec(player.global_position),"clip":str(player.get("active_clip")),"animation_clock":float(player.get("animation_clock"))})
		if lateral(crossing)>float(crossing.rail_offset)+1.45:
			player.set("test_direction",Vector2.ZERO)
		var wanted: String = ""
		if phase=="anticipation" and frame>=3:
			wanted="02-anticipation"
		elif phase=="airborne" and flip<.18:
			wanted="03-takeoff"
		elif phase=="airborne" and flip>=.22 and flip<.45:
			wanted="04-quarter-turn"
		elif phase=="airborne" and flip>=.46 and flip<.7:
			wanted="05-inverted-apex"
		elif phase=="airborne" and flip>=.73:
			wanted="06-open-for-landing"
		elif phase=="landing":
			wanted="07-landing"
		elif phase=="grounded" and frame>70:
			wanted="08-recovered"
		if wanted!="" and not phase_names.has(wanted):
			phase_names.append(wanted)
			await capture_phase(wanted)
	player.set("test_direction",Vector2.ZERO)
	check("Space physically crosses the existing rail and lands beyond it",lateral(crossing)>float(crossing.rail_contact_lateral)+.7 and player.is_on_floor() and int(player.get("jump_count"))==before+1,{"lateral":lateral(crossing),"rail_contact":crossing.rail_contact_lateral,"peak":maximum_height})
	check("This world jump never relies on the ocean as a landing",continuous_dry)
	check("World jump has every requested animation phase",phase_names.size()==7,phase_names)
	check("Ordinary jumping does not trigger entry fade or hide the player",not bool(player.get("entering")) and (player.get("visual") as Node3D).visible)

func lateral(crossing: Dictionary) -> float:
	var center: Vector3 = crossing.center as Vector3
	var normal: Vector3 = player.global_position.normalized()
	return normal.dot(crossing.side as Vector3)*radius/normal.dot(center)

func capture_phase(label: String) -> void:
	if not capture:
		return
	player.set_physics_process(false)
	(world.get("camera_obstruction") as RefCounted).call("reset")
	var hud: CanvasLayer = world.get("hud") as CanvasLayer
	hud.visible = false
	var up: Vector3 = player.global_position.normalized()
	var forward: Vector3 = player.get("heading") as Vector3
	var right: Vector3 = forward.cross(up).normalized()
	var aim: Vector3 = player.global_position+up*.9
	for angle: String in ["front-three-quarter","side"]:
		var eye: Vector3 = aim+up*1.35+(forward*5.0+right*4.0 if angle=="front-three-quarter" else right*6.5)
		camera.fov = 40.0
		camera.global_transform = Transform3D(Basis.IDENTITY,eye).looking_at(aim,up)
		await process_frame
		await RenderingServer.frame_post_draw
		var pixels: Image = root.get_texture().get_image()
		var filename: String = label+"-"+angle+".png"
		var error: Error = pixels.save_png(ProjectSettings.globalize_path(OUTPUT+filename))
		check("Write actual world pose "+filename,error==OK)
		images.append({"file":filename,"state":str(player.get("jump_state")),"clip":str(player.get("active_clip")),"flip_progress":float(player.get("flip_progress")),"grounded":player.is_on_floor(),"feet_position":vec(player.global_position),"camera_position":vec(eye),"camera_target":vec(aim),"physics_paused_only_for_same_pose_views":true})
	player.set_physics_process(true)

func shore_safety() -> void:
	release_jump()
	player.set("test_direction",Vector2.ZERO)
	var shore_angle: float = .0
	var outward: Vector3 = Vector3(-1,0,-1).normalized()
	for i: int in range(1,100):
		var angle: float = float(i)*.01
		var normal: Vector3 = Vector3.UP*cos(angle)+outward*sin(angle)
		if (player.call("ground_at",normal) as Dictionary).is_empty():
			shore_angle=angle
			break
	check("Locate an actual unbridged shoreline",shore_angle>.3 and shore_angle<.8,shore_angle)
	if shore_angle<=.0:
		return
	var start: Vector3 = Vector3.UP*cos(shore_angle-.025)+outward*sin(shore_angle-.025)
	player.call("teleport",start,radius+.65)
	player.set("heading",outward.slide(start).normalized())
	await tick(35)
	player.set("test_direction",Vector2(0,-1))
	player.set("test_running",true)
	press_jump()
	var dry: bool = true
	var radius_min: float = INF
	for frame: int in range(180):
		if frame==2:
			release_jump()
		await physics_frame
		dry = dry and not (player.call("ground_at",player.global_position.normalized()) as Dictionary).is_empty()
		radius_min = minf(radius_min,player.global_position.length())
	player.set("test_direction",Vector2.ZERO)
	player.set("test_running",false)
	check("Running jump toward open ocean stops at dry shore and lands",dry and player.is_on_floor() and radius_min>radius-.03,{"dry_all_frames":dry,"minimum_radius":radius_min})

func world_input_gates() -> void:
	player.set("allow_test_input",false)
	world.call("teleport_to","counseling")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await tick(35)
	for mode: String in ["overview","paused","destinations"]:
		if mode=="overview":
			world.call("set_overview",true)
		elif mode=="paused":
			world.call("pause_world")
		else:
			var hud: CanvasLayer = world.get("hud") as CanvasLayer
			# Use the same existing toggle button as a user opening this menu.
			(hud.get("destination_toggle") as Button).pressed.emit()
		var before: int = int(player.get("jump_count"))
		release_jump()
		await tick(2)
		press_jump()
		await tick(30)
		check("Space cannot jump with "+mode+" UI active",int(player.get("jump_count"))==before and str(player.get("jump_state"))=="grounded")
		release_jump()
		if mode=="destinations":
			((world.get("hud") as CanvasLayer).get("destination_toggle") as Button).pressed.emit()
		elif mode=="overview":
			world.call("set_overview",false)
			check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
		else:
			world.call("resume_world",{})
		await tick(2)

func portal_unchanged() -> void:
	world.call("teleport_to","counseling")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await tick(35)
	world.call("update_nearest")
	check("E portal is available at the same station arrival",str(world.get("nearest_id"))=="counseling")
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	Input.parse_input_event(event)
	await tick(2)
	check("E retains station entry and its separate JumpDown animation",bool(world.get("entering")) and bool(player.get("entering")) and str(player.get("active_clip"))=="JumpDown")
	var before: int = int(player.get("jump_count"))
	press_jump()
	await tick(15)
	check("Space cannot interrupt portal entry",int(player.get("jump_count"))==before and bool(player.get("entering")))
	release_jump()
	world.set_process(true)
	await tick(95)
	world.set_process(false)
	check("Original E entry emits the correct station request",portal_requests==["counseling"],portal_requests)
	world.call("resume_world",{})
	await tick(30)
	check("Returning from a portal restores grounded movement state",not bool(player.get("entering")) and str(player.get("jump_state"))=="grounded" and bool(player.get("controls_enabled")))

func on_portal(station: String, _return_token: Dictionary) -> void:
	portal_requests.append(station)

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

func tick(count: int) -> void:
	for frame: int in range(count):
		await physics_frame

func serialise_crossing(value: Dictionary) -> Dictionary:
	var result: Dictionary = value.duplicate()
	for key: String in result:
		if result[key] is Vector3:
			result[key]=vec(result[key] as Vector3)
	return result

func vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]
