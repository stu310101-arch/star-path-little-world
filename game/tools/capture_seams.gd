extends SceneTree
const Geo = preload("res://scripts/planet_geometry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible = false
	var camera: Camera3D = world.get("camera") as Camera3D
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	camera.fov = 48.0
	camera.h_offset = 0.0
	var layout: Dictionary = world.get("layout")
	var radius: float = float(layout.radius)
	var views: Array[Dictionary] = [
		{"district":4,"point":Vector2(-8,18),"name":"lake-road","height":4.5,"back":7.0},
		{"district":0,"point":Vector2(-21,19),"name":"lake-path","height":6.0,"back":8.0},
		{"district":5,"point":Vector2(25,20),"name":"boardwalk","height":6.0,"back":8.0}
	]
	for view: Dictionary in views:
		var n: Array = layout.stations[int(view.district)].normal
		var up: Vector3 = Vector3(n[0],n[1],n[2])
		var at: Vector3 = Geo.surface(up,view.point as Vector2,radius+.3)
		var radial: Vector3 = at.normalized()
		var axes: Basis = Geo.frame(radial)
		player.teleport(radial,radius+.65)
		for i: int in range(35):
			await physics_frame
		camera.global_transform = Transform3D(Basis.IDENTITY,at+radial*float(view.height)+axes.x*4.0+axes.z*float(view.back)).looking_at(at+radial*.7,radial)
		await create_timer(.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/seam-"+str(view.name)+"-after.png"))
		print("SEAM_CAPTURE ",view.name)
	quit()
