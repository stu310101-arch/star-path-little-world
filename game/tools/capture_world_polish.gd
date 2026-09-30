extends SceneTree
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
var camera: Camera3D
var world: Node3D
var radius: float
var folder: String = "res://../deliverables/world-polish"

func _initialize() -> void:
	call_deferred("run")

func take(label: String) -> void:
	await create_timer(.3).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(folder+"/"+label+".png"))
	print("POLISH_CAPTURE ",label)

func view(up: Vector3,p: Vector2,height: float,side: float,back: float,label: String) -> void:
	var radial: Vector3 = Geo.surface(up,p,radius).normalized()
	var axes: Basis = Basis(Quaternion(up,radial))*Geo.frame(up)
	var at: Vector3 = radial*(radius+.26)
	camera.global_transform = Transform3D(Basis.IDENTITY,at+radial*height+axes.x*side+axes.z*back).looking_at(at+radial*.8,radial)
	await take(label)

func run() -> void:
	if OS.get_cmdline_user_args().has("--authored"):
		folder="res://../deliverables/authored-world"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible = false
	camera = world.get("camera") as Camera3D
	camera.h_offset = 0.0
	camera.fov = 51.0
	radius = float(world.get("layout").radius)
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var directions: Array[Vector3] = Routes.directions()
	for i: int in range(6):
		await view(directions[i],Vector2.ZERO,30,19,27,"district-"+str(i))
		await view(directions[i],Vector2(data[i].civic[0],data[i].civic[1]),4.7,5,7,"civic-"+str(i))
		await view(directions[i],Vector2(data[i].visit[0],data[i].visit[1]),5,5,7,"reserve-"+str(i))
	await view(Vector3.RIGHT,Vector2(36,6),6.5,6,7.5,"marina")
	await view(Vector3.RIGHT,Vector2(35,6),3,-6,-5,"marina-entry")
	await view(Vector3.RIGHT,Vector2(25.5,0),3.3,-4.8,5.5,"river-crossing")
	await view(Vector3.DOWN,Vector2(23,21),4.4,5.5,7,"wetland-bend")
	await view(Vector3.LEFT,Vector2(0,23),3.6,5,6,"campus-river")
	var midpoint: Vector3 = Vector3.RIGHT.slerp(Vector3.FORWARD,.5)
	await view(midpoint,Vector2.ZERO,4.7,5,8,"interisland-bridge")
	var report: Dictionary = {"nodes":world.find_children("*","",true,false).size(),"meshes":world.find_children("*","MeshInstance3D",true,false).size(),"physics_bodies":world.find_children("*","StaticBody3D",true,false).size(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"fps":Engine.get_frames_per_second()}
	var output: FileAccess = FileAccess.open(folder+"/render-review.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("WORLD_POLISH_CAPTURE_OK")
	quit()
