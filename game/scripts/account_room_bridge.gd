extends Node

## Keeps account credentials in the persistent host, and room state in the room.
signal opened(view: String)
signal closed
signal failed(message: String)

const AccountSession = preload("res://scripts/account_session.gd")
const NativeHost = preload("res://scripts/account_native_host.gd")
var room: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var account: Node
var active: bool = false
var snapshot: Dictionary = {}
var _open_generation: int = 0
var _host_opened: bool = false

func configure(owner_room: Node3D, actor: CharacterBody3D, room_hud: CanvasLayer) -> void:
	room = owner_room
	player = actor
	hud = room_hud
	account = get_tree().root.get_node_or_null("StarPathAccount")
	if account == null:
		account = AccountSession.new()
		account.name = "StarPathAccount"
		get_tree().root.add_child.call_deferred(account)
	account.connect("closed", _closed)

func is_open() -> bool:
	return active

func open_view(view: String) -> bool:
	if view not in NativeHost.VIEWS or account == null:
		return false
	if active:
		return _host_opened and bool(account.call("open_view", view))
	snapshot = {"transform": player.global_transform, "heading": player.get("heading"), "controls": player.get("controls_enabled"), "process_mode": player.process_mode, "hud_visible": hud.visible}
	var camera: Camera3D = room.get("camera") as Camera3D
	if camera != null:
		snapshot["camera_transform"] = camera.global_transform
		snapshot["camera_fov"] = camera.fov
	for property: Dictionary in room.get_property_list():
		var name: String = str(property.name)
		if name in ["camera_yaw", "camera_pitch", "camera_distance"]:
			snapshot[name] = room.get(name)
	active = true
	_clear_inputs(true)
	player.set("controls_enabled", false)
	player.velocity = Vector3.ZERO
	player.process_mode = Node.PROCESS_MODE_DISABLED
	hud.hide()
	_open_generation += 1
	_open_after_focus.call_deferred(view, _open_generation)
	return true

func _open_after_focus(view: String, generation: int) -> void:
	if room.has_method("begin_account_focus"):
		var focused: Variant = await room.call("begin_account_focus", view)
		if not active or generation != _open_generation:
			return
		if focused is bool and not focused:
			_closed()
			failed.emit("工作台視角尚未準備完成，請稍後再試。")
			return
	if not active or generation != _open_generation:
		return
	if not bool(account.call("open_view", view)):
		_closed()
		failed.emit(str(account.get("last_error")))
		return
	_host_opened = true
	opened.emit(view)

func close_view() -> void:
	if active:
		account.call("close_view")
		_closed()

func _closed() -> void:
	if not active:
		return
	active = false
	_host_opened = false
	_open_generation += 1
	if room.has_method("end_account_focus"):
		room.call("end_account_focus")
	_clear_inputs(false)
	player.global_transform = snapshot.transform as Transform3D
	player.set("heading", snapshot.heading)
	player.set("controls_enabled", snapshot.controls)
	player.velocity = Vector3.ZERO
	player.process_mode = snapshot.process_mode
	if player.has_method("reset_render_interpolation"):
		player.call("reset_render_interpolation")
	for name: String in ["camera_yaw", "camera_pitch", "camera_distance"]:
		if snapshot.has(name):
			room.set(name, snapshot[name])
	var camera: Camera3D = room.get("camera") as Camera3D
	if camera != null and snapshot.has("camera_transform"):
		camera.global_transform = snapshot.camera_transform as Transform3D
		camera.fov = float(snapshot.camera_fov)
	hud.visible = bool(snapshot.hud_visible)
	get_viewport().gui_release_focus()
	snapshot.clear()
	closed.emit()

func _clear_inputs(modal: bool) -> void:
	if room.has_method("_finish_drag"):
		room.call("_finish_drag")
	if player.has_method("cancel_jump_input"):
		player.call("cancel_jump_input")
	for action: StringName in [&"move_left", &"move_right", &"move_forward", &"move_back", &"run", &"jump", &"interact"]:
		if InputMap.has_action(action):
			Input.action_release(action)
	var touch: Node = get_node_or_null("/root/WebTouch")
	if touch != null:
		touch.call("reset_input")
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldTouchUI")
		if bridge != null:
			bridge.setModalOpen(modal)

func _input(event: InputEvent) -> void:
	if active and event.is_action_pressed("ui_cancel"):
		close_view()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	_open_generation += 1
	if active and is_instance_valid(account):
		active = false
		account.call("close_view")
