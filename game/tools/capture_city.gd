extends SceneTree

func _initialize() -> void:
	call_deferred("capture_city")

func capture_city() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.set_process(false)
	var hud: CanvasLayer = world.get("hud") as CanvasLayer
	hud.visible = false
	var camera: Camera3D = world.get("camera") as Camera3D
	camera.h_offset = 0.0
	camera.fov = 48.0
	camera.global_transform = Transform3D(Basis.IDENTITY,Vector3(25,60,29)).looking_at(Vector3(0,37,0),Vector3.UP)
	await create_timer(2.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/city-layout.png"))
	print("CITY_LAYOUT_CAPTURE_OK")
	quit()
