extends SceneTree

## Visible Windows check for WRY's physical child-window rectangle. Local HTML
## only, isolated profile, no Firebase, tokens, network or external browser.
const NativeHost = preload("res://scripts/account_native_host.gd")
var host: Node
var room: Node3D
var probe: Dictionary = {}
var failures: int = 0

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	root.title = "Star Path - Bounded Terminal QA"
	root.size = Vector2i(1280, 800)
	root.position = Vector2i(70, 70)
	root.close_requested.connect(func() -> void: quit())
	room = load("res://scenes/admissions_room.tscn").instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	var until: int = Time.get_ticks_msec() + 15000
	while room.get("ready_for_play") != true and Time.get_ticks_msec() < until:
		await process_frame
	(room.get("player") as Node).process_mode = Node.PROCESS_MODE_DISABLED
	(room.get("hud") as CanvasLayer).hide()
	host = NativeHost.new()
	root.add_child(host)
	host.call("_ensure_loading_ui")
	var terminal: CanvasLayer = host.get("terminal") as CanvasLayer
	terminal.call("set_view", "general")
	terminal.show()
	(terminal.get("status") as Control).hide()
	var webview: Control = ClassDB.instantiate("WebView") as Control
	webview.set("full_window_size", false)
	webview.set("data_directory", "user://qa/account-layout-only")
	webview.set("forward_input_events", false)
	webview.set("url", "")
	webview.set("html", "<!doctype html><html lang='zh-Hant'><meta charset='utf-8'><style>html,body{height:100%;margin:0;box-sizing:border-box;background:#f6f3e9;color:#244f4b;font:20px system-ui}body{border:8px solid #d7b878;padding:32px}h1{font-size:32px}p{max-width:520px;line-height:1.8}.tabs{padding:14px;background:#dce6dd;border-radius:10px}</style><body><div class='tabs'>一般大學　　特殊招生　　APCS　　成績</div><h1>在工作台上，找到下一步</h1><p>這是獨立的版面驗證頁。螢幕外側應保留落點分析室，頂部與底部能看到遊戲邊框。</p><p id='bounds'></p><script>setInterval(()=>{document.getElementById('bounds').textContent=innerWidth+' × '+innerHeight;window.ipc.postMessage(JSON.stringify({width:innerWidth,height:innerHeight,dpr:devicePixelRatio}))},500)</script></body></html>")
	webview.connect("ipc_message", func(payload: String) -> void:
		var data: Variant = JSON.parse_string(payload)
		if data is Dictionary:
			probe = data)
	host.set("webview", webview)
	host.set("opened", true)
	host.set("host_ready", true)
	terminal.add_child(webview)
	host.call("_place_webview")
	for state: String in ["normal", "moved", "compact", "maximized"]:
		if state == "moved":
			root.position = Vector2i(210, 135)
		elif state == "compact":
			root.size = Vector2i(800, 650)
		elif state == "maximized":
			root.mode = Window.MODE_MAXIMIZED
		await check_bounds(state, terminal, webview)
	if OS.get_cmdline_user_args().has("--keep-open"):
		return
	host.queue_free()
	room.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func check_bounds(state: String, terminal: CanvasLayer, webview: Control) -> void:
	await create_timer(1.5).timeout
	var rect: Rect2 = terminal.get("screen_rect") as Rect2
	var physical: Rect2 = root.get_final_transform() * rect
	var expected: Vector2 = physical.size
	var actual := Vector2(float(probe.get("width", 0)), float(probe.get("height", 0))) * float(probe.get("dpr", 1))
	var correct: bool = actual.distance_to(expected) < 3.0 and webview.get_screen_position().distance_to(physical.position) < 1.0
	if not correct:
		failures += 1
	print("ACCOUNT_NATIVE_LAYOUT ", state, " expected=", expected, " actual=", actual, " position=", webview.get_screen_position(), " passed=", correct)
	print("ACCOUNT_NATIVE_LAYOUT root=", root.size, " logical=", root.get_visible_rect(), " rect=", rect, " control=", webview.position)
	print("ACCOUNT_NATIVE_LAYOUT final=", root.get_final_transform(), " stretch=", root.get_stretch_transform(), " screen=", root.get_screen_transform())
