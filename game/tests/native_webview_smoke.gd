extends SceneTree

var host: Node
var deadline: int

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.title = "Little World - Embedded Go QA"
	host = load("res://scripts/native_computer_game.gd").new()
	host.set("data_directory", "user://qa/embedded-go-smoke")
	root.add_child(host)
	if not bool(host.call("open_game")):
		push_error(str(host.get("last_error")))
		quit(1)
		return
	deadline = Time.get_ticks_msec() + 30000
	while not bool(host.get("game_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame
	print("NATIVE_WEBVIEW_SMOKE ready=", host.get("game_ready"), " host=", host.get("host_ready"))
	if OS.get_cmdline_user_args().has("--keep-open"):
		return
	var success: bool = bool(host.get("game_ready"))
	host.call("destroy")
	await process_frame
	quit(0 if success else 1)
