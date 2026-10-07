extends Node3D

signal world_ready
signal request_open_station(station_id: String, return_token: Dictionary)

const Geo = preload("res://scripts/planet_geometry.gd")
const PlayerScript = preload("res://scripts/planet_player.gd")
const HudScript = preload("res://scripts/world_hud.gd")
const CameraObstruction = preload("res://scripts/camera_obstruction.gd")
const SakuraPlan = preload("res://scripts/sakura_routes.gd")
const MusicScript = preload("res://scripts/world_music.gd")
const BenchScript = preload("res://scripts/bench_interaction.gd")
const TrainingTransition = preload("res://scripts/training_room_transition.gd")
const DistrictStreaming = preload("res://scripts/district_streaming.gd")
const PerformanceTelemetry = preload("res://scripts/performance_telemetry.gd")
var streaming: Node
var performance_telemetry: Node
var benches: Node
var music: Node
var music_context: String = "world"
var music_candidate: String = "world"
var music_candidate_clock: float = 0.0
var layout: Dictionary
var player: PlanetPlayer
var camera: Camera3D
var hud: CanvasLayer
var overview: bool = true
var paused: bool = false
var orbit_yaw: float = 0.45
var orbit_pitch: float = 0.63
var orbit_distance: float = 89.0
var near_distance: float = 7.0
var near_pitch: float = 0.58
var dragging_view: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE
var drag_origin: Vector2 = Vector2.ZERO
var camera_aim: Vector3 = Vector3.ZERO
var camera_obstruction: RefCounted = CameraObstruction.new()
var entering: bool = false
var entry_elapsed: float = 0.0
var entry_station: String = ""
var entry_return: Dictionary = {}
var capture_focus: Node3D = null
var nearest_id: String = ""
var nearest_label: String = ""
var first_camera: bool = true
var elapsed: float = 0.0
var capture_stage: int = 0
var web_status_clock: float = 0.0
var review_mode: bool = false
var last_review_hash: String = ""
var review_hidden_habitats: Array[Node3D] = []
var preparing_roam: bool = false
var preparing_room: bool = false
var startup_presented: bool = false
var startup_frames: int = 0
var preparation_status_clock: float = 0.0

func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	orbit_distance = float(layout.radius) * 3.7
	setup_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mouse_exited.connect(finish_view_drag)
	player = PlayerScript.new() as PlanetPlayer
	player.name = "Player"
	player.planet_radius = float(layout.radius)
	add_child(player)
	player.teleport(Geo.surface(Vector3.UP, Vector2(0, 3), float(layout.radius)).normalized(), float(layout.radius) + 0.6)
	camera = Camera3D.new()
	camera.name = "WorldCamera"
	camera.fov = 42.0
	camera.far = float(layout.radius) * 7.0
	camera.near = 0.08
	add_child(camera)
	camera.make_current()
	music = MusicScript.new()
	music.name = "WorldMusic"
	add_child(music)
	hud = HudScript.new() as CanvasLayer
	hud.set("world", self)
	add_child(hud)
	benches = BenchScript.new()
	benches.name = "BenchInteraction"
	add_child(benches)
	streaming = DistrictStreaming.new() as Node
	streaming.name = "DistrictStreaming"
	add_child(streaming)
	streaming.connect("chunk_added", _on_detail_added)
	streaming.connect("chunk_removing", _on_detail_removing)
	streaming.call("configure", self)
	performance_telemetry = PerformanceTelemetry.new() as Node
	performance_telemetry.name = "PerformanceTelemetry"
	add_child(performance_telemetry)
	camera_obstruction.call("set_active", false)
	refresh_music_context(0.0, true)
	player.controls_enabled = false
	player.process_mode = Node.PROCESS_MODE_DISABLED
	world_ready.emit()
	print("WORLD_READY stations=6 radius=", layout.radius)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.planetWorldReady = true; window.dispatchEvent(new CustomEvent('planet-world-ready'));")

	if OS.has_feature("web") and OS.is_debug_build():
		var review_hash: String=str(JavaScriptBridge.eval("window.location.hash"))
		if review_hash.begins_with("#review-"):
			setup_review_camera(review_hash)

func setup_review_camera(hash_value: String) -> void:
	var parts: PackedStringArray=hash_value.split("-")
	if parts.size()!=3 or not parts[2].is_valid_int():
		return
	var index: int=clampi(int(parts[2]),0,5)
	last_review_hash=hash_value
	restore_review_habitats()
	if parts[1] == "bench":
		setup_bench_review(index)
		return
	if parts[1] in ["water", "waterbefore"]:
		setup_water_review(index, parts[1]=="waterbefore")
		return
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var n: Array=layout.stations[index].normal
	var up: Vector3=Vector3(n[0],n[1],n[2])
	var radius: float=float(layout.radius)
	var axes: Basis=Geo.frame(up)
	var eye: Vector3=up*(radius+33)+axes.x*22+axes.z*31
	var aim: Vector3=up*(radius+.7)
	if parts[1]=="ecology":
		var row: Dictionary=data[index]
		var at: Vector3=Geo.surface(up,Vector2(row.visit[0],row.visit[1]),radius+.3)
		up=at.normalized()
		axes=Geo.frame(up)
		eye=at+up*7.5+axes.x*6+axes.z*9
		aim=at+up
	review_mode=true
	hud.visible=false
	camera.h_offset=0.0
	camera.fov=48.0
	camera.global_transform=Transform3D(Basis.IDENTITY,eye).looking_at(aim,up)

func setup_bench_review(index: int) -> void:
	if entering:
		return
	# Physics needs one sync before a freshly loaded scene can probe its paving.
	await get_tree().physics_frame
	var names: Array[String] = ["EastViewBench", "WestViewBench", "Marina"]
	var seat: StaticBody3D
	for candidate: StaticBody3D in benches.get("seats"):
		if str(candidate.get_path()).contains(names[mini(index, 2)]):
			seat = candidate
			break
	if seat == null:
		return
	var safe: Dictionary = benches.call("safe_stand", seat) as Dictionary
	if safe.is_empty():
		return
	var point: Vector3 = safe.point
	player.teleport(point.normalized(), point.length() + .15)
	player.heading = (seat.global_position - point).slide(point.normalized()).normalized()
	player.visual.rotation.y = PI
	paused = false
	review_mode = false
	capture_focus = null
	hud.visible = true
	hud.call("close_panel")
	(hud.get("destination_card") as Control).visible = false
	near_distance = 7.0
	near_pitch = .46
	camera.fov = 42.0
	set_overview(false)

func setup_water_review(index: int, hide_habitat: bool) -> void:
	if entering:
		return
	var habitat_data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/water_ecology.json")) as Dictionary
	var districts: Array=habitat_data.get("districts", []) as Array
	var station_id: String=str(layout.stations[index].id)
	var review: Dictionary={}
	for district: Dictionary in districts:
		if str(district.get("station", ""))==station_id:
			review=district.get("review", {}) as Dictionary
			break
	if not review.has("point") or not review.has("target"):
		push_warning("No waterfront review view for "+station_id)
		return
	var point: Array=review.point as Array
	var target: Array=review.target as Array
	var normal: Array=layout.stations[index].normal
	var district_up: Vector3=Vector3(normal[0],normal[1],normal[2])
	var radius: float=float(layout.radius)
	var arrival: Vector3=Geo.surface(district_up,Vector2(point[0],point[1]),radius).normalized()
	var aim: Vector3=Geo.surface(district_up,Vector2(target[0],target[1]),radius)
	player.finish_entry()
	player.teleport(arrival,radius+.65)
	var direction: Vector3=(aim-player.global_position).slide(arrival)
	if direction.length_squared()>.0001:
		player.heading=direction.normalized()
	player.global_basis=Basis(player.heading.cross(arrival).normalized(),arrival,-player.heading)
	paused=false
	review_mode=false
	capture_focus=null
	hud.visible=true
	hud.call("close_panel")
	near_distance=7.0
	near_pitch=clampf(float(review.get("pitch", .45)),.08,1.42)
	camera.fov=42.0
	camera_obstruction.call("force_update")
	set_overview(false)
	# Use the ordinary player physics and camera so this view remains playable.
	if hide_habitat:
		var reserves: Node=get_node_or_null("Globe/EcologicalReserves")
		if reserves != null:
			for node: Node in reserves.find_children("AquaticHabitat", "Node3D", true, false):
				var habitat: Node3D=node as Node3D
				if habitat != null and habitat.visible:
					review_hidden_habitats.append(habitat)
					habitat.visible=false

func restore_review_habitats() -> void:
	for habitat: Node3D in review_hidden_habitats:
		if is_instance_valid(habitat):
			habitat.visible=true
	review_hidden_habitats.clear()

func setup_input() -> void:
	var mappings: Dictionary = {"move_left":KEY_A,"move_right":KEY_D,"move_forward":KEY_W,"move_back":KEY_S,"run":KEY_SHIFT,"jump":KEY_SPACE,"switch_view":KEY_TAB,"interact":KEY_E,"reset":KEY_HOME}
	for action: String in mappings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = mappings[action]
		InputMap.action_add_event(action, key)

func _process(delta: float) -> void:
	elapsed += delta
	# The first two frames present the overview before optional HTTP or model work.
	startup_frames += 1
	if not startup_presented and startup_frames >= 3:
		startup_presented = true
		var packs: Node = get_node_or_null("/root/WebPacks")
		if packs != null:
			packs.call("start_all_downloads")
		player.begin_prepare_visuals()
		music.call("begin_prepare_music")
	if preparing_roam:
		player.step_prepare_visuals()
		streaming.call("pin_position", player.global_position)
		if _all_downloads_ready() and player.visuals_ready() and bool(streaming.call("is_position_ready", player.global_position)):
			preparing_roam = false
			set_overview(false)
	if preparing_room:
		_continue_training_room.call_deferred()
	preparation_status_clock += delta
	if preparation_status_clock >= 0.1:
		preparation_status_clock = 0.0
		_update_preparation_status()
	refresh_music_context(delta)
	if entering:
		entry_elapsed += delta
		player.sample_entry(entry_elapsed/1.4)
		if entry_elapsed >= 1.4:
			entering = false
			request_open_station.emit(entry_station,entry_return)
			if entry_station == "wordking":
				open_training_room.call_deferred()
			else:
				hud.call("show_station",entry_station)
	if not review_mode:
		update_camera(delta)
	streaming.call("update_context", overview, player.global_position, camera.global_position, camera_aim, delta)
	if not overview:
		update_nearest()
	hud.call("update_status", overview, nearest_label, player.global_position.length())
	if OS.has_feature("web") and OS.is_debug_build():
		web_status_clock += delta
		if web_status_clock > (0.05 if player.jump_state != &"grounded" else 0.25):
			web_status_clock = 0.0
			var review_hash: String=str(JavaScriptBridge.eval("window.location.hash"))
			if review_hash!=last_review_hash:
				last_review_hash=review_hash
				restore_review_habitats()
				if review_hash.begins_with("#review-"):
					setup_review_camera(review_hash)
				elif review_mode:
					review_mode=false
					hud.visible=true
					first_camera=true
			var status: Dictionary = {"overview":overview,"paused":paused,"entering":entering,"entry_height":player.visual.position.y,"visible":player.visual.visible,"position":[player.position.x,player.position.y,player.position.z],"animation":str(player.active_clip),"fps":Engine.get_frames_per_second(),"yaw":orbit_yaw,"pitch":orbit_pitch,"near_pitch":near_pitch,"heading":[player.heading.x,player.heading.y,player.heading.z],"dragging":dragging_view}
			status["music"] = music.call("get_state")
			status["bench"] = {"state":str(benches.get("state")), "count":benches.get("seats").size(), "prompt":benches.call("prompt")}
			var map_control: Control = hud.get("minimap") as Control
			var destination_button: Button = hud.get("destination_toggle") as Button
			var viewport_size: Vector2 = get_viewport().get_visible_rect().size
			var button_centre: Vector2 = (destination_button.global_position+destination_button.size*.5)/viewport_size
			status["minimap_location"] = str(map_control.get("current_location"))
			var globe: Node3D = get_node("Globe") as Node3D
			var globe_center: Vector2 = camera.unproject_position(globe.global_position)/viewport_size
			status["globe_screen_center"] = [globe_center.x,globe_center.y]
			status["globe_origin"] = [globe.global_position.x,globe.global_position.y,globe.global_position.z]
			status["globe_basis"] = [globe.global_basis.x.x,globe.global_basis.x.y,globe.global_basis.x.z,globe.global_basis.y.x,globe.global_basis.y.y,globe.global_basis.y.z,globe.global_basis.z.x,globe.global_basis.z.y,globe.global_basis.z.z]
			status["mouse_mode"] = Input.mouse_mode
			status["camera_distance"] = camera.global_position.distance_to(camera_aim)
			status["camera_fov"] = camera.fov
			status["camera_target"] = [camera_aim.x,camera_aim.y,camera_aim.z]
			status["jump_state"] = str(player.jump_state)
			status["jump_count"] = player.jump_count
			status["landing_count"] = player.landing_count
			status["grounded"] = player.is_on_floor() and not player.needs_settle
			status["radial_velocity"] = player.radial_velocity
			status["jump_height"] = player.jump_height
			status["max_jump_height"] = player.max_jump_height
			status["ground_distance"] = player.ground_distance
			status["jump_clock"] = player.jump_clock
			status["flip_progress"] = player.flip_progress
			var arrow: Vector2 = map_control.get("arrow_heading_2d") as Vector2
			var map_forward: Vector3 = map_control.get("map_forward") as Vector3
			status["minimap_arrow"] = [arrow.x,arrow.y]
			status["minimap_frame"] = [map_forward.x,map_forward.y,map_forward.z]
			status["destination_button"] = [button_centre.x,button_centre.y]
			status["destinations_open"] = (hud.get("destination_card") as Control).visible
			JavaScriptBridge.eval("window.planetWorldState = " + JSON.stringify(status) + "; document.getElementById('canvas')?.setAttribute('data-world-state', JSON.stringify(window.planetWorldState));")
	if OS.get_cmdline_user_args().has("--capture"):
		if elapsed > 3.0 and capture_stage == 0:
			capture_stage = 1
			capture("overview")
		elif elapsed > 4.0 and capture_stage == 1:
			capture_stage = 2
			set_overview(false)
		elif elapsed > 7.0 and capture_stage == 2:
			capture_stage = 3
			capture("character")
		elif elapsed > 8.0 and capture_stage == 3:
			get_tree().quit()
	elif OS.get_cmdline_user_args().has("--capture-tour"):
		if elapsed > 3.0 + float(capture_stage) * 2.0:
			if capture_stage == 0:
				capture("overview")
			elif capture_stage < 13:
				if capture_stage % 2 == 1:
					var index: int = floori(float(capture_stage - 1) * 0.5)
					teleport_to(str(layout.stations[index].id))
					near_distance = 9.0
				else:
					var index: int = floori(float(capture_stage - 2) * 0.5)
					capture(str(layout.stations[index].id))
			elif capture_stage == 13:
				orbit_yaw += PI
				orbit_pitch = -0.35
				set_overview(true)
			elif capture_stage == 14:
				capture("overview-back")
			elif capture_stage == 15:
				visit_sakura()
				near_distance = 10.0
			elif capture_stage == 16:
				capture("sakura")
			elif capture_stage == 17:
				for actor: Node in find_children("fishing_boat*", "Node3D", true, false):
					if str(actor.name).begins_with("fishing_boat"):
						capture_focus = actor as Node3D
						break
				first_camera = true
			elif capture_stage == 18:
				capture("fishing-boat")
			elif capture_stage == 19:
				focus_sakura_bridge()
			elif capture_stage == 20:
				capture("sakura-bridge")
			elif capture_stage == 21:
				capture_focus = null
				teleport_to("counseling")
				near_distance = 12.0
				near_pitch = .8
			elif capture_stage == 22:
				capture("city-street")
			else:
				get_tree().quit()
			capture_stage += 1
	elif OS.get_cmdline_user_args().has("--capture-entry"):
		if capture_stage == 0 and elapsed > 3.0:
			teleport_to("counseling")
			capture_stage = 1
		elif capture_stage == 1 and elapsed > 4.0:
			open_station("counseling")
			capture_stage = 2
		elif capture_stage == 2 and entry_elapsed > 0.55:
			capture("entry-jump")
			capture_stage = 3
		elif capture_stage == 3 and not entering:
			capture("entry-panel")
			capture_stage = 4
		elif capture_stage == 4 and elapsed > 6.5:
			resume_world({})
			capture_stage = 5
		elif capture_stage == 5 and elapsed > 7.3:
			capture("entry-return")
			capture_stage = 6
		elif capture_stage == 6 and elapsed > 8.0:
			get_tree().quit()

	elif OS.get_cmdline_user_args().has("--capture-garden"):
		if capture_stage == 0 and elapsed > 3.0:
			visit_sakura()
			near_distance = 10.0
			capture_stage = 1
		elif capture_stage == 1 and elapsed > 6.0:
			capture("sakura")
			capture_stage = 2
		elif capture_stage == 2 and elapsed > 7.0:
			focus_sakura_bridge()
			capture_stage = 3
		elif capture_stage == 3 and elapsed > 9.5:
			capture("sakura-bridge")
			capture_stage = 4
		elif capture_stage == 4 and elapsed > 10.5:
			get_tree().quit()

func focus_sakura_bridge() -> void:
	capture_focus = Node3D.new()
	capture_focus.name = "BridgeReview"
	add_child(capture_focus)
	var grove_up: Vector3 = Vector3(.75,1,.85).normalized()
	var bridge_up: Vector3 = Vector3.UP.slerp(grove_up,.80)
	var forward: Vector3 = (grove_up-bridge_up).slide(bridge_up).normalized()
	capture_focus.transform = Transform3D(Basis(bridge_up.cross(-forward).normalized(),bridge_up,-forward),bridge_up*(float(layout.radius)+.3))
	first_camera = true

func capture(label: String) -> void:
	await RenderingServer.frame_post_draw
	var path: String = ProjectSettings.globalize_path("res://../deliverables/" + label + ".png")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE ", path)

func update_camera(delta: float) -> void:
	if is_instance_valid(capture_focus):
		var up: Vector3 = capture_focus.global_position.normalized()
		var aim: Vector3 = capture_focus.global_position+up*.6
		var eye: Vector3 = aim+up*4.0+capture_focus.basis.x*5.0+capture_focus.basis.z*7.0
		if capture_focus.name == "BridgeReview":
			eye = aim+up*8.0+capture_focus.basis.x*10.0+capture_focus.basis.z*10.0
		camera_aim = aim
		camera.global_transform = Transform3D(Basis.IDENTITY,eye).looking_at(aim,up)
		camera_obstruction.call("set_active", false)
	elif overview:
		# Interpolating camera positions cuts a chord through the orbit, causing
		# involuntary zoom. Build the camera from its orientation and fixed radius.
		# The rotated up vector also allows a complete turn through either pole.
		var orbit_basis: Basis = Basis(Vector3.UP,orbit_yaw)*Basis(Vector3.RIGHT,-orbit_pitch)
		camera_aim = Vector3.ZERO
		camera.global_transform = Transform3D(orbit_basis,orbit_basis.z*orbit_distance)
		camera_obstruction.call("set_active", false)
	else:
		camera_obstruction.call("set_active", true)
		var up: Vector3 = player.global_position.normalized()
		camera_aim = player.global_position+up*1.0
		var offset: Vector3 = -player.heading*cos(near_pitch)+up*sin(near_pitch)
		var eye: Vector3 = camera_aim+offset*near_distance
		camera.global_transform = Transform3D(Basis.IDENTITY,eye).looking_at(camera_aim,up)
		camera_obstruction.call("update",self,camera,camera_aim,delta)
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	first_camera = false

func begin_view_drag(button_index: MouseButton) -> void:
	if paused or dragging_view or hud.call("is_settings_open"):
		return
	drag_origin = get_viewport().get_mouse_position()
	drag_button = button_index
	dragging_view = true
	get_viewport().set_input_as_handled()

func finish_view_drag() -> void:
	if not dragging_view:
		return
	dragging_view = false
	drag_button = MOUSE_BUTTON_NONE
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		finish_view_drag()
		if music != null:
			music.call("set_background_paused", true)
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and music != null:
		music.call("set_background_paused", false)

func _input(event: InputEvent) -> void:
	if music != null and ((event is InputEventKey and event.is_pressed() and not event.is_echo()) or (event is InputEventMouseButton and event.is_pressed()) or (event is InputEventScreenTouch and event.is_pressed())):
		music.call("unlock")
	if hud != null and bool(hud.call("is_settings_open")):
		return
	# Handle the drag before GUI containers can consume mouse motion.
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if not mouse.pressed and mouse.button_index == drag_button:
			finish_view_drag()
			get_viewport().set_input_as_handled()
		elif mouse.pressed and mouse.button_index == MOUSE_BUTTON_RIGHT:
			begin_view_drag(mouse.button_index)
	elif event is InputEventMouseMotion and dragging_view and not paused:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		# Visible cursor dragging uses ordinary button state, never pointer lock.
		# Releasing outside the canvas cannot leave rotation latched on re-entry.
		var held_mask: int = MOUSE_BUTTON_MASK_LEFT if drag_button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		if (motion.button_mask & held_mask) == 0:
			finish_view_drag()
			return
		if overview:
			orbit_yaw -= motion.relative.x * 0.005
			orbit_pitch += motion.relative.y * 0.003
		else:
			player.rotate_heading(-motion.relative.x * 0.005)
			near_pitch = clampf(near_pitch + motion.relative.y * 0.003, .08, 1.42)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if hud != null and bool(hud.call("is_settings_open")):
		return
	if preparing_roam or preparing_room:
		if event.is_action_pressed("switch_view") or (event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE):
			cancel_preparation()
		return
	if paused and not (event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE):
		return
	if event.is_action_pressed("switch_view"):
		set_overview(not overview)
	elif event.is_action_pressed("reset"):
		teleport_to("counseling")
	elif event.is_action_pressed("interact") and not event.is_echo():
		interact_nearest()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		finish_view_drag()
		if player.is_resting:
			benches.call("interact")
		else:
			resume_world({})
	elif event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		# Left presses reach this only after buttons/menus have handled their click.
		# Releases stay in _input so leaving the world area cannot leave a stuck drag.
		if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
			begin_view_drag(mouse.button_index)
		elif mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if dragging_view:
				return
			var change: float = -1.0 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
			if overview:
				orbit_distance = clampf(orbit_distance + change * 5.0, float(layout.radius) * 2.4, float(layout.radius) * 5.0)
			else:
				near_distance = clampf(near_distance + change * 0.6, 4.0, 12.0)

func _all_downloads_ready() -> bool:
	var packs: Node = get_node_or_null("/root/WebPacks")
	return packs == null or bool(packs.call("all_resources_ready"))

func set_overview(enabled: bool) -> void:
	if entering:
		return
	if enabled:
		# Cancelling first-entry preparation can keep overview=true throughout.
		# Release its pin explicitly even when the camera mode never changed.
		streaming.call("clear_pin")
	if not enabled and (not _all_downloads_ready() or not player.visuals_ready() or not bool(streaming.call("is_position_ready", player.global_position))):
		preparing_roam = true
		player.begin_prepare_visuals()
		streaming.call("pin_position", player.global_position)
		player.controls_enabled = false
		player.process_mode = Node.PROCESS_MODE_DISABLED
		return
	preparing_roam = false
	finish_view_drag()
	player.cancel_jump_input()
	overview = enabled
	player.process_mode = Node.PROCESS_MODE_DISABLED if overview else Node.PROCESS_MODE_INHERIT
	camera_obstruction.call("set_active", not overview)
	camera_obstruction.call("force_update")
	if not overview:
		streaming.call("pin_position", player.global_position)
	player.controls_enabled = not overview and not paused
	if OS.get_cmdline_user_args().has("--capture") or OS.get_cmdline_user_args().has("--capture-tour"):
		player.controls_enabled = false
	# Switch without flying through the sphere.
	first_camera = true
	refresh_music_context(0.0, true)

func teleport_to(station_id: String) -> void:
	if entering:
		return
	player.finish_entry()
	var station: Node3D = get_node_or_null("Stations/" + station_id) as Node3D
	if station == null:
		return
	var up: Vector3 = station.position.normalized()
	var arrival: Vector3 = Geo.surface(up, Vector2(0, 2.5), float(layout.radius)).normalized()
	player.teleport(arrival, float(layout.radius) + 0.65)
	# Face the destination even where the tangent frame changes near a pole.
	player.heading = (station.global_position - player.global_position).slide(arrival).normalized()
	player.global_basis = Basis(player.heading.cross(arrival).normalized(),arrival,-player.heading)
	paused = false
	hud.call("close_panel")
	set_overview(false)

func visit_sakura() -> void:
	if entering:
		return
	player.finish_entry()
	var up: Vector3 = SakuraPlan.grove_up()
	var arrival: Vector3 = Geo.surface(up,SakuraPlan.entry_offset(float(layout.radius))*.7,float(layout.radius)).normalized()
	player.teleport(arrival,float(layout.radius)+0.6)
	player.heading = (up-arrival).slide(arrival).normalized()
	paused = false
	hud.call("close_panel")
	set_overview(false)

func update_nearest() -> void:
	nearest_id = ""
	nearest_label = ""
	var distance: float = 3.2
	for station: Node in $Stations.get_children():
		var node: Node3D = station as Node3D
		var marker_visible: bool = not (paused and str(node.name) == entry_station)
		(node.get_node("StationLabel") as Label3D).visible = marker_visible
		(node.get_node("Beacon") as MeshInstance3D).visible = marker_visible
		var d: float = player.global_position.distance_to(node.global_position)
		if d < distance:
			distance = d
			nearest_id = str(node.get_meta("station_id"))
			nearest_label = str(node.get_meta("label"))
	benches.call("refresh_nearest")
	var nearby_seat: StaticBody3D = benches.get("nearest") as StaticBody3D
	if player.is_resting or (nearby_seat != null and nearby_seat.global_position.distance_to(player.global_position) < distance):
		nearest_id = ""
		nearest_label = ""
	elif nearest_id != "":
		benches.set("nearest", null)

func interact_nearest() -> void:
	if paused or overview or entering or preparing_roam or preparing_room:
		return
	var destinations: Control = hud.get("destination_card") as Control
	if destinations != null and destinations.visible:
		return
	update_nearest()
	if player.is_resting or benches.get("nearest") != null:
		benches.call("interact")
	elif nearest_id != "":
		open_station(nearest_id)

func open_station(station_id: String) -> void:
	if paused or entering or preparing_roam or preparing_room or not player.visuals_ready():
		return
	var station: Node3D = get_node_or_null("Stations/"+station_id) as Node3D
	if station == null:
		return
	entry_return = {"position":player.global_position,"heading":player.heading}
	entry_station = station_id
	entry_elapsed = 0.0
	pause_world()
	var direction: Vector3 = player.heading
	player.teleport(station.position.normalized(),float(layout.radius)+0.32)
	player.heading = direction.slide(player.position.normalized()).normalized()
	player.global_basis = Basis(player.heading.cross(player.up_direction).normalized(),player.up_direction,-player.heading)
	player.begin_entry()
	entering = true
	refresh_music_context(0.0, true)

func pause_world() -> void:
	finish_view_drag()
	player.cancel_jump_input()
	paused = true
	player.controls_enabled = false

func open_training_room() -> void:
	if not paused or entry_station != "wordking":
		return
	preparing_room = true

func _continue_training_room() -> void:
	if not preparing_room:
		return
	if not paused or entry_station != "wordking":
		preparing_room = false
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		if not bool(packs.call("all_resources_ready")):
			return
		packs.call("request_resource", TrainingTransition.ROOM_SCENE, 200)
		if not bool(packs.call("is_resource_ready", TrainingTransition.ROOM_SCENE)):
			return
	preparing_room = false
	hud.call("set_preparation", "", false)
	var transition: Node = TrainingTransition.new()
	transition.name = "TrainingRoomTransition"
	get_tree().root.add_child(transition)
	if not bool(transition.call("open_from_world", self, entry_return)):
		transition.queue_free()
		resume_world(entry_return)

func _update_preparation_status() -> void:
	var packs: Node = get_node_or_null("/root/WebPacks")
	var status: Dictionary = packs.call("get_status") as Dictionary if packs != null else {}
	var complete: bool = bool(status.get("all_ready", true))
	var startup_message: String = ""
	var startup_error: String = str(packs.call("startup_error")) if packs != null else ""
	if bool(status.get("enabled", false)) and not complete:
		var network_done: bool = int(status.network_received_bytes) >= int(status.total_bytes)
		startup_message = ("全部資源已下載，正在準備…" if network_done else "遊戲資源下載 %.1f / %.1f MB" % [float(status.network_received_bytes)/1000000.0, float(status.total_bytes)/1000000.0])
		startup_message += "\n可返回總覽或切換分頁，下載會繼續"
		hud.call("set_background_download", startup_message if startup_error.is_empty() else startup_error, not startup_error.is_empty())
	else:
		hud.call("set_background_download", "")
	if not preparing_roam and not preparing_room:
		hud.call("set_preparation", "", false)
		return
	var message: String = "正在準備訓練室…" if preparing_room else "正在準備角色與目的地…"
	var error: String = player.visuals_error() if preparing_roam else ""
	if error.is_empty() and preparing_roam:
		error = str(streaming.call("position_error", player.global_position))
	if packs != null:
		if error.is_empty():
			error = str(packs.call("startup_error"))
		if preparing_room and error.is_empty():
			error = str(packs.call("resource_error", TrainingTransition.ROOM_SCENE))
		if not complete:
			message = startup_message
		elif preparing_roam:
			message = "正在建立角色…" if not player.visuals_ready() else "正在建立目的地細節…"
	hud.call("set_preparation", error if not error.is_empty() else message, not error.is_empty())

func retry_preparation() -> void:
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("retry_failed")
	player.retry_prepare_visuals()
	streaming.call("retry_failed")

func cancel_preparation() -> void:
	preparing_roam = false
	preparing_room = false
	if paused:
		resume_world(entry_return)
	set_overview(true)
	hud.call("set_preparation", "", false)

func can_player_jump() -> bool:
	if overview or paused or entering or preparing_roam or preparing_room or player.is_resting or hud.call("is_settings_open"):
		return false
	var destinations: Control = hud.get("destination_card") as Control
	return destinations == null or not destinations.visible

func resume_world(return_token: Dictionary) -> void:
	if entering:
		return
	if paused and return_token.is_empty() and not entry_return.is_empty():
		return_token = entry_return
	player.finish_entry()
	if return_token.has("position"):
		player.teleport((return_token.position as Vector3).normalized(), (return_token.position as Vector3).length())
		player.heading = return_token.heading
	paused = false
	if not overview:
		streaming.call("pin_position", player.global_position)
		camera_obstruction.call("force_update")
	player.controls_enabled = not overview
	hud.call("close_panel")
	entry_return = {}
	entry_station = ""
	refresh_music_context(0.0, true)

func desired_music_context() -> String:
	if (entering or paused) and not entry_station.is_empty():
		return entry_station
	if overview or hud == null:
		return "world"
	var map_control: Control = hud.get("minimap") as Control
	return str(map_control.call("station_at", player.global_position.normalized())) if map_control != null else "world"

func refresh_music_context(delta: float, immediate: bool = false) -> void:
	if music == null:
		return
	var desired: String = desired_music_context()
	if desired != music_candidate:
		music_candidate = desired
		music_candidate_clock = 0.0
	else:
		music_candidate_clock += delta
	# A brief dwell prevents a footstep along a coastline from swapping tracks repeatedly.
	if immediate or music_candidate_clock >= 0.75:
		if immediate or music_context != desired:
			music_context = desired
			music.call("set_context", desired)

func visit_ecology(index: int) -> void:
	if entering:
		return
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var row: Dictionary=districts[index]
	var normal: Array=layout.stations[index].normal
	var up: Vector3=Vector3(normal[0],normal[1],normal[2])
	var offset: Vector2=Vector2(row.visit[0],row.visit[1])
	player.finish_entry()
	player.teleport(Geo.surface(up,offset,float(layout.radius)).normalized(),float(layout.radius)+.65)
	paused=false
	hud.call("close_panel")
	set_overview(false)

func _on_detail_added(detail: Node) -> void:
	camera_obstruction.call("register_region", detail)

func _on_detail_removing(detail: Node) -> void:
	camera_obstruction.call("unregister_region", detail)
	if is_instance_valid(capture_focus) and detail.is_ancestor_of(capture_focus):
		capture_focus = null
	restore_review_habitats()

func _exit_tree() -> void:
	# The room transition detaches this world too. Re-index lazily on return.
	camera_obstruction.call("reset")
