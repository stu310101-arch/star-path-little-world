extends Node
## Content selection is independent of the existing render-quality preferences.
signal selected
const SETTINGS: String = "user://resource_profile.cfg"
const WORLDS: Dictionary = {"full":"res://scenes/world.tscn", "low":"res://scenes/world_low.tscn"}
var profile: String = ""
var _layer: CanvasLayer
var _status: Label
var _busy: bool = false
var _keep_old: CheckBox
var _previous_paused: bool = false
var _telemetry_clock: float = 0.0
var _telemetry: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("web"):
		_telemetry = bool(JavaScriptBridge.eval("new URLSearchParams(location.search).has('performance')"))
		var choice: String = str(JavaScriptBridge.eval("window.LittleWorldResourceProfile || ''"))
		if WORLDS.has(choice):
			profile = choice
	else:
		var config: ConfigFile = ConfigFile.new()
		if config.load(SETTINGS) == OK:
			var choice: String = str(config.get_value("content", "profile", ""))
			if WORLDS.has(choice):
				profile = choice
	# Test/review overrides never overwrite a player's persistent choice.
	for argument: String in OS.get_cmdline_user_args():
		if argument in ["--resources=low", "--resources=full"]:
			profile = argument.trim_prefix("--resources=")

func is_low() -> bool:
	return profile == "low"

func world_path() -> String:
	return str(WORLDS.get(profile, WORLDS.full))

func prepare_entry() -> void:
	if profile.is_empty():
		_show_choices()
		await selected
	_show_progress()
	var packs: Node = get_node("/root/WebPacks")
	if OS.has_feature("web"):
		await _browser_store("reserve", profile)
	packs.call("select_profile", profile)
	packs.call("start_all_downloads")
	while not bool((packs.call("profile_progress", profile) as Dictionary).ready):
		var progress: Dictionary = packs.call("profile_progress", profile)
		var error: String = str(progress.get("error", ""))
		_status.text = error if not error.is_empty() else "準備%s材質包… %.1f / %.1f MB" % ["低階" if is_low() else "滿血", float(progress.get("received_bytes", 0)) / 1048576.0, float(progress.get("total_bytes", 0)) / 1048576.0]
		await get_tree().process_frame
	if OS.has_feature("web"):
		await _browser_store("retain", profile)
	_layer.queue_free()
	_layer = null

func _panel() -> VBoxContainer:
	_layer = CanvasLayer.new()
	_layer.layer = 120
	add_child(_layer)
	var background: ColorRect = ColorRect.new()
	background.color = Color("173b3d")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(background)
	var margin: MarginContainer = MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	background.add_child(margin)
	var fit: Callable = func() -> void:
		var inset: int = maxi(24, int((background.size.x - 560.0) * .5))
		margin.add_theme_constant_override("margin_left", inset)
		margin.add_theme_constant_override("margin_right", inset)
	background.resized.connect(fit)
	fit.call()
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var panel: VBoxContainer = VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 18)
	panel.add_theme_font_override("font", preload("res://assets/fonts/NotoSansTC.ttf"))
	scroll.add_child(panel)
	var title: Label = Label.new()
	title.text = "星途 · 選擇遊戲材質包"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 26)
	panel.add_child(title)
	return panel

func _show_choices() -> void:
	var panel: VBoxContainer = _panel()
	var help: Label = Label.new()
	help.text = "低階：簡化材質、建物與裝飾，保留探索與留言功能。\n滿血：使用現有完整場景與美術。\n設定會保存在這台裝置；可在遊戲設定切換。"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 18)
	panel.add_child(help)
	for value: String in ["low", "full"]:
		var button: Button = Button.new()
		button.name = "SelectResources_" + value
		button.text = "使用低階材質包" if value == "low" else "使用滿血材質包"
		button.custom_minimum_size.y = 58
		button.pressed.connect(_choose.bind(value))
		panel.add_child(button)

func _choose(value: String) -> void:
	profile = value
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "profile", profile)
	config.save(SETTINGS)
	_layer.queue_free()
	_layer = null
	selected.emit()

func _show_progress() -> void:
	var panel: VBoxContainer = _panel()
	_status = Label.new()
	_status.text = "準備遊戲內容…"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)
	var retry: Button = Button.new()
	retry.text = "下載失敗時重試"
	retry.custom_minimum_size.y = 48
	retry.pressed.connect(func() -> void: get_node("/root/WebPacks").call("retry_failed"))
	panel.add_child(retry)
	var change: Button = Button.new()
	change.text = "重新選擇材質包"
	change.pressed.connect(_choose_again)
	panel.add_child(change)

func _choose_again() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.LittleWorldChooseResources()")
	elif not OS.has_feature("editor"):
		DirAccess.remove_absolute(SETTINGS)
		OS.set_restart_on_exit(true)
		get_tree().quit()

func change_on_restart() -> void:
	if _busy:
		return
	if is_instance_valid(_layer):
		_layer.queue_free()
	_previous_paused = get_tree().paused
	get_tree().paused = true
	if OS.has_feature("web"):
		await _browser_store("status", profile)
	_show_manager()

func _show_manager() -> void:
	var panel: VBoxContainer = _panel()
	var packs: Node = get_node("/root/WebPacks")
	_status = Label.new()
	_status.text = "目前使用：%s材質包\n下載完成後重新啟動套用；帳號與探索進度會保留。" % _title(profile)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)
	_keep_old = CheckBox.new()
	_keep_old.name = "KeepPreviousResourcePack"
	_keep_old.text = "切換後保留原材質包"
	_keep_old.button_pressed = true
	panel.add_child(_keep_old)
	if OS.has_feature("web"):
		var install: Button = Button.new()
		install.text = "加入手機主畫面"
		install.pressed.connect(func() -> void: JavaScriptBridge.eval("window.LittleWorldInstallApp()"))
		panel.add_child(install)
	for target: String in ["low", "full"]:
		var cached: bool = packs.call("profile_cached", target)
		var button: Button = Button.new()
		button.name = "ManageResources_" + target
		button.text = "%s材質包 · %s" % [_title(target), "目前使用" if target == profile else "已下載，切換使用" if cached else "下載並切換"]
		button.disabled = target == profile
		button.custom_minimum_size.y = 54
		button.pressed.connect(_download_and_switch.bind(target))
		panel.add_child(button)
		if target != profile:
			var remove: Button = Button.new()
			remove.text = "刪除已保留的%s材質包" % _title(target) if cached else "清除%s包下載快取" % _title(target)
			remove.pressed.connect(_delete_inactive.bind(target))
			panel.add_child(remove)
	var close: Button = Button.new()
	close.name = "CloseResourceManager"
	close.text = "返回"
	close.custom_minimum_size.y = 48
	close.pressed.connect(func() -> void:
		if not _busy:
			_layer.queue_free()
			_layer = null
			get_tree().paused = _previous_paused)
	panel.add_child(close)

func _download_and_switch(target: String) -> void:
	if _busy:
		return
	_busy = true
	var keep: bool = _keep_old.button_pressed
	var packs: Node = get_node("/root/WebPacks")
	if OS.has_feature("web"):
		await _browser_store("reserve", target)
	packs.call("retry_failed")
	packs.call("request_profile", target)
	while true:
		var progress: Dictionary = packs.call("profile_progress", target)
		if not str(progress.error).is_empty():
			_status.text = str(progress.error) + "\n請再次按下載重試。"
			_busy = false
			return
		_status.text = "下載%s材質包… %.1f / %.1f MB" % [_title(target), float(progress.received_bytes) / 1048576.0, float(progress.total_bytes) / 1048576.0]
		if bool(progress.ready):
			break
		await get_tree().process_frame
	if OS.has_feature("web"):
		if not await _browser_store("retain", target):
			_status.text = "瀏覽器無法保留完整資源包，請檢查可用儲存空間後重試。"
			_busy = false
			return
		if keep:
			await _browser_store("retain", profile)
		else:
			await _browser_store("delete", profile)
	elif not keep:
		packs.call("delete_cached_profile", profile, target)
	_restart_with(target)

func _delete_inactive(target: String) -> void:
	if _busy or target == profile:
		return
	_busy = true
	if OS.has_feature("web"):
		await _browser_store("delete", target)
	else:
		get_node("/root/WebPacks").call("delete_cached_profile", target, profile)
	_busy = false
	_layer.queue_free()
	_show_manager()

func _browser_store(action: String, target: String) -> bool:
	var store: JavaScriptObject = JavaScriptBridge.get_interface("LittleWorldResourceStore")
	if store == null:
		return false
	store.run(action, target)
	while bool(store.busy):
		await get_tree().process_frame
	return bool(store.ok)

func _restart_with(target: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.LittleWorldUseResources('%s')" % target)
		return
	var config: ConfigFile = ConfigFile.new()
	config.set_value("content", "profile", target)
	config.save(SETTINGS)
	if not OS.has_feature("editor"):
		OS.set_restart_on_exit(true)
		get_tree().quit()
	else:
		_status.text = "已下載%s材質包。請停止並重新執行遊戲套用。" % _title(target)
		_busy = false

func _title(value: String) -> String:
	return "低階" if value == "low" else "滿血"

func _process(delta: float) -> void:
	if not _telemetry:
		return
	_telemetry_clock += delta
	if _telemetry_clock < .2:
		return
	_telemetry_clock = 0
	var buttons: Array[Dictionary] = []
	if is_instance_valid(_layer):
		var size: Vector2 = get_viewport().get_visible_rect().size
		for child: Node in _layer.find_children("*", "Button", true, false):
			var button: Button = child as Button
			var point: Vector2 = (button.global_position + button.size * .5) / size
			buttons.append({"name":str(button.name),"text":button.text,"disabled":button.disabled,"pressed":button.button_pressed,"center":[point.x,point.y]})
	var state: Dictionary = {"profile":profile,"busy":_busy,"status":_status.text if is_instance_valid(_status) else "","buttons":buttons}
	JavaScriptBridge.eval("window.resourcePackState = " + JSON.stringify(state))
