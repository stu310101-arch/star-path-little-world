extends "res://tests/check_counseling_room.gd"
## Focused furniture acceptance. Uses the production room, input handlers,
## collision shapes and modal, with an in-memory account fixture only.
var seats: Node
var movement_samples: Array[Dictionary] = []

func coordinate(value: Variant) -> Vector3:
	return value as Vector3 if value is Vector3 else vector(value as Array)

func tap_key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	await tick(1)
	event = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = false
	Input.parse_input_event(event)
	await tick(2)

func hold(action: String, frames: int) -> float:
	var started: int = Engine.get_physics_frames()
	Input.action_press(action)
	await tick(frames)
	Input.action_release(action)
	return float(Engine.get_physics_frames()-started)*Engine.time_scale/float(Engine.physics_ticks_per_second)

func target_by_id(id: String) -> Dictionary:
	for target: Dictionary in seats.get("targets"):
		if str(target.id) == id:
			return target
	return {}

func snapshot_chair(target: Dictionary) -> Dictionary:
	var body: Node3D = room.get_node_or_null(NodePath(str(target.collider_id))) as Node3D
	var visual: Node3D = (room.get("room_model") as Node3D).find_child(str(target.visual_node),true,false) as Node3D
	return {"actor":player.global_position,"collider":body.global_position,"visual":visual.global_position,
		"seat":coordinate(target.seat_point),"stand":coordinate(target.stand_point),"point":coordinate(target.point)}

func chair_collider_clear(target: Dictionary) -> bool:
	var body: CollisionObject3D = room.get_node(NodePath(str(target.collider_id))) as CollisionObject3D
	var shape: CollisionShape3D = body.get_child(0) as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape.shape
	query.transform = shape.global_transform
	query.collision_mask = int(seats.get("saved_mask"))
	query.exclude = [body.get_rid(),player.get_rid(),(room.get_node("Floor") as CollisionObject3D).get_rid()]
	var hits: Array[Dictionary] = room.get_world_3d().direct_space_state.intersect_shape(query,8)
	for hit: Dictionary in hits:
		print("CHAIR_PROBE_CONTACT ",target.id," ",(hit.collider as Node).name," transform=",shape.global_transform)
	return hits.is_empty()

func exercise_movement(id: String) -> void:
	room.set("camera_yaw",0.0)
	room.call("update_camera",0.0,true)
	var target: Dictionary = seats.get("active")
	var before: Dictionary = snapshot_chair(target)
	var elapsed: float = await hold("move_back",18)
	var after: Dictionary = snapshot_chair(seats.get("active"))
	var delta: Vector3 = after.actor-before.actor
	var speed: float = delta.length()/elapsed
	var synchronized: bool = true
	for key: String in ["collider","visual","seat","stand","point"]:
		synchronized = synchronized and ((after[key] as Vector3)-(before[key] as Vector3)).is_equal_approx(delta)
	var cached: Dictionary = target_by_id(id)
	synchronized = synchronized and coordinate(cached.seat_point).is_equal_approx(after.seat) and coordinate(cached.point).is_equal_approx(after.point)
	check(id+": WASD moves actor, chair mesh, collision and both live anchors together",synchronized and delta.z>.35,{"delta":delta,"elapsed_s":elapsed})
	check(id+": seated speed is 2.6 m/s and below ordinary walking",absf(speed-2.6)<.35 and speed<float(player.get("walk_speed")),{"measured_m_s":speed,"walking_m_s":player.get("walk_speed")})
	var side_before: Vector3 = player.global_position
	await hold("move_right",8)
	var side_after: Vector3 = player.global_position
	await hold("move_left",8)
	check(id+": A and D translate the chair in opposite directions",side_after.x-side_before.x>.15 and player.global_position.x<side_after.x-.15)
	var towards_desk: Vector3 = player.global_position
	await hold("move_forward",90)
	var stopped: Vector3 = player.global_position
	await hold("move_forward",18)
	check(id+": W stops against the real desk without penetration",towards_desk.z-stopped.z>.35 and stopped.distance_to(player.global_position)<.02 and chair_collider_clear(seats.get("active")),{"start":towards_desk,"stopped":stopped,"after_more_input":player.global_position})
	if id=="interest_high1_chair":
		await hold("move_back",180)
		var wall_stop: Vector3 = player.global_position
		await hold("move_back",18)
		check(id+": room boundary blocks seated movement without penetration",wall_stop.z>3.5 and wall_stop.distance_to(player.global_position)<.02 and chair_collider_clear(seats.get("active")),{"stopped":wall_stop,"after_more_input":player.global_position})
		await hold("move_forward",180)
	movement_samples.append({"chair":id,"measured_speed_m_s":speed,"walking_speed_m_s":player.get("walk_speed"),"synchronized":synchronized,"desk_stop":str(stopped)})

func exercise_grade(view: String, tab: int, at: Vector3) -> void:
	await walk_to(at)
	await tick(15)
	room.call("refresh_nearest")
	var nearby: Dictionary = room.get("nearest")
	check(view+": real approach selects its wooden chair",str(nearby.get("kind",""))=="seat" and str(nearby.get("station_view",""))==view,nearby.get("id"))
	await tap_key(KEY_E)
	await tick(76)
	check(view+": E sits and associates the correct grade",bool(seats.call("is_seated")) and str(seats.call("associated_view"))==view)
	if not bool(seats.call("is_seated")):
		return
	await capture(view+"-seated")
	await exercise_movement(str((seats.get("active") as Dictionary).id))
	await tick(30)
	Input.action_press("move_back")
	await tap_key(KEY_F)
	var panel: Control = room.get("interest_panel") as Control
	check(view+": F opens the real Godot form on the correct grade",is_instance_valid(panel) and panel.visible and (panel.get("tabs") as TabContainer).current_tab==tab)
	if is_instance_valid(panel):
		check(view+": opening form releases held movement",not Input.is_action_pressed("move_back") and player.process_mode==Node.PROCESS_MODE_DISABLED)
		var frozen: Dictionary = snapshot_chair(seats.get("active"))
		var camera_before: Transform3D = camera.global_transform
		await hold("move_back",12)
		room.call("touch_look",Vector2(100,90))
		var now: Dictionary = snapshot_chair(seats.get("active"))
		var unchanged: bool = true
		for key: String in frozen:
			unchanged = unchanged and (frozen[key] as Vector3).is_equal_approx(now[key])
		check(view+": modal freezes chair, actor, anchors and camera",unchanged and camera.global_transform.is_equal_approx(camera_before))
		await capture(view+"-form")
		panel.call("request_close")
		await tick(3)
		check(view+": closing form preserves seated position and controls",not bool(room.call("_modal_open")) and bool(seats.call("is_seated")) and not bool(player.get("controls_enabled")) and player.global_position.is_equal_approx(frozen.actor))
	var stand: Vector3 = coordinate((seats.get("active") as Dictionary).stand_point)
	await tap_key(KEY_E)
	await tick(70)
	check(view+": E stands at the moved chair and restores ordinary controls",not bool(seats.call("is_active")) and bool(player.get("controls_enabled")) and player.global_position.distance_to(stand)<.7 and bool(seats.call("_capsule_clear",player.global_position)),player.global_position)
	var standing: Vector3 = player.global_position
	await hold("move_back",8)
	check(view+": ordinary walking works after standing",player.global_position.distance_to(standing)>.2)
	restore_camera()

func room_overview() -> void:
	var original: Transform3D = camera.global_transform
	var original_fov: float = camera.fov
	room.set_process(false)
	player.hide()
	(room.get("ui_root") as Control).hide()
	camera.global_position = Vector3(0,3.12,3.85)
	camera.look_at(Vector3(0,1.0,-1.65),Vector3.UP)
	camera.fov = 78.0
	await capture("studio-overview")
	camera.global_position = Vector3(-1.65,2.55,3.45)
	camera.look_at(Vector3(-4.35,.68,.9),Vector3.UP)
	camera.fov = 62.0
	await capture("sofa-table-floor")
	camera.global_transform = original
	camera.fov = original_fov
	player.show()
	(room.get("ui_root") as Control).show()
	room.set_process(true)

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	output_directory = "res://../deliverables/counseling-room/r8/"
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
	room.connect("request_return_to_world",func() -> void: returns+=1)
	check("Production room and character are ready",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	await tick(20)
	player = room.get("player") as CharacterBody3D
	camera = room.get("camera") as Camera3D
	seats = room.get("seats") as Node
	layout = room.get("layout") as Dictionary
	spawn = vector(layout.spawn.position)
	facing = vector(layout.spawn.facing)
	initial_camera = {"yaw":room.get("camera_yaw"),"pitch":room.get("camera_pitch"),"distance":room.get("camera_distance")}
	for station: Dictionary in layout.stations:
		if station.view=="interest_high1": high1=vector(station.approach)
		elif station.view=="interest_high3": high3=vector(station.approach)
	check("Imported room is r8",str(layout.revision).ends_with("r8"),layout.revision)
	check("Four seat anchors contain two movable wooden chairs",(seats.get("targets") as Array).size()==4 and (seats.get("targets") as Array).filter(func(t:Dictionary)->bool:return bool(t.get("movable",false))).size()==2)
	check("Entrance actor is standing on the floor",player.is_on_floor() and absf(player.global_position.y)<.15)
	await capture("entrance")
	await room_overview()
	await exercise_grade("interest_high1",0,high1)
	await exercise_grade("interest_high3",1,high3)
	for target: Dictionary in seats.get("targets"):
		if bool(target.get("movable",false)):
			continue
		player.call("place_at",target.point as Vector3,facing)
		restore_camera()
		await tick(10)
		room.call("refresh_nearest")
		await capture(str(target.id)+"-corner")
		await tap_key(KEY_E)
		await tick(76)
		check(str(target.id)+": E sits on the repositioned sofa",bool(seats.call("is_seated")))
		var before: Vector3 = player.global_position
		await hold("move_right",12)
		check(str(target.id)+": sofa remains stationary under WASD",player.global_position.is_equal_approx(before))
		await capture(str(target.id)+"-seated")
		await tap_key(KEY_E)
		await tick(70)
		check(str(target.id)+": E restores safe standing",not bool(seats.call("is_active")) and bool(player.get("controls_enabled")) and bool(seats.call("_capsule_clear",player.global_position)))
	# A small real lens-volume sweep catches the changed furniture clipping.
	var probe := SphereShape3D.new()
	probe.radius = .17
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = probe
	query.collision_mask = 257
	query.exclude = [player.get_rid()]
	var blocked: int = 0
	var sample_count: int = 0
	for at: Vector3 in [spawn,high1,high3,Vector3(-3.77,.06,.94)]:
		player.call("place_at",at,facing)
		await tick(2)
		for yaw: float in [0.0,PI*.5,PI,PI*1.5]:
			room.set("camera_yaw",yaw)
			room.set("camera_pitch",.28)
			room.call("update_camera",0.0,true)
			query.transform = Transform3D(Basis.IDENTITY,camera.global_position)
			if not room.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): blocked+=1
			sample_count+=1
	check("Changed furniture does not penetrate the camera lens probe",blocked==0,{"blocked":blocked,"samples":sample_count})
	player.call("place_at",spawn,facing)
	restore_camera()
	await walk_to(vector(layout.exit.position))
	room.call("refresh_nearest")
	await tap_key(KEY_E)
	check("E at exit emits the return transition and stops controls",returns==1 and not bool(player.get("controls_enabled")))
	var report: Dictionary = {"revision":layout.revision,"failures":failures,"checks":checks,"movement":movement_samples,"physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"captures":captures,"scope":"Brief native acceptance of changed furniture, real keyboard seat/workbench/stand interactions, slower movable chairs, desk/wall collision, modal pause and return. Speed uses elapsed simulation physics ticks; chair penetration probe excludes intentional floor contact. In-memory account fixture only; no account/network, browser, phone or sustained performance acceptance."}
	FileAccess.open(output_directory+"native-brief-checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t")+"\n")
	print("COUNSELING_R8_BRIEF checks=",checks.size()," failures=",failures)
	quit(1 if failures else 0)
