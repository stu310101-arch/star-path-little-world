extends Node

signal custom_action(id: String)

const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const RestPose = preload("res://scripts/bench_pose.gd")
const ReadingPose = preload("res://scripts/training_reading_pose.gd")
const SIT_SECONDS: float = 1.05
const STAND_SECONDS: float = .9
const BOOK_SECONDS: float = .75

var room: Node3D
var player: PlanetPlayer
var room_model: Node3D
var layout: Dictionary
var targets: Array[Dictionary] = []
var books: Array[Dictionary] = []
var nearest: Dictionary = {}
var active: Dictionary = {}
var state: StringName = &"idle"
var clock: float = 0.0
var saved_controls: bool = true
var saved_mask: int = 9
var saved_position: Vector3
var saved_basis: Basis
var saved_visual: Quaternion
var seat_feet: Vector3
var seat_basis: Basis
var seat_camera: Dictionary = {}
var exit_position: Vector3
var rest_pose: RefCounted
var reading_pose: RefCounted
var held_book: Node3D
var selected_shelf_book: Node3D
var shelf_book_was_visible: bool = true
var book_start: Transform3D
var book_end: Transform3D
var book_id: String = ""
var book_open_amount: float = 0.0
var reading_camera: Dictionary = {}
var leaf_left: Node3D
var leaf_right: Node3D
var layer: CanvasLayer
var overlay: Control
var dim: ColorRect
var modal_row: HBoxContainer
var modal_panel: PanelContainer
var modal_column: VBoxContainer
var content: VBoxContainer
var title: Label
var footer: Label
var close_button: Button
var message: String = ""
var message_clock: float = 0.0

func configure(room_node: Node3D, player_node: CharacterBody3D, room_layout: Dictionary, art: Node3D) -> void:
	room = room_node
	player = player_node as PlanetPlayer
	layout = room_layout
	room_model = art
	for seat: Dictionary in layout.get("seats", []):
		var target: Dictionary = seat.duplicate(true)
		target["kind"] = "seat"
		target["radius"] = float(target.get("radius", 1.45))
		register_target(target)
	for book: Dictionary in layout.get("books", []):
		books.append(book)
	if not books.is_empty():
		var bookcase: Dictionary = (layout.get("bookcase", {}) as Dictionary).duplicate(true)
		bookcase["id"] = "bookcase"
		bookcase["kind"] = "books"
		bookcase["label"] = "選取書籍閱讀"
		bookcase["position"] = bookcase.get("position", [8.3, .08, 1.95])
		bookcase["radius"] = float(bookcase.get("radius", 1.65))
		register_target(bookcase)
	_build_ui()

func register_target(target: Dictionary) -> void:
	for index: int in range(targets.size()):
		if str(targets[index].get("id", "")) == str(target.get("id", "")):
			targets[index] = target
			return
	targets.append(target)

func _vector(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	var values: Array = raw as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func is_busy() -> bool:
	return state != &"idle"

func camera_blocked() -> bool:
	return state in [&"selecting", &"taking_book", &"reading", &"returning_book", &"inspection"]

func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func refresh_nearest() -> void:
	nearest = {}
	if state != &"idle" or player == null or player.needs_settle or player.jump_state != &"grounded":
		return
	var best: float = INF
	for target: Dictionary in targets:
		if not bool(target.get("enabled", true)):
			continue
		var at: Vector3 = _vector(target.get("approach", target.get("position", [0, 0, 0])))
		var distance: float = _horizontal_distance(player.global_position, at)
		var radius: float = float(target.get("radius", 1.4))
		if distance > radius or absf(player.global_position.y - at.y) > .7:
			continue
		if str(target.get("kind", "custom")) == "seat":
			# Swivel chairs are approached from the aisle behind them, while the
			# authored seated pose faces their monitor. Respect the entry anchor.
			var entry_side: Vector3 = (at - _vector(target.position)).slide(Vector3.UP).normalized()
			if entry_side.dot((player.global_position - _vector(target.position)).slide(Vector3.UP)) < .15:
				continue
		if not _visible_target(target, at):
			continue
		if distance < best:
			nearest = target
			best = distance

func _visible_target(target: Dictionary, at: Vector3) -> bool:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * .85, at + Vector3.UP * .85, 1)
	query.exclude = [player.get_rid()]
	var collider: CollisionObject3D = room.get_node_or_null(NodePath(str(target.get("collider_name", "__none")))) as CollisionObject3D
	if collider != null:
		query.exclude.append(collider.get_rid())
	return room.get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func prompt() -> String:
	match state:
		&"sitting": return "正在坐下…"
		&"seated": return "E  起身   ·   F 開關螢幕" if str(active.get("id", "")).contains("gaming") else "E  起身   ·   拖曳可環顧四周"
		&"standing": return "正在起身…"
		&"selecting": return "選擇一本書   ·   Esc 關閉"
		&"taking_book": return "正在拿取書籍…"
		&"reading": return "E / Esc  闔上並放回書架"
		&"returning_book": return "正在放回書籍…"
		&"inspection": return "E / Esc  關閉"
	if message_clock > 0:
		return message
	if nearest.is_empty():
		return ""
	var label_text: String = str(nearest.get("label", "互動"))
	return "E  坐下 · " + label_text if str(nearest.get("kind", "")) == "seat" else "E  " + label_text

func interact() -> bool:
	match state:
		&"seated":
			var safe: Dictionary = _safe_stand(active)
			if safe.is_empty():
				message = "前方暫時無法起身"
				message_clock = 2.0
				return true
			exit_position = safe.point as Vector3
			state = &"standing"
			clock = 0
			return true
		&"reading", &"inspection", &"selecting":
			close_modal()
			return true
		&"sitting", &"standing", &"taking_book", &"returning_book":
			return true
	refresh_nearest()
	if nearest.is_empty():
		return false
	active = nearest.duplicate(true)
	match str(active.get("kind", "custom")):
		"seat": _begin_sitting()
		"books": _open_books()
		_: custom_action.emit(str(active.id))
	return true

func _lock_player() -> void:
	saved_controls = player.controls_enabled
	saved_mask = player.collision_mask
	saved_position = player.global_position
	saved_basis = player.global_basis
	saved_visual = player.visual.quaternion
	player.reset_jump_motion()
	player.set_clip(&"Idle")
	player.is_resting = true
	player.controls_enabled = false
	player.velocity = Vector3.ZERO

func _unlock_player() -> void:
	player.is_resting = false
	player.controls_enabled = saved_controls
	player.collision_mask = saved_mask
	player.velocity = Vector3.ZERO
	player.reset_jump_motion()
	player.active_clip = &""
	player.set_clip(&"Idle")
	player.needs_settle = true
	player.last_safe_position = player.global_position
	state = &"idle"
	active = {}
	nearest = {}

func _capsule_clear(at: Vector3) -> bool:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .275
	capsule.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * .84)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	return room.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _safe_stand(seat: Dictionary) -> Dictionary:
	var front: Vector3 = _vector(seat.approach)
	front.y = float(layout.get("floor_y", .0375)) + .035
	var facing: Basis = Basis(Vector3.UP, float(seat.get("facing", 0.0)))
	for offset: Vector3 in [Vector3.ZERO, Vector3(0, 0, .25), Vector3(-.3, 0, .15), Vector3(.3, 0, .15), Vector3(0, 0, .5)]:
		var candidate: Vector3 = front + facing * offset
		if _capsule_clear(candidate):
			return {"point": candidate}
	return {}

func _begin_sitting() -> void:
	var safe: Dictionary = _safe_stand(active)
	if safe.is_empty():
		message = "請由座椅前方接近"
		message_clock = 2.0
		return
	_lock_player()
	exit_position = safe.point as Vector3
	seat_basis = Basis(Vector3.UP, float(active.get("facing", 0)))
	seat_feet = _vector(active.position) - Vector3.UP * .52 + seat_basis.z * float(active.get("pose_forward", 0.0))
	seat_camera = {"camera_yaw": room.get("camera_yaw"), "camera_pitch": room.get("camera_pitch"), "camera_distance": room.get("camera_distance")}
	var facing: float = float(active.get("facing", 0))
	room.set("camera_yaw", facing + PI - .35 if str(active.id).contains("gaming") else facing - .60)
	room.set("camera_pitch", .26)
	room.set("camera_distance", 3.4)
	if rest_pose == null:
		rest_pose = RestPose.new() as RefCounted
		rest_pose.call("configure", player.visual, player.locomotion_model)
	player.collision_mask = 0
	state = &"sitting"
	clock = 0
	rest_pose.call("set_amount", 0.0)

func _update_seat() -> void:
	var amount: float = 1.0
	var point: Vector3 = seat_feet
	if state == &"sitting":
		var progress: float = clampf(clock / SIT_SECONDS, 0, 1)
		amount = smoothstep(.12, 1, progress)
		point = saved_position.lerp(seat_feet, smoothstep(0, 1, progress))
		if progress >= 1:
			state = &"seated"
	elif state == &"standing":
		var progress: float = clampf(clock / STAND_SECONDS, 0, 1)
		amount = 1.0 - smoothstep(0, 1, progress)
		point = seat_feet.lerp(exit_position, smoothstep(0, 1, progress))
		if progress >= 1:
			rest_pose.call("finish")
			for property: String in seat_camera:
				room.set(property, seat_camera[property])
			seat_camera.clear()
			player.call("place_at", exit_position, player.heading)
			var local_facing: Vector3 = player.global_basis.inverse() * seat_basis.z
			player.visual.rotation = Vector3(0, atan2(local_facing.x, local_facing.z), 0)
			_unlock_player()
			return
	player.global_transform = Transform3D(seat_basis, point)
	player.up_direction = Vector3.UP
	player.previous_up = Vector3.UP
	var turn: float = smoothstep(0, .38, clock / SIT_SECONDS) if state == &"sitting" else 1.0
	var original_visual: Quaternion = saved_basis.get_rotation_quaternion() * saved_visual
	player.visual.quaternion = seat_basis.get_rotation_quaternion().inverse() * original_visual.slerp(seat_basis.get_rotation_quaternion(), turn)
	rest_pose.call("set_amount", amount, clock)

func _open_books() -> void:
	_lock_player()
	state = &"selecting"
	_prepare_modal("選取書籍閱讀", "方向鍵選擇 · Enter 拿取 · Esc 關閉")
	var intro: Label = _label("選一本書拿起來。書籍內容將於之後加入。", 18)
	content.add_child(intro)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(520, 310)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var grid: GridContainer = GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)
	var first: Button = null
	for book: Dictionary in books:
		var button: Button = _button(str(book.get("title", book.id)))
		button.custom_minimum_size = Vector2(164, 56)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(select_book.bind(str(book.id)))
		grid.add_child(button)
		if first == null:
			first = button
	if first != null:
		first.grab_focus.call_deferred()

func select_book(id: String) -> void:
	if state != &"selecting":
		return
	var selected: Dictionary = {}
	for book: Dictionary in books:
		if str(book.id) == id:
			selected = book
			break
	if selected.is_empty():
		return
	book_id = id
	selected_shelf_book = room_model.find_child(str(selected.get("node_name", id)), true, false) as Node3D
	var source: Vector3 = _vector(selected.get("position", [9.2, 1.5, 1.95]))
	if selected_shelf_book != null:
		shelf_book_was_visible = selected_shelf_book.visible
		selected_shelf_book.visible = false
	overlay.visible = false
	var to_shelf: Vector3 = (source - player.global_position).slide(Vector3.UP).normalized()
	var body_visual_basis: Basis = Basis.looking_at(-to_shelf, Vector3.UP)
	player.visual.quaternion = player.global_basis.get_rotation_quaternion().inverse() * body_visual_basis.get_rotation_quaternion()
	reading_camera = {"camera_yaw": room.get("camera_yaw"), "camera_pitch": room.get("camera_pitch"), "camera_distance": room.get("camera_distance")}
	room.set("camera_yaw", atan2(to_shelf.x, to_shelf.z) - .65)
	room.set("camera_pitch", .16)
	room.set("camera_distance", 2.7)
	reading_pose = ReadingPose.new() as RefCounted
	reading_pose.call("configure", player)
	_create_book(Color(str(selected.get("color", "345c58"))))
	book_start = Transform3D(Basis(Vector3.UP, float(selected.get("rotation_y", 0))), source)
	book_end = Transform3D(player.visual.global_basis * Basis(Vector3.RIGHT, -.22), player.visual.to_global(Vector3(0, 1.10, .47)))
	held_book.global_transform = book_start
	state = &"taking_book"
	clock = 0

func _create_book(color: Color) -> void:
	held_book = Node3D.new()
	held_book.name = "HeldReadingBook"
	room.add_child(held_book)
	var cover: StandardMaterial3D = StandardMaterial3D.new()
	cover.albedo_color = color
	cover.roughness = .85
	var pages: StandardMaterial3D = StandardMaterial3D.new()
	pages.albedo_color = Color("f0e7cb")
	pages.roughness = .96
	leaf_left = Node3D.new()
	leaf_right = Node3D.new()
	held_book.add_child(leaf_left)
	held_book.add_child(leaf_right)
	for side: int in [-1, 1]:
		var leaf: Node3D = leaf_left if side < 0 else leaf_right
		_book_box(leaf, Vector3(side * .105, -.018, 0), Vector3(.21, .012, .29), cover)
		_book_box(leaf, Vector3(side * .102, 0, 0), Vector3(.197, .028, .276), pages)
	_book_box(held_book, Vector3(0, -.018, 0), Vector3(.016, .03, .29), cover)
	_set_book_open(0)

func _book_box(parent: Node3D, at: Vector3, size_value: Vector3, material: Material) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var box: BoxMesh = BoxMesh.new()
	box.size = size_value
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)

func _set_book_open(amount: float) -> void:
	book_open_amount = amount
	leaf_left.rotation.z = lerpf(-1.50, -.06, amount)
	leaf_right.rotation.z = lerpf(1.50, .06, amount)

func _show_reading() -> void:
	var book_title: String = book_id
	for book: Dictionary in books:
		if str(book.id) == book_id:
			book_title = str(book.get("title", book_id))
	_prepare_modal(book_title, "E / Esc 闔上並放回書架")
	modal_row.alignment = BoxContainer.ALIGNMENT_END
	dim.color.a = .18
	# Blank pages intentionally contain no invented chapters or book content.
	var pages_row: HBoxContainer = HBoxContainer.new()
	pages_row.add_theme_constant_override("separation", 3)
	content.add_child(pages_row)
	for page: int in range(2):
		var blank: PanelContainer = PanelContainer.new()
		blank.custom_minimum_size = Vector2(220, 255)
		blank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		blank.add_theme_stylebox_override("panel", _style(Color("faf4df"), Color("d9cda8")))
		blank.tooltip_text = "空白書頁"
		pages_row.add_child(blank)
	var status: Label = _label("書籍內容尚未加入", 17)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(status)
	close_button.text = "闔上並放回書架"
	close_button.grab_focus.call_deferred()

func show_inspection(heading: String, body: String, texture: Texture2D = null) -> void:
	if state != &"idle":
		return
	_lock_player()
	state = &"inspection"
	_prepare_modal(heading, "E / Esc 關閉")
	if texture != null:
		var picture: TextureRect = TextureRect.new()
		picture.texture = texture
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.custom_minimum_size = Vector2(520, 320)
		content.add_child(picture)
	var description: Label = _label(body, 19)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.custom_minimum_size.x = 520
	content.add_child(description)
	close_button.grab_focus.call_deferred()

func close_modal() -> void:
	if state == &"reading":
		overlay.visible = false
		state = &"returning_book"
		clock = 0
	elif state in [&"selecting", &"inspection"]:
		overlay.visible = false
		_unlock_player()

func _update_book() -> void:
	var progress: float = clampf(clock / BOOK_SECONDS, 0, 1)
	var amount: float = smoothstep(0, 1, progress)
	if state == &"returning_book":
		amount = 1.0 - amount
	held_book.global_transform = book_start.interpolate_with(book_end, amount)
	held_book.global_position.y += sin(amount * PI) * .18
	_set_book_open(smoothstep(.35, 1, amount))
	reading_pose.call("set_amount", amount)
	if progress >= 1:
		if state == &"taking_book":
			state = &"reading"
			_show_reading()
		else:
			_restore_book()
			player.global_basis = saved_basis
			player.visual.quaternion = saved_visual
			_unlock_player()

func _restore_book() -> void:
	if is_instance_valid(room):
		for property: String in reading_camera:
			room.set(property, reading_camera[property])
	reading_camera.clear()
	if is_instance_valid(selected_shelf_book):
		selected_shelf_book.visible = shelf_book_was_visible
	selected_shelf_book = null
	if is_instance_valid(held_book):
		held_book.queue_free()
		held_book = null
	if reading_pose != null:
		reading_pose.call("finish")
		reading_pose = null
	book_id = ""

func _physics_process(delta: float) -> void:
	message_clock = maxf(0.0, message_clock - delta)
	clock += delta
	if state in [&"sitting", &"seated", &"standing"]:
		_update_seat()
	elif state in [&"taking_book", &"returning_book"]:
		_update_book()

func _input(event: InputEvent) -> void:
	if state == &"idle" or not event is InputEventKey or event.is_echo():
		return
	var key_event: InputEventKey = event as InputEventKey
	if key_event.pressed and (key_event.physical_keycode == KEY_ESCAPE or key_event.keycode == KEY_ESCAPE):
		if state == &"seated":
			interact()
		else:
			close_modal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and camera_blocked():
		interact()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_restore_book()
	if rest_pose != null:
		rest_pose.call("finish")
	if is_instance_valid(player) and state != &"idle":
		player.is_resting = false
		player.controls_enabled = saved_controls
		player.collision_mask = saved_mask

func _style(fill: Color, border: Color = Color("c3b893")) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style

func _label(text: String, size_value: int) -> Label:
	var result: Label = Label.new()
	result.text = text
	result.add_theme_font_override("font", FONT)
	result.add_theme_font_size_override("font_size", size_value)
	result.add_theme_color_override("font_color", Color("294a4c"))
	return result

func _button(text: String) -> Button:
	var result: Button = Button.new()
	result.text = text
	result.add_theme_font_override("font", FONT)
	result.add_theme_font_size_override("font_size", 18)
	result.add_theme_color_override("font_color", Color("f5eedc"))
	result.add_theme_color_override("font_hover_color", Color("213f41"))
	result.add_theme_stylebox_override("normal", _style(Color("345c58")))
	result.add_theme_stylebox_override("hover", _style(Color("e9d49b")))
	result.add_theme_stylebox_override("pressed", _style(Color("b49b69")))
	result.add_theme_stylebox_override("focus", _style(Color("00000000"), Color("b88b2c")))
	return result

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.name = "InteractionUI"
	layer.layer = 20
	add_child(layer)
	overlay = Control.new()
	overlay.name = "Modal"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	dim = ColorRect.new()
	dim.color = Color(0.04, .10, .11, .60)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var margins: MarginContainer = MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge: String in ["left", "top", "right", "bottom"]:
		margins.add_theme_constant_override("margin_" + edge, 24)
	overlay.add_child(margins)
	var center: VBoxContainer = VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	margins.add_child(center)
	modal_row = HBoxContainer.new()
	modal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(modal_row)
	modal_panel = PanelContainer.new()
	modal_panel.add_theme_stylebox_override("panel", _style(Color("ede9d7")))
	modal_row.add_child(modal_panel)
	modal_column = VBoxContainer.new()
	modal_column.add_theme_constant_override("separation", 16)
	modal_panel.add_child(modal_column)
	title = _label("", 27)
	modal_column.add_child(title)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	modal_column.add_child(content)
	footer = _label("", 15)
	modal_column.add_child(footer)
	close_button = _button("關閉")
	close_button.pressed.connect(close_modal)
	modal_column.add_child(close_button)
	overlay.visible = false

func _prepare_modal(heading: String, hint: String) -> void:
	for child: Node in content.get_children():
		content.remove_child(child)
		child.queue_free()
	title.text = heading
	footer.text = hint
	modal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	dim.color.a = .60
	close_button.text = "關閉"
	overlay.visible = true
