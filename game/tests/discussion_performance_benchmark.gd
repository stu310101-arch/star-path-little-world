extends SceneTree
## Explicitly uncapped, forced native rendering; never an invisible/headless FPS proxy.
const Garden = preload("res://scripts/discussion_garden.gd")
class Quality:
	extends Node
	signal state_changed
	var quality_profile: String = "mobile"
	func is_low_quality() -> bool: return true
	func is_constrained_runtime() -> bool: return true
	func is_mobile_performance_profile() -> bool: return true
class Account:
	extends Node
	signal forum_message(packet: Dictionary)
	signal closed
	signal state_changed(user: Dictionary)
	var user: Dictionary = {"profileReady":true,"sessionGeneration":7}
	func request_forum_page(_command: Dictionary) -> bool: return false
	func open_view(_view: String) -> bool: return false
var room: Node3D
var camera: Camera3D
var player: CharacterBody3D
var output: String = "res://../deliverables/discussion-overhaul/performance/baseline.json"
var report: Dictionary = {"samples":[],"errors":[]}
var optimize: bool = false
var sample_seconds: float = 3.0
var baseline_script: bool = false
var moving: bool = false
var reference_cameras: bool = false
var fixed_camera_pose: Dictionary = {}
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	optimize = args.has("--optimize")
	baseline_script = args.has("--baseline-script")
	moving = args.has("--movement")
	reference_cameras = args.has("--reference-cameras")
	for i: int in range(args.size()-1):
		if args[i] == "--report": output = args[i+1]
		if args[i] == "--seconds": sample_seconds = float(args[i+1])
	run.call_deferred()
func stats(values: Array[float], frame_units: bool = true) -> Dictionary:
	values.sort()
	var sum_value: float = 0.0
	var stalls: int = 0
	for v: float in values:
		sum_value += v
		if v > 50.0: stalls += 1
	var result: Dictionary = {"p50":values[values.size()/2],"p95":values[mini(values.size()-1,ceili(values.size()*.95)-1)],"p99":values[mini(values.size()-1,ceili(values.size()*.99)-1)],"max":values.back(),"mean":sum_value/values.size()}
	if frame_units: result["over_50_ms"] = stalls
	return result
func render_tick() -> void:
	await process_frame
	apply_fixed_camera()
	RenderingServer.force_draw(true)
func apply_fixed_camera() -> void:
	if fixed_camera_pose.is_empty() or camera == null: return
	camera.global_position = Garden.vector(fixed_camera_pose.camera_position)
	camera.global_rotation = Garden.vector(fixed_camera_pose.camera_rotation)
	camera.fov = 65
func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This benchmark requires an actual renderer")
		quit(1)
		return
	root.size = Vector2i(1280,800)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	root.scaling_3d_scale = .675 # Native mobile profile caps 3D at 960 x 540; 16:10 yields 864 x 540.
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	RenderingServer.set_render_loop_enabled(false)
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var quality := Quality.new()
	root.add_child(quality)
	var started: int = Time.get_ticks_usec()
	var script: Script = Garden
	if baseline_script:
		var frozen := GDScript.new()
		frozen.source_code = FileAccess.get_file_as_string("res://../deliverables/discussion-overhaul/performance/baseline-garden-source.gd")
		if frozen.reload() != OK:
			quit(1)
			return
		script = frozen
	room = script.new()
	room.set("graphics_settings",quality)
	root.add_child(room)
	current_scene = room
	var load_frames: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	var load_trace: Array[Dictionary] = []
	while not bool(room.get("ready_for_play")) and Time.get_ticks_usec()-started < 90000000:
		var before: Dictionary = {"state":room.get("detail_state"),"models":room.get("models").size(),"avatar":room.get("player").call("get_visual_preparation_state")}
		await render_tick()
		var now: int = Time.get_ticks_usec()
		var frame_ms: float = float(now-previous)/1000.0
		load_frames.append(frame_ms)
		if frame_ms > 8.0:
			load_trace.append({"frame_ms":frame_ms,"before":before,"after":{"state":room.get("detail_state"),"models":room.get("models").size(),"avatar":room.get("player").call("get_visual_preparation_state")}})
		previous = now
	if not bool(room.get("ready_for_play")):
		push_error("Garden never became ready")
		quit(1)
		return
	report["load_ready_ms"] = float(Time.get_ticks_usec()-started)/1000.0
	report["loading_frame_ms"] = stats(load_frames)
	report["loading_slow_frames"] = load_trace
	var prewarm: RefCounted = room.get("avatar_prewarm") as RefCounted
	if prewarm != null: report["avatar_prewarm"] = prewarm.call("metrics")
	if optimize:
		var optimizer: Node = load("res://scripts/discussion_render_optimizer.gd").new()
		room.add_child(optimizer)
		optimizer.call("configure",room)
		report["optimizer"] = optimizer.call("metrics")
	for child: Node in room.get_children():
		if child.get_script()!=null and child.get_script().resource_path == "res://scripts/discussion_render_optimizer.gd":
			report["optimizer"] = child.call("metrics")
	player = room.get("player")
	camera = room.get("camera")
	player.set("controls_enabled",false)
	var layout: Dictionary = room.get("layout")
	var points: Array[Dictionary] = [{"id":"hub","position":layout.spawn.position,"target":[0,1.5,0]}]
	for zone: Dictionary in layout.zones:
		points.append({"id":str(zone.id),"position":zone.controls.point,"target":zone.center})
	for point: Dictionary in points:
		await sample(point)
	report["moving"] = moving
	report["baseline_script"] = baseline_script
	report["reference_cameras"] = reference_cameras
	report["viewpoint_policy"] = "Original world-space camera poses" if reference_cameras else "Current layout logical arrival/control points at 65 degrees; layout changes alter framing"
	report["layout_sha256"] = FileAccess.get_sha256("res://assets/discussion_garden/layout.json")
	report["loaded_assets"] = room.get("model_paths")
	var asset_hashes: Dictionary = {}
	for path: String in room.get("model_paths"): asset_hashes[path] = FileAccess.get_sha256(path)
	report["asset_sha256"] = asset_hashes
	report["gpu_memory_bytes"] = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
	report.merge({"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"driver":RenderingServer.get_video_adapter_api_version(),"renderer":RenderingServer.get_current_rendering_method(),"headless":false,"frame_limit":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(),"window":[1280,800],"scaling_3d":root.scaling_3d_scale,"quality":"minimum native mobile equivalent; no shadows or AA; unchanged avatar and UI","mode":"One forced render with swap per process frame; automatic draw disabled, uncapped, VSync disabled. Native GPU under concurrent desktop workload; not minimum-spec hardware proof.","garden_sha256":FileAccess.get_sha256("res://assets/discussion_garden/garden.glb"),"garden_script_sha256":FileAccess.get_sha256("res://scripts/discussion_garden.gd"),"static_memory":Performance.get_monitor(Performance.MEMORY_STATIC),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT)})
	if baseline_script:
		report.garden_script_sha256 = FileAccess.get_sha256("res://../deliverables/discussion-overhaul/performance/baseline-garden-source.gd")
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("DISCUSSION_BENCHMARK ",output," ",JSON.stringify(report))
	RenderingServer.set_render_loop_enabled(true)
	quit()
func sample(point: Dictionary) -> void:
	fixed_camera_pose = {}
	if reference_cameras and not moving:
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../deliverables/discussion-overhaul/performance/baseline.json"))
		for row: Dictionary in baseline.samples:
			if row.point == point.id: fixed_camera_pose = row
	var at: Vector3 = Garden.vector(point.position)
	var target: Vector3 = Garden.vector(point.target)
	var facing: Vector3 = (target-at).normalized()
	player.call("place_at",at,facing)
	player.set("allow_test_input",false)
	room.set("camera_yaw",atan2(-facing.x,-facing.z))
	room.call("_update_zone_visibility",true)
	room.call("update_camera",0,true)
	camera.fov = 65
	for i: int in range(45): await render_tick()
	var frames: Array[float] = []
	var submits: Array[float] = []
	var calls: Array[float] = []
	var primitives: Array[float] = []
	var gpu: Array[float] = []
	var started: int = Time.get_ticks_usec()
	var previous: int = started
	var initial_position: Vector3 = player.global_position
	if moving:
		player.set("allow_test_input",true)
		player.set("test_direction",Vector2(0,-1))
	while Time.get_ticks_usec()-started < int(sample_seconds*1000000):
		if moving:
			room.set("camera_yaw",atan2(-facing.x,-facing.z)+sin(float(Time.get_ticks_usec()-started)/1000000.0)*.3)
		await process_frame
		var before_draw: int = Time.get_ticks_usec()
		apply_fixed_camera()
		RenderingServer.force_draw(true)
		var now: int = Time.get_ticks_usec()
		frames.append(float(now-previous)/1000.0)
		submits.append(float(now-before_draw)/1000.0)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		previous = now
	var row: Dictionary = {"point":point.id,"frames":frames.size(),"frame_ms":stats(frames),"draw_submit_ms":stats(submits),"gpu_ms":stats(gpu),"draw_calls":stats(calls,false),"primitives":stats(primitives,false),"camera_position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"camera_rotation":[camera.global_rotation.x,camera.global_rotation.y,camera.global_rotation.z]}
	row["travelled_distance"] = player.global_position.distance_to(initial_position)
	row["fov"] = camera.fov
	row["player_start"] = [initial_position.x,initial_position.y,initial_position.z]
	row["player_end"] = [player.global_position.x,player.global_position.y,player.global_position.z]
	player.set("allow_test_input",false)
	report.samples.append(row)
	var capture_path: String = output.get_basename()+"-"+str(point.id)+".png"
	root.get_texture().get_image().save_png(capture_path)
	print("DISCUSSION_SAMPLE ",JSON.stringify(row))
