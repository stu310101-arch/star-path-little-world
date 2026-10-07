extends CanvasLayer

const MinimapScript = preload("res://scripts/world_minimap.gd")
const GraphicsSettingsScript = preload("res://scripts/graphics_settings.gd")

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
var graphics_settings: Node
var settings_button: Button
var settings_overlay: Control
var settings_panel: PanelContainer
var settings_scroll: ScrollContainer
var settings_viewport: Viewport
var msaa_button: Button
var frame_buttons: Array[Button] = []
var settings_status: Label
var _settings_previous_controls: bool = false
var preparation_overlay: CenterContainer
var preparation_label: Label
var preparation_retry: Button
var background_download_label: Label
var background_download_retry: Button
var quality_buttons: Array[Button] = []
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
	graphics_settings = GraphicsSettingsScript.new() as Node
	graphics_settings.name = "GraphicsSettings"
	add_child(graphics_settings)
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
	settings_button = button("畫面設定")
	settings_button.name = "GraphicsSettingsButton"
	settings_button.focus_mode = Control.FOCUS_ALL
	settings_button.pressed.connect(open_graphics_settings)
	sidebar.add_child(settings_button)
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
	_build_graphics_settings(screen)

func set_background_download(message: String, failed: bool = false) -> void:
	background_download_label.text = message
	background_download_label.visible = not message.is_empty()
	background_download_retry.visible = failed

func set_preparation(message: String, failed: bool) -> void:
	if preparation_overlay == null:
		if message.is_empty():
			return
		preparation_overlay = CenterContainer.new()
		preparation_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		get_node("Screen").add_child(preparation_overlay)
		var card: PanelContainer = PanelContainer.new()
		card.add_theme_stylebox_override("panel", style(Color("f7f3e7"), 22))
		card.custom_minimum_size = Vector2(420, 170)
		preparation_overlay.add_child(card)
		var content: VBoxContainer = VBoxContainer.new()
		content.add_theme_constant_override("separation", 16)
		card.add_child(content)
		preparation_label = label("", 20)
		preparation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(preparation_label)
		preparation_retry = button("重新下載", true)
		preparation_retry.pressed.connect(func() -> void: world.call("retry_preparation"))
		content.add_child(preparation_retry)
		var cancel: Button = button("返回世界總覽")
		cancel.pressed.connect(func() -> void: world.call("cancel_preparation"))
		content.add_child(cancel)
	preparation_overlay.visible = not message.is_empty()
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
	content.add_child(label("畫面設定", 26))
	var detail: Label = label("即時套用，並記住這台裝置的選擇。", 14, Color("647b75"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(detail)
	var quality_row: HBoxContainer = HBoxContainer.new()
	quality_row.add_theme_constant_override("separation", 8)
	content.add_child(quality_row)
	var quality_group: ButtonGroup = ButtonGroup.new()
	for profile: String in ["low", "standard"]:
		var choice: Button = button("低配／省記憶體" if profile == "low" else "一般畫質", true)
		choice.name = "QualityLow" if profile == "low" else "QualityStandard"
		choice.toggle_mode = true
		choice.button_group = quality_group
		choice.focus_mode = Control.FOCUS_ALL
		choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		choice.set_meta("quality_profile", profile)
		choice.pressed.connect(func() -> void: graphics_settings.call("set_quality_profile", profile))
		quality_row.add_child(choice)
		quality_buttons.append(choice)
	var quality_help: Label = label("低配：3D 最高約 720p、較少遠景細節，預設 MSAA 關／30 FPS。文字維持清晰。一般：原解析度與較完整的遠景。", 14, Color("647b75"))
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
	content.add_child(label("幀率上限", 17))
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
	var fps_help: Label = label("30 較省電，60 均衡，90 適合高更新率螢幕。實際幀率仍依裝置、螢幕與瀏覽器而定。", 14, Color("647b75"))
	fps_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(fps_help)
	settings_status = label("", 13, Color("647b75"))
	settings_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(settings_status)
	var reset: Button = button("恢復預設：低配／MSAA 關／30 FPS")
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

func _resize_graphics_settings() -> void:
	# The retained HUD is detached indoors, but its root viewport still resizes.
	var available: Vector2 = settings_viewport.get_visible_rect().size
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
	for choice: Button in frame_buttons:
		choice.set_pressed_no_signal(int(choice.get_meta("frame_limit")) == int(state.get("frame_limit", 60)))
	if int(state.get("settings_error", OK)) != OK:
		settings_status.text = "目前選擇已套用，但無法儲存；重新開啟後可能不會保留。"
	elif not bool(state.get("persistent", true)):
		settings_status.text = "此瀏覽模式無法保留設定，這次遊玩仍可套用。"
	else:
		settings_status.text = "設定會自動儲存。"

func is_settings_open() -> bool:
	return settings_overlay != null and settings_overlay.visible

func open_graphics_settings() -> void:
	if is_settings_open() or bool(world.get("entering")) or bool(world.get("preparing_roam")) or bool(world.get("preparing_room")):
		return
	world.call("finish_view_drag")
	var actor: Node = world.get("player") as Node
	_settings_previous_controls = bool(actor.get("controls_enabled"))
	actor.call("cancel_jump_input")
	actor.set("controls_enabled", false)
	destination_card.visible = false
	destination_toggle.text = "選擇目的地    +"
	settings_overlay.visible = true
	msaa_button.grab_focus()

func close_graphics_settings() -> void:
	if not is_settings_open():
		return
	settings_overlay.visible = false
	var actor: Node = world.get("player") as Node
	var prepared: bool = not actor.has_method("visuals_ready") or bool(actor.call("visuals_ready"))
	actor.set("controls_enabled", _settings_previous_controls and prepared and not bool(world.get("overview")) and not bool(world.get("paused")) and not bool(world.get("entering")) and not bool(world.get("preparing_roam")) and not bool(world.get("preparing_room")))
	actor.call("cancel_jump_input")
	# Return Space/Tab to jumping and view switching after leaving the menu.
	get_viewport().gui_release_focus()

func _input(event: InputEvent) -> void:
	if is_settings_open() and event.is_action_pressed("ui_cancel"):
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
