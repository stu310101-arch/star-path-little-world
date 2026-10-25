extends Node
## Persistent entry gate. Only a completed hosted profile unlocks gameplay.
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const WORLD: String = "res://scenes/world.tscn"
const ENTRY: String = "res://scenes/login_entry.tscn"
const AccountSession = preload("res://scripts/account_session.gd")
const IDENTITIES: Array[String] = ["high_school", "graduate", "university", "professional"]
var armed: bool = false
var locked: bool = true
var admitted_generation: int = -1
var layer: CanvasLayer
var message: Label
var account: Node
var changing: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func start() -> void:
	if armed:
		return
	armed = true
	account = get_node_or_null("/root/StarPathAccount")
	if account == null:
		account = AccountSession.new()
		account.name = "StarPathAccount"
		get_tree().root.add_child(account)
	account.connect("state_changed", _state_changed)
	account.connect("failed", _account_failed)
	account.connect("closed", _account_closed)
	_build_ui()
	_apply_lock()
	_state_changed(account.get("user") as Dictionary)
	if locked:
		if account.has_method("resume_session"):
			message.text = "正在恢復這台裝置的登入狀態…"
			account.connect("session_checked", _session_checked)
			account.call_deferred("resume_session")
		else:
			_open_account.call_deferred()

func _session_checked(_user: Dictionary) -> void:
	if locked:
		_open_account()

func _account_failed(text: String) -> void:
	if message != null:
		message.text = text

func _build_ui() -> void:
	layer = CanvasLayer.new()
	layer.layer = 90
	add_child(layer)
	var background := ColorRect.new()
	background.color = Color("173b3d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 22)
	center.add_child(column)
	var title := Label.new()
	title.text = "星途 · Little World"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT)
	title.add_theme_font_size_override("font_size", 30)
	column.add_child(title)
	message = Label.new()
	message.text = "登入或建立星途帳號，選擇身分後開始探索。"
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.add_theme_font_override("font", FONT)
	message.add_theme_font_size_override("font_size", 18)
	column.add_child(message)
	var button := Button.new()
	button.text = "登入 / 建立帳號"
	button.custom_minimum_size = Vector2(280, 52)
	button.add_theme_font_override("font", FONT)
	button.pressed.connect(_open_account)
	column.add_child(button)

func _open_account() -> void:
	if not locked:
		return
	if not bool(account.call("open_view", "account")):
		message.text = str(account.get("last_error"))

func _account_closed() -> void:
	if armed and locked:
		var error: String = str(account.get("last_error"))
		message.text = error if not error.is_empty() else "請完成登入與身分選擇後進入星途。"

func _state_changed(user: Dictionary) -> void:
	if not armed or changing:
		return
	var ready: bool = user.get("signedIn", false) == true and user.get("profileReady", false) == true and user.get("identity", "") in IDENTITIES
	var generation: int = int(user.get("sessionGeneration", -1))
	if not ready:
		if not locked:
			locked = true
			_apply_lock()
			_reset_scene.call_deferred()
		return
	if locked:
		admitted_generation = generation
		locked = false
		account.call("close_view")
		get_tree().paused = false
		layer.hide()
		get_tree().change_scene_to_file.call_deferred(str(get_node("/root/ResourceProfile").call("world_path")))
	elif generation != admitted_generation:
		locked = true
		_apply_lock()
		_reset_scene.call_deferred()

func _apply_lock() -> void:
	get_tree().paused = true
	if layer != null:
		layer.show()
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"run", &"jump", &"interact"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	get_node("/root/WebTouch").call("reset_input")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _reset_scene() -> void:
	changing = true
	# Transitions own suspended worlds outside current_scene; release both.
	for child: Node in get_tree().root.get_children():
		if child.has_method("open_from_world") and child.has_method("finish_return"):
			child.queue_free()
	get_tree().change_scene_to_file(ENTRY)
	await get_tree().process_frame
	changing = false
	_state_changed(account.get("user") as Dictionary)

func _input(_event: InputEvent) -> void:
	if armed and locked and not bool(account.get("opened")):
		# GUI still receives its input; consume gameplay only after GUI dispatch.
		pass

func _unhandled_input(_event: InputEvent) -> void:
	if armed and locked:
		get_viewport().set_input_as_handled()
