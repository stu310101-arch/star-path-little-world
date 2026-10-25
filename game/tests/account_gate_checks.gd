extends SceneTree
const Catalog = preload("res://scripts/university_catalog.gd")
const Progress = preload("res://scripts/progress_protocol.gd")
class Service:
	extends Node
	signal state_changed(user: Dictionary)
	signal closed
	signal failed(message: String)
	signal progress_message(packet: Dictionary)
	var user: Dictionary = {}
	var opened: bool = false
	var last_error: String = ""
	var commands: Array[Dictionary] = []
	func open_view(_view: String) -> bool:
		opened = true
		return true
	func close_view() -> void:
		opened = false
		closed.emit()
	func request_progress(command: Dictionary) -> bool:
		commands.append(command)
		return true
var failures: int = 0
var count: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	count += 1
	print("GATE_CHECK ",label," ",passed)
	if not passed:
		failures += 1
func tick(frames: int = 4) -> void:
	for i: int in range(frames):
		await process_frame
func run() -> void:
	var service := Service.new()
	service.name = "StarPathAccount"
	service.process_mode = Node.PROCESS_MODE_ALWAYS
	service.user = {"signedIn":true,"displayName":"學生","identity":"university","profileReady":true,"sessionGeneration":7}
	root.add_child(service)
	var catalog: RefCounted = Catalog.new()
	check("Real university catalogue loads",catalog.call("load_content"))
	catalog.call("configure_cloud",service)
	catalog.call("load_progress")
	check("Cloud catalogue starts with get, not automatic local import",service.commands.size()==1 and service.commands[0].action=="university-get")
	catalog.call("toggle_favorite","001")
	check("Favorite mutation sends explicit true",service.commands.back().action=="university-favorite" and service.commands.back().value==true)
	catalog.call("toggle_favorite","001")
	check("Unfavorite sends explicit false",service.commands.back().value==false)
	var packet: Dictionary = {"channel":"starpath-progress","version":1,"type":"state","app":"university","requestId":service.commands.back().requestId,"sessionGeneration":7,"favorites":{"001":false,"002":true},"explored":["003"],"revision":1}
	service.progress_message.emit(Progress.sanitize_packet(packet))
	check("Cloud state honors false tombstones and explored IDs",not catalog.favorites.has("001") and catalog.favorites.has("002") and catalog.visited.has("003"))
	catalog.call("detach_cloud")
	service.user = {}
	var gate: Node = root.get_node("AccountGate")
	gate.call("start")
	await tick()
	check("Unauthenticated game is paused behind persistent gate",paused and gate.get("locked") and current_scene==null)
	service.user = {"signedIn":true,"displayName":"學生","identity":"","profileReady":false,"sessionGeneration":1}
	service.state_changed.emit(service.user)
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await tick()
	check("Esc cannot bypass unfinished identity",paused and gate.get("locked") and current_scene==null)
	service.user.identity = "university"
	service.user.profileReady = true
	service.state_changed.emit(service.user)
	await tick(6)
	check("Server-ready profile enters world",not paused and not gate.get("locked") and current_scene!=null and current_scene.has_method("teleport_to"))
	var previous_world: int = current_scene.get_instance_id()
	service.user.sessionGeneration = 2
	service.state_changed.emit(service.user)
	check("Changed account locks before the old scene can accept input",paused and gate.get("locked"))
	await tick(8)
	check("Changed account enters a fresh world without retaining old scene",not paused and not gate.get("locked") and current_scene!=null and current_scene.get_instance_id()!=previous_world and not is_instance_id_valid(previous_world))
	service.user = {}
	service.state_changed.emit(service.user)
	check("Logout locks synchronously before scene cleanup",paused and gate.get("locked"))
	await tick(6)
	check("Logout removes old world and returns to login entry",current_scene!=null and current_scene.name=="LoginEntry" and paused)
	print("GATE_RESULT checks=",count," failures=",failures)
	quit(0 if failures==0 else 1)
