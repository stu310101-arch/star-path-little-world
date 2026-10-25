extends Node3D
## Authored warm window interest room, loaded only after entering the room.
## The Blender model owns appearance; layout metadata owns physical interaction.

signal room_ready
signal request_return_to_world

const IndoorPlayer = preload("res://scripts/indoor_player.gd")
const AccountSession = preload("res://scripts/account_session.gd")
const INTEREST_PANEL_PATH: String = "res://scripts/interest_panel.gd"
const FurnitureInteraction = preload("res://scripts/admissions_furniture_interaction.gd")
const GraphicsProfile = preload("res://scripts/graphics_settings.gd")
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const WORLD_SCENE: String = "res://scenes/world.tscn"
const EXIT: Vector3 = Vector3(0, .06, 4.83)
var model_path: String = "res://assets/counseling_room/counseling_room.glb"
var layout_path: String = "res://assets/counseling_room/layout.json"
const CAMERA_RIG_PATH: String = "res://scripts/admissions_camera_rig.gd"
const EXPECTED_VIEWS: Array[String] = ["interest_high1", "interest_high3", "exit"]

var graphics_settings: Node
var low_quality: bool = true
var _mobile_touch: bool = false
var music: Node
var player: CharacterBody3D
var camera: Camera3D
var account: Node
var interest_panel: Control
var panel_snapshot: Dictionary = {}
var _return_after_close: bool = false
var seats: Node
var hud: CanvasLayer
var ready_for_play: bool = false
var returning: bool = false
var camera_yaw: float = 0.0
var camera_pitch: float = .30
var camera_distance: float = 3.1
var dragging_view: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE
var camera_rig: Node
var room_model: Node3D
var layout: Dictionary = {}
var detail_state: String = "idle"
var detail_error: String = ""
var requested_model: bool = false
var ready_ms: int = 0
var started_ms: int = 0
var max_load_operation_ms: float = 0.0
var room_bounds: AABB = AABB(Vector3(-6.5, 0, -5.5), Vector3(13, 4.6, 11))
var stations: Array[Dictionary] = []
var nearest: Dictionary = {}
var display_font: FontVariation
var prompt: Label
var action_button: Button
var seated_workbench_button: Button
var notice: Label
var retry_button: Button
var ui_root: Control
var _notice_until: int = 0

func set_shared_music(shared: Node) -> void:
	music = shared

func _ready() -> void:
	var resources: Node = get_node_or_null("/root/ResourceProfile")
	if resources != null and bool(resources.call("is_low")):
		model_path = "res://generated/low/counseling/room.scn"
		layout_path = "res://generated/low/counseling/layout.json"
	add_to_group("touch_camera")
	_setup_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mouse_exited.connect(_finish_drag)
	started_ms = Time.get_ticks_msec()
	_mobile_touch = GraphicsProfile.is_mobile_web()
	if graphics_settings == null:
		graphics_settings = get_tree().get_first_node_in_group("graphics_settings")
	if is_instance_valid(graphics_settings):
		graphics_settings.connect("state_changed", _apply_quality)
	_prepare_display_font()
	_build_lighting()
	_apply_quality()
	player = IndoorPlayer.new() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	player.call("enable_render_interpolation")
	player.set("controls_enabled", false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.call("begin_prepare_visuals")
	player.call("place_at", Vector3(0, .09, 2.8), Vector3.FORWARD)
	camera = Camera3D.new()
	camera.name = "RoomCamera"
	camera.fov = 62.0
	camera.near = .12
	camera.far = 60.0
	add_child(camera)
	camera.make_current()
	_build_hud()
	account = get_tree().root.get_node_or_null("StarPathAccount")
	if account == null:
		account = AccountSession.new()
		account.name = "StarPathAccount"
		get_tree().root.add_child.call_deferred(account)
	_request_models()
	add_child(preload("res://scripts/interest_diagnostics.gd").new())

func _prepare_display_font() -> void:
	display_font = FontVariation.new()
	var scalable_font: FontFile = FONT.duplicate() as FontFile
	scalable_font.multichannel_signed_distance_field = true
	display_font.base_font = scalable_font
	display_font.variation_opentype = {2003265652: 550.0}

func _vector(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() == 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return Vector3(INF, INF, INF)

func _valid_layout(data: Dictionary) -> bool:
	if int(data.get("schemaVersion", 0)) != 1 or not data.get("bounds") is Dictionary:
		return false
	var bounds_data: Dictionary = data.bounds as Dictionary
	var minimum: Vector3 = _vector(bounds_data.get("min"))
	var maximum: Vector3 = _vector(bounds_data.get("max"))
	if not minimum.is_finite() or not maximum.is_finite():
		return false
	if maximum.x <= minimum.x or maximum.y <= minimum.y or maximum.z <= minimum.z:
		return false
	if not data.get("spawn") is Dictionary or not _vector((data.spawn as Dictionary).get("position")).is_finite():
		return false
	var facing: Vector3 = _vector((data.spawn as Dictionary).get("facing", [0, 0, -1]))
	if not facing.is_finite() or facing.slide(Vector3.UP).length_squared() < .01:
		return false
	if not data.get("colliders") is Array or not data.get("stations") is Array:
		return false
	for entry: Variant in data.colliders as Array:
		if not entry is Dictionary:
			return false
		var row: Dictionary = entry as Dictionary
		var center: Vector3 = _vector(row.get("center"))
		var size: Vector3 = _vector(row.get("size"))
		if not center.is_finite() or not size.is_finite() or size.x <= 0 or size.y <= 0 or size.z <= 0 or not is_finite(float(row.get("rotation_y", 0.0))):
			return false
	var views: Array[String] = []
	for entry: Variant in data.stations as Array:
		if not entry is Dictionary:
			return false
		var row: Dictionary = entry as Dictionary
		var view: String = str(row.get("view", ""))
		var radius: float = float(row.get("radius", 1.5))
		if view not in EXPECTED_VIEWS or view in views or not _vector(row.get("approach")).is_finite() or not is_finite(radius) or radius <= 0.0:
			return false
		if row.has("sign") and (not row.sign is Dictionary or not _vector((row.sign as Dictionary).get("position")).is_finite()):
			return false
		for field: String in ["focus_camera", "focus_target"]:
			if row.has(field) and not _vector(row[field]).is_finite():
				return false
		views.append(view)
	return views.size() == EXPECTED_VIEWS.size()

func _request_models() -> void:
	detail_error = ""
	detail_state = "waiting"
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("request_resource", layout_path, 200)
		packs.call("request_resource", model_path, 200)

func _loading_failed(message: String) -> void:
	detail_error = message
	detail_state = "error"
	requested_model = false

func _step_loading() -> void:
	if detail_state in ["ready", "error"]:
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		for path: String in [layout_path, model_path]:
			if not str(packs.call("resource_error", path)).is_empty():
				_loading_failed("暖窗書房下載失敗，可以重試或返回世界。")
				return
			if not bool(packs.call("is_resource_ready", path)):
				return
	if layout.is_empty():
		if not FileAccess.file_exists(layout_path):
			_loading_failed("暖窗書房配置尚未準備完成，可以重試或返回。")
			return
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(layout_path))
		if not parsed is Dictionary or not _valid_layout(parsed as Dictionary):
			_loading_failed("暖窗書房配置不完整，請返回後重試。")
			return
		layout = parsed as Dictionary
		detail_state = "loading"
		return
	if not requested_model:
		var result: Error = ResourceLoader.load_threaded_request(model_path, "PackedScene", true, ResourceLoader.CACHE_MODE_REUSE)
		if result != OK:
			_loading_failed("暖窗書房模型無法開始載入，可以重試或返回。")
			return
		requested_model = true
		return
	var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(model_path)
	if status in [ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE]:
		if status == ResourceLoader.THREAD_LOAD_FAILED:
			ResourceLoader.load_threaded_get(model_path)
		_loading_failed("暖窗書房模型載入失敗，可以重試或返回。")
		return
	if status != ResourceLoader.THREAD_LOAD_LOADED:
		return
	var operation_started: int = Time.get_ticks_usec()
	var packed: PackedScene = ResourceLoader.load_threaded_get(model_path) as PackedScene
	requested_model = false
	if packed == null:
		_loading_failed("暖窗書房模型格式無法讀取，可以返回後重試。")
		return
	var rig_script: Script = load(CAMERA_RIG_PATH) as Script
	if rig_script == null or not rig_script.can_instantiate():
		_loading_failed("室內鏡頭尚未準備完成，請返回後重試。")
		return
	var instance: Node = packed.instantiate()
	if not instance is Node3D:
		instance.free()
		_loading_failed("暖窗書房場景格式無法讀取。")
		return
	room_model = instance as Node3D
	room_model.name = "CounselingArt"
	add_child(room_model)
	_apply_layout(rig_script)
	max_load_operation_ms = float(Time.get_ticks_usec() - operation_started) / 1000.0
	detail_state = "ready"

func _apply_layout(rig_script: Script) -> void:
	var bounds_data: Dictionary = layout.bounds as Dictionary
	var minimum: Vector3 = _vector(bounds_data.min)
	room_bounds = AABB(minimum, _vector(bounds_data.max) - minimum)
	for row: Dictionary in layout.colliders as Array:
		var body: StaticBody3D = StaticBody3D.new()
		body.name = str(row.get("id", "Furniture")).validate_node_name()
		body.position = _vector(row.center)
		body.rotation.y = float(row.get("rotation_y", 0.0))
		var camera_only: bool = bool(row.get("camera_only", false))
		body.collision_layer = 256 if camera_only else 1
		body.collision_mask = 0 if camera_only else 4
		body.add_to_group("counseling_room_collision")
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = _vector(row.size)
		var collision: CollisionShape3D = CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		add_child(body)
	for row: Dictionary in layout.stations as Array:
		var station: Dictionary = row.duplicate(true)
		station["point"] = _vector(row.approach)
		station["radius"] = float(row.get("radius", 1.5))
		station["title"] = str(row.get("title", row.view))
		station["subtitle"] = str(row.get("subtitle", ""))
		stations.append(station)
		if row.has("sign"):
			_add_station_sign(station)
	for display: Dictionary in layout.get("displays", []):
		_add_station_sign(display)
	var spawn_data: Dictionary = layout.spawn as Dictionary
	var facing: Vector3 = _vector(spawn_data.get("facing", [0, 0, -1]))
	player.call("place_at", _vector(spawn_data.position), facing)
	camera_rig = rig_script.new() as Node
	camera_rig.name = "CameraRig"
	add_child(camera_rig)
	camera_rig.call("configure", self, camera, player, room_bounds, 257)
	seats = FurnitureInteraction.new() as Node
	seats.name = "FurnitureInteraction"
	add_child(seats)
	seats.call("configure", self, player, layout)
	update_camera(0, true)

func _add_station_sign(station: Dictionary) -> void:
	var sign_data: Dictionary = station.sign as Dictionary
	var label: Label3D = Label3D.new()
	label.name = "StationLabel_" + str(station.view)
	label.text = str(station.title)
	label.font = display_font
	label.font_size = 64
	var text_width: float = display_font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 64).x
	label.pixel_size = clampf(float(sign_data.get("width", .9)) / maxf(text_width, 1), .001, .006)
	label.modulate = Color(str(sign_data.get("color", "244954")))
	label.outline_size = 0
	label.shaded = false
	label.position = _vector(sign_data.position)
	label.rotation.y = float(sign_data.get("rotation_y", 0.0))
	add_child(label)

func retry_loading() -> void:
	if ready_for_play or returning:
		return
	var packs: Node = get_node_or_null("/root/WebPacks")
	if packs != null:
		packs.call("retry_resource", model_path)
		packs.call("retry_resource", layout_path)
	player.call("retry_prepare_visuals")
	if detail_state != "ready":
		layout.clear()
		_request_models()

func _build_lighting() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("dce6dc")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e1e8e5")
	environment.ambient_light_energy = .38
	var sky_material: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("8b9fab")
	sky_material.sky_horizon_color = Color("dcd9c9")
	sky_material.ground_horizon_color = Color("918679")
	sky_material.ground_bottom_color = Color("5b554b")
	sky_material.sky_energy_multiplier = .45
	var sky: Sky = Sky.new()
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "CounselingEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.name = "WindowDaylight"
	sun.rotation_degrees = Vector3(-48, -38, 0)
	sun.light_color = Color("fff7e7")
	sun.light_energy = .04
	sun.directional_shadow_max_distance = 24.0
	sun.shadow_bias = .12
	sun.shadow_normal_bias = .7
	sun.shadow_enabled = true
	add_child(sun)
	# Window bounce lives inside the deep west reveal. Its direction gives the
	# desks and joinery form without an unmotivated pool from above the ceiling.
	var window: SpotLight3D = SpotLight3D.new()
	window.name = "WestWindowBounce"
	window.position = Vector3(-5.05, 2.65, -.55)
	window.light_color = Color("fff2d9")
	window.light_energy = .24
	window.spot_range = 13.0
	window.spot_angle = 76
	window.spot_attenuation = .35
	window.shadow_enabled = true
	window.shadow_bias = .8
	window.shadow_normal_bias = 3.0
	add_child(window)
	window.look_at(Vector3(1.8, .15, -1.8), Vector3.UP)
	var fill: OmniLight3D = OmniLight3D.new()
	fill.name = "EastWindowFill"
	fill.position = Vector3(4.95, 2.3, .1)
	fill.light_color = Color("e5edf0")
	fill.light_energy = .06
	fill.omni_range = 9
	fill.shadow_enabled = false
	add_child(fill)
	var lamp: OmniLight3D = OmniLight3D.new()
	lamp.name = "ReadingLampGlow"
	lamp.position = Vector3(-4.75, 1.54, -1.27)
	lamp.light_color = Color("ffdeb3")
	lamp.light_energy = .20
	lamp.omni_range = 2.6
	lamp.omni_attenuation = 1.4
	lamp.shadow_enabled = false
	add_child(lamp)

func _apply_quality() -> void:
	low_quality = bool(graphics_settings.call("is_low_quality")) if is_instance_valid(graphics_settings) else str(get_viewport().get_meta("graphics_quality_profile", "low")) in ["mobile", "balanced", "low"]
	if is_instance_valid(graphics_settings) and graphics_settings.has_method("is_constrained_runtime"):
		low_quality = low_quality or bool(graphics_settings.call("is_constrained_runtime"))
	# Room lights are created after the outdoor settings service applies its
	# profile. Apply the same shadow budget here, including live profile changes.
	for light_name: String in ["WindowDaylight", "WestWindowBounce"]:
		var light: Light3D = get_node_or_null(light_name) as Light3D
		if light != null:
			light.shadow_enabled = not low_quality

func _panel(color: String) -> StyleBoxFlat:
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = Color(color)
	panel.set_corner_radius_all(12)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 10
	panel.content_margin_bottom = 10
	return panel

func _label(text_value: String, size: int, color: String = "f0e6d1") -> Label:
	var label: Label = Label.new()
	label.text = text_value
	label.add_theme_font_override("font", display_font)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(color))
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(text_value: String, action: Callable) -> Button:
	var button: Button = Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 46
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_override("font", display_font)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", Color("17383f"))
	button.add_theme_stylebox_override("normal", _panel("f0e6d1"))
	button.add_theme_stylebox_override("hover", _panel("d4ac60"))
	button.add_theme_stylebox_override("pressed", _panel("b6d2c4"))
	button.pressed.connect(action)
	return button

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "RoomHUD"
	add_child(hud)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(ui_root)
	var top: HBoxContainer = HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 18
	top.offset_right = -18
	top.offset_top = 18
	top.add_theme_constant_override("separation", 10)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(top)
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _panel("17383fee"))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(badge)
	var words: VBoxContainer = VBoxContainer.new()
	badge.add_child(words)
	words.add_child(_label("第一站 · 輔導室", 25))
	words.add_child(_label("暖窗書房 · 發現自己的方向", 15, "b6d2c4"))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var account_button: Button = _button("我的興趣量表", open_interest_panel)
	account_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(account_button)
	var exit_button: Button = _button("返回世界", _return_immediately)
	exit_button.name = "ReturnToWorld"
	exit_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(exit_button)
	var bottom: PanelContainer = PanelContainer.new()
	ui_root.add_child(bottom)
	bottom.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.offset_left = -225
	bottom.offset_right = 225
	bottom.offset_top = -176
	bottom.offset_bottom = -22
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_stylebox_override("panel", _panel("17383fed"))
	var column: VBoxContainer = VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(column)
	prompt = _label("正在準備角色…", 20)
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(prompt)
	action_button = _button("開啟工作桌", activate_nearest)
	action_button.name = "UseWorkbench"
	column.add_child(action_button)
	seated_workbench_button = _button("使用工作桌", _open_seated_workbench)
	seated_workbench_button.name = "SeatedWorkbench"
	seated_workbench_button.visible = false
	column.add_child(seated_workbench_button)
	notice = _label("WASD 移動・拖曳轉向・靠近後按 E", 14, "b6d2c4")
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(notice)
	retry_button = _button("重試載入", retry_loading)
	retry_button.visible = false
	column.add_child(retry_button)
	get_viewport().size_changed.connect(_resize_hud)
	_resize_hud()

func _resize_hud() -> void:
	if hud == null:
		return
	# Keep 46px touch targets after the world's expanded 960px mobile canvas
	# and rendering-resolution settings; do not scale them down with 3D quality.
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var display_width: float = float(get_window().size.x)
	var safe: Vector4 = Vector4.ZERO
	if OS.has_feature("web"):
		display_width = float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
		var values: Variant = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.LittleWorldTouchUI?.safeArea() || [0,0,0,0])")))
		if values is Array and (values as Array).size() == 4:
			safe = Vector4(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	var density: float = maxf(.25, logical.x / maxf(1.0, display_width))
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	ui_root.scale = Vector2.ONE * density
	ui_root.position = Vector2(safe.x, safe.y) * density
	ui_root.size = logical / density - Vector2(safe.x + safe.z, safe.y + safe.w)
	var width: float = ui_root.size.x
	var short_landscape: bool = ui_root.size.y < 500 and width > ui_root.size.y
	var top: HBoxContainer = ui_root.get_child(0) as HBoxContainer
	var badge: PanelContainer = top.get_child(0) as PanelContainer
	badge.visible = width >= 1000
	var bottom: PanelContainer = ui_root.get_child(1) as PanelContainer
	var half: float = minf(225, width * .46)
	bottom.offset_left = -half
	bottom.offset_right = half
	bottom.offset_bottom = -24 if width >= 640 else -155
	var idle_hint: bool = ready_for_play and not action_button.visible
	bottom.offset_top = bottom.offset_bottom - (48 if idle_hint else (118 if short_landscape else 154)) - (53 if seated_workbench_button.visible else 0)
	prompt.visible = not short_landscape and not idle_hint

func _setup_input() -> void:
	var keys: Dictionary = {"move_left":KEY_A, "move_right":KEY_D, "move_forward":KEY_W, "move_back":KEY_S, "run":KEY_SHIFT, "jump":KEY_SPACE, "interact":KEY_E, "seated_workbench":KEY_F}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event: InputEventKey = InputEventKey.new()
			event.physical_keycode = int(keys[action]) as Key
			InputMap.action_add_event(action, event)

func _modal_open() -> bool:
	return is_instance_valid(interest_panel)

func _process(delta: float) -> void:
	if returning:
		return
	_step_loading()
	if not ready_for_play:
		player.call("step_prepare_visuals")
		var error: String = detail_error if not detail_error.is_empty() else str(player.call("visuals_error"))
		retry_button.visible = not error.is_empty()
		prompt.text = error if not error.is_empty() else ("正在準備角色…" if detail_state == "ready" else "正在準備暖窗書房…")
		prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		action_button.disabled = true
		notice.text = "可隨時返回世界；資料下載完成後開放移動"
		if detail_state != "ready" or not bool(player.call("visuals_ready")):
			return
		ready_for_play = true
		ready_ms = Time.get_ticks_msec() - started_ms
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set("controls_enabled", true)
		room_ready.emit()
		print("COUNSELING_ROOM_READY milliseconds=", ready_ms, " model_operation_ms=", max_load_operation_ms)
	if _modal_open():
		return
	update_camera(delta)
	refresh_nearest()

func nearest_station(at: Vector3) -> Dictionary:
	var chosen: Dictionary = {}
	var distance: float = INF
	for station: Dictionary in stations:
		var separation: float = at.distance_to(station.point as Vector3)
		if separation <= float(station.radius) and separation < distance:
			chosen = station
			distance = separation
	return chosen

func refresh_nearest() -> void:
	if player == null or not ready_for_play:
		return
	nearest = nearest_station(player.global_position)
	if seats != null:
		nearest = seats.get("active") as Dictionary if bool(seats.call("is_active")) else seats.call("prefer_target", nearest) as Dictionary
	var touch: bool = bool(get_meta("force_touch_controls", false)) or _mobile_touch
	var prefix: String = "點擊 · " if touch else "E · "
	var seated: bool = seats != null and bool(seats.call("is_seated"))
	var has_workbench: bool = seated and not str(seats.call("associated_view")).is_empty()
	var show_action: bool = not nearest.is_empty()
	if seated_workbench_button.visible != has_workbench or action_button.visible != show_action:
		seated_workbench_button.visible = has_workbench
		action_button.visible = show_action
		_resize_hud()
	seated_workbench_button.text = "使用工作桌" if touch else "F · 使用工作桌"
	if seats != null and bool(seats.call("is_active")):
		action_button.disabled = bool(seats.call("is_transitioning"))
		action_button.text = "請稍候…" if action_button.disabled else prefix + "起身"
		prompt.text = str(nearest.get("title", "座椅"))
		notice.text = str(seats.call("status_text"))
		return
	action_button.disabled = nearest.is_empty()
	if str(nearest.get("kind", "")) == "seat":
		action_button.text = prefix + "坐下"
		prompt.text = str(nearest.title)
		notice.text = "坐下休息，起身後可繼續探索"
		return
	action_button.text = "請走近工作桌" if nearest.is_empty() else (prefix + "返回世界" if str(nearest.view) == "exit" else prefix + "開啟" + str(nearest.title))
	prompt.text = "走近量表桌，整理你的興趣" if nearest.is_empty() else str(nearest.title)
	if Time.get_ticks_msec() >= _notice_until:
		notice.text = ("左側搖桿移動・右側拖曳轉向" if touch else "WASD 移動・拖曳轉向・靠近後按 E") if nearest.is_empty() else str(nearest.subtitle)

func activate_nearest() -> void:
	if not ready_for_play or returning or _modal_open():
		return
	refresh_nearest()
	if seats != null and (bool(seats.call("is_active")) or str(nearest.get("kind", "")) == "seat"):
		seats.call("interact", nearest)
		return
	if nearest.is_empty():
		return
	if str(nearest.view) == "exit":
		_return_immediately()
	else:
		open_station(str(nearest.view))

func open_station(view: String) -> void:
	if not ready_for_play or returning or _modal_open():
		return
	if seats != null and bool(seats.call("is_transitioning")):
		return
	if view in ["interest", "interest_high1", "interest_high3"]:
		open_interest_panel("high1" if view == "interest_high1" else ("high3" if view == "interest_high3" else ""))


func open_interest_panel(stage: String = "") -> void:
	if not ready_for_play or returning or _modal_open():
		return
	if seats != null and bool(seats.call("is_transitioning")):
		return
	var panel_script: Script = load(INTEREST_PANEL_PATH) as Script
	if panel_script == null:
		_show_error("興趣量表尚未準備完成，請稍後重試。")
		return
	panel_snapshot = {"transform":player.global_transform, "heading":player.get("heading"),
		"controls":player.get("controls_enabled"), "process_mode":player.process_mode,
		"camera_transform":camera.global_transform, "camera_fov":camera.fov,
		"camera_yaw":camera_yaw, "camera_pitch":camera_pitch, "camera_distance":camera_distance}
	_finish_drag()
	_clear_modal_inputs(true)
	player.set("controls_enabled", false)
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	ui_root.hide()
	interest_panel = panel_script.new() as Control
	interest_panel.name = "InterestPanel"
	hud.add_child(interest_panel)
	interest_panel.connect("closed", _interest_panel_closed)
	interest_panel.call("configure", account)
	interest_panel.call("open_panel", stage)

func _interest_panel_closed() -> void:
	if not is_instance_valid(interest_panel):
		return
	interest_panel.queue_free()
	interest_panel = null
	_clear_modal_inputs(false)
	player.global_transform = panel_snapshot.transform as Transform3D
	player.set("heading", panel_snapshot.heading)
	player.set("controls_enabled", panel_snapshot.controls)
	player.process_mode = panel_snapshot.process_mode
	player.velocity = Vector3.ZERO
	player.call("reset_render_interpolation")
	camera.global_transform = panel_snapshot.camera_transform as Transform3D
	camera.fov = float(panel_snapshot.camera_fov)
	camera_yaw = float(panel_snapshot.camera_yaw)
	camera_pitch = float(panel_snapshot.camera_pitch)
	camera_distance = float(panel_snapshot.camera_distance)
	if camera_rig != null:
		camera_rig.call("reset_follow")
	panel_snapshot.clear()
	ui_root.show()
	get_viewport().gui_release_focus()
	refresh_nearest()
	if _return_after_close:
		_return_after_close = false
		_return_immediately()

func _clear_modal_inputs(modal: bool) -> void:
	_release_inputs()
	if player.has_method("cancel_jump_input"):
		player.call("cancel_jump_input")
	var touch: Node = get_node_or_null("/root/WebTouch")
	if touch != null:
		touch.call("reset_input")
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldTouchUI")
		if bridge != null:
			bridge.setModalOpen(modal)

func _open_seated_workbench() -> void:
	if seats != null and ready_for_play and not returning and not _modal_open():
		seats.call("open_workbench")

func get_account_focus(view: String) -> Dictionary:
	for station: Dictionary in stations:
		if str(station.view) != view:
			continue
		var point: Vector3 = station.point as Vector3
		var camera_point: Vector3 = _vector(station.get("focus_camera", [point.x, 2.1, point.z + 2.8]))
		var target: Vector3 = _vector(station.get("focus_target", [point.x, .95, point.z - 1.2]))
		return {"focus_camera":camera_point, "focus_target":target, "fov":float(station.get("focus_fov", 48.0))}
	return {}

func begin_account_focus(view: String) -> bool:
	_finish_drag()
	if camera_rig == null:
		return false
	return bool(await camera_rig.call("focus_to", get_account_focus(view)))

func end_account_focus() -> void:
	if camera_rig != null:
		camera_rig.call("reset_follow")

func _show_error(message: String) -> void:
	notice.text = message
	_notice_until = Time.get_ticks_msec() + 8000

func _input(event: InputEvent) -> void:
	if _modal_open() or returning or not ready_for_play:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if not button.pressed and button.button_index == drag_button:
			_finish_drag()
	elif event is InputEventMouseMotion and dragging_view:
		touch_look((event as InputEventMouseMotion).relative)

func _unhandled_input(event: InputEvent) -> void:
	if _modal_open() or returning:
		return
	if event.is_action_pressed("ui_cancel"):
		if seats != null and bool(seats.call("handle_cancel")):
			get_viewport().set_input_as_handled()
			return
		_return_immediately()
		get_viewport().set_input_as_handled()
		return
	if not ready_for_play:
		return
	if event.is_action_pressed("interact") and not event.is_echo():
		activate_nearest()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("seated_workbench") and not event.is_echo():
		_open_seated_workbench()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.pressed and button.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging_view = true
			drag_button = button.button_index
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(2.2, camera_distance - .35)
		elif button.pressed and button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(6.5, camera_distance + .35)

func touch_look(relative: Vector2) -> void:
	if not ready_for_play or returning or _modal_open():
		return
	camera_yaw -= relative.x * .005
	camera_pitch = clampf(camera_pitch + relative.y * .004, -.08, .66)
	if seats == null or not bool(seats.call("is_active")):
		player.call("rotate_heading", -relative.x * .005)

func _finish_drag() -> void:
	dragging_view = false
	drag_button = MOUSE_BUTTON_NONE

func can_player_jump() -> bool:
	return ready_for_play and not returning and not _modal_open() and (seats == null or not bool(seats.call("is_active")))

func update_camera(delta: float, snap: bool = false) -> void:
	if camera == null or player == null or camera_rig == null or _modal_open():
		return
	var frame: Transform3D = player.call("get_render_transform") as Transform3D
	var aim: Vector3 = frame.origin + Vector3.UP * 1.15
	var offset: Vector3 = Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	camera_rig.call("follow", aim, aim + offset, delta, snap)

func _release_inputs() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "jump", "run", "interact", "seated_workbench"]:
		Input.action_release(action)

func _return_immediately() -> void:
	if returning:
		return
	if _modal_open():
		_return_after_close = true
		interest_panel.call("request_close")
		return
	if seats != null:
		seats.call("reset")
	_finish_drag()
	_release_inputs()
	returning = true
	player.set("controls_enabled", false)
	player.velocity = Vector3.ZERO
	if request_return_to_world.get_connections().is_empty():
		_return_to_main_scene.call_deferred()
	else:
		request_return_to_world.emit()

func _return_to_main_scene() -> void:
	var result: Error = get_tree().change_scene_to_file(WORLD_SCENE)
	if result != OK:
		returning = false
		player.set("controls_enabled", ready_for_play)
		_show_error("世界載入失敗，請再按返回重試。")

func _exit_tree() -> void:
	if is_instance_valid(graphics_settings) and graphics_settings.is_connected("state_changed", _apply_quality):
		graphics_settings.disconnect("state_changed", _apply_quality)
