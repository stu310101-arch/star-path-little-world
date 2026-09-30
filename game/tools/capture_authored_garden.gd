extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const OUTPUT: String = "res://../deliverables/authored-garden/"

var world: Node3D
var player: PlanetPlayer
var camera: Camera3D
var hud: CanvasLayer
var minimap: Control
var radius: float = 48.0
var records: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Garden visual review requires the native renderer; run without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	var grove: Node3D = world.get_node("Globe/SakuraGrove") as Node3D
	if int(grove.get_meta("layout_version",0)) != Plan.LAYOUT_VERSION:
		push_error("Sakura scene is stale: rebuild the authored garden before reviewing its images.")
		quit(1)
		return
	player = world.get("player") as PlanetPlayer
	camera = world.get("camera") as Camera3D
	hud = world.get("hud") as CanvasLayer
	minimap = hud.get("minimap") as Control
	radius = float((world.get("layout") as Dictionary).radius)
	hud.visible = true
	hud.call("close_panel")
	world.call("set_overview",false)
	world.set("near_distance",7.0)
	world.set("capture_focus",null)
	player.controls_enabled = false
	player.allow_test_input = false
	player.test_direction = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame
	await physics_frame
	var up: Vector3 = Plan.grove_up()
	var entry: Vector2 = Plan.entry_offset(radius)
	var views: Array[Dictionary] = [
		{"name":"01-bridge-enter","normal":Plan.bridge_start().slerp(Plan.bridge_finish(),.77),"target":Plan.garden_endpoint(),"pitch":.46,"purpose":"進橋口：確認到達花園的視線、入口淨空與路線延續"},
		{"name":"02-bridge-leave","normal":normal_at(entry*.35),"target":Plan.bridge_start(),"pitch":.43,"purpose":"出橋口：從園內看橋與城鎮，檢查座椅是否侵入通道"},
		{"name":"03-loop-east","normal":normal_at(Vector2(4.8,2.2)),"target":normal_at(Vector2(0,2.7)),"pitch":.48,"purpose":"東環：檢查中心主景、對岸樹群與東側觀景凹位的關係"},
		{"name":"04-loop-west","normal":normal_at(Vector2(-4.8,2.2)),"target":normal_at(Vector2(0,2.7)),"pitch":.48,"purpose":"西環：檢查主步道、座椅凹位與樹幹的層次及淨空"},
		{"name":"05-loop-north","normal":normal_at(Vector2(0,5.5)),"target":Plan.garden_endpoint(),"pitch":.52,"purpose":"北環：確認環線完整、入口可辨識且景觀有留白"},
		{"name":"06-east-overlook","normal":normal_at(Vector2(6.1,2.15)),"target":normal_at(Vector2(12,2.15)),"pitch":.42,"purpose":"東觀景凹位：站在可通行區檢查座椅朝向、海景與安全封邊"},
		{"name":"07-west-overlook","normal":normal_at(Vector2(-6.1,2.15)),"target":normal_at(Vector2(-12,2.15)),"pitch":.42,"purpose":"西觀景凹位：檢查入口寬度、座椅退讓與外緣欄杆"}
	]
	for view: Dictionary in views:
		await stage_player(view)
		await take(str(view.name),str(view.purpose),false,float(view.pitch))
		if str(view.name)=="04-loop-west" and OS.get_cmdline_user_args().has("--diagnose-multimesh"):
			for node: Node in world.find_children("*","MultiMeshInstance3D",true,false):
				if node.name=="FlowerBed" or node.name=="SettledBlossoms":
					(node as MultiMeshInstance3D).visible=false
			await take("debug-no-static-instances","diagnostic",false,float(view.pitch))
			quit()
			return
		if str(view.name)=="06-east-overlook" and OS.get_cmdline_user_args().has("--diagnose"):
			for path: String in ["Globe/OceanLife","Player","Stations"]:
				(world.get_node(path) as Node3D).visible=false
				await take("debug-no-"+path.get_file(),"diagnostic",false,float(view.pitch))
			(world.get("camera_obstruction") as RefCounted).call("reset")
			await take("debug-no-fade","diagnostic",false,float(view.pitch))
			quit()
			return
	# The eighth image is explicitly a plan review, not an alternative gameplay
	# camera. Keep the same HUD and a character on the real arrival path for scale.
	await stage_player({"normal":normal_at(entry*.7),"target":Plan.garden_endpoint(),"pitch":.5})
	(world.get("camera_obstruction") as RefCounted).call("reset")
	var axes: Basis = Geo.frame(up)
	var aim: Vector3 = Geo.surface(up,Vector2(0,1.1),radius).normalized()*(radius+.3)
	var eye: Vector3 = aim+up*28.0+axes.z*5.0
	camera.global_transform = Transform3D(Basis.IDENTITY,eye).looking_at(aim,-axes.z)
	world.set("camera_aim",aim)
	await take("08-layout-overhead","配置審核：入口、閉合環線、兩個景觀凹位與12株樹的整體秩序",true,.0)
	var output: Dictionary = {"passed":failures == 0,"layout_version":Plan.LAYOUT_VERSION,"images":records,"failures":failures,"gameplay_camera_distance":7.0,"notes":"Seven views use the actual fixed-distance roaming camera with HUD. The eighth is an explicit overhead layout review."}
	var file: FileAccess = FileAccess.open(OUTPUT+"capture-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	print("AUTHORED_GARDEN_CAPTURE "+JSON.stringify(output))
	quit(0 if failures == 0 else 1)

func normal_at(point: Vector2) -> Vector3:
	return Geo.surface(Plan.grove_up(),point,radius).normalized()

func stage_player(view: Dictionary) -> void:
	(world.get("camera_obstruction") as RefCounted).call("reset")
	var normal: Vector3 = view.normal
	var target: Vector3 = view.target
	player.set_physics_process(true)
	player.teleport(normal,radius+.7)
	player.heading = (target*radius-normal*radius).slide(normal).normalized()
	player.visual.rotation.y = PI
	world.set("near_pitch",float(view.pitch))
	world.set("near_distance",7.0)
	for i: int in range(36):
		await physics_frame
	player.set_physics_process(false)
	var settled_up: Vector3 = player.global_position.normalized()
	player.heading = (target*radius-player.global_position).slide(settled_up).normalized()
	player.previous_up = settled_up
	player.global_basis = Basis(player.heading.cross(settled_up).normalized(),settled_up,-player.heading)
	player.visual.rotation.y = PI
	player.set_clip(&"Idle")
	for i: int in range(12):
		world.call("update_camera",1.0/30.0)
		update_hud()
		await process_frame

func update_hud() -> void:
	world.call("update_nearest")
	hud.call("update_status",false,str(world.get("nearest_label")),player.global_position.length())
	minimap.call("refresh")

func take(name: String,purpose: String,overhead: bool,pitch: float) -> void:
	update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	var ground: Dictionary = player.ground_at(player.global_position.normalized())
	var grounded: bool = player.is_on_floor() and not ground.is_empty()
	var aim: Vector3 = world.get("camera_aim") as Vector3
	var distance: float = camera.global_position.distance_to(aim)
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))
	var valid: bool = error == OK and grounded and (overhead or absf(distance-7.0) < .01)
	if not valid:
		failures += 1
		push_error("Garden review frame failed validation: "+name)
	var ground_path: String = str((ground.collider as Node).get_path()) if not ground.is_empty() else "MISSING"
	var arrow: Vector2 = minimap.get("arrow_heading_2d") as Vector2
	records.append({"file":name+".png","purpose":purpose,"overhead":overhead,"grounded":grounded,"ground_collider":ground_path,"player_position":vector_array(player.global_position),"heading":vector_array(player.heading),"camera_position":vector_array(camera.global_position),"camera_aim":vector_array(aim),"camera_distance":distance,"pitch":pitch,"minimap_location":str(minimap.get("current_location")),"minimap_arrow":[arrow.x,arrow.y],"hud_visible":hud.visible,"size":[image.get_width(),image.get_height()],"passed":valid})
	print("GARDEN_FRAME "+name+" grounded="+str(grounded)+" distance="+str(distance))

func vector_array(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]
