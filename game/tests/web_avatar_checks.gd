extends SceneTree

# Real Compatibility renders of the native and Web export copies at identical
# authored times/camera. The Python derivation verifies every original key and
# exact material, topology, skin and bone data; this covers actual Godot import.
const OUTPUT: String = "res://../deliverables/web-optimization/avatar/"
var stage: Node3D
var failures: Array[String] = []
var samples: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("A real renderer is required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960, 720)
	root.msaa_3d = Viewport.MSAA_DISABLED
	Engine.max_fps = 60
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
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	stage.add_child(sun)
	var camera: Camera3D = Camera3D.new()
	camera.position = Vector3(2.4, 2.0, 6.3)
	stage.add_child(camera)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.fov = 36
	camera.current = true
	await compare("graduate.glb", ["Walk", "Run", "Idle", "JumpDown"])
	await compare("graduate_jump.glb", ["JumpStart", "JumpAir", "JumpLand"])
	var report: Dictionary = {"failures": failures, "samples": samples, "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method()}
	var file: FileAccess = FileAccess.open(OUTPUT + "engine.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("WEB_AVATAR_CHECKS samples=", samples.size(), " failures=", failures)
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func resolve(player: AnimationPlayer, clip: String) -> StringName:
	for candidate: StringName in player.get_animation_list():
		if String(candidate).get_file().to_lower() == clip.to_lower():
			return candidate
	return &""

func compare(filename: String, clips: Array) -> void:
	var old: Node3D = (load("res://assets/character/runtime/" + filename) as PackedScene).instantiate() as Node3D
	var optimized: Node3D = (load("res://assets/character/runtime_web/" + filename) as PackedScene).instantiate() as Node3D
	stage.add_child(old)
	stage.add_child(optimized)
	var old_anim: AnimationPlayer = old.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var new_anim: AnimationPlayer = optimized.find_child("AnimationPlayer", true, false) as AnimationPlayer
	old_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	new_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var old_skeleton: Skeleton3D = old.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var new_skeleton: Skeleton3D = optimized.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	verify(old_anim.get_animation_list() == new_anim.get_animation_list(), filename + " animation names")
	verify(old_skeleton.get_bone_count() == new_skeleton.get_bone_count(), filename + " bone count")
	var new_meshes: Array[Node] = optimized.find_children("*", "MeshInstance3D", true, false)
	var surfaces: int = 0
	for node: Node in new_meshes:
		surfaces += (node as MeshInstance3D).mesh.get_surface_count()
	verify(surfaces == 11, filename + " preserves eleven material surfaces")
	for clip: String in clips:
		for model: Node3D in [old, optimized]:
			for node: Node in model.find_children("*", "MeshInstance3D", true, false):
				var mesh: MeshInstance3D = node as MeshInstance3D
				for i: int in range(mesh.get_blend_shape_count()):
					mesh.set_blend_shape_value(i, 0.0)
		old_anim.play(resolve(old_anim, clip))
		new_anim.play(resolve(new_anim, clip))
		var duration: float = old_anim.get_animation(resolve(old_anim, clip)).length
		verify(is_equal_approx(duration, new_anim.get_animation(resolve(new_anim, clip)).length), clip + " duration")
		for fraction: float in [0.0, 0.17, 0.37, 0.63, 0.89, 1.0]:
			old_anim.seek(duration * fraction, true)
			new_anim.seek(duration * fraction, true)
			await process_frame
			for i: int in range(old_skeleton.get_bone_count()):
				verify(old_skeleton.get_bone_name(i) == new_skeleton.get_bone_name(i), clip + " bone names")
				verify(old_skeleton.get_bone_global_pose(i).is_equal_approx(new_skeleton.get_bone_global_pose(i)), clip + " bone pose " + str(i))
			var stem: String = clip + "-" + str(int(fraction * 100))
			old.visible = true
			optimized.visible = false
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + stem + "-before.png")
			old.visible = false
			optimized.visible = true
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT + stem + "-after.png")
			samples.append({"clip": clip, "time": duration * fraction, "before": stem + "-before.png", "after": stem + "-after.png"})
	old.queue_free()
	optimized.queue_free()
	await process_frame
