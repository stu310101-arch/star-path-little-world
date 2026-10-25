extends SceneTree

# Imported mobile assets must retain the exact authored skeletal poses while
# omitting expensive secondary cloth morphs. With a real renderer this also
# saves paired pose images; headless verifies the same import/animation data.
const OUTPUT: String = "res://../deliverables/mobile-optimization/avatar/"
var failures: Array[String] = []
var samples: Array[Dictionary] = []
var stage: Node3D

func _initialize() -> void:
	call_deferred("run")

func verify(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960, 720)
	root.msaa_3d = Viewport.MSAA_DISABLED
	Engine.max_fps = 60
	stage = Node3D.new()
	root.add_child(stage)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(.17, .22, .25)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = .65
	environment_node.environment = environment
	stage.add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -25, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	stage.add_child(sun)
	var camera := Camera3D.new()
	camera.position = Vector3(2.4, 2.0, 6.3)
	stage.add_child(camera)
	camera.look_at(Vector3(0, .95, 0))
	camera.fov = 36
	camera.current = true
	await compare("graduate.glb", ["Idle", "Walk", "Run", "JumpDown"])
	await compare("graduate_jump.glb", ["JumpStart", "JumpAir", "JumpLand"])
	var report: Dictionary = {"failures": failures, "samples": samples, "display": DisplayServer.get_name(), "gpu": RenderingServer.get_video_adapter_name(), "renderer": RenderingServer.get_current_rendering_method(), "note": "Bone poses checked after real Godot glTF import. Headless results do not measure GPU or phone FPS."}
	var output := FileAccess.open(OUTPUT + ("headless.json" if DisplayServer.get_name() == "headless" else "render.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("MOBILE_AVATAR_CHECKS samples=", samples.size(), " failures=", failures)
	stage.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func resolve(player: AnimationPlayer, clip: String) -> StringName:
	for candidate: StringName in player.get_animation_list():
		if String(candidate).get_file().to_lower() == clip.to_lower():
			return candidate
	return &""

func compare(filename: String, clips: Array) -> void:
	var original := (load("res://assets/character/runtime_web/" + filename) as PackedScene).instantiate() as Node3D
	var mobile := (load("res://assets/character/runtime_mobile/" + filename) as PackedScene).instantiate() as Node3D
	stage.add_child(original)
	stage.add_child(mobile)
	var old_anim := original.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var new_anim := mobile.find_child("AnimationPlayer", true, false) as AnimationPlayer
	old_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	new_anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var old_skeleton := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var new_skeleton := mobile.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	verify(old_anim.get_animation_list() == new_anim.get_animation_list(), filename + " animation names")
	verify(old_skeleton.get_bone_count() == new_skeleton.get_bone_count(), filename + " bone count")
	var surfaces: int = 0
	for node: Node in mobile.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		surfaces += mesh_instance.mesh.get_surface_count()
		verify(mesh_instance.get_blend_shape_count() == 0, filename + " no blend shapes")
		verify(mesh_instance.skin != null and not mesh_instance.skeleton.is_empty(), filename + " mesh still skinned")
	verify(surfaces == 11, filename + " keeps eleven material surfaces")
	for clip: String in clips:
		var old_name: StringName = resolve(old_anim, clip)
		var new_name: StringName = resolve(new_anim, clip)
		verify(old_name != &"" and new_name != &"", clip + " present")
		old_anim.play(old_name)
		new_anim.play(new_name)
		var duration: float = old_anim.get_animation(old_name).length
		verify(is_equal_approx(duration, new_anim.get_animation(new_name).length), clip + " duration")
		var animation: Animation = new_anim.get_animation(new_name)
		for track: int in range(animation.get_track_count()):
			verify(animation.track_get_type(track) != Animation.TYPE_BLEND_SHAPE, clip + " no morph tracks")
		for fraction: float in [0.0, .17, .37, .63, .89, 1.0]:
			old_anim.seek(duration * fraction, true)
			new_anim.seek(duration * fraction, true)
			await process_frame
			for index: int in range(old_skeleton.get_bone_count()):
				verify(old_skeleton.get_bone_name(index) == new_skeleton.get_bone_name(index), clip + " bone name")
				verify(old_skeleton.get_bone_global_pose(index).is_equal_approx(new_skeleton.get_bone_global_pose(index)), clip + " bone pose " + str(index))
			var stem: String = clip + "-" + str(int(fraction * 100))
			if DisplayServer.get_name() != "headless":
				original.visible = true
				mobile.visible = false
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT + stem + "-desktop.png")
				original.visible = false
				mobile.visible = true
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT + stem + "-mobile.png")
			samples.append({"clip": clip, "time": duration * fraction, "bones": old_skeleton.get_bone_count(), "stem": stem})
	original.queue_free()
	mobile.queue_free()
	await process_frame
