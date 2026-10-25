extends SceneTree
const Model = preload("res://scripts/interest_model.gd")
const Controller = preload("res://scripts/interest_controller.gd")
const InterestPanel = preload("res://scripts/interest_panel.gd")
const Diagnostics = preload("res://scripts/interest_diagnostics.gd")

class Service:
	extends Node
	signal state_changed(user: Dictionary)
	signal interest_message(packet: Dictionary)
	var user: Dictionary = {"profileReady":true,"sessionGeneration":7}
	var commands: Array[Dictionary] = []
	var accepted: bool = true
	func request_interest(command: Dictionary) -> bool:
		commands.append(command.duplicate(true))
		return accepted
	func respond(payload: Dictionary) -> void:
		var packet: Dictionary = {"requestId":commands.back().requestId,"sessionGeneration":user.sessionGeneration}
		packet.merge(payload,true)
		interest_message.emit(packet)

var failures: int = 0
var count: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	count += 1
	print("INTEREST_CHECK ",label," ",passed)
	if not passed:
		failures += 1
func valid_profile() -> Dictionary:
	var data: Dictionary = Model.new_profile()
	for key: String in data.riasec:
		data.riasec[key] = "0"
	for key: String in data.knowledge:
		data.knowledge[key] = "0"
	return data
func tick() -> void:
	await process_frame
	await process_frame
func activate_keyboard(control: Control) -> void:
	control.grab_focus()
	var event := InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = true
	root.push_input(event)
	await tick()
	event = InputEventKey.new()
	event.keycode = KEY_ENTER
	event.pressed = false
	root.push_input(event)
	await tick()
func run() -> void:
	var blank: Dictionary = Model.new_profile()
	check("Exactly 39 required scores; blank is not zero",Model.validate(blank).size() == 39 and Model.filled_count(blank) == 0)
	var data: Dictionary = valid_profile()
	check("39 zero scores and no optional fits valid",Model.validate(data).is_empty())
	data.riasec.R = "90"
	data.knowledge.k33 = "18"
	check("Inclusive maxima valid",Model.validate(data).is_empty())
	data.riasec.I = "91"
	data.knowledge.k01 = "18.5"
	check("Out of range and fractional scores rejected",Model.validate(data).size() == 2)
	data = valid_profile()
	data.bestFits[0] = {"groupId":"information","category":"資訊工程","z":"-0.25"}
	check("Signed finite Z preserved",Model.validate(data).is_empty() and Model.normalized(data).bestFits[0].z == "-0.25")
	data.suitableFits[1] = {"groupId":"information","category":" 資訊工程 ","z":"0"}
	check("Duplicate group/category rejected across degrees",Model.validate(data).has("suitableFits.1.category"))
	data.suitableFits[1].category = ""
	data.suitableFits[1].z = "NaN"
	check("Partial rows require missing category and finite Z",Model.validate(data).has("suitableFits.1.category") and Model.validate(data).has("suitableFits.1.z"))
	var legacy: Dictionary = valid_profile()
	legacy.riasecDate = " 2024- "
	legacy.knowledgeDate = "未填完"
	check("Hidden legacy partial dates cannot block completion or be silently changed",Model.validate(legacy).is_empty() and Model.normalized(legacy).riasecDate == " 2024- " and Model.normalized(legacy).knowledgeDate == "未填完")
	check("25 rows in each group",blank.bestFits.size() == 25 and blank.suitableFits.size() == 25)
	var service := Service.new()
	root.add_child(service)
	var controller := Controller.new()
	root.add_child(controller)
	controller.configure(service)
	controller.profile.riasec.R = "not yet"
	controller.edited()
	controller.save(false)
	check("Draft sends exact invalid raw text",service.commands.back().profile.riasec.R == "not yet")
	var submitted: Dictionary = service.commands.back().profile
	service.respond({"type":"state","recordId":controller.record_id,"revision":1,"profile":submitted,"hasDraft":true,"hasCompleted":false})
	check("Save success establishes clean baseline",not controller.is_dirty() and controller.revision == 1)
	controller.profile.riasec.R = "12"
	controller.edited()
	controller.save(false)
	var late_id: String = service.commands.back().requestId
	controller._timed_out()
	check("Timeout preserves edits and provides retry",controller.is_dirty() and controller.profile.riasec.R == "12" and not controller.retry_command.is_empty())
	controller.retry()
	check("Retry preserves mutation ID for server idempotence",service.commands.back().requestId == late_id)
	service.interest_message.emit({"type":"state","requestId":"obsolete_request","sessionGeneration":7,"recordId":controller.record_id,"revision":100,"profile":submitted})
	check("Late response cannot change pending newer request",controller.revision == 1 and controller.busy())
	service.respond({"type":"error","code":"unavailable","message":"測試離線"})
	check("Network errors preserve input",controller.profile.riasec.R == "12" and controller.error)
	controller.discard()
	check("Discard restores last saved raw draft",controller.profile.riasec.R == "not yet" and not controller.is_dirty())
	controller.profile = valid_profile()
	controller.edited()
	controller.save(true)
	var completed: Dictionary = service.commands.back().profile.duplicate(true)
	check("Complete strips all unused rows instead of storing fake zero Z",completed.bestFits.is_empty() and completed.suitableFits.is_empty())
	controller.profile.riasec.R = "22"
	controller.edited()
	service.respond({"type":"state","recordId":controller.record_id,"revision":2,"profile":completed,"hasCompleted":true,"hasDraft":false})
	check("Edits made during a save survive completion response",controller.profile.riasec.R == "22" and controller.is_dirty() and controller.has_completed)
	controller.save(false)
	var retry_snapshot: Dictionary = service.commands.back().profile.duplicate(true)
	controller._timed_out()
	controller.profile.riasec.R = "23"
	controller.edited()
	controller.retry()
	service.respond({"type":"state","recordId":controller.record_id,"revision":3,"profile":retry_snapshot,"hasCompleted":true,"hasDraft":true})
	check("Editing after timeout is not overwritten by retry of older snapshot",controller.profile.riasec.R == "23" and controller.baseline.riasec.R == "22" and controller.is_dirty())
	var kept_id: String = controller.record_id
	controller.configure(service)
	check("Reopening with same account preserves selected record and edits",controller.record_id == kept_id and controller.profile.riasec.R == "23")
	controller.refresh_history()
	service.respond({"type":"list","records":[{"id":"saved","title":"完成紀錄","revision":2,"hasCompleted":true,"hasDraft":true}],"activeRecordId":"saved","selectionRevision":3,"nextCursor":null})
	check("History retains completed and draft separately",controller.records[0].hasCompleted and controller.records[0].hasDraft)
	controller.select_active("saved")
	check("Active selection carries selection revision",service.commands.back().expectedSelectionRevision == 3)
	service.respond({"type":"active","activeRecordId":"saved","selectionRevision":4})
	service.user = {"profileReady":true,"sessionGeneration":8}
	service.state_changed.emit(service.user)
	check("Account swap clears drafts history active and pending",not controller.is_dirty() and controller.records.is_empty() and controller.profile.riasec.R == "" and controller.active_record_id.is_empty() and not controller.busy())
	controller.refresh_history()
	service.respond({"type":"list","records":[{"id":"active_test","title":"測試資料","revision":2,"hasCompleted":true,"hasDraft":false}],"activeRecordId":"active_test","selectionRevision":1,"nextCursor":null})
	await tick()
	check("Pristine open loads the account active record",service.commands.back().action == "get" and service.commands.back().recordId == "active_test")
	service.respond({"type":"state","recordId":"active_test","revision":2,"profile":valid_profile(),"hasCompleted":true,"hasDraft":false})
	check("Active record can be edited in Godot",controller.record_id == "active_test" and controller.has_completed and controller.profile.knowledge.k33 == "0")
	controller.open_record("another_record")
	controller.profile.riasec.R = "42"
	controller.edited()
	service.respond({"type":"state","recordId":"another_record","revision":1,"profile":valid_profile(),"hasCompleted":false,"hasDraft":true})
	check("New edits during record load cannot be replaced or assigned to another record",controller.record_id == "active_test" and controller.profile.riasec.R == "42" and controller.is_dirty())
	controller.queue_free()
	await tick()
	var panel := InterestPanel.new()
	root.add_child(panel)
	panel.configure(service)
	panel.open_panel()
	service.respond({"type":"list","records":[],"nextCursor":null,"activeRecordId":"","selectionRevision":0})
	await tick()
	check("Form offers all 39 score controls",panel.inputs.has("riasec.R") and panel.inputs.has("riasec.C") and panel.inputs.has("knowledge.k01") and panel.inputs.has("knowledge.k33"))
	check("Only two grade areas are visible with separate record management",not panel.tabs.tabs_visible and panel.grade_buttons.size() == 2 and panel.grade_buttons.high1.text == "高一測驗資料" and panel.grade_buttons.high3.text == "高三測驗資料" and panel.history_button.text == "我的紀錄")
	panel.grade_buttons.high3.pressed.emit()
	panel.high3_buttons.fits.pressed.emit()
	panel.grade_buttons.high1.pressed.emit()
	panel.grade_buttons.high3.pressed.emit()
	check("High-three nested navigation retains its selected section",panel.tabs.current_tab == 2 and panel.high3_navigation.visible and panel.high3_buttons.fits.button_pressed)
	panel.open_panel("high1")
	service.respond({"type":"list","records":[],"nextCursor":null,"activeRecordId":"","selectionRevision":0})
	check("High-one station opens all six types in one area",panel.tabs.current_tab == 0 and not panel.high3_navigation.visible)
	panel.open_panel("high3")
	service.respond({"type":"list","records":[],"nextCursor":null,"activeRecordId":"","selectionRevision":0})
	check("High-three station opens knowledge inside its grade area",panel.tabs.current_tab == 1 and panel.high3_navigation.visible)
	panel.grade_buttons.high3.set_pressed_no_signal(false)
	panel.grade_buttons.high3.pressed.emit()
	check("Selecting the current grade keeps its active indicator",panel.grade_buttons.high3.button_pressed and panel.high3_buttons.knowledge.button_pressed)
	panel.grade_buttons.high1.pressed.emit()
	await activate_keyboard(panel.grade_buttons.high3)
	await activate_keyboard(panel.high3_buttons.fits)
	check("Keyboard Enter reaches high-three nested suitability controls",panel.tabs.current_tab == 2 and panel.high3_buttons.fits.button_pressed)
	panel.grade_buttons.high1.pressed.emit()
	var prior_dates: Dictionary = Model.new_profile()
	prior_dates.riasecDate = "2024-"
	prior_dates.knowledgeDate = "未填完"
	panel.controller.profile = Model.for_editing(prior_dates)
	panel._rebuild()
	check("Form has no date controls even when loading a legacy draft",not panel.inputs.has("riasecDate") and not panel.inputs.has("knowledgeDate") and not panel.field_tabs.has("riasecDate") and not panel.field_tabs.has("knowledgeDate"))
	panel.controller.save(false)
	check("Hidden compatibility strings survive drafts without new required grade input",service.commands.back().profile.riasecDate == "2024-" and service.commands.back().profile.knowledgeDate == "未填完" and service.commands.back().profile.keys().size() == prior_dates.keys().size() and service.commands.back().profile.schemaVersion == 1)
	service.respond({"type":"state","recordId":panel.controller.record_id,"revision":1,"profile":service.commands.back().profile,"hasDraft":true,"hasCompleted":false})
	panel._input_changed("riasec.R","0")
	check("Stage progress counts an explicit zero and leaves blank stage empty",panel.progress_label.text.begins_with("高一 1 / 6　·　高三 0 / 33　·　共 1 / 39"))
	panel.tabs.current_tab = 1
	panel.tabs.current_tab = 0
	check("Tab switches preserve explicit zero",panel.controller.profile.riasec.R == "0")
	panel._add_row("bestFits")
	await tick()
	check("26th fit row is editable",panel.controller.profile.bestFits.size() == 26 and panel.inputs.has("bestFits.25.z"))
	(panel.inputs["bestFits.25.groupId"] as OptionButton).item_selected.emit(1)
	check("Row callbacks update their own index",panel.controller.profile.bestFits[25].groupId == "information" and panel.controller.profile.bestFits[0].groupId == "")
	panel._clear_row("bestFits",25)
	check("Clear row restores blank instead of zero",Model.is_blank_row(panel.controller.profile.bestFits[25]))
	panel._complete()
	await tick()
	check("Validation focuses first missing score with inline message",panel.tabs.current_tab == 0 and panel.errors["riasec.I"].visible and panel.inputs["riasec.I"].has_focus())
	panel.request_close()
	check("Dirty close opens three-choice dialog",panel.dialog.visible and panel.visible)
	panel.dialog.canceled.emit()
	panel.dialog.hide()
	check("Cancel keeps data in form",panel.visible and panel.controller.profile.riasec.R == "0")
	panel.request_close()
	panel._dialog_action(&"discard")
	check("Discard closes safely",not panel.visible and not panel.controller.is_dirty())
	panel.open_panel()
	service.respond({"type":"list","records":[],"nextCursor":null,"activeRecordId":"","selectionRevision":0})
	panel._input_changed("riasec.R","0")
	panel.request_close()
	panel.dialog.hide()
	panel._save_navigation()
	service.respond({"type":"state","recordId":panel.controller.record_id,"revision":1,"profile":service.commands.back().profile,"hasDraft":true,"hasCompleted":false})
	await tick()
	check("Save and close waits for account confirmation",not panel.visible and not panel.controller.is_dirty())
	panel.open_panel()
	service.respond({"type":"list","records":[],"nextCursor":null,"activeRecordId":"","selectionRevision":0})
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(390,844)
	await tick()
	check("Mobile panel stays within viewport",panel.shell.get_global_rect().end.x <= 390.1 and panel.shell.get_global_rect().end.y <= 844.1)
	check("Mobile score and fit fields stack vertically",panel.score_grids[0].columns == 1 and panel.fit_grids[0].columns == 1)
	check("Mobile primary actions retain 44 pixel touch targets",panel.draft_button.size.y >= 44 and panel.complete_button.size.y >= 44)
	check("Mobile grade navigation remains visible without clipped tab scrolling",panel.grade_buttons.high1.size.y >= 44 and panel.grade_buttons.high3.size.y >= 44 and panel.grade_buttons.high3.get_global_rect().end.x <= 390.1)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(960,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	await tick()
	var logical: Vector2 = root.get_visible_rect().size
	var physical_height: float = panel.draft_button.size.y*panel.scale.y*390.0/logical.x
	check("Expanded 960 canvas keeps 390px form columns and physical touch targets",is_equal_approx(panel.size.x,390.0) and panel.score_grids[0].columns == 1 and physical_height >= 43.9)
	var diagnostics := Diagnostics.new()
	panel.add_child(diagnostics)
	var geometry: Dictionary = diagnostics.control_geometry(panel.grade_buttons.high3)
	var expected: Vector2 = panel.grade_buttons.high3.get_global_transform_with_canvas()*(panel.grade_buttons.high3.size*.5)
	var observed: Vector2 = Vector2(geometry.center[0],geometry.center[1])*logical
	check("Scaled diagnostics map real canvas controls without double scaling",geometry.visible and observed.distance_to(expected) < .01)
	diagnostics.queue_free()
	root.gui_embed_subwindows = true
	panel._input_changed("riasec.R","1")
	panel.request_close()
	await tick()
	var dialog_button_height: float = panel.dialog.get_ok_button().size.y*panel.dialog.content_scale_factor*390.0/logical.x
	check("Embedded unsaved dialog keeps physical mobile width and touch targets",panel.dialog.visible and panel.dialog.size.x*390.0/logical.x <= 390.1 and dialog_button_height >= 43.9)
	panel.dialog.canceled.emit()
	panel.dialog.hide()
	root.content_scale_size = Vector2i(1440,900)
	root.size = Vector2i(1280,800)
	await tick()
	check("Desktop stretch keeps a display-sized form and three score columns",is_equal_approx(panel.size.x,1280.0) and panel.score_grids[0].columns == 3 and panel.draft_button.size.y*panel.scale.y*1280.0/root.get_visible_rect().size.x >= 43.9)
	panel._input_changed("riasec.R","31")
	service.user = {"profileReady":true,"sessionGeneration":9}
	service.state_changed.emit(service.user)
	check("Account switch closes visible old profile",not panel.visible and panel.controller.profile.riasec.R == "")
	panel.queue_free()
	service.queue_free()
	await tick()
	print("INTEREST_RESULT checks=",count," failures=",failures)
	quit(0 if failures == 0 else 1)
