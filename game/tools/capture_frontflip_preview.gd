extends SceneTree

const OUTPUT: String = "res://../deliverables/jump/studio/"
var player: PlanetPlayer
var camera: Camera3D
var caption: Label
var records: Array[Dictionary] = []

func jump_key(pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = pressed
	Input.parse_input_event(event)

func _initialize() -> void:
	call_deferred("run")

func material(color: String) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = Color(color)
	result.roughness = 0.8
	return result

func box(parent: Node3D, name_value: String, size: Vector3, point: Vector3, color: String, layer: int) -> void:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	mesh.name = name_value
	var shape: BoxMesh = BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material(color)
	mesh.position = point
	parent.add_child(mesh)
	if layer > 0:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = layer
		body.collision_mask = 0
		mesh.add_child(body)
		var collider: CollisionShape3D = CollisionShape3D.new()
		var box_shape: BoxShape3D = BoxShape3D.new()
		box_shape.size = size
		collider.shape = box_shape
		body.add_child(collider)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Frontflip preview requires native rendering")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(960,720)
	Engine.max_fps = 30
	Engine.physics_ticks_per_second = 60
	for action: String in ["move_left","move_right","move_forward","move_back","run","jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	var key: InputEventKey = InputEventKey.new()
	key.physical_keycode = KEY_SPACE
	InputMap.action_add_event("jump",key)
	var stage: Node3D = Node3D.new()
	root.add_child(stage)
	current_scene = stage
	var env: WorldEnvironment = WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color("26393e")
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color("d7e4ed")
	env.environment.ambient_light_energy = 0.55
	stage.add_child(env)
	var light: DirectionalLight3D = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-48,-35,0)
	light.light_color = Color("fff0db")
	light.light_energy = 1.05
	light.shadow_enabled = true
	stage.add_child(light)
	box(stage,"ReviewFloor",Vector3(11,0.24,12),Vector3(0,47.88,-1.5),"819087",1)
	# A visible 1.05 m physical railing; the actor must actually clear it.
	for rail_height: float in [0.45,1.0]:
		box(stage,"Rail",Vector3(2.6,0.1,0.1),Vector3(0,48+rail_height,-1.7),"c9aa75",8)
	for x: float in [-1.25,1.25]:
		box(stage,"RailPost",Vector3(0.12,1.05,0.12),Vector3(x,48.525,-1.7),"53696b",8)
	player = PlanetPlayer.new()
	player.planet_radius = 48.0
	stage.add_child(player)
	player.teleport(Vector3.UP,48.35)
	player.controls_enabled = true
	player.allow_test_input = true
	player.test_direction = Vector2.ZERO
	camera = Camera3D.new()
	camera.position = Vector3(5.8,51.5,6.3)
	camera.fov = 39.0
	stage.add_child(camera)
	camera.look_at(Vector3(0,49.3,-1.45),Vector3.UP)
	camera.make_current()
	var hud: CanvasLayer = CanvasLayer.new()
	stage.add_child(hud)
	caption = Label.new()
	caption.position = Vector2(28,22)
	caption.add_theme_font_override("font",load("res://assets/fonts/NotoSansTC.ttf") as Font)
	caption.add_theme_font_size_override("font_size",22)
	caption.add_theme_color_override("font_color",Color("f1e6c8"))
	hud.add_child(caption)
	for _index: int in range(45):
		await physics_frame
	var started: int = Time.get_ticks_msec()
	var pressed: bool = false
	var released: bool = false
	var stopped: bool = false
	var frame_index: int = 0
	while Time.get_ticks_msec()-started < 2800:
		var elapsed: float = float(Time.get_ticks_msec()-started)/1000.0
		if elapsed >= 0.45 and not pressed:
			player.test_direction = Vector2(0,-1)
			jump_key(true)
			pressed = true
		if elapsed >= 0.70 and not released:
			jump_key(false)
			released = true
		if elapsed >= 1.65 and not stopped:
			player.test_direction = Vector2.ZERO
			stopped = true
		caption.text = "前空翻越障  ·  1.05 m 欄杆\n"+str(player.active_clip)
		await process_frame
		await RenderingServer.frame_post_draw
		var filename: String = "frame_%04d.png" % frame_index
		root.get_texture().get_image().save_png(OUTPUT+filename)
		records.append({"frame":frame_index,"seconds":elapsed,"file":filename,"position":[player.position.x,player.position.y,player.position.z],"clip":str(player.active_clip),"grounded":player.is_on_floor()})
		frame_index += 1
	jump_key(false)
	var completed: bool = player.global_position.z < -2.1 and player.is_on_floor()
	var report: Dictionary = {"passed":completed,"frames":records,"final_position":[player.position.x,player.position.y,player.position.z],"note":"Real PlanetPlayer, Space action, real 1.05 m railing collision; source timing retained in frame manifest."}
	var file: FileAccess = FileAccess.open(OUTPUT+"capture.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("FRONTFLIP_STUDIO "+JSON.stringify({"passed":completed,"frames":records.size(),"final_position":report.final_position}))
	quit(0 if completed else 1)
