extends Node
## Opt-in, read-only geometry/status. Never publishes scores, titles, IDs or input values.
var enabled: bool = false
var elapsed: float = 0.0
var panel_mode: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel_mode = get_parent().has_method("open_panel")
	enabled = OS.get_cmdline_user_args().has("--performance")
	if OS.has_feature("web"):
		enabled = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
	set_process(enabled)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.4: return
	elapsed = 0.0
	_publish(snapshot())

func _exit_tree() -> void:
	if enabled: _publish({"ticks_ms":Time.get_ticks_msec(),"open":false,"present":false})

func _publish(value: Dictionary) -> void:
	if enabled and OS.has_feature("web"):
		var channel: String = "recommendationDiagnostics" if panel_mode else "recommendationRoomDiagnostics"
		JavaScriptBridge.eval("window."+channel+"="+JSON.stringify(value)+";")

func _geometry(control: Control) -> Dictionary:
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var transform: Transform2D = control.get_global_transform_with_canvas()
	var point: Vector2 = transform*(control.size*0.5)
	var clipped: bool = not control.is_visible_in_tree() or not Rect2(Vector2.ZERO,viewport).has_point(point)
	var ancestor: Node = control.get_parent()
	while ancestor != null:
		if ancestor is Control and (ancestor as Control).clip_contents:
			var clip: Control = ancestor as Control
			clipped = clipped or not Rect2(Vector2.ZERO,clip.size).has_point(clip.get_global_transform_with_canvas().affine_inverse()*point)
		ancestor = ancestor.get_parent()
	var normalized: Vector2 = point/viewport
	var extent: Vector2 = transform.basis_xform(control.size)
	return {"center":[normalized.x,normalized.y],"visible":not clipped,"size":[absf(extent.x),absf(extent.y)]}

func snapshot() -> Dictionary:
	var source: Node = get_parent()
	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var result: Dictionary = {"ticks_ms":Time.get_ticks_msec(),"present":true,"viewport":[viewport.x,viewport.y]}
	var button_root: Node = source.get("shell") if panel_mode else source.get("ui_root")
	var buttons: Array[Dictionary] = []
	var options: Array[Dictionary] = []
	if is_instance_valid(button_root):
		for node: Node in button_root.find_children("*","Button",true,false):
			if not (node as Control).is_visible_in_tree() or node.get_viewport()!=get_viewport(): continue
			var info: Dictionary = _geometry(node as Control)
			info.merge({"name":str(node.name),"disabled":(node as Button).disabled})
			if node is OptionButton:
				info.merge({"selected":(node as OptionButton).selected,"count":(node as OptionButton).item_count})
				options.append(info)
			else:
				# These are action labels, never content labels or LineEdit values.
				info["text"] = (node as Button).text
				buttons.append(info)
	result["buttons"] = buttons
	result["options"] = options
	if panel_mode:
		var settings: Dictionary = source.get("settings")
		result.merge({"open":(source as Control).is_visible_in_tree(),"tab_index":int(source.get("page_index")),"busy":bool(source.get("controller").call("busy")),"error":bool(source.get("controller").get("error")),"mode":str(settings.get("mode","")),"source":str(settings.get("source","")),"has_exam":not str(settings.get("examId","")).is_empty(),"has_report":source.get("active_report") is Dictionary,"results_count":(source.get("rows") as Array).size(),"choice_count":(source.get("choices") as Array).size(),"comparison_count":(source.get("comparison") as Array).size(),"favorite_count":(source.get("favorite_rows") as Array).size(),"manual_count":(settings.get("manual",[]) as Array).size()})
		result["result_page"]=int(source.get("result_page"))
	else:
		result["ready"] = bool(source.get("ready_for_play"))
		result["resource_profile"] = "low" if str(source.get("model_path")).contains("/generated/low/") else "full"
		var player: Node3D = source.get("player")
		if is_instance_valid(player): result["player"] = {"position":[player.position.x,player.position.y,player.position.z],"controls_enabled":bool(player.get("controls_enabled"))}
	return result
