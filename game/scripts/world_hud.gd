extends CanvasLayer

const MinimapScript = preload("res://scripts/world_minimap.gd")

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
var music_button: Button
var music_slider: HSlider
var music_title: Label
var music_percent: Label
var font: Font = preload("res://assets/fonts/NotoSansTC.ttf")
var ink: Color = Color("203e46")

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
	node.add_theme_stylebox_override("normal", style(Color("efd7a5") if accent else Color("edf1e9"), 12))
	node.add_theme_stylebox_override("hover", style(Color("f5e4bf") if accent else Color("d7e6db"), 12))
	node.add_theme_stylebox_override("pressed", style(Color("c3d7cb"), 12))
	return node

func _ready() -> void:
	var weighted_font: FontVariation = FontVariation.new()
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
	music_button.pressed.connect(func() -> void:
		var audio: Node = world.get("music") as Node
		var state: Dictionary = audio.call("get_state")
		audio.call("set_muted", not bool(state.get("muted", false))))
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
	map_column.add_child(minimap)
	var legend: Label = label("▲ 人物朝向   ①–⑥ 入口   ✿ 櫻花林",11,Color("bdd0c5"))
	legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_column.add_child(legend)
	view_button = button("開始漫遊    ↗", true)
	view_button.pressed.connect(func() -> void: world.call("set_overview", not bool(world.get("overview"))))
	sidebar.add_child(view_button)
	destination_toggle = button("選擇目的地    +")
	destination_toggle.pressed.connect(func() -> void:
		destination_card.visible = not destination_card.visible
		if destination_card.visible:
			world.get("player").cancel_jump_input()
		destination_toggle.text = "收起目的地    −" if destination_card.visible else "選擇目的地    +")
	sidebar.add_child(destination_toggle)
	var card: PanelContainer = PanelContainer.new()
	destination_card = card
	card.visible = false
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
		entry.pressed.connect(world.teleport_to.bind(str(station.id)))
		destinations.add_child(entry)
		station_buttons.append(entry)
	var sakura: Button = button("✿    櫻花林散步    ›")
	sakura.alignment = HORIZONTAL_ALIGNMENT_LEFT
	sakura.pressed.connect(world.visit_sakura)
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
	popup.id_pressed.connect(world.visit_ecology)
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
	prompt_label = label("六個目的地，一顆小小的世界", 15, Color("e9ddb9"))
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

func refresh_music_controls() -> void:
	var state: Dictionary = world.get("music").call("get_state")
	music_button.text = "音樂：靜音" if bool(state.get("muted", false)) else "音樂：開"
	var volume: float = float(state.get("volume", 0.4))
	music_slider.set_value_no_signal(volume)
	music_percent.text = "%d%%" % roundi(volume * 100.0)
	if not bool(state.get("unlocked", false)):
		music_title.text = "點擊畫面播放音樂"
	else:
		music_title.text = str(state.get("title", "星球漫遊"))

func update_status(is_overview: bool, nearby: String, _radial_height: float) -> void:
	if last_overview != is_overview:
		last_overview = is_overview
		for control: Control in overview_controls:
			control.visible = is_overview
		destination_card.visible = false
		destination_toggle.text = "選擇目的地    +"
	mode_label.text = "●   世界總覽" if is_overview else "●   自由漫遊"
	view_button.text = "開始漫遊    ↗" if is_overview else "回到世界總覽    ↗"
	prompt_label.text = "E  進入「%s」" % nearby if nearby != "" and not is_overview else "六個目的地，一顆小小的世界"
	var benches: Node = world.get("benches") as Node
	if benches != null:
		var rest_prompt: String = str(benches.call("prompt"))
		rest_button.visible = not rest_prompt.is_empty() and bool(benches.call("available"))
		rest_button.text = rest_prompt
		rest_button.disabled = benches.get("state") in [&"sitting", &"standing"]
		if bool(world.get("player").get("is_resting")) and not is_overview:
			mode_label.text = "●   稍作休息"

func show_station(station_id: String) -> void:
	var config: Dictionary = world.get("layout")
	for station: Dictionary in config.stations:
		if station.id == station_id:
			panel_title.text = station.label
			panel_body.text = str(station.subtitle) + "\n\n這裡是功能入口預覽。網站工具將在後續階段接入；返回時會留在原本的位置。"
	modal.visible = true
	for entry: Button in station_buttons:
		entry.disabled = true
	view_button.disabled = true

func close_panel() -> void:
	modal.visible = false
	for entry: Button in station_buttons:
		entry.disabled = false
	view_button.disabled = false
