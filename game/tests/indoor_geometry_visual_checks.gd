extends SceneTree
## Fixed native-rendered indoor geometry views. Changes only fixture cameras.
const OUTPUT: String = "res://../deliverables/graphics-performance/indoor-visual/"
var captures: Array[Dictionary] = []
var failures: Array[String] = []
var room: Node3D

func _initialize() -> void:
	call_deferred("_run")

func _tick(frames: int = 4) -> void:
	for index: int in range(frames):
		await process_frame

func _load_room(path: String) -> bool:
	if is_instance_valid(room):
		root.remove_child(room)
		room.queue_free()
		await _tick()
	room = (load(path) as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	var deadline: int = Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < deadline:
		if bool(room.get("ready_for_play")) and str(room.get("detail_state")) == "ready":
			await _tick(10)
			room.set_process(false)
			return true
		await _tick()
	failures.append("Room did not finish loading: " + path)
	return false

func _capture(label: String, at: Vector3, target: Vector3, fov: float = 70.0) -> void:
	var camera: Camera3D = room.get("camera") as Camera3D
	camera.position = at
	camera.fov = fov
	camera.look_at(target, Vector3.UP)
	await _tick(5)
	await RenderingServer.frame_post_draw
	var file: String = ProjectSettings.globalize_path(OUTPUT + label + ".png")
	var error: Error = root.get_texture().get_image().save_png(file)
	if error != OK:
		failures.append("Cannot save " + label)
	captures.append({"view": label, "camera": [at.x, at.y, at.z], "target": [target.x, target.y, target.z], "image": file})

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Requires real renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	Engine.max_fps = 30
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	if await _load_room("res://scenes/admissions_room.tscn"):
		await _capture("admissions-entry", Vector3(0, 1.7, 5.8), Vector3(0, 1.5, -3))
		await _capture("admissions-general", Vector3(-2.7, 1.6, -.1), Vector3(-5.2, .9, -2.7))
		await _capture("admissions-special", Vector3(1.2, 1.7, -2.0), Vector3(-.4, 1.2, -5.5))
		await _capture("admissions-apcs", Vector3(3.5, 1.7, -.2), Vector3(6.6, 1.2, -2.7))
		await _capture("admissions-passport", Vector3(5.2, 1.7, 5.5), Vector3(5.2, .8, 2.8))
		await _capture("admissions-ceiling", Vector3(1, 1.7, 3), Vector3(0, 4.9, -2))
		await _capture("admissions-low-floor", Vector3(-4, .19, 1), Vector3(-7.9, -.01, -2))
	if await _load_room("res://scenes/training_room.tscn"):
		await _capture("training-entry", Vector3(0, 1.7, 8.4), Vector3(0, 1.4, -3))
		await _capture("training-backdrop", Vector3(0, 1.7, -4.5), Vector3(0, 2.0, -8.8))
		await _capture("training-ceiling", Vector3(0, 1.7, 5), Vector3(1, 3.35, -3))
		await _capture("training-low-floor", Vector3(3, .4, 5), Vector3(0, .035, 0))
		await _capture("training-lounge", Vector3(-3, 1.7, 1), Vector3(-7.1, .9, -1))
		await _capture("training-computers", Vector3(-2, 1.7, 4), Vector3(-7.7, 1.2, 3))
		await _capture("training-display", Vector3(3, 1.7, -2), Vector3(6.2, 1.4, -2))
	if await _load_room("res://scenes/university_hall.tscn"):
		await _capture("university-atrium", Vector3(0, 1.8, 10.5), Vector3(0, 3, -6), 76)
		await _capture("university-atrium-ceiling", Vector3(0, 1.8, 3), Vector3(0, 8.8, -4), 76)
		await _capture("university-atrium-side", Vector3(-9, 1.6, 4), Vector3(-14.8, 2, -2), 76)
		room.call("show_region", "north", 0)
		room.set_process(false)
		await _tick(10)
		await _capture("university-gallery", Vector3(0, 1.8, 16.5), Vector3(0, 2, -8), 76)
		await _capture("university-gallery-ceiling", Vector3(0, 1.8, 6), Vector3(0, 8.8, -4), 76)
		await _capture("university-gallery-left", Vector3(-3.3, 1.6, 12), Vector3(-9.2, 1.25, 12), 65)
		await _capture("university-gallery-right", Vector3(3.3, 1.6, 12), Vector3(9.2, 1.25, 12), 65)
	var report: Dictionary = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_current_rendering_method(),
		"captures": captures, "failures": failures, "scope": "Actual indoor GLBs/runtime resources with production materials and lights; fixed cameras inside valid room volumes; no gameplay settings or asset substitutions."}
	FileAccess.open(OUTPUT + "report.json", FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	if is_instance_valid(room):
		room.queue_free()
	await _tick()
	print("INDOOR_VISUAL_CAPTURES ", captures.size(), " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
