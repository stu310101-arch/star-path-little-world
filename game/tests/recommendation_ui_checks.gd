extends SceneTree
const RecommendationPanel = preload("res://scripts/recommendation_panel.gd")
const Protocol = preload("res://scripts/recommendation_protocol.gd")
const Controller = preload("res://scripts/recommendation_controller.gd")
const Session = preload("res://scripts/account_session.gd")
const Native = preload("res://scripts/account_native_host.gd")
var failures: int = 0
var checks: int = 0
var check_records: Array[Dictionary] = []
var captured: Array[Dictionary] = []

class Service:
	extends Node
	signal state_changed(user: Dictionary)
	signal recommendation_message(packet: Dictionary)
	signal progress_message(packet: Dictionary)
	signal interest_message(packet: Dictionary)
	signal closed
	var user: Dictionary = {"signedIn":true,"profileReady":true,"sessionGeneration":7,"identity":"high_school"}
	var commands: Array[Dictionary] = []
	var accepted: bool = true
	func request_recommendation(command: Dictionary) -> bool:
		commands.append(command.duplicate(true))
		return accepted
	func request_progress(_command: Dictionary) -> bool: return true
	func request_interest(_command: Dictionary) -> bool: return true
	func open_view(_view: String) -> bool: return true
	func latest(action: String) -> Dictionary:
		for index: int in range(commands.size()-1,-1,-1):
			if commands[index].action==action: return commands[index]
		return {}
	func reply(action: String, payload: Dictionary, request_id: String = "") -> void:
		var command: Dictionary = latest(action)
		var packet: Dictionary = {"channel":Protocol.CHANNEL,"version":1,"sessionGeneration":user.sessionGeneration,"requestId":str(command.requestId) if request_id.is_empty() else request_id,"type":Protocol.expected_type(action)}
		packet.merge(payload,true)
		recommendation_message.emit(packet)

class FakeWebView:
	extends Control
	var scripts: Array[String] = []
	func eval(source: String) -> void: scripts.append(source)

func check(label: String, passed: bool) -> void:
	checks+=1
	check_records.append({"test":label,"passed":passed})
	print("RECOMMENDATION_UI_CHECK ",label," passed=",passed)
	if not passed: failures+=1

func _initialize() -> void:
	run.call_deferred()

func item(code: String = "011001") -> Dictionary:
	return {"programRef":"115:"+code,"year":"115","programCode":code,"schoolId":"011","schoolName":"國立清華大學","programName":"資訊工程學系","universityId":"010","groupIds":["information"],"categories":["資訊工程"],"matchLevel":2,"matchKind":"exact","status":"passed","statusLabel":"歷史一階門檻達標","priorityTier":1,"reasons":["報告最適合：資訊工程"],"missing":[],"gapSummary":"","favorite":false,"favoriteRevision":0}

func results(query_id: String = "query_a") -> Dictionary:
	var rows: Array = []
	for index: int in range(1,5): rows.append(item("01100"+str(index)))
	return {"queryId":query_id,"items":rows,"nextCursor":null,"total":4,"counts":{"passed":4,"failed":0,"pending":0,"explore":0,"extension":0},"inputs":{"settings":Controller.default_settings(),"report":{"recordId":"report_one","revision":2,"selectionRevision":1,"title":"秋季探索"},"exam":null,"algorithmVersion":"v1","dataVersion":"test"},"warnings":[]}

func details(reference: String) -> Dictionary:
	return {"queryId":"query_a","item":item(reference.substr(4)),"details":{"matchReasons":["報告最適合：資訊工程"],"academicStatus":"歷史一階門檻達標","missing":[],"rules":[{"label":"數學A篩選","actual":12,"required":11,"passed":true}],"boostPlans":[],"sources":[{"label":"官方資料","url":"https://www.cac.edu.tw/apply115/"}],"history":[{"year":"113","programRef":null,"status":"unmapped","label":"未對應"},{"year":"114","programRef":"114:011001","status":"passed","label":"歷史一階門檻達標"},{"year":"115","programRef":reference,"status":"passed","label":"歷史一階門檻達標"}],"reportSummary":null,"fitEvidence":[{"groupId":"information","category":"資訊工程","level":2,"z":"1.2"}],"mappingNote":"本校學類對應"}}

func paged_results(index: int, query_id: String = "query_a") -> Dictionary:
	var packet: Dictionary=results(query_id)
	packet.items=[]
	for number: int in range(index*20+1,mini(index*20+21,46)): packet.items.append(item("%06d"%(11000+number)))
	packet.total=45
	packet.counts.passed=45
	packet.nextCursor="page_%d"%(index+1) if index<2 else null
	return packet

func tick() -> void:
	await process_frame
	await process_frame

func run() -> void:
	var wire_path: String=ProjectSettings.globalize_path("res://../admissions-site/tests/fixtures/recommendation-wire.json")
	if FileAccess.file_exists(wire_path):
		var wire: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(wire_path))
		for packet: Dictionary in wire.packets:
			check("TypeScript service wire: "+str(packet.type),not Protocol.sanitize_packet(packet).is_empty())
	else:
		check("TypeScript service wire fixture exists",false)
	var settings: Dictionary=Controller.default_settings()
	settings.manual=[{"groupId":"information","category":"資訊工程","level":2}]
	check("Complete settings preserve explicit blank exam",Protocol.settings(settings))
	var command: Dictionary={"action":"query","requestId":"q1","settings":settings}
	check("Bounded query accepted",not Protocol.sanitize_command(command,7).is_empty())
	command.uid="other"
	check("Game cannot choose account ownership",Protocol.sanitize_command(command,7).is_empty())
	command.erase("uid")
	settings.year="114"
	check("Only115 is a recommendation candidate year",not Protocol.settings(settings))
	settings.year="115"
	check("Annual references are never bare codes",Protocol.program_ref("115:011001") and not Protocol.program_ref("011001") and not Protocol.program_ref("115:11+001"))
	var payload: Dictionary=results()
	payload.merge({"channel":Protocol.CHANNEL,"version":1,"type":"results","requestId":"q1","sessionGeneration":7})
	check("Structured result packet accepted",not Protocol.sanitize_packet(payload).is_empty())
	payload.items[0].uid="hidden"
	check("Nested credential/account fields rejected",Protocol.sanitize_packet(payload).is_empty())
	payload.items[0].erase("uid")
	payload.items[0].priorityTier=1.2
	check("Priority tiers must be integer",Protocol.sanitize_packet(payload).is_empty())
	payload.items[0].priorityTier=1
	var native: Node=Native.new()
	var view: FakeWebView=FakeWebView.new()
	native.add_child(view)
	native.set("webview",view)
	native.set("trusted_document",true)
	native.set("host_ready",true)
	native.set("session_generation",7)
	check("Hidden Windows host calls recommendation entry",native.call("request_recommendation",command) and view.scripts.size()==1 and view.scripts[0].contains("recommendationCommand"))
	native.connect("recommendation_message",func(packet: Dictionary) -> void: captured.append(packet))
	check("JSON numeric fields survive native wire transport",not Protocol.sanitize_packet(JSON.parse_string(JSON.stringify(payload))).is_empty())
	native.call("_receive_message",JSON.stringify(payload))
	check("Native host forwards validated result",captured.size()==1)
	native.set("trusted_document",false)
	native.call("_receive_message",JSON.stringify(payload))
	check("Untrusted navigation cannot emit recommendations",captured.size()==1)
	native.free()
	var session: Node=Session.new()
	var transport: Service=Service.new()
	session.add_child(transport)
	session.set("native_host",transport)
	session.set("user",transport.user.duplicate())
	captured.clear()
	session.connect("recommendation_message",func(packet: Dictionary) -> void: captured.append(packet))
	check("Account transport accepts recommendation query",session.call("request_recommendation",command))
	check("Same request retries with identical content",session.call("request_recommendation",command))
	var changed_command: Dictionary=command.duplicate(true)
	changed_command.settings.mode="interest"
	check("Pending mutation ID cannot change request",not session.call("request_recommendation",changed_command))
	session.call("_recommendation_message",payload)
	session.call("_recommendation_message",payload)
	check("Matching reply delivered only once",captured.size()==1)
	session.call("request_recommendation",command)
	session.call("_update_user",{})
	session.call("_recommendation_message",payload)
	check("Logout invalidates in flight result",captured.size()==1)
	session.free()
	var service: Service=Service.new()
	root.add_child(service)
	var panel: Control=RecommendationPanel.new()
	root.add_child(panel)
	await tick()
	panel.call("setup",service)
	panel.call("open_panel","data")
	await tick()
	check("Three station tabs share native panel",panel.get("pages").size()==3 and panel.visible and panel.get("page_index")==0)
	service.reply("bootstrap",{"settings":Controller.default_settings(),"settingsRevision":3,"activeReport":{"recordId":"report_one","revision":2,"selectionRevision":1,"title":"秋季探索"},"catalog":[{"groupId":"information","groupLabel":"資訊學群","category":"資訊工程"}],"years":["115"],"algorithmVersion":"v1","dataVersion":"test"})
	service.reply("listExams",{"items":[{"id":"exam_one","title":"合成測試模考","examDate":"2026-10-01","kind":"mock","summary":"國12 英12 數A12","updatedAtMillis":123}],"nextCursor":null})
	service.reply("listFavorites",{"items":[],"nextCursor":null})
	service.reply("query",results())
	await tick()
	check("Bootstrap uses completed report metadata",panel.get("active_report").revision==2 and panel.get("settings_revision")==3)
	check("Saved score list uses explicit selection",panel.get("exams").size()==1 and panel.get("settings").examId=="")
	check("Query renders bounded result cards",panel.get("rows").size()==4 and panel.get("controller").get("query_id")=="query_a")
	check("Report evidence is labelled as a report conclusion",panel.call("_fit_label",2)=="報告最適合")
	panel.get("result_packet").inputs.settings.source="manual"
	check("Manual priority never claims psychological suitability",panel.call("_fit_label",2)=="優先探索" and panel.call("_fit_label",1)=="也想看看")
	panel.get("result_packet").inputs.settings.source="activeReport"
	panel.call("_toggle_compare","115:011001")
	panel.call("_toggle_compare","115:011002")
	panel.call("_toggle_compare","115:011003")
	panel.call("_toggle_compare","115:011004")
	check("Comparison never exceeds three programs",panel.get("comparison").size()==3)
	for request: Dictionary in service.commands.duplicate(true):
		if request.action=="detail": service.reply("detail",details(request.programRef),request.requestId)
	await tick()
	check("Comparison details share the same query snapshot",panel.get("details").size()==3)
	if "--capture" in OS.get_cmdline_user_args():
		root.size=Vector2i(1280,900)
		await tick()
		panel.call("_resize_canvas")
		panel.call("_select_tab",1)
		await capture("fixture-desktop-results.png")
		panel.call("_select_tab",2)
		await capture("fixture-desktop-comparison.png")
		root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
		root.size=Vector2i(390,844)
		await tick()
		panel.call("_resize_canvas")
		await capture("fixture-narrow-comparison.png")
		panel.call("_select_tab",1)
		await capture("fixture-narrow-results.png")
		root.size=Vector2i(1280,900)
		await tick()
		panel.call("_resize_canvas")
	panel.call("_open_detail","115:011001")
	check("Detail overlay opens with history and sources",panel.get("detail_overlay").visible)
	panel.call("close_panel")
	check("Escape from detail retains main panel",not panel.get("detail_overlay").visible and panel.visible)
	check("Only official HTTPS links can be opened",panel.call("_safe_source","https://www.cac.edu.tw/apply115/") and not panel.call("_safe_source","javascript:alert(1)") and not panel.call("_safe_source","https://www.cac.edu.tw.evil.test/"))
	panel.call("_set_favorite","115:011001",true,0)
	check("Favorite not confirmed before server acknowledgement",panel.get("favorite_states")["115:011001"].value==false)
	service.reply("setFavorite",{"programRef":"115:011001","value":true,"revision":1})
	check("Confirmed favorite preserves revision",panel.get("favorite_states")["115:011001"].value==true and panel.get("favorite_states")["115:011001"].revision==1)
	panel.call("_run_query")
	service.reply("query",paged_results(0))
	await tick()
	check("Each recommendation page displays at most twenty rows",panel.get("rows").size()==20 and panel.get("result_page")==0)
	panel.call("_change_result_page",1)
	check("Next page uses the current snapshot and opaque cursor",service.latest("page").queryId=="query_a" and service.latest("page").cursor=="page_1")
	service.reply("page",paged_results(1))
	await tick()
	check("Next page replaces twenty cards rather than appending",panel.get("rows").size()==20 and panel.get("result_page")==1 and panel.get("rows")[0].programRef=="115:011021")
	var command_count: int=service.commands.size()
	panel.call("_change_result_page",0)
	check("Previous page reuses the same snapshot cache",panel.get("result_page")==0 and panel.get("rows")[0].programRef=="115:011001" and service.commands.size()==command_count)
	panel.call("_change_result_page",1)
	check("Returning to a cached next page avoids another query",panel.get("result_page")==1 and service.commands.size()==command_count)
	panel.call("_select_tab",1)
	await tick()
	(panel.get("scrolls")[1] as ScrollContainer).scroll_vertical=120
	var state: Dictionary=panel.call("get_return_state")
	check("Return state stores account generation and bounded comparison",state.sessionGeneration==7 and state.comparison.size()==3)
	check("Return state saves the current page and list position",state.resultPage==1 and state.scroll==120)
	panel.call("_inputs_changed")
	panel.call("restore_return_state",state)
	panel.call("_run_query")
	service.reply("query",paged_results(0,"restored_query"))
	check("Return reloads earlier cursors through one new snapshot",service.latest("page").queryId=="restored_query" and service.latest("page").cursor=="page_1")
	service.reply("page",paged_results(1,"restored_query"))
	await tick()
	await tick()
	check("Return restores the selected page with only twenty cards",panel.get("result_page")==1 and panel.get("rows").size()==20 and (panel.get("scrolls")[1] as ScrollContainer).scroll_vertical==120)
	var control: Node=panel.get("controller")
	control.call("send","query",{"settings":Controller.default_settings()})
	var old_query: Dictionary=service.latest("query")
	control.call("send","query",{"settings":Controller.default_settings()})
	service.reply("query",results("old_query"),old_query.requestId)
	check("Older query cannot replace newer inputs",control.get("query_id")=="")
	service.reply("query",results("new_query"))
	check("Latest query is accepted",control.get("query_id")=="new_query")
	service.user.sessionGeneration=8
	service.state_changed.emit(service.user)
	panel.call("restore_return_state",state)
	check("Returning after account switch cannot restore old private choices",panel.get("comparison").is_empty() and panel.get("rows").is_empty() and panel.get("settings").examId=="")
	panel.size=Vector2(390,780)
	panel.call("_layout")
	await tick()
	check("Narrow viewport uses single comparison card",panel.get("_small")==true)
	check("Shell stays inside narrow canvas",panel.get("shell").position.x>=0 and panel.get("shell").size.x<=panel.size.x)
	panel.free()
	service.free()
	await tick()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/recommendations/ui"))
	var report:=FileAccess.open("res://../deliverables/recommendations/ui/protocol-ui-checks.json",FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":check_records,"total":checks,"failures":failures,"scope":"Synthetic Godot native UI fixtures and real TypeScript-produced protocol packets; not live cloud or physical phone evidence."},"	"))
	report.close()
	print("RECOMMENDATION_UI_CHECKS total=",checks," failures=",failures)
	quit(1 if failures else 0)

func capture(name: String) -> void:
	for frame: int in range(5): await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/recommendations/ui"))
	root.get_texture().get_image().save_png("res://../deliverables/recommendations/ui/"+name)
