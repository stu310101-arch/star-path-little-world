extends SceneTree
const Geo=preload("res://scripts/planet_geometry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene=world
	await physics_frame
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible=false
	var camera: Camera3D=world.get("camera") as Camera3D
	camera.h_offset=0.0
	camera.fov=48.0
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var layout: Dictionary=world.get("layout")
	var radius: float=float(layout.radius)
	for i: int in range(data.size()):
		var n: Array=layout.stations[i].normal
		var up: Vector3=Vector3(n[0],n[1],n[2])
		var basis: Basis=Geo.frame(up)
		camera.global_transform=Transform3D(Basis.IDENTITY,up*(radius+33)+basis.x*22+basis.z*31).looking_at(up*(radius+.7),up)
		await take("district-"+str(i))
	for i: int in [0,3,4,5]:
		var row: Dictionary=data[i]
		var n: Array=layout.stations[i].normal
		var up: Vector3=Vector3(n[0],n[1],n[2])
		var p: Vector2=Vector2(row.visit[0],row.visit[1])
		var at: Vector3=Geo.surface(up,p,radius+.3)
		var basis: Basis=Geo.frame(at.normalized())
		camera.global_transform=Transform3D(Basis.IDENTITY,at+at.normalized()*7.5+basis.x*6+basis.z*9).looking_at(at+at.normalized(),at.normalized())
		await take("ecology-"+str(i))
	print("ECOLOGY_CAPTURE_OK")
	quit()

func take(label: String) -> void:
	await create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/"+label+".png"))
