extends SceneTree
## Real browser-created emulator account, native WRY IPC, then browser verification.
const Native = preload("res://scripts/account_native_host.gd")
const Startup = preload("res://tests/startup_fixture.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var responses: Dictionary = {}
var serial: int = 0
var account: Node
var native: Node
var view: Control

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	print("INTEREST_ACCOUNT_CHECK ",label," ",passed)
	if not passed:
		failures += 1

func wait_until(condition: Callable, timeout_ms: int = 25000) -> bool:
	var deadline: int = Time.get_ticks_msec()+timeout_ms
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return condition.call()

func command(data: Dictionary) -> Dictionary:
	serial += 1
	var id: String = "native_interest_qa_%d_%d" % [Time.get_ticks_msec(),serial]
	data["requestId"] = id
	if not account.call("request_interest",data):
		return {"type":"error","code":"not-accepted"}
	if not await wait_until(func() -> bool: return responses.has(id)):
		return {"type":"error","code":"timeout"}
	return responses[id]

func run() -> void:
	root.size = Vector2i(1280,800)
	root.title = "Star Path Interest Cross Target QA"
	if Native.active_origin()==Native.ORIGIN or DisplayServer.get_name()=="headless":
		push_error("Requires visible Windows debug engine and explicit local emulator host")
		quit(2)
		return
	var session: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://../build/counseling-qa-session.json"))
	if not session is Dictionary or not str(session.get("email","")).begins_with("interest-") or not str(session.get("email","")).ends_with("@example.invalid"):
		push_error("Run tools/check_interest_account_browser.cjs prepare first")
		quit(2)
		return
	change_scene_to_file("res://scenes/login_entry.tscn")
	await process_frame
	await process_frame
	account = root.get_node("StarPathAccount")
	var gate: Node = root.get_node("AccountGate")
	native = account.get("native_host")
	account.connect("interest_message",func(packet: Dictionary) -> void: responses[str(packet.get("requestId",""))] = packet)
	check("Native local host becomes ready",await wait_until(func() -> bool: return is_instance_valid(native) and bool(native.get("host_ready")),35000))
	if not native.get("host_ready"):
		finish()
		return
	view = native.get("webview")
	# Synthetic local credentials are entered through the existing account UI.
	view.call("eval","""
(async () => {
  if (!['127.0.0.1','localhost'].includes(location.hostname)) return;
  const runtime = await window.__starPathFirebase;
  if (!runtime?.auth?.emulatorConfig) return;
  await window.StarPathHost.signOut();
  window.StarPathHost.navigate('account');
  const deadline = Date.now()+18000;
  const start = () => {
    const frame = document.querySelector('iframe.host-content');
    const doc = frame?.contentDocument;
    if (!doc?.querySelector('input[type="email"]')) { if(Date.now()<deadline)setTimeout(start,100); return; }
    const win = frame.contentWindow;
    const set = (selector,value) => {
      const input = doc.querySelector(selector);
      Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype,'value').set.call(input,value);
      input.dispatchEvent(new win.Event('input',{bubbles:true}));
      input.dispatchEvent(new win.Event('change',{bubbles:true}));
    };
    set('input[type="email"]',%s);
    set('input[type="password"]','Only-Local-Interest-QA-2026!');
    setTimeout(()=>doc.querySelector('.account-form button[type="submit"]')?.click(),150);
  };
  start();
})();
""" % JSON.stringify(session.email))
	var admitted: bool = await wait_until(func() -> bool: return not paused and not gate.get("locked") and current_scene!=null and current_scene.has_method("teleport_to"),35000)
	check("Browser account logs into native Godot through real account UI",admitted)
	if not admitted:
		finish()
		return
	account.call("close_view")
	var first: Dictionary = await command({"action":"get","recordId":session.recordId})
	check("Native reads browser draft through hidden host",first.get("type")=="state" and first.get("revision")==1 and first.get("hasDraft")==true)
	if not first.get("profile") is Dictionary:
		finish()
		return
	var profile: Dictionary = first.profile.duplicate(true)
	check("Cross-target profile preserves blank and both 26-row sets",profile.riasec.R=="" and profile.bestFits.size()==26 and profile.suitableFits.size()==26)
	profile.riasec.R = "90"
	var completed: Dictionary = await command({"action":"complete","recordId":session.recordId,"expectedRevision":1,"profile":profile})
	check("Native completes all 39 scores",completed.get("type")=="state" and completed.get("revision")==2 and completed.get("hasCompleted")==true and completed.get("hasDraft")==false)
	check("First completed record is automatically selected",completed.get("activeRecordId")==session.recordId and completed.get("selectionRevision")==1)
	profile.title = "第二次量表測試"
	var second: Dictionary = await command({"action":"complete","recordId":session.secondId,"expectedRevision":0,"profile":profile})
	check("Additional completed record preserves original selection",second.get("type")=="state" and second.get("activeRecordId")==session.recordId)
	var selected: Dictionary = await command({"action":"setActive","recordId":session.secondId,"expectedSelectionRevision":1})
	check("Native explicitly selects another completed record",selected.get("type")=="active" and selected.get("activeRecordId")==session.secondId and selected.get("selectionRevision")==2)
	profile.title = "跨裝置量表測試"
	profile.riasec.R = ""
	var draft: Dictionary = await command({"action":"saveDraft","recordId":session.recordId,"expectedRevision":2,"profile":profile})
	check("Editing a completed record preserves its valid completed snapshot",draft.get("type")=="state" and draft.get("revision")==3 and draft.get("hasDraft")==true and draft.get("hasCompleted")==true)
	var stale: Dictionary = await command({"action":"saveDraft","recordId":session.recordId,"expectedRevision":0,"profile":profile})
	check("Stale native write is rejected without overwrite",stale.get("type")=="error" and stale.get("code")=="cloud-revision-conflict")
	await exercise_settings(session.recordId)
	await exercise_room(session.secondId)
	check("Interest data operations leave the account website hidden",not bool(account.get("opened")))
	view.call("eval","window.StarPathHost.signOut()")
	check("Signout clears user and locks game",await wait_until(func() -> bool: return paused and gate.get("locked") and (account.get("user") as Dictionary).is_empty(),15000))
	finish()

func exercise_settings(record_id: String) -> void:
	var world: Node = current_scene
	world.call("teleport_to","counseling")
	check("World finishes first-station preparation",await Startup.wait_roaming(world,self))
	var hud: Node = world.get("hud")
	var actor: Node = world.get("player")
	hud.call("open_graphics_settings")
	(hud.get("interest_settings_button") as Button).pressed.emit()
	var panel: Control = hud.get("interest_panel")
	check("Game settings opens the native editable interest panel",is_instance_valid(panel) and panel.visible and not actor.get("controls_enabled"))
	if not is_instance_valid(panel):
		return
	var controller: Node = panel.get("controller")
	await wait_until(func() -> bool: return not controller.call("busy"))
	controller.call("open_record",record_id)
	check("Settings retrieves the same account draft",await wait_until(func() -> bool: return not controller.call("busy") and controller.get("record_id")==record_id and controller.get("revision")==3))
	for frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/counseling-room/account"))
	root.get_texture().get_image().save_png("res://../deliverables/counseling-room/account/native-settings-account.png")
	panel.call("request_close")
	check("Closing form returns to settings with controls still paused",not panel.visible and hud.call("is_settings_open") and not actor.get("controls_enabled"))
	hud.call("close_graphics_settings")
	check("Closing game settings restores character controls",not hud.call("is_settings_open") and actor.get("controls_enabled"))

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/counseling-room/account"))
	var report := FileAccess.open("res://../deliverables/counseling-room/account/native-cross-target.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"hostOrigin":Native.active_origin(),"scope":"Actual Windows Godot, native hidden WRY host, browser-created account and real local Auth/Firestore emulators"},"\t"))
	report.close()
	print("INTEREST_ACCOUNT_RESULT failures=",failures)
	quit(0 if failures==0 else 1)

func exercise_room(selected_id: String) -> void:
	var world: Node3D = current_scene as Node3D
	var entry: Vector3 = (world.get("player") as Node3D).global_position
	world.call("open_station","counseling")
	check("First station enters its independent counseling room",await wait_until(func() -> bool: return current_scene!=null and current_scene!=world and current_scene.get_script().resource_path=="res://scripts/counseling_room.gd",15000))
	if current_scene==null or current_scene==world:
		return
	var room: Node3D = current_scene as Node3D
	check("Deferred high-detail room becomes playable",await Startup.wait_room(room,self))
	var actor: CharacterBody3D = room.get("player")
	var layout: Dictionary = room.get("layout")
	for stage: String in ["high1", "high3"]:
		var station: Dictionary = {}
		for item: Dictionary in layout.stations:
			if item.view == "interest_" + stage:
				station = item
		check("Room has the %s data device" % stage, not station.is_empty())
		if station.is_empty():
			continue
		var point: Array = station.approach
		actor.call("place_at",Vector3(float(point[0]),float(point[1]),float(point[2])),Vector3.FORWARD)
		for frame: int in range(4):
			await physics_frame
		room.call("refresh_nearest")
		room.call("activate_nearest")
		var panel: Control = room.get("interest_panel")
		check("%s device opens the Godot form and freezes movement" % stage,is_instance_valid(panel) and panel.visible and actor.process_mode==Node.PROCESS_MODE_DISABLED)
		if is_instance_valid(panel):
			var expected_tab: int = 0 if stage == "high1" else 1
			check("%s device opens its matching grade area" % stage, (panel.get("tabs") as TabContainer).current_tab == expected_tab)
			var controller: Node = panel.get("controller")
			check("%s device opens the shared account recommendation record" % stage,await wait_until(func() -> bool: return controller.get("record_id")==selected_id and controller.get("revision")==1 and not controller.call("busy")))
			panel.call("request_close")
			check("Closing %s form restores movement" % stage,not is_instance_valid(room.get("interest_panel")) and actor.get("controls_enabled"))
	room.call("_return_immediately")
	check("Room exit returns to the original world instance",await wait_until(func() -> bool: return current_scene==world,8000))
	check("Room exit restores first-station arrival position",(world.get("player") as Node3D).global_position.distance_to(entry)<.04)
