extends SceneTree

# Same workspace assets, light, environment, camera and native renderer. The
# only difference between images is canonical full geometry versus overview.
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1200, 800)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	world.set_script(null)
	root.add_child(world)
	current_scene = world
	var camera: Camera3D = Camera3D.new()
	camera.fov = 42.0
	camera.far = 336.0
	var direction: Vector3 = Vector3(sin(.45) * cos(.63), sin(.63), cos(.45) * cos(.63))
	camera.transform = Transform3D(Basis.IDENTITY, direction * 177.6).looking_at(Vector3.ZERO, Vector3.UP)
	world.add_child(camera)
	camera.make_current()
	await capture("comparison-workspace-overview")
	for entry: Array in [["Globe", "res://generated/globe.tscn"], ["Neighborhood", "res://generated/neighborhood.tscn"]]:
		var previous: Node = world.get_node(str(entry[0]))
		world.remove_child(previous)
		previous.free()
		var full: Node3D = (load(str(entry[1])) as PackedScene).instantiate() as Node3D
		world.add_child(full)
		full.process_mode = Node.PROCESS_MODE_DISABLED
	await capture("comparison-workspace-full")
	(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = true
	await capture("comparison-workspace-full-shadows")
	world.queue_free()
	await process_frame
	quit()

func capture(label: String) -> void:
	for _frame: int in range(4):
		await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	assert(image.save_png("res://../deliverables/performance/" + label + ".png") == OK)
	print("STREAMING_COMPARISON_CAPTURE ", label)
