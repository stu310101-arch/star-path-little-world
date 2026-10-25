extends SceneTree

class Recorder:
	extends Node
	var room: Node3D
	var rows: Array[Dictionary] = []
	var enabled: bool = false
	func _process(delta: float) -> void:
		if not enabled: return
		var player: PlanetPlayer = room.get("player")
		var camera: Camera3D = room.get("camera")
		var aim: Vector3 = player.get_render_transform().origin + Vector3.UP * 1.12
		var offset: Vector3 = camera.global_position - aim
		rows.append({"delta":delta,"height":player.position.y,"distance":offset.length(),"pitch":atan2(offset.y,Vector2(offset.x,offset.z).length()),"grounded":player.is_on_floor(),"speed":player.velocity.slide(Vector3.UP).length()})

var failures: int = 0
var runs: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var diagnostic: bool = OS.get_cmdline_user_args().has("--before")
	var room: Node3D = (load("res://scenes/training_room.tscn") as PackedScene).instantiate()
	root.add_child(room)
	current_scene = room
	var deadline: int = Time.get_ticks_msec()+60000
	while not bool(room.get("ready_for_play")) and Time.get_ticks_msec()<deadline:
		await process_frame
	if not bool(room.get("ready_for_play")):
		push_error("Training room did not load")
		quit(1)
		return
	var player: PlanetPlayer = room.get("player")
	player.allow_test_input = true
	var recorder := Recorder.new()
	recorder.room = room
	recorder.process_priority = 1000
	root.add_child(recorder)
	for fps: int in [30,45,90]:
		Engine.max_fps = fps
		player.test_direction = Vector2.ZERO
		player.call("place_at",Vector3(-2.5,.09,4.7),Vector3.FORWARD)
		room.set("camera_yaw",0.0)
		room.call("update_camera",0.0,true)
		await create_timer(.4).timeout
		player.test_direction = Vector2(0,-1)
		await create_timer(.4).timeout
		recorder.rows.clear()
		recorder.enabled = true
		await create_timer(1.25).timeout
		recorder.enabled = false
		if OS.get_cmdline_user_args().has("--capture"):
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../deliverables/world-correction/training-walk-%d.png" % fps)
		player.test_direction = Vector2.ZERO
		var distances: Array[float] = []
		var pitches: Array[float] = []
		var heights: Array[float] = []
		var grounded: bool = true
		var min_speed: float = INF
		for row: Dictionary in recorder.rows:
			distances.append(row.distance)
			pitches.append(row.pitch)
			heights.append(row.height)
			grounded = grounded and bool(row.grounded)
			min_speed = minf(min_speed,float(row.speed))
		var distance_range: float = distances.max()-distances.min()
		var pitch_range: float = rad_to_deg(pitches.max()-pitches.min())
		var passed: bool = grounded and min_speed>3.7 and heights.max()-heights.min()<.001 and distance_range<.004 and pitch_range<.06
		if not passed: failures += 1
		var result: Dictionary = {"fps":fps,"samples":recorder.rows.size(),"passed":passed,"grounded":grounded,"min_speed":min_speed,"height_range":heights.max()-heights.min(),"camera_distance_range":distance_range,"camera_pitch_range_degrees":pitch_range}
		runs.append(result)
		print("TRAINING_CAMERA ",JSON.stringify(result))
	var path: String = "res://../deliverables/world-correction/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))
	FileAccess.open(path+("camera-before.json" if diagnostic else "camera-after.json"),FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"runs":runs},"\t"))
	room.free()
	recorder.free()
	quit(0 if diagnostic or failures==0 else 1)
