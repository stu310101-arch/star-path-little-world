extends SceneTree
const HUD = preload("res://scripts/discussion_hud.gd")
const OUTPUT := "res://../deliverables/discussion-revision"
var hud: CanvasLayer
var checks: Array[Dictionary] = []
var failures: int = 0
var actions: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed})
	print("HUD_CHECK ", label, " ", passed)
	if not passed:
		failures += 1

func settle() -> void:
	for count: int in range(4):
		await process_frame

func within(control: Control, viewport_size: Vector2) -> bool:
	var bounds: Rect2 = control.get_global_rect()
	return bounds.position.x >= 0 and bounds.position.y >= 0 and bounds.end.x <= viewport_size.x + 1 and bounds.end.y <= viewport_size.y + 1

func capture(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var picture: Image = root.get_texture().get_image()
	picture.save_png(OUTPUT.path_join(file_name))

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,800)
	root.title = "交流花園 HUD · 版面驗證"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var background := ColorRect.new()
	background.color = Color("8ca2a3")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	hud = HUD.new()
	hud.set_meta("reduce_motion", true)
	root.add_child(hud)
	hud.connect("interaction_requested", func() -> void: actions.append("interact"))
	hud.connect("page_requested", func(direction: String) -> void: actions.append(direction))
	hud.connect("destination_requested", func(zone: String) -> void: actions.append(zone))
	var state: Dictionary = {"ready":true,"zone":"university","kind":"post","number":4,"occupied":false,"pending":false,"has_previous":false,"has_next":true,"page":0}
	state.hub = true
	hud.call("update_state",state)
	check("Hub has its own location and five-area introduction",(hud.get("location_title") as Label).text=="中心廣場" and (hud.get("location_description") as Label).text.contains("五區由此出發"))
	check("Hub does not falsely mark a destination as current",(hud.get("guide_rows") as Dictionary).values().all(func(row: Button) -> bool: return not row.text.contains("所在地")))
	check("Hub retains the selected zone paging contract",(hud.get("page_label") as Label).text=="大學交流 · 第 1 頁" and not (hud.get("next_button") as Button).disabled)
	state.hub = false
	hud.call("update_state",state)
	check("Leaving hub restores the current area label",(hud.get("location_title") as Label).text=="大學交流區" and (hud.get("guide_rows")["university"] as Button).text.contains("所在地"))
	await settle()
	check("Desktop interaction fits",within(hud.get("interaction_card"),Vector2(1280,800)))
	check("Desktop context card is compact",(hud.get("interaction_card") as Control).size.y <= 128)
	check("Desktop location and actions do not overlap",not (hud.get("location_card") as Control).get_global_rect().intersects((hud.get("top_actions") as Control).get_global_rect()))
	check("Empty device offers posting",(hud.get("interaction_button") as Button).text == "在此留言")
	(hud.get("interaction_button") as Button).pressed.emit()
	check("Interaction dispatches",actions.has("interact"))
	await capture("hud-desktop-empty.png")
	state.occupied = true
	state.preview = "想讀資訊工程，也喜歡設計，大家當初怎麼選科系？"
	hud.call("update_state",state)
	await settle()
	check("Occupied device offers discussion",(hud.get("interaction_button") as Button).text == "閱讀與回覆")
	await capture("hud-desktop-discussion.png")
	state.kind = ""
	hud.call("update_state",state)
	check("No permanent interaction block while exploring",not (hud.get("interaction_card") as Control).visible)
	check("Distant action disabled",(hud.get("interaction_button") as Button).disabled)
	hud.call("toggle_guide")
	await settle()
	check("Five destinations available",(hud.get("guide_rows") as Dictionary).size() == 5)
	check("Guide fits desktop",within(hud.get("guide_panel"),Vector2(1280,800)))
	(hud.get("next_button") as Button).pressed.emit()
	check("Paging dispatches direction",actions.has("next"))
	(hud.get("guide_rows")["career"] as Button).pressed.emit()
	check("Destination dispatches without scene mutation",actions.has("career"))
	check("Destination closes guide",not (hud.get("guide_panel") as Control).visible)
	state.pending = true
	hud.call("update_state",state)
	check("Loading prevents duplicate page request",(hud.get("refresh_button") as Button).disabled and (hud.get("next_button") as Button).disabled)
	hud.call("show_notice","留言暫時無法讀取，請在導覽按刷新重試。",true)
	check("Failures remain readable",(hud.get("toast_card") as Control).visible)
	root.size = Vector2i(390,844)
	await settle()
	state.pending = false
	state.touch = true
	state.kind = "post"
	state.zone = "high_school"
	state.destination_zone = "career"
	state.destination_distance = 37
	state.destination_direction = "前方"
	hud.call("update_state",state)
	await settle()
	check("390px interaction fits",within(hud.get("interaction_card"),Vector2(390,844)))
	check("390px actions fit",within(hud.get("top_actions"),Vector2(390,844)))
	check("390px route fits",within(hud.get("route_card"),Vector2(390,844)))
	check("390px interaction keeps touch control area free",(hud.get("interaction_card") as Control).get_global_rect().end.y <= 844-170)
	check("Touch prompt matches input",(hud.get("key_badge") as Label).text == "點擊")
	hud.call("_dismiss_notice")
	await settle()
	check("Route never covers location",not (hud.get("route_card") as Control).get_global_rect().intersects((hud.get("location_card") as Control).get_global_rect()))
	check("Restored route retains destination and distance",(hud.get("route_label") as Label).text.contains("37 m") and (hud.get("route_label") as Label).text.contains("未來就業"))
	await capture("hud-mobile-discussion.png")
	hud.call("toggle_guide")
	await settle()
	check("390px guide fits",within(hud.get("guide_panel"),Vector2(390,844)))
	check("Guide does not stack interaction",not (hud.get("interaction_card") as Control).visible)
	hud.call("show_notice","留言暫時無法讀取，請按刷新重試。",true)
	await settle()
	check("Guide and notice do not overlap at 390px",not (hud.get("guide_panel") as Control).get_global_rect().intersects((hud.get("toast_card") as Control).get_global_rect()))
	check("Notice hides route without covering it",not (hud.get("route_card") as Control).visible)
	hud.call("_dismiss_notice")
	await settle()
	await capture("hud-mobile-guide.png")
	check("Escape can close guide",bool(hud.call("close_guide")))
	check("Closed guide does not consume next Escape",not bool(hud.call("close_guide")))
	state.ready = false
	state.error = "花園下載中斷，請檢查網路後重試。"
	hud.call("update_state",state)
	await settle()
	check("Scene loading retry is visible",(hud.get("retry_button") as Control).visible)
	check("Loading card fits 390px",within(hud.get("loading_card"),Vector2(390,844)))
	await capture("hud-mobile-error.png")
	root.size = Vector2i(640,360)
	await settle()
	state.ready = true
	state.kind = ""
	state.error = ""
	hud.call("update_state",state)
	hud.call("toggle_guide")
	await settle()
	check("Guide scrolls within short landscape view",within(hud.get("guide_panel"),Vector2(640,360)))
	check("Short landscape guide leaves location readable",not (hud.get("guide_panel") as Control).get_global_rect().intersects((hud.get("location_card") as Control).get_global_rect()))
	await capture("hud-small-landscape-guide.png")
	var report_name: String = "hud-headless-checks.json" if DisplayServer.get_name()=="headless" else "hud-checks.json"
	var report := FileAccess.open(OUTPUT.path_join(report_name),FileAccess.WRITE)
	report.store_string(JSON.stringify({"checks":checks,"failures":failures,"screenshots_rendered":DisplayServer.get_name()!="headless"},"  "))
	report.close()
	quit(1 if failures else 0)
