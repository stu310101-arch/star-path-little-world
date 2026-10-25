extends Control
## Three desks share this one native journal. Private data stays scoped to the account.
signal closed
signal visit_university(school_id: String, state: Dictionary)
const Controller = preload("res://scripts/recommendation_controller.gd")
const Catalog = preload("res://scripts/university_catalog.gd")
const InterestPanel = preload("res://scripts/interest_panel.gd")
const INK: Color = Color("242743")
const MUTED: Color = Color("66647e")
const PAPER: Color = Color("f7f4ec")
const LAVENDER: Color = Color("e1dcf5")
const GOLD: Color = Color("dfc59a")
const STATUS_LABELS: Dictionary = {"all":"符合學類","passed":"回測達標","failed":"尚有差距","pending":"待補資料","explore":"純興趣探索","extension":"延伸探索"}
var controller: Node
var account: Node
var university: RefCounted
var settings: Dictionary = Controller.default_settings()
var settings_revision: int = 0
var active_report: Variant = null
var choices: Array = []
var exams: Array = []
var exam_cursor: Variant = null
var rows: Array = []
var result_packet: Dictionary = {}
var next_cursor: Variant = null
var result_pages: Array[Dictionary] = []
var result_page: int = 0
var requested_page: int = -1
var favorite_rows: Array = []
var favorite_cursor: Variant = null
var favorite_states: Dictionary = {}
var details: Dictionary = {}
var comparison: Array[String] = []
var awaiting_details: Array[String] = []
var detail_reference: String = ""
var mobile_comparison: int = 0
var page_index: int = 0
var status: Label
var shell: PanelContainer
var pages: Array[VBoxContainer] = []
var scrolls: Array[ScrollContainer] = []
var nav: Array[Button] = []
var detail_overlay: PanelContainer
var detail_content: VBoxContainer
var interest_panel: Control
var keep_inputs: bool = false
var restored_page: int = -1
var restored_scroll: int = 0
var restore_pending: Dictionary = {}
var query_dirty: bool = true
var input_version: int = 0
var bootstrap_input_version: int = 0
var _small: bool = false
var _built: bool = false
var _width: float = -1
var _keyboard_height: int = -1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	controller = Controller.new()
	add_child(controller)
	controller.changed.connect(_status_changed)
	controller.response.connect(_response)
	controller.account_reset.connect(_account_reset)
	university = Catalog.new()
	university.call("load_content")
	university.connect("progress_changed",_university_changed)
	_build()
	_built = true
	add_child(preload("res://scripts/recommendation_diagnostics.gd").new())
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	visible = false
	if is_instance_valid(account): setup(account)
	if not restore_pending.is_empty():
		var pending_state: Dictionary = restore_pending.duplicate(true)
		restore_pending.clear()
		restore_return_state(pending_state)

func setup(service: Node) -> void:
	if not _built:
		account = service
		return
	if is_instance_valid(account) and account!=service and account.is_connected("closed",_host_closed): account.disconnect("closed",_host_closed)
	account = service
	controller.call("setup",service)
	university.call("detach_cloud")
	if is_instance_valid(service):
		university.call("configure_cloud",service)
		university.call("refresh_cloud")
		if not service.is_connected("closed",_host_closed): service.connect("closed",_host_closed)

func open_panel(tab: Variant = 0) -> void:
	page_index = int(tab) if tab is int else int({"data":0,"recommendations":1,"compare":2}.get(str(tab),0))
	page_index = clampi(page_index,0,2)
	show()
	shell.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resize_canvas()
	_select_tab(page_index)
	_refresh(keep_inputs or not choices.is_empty())

func close_panel() -> void:
	if is_instance_valid(interest_panel) and interest_panel.visible:
		interest_panel.call("request_close")
		return
	if detail_overlay.visible:
		detail_overlay.hide()
		detail_reference = ""
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD): DisplayServer.virtual_keyboard_hide()
	hide()
	closed.emit()

func get_return_state() -> Dictionary:
	return {"sessionGeneration":int(controller.get("generation")),"settings":settings.duplicate(true),"comparison":comparison.duplicate(),"tab":page_index,"resultPage":result_page,"scroll":scrolls[1].scroll_vertical,"detailRef":detail_reference}

func restore_return_state(state: Dictionary) -> void:
	if not _built:
		restore_pending = state.duplicate(true)
		return
	if int(state.get("sessionGeneration",-2))!=int(controller.get("generation")):
		_account_reset()
		return
	var next_settings: Variant = state.get("settings")
	if not preload("res://scripts/recommendation_protocol.gd").settings(next_settings): return
	settings = next_settings.duplicate(true)
	comparison.clear()
	for reference: Variant in state.get("comparison",[]):
		if comparison.size()<3 and preload("res://scripts/recommendation_protocol.gd").program_ref(reference) and str(reference) not in comparison: comparison.append(str(reference))
	page_index = clampi(int(state.get("tab",0)),0,2)
	restored_page = clampi(int(state.get("resultPage",0)),0,110)
	restored_scroll = maxi(0,int(state.get("scroll",0)))
	detail_reference = str(state.get("detailRef",""))
	keep_inputs = true
	awaiting_details.assign(comparison)
	if not detail_reference.is_empty() and detail_reference not in awaiting_details: awaiting_details.append(detail_reference)
	show()
	_select_tab(page_index)

func _exit_tree() -> void:
	if is_instance_valid(account) and account.is_connected("closed",_host_closed): account.disconnect("closed",_host_closed)
	if university!=null: university.call("detach_cloud")

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_panel()

func _process(_delta: float) -> void:
	if visible and _built:
		var keyboard: int = DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
		if keyboard!=_keyboard_height:
			_keyboard_height = keyboard
			_layout()

func _style(color: Color, radius: int = 14, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var value := StyleBoxFlat.new()
	value.bg_color = color
	value.set_corner_radius_all(radius)
	value.set_border_width_all(1)
	value.border_color = border
	value.content_margin_left = 16
	value.content_margin_right = 16
	value.content_margin_top = 12
	value.content_margin_bottom = 12
	return value

func _build() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var design := Theme.new()
	var scalable_font: FontFile=preload("res://assets/fonts/NotoSansTC.ttf").duplicate() as FontFile
	scalable_font.multichannel_signed_distance_field=true
	var weighted_font:=FontVariation.new()
	weighted_font.base_font=scalable_font
	weighted_font.variation_opentype={2003265652:550.0}
	design.default_font=weighted_font
	design.default_font_size = 17
	for type_name: String in ["Label","Button","OptionButton","LineEdit","PopupMenu"]:
		for name: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]: design.set_color(name,type_name,INK)
	for type_name: String in ["Button","OptionButton"]:
		design.set_stylebox("normal",type_name,_style(LAVENDER,10))
		design.set_stylebox("hover",type_name,_style(Color("d3cbed"),10))
		design.set_stylebox("pressed",type_name,_style(GOLD,10))
		design.set_stylebox("disabled",type_name,_style(Color("e4e2df"),10))
		design.set_stylebox("focus",type_name,_style(Color.TRANSPARENT,10,Color("77649f")))
	design.set_stylebox("normal","LineEdit",_style(Color.WHITE,10,Color("d4cde2")))
	design.set_stylebox("focus","LineEdit",_style(Color.WHITE,10,Color("77649f")))
	design.set_color("caret_color","LineEdit",INK)
	design.set_color("font_placeholder_color","LineEdit",MUTED)
	design.set_stylebox("panel","PopupMenu",_style(PAPER,10,Color("b9abc8")))
	design.set_stylebox("hover","PopupMenu",_style(LAVENDER,8))
	design.set_constant("v_separation","PopupMenu",16)
	theme = design
	var backdrop := ColorRect.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.08,0.08,0.18,.76)
	add_child(backdrop)
	shell = PanelContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_stylebox_override("panel",_style(PAPER,20))
	add_child(shell)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",10)
	shell.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title: Label = _label("星圖羅盤 · 選校研究所",24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	_button(heading,"關閉",close_panel)
	_text(body,"把喜歡的方向，和現在的成績放在一起。",15,MUTED)
	var navigation := HFlowContainer.new()
	navigation.add_theme_constant_override("h_separation",8)
	body.add_child(navigation)
	for index: int in range(3):
		var button: Button = _button(navigation,["推薦依據","校系推薦","收藏比較"][index],func() -> void: _select_tab(index))
		button.toggle_mode = true
		button.name = ["RecommendationInputs","RecommendationResults","RecommendationComparison"][index]
		nav.append(button)
	for index: int in range(3):
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		body.add_child(scroll)
		scrolls.append(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",12)
		scroll.add_child(page)
		pages.append(page)
	status = _label("",14,MUTED)
	body.add_child(status)
	var recovery := HFlowContainer.new()
	body.add_child(recovery)
	_button(recovery,"重試連線",func() -> void: controller.call("retry"))
	_button(recovery,"重新讀取",func() -> void: _refresh(true))
	_button(recovery,"載入帳號設定",func() -> void: _refresh(false))
	detail_overlay = PanelContainer.new()
	detail_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	detail_overlay.add_theme_stylebox_override("panel",_style(PAPER,16,Color("b9abc8")))
	add_child(detail_overlay)
	var detail_box := VBoxContainer.new()
	detail_overlay.add_child(detail_box)
	_button(detail_box,"返回推薦清單",func() -> void: detail_overlay.hide(); detail_reference="")
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	detail_box.add_child(detail_scroll)
	detail_content = VBoxContainer.new()
	detail_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_content.add_theme_constant_override("separation",12)
	detail_scroll.add_child(detail_content)
	detail_overlay.hide()

func _label(text: String, font_size: int = 17, color: Color = INK) -> Label:
	var value := Label.new()
	value.text = text
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	value.add_theme_font_size_override("font_size",font_size)
	value.add_theme_color_override("font_color",color)
	return value

func _text(parent: Node, text: String, font_size: int = 17, color: Color = INK) -> Label:
	var value: Label = _label(text,font_size,color)
	parent.add_child(value)
	return value

func _button(parent: Node, text: String, action: Callable) -> Button:
	var value := Button.new()
	value.text = text
	value.custom_minimum_size.y = 44
	value.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	value.pressed.connect(action)
	parent.add_child(value)
	return value

func _option(parent: Node, entries: Array, selected: int, action: Callable) -> OptionButton:
	var value := OptionButton.new()
	value.custom_minimum_size.y = 46
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.fit_to_longest_item = false
	for entry: Variant in entries: value.add_item(str(entry))
	if value.item_count>0: value.select(clampi(selected,0,value.item_count-1))
	value.item_selected.connect(action)
	parent.add_child(value)
	return value

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _card(parent: Node) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel",_style(Color.WHITE,14,Color("ded8e8")))
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",10)
	panel.add_child(body)
	return body

func _select_tab(index: int) -> void:
	page_index = clampi(index,0,2)
	for number: int in range(3):
		scrolls[number].visible = number==page_index
		nav[number].button_pressed = number==page_index
	_render()

func _refresh(preserve: bool) -> void:
	if not preserve:
		restored_page=-1
		restored_scroll=0
	if preserve and restored_page<0 and not result_packet.is_empty():
		restored_page=result_page
		restored_scroll=scrolls[1].scroll_vertical
	exams.clear()
	exam_cursor=null
	favorite_rows.clear()
	favorite_cursor=null
	keep_inputs = preserve
	bootstrap_input_version=input_version
	controller.call("send","bootstrap")
	controller.call("send","listExams",{"cursor":null})
	controller.call("send","listFavorites",{"cursor":null})

func _render() -> void:
	if not _built: return
	_render_inputs()
	_render_results()
	_render_comparison()
	_status_changed()

func _render_inputs() -> void:
	var page: VBoxContainer = pages[0]
	_clear(page)
	var report_box: VBoxContainer = _card(page)
	_text(report_box,"01  興趣方向",20)
	_text(report_box,"選用完成報告："+str(active_report.title) if active_report is Dictionary else "尚未選用已完成的量表。可先自選學類探索。")
	if active_report is Dictionary: _text(report_box,"採用完成版本 %d；草稿修改不會改變本次推薦。"%int(active_report.revision),14,MUTED)
	var actions := HFlowContainer.new()
	report_box.add_child(actions)
	_button(actions,"管理我的量表",_manage_interest)
	var source_picker: OptionButton = _option(report_box,["依照已完成報告","自選探索方向"],0 if settings.source=="activeReport" else 1,func(index: int) -> void:
		settings.source = "activeReport" if index==0 else "manual"
		_inputs_changed()
		_render_inputs())
	source_picker.name="RecommendationSource"
	if settings.source=="manual":
		_text(report_box,"自選方向由你決定優先度，不會改寫量表結論。",15,MUTED)
		for index: int in range(settings.manual.size()):
			var row: Dictionary = settings.manual[index]
			var line := HFlowContainer.new()
			report_box.add_child(line)
			_text(line,str(row.category),17)
			_option(line,["優先探索","也想看看"],0 if int(row.level)==2 else 1,func(selected: int) -> void: settings.manual[index].level=2 if selected==0 else 1; _inputs_changed())
			_button(line,"移除",func() -> void: settings.manual.remove_at(index); _inputs_changed(); _render_inputs())
		if choices.is_empty():
			_text(report_box,"正在讀取可探索學類…",15,MUTED)
		else:
			var choice_names: Array = []
			for row: Dictionary in choices: choice_names.append(str(row.groupLabel)+" · "+str(row.category))
			var pick: OptionButton = _option(report_box,choice_names,0,func(_index: int) -> void: pass)
			pick.name="RecommendationManualCategory"
			_button(report_box,"加入探索學類",func() -> void:
				var chosen: Dictionary = choices[pick.selected]
				for row: Dictionary in settings.manual:
					if row.groupId==chosen.groupId and row.category==chosen.category: return
				if settings.manual.size()<128:
					settings.manual.append({"groupId":chosen.groupId,"category":chosen.category,"level":2})
					_inputs_changed()
					_render_inputs())
	var exam_box: VBoxContainer = _card(page)
	_text(exam_box,"02  選擇一份成績",20)
	var exam_names: Array = ["暫不帶成績 · 純興趣探索"]
	var selection: int = 0
	for index: int in range(exams.size()):
		var exam: Dictionary = exams[index]
		exam_names.append(str(exam.examDate)+" · "+str(exam.title))
		if exam.id==settings.examId: selection=index+1
	if not str(settings.examId).is_empty() and selection==0:
		exam_names.append("已選成績 · 載入更多紀錄可查看名稱")
		selection=exam_names.size()-1
	var exam_picker: OptionButton = _option(exam_box,exam_names,selection,func(index: int) -> void:
		if index<=exams.size():
			settings.examId="" if index==0 else str(exams[index-1].id)
			_inputs_changed()
			_render_inputs())
	exam_picker.name="RecommendationExam"
	for exam: Dictionary in exams:
		if exam.id==settings.examId: _text(exam_box,str(exam.summary),15,MUTED)
	var exam_actions := HFlowContainer.new()
	exam_box.add_child(exam_actions)
	if exam_cursor!=null: _button(exam_actions,"更多成績",func() -> void: controller.call("send","listExams",{"cursor":exam_cursor}))
	_button(exam_actions,"管理我的成績",func() -> void: if is_instance_valid(account): account.call("open_view","scores"))
	_text(exam_box,"僅在官方招生條件有分組時使用：",14,MUTED)
	var gender_picker: OptionButton = _option(exam_box,["尚未指定官方招生分組","官方男生組","官方女生組"],["","male","female"].find(settings.applicantGender),func(index: int) -> void: settings.applicantGender=["","male","female"][index]; _inputs_changed())
	gender_picker.name="RecommendationGender"
	var mode_box: VBoxContainer = _card(page)
	_text(mode_box,"03  排序取向",20)
	_mode_controls(mode_box)
	_text(mode_box,"均衡時，「最適合但未達」與「適合且達標」列在同一優先層。缺資料的校系另列，沒有成績時只看興趣方向。",15,MUTED)
	var buttons := HFlowContainer.new()
	mode_box.add_child(buttons)
	_button(buttons,"查看我的推薦",func() -> void: _select_tab(1); _run_query())
	_button(buttons,"儲存這組選擇",func() -> void: controller.call("send","saveSettings",{"settings":settings.duplicate(true),"expectedRevision":settings_revision}))

func _mode_controls(parent: Node) -> void:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation",8)
	parent.add_child(row)
	for index: int in range(3):
		var id: String = ["interest","balanced","academic"][index]
		var button: Button = _button(row,["興趣較重 7：3","均衡 5：5","成績較重 3：7"][index],func() -> void:
			settings.mode=id
			_inputs_changed()
			_render()
			if page_index==1: _run_query())
		button.name = "RecommendationMode_"+id
		button.toggle_mode = true
		button.button_pressed = settings.mode==id

func _inputs_changed() -> void:
	input_version+=1
	query_dirty = true
	controller.call("invalidate_query")
	details.clear()
	result_packet.clear()
	rows.clear()
	next_cursor = null
	result_pages.clear()
	result_page=0
	requested_page=-1
	restored_page=-1
	restored_scroll=0
	controller.set("status","選擇已變更，請更新推薦；尚未儲存至帳號。")
	_status_changed()

func _run_query(for_comparison: bool = false) -> void:
	var query_settings: Dictionary = settings.duplicate(true)
	if settings.source=="activeReport" and not active_report is Dictionary:
		if for_comparison: query_settings.source="manual"; query_settings.manual=[]
		else:
			controller.set("status","請先選用一份完成報告，或改用自選探索方向。")
			controller.set("error",true)
			_status_changed()
			return
	rows.clear()
	details.clear()
	next_cursor = null
	result_packet.clear()
	result_pages.clear()
	result_page=0
	requested_page=-1
	awaiting_details.assign(comparison)
	if not detail_reference.is_empty() and detail_reference not in awaiting_details: awaiting_details.append(detail_reference)
	query_dirty = false
	controller.call("send","query",{"settings":query_settings})
	_render_results()

func _render_results() -> void:
	var page: VBoxContainer = pages[1]
	_clear(page)
	_mode_controls(page)
	_text(page,"115 學年度歷史一階回測 · 結果為探索參考",15,MUTED)
	var search := LineEdit.new()
	search.placeholder_text = "搜尋學校、科系或校系代碼"
	search.max_length=80
	search.custom_minimum_size.y=46
	search.text=str(settings.filters.keyword)
	search.text_changed.connect(func(value: String) -> void: settings.filters.keyword=value; _inputs_changed())
	search.text_submitted.connect(func(_value: String) -> void: _inputs_changed(); _run_query())
	page.add_child(search)
	var filter_row := HFlowContainer.new()
	page.add_child(filter_row)
	var statuses: Array = STATUS_LABELS.keys()
	var status_picker: OptionButton = _option(filter_row,STATUS_LABELS.values(),statuses.find(settings.filters.status),func(index: int) -> void: settings.filters.status=statuses[index]; _inputs_changed(); _run_query())
	status_picker.name="RecommendationStatus"
	var categories: Array = [""]
	for choice: Dictionary in choices:
		if choice.category not in categories: categories.append(choice.category)
	var category_labels: Array = categories.duplicate()
	category_labels[0]="全部學類"
	var category_picker: OptionButton = _option(filter_row,category_labels,maxi(0,categories.find(settings.filters.category)),func(index: int) -> void: settings.filters.category=categories[index]; _inputs_changed(); _run_query())
	category_picker.name="RecommendationCategory"
	_button(filter_row,"更新推薦",func() -> void: _inputs_changed(); _run_query())
	if result_packet.is_empty():
		_text(page,"選好報告與成績後，按「更新推薦」。" if query_dirty or bool(controller.get("error")) else "羅盤正在整理相符的校系…",18,MUTED)
		return
	var inputs: Dictionary = result_packet.get("inputs",{})
	var basis: String = "報告："+str(inputs.report.title) if inputs.get("report") is Dictionary else "自選探索方向"
	basis += "　｜　成績："+str(inputs.exam.title) if inputs.get("exam") is Dictionary else "　｜　未選成績，純興趣探索"
	_text(page,basis,15,MUTED)
	_text(page,"找到 %d 筆，本頁 %d 筆"%[int(result_packet.get("total",0)),rows.size()],18)
	var counts: Dictionary = result_packet.get("counts",{})
	_text(page,"達標 %d · 尚有差距 %d · 待補資料 %d · 興趣探索 %d · 延伸 %d"%[int(counts.get("passed",0)),int(counts.get("failed",0)),int(counts.get("pending",0)),int(counts.get("explore",0)),int(counts.get("extension",0))],14,MUTED)
	for warning: Variant in result_packet.get("warnings",[]): _text(page,str(warning),15,Color("885824"))
	_result_pagination(page)
	if rows.is_empty(): _text(page,"這組條件沒有相符的校系。可調整學類或篩選條件；系統不會自動放寬你的選擇。",18)
	for row: Dictionary in rows: _result_card(page,row)
	if not rows.is_empty(): _result_pagination(page,true)

func _result_pagination(parent: Node, bottom: bool = false) -> void:
	var controls:=HFlowContainer.new()
	controls.add_theme_constant_override("h_separation",8)
	parent.add_child(controls)
	var loading: bool=bool(controller.call("busy","page")) or bool(controller.call("busy","query"))
	var previous: Button=_button(controls,"上一頁",func() -> void: _change_result_page(result_page-1))
	previous.name="RecommendationPreviousBottom" if bottom else "RecommendationPrevious"
	previous.disabled=result_page==0 or loading
	var position_label: Label=_text(controls,"第 %d / %d 頁"%[result_page+1,maxi(1,ceili(float(result_packet.get("total",0))/20.0))],16,MUTED)
	position_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	position_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var next: Button=_button(controls,"下一頁",func() -> void: _change_result_page(result_page+1))
	next.name="RecommendationNextBottom" if bottom else "RecommendationNext"
	next.disabled=next_cursor==null or loading

func _display_result_page(index: int) -> void:
	result_page=index
	result_packet=result_pages[index]
	rows=result_packet.items.duplicate(true)
	next_cursor=result_packet.nextCursor

func _change_result_page(index: int) -> void:
	if index<0 or bool(controller.call("busy","query")) or bool(controller.call("busy","page")): return
	if index<result_pages.size():
		_display_result_page(index)
		_render_results()
		scrolls[1].set_deferred("scroll_vertical",0)
	elif index==result_pages.size() and not result_pages.is_empty() and result_pages.back().nextCursor!=null:
		requested_page=index
		controller.call("send","page",{"queryId":controller.get("query_id"),"cursor":result_pages.back().nextCursor})
		_render_results()

func _result_card(parent: Node, row: Dictionary) -> void:
	var card: VBoxContainer = _card(parent)
	var tier: Variant = row.get("priorityTier")
	_text(card,"同優先層 %d"%int(tier) if tier!=null else str(row.get("statusLabel","探索校系")),14,MUTED)
	_text(card,str(row.schoolName)+"\n"+str(row.programName),20)
	_text(card,str(row.get("statusLabel","")),16)
	for reason: Variant in row.get("reasons",[]): _text(card,str(reason),15,MUTED)
	if not str(row.get("gapSummary","")).is_empty(): _text(card,str(row.gapSummary),15,Color("855b34"))
	if not row.get("missing",[]).is_empty(): _text(card,"待補資料："+"、".join(row.missing),15,Color("855b34"))
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",8)
	card.add_child(actions)
	var reference: String = str(row.programRef)
	_button(actions,"查看理由與門檻",func() -> void: _open_detail(reference))
	var favorite: Dictionary = favorite_states.get(reference,{"value":row.get("favorite",false),"revision":row.get("favoriteRevision",row.get("revision",0))})
	_button(actions,"取消校系收藏" if bool(favorite.value) else "收藏校系",func() -> void: _set_favorite(reference,not bool(favorite.value),int(favorite.revision)))
	_button(actions,"移出比較" if reference in comparison else "加入比較",func() -> void: _toggle_compare(reference))
	_school_actions(actions,str(row.get("universityId","")))

func _school_actions(parent: Node, id: String) -> void:
	if id.is_empty(): return
	var school_favorites: Dictionary = university.get("favorites")
	var pending_cloud: Dictionary = university.get("cloud_requests")
	var save_error: String = str(university.get("save_error"))
	var button: Button = _button(parent,"學校收藏同步中" if not pending_cloud.is_empty() else ("取消學校收藏" if school_favorites.has(id) else "收藏學校"),func() -> void:
		university.call("toggle_favorite",id)
		_render()
		if detail_overlay.visible and details.has(detail_reference): _show_detail(detail_reference))
	button.disabled = not pending_cloud.is_empty()
	if not save_error.is_empty() and pending_cloud.is_empty():
		button.text="重試學校收藏同步"
		button.pressed.disconnect(button.pressed.get_connections()[0].callable)
		button.pressed.connect(func() -> void: university.call("refresh_cloud"))
	_button(parent,"前往大學館",func() -> void: visit_university.emit(id,get_return_state()))

func _set_favorite(reference: String, value: bool, revision: int) -> void:
	if bool(controller.call("busy","setFavorite")): return
	controller.call("send","setFavorite",{"programRef":reference,"value":value,"expectedRevision":revision})

func _toggle_compare(reference: String) -> void:
	if reference in comparison: comparison.erase(reference)
	elif comparison.size()<3:
		comparison.append(reference)
		_request_detail(reference)
	else:
		controller.set("status","最多比較 3 個校系，請先移除其中一個。")
		_status_changed()
		return
	mobile_comparison=clampi(mobile_comparison,0,maxi(0,comparison.size()-1))
	_render()

func _request_detail(reference: String) -> void:
	if details.has(reference): return
	if reference not in awaiting_details: awaiting_details.append(reference)
	if str(controller.get("query_id")).is_empty():
		if not bool(controller.call("busy","query")): _run_query(true)
		return
	awaiting_details.erase(reference)
	controller.call("send","detail",{"queryId":controller.get("query_id"),"programRef":reference})

func _open_detail(reference: String) -> void:
	detail_reference=reference
	detail_overlay.show()
	_clear(detail_content)
	_text(detail_content,"正在讀取校系詳情…",20)
	if details.has(reference): _show_detail(reference)
	else: _request_detail(reference)

func _show_detail(reference: String) -> void:
	if not details.has(reference): return
	_clear(detail_content)
	_detail_body(detail_content,details[reference],false)
	detail_overlay.show()

func _detail_body(parent: Node, packet: Dictionary, compact: bool) -> void:
	var row: Dictionary = packet.item
	var data: Dictionary = packet.details
	_text(parent,str(row.schoolName)+"\n"+str(row.programName),20)
	_text(parent,str(row.statusLabel),17)
	for reason: Variant in data.matchReasons: _text(parent,str(reason),15,MUTED)
	for fit: Dictionary in data.fitEvidence:
		_text(parent,"%s · %s%s"%[str(fit.get("category","")),_fit_label(int(fit.get("level",0)))," · 報告 Z "+str(fit.z) if fit.get("z")!=null and str(fit.get("z","")).length()>0 else ""],14,MUTED)
	if not str(data.mappingNote).is_empty(): _text(parent,str(data.mappingNote),15,MUTED)
	_text(parent,"歷年一階回測",19)
	for year: Dictionary in data.history: _text(parent,str(year.year)+" 年 · "+str(year.label),15)
	if not data.missing.is_empty(): _text(parent,"待補資料："+"、".join(data.missing),15,Color("855b34"))
	_text(parent,"本年度逐項門檻",19)
	for rule: Dictionary in data.rules:
		_text(parent,"%s %s\n目前：%s　需要：%s"%["✓" if rule.get("passed")==true else ("待補" if rule.get("passed")==null else "○"),str(rule.get("label","條件")),_value_text(rule.get("actual")),_value_text(rule.get("required"))],15)
	for plan: Dictionary in data.boostPlans:
		_text(parent,str(plan.get("summary","補分參考")),15,Color("855b34"))
	var id: String = str(row.get("universityId",""))
	var schools: Dictionary = university.get("by_id")
	if schools.has(id):
		var school: Dictionary = schools[id]
		_text(parent,"校園資訊",19)
		_text(parent,str(school.get("sections",{}).get("location","")),15,MUTED)
		if not compact: _text(parent,str(school.get("sections",{}).get("surroundings","")),15,MUTED)
	if not compact and data.reportSummary is Dictionary:
		_text(parent,"量表補充資料",19)
		var summary: Dictionary = data.reportSummary
		var raw: Array[String] = []
		for key: String in summary.get("riasec",{}): raw.append(key+" "+str(summary.riasec[key]))
		_text(parent,"RIASEC："+" · ".join(raw),15,MUTED)
		var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interest_catalog.json"))
		raw.clear()
		for knowledge: Dictionary in catalog.get("knowledge",[]): raw.append(str(knowledge.label)+" "+str(summary.get("knowledge",{}).get(knowledge.id,"—")))
		_text(parent,"知識分數："+" · ".join(raw),15,MUTED)
	var sources := HFlowContainer.new()
	parent.add_child(sources)
	for source: Dictionary in data.sources:
		if _safe_source(str(source.url)): _button(sources,str(source.label),func() -> void: OS.shell_open(str(source.url)))
	var actions := HFlowContainer.new()
	parent.add_child(actions)
	_school_actions(actions,id)
	if compact: _button(actions,"移出比較",func() -> void: _toggle_compare(str(row.programRef)))
	else: _button(actions,"移出比較" if str(row.programRef) in comparison else "加入比較",func() -> void: _toggle_compare(str(row.programRef)))

func _fit_label(level: int) -> String:
	var source: String=str(result_packet.get("inputs",{}).get("settings",settings).get("source",settings.source))
	if source=="manual": return "優先探索" if level==2 else "也想看看"
	return "報告最適合" if level==2 else "報告適合"

func _value_text(value: Variant) -> String:
	return "尚未提供" if value==null else str(value)

func _safe_source(url: String) -> bool:
	if not url.begins_with("https://") or url.length()>4096 or url.contains("\n") or url.contains("\r") or url.contains("\\"): return false
	var host: String = url.substr(8).split("/")[0].to_lower()
	return host in ["www.cac.edu.tw","cac.edu.tw","collego.edu.tw","www.collego.edu.tw","www.ceec.edu.tw","career.ceec.edu.tw"]

func _render_comparison() -> void:
	var page: VBoxContainer = pages[2]
	_clear(page)
	_text(page,"比較候選 · %d / 3"%comparison.size(),20)
	if comparison.is_empty(): _text(page,"從推薦清單或收藏選擇最多 3 個校系，並列查看興趣理由、歷年門檻與校園資訊。",16,MUTED)
	else:
		if _small:
			var names: Array = []
			for reference: String in comparison:
				names.append(str(details[reference].item.programName) if details.has(reference) else reference)
			_option(page,names,mobile_comparison,func(index: int) -> void: mobile_comparison=index; _render_comparison())
		var grid := GridContainer.new()
		grid.columns=1 if _small else comparison.size()
		grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation",12)
		page.add_child(grid)
		for index: int in range(comparison.size()):
			if _small and index!=mobile_comparison: continue
			var reference: String = comparison[index]
			var column: VBoxContainer = _card(grid)
			if details.has(reference): _detail_body(column,details[reference],true)
			else:
				_text(column,"正在準備 "+reference,16)
				_button(column,"讀取比較資料",func() -> void: _request_detail(reference))
	_text(page,"我的校系收藏",20)
	if favorite_rows.is_empty(): _text(page,"收藏的校系會保存在你的帳號。學校收藏仍可在大學館查看。",16,MUTED)
	for saved: Dictionary in favorite_rows:
		var card: VBoxContainer = _card(page)
		_text(card,str(saved.schoolName)+" · "+str(saved.programName),18)
		var actions := HFlowContainer.new()
		card.add_child(actions)
		var reference: String = str(saved.programRef)
		_button(actions,"移出比較" if reference in comparison else "加入比較",func() -> void: _toggle_compare(reference))
		_button(actions,"查看詳情",func() -> void: _open_detail(reference))
		_button(actions,"取消校系收藏",func() -> void: _set_favorite(reference,false,int(saved.revision)))
		_school_actions(actions,str(saved.get("universityId","")))
	if favorite_cursor!=null: _button(page,"更多校系收藏",func() -> void: controller.call("send","listFavorites",{"cursor":favorite_cursor}))

func _response(action: String, packet: Dictionary) -> void:
	if packet.type=="error":
		if packet.code in ["query-expired","cursor-expired"]: query_dirty=true
		_render_results()
		return
	match action:
		"bootstrap":
			settings_revision=int(packet.settingsRevision)
			active_report=packet.activeReport
			choices=packet.catalog
			if not keep_inputs and bootstrap_input_version==input_version: settings=packet.settings.duplicate(true)
			settings.year="115"
			keep_inputs=true
			if (settings.source=="manual" or active_report is Dictionary) and not bool(controller.call("busy","query")):
				_run_query()
			elif not comparison.is_empty(): _run_query(true)
		"listExams":
			if packet.items.is_empty() and exam_cursor==null: exams.clear()
			for item: Dictionary in packet.items: _upsert(exams,item,"id")
			exam_cursor=packet.nextCursor
		"query","page":
			if action=="query":
				result_pages.clear()
				result_pages.append(packet)
				_display_result_page(0)
			else:
				if requested_page!=result_pages.size(): return
				result_pages.append(packet)
				_display_result_page(requested_page)
				requested_page=-1
			for item: Dictionary in packet.items:
				_update_favorite(str(item.programRef),bool(item.favorite),int(item.favoriteRevision))
			var wanted: Array[String] = awaiting_details.duplicate()
			awaiting_details.clear()
			for reference: String in wanted: _request_detail(reference)
			if restored_page>result_page and next_cursor!=null:
				_change_result_page(result_page+1)
			else:
				restored_page=-1
				_restore_list_scroll.call_deferred()
		"detail":
			details[str(packet.item.programRef)]=packet
			_update_favorite(str(packet.item.programRef),bool(packet.item.favorite),int(packet.item.favoriteRevision))
			if detail_reference==str(packet.item.programRef): _show_detail(detail_reference)
		"saveSettings": settings_revision=int(packet.settingsRevision)
		"listFavorites":
			for item: Dictionary in packet.items:
				_upsert(favorite_rows,item,"programRef")
				_update_favorite(str(item.programRef),true,int(item.revision))
			favorite_cursor=packet.nextCursor
		"setFavorite":
			_update_favorite(str(packet.programRef),bool(packet.value),int(packet.revision))
			favorite_rows=favorite_rows.filter(func(item: Dictionary) -> bool: return item.programRef!=packet.programRef)
			if packet.value:
				favorite_rows.clear()
				controller.call("send","listFavorites",{"cursor":null})
	_render()

func _upsert(array: Array, item: Dictionary, key: String) -> void:
	for index: int in range(array.size()):
		if array[index][key]==item[key]: array[index]=item; return
	array.append(item)

func _update_favorite(reference: String, value: bool, revision: int) -> void:
	if revision<int(favorite_states.get(reference,{}).get("revision",-1)): return
	favorite_states[reference]={"value":value,"revision":revision}

func _restore_list_scroll() -> void:
	var desired: int=restored_scroll
	var page: int=result_page
	var generation: int=int(controller.get("generation"))
	restored_scroll=0
	await get_tree().process_frame
	if page==result_page and generation==int(controller.get("generation")): scrolls[1].scroll_vertical=desired

func _status_changed() -> void:
	if not _built: return
	status.text=str(controller.get("status"))
	status.add_theme_color_override("font_color",Color("a04045") if bool(controller.get("error")) else MUTED)

func _account_reset() -> void:
	settings=Controller.default_settings()
	settings_revision=0
	active_report=null
	exams.clear()
	exam_cursor=null
	rows.clear()
	result_packet.clear()
	next_cursor=null
	result_pages.clear()
	result_page=0
	requested_page=-1
	favorite_rows.clear()
	favorite_states.clear()
	favorite_cursor=null
	details.clear()
	comparison.clear()
	awaiting_details.clear()
	detail_reference=""
	restored_page=-1
	restored_scroll=0
	keep_inputs=false
	query_dirty=true
	if detail_overlay!=null: detail_overlay.hide()
	_render()

func _university_changed() -> void:
	_render_results()
	_render_comparison()
	if detail_overlay.visible and details.has(detail_reference): _show_detail(detail_reference)

func _manage_interest() -> void:
	if not is_instance_valid(interest_panel):
		interest_panel=InterestPanel.new()
		add_child(interest_panel)
		interest_panel.call("configure",account)
		interest_panel.connect("closed",func() -> void: shell.show(); _refresh(true))
	shell.hide()
	interest_panel.call("open_panel","high3")

func _host_closed() -> void:
	if visible: _refresh(true)

func _resize_canvas() -> void:
	var logical: Vector2=get_viewport().get_visible_rect().size
	var display_width: float=float(get_window().size.x)
	var safe: Vector4=Vector4.ZERO
	if OS.has_feature("web"):
		display_width=float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
		var values: Variant=JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.LittleWorldTouchUI?.safeArea() || [0,0,0,0])")))
		if values is Array and values.size()==4: safe=Vector4(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
	var density: float=maxf(.25,logical.x/maxf(1.0,display_width))
	scale=Vector2.ONE*density
	position=Vector2(safe.x,safe.y)*density
	size=logical/density-Vector2(safe.x+safe.z,safe.y+safe.w)
	_layout()

func _layout() -> void:
	if not _built: return
	var compact: bool=size.x<900
	var margin: float=8 if size.x<700 else 28
	var keyboard: float=maxi(0,_keyboard_height)*size.y/maxf(1,float(get_window().size.y))
	for panel: PanelContainer in [shell,detail_overlay]:
		panel.offset_left=margin
		panel.offset_top=margin
		panel.offset_right=-margin
		panel.offset_bottom=-margin-keyboard
	if compact!=_small or not is_equal_approx(size.x,_width):
		_small=compact
		_width=size.x
		_render_comparison()
