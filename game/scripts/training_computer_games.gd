extends Node3D

# The authored IDs are the contract: a computer always belongs to one chair,
# regardless of which monitor happens to be geometrically closest.
const CATALOG_PATH: String = "res://data/training_computer_games.json"
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")

var room: Node3D
var router: Node
var assignments: Dictionary = {}
var screen_points: Dictionary = {}
var labels: Dictionary = {}
var layer: CanvasLayer
var overlay: Control
var panel: PanelContainer
var title: Label
var enter_button: Button
var hint: Label
var game_open: bool = false
var shown_seat_id: String = ""

func configure(host: Node3D, art: Node3D, interactions: Node, room_layout: Dictionary) -> void:
	room = host
	router = interactions
	name = "ComputerGames"
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	if not parsed is Dictionary:
		push_error("Computer game assignments could not be read")
		return
	var computers: Dictionary = {}
	for computer: Dictionary in room_layout.get("computers", []):
		computers[str(computer.get("id", ""))] = computer
	var seats: Dictionary = {}
	for seat: Dictionary in router.get("targets") as Array:
		if str(seat.get("kind", "")) == "seat":
			seats[str(seat.get("id", ""))] = seat
	var assigned_computers: Dictionary = {}
	for row: Dictionary in (parsed as Dictionary).get("computers", []):
		var computer_id: String = str(row.get("computer_id", ""))
		var seat_id: String = str(row.get("seat_id", ""))
		if not computers.has(computer_id) or not seats.has(seat_id) or assignments.has(seat_id) or assigned_computers.has(computer_id):
			push_error("Invalid or duplicate computer/chair assignment: " + computer_id + " / " + seat_id)
			continue
		var computer: Dictionary = computers[computer_id] as Dictionary
		var monitor: Node3D = art.find_child(str(computer.get("node_name", "")), true, false) as Node3D
		if monitor == null:
			push_error("Assigned computer screen is missing: " + computer_id)
			continue
		var game: Dictionary = (row.get("game", {}) as Dictionary).duplicate(true)
		var seat: Dictionary = (seats[seat_id] as Dictionary).duplicate(true)
		var game_title: String = str(game.get("title", "尚未安裝遊戲"))
		seat["computer_id"] = computer_id
		seat["computer_game"] = game
		seat["label"] = str(computer.get("label", "電腦")) + " · " + game_title
		router.call("register_target", seat)
		assignments[seat_id] = {"computer_id": computer_id, "game": game, "title": game_title}
		assigned_computers[computer_id] = true
		var screen_center: Vector3 = _screen_center(monitor)
		screen_points[seat_id] = screen_center
		var label: Label3D = Label3D.new()
		label.name = "Title_" + computer_id
		label.text = game_title
		label.font = FONT
		label.font_size = 44
		label.outline_size = 10
		label.pixel_size = .0045
		label.modulate = Color("f4e2ac") if not game.is_empty() else Color("d0d9d2")
		label.outline_modulate = Color("143033")
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.visible = false
		add_child(label)
		label.global_position = screen_center + Vector3.UP * .42
		labels[seat_id] = label
	_build_ui()
	refresh_ui()

func _screen_center(monitor: Node3D) -> Vector3:
	# The GLB screen assembly has separate ink/light mesh children. Derive its
	# display anchor from those authored meshes, preserving all their transforms.
	var meshes: Array[Node] = monitor.find_children("*", "MeshInstance3D", true, false)
	if monitor is MeshInstance3D:
		meshes.append(monitor)
	var bounds: AABB = AABB()
	var started: bool = false
	for node: Node in meshes:
		var mesh: MeshInstance3D = node as MeshInstance3D
		var global_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = bounds.merge(global_bounds) if started else global_bounds
		started = true
	return bounds.get_center() if started else monitor.global_position

func is_open() -> bool:
	return game_open

func set_game_open(opened: bool) -> void:
	game_open = opened
	if is_instance_valid(router):
		router.set("computer_game_open", opened)
	refresh_ui()

func game_for_seat(seat_id: String) -> Dictionary:
	var assignment: Dictionary = assignments.get(seat_id, {}) as Dictionary
	return (assignment.get("game", {}) as Dictionary).duplicate(true)

func active_game() -> Dictionary:
	if router == null or str(router.get("state")) != "seated":
		return {}
	var seat: Dictionary = router.get("active") as Dictionary
	return game_for_seat(str(seat.get("id", "")))

func handle_input(event: InputEvent) -> bool:
	if game_open:
		if event is InputEventKey and event.is_pressed() and not event.is_echo():
			var close_key: InputEventKey = event as InputEventKey
			if close_key.physical_keycode == KEY_ESCAPE or close_key.keycode == KEY_ESCAPE:
				room.call("close_computer_game")
		# While the HTML owns focus, gameplay keyboard and drag input stay locked.
		return true
	if not event is InputEventKey or not event.is_pressed() or event.is_echo():
		return false
	var key: InputEventKey = event as InputEventKey
	if key.physical_keycode not in [KEY_F, KEY_ENTER, KEY_KP_ENTER] and key.keycode not in [KEY_F, KEY_ENTER, KEY_KP_ENTER]:
		return false
	if router == null or str(router.get("state")) != "seated":
		return false
	var seat: Dictionary = router.get("active") as Dictionary
	if not assignments.has(str(seat.get("id", ""))):
		return false
	launch_active_game()
	return true

func launch_active_game() -> void:
	if game_open or not is_instance_valid(room) or bool(room.get("returning")):
		return
	var game: Dictionary = active_game()
	if game.is_empty():
		return
	if bool(room.call("open_computer_game", game)):
		set_game_open(true)

func refresh_ui() -> void:
	if router == null or panel == null:
		return
	var interaction_state: String = str(router.get("state"))
	var target: Dictionary = router.get("nearest") as Dictionary if interaction_state == "idle" else router.get("active") as Dictionary
	var seat_id: String = str(target.get("id", ""))
	var assigned: bool = assignments.has(seat_id)
	var seated: bool = interaction_state == "seated"
	for id: String in labels:
		var label: Label3D = labels[id] as Label3D
		label.visible = assigned and id == seat_id and not seated and not game_open and interaction_state in ["idle", "sitting"]
	panel.visible = assigned and seated and not game_open
	if not panel.visible:
		shown_seat_id = ""
		return
	var assignment: Dictionary = assignments[seat_id] as Dictionary
	var game: Dictionary = assignment.game as Dictionary
	title.text = str(assignment.title)
	enter_button.visible = not game.is_empty()
	enter_button.disabled = game.is_empty()
	hint.text = "E 起身"
	if shown_seat_id != seat_id:
		shown_seat_id = seat_id
		if not game.is_empty():
			enter_button.grab_focus.call_deferred()
	_position_panel(seat_id)

func _position_panel(seat_id: String) -> void:
	var camera: Camera3D = room.get("camera") as Camera3D
	if camera == null:
		return
	var point: Vector3 = screen_points[seat_id] as Vector3
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	# A compact container follows the authored screen. Clamp to the viewport
	# so orbiting the chair or resizing the game keeps Enter reachable.
	var anchor: Vector2 = camera.unproject_position(point)
	if camera.is_position_behind(point):
		anchor = viewport_size * Vector2(.5, .65)
	panel.reset_size()
	var panel_size: Vector2 = panel.get_combined_minimum_size()
	panel.position = Vector2(clampf(anchor.x - panel_size.x * .5, 16, maxf(16, viewport_size.x - panel_size.x - 16)), clampf(anchor.y - panel_size.y * .5, 112, maxf(112, viewport_size.y - panel_size.y - 92)))

func _process(_delta: float) -> void:
	refresh_ui()

func _style(fill: Color, border: Color) -> StyleBoxFlat:
	var style: StyleBoxFlat = StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.name = "ComputerGameUI"
	layer.layer = 19
	add_child(layer)
	overlay = Control.new()
	overlay.name = "ScreenOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(overlay)
	panel = PanelContainer.new()
	panel.name = "ComputerScreen"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(Color("173b3aee"), Color("c4b584")))
	overlay.add_child(panel)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	panel.add_child(column)
	title = Label.new()
	title.name = "GameTitle"
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("f5eedc"))
	column.add_child(title)
	enter_button = Button.new()
	enter_button.name = "EnterGame"
	enter_button.text = "進入 · F / Enter"
	enter_button.custom_minimum_size = Vector2(200, 44)
	enter_button.add_theme_font_override("font", FONT)
	enter_button.add_theme_font_size_override("font_size", 19)
	enter_button.add_theme_color_override("font_color", Color("f5eedc"))
	enter_button.add_theme_color_override("font_hover_color", Color("213f41"))
	enter_button.add_theme_color_override("font_pressed_color", Color("213f41"))
	enter_button.add_theme_stylebox_override("normal", _style(Color("345c58"), Color("a7986c")))
	enter_button.add_theme_stylebox_override("hover", _style(Color("e9d49b"), Color("f4e8c8")))
	enter_button.add_theme_stylebox_override("pressed", _style(Color("b49b69"), Color("f4e8c8")))
	enter_button.add_theme_stylebox_override("disabled", _style(Color("334745"), Color("657a71")))
	var focus: StyleBoxFlat = _style(Color.TRANSPARENT, Color("f4d575"))
	focus.set_border_width_all(2)
	enter_button.add_theme_stylebox_override("focus", focus)
	enter_button.pressed.connect(launch_active_game)
	column.add_child(enter_button)
	hint = Label.new()
	hint.name = "StandHint"
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_override("font", FONT)
	hint.add_theme_font_size_override("font_size", 15)
	hint.add_theme_color_override("font_color", Color("d0d9d2"))
	column.add_child(hint)
	panel.visible = false

func _exit_tree() -> void:
	if is_instance_valid(router):
		router.set("computer_game_open", false)
