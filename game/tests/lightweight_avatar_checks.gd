extends SceneTree

# Rendered export-copy validation only. This deliberately loads originals next
# to runtime copies; it is not a game performance benchmark or shipping scene.
const OUTPUT: String = "res://../deliverables/low-memory/avatar/"
var stage: Node3D
var label: Label
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"name": title, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(title + ": " + str(evidence))

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("This check needs the real Compatibility renderer for imported morph validation.")
		quit(1)
		return
	root.size = Vector2i(1200, 760)
	root.msaa_3d = Viewport.MSAA_DISABLED
	Engine.max_fps = 30
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
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
	var canvas: CanvasLayer = CanvasLayer.new()
	root.add_child(canvas)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 22)
	canvas.add_child(label)
	await compare_asset("graduate.glb", ["Walk", "Run", "Idle", "JumpDown"])
	await compare_asset("graduate_jump.glb", ["JumpStart", "JumpAir", "JumpLand"])
	await capture_rest()
	var report: Dictionary = {"passed": failures == 0, "failures": failures,
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu": RenderingServer.get_video_adapter_name(), "checks": checks, "samples": samples,
		"note": "Imported animation poses sampled in the real Compatibility renderer; left original, right runtime copy. Mesh readback comparison validates signed runtime morph weights; source derivation covers every original key. This is separate from live player controls/physics tests."}
	var output: FileAccess = FileAccess.open(OUTPUT + "engine-validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "\t"))
	output.close()
	print("LIGHTWEIGHT_AVATAR_CHECKS ", JSON.stringify({"checks": checks.size(), "failures": failures, "samples": samples.size()}))
	stage.queue_free()
	canvas.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func compare_asset(filename: String, clips: Array) -> void:
	var old_packed: PackedScene = load("res://assets/character/" + filename) as PackedScene
	var new_packed: PackedScene = load("res://assets/character/runtime/" + filename) as PackedScene
	check(filename + " exports load", old_packed != null and new_packed != null)
	if old_packed == null or new_packed == null:
		return
	var old_model: Node3D = old_packed.instantiate() as Node3D
	var new_model: Node3D = new_packed.instantiate() as Node3D
	var old_holder: Node3D = Node3D.new()
	var new_holder: Node3D = Node3D.new()
	old_holder.position.x = -0.8
	new_holder.position.x = 0.8
	stage.add_child(old_holder)
	stage.add_child(new_holder)
	old_holder.add_child(old_model)
	new_holder.add_child(new_model)
	var old_animation: AnimationPlayer = old_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var new_animation: AnimationPlayer = new_model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	old_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	new_animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	check(filename + " animation lists exact", old_animation.get_animation_list() == new_animation.get_animation_list())
	var old_meshes: Array[Node] = old_model.find_children("*", "MeshInstance3D", true, false)
	var new_meshes: Array[Node] = new_model.find_children("*", "MeshInstance3D", true, false)
	check(filename + " mesh parts retained", old_meshes.size() == new_meshes.size(), new_meshes.size())
	for clip: String in clips:
		var animation_name: StringName = resolve_clip(old_animation, clip)
		check(filename + " has " + clip, animation_name != &"")
		if animation_name == &"":
			continue
		for mesh_node: Node in old_meshes + new_meshes:
			var mesh_instance: MeshInstance3D = mesh_node as MeshInstance3D
			for index: int in range(mesh_instance.get_blend_shape_count()):
				mesh_instance.set_blend_shape_value(index, 0.0)
		old_animation.play(animation_name)
		new_animation.play(animation_name)
		var clip_length: float = old_animation.get_animation(animation_name).length
		for fraction: float in [0.0, 0.17, 0.37, 0.63, 0.89, 1.0]:
			var at: float = clip_length * fraction
			old_animation.seek(at, true)
			new_animation.seek(at, true)
			await process_frame
			await RenderingServer.frame_post_draw
			var differences: Dictionary = compare_morphs(old_meshes, new_meshes)
			check(clip + " imported morph error at " + str(fraction), float(differences.position) <= 0.0023 and float(differences.normal) <= 0.07, differences)
			samples.append({"asset": filename, "clip": clip, "time": at, "maximum_position_error_metres": differences.position, "maximum_normal_vector_error": differences.normal})
			if fraction in [0.37, 0.89]:
				label.text = "Original (left) / runtime copy (right)  |  " + clip + "  " + ("%.3f s" % at)
				await process_frame
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(OUTPUT + clip + "-" + str(int(fraction * 100)) + ".png")
	old_holder.queue_free()
	new_holder.queue_free()
	old_packed = null
	new_packed = null
	await process_frame
	await process_frame

func compare_morphs(old_meshes: Array[Node], new_meshes: Array[Node]) -> Dictionary:
	var maximum: float = 0.0
	var normal_maximum: float = 0.0
	for mesh_index: int in range(old_meshes.size()):
		var old_mesh: MeshInstance3D = old_meshes[mesh_index] as MeshInstance3D
		var new_mesh: MeshInstance3D = new_meshes[mesh_index] as MeshInstance3D
		var old_bake: ArrayMesh = old_mesh.bake_mesh_from_current_blend_shape_mix()
		var new_bake: ArrayMesh = new_mesh.bake_mesh_from_current_blend_shape_mix()
		if old_bake == null or new_bake == null or old_bake.get_surface_count() != new_bake.get_surface_count():
			return {"position": INF, "normal": INF}
		for surface: int in range(old_bake.get_surface_count()):
			var old_arrays: Array = old_bake.surface_get_arrays(surface)
			var new_arrays: Array = new_bake.surface_get_arrays(surface)
			var old_vertices: PackedVector3Array = old_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			var new_vertices: PackedVector3Array = new_arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			if old_vertices.size() != new_vertices.size():
				return {"position": INF, "normal": INF}
			for vertex: int in range(old_vertices.size()):
				maximum = maxf(maximum, (old_mesh.global_basis * (old_vertices[vertex] - new_vertices[vertex])).length())
			var old_normals: PackedVector3Array = old_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			var new_normals: PackedVector3Array = new_arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
			for vertex: int in range(old_normals.size()):
				normal_maximum = maxf(normal_maximum, old_normals[vertex].normalized().distance_to(new_normals[vertex].normalized()))
	return {"position": maximum, "normal": normal_maximum}

func resolve_clip(animation_player: AnimationPlayer, clip: String) -> StringName:
	for candidate: StringName in animation_player.get_animation_list():
		if String(candidate).get_file().to_lower() == clip.to_lower():
			return candidate
	return &""

func capture_rest() -> void:
	var holder: Node3D = Node3D.new()
	stage.add_child(holder)
	var walking: Node3D = (load("res://assets/character/runtime/graduate.glb") as PackedScene).instantiate() as Node3D
	holder.add_child(walking)
	var rest: RefCounted = (load("res://scripts/bench_pose.gd") as Script).new() as RefCounted
	rest.call("configure", holder, walking)
	for amount: float in [0.5, 1.0]:
		rest.call("set_amount", amount)
		label.text = "Preserved authored corrective sitting pose  |  " + str(amount)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OUTPUT + "Sit-" + str(int(amount * 100)) + ".png")
	check("Rest model and all 12 authored corrective poses are retained", (rest.get("meshes") as Array).size() == 27)
	rest.call("finish")
	holder.queue_free()
	rest = null
	await process_frame
