extends Node
var _callback: JavaScriptObject

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
		var x: float = float(arguments[1])
		var y: float = float(arguments[2])
		var strengths: Dictionary = {"move_left":maxf(-x, 0), "move_right":maxf(x, 0), "move_forward":maxf(-y, 0), "move_back":maxf(y, 0)}
		for action: String in strengths:
			if not InputMap.has_action(action):
				continue
			if float(strengths[action]) > 0.0:
				Input.action_press(action, float(strengths[action]))
			else:
				Input.action_release(action)
	elif kind == "action":
		var action: String = str(arguments[1])
		if action == "use":
			var key: InputEventKey = InputEventKey.new()
			key.keycode = KEY_F
			key.physical_keycode = KEY_F
			key.pressed = bool(arguments[2])
			Input.parse_input_event(key)
		elif action in ["run", "jump", "interact"] and InputMap.has_action(action):
			var event: InputEventAction = InputEventAction.new()
			event.action = action
			event.pressed = bool(arguments[2])
			event.strength = 1.0 if event.pressed else 0.0
			Input.parse_input_event(event)
	elif kind == "look":
		for target: Node in get_tree().get_nodes_in_group("touch_camera"):
			target.call("touch_look", Vector2(float(arguments[1]), float(arguments[2])))
