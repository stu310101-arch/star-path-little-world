extends CanvasLayer
## Exploration UI. Only scene state enters this component; it never reads accounts.
signal interaction_requested
signal account_requested
signal return_requested
signal page_requested(direction: String)
signal retry_requested
signal destination_requested(zone: String)

const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const INK := Color("203e46")
const PAPER := Color("f1efdf")
const MUTED := Color("bfcfc5")
const GOLD := Color("efd7a5")
const ZONES: Array[String] = ["university", "major", "career", "high_school", "campus"]
const TITLES: Dictionary = {"university":"大學交流區", "major":"科系交流區", "career":"未來就業交流區", "high_school":"高中生發問區", "campus":"校園討論區"}
const SHORT_TITLES: Dictionary = {"university":"大學交流", "major":"科系交流", "career":"未來就業", "high_school":"高中生發問", "campus":"校園討論"}
const DESCRIPTIONS: Dictionary = {"university":"沿湖坐一坐，聊聊大學生活", "major":"穿過磚巷，找到你的學習方向", "career":"走上露臺，交換未來的想像", "high_school":"林間停一停，讓問題得到回應", "campus":"在庭院相遇，分享日常小事"}

var screen: Control
var location_card: PanelContainer
var location_number: Label
var location_title: Label
var location_description: Label
var top_actions: HBoxContainer
var guide_button: Button
var account_button: Button
var return_button: Button
var guide_panel: PanelContainer
var guide_rows: Dictionary = {}
var interaction_card: PanelContainer
var interaction_title: Label
var interaction_preview: Label
var interaction_button: Button
var key_badge: Label
var paging_row: HBoxContainer
var previous_button: Button
var next_button: Button
var refresh_button: Button
var page_label: Label
var toast_card: PanelContainer
var toast_label: Label
var toast_timer: Timer
var welcome: Label
var loading_card: PanelContainer
var loading_title: Label
var loading_description: Label
var retry_button: Button
var route_card: PanelContainer
var route_label: Label
var route_cancel: Button
var _font: FontVariation
var _state: Dictionary = {}
var _zone: String = ""
var _hub: bool = false
var _compact: bool = false
var _touch: bool = false
var _guide_open: bool = false
var _toast_error: bool = false
var _zone_tween: Tween
var _layout_queued: bool = false
var _last_compact_style: int = -1
var _last_guide_open: bool = false
var _hint_timer: Timer
var _first_ready_shown: bool = false
var _welcome_done: bool = false

func _ready() -> void:
	name = "DiscussionHUD"
	layer = 12
	_font = FontVariation.new()
	_font.base_font = FONT
	_font.variation_opentype = {2003265652:550.0}
	screen = Control.new()
	screen.name = "Screen"
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)
	_build_location()
	_build_actions()
	_build_guide()
	_build_interaction()
	_build_notices()
	for card: Control in [location_card, interaction_card, loading_card, toast_card]:
		card.minimum_size_changed.connect(_queue_layout)
	get_viewport().size_changed.connect(_resize)
	_resize()
	# This hint appears once. Idle exploration then has no bottom overlay.
	_hint_timer = Timer.new()
	_hint_timer.one_shot = true
	_hint_timer.wait_time = 12
	_hint_timer.timeout.connect(func() -> void:
		_welcome_done = true
		welcome.hide())
	add_child(_hint_timer)
	update_state({"ready":false})

func _label(value: String, font_size: int, color: Color = PAPER) -> Label:
	var result := Label.new()
	result.text = value
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.add_theme_font_override("font", _font)
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

func _style(color: Color, margin: int = 12) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.set_corner_radius_all(12)
	result.content_margin_left = margin
	result.content_margin_right = margin
	result.content_margin_top = margin
	result.content_margin_bottom = margin
	return result

func _panel(parent: Node, node_name: String, color: Color = Color("173b45f5"), margin: int = 12) -> PanelContainer:
	var result := PanelContainer.new()
	result.name = node_name
	var box := _style(color, margin)
	box.set_border_width_all(1)
	box.border_color = Color("a8c0ac30")
	box.shadow_color = Color("061a2433")
	box.shadow_size = 5
	box.shadow_offset = Vector2(0, 3)
	result.add_theme_stylebox_override("panel", box)
	result.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(result)
	return result

func _button(value: String, callback: Callable, accent: bool = false) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size.y = 44
	result.add_theme_font_override("font", _font)
	result.add_theme_font_size_override("font_size", 15)
	result.add_theme_color_override("font_color", INK if accent else PAPER)
	result.add_theme_color_override("font_hover_color", INK if accent else PAPER)
	result.add_theme_color_override("font_pressed_color", INK if accent else PAPER)
	result.add_theme_color_override("font_disabled_color", Color("9eafa8"))
	result.add_theme_stylebox_override("normal", _style(GOLD if accent else Color("244954f5"), 10))
	result.add_theme_stylebox_override("hover", _style(Color("f6e5bf") if accent else Color("32616c"), 10))
	result.add_theme_stylebox_override("pressed", _style(Color("c5d8c8") if accent else Color("39717b"), 10))
	result.add_theme_stylebox_override("disabled", _style(Color("28454bdd"), 10))
	var focus := _style(Color.TRANSPARENT, 10)
	focus.set_border_width_all(2)
	focus.border_color = GOLD
	result.add_theme_stylebox_override("focus", focus)
	result.focus_mode = Control.FOCUS_NONE
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	result.pressed.connect(callback)
	return result

func _column(parent: Node, gap: int = 6) -> VBoxContainer:
	var result := VBoxContainer.new()
	result.add_theme_constant_override("separation", gap)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func _build_location() -> void:
	location_card = _panel(screen, "Location", Color("173b45ed"), 14)
	location_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var column := _column(location_card, 2)
	location_number = _label("校園交流花園", 11, GOLD)
	column.add_child(location_number)
	location_title = _label("自由探索", 20)
	column.add_child(location_title)
	location_description = _label("五個主題，四十個相遇的地方", 12, MUTED)
	column.add_child(location_description)

func _build_actions() -> void:
	top_actions = HBoxContainer.new()
	top_actions.name = "TopActions"
	top_actions.add_theme_constant_override("separation", 6)
	screen.add_child(top_actions)
	guide_button = _button("五區導覽", toggle_guide)
	guide_button.tooltip_text = "查看五個交流區與本區留言頁"
	top_actions.add_child(guide_button)
	account_button = _button("帳號", func() -> void: account_requested.emit())
	top_actions.add_child(account_button)
	return_button = _button("返回世界", func() -> void: return_requested.emit())
	return_button.tooltip_text = "返回星途大世界（Esc）"
	top_actions.add_child(return_button)

func _build_guide() -> void:
	guide_panel = _panel(screen, "Guide")
	var scroll := ScrollContainer.new()
	scroll.name = "GuideScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	guide_panel.add_child(scroll)
	var column := _column(scroll, 6)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var heading := HBoxContainer.new()
	column.add_child(heading)
	var title := _label("慢慢走，找個話題", 18)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(title)
	var close_button := _button("收起", toggle_guide)
	close_button.add_theme_font_size_override("font_size", 13)
	heading.add_child(close_button)
	var subtitle := _label("選擇一區，沿著園徑前往", 13, MUTED)
	column.add_child(subtitle)
	for index: int in range(ZONES.size()):
		var id: String = ZONES[index]
		var row := _button("%02d   %s" % [index + 1, TITLES[id]], func() -> void: _select_destination(id))
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.tooltip_text = DESCRIPTIONS[id]
		guide_rows[id] = row
		column.add_child(row)
	var divider := HSeparator.new()
	column.add_child(divider)
	page_label = _label("本區留言 · 第 1 頁", 13, MUTED)
	column.add_child(page_label)
	paging_row = HBoxContainer.new()
	paging_row.add_theme_constant_override("separation", 6)
	column.add_child(paging_row)
	previous_button = _button("上一頁", func() -> void: page_requested.emit("previous"))
	next_button = _button("下一頁", func() -> void: page_requested.emit("next"))
	refresh_button = _button("刷新", func() -> void: page_requested.emit("refresh"))
	for control: Button in [previous_button, next_button, refresh_button]:
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		paging_row.add_child(control)
	var note := _label("每座裝置一則留言，也能回覆彼此。", 12, MUTED)
	column.add_child(note)
	guide_panel.hide()

func _build_interaction() -> void:
	interaction_card = _panel(screen, "Interaction", Color("173b45f5"), 12)
	var column := _column(interaction_card, 5)
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	column.add_child(title_row)
	interaction_title = _label("留言裝置 01", 15, GOLD)
	interaction_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(interaction_title)
	key_badge = _label("E", 15, GOLD)
	key_badge.tooltip_text = "按 E 或點擊下方按鈕"
	title_row.add_child(key_badge)
	interaction_preview = _label("這裡還空著，留下第一個想法。", 14)
	interaction_preview.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	interaction_preview.clip_text = true
	column.add_child(interaction_preview)
	interaction_button = _button("在此留言", func() -> void: interaction_requested.emit(), true)
	column.add_child(interaction_button)
	interaction_card.hide()

func _build_notices() -> void:
	welcome = _label("WASD 移動   ·   拖曳轉向   ·   走近裝置按 E 留言", 13)
	welcome.name = "WelcomeHint"
	welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	welcome.add_theme_color_override("font_shadow_color", Color("102e38"))
	welcome.add_theme_constant_override("shadow_offset_x", 1)
	welcome.add_theme_constant_override("shadow_offset_y", 1)
	screen.add_child(welcome)
	toast_card = _panel(screen, "Notice", Color("173b45fa"), 12)
	toast_label = _label("", 14)
	toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_card.add_child(toast_label)
	toast_card.hide()
	toast_timer = Timer.new()
	toast_timer.one_shot = true
	toast_timer.timeout.connect(_dismiss_notice)
	add_child(toast_timer)
	loading_card = _panel(screen, "Loading", Color("173b45fa"), 18)
	var loading_column := _column(loading_card, 8)
	loading_title = _label("正在準備交流花園…", 18, GOLD)
	loading_column.add_child(loading_title)
	loading_description = _label("稍等片刻，下一段相遇就要開始。", 14)
	loading_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loading_column.add_child(loading_description)
	retry_button = _button("重試載入", func() -> void: retry_requested.emit(), true)
	loading_column.add_child(retry_button)
	route_card = _panel(screen, "Route", Color("173b45eb"), 8)
	var route_row := HBoxContainer.new()
	route_card.add_child(route_row)
	route_label = _label("", 13, GOLD)
	route_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	route_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	route_label.clip_text = true
	route_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	route_row.add_child(route_label)
	route_cancel = _button("取消", func() -> void: destination_requested.emit(""))
	route_cancel.add_theme_font_size_override("font_size", 12)
	route_row.add_child(route_cancel)
	route_card.hide()

## ready, zone, hub, kind (post/browse/exit/empty), number, preview, occupied,
## pending, has_previous, has_next, page (zero based), error, touch,
## destination_zone, destination_distance, destination_direction (human text).
func update_state(value: Dictionary) -> void:
	if value == _state and _last_guide_open == _guide_open:
		return
	var old_touch: bool = _touch
	_state = value.duplicate()
	_last_guide_open = _guide_open
	if screen == null:
		return
	var ready: bool = bool(value.get("ready", true))
	_touch = bool(get_meta("force_touch_controls", false)) or OS.has_feature("web_mobile") or bool(value.get("touch", false))
	var zone: String = str(value.get("zone", "university"))
	if zone not in ZONES:
		zone = "university"
	var is_hub: bool = bool(value.get("hub", false))
	if zone != _zone or is_hub != _hub:
		_zone = zone
		_hub = is_hub
		_set_text(location_number, "校園交流花園  ·  探索起點" if _hub else "校園交流花園  ·  %02d / 05" % (ZONES.find(zone) + 1))
		_set_text(location_title, "中心廣場" if _hub else TITLES[zone])
		_set_text(location_description, "五區由此出發，找到想聊的話題" if _hub else DESCRIPTIONS[zone])
		for id: String in guide_rows:
			(guide_rows[id] as Button).text = "%02d   %s%s" % [ZONES.find(id) + 1, TITLES[id], "  ·  所在地" if id == zone and not _hub else ""]
		if not bool(get_meta("reduce_motion", false)):
			if _zone_tween != null and _zone_tween.is_valid():
				_zone_tween.kill()
			location_card.modulate.a = .65
			_zone_tween = create_tween()
			_zone_tween.tween_property(location_card, "modulate:a", 1.0, .24)
	var is_pending: bool = bool(value.get("pending", false))
	var kind: String = str(value.get("kind", ""))
	var occupied: bool = bool(value.get("occupied", false))
	loading_card.visible = not ready
	interaction_card.visible = ready and kind in ["post", "browse", "exit"] and not _guide_open
	if ready and not _first_ready_shown:
		_first_ready_shown = true
		_hint_timer.start()
	if interaction_card.visible:
		_welcome_done = true
	welcome.visible = not _welcome_done and not _guide_open and ready
	previous_button.disabled = is_pending or not bool(value.get("has_previous", false))
	next_button.disabled = is_pending or not bool(value.get("has_next", false))
	refresh_button.disabled = is_pending or not ready
	_set_text(refresh_button, "讀取中…" if is_pending else "刷新")
	_set_text(page_label, "%s · 第 %d 頁" % [SHORT_TITLES[zone], int(value.get("page", 0)) + 1])
	interaction_button.disabled = not ready or kind not in ["post", "browse", "exit"]
	if kind == "post":
		var status: String = "已有留言" if occupied else "讀取留言中…" if is_pending else "等待你的想法"
		_set_text(interaction_title, "留言裝置 %02d  ·  %s" % [int(value.get("number", 1)), status])
		var preview: String = str(value.get("preview", "")).strip_edges() if occupied else "每座裝置一則留言，大家都能回覆。"
		preview = preview.replace("\n", " ").replace("\r", " ").replace("\t", " ").left(120)
		_set_text(interaction_preview, "打開這則留言，加入對話。" if preview.is_empty() else preview)
		_set_text(interaction_button, "閱讀與回覆" if occupied else "開啟留言裝置" if is_pending else "在此留言")
	elif kind == "browse":
		interaction_title.text = "%s · 交流入口" % SHORT_TITLES[zone]
		interaction_preview.text = "閱讀本區的話題，或走近任何一座留言裝置。"
		interaction_button.text = "查看本區留言"
	elif kind == "exit":
		interaction_title.text = "星途大世界"
		interaction_preview.text = "帶著剛剛的想法，繼續下一段旅程。"
		interaction_button.text = "返回世界"
	_set_text(key_badge, "點擊" if _touch else "E")
	var error: String = str(value.get("error", ""))
	_set_text(loading_title, "暫時無法進入花園" if not error.is_empty() else "正在準備交流花園…")
	_set_text(loading_description, error if not error.is_empty() else str(value.get("loading_message", "稍等片刻，下一段相遇就要開始。")))
	retry_button.visible = not error.is_empty()
	var target: String = str(value.get("destination_zone", ""))
	route_card.visible = target in ZONES and ready and not _guide_open and not toast_card.visible
	if target in ZONES:
		var distance: int = maxi(0, int(value.get("destination_distance", 0)))
		var direction: String = str(value.get("destination_direction", "沿園徑前進"))
		_set_text(route_label, "%s  ·  %s  %d m" % [SHORT_TITLES[target], direction, distance])
	if _touch != old_touch:
		_queue_layout()

func _set_text(control: Control, value: String) -> void:
	if str(control.get("text")) != value:
		control.set("text", value)

func _queue_layout() -> void:
	if _layout_queued or not is_inside_tree():
		return
	_layout_queued = true
	_finish_layout.call_deferred()

func _finish_layout() -> void:
	_layout_queued = false
	_resize_cards()

func _dismiss_notice() -> void:
	toast_card.hide()
	# Restore the route after a temporary notification without polling every frame.
	var target: String = str(_state.get("destination_zone", ""))
	route_card.visible = target in ZONES and bool(_state.get("ready", true)) and not _guide_open

func show_notice(message: String, is_error: bool = false, seconds: float = 7.0) -> void:
	_toast_error = is_error
	toast_label.text = message
	toast_label.add_theme_color_override("font_color", Color("ffe0c4") if is_error else PAPER)
	toast_card.show()
	route_card.hide()
	toast_timer.start(maxf(1.0, seconds))
	_queue_layout()

func toggle_guide() -> void:
	_guide_open = not _guide_open
	guide_panel.visible = _guide_open
	guide_button.text = "收起導覽" if _guide_open else "五區導覽"
	update_state(_state)
	_queue_layout()

func close_guide() -> bool:
	if not _guide_open:
		return false
	toggle_guide()
	return true

## Compatibility aliases for scene assertions and existing access points.
## The former separate compose button is intentionally the same contextual action.
func elements() -> Dictionary:
	return {"ui_root":screen, "zone_label":location_title, "prompt":interaction_title,
		"notice":toast_label, "action_button":interaction_button,
		"compose_button":interaction_button, "previous_button":previous_button,
		"next_button":next_button, "refresh_button":refresh_button, "retry_button":retry_button}

func _select_destination(zone: String) -> void:
	destination_requested.emit(zone)
	if _guide_open:
		toggle_guide()

func _resize() -> void:
	if screen == null:
		return
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var display_width: float = float(get_window().size.x)
	if OS.has_feature("web"):
		display_width = float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
	var density: float = maxf(.25, logical.x / maxf(1, display_width))
	screen.scale = Vector2.ONE * density
	screen.size = logical / density
	_compact = screen.size.x < 640
	_touch = bool(get_meta("force_touch_controls", false)) or OS.has_feature("web_mobile") or bool(_state.get("touch", false))
	_resize_cards()

func _place(control: Control, at: Vector2, width: float, height: float = 0) -> void:
	control.position = at
	control.size = Vector2(width, maxf(height, control.get_combined_minimum_size().y))

func _resize_cards() -> void:
	if screen == null:
		return
	var width: float = screen.size.x
	var height: float = screen.size.y
	var margin: float = 12 if _compact else 20
	var card_width: float = minf(430, width - margin * 2)
	if _last_compact_style != int(_compact):
		_last_compact_style = int(_compact)
		location_description.visible = not _compact
		location_title.add_theme_font_size_override("font_size", 17 if _compact else 20)
		location_number.add_theme_font_size_override("font_size", 10 if _compact else 11)
		return_button.text = "返回" if _compact else "返回世界"
	_set_text(guide_button, ("收起" if _guide_open else "導覽") if _compact else ("收起導覽" if _guide_open else "五區導覽"))
	if _compact:
		_place(location_card, Vector2(margin, margin), width - margin * 2)
		_place(top_actions, Vector2(width - margin - 208, location_card.position.y + location_card.size.y + 8), 208)
	else:
		_place(location_card, Vector2(margin, margin), 286)
		_place(top_actions, Vector2(width - margin - 280, margin), 280)
	var bottom: float = 174 if _touch and height > 550 else 18
	var interaction_height: float = maxf(116, interaction_card.get_combined_minimum_size().y)
	_place(interaction_card, Vector2((width-card_width)/2, height-bottom-interaction_height), card_width, interaction_height)
	_place(welcome, Vector2(margin, height-bottom-24), width-margin*2, 24)
	welcome.text = "拖曳轉向 · 走近裝置即可點擊留言" if _touch else "WASD 移動  ·  拖曳轉向  ·  走近裝置按 E 留言"
	var guide_width: float = minf(330, width-margin*2)
	var guide_top: float = top_actions.position.y + top_actions.size.y + 8
	if width-margin-guide_width < location_card.position.x+location_card.size.x:
		guide_top = maxf(guide_top, location_card.position.y+location_card.size.y+8)
	var notice_space: float = maxf(64, toast_card.get_combined_minimum_size().y)+8 if toast_card.visible and _compact else 0
	_place(guide_panel, Vector2(width-margin-guide_width, guide_top), guide_width, minf(472, maxf(64, height-guide_top-margin-notice_space)))
	var toast_y: float = maxf(location_card.position.y + location_card.size.y + 12, top_actions.position.y + top_actions.size.y + 12)
	if _guide_open and _compact:
		toast_y = guide_panel.position.y + guide_panel.size.y + 8
	_place(toast_card, Vector2((width-card_width)/2, toast_y), card_width)
	_place(loading_card, Vector2((width-card_width)/2, height*.43), card_width)
	_place(route_card, Vector2(margin, top_actions.position.y + top_actions.size.y + 8 if _compact else location_card.position.y+location_card.size.y+10), minf(350, width-margin*2))
