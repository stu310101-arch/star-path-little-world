extends CanvasLayer

signal travel_requested(id: String)
signal region_requested(region: String)
signal return_requested
signal atrium_requested
signal interact_requested
signal retry_requested
signal modal_changed(open: bool)
signal inspect_requested(id: String)
signal inspection_closed
signal inspection_zoomed(amount: float)
signal inspection_reset

const Catalog = preload("res://scripts/university_catalog.gd")
const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const INK: Color = Color("234641")
const MUTED: Color = Color("62766c")
const PAPER: Color = Color("f7f4e9")

var catalog: RefCounted
var root: Control
var overlay: ColorRect
var modal: PanelContainer
var content: VBoxContainer
var header_title: Label
var header_subtitle: Label
var status_label: Label
var action_button: Button
var retry_button: Button
var modal_title: Label
var modal_subtitle: Label
var modal_actions: HBoxContainer
var body: VBoxContainer
var body_scroll: ScrollContainer
var results: VBoxContainer
var results_label: Label
var search_box: LineEdit
var region_filter: OptionButton
var mode_filter: OptionButton
var favorite_button: Button
var tabs: HFlowContainer
var school: Dictionary = {}
var selected_section: int = 0
var directory_mode: String = "all"
var current_panel: String = ""
var hud_margin: MarginContainer
var modal_margin: MarginContainer
var toolbar: HFlowContainer
var read_body: VBoxContainer
var toast: Label
var ui_font: FontVariation
var mobile: bool = preload("res://scripts/graphics_settings.gd").is_mobile_web()
var return_label: String = ""
var inspection_margin: MarginContainer
var inspection_title: Label
var inspection_features: Label

func configure(data: RefCounted) -> void:
	catalog = data
	ui_font = FontVariation.new()
	ui_font.base_font = FONT
	ui_font.variation_opentype = {2003265652: 550.0}
	_build()
	catalog.connect("progress_changed",_cloud_progress_changed)

func _cloud_progress_changed() -> void:
	if current_panel=="directory" and is_instance_valid(results):
		_refresh_results()
	elif current_panel=="school" and is_instance_valid(favorite_button):
		_update_favorite()

func _style(color: Color, radius: int = 12, padding: int = 14) -> StyleBoxFlat:
	var value: StyleBoxFlat = StyleBoxFlat.new()
	value.bg_color = color
	value.set_corner_radius_all(radius)
	value.content_margin_left = padding
	value.content_margin_right = padding
	value.content_margin_top = padding
	value.content_margin_bottom = padding
	return value

func _label(text_value: String, size: int = 20, color: Color = INK) -> Label:
	var node: Label = Label.new()
	node.text = text_value
	node.add_theme_font_override("font", ui_font)
	node.add_theme_font_size_override("font_size", roundi(size * 1.4) if mobile else size)
	node.add_theme_color_override("font_color", color)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return node

func _paragraph(parent: Node, text_value: String, size: int = 22, color: Color = INK) -> Label:
	var node: Label = _label(text_value, size, color)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func _button(text_value: String, callback: Callable, dark: bool = false) -> Button:
	var node: Button = Button.new()
	node.text = text_value
	node.custom_minimum_size.y = 84 if mobile else 48
	node.add_theme_font_override("font", ui_font)
	node.add_theme_font_size_override("font_size", 29 if mobile else 18)
	node.add_theme_color_override("font_color", PAPER if dark else INK)
	node.add_theme_color_override("font_hover_color", PAPER if dark else INK)
	node.add_theme_color_override("font_pressed_color", PAPER if dark else INK)
	node.add_theme_stylebox_override("normal", _style(INK if dark else Color("e8ecdf"), 10, 12))
	node.add_theme_stylebox_override("hover", _style(Color("34645a") if dark else Color("d9e5d5"), 10, 12))
	node.add_theme_stylebox_override("pressed", _style(Color("497767") if dark else Color("cbdcc8"), 10, 12))
	var focus: StyleBoxFlat = _style(Color(0, 0, 0, 0), 10, 0)
	focus.border_color = Color("c8964d")
	focus.set_border_width_all(3)
	node.add_theme_stylebox_override("focus", focus)
	node.pressed.connect(callback)
	return node

func _clear(node: Node) -> void:
	for child: Node in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _build() -> void:
	name = "UniversityHUD"
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var theme: Theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 30 if mobile else 20
	root.theme = theme
	hud_margin = MarginContainer.new()
	root.add_child(hud_margin)
	hud_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		hud_margin.add_theme_constant_override("margin_" + side, 24)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 12)
	hud_margin.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	column.add_child(top)
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _style(Color("183b31f2"), 16, 18))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(badge)
	var title_column: VBoxContainer = VBoxContainer.new()
	badge.add_child(title_column)
	title_column.add_child(_label("C A M P U S   A T L A S", 12, Color("dfb46e")))
	header_title = _label("大學館", 27, PAPER)
	title_column.add_child(header_title)
	header_subtitle = _label("在一段散步裡，遇見未來的日常。", 15, Color("ccd8c1"))
	title_column.add_child(header_subtitle)
	toolbar = HFlowContainer.new()
	toolbar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.alignment = FlowContainer.ALIGNMENT_END
	toolbar.add_theme_constant_override("h_separation", 8)
	toolbar.add_theme_constant_override("v_separation", 8)
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(toolbar)
	var map_button: Button = _button("導覽" if mobile else "導覽地圖  M", open_directory.bind("all"))
	map_button.name = "OpenMap"
	toolbar.add_child(map_button)
	var journal_button: Button = _button("收藏" if mobile else "收藏手冊  J", open_directory.bind("favorites"))
	journal_button.name = "OpenJournal"
	toolbar.add_child(journal_button)
	var atrium_button: Button = _button("中庭", func() -> void: atrium_requested.emit())
	atrium_button.name = "ReturnAtrium"
	toolbar.add_child(atrium_button)
	var world_button: Button = _button(return_label if not return_label.is_empty() else ("返回" if mobile else "返回世界"), func() -> void: return_requested.emit())
	world_button.name = "ReturnWorld"
	toolbar.add_child(world_button)
	toast = _label("", 18, Color("f7f4e9"))
	toast.add_theme_color_override("font_shadow_color", Color("234641"))
	toast.add_theme_constant_override("shadow_offset_x", 1)
	toast.add_theme_constant_override("shadow_offset_y", 1)
	column.add_child(toast)
	var spacer: Control = Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 12)
	column.add_child(bottom)
	var status_panel: PanelContainer = PanelContainer.new()
	status_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_panel.add_theme_stylebox_override("panel", _style(Color("234641ec"), 14, 14))
	status_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(status_panel)
	status_label = _label("正在準備大學館…", 18, PAPER)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_panel.add_child(status_label)
	retry_button = _button("重試載入", func() -> void: retry_requested.emit())
	retry_button.name = "RetryHall"
	retry_button.visible = false
	bottom.add_child(retry_button)
	action_button = _button("走近展位探索", func() -> void: interact_requested.emit(), true)
	action_button.name = "InteractExhibit"
	action_button.custom_minimum_size.x = 205
	action_button.disabled = true
	bottom.add_child(action_button)
	overlay = ColorRect.new()
	overlay.name = "ReaderOverlay"
	overlay.color = Color("142d28a8")
	root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	modal_margin = MarginContainer.new()
	overlay.add_child(modal_margin)
	modal_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal = PanelContainer.new()
	modal.add_theme_stylebox_override("panel", _style(PAPER, 20, 24))
	modal_margin.add_child(modal)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	modal.add_child(content)
	var modal_heading: HBoxContainer = HBoxContainer.new()
	content.add_child(modal_heading)
	modal_title = _label("導覽地圖", 30)
	modal_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	modal_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	modal_heading.add_child(modal_title)
	var close: Button = _button("關閉" if mobile else "關閉  Esc", close_panel)
	close.name = "ClosePanel"
	modal_heading.add_child(close)
	modal_subtitle = _label("", 16, MUTED)
	modal_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(modal_subtitle)
	modal_actions = HBoxContainer.new()
	content.add_child(modal_actions)
	body_scroll = ScrollContainer.new()
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.add_child(body_scroll)
	body = VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	body_scroll.add_child(body)
	root.resized.connect(_resize)
	_build_inspection_controls()
	_resize()

func _build_inspection_controls() -> void:
	inspection_margin = MarginContainer.new()
	root.add_child(inspection_margin)
	inspection_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	inspection_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["left", "right", "top", "bottom"]:
		inspection_margin.add_theme_constant_override("margin_" + side, 24)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inspection_margin.add_child(column)
	var heading: HBoxContainer = HBoxContainer.new()
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(heading)
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", _style(Color("183b31f2"), 12, 16))
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(badge)
	inspection_title = _label("", 24, PAPER)
	badge.add_child(inspection_title)
	var spacer: Control = Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var tray: PanelContainer = PanelContainer.new()
	tray.add_theme_stylebox_override("panel", _style(Color("183b31f2"), 12, 14))
	tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(tray)
	var tray_column: VBoxContainer = VBoxContainer.new()
	tray_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tray.add_child(tray_column)
	inspection_features = _label("", 17, Color("e6d5af"))
	inspection_features.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tray_column.add_child(inspection_features)
	var hint: Label = _label("拖曳查看角度 · 放大觀察細節 · 藝術化縮景", 17, PAPER)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tray_column.add_child(hint)
	var actions: HFlowContainer = HFlowContainer.new()
	actions.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_theme_constant_override("h_separation", 10)
	tray_column.add_child(actions)
	for descriptor: Dictionary in [
		{"name":"InspectZoomIn", "text":"＋ 放大", "callback":func() -> void: inspection_zoomed.emit(-.35)},
		{"name":"InspectZoomOut", "text":"－ 縮小", "callback":func() -> void: inspection_zoomed.emit(.35)},
		{"name":"InspectReset", "text":"重設視角", "callback":func() -> void: inspection_reset.emit()},
		{"name":"InspectClose", "text":"返回展廊" if mobile else "返回展廊  Esc", "callback":func() -> void: inspection_closed.emit()}
	]:
		var button: Button = _button(str(descriptor.text), descriptor.callback)
		button.name = str(descriptor.name)
		actions.add_child(button)
	inspection_margin.hide()

func set_inspection(entry: Dictionary = {}) -> void:
	var active: bool = not entry.is_empty()
	inspection_margin.visible = active
	hud_margin.visible = not active
	if active:
		current_panel = "model"
		inspection_title.text = str(entry.name) + " · 模型近觀"
		var features: PackedStringArray = []
		for module: Dictionary in entry.get("art_profile", {}).get("modules", []):
			features.append(str(module.get("label", "")))
		inspection_features.text = "展示線索：" + " · ".join(features)
	else:
		if current_panel == "model":
			current_panel = ""

func _inspect_school(id: String) -> void:
	close_panel()
	inspect_requested.emit(id)

func _resize() -> void:
	if root == null:
		return
	var size: Vector2 = root.size
	var margin_x: int = int(maxf(16.0, (size.x - 1160.0) * .5))
	var margin_y: int = 24 if size.y >= 650 else 12
	modal_margin.add_theme_constant_override("margin_left", margin_x)
	modal_margin.add_theme_constant_override("margin_right", margin_x)
	modal_margin.add_theme_constant_override("margin_top", margin_y)
	modal_margin.add_theme_constant_override("margin_bottom", margin_y)
	header_subtitle.visible = not mobile and size.x >= 950
	header_title.add_theme_font_size_override("font_size", 32 if mobile else (27 if size.x >= 950 else 21))

func is_open() -> bool:
	return overlay != null and overlay.visible

func close_panel() -> void:
	for filter: OptionButton in [region_filter, mode_filter]:
		if is_instance_valid(filter):
			filter.get_popup().hide()
	overlay.hide()
	current_panel = ""
	modal_changed.emit(false)

func _open(kind: String) -> void:
	current_panel = kind
	_clear(body)
	_clear(modal_actions)
	search_box = null
	region_filter = null
	mode_filter = null
	results = null
	favorite_button = null
	overlay.show()
	body_scroll.scroll_vertical = 0
	modal_changed.emit(true)

func set_status(message: String, action: String = "", retry: bool = false) -> void:
	status_label.text = message
	action_button.text = action if not action.is_empty() else "走近展位探索"
	action_button.disabled = action.is_empty()
	retry_button.visible = retry
	toast.text = str(catalog.save_error)

func set_place(region: String, page: int = 0) -> void:
	header_title.text = "大學館" if region.is_empty() else Catalog.region_label(region) + "展廊  %02d" % (page + 1)
	header_subtitle.text = "已探索 %d / 138  ·  收藏 %d" % [catalog.visited.size(), catalog.favorites.size()]

func open_directory(mode: String = "all") -> void:
	directory_mode = mode
	_open("directory")
	modal_title.text = "我的收藏手冊" if mode == "favorites" else "臺灣校園・導覽地圖"
	modal_subtitle.text = "138 個探索條目 · 已探索 %d · 收藏 %d   |   資料版本 %s" % [catalog.visited.size(), catalog.favorites.size(), catalog.source_date]
	if is_instance_valid(catalog.get("cloud")):
		body.add_child(_button("重新同步探索紀錄",func() -> void: catalog.call("refresh_cloud")))
		if bool(catalog.call("has_legacy_progress")):
			body.add_child(_button("將此裝置舊探索紀錄匯入目前帳號",func() -> void: catalog.call("import_legacy_progress")))
	var regions: HFlowContainer = HFlowContainer.new()
	regions.add_theme_constant_override("h_separation", 8)
	regions.add_theme_constant_override("v_separation", 8)
	body.add_child(regions)
	for region: String in Catalog.REGION_IDS:
		var button: Button = _button("%s  %d 條目 →" % [Catalog.region_label(region), catalog.region_entries(region).size()], _go_region.bind(region))
		button.name = "Region_" + region
		regions.add_child(button)
	var filters: HBoxContainer = HBoxContainer.new()
	filters.add_theme_constant_override("separation", 10)
	body.add_child(filters)
	search_box = LineEdit.new()
	search_box.name = "SchoolSearch"
	search_box.placeholder_text = "搜尋校名、簡稱、校區或特色…"
	search_box.custom_minimum_size.y = 84 if mobile else 48
	search_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search_box.add_theme_stylebox_override("normal", _style(Color("ffffff"), 10, 12))
	search_box.text_changed.connect(func(_value: String) -> void: _refresh_results())
	filters.add_child(search_box)
	region_filter = OptionButton.new()
	region_filter.name = "RegionFilter"
	region_filter.custom_minimum_size = Vector2(185, 84) if mobile else Vector2(140, 48)
	region_filter.add_item("全部地區")
	for region: String in Catalog.REGION_IDS:
		region_filter.add_item(Catalog.region_label(region))
	region_filter.item_selected.connect(func(_index: int) -> void: _refresh_results())
	filters.add_child(region_filter)
	mode_filter = OptionButton.new()
	mode_filter.name = "ProgressFilter"
	mode_filter.custom_minimum_size = Vector2(175, 84) if mobile else Vector2(132, 48)
	for label_value: String in ["全部學校", "我的收藏", "已探索"]:
		mode_filter.add_item(label_value)
	mode_filter.select(1 if mode == "favorites" else 0)
	mode_filter.item_selected.connect(func(_index: int) -> void: _refresh_results())
	filters.add_child(mode_filter)
	results_label = _label("", 16, MUTED)
	body.add_child(results_label)
	results = VBoxContainer.new()
	results.add_theme_constant_override("separation", 10)
	body.add_child(results)
	_refresh_results()

func _refresh_results() -> void:
	_clear(results)
	var region: String = "" if region_filter.selected == 0 else Catalog.REGION_IDS[region_filter.selected - 1]
	var modes: Array[String] = ["all", "favorites", "visited"]
	var list: Array[Dictionary] = catalog.search(search_box.text, region, modes[mode_filter.selected])
	results_label.text = "%d 個條目 · 點「前往展位」開始探索" % list.size()
	if list.is_empty():
		_paragraph(results, "還沒有收藏的學校。走近展位，將喜歡的校園加入手冊。" if mode_filter.selected == 1 and search_box.text.is_empty() else "找不到符合的學校，試試簡稱或切換地區。", 21, MUTED)
	for entry: Dictionary in list:
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", _style(Color("ffffff"), 12, 16))
		results.add_child(card)
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		card.add_child(row)
		var copy: VBoxContainer = VBoxContainer.new()
		copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(copy)
		var explored: String = "  ·  已探索" if catalog.visited.has(str(entry.id)) else ""
		_paragraph(copy, "%s  %s" % [entry.id, entry.name], 22)
		_paragraph(copy, str(entry.summary), 18, MUTED)
		_paragraph(copy, Catalog.region_label(str(entry.region)) + "  /  " + " · ".join(entry.get("tags", [])) + explored, 14, MUTED)
		var actions: VBoxContainer = VBoxContainer.new()
		row.add_child(actions)
		var go: Button = _button("前往展位 →", _go_school.bind(str(entry.id)), true)
		go.name = "Travel_" + str(entry.id)
		actions.add_child(go)
		var collect: Button = _button("已收藏" if catalog.favorites.has(str(entry.id)) else "＋ 收藏", _toggle_directory_favorite.bind(str(entry.id)))
		collect.name = "Favorite_" + str(entry.id)
		actions.add_child(collect)

func _toggle_directory_favorite(id: String) -> void:
	catalog.toggle_favorite(id)
	_refresh_results()
	modal_subtitle.text = "138 個探索條目 · 已探索 %d · 收藏 %d   |   資料版本 %s" % [catalog.visited.size(), catalog.favorites.size(), catalog.source_date]

func _go_school(id: String) -> void:
	close_panel()
	travel_requested.emit(id)

func _go_region(region: String) -> void:
	close_panel()
	region_requested.emit(region)

func open_school(entry: Dictionary, section: int = -1) -> void:
	school = entry
	selected_section = section + 1
	catalog.visit(str(entry.id))
	_open("school")
	modal_title.text = str(entry.name)
	modal_subtitle.text = "%s展區  ·  %s  ·  資料版本 %s" % [Catalog.region_label(str(entry.region)), " · ".join(entry.get("tags", [])), catalog.source_date]
	if str(entry.id) in ["070", "071", "072"]:
		modal_subtitle.text += "  ·  同屬國防大學"
	favorite_button = _button("", _toggle_school_favorite, true)
	favorite_button.name = "CollectSchool"
	modal_actions.add_child(favorite_button)
	modal_actions.add_child(_button("前往此校展位", _go_school.bind(str(entry.id))))
	_update_favorite()
	tabs = HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	body.add_child(tabs)
	var names: Array[String] = ["校園印象"]
	names.append_array(Catalog.SECTION_NAMES)
	names.append("資料來源")
	for index: int in range(names.size()):
		var tab: Button = _button(names[index], _select_section.bind(index), index == selected_section)
		tab.name = "Section_%d" % index
		tabs.add_child(tab)
	read_body = VBoxContainer.new()
	read_body.add_theme_constant_override("separation", 18)
	body.add_child(read_body)
	_show_section()

func _toggle_school_favorite() -> void:
	catalog.toggle_favorite(str(school.id))
	_update_favorite()

func _update_favorite() -> void:
	favorite_button.text = "已收藏・點此取消" if catalog.favorites.has(str(school.id)) else "＋ 加入我的收藏"

func _select_section(index: int) -> void:
	selected_section = index
	for child: Node in tabs.get_children():
		var button: Button = child as Button
		var active: bool = child.get_index() == index
		button.add_theme_stylebox_override("normal", _style(INK if active else Color("e8ecdf"), 10, 12))
		button.add_theme_color_override("font_color", PAPER if active else INK)
	_show_section()
	body_scroll.scroll_vertical = 0

func _show_section() -> void:
	_clear(read_body)
	if selected_section == 0:
		_paragraph(read_body, str(school.summary), 29)
		var inspect: Button = _button("近看校園模型 →", _inspect_school.bind(str(school.id)), true)
		inspect.name = "InspectSchool"
		read_body.add_child(inspect)
		var research: Dictionary = school.get("research_update", {})
		if not research.is_empty():
			_paragraph(read_body, "短版介紹含官方補充 · " + str(research.reviewed_on) + " 查閱", 16, MUTED)
		_paragraph(read_body, "從這三個角度認識校園", 17, MUTED)
		for index: int in range(school.get("highlights", []).size()):
			_paragraph(read_body, "%02d   %s" % [index + 1, school.highlights[index]], 23)
		_paragraph(read_body, "校區與生活範圍", 17, MUTED)
		_paragraph(read_body, str(school.get("campus_info", "")), 21)
		_paragraph(read_body, "展位線索 · " + " · ".join(school.get("diorama", {}).get("features", [])), 17, MUTED)
		var art_profile: Dictionary = school.get("art_profile", {})
		var representation: String = str(art_profile.get("representation_note", "呈現校內、周邊生活圈與學習特色的藝術化縮景，非精確校園建築模型。"))
		_paragraph(read_body, representation + "選擇上方頁籤，閱讀完整介紹與來源。", 16, MUTED)
	elif selected_section <= 5:
		var key: String = Catalog.SECTION_IDS[selected_section - 1]
		_paragraph(read_body, Catalog.SECTION_NAMES[selected_section - 1], 27)
		if key == "reviews":
			var note: PanelContainer = PanelContainer.new()
			note.add_theme_stylebox_override("panel", _style(Color("e6eadb"), 12, 16))
			read_body.add_child(note)
			_paragraph(note, "學生經驗保留原文的年代、校區與個人情境；不同人的感受不代表全校一致。", 18, MUTED)
		_paragraph(read_body, str(school.sections[key]), 23)
		if key == "reviews":
			var student_sources: Array[Dictionary] = []
			for source: Dictionary in school.get("sources", []):
				var url: String = str(source.get("url", ""))
				if url.begins_with("https://www.dcard.tw/") or url.begins_with("https://www.ptt.cc/"):
					student_sources.append(source)
			if not student_sources.is_empty():
				_paragraph(read_body, "閱讀學生原文與討論", 20)
				_source_links(student_sources)
	else:
		_paragraph(read_body, "原始資料與延伸閱讀", 27)
		var research: Dictionary = school.get("research_update", {})
		if not research.is_empty():
			_paragraph(read_body, "官方補充 · " + str(research.reviewed_on) + " 查閱", 21)
			_paragraph(read_body, str(research.get("note", "")), 17, MUTED)
			_source_links(research.get("sources", []))
			_paragraph(read_body, "參考文件所列來源", 21)
		_paragraph(read_body, "整理文件：2026-10-09。以下連結由原始資料提供，點選後於瀏覽器開啟。", 17, MUTED)
		_source_links(school.get("sources", []))
		_paragraph(read_body, "名冊及整理說明", 20)
		_paragraph(read_body, str(catalog.source_note), 16, MUTED)

func _source_links(sources: Array) -> void:
	for source: Dictionary in sources:
		var title_value: String = str(source.get("title", "資料來源"))
		var url: String = str(source.get("url", ""))
		var link: Button = _button(title_value + "  ↗", _open_source.bind(url))
		link.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		link.alignment = HORIZONTAL_ALIGNMENT_LEFT
		link.tooltip_text = url
		read_body.add_child(link)
		var note_value: String = str(source.get("note", ""))
		if not note_value.is_empty():
			_paragraph(read_body, note_value, 16, MUTED)

func _open_source(url: String) -> void:
	if not (url.begins_with("https://") or url.begins_with("http://")):
		return
	if OS.has_feature("web"):
		JavaScriptBridge.eval("(() => { const w = window.open(" + JSON.stringify(url) + ", '_blank'); if (w) w.opener = null; })()")
	else:
		OS.shell_open(url)

func debug_buttons() -> Dictionary:
	var output: Dictionary = {}
	for node: Node in root.find_children("*", "Button", true, false):
		var button: Button = node as Button
		if button.is_visible_in_tree():
			var rect: Rect2 = button.get_global_rect()
			var visible_center: bool = Rect2(Vector2.ZERO, root.size).has_point(rect.get_center())
			var ancestor: Node = button.get_parent()
			while ancestor != null:
				if ancestor is Control and (ancestor as Control).clip_contents:
					visible_center = visible_center and (ancestor as Control).get_global_rect().has_point(rect.get_center())
				ancestor = ancestor.get_parent()
			output[str(button.name)] = {"text":button.text, "rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "disabled":button.disabled, "visible":visible_center}
	return output

func debug_controls() -> Dictionary:
	var output: Dictionary = {}
	for control: Control in [search_box, region_filter, mode_filter]:
		if not is_instance_valid(control) or not control.is_visible_in_tree():
			continue
		var rect: Rect2 = control.get_global_rect()
		var info: Dictionary = {"rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y]}
		if control is LineEdit:
			info["text"] = (control as LineEdit).text
		if control is OptionButton:
			info["selected"] = (control as OptionButton).selected
		output[str(control.name)] = info
	return output
