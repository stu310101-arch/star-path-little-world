extends SceneTree
## Actual Windows WRY host + local Auth/Firestore emulator. Never targets production.
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
	print("RECOMMENDATION_ACCOUNT_CHECK ",label," passed=",passed)
	if not passed: failures+=1

func wait_until(condition: Callable, timeout_ms: int = 25000) -> bool:
	var deadline: int=Time.get_ticks_msec()+timeout_ms
	while not condition.call() and Time.get_ticks_msec()<deadline: await process_frame
	return condition.call()

func command(data: Dictionary) -> Dictionary:
	serial+=1
	var id: String="native_recommendation_%d_%d"%[Time.get_ticks_msec(),serial]
	data.requestId=id
	if not account.call("request_recommendation",data): return {"type":"error","code":"not-accepted"}
	if not await wait_until(func() -> bool: return responses.has(id)): return {"type":"error","code":"timeout"}
	return responses[id]

func run() -> void:
	root.size=Vector2i(1280,900)
	root.title="Star Path Recommendation Local QA"
	if Native.active_origin()==Native.ORIGIN or DisplayServer.get_name()=="headless":
		push_error("Requires native renderer and explicit local emulator host")
		quit(2)
		return
	var saved: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://../build/recommendation-qa-session.json"))
	if not saved is Dictionary or not str(saved.get("email","")).begins_with("recommendation-") or not str(saved.get("email","")).ends_with("@example.invalid"):
		push_error("Prepare a synthetic local recommendation account first")
		quit(2)
		return
	change_scene_to_file("res://scenes/login_entry.tscn")
	await process_frame
	await process_frame
	account=root.get_node("StarPathAccount")
	var gate: Node=root.get_node("AccountGate")
	native=account.get("native_host")
	account.connect("recommendation_message",func(packet: Dictionary) -> void: responses[str(packet.get("requestId",""))]=packet)
	check("Local native account host becomes ready",await wait_until(func() -> bool: return is_instance_valid(native) and bool(native.get("host_ready")),35000))
	if not bool(native.get("host_ready")):
		finish()
		return
	view=native.get("webview")
	view.connect("ipc_message",func(payload: String) -> void:
		var packet: Variant=JSON.parse_string(payload)
		if packet is Dictionary and packet.get("channel")=="starpath-recommendations":
			var accepted: Dictionary=preload("res://scripts/recommendation_protocol.gd").sanitize_packet(packet)
			print("RECOMMENDATION_WIRE type=",packet.get("type")," bytes=",payload.to_utf8_buffer().size()," accepted=",not accepted.is_empty())
			if accepted.is_empty():
				var protocol=preload("res://scripts/recommendation_protocol.gd")
				print("RECOMMENDATION_WIRE safe=",protocol._safe(packet)," keys=",packet.keys())
				for item: Variant in packet.get("items",[]):
					if not protocol.item(item): print("RECOMMENDATION_WIRE rejected_item_keys=",item.keys())
	)
	view.call("eval","""
(async()=>{
 if(!['127.0.0.1','localhost'].includes(location.hostname))return;
 const runtime=await window.__starPathFirebase;if(!runtime?.auth?.emulatorConfig)return;
 await window.StarPathHost.signOut();window.StarPathHost.navigate('account');
 const deadline=Date.now()+18000;
 const start=()=>{
  const frame=document.querySelector('iframe.host-content'),doc=frame?.contentDocument;
  if(!doc?.querySelector('input[type="email"]')){if(Date.now()<deadline)setTimeout(start,100);return;}
  const win=frame.contentWindow;
  const set=(selector,value)=>{const input=doc.querySelector(selector);Object.getOwnPropertyDescriptor(win.HTMLInputElement.prototype,'value').set.call(input,value);input.dispatchEvent(new win.Event('input',{bubbles:true}));input.dispatchEvent(new win.Event('change',{bubbles:true}));};
  set('input[type="email"]',%s);set('input[type="password"]','Only-Local-Recommendation-QA-2026!');
  setTimeout(()=>doc.querySelector('.account-form button[type="submit"]')?.click(),150);
 };start();
})();
"""%JSON.stringify(saved.email))
	var admitted: bool=await wait_until(func() -> bool: return not paused and not bool(gate.get("locked")) and current_scene!=null and current_scene.has_method("teleport_to"),35000)
	check("Synthetic browser account logs into native through existing account UI",admitted)
	if not admitted:
		finish()
		return
	account.call("close_view")
	var bootstrap: Dictionary=await command({"action":"bootstrap"})
	check("Native receives completed recommendation snapshot",bootstrap.get("type")=="bootstrap" and bootstrap.get("activeReport") is Dictionary)
	if bootstrap.get("type")!="bootstrap":
		print("RECOMMENDATION_ACCOUNT_FAILURE bootstrap=",bootstrap.get("code","unknown"))
		finish()
		return
	check("Newer draft cannot replace completed report",str(bootstrap.activeReport.title)=="推薦完成報告")
	var exams: Dictionary=await command({"action":"listExams","cursor":null})
	check("Browser saved exam is available through native IPC",exams.get("type")=="exams" and (exams.get("items",[]) as Array).any(func(item: Dictionary) -> bool: return item.id==saved.examId))
	var settings: Dictionary=bootstrap.settings.duplicate(true)
	settings.source="activeReport"
	settings.examId=str(saved.examId)
	settings.mode="academic"
	if "--visible-query-probe" in OS.get_cmdline_user_args():
		account.call("open_view","account")
	var query_started: int=Time.get_ticks_msec()
	var ranked: Dictionary=await command({"action":"query","settings":settings})
	print("RECOMMENDATION_QUERY elapsed_ms=",Time.get_ticks_msec()-query_started)
	if "--visible-query-probe" in OS.get_cmdline_user_args():
		check("Visible query probe returns",ranked.get("type")=="results")
		finish()
		return
	check("Selected saved exam produces native recommendations",ranked.get("type")=="results" and not (ranked.get("items",[]) as Array).is_empty())
	if ranked.get("type")!="results":
		print("RECOMMENDATION_ACCOUNT_FAILURE query_code=",ranked.get("code","unknown"))
		finish()
		return
	var detail: Dictionary=await command({"action":"detail","queryId":ranked.queryId,"programRef":saved.programRef})
	check("Browser favorite has real native detail and historical comparisons",detail.get("type")=="detail" and detail.item.favorite and detail.details.history.size()==3)
	var second: Dictionary=await command({"action":"detail","queryId":ranked.queryId,"programRef":saved.secondRef})
	check("Second candidate detail can be inspected outside current page",second.get("type")=="detail")
	if second.get("type")=="detail":
		var favorite: Dictionary=await command({"action":"setFavorite","programRef":saved.secondRef,"value":true,"expectedRevision":int(second.item.favoriteRevision)})
		check("Native confirms new favorite for browser cross target verification",favorite.get("type")=="favorite" and favorite.value)
	var write: Dictionary=await command({"action":"saveSettings","settings":settings,"expectedRevision":int(bootstrap.settingsRevision)})
	check("Native saves academic mode with revision",write.get("type")=="settings" and write.settings.mode=="academic")
	await exercise_room()
	check("Data operations keep account website hidden",not bool(account.get("opened")))
	view.call("eval","window.StarPathHost.signOut()")
	check("Native signout clears recommendations and locks game",await wait_until(func() -> bool: return paused and bool(gate.get("locked")) and (account.get("user") as Dictionary).is_empty(),15000))
	finish()

func exercise_room() -> void:
	var world: Node3D=current_scene as Node3D
	world.call("teleport_to","recommendations")
	check("Third station prepares for walking",await Startup.wait_roaming(world,self))
	var entry: Vector3=(world.get("player") as Node3D).global_position
	world.call("open_station","recommendations")
	check("Third station enters authored recommendation room",await wait_until(func() -> bool: return current_scene!=null and current_scene!=world and current_scene.get_script().resource_path=="res://scripts/recommendation_room.gd",20000))
	if current_scene==null or current_scene==world: return
	var room: Node3D=current_scene as Node3D
	check("Room assets and avatar become playable",await Startup.wait_room(room,self))
	room.call("open_recommendation_panel","recommendations")
	var panel: Control=room.get("recommendation_panel")
	check("Real room opens native recommendation UI",is_instance_valid(panel) and panel.visible)
	if not is_instance_valid(panel): return
	var controller: Node=panel.get("controller")
	check("Panel queries real hidden account host",await wait_until(func() -> bool: return not (panel.get("result_packet") as Dictionary).is_empty() and not bool(controller.call("busy")),30000))
	check("Panel reads native-saved academic preference",panel.get("settings").mode=="academic")
	check("Open recommendation form freezes character",not bool((room.get("player") as Node).get("controls_enabled")))
	panel.call("_change_result_page",1)
	check("Native next page replaces the twenty visible results",await wait_until(func() -> bool: return int(panel.get("result_page"))==1 and (panel.get("rows") as Array).size()==20 and not bool(controller.call("busy")),25000))
	await capture("native-recommendation-desktop.png")
	var rows: Array=panel.get("rows")
	for index: int in range(mini(3,rows.size())): panel.call("_toggle_compare",str(rows[index].programRef))
	check("Three comparisons load through real detail requests",await wait_until(func() -> bool: return (panel.get("comparison") as Array).size()==3 and (panel.get("details") as Dictionary).size()>=3 and not bool(controller.call("busy")),25000))
	panel.call("_select_tab",2)
	await capture("native-recommendation-compare.png")
	root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	root.size=Vector2i(390,844)
	await wait_until(func() -> bool: return root.size.x==390,3000)
	panel.call("_resize_canvas")
	await capture("native-recommendation-narrow-compare.png")
	check("Narrow native viewport displays one comparison card",bool(panel.get("_small")))
	panel.call("_select_tab",1)
	await capture("native-recommendation-narrow-results.png")
	root.size=Vector2i(1280,900)
	panel.call("_resize_canvas")
	panel.call("_select_tab",2)
	for frame: int in range(3): await process_frame
	(panel.get("scrolls")[1] as ScrollContainer).scroll_vertical=120
	var kept: Dictionary=panel.call("get_return_state")
	var university_id: String=str(rows[0].universityId) if not rows.is_empty() else ""
	if university_id.is_empty():
		check("Recommended school has gallery mapping",false)
		return
	panel.emit_signal("visit_university",university_id,kept)
	check("Recommendation navigation opens university gallery",await wait_until(func() -> bool: return current_scene!=null and current_scene.get_script().resource_path=="res://scripts/university_hall.gd",20000))
	if current_scene==null or current_scene.get_script().resource_path!="res://scripts/university_hall.gd": return
	var hall: Node3D=current_scene as Node3D
	check("University gallery becomes playable",await Startup.wait_room(hall,self))
	await capture("native-recommendation-gallery.png")
	hall.call("return_to_world")
	check("Gallery returns to recommendation room",await wait_until(func() -> bool: return current_scene!=null and current_scene.get_script().resource_path=="res://scripts/recommendation_room.gd",20000))
	if current_scene==null or current_scene.get_script().resource_path!="res://scripts/recommendation_room.gd": return
	room=current_scene as Node3D
	check("Returned recommendation room prepares normally",await Startup.wait_room(room,self))
	check("Return restores visible comparison panel",await wait_until(func() -> bool: return is_instance_valid(room.get("recommendation_panel")) and bool((room.get("recommendation_panel") as Control).visible),15000))
	panel=room.get("recommendation_panel")
	if is_instance_valid(panel):
		controller=panel.get("controller")
		await wait_until(func() -> bool: return not bool(controller.call("busy")),25000)
		check("Return retains comparison list mode and tab",panel.get("comparison")==kept.comparison and panel.get("settings").mode=="academic" and panel.get("page_index")==2)
		await capture("native-recommendation-return.png")
		check("Return retains the current result page and list position",int(panel.get("result_page"))==int(kept.resultPage) and (panel.get("rows") as Array).size()==20 and (panel.get("scrolls")[1] as ScrollContainer).scroll_vertical==int(kept.scroll))
		panel.call("close_panel")
	room.call("_return_immediately")
	check("Leaving recommendation room restores original world instance",await wait_until(func() -> bool: return current_scene==world,10000))
	if current_scene==world: check("World entry location is preserved",(world.get("player") as Node3D).global_position.distance_to(entry)<.05)

func capture(name: String) -> void:
	for frame: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/recommendations/account"))
	root.get_texture().get_image().save_png("res://../deliverables/recommendations/account/"+name)

func finish() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/recommendations/account"))
	var report_name: String="native-visible-timer-probe.json" if "--visible-query-probe" in OS.get_cmdline_user_args() else "native-cross-target.json"
	var report:=FileAccess.open("res://../deliverables/recommendations/account/"+report_name,FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"hostOrigin":Native.active_origin(),"scope":"Windows native Godot + WRY IPC with synthetic local Auth/Firestore account. Narrow window is not a physical phone."},"\t"))
	report.close()
	print("RECOMMENDATION_ACCOUNT_RESULT failures=",failures)
	quit(0 if failures==0 else 1)
