extends SceneTree

# Same isolated avatar/camera/action route for each export variant. Uncapped
# rendering exposes avatar cost; this is not a whole-world 30 FPS claim.
var variant: String = "runtime"
var stage: Node3D
var walking: Node3D
var jumping: Node3D
var walk_animation: AnimationPlayer
var jump_animation: AnimationPlayer
var frame_times: Array[float] = []
var cpu_times: Array[float] = []
var draws: Array[int] = []
var collect: bool = false
var started_usec: int = 0
var last_usec: int = 0
var previous_clip: int = -1
var meshes: Array[Node] = []
var max_active_targets: int = 0
var total_targets: int = 0
var setup_ms: float = 0

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_DISABLED
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var begin: int = Time.get_ticks_usec()
	stage = Node3D.new()
	root.add_child(stage)
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.17, 0.22, 0.25)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	environment_node.environment = environment
	stage.add_child(environment_node)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -25, 0)
	sun.shadow_enabled = false
	stage.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(0.7, 1.6, 4.0)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.current = true
	var prefix: String = "res://assets/character/" + ("" if variant == "original" else variant + "/")
	walking = (load(prefix + "graduate.glb") as PackedScene).instantiate() as Node3D
	jumping = (load(prefix + "graduate_jump.glb") as PackedScene).instantiate() as Node3D
	stage.add_child(walking)
	stage.add_child(jumping)
	walk_animation = walking.find_child("AnimationPlayer", true, false) as AnimationPlayer
	jump_animation = jumping.find_child("AnimationPlayer", true, false) as AnimationPlayer
	walk_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	jump_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	meshes = walking.find_children("*", "MeshInstance3D", true, false) + jumping.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		total_targets += (node as MeshInstance3D).get_blend_shape_count()
	setup_ms = float(Time.get_ticks_usec() - begin) / 1000.0
	started_usec = Time.get_ticks_usec()
	last_usec = started_usec
	process_frame.connect(tick)

func tick() -> void:
	var now: int = Time.get_ticks_usec()
	var elapsed: float = float(now - started_usec) / 1000000.0
	if elapsed >= 35.0:
		finish()
		return
	if elapsed >= 5.0:
		frame_times.append(float(now - last_usec) / 1000.0)
		cpu_times.append(float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0)
		draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	last_usec = now
	var clip_names: Array[StringName] = [&"Walk", &"Run", &"Idle", &"JumpStart", &"JumpAir", &"JumpLand", &"JumpDown"]
	var route_time: float = maxf(0.0, elapsed - 5.0)
	var index: int = mini(6, int(route_time / (30.0 / 7.0)))
	var clip: StringName = clip_names[index]
	var jumping_now: bool = index in [3, 4, 5]
	var animation_player: AnimationPlayer = jump_animation if jumping_now else walk_animation
	if index != previous_clip:
		for node: Node in meshes:
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			for shape: int in range(mesh_instance.get_blend_shape_count()):
				mesh_instance.set_blend_shape_value(shape, 0.0)
		for candidate: StringName in animation_player.get_animation_list():
			if String(candidate).get_file().to_lower() == String(clip).to_lower():
				animation_player.play(candidate)
				break
		walking.visible = not jumping_now
		jumping.visible = jumping_now
		previous_clip = index
	var animation: Animation = animation_player.get_animation(animation_player.current_animation)
	animation_player.seek(fposmod(route_time, maxf(animation.length, 0.001)), true)
	if Engine.get_process_frames() % 30 == 0:
		var active: int = 0
		for node: Node in meshes:
			var mesh_instance: MeshInstance3D = node as MeshInstance3D
			if not mesh_instance.is_visible_in_tree():
				continue
			for shape: int in range(mesh_instance.get_blend_shape_count()):
				if absf(mesh_instance.get_blend_shape_value(shape)) > 0.00001:
					active += 1
		max_active_targets = maxi(max_active_targets, active)

func finish() -> void:
	process_frame.disconnect(tick)
	frame_times.sort()
	var total_ms: float = 0.0
	var stalls: int = 0
	for milliseconds: float in frame_times:
		total_ms += milliseconds
		if milliseconds > 100.0:
			stalls += 1
	var cpu_total: float = 0.0
	for milliseconds: float in cpu_times:
		cpu_total += milliseconds
	var draw_total: int = 0
	for count: int in draws:
		draw_total += count
	var output_path: String = "res://../deliverables/low-memory/avatar/benchmark-" + variant + ".json"
	var result: Dictionary = {"variant": variant, "viewport": [1280, 720], "msaa": "disabled", "fps_cap": 0,
		"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info(), "setup_ms": setup_ms,
		"frames": frame_times.size(), "duration_ms": total_ms, "average_fps": frame_times.size() * 1000.0 / total_ms,
		"p95_frame_ms": frame_times[int(floorf((frame_times.size() - 1) * 0.95))], "stalls_over_100ms": stalls,
		"maximum_frame_ms": frame_times.back(), "mean_process_ms": cpu_total / cpu_times.size(),
		"mean_draw_calls": float(draw_total) / draws.size(), "stored_targets": total_targets,
		"maximum_active_targets_on_visible_model": max_active_targets,
		"godot_static_memory_bytes": OS.get_static_memory_usage(), "godot_static_memory_peak_bytes": OS.get_static_memory_peak_usage(),
		"note": "One isolated native 30 s action route after 5 s warmup, both model variants resident. Uncapped vsync-off exposes avatar-only cost. Not whole-world FPS or 4 GB device qualification."}
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	print("AVATAR_BENCHMARK ", JSON.stringify(result))
	quit()
