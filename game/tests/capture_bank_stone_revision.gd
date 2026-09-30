extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
var world: Node3D
var out_dir: String = "res://../deliverables/lake-bank-revision/"

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.call("setup_water_review", 1, false)
	await create_timer(1.0).timeout
	var stage: String = "after" if OS.get_cmdline_user_args().has("--after") else "before"
	await take(stage + "-marina-review")
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible = false
	var camera: Camera3D = world.get("camera") as Camera3D
	var player: Node3D = world.get("player") as Node3D
	player.set_physics_process(false)
	var layout: Dictionary = world.get("layout")
	var n: Array = layout.stations[1].normal
	var up: Vector3 = Vector3(n[0], n[1], n[2])
	var radius: float = float(layout.radius)
	var at: Vector3 = Geo.surface(up, Vector2(24.2, 21.1), radius + .2)
	var eye: Vector3 = Geo.surface(up, Vector2(22.5, 14.5), radius + 2.6)
	player.call("teleport", Geo.surface(up, Vector2(22.884, 15.943), radius).normalized(), radius + .04)
	player.set("heading", (at-player.global_position).slide(player.global_position.normalized()).normalized())
	camera.h_offset = 0.0
	camera.fov = 49.0
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(at, at.normalized())
	await take(stage + "-north-bank")
	at = Geo.surface(up, Vector2(24.2, 21.1), radius + .20)
	eye = Geo.surface(up, Vector2(25.4, 17.7), radius + 1.7)
	camera.fov = 44.0
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(at, at.normalized())
	await take(stage + "-stone-detail")
	print("BANK_STONE_NATIVE_CAPTURE_OK ", stage)
	quit()

func take(label: String) -> void:
	await create_timer(.5).timeout
	await RenderingServer.frame_post_draw
	var result: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(out_dir + label + ".png"))
	assert(result == OK)
