extends Control
## Pure Godot form: the account bridge only transports data, never opens a form.
signal closed

const Model = preload("res://scripts/interest_model.gd")
const Controller = preload("res://scripts/interest_controller.gd")
const INK: Color = Color("334f48")
const MUTED: Color = Color("67786e")
const SAGE: Color = Color("e4eee5")
const CREAM: Color = Color("fffaf0")
const RED: Color = Color("a33c39")
var controller: Node
var catalog: Dictionary = {}
var tabs: TabContainer
var grade_buttons: Dictionary = {}
var high3_buttons: Dictionary = {}
var high3_navigation: HFlowContainer
var history_button: Button
var last_high3_tab: int = 1
var shell: PanelContainer
var pages: Array[VBoxContainer] = []
var scrolls: Array[ScrollContainer] = []
var score_grids: Array[GridContainer] = []
var fit_grids: Array[GridContainer] = []
var inputs: Dictionary = {}
var errors: Dictionary = {}
var field_tabs: Dictionary = {}
var progress_label: Label
var status_label: Label
var draft_button: Button
var complete_button: Button
var retry_button: Button
var history_box: VBoxContainer
var dialog: ConfirmationDialog
var navigation: Callable
var save_then_navigate: bool = false
var _built: bool = false
var _layout_width: float = -1.0
var _layout_height: float = -1.0
var _keyboard_height: int = -1
var _showing_errors: bool = false
var _last_records: String = ""

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	get_viewport().size_changed.connect(_resize_canvas)
	_resize_canvas()
	mouse_filter = Control.MOUSE_FILTER_STOP
	controller = Controller.new()
	add_child(controller)
	controller.changed.connect(_state_changed)
	controller.document_loaded.connect(_document_loaded)
	controller.saved.connect(_saved)
	controller.account_reset.connect(_account_reset)
	catalog = Model.catalog()
	_build()
	_built = true
	_rebuild()
	add_child(preload("res://scripts/interest_diagnostics.gd").new())
	visible = false

func configure(account_session: Node) -> void:
	controller.call("configure",account_session)

func open_panel(stage: String = "") -> void:
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_resize_canvas()
	if stage == "high1":
		tabs.current_tab = 0
	elif stage == "high3":
		tabs.current_tab = 1
	_sync_navigation()
	_layout()
	controller.call("refresh_history")
	var first_field: String = {0:"title",1:"knowledge.k01",2:"bestFits.0.groupId"}.get(tabs.current_tab,"")
	if inputs.has(first_field) and not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		(inputs[first_field] as Control).grab_focus()

func request_close() -> void:
	_request_navigation(_close)

func _close() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		DisplayServer.virtual_keyboard_hide()
	hide()
	closed.emit()

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		request_close()

func _process(_delta: float) -> void:
	if visible:
		_layout()

func _style(color: Color, radius: int = 14, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.set_border_width_all(1)
	style.border_color = border
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style

func _build() -> void:
	var design := Theme.new()
	var weighted_font := FontVariation.new()
	var scalable_font: FontFile = preload("res://assets/fonts/NotoSansTC.ttf").duplicate() as FontFile
	scalable_font.multichannel_signed_distance_field = true
	weighted_font.base_font = scalable_font
	weighted_font.variation_opentype = {2003265652:550.0}
	design.default_font = weighted_font
	design.default_font_size = 17
	for kind: String in ["Label","Button","LineEdit","OptionButton","TabContainer","TabBar","PopupMenu"]:
		design.set_color("font_color",kind,INK)
		design.set_color("font_focus_color",kind,INK)
		design.set_color("font_hover_color",kind,INK)
		design.set_color("font_hover_pressed_color",kind,INK)
		design.set_color("font_hovered_color",kind,INK)
		design.set_color("font_pressed_color",kind,INK)
		design.set_color("font_selected_color",kind,INK)
		design.set_color("font_unselected_color",kind,MUTED)
	design.set_stylebox("normal","Button",_style(SAGE,12))
	design.set_stylebox("hover","Button",_style(Color("d6e6d6"),12))
	design.set_stylebox("pressed","Button",_style(Color("c4daca"),12))
	design.set_stylebox("disabled","Button",_style(Color("e9e8df"),12))
	design.set_stylebox("focus","Button",_style(Color.TRANSPARENT,12,Color("6c9b83")))
	design.set_stylebox("normal","LineEdit",_style(Color.WHITE,10,Color("d8dfd5")))
	design.set_stylebox("focus","LineEdit",_style(Color.WHITE,10,Color("739c86")))
	design.set_color("font_placeholder_color","LineEdit",Color("7b867d"))
	design.set_color("caret_color","LineEdit",INK)
	design.set_color("selection_color","LineEdit",Color("c2d9ce"))
	design.set_stylebox("normal","OptionButton",_style(Color.WHITE,10,Color("d8dfd5")))
	design.set_stylebox("hover","OptionButton",_style(SAGE,10))
	design.set_stylebox("pressed","OptionButton",_style(SAGE,10))
	design.set_stylebox("panel","PopupMenu",_style(CREAM,12,Color("d8dfd5")))
	design.set_stylebox("hover","PopupMenu",_style(SAGE,8))
	design.set_constant("v_separation","PopupMenu",20)
	design.set_stylebox("panel","TabContainer",_style(Color.TRANSPARENT,0))
	design.set_stylebox("tab_selected","TabContainer",_style(SAGE,10))
	design.set_stylebox("tab_unselected","TabContainer",_style(Color("f3eee4"),10))
	design.set_stylebox("tab_hovered","TabContainer",_style(Color("e9efe6"),10))
	theme = design
	var shade := ColorRect.new()
	shade.color = Color(0.12,0.20,0.17,0.64)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shell = PanelContainer.new()
	shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shell.add_theme_stylebox_override("panel",_style(CREAM,22))
	add_child(shell)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation",10)
	shell.add_child(box)
	var heading := HBoxContainer.new()
	box.add_child(heading)
	var title := _label("留一點時間，認識自己",25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_child(title)
	_button("關閉",heading,request_close)
	var subtitle_row := HBoxContainer.new()
	box.add_child(subtitle_row)
	var subtitle := _label("第一站 · 輔導室興趣量表區",15,MUTED)
	subtitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_row.add_child(subtitle)
	history_button = _button("我的紀錄",subtitle_row,func() -> void: _select_page(3))
	history_button.name = "InterestHistory"
	history_button.toggle_mode = true
	progress_label = _label("",15,MUTED)
	box.add_child(progress_label)
	var grade_navigation := HFlowContainer.new()
	grade_navigation.add_theme_constant_override("h_separation",10)
	box.add_child(grade_navigation)
	grade_buttons.high1 = _button("高一測驗資料",grade_navigation,func() -> void: _select_page(0))
	grade_buttons.high1.name = "InterestHigh1"
	grade_buttons.high3 = _button("高三測驗資料",grade_navigation,func() -> void: _select_page(last_high3_tab))
	grade_buttons.high3.name = "InterestHigh3"
	for button: Button in grade_buttons.values():
		button.toggle_mode = true
	high3_navigation = HFlowContainer.new()
	high3_navigation.add_theme_constant_override("h_separation",10)
	box.add_child(high3_navigation)
	high3_buttons.knowledge = _button("33 種知識",high3_navigation,func() -> void: _select_page(1))
	high3_buttons.knowledge.name = "InterestKnowledge"
	high3_buttons.fits = _button("適配度與 Z 分數",high3_navigation,func() -> void: _select_page(2))
	high3_buttons.fits.name = "InterestFits"
	for button: Button in high3_buttons.values():
		button.toggle_mode = true
	tabs = TabContainer.new()
	tabs.tabs_visible = false
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.clip_contents = true
	tabs.get_tab_bar().tab_alignment = TabBar.ALIGNMENT_LEFT
	tabs.get_tab_bar().scrolling_enabled = true
	box.add_child(tabs)
	for caption: String in ["高一・RIASEC","高三・33種知識","高三・適配度與Z","我的紀錄"]:
		var scroll := ScrollContainer.new()
		scroll.name = caption
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tabs.add_child(scroll)
		scrolls.append(scroll)
		var page := VBoxContainer.new()
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.add_theme_constant_override("separation",14)
		scroll.add_child(page)
		pages.append(page)
	tabs.tab_changed.connect(_tab_changed)
	_sync_navigation()
	status_label = _label("",14,MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status_label)
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",10)
	box.add_child(actions)
	draft_button = _button("儲存草稿",actions,_save_draft)
	complete_button = _button("完成並儲存",actions,_complete)
	complete_button.add_theme_stylebox_override("normal",_style(Color("f7d7bf"),12))
	retry_button = _button("重試連線",actions,func() -> void: controller.call("retry"))
	dialog = ConfirmationDialog.new()
	dialog.title = "還有尚未儲存的內容"
	dialog.borderless = true
	dialog.dialog_text = "還有尚未儲存的內容。\n要先把目前填寫的內容儲存到帳號嗎？"
	dialog.add_theme_stylebox_override("panel",_style(CREAM,16,Color("739c86")))
	dialog.get_label().autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialog.ok_button_text = "儲存草稿"
	dialog.cancel_button_text = "繼續填寫"
	var discard_button: Button = dialog.add_button("不儲存",false,"discard")
	for button: Button in [dialog.get_ok_button(),dialog.get_cancel_button(),discard_button]:
		button.custom_minimum_size.y = 44
	dialog.confirmed.connect(_save_navigation)
	dialog.canceled.connect(func() -> void: navigation = Callable())
	dialog.custom_action.connect(_dialog_action)
	add_child(dialog)

func _label(text: String, font_size: int = 17, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size",font_size)
	label.add_theme_color_override("font_color",color)
	return label

func _paragraph(parent: Control, text: String) -> void:
	var label: Label = _label(text,16,MUTED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func _button(text: String, parent: Control, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _field(parent: Control, caption: String, path: String, value: String, placeholder: String, tab_index: int, limit: int = 32, integer: bool = false) -> LineEdit:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(box)
	var label: Label = _label(caption,16)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(label)
	var field := LineEdit.new()
	field.text = value
	field.placeholder_text = placeholder
	field.max_length = limit
	field.custom_minimum_size.y = 46
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.expand_to_text_length = false
	field.virtual_keyboard_enabled = true
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER if integer else LineEdit.KEYBOARD_TYPE_DEFAULT
	field.text_changed.connect(func(text: String) -> void: _input_changed(path,text))
	field.focus_entered.connect(func() -> void: _ensure_visible_field.call_deferred(path))
	box.add_child(field)
	inputs[path] = field
	field_tabs[path] = tab_index
	_add_error(box,path)
	return field

func _add_error(parent: Control, path: String) -> void:
	var label: Label = _label("",14,RED)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.hide()
	parent.add_child(label)
	errors[path] = label

func _card(parent: Control) -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",_style(Color("f5f3e9"),14))
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation",9)
	card.add_child(content)
	return content

func _clear_page(page: Control) -> void:
	for child: Node in page.get_children():
		page.remove_child(child)
		child.queue_free()

func _document_loaded() -> void:
	_rebuild()
	if _built and tabs.current_tab == 3:
		tabs.current_tab = 0

func _rebuild() -> void:
	if not _built:
		return
	inputs.clear()
	errors.clear()
	field_tabs.clear()
	score_grids.clear()
	fit_grids.clear()
	_showing_errors = false
	for page: VBoxContainer in pages:
		_clear_page(page)
	var profile: Dictionary = controller.get("profile")
	var intro := _card(pages[0])
	_field(intro,"這份紀錄的名稱","title",str(profile.title),"例如 我的興趣探索紀錄",0,80)
	_paragraph(pages[0],"這一區記錄高一的興趣量表。請照報告填寫 RIASEC 六種類型的原始分數，每項 0–90 分，六項皆須填寫。")
	var six := GridContainer.new()
	six.columns = 3
	six.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	six.add_theme_constant_override("h_separation",12)
	six.add_theme_constant_override("v_separation",12)
	pages[0].add_child(six)
	score_grids.append(six)
	for item: Dictionary in catalog.get("riasec",[]):
		_field(_card(six),str(item.label),"riasec."+str(item.id),str(profile.riasec.get(item.id,"")),"0–90",0,32,true)
	_paragraph(pages[1],"這一區記錄高三的學系探索量表。請依報告逐項填寫「33 種知識分數」，每項 0–18 分，33 項皆須填寫，分數反映喜歡程度。")
	var knowledge := GridContainer.new()
	knowledge.columns = 3
	knowledge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	knowledge.add_theme_constant_override("h_separation",12)
	knowledge.add_theme_constant_override("v_separation",12)
	pages[1].add_child(knowledge)
	score_grids.append(knowledge)
	for item: Dictionary in catalog.get("knowledge",[]):
		_field(_card(knowledge),str(item.label),"knowledge."+str(item.id),str(profile.knowledge.get(item.id,"")),"0–18",1,32,true)
	_paragraph(pages[2],"請依高三學系探索量表填寫。「最適合」與「適合」各 25 列，可再增加；沒有的項目留白。")
	_paragraph(pages[2],"每列須填學群、學類與 Z 分數；Z 可有負號、小數或 0，程度與學類照原報告填寫。")
	var jump := HFlowContainer.new()
	pages[2].add_child(jump)
	_button("前往最適合",jump,func() -> void: _focus_field("bestFits.0.groupId"))
	_button("前往適合",jump,func() -> void: _focus_field("suitableFits.0.groupId"))
	for section: String in ["bestFits","suitableFits"]:
		var section_header := HFlowContainer.new()
		pages[2].add_child(section_header)
		section_header.add_child(_label(("最適合" if section == "bestFits" else "適合")+" · %d 列" % profile[section].size(),23))
		var current_section: String = section
		var add: Button = _button("＋ 新增一列",section_header,func() -> void: _add_row(current_section))
		add.disabled = (profile[section] as Array).size() >= Model.MAX_ROWS
		_build_fit_rows(section)
	_build_history()
	_layout_width = -1
	_layout()
	_state_changed()

func _build_fit_rows(section: String) -> void:
	var profile: Dictionary = controller.get("profile")
	var rows: Array = profile[section]
	for index: int in range(rows.size()):
		var row: Dictionary = rows[index]
		var card: VBoxContainer = _card(pages[2])
		var heading := HBoxContainer.new()
		card.add_child(heading)
		var number: Label = _label("第 %d 列" % (index+1),14,MUTED)
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		heading.add_child(number)
		var captured_index: int = index
		_button("清空",heading,func() -> void: _clear_row(section,captured_index))
		var grid := GridContainer.new()
		grid.columns = 3
		grid.add_theme_constant_override("h_separation",10)
		grid.add_theme_constant_override("v_separation",8)
		card.add_child(grid)
		fit_grids.append(grid)
		var group_box := VBoxContainer.new()
		group_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(group_box)
		group_box.add_child(_label("學群",16))
		var group := OptionButton.new()
		group.custom_minimum_size.y = 46
		group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		group.clip_text = true
		group.fit_to_longest_item = false
		group.add_item("選擇學群")
		group.set_item_metadata(0,"")
		for item: Dictionary in catalog.get("groups",[]):
			group.add_item(str(item.label))
			var position: int = group.item_count-1
			group.set_item_metadata(position,str(item.id))
			if row.groupId == item.id:
				group.select(position)
		var prefix: String = section+"."+str(index)+"."
		var path: String = prefix+"groupId"
		group.item_selected.connect(func(position: int) -> void: _input_changed(path,str(group.get_item_metadata(position))))
		group_box.add_child(group)
		inputs[path] = group
		field_tabs[path] = 2
		_add_error(group_box,path)
		_field(grid,"學類",prefix+"category",str(row.category),"照原報告填寫",2,80)
		_field(grid,"Z 分數",prefix+"z",str(row.z),"例如 -0.25",2)

func _build_history() -> void:
	_clear_page(pages[3])
	_paragraph(pages[3],"每份紀錄包含高一的 RIASEC，以及高三的 33 種知識、適配度與 Z 分數，保存在你的星途帳號。草稿可隨時接著填；完成後可選擇之後分析推薦要使用的版本。")
	var actions := HFlowContainer.new()
	pages[3].add_child(actions)
	_button("＋ 新增紀錄",actions,func() -> void: _request_navigation(func() -> void: controller.call("new_record"); tabs.current_tab = 0))
	_button("複製為新紀錄",actions,func() -> void: controller.call("duplicate_current"); tabs.current_tab = 0)
	_button("重新整理",actions,func() -> void: controller.call("refresh_history"))
	history_box = VBoxContainer.new()
	history_box.add_theme_constant_override("separation",12)
	pages[3].add_child(history_box)
	var records: Array = controller.get("records")
	if records.is_empty():
		_paragraph(history_box,"帳號還沒有可顯示的紀錄。完成填寫後，按下方按鈕即可存入帳號。")
	for entry: Dictionary in records:
		var card: VBoxContainer = _card(history_box)
		var title_text: String = str(entry.get("title","")).strip_edges()
		var title: Label = _label(title_text if not title_text.is_empty() else "未命名草稿",20)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		card.add_child(title)
		var badges: String = "已完成" if entry.get("hasCompleted",false) else "草稿"
		if entry.get("hasCompleted",false) and entry.get("hasDraft",false):
			badges += " · 有修改中的草稿"
		if str(entry.id) == str(controller.get("active_record_id")):
			badges += " · 之後分析使用中"
		_paragraph(card,badges)
		var buttons := HFlowContainer.new()
		card.add_child(buttons)
		var id: String = str(entry.id)
		_button("開啟／編輯",buttons,func() -> void: _request_navigation(func() -> void: controller.call("open_record",id)))
		if entry.get("hasCompleted",false):
			var active: Button = _button("設為之後分析使用",buttons,func() -> void: controller.call("select_active",id))
			active.disabled = id == str(controller.get("active_record_id"))
	if controller.get("next_cursor") is Dictionary:
		_button("載入更多紀錄",history_box,func() -> void: controller.call("refresh_history",true))
	_last_records = JSON.stringify([records,controller.get("active_record_id"),controller.get("next_cursor")])

func _input_changed(path: String, value: String) -> void:
	var profile: Dictionary = controller.get("profile")
	var parts: PackedStringArray = path.split(".")
	if parts.size() == 1:
		profile[path] = value
	elif parts.size() == 2:
		profile[parts[0]][parts[1]] = value
	else:
		profile[parts[0]][parts[1].to_int()][parts[2]] = value
	if errors.has(path):
		(errors[path] as Label).hide()
	controller.call("edited")

func _add_row(section: String) -> void:
	var profile: Dictionary = controller.get("profile")
	if (profile[section] as Array).size() >= Model.MAX_ROWS:
		return
	profile[section].append(Model.empty_row())
	controller.call("edited")
	var index: int = profile[section].size()-1
	_rebuild()
	tabs.current_tab = 2
	_focus_field(section+"."+str(index)+".groupId")

func _clear_row(section: String, index: int) -> void:
	var profile: Dictionary = controller.get("profile")
	profile[section][index] = Model.empty_row()
	for key: String in ["groupId","category","z"]:
		var path: String = section+"."+str(index)+"."+key
		if key == "groupId":
			(inputs[path] as OptionButton).select(0)
		else:
			(inputs[path] as LineEdit).text = ""
		(errors[path] as Label).hide()
	controller.call("edited")

func _save_draft() -> void:
	controller.call("save",false)

func _complete() -> void:
	var validation: Dictionary = Model.validate(controller.get("profile"))
	_showing_errors = not validation.is_empty()
	for path: String in errors:
		var label: Label = errors[path]
		label.text = str(validation.get(path,""))
		label.visible = validation.has(path)
	if not validation.is_empty():
		status_label.text = "還有 %d 個欄位需要確認；也可以先儲存草稿。" % validation.size()
		status_label.add_theme_color_override("font_color",RED)
		_focus_field(str(validation.keys()[0]))
		return
	controller.call("save",true)

func _focus_field(path: String) -> void:
	if not inputs.has(path):
		return
	tabs.current_tab = int(field_tabs[path])
	var field: Control = inputs[path]
	field.grab_focus.call_deferred()
	_ensure_visible_field.call_deferred(path)

func _ensure_visible_field(path: String) -> void:
	if not visible or not inputs.has(path):
		return
	var field: Control = inputs[path]
	var index: int = int(field_tabs[path])
	if is_instance_valid(field) and tabs.current_tab == index and scrolls[index].is_ancestor_of(field):
		scrolls[index].ensure_control_visible(field)

func _state_changed() -> void:
	if not _built:
		return
	var profile: Dictionary = controller.get("profile")
	var dirty: bool = bool(controller.call("is_dirty"))
	var stage_counts: Array[int] = []
	for section: String in ["riasec","knowledge"]:
		var filled: int = 0
		for value: Variant in profile[section].values():
			if not str(value).strip_edges().is_empty():
				filled += 1
		stage_counts.append(filled)
	progress_label.text = "高一 %d / 6　·　高三 %d / 33　·　共 %d / 39\n%s" % [stage_counts[0],stage_counts[1],Model.filled_count(profile),"有尚未儲存的修改" if dirty else ("帳號紀錄已儲存" if int(controller.get("revision")) > 0 else "新紀錄")]
	progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = str(controller.get("status"))
	status_label.add_theme_color_override("font_color",RED if controller.get("error") else MUTED)
	var busy: bool = controller.call("busy")
	var pending: Dictionary = controller.get("pending")
	var loading_profile: bool = str((pending.get("command",{}) as Dictionary).get("action","")) == "get"
	for control: Control in inputs.values():
		if control is LineEdit:
			(control as LineEdit).editable = not loading_profile
		elif control is OptionButton:
			(control as OptionButton).disabled = loading_profile
	draft_button.disabled = busy
	complete_button.disabled = busy
	retry_button.visible = not (controller.get("retry_command") as Dictionary).is_empty()
	retry_button.disabled = busy
	if controller.get("error"):
		save_then_navigate = false
		navigation = Callable()
	var history_signature: String = JSON.stringify([controller.get("records"),controller.get("active_record_id"),controller.get("next_cursor")])
	if history_signature != _last_records:
		_build_history()

func _tab_changed(index: int) -> void:
	if index in [1,2]:
		last_high3_tab = index
	_sync_navigation()
	if index == 3 and visible and not controller.call("busy"):
		controller.call("refresh_history")

func _select_page(index: int) -> void:
	tabs.current_tab = index
	_sync_navigation()

func _sync_navigation() -> void:
	if tabs == null:
		return
	grade_buttons.high1.set_pressed_no_signal(tabs.current_tab == 0)
	grade_buttons.high3.set_pressed_no_signal(tabs.current_tab in [1,2])
	history_button.set_pressed_no_signal(tabs.current_tab == 3)
	high3_navigation.visible = tabs.current_tab in [1,2]
	high3_buttons.knowledge.set_pressed_no_signal(tabs.current_tab == 1)
	high3_buttons.fits.set_pressed_no_signal(tabs.current_tab == 2)

func _request_navigation(action: Callable) -> void:
	if controller.call("busy"):
		status_label.text = "正在與帳號同步，請稍候；內容仍留在目前畫面。"
		return
	if controller.call("is_dirty"):
		navigation = action
		dialog.content_scale_factor = scale.x
		dialog.popup_centered(Vector2i(Vector2(minf(500,size.x-24),210)*scale.x))
	else:
		action.call()

func _save_navigation() -> void:
	save_then_navigate = true
	if not controller.call("save",false):
		save_then_navigate = false

func _saved(_action: String) -> void:
	if save_then_navigate:
		save_then_navigate = false
		if navigation.is_valid() and not controller.call("is_dirty"):
			var action: Callable = navigation
			navigation = Callable()
			action.call_deferred()

func _dialog_action(action: StringName) -> void:
	if action == &"discard":
		dialog.hide()
		controller.call("discard")
		var next: Callable = navigation
		navigation = Callable()
		if next.is_valid():
			next.call()

func _account_reset() -> void:
	navigation = Callable()
	save_then_navigate = false
	dialog.hide()
	if visible:
		_close()

func _layout() -> void:
	if not _built or not is_inside_tree():
		return
	var keyboard: int = DisplayServer.virtual_keyboard_get_height() if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD) else 0
	if is_equal_approx(_layout_width,size.x) and is_equal_approx(_layout_height,size.y) and keyboard == _keyboard_height:
		return
	_layout_width = size.x
	_layout_height = size.y
	_keyboard_height = keyboard
	var margin: float = 12.0 if size.x < 700.0 else 28.0
	var horizontal: float = maxf(margin,(size.x-1120.0)/2.0)
	shell.offset_left = horizontal
	shell.offset_right = -horizontal
	shell.offset_top = margin
	var screen_height: float = maxf(float(DisplayServer.window_get_size().y),1.0)
	var keyboard_canvas: float = keyboard * size.y/screen_height
	shell.offset_bottom = -margin-keyboard_canvas
	var columns: int = 1 if size.x < 520.0 else (2 if size.x < 850.0 else 3)
	for grid: GridContainer in score_grids:
		grid.columns = columns
	for grid: GridContainer in fit_grids:
		grid.columns = 1 if size.x < 700.0 else 3

func _resize_canvas() -> void:
	# The game uses an expanded logical canvas on phones. Size this form in
	# display pixels, as the room HUD does, so text and touch targets stay usable.
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var display_width: float = float(get_window().size.x)
	var safe: Vector4 = Vector4.ZERO
	if OS.has_feature("web"):
		display_width = float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
		var values: Variant = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.LittleWorldTouchUI?.safeArea() || [0,0,0,0])")))
		if values is Array and (values as Array).size() == 4:
			safe = Vector4(float(values[0]),float(values[1]),float(values[2]),float(values[3]))
	var density: float = maxf(.25,logical.x/maxf(1.0,display_width))
	scale = Vector2.ONE*density
	position = Vector2(safe.x,safe.y)*density
	size = logical/density-Vector2(safe.x+safe.z,safe.y+safe.w)
	_layout_width = -1
	_layout()
