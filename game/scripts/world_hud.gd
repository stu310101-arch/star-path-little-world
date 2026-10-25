extends CanvasLayer

const MinimapScript = preload("res://scripts/world_minimap.gd")
const FullMapScript = preload("res://scripts/world_full_map.gd")
const GraphicsSettingsScript = preload("res://scripts/graphics_settings.gd")
const InterestPanelScript = preload("res://scripts/interest_panel.gd")

var world: Node3D
var view_button: Button
var mode_label: Label
var prompt_label: Label
var rest_button: Button
var modal: CenterContainer
var panel_title: Label
var panel_body: Label
var station_buttons: Array[Button] = []
var overview_controls: Array[Control] = []
var sidebar: VBoxContainer
var destination_card: PanelContainer
var destination_toggle: Button
var last_overview: bool = true
var minimap: Control
var full_map_overlay: Control
var full_map_content: Control
var full_map: Control
var full_map_close: Button
var _map_previous_controls: bool = false
var _map_previous_paused: bool = false
var _map_browser_window: JavaScriptObject
var _map_pop_callback: JavaScriptObject
var _map_history_active: bool = false
var _map_history_closing: bool = false
var music_button: Button
var music_slider: HSlider
var music_title: Label
var music_percent: Label
var graphics_settings: Node
var settings_button: Button
var interest_settings_button: Button
var interest_panel: Control
var settings_overlay: Control
var settings_panel: PanelContainer
var settings_scroll: ScrollContainer
var settings_viewport: Viewport
var msaa_button: Button
var frame_buttons: Array[Button] = []
var settings_status: Label
var settings_performance: Label
var _settings_refresh_clock: float = 0.0
var _settings_previous_controls: bool = false
var preparation_overlay: CenterContainer
var preparation_label: Label
var preparation_retry: Button
var background_download_label: Label
var background_download_retry: Button
var quality_buttons: Array[Button] = []
var font: Font = preload("res://assets/fonts/NotoSansTC.ttf")
var ink: Color = Color("203e46")
var compact_hud: bool = false
var compact_menu: Control
var compact_menu_button: Button
var compact_start: Button
var compact_menu_close: Button
var compact_map_card: PanelContainer
var _compact_previous_controls: bool = false
var _compact_previous_paused: bool = false
var _compact_touch_overview: int = -1
var account_button: Button
var scores_button: Button
var sign_out_button: Button
var account_status: Label
var account_controls: VBoxContainer
var _account_previous_visible: bool = true

func label(text: String, size: int = 18, color: Color = Color("203e46")) -> Label:
	var node: Label = Label.new()
	node.text = text
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	if color.r > 0.6 and color.g > 0.6:
		node.add_theme_color_override("font_shadow_color", Color(0.04,0.12,0.14,0.95))
		node.add_theme_constant_override("shadow_offset_x", 1)
		node.add_theme_constant_override("shadow_offset_y", 2)
	return node

func style(color: Color, corner: int = 16) -> StyleBoxFlat:
	var box: StyleBoxFlat = StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(corner)
	box.content_margin_left = 20
	box.content_margin_right = 20
	box.content_margin_top = 12
	box.content_margin_bottom = 12
	return box

func button(text: String, accent: bool = false) -> Button:
	var node: Button = Button.new()
	node.text = text
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.focus_mode = Control.FOCUS_NONE
	node.add_theme_font_override("font", font)
	node.add_theme_font_size_override("font_size", 17)
	node.add_theme_color_override("font_color", ink)
	node.add_theme_color_override("font_hover_color", ink)
	node.add_theme_color_override("font_pressed_color", ink)
	node.add_theme_color_override("font_focus_color", ink)
	node.add_theme_color_override("font_hover_pressed_color", ink)
	node.add_theme_stylebox_override("normal", style(Color("efd7a5") if accent else Color("edf1e9"), 12))
	node.add_theme_stylebox_override("hover", style(Color("f5e4bf") if accent else Color("d7e6db"), 12))
	node.add_theme_stylebox_override("pressed", style(Color("c3d7cb"), 12))
	return node

func _ready() -> void:
	compact_hud = bool(get_meta("force_compact_hud", false)) or GraphicsSettingsScript.is_mobile_web()
	if OS.has_feature("web"):
		compact_hud = compact_hud or bool(JavaScriptBridge.eval("new URLSearchParams(location.search).get('touch') === '1'"))
	graphics_settings = GraphicsSettingsScript.new() as Node
	graphics_settings.name = "GraphicsSettings"
	add_child(graphics_settings)
	var weighted_font: FontVariation = FontVariation.new()
	if compact_hud:
		# A bitmap font is magnified before the logical canvas is reduced on a
		# phone. A private MSDF instance keeps glyph edges sharp at any density.
		var scalable_font: FontFile = font.duplicate() as FontFile
		scalable_font.multichannel_signed_distance_field = true
		scalable_font.fallbacks = [font]
		weighted_font.base_font = scalable_font
	else:
		weighted_font.base_font = font
	weighted_font.variation_opentype = {2003265652:550.0}
	font = weighted_font
	name = "WorldHUD"
	var screen: Control = Control.new()
	screen.name = "Screen"
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme: Theme = Theme.new()
	ui_theme.default_font = font
	ui_theme.default_font_size = 17
	var focus: StyleBoxFlat = style(Color(0,0,0,0),12)
	focus.set_border_width_all(2)
	focus.border_color = Color("edcb82")
	ui_theme.set_stylebox("focus","Button",focus)
	screen.theme = ui_theme
	add_child(screen)
	var margin: MarginContainer = MarginContainer.new()
	margin.name = "Margin"
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(margin)
	var column: VBoxContainer = VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 22)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)
	var top: HBoxContainer = HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(top)
	var brand: VBoxContainer = VBoxContainer.new()
	top.add_child(brand)
	brand.add_child(label("星途", 38, Color("f8eed7")))
	brand.add_child(label("L I T T L E   W O R L D", 12, Color("bfd3d5")))
	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)
	var music_controls: VBoxContainer = VBoxContainer.new()
	music_controls.name = "MusicControls"
	music_controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_controls.add_theme_constant_override("separation", 3)
	top.add_child(music_controls)
	var music_row: HBoxContainer = HBoxContainer.new()
	music_row.add_theme_constant_override("separation", 10)
	music_controls.add_child(music_row)
	music_button = button("音樂：開")
	music_button.name = "MusicMute"
	music_button.add_theme_font_size_override("font_size", 14)
	music_button.tooltip_text = "開啟／靜音背景音樂"
	music_button.pressed.connect(_activate_music_button)
	music_row.add_child(music_button)
	music_slider = HSlider.new()
	music_slider.name = "MusicVolume"
	music_slider.custom_minimum_size = Vector2(96, 24)
	music_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_slider.min_value = 0.0
	music_slider.max_value = 1.0
	music_slider.step = 0.01
	music_slider.focus_mode = Control.FOCUS_NONE
	music_slider.tooltip_text = "背景音樂音量"
	music_slider.value_changed.connect(func(value: float) -> void: world.get("music").call("set_music_volume", value))
	music_row.add_child(music_slider)
	music_percent = label("40%", 13, Color("e6eada"))
	music_percent.custom_minimum_size.x = 36
	music_percent.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	music_row.add_child(music_percent)
	music_title = label("點擊畫面播放音樂", 12, Color("bfd3d5"))
	music_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	music_controls.add_child(music_title)
	world.get("music").connect("state_changed", refresh_music_controls)
	refresh_music_controls()
	var badge: PanelContainer = PanelContainer.new()
	badge.add_theme_stylebox_override("panel", style(Color("244954"), 24))
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(badge)
	mode_label = label("●   世界總覽", 16, Color("e6eada"))
	badge.add_child(mode_label)
	background_download_label = label("", 14, Color("f8eed7"))
	background_download_label.name = "BackgroundDownloadStatus"
	background_download_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	background_download_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background_download_label.visible = false
	column.add_child(background_download_label)
	background_download_retry = button("重試背景下載")
	background_download_retry.name = "BackgroundDownloadRetry"
	background_download_retry.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	background_download_retry.pressed.connect(func() -> void: world.call("retry_preparation"))
	background_download_retry.visible = false
	column.add_child(background_download_retry)
	var body: HBoxContainer = HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(body)
	sidebar = VBoxContainer.new()
	sidebar.name = "Sidebar"
	sidebar.custom_minimum_size.x = 270
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sidebar.add_theme_constant_override("separation", 12)
	body.add_child(sidebar)
	var map_card: PanelContainer = PanelContainer.new()
	map_card.name = "MinimapCard"
	map_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var map_style: StyleBoxFlat = style(Color("183b45"),16)
	map_style.content_margin_left = 12
	map_style.content_margin_right = 12
	map_card.add_theme_stylebox_override("panel",map_style)
	sidebar.add_child(map_card)
	var map_column: VBoxContainer = VBoxContainer.new()
	map_column.name = "MapColumn"
	map_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_column.add_theme_constant_override("separation",8)
	map_card.add_child(map_column)
	var map_location: Label = label("附近地圖",15,Color("f2e8ce"))
	map_location.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_column.add_child(map_location)
	minimap = MinimapScript.new() as Control
	minimap.name = "Minimap"
	minimap.custom_minimum_size = Vector2(224,180)
	minimap.set("world",world)
	minimap.set("location_label",map_location)
	minimap.connect("expand_requested", open_full_map)
	map_column.add_child(minimap)
	var legend: Label = label("▲ 人物朝向   ①–⑥ 入口   ✿ 櫻花林\n點擊小地圖查看全圖",11,Color("bdd0c5"))
	if get_node("/root/ResourceProfile").call("is_low"):
		legend.text = "▲ 人物朝向   ①–⑥ 入口\n點擊小地圖查看全圖"
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_column.add_child(legend)
	view_button = button("開始漫遊    ↗", true)
	view_button.pressed.connect(_activate_view_button)
	sidebar.add_child(view_button)
	destination_toggle = button("選擇目的地    +")
	destination_toggle.pressed.connect(func() -> void:
		destination_card.visible = not destination_card.visible
		if destination_card.visible:
			world.get("player").cancel_jump_input()
		destination_toggle.text = "收起目的地    −" if destination_card.visible else "選擇目的地    +")
	sidebar.add_child(destination_toggle)
	settings_button = button("遊戲設定")
	settings_button.name = "GraphicsSettingsButton"
	settings_button.focus_mode = Control.FOCUS_ALL
	settings_button.pressed.connect(open_graphics_settings)
	sidebar.add_child(settings_button)
	account_controls = VBoxContainer.new()
	account_controls.name = "AccountControls"
	account_controls.add_theme_constant_override("separation", 5)
	sidebar.add_child(account_controls)
	account_status = label("星途共用帳號 · 尚未登入", 13, Color("d7e4de"))
	account_status.name = "AccountStatus"
	account_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	account_controls.add_child(account_status)
	var account_row := HBoxContainer.new()
	account_controls.add_child(account_row)
	account_button = button("登入")
	account_button.name = "AccountButton"
	account_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	account_button.pressed.connect(func() -> void: world.call("open_account", "account"))
	account_row.add_child(account_button)
	scores_button = button("我的成績")
	scores_button.name = "MyScoresButton"
	scores_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scores_button.pressed.connect(func() -> void: world.call("open_account", "scores"))
	account_row.add_child(scores_button)
	sign_out_button = button("登出")
	sign_out_button.name = "SignOutButton"
	sign_out_button.pressed.connect(func() -> void: world.get("account").call("sign_out"))
	account_controls.add_child(sign_out_button)
	var account_service: Node = world.get("account") as Node
	if account_service != null:
		account_service.connect("state_changed", refresh_account)
		refresh_account(account_service.get("user") as Dictionary)
	else:
		refresh_account({})
	var card: PanelContainer = PanelContainer.new()
	destination_card = card
	card.visible = false
	card.visibility_changed.connect(_sync_destination_layout)
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", style(Color("f6f3e9"), 18))
	sidebar.add_child(card)
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.name = "DestinationScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var destinations: VBoxContainer = VBoxContainer.new()
	destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destinations.add_theme_constant_override("separation", 8)
	scroll.add_child(destinations)
	destinations.add_child(label("探索目的地", 18))
	destinations.add_child(label("選擇一站，直接抵達", 13, Color("748a86")))
	var config: Dictionary = world.get("layout")
	for i: int in range(config.stations.size()):
		var station: Dictionary = config.stations[i]
		var entry: Button = button("%02d    %s    ›" % [i + 1, station.label])
		entry.alignment = HORIZONTAL_ALIGNMENT_LEFT
		entry.pressed.connect(func() -> void:
			close_compact_menu()
			world.call("teleport_to", str(station.id)))
		destinations.add_child(entry)
		station_buttons.append(entry)
	var sakura: Button = button("✿    櫻花林散步    ›")
	sakura.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sakura.pressed.connect(func() -> void:
		close_compact_menu()
		world.call("visit_sakura"))
	sakura.visible = not bool(get_node("/root/ResourceProfile").call("is_low"))
	destinations.add_child(sakura)
	station_buttons.append(sakura)
	var ecology: MenuButton = MenuButton.new()
	ecology.text="自然景點    ▾"
	ecology.alignment=HORIZONTAL_ALIGNMENT_LEFT
	ecology.add_theme_font_override("font",font)
	ecology.add_theme_font_size_override("font_size",17)
	ecology.add_theme_color_override("font_color",ink)
	ecology.add_theme_stylebox_override("normal",style(Color("edf1e9"),12))
	ecology.add_theme_stylebox_override("hover",style(Color("d7e6db"),12))
	var popup: PopupMenu=ecology.get_popup()
	popup.add_theme_font_override("font",font)
	popup.add_theme_font_size_override("font_size",18)
	var nature_names: Array[String]=["湖畔闊葉林","河口蘆葦濕地","蕨類混合林","溪谷柳樹林","紅屋頂湖畔住宅","沼澤木棧道"]
	for i: int in range(nature_names.size()):
		popup.add_item(nature_names[i],i)
	popup.id_pressed.connect(func(id: int) -> void:
		close_compact_menu()
		world.call("visit_ecology", id))
	destinations.add_child(ecology)
	station_buttons.append(ecology)
	var bottom: HBoxContainer = HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(bottom)
	var help: VBoxContainer = VBoxContainer.new()
	bottom.add_child(help)
	help.add_child(label("W A S D  移動     Shift  跑步     空白鍵  前空翻跳躍", 14, Color("d7e4de")))
	help.add_child(label("按住左／右鍵拖曳旋轉     Tab  切換視角     滾輪  縮放     Home  返回起點", 14, Color("9fbebf")))
	var gap: Control = Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(gap)
	prompt_label = label("六個目的地，自由探索整個世界", 15, Color("e9ddb9"))
	prompt_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(prompt_label)
	rest_button = button("E  坐下休息", true)
	rest_button.name = "RestButton"
	screen.add_child(rest_button)
	rest_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	rest_button.offset_left = -126
	rest_button.offset_right = 126
	rest_button.offset_top = -122
	rest_button.offset_bottom = -70
	rest_button.visible = false
	rest_button.pressed.connect(func() -> void: world.call("interact_nearest"))
	modal = CenterContainer.new()
	modal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	modal.visible = false
	screen.add_child(modal)
	var panel: PanelContainer = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style(Color("f7f3e7"), 22))
	panel.custom_minimum_size = Vector2(520, 280)
	modal.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	panel.add_child(content)
	panel_title = label("", 28)
	content.add_child(panel_title)
	panel_body = label("", 18)
	panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.custom_minimum_size.x = 460
	content.add_child(panel_body)
	var close: Button = button("繼續探索", true)
	close.pressed.connect(func() -> void: world.call("resume_world", {}))
	content.add_child(close)
	_build_graphics_settings(screen)
	_build_full_map(screen)
	if compact_hud:
		_build_compact_hud(screen)
		get_viewport().size_changed.connect(_resize_compact_hud)
		_resize_compact_hud.call_deferred()

func _sync_destination_layout() -> void:
	# The expanded sidebar belongs to travel. Secondary account/settings rows
	# return when it closes, leaving destinations visible without an initial scroll.
	var expanded: bool = destination_card.visible
	if account_controls != null:
		account_controls.visible = not expanded
	if settings_button != null:
		settings_button.visible = not expanded

func _activate_view_button() -> void:
	close_compact_menu()
	world.call("set_overview", not bool(world.get("overview")))

func _build_compact_hud(screen: Control) -> void:
	# Keep one set of navigation/music controls; place them in a scrollable
	# drawer instead of reserving a desktop sidebar across the game view.
	get_node("Screen/Margin").hide()
	compact_menu_button = button("☰ 選單")
	compact_menu_button.name = "CompactMenuButton"
	compact_menu_button.custom_minimum_size = Vector2(100, 46)
	compact_menu_button.pressed.connect(open_compact_menu)
	screen.add_child(compact_menu_button)
	compact_start = button("開始漫遊 ↗", true)
	compact_start.name = "CompactStartRoaming"
	compact_start.custom_minimum_size = Vector2(142, 46)
	compact_start.pressed.connect(_activate_view_button)
	screen.add_child(compact_start)
	compact_map_card = sidebar.get_node("MinimapCard") as PanelContainer
	minimap.set("compact_preview", true)
	compact_map_card.reparent(screen)
	var map_style: StyleBoxFlat = style(Color(0.05, .16, .19, .86), 12)
	map_style.set_content_margin_all(6)
	compact_map_card.add_theme_stylebox_override("panel", map_style)
	var map_column: VBoxContainer = compact_map_card.get_node("MapColumn") as VBoxContainer
	map_column.add_theme_constant_override("separation", 2)
	(map_column.get_child(0) as Label).add_theme_font_size_override("font_size", 12)
	(map_column.get_child(2) as Control).hide()
	compact_menu = Control.new()
	compact_menu.name = "CompactMenu"
	compact_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	compact_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	compact_menu.hide()
	screen.add_child(compact_menu)
	var shade := ColorRect.new()
	shade.color = Color(.02, .07, .08, .88)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	compact_menu.add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	compact_menu.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title: Label = label("探索與設定", 22, Color("f6e8cb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	compact_menu_close = button("×", true)
	compact_menu_close.name = "CloseCompactMenu"
	compact_menu_close.custom_minimum_size = Vector2(52, 48)
	compact_menu_close.pressed.connect(close_compact_menu)
	header.add_child(compact_menu_close)
	var scroll := ScrollContainer.new()
	scroll.name = "CompactMenuScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 12)
	scroll.add_child(controls)
	sidebar.reparent(controls)
	sidebar.custom_minimum_size.x = 0
	sidebar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	destination_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	destination_card.custom_minimum_size.y = 340
	var music_controls: Control = music_button.get_parent().get_parent() as Control
	music_controls.reparent(controls)
	music_slider.custom_minimum_size.y = 48
	music_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	background_download_label.reparent(controls)
	background_download_retry.reparent(controls)
	var help: Label = label("左下搖桿移動；右側空白處拖曳轉視角。\n點右上小地圖查看全圖。\n橫向遊玩可看見更寬的場景。", 15, Color("d7e4de"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	controls.add_child(help)
	# The browser's fullscreen button lives here visually, but its DOM click
	# retains the user activation required by Safari/Chrome fullscreen APIs.
	var browser_controls := Control.new()
	browser_controls.custom_minimum_size.y = 56
	content.add_child(browser_controls)
	var reset_settings: Button = settings_overlay.find_child("RestoreGraphicsDefaults", true, false) as Button
	reset_settings.tooltip_text = reset_settings.text
	reset_settings.text = "恢復建議設定"
	prompt_label.reparent(screen)
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.add_theme_font_size_override("font_size", 16)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Overlays retain the highest draw/input order after reparenting controls.
	screen.move_child(compact_menu, -1)
	for overlay: Control in [modal, settings_overlay, full_map_overlay]:
		screen.move_child(overlay, -1)

func _resize_compact_hud() -> void:
	if not compact_hud:
		return
	var screen: Control = get_node("Screen") as Control
	var logical: Vector2 = get_viewport().get_visible_rect().size
	var display_width: float = float(get_window().size.x)
	if OS.has_feature("web"):
		display_width = float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
	var density: float = maxf(.25, logical.x / maxf(display_width, 1.0))
	var safe: Vector4 = _compact_safe_insets()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.scale = Vector2.ONE * density
	screen.position = Vector2(safe.x, safe.y) * density
	screen.size = logical / density - Vector2(safe.x + safe.z, safe.y + safe.w)
	var landscape: bool = screen.size.x > screen.size.y
	var map_size := Vector2(120, 68) if landscape else Vector2(128, 90)
	minimap.custom_minimum_size = map_size
	compact_map_card.size = Vector2.ZERO
	compact_map_card.position = Vector2(screen.size.x - map_size.x - 24, 10)
	compact_menu_button.position = Vector2(10, 10)
	compact_start.position = Vector2(10, 64)
	compact_start.visible = bool(world.get("overview"))
	prompt_label.position = Vector2(12, 64)
	prompt_label.size = Vector2(maxf(140, screen.size.x - map_size.x - 48), 48)
	rest_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rest_button.position = Vector2(10, 114 if not landscape else 64)
	rest_button.size = Vector2(180, 46)
	rest_button.custom_minimum_size = Vector2(180, 46)
	var panel: Control = modal.get_child(0) as Control
	panel.custom_minimum_size.x = minf(520, screen.size.x - 24)
	panel_body.custom_minimum_size.x = minf(460, screen.size.x - 64)
	if preparation_overlay != null:
		(preparation_overlay.get_child(0) as Control).custom_minimum_size.x = minf(420, screen.size.x - 24)
	_resize_graphics_settings()
	_resize_full_map()

func _compact_safe_insets() -> Vector4:
	if not OS.has_feature("web"):
		return Vector4.ZERO
	var values: Variant = JSON.parse_string(str(JavaScriptBridge.eval("JSON.stringify(window.LittleWorldTouchUI?.safeArea() || [0,0,0,0])")))
	if values is Array and (values as Array).size() == 4:
		return Vector4(float(values[0]), float(values[1]), float(values[2]), float(values[3]))
	return Vector4.ZERO

func is_compact_menu_open() -> bool:
	return compact_menu != null and compact_menu.visible

func open_compact_menu() -> void:
	if (world.get("account_view_open") == true) or is_compact_menu_open() or is_full_map_open() or is_settings_open() or modal.visible or bool(world.get("entering")) or bool(world.get("preparing_roam")) or bool(world.get("preparing_room")):
		return
	var actor: Node = world.get("player") as Node
	_compact_previous_controls = bool(actor.get("controls_enabled"))
	_compact_previous_paused = bool(world.get("paused"))
	world.call("finish_view_drag")
	actor.call("cancel_jump_input")
	actor.set("controls_enabled", false)
	actor.set("velocity", Vector3.ZERO)
	world.set("paused", true)
	compact_menu.show()
	_set_map_touch_modal(true)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.LittleWorldTouchUI?.setMenuOpen(true)")

func close_compact_menu() -> void:
	if not is_compact_menu_open():
		return
	compact_menu.hide()
	world.set("paused", _compact_previous_paused)
	var actor: Node = world.get("player") as Node
	var prepared: bool = not actor.has_method("visuals_ready") or bool(actor.call("visuals_ready"))
	actor.set("controls_enabled", _compact_previous_controls and prepared and not bool(world.get("overview")) and not bool(world.get("paused")) and not bool(world.get("entering")) and not bool(world.get("preparing_roam")) and not bool(world.get("preparing_room")))
	actor.call("cancel_jump_input")
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.LittleWorldTouchUI?.setMenuOpen(false)")
	_set_map_touch_modal(false)
	get_viewport().gui_release_focus()

func _build_full_map(screen: Control) -> void:
	full_map_overlay = Control.new()
	full_map_overlay.name = "FullWorldMapOverlay"
	full_map_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	full_map_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	full_map_overlay.visible = false
	screen.add_child(full_map_overlay)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.02, 0.06, 0.08, 0.93)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_map_overlay.add_child(shade)
	full_map_content = Control.new()
	full_map_content.name = "FullMapContent"
	full_map_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	full_map_overlay.add_child(full_map_content)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	full_map_content.add_child(margin)
	var panel: PanelContainer = PanelContainer.new()
	panel.name = "FullMapPanel"
	panel.add_theme_stylebox_override("panel", style(Color("102f3a"), 18))
	margin.add_child(panel)
	var content: VBoxContainer = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var header: HBoxContainer = HBoxContainer.new()
	content.add_child(header)
	var title: Label = label("完整世界地圖", 23, Color("f6e8cb"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(title)
	full_map_close = button("×", true)
	full_map_close.name = "CloseWorldMap"
	full_map_close.tooltip_text = "關閉地圖（Esc／返回）"
	full_map_close.custom_minimum_size = Vector2(52, 52)
	full_map_close.focus_mode = Control.FOCUS_ALL
	full_map_close.add_theme_font_size_override("font_size", 28)
	full_map_close.pressed.connect(close_full_map)
	header.add_child(full_map_close)
	full_map = FullMapScript.new() as Control
	full_map.name = "FullWorldMap"
	full_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	full_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(full_map)
	var legend: Label = label("▲ 你的位置　①–⑥ 六個入口　✿ 櫻花林\n正面與背面同時顯示；金色線是連接步道", 13, Color("bcd0c5"))
	if get_node("/root/ResourceProfile").call("is_low"):
		legend.text = "▲ 你的位置　①–⑥ 六個入口\n正面與背面同時顯示；金色線是連接步道"
	legend.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(legend)
	full_map_overlay.resized.connect(_resize_full_map)
	_resize_full_map.call_deferred()

func _resize_full_map() -> void:
	if full_map_content == null or full_map_overlay.size.x <= 0.0:
		return
	# The world uses an expanded logical canvas on phones. Keep map text and
	# the close target in screen pixels instead of shrinking them with that HUD.
	var display_width: float = float(get_window().size.x)
	if OS.has_feature("web"):
		display_width = float(JavaScriptBridge.eval("document.getElementById('canvas').getBoundingClientRect().width"))
	var density: float = maxf(1.0, full_map_overlay.size.x / maxf(display_width, 1.0))
	full_map_content.scale = Vector2.ONE * density
	full_map_content.size = full_map_overlay.size / density

func is_full_map_open() -> bool:
	return full_map_overlay != null and full_map_overlay.visible

func _set_map_touch_modal(open: bool) -> void:
	var touch: Node = get_node_or_null("/root/WebTouch")
	if touch != null:
		touch.call("reset_input")
	if OS.has_feature("web"):
		var bridge: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldTouchUI")
		if bridge != null:
			bridge.setModalOpen(open)

func open_full_map() -> void:
	close_compact_menu()
	if (world.get("account_view_open") == true) or _map_history_closing or is_full_map_open() or is_settings_open() or modal.visible or bool(world.get("entering")) or bool(world.get("preparing_roam")) or bool(world.get("preparing_room")):
		return
	world.call("finish_view_drag")
	var actor: Node = world.get("player") as Node
	_map_previous_controls = bool(actor.get("controls_enabled"))
	_map_previous_paused = bool(world.get("paused"))
	actor.call("cancel_jump_input")
	actor.set("controls_enabled", false)
	actor.set("velocity", Vector3.ZERO)
	world.set("paused", true)
	destination_card.visible = false
	destination_toggle.text = "選擇目的地    +"
	_set_map_touch_modal(true)
	_resize_full_map()
	full_map_overlay.visible = true
	full_map.call("configure", minimap)
	full_map_close.grab_focus()
	if OS.has_feature("web"):
		if _map_pop_callback == null:
			_map_browser_window = JavaScriptBridge.get_interface("window")
			_map_pop_callback = JavaScriptBridge.create_callback(_on_map_history_back)
			_map_browser_window.addEventListener("popstate", _map_pop_callback)
		JavaScriptBridge.eval("history.pushState(Object.assign({}, history.state, {littleWorldMap:true}), '', location.href);")
		_map_history_active = true

func close_full_map() -> void:
	if not is_full_map_open():
		return
	full_map_overlay.visible = false
	world.set("paused", _map_previous_paused)
	var actor: Node = world.get("player") as Node
	var prepared: bool = not actor.has_method("visuals_ready") or bool(actor.call("visuals_ready"))
	actor.set("controls_enabled", _map_previous_controls and prepared and not bool(world.get("overview")) and not bool(world.get("paused")) and not bool(world.get("entering")) and not bool(world.get("preparing_roam")) and not bool(world.get("preparing_room")))
	actor.call("cancel_jump_input")
	_set_map_touch_modal(false)
	get_viewport().gui_release_focus()
	if _map_history_active:
		_map_history_active = false
		_map_history_closing = bool(JavaScriptBridge.eval("Boolean(history.state && history.state.littleWorldMap)"))
		if _map_history_closing:
			JavaScriptBridge.eval("history.back();")

func _on_map_history_back(_arguments: Array) -> void:
	_map_history_active = false
	if _map_history_closing:
		_map_history_closing = false
		return
	close_full_map()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and is_full_map_open():
		close_full_map()
		get_viewport().set_input_as_handled()
	elif what == NOTIFICATION_WM_GO_BACK_REQUEST and is_compact_menu_open():
		close_compact_menu()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if _map_pop_callback != null and _map_browser_window != null:
		_map_browser_window.removeEventListener("popstate", _map_pop_callback)
	_map_pop_callback = null
	_map_browser_window = null

func set_background_download(message: String, failed: bool = false) -> void:
	background_download_label.text = message
	background_download_label.visible = not message.is_empty()
	background_download_retry.visible = failed
	if compact_menu_button != null:
		compact_menu_button.text = "☰ 選單 !" if failed else "☰ 選單"
		compact_menu_button.tooltip_text = message

func set_preparation(message: String, failed: bool) -> void:
	if preparation_overlay == null:
		if message.is_empty():
			return
		preparation_overlay = CenterContainer.new()
		preparation_overlay.visible = false
		preparation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		get_node("Screen").add_child(preparation_overlay)
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", style(Color("f7f3e7"), 22))
		card.custom_minimum_size = Vector2(minf(420, (get_node("Screen") as Control).size.x - 24) if compact_hud else 420, 170)
		preparation_overlay.add_child(card)
		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 16)
		card.add_child(content)
		preparation_label = label("", 20)
		preparation_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preparation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(preparation_label)
		preparation_retry = button("重新下載", true)
		preparation_retry.pressed.connect(func() -> void: world.call("retry_preparation"))
		content.add_child(preparation_retry)
		var cancel: Button = button("返回世界總覽")
		cancel.pressed.connect(func() -> void: world.call("cancel_preparation"))
		content.add_child(cancel)
	var showing: bool = not message.is_empty()
	if preparation_overlay.visible != showing:
		_set_map_touch_modal(showing)
	preparation_overlay.visible = showing
	preparation_label.text = message
	preparation_retry.visible = failed

func _build_graphics_settings(screen: Control) -> void:
	settings_overlay = Control.new()
	settings_overlay.name = "GraphicsSettingsOverlay"
	settings_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	settings_overlay.visible = false
	screen.add_child(settings_overlay)
	var shade: ColorRect = ColorRect.new()
	shade.color = Color(0.025, 0.08, 0.10, 0.76)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	settings_overlay.add_child(shade)
	var safe_area: MarginContainer = MarginContainer.new()
	safe_area.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		safe_area.add_theme_constant_override("margin_" + side, 16)
	settings_overlay.add_child(safe_area)
	var center: CenterContainer = CenterContainer.new()
	safe_area.add_child(center)
	settings_panel = PanelContainer.new()
	settings_panel.name = "SettingsPanel"
	settings_panel.add_theme_stylebox_override("panel", style(Color("f7f3e7"), 22))
	center.add_child(settings_panel)
	var panel_content: VBoxContainer = VBoxContainer.new()
	panel_content.add_theme_constant_override("separation", 12)
	settings_panel.add_child(panel_content)
	settings_scroll = ScrollContainer.new()
	settings_scroll.name = "SettingsScroll"
	settings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel_content.add_child(settings_scroll)
	var content: VBoxContainer = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	settings_scroll.add_child(content)
	content.add_child(label("遊戲設定", 26))
	interest_settings_button = button("我的興趣量表", true)
	interest_settings_button.name = "SettingsInterestProfile"
	interest_settings_button.focus_mode = Control.FOCUS_ALL
	interest_settings_button.pressed.connect(open_interest_settings)
	content.add_child(interest_settings_button)
	var interest_help: Label = label("修改 RIASEC、33種知識分數與適配度，查看帳號內的歷次紀錄。", 14, Color("647b75"))
	interest_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(interest_help)
	content.add_child(label("畫面與效能", 19))
	var detail: Label = label("即時套用，並記住這台裝置的選擇。", 14, Color("647b75"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail)
	var resources: Node = get_node("/root/ResourceProfile")
	var pack_label: Label = label("目前材質包：" + ("低階" if resources.call("is_low") else "滿血"), 17)
	content.add_child(pack_label)
	var change_resources: Button = button("切換材質包（重新啟動）")
	change_resources.pressed.connect(func() -> void: resources.call("change_on_restart"))
	content.add_child(change_resources)
	var account_actions: HBoxContainer = HBoxContainer.new()
	content.add_child(account_actions)
	for action: String in ["switch_account", "sign_out"]:
		var account_action: Button = button("切換帳號" if action == "switch_account" else "登出")
		account_action.name = "SettingsSwitchAccount" if action == "switch_account" else "SettingsSignOut"
		account_action.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		account_action.pressed.connect(func() -> void:
			close_graphics_settings()
			world.get("account").call(action))
		account_actions.add_child(account_action)
	var quality_row: GridContainer = GridContainer.new()
	quality_row.columns = 2
	quality_row.add_theme_constant_override("h_separation", 8)
	quality_row.add_theme_constant_override("v_separation", 8)
	content.add_child(quality_row)
	var quality_group: ButtonGroup = ButtonGroup.new()
	for profile: String in GraphicsSettingsScript.QUALITY_PROFILES:
		var choice: Button = button({"mobile":"手機省電", "balanced":"手機流暢", "low":"低配", "standard":"一般"}[profile], true)
		choice.name = {"mobile":"QualityMobile", "balanced":"QualityBalanced", "low":"QualityLow", "standard":"QualityStandard"}[profile]
		choice.toggle_mode = true
		choice.button_group = quality_group
		choice.focus_mode = Control.FOCUS_ALL
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.set_meta("quality_profile", profile)
		choice.pressed.connect(func() -> void: graphics_settings.call("set_quality_profile", profile))
		quality_row.add_child(choice)
		quality_buttons.append(choice)
	var quality_help: Label = label("手機／平板：流暢模式在 320–432p 調整，省電固定最高 432p。省電模式與手機低畫質會限制附近細節、簡化地表，最高 30 FPS。電腦流暢模式為 432–720p。一般使用原解析度與陰影；持續卡頓時會自動啟用效能保護。文字維持清晰。", 14, Color("647b75"))
	quality_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(quality_help)
	msaa_button = button("MSAA：開啟（2×）")
	msaa_button.name = "MSAAToggle"
	msaa_button.focus_mode = Control.FOCUS_ALL
	msaa_button.toggle_mode = true
	msaa_button.pressed.connect(func() -> void:
		graphics_settings.call("set_msaa_enabled", msaa_button.button_pressed))
	content.add_child(msaa_button)
	var aa_help: Label = label("開啟：邊緣更平滑。關閉：減少顯示負擔，邊緣鋸齒會較明顯。", 14, Color("647b75"))
	aa_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(aa_help)
	content.add_child(label("偏好幀率上限", 17))
	var frame_row: HBoxContainer = HBoxContainer.new()
	frame_row.add_theme_constant_override("separation", 8)
	content.add_child(frame_row)
	var frame_group: ButtonGroup = ButtonGroup.new()
	for fps: int in GraphicsSettingsScript.FRAME_LIMITS:
		var choice: Button = button(str(fps), true)
		choice.name = "FPS" + str(fps)
		choice.focus_mode = Control.FOCUS_ALL
		choice.toggle_mode = true
		choice.button_group = frame_group
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.set_meta("frame_limit", fps)
		choice.pressed.connect(func() -> void: graphics_settings.call("set_frame_limit", fps))
		frame_row.add_child(choice)
		frame_buttons.append(choice)
	var fps_help: Label = label("30 較省電，60 均衡，90 適合高更新率螢幕。省電或效能保護期間最高 30；閒置時可降至 15。偏好會保留，目前實際上限顯示於下方。", 14, Color("647b75"))
	fps_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(fps_help)
	settings_performance = label("", 14, Color("203e46"))
	settings_performance.name = "GraphicsPerformanceStatus"
	settings_performance.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(settings_performance)
	settings_status = label("", 13, Color("647b75"))
	settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(settings_status)
	var default_mobile: bool = GraphicsSettingsScript.is_mobile_web()
	var default_fps: int = GraphicsSettingsScript.default_frame_limit(default_mobile)
	var default_profile: String = GraphicsSettingsScript.default_quality_profile(default_mobile)
	var default_label: String = {"mobile":"手機省電", "balanced":"手機流暢", "low":"低配", "standard":"一般"}[default_profile]
	var reset: Button = button("恢復預設：%s／MSAA %s／%d FPS" % [default_label, "關" if default_profile != "standard" else "開", default_fps])
	reset.name = "RestoreGraphicsDefaults"
	reset.add_theme_font_size_override("font_size", 14)
	reset.focus_mode = Control.FOCUS_ALL
	reset.pressed.connect(func() -> void: graphics_settings.call("restore_defaults"))
	content.add_child(reset)
	var close_settings: Button = button("完成", true)
	close_settings.name = "CloseGraphicsSettings"
	close_settings.focus_mode = Control.FOCUS_ALL
	close_settings.pressed.connect(close_graphics_settings)
	panel_content.add_child(close_settings)
	graphics_settings.connect("state_changed", _refresh_graphics_settings)
	settings_viewport = get_viewport()
	settings_viewport.size_changed.connect(_resize_graphics_settings)
	_resize_graphics_settings()
	_refresh_graphics_settings()
	set_process(false)

func _resize_graphics_settings() -> void:
	# The retained HUD is detached indoors, but its root viewport still resizes.
	var available: Vector2 = settings_viewport.get_visible_rect().size
	if compact_hud and has_node("Screen"):
		available = (get_node("Screen") as Control).size
	settings_panel.custom_minimum_size.x = minf(460.0, maxf(240.0, available.x - 32.0))
	# Keep the close action outside the scroll area, even on short landscape
	# viewports. The remaining height covers panel margins and the footer.
	settings_scroll.custom_minimum_size.y = minf(520.0, maxf(100.0, available.y - 144.0))

func _refresh_graphics_settings() -> void:
	var state: Dictionary = graphics_settings.call("get_state") as Dictionary
	for choice: Button in quality_buttons:
		choice.set_pressed_no_signal(str(choice.get_meta("quality_profile")) == str(state.get("quality_profile", "low")))
	var enabled: bool = bool(state.get("msaa_enabled", true))
	msaa_button.set_pressed_no_signal(enabled)
	msaa_button.text = "MSAA：開啟（2×）" if enabled else "MSAA：關閉"
	if enabled and int(state.get("applied_msaa", Viewport.MSAA_2X)) == Viewport.MSAA_DISABLED:
		msaa_button.text = "MSAA：偏好開啟（目前省電關閉）"
	for choice: Button in frame_buttons:
		choice.set_pressed_no_signal(int(choice.get_meta("frame_limit")) == int(state.get("frame_limit", 60)))
	if int(state.get("settings_error", OK)) != OK:
		settings_status.text = "目前選擇已套用，但無法儲存；重新開啟後可能不會保留。"
	elif not bool(state.get("persistent", true)):
		settings_status.text = "此瀏覽模式無法保留設定，這次遊玩仍可套用。"
	else:
		settings_status.text = "設定會自動儲存。"
	_refresh_graphics_performance(state)

func _refresh_graphics_performance(state: Dictionary) -> void:
	if settings_performance == null:
		return
	var pixels: Array = state.get("internal_3d_pixels", [0, 0]) as Array
	var resolution: String = "%d × %d" % [int(pixels[0]), int(pixels[1])]
	var mode: String = "自動調整" if bool(state.get("adaptive_enabled", false)) else "固定畫質"
	var fps: float = float(state.get("recent_gameplay_fps", 0.0))
	var pacing: String = {"warming":"暖機中", "stable":"穩定", "mixed":"偶有波動", "overloaded":"持續掉幀"}.get(str(state.get("pacing_status", "warming")), "暖機中")
	var reading: String = "等待遊玩取樣" if fps <= 0.0 else "%.1f FPS／目標 %.0f，%s" % [fps, float(state.get("effective_target_fps", 30.0)), pacing]
	var active_limit: int = int(state.get("applied_max_fps", state.get("frame_limit", 30)))
	var preferred_limit: int = int(state.get("frame_limit", 30))
	var protection: String = ""
	if bool(state.get("runtime_pressure", false)):
		protection = "已啟用效能保護"
	elif bool(state.get("constrained_runtime", false)):
		protection = "已啟用省電負載限制"
	if bool(state.get("idle_limited", false)):
		protection += ("・" if not protection.is_empty() else "") + "閒置省電"
	if bool(state.get("background_hidden", false)):
		protection += ("・" if not protection.is_empty() else "") + "背景暫停繪圖"
	var limit_text: String = "目前實際上限：%d FPS（偏好 %d）" % [active_limit, preferred_limit]
	if not protection.is_empty():
		limit_text += "\n" + protection
	settings_performance.text = "目前 3D：%s（%s）\n%s\n最近遊玩：%s\n幀率用來觀察流暢度，並非 GPU 使用率或溫度。" % [resolution, mode, limit_text, reading]

func _process(delta: float) -> void:
	_settings_refresh_clock += delta
	if _settings_refresh_clock >= 0.5 and is_settings_open():
		_settings_refresh_clock = 0.0
		_refresh_graphics_performance(graphics_settings.call("get_state") as Dictionary)

func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible

func open_graphics_settings() -> void:
	close_compact_menu()
	if (world.get("account_view_open") == true) or is_full_map_open() or is_settings_open() or bool(world.get("entering")) or bool(world.get("preparing_roam")) or bool(world.get("preparing_room")):
		return
	world.call("finish_view_drag")
	var actor: Node = world.get("player") as Node
	_settings_previous_controls = bool(actor.get("controls_enabled"))
	actor.call("cancel_jump_input")
	actor.set("controls_enabled", false)
	destination_card.visible = false
	destination_toggle.text = "選擇目的地    +"
	settings_overlay.visible = true
	_set_map_touch_modal(true)
	_settings_refresh_clock = 0.0
	_refresh_graphics_settings()
	set_process(true)
	msaa_button.grab_focus()

func close_graphics_settings() -> void:
	if is_interest_panel_open():
		interest_panel.call("request_close")
		return
	if not is_settings_open():
		return
	settings_overlay.visible = false
	_set_map_touch_modal(false)
	set_process(false)
	var actor: Node = world.get("player") as Node
	var prepared: bool = not actor.has_method("visuals_ready") or bool(actor.call("visuals_ready"))
	actor.set("controls_enabled", _settings_previous_controls and prepared and not bool(world.get("overview")) and not bool(world.get("paused")) and not bool(world.get("entering")) and not bool(world.get("preparing_roam")) and not bool(world.get("preparing_room")))
	actor.call("cancel_jump_input")
	# Return Space/Tab to jumping and view switching after leaving the menu.
	get_viewport().gui_release_focus()

func is_interest_panel_open() -> bool:
	return is_instance_valid(interest_panel) and interest_panel.visible

func open_interest_settings() -> void:
	if not is_settings_open() or is_interest_panel_open():
		return
	if not is_instance_valid(interest_panel):
		interest_panel = InterestPanelScript.new() as Control
		interest_panel.name = "SettingsInterestPanel"
		add_child(interest_panel)
		interest_panel.connect("closed", _interest_settings_closed)
	interest_panel.call("configure", world.get("account"))
	interest_panel.call("open_panel")
	(world.get("player") as Node).set("controls_enabled", false)
	_set_map_touch_modal(true)

func _interest_settings_closed() -> void:
	# Closing this nested account panel returns to settings, not to walking.
	if is_settings_open():
		_set_map_touch_modal(true)
		(world.get("player") as Node).set("controls_enabled", false)
		interest_settings_button.grab_focus()

func _input(event: InputEvent) -> void:
	if is_interest_panel_open():
		return # The form owns text input, Escape and its unsaved-changes dialog.
	if is_compact_menu_open():
		if event.is_action_pressed("ui_cancel"):
			close_compact_menu()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			get_viewport().set_input_as_handled()
	elif is_full_map_open():
		if event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_XBUTTON1 and event.is_pressed()):
			close_full_map()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey:
			if event.is_action("ui_focus_next") or event.is_action("ui_focus_prev"):
				full_map_close.grab_focus()
			if not event.is_action("ui_accept"):
				get_viewport().set_input_as_handled()
	elif is_settings_open() and event.is_action_pressed("ui_cancel"):
		close_graphics_settings()
		get_viewport().set_input_as_handled()

func _pending_music_failed(state: Dictionary) -> bool:
	var pending: String = str(state.get("pending_context", ""))
	return not pending.is_empty() and (state.get("load_errors", {}) as Dictionary).has(pending)

func _activate_music_button() -> void:
	var audio: Node = world.get("music") as Node
	var state: Dictionary = audio.call("get_state")
	# Historical errors from another district must not disable mute controls.
	if _pending_music_failed(state):
		audio.call("retry_pending_music")
		return
	audio.call("set_muted", not bool(state.get("muted", false)))

func refresh_music_controls() -> void:
	var state: Dictionary = world.get("music").call("get_state")
	music_button.text = "音樂：靜音" if bool(state.get("muted", false)) else "音樂：開"
	if _pending_music_failed(state):
		music_button.text = "重試音樂"
	var volume: float = float(state.get("volume", 0.4))
	music_slider.set_value_no_signal(volume)
	music_percent.text = "%d%%" % roundi(volume * 100.0)
	if not bool(state.get("unlocked", false)):
		music_title.text = "點擊畫面播放音樂"
	else:
		music_title.text = str(state.get("title", "星球漫遊"))
		if music_title.text.is_empty() and not str(state.get("pending_context", "")).is_empty():
			music_title.text = "音樂準備中"

func update_status(is_overview: bool, nearby: String, _radial_height: float) -> void:
	if last_overview != is_overview:
		last_overview = is_overview
		for control: Control in overview_controls:
			control.visible = is_overview
		destination_card.visible = false
		destination_toggle.text = "選擇目的地    +"
	mode_label.text = "●   世界總覽" if is_overview else "●   自由漫遊"
	view_button.text = "開始漫遊    ↗" if is_overview else "回到世界總覽    ↗"
	prompt_label.text = "E  進入「%s」" % nearby if nearby != "" and not is_overview else "六個目的地，自由探索整個世界"
	if compact_hud:
		compact_start.visible = is_overview
		prompt_label.text = "按「互動」進入 %s" % nearby if nearby != "" and not is_overview else ""
		if _compact_touch_overview != int(is_overview):
			_compact_touch_overview = int(is_overview)
			if OS.has_feature("web"):
				JavaScriptBridge.eval("window.LittleWorldTouchUI?.setGameplayActive(%s)" % ("false" if is_overview else "true"))
	var benches: Node = world.get("benches") as Node
	if benches != null:
		var rest_prompt: String = str(benches.call("prompt"))
		rest_button.visible = not rest_prompt.is_empty() and bool(benches.call("available"))
		rest_button.text = rest_prompt
		if compact_hud:
			rest_button.text = rest_prompt.trim_prefix("E  ")
			if rest_button.visible:
				prompt_label.text = ""
		rest_button.disabled = benches.get("state") in [&"sitting", &"standing"]
		if bool(world.get("player").get("is_resting")) and not is_overview:
			mode_label.text = "●   稍作休息"

func show_station(station_id: String) -> void:
	close_compact_menu()
	var config: Dictionary = world.get("layout")
	for station: Dictionary in config.stations:
		if station.id == station_id:
			panel_title.text = station.label
			panel_body.text = str(station.subtitle) + "\n\n這裡是功能入口預覽。網站工具將在後續階段接入；返回時會留在原本的位置。"
	modal.visible = true
	_set_map_touch_modal(true)
	for entry: Button in station_buttons:
		entry.disabled = true
	view_button.disabled = true

func close_panel() -> void:
	var was_visible: bool = modal.visible
	modal.visible = false
	if was_visible:
		_set_map_touch_modal(false)
	for entry: Button in station_buttons:
		entry.disabled = false
	view_button.disabled = false

func refresh_account(user: Dictionary) -> void:
	var signed_in: bool = user.get("signedIn", false) == true
	account_button.text = "帳號" if signed_in else "登入"
	sign_out_button.visible = signed_in
	var display_name: String = str(user.get("displayName", "")).strip_edges()
	account_status.text = ("星途 · " + (display_name if not display_name.is_empty() else "已登入")) if signed_in else "星途共用帳號 · 尚未登入"
	account_status.tooltip_text = account_status.text

func show_account_error(message: String) -> void:
	account_status.text = message
	account_status.tooltip_text = message

func set_account_modal(open: bool) -> void:
	if open:
		_account_previous_visible = visible
	visible = false if open else _account_previous_visible
	_set_map_touch_modal(open)
	destination_card.visible = false
	destination_toggle.text = "選擇目的地    +"
	for entry: Button in station_buttons:
		entry.disabled = open
	for entry: Button in [view_button, account_button, scores_button, sign_out_button, settings_button, destination_toggle]:
		entry.disabled = open
