extends SceneTree

const TouchBridge = preload("res://scripts/web_touch.gd")
var failures: int = 0

func _initialize() -> void:
	call_deferred("_run")

func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)

func _run() -> void:
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "run", "jump", "interact"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var bridge: Node = TouchBridge.new()
	root.add_child(bridge)
	bridge.call("_touch", ["axis", 0.18, -0.24])
	_check(is_equal_approx(Input.get_action_strength("move_right"), 0.18), "Joystick must retain partial analog strength")
	_check(is_equal_approx(Input.get_action_strength("move_forward"), 0.24), "Forward analog strength must survive bridge")
	bridge.call("_touch", ["axis", 3.0, -4.0])
	_check(is_equal_approx(Input.get_action_strength("move_right"), 0.6), "Out-of-range diagonal must be normalized")
	bridge.call("_touch", ["axis", NAN, 0.0])
	_check(not Input.is_action_pressed("move_right") and not Input.is_action_pressed("move_forward"), "Non-finite motion must reset movement")
	bridge.call("_touch", ["axis", -1.0, 0.0])
	bridge.call("_touch", ["action", "run", 1])
	Input.flush_buffered_events()
	_check(Input.is_action_pressed("run") and Input.is_action_pressed("move_left"), "Run and move must be usable together")
	bridge.call("reset_input")
	_check(not Input.is_action_pressed("run") and not Input.is_action_pressed("move_left"), "Focus reset must clear every touch action")
	bridge.call("_touch", ["action", "jump", 1])
	bridge.call("_touch", ["action", "jump", 0])
	Input.flush_buffered_events()
	_check(not Input.is_action_pressed("jump"), "Button release must reach Input")
	bridge.call("_touch", ["action", "move_right", 1])
	_check(not Input.is_action_pressed("move_right"), "Buttons must not inject arbitrary actions")
	bridge.call("_touch", ["action", "run", 1])
	bridge.call("reset_input")
	Input.flush_buffered_events()
	_check(not Input.is_action_pressed("run"), "Focus reset must release a button press still buffered in the same frame")
	bridge.free()
	print("WEB_TOUCH_CHECKS ", "PASS" if failures == 0 else "FAIL", " failures=", failures)
	quit(1 if failures else 0)
