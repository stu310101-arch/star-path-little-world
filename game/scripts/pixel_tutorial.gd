extends Node3D
## 獨立於原教學的 3D 體素互動島。龍是可操控的角色與對話嚮導。
## 不讀取、不寫入玩家的帳號、成績、量表、收藏或論壇資料。
signal request_return_to_world

const Content = preload("res://scripts/pixel_tutorial_content.gd")
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const SPEED: float = 5.5
const RUN_SPEED: float = 9.0
const GRAVITY: float = 20.0
const JUMP_SPEED: float = 8.0

var graphics_settings: Node
var shared_music: Node
var player: CharacterBody3D
var dragon_visual: Node3D
var left_wing: Node3D
var right_wing: Node3D
var crown_root: Node3D
var camera: Camera3D
var camera_yaw: float = 0.0
var camera_pitch: float = 0.55
var camera_distance: float = 15.0
var overview: bool = false
var dragging: bool = false
var pending_jump: bool = false
var steps: Array[Dictionary] = []
var finished: Array[bool] = []
var positions: Array[Vector3] = []
var beacons: Array[MeshInstance3D] = []
var markers: Array[Label3D] = []
var material_cache: Dictionary = {}
var active_station: int = -1
var nearest_station: int = -1
var distance_walked: float = 0.0
var jump_count: int = 0
var camera_drag_amount: float = 0.0
var elapsed: float = 0.0
var ui: CanvasLayer
var progress_label: Label
var dialogue_label: Label
var hint_label: Label
var action_button: Button
var modal: Control
var modal_title: Label
var modal_body: Label
var modal_question: Label
var answer_list: VBoxContainer
var modal_feedback: Label
var map_overlay: Control
var map_grid: GridContainer
var touch_controls: Control
var touch_enabled: bool = false
var modal_card: PanelContainer
var modal_scroll: ScrollContainer
var map_scroll: ScrollContainer

func set_shared_music(value: Node) -> void:
	shared_music = value

func _ready() -> void:
	name = "DragonVoxelTutorial"
	steps = Content.stations()
	finished.resize(steps.size())
	finished.fill(false)
	_setup_inputs()
	_create_world()
	_create_dragon()
	_create_camera()
	_create_ui()
	get_viewport().size_changed.connect(_resize_ui)
	_resize_ui.call_deferred()
	_refresh_hud()
	print("PIXEL_TUTORIAL_READY stations=", steps.size())

func _setup_inputs() -> void:
	var keys: Dictionary = {
		"move_left": KEY_A, "move_right": KEY_D,
		"move_forward": KEY_W, "move_back": KEY_S,
		"run": KEY_SHIFT, "jump": KEY_SPACE,
		"interact": KEY_E, "switch_view": KEY_TAB, "reset": KEY_HOME
	}
	for action: String in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key: InputEventKey = InputEventKey.new()
		key.physical_keycode = int(keys[action])
		InputMap.action_add_event(action, key)

func _material(color: Color) -> StandardMaterial3D:
	var key: String = color.to_html()
	if material_cache.has(key):
		return material_cache[key] as StandardMaterial3D
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material_cache[key] = mat
	return mat

func _cube(parent: Node3D, title: String, at: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = title
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = _material(color)
	part.position = at
	parent.add_child(part)
	return part

func _create_world() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#87c8df")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#d7f1ed")
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -28, 0)
	sun.light_color = Color("#fff1c7")
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)
	var ground := StaticBody3D.new()
	ground.name = "VoxelGround"
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	_cube(ground, "Grass", Vector3(0, -0.5, 0), Vector3(66, 1, 82), Color("#74b96c"))
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(66, 1, 82)
	floor_shape.shape = floor_box
	floor_shape.position.y = -0.5
	ground.add_child(floor_shape)
	for x in range(-32, 33, 4):
		_cube(self, "GrassEdge", Vector3(x, -0.2, -41), Vector3(3.8, .7, 2), Color("#4b815c"))
		_cube(self, "GrassEdge", Vector3(x, -0.2, 41), Vector3(3.8, .7, 2), Color("#4b815c"))
	for z in range(-38, 39, 4):
		_cube(self, "GrassEdge", Vector3(-33, -0.2, z), Vector3(2, .7, 3.8), Color("#4b815c"))
		_cube(self, "GrassEdge", Vector3(33, -0.2, z), Vector3(2, .7, 3.8), Color("#4b815c"))
	for row in range(5):
		_cube(self, "PathEastWest", Vector3(0, 0.015, (row - 2) * 13), Vector3(55, 0.04, 2.6), Color("#e2d2ad"))
	for col in range(3):
		_cube(self, "PathNorthSouth", Vector3((col - 1) * 17, 0.02, 0), Vector3(2.6, 0.04, 67), Color("#e2d2ad"))
	for index in range(steps.size()):
		_create_station(index)
	for i in range(16):
		var x: float = -29.5 if i % 2 == 0 else 29.5
		var z: float = -34.0 + float(i / 2) * 9.5
		_create_voxel_tree(Vector3(x, 0, z))
	_cube(self, "WelcomeMarker", Vector3(-17, 0.08, -33), Vector3(3, .16, 3), Color("#fff1a7"))

func _create_voxel_tree(at: Vector3) -> void:
	var tree := Node3D.new()
	tree.position = at
	add_child(tree)
	_cube(tree, "Trunk", Vector3(0, 1.25, 0), Vector3(.65, 2.5, .65), Color("#8d654b"))
	_cube(tree, "LeavesLower", Vector3(0, 2.65, 0), Vector3(3.0, 1.15, 3.0), Color("#408e6b"))
	_cube(tree, "LeavesUpper", Vector3(0, 3.5, 0), Vector3(2.2, 1.0, 2.2), Color("#54a97d"))

func _create_station(index: int) -> void:
	var step: Dictionary = steps[index]
	var spot := Vector3(float((index % 3) - 1) * 17.0, 0, float((index / 3) - 2) * 13.0)
	positions.append(spot)
	var exhibit := Node3D.new()
	exhibit.name = "Lesson%02d" % (index + 1)
	exhibit.position = spot
	add_child(exhibit)
	var tint := Color(str(step["color"]))
	_cube(exhibit, "Platform", Vector3(0, 0.065, 0), Vector3(8.6, .13, 8.0), tint.darkened(.22))
	_cube(exhibit, "PlatformInset", Vector3(0, 0.14, 0), Vector3(7.6, .055, 7), Color("#fbedd2"))
	for side in [-1.0, 1.0]:
		_cube(exhibit, "GateColumn", Vector3(side * 3.2, 1.25, -2.8), Vector3(.65, 2.5, .65), tint.darkened(.30))
		_cube(exhibit, "GateCap", Vector3(side * 3.2, 2.6, -2.8), Vector3(1, .45, 1), tint)
	_cube(exhibit, "GateHeader", Vector3(0, 2.4, -2.8), Vector3(6.4, .35, .65), tint)
	_cube(exhibit, "Pedestal", Vector3(0, .6, 0), Vector3(1.8, 1.1, 1.8), Color("#5e6576"))
	var beacon := _cube(exhibit, "Beacon", Vector3(0, 1.53, 0), Vector3(1.25, 1.25, 1.25), tint)
	beacons.append(beacon)
	var number := Label3D.new()
	number.name = "StationLabel"
	number.text = "%02d  %s" % [index + 1, str(step["title"]).substr(3)]
	number.font = FONT
	number.font_size = 43
	number.pixel_size = 0.007
	number.outline_size = 8
	number.modulate = Color("#fff7df")
	number.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	number.position = Vector3(0, 3.55, -2.8)
	exhibit.add_child(number)
	markers.append(number)

func _create_dragon() -> void:
	player = CharacterBody3D.new()
	player.name = "Dragon"
	player.collision_layer = 4
	player.collision_mask = 1
	player.floor_snap_length = .35
	player.position = Vector3(-17, .3, -31)
	add_child(player)
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = .42
	capsule.height = 1.8
	collider.shape = capsule
	collider.position.y = .9
	player.add_child(collider)
	dragon_visual = Node3D.new()
	dragon_visual.name = "PixelDragon"
	player.add_child(dragon_visual)
	var emerald := Color("#2caa89")
	var light := Color("#81dfaa")
	var belly := Color("#f4d9a1")
	var dark := Color("#244d51")
	_cube(dragon_visual, "Body", Vector3(0, 1.05, .15), Vector3(1.2, 1.05, 1.4), emerald)
	_cube(dragon_visual, "Belly", Vector3(0, .96, -.59), Vector3(.9, .83, .14), belly)
	_cube(dragon_visual, "Head", Vector3(0, 1.83, -.64), Vector3(1.22, .94, 1.08), light)
	_cube(dragon_visual, "Snout", Vector3(0, 1.56, -1.29), Vector3(.89, .39, .55), emerald)
	for sign in [-1.0, 1.0]:
		_cube(dragon_visual, "Eye", Vector3(sign * .34, 1.96, -1.19), Vector3(.17, .2, .08), dark)
		_cube(dragon_visual, "Horn", Vector3(sign * .40, 2.42, -.46), Vector3(.28, .55, .27), Color("#f0cb82"))
		_cube(dragon_visual, "Feet", Vector3(sign * .36, .34, .20), Vector3(.38, .56, .62), emerald.darkened(.1))
		_cube(dragon_visual, "Arm", Vector3(sign * .72, 1.13, -.4), Vector3(.4, .3, .66), emerald)
	for i in range(3):
		_cube(dragon_visual, "Tail", Vector3(0, .82 - i * .18, 1.06 + i * .39), Vector3(.68 - i * .13, .55 - i * .10, .53), emerald.darkened(.09 * i))
	for i in range(3):
		_cube(dragon_visual, "BackSpike", Vector3(0, 1.72 - i * .13, .36 + i * .47), Vector3(.30, .48, .34), Color("#f6c97d"))
	left_wing = Node3D.new()
	left_wing.position = Vector3(-.59, 1.3, .28)
	dragon_visual.add_child(left_wing)
	_cube(left_wing, "LeftWing", Vector3(-.74, .08, 0), Vector3(1.45, .22, .95), Color("#168d81"))
	_cube(left_wing, "LeftWingTip", Vector3(-1.43, .17, -.19), Vector3(.65, .2, .7), Color("#76d7ba"))
	right_wing = Node3D.new()
	right_wing.position = Vector3(.59, 1.3, .28)
	dragon_visual.add_child(right_wing)
	_cube(right_wing, "RightWing", Vector3(.74, .08, 0), Vector3(1.45, .22, .95), Color("#168d81"))
	_cube(right_wing, "RightWingTip", Vector3(1.43, .17, -.19), Vector3(.65, .2, .7), Color("#76d7ba"))
	crown_root = Node3D.new()
	crown_root.name = "DragonGraduationCrown"
	dragon_visual.add_child(crown_root)
	_cube(crown_root, "CrownBand", Vector3(0, 2.58, -.62), Vector3(1.3, .2, .9), Color("#f5c65c"))
	for sign in [-1.0, 0.0, 1.0]:
		_cube(crown_root, "StarPoint", Vector3(sign * .43, 2.86, -.62), Vector3(.22, .38, .3), Color("#fff3af"))
	crown_root.visible = false

func _create_camera() -> void:
	camera = Camera3D.new()
	camera.name = "DragonCamera"
	camera.fov = 58
	camera.near = 0.1
	camera.far = 180
	add_child(camera)
	camera.make_current()
	_update_camera(1.0)

func _process(delta: float) -> void:
	elapsed += delta
	if player == null:
		return
	dragon_visual.position.y = sin(elapsed * 4.0) * .06
	left_wing.rotation.z = sin(elapsed * 8.0) * .24 - .12
	right_wing.rotation.z = -left_wing.rotation.z
	for index in range(beacons.size()):
		var beacon: MeshInstance3D = beacons[index]
		beacon.rotation.y += delta * (1.0 if not finished[index] else .25)
		beacon.position.y = 1.53 + .13 * sin(elapsed * 2.5 + index)
	_update_camera(delta)
	var next_near: int = _find_nearest()
	if next_near != nearest_station:
		nearest_station = next_near
		_refresh_hud()

func _physics_process(delta: float) -> void:
	if player == null:
		return
	var old_position := player.global_position
	var can_move := not modal.visible and not map_overlay.visible
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_move else Vector2.ZERO
	var right := camera.global_basis.x
	var backward := camera.global_basis.z
	right.y = 0
	backward.y = 0
	right = right.normalized()
	backward = backward.normalized()
	var wish := right * axis.x + backward * axis.y
	if wish.length_squared() > 1.0:
		wish = wish.normalized()
	var running: bool = can_move and Input.is_action_pressed("run")
	var pace := RUN_SPEED if running else SPEED
	player.velocity.x = wish.x * pace
	player.velocity.z = wish.z * pace
	if player.is_on_floor():
		player.velocity.y = -0.3
		if can_move and (Input.is_action_just_pressed("jump") or pending_jump):
			player.velocity.y = JUMP_SPEED
			jump_count += 1
	else:
		player.velocity.y -= GRAVITY * delta
	pending_jump = false
	player.move_and_slide()
	distance_walked += Vector2(player.global_position.x - old_position.x, player.global_position.z - old_position.z).length()
	if wish.length_squared() > .03:
		var face: float = atan2(-wish.x, -wish.z)
		dragon_visual.rotation.y = lerp_angle(dragon_visual.rotation.y, face, minf(1.0, 9.0 * delta))
	if player.position.y < -5.0:
		_teleport(0)

func _update_camera(delta: float) -> void:
	if player == null or camera == null:
		return
	var target := player.global_position + Vector3(0, 1.25, 0)
	var direction := Vector3(sin(camera_yaw) * cos(camera_pitch), sin(camera_pitch), cos(camera_yaw) * cos(camera_pitch))
	var desired := target + direction * camera_distance
	camera.global_position = camera.global_position.lerp(desired, minf(1.0, delta * 10.0))
	camera.look_at(target, Vector3.UP)

func _input(event: InputEvent) -> void:
	# 收鍵要不受 GUI 點擊影響，避免在按鈕上放開滑鼠後鏡頭持續拖曳。
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			dragging = false

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if modal.visible:
				_close_modal()
			elif map_overlay.visible:
				_close_map()
			else:
				request_return_to_world.emit()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_M:
			_toggle_map()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_TAB and not modal.visible and not map_overlay.visible:
			overview = not overview
			camera_distance = 34.0 if overview else 15.0
			_refresh_hud()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_HOME and not modal.visible and not map_overlay.visible:
			_teleport(0)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("interact") and not modal.visible and not map_overlay.visible:
		_interact()
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			dragging = event.pressed
		if event.pressed and not modal.visible and not map_overlay.visible:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_distance = maxf(6.0, camera_distance - 1.5)
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_distance = minf(35.0, camera_distance + 1.5)
	if event is InputEventMouseMotion and dragging and not modal.visible and not map_overlay.visible:
		_rotate_camera(event.relative)
	if event is InputEventScreenDrag and not modal.visible and not map_overlay.visible:
		_rotate_camera(event.relative)

func _rotate_camera(motion: Vector2) -> void:
	camera_yaw -= motion.x * .006
	camera_pitch = clampf(camera_pitch + motion.y * .004, .21, 1.25)
	camera_drag_amount += motion.length()

func _find_nearest() -> int:
	var index: int = -1
	var closest: float = 5.2
	for i in range(positions.size()):
		var distance: float = Vector2(player.global_position.x - positions[i].x, player.global_position.z - positions[i].z).length()
		if distance < closest:
			index = i
			closest = distance
	return index

func _teleport(index: int) -> void:
	if index < 0 or index >= positions.size():
		return
	player.position = positions[index] + Vector3(0, .3, 3.7)
	player.velocity = Vector3.ZERO
	nearest_station = index
	_refresh_hud()

func _interact() -> void:
	if nearest_station < 0:
		hint_label.text = "龍：再靠近發光方塊展台一點，才能開始挑戰。"
		return
	_open_station(nearest_station)

func _open_station(index: int) -> void:
	if index < 0 or index >= steps.size():
		return
	_close_map()
	active_station = index
	var step: Dictionary = steps[index]
	modal_title.text = str(step["title"]) + ("  ★ 已完成" if finished[index] else "")
	modal_body.text = str(step["lesson"]) + "\n\n" + str(step["tip"])
	modal_question.text = "龍的挑戰：" + str(step["question"])
	modal_feedback.text = ""
	for child in answer_list.get_children():
		child.queue_free()
	var choices: Array = step["choices"]
	for i in range(choices.size()):
		var btn := _button("%d. %s" % [i + 1, str(choices[i])], false)
		btn.custom_minimum_size = Vector2(0, 54)
		btn.pressed.connect(_answer.bind(i))
		answer_list.add_child(btn)
	modal.show()
	_update_touch_controls()
	get_viewport().gui_release_focus()

func _answer(option: int) -> void:
	if active_station < 0:
		return
	var step: Dictionary = steps[active_station]
	if option != int(step["answer"]):
		modal_feedback.text = "龍：差一點！再看一下上面的玩法提示。"
		return
	if active_station == 0 and (distance_walked < 3.0 or jump_count < 1):
		modal_feedback.text = "龍：答對了！但請先關閉卡片，移動滿 3 公尺、跳躍一次，再回來領星星。"
		return
	if active_station == 1 and camera_drag_amount < 35.0:
		modal_feedback.text = "龍：答對了！先關閉卡片，在 3D 世界拖曳鏡頭看看我，再回來領星星。"
		return
	if active_station == steps.size() - 1 and _completed_count() < steps.size() - 1 and not finished[active_station]:
		modal_feedback.text = "龍：先去收集前面 14 座展台的星星，最後再回來參加畢業挑戰！"
		return
	if not finished[active_station]:
		finished[active_station] = true
		beacons[active_station].material_override = _material(Color("#ffe184"))
		markers[active_station].modulate = Color("#ffec9a")
	modal_feedback.text = "★ 挑戰完成！星星已點亮。可以按下方關閉，繼續找下一座展台。"
	_refresh_hud()

func _close_modal() -> void:
	modal.hide()
	_update_touch_controls()
	active_station = -1
	_refresh_hud()

func _toggle_map() -> void:
	if modal.visible:
		return
	if map_overlay.visible:
		_close_map()
	else:
		_open_map()

func _open_map() -> void:
	_refresh_map()
	map_overlay.show()
	_update_touch_controls()

func _close_map() -> void:
	if map_overlay != null:
		map_overlay.hide()
		_update_touch_controls()

func _refresh_map() -> void:
	for child in map_grid.get_children():
		child.queue_free()
	for i in range(steps.size()):
		var index: int = i
		var text: String = ("★ " if finished[i] else "□ ") + str(steps[i]["title"])
		var btn := _button(text, finished[i])
		btn.custom_minimum_size = Vector2(160, 54)
		btn.pressed.connect(func() -> void:
			_close_map()
			_teleport(index))
		map_grid.add_child(btn)

func _completed_count() -> int:
	var count: int = 0
	for value in finished:
		if value:
			count += 1
	return count

func _refresh_hud() -> void:
	if progress_label == null:
		return
	var count: int = _completed_count()
	progress_label.text = "★ 龍的教學島   %d / %d 顆星" % [count, steps.size()]
	if nearest_station >= 0:
		var step: Dictionary = steps[nearest_station]
		dialogue_label.text = "龍：%s%s！準備好按 E 挑戰了嗎？" % [str(step["title"]), "（已完成）" if finished[nearest_station] else ""]
		hint_label.text = "E／互動：開始此站練習  •  M：教學地圖  •  Tab：總覽"
		action_button.disabled = false
		action_button.text = "E  挑戰 %02d" % (nearest_station + 1)
	else:
		dialogue_label.text = "龍：跟著方塊小路，去找新的發光展台！"
		hint_label.text = "WASD 移動  •  Shift 跑步  •  Space 跳躍  •  拖曳轉鏡頭"
		action_button.disabled = true
		action_button.text = "靠近展台按 E"
	if crown_root != null:
		crown_root.visible = count == steps.size()
	if count == steps.size():
		dialogue_label.text = "龍：全部 15 顆教學星星收集成功！你已完成星途新手探險！"

func _label(text: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_override("font", FONT)
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return node

func _style(bg: Color) -> StyleBoxFlat:
	var sty := StyleBoxFlat.new()
	sty.bg_color = bg
	sty.set_corner_radius_all(5)
	sty.content_margin_left = 15.0
	sty.content_margin_right = 15.0
	sty.content_margin_top = 11.0
	sty.content_margin_bottom = 11.0
	sty.set_border_width_all(2)
	sty.border_color = Color("#31565b")
	return sty

func _button(text: String, gold: bool = false) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_font_override("font", FONT)
	btn.add_theme_font_size_override("font_size", 17)
	btn.add_theme_color_override("font_color", Color("#213b42"))
	btn.add_theme_color_override("font_hover_color", Color("#213b42"))
	btn.add_theme_color_override("font_pressed_color", Color("#213b42"))
	btn.add_theme_stylebox_override("normal", _style(Color("#ffdf91") if gold else Color("#f0f5eb")))
	btn.add_theme_stylebox_override("hover", _style(Color("#fff0c3")))
	btn.add_theme_stylebox_override("pressed", _style(Color("#a7dece")))
	btn.focus_mode = Control.FOCUS_NONE
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return btn

func _create_ui() -> void:
	ui = CanvasLayer.new()
	ui.name = "TutorialHUD"
	ui.layer = 18
	add_child(ui)
	var screen := Control.new()
	screen.name = "Screen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(screen)
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 15
	top.offset_top = 12
	top.offset_right = -15
	top.offset_bottom = 90
	top.add_theme_constant_override("separation", 16)
	screen.add_child(top)
	var header := PanelContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_theme_stylebox_override("panel", _style(Color("#123c48dd")))
	top.add_child(header)
	var header_inner := VBoxContainer.new()
	header.add_child(header_inner)
	progress_label = _label("", 22, Color("#ffe1a1"))
	header_inner.add_child(progress_label)
	var sub := _label("全新麥塊風體素教學：操控龍，逐站收集知識星星", 13, Color("#fff4d3"))
	header_inner.add_child(sub)
	var exit := _button("返回星途", true)
	exit.custom_minimum_size = Vector2(155, 60)
	exit.pressed.connect(func() -> void: request_return_to_world.emit())
	top.add_child(exit)
	var speech := PanelContainer.new()
	speech.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	speech.offset_left = 15
	speech.offset_right = -15
	speech.offset_bottom = -14
	speech.offset_top = -138
	speech.add_theme_stylebox_override("panel", _style(Color("#163e49e8")))
	screen.add_child(speech)
	var speech_row := VBoxContainer.new()
	speech_row.add_theme_constant_override("separation", 5)
	speech.add_child(speech_row)
	dialogue_label = _label("", 19, Color("#fceac3"))
	speech_row.add_child(dialogue_label)
	hint_label = _label("", 14, Color("#c7e5d8"))
	speech_row.add_child(hint_label)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	speech_row.add_child(actions)
	action_button = _button("靠近展台按 E", true)
	action_button.pressed.connect(_interact)
	actions.add_child(action_button)
	var map_button := _button("M 教學地圖")
	map_button.pressed.connect(_toggle_map)
	actions.add_child(map_button)
	var jump_button := _button("跳躍")
	jump_button.pressed.connect(func() -> void: pending_jump = true)
	actions.add_child(jump_button)
	_build_modal(screen)
	_build_map(screen)
	_build_touch_controls(screen)
	_update_touch_controls()

func _build_modal(screen: Control) -> void:
	modal = Control.new()
	modal.name = "LessonChallenge"
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(modal)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, .08, .11, .83)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(backdrop)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.add_child(center)
	var card := PanelContainer.new()
	modal_card = card
	card.name = "ChallengeCard"
	card.custom_minimum_size = Vector2(630, 0)
	card.add_theme_stylebox_override("panel", _style(Color("#f8f4e8")))
	center.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 13)
	modal_scroll = ScrollContainer.new()
	modal_scroll.name = "ChallengeScroll"
	modal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	modal_scroll.custom_minimum_size = Vector2(600, 510)
	card.add_child(modal_scroll)
	modal_scroll.add_child(content)
	modal_title = _label("", 25, Color("#184651"))
	content.add_child(modal_title)
	modal_body = _label("", 17, Color("#375961"))
	content.add_child(modal_body)
	modal_question = _label("", 18, Color("#184651"))
	content.add_child(modal_question)
	answer_list = VBoxContainer.new()
	answer_list.add_theme_constant_override("separation", 8)
	content.add_child(answer_list)
	modal_feedback = _label("", 16, Color("#a05c35"))
	content.add_child(modal_feedback)
	var dismiss := _button("先去練習／關閉卡片")
	dismiss.pressed.connect(_close_modal)
	content.add_child(dismiss)
	modal.hide()

func _build_map(screen: Control) -> void:
	map_overlay = Control.new()
	map_overlay.name = "LessonMap"
	map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	screen.add_child(map_overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.015, .06, .09, .90)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(Color("#eaf3eb")))
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)
	column.add_child(_label("龍的方塊島地圖  ·  點關卡立即傳送", 23, Color("#234751")))
	column.add_child(_label("□ 尚未完成　★ 已解鎖星星　｜　此傳送只限教學島", 15, Color("#49686c")))
	map_scroll = ScrollContainer.new()
	map_scroll.custom_minimum_size = Vector2(565, 420)
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(map_scroll)
	map_grid = GridContainer.new()
	map_grid.columns = 3
	map_grid.add_theme_constant_override("h_separation", 8)
	map_grid.add_theme_constant_override("v_separation", 8)
	map_scroll.add_child(map_grid)
	var close := _button("關閉地圖（M／Esc）", true)
	close.pressed.connect(_close_map)
	column.add_child(close)
	map_overlay.hide()

func _build_touch_controls(screen: Control) -> void:
	# 也保留桌面操作；在手機 Web / 實體觸控裝置額外顯示方向鍵。
	touch_controls = Control.new()
	touch_controls.name = "TouchMove"
	touch_controls.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	touch_controls.offset_left = 18
	touch_controls.offset_top = -325
	touch_controls.offset_right = 240
	touch_controls.offset_bottom = -150
	screen.add_child(touch_controls)
	touch_enabled = DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")
	touch_controls.visible = touch_enabled
	var directions: Array = [
		["move_forward", "↑", Vector2(75, 0)],
		["move_left", "←", Vector2(0, 54)],
		["move_back", "↓", Vector2(75, 54)],
		["move_right", "→", Vector2(150, 54)],
		["run", "跑", Vector2(75, 108)]
	]
	for row in directions:
		var action := StringName(row[0])
		var btn := _button(str(row[1]))
		btn.position = row[2]
		btn.size = Vector2(66, 50)
		btn.button_down.connect(func() -> void: Input.action_press(action))
		btn.button_up.connect(func() -> void: Input.action_release(action))
		touch_controls.add_child(btn)


func _update_touch_controls() -> void:
	if touch_controls != null:
		touch_controls.visible = touch_enabled and not modal.visible and not map_overlay.visible

func _resize_ui() -> void:
	if modal_card == null or map_scroll == null:
		return
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var narrow: bool = viewport_size.x < 740.0
	modal_card.custom_minimum_size.x = minf(630.0, maxf(260.0, viewport_size.x - 36.0))
	modal_scroll.custom_minimum_size = Vector2(minf(600.0, maxf(220.0, viewport_size.x - 72.0)), minf(510.0, maxf(240.0, viewport_size.y - 32.0)))
	map_grid.columns = 1 if narrow else 3
	map_scroll.custom_minimum_size = Vector2(minf(565.0, maxf(220.0, viewport_size.x - 72.0)), minf(420.0, maxf(220.0, viewport_size.y - 180.0)))

func _exit_tree() -> void:
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"run", &"jump"]:
		if InputMap.has_action(action):
			Input.action_release(action)
