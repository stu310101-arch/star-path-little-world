extends Node

signal closed
signal failed(message: String)

const EXTENSION: String = "res://addons/godot_wry/WRY.gdextension"
const HOST: String = "res://web_games/native_go.html"
const SOURCE: String = "res://web_games/go/index.html"

var webview: Control
var opened: bool = false
var host_ready: bool = false
var game_ready: bool = false
var deadline: int = 0
var last_error: String = ""
# Separate profile is also useful to native integration fixtures; no browser
# profile or website account is shared with the user's external browser.
var data_directory: String = "user://computer_games/webview"

func open_game() -> bool:
	last_error = ""
	if is_instance_valid(webview):
		opened = true
		webview.call("set_visible", true)
		webview.call("focus")
		return true
	if not OS.has_feature("windows") or DisplayServer.get_name() == "headless":
		last_error = "此版本無法顯示遊戲內圍棋。請使用 Windows 遊戲版或網頁版。"
		return false
	if not _has_webview_runtime():
		last_error = "圍棋需要 Microsoft Edge WebView2 Runtime。安裝後重新啟動遊戲即可遊玩。"
		return false
	if not FileAccess.file_exists(HOST) or not FileAccess.file_exists(SOURCE):
		last_error = "圍棋檔案不完整，請重新安裝完整遊戲。"
		return false
	if not ClassDB.class_exists("WebView"):
		GDExtensionManager.load_extension(EXTENSION)
	if not ClassDB.class_exists("WebView"):
		last_error = "圍棋內嵌元件無法載入，請重新安裝完整遊戲。"
		return false
	webview = ClassDB.instantiate("WebView") as Control
	webview.name = "EmbeddedGo"
	webview.set("full_window_size", true)
	webview.set("url", HOST)
	webview.set("data_directory", data_directory)
	webview.set("forward_input_events", false)
	webview.set("devtools", false)
	webview.connect("ipc_message", _on_message)
	opened = true
	host_ready = false
	game_ready = false
	deadline = Time.get_ticks_msec() + 25000
	add_child(webview)
	return true

func _has_webview_runtime() -> bool:
	var folders: PackedStringArray = PackedStringArray()
	var fixed_runtime: String = OS.get_environment("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER")
	if not fixed_runtime.is_empty() and FileAccess.file_exists(fixed_runtime.path_join("msedgewebview2.exe")):
		return true
	for variable: String in ["ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"]:
		var base: String = OS.get_environment(variable)
		if not base.is_empty():
			folders.append(base.path_join("Microsoft/EdgeWebView/Application"))
	for folder: String in folders:
		var directory: DirAccess = DirAccess.open(folder)
		if directory != null:
			for version: String in directory.get_directories():
				if FileAccess.file_exists(folder.path_join(version).path_join("msedgewebview2.exe")):
					return true
	return false

func _on_message(payload: String) -> void:
	# WRY holds its Rust instance during IPC callbacks. Defer all view/focus
	# changes until after it returns, including closing via a HTML button.
	_receive_message.call_deferred(payload)

func _receive_message(payload: String) -> void:
	var data: Variant = JSON.parse_string(payload)
	if not data is Dictionary or not is_instance_valid(webview):
		return
	match str(data.get("type", "")):
		"host_ready": host_ready = true
		"ready":
			host_ready = true
			game_ready = true
			if not opened:
				webview.call("set_visible", false)
				webview.call("focus_parent")
		"load_failed": game_ready = false
		"close": close_game()

func _process(_delta: float) -> void:
	if is_instance_valid(webview) and not host_ready and Time.get_ticks_msec() > deadline:
		last_error = "圍棋載入逾時，請再次進入重試。"
		destroy()
		failed.emit(last_error)

func close_game() -> void:
	if not opened:
		return
	opened = false
	if is_instance_valid(webview):
		webview.call("set_visible", false)
		webview.call("focus_parent")
	closed.emit()

func destroy() -> void:
	close_game()
	if is_instance_valid(webview):
		webview.queue_free()
	webview = null
	host_ready = false
	game_ready = false
