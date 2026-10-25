extends SceneTree
## Production room geometry, direct physics routes, lens clearance and return state.
## No signed-in account or private records are accessed by this fixture.
const Room = preload("res://scripts/recommendation_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
class OfflineAccount:
	extends Node
	signal state_changed(user: Dictionary)
	signal recommendation_message(packet: Dictionary)
	signal interest_message(packet: Dictionary)
	signal progress_message(packet: Dictionary)
	signal closed
	var user: Dictionary = {"profileReady":false,"signedIn":false,"sessionGeneration":0}
	func request_recommendation(_command: Dictionary) -> bool:
		return false
	func request_progress(_command: Dictionary) -> bool:
		return false
var room: Node3D
var player: CharacterBody3D
var camera: Camera3D
var checks: Array[Dictionary] = []
var failures: int = 0
var captures: bool = false
var output: String
var returned: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	print("RECOMMENDATION_ROOM_CHECK ",label," ",passed)
	if not passed:
		failures += 1
		push_error(label+": "+str(evidence))

func tick(count: int = 1) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame

func press_key(code: Key) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	Input.parse_input_event(event)
	await tick(2)
	event=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=false
	Input.parse_input_event(event)
	await tick(4)

func vector(value: Variant) -> Vector3:
	return value as Vector3 if value is Vector3 else Vector3(float(value[0]),float(value[1]),float(value[2]))

func capture(name: String) -> void:
	if not captures:
		return
	await tick(3)
	await RenderingServer.frame_post_draw
	check("Native capture "+name,root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+name+".png"))==OK)

func direct_walk(label: String, start: Vector3, destination: Vector3, expected: String = "") -> void:
	player.call("place_at",start,Vector3.FORWARD)
	await tick(8)
	var origin: Vector3 = player.position
	var direction: Vector3 = (destination-origin).slide(Vector3.UP).normalized()
	var expected_length: float = (destination-origin).slide(Vector3.UP).length()
	var travelled: float = 0.0
	var deviation: float = 0.0
	var previous: Vector3 = origin
	var contacts: Array[String] = []
	player.set("allow_test_input",true)
	player.set("test_direction",Vector2(direction.dot(player.global_basis.x),-direction.dot(player.get("heading") as Vector3)))
	for index: int in range(ceili((expected_length/float(player.get("walk_speed"))+1.5)*60)):
		await tick()
		travelled += (player.position-previous).slide(Vector3.UP).length()
		previous=player.position
		var distance: Vector3 = (player.position-origin).slide(Vector3.UP)
		deviation=maxf(deviation,(distance-direction*distance.dot(direction)).length())
		for collision_index: int in range(player.get_slide_collision_count()):
			var hit: KinematicCollision3D = player.get_slide_collision(collision_index)
			if absf(hit.get_normal().dot(Vector3.UP))<.55:
				contacts.append(str((hit.get_collider() as Node).name))
		if not contacts.is_empty() or (player.position-destination).slide(Vector3.UP).length()<.12:
			break
	player.set("test_direction",Vector2.ZERO)
	player.set("allow_test_input",false)
	await tick(3)
	var error: float = (player.position-destination).slide(Vector3.UP).length()
	check(label+" reaches directly",error<.20 and contacts.is_empty(),{"error":error,"contacts":contacts})
	check(label+" does not detour",deviation<.12 and travelled<expected_length+.20,{"deviation":deviation,"distance":travelled})
	room.call("refresh_nearest")
	if not expected.is_empty():
		check(label+" reaches correct station",str((room.get("nearest") as Dictionary).get("view",""))==expected)

func run() -> void:
	var low: bool = OS.get_cmdline_user_args().has("--resources=low")
	captures=OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name()!="headless"
	output="res://../deliverables/recommendation-room/"+("low/" if low else "full/")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	Engine.max_fps=60
	root.size=Vector2i(1440,900)
	root.set_meta("graphics_quality_profile","low" if low else "standard")
	var service:=OfflineAccount.new()
	service.name="StarPathAccount"
	root.add_child(service)
	room=Room.new()
	room.connect("request_return_to_world",func() -> void: returned+=1)
	root.add_child(room)
	current_scene=room
	check("Production room and avatar become ready",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		finish(low)
		return
	player=room.get("player") as CharacterBody3D
	camera=room.get("camera") as Camera3D
	var layout: Dictionary = room.get("layout") as Dictionary
	var spawn: Vector3 = vector(layout.spawn.position)
	check("Three workstations plus exit",(room.get("stations") as Array).size()==4)
	check("Three work chairs and two fixed quiet seats",(layout.interactables as Array).size()==5)
	var work_views: Array[String] = []
	for seat: Dictionary in layout.interactables:
		if not str(seat.get("station_view","")).is_empty():work_views.append(str(seat.station_view))
	work_views.sort()
	check("Each workstation owns one sittable chair",work_views==["compare","data","recommendations"])
	check("Correct resource profile path",str(room.get("model_path")).contains("generated/low/")==low)
	var triangles: int = 0
	var texture_paths: Array[String] = []
	for node: Node in (room.get("room_model") as Node3D).find_children("*","MeshInstance3D",true,false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for surface: int in range(mesh.get_surface_count()):
			triangles += (mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
			var mat: StandardMaterial3D = mesh.surface_get_material(surface) as StandardMaterial3D
			if mat != null and mat.albedo_texture != null and mat.albedo_texture.resource_path not in texture_paths:
				texture_paths.append(mat.albedo_texture.resource_path)
	check("Imported mesh budget",triangles>0 and triangles<=(60000 if low else 180000),triangles)
	var canonical: bool = texture_paths.size()==2
	var prefix: String = "res://generated/low/recommendation/textures/" if low else "res://assets/recommendation_room/textures/"
	for path: String in texture_paths:
		canonical = canonical and path.begins_with(prefix)
	check("Only canonical profile textures are runtime dependencies",canonical,texture_paths)
	await tick(8)
	await capture("entrance")
	(room.get("hud") as CanvasLayer).hide()
	var saved_process: bool = room.is_processing()
	room.set_process(false)
	camera.position=Vector3(0,3.12,4.55)
	camera.look_at(Vector3(0,1.0,-1.4))
	player.hide()
	await capture("overview")
	camera.position=Vector3(0,2.75,-.65)
	camera.look_at(Vector3(0,1.0,3.55))
	await capture("asymmetric-seating")
	player.show()
	room.set_process(saved_process)
	(room.get("hud") as CanvasLayer).show()
	for station: Dictionary in layout.stations:
		var approach: Vector3 = vector(station.approach)
		await direct_walk("spawn to "+str(station.view),spawn,approach,str(station.view))
		await direct_walk(str(station.view)+" to spawn",approach,spawn)
		if station.view!="exit":
			player.call("place_at",approach,Vector3.FORWARD)
			room.set("camera_yaw",0.0)
			room.set("camera_pitch",.3)
			room.call("update_camera",0.0,true)
			await capture(str(station.view)+"-workbench")
	# Every pair of station approaches stays reachable without a chair detour.
	for route: Array in [[0,1],[1,2],[2,0]]:
		var from: Dictionary=layout.stations[route[0]]
		var to: Dictionary=layout.stations[route[1]]
		await direct_walk(str(from.view)+" to "+str(to.view),vector(from.approach),vector(to.approach),str(to.view))
	var shape:=SphereShape3D.new()
	shape.radius=.17
	var query:=PhysicsShapeQueryParameters3D.new()
	query.shape=shape;query.collision_mask=257;query.exclude=[player.get_rid()]
	var blocked: int = 0
	var samples: int = 0
	for station: Dictionary in layout.stations:
		player.call("place_at",vector(station.approach),Vector3.FORWARD)
		await tick(2)
		for pitch: float in [.02,.28,.55]:
			for index: int in range(24):
				room.set("camera_yaw",float(index)*TAU/24)
				room.set("camera_pitch",pitch)
				room.call("update_camera",0.0,true)
				query.transform=Transform3D(Basis.IDENTITY,camera.position)
				if not room.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty():blocked+=1
				samples+=1
	check("Camera lens clears all station angles",blocked==0,{"blocked":blocked,"samples":samples})
	var seats: Node = room.get("seats") as Node
	for seat: Dictionary in seats.get("targets") as Array:
		var work_view: String=str(seat.get("station_view",""))
		if not work_view.is_empty():
			await direct_walk("spawn to "+str(seat.id),spawn,seat.point as Vector3)
		player.call("place_at",seat.point as Vector3,Vector3.FORWARD)
		room.set("camera_yaw",0.0);room.set("camera_pitch",.3)
		await tick(5)
		seats.call("interact",seat)
		await tick(76)
		check("Sit on "+str(seat.id),bool(seats.call("is_seated")))
		check("Seated pose faces authored direction "+str(seat.id),(seats.get("seat_basis") as Basis).z.dot(Vector3.FORWARD)>.99)
		await capture(str(seat.id)+"-seated")
		if not work_view.is_empty():
			var seated_position: Vector3=player.position
			check("Seated chair exposes associated workbench "+work_view,str(seats.call("associated_view"))==work_view and (room.get("seated_workbench_button") as Button).visible)
			await press_key(KEY_F)
			var work_panel: Control=room.get("recommendation_panel") as Control
			check("F opens matching workbench "+work_view,is_instance_valid(work_panel) and int(work_panel.get("page_index"))==int({"data":0,"recommendations":1,"compare":2}[work_view]) and bool(room.call("_modal_open")))
			check("Workbench modal preserves the seated position "+work_view,bool(seats.call("is_seated")) and player.position.distance_to(seated_position)<.01)
			if is_instance_valid(work_panel):work_panel.call("close_panel")
			await tick(5)
			check("Closing workbench returns to the same chair "+work_view,bool(seats.call("is_seated")) and not bool(room.call("_modal_open")) and not bool(player.get("controls_enabled")) and player.position.distance_to(seated_position)<.01)
			await press_key(KEY_E)
		else:
			seats.call("interact",seat)
		await tick(70)
		check("Stand safely from "+str(seat.id),not bool(seats.call("is_active")) and bool(player.get("controls_enabled")))
		if not work_view.is_empty():
			await direct_walk(str(seat.id)+" to spawn",player.position,spawn)
	for profile: String in ["low","mobile","balanced","standard"]:
		root.set_meta("graphics_quality_profile",profile)
		room.call("_apply_quality")
		for name: String in ["WindowDaylight","WestWindowBounce"]:
			check(profile+" shadow "+name,(room.get_node(name) as Light3D).shadow_enabled==(profile=="standard"))
	root.set_meta("graphics_quality_profile","low" if low else "standard")
	room.call("_apply_quality")
	player.call("place_at",spawn,Vector3.FORWARD)
	room.set("camera_yaw",.42)
	var state: Dictionary = room.call("capture_return_state") as Dictionary
	room.call("restore_return_state",state)
	check("Player position and camera round trip",player.position.distance_to(spawn)<.01 and is_equal_approx(float(room.get("camera_yaw")),.42))
	if OS.get_cmdline_user_args().has("--modal"):
		for tab: String in ["data","recommendations","compare"]:
			room.call("open_station",tab)
			await tick(3)
			check(tab+" disables movement",not bool(player.get("controls_enabled")) and bool(room.call("_modal_open")))
			var panel: Control = room.get("recommendation_panel") as Control
			if is_instance_valid(panel):
				panel.call("close_panel")
				await tick(3)
				check(tab+" close restores movement",bool(player.get("controls_enabled")) and not bool(room.call("_modal_open")))
	room.call("_return_immediately")
	check("Return emits one transition signal",returned==1)
	check("Return releases movement",not bool(player.get("controls_enabled")))
	finish(low)

func finish(low: bool) -> void:
	FileAccess.open(output+("headless-checks.json" if DisplayServer.get_name()=="headless" else "native-checks.json"),FileAccess.WRITE).store_string(JSON.stringify({"failed":failures,"checks":checks,"profile":"low" if low else "full","renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"captures":captures,"scope":"Production avatar, direct routes, lens, seats and native desktop rendering. This is not physical-phone or browser performance evidence."},"\t"))
	print("RECOMMENDATION_ROOM_CHECKS ",checks.size()," failures=",failures)
	quit(1 if failures else 0)
