extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size=Vector2i(1280,800)
	var world: Node3D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene=world
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/water_ecology.json")) as Dictionary
	for index: int in range(6):
		world.call("setup_water_review",index,false)
		(world.get("player") as Node3D).set("controls_enabled",false)
		for frame: int in range(90):
			await physics_frame
		await RenderingServer.frame_post_draw
		var output: String="res://../deliverables/water-ecology/%02d-%s.jpg" % [index,str(plan.districts[index].station)]
		var result: int=root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path(output),.94)
		print("WATERFRONT_FRAME ",output," result=",result)
	world.call("setup_water_review",0,true)
	(world.get("player") as Node3D).set("controls_enabled",false)
	for frame: int in range(90):
		await physics_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_jpg(ProjectSettings.globalize_path("res://../deliverables/water-ecology/00-content-before.jpg"),.94)
	quit()
