extends SceneTree

class Recorder:
	extends Node
	var hall: Node3D
	var active: bool = false
	var frames: Array[Dictionary] = []
	func _process(delta: float) -> void:
		if not active:
			return
		var player: CharacterBody3D = hall.get("player") as CharacterBody3D
		var camera: Camera3D = hall.get("camera") as Camera3D
		var aim: Vector3 = player.global_position + Vector3.UP * 1.25
		frames.append({"delta":delta,"y":player.position.y,"player":[player.position.x,player.position.y,player.position.z],"camera":[camera.position.x,camera.position.y,camera.position.z],"distance":camera.position.distance_to(aim),"pitch":atan2(camera.position.y-aim.y,Vector2(camera.position.x-aim.x,camera.position.z-aim.z).length()),"grounded":player.is_on_floor(),"speed":Vector2(player.velocity.x,player.velocity.z).length()})

var hall: Node3D
var checks: Array[Dictionary] = []
var runs: Array[Dictionary] = []
var failures: int = 0
var recorder: Recorder
var diagnostic: bool = false
var capture: bool = false
const CAPTURE_DIR: String = "res://../deliverables/university-hall/movement/"

func _initialize() -> void:
	diagnostic = "--diagnostic" in OS.get_cmdline_user_args()
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(title: String, passed: bool, detail: Variant = "") -> void:
	checks.append({"name":title,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(title + " " + str(detail))

func walk_route(label_value: String, start: Vector3, direction: Vector3, yaw: float, fps: int) -> void:
	Engine.max_fps = fps
	var player: CharacterBody3D = hall.get("player") as CharacterBody3D
	player.set("allow_test_input", true)
	player.set("test_direction", Vector2.ZERO)
	hall.set("camera_yaw", yaw)
	player.call("place_at", start, direction)
	hall.call("update_camera", 0, true)
	for index: int in range(30):
		await physics_frame
	player.set("test_direction", Vector2(0,-1))
	# Discard acceleration of the old camera to expose its steady walking jitter.
	for index: int in range(45):
		await physics_frame
	recorder.frames.clear()
	recorder.active = true
	for index: int in range(90):
		await physics_frame
		if capture and fps == 45 and label_value == "gallery beside exhibit tables" and index in [0,30,60]:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(CAPTURE_DIR + "walking-%02d.png" % index)
	recorder.active = false
	player.set("test_direction", Vector2.ZERO)
	var min_y: float = INF
	var max_y: float = -INF
	var min_distance: float = INF
	var max_distance: float = -INF
	var min_pitch: float = INF
	var max_pitch: float = -INF
	var grounded: int = 0
	var min_speed: float = INF
	var max_speed: float = -INF
	for frame: Dictionary in recorder.frames:
		min_y = minf(min_y, float(frame.y))
		max_y = maxf(max_y, float(frame.y))
		min_distance = minf(min_distance, float(frame.distance))
		max_distance = maxf(max_distance, float(frame.distance))
		min_pitch = minf(min_pitch, float(frame.pitch))
		max_pitch = maxf(max_pitch, float(frame.pitch))
		min_speed = minf(min_speed, float(frame.speed))
		max_speed = maxf(max_speed, float(frame.speed))
		grounded += int(frame.grounded)
	var metrics: Dictionary = {"route":label_value,"fps_cap":fps,"frames":recorder.frames.size(),"grounded_frames":grounded,"floor_y_range_m":max_y-min_y,"camera_distance_range_m":max_distance-min_distance,"camera_pitch_range_degrees":rad_to_deg(max_pitch-min_pitch),"min_speed":min_speed,"max_speed":max_speed,"trajectory":recorder.frames.duplicate(true)}
	runs.append(metrics)
	check(label_value + " real player remains grounded at " + str(fps) + " fps", grounded == recorder.frames.size() and min_speed > 3.7 and max_y-min_y < .001, {"grounded":grounded,"frames":recorder.frames.size(),"min_speed":min_speed,"y_range":max_y-min_y})
	check(label_value + " camera does not oscillate relative to a steadily walking player at " + str(fps) + " fps", diagnostic or (max_distance-min_distance < .004 and rad_to_deg(max_pitch-min_pitch) < .06), {"distance_range_m":max_distance-min_distance,"pitch_range_degrees":rad_to_deg(max_pitch-min_pitch)})
	print("MOVEMENT_ROUTE ", label_value, " fps=",fps," floor_range=",max_y-min_y," camera_distance_range=",max_distance-min_distance," pitch_range=",rad_to_deg(max_pitch-min_pitch))

func run() -> void:
	root.size = Vector2i(1280, 800)
	if capture:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	Engine.max_fps = 0
	hall = (load("res://scenes/university_hall.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hall)
	current_scene = hall
	var deadline: int = Time.get_ticks_msec() + 60000
	while not bool(hall.get("ready_for_play")) and Time.get_ticks_msec() < deadline:
		await process_frame
	check("Actual exhibition hall and graduate avatar finish loading", bool(hall.get("ready_for_play")), hall.get("detail_error"))
	if not bool(hall.get("ready_for_play")):
		quit(1)
		return
	recorder = Recorder.new()
	recorder.hall = hall
	recorder.process_priority = 1000
	root.add_child(recorder)
	for fps: int in [30,45]:
		hall.call("show_atrium", false)
		await walk_route("atrium clear aisle", Vector3(3,.08,6), Vector3.FORWARD, 0, fps)
		hall.call("show_region", "north", 0)
		await walk_route("gallery centre aisle", Vector3(0,.08,14), Vector3.FORWARD, 0, fps)
		await walk_route("gallery beside exhibit tables", Vector3(-6,.08,14), Vector3.FORWARD, PI*.5, fps)
	var output: Dictionary = {"passed":failures==0,"failed":failures,"diagnostic":diagnostic,"renderer":DisplayServer.get_name(),"physics_ticks_per_second":Engine.physics_ticks_per_second,"rendered_captures":capture,"checks":checks,"runs":runs}
	var path: String = "res://tests/university_movement_before.json" if diagnostic else "res://tests/university_movement_results.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	file.close()
	print("UNIVERSITY_MOVEMENT_CHECKS failed=",failures," runs=",runs.size())
	for voice: Node in hall.find_children("*", "AudioStreamPlayer", true, false):
		(voice as AudioStreamPlayer).stop()
	await create_timer(.15).timeout
	hall.queue_free()
	recorder.queue_free()
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)
