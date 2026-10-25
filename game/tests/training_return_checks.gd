extends SceneTree

const Fixture: Script = preload("res://tests/startup_fixture.gd")
var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(label: String, passed: bool) -> void:
	print("TRAINING_RETURN_CHECK ", label, " passed=", passed)
	if not passed:
		failures += 1

func _run() -> void:
	for scenario: String in ["hud_ready", "hud_loading", "escape_loading", "portal_ready"]:
		var early_return: bool = scenario.ends_with("loading")
		var room: Node3D = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
		root.add_child(room)
		current_scene = room
		if not early_return:
			check("Standalone room becomes playable", await Fixture.wait_room(room, self))
		await process_frame
		var room_id: int = room.get_instance_id()
		var button: Button = room.find_child("ReturnToWorld", true, false) as Button
		if early_return:
			check("Return is tested before player readiness", not bool(room.get("ready_for_play")))
		if scenario.begins_with("hud"):
			# Exercise the HUD hit target and input dispatch, including a double click.
			var point: Vector2 = button.get_global_rect().get_center()
			for click: int in range(2):
				for down: bool in [true, false]:
					var event: InputEventMouseButton = InputEventMouseButton.new()
					event.button_index = MOUSE_BUTTON_LEFT
					event.position = point
					event.global_position = point
					event.pressed = down
					root.push_input(event, true)
		else:
			if scenario == "portal_ready":
				room.get("player").call("place_at", Vector3(0, .09, 7.2), Vector3.BACK)
			for down: bool in [true, false]:
				var event: InputEventKey = InputEventKey.new()
				event.keycode = KEY_ESCAPE if early_return else KEY_E
				event.physical_keycode = event.keycode
				event.pressed = down
				root.push_input(event, true)
		check("Input starts the return: " + scenario, bool(room.get("returning")))
		var deadline: int = Time.get_ticks_msec() + 15000
		while current_scene == room and Time.get_ticks_msec() < deadline:
			await process_frame
		await process_frame
		var world: Node3D = current_scene as Node3D
		var returned: bool = world != null and world.scene_file_path == "res://scenes/world.tscn"
		check("Standalone room returns to main world: " + scenario, returned)
		check("Room is released after return", not is_instance_id_valid(room_id))
		if not returned:
			quit(1)
			return
		check("World camera is active", root.get_camera_3d() == world.get("camera"))
		if OS.get_cmdline_user_args().has("--constrained"):
			var settings: Node = world.get("graphics_settings") as Node
			settings.set("quality_profile", "mobile")
			settings.call("apply_settings")
			settings.emit_signal("state_changed")
			check("Returned world uses constrained runtime", bool(world.get("streaming").call("metrics").constrained_runtime))
		world.call("set_overview", false)
		check("Returned world can enter roaming", await Fixture.wait_roaming(world, self))
		check("Returned world accepts movement", bool(world.get("player").get("controls_enabled")))
		current_scene = null
		world.queue_free()
		await process_frame
		await process_frame
	print("TRAINING_RETURN_CHECKS failures=", failures)
	quit(0 if failures == 0 else 1)
