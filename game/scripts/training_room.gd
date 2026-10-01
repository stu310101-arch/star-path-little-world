extends Node3D

signal room_ready
signal request_return_to_world

const IndoorPlayer = preload("res://scripts/indoor_player.gd")
const Projector = preload("res://scripts/training_projector.gd")
const RoomInteractions = preload("res://scripts/training_room_interactions.gd")
const FurnitureActions = preload("res://scripts/training_room_props.gd")
const ROOM_MODEL: String = "res://assets/training_room/wordking_training_room.glb"
const ROOM_LAYOUT: String = "res://assets/training_room/layout.json"
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")

var player: CharacterBody3D
var camera: Camera3D
var music: Node
var room_model: Node3D
var ready_for_play: bool = false
var returning: bool = false
var exit_point: Vector3 = Vector3(0, .04, 8.48)
var camera_yaw: float = 0.0
var camera_pitch: float = .30
var camera_distance: float = 4.2
var dragging_view: bool = false
var drag_button: MouseButton = MOUSE_BUTTON_NONE
var return_prompt: Label
var music_button: Button
var ui_root: Control
var ui_font: FontVariation
var status_clock: float = 0.0
var performance_enabled: bool = false
var layout: Dictionary = {}
var interactions: Node
var furniture_actions: Node3D

func set_shared_music(music_node: Node) -> void:
	music = music_node

func _ready() -> void:
	name = "TrainingRoom"
	if OS.has_feature("web"):
		performance_enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	_setup_input()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_window().mouse_exited.connect(_finish_drag)
	layout = JSON.parse_string(FileAccess.get_file_as_string(ROOM_LAYOUT)) as Dictionary
	room_model = (load(ROOM_MODEL) as PackedScene).instantiate() as Node3D
	room_model.name = "RoomArt"
	add_child(room_model)
	_build_collision()
	_build_lighting()
	var projection: Node3D = Projector.new() as Node3D
	add_child(projection)
	projection.call("configure", room_model, _vector(layout.get("device", [.65, .034, -.8]) as Array))
	player = IndoorPlayer.new() as CharacterBody3D
	player.name = "Player"
	add_child(player)
	player.set("controls_enabled", false)
	player.process_mode = Node.PROCESS_MODE_DISABLED
	player.call("begin_prepare_visuals")
	player.call("place_at", Vector3(0, .09, 6.2), Vector3.FORWARD)
	camera = Camera3D.new()
	camera.name = "RoomCamera"
	camera.fov = 66.0
	camera.near = .06
	camera.far = 65.0
	add_child(camera)
	camera.make_current()
	_build_hud()
	interactions = RoomInteractions.new() as Node
	add_child(interactions)
	interactions.call("configure", self, player, layout, room_model)
	furniture_actions = FurnitureActions.new() as Node3D
	add_child(furniture_actions)
	furniture_actions.call("configure", self, room_model, interactions, layout)
	if is_instance_valid(music):
		music.call("set_context", "wordking")
		music.connect("state_changed", _refresh_music)
		_refresh_music()
	update_camera(0.0, true)
	return_prompt.text = "正在準備角色…"

func _setup_input() -> void:
	var keys: Dictionary = {"move_left": KEY_A, "move_right": KEY_D, "move_forward": KEY_W, "move_back": KEY_S, "run": KEY_SHIFT, "jump": KEY_SPACE, "interact": KEY_E}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = int(keys[action]) as Key
		InputMap.action_add_event(action, key)

func _box_collision(label_text: String, at: Vector3, dimensions: Vector3, yaw: float = 0.0) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name = label_text.validate_node_name()
	body.collision_layer = 1
	body.collision_mask = 4
	body.position = at
	body.rotation.y = yaw
	body.add_to_group("training_room_collision")
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size = dimensions
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _vector(values: Array) -> Vector3:
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func _build_collision() -> void:
	var floor_y: float = float(layout.get("floor_y", .0375))
	_box_collision("Floor", Vector3(0, floor_y - .15, 0), Vector3(20.5, .3, 18.5))
	_box_collision("WestWall", Vector3(-10.05, 1.7, 0), Vector3(.22, 3.4, 18.5))
	_box_collision("EastWall", Vector3(10.05, 1.7, 0), Vector3(.22, 3.4, 18.5))
	_box_collision("BackWall", Vector3(0, 1.7, -9.08), Vector3(20.5, 3.4, .24))
	_box_collision("EntryBoundary", Vector3(0, 1.7, 9.2), Vector3(20.5, 3.4, .20))
	_box_collision("Ceiling", Vector3(0, 3.49, 0), Vector3(20.5, .18, 18.5))
	for row: Dictionary in layout.get("colliders", []):
		_box_collision(str(row.name), _vector(row.center as Array), _vector(row.size as Array), float(row.get("rotation_y", 0.0)))
	var device_body: StaticBody3D = StaticBody3D.new()
	device_body.name = "WordKingDeviceCollision"
	var device_collision: Dictionary = layout.get("device_collision", {}) as Dictionary
	device_body.position = _vector(device_collision.get("center", [.65, .27, -.8]) as Array)
	device_body.collision_layer = 1
	device_body.collision_mask = 4
	device_body.add_to_group("training_room_collision")
	var cylinder: CylinderShape3D = CylinderShape3D.new()
	cylinder.radius = float(device_collision.get("radius", .93))
	cylinder.height = float(device_collision.get("height", .55))
	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.shape = cylinder
	device_body.add_child(collision)
	add_child(device_body)

func _build_lighting() -> void:
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("61796f")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e3e8eb")
	environment.ambient_light_energy = .42
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment: WorldEnvironment = WorldEnvironment.new()
	world_environment.name = "RoomEnvironment"
	world_environment.environment = environment
	add_child(world_environment)
	var key: DirectionalLight3D = DirectionalLight3D.new()
	key.name = "SoftWarmKey"
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_color = Color("fff6e8")
	key.light_energy = .38
	key.shadow_enabled = false
	add_child(key)
	# Aim the ceiling fixture downward instead of lighting the roof from below.
	var ceiling_light: SpotLight3D = SpotLight3D.new()
	ceiling_light.name = "DownwardCeilingLight"
	ceiling_light.position = Vector3(0, 3.25, 0)
	ceiling_light.rotation_degrees.x = -90
	ceiling_light.spot_range = 15.0
	ceiling_light.spot_angle = 82.0
	ceiling_light.spot_angle_attenuation = .45
	ceiling_light.light_color = Color("fff8ed")
	ceiling_light.light_energy = .18
	ceiling_light.shadow_enabled = true
	ceiling_light.shadow_bias = .045
	add_child(ceiling_light)
	var light_positions: Array[Vector3] = [Vector3(-6.5, 2.8, 5), Vector3(6.7, 2.8, -3.5)]
	for i: int in range(light_positions.size()):
		var lamp: OmniLight3D = OmniLight3D.new()
		lamp.name = "SoftInteriorLight%d" % i
		lamp.position = light_positions[i]
		lamp.omni_range = 8.0
		lamp.omni_attenuation = 1.5
		lamp.light_color = Color("fff8ed")
		lamp.light_energy = .22
		lamp.shadow_enabled = false
		lamp.shadow_bias = .045
		add_child(lamp)

func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label_node: Label = Label.new()
	label_node.text = text_value
	label_node.add_theme_font_override("font", ui_font)
	label_node.add_theme_font_size_override("font_size", font_size)
	label_node.add_theme_color_override("font_color", color)
	label_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label_node

func _panel(color: Color) -> StyleBoxFlat:
	var panel: StyleBoxFlat = StyleBoxFlat.new()
	panel.bg_color = color
	panel.set_corner_radius_all(16)
	panel.content_margin_left = 20
	panel.content_margin_right = 20
	panel.content_margin_top = 14
	panel.content_margin_bottom = 14
	return panel

func _build_hud() -> void:
	ui_font = FontVariation.new()
	ui_font.base_font = FONT
	ui_font.variation_opentype = {2003265652: 550.0}
	var canvas: CanvasLayer = CanvasLayer.new()
	canvas.name = "RoomHUD"
	add_child(canvas)
	ui_root = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(ui_root)
	var margin: MarginContainer = MarginContainer.new()
	ui_root.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _panel(Color("244954ee")))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(badge)
	var title_column: VBoxContainer = VBoxContainer.new()
	badge.add_child(title_column)
	title_column.add_child(_label("練功區", 25, Color("f8eed7")))
	title_column.add_child(_label("每天前進一小步", 14, Color("c4d7ce")))
	var top_spacer: Control = Control.new()
	top_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_spacer)
	music_button = Button.new()
	music_button.text = "音樂：開"
	music_button.focus_mode = Control.FOCUS_NONE
	music_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	music_button.add_theme_font_override("font", ui_font)
	music_button.add_theme_font_size_override("font_size", 15)
	music_button.add_theme_color_override("font_color", Color("203e46"))
	music_button.add_theme_stylebox_override("normal", _panel(Color("edf1e9")))
	music_button.add_theme_stylebox_override("hover", _panel(Color("efd7a5")))
	music_button.pressed.connect(_toggle_music)
	music_button.visible = is_instance_valid(music)
	top.add_child(music_button)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var bottom: PanelContainer = PanelContainer.new()
	bottom.add_theme_stylebox_override("panel", _panel(Color("244954e8")))
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var bottom_row: HBoxContainer = HBoxContainer.new()
	bottom_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(bottom_row)
	var controls: Label = _label("W A S D 移動   Shift 跑步   Space 跳躍\n按住左／右鍵拖曳視角   滾輪縮放", 16, Color("e7eee5"))
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(controls)
	return_prompt = _label("", 19, Color("f3dba7"))
	return_prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bottom_row.add_child(return_prompt)

func _refresh_music() -> void:
	if not is_instance_valid(music) or music_button == null:
		return
	var state: Dictionary = music.call("get_state") as Dictionary
	music_button.text = "音樂：關" if bool(state.get("muted", false)) else "音樂：開"

func _toggle_music() -> void:
	if is_instance_valid(music):
		music.call("unlock")
		var state: Dictionary = music.call("get_state") as Dictionary
		music.call("set_muted", not bool(state.get("muted", false)))

func _can_return() -> bool:
	if not ready_for_play or returning:
		return false
	if interactions != null and bool(interactions.call("is_busy")):
		return false
	var delta_position: Vector3 = player.position - exit_point
	delta_position.y = 0.0
	return delta_position.length() < 1.8 and player.position.y < 1.0

func can_player_jump() -> bool:
	return ready_for_play and not returning and (interactions == null or not bool(interactions.call("is_busy")))

func _unhandled_input(event: InputEvent) -> void:
	if returning:
		return
	if not ready_for_play:
		if event is InputEventKey and event.is_pressed() and event.keycode == KEY_ESCAPE:
			returning = true
			request_return_to_world.emit()
		elif event is InputEventKey and event.is_pressed() and event.keycode == KEY_R:
			var packs: Node = get_node_or_null("/root/WebPacks")
			if packs != null:
				packs.call("retry_failed")
			player.call("retry_prepare_visuals")
		return
	if is_instance_valid(music) and (event is InputEventKey or event is InputEventMouseButton):
		music.call("unlock")
	if event is InputEventKey and (event as InputEventKey).pressed and not event.is_echo() and (event as InputEventKey).physical_keycode == KEY_F:
		if interactions != null and str(interactions.get("state")) == "seated" and furniture_actions != null:
			if bool(furniture_actions.call("use_nearest_computer")):
				get_viewport().set_input_as_handled()
				return
	if event.is_action_pressed("interact") and not event.is_echo():
		if interactions != null and bool(interactions.call("interact")):
			get_viewport().set_input_as_handled()
			return
		if _can_return():
			returning = true
			player.set("controls_enabled", false)
			get_viewport().set_input_as_handled()
			request_return_to_world.emit()
		return
	if interactions != null and bool(interactions.call("camera_blocked")):
		_finish_drag()
		return
	if event is InputEventMouseButton:
		var mouse: InputEventMouseButton = event as InputEventMouseButton
		if mouse.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging_view = mouse.pressed
			drag_button = mouse.button_index if mouse.pressed else MOUSE_BUTTON_NONE
		elif mouse.pressed and mouse.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera_distance = clampf(camera_distance + (-.35 if mouse.button_index == MOUSE_BUTTON_WHEEL_UP else .35), 2.2, 6.0)
	elif event is InputEventMouseMotion and dragging_view:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var rotation_delta: float = -motion.relative.x * .005
		camera_yaw += rotation_delta
		camera_pitch = clampf(camera_pitch + motion.relative.y * .004, -.08, .64)
		player.call("rotate_heading", rotation_delta)

func _finish_drag() -> void:
	dragging_view = false
	drag_button = MOUSE_BUTTON_NONE

func update_camera(delta: float, snap: bool = false) -> void:
	if player == null or camera == null:
		return
	var aim: Vector3 = player.global_position + Vector3.UP * 1.12
	var offset: Vector3 = Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch)) * camera_distance
	var desired: Vector3 = aim + offset
	desired.y = clampf(desired.y, .40, 3.15)
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(aim, desired, 1)
	query.hit_from_inside = true
	# Seat proxies include their backrests. A seated aim point can be inside
	# that box, so do not collapse the orbit camera into the character's head.
	if interactions != null and str(interactions.get("state")) in ["sitting", "seated", "standing"]:
		var active_seat: Dictionary = interactions.get("active") as Dictionary
		var seat_collider: String = str(active_seat.get("collider_name", ""))
		var excluded: Array[RID] = []
		for child: Node in get_children():
			if child is CollisionObject3D:
				var same_seat: bool = str(child.name) == seat_collider
				var same_sofa: bool = seat_collider.begins_with("Sofa_") and str(child.name).begins_with("Sofa_")
				if same_seat or same_sofa:
					excluded.append((child as CollisionObject3D).get_rid())
		query.exclude = excluded
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = (hit.position as Vector3) + (hit.normal as Vector3) * .22
	# Clamp the lens inside the enclosure even before physics has synced.
	desired.x = clampf(desired.x, -9.75, 9.75)
	desired.z = clampf(desired.z, -8.75, 8.85)
	camera.global_position = desired if snap else camera.global_position.lerp(desired, 1.0 - exp(-delta * 12.0))
	if camera.global_position.distance_squared_to(aim) > .002:
		camera.look_at(aim, Vector3.UP)

func _process(delta: float) -> void:
	if returning:
		return
	if not ready_for_play:
		player.call("step_prepare_visuals")
		if not bool(player.call("visuals_ready")):
			var message: String = str(player.call("visuals_error"))
			return_prompt.text = "正在準備角色…  Esc 返回" if message.is_empty() else message + "  R 重試 / Esc 返回"
			return
		ready_for_play = true
		player.process_mode = Node.PROCESS_MODE_INHERIT
		player.set("controls_enabled", true)
		room_ready.emit()
		print("TRAINING_ROOM_READY device=1 display_sockets=6 floor=20x18")
	if dragging_view and not Input.is_mouse_button_pressed(drag_button):
		_finish_drag()
	if interactions != null:
		interactions.call("refresh_nearest")
		if bool(interactions.call("camera_blocked")):
			_finish_drag()
	update_camera(delta)
	var action_prompt: String = str(interactions.call("prompt")) if interactions != null else ""
	return_prompt.text = action_prompt if not action_prompt.is_empty() else ("E  返回 3D 世界" if _can_return() else "靠近家具可互動 · 入口可返回世界")
	if player.position.y < -3.0:
		player.call("place_at", Vector3(0, .09, 6.2), Vector3.FORWARD)
		camera_yaw = 0.0
	if OS.has_feature("web") and (OS.is_debug_build() or performance_enabled):
		status_clock += delta
		if status_clock > .25:
			status_clock = 0.0
			var state: Dictionary = {"ready": true, "near_exit": _can_return(), "player": [player.position.x, player.position.y, player.position.z], "fps": Engine.get_frames_per_second(), "device_count": 1, "display_sockets": 6}
			JavaScriptBridge.eval("window.trainingRoomState = " + JSON.stringify(state) + ";")

func _exit_tree() -> void:
	if is_instance_valid(music) and music.is_connected("state_changed", _refresh_music):
		music.disconnect("state_changed", _refresh_music)
	if OS.has_feature("web") and (OS.is_debug_build() or performance_enabled):
		JavaScriptBridge.eval("window.trainingRoomState = null;")
