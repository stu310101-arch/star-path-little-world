extends SceneTree

## Native Compatibility renderer review of the production GLB files. This is a
## neutral tree asset review, kept distinct from capture_world_redesign gameplay.
var output: String
var scene: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name()=="headless":
		push_error("Vegetation visual review requires the native renderer")
		quit(1)
		return
	output = ProjectSettings.globalize_path("res://../deliverables/vegetation/native")
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280,800)
	root.msaa_3d = Viewport.MSAA_4X
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment: WorldEnvironment = WorldEnvironment.new()
	environment.environment = Environment.new()
	var env: Environment = environment.environment
	env.background_mode = Environment.BG_SKY
	var sky: Sky = Sky.new()
	var atmosphere: ProceduralSkyMaterial = ProceduralSkyMaterial.new()
	atmosphere.sky_top_color = Color(.28,.36,.45)
	atmosphere.sky_horizon_color = Color(.72,.74,.76)
	atmosphere.ground_bottom_color = Color(.16,.18,.20)
	atmosphere.ground_horizon_color = Color(.62,.65,.68)
	sky.sky_material = atmosphere
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = .8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	scene.add_child(environment)
	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48,-35,0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	scene.add_child(sun)
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(200,200)
	floor_mesh.mesh = plane
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(.19,.21,.23)
	material.roughness = .85
	floor_mesh.material_override = material
	scene.add_child(floor_mesh)
	camera = Camera3D.new()
	camera.near = .1
	camera.far = 100
	camera.fov = 40
	scene.add_child(camera)
	camera.make_current()
	var models: Array[Node3D] = []
	for key: String in ["alder","birch","pine","willow"]:
		var model: Node3D = (load("res://assets/vegetation_rebuilt/"+key+".glb") as PackedScene).instantiate() as Node3D
		scene.add_child(model)
		model.visible = false
		models.append(model)
	for model: Node3D in models:
		model.visible = true
		camera.position = Vector3(9,5,12)
		camera.look_at(Vector3(0,3.5,0))
		await take(str(model.name)+"-front")
		camera.position = Vector3(-9,5,-12)
		camera.look_at(Vector3(0,3.5,0))
		await take(str(model.name)+"-rear")
		model.visible = false
	for index: int in range(models.size()):
		models[index].visible = true
		models[index].position.x = (index-1.5)*7.0
	camera.position = Vector3(18,10,30)
	camera.fov = 48
	camera.look_at(Vector3(0,3.5,0))
	await take("fleet")
	print("VEGETATION_NATIVE_CAPTURE_COMPLETE ",RenderingServer.get_video_adapter_name())
	scene.queue_free()
	await process_frame
	quit()

func take(label: String) -> void:
	for frame: int in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
	print("VEGETATION_CAPTURE ",label)
