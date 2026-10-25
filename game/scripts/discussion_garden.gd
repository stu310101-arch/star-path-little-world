extends Node3D
## Authored garden. Every device has its own stable thread and interaction.
signal room_ready
signal request_return_to_world
const IndoorPlayer = preload("res://scripts/indoor_player.gd")
const CameraRig = preload("res://scripts/admissions_camera_rig.gd")
const Protocol = preload("res://scripts/forum_protocol.gd")
const MessageDevice = preload("res://scripts/discussion_device.gd")
const Navigation = preload("res://scripts/discussion_navigation.gd")
const GardenHUD = preload("res://scripts/discussion_hud.gd")
const AvatarPrewarm = preload("res://scripts/discussion_avatar_prewarm.gd")
const LOW_GARDEN: String = "res://assets/discussion_garden/garden_low.glb"
const Architecture = preload("res://scripts/discussion_architecture.gd")
const Atmosphere = preload("res://scripts/discussion_atmosphere.gd")
const RenderOptimizer = preload("res://scripts/discussion_render_optimizer.gd")
const LoadReaper = preload("res://scripts/university_load_reaper.gd")
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const LAYOUT: String = "res://assets/discussion_garden/layout.json"
const MODELS: Array[String] = ["res://assets/discussion_garden/garden.glb", "res://assets/discussion_garden/message_device.glb"]
const TITLES: Dictionary = {"university":"大學交流區","major":"科系交流區","career":"未來就業交流區","high_school":"高中生發問區","campus":"校園討論區"}
var graphics_settings: Node
var music: Node
var player: CharacterBody3D
var camera: Camera3D
var camera_rig: Node
var account: Node
var ready_for_play: bool = false
var returning: bool = false
var detail_state: String = "waiting"
var detail_error: String = ""
var layout_path: String = LAYOUT
var layout: Dictionary = {}
var models: Array[PackedScene] = []
var model_paths: Array[String] = [MODELS[0]]
var requested_model: String = ""
var room_model: Node3D
var zones: Dictionary = {}
var nearest: Dictionary = {}
var current_zone: String = "university"
var pages: Dictionary = {}
var pending: Dictionary = {}
var attempted: Dictionary = {}
var request_serial: int = 0
var snapshot: Dictionary = {}
var camera_yaw: float = 0.0
var camera_pitch: float = .28
var camera_distance: float = 4.5
var camera_shoulder: float = 0.0
var dragging_view: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE
var hud: CanvasLayer
var ui_root: Control
var zone_label: Label
var prompt: Label
var notice: Label
var action_button: Button
var previous_button: Button
var next_button: Button
var refresh_button: Button
var compose_button: Button
var retry_button: Button
var notice_until: int = 0
var frame_counter: int = 0
var display_font: FontVariation
var render_optimizer: Node3D
var selected_device: Node3D
var selection_ring: MeshInstance3D
var destination_zone: String = ""
var route_points: Array[Vector3] = []
var proximity_clock: float = 0.0
var visibility_clock: float = 0.0
var loading_message: String = "整理步道與五個交流角落…"
var account_view_open: bool = false
var avatar_prewarm: RefCounted
var low_art_selected: bool = false

func set_shared_music(shared: Node) -> void:
	music = shared

func _ready() -> void:
	display_font = FontVariation.new()
	var scalable_font: FontFile = FONT.duplicate() as FontFile
	scalable_font.multichannel_signed_distance_field = true
	display_font.base_font = scalable_font
	display_font.variation_opentype = {2003265652: 550.0}
	add_to_group("touch_camera")
	for action: String in {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"run":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E}:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = {"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"run":KEY_SHIFT,"jump":KEY_SPACE,"interact":KEY_E}[action]
			InputMap.action_add_event(action, event)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mouse_exited.connect(_finish_drag)
	_build_environment()
	if graphics_settings == null:
		graphics_settings = get_tree().get_first_node_in_group("graphics_settings")
	if is_instance_valid(graphics_settings):
		graphics_settings.connect("state_changed", _apply_quality)
	_apply_quality()
	player = IndoorPlayer.new() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	player.call("enable_render_interpolation")
	player.set("controls_enabled", false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.call("begin_prepare_visuals")
	avatar_prewarm = AvatarPrewarm.new()
	avatar_prewarm.call("configure",player,get_tree())
	player.call("place_at", Vector3(0, .06, 15.4))
	camera = Camera3D.new()
	camera.name = "GardenCamera"
	camera.fov = 65
	camera.near = .12
	camera.far = 150
	add_child(camera)
	camera.make_current()
	_build_hud()
	account = get_node_or_null("/root/StarPathAccount")
	if account != null:
		account.connect("forum_message", receive_packet)
		account.connect("closed", _modal_closed)
		account.connect("state_changed", _account_changed)
	low_art_selected = _prefers_low_art()
	model_paths[0] = LOW_GARDEN if low_art_selected else MODELS[0]
	if get_node("/root/ResourceProfile").call("is_low"):
		model_paths[0] = "res://generated/low/discussion/garden.scn"
		layout_path = "res://generated/low/discussion/layout.json"
	_request_art()

func _prefers_low_art() -> bool:
	if not is_instance_valid(graphics_settings):
		return false
	if graphics_settings.get("quality_profile") in ["mobile","low"]:
		return true
	if graphics_settings.has_method("is_constrained_runtime"):
		return bool(graphics_settings.call("is_constrained_runtime"))
	return bool(graphics_settings.call("is_low_quality"))

static func vector(value: Variant) -> Vector3:
	if value is Array and value.size() == 3:
		return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3(INF,INF,INF)

static func valid_layout(data: Dictionary) -> bool:
	if data.get("schemaVersion") != 1 or not data.get("bounds") is Dictionary or not data.get("spawn") is Dictionary or not data.get("exit") is Dictionary or not data.get("zones") is Array or not data.get("colliders") is Array:
		return false
	if not vector(data.bounds.get("min")).is_finite() or not vector(data.bounds.get("max")).is_finite() or not vector(data.spawn.get("position")).is_finite() or not vector(data.exit.get("position")).is_finite():
		return false
	var found: Array[String] = []
	for row: Variant in data.zones:
		if not row is Dictionary or row.get("id") not in Protocol.ZONES or str(row.id) in found or not row.get("slots") is Array or row.slots.size() != 8 or not vector(row.get("center")).is_finite() or not row.get("controls") is Dictionary or not vector(row.controls.get("point")).is_finite():
			return false
		found.append(str(row.id))
		if row.has("device_model") and device_model_path(row).is_empty():
			return false
		for slot: Variant in row.slots:
			if not slot is Dictionary or not vector(slot.get("position")).is_finite():
				return false
	for row: Variant in data.colliders:
		if not row is Dictionary or not vector(row.get("center")).is_finite() or not vector(row.get("size")).is_finite():
			return false
		var size: Vector3 = vector(row.size)
		if size.x <= 0 or size.y <= 0 or size.z <= 0:
			return false
	return found.size() == 5

static func device_model_path(zone: Dictionary) -> String:
	var value: String = str(zone.get("device_model", "message_device.glb"))
	var directory: String = MODELS[1].get_base_dir()
	var filename: String = value.get_file()
	if value != filename and value != directory.path_join(filename):
		return ""
	if filename != "message_device.glb" and filename != "message_device_%s.glb" % str(zone.get("id", "")):
		return ""
	return directory.path_join(filename)

func _device_path(zone: Dictionary) -> String:
	return "res://generated/low/discussion/device.scn" if bool(layout.get("low_resources", false)) else device_model_path(zone)

func _request_art() -> void:
	detail_error = ""
	detail_state = "waiting"
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		for path: String in [LAYOUT] + model_paths:
			packs.call("request_resource", path, 200)

func _step_loading() -> void:
	if detail_state in ["ready", "error", "assembling"]:
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		for path: String in [LAYOUT] + model_paths:
			if not str(packs.call("resource_error", path)).is_empty():
				_art_error("花園素材下載失敗，請重試或返回世界。")
				return
			if not bool(packs.call("is_resource_ready", path)):
				return
	if layout.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if not parsed is Dictionary or not valid_layout(parsed):
			_art_error("花園配置尚未準備完成，請返回後重試。")
			return
		layout = parsed
		for zone: Dictionary in layout.zones:
			var path: String = _device_path(zone)
			if path not in model_paths:
				model_paths.append(path)
				if packs != null:
					packs.call("request_resource", path, 200)
		return
	detail_state = "loading"
	if models.size() < model_paths.size():
		var path: String = model_paths[models.size()]
		if requested_model.is_empty():
			if ResourceLoader.load_threaded_request(path, "PackedScene") != OK:
				_art_error("花園模型無法開始載入。")
				return
			requested_model = path
			return
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(path)
		if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
			if status == ResourceLoader.THREAD_LOAD_FAILED:
				ResourceLoader.load_threaded_get(path)
			requested_model = ""
			_art_error("花園模型載入失敗，請重試。")
			return
		if status != ResourceLoader.THREAD_LOAD_LOADED:
			return
		models.append(ResourceLoader.load_threaded_get(path) as PackedScene)
		requested_model = ""
		return
	room_model = models[0].instantiate() as Node3D
	room_model.name = "GardenArt"
	room_model.visible = false
	add_child(room_model)
	detail_state = "assembling"
	_apply_layout()

func _art_error(text: String) -> void:
	detail_state = "error"
	detail_error = text

func retry_loading() -> void:
	if ready_for_play:
		request_page(current_zone, "refresh")
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		for path: String in [LAYOUT] + model_paths:
			packs.call("retry_resource", path)
	player.call("retry_prepare_visuals")
	avatar_prewarm.call("retry")
	detail_error = ""
	if detail_state not in ["ready","assembling"]:
		_request_art()

func _collider(parent: Node3D, center: Vector3, size: Vector3, rotation_y: float = 0, camera_only: bool = false, body_name: String = "") -> void:
	var body := StaticBody3D.new()
	if not body_name.is_empty():
		body.name = body_name
	body.position = center
	body.rotation.y = rotation_y
	body.collision_layer = 256 if camera_only else 1
	body.collision_mask = 0 if camera_only else 4
	body.add_to_group("discussion_garden_collision")
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	parent.add_child(body)

func _sign(parent: Node3D, text: String, at: Vector3, rotation_y: float, small: bool = false) -> Label3D:
	var label := Label3D.new()
	label.font = display_font
	label.text = text
	label.font_size = 32 if small else 48
	label.pixel_size = .0018 if small else .003
	label.outline_size = 2
	label.outline_modulate = Color("f2e8ce") if small else Color("173b3d")
	label.modulate = Color("193e3e") if small else Color("f2e8ce")
	label.position = at
	label.rotation.y = rotation_y
	label.no_depth_test = false
	label.double_sided = false
	label.visibility_range_end = 25 if small else 70
	parent.add_child(label)
	return label

func _apply_layout() -> void:
	if not bool(layout.get("low_resources", false)):
		Architecture.build(room_model,layout)
	loading_message = "鋪好步道，準備可探索的空間…"
	var collider_count: int = 0
	for row: Dictionary in layout.colliders:
		_collider(self, vector(row.center), vector(row.size),float(row.get("rotation_y",0)),bool(row.get("camera_only",false)),str(row.get("name","GardenCollider")))
		collider_count += 1
		if collider_count % 24 == 0:
			await get_tree().process_frame
			if returning:
				return
	for zone: Dictionary in layout.zones:
		var id: String = str(zone.id)
		var row: Dictionary = zone.duplicate(true)
		row["devices"] = []
		row["labels"] = []
		row["art"] = []
		row["art_visible"] = true
		for node: Node in room_model.find_children("SM_Zone_"+id+"*", "Node3D", true, false):
			row.art.append(node)
			# Joined Blender meshes keep the hub origin. Their authored zone
			# center is the correct distance reference, not instance origin.
			if node is MeshInstance3D:
				(node as MeshInstance3D).visibility_range_end = 0
		for slot: Dictionary in zone.slots:
			var device: Node3D = MessageDevice.new()
			device.name = "Message_" + id + "_" + str(row.devices.size())
			device.position = vector(slot.position)
			device.rotation.y = float(slot.get("rotation_y", 0))
			add_child(device)
			device.add_child(models[model_paths.find(_device_path(zone))].instantiate())
			for mesh: Node in device.find_children("*","MeshInstance3D",true,false):
				(mesh as MeshInstance3D).visibility_range_end = 50
			var collider: Dictionary = layout.get("device",{}).get("collider",{"center":[0,.75,0],"size":[.84,1.5,.56]})
			_collider(device,vector(collider.center),vector(collider.size),0,false,"DeviceCollider")
			var label: Label3D = _sign(device,"尚無留言",vector(layout.get("device",{}).get("preview_anchor",[0,1.07,.18])),0,true)
			label.width = 300
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			device.call("configure",id,row.devices.size(),label)
			row.devices.append(device)
			row.labels.append(label)
			loading_message = "準備%s的留言裝置…" % str(TITLES[id])
			if row.devices.size() % 2 == 0:
				await get_tree().process_frame
				if returning:
					return
		var sign: Dictionary = zone.controls.sign
		_sign(self,str(TITLES[id]),vector(sign.position),float(sign.get("rotation_y",0)))
		zones[id] = row
		await get_tree().process_frame
		if returning:
			return
	var welcome: Label3D = _sign(self,"校園生活誌 · 交流花園",vector(layout.get("title_anchor",[0,2.9,17.3])),0)
	welcome.pixel_size = .0045
	player.call("place_at", vector(layout.spawn.position),vector(layout.spawn.get("facing",[0,0,-1])))
	_update_zone_visibility(true)
	camera_rig = CameraRig.new()
	add_child(camera_rig)
	var minimum: Vector3 = vector(layout.bounds.min)
	camera_rig.call("configure",self,camera,player,AABB(minimum,vector(layout.bounds.max)-minimum),257)
	update_camera(0,true)
	render_optimizer = RenderOptimizer.new()
	add_child(render_optimizer)
	render_optimizer.call("configure",self)
	Atmosphere.finish_surfaces(room_model)
	_build_selection_ring()
	_apply_quality()
	room_model.visible = true
	detail_state = "ready"

func _build_environment() -> void:
	Atmosphere.build(self)

func _apply_quality() -> void:
	var low: bool = not is_instance_valid(graphics_settings) or bool(graphics_settings.call("is_low_quality"))
	($GardenSun as DirectionalLight3D).shadow_enabled = not low
	if ready_for_play and _prefers_low_art() != low_art_selected:
		hud.call("show_notice","畫質設定已套用；植栽細節將在下次進入花園時更新。",false,6.0)

func _build_hud() -> void:
	hud = GardenHUD.new()
	add_child(hud)
	var elements: Dictionary = hud.call("elements")
	ui_root = elements.ui_root
	zone_label = elements.zone_label
	prompt = elements.prompt
	notice = elements.notice
	action_button = elements.action_button
	compose_button = elements.compose_button
	previous_button = elements.previous_button
	next_button = elements.next_button
	refresh_button = elements.refresh_button
	retry_button = elements.retry_button
	hud.connect("interaction_requested", activate_nearest)
	hud.connect("account_requested", func() -> void: _open_modal({"account":true}))
	hud.connect("return_requested", return_to_world)
	hud.connect("page_requested", func(direction: String) -> void: request_page(current_zone,direction))
	hud.connect("retry_requested", retry_loading)
	hud.connect("destination_requested", _select_destination)

func _resize_hud() -> void:
	if is_instance_valid(hud):
		hud.call("_resize")

func _build_selection_ring() -> void:
	# A single, unlit ground marker follows focus; no per-device ticking effects.
	selection_ring = MeshInstance3D.new()
	selection_ring.name = "ActiveDeviceRing"
	var mesh := TorusMesh.new()
	mesh.inner_radius = .66
	mesh.outer_radius = .71
	mesh.rings = 32
	mesh.ring_segments = 4
	selection_ring.mesh = mesh
	selection_ring.scale.y = .08
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("e2c68a")
	selection_ring.material_override = material
	selection_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	selection_ring.visible = false
	add_child(selection_ring)

func _update_focus() -> void:
	var device: Node3D = _nearest_device()
	if device == selected_device:
		return
	if is_instance_valid(selected_device):
		selected_device.call("set_focused",false)
	selected_device = device
	selection_ring.visible = device != null
	if device != null:
		device.call("set_focused",true)
		selection_ring.global_position = device.global_position + Vector3.UP*.025

func _update_hud() -> void:
	if not is_instance_valid(hud):
		return
	var device: Node3D = _nearest_device()
	var post: Dictionary = _nearest_post()
	var page: Dictionary = pages.get(current_zone,{})
	var route: Dictionary = _route_status()
	hud.call("update_state",{
		"ready":ready_for_play,"zone":current_zone,"kind":str(nearest.get("kind","")),
		"hub":is_instance_valid(player) and Vector2(player.position.x,player.position.z).length()<10.5 and nearest.get("kind","") not in ["post","browse"],
		"number":int(device.call("number")) if device != null else 0,
		"preview":str(post.get("preview","")),"occupied":not post.is_empty(),
		"pending":pending.has(current_zone),"has_previous":bool(page.get("hasPrevious",false)),
		"has_next":bool(page.get("hasNext",false)),"page":int(page.get("devicePage",0)),
		"error":detail_error,"loading_message":loading_message,
		"touch":OS.has_feature("web_mobile") or bool(get_meta("force_touch_controls",false)),
		"destination_zone":destination_zone,"destination_distance":route.get("distance",0),
		"destination_direction":route.get("direction","")})

func _select_destination(zone: String) -> void:
	destination_zone = zone if zones.has(zone) else ""
	route_points.clear()
	if destination_zone.is_empty():
		_update_hud()
		return
	route_points = Navigation.route(layout,player.global_position,current_zone,destination_zone)
	if route_points.is_empty():
		if Navigation.arrived(layout,player.global_position,current_zone,destination_zone):
			_arrive_at_destination()
		else:
			destination_zone = ""
			hud.call("show_notice","暫時找不到可通行的路線，請走回步道後重新選擇目的地。",false,7.0)
	_update_hud()

func _arrive_at_destination() -> void:
	if destination_zone.is_empty():
		return
	var title: String = str(TITLES[destination_zone])
	destination_zone = ""
	route_points.clear()
	hud.call("show_notice","已抵達%s，走近任一留言裝置即可交流。" % title,false,5.0)

func _route_status() -> Dictionary:
	if destination_zone.is_empty() or route_points.is_empty() or not is_instance_valid(player):
		return {}
	var here: Vector3 = player.global_position
	here.y = .06
	while not route_points.is_empty() and here.distance_to(route_points[0]) < 2.2:
		if route_points.size() > 1 and not Navigation.segment_clear(layout,here,route_points[1]):
			break
		route_points.pop_front()
	if route_points.is_empty():
		_arrive_at_destination()
		return {}
	var distance: float = here.distance_to(route_points[0])
	for index: int in range(1,route_points.size()):
		distance += route_points[index-1].distance_to(route_points[index])
	var target: Vector3 = route_points[0]-here
	var forward: Vector3 = Vector3(-sin(camera_yaw),0,-cos(camera_yaw))
	var angle: float = forward.signed_angle_to(target.normalized(),Vector3.UP)
	var direction: String = "沿步道向前"
	if absf(angle) > 2.35:
		direction = "轉身沿步道走"
	elif angle > .45:
		direction = "沿左側步道"
	elif angle < -.45:
		direction = "沿右側步道"
	return {"distance":int(ceil(distance)),"direction":direction}

func _process(delta: float) -> void:
	if returning:
		return
	_step_loading()
	if not ready_for_play:
		if bool(avatar_prewarm.call("step")):
			player.call("step_prepare_visuals")
		elif not str(avatar_prewarm.get("error")).is_empty():
			detail_error = str(avatar_prewarm.get("error"))
		if not str(player.call("visuals_error")).is_empty():
			detail_error = "角色載入未完成，請按重試。"
		_update_hud()
		if detail_state != "ready" or not bool(player.call("visuals_ready")):
			return
		avatar_prewarm.call("release_completed")
		ready_for_play = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set("controls_enabled",true)
		room_ready.emit()
		request_page(current_zone,"first")
		refresh_nearest()
	for id: String in pending.keys():
		if Time.get_ticks_msec() > int(pending[id].deadline):
			pending.erase(id)
			_show_error("留言讀取逾時，原頁保留；請按刷新重試。")
	if not snapshot.is_empty():
		return
	update_camera(delta)
	proximity_clock += delta
	visibility_clock += delta
	if proximity_clock >= .10:
		proximity_clock = 0
		refresh_nearest()
	if visibility_clock >= .20:
		visibility_clock = 0
		_update_zone_visibility()

func _update_zone_visibility(force: bool = false) -> void:
	for id: String in zones:
		var zone: Dictionary = zones[id]
		var center: Vector3 = vector(zone.center)
		center.y = player.position.y
		var distance: float = player.position.distance_to(center)
		var visible_distance: float = float(zone.get("visibility_distance", 48))
		var should_show: bool = distance < (visible_distance if zone.art_visible else visible_distance-4)
		if force or should_show != bool(zone.art_visible):
			zone.art_visible = should_show
			for mesh: Node3D in zone.art:
				mesh.visible = should_show

func refresh_nearest() -> void:
	if not ready_for_play:
		return
	nearest = {}
	var best: float = INF
	var zone_distance: float = INF
	var next_zone: String = current_zone
	for id: String in zones:
		var zone: Dictionary = zones[id]
		var separation: float = player.position.distance_to(vector(zone.center))
		if separation < zone_distance:
			zone_distance = separation
			next_zone = id
		for index: int in range(8):
			var device: Node3D = zone.devices[index]
			var distance: float = float(device.call("distance_to_player",player.global_position))
			if distance <= MessageDevice.INTERACTION_RADIUS and distance < best:
				best = distance
				nearest = {"zone":id,"slot":index,"kind":"post"}
		var control_distance: float = player.position.distance_to(vector(zone.controls.point))
		if nearest.is_empty() and control_distance < float(zone.controls.get("radius",2)):
			nearest = {"zone":id,"kind":"browse"}
	current_zone = str(nearest.get("zone",next_zone))
	if not attempted.has(current_zone) and not pending.has(current_zone):
		request_page(current_zone,"first")
	if player.position.distance_to(vector(layout.exit.position)) < float(layout.exit.radius):
		nearest = {"kind":"exit"}
	_update_focus()
	_update_hud()

func _nearest_device() -> Node3D:
	if nearest.get("kind") != "post":
		return null
	return zones[nearest.zone].devices[int(nearest.slot)] as Node3D

func _nearest_post() -> Dictionary:
	var device: Node3D = _nearest_device()
	return device.get("message") as Dictionary if device != null else {}

func activate_nearest() -> void:
	if not ready_for_play or returning or not snapshot.is_empty():
		return
	refresh_nearest()
	if nearest.get("kind") == "exit":
		return_to_world()
	elif nearest.get("kind") == "browse":
		_open_modal({"zone":nearest.zone})
	else:
		var device: Node3D = _nearest_device()
		if device != null:
			_open_modal(device.call("context") as Dictionary)

func request_page(zone: String, direction: String) -> void:
	if account == null or zone not in Protocol.ZONES or pending.has(zone):
		return
	request_serial += 1
	attempted[zone] = true
	var id: String = "garden_"+str(get_instance_id())+"_"+str(request_serial)
	pending[zone] = {"requestId":id,"deadline":Time.get_ticks_msec()+15000,"items":{},"expected":-1}
	if not bool(account.call("request_forum_page",{"zone":zone,"direction":direction,"requestId":id,"devices":true})):
		pending.erase(zone)
		_show_error("留言服務尚未連線，請確認登入後按刷新。")

func receive_packet(raw: Dictionary) -> void:
	var packet: Dictionary = Protocol.sanitize_packet(raw)
	if packet.is_empty() or not pending.has(packet.zone):
		return
	var state: Dictionary = pending[packet.zone]
	if state.requestId != packet.requestId:
		return
	if account != null and int(packet.sessionGeneration) != int((account.get("user") as Dictionary).get("sessionGeneration",-1)):
		return
	match str(packet.type):
		"page-begin":
			if int(state.expected) != -1:
				pending.erase(packet.zone)
				return
			state.expected = packet.itemCount
			state.devicePage = int(packet.get("devicePage",0))
		"page-item", "page-empty":
			if int(state.expected) < 0 or int(packet.index) >= int(state.expected) or state.items.has(int(packet.index)):
				pending.erase(packet.zone)
				return
			if str(packet.threadId) != MessageDevice.thread_for(str(packet.zone),int(state.get("devicePage",0)),int(packet.index)):
				pending.erase(packet.zone)
				_show_error("裝置留言位置不符，請按刷新重試。")
				return
			state.items[int(packet.index)] = packet
		"page-end":
			if int(state.expected) != int(packet.count) or state.items.size() != int(packet.count):
				pending.erase(packet.zone)
				_show_error("留言頁未完整送達，請刷新重試。")
				return
			var items: Array[Dictionary] = []
			for index: int in range(int(packet.count)):
				if not state.items.has(index):
					pending.erase(packet.zone)
					return
				items.append(state.items[index])
			pages[packet.zone] = {"items":items,"hasNext":packet.hasNext,"hasPrevious":packet.hasPrevious,"devicePage":int(state.get("devicePage",0))}
			pending.erase(packet.zone)
			_apply_page(str(packet.zone))
		"page-error":
			pending.erase(packet.zone)
			_show_error("留言暫時無法讀取，原頁保留；請按刷新重試。")

func _apply_page(zone: String) -> void:
	if not zones.has(zone):
		return
	var items: Array = pages[zone].items
	for index: int in range(8):
		zones[zone].devices[index].call("apply_slot",int(pages[zone].get("devicePage",0)),items[index] if index < items.size() else {})

func _open_modal(context: Dictionary) -> void:
	if account == null or not ready_for_play or returning or not snapshot.is_empty():
		return
	account_view_open = true
	snapshot = {"transform":player.global_transform,"heading":player.get("heading"),"controls":player.get("controls_enabled"),"process":player.process_mode,"camera":camera.global_transform}
	_finish_drag()
	_release_inputs()
	player.set("controls_enabled",false)
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	hud.hide()
	var accepted: bool = bool(account.call("open_view","account")) if context.get("account",false) else bool(account.call("open_forum",context))
	if not accepted:
		_modal_closed()
		_show_error("留言面板尚未準備完成，請稍後重試。")

func _modal_closed() -> void:
	account_view_open = false
	if snapshot.is_empty() or not is_instance_valid(player):
		return
	_release_inputs()
	player.global_transform = snapshot.transform
	player.set("heading",snapshot.heading)
	player.set("controls_enabled",snapshot.controls)
	player.process_mode = snapshot.process
	player.velocity = Vector3.ZERO
	player.call("reset_render_interpolation")
	camera.global_transform = snapshot.camera
	snapshot.clear()
	hud.show()
	pending.erase(current_zone)
	request_page(current_zone,"refresh")

func _account_changed(_user: Dictionary) -> void:
	pending.clear()
	attempted.clear()
	pages.clear()
	for zone: String in zones:
		pages[zone] = {"items":[],"hasNext":false,"hasPrevious":false}
		_apply_page(zone)
	pages.clear()

func _show_error(text: String) -> void:
	hud.call("show_notice",text,true,8.0)

func _release_inputs() -> void:
	get_node("/root/WebTouch").call("reset_input")
	for action: String in ["move_left","move_right","move_forward","move_back","run","jump","interact"]:
		Input.action_release(action)

func _input(event: InputEvent) -> void:
	if not snapshot.is_empty() or returning or not ready_for_play:
		return
	if event is InputEventMouseButton and not event.pressed and event.button_index == drag_button:
		_finish_drag()
	elif event is InputEventMouseMotion and dragging_view:
		touch_look(event.relative)

func _unhandled_input(event: InputEvent) -> void:
	if returning:
		return
	if event.is_action_pressed("ui_cancel"):
		if not snapshot.is_empty():
			account.call("close_view")
		elif not bool(hud.call("close_guide")):
			return_to_world()
		get_viewport().set_input_as_handled()
	elif snapshot.is_empty() and ready_for_play:
		if event.is_action_pressed("interact") and not event.is_echo():
			activate_nearest()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.pressed:
			if event.button_index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
				dragging_view = true
				drag_button = event.button_index
			elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = maxf(2.5,camera_distance-.3)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = minf(7,camera_distance+.3)

func touch_look(relative: Vector2) -> void:
	if not ready_for_play or returning or not snapshot.is_empty():
		return
	camera_yaw -= relative.x*.005
	camera_pitch = clampf(camera_pitch+relative.y*.004,-.08,.75)
	player.call("rotate_heading",-relative.x*.005)

func _finish_drag() -> void:
	dragging_view = false
	drag_button = MOUSE_BUTTON_NONE

func can_player_jump() -> bool:
	return ready_for_play and not returning and snapshot.is_empty()

func update_camera(delta: float, snap: bool = false) -> void:
	if camera_rig == null or not snapshot.is_empty():
		return
	var frame: Transform3D = player.call("get_render_transform")
	var shoulder_target: float = 1.25 if _nearest_device() != null else 0.0
	camera_shoulder = shoulder_target if snap else lerpf(camera_shoulder,shoulder_target,1.0-exp(-delta*5.0))
	var right: Vector3 = Vector3(cos(camera_yaw),0,-sin(camera_yaw))
	var aim: Vector3 = frame.origin+Vector3.UP*1.15
	var offset: Vector3 = Vector3(sin(camera_yaw)*cos(camera_pitch),sin(camera_pitch),cos(camera_yaw)*cos(camera_pitch))*camera_distance
	camera_rig.call("follow",aim,aim+offset+right*camera_shoulder,delta,snap)

func return_to_world() -> void:
	if returning:
		return
	if not snapshot.is_empty():
		account.call("close_view")
	returning = true
	pending.clear()
	_release_inputs()
	player.set("controls_enabled",false)
	if request_return_to_world.get_connections().is_empty():
		get_tree().change_scene_to_file.call_deferred(str(get_node("/root/ResourceProfile").call("world_path")))
	else:
		request_return_to_world.emit()

func _exit_tree() -> void:
	if avatar_prewarm != null:
		avatar_prewarm.call("cancel")
	if is_instance_valid(graphics_settings) and graphics_settings.is_connected("state_changed", _apply_quality):
		graphics_settings.disconnect("state_changed", _apply_quality)
	if not requested_model.is_empty():
		var reaper: Node = LoadReaper.new()
		reaper.name = "DiscussionPendingLoad"
		reaper.process_mode = Node.PROCESS_MODE_ALWAYS
		reaper.set("path", requested_model)
		get_tree().root.call_deferred("add_child", reaper)
		requested_model = ""
