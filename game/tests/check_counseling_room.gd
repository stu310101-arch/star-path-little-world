extends SceneTree

const Room = preload("res://scripts/counseling_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const VisualFixture = preload("res://tests/interest_visual_review.gd")
var output_directory: String = "res://../deliverables/counseling-room/r8/"
var room: Node3D
var player: CharacterBody3D
var camera: Camera3D
var checks: Array[Dictionary] = []
var failures: int = 0
var captures: bool = false
var returns: int = 0
var layout: Dictionary
var spawn: Vector3
var facing: Vector3
var high1: Vector3
var high3: Vector3
var initial_camera: Dictionary

func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func restore_camera() -> void:
	room.set("camera_yaw",initial_camera.yaw)
	room.set("camera_pitch",initial_camera.pitch)
	room.set("camera_distance",initial_camera.distance)
	room.call("update_camera",0.0,true)

func performance_sample() -> Dictionary:
	player.call("place_at",spawn,facing)
	restore_camera()
	await tick(15)
	var frame_ms: Array[float] = []
	var draws: Array[int] = []
	var primitives: Array[int] = []
	var process_ms: Array[float] = []
	var start: int = Time.get_ticks_usec()
	var previous: int = start
	var aisle: Vector3 = (high1+high3)*.5
	var destination: Vector3 = aisle
	var travelled: float = 0.0
	var previous_position: Vector3 = player.global_position
	player.set("allow_test_input",true)
	while Time.get_ticks_usec()-start < 20000000:
		if (player.global_position-destination).slide(Vector3.UP).length()<.2:
			destination = spawn if destination==aisle else aisle
		var direction: Vector3 = (destination-player.global_position).slide(Vector3.UP).normalized()
		player.set("test_direction",Vector2(direction.dot(player.global_basis.x),-direction.dot(player.get("heading") as Vector3)))
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_ms.append(float(now-previous)/1000.0)
		previous=now
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		primitives.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)))
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS)*1000.0)
		travelled += player.global_position.distance_to(previous_position)
		previous_position=player.global_position
	player.set("allow_test_input",false)
	player.set("test_direction",Vector2.ZERO)
	frame_ms.sort(); draws.sort(); primitives.sort(); process_ms.sort()
	var seconds: float = float(Time.get_ticks_usec()-start)/1000000.0
	var report: Dictionary = {"seconds":seconds,"frames":frame_ms.size(),"average_fps":float(frame_ms.size())/seconds,
		"revision":layout.revision,
		"frame_ms_median":frame_ms[frame_ms.size()/2],"frame_ms_p95":frame_ms[int(frame_ms.size()*.95)],"frame_ms_max":frame_ms.back(),
		"cpu_process_ms_median":process_ms[process_ms.size()/2],"draw_calls_median":draws[draws.size()/2],
		"primitives_median":primitives[primitives.size()/2],"distance_m":travelled,"fps_cap":Engine.max_fps,
		"size":str(root.size),"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),
		"scope":"Native desktop GPU, 20 seconds continuous real physics movement; not phone, browser or minimum hardware evidence."}
	FileAccess.open(output_directory+"native-performance.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUNSELING_ROOM_PERFORMANCE ",JSON.stringify(report))
	return report

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":str(evidence)})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame
		await process_frame

func capture(label: String) -> void:
	if not captures:
		return
	await tick(3)
	await RenderingServer.frame_post_draw
	check("Native capture " + label, root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_directory + label + ".png")) == OK)

func walk_to(target: Vector3) -> void:
	player.set("allow_test_input", true)
	var deadline: int = Time.get_ticks_msec() + 8000
	while player.global_position.distance_to(target) > .16 and Time.get_ticks_msec() < deadline:
		var desired: Vector3 = (target - player.global_position).slide(Vector3.UP).normalized()
		var heading: Vector3 = player.get("heading") as Vector3
		player.set("test_direction", Vector2(desired.dot(player.global_basis.x), -desired.dot(heading)))
		await tick(1)
	player.set("test_direction", Vector2.ZERO)
	player.set("allow_test_input", false)
	await tick(3)
	check("Continuous physics walk to " + str(target), player.global_position.distance_to(target) < .22, player.global_position)

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--output-directory"):
		output_directory = arguments[arguments.find("--output-directory")+1].trim_suffix("/")+"/"
	captures = arguments.has("--capture") and DisplayServer.get_name()!="headless"
	Engine.max_fps = 60
	root.size = Vector2i(1440,900)
	root.set_meta("graphics_quality_profile","standard")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	var account: Node = VisualFixture.Service.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	room = Room.new()
	root.add_child(room)
	current_scene = room
	room.connect("request_return_to_world", func() -> void: returns += 1)
	check("Real avatar and authored model become ready", await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	await tick(20)
	player = room.get("player") as CharacterBody3D
	camera = room.get("camera") as Camera3D
	layout = room.get("layout") as Dictionary
	spawn = vector(layout.spawn.position)
	facing = vector(layout.spawn.get("facing",[0,0,-1]))
	initial_camera = {"yaw":room.get("camera_yaw"),"pitch":room.get("camera_pitch"),"distance":room.get("camera_distance")}
	for station: Dictionary in layout.stations:
		if station.view=="interest_high1": high1=vector(station.approach)
		elif station.view=="interest_high3": high3=vector(station.approach)
	check("Player is on floor", player.is_on_floor() and absf(player.global_position.y)<.15, player.global_position)
	check("Room only uses the authored full-detail asset", str(room.MODEL_PATH).contains("assets/counseling_room/") and not str(room.MODEL_PATH).contains("/low/"))
	var art: Node3D = room.get("room_model") as Node3D
	var meshes: Array[Node] = art.find_children("*","MeshInstance3D",true,false)
	var triangles: int = 0
	var textured: int = 0
	var normal_mapped: int = 0
	for node: Node in meshes:
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array = mesh.surface_get_arrays(surface)
			triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
			var mat: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if mat != null:
				if mat.albedo_texture != null: textured += 1
				if mat.normal_enabled and mat.normal_texture != null: normal_mapped += 1
	check("Imported geometry stays within the room triangle budget",meshes.size()>0 and triangles>0 and triangles<180000,{"meshes":meshes.size(),"triangles":triangles,"scope":"Technical budget only; visual quality requires rendered review."})
	check("PBR color and normal maps reached Godot",textured>0 and normal_mapped>0,{"textured":textured,"normal_mapped":normal_mapped,"scope":"Canonical map assignments and dimensions are checked separately."})
	var station_rows: Array = (room.get("layout") as Dictionary).get("stations",[])
	check("Exactly two grade assessment stations and no divided interest exhibits",station_rows.size()==3 and str(station_rows[0].view)=="interest_high1" and str(station_rows[1].view)=="interest_high3" and (room.get("layout") as Dictionary).get("displays",[]).is_empty())
	await capture("entrance")
	if captures:
		var original_view: Transform3D = camera.global_transform
		var original_fov: float = camera.fov
		room.set_process(false)
		player.hide()
		(room.get("ui_root") as Control).hide()
		var minimum: Vector3 = vector(layout.bounds.min)
		var maximum: Vector3 = vector(layout.bounds.max)
		camera.global_position=Vector3((minimum.x+maximum.x)*.5,maximum.y-.38,maximum.z-.45)
		var look_target: Vector3 = (high1+high3)*.5
		var screen_midpoint: Vector3 = Vector3.ZERO
		var screen_count: int = 0
		for station: Dictionary in layout.stations:
			if station.get("screen") is Dictionary:
				screen_midpoint+=vector(station.screen.center)
				screen_count+=1
		if screen_count>0:look_target=look_target.lerp(screen_midpoint/float(screen_count),.5)
		look_target.x=(minimum.x+maximum.x)*.5
		look_target.y=1.0
		camera.look_at(look_target,Vector3.UP)
		camera.fov=78.0
		check("Overview camera stays inside the actual walls and ceiling",AABB(minimum,maximum-minimum).has_point(camera.global_position),camera.global_position)
		await capture("studio-overview")
		camera.global_transform=original_view
		camera.fov=original_fov
		player.show()
		(room.get("ui_root") as Control).show()
		room.set_process(true)
	if OS.get_cmdline_user_args().has("--overview-only"):
		quit(0)
		return
	await walk_to(high1)
	# Let the follow camera finish its normal movement easing before comparing
	# modal preservation; the form must preserve a settled viewpoint.
	await tick(45)
	room.call("refresh_nearest")
	check("Grade-one terminal has a nearby interest interaction",str((room.get("nearest") as Dictionary).get("view",""))=="interest_high1")
	if OS.get_cmdline_user_args().has("--modal"):
		var before: Transform3D = player.global_transform
		var original_camera: Transform3D = camera.global_transform
		Input.action_press("move_forward")
		var event: InputEventKey = InputEventKey.new()
		event.physical_keycode=KEY_E
		event.keycode=KEY_E
		event.pressed=true
		Input.parse_input_event(event)
		await tick(3)
		var panel: Control = room.get("interest_panel") as Control
		check("E at terminal opens the real Godot form",is_instance_valid(panel) and panel.visible)
		if is_instance_valid(panel):
			check("Grade-one device opens its RIASEC page",(panel.get("tabs") as TabContainer).current_tab==0)
			check("Form freezes actor and clears held movement",player.process_mode==Node.PROCESS_MODE_DISABLED and not Input.is_action_pressed("move_forward") and not bool(player.get("controls_enabled")))
			room.call("touch_look",Vector2(100,90))
			await tick(3)
			check("Modal keeps original camera and actor fixed",player.global_transform.is_equal_approx(before) and camera.global_transform.is_equal_approx(original_camera),{"camera_before":original_camera,"camera_now":camera.global_transform,"actor_before":before,"actor_now":player.global_transform})
			panel.call("request_close")
			await tick(3)
			check("Clean close restores controls and exact actor position",not bool(room.call("_modal_open")) and bool(player.get("controls_enabled")) and player.global_transform.is_equal_approx(before))
			check("Clean close restores the original camera",camera.global_transform.is_equal_approx(original_camera))
	restore_camera()
	await capture("interest-terminal")
	await walk_to(high3)
	await tick(45)
	room.call("refresh_nearest")
	check("Grade-three cabinet has its own assessment interaction",str((room.get("nearest") as Dictionary).get("view",""))=="interest_high3")
	await capture("grade-three-terminal")
	if OS.get_cmdline_user_args().has("--modal"):
		room.call("activate_nearest")
		await tick(3)
		var high3_panel: Control = room.get("interest_panel") as Control
		check("Grade-three device opens its knowledge page",is_instance_valid(high3_panel) and (high3_panel.get("tabs") as TabContainer).current_tab==1)
		if is_instance_valid(high3_panel):
			high3_panel.call("request_close")
			await tick(3)
	# Sample lens volumes around the real standing actor at three room locations.
	var probe: SphereShape3D = SphereShape3D.new()
	probe.radius=.17
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape=probe
	query.collision_mask=257
	query.exclude=[player.get_rid()]
	var blocked: int = 0
	var sample_count: int = 0
	for at: Vector3 in [high1,spawn,high3]:
		player.call("place_at",at,facing)
		await tick(2)
		for pitch: float in [.02,.28,.55]:
			for yaw_index: int in range(24):
				room.set("camera_pitch",pitch)
				room.set("camera_yaw",float(yaw_index)*TAU/24)
				room.call("update_camera",0.0,true)
				query.transform=Transform3D(Basis.IDENTITY,camera.global_position)
				if not room.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():blocked+=1
				sample_count+=1
	check("Camera sphere stays out of room collision geometry",blocked==0,{"blocked":blocked,"samples":sample_count})
	var seats: Node = room.get("seats") as Node
	var targets: Array = seats.get("targets") as Array
	check("One shared sofa has two usable seat anchors",targets.size()==2)
	for target: Dictionary in targets:
		var seat_facing: Vector3 = Vector3.FORWARD.rotated(Vector3.UP,float(target.facing))
		player.call("place_at",target.point as Vector3,seat_facing)
		restore_camera()
		await tick(3)
		if target==targets[0]:await capture("consultation-corner")
		seats.call("interact",target)
		await tick(76)
		check("Sit on " + str(target.id),bool(seats.call("is_seated")))
		if target==targets[0]:await capture("consultation-seated")
		seats.call("interact",target)
		await tick(70)
		check("Safe stand from " + str(target.id),not bool(seats.call("is_active")) and bool(player.get("controls_enabled")))
	player.call("place_at",spawn,facing)
	restore_camera()
	if OS.get_cmdline_user_args().has("--perf"):
		var performance: Dictionary = await performance_sample()
		check("20-second native performance sample contains actual continuous movement",float(performance.seconds)>=20.0 and float(performance.distance_m)>30)
		player.call("place_at",spawn,facing)
		restore_camera()
	root.content_scale_size=Vector2i(960,600)
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size=Vector2i(390,844)
	room.set_meta("force_touch_controls",true)
	room.call("_resize_hud")
	await tick(4)
	await capture("mobile-390x844")
	room.call("_return_immediately")
	check("Return uses transition signal",returns==1)
	check("Return disables actor movement",not bool(player.get("controls_enabled")))
	var report: Dictionary = {"revision":layout.revision,"failures":failures,"checks":checks,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"triangles":triangles,"captures":captures,"scope":"Production avatar, modal, seats, lens collision and renderer. The separate direct-routes fixture forbids corrective detours. Triangle and material counts are technical checks, not visual-quality evidence."}
	FileAccess.open(output_directory+("headless-checks.json" if DisplayServer.get_name()=="headless" else "native-checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUNSELING_ROOM_CHECKS ",checks.size()," failures=",failures)
	quit(1 if failures else 0)
