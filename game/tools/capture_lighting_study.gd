extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
var world: Node3D
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func take(label: String) -> void:
	await create_timer(.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/lighting-"+label+".png"))
	print("LIGHT_STUDY ",label)

func run() -> void:
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible=false
	camera=world.get("camera") as Camera3D
	camera.fov=51
	camera.h_offset=0
	var env: Environment = (world.get_node("Environment") as WorldEnvironment).environment
	var sun: DirectionalLight3D=world.get_node("Sun") as DirectionalLight3D
	var fill: DirectionalLight3D=world.get_node("Fill") as DirectionalLight3D
	for variant: int in range(2):
		if variant==1:
			env.ambient_light_energy=.42
			env.ambient_light_color=Color(.86,.89,.93)
			sun.light_energy=.74
			fill.light_energy=.18
		var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
		for district_index: int in [0,5]:
			var up: Vector3 = Vector3.UP if district_index==0 else Vector3.DOWN
			var p: Array = data[district_index].civic if district_index==0 else data[district_index].visit
			var n: Vector3=Geo.surface(up,Vector2(p[0],p[1]),48).normalized()
			var axes: Basis=Basis(Quaternion(up,n))*Geo.frame(up)
			var at: Vector3=n*48.26
			camera.global_transform=Transform3D(Basis.IDENTITY,at+n*4.7+axes.x*5+axes.z*7).looking_at(at+n*.8,n)
			await take(str(variant)+"-"+str(district_index))
	quit()
