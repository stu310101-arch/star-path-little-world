extends SceneTree

const Pose = preload("res://scripts/bench_pose.gd")
const Civic = preload("res://tools/refine_civic_plazas.gd")
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var visual := Node3D.new()
	stage.add_child(visual)
	var walking := Node3D.new()
	visual.add_child(walking)
	var pose = Pose.new()
	pose.configure(visual,walking,.4)
	check("Small seat chooses independent pose",str(pose.model.get_meta("seat_pose_asset")).ends_with("graduate_rest_small.glb"))
	check("Character retains original unit scale",pose.model.scale.is_equal_approx(Vector3.ONE))
	check("All 27 character parts are present",pose.meshes.size()==27)
	for amount: float in [0.0,.25,.5,.75,1.0]:
		pose.set_amount(amount)
		check("Pose %.2f is visible without locomotion overlap" % amount,pose.model.visible and not walking.visible)
		var total: float = 0.0
		for index: int in range(pose.meshes[0].get_blend_shape_count()):
			total += pose.meshes[0].get_blend_shape_value(index)
		check("Pose %.2f has normalized morph weights" % amount,is_equal_approx(total,0.0 if amount==0.0 else 1.0))
	if OS.get_cmdline_user_args().has("--capture"):
		root.size=Vector2i(1000,800)
		var ground := MeshInstance3D.new()
		var floor_mesh := BoxMesh.new()
		floor_mesh.size=Vector3(5,.05,5)
		ground.mesh=floor_mesh
		ground.position.y=-.03
		var floor_material := StandardMaterial3D.new()
		floor_material.albedo_color=Color("596961")
		ground.material_override=floor_material
		stage.add_child(ground)
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		Civic.bench(surface,Transform3D(Basis(Vector3.UP,PI).scaled(Vector3.ONE*.4),Vector3.ZERO),Color("668079"))
		var seat := MeshInstance3D.new()
		seat.mesh=surface.commit()
		var seat_material := StandardMaterial3D.new()
		seat_material.vertex_color_use_as_albedo=true
		seat.material_override=seat_material
		stage.add_child(seat)
		var environment := WorldEnvironment.new()
		environment.environment=Environment.new()
		environment.environment.background_mode=Environment.BG_COLOR
		environment.environment.background_color=Color("263535")
		environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
		environment.environment.ambient_light_color=Color.WHITE
		environment.environment.ambient_light_energy=.8
		stage.add_child(environment)
		var light := DirectionalLight3D.new()
		light.rotation_degrees=Vector3(-40,-25,0)
		light.light_energy=1.6
		stage.add_child(light)
		var camera := Camera3D.new()
		stage.add_child(camera)
		camera.current=true
		camera.position=Vector3(2.0,1.45,2.8)
		camera.look_at(Vector3(0,.7,.12))
		for amount: float in [0.0,.5,1.0]:
			pose.set_amount(amount)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/bench-rest-small/pose-%.1f.png" % amount))
		camera.position=Vector3(2.8,.85,.5)
		camera.look_at(Vector3(0,.6,.1))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/bench-rest-small/pose-side.png"))
	pose.finish()
	check("Finishing restores ordinary locomotion",walking.visible and not pose.model.visible)
	var indoor = Pose.new()
	indoor.configure(visual,walking)
	check("Default indoor pose remains original asset",str(indoor.model.get_meta("seat_pose_asset")).ends_with("graduate_rest.glb"))
	var scaled_visual := Node3D.new()
	scaled_visual.scale = Vector3.ONE*.4
	stage.add_child(scaled_visual)
	var scaled_walking := Node3D.new()
	scaled_visual.add_child(scaled_walking)
	var scaled_pose = Pose.new()
	scaled_pose.configure(scaled_visual,scaled_walking,.4,.4)
	check("Matching small avatar and seat use original authored pose",str(scaled_pose.model.get_meta("seat_pose_asset")).ends_with("graduate_rest.glb"))
	check("Scaled rest model inherits avatar scale exactly once",scaled_pose.model.scale.is_equal_approx(Vector3.ONE) and scaled_pose.model.global_basis.get_scale().is_equal_approx(Vector3.ONE*.4))
	scaled_pose.set_amount(1.0)
	check("Scaled seated pose replaces locomotion",scaled_pose.model.visible and not scaled_walking.visible)
	scaled_pose.finish()
	check("Scaled standing pose restores locomotion",not scaled_pose.model.visible and scaled_walking.visible)
	var output := FileAccess.open("res://../deliverables/bench-rest-small/runtime-checks.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks},"\t"))
	print("SMALL_BENCH_POSE_CHECKS ",checks.size()," failures=",failures)
	stage.queue_free()
	await process_frame
	quit(1 if failures else 0)
