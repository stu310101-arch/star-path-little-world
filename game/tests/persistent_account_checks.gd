extends SceneTree
class Service:
	extends Node
	signal state_changed(user: Dictionary)
	signal session_checked(user: Dictionary)
	signal closed
	signal failed(message: String)
	signal progress_message(packet: Dictionary)
	var user: Dictionary = {}
	var opened: bool = false
	var last_error: String = ""
	var opens: int = 0
	func resume_session() -> void:
		user = {"signedIn":true,"displayName":"測試使用者","identity":"university","profileReady":true,"sessionGeneration":77}
		state_changed.emit(user)
		session_checked.emit(user)
	func open_view(_view: String) -> bool:
		opens += 1
		opened = true
		return true
	func close_view() -> void:
		opened = false
		closed.emit()
func _initialize() -> void:
	run.call_deferred()
func run() -> void:
	root.get_node("ResourceProfile").set("profile", "low")
	var service: Node = Service.new()
	service.name = "StarPathAccount"
	root.add_child(service)
	var gate: Node = root.get_node("AccountGate")
	gate.call("start")
	for frame: int in range(12):
		await process_frame
	var passed: bool = current_scene != null and current_scene.has_method("teleport_to") and not paused and service.get("opens") == 0
	print("PERSISTENT_ACCOUNT_CHECK restored session enters without login modal ", passed)
	service.set("user", {})
	service.emit_signal("state_changed", {})
	passed = passed and paused and bool(gate.get("locked"))
	print("PERSISTENT_ACCOUNT_CHECK explicit logout locks game ", paused and bool(gate.get("locked")))
	if current_scene != null:
		current_scene.queue_free()
	await process_frame
	await process_frame
	quit(0 if passed else 1)
