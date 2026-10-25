extends SceneTree
const Startup = preload("res://tests/startup_fixture.gd")
class Account:
	extends Node
	signal closed
	var user: Dictionary = {"profileReady":true}
	var accepted: bool = true
	var views: Array[String] = []
	func open_view(view: String) -> bool:
		views.append(view)
		return accepted
	func close_view() -> void:
		closed.emit()
var failures: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	print("SHARED_GAME_CHECK ",label," ",passed)
	if not passed:
		failures += 1
func run() -> void:
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var room: Node3D = (load("res://scenes/training_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	check("Training room and shared avatar are ready",await Startup.wait_room(room,self))
	var player: Node3D = room.get("player")
	var camera: Camera3D = room.get("camera")
	var hud: Control = room.get("ui_root")
	for view: String in ["wordking","go"]:
		var before: Transform3D = player.global_transform
		var camera_before: Transform3D = camera.global_transform
		var player_mode: int = player.process_mode
		check(view+" uses the shared host",room.call("_open_shared_game",view) and account.views.back()==view)
		check(view+" freezes player and clears HUD",not player.get("controls_enabled") and player.process_mode==Node.PROCESS_MODE_DISABLED and not hud.visible)
		account.close_view()
		check(view+" close restores player camera and HUD",player.get("controls_enabled") and player.process_mode==player_mode and player.global_transform.is_equal_approx(before) and camera.global_transform.is_equal_approx(camera_before) and hud.visible)
	account.accepted = false
	check("Failed shared host open returns failure",not room.call("_open_shared_game","go"))
	check("Failed host open restores controls and UI",player.get("controls_enabled") and hud.visible and room.get("shared_game_snapshot").is_empty())
	current_scene = null
	room.queue_free()
	account.queue_free()
	await process_frame
	print("SHARED_GAME_RESULT failures=",failures)
	quit(0 if failures==0 else 1)
