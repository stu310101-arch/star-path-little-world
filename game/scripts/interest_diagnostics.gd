extends Node
## Opt-in UI geometry only. Never publishes scores, names, dates, IDs or text input.
var enabled: bool = false
var clock: float = 0.0
var acknowledgments: int = 0
var panel_mode: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel_mode = get_parent().has_method("open_panel")
	enabled = OS.get_cmdline_user_args().has("--performance")
	if OS.has_feature("web"):
		enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	set_process(enabled)
	if panel_mode and enabled:
		get_parent().get("controller").connect("saved",func(_action: String) -> void: acknowledgments += 1)

func _process(delta: float) -> void:
	clock += delta
	if clock < 0.4:
		return
	clock = 0.0
	_publish(snapshot())

func _exit_tree() -> void:
	if enabled:
		_publish({"ticks_ms":Time.get_ticks_msec(),"open":false,"present":false})

func _publish(value: Dictionary) -> void:
	if enabled and OS.has_feature("web"):
		var target: String = "interestDiagnostics" if panel_mode else "counselingDiagnostics"
		JavaScriptBridge.eval("window."+target+"="+JSON.stringify(value)+";")

func control_geometry(control: Control) -> Dictionary:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var point: Vector2 = control.get_global_transform_with_canvas()*(control.size*0.5)
	var clipped: bool = not control.is_visible_in_tree() or not Rect2(Vector2.ZERO,viewport).has_point(point)
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			var clipping_control: Control = ancestor as Control
			var local_point: Vector2 = clipping_control.get_global_transform_with_canvas().affine_inverse()*point
			clipped = clipped or not Rect2(Vector2.ZERO,clipping_control.size).has_point(local_point)
		ancestor = ancestor.get_parent()
	var normalized: Vector2 = point/viewport
	return {"center":[normalized.x,normalized.y],"visible":not clipped,"size":[control.size.x,control.size.y]}

func snapshot() -> Dictionary:
	var source: Node = get_parent()
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var result: Dictionary = {"ticks_ms":Time.get_ticks_msec(),"present":true,"viewport":[viewport.x,viewport.y]}
	var buttons: Array[Dictionary] = []
	for node: Node in source.find_children("*","Button",true,false):
		if node is OptionButton or not (node as Control).is_visible_in_tree() or node.get_viewport() != get_viewport():
			continue
		var info: Dictionary = control_geometry(node as Control)
		info.merge({"name":str(node.name),"text":(node as Button).text,"disabled":(node as Button).disabled})
		buttons.append(info)
	result["buttons"] = buttons
	if panel_mode:
		result["open"] = (source as Control).is_visible_in_tree()
		result["save_acknowledgments"] = acknowledgments
		result["busy"] = source.get("controller").call("busy")
		result["dialog_open"] = (source.get("dialog") as Window).visible
		var fields: Dictionary = {}
		for field: String in source.get("inputs"):
			fields[field] = control_geometry(source.get("inputs")[field])
		result["fields"] = fields
		var tabs: TabContainer = source.get("tabs")
		var bar: TabBar = tabs.get_tab_bar()
		var tab_items: Array[Dictionary] = []
		for index: int in range(tabs.get_tab_count()):
			var rect: Rect2 = bar.get_tab_rect(index)
			var center: Vector2 = (bar.get_global_transform_with_canvas()*rect.get_center())/viewport
			tab_items.append({"index":index,"text":tabs.get_tab_title(index),"center":[center.x,center.y],"visible":bar.is_visible_in_tree() and bar.get_global_rect().has_point(bar.global_position+rect.get_center())})
		result["tab_index"] = tabs.current_tab
		result["tabs"] = tab_items
	else:
		result["ready"] = bool(source.get("ready_for_play"))
		var player: Node3D = source.get("player")
		if is_instance_valid(player):
			result["player"] = {"position":[player.position.x,player.position.y,player.position.z],"controls_enabled":bool(player.get("controls_enabled"))}
	return result
