extends CanvasLayer

## Game-owned terminal bezel. The visible room stays around its bounded screen.
signal return_requested
signal retry_requested
signal bounds_changed(rect: Rect2)

const FONT: Font = preload("res://assets/fonts/NotoSansTC.ttf")
const TITLES: Dictionary = {"query":"落點分析工作台", "general":"一般大學工作台", "special":"特殊招生工作台", "apcs":"APCS 工作台", "scores":"我的成績紀錄", "account":"星途共用帳號", "forum":"校園交流留言", "wordking":"星途單字王", "go":"星途圍棋"}
var panel: Panel
var screen: Panel
var status: CenterContainer
var message: Label
var retry: Button
var back: Button
var title: Label
var footer: Label
var screen_rect: Rect2

static func panel_rect(viewport: Vector2, compact: bool = false) -> Rect2:
	if compact or viewport.x / maxf(viewport.y, 1.0) < 1.25:
		var margin: Vector2 = Vector2(8, maxf(8, viewport.y * .035))
		return Rect2(margin, viewport - margin * 2)
	var dimensions: Vector2 = Vector2(viewport.x * .78, viewport.y * .82)
	return Rect2(Vector2(viewport.x * .185, viewport.y * .09), dimensions)

func _ready() -> void:
	layer = 95
	var shade := ColorRect.new()
	shade.color = Color(.035, .11, .12, .23)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	panel = Panel.new()
	panel.add_theme_stylebox_override("panel", _style(Color("173b3d"), Color("bba576"), 18, 2))
	shade.add_child(panel)
	title = _label("落點分析工作台", 22, Color("f6ecd3"))
	panel.add_child(title)
	back = _button("離開螢幕  Esc")
	back.pressed.connect(func() -> void: return_requested.emit())
	panel.add_child(back)
	screen = Panel.new()
	screen.add_theme_stylebox_override("panel", _style(Color("f6f3e9"), Color("82978b"), 3, 1))
	panel.add_child(screen)
	status = CenterContainer.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(status)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	status.add_child(column)
	message = _label("正在開啟工作台…", 20, Color("244f4b"))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(message)
	retry = _button("重新連線")
	retry.pressed.connect(func() -> void: retry_requested.emit())
	column.add_child(retry)
	footer = _label("星途・學習工作站    /    每一次練習，都讓方向更清楚", 12, Color("b9c7b8"))
	panel.add_child(footer)
	get_viewport().size_changed.connect(relayout)
	relayout()
	hide()

func _style(color: Color, border: Color, radius: int, width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	return style

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.add_theme_font_override("font", FONT)
	button.add_theme_font_size_override("font_size", 17)
	for state: String in ["normal", "hover", "pressed", "focus"]:
		button.add_theme_stylebox_override(state, _style(Color("efd7a5") if state == "normal" else Color("fff0ca"), Color("d7b878"), 9, 1))
		button.add_theme_color_override("font_" + state + "_color", Color("203e46"))
	button.add_theme_color_override("font_color", Color("203e46"))
	return button

func set_view(view: String) -> void:
	title.text = str(TITLES.get(view, TITLES.query))

func relayout() -> void:
	if panel == null:
		return
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var compact: bool = get_window().size.x < 900 or viewport.x / maxf(viewport.y, 1) < 1.25
	var rect: Rect2 = panel_rect(viewport, compact)
	panel.position = rect.position
	panel.size = rect.size
	var pad: float = 9 if compact else 14
	title.position = Vector2(pad + 8, 10)
	title.size = Vector2(maxf(50, rect.size.x - 200), 42)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 18 if compact else 22)
	back.position = Vector2(rect.size.x - 166, 10)
	back.size = Vector2(150, 44)
	screen.position = Vector2(pad, 64)
	screen.size = Vector2(rect.size.x - pad * 2, maxf(50, rect.size.y - 94))
	footer.position = Vector2(pad + 4, rect.size.y - 26)
	footer.size = Vector2(rect.size.x - pad * 2, 22)
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	screen_rect = Rect2(rect.position + screen.position + Vector2.ONE, screen.size - Vector2.ONE * 2)
	bounds_changed.emit(screen_rect)
