extends SceneTree

const Host: Script = preload("res://scripts/native_computer_game.gd")
const OUTPUT: String = "res://../deliverables/training-room/native-go-checks.json"
var host: Node
var view: Control
var results: Array[Dictionary] = []
var failures: int = 0
var responses: Dictionary = {}
var request_id: int = 0
var profile: String

func _initialize() -> void:
	call_deferred("run")

func check(label_text: String, passed: bool, evidence: Variant = null) -> void:
	results.append({"test": label_text, "passed": passed, "evidence": evidence})
	print("PASS " if passed else "FAIL ", label_text, " ", evidence if evidence != null else "")
	if not passed:
		failures += 1

func connect_view() -> void:
	view = host.get("webview") as Control
	view.connect("ipc_message", func(payload: String) -> void:
		var data: Variant = JSON.parse_string(payload)
		if data is Dictionary and str(data.get("type", "")) == "qa":
			responses[int(data.id)] = data.get("result")
	)

func js(code: String) -> Variant:
	request_id += 1
	var id: int = request_id
	var script: String = "(() => { const w = document.getElementById('game').contentWindow; const d = w.document; let result; try { result = (() => { %s })(); } catch(e) { result = {error: String(e)}; } window.ipc.postMessage(JSON.stringify({type:'qa', id:%d, result})); })()" % [code, id]
	view.call("eval", script)
	var deadline: int = Time.get_ticks_msec() + 5000
	while not responses.has(id) and Time.get_ticks_msec() < deadline:
		await process_frame
	if not responses.has(id):
		check("JavaScript response timeout", false, code)
		return null
	var result: Variant = responses[id]
	responses.erase(id)
	return result

func wait_ready() -> bool:
	var deadline: int = Time.get_ticks_msec() + 30000
	while not bool(host.get("game_ready")) and Time.get_ticks_msec() < deadline:
		await process_frame
	return bool(host.get("game_ready"))

func run() -> void:
	root.title = "Little World - Native Go Integration Checks"
	profile = "user://qa/go-" + str(Time.get_unix_time_from_system()).replace(".", "-")
	host = Host.new()
	host.set("data_directory", profile)
	root.add_child(host)
	var launched: bool = bool(host.call("open_game"))
	check("Windows native child WebView opens", launched, host.get("last_error"))
	if not launched:
		finish()
		return
	connect_view()
	check("Packaged HTML and embedded app become ready", await wait_ready())
	if not bool(host.get("game_ready")):
		finish()
		return
	check("Initial screen asks for configuration", await js("return !d.getElementById('setup-view').hidden && d.getElementById('game-view').hidden;") == true)
	check("Go is served locally inside WebView", await js("return w.location.hostname.startsWith('res.') && !!w.Worker;") == true)
	await js("d.querySelector('[name=difficulty][value=easy]').click(); d.getElementById('new-submit').click(); return true;")
	check("Configuration starts 9x9 board", await js("return d.querySelectorAll('.point').length === 81 && !d.getElementById('game-view').hidden;") == true)
	check("Board accepts a player click", await js("d.querySelectorAll('.point')[40].click(); return JSON.parse(w.localStorage.getItem('songfeng-go-v1')).game.history.length >= 1;") == true)
	var saved: Variant = null
	var deadline: int = Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < deadline:
		saved = await js("return JSON.parse(w.localStorage.getItem('songfeng-go-v1'));")
		if saved is Dictionary and (saved.game.history as Array).size() >= 2:
			break
		await create_timer(.2).timeout
	check("Player stone and AI worker reply are saved", saved is Dictionary and (saved.game.history as Array).size() == 2, saved.game.history.size() if saved is Dictionary else saved)
	check("Wood-coloured supplied board is in use", await js("return w.getComputedStyle(d.querySelector('.board-frame')).backgroundColor === 'rgb(223, 183, 128)';") == true)
	var identity: int = view.get_instance_id()
	host.call("close_game")
	check("Return hides view and clears its open state", not bool(host.get("opened")))
	host.call("open_game")
	check("Reopening keeps same live WebView and match", view.get_instance_id() == identity and await js("return JSON.parse(w.localStorage.getItem('songfeng-go-v1')).game.history.length;") == 2.0)
	root.size = Vector2i(960, 640)
	await create_timer(.5).timeout
	check("Native view fits resized game window", await js("return [window.innerWidth,window.innerHeight];") == [960.0,640.0])
	await js("document.getElementById('back').click(); return true;")
	await process_frame
	await process_frame
	check("HTML return button reaches Godot", not bool(host.get("opened")))
	host.call("open_game")
	await js("d.dispatchEvent(new w.KeyboardEvent('keydown',{key:'Escape',bubbles:true})); d.dispatchEvent(new w.KeyboardEvent('keyup',{key:'Escape',bubbles:true})); return true;")
	await process_frame
	await process_frame
	check("Escape inside Go returns through native IPC", not bool(host.get("opened")))
	host.call("destroy")
	await process_frame
	await create_timer(.5).timeout
	check("Leaving room releases native WebView", not is_instance_valid(view))
	host.call("open_game")
	connect_view()
	check("Second visit loads the local match", await wait_ready() and await js("return !d.getElementById('continue-card').hidden;") == true)
	await js("d.getElementById('continue-btn').click(); return true;")
	check("Saved match survives WebView destruction", await js("return JSON.parse(w.localStorage.getItem('songfeng-go-v1')).game.history.length;") == 2.0)
	finish()

func finish() -> void:
	if is_instance_valid(host):
		host.call("destroy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file: FileAccess = FileAccess.open(OUTPUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"failures": failures, "checks": results, "profile": profile, "platform": OS.get_name(), "renderer": DisplayServer.get_name()}, "  "))
	file.close()
	await process_frame
	quit(1 if failures else 0)
