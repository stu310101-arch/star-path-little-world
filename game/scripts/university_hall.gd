extends Node3D

signal room_ready
signal request_return_to_world

const IndoorPlayer = preload("res://scripts/indoor_player.gd")
const Catalog = preload("res://scripts/university_catalog.gd")
const HallUI = preload("res://scripts/university_hall_ui.gd")
const HallSpace = preload("res://scripts/university_hall_space.gd")
const WorldMusic = preload("res://scripts/world_music.gd")
const LoadReaper = preload("res://scripts/university_load_reaper.gd")
const WORLD_SCENE: String = "res://scenes/world.tscn"
const LAYOUT_PATH: String = "res://assets/university_hall/layout.json"
const MODEL_PATHS: Dictionary = {
	"atrium":"res://assets/university_hall/atrium.glb",
	"gallery":"res://assets/university_hall/gallery.glb",
	"exhibit_kit":"res://assets/university_hall/exhibit_kit.glb",
	"feature_book":"res://assets/university_hall/feature_book.glb"
}

var player: CharacterBody3D
var camera: Camera3D
var music: Node
var graphics_settings: Node
var catalog: RefCounted = Catalog.new()
var ui: CanvasLayer
var space: Node3D
var ready_for_play: bool = false
var returning: bool = false
var low_quality: bool = true
var detail_state: String = "waiting"
var detail_error: String = ""
var region: String = ""
var page: int = 0
var camera_yaw: float = 0
var camera_pitch: float = .27
var camera_distance: float = 4.8
var dragging_view: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE
var nearest_target: Dictionary = {}
var models: Dictionary = {}
var model_paths: Dictionary = MODEL_PATHS.duplicate()
var layout_path: String = LAYOUT_PATH
var model_index: int = 0
var loading_path: String = ""
var requested_model: bool = false
var pending_school: String = ""
var pending_region: String = ""
var load_started_ms: int = 0
var ready_ms: int = 0
var max_load_operation_ms: float = 0
var status_clock: float = 0
var telemetry_clock: float = 0
var telemetry_enabled: bool = false
var _owns_music: bool = false
var inspection_id: String = ""
var inspection_booth: Node3D
var inspection_angle: float = .15
var inspection_pitch: float = .60
var inspection_distance: float = 3.65
var inspection_light: SpotLight3D
var _follow_aim: Vector3 = Vector3.ZERO
var _follow_aim_ready: bool = false
var initial_school_id: String = ""
var return_label: String = ""

func set_shared_music(shared: Node) -> void:
	music = shared

func _ready() -> void:
	name = "UniversityHall"
	if get_node("/root/ResourceProfile").call("is_low"):
		model_paths = {"atrium":"res://generated/low/university/atrium.scn", "gallery":"res://generated/low/university/gallery.scn", "exhibit_kit":"res://generated/low/university/exhibit_kit.scn", "feature_book":"res://generated/low/university/feature_book.scn"}
		layout_path = "res://generated/low/university/layout.json"
	add_to_group("touch_camera")
	load_started_ms = Time.get_ticks_msec()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_setup_input()
	get_window().mouse_exited.connect(_finish_drag)
	if graphics_settings == null:
		graphics_settings = get_tree().get_first_node_in_group("graphics_settings")
	if is_instance_valid(graphics_settings):
		graphics_settings.connect("state_changed", _apply_quality)
	_build_environment()
	_apply_quality()
	var content_ready: bool = catalog.load_content()
	catalog.call("configure_cloud",get_node_or_null("/root/StarPathAccount"))
	catalog.load_progress()
	ui = HallUI.new()
	ui.set("return_label", return_label)
	add_child(ui)
	ui.call("configure", catalog)
	if not initial_school_id.is_empty():
		travel_to_school(initial_school_id)
	ui.connect("travel_requested", travel_to_school)
	ui.connect("region_requested", show_region)
	ui.connect("return_requested", return_to_world)
	ui.connect("atrium_requested", show_atrium)
	ui.connect("interact_requested", interact_nearest)
	ui.connect("retry_requested", retry_loading)
	ui.connect("modal_changed", _modal_changed)
	ui.connect("inspect_requested", inspect_school)
	ui.connect("inspection_closed", close_inspection)
	ui.connect("inspection_zoomed", zoom_inspection)
	ui.connect("inspection_reset", reset_inspection)
	space = HallSpace.new()
	space.name = "ExhibitionSpace"
	add_child(space)
	space.call("configure", catalog, models, {})
	player = IndoorPlayer.new() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	player.set("controls_enabled", false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.call("begin_prepare_visuals")
	player.call("place_at", Vector3(0, .08, 6), Vector3.FORWARD)
	camera = Camera3D.new()
	camera.name = "HallCamera"
	camera.fov = 65
	camera.near = .15
	camera.far = 65
	add_child(camera)
	camera.make_current()
	update_camera(0, true)
	if music == null:
		music = WorldMusic.new()
		add_child(music)
		_owns_music = true
		music.call("begin_prepare_music")
	music.call("set_context", "universities")
	if OS.has_feature("web"):
		telemetry_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	if not content_ready:
		detail_state = "error"
		detail_error = str(catalog.error)
	else:
		_request_models()
	_update_status()

func _setup_input() -> void:
	var bindings: Dictionary = {"move_forward":KEY_W, "move_back":KEY_S, "move_left":KEY_A, "move_right":KEY_D, "run":KEY_SHIFT, "jump":KEY_SPACE, "interact":KEY_E}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = bindings[action]
			InputMap.action_add_event(action, event)

func _build_environment() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("29312c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e2d6bd")
	environment.ambient_light_energy = .25
	# A small static radiance map gives brass and glass a soft room reflection.
	# The visible background stays solid; no extra capture camera is needed.
	var reflection_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	reflection_material.sky_top_color = Color("637082")
	reflection_material.sky_horizon_color = Color("b6a794")
	reflection_material.ground_horizon_color = Color("7b6550")
	reflection_material.ground_bottom_color = Color("30251e")
	reflection_material.sky_energy_multiplier = .6
	reflection_material.ground_energy_multiplier = .4
	var reflection_sky: Sky = Sky.new()
	reflection_sky.radiance_size = Sky.RADIANCE_SIZE_128
	reflection_sky.sky_material = reflection_material
	environment.sky = reflection_sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "LibraryDaylight"
	sun.rotation_degrees = Vector3(-48, -28, 0)
	sun.light_color = Color("e0e8ef")
	sun.light_energy = .48
	sun.shadow_bias = .06
	sun.directional_shadow_max_distance = 45
	add_child(sun)
	# Only the currently inspected table gets a close-range light. Its shadow
	# follows the same profile as the room rather than bypassing the low budget.
	inspection_light = SpotLight3D.new()
	inspection_light.name = "ExhibitInspectionLight"
	inspection_light.light_color = Color("ffecd1")
	inspection_light.light_energy = .7
	inspection_light.spot_range = 6
	inspection_light.spot_angle = 55
	inspection_light.spot_attenuation = .7
	inspection_light.shadow_enabled = true
	inspection_light.shadow_bias = .1
	inspection_light.shadow_normal_bias = 1.5
	inspection_light.visible = false
	add_child(inspection_light)

func _apply_quality() -> void:
	low_quality = bool(graphics_settings.call("is_low_quality")) if is_instance_valid(graphics_settings) else str(get_viewport().get_meta("graphics_quality_profile", "low")) in ["mobile", "balanced", "low"]
	if is_instance_valid(graphics_settings) and graphics_settings.has_method("is_constrained_runtime"):
		low_quality = low_quality or bool(graphics_settings.call("is_constrained_runtime"))
	var sun: DirectionalLight3D = get_node_or_null("LibraryDaylight") as DirectionalLight3D
	if sun != null:
		sun.shadow_enabled = not low_quality
	if inspection_light != null:
		inspection_light.shadow_enabled = not low_quality

func _request_models() -> void:
	detail_state = "waiting"
	detail_error = ""
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("request_resource", str(model_paths.atrium), 80)

func _step_loading() -> void:
	if detail_state in ["ready", "error"]:
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		var error: String = str(packs.call("resource_error", str(model_paths.atrium)))
		if not error.is_empty():
			detail_error = "展館素材下載失敗，可以重試或返回世界。"
			detail_state = "error"
			return
		if not bool(packs.call("is_resource_ready", str(model_paths.atrium))):
			return
	detail_state = "loading"
	if model_index >= model_paths.size():
		detail_state = "ready"
		var layout: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		space.call("configure", catalog, models, layout if layout is Dictionary else {})
		show_atrium(false)
		return
	var key: String = str(model_paths.keys()[model_index])
	var path: String = str(model_paths[key])
	if not requested_model:
		var request_error: Error = ResourceLoader.load_threaded_request(path, "PackedScene", true, ResourceLoader.CACHE_MODE_REUSE)
		if request_error != OK:
			detail_error = "展館模型無法載入：" + key
			detail_state = "error"
			return
		requested_model = true
		loading_path = path
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
	if status == ResourceLoader.THREAD_LOAD_FAILED or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(path)
		detail_error = "展館模型未能完成載入：" + key
		detail_state = "error"
		requested_model = false
		loading_path = ""
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var started: int = Time.get_ticks_usec()
	var packed: PackedScene = ResourceLoader.load_threaded_get(path) as PackedScene
	max_load_operation_ms = maxf(max_load_operation_ms, float(Time.get_ticks_usec() - started) / 1000.0)
	requested_model = false
	loading_path = ""
	if packed == null:
		detail_state = "error"
		detail_error = "展館模型格式無法讀取。"
		return
	models[key] = packed
	model_index += 1

func retry_loading() -> void:
	if not str(catalog.error).is_empty():
		if not catalog.load_content():
			return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("retry_resource", str(model_paths.atrium))
	player.call("retry_prepare_visuals")
	_request_models()

func _process(delta: float) -> void:
	if returning:
		return
	_step_loading()
	if not ready_for_play:
		player.call("step_prepare_visuals")
		if detail_state == "ready" and bool(player.call("visuals_ready")):
			ready_for_play = true
			ready_ms = Time.get_ticks_msec() - load_started_ms
			player.process_mode = Node.PROCESS_MODE_INHERIT
			player.set("controls_enabled", not bool(ui.call("is_open")))
			if not pending_school.is_empty():
				var id: String = pending_school
				pending_school = ""
				travel_to_school(id)
			elif not pending_region.is_empty():
				var destination: String = pending_region
				pending_region = ""
				show_region(destination)
			room_ready.emit()
			print("UNIVERSITY_HALL_READY entries=", catalog.entries.size(), " milliseconds=", ready_ms)
	if ready_for_play:
		if dragging_view and not Input.is_mouse_button_pressed(drag_button):
			_finish_drag()
		nearest_target = space.call("nearest", player.position) as Dictionary
		update_camera(delta)
		if player.position.y < -3:
			_place_player(Vector3(0, .08, 6 if region.is_empty() else 16), Vector3.FORWARD, 0)
	status_clock += delta
	if status_clock >= .12:
		status_clock = 0
		_update_status()
		space.call("update_label_visibility", player.position)
	if OS.has_feature("web") and (OS.is_debug_build() or telemetry_enabled):
		telemetry_clock += delta
		if telemetry_clock >= .25:
			telemetry_clock = 0
			JavaScriptBridge.eval("window.universityHallState = " + JSON.stringify(debug_state()) + ";")

func _update_status() -> void:
	if ui == null:
		return
	ui.call("set_place", region, page)
	if not ready_for_play:
		var message: String = "正在載入大學館… %d / %d" % [model_index, model_paths.size()]
		var error: String = detail_error
		if error.is_empty():
			error = str(player.call("visuals_error"))
		if detail_state == "ready" and error.is_empty():
			message = "正在準備角色…"
		ui.call("set_status", message if error.is_empty() else error, "", not error.is_empty())
		return
	var hint: String = "WASD 移動 · 拖曳轉向 · E 互動  |  M 導覽 · J 手冊"
	if not region.is_empty():
		hint = "%s展廊 %d / %d · 已探索 %d / 138\n%s" % [Catalog.region_label(region), page + 1, catalog.page_count(region), catalog.visited.size(), hint]
	else:
		hint = "走進展區，探索不同的校園日常。\n" + hint
	ui.call("set_status", hint, "E  " + str(nearest_target.label) if not nearest_target.is_empty() else "")

func show_atrium(close_ui: bool = true) -> void:
	close_inspection()
	# An explicit return cancels queued navigation, including the short period
	# when models are ready but the avatar is still preparing.
	if close_ui:
		pending_region = ""
		pending_school = ""
	if detail_state != "ready":
		return
	if close_ui:
		ui.call("close_panel")
	region = ""
	page = 0
	space.call("build_atrium")
	_place_player(Vector3(0, .08, 6), Vector3.FORWARD, 0)
	nearest_target = {}
	_update_status()

func show_region(region_id: String, page_number: int = 0) -> void:
	if region_id not in Catalog.REGION_IDS:
		return
	close_inspection()
	if not ready_for_play:
		pending_region = region_id
		pending_school = ""
		return
	ui.call("close_panel")
	region = region_id
	page = clampi(page_number, 0, catalog.page_count(region) - 1)
	space.call("build_gallery", region, page)
	_place_player(Vector3(0, .08, 16), Vector3.FORWARD, 0)
	nearest_target = {}
	_update_status()

func travel_to_school(id: String) -> void:
	var address: Dictionary = catalog.locate(id)
	if address.is_empty():
		return
	if not ready_for_play:
		pending_school = id
		pending_region = ""
		return
	show_region(str(address.region), int(address.page))
	var location: Dictionary = (space.get("booth_positions") as Dictionary).get(id, {})
	if not location.is_empty():
		camera_pitch = .42
		camera_distance = 3.8
		_place_player(location.position as Vector3, location.facing as Vector3, float(location.yaw))
	nearest_target = space.call("nearest", player.position) as Dictionary
	_update_status()

func _place_player(at: Vector3, facing: Vector3, yaw: float) -> void:
	_finish_drag()
	player.call("place_at", at, facing)
	camera_yaw = yaw
	update_camera(0, true)

func interact_nearest() -> void:
	if not ready_for_play or returning or not inspection_id.is_empty() or bool(ui.call("is_open")):
		return
	nearest_target = space.call("nearest", player.position) as Dictionary
	if nearest_target.is_empty():
		return
	var target: Dictionary = nearest_target.duplicate()
	match str(target.kind):
		"region":
			show_region(str(target.region))
		"page":
			show_region(region, int(target.page))
		"atrium":
			show_atrium()
		"map":
			ui.call("open_directory", "all")
		"journal":
			ui.call("open_directory", "favorites")
		"exit":
			return_to_world()
		"school", "overview":
			ui.call("open_school", catalog.by_id[str(target.school_id)], int(target.section))

func _modal_changed(open: bool) -> void:
	if open:
		close_inspection()
	_finish_drag()
	_set_touch_modal(open)
	if player != null:
		player.set("controls_enabled", ready_for_play and not open and not returning)
		player.call("cancel_jump_input")
		player.velocity = Vector3.ZERO

func _set_touch_modal(open: bool) -> void:
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldTouchUI")
		if bridge != null:
			bridge.setModalOpen(open)

func can_player_jump() -> bool:
	return ready_for_play and not returning and inspection_id.is_empty() and not bool(ui.call("is_open"))

func touch_look(relative: Vector2) -> void:
	if not inspection_id.is_empty():
		_rotate_view(relative)
		return
	if not can_player_jump():
		return
	_rotate_view(relative)

func _rotate_view(relative: Vector2) -> void:
	if not inspection_id.is_empty():
		inspection_angle = clampf(inspection_angle - relative.x * .004, -.65, .65)
		inspection_pitch = clampf(inspection_pitch + relative.y * .004, .28, 1.08)
		return
	var yaw_delta: float = -relative.x * .005
	camera_yaw += yaw_delta
	camera_pitch = clampf(camera_pitch + relative.y * .004, -.04, .72)
	player.call("rotate_heading", yaw_delta)

func _unhandled_input(event: InputEvent) -> void:
	if returning:
		return
	# Touch emits both an emulated mouse move and the original screen drag.
	# UI buttons already handled their events; orbit uses just the latter.
	if not inspection_id.is_empty() and event.device == InputEvent.DEVICE_ID_EMULATION and (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		if event.keycode == KEY_ESCAPE:
			if bool(ui.call("is_open")):
				ui.call("close_panel")
			elif not ready_for_play:
				return_to_world()
			else:
				ui.call("open_directory", "all")
			get_viewport().set_input_as_handled()
			return
		if not bool(ui.call("is_open")):
			if event.keycode == KEY_M or event.keycode == KEY_J:
				ui.call("open_directory", "favorites" if event.keycode == KEY_J else "all")
				get_viewport().set_input_as_handled()
				return
			if event.keycode == KEY_R and detail_state == "error":
				retry_loading()
				return
	if not ready_for_play or bool(ui.call("is_open")):
		return
	if music != null and (event is InputEventKey or event is InputEventMouseButton):
		music.call("unlock")
	if event.is_action_pressed("interact") and not event.is_echo():
		interact_nearest()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging_view = event.pressed
			drag_button = event.button_index if event.pressed else MOUSE_BUTTON_NONE
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if not inspection_id.is_empty():
				zoom_inspection(-.35 if event.button_index == MOUSE_BUTTON_WHEEL_UP else .35)
			else:
				camera_distance = clampf(camera_distance + (-.4 if event.button_index == MOUSE_BUTTON_WHEEL_UP else .4), 2.4, 7)
	elif event is InputEventMouseMotion and dragging_view:
		_rotate_view(event.relative)
	elif event is InputEventScreenDrag and not inspection_id.is_empty():
		_rotate_view(event.relative)
		get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	if not returning and not inspection_id.is_empty() and event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_ESCAPE:
		close_inspection()
		get_viewport().set_input_as_handled()
		return
	# LineEdit consumes Esc before _unhandled_input. Closing the modal must work
	# even while the user is typing a school name or using a filter popup.
	if not returning and ui != null and bool(ui.call("is_open")) and event is InputEventKey and event.is_pressed() and not event.is_echo() and event.keycode == KEY_ESCAPE:
		ui.call("close_panel")
		get_viewport().set_input_as_handled()

func _finish_drag() -> void:
	dragging_view = false
	drag_button = MOUSE_BUTTON_NONE

func _camera_room_bounds(point: Vector3) -> Vector3:
	return Vector3(clampf(point.x, -15.5 if region.is_empty() else -14.5, 15.5 if region.is_empty() else 14.5), clampf(point.y, .4, 5.8), clampf(point.z, -12.5 if region.is_empty() else -18.5, 12.5 if region.is_empty() else 18.5))

func update_camera(delta: float, snap: bool = false) -> void:
	if camera == null or player == null:
		return
	if not inspection_id.is_empty() and is_instance_valid(inspection_booth):
		_follow_aim_ready = false
		var model_aim: Vector3 = inspection_booth.to_global(Vector3(0, 1.25, -.15))
		var orbit: Vector3 = Vector3(sin(inspection_angle) * cos(inspection_pitch), sin(inspection_pitch), cos(inspection_angle) * cos(inspection_pitch)) * inspection_distance
		var model_camera: Vector3 = model_aim + inspection_booth.global_basis * orbit
		camera.global_position = model_camera if snap else camera.global_position.lerp(model_camera, 1.0 - exp(-delta * 12))
		camera.look_at(model_aim, Vector3.UP)
		return
	var aim: Vector3 = player.global_position + Vector3.UP * 1.25
	var offset: Vector3 = Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	var desired: Vector3 = aim + offset
	if ready_for_play:
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(aim, desired, 1)
		query.hit_from_inside = true
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty():
			desired = (hit.position as Vector3) + (hit.normal as Vector3) * .2
	desired = _camera_room_bounds(desired)
	# Physics advances at 60 Hz while rendered frames can run at 30/45 Hz or
	# miss a frame. Smoothing world position but aiming directly at the latest
	# body position made the camera breathe in/out on a perfectly flat floor.
	# Translate with the body first; smooth only changes in orbit/obstruction.
	var follow_position: Vector3 = camera.global_position
	if _follow_aim_ready and not snap:
		follow_position += aim - _follow_aim
	camera.global_position = desired if snap else _camera_room_bounds(follow_position.lerp(desired, 1.0 - exp(-delta * 12)))
	_follow_aim = aim
	_follow_aim_ready = true
	if camera.global_position.distance_squared_to(aim) > .002:
		camera.look_at(aim, Vector3.UP)

func return_to_world() -> void:
	if returning:
		return
	returning = true
	close_inspection()
	_finish_drag()
	if player != null:
		player.set("controls_enabled", false)
	if request_return_to_world.get_connections().is_empty():
		get_tree().change_scene_to_file(WORLD_SCENE)
	else:
		request_return_to_world.emit()

func debug_state() -> Dictionary:
	var state: Dictionary = {"ready":ready_for_play, "detail_state":detail_state, "detail_error":detail_error, "region":region, "page":page, "entries":catalog.entries.size(), "visited":catalog.visited.keys(), "favorites":catalog.favorites.keys(), "player":[player.position.x,player.position.y,player.position.z], "nearest":str(nearest_target.get("id", "")), "panel":str(ui.get("current_panel")), "school":str((ui.get("school") as Dictionary).get("id", "")), "fps":Engine.get_frames_per_second(), "ready_ms":ready_ms, "max_load_operation_ms":max_load_operation_ms, "low_quality":low_quality, "nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT), "resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT), "instance":get_instance_id(), "buttons":ui.call("debug_buttons")}
	if is_instance_valid(graphics_settings):
		state["graphics"] = graphics_settings.call("get_state")
	state["viewport"] = [get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	state["ticks_ms"] = Time.get_ticks_msec()
	state["controls"] = ui.call("debug_controls")
	state["selected_section"] = int(ui.get("selected_section"))
	state["inspection_id"] = inspection_id
	state["inspection_distance"] = inspection_distance
	state["inspection_angle"] = inspection_angle
	state["inspection_pitch"] = inspection_pitch
	state["player_visible"] = player.visible
	state["player_controls_enabled"] = bool(player.get("controls_enabled"))
	var results: VBoxContainer = ui.get("results") as VBoxContainer
	state["results_count"] = results.get_child_count() if is_instance_valid(results) and str(ui.get("current_panel")) == "directory" else 0
	return state

func inspect_school(id: String) -> void:
	if not ready_for_play or returning or not catalog.by_id.has(id):
		return
	# The model uses the same authored meshes in the live gallery. A close view
	# does not scale the avatar or replace the asset with a separate render.
	if space.get_node_or_null("School_" + id) == null:
		travel_to_school(id)
	inspection_booth = space.get_node_or_null("School_" + id) as Node3D
	if inspection_booth == null:
		return
	ui.call("close_panel")
	inspection_id = id
	inspection_light.global_position = inspection_booth.to_global(Vector3(-1.6, 4.6, 1.4))
	inspection_light.look_at(inspection_booth.to_global(Vector3(0, .9, -.15)), Vector3.UP)
	inspection_light.visible = true
	_finish_drag()
	reset_inspection()
	player.visible = false
	player.set("controls_enabled", false)
	player.call("cancel_jump_input")
	player.velocity = Vector3.ZERO
	_set_touch_modal(true)
	ui.call("set_inspection", catalog.by_id[id])
	update_camera(0, true)

func reset_inspection() -> void:
	inspection_angle = .15
	inspection_pitch = .60
	inspection_distance = 3.65

func zoom_inspection(amount: float) -> void:
	inspection_distance = clampf(inspection_distance + amount, 2.6, 5.3)

func close_inspection() -> void:
	if inspection_id.is_empty():
		return
	inspection_id = ""
	inspection_light.visible = false
	inspection_booth = null
	_finish_drag()
	player.visible = true
	var reading: bool = bool(ui.call("is_open"))
	player.set("controls_enabled", ready_for_play and not returning and not reading)
	_set_touch_modal(reading)
	ui.call("set_inspection")
	update_camera(0, true)

func _exit_tree() -> void:
	catalog.call("detach_cloud")
	if is_instance_valid(graphics_settings) and graphics_settings.is_connected("state_changed", _apply_quality):
		graphics_settings.disconnect("state_changed", _apply_quality)
	_set_touch_modal(false)
	if requested_model and not loading_path.is_empty():
		var reaper: Node = LoadReaper.new()
		reaper.name = "UniversityPendingLoad"
		reaper.set("path", loading_path)
		get_tree().root.call_deferred("add_child", reaper)
	models.clear()
