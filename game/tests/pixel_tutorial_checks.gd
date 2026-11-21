extends SceneTree
## Headless smoke: godot --headless --path game --script res://tests/pixel_tutorial_checks.gd

const Content = preload("res://scripts/pixel_tutorial_content.gd")
const Tutorial = preload("res://scenes/pixel_tutorial.tscn")
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _expect(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)

func _run() -> void:
	var definitions: Array[Dictionary] = Content.stations()
	_expect(definitions.size() == 15, "教學應有 15 個完整的功能展台")
	var seen_titles: Dictionary = {}
	for step in definitions:
		_expect(str(step.get("title", "")) != "", "展台缺少標題")
		_expect(str(step.get("lesson", "")).length() >= 15, "展台講解過短")
		var choices: Array = step.get("choices", [])
		_expect(choices.size() == 3, "每站應有 3 個選項")
		_expect(int(step.get("answer", -1)) in [0, 1, 2], "正確答案索引不合法")
		_expect(not seen_titles.has(str(step.get("title", ""))), "站點標題重複")
		seen_titles[str(step.get("title", ""))] = true
	var room: Node3D = Tutorial.instantiate() as Node3D
	_expect(room != null, "3D 場景載入失敗")
	if room != null:
		root.add_child(room)
		await process_frame
		_expect(room.has_signal("request_return_to_world"), "缺少返回世界訊號")
		_expect((room.get("positions") as Array).size() == 15, "站點沒有建立位置")
		_expect((room.get("beacons") as Array).size() == 15, "站點沒有建立體素信標")
		_expect(room.get_node_or_null("Dragon") != null, "缺少可操控的龍角色")
		_expect(room.get_node_or_null("DragonCamera") != null, "缺少 3D 跟隨相機")
		_expect(room.get_node_or_null("TutorialHUD") != null, "缺少教學 UI")
		room.set("distance_walked", 5.0)
		room.set("jump_count", 1)
		room.set("camera_drag_amount", 80.0)
		for i in range(definitions.size()):
			room.call("_open_station", i)
			room.call("_answer", int(definitions[i]["answer"]))
			_expect(bool((room.get("finished") as Array)[i]), "站點 %d 答題沒有完成" % i)
			room.call("_close_modal")
		_expect(int(room.call("_completed_count")) == 15, "全破進度應是 15")
		room.call("_open_map")
		_expect((room.get("map_overlay") as Control).visible, "地圖應可開啟")
		room.call("_close_map")
		_expect(not (room.get("map_overlay") as Control).visible, "地圖應可關閉")
		room.queue_free()
	if errors.is_empty():
		print("PIXEL_TUTORIAL_CHECKS_OK stations=15")
	else:
		for error in errors:
			push_error("PIXEL_TUTORIAL_CHECKS_FAIL: " + error)
	quit(0 if errors.is_empty() else 1)
