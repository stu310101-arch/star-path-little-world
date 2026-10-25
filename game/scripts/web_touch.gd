extends Node
var _callback: JavaScriptObject
var _touch_actions: Dictionary = {}
var _use_pressed: bool = false

func _ready() -> void:
	if not OS.has_feature("web"):
		return
	var ui: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldTouchUI")
	if ui != null:
		_callback = JavaScriptBridge.create_callback(_touch)
		ui.attach(_callback)

func _touch(arguments: Array) -> void:
	if arguments.size() < 3:
		return
	var kind: String = str(arguments[0])
	if kind == "axis":
		var axis: Vector2 = Vector2(float(arguments[1]), float(arguments[2]))
		if not axis.is_finite():
			axis = Vector2.ZERO
		axis = axis.limit_length(1.0)
		_set_axis_action(&"move_left", maxf(-axis.x, 0.0))
		_set_axis_action(&"move_right", maxf(axis.x, 0.0))
		_set_axis_action(&"move_forward", maxf(-axis.y, 0.0))
		_set_axis_action(&"move_back", maxf(axis.y, 0.0))
	elif kind == "action":
		var action: String = str(arguments[1])
		if action == "use":
			_set_use(bool(arguments[2]))
		elif action in ["run", "jump", "interact"] and InputMap.has_action(action):
			var event: InputEventAction = InputEventAction.new()
			event.action = action
			event.pressed = bool(arguments[2])
			event.strength = 1.0 if event.pressed else 0.0
			Input.parse_input_event(event)
			if event.pressed:
				_touch_actions[action] = true
			else:
				_touch_actions.erase(action)
	elif kind == "look":
		var relative: Vector2 = Vector2(float(arguments[1]), float(arguments[2]))
		if not relative.is_finite() or relative.is_zero_approx():
			return
		for target: Node in get_tree().get_nodes_in_group("touch_camera"):
			if target.has_method("touch_look"):
				target.call("touch_look", relative)

func _set_axis_action(action: StringName, strength: float) -> void:
	if not InputMap.has_action(action):
		return
	if strength > 0.0:
		Input.action_press(action, strength)
		_touch_actions[action] = true
	else:
		Input.action_release(action)
		_touch_actions.erase(action)

func _set_use(pressed: bool) -> void:
	if pressed == _use_pressed:
		return
	_use_pressed = pressed
	var key: InputEventKey = InputEventKey.new()
	key.keycode = KEY_F
	key.physical_keycode = KEY_F
	key.pressed = pressed
	Input.parse_input_event(key)

func reset_input() -> void:
	for action: StringName in _touch_actions:
		Input.action_release(action)
		# Queue a matching release after any still-buffered button press. A
		# focus loss can arrive before Input has consumed this frame's events.
		var event: InputEventAction = InputEventAction.new()
		event.action = action
		event.pressed = false
		event.strength = 0.0
		Input.parse_input_event(event)
	_touch_actions.clear()
	_set_use(false)

func _notification(what: int) -> void:
	# The native focus event backs up browser blur/pagehide on mobile suspension.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		reset_input()

func _exit_tree() -> void:
	reset_input()
