extends Node

## Account-only WebView. Authentication credentials stay inside the hosted page.
signal closed
signal state_changed(user: Dictionary)
signal session_checked(user: Dictionary)
signal failed(message: String)
signal forum_message(packet: Dictionary)
signal progress_message(packet: Dictionary)
signal interest_message(packet: Dictionary)
signal recommendation_message(packet: Dictionary)

const EXTENSION: String = "res://addons/godot_wry/WRY.gdextension"
const ORIGIN: String = "https://star-path-little-world.star-path-little-world.workers.dev"
const HOST: String = ORIGIN + "/admissions/host/"
const CHANNEL: String = "starpath-account"
const VIEWS: Array[String] = ["query", "general", "special", "apcs", "scores", "account", "forum", "wordking", "go"]
const ForumProtocol = preload("res://scripts/forum_protocol.gd")
const ProgressProtocol = preload("res://scripts/progress_protocol.gd")
const InterestProtocol = preload("res://scripts/interest_protocol.gd")
const RecommendationProtocol = preload("res://scripts/recommendation_protocol.gd")
const TerminalFrame = preload("res://scripts/account_terminal_frame.gd")
const OFFICIAL_PATHS: Dictionary = {
	"www.cac.edu.tw": ["/cacportal/apply_his_report/113/", "/CacLink/apply114/", "/CacLink/apply115/", "/apply114/system/", "/apply115/system/"],
	"navy.mnd.gov.tw": ["/policyroom/Policy_Info.aspx", "/PolicyRoom/Policy_Info.aspx"],
	"daa.cpu.edu.tw": ["/p/406-1033-42144%2Cr35.php", "/p/406-1033-43854%2Cr35.php"],
	"www.jctv.ntut.edu.tw": ["/caac/contents.php"], "udb.moe.edu.tw": ["/ulist/Resource"],
	"www.dila.edu.tw": ["/files/Handbook/"], "www.tcpa.edu.tw": ["/p/406-1000-44073%2Cr302.php"],
	"studadm.nou.edu.tw": ["/Recruit/", "/FileUploads/File/794/11432701.pdf"],
	"www.ouk.edu.tw": ["/SchoolInformation/AdmissionsInformation", "/FileDownLoad/FileUpload/20250703161727074134.pdf"],
	"exam.tpa.edu.tw": ["/var/file/22/1022/img/336/351254907.pdf"], "www.ceec.edu.tw": ["/xmdoc/cont"]
}

var webview: Control
var opened: bool = false
var host_ready: bool = false
var trusted_document: bool = false
var current_view: String = "account"
var last_error: String = ""
var data_directory: String = "user://starpath_account/webview"
var deadline: int = 0
var pending_sign_out: bool = false
var loading_layer: CanvasLayer
var loading_label: Label
var retry_button: Button
var terminal: CanvasLayer
var previous_window_rect: Rect2i
var pending_forum: Dictionary = {}
var session_generation: int = -1

static func resolve_origin(candidate: String, debug_build: bool) -> String:
	if not debug_build or candidate.is_empty():
		return ORIGIN
	var expression := RegEx.new()
	expression.compile("^http://(127\\.0\\.0\\.1|localhost):([0-9]{1,5})$")
	var matched: RegExMatch = expression.search(candidate)
	if matched == null or int(matched.get_string(2)) < 1 or int(matched.get_string(2)) > 65535:
		return ORIGIN
	return candidate

static func active_origin() -> String:
	return resolve_origin(OS.get_environment("STARPATH_DEV_HOST_ORIGIN"), OS.is_debug_build())

static func host_url(view: String) -> String:
	return active_origin() + "/admissions/host/?platform=native&view=" + view

static func allowed_host_url(url: String) -> bool:
	for target: String in VIEWS:
		if url == host_url(target):
			return true
	return false

static func allowed_external_url(url: String) -> bool:
	if url.length() > 4096 or url.contains("\n") or url.contains("\r") or url.contains("\\"):
		return false
	return allowed_pairing_url(url) or allowed_official_url(url)

static func allowed_pairing_url(url: String) -> bool:
	var prefix: String = active_origin() + "/admissions/account/native/"
	return url == prefix or (url.begins_with(prefix + "?") and not url.contains("#"))

static func allowed_official_url(url: String) -> bool:
	for hostname: String in OFFICIAL_PATHS:
		var origin: String = "https://" + hostname
		if not url.begins_with(origin + "/"):
			continue
		var path: String = url.substr(origin.length()).get_slice("?", 0).get_slice("#", 0)
		if path.contains("/../") or path.contains("/./") or path.to_lower().contains("%2e") or path.to_lower().contains("%2f"):
			return false
		for allowed: String in OFFICIAL_PATHS[hostname]:
			if path == allowed or (allowed.ends_with("/") and path.begins_with(allowed)):
				return true
	return false

func _ensure_loading_ui() -> void:
	if loading_layer != null:
		return
	terminal = TerminalFrame.new()
	add_child(terminal)
	loading_layer = terminal
	loading_label = terminal.get("message") as Label
	retry_button = terminal.get("retry") as Button
	terminal.connect("return_requested", close_host)
	terminal.connect("retry_requested", _retry)
	terminal.connect("bounds_changed", _place_webview)

func _place_webview(_rect: Rect2 = Rect2()) -> void:
	if not is_instance_valid(webview) or not webview.is_inside_tree():
		return
	var rect: Rect2 = terminal.get("screen_rect") as Rect2
	var physical: Rect2 = get_viewport().get_final_transform() * rect
	# WRY 1.0.2 uses get_screen_position but an unscaled Control.size as
	# physical child-window bounds. Compensate for canvas stretch and OS origin.
	webview.size = physical.size
	var screen_transform: Transform2D = webview.get_screen_transform()
	webview.position += screen_transform.basis_xform_inv(physical.position - screen_transform.origin)
	webview.call_deferred("resize")
	previous_window_rect = Rect2i(get_window().position, get_window().size)

func open_host(view: String, silently: bool = false) -> bool:
	if view not in VIEWS:
		return false
	current_view = view
	last_error = ""
	if not OS.has_feature("windows") or DisplayServer.get_name() == "headless":
		last_error = "此環境無法顯示星途帳號頁，請使用 Windows 遊戲版或網頁版。"
		return false
	_ensure_loading_ui()
	opened = not silently
	terminal.call("set_view", view)
	terminal.visible = opened
	if is_instance_valid(webview):
		if host_ready:
			_navigate()
			_place_webview()
			webview.call("set_visible", opened)
			if opened:
				webview.call("focus")
		else:
			loading_layer.visible = opened
		return true
	if not _has_runtime():
		last_error = "請安裝 Microsoft Edge WebView2 Runtime，\n重新啟動後即可使用星途帳號與落點分析。"
		_show_failure(last_error)
		return true
	if not ClassDB.class_exists("WebView"):
		GDExtensionManager.load_extension(EXTENSION)
	if not ClassDB.class_exists("WebView"):
		_show_failure("帳號視窗元件無法載入，請重新安裝完整遊戲。")
		return true
	# These methods/properties are exposed by the vendored Godot WRY v1.0.2.
	webview = ClassDB.instantiate("WebView") as Control
	webview.name = "StarPathAccountWebView"
	webview.set("full_window_size", false)
	webview.set("url", host_url(view))
	if active_origin() != ORIGIN and data_directory == "user://starpath_account/webview":
		data_directory = "user://starpath_account/dev_" + active_origin().sha256_text().left(12) + "/webview"
	webview.set("data_directory", data_directory)
	webview.set("forward_input_events", false)
	webview.set("focused_when_created", false)
	webview.set("devtools", false)
	webview.visible = false
	webview.connect("ipc_message", _on_message)
	webview.connect("page_load_started", _on_page_started)
	_start_loading()
	terminal.add_child(webview)
	_place_webview()
	return true

func resume_host() -> bool:
	return open_host("account", true)

func _has_runtime() -> bool:
	var fixed_runtime: String = OS.get_environment("WEBVIEW2_BROWSER_EXECUTABLE_FOLDER")
	if not fixed_runtime.is_empty() and FileAccess.file_exists(fixed_runtime.path_join("msedgewebview2.exe")):
		return true
	for variable: String in ["ProgramFiles(x86)", "ProgramFiles", "LOCALAPPDATA"]:
		var base: String = OS.get_environment(variable)
		if base.is_empty():
			continue
		var directory := DirAccess.open(base.path_join("Microsoft/EdgeWebView/Application"))
		if directory != null:
			for version: String in directory.get_directories():
				if FileAccess.file_exists(directory.get_current_dir().path_join(version).path_join("msedgewebview2.exe")):
					return true
	return false

func _start_loading() -> void:
	host_ready = false
	trusted_document = false
	deadline = Time.get_ticks_msec() + 30000
	loading_label.text = "正在載入落點分析與星途帳號…"
	(terminal.get("status") as Control).show()
	retry_button.hide()
	if opened:
		loading_layer.show()

func _retry() -> void:
	last_error = ""
	if is_instance_valid(webview):
		_start_loading()
		webview.call("load_url", host_url(current_view))
	else:
		open_host(current_view)

func _on_page_started(url: String) -> void:
	# Update trust synchronously; defer WRY mutation until its callback returns.
	trusted_document = allowed_host_url(url)
	host_ready = false
	if not trusted_document:
		_show_failure.call_deferred("帳號頁導向未允許的網址，已停止顯示。請重新載入。")

func _on_message(payload: String) -> void:
	if not trusted_document or payload.to_utf8_buffer().size() > InterestProtocol.MAX_BYTES:
		return
	_receive_message.call_deferred(payload)

func _receive_message(payload: String) -> void:
	if not trusted_document or not is_instance_valid(webview):
		return
	var data: Variant = JSON.parse_string(payload)
	if data is Dictionary and data.get("channel") == RecommendationProtocol.CHANNEL:
		var recommendation: Dictionary = RecommendationProtocol.sanitize_packet(data)
		if not recommendation.is_empty():
			recommendation_message.emit(recommendation)
		return
	if data is Dictionary and data.get("channel") == InterestProtocol.CHANNEL:
		var interest: Dictionary = InterestProtocol.sanitize_packet(data)
		if not interest.is_empty():
			interest_message.emit(interest)
		return
	if payload.to_utf8_buffer().size() > 4096:
		return
	var progress: Dictionary = ProgressProtocol.sanitize_packet(data)
	if not progress.is_empty():
		progress_message.emit(progress)
		return
	var packet: Dictionary = ForumProtocol.sanitize_packet(data)
	if not packet.is_empty():
		forum_message.emit(packet)
		return
	if not data is Dictionary or data.get("channel") != CHANNEL or data.get("version") != 1:
		return
	match str(data.get("type", "")):
		"ready":
			host_ready = true
			deadline = 0
			last_error = ""
			(terminal.get("status") as Control).hide()
			_place_webview()
			_navigate()
			if not pending_forum.is_empty():
				webview.call("eval", "window.StarPathHost?.openForum(" + JSON.stringify(pending_forum) + ");")
				pending_forum.clear()
			if pending_sign_out:
				pending_sign_out = false
				sign_out()
			webview.call("set_visible", opened)
			if opened:
				webview.call("focus")
		"auth-state":
			# Older hosted pages authenticate successfully but cannot complete the
			# mandatory identity gate. Surface this mismatch instead of waiting forever.
			if legacy_auth_packet(data):
				_show_failure("登入已成功，但帳號頁仍是舊版本，尚未支援身分設定。\n請按「重新連線」取得新版帳號頁，再選擇身分進入遊戲。")
				return
			var generation: Variant = data.get("sessionGeneration", (data.get("user") as Dictionary).get("sessionGeneration", -1) if data.get("user") is Dictionary else -1)
			if not valid_generation(generation) or int(generation) < session_generation:
				return
			var clean: Variant = sanitize_user(data.get("user"))
			if clean != null:
				if not (clean as Dictionary).is_empty() and int(clean.get("sessionGeneration", -1)) != int(generation):
					return
				session_generation = int(generation)
				state_changed.emit(clean as Dictionary)
				if data.get("resolving", false) != true:
					session_checked.emit(clean as Dictionary)
		"close": close_host()
		"open-external":
			var url: Variant = data.get("url")
			if opened and url is String and allowed_external_url(url):
				if OS.shell_open(url) != OK:
					_show_failure("無法開啟系統瀏覽器。請確認預設瀏覽器後重試。")

static func legacy_auth_packet(data: Dictionary) -> bool:
	var value: Variant = data.get("user")
	return value is Dictionary and value.get("signedIn") == true and not data.has("sessionGeneration") and not value.has("sessionGeneration") and not value.has("profileReady")

static func valid_generation(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0 and float(value) <= 9007199254740991 and floorf(float(value)) == float(value)

static func sanitize_user(value: Variant) -> Variant:
	if value == null:
		return {}
	if not value is Dictionary or not value.get("signedIn") is bool or value.get("signedIn") != true:
		return null
	if not value.get("displayName", "") is String:
		return null
	var clean: Dictionary = {"signedIn":true, "displayName":str(value.get("displayName", "")).left(80)}
	if value.has("profileReady"):
		if not value.profileReady is bool or not value.get("identity", "") is String or not valid_generation(value.get("sessionGeneration")):
			return null
		clean["profileReady"] = value.profileReady
		clean["identity"] = str(value.identity).left(40)
		clean["sessionGeneration"] = int(value.sessionGeneration)
		if clean.sessionGeneration < 0 or (clean.profileReady and clean.identity not in ForumProtocol.IDENTITIES):
			return null
	return clean

func request_forum_page(command: Dictionary) -> bool:
	if not host_ready or not trusted_document or not is_instance_valid(webview):
		return false
	webview.call("eval", "window.StarPathHost?.forumPage(" + JSON.stringify(command) + ");")
	return true

func request_progress(command: Dictionary) -> bool:
	if not host_ready or not trusted_document or not is_instance_valid(webview):
		return false
	webview.call("eval", "window.StarPathHost?.progressCommand(" + JSON.stringify(command) + ");")
	return true

func request_interest(command: Dictionary) -> bool:
	if not host_ready or not trusted_document or not is_instance_valid(webview):
		return false
	var clean: Dictionary = InterestProtocol.sanitize_command(command,session_generation)
	if clean.is_empty():
		return false
	webview.call("eval", "window.StarPathHost?.interestCommand(" + JSON.stringify(clean) + ");")
	return true

func request_recommendation(command: Dictionary) -> bool:
	if not host_ready or not trusted_document or not is_instance_valid(webview):
		return false
	var clean: Dictionary = RecommendationProtocol.sanitize_command(command,session_generation)
	if clean.is_empty():
		return false
	webview.call("eval", "window.StarPathHost?.recommendationCommand(" + JSON.stringify(clean) + ");")
	return true

func open_forum(context: Dictionary) -> bool:
	pending_forum = context.duplicate(true)
	if not open_host("forum"):
		pending_forum.clear()
		return false
	if host_ready:
		webview.call("eval", "window.StarPathHost?.openForum(" + JSON.stringify(pending_forum) + ");")
		pending_forum.clear()
	return true

func _navigate() -> void:
	if host_ready and is_instance_valid(webview):
		webview.call("eval", "window.StarPathHost?.navigate(" + JSON.stringify(current_view) + ");")

func sign_out() -> void:
	if host_ready and is_instance_valid(webview):
		webview.call("eval", "window.StarPathHost?.signOut();")
	else:
		pending_sign_out = true

func _suspend_pairing() -> void:
	if host_ready and trusted_document and is_instance_valid(webview):
		webview.call("eval", "window.StarPathHost?.suspend();")

func _show_failure(message: String) -> void:
	_suspend_pairing()
	last_error = message
	host_ready = false
	trusted_document = false
	deadline = 0
	if is_instance_valid(webview):
		webview.call("set_visible", false)
		if opened:
			webview.call("focus_parent")
	loading_label.text = message
	(terminal.get("status") as Control).show()
	retry_button.show()
	if opened:
		loading_layer.show()
	failed.emit(message)

func _process(_delta: float) -> void:
	if opened and is_instance_valid(webview) and previous_window_rect != Rect2i(get_window().position, get_window().size):
		terminal.call("relayout")
	if deadline > 0 and Time.get_ticks_msec() > deadline and not host_ready:
		_show_failure("星途帳號載入逾時。\n請確認網路後重試，或返回世界。")

func _input(event: InputEvent) -> void:
	if opened and not host_ready and event.is_action_pressed("ui_cancel"):
		close_host()
		get_viewport().set_input_as_handled()

func close_host() -> void:
	if not opened:
		return
	_suspend_pairing()
	opened = false
	if loading_layer != null:
		loading_layer.hide()
	if is_instance_valid(webview):
		webview.call("set_visible", false)
		webview.call("focus_parent")
	closed.emit()
