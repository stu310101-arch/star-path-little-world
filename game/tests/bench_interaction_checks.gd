extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

const Geo = preload("res://scripts/planet_geometry.gd")
const Sakura = preload("res://scripts/sakura_routes.gd")
const OUTPUT: String = "res://../deliverables/performance/bench-checks.json"

var world: Node3D
var player: PlanetPlayer
var benches: Node
var checks: Array[Dictionary] = []
var inventory: Array[Dictionary] = []
var failures: int = 0
var radius: float = 48.0
var portal_requests: Array[String] = []
var access_only: bool = false
var seat_filter: String = ""

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+str(detail))

func run_checks() -> void:
	access_only = OS.get_cmdline_user_args().has("--access-only")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seat-filter="):
			seat_filter = argument.trim_prefix("--seat-filter=")
	# Retain a 1/60 s simulated physics step while running twice as fast.
	Engine.time_scale = 2.0
	Engine.physics_ticks_per_second = 120
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	player = world.get("player") as PlanetPlayer
	benches = world.get("benches") as Node
	radius = player.planet_radius
	check("World installs a bench interaction controller",benches != null)
	if benches == null:
		finish()
		return
	world.connect("request_open_station",on_portal)
	world.call("set_overview",false)
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	player.allow_test_input = true
	player.test_direction = Vector2.ZERO
	await tick(30)
	var seats: Array = benches.get("seats") as Array
	check("All 34 authored world benches are registered, including six legacy civic names",seats.size()==34,seats.size())
	var counts: Dictionary = {}
	for seat: StaticBody3D in seats:
		var path: String = str(world.get_path_to(seat))
		var district: String = bench_district(seat)
		counts[district] = int(counts.get(district,0))+1
		inventory.append({"path":path,"district":district,"position":vec(seat.global_position)})
	for district: String in ["counseling","admissions","recommendations","universities","life","wordking","sakura"]:
		var expected: int = 2 if district=="sakura" else (7 if district=="admissions" else 5)
		check("Complete bench coverage in "+district,int(counts.get(district,0))==expected,counts.get(district,0))
	check_garden_access()
	for index: int in range(seats.size()):
		if not seat_filter.is_empty() and not str(world.get_path_to(seats[index])).contains(seat_filter):
			continue
		await check_seat(seats[index] as StaticBody3D,index)
	if not access_only and seat_filter.is_empty() and not seats.is_empty():
		await check_safety_gates(seats[0] as StaticBody3D)
		await check_ui_and_teleport(seats[0] as StaticBody3D)
	if not access_only and seat_filter.is_empty():
		await check_station_entry()
	finish()

func check_garden_access() -> void:
	var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
	for sign_value: float in [-1.0,1.0]:
		var clear: bool = true
		var blocked_at: Array = []
		# Probe the full real capsule through the open terrace mouth. No bench,
		# railing or vegetation is removed or collision-disabled for these tests.
		for step: int in range(25):
			var offset: Vector2 = Vector2(sign_value*4.8,2.2).lerp(Vector2(sign_value*6.75,2.15),float(step)/24.0)
			var normal: Vector3 = Geo.surface(Sakura.grove_up(),offset,radius).normalized()
			var ground: Dictionary = Geo.ground_probe(space,normal,radius)
			if ground.is_empty() or not capsule_clear((ground.get("position",Vector3.ZERO) as Vector3)+normal*.035):
				clear = false
				blocked_at.append([offset.x,offset.y])
		check("Sakura "+str(sign_value)+" terrace has an unobstructed full-capsule entrance",clear,blocked_at)
		var inside: Vector3 = Geo.surface(Sakura.grove_up(),Vector2(sign_value*7.95,2.15),radius).normalized()*(radius+.72)
		var outside: Vector3 = Geo.surface(Sakura.grove_up(),Vector2(sign_value*8.55,2.15),radius).normalized()*(radius+.72)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(inside,outside,8)
		var hit: Dictionary = space.intersect_ray(query)
		var collider: Node = hit.get("collider") as Node
		check("Sakura "+str(sign_value)+" outer safety railing still blocks passage",collider != null and str(collider.get_path()).contains("OverlookGuardrails"),str(collider.get_path()) if collider != null else "missing")

func check_seat(seat: StaticBody3D,index: int) -> void:
	var label: String = "%02d %s" % [index+1,str(world.get_path_to(seat))]
	var raw: Vector3 = seat.to_global(Vector3(0,0,-.95))
	var ground: Dictionary = Geo.ground_probe(player.get_world_3d().direct_space_state,raw.normalized(),radius)
	var safe: bool = not ground.is_empty()
	var point: Vector3 = Vector3.ZERO
	if safe:
		point = (ground.position as Vector3)+raw.normalized()*.035
		safe = capsule_clear(point)
	check("Dry, unobstructed standing space in front of "+label,safe)
	if not safe:
		return
	await approach(seat,point)
	world.call("update_nearest")
	benches.call("refresh_nearest")
	check("Approaching the front selects "+label,benches.get("nearest")==seat)
	if access_only:
		print("BENCH_ACCESS_CHECKED ",index+1,"/34 ",label)
		return
	press_e()
	# Input.parse_input_event can remain buffered until the next process frame;
	# two physics signals can occur before it flushes at the 120 Hz test rate.
	await wait_state("sitting",12)
	check("E begins sitting at "+label,str(benches.get("state"))=="sitting" and benches.get("active")==seat and player.is_resting,{"state":str(benches.get("state")),"clock":benches.get("clock"),"resting":player.is_resting})
	await wait_state("resting")
	check("Sit transition reaches a stable rest at "+label,str(benches.get("state"))=="resting" and player.is_resting)
	var resting_position: Vector3 = player.global_position
	player.test_direction = Vector2(1,-1).normalized()
	player.test_running = true
	var before_jumps: int = player.jump_count
	var jump_accepted: bool = player.request_jump()
	press_e(true)
	await tick(10)
	check("Rest blocks walking, running, jumping and held-E repeat at "+label,player.global_position.distance_to(resting_position)<.0001 and player.jump_count==before_jumps and not jump_accepted and str(benches.get("state"))=="resting")
	player.test_direction = Vector2.ZERO
	player.test_running = false
	press_e()
	await wait_state("standing",12)
	check("A fresh E starts standing at "+label,str(benches.get("state"))=="standing")
	await wait_state("idle")
	await tick(18)
	var local_exit: Vector3 = seat.to_local(player.global_position)
	check("Standing restores a clear grounded front exit at "+label,str(benches.get("state"))=="idle" and not player.is_resting and player.collision_mask==9 and player.is_on_floor() and local_exit.z<-.6 and capsule_clear(player.global_position),{"local_exit":vec(local_exit),"on_floor":player.is_on_floor(),"mask":player.collision_mask})
	print("BENCH_CHECKED ",index+1,"/34 ",label)

func check_safety_gates(seat: StaticBody3D) -> void:
	var rear: Vector3 = seat.to_global(Vector3(0,0,.9))
	var rear_ground: Dictionary = player.ground_at(rear.normalized())
	if not rear_ground.is_empty():
		await approach(seat,(rear_ground.position as Vector3)+rear.normalized()*.04)
		check("A bench cannot be activated through its backrest",not bool(benches.call("can_approach",seat)) and benches.get("nearest")!=seat)
	var target: Dictionary = benches.call("safe_stand",seat) as Dictionary
	check("Safety-test bench has a clear baseline exit",not target.is_empty())
	if target.is_empty():
		return
	var start: Vector3 = target.point
	await approach(seat,start)
	# Positive control: a temporary solid obstacle blocks the whole front, so
	# clearance and swept approach tests must reject what they previously allowed.
	var blocker: StaticBody3D = StaticBody3D.new()
	blocker.name = "BenchChecksTemporaryBlocker"
	blocker.collision_layer = 8
	blocker.collision_mask = 0
	var shape_node: CollisionShape3D = CollisionShape3D.new()
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = Vector3(2.4,2.1,1.65)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	world.add_child(blocker)
	blocker.global_transform = seat.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.0,-1.18))
	await tick(2)
	check("An actual collider prevents unsafe front activation",(benches.call("safe_stand",seat) as Dictionary).is_empty() and not bool(benches.call("can_approach",seat)))
	blocker.queue_free()
	await tick(3)
	await approach(seat,start)
	for mode: String in ["overview","paused","destinations","airborne"]:
		if mode=="overview":
			world.call("set_overview",true)
		elif mode=="paused":
			world.call("pause_world")
		elif mode=="destinations":
			((world.get("hud") as CanvasLayer).get("destination_toggle") as Button).pressed.emit()
		else:
			player.jump_state = &"airborne"
		benches.call("refresh_nearest")
		check("Bench activation is gated while "+mode,not bool(benches.call("interact")) and str(benches.get("state"))=="idle")
		if mode=="overview":
			world.call("set_overview",false)
			check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
		elif mode=="paused":
			world.call("resume_world",{})
		elif mode=="destinations":
			((world.get("hud") as CanvasLayer).get("destination_toggle") as Button).pressed.emit()
		else:
			player.reset_jump_motion()
		await approach(seat,start)

func check_ui_and_teleport(seat: StaticBody3D) -> void:
	var target: Dictionary = benches.call("safe_stand",seat) as Dictionary
	if target.is_empty():
		return
	await approach(seat,target.point)
	var rest_button: Button
	for node: Node in (world.get("hud") as CanvasLayer).find_children("*","Button",true,false):
		var button: Button = node as Button
		if button.text.contains("坐下休息"):
			rest_button = button
			break
	check("Nearby bench exposes a visible clickable sit button",rest_button != null and rest_button.is_visible_in_tree() and not rest_button.disabled)
	if rest_button != null:
		rest_button.pressed.emit()
	else:
		press_e()
	await wait_state("resting")
	check("Onscreen sit button invokes the same seated state",str(benches.get("state"))=="resting" and player.is_resting)
	var blocked_exit: StaticBody3D = StaticBody3D.new()
	blocked_exit.name = "BenchChecksTemporaryExitBlocker"
	blocked_exit.collision_layer = 8
	blocked_exit.collision_mask = 0
	var blocked_shape: CollisionShape3D = CollisionShape3D.new()
	var exit_box: BoxShape3D = BoxShape3D.new()
	exit_box.size = Vector3(2.4,2.1,1.65)
	blocked_shape.shape = exit_box
	blocked_exit.add_child(blocked_shape)
	world.add_child(blocked_exit)
	blocked_exit.global_transform = seat.global_transform*Transform3D(Basis.IDENTITY,Vector3(0,1.0,-1.18))
	await tick(2)
	var resting_position: Vector3 = player.global_position
	press_e()
	await tick(5)
	check("An occupied exit cannot move the seated player through an obstacle",str(benches.get("state"))=="resting" and player.global_position.distance_to(resting_position)<.0001 and player.is_resting)
	blocked_exit.queue_free()
	await tick(3)
	world.call("teleport_to","life")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await tick(30)
	check("Destination teleport clears rest and restores player collision",str(benches.get("state"))=="idle" and benches.get("active")==null and not player.is_resting and player.collision_mask==9 and player.is_on_floor())
	await approach(seat,target.point)
	press_e()
	await tick(8)
	check("Second teleport test starts during the sitting transition",str(benches.get("state"))=="sitting")
	world.call("visit_sakura")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await tick(30)
	check("Sakura travel cancels an unfinished sit safely",str(benches.get("state"))=="idle" and not player.is_resting and player.collision_mask==9 and player.is_on_floor())

func check_station_entry() -> void:
	player.allow_test_input = false
	world.call("teleport_to","counseling")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await tick(30)
	world.call("update_nearest")
	check("Existing station E remains available at arrival",str(world.get("nearest_id"))=="counseling")
	press_e()
	await tick(2)
	check("E still enters the intended station instead of a distant bench",bool(world.get("entering")) and player.entering and player.active_clip==&"JumpDown" and str(benches.get("state"))=="idle", {"world_entering":world.get("entering"), "player_entering":player.entering, "clip":str(player.active_clip), "bench_state":str(benches.get("state")), "entry_elapsed":world.get("entry_elapsed")})
	await tick(100)
	check("Station entry emits exactly the original destination request",portal_requests==["counseling"],portal_requests)
	world.call("resume_world",{})
	await tick(30)
	check("Station return restores ordinary player movement",not player.entering and not player.is_resting and player.controls_enabled and player.collision_mask==9)

func approach(seat: StaticBody3D,point: Vector3) -> void:
	player.test_direction = Vector2.ZERO
	player.test_running = false
	player.teleport(point.normalized(),point.length()+.10)
	player.heading = (seat.global_position-point).slide(point.normalized()).normalized()
	if player.heading.length_squared()<.5:
		player.heading = -seat.global_basis.z
	player.global_basis = Basis(player.heading.cross(point.normalized()).normalized(),point.normalized(),-player.heading)
	await tick(25)
	world.call("update_nearest")
	benches.call("refresh_nearest")
	await tick(2)

func capsule_clear(point: Vector3) -> bool:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = .27
	shape.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Geo.frame(point.normalized()),point+point.normalized()*.82)
	query.collision_mask = 8
	query.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty()

func press_e(echo: bool = false) -> void:
	if not echo:
		var release: InputEventKey = InputEventKey.new()
		release.physical_keycode = KEY_E
		release.keycode = KEY_E
		release.pressed = false
		Input.parse_input_event(release)
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_E
	event.keycode = KEY_E
	event.pressed = true
	event.echo = echo
	Input.parse_input_event(event)
	# Headless runs may execute several physics ticks before their next render
	# input flush. Dispatch this synthetic key before asserting a two-tick state.
	Input.flush_buffered_events()

func wait_state(expected: String,max_frames: int = 125) -> void:
	for frame: int in range(max_frames):
		if str(benches.get("state"))==expected:
			return
		await physics_frame

func tick(count: int) -> void:
	for frame: int in range(count):
		await physics_frame

func on_portal(station: String,_return_token: Dictionary) -> void:
	portal_requests.append(station)

func vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func bench_district(seat: StaticBody3D) -> String:
	# Static seat bodies are permanent and flattened by the offline builder.
	# Keep the original seven-area coverage assertion using their authored key
	# or preserved source-path name, instead of assuming the old node hierarchy.
	var visual_key: String = str(seat.get_meta("camera_visual_group", ""))
	var path: String = str(world.get_path_to(seat))
	if visual_key.contains("/SakuraGrove/") or path.contains("SakuraGrove"):
		return "sakura"
	for district: String in ["counseling", "admissions", "recommendations", "universities", "life", "wordking"]:
		if visual_key.begins_with(district + "/") or str(seat.name).begins_with(district + "_") or path.begins_with("Neighborhood/" + district + "/"):
			return district
	return "unidentified"

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var destination: String = OUTPUT.replace("checks.json","access-checks.json") if access_only else OUTPUT
	if not seat_filter.is_empty():
		destination = OUTPUT.replace("checks.json","focused-checks.json")
	var file: FileAccess = FileAccess.open(destination,FileAccess.WRITE)
	var notes: String = "Real generated world and player physics; all 34 bench approaches and both Sakura full-capsule entrances."
	if not access_only:
		if seat_filter.is_empty():
			notes += " All 34 E sit/stand cycles; a temporary blocker is used only as a collision positive control, never to alter the authored accessibility checks."
		else:
			notes = "Focused E sit/stand cycles for benches whose path contains '"+seat_filter+"', plus complete registry counts and both Sakura entrance/guard checks."
	file.store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks,"inventory":inventory,"access_only":access_only,"seat_filter":seat_filter,"notes":notes},"\t"))
	file.close()
	print("BENCH_INTERACTION_CHECKS checks=",checks.size()," failures=",failures," seats=",inventory.size())
	if is_instance_valid(world):
		world.free()
	world = null
	player = null
	benches = null
	quit(1 if failures>0 else 0)
