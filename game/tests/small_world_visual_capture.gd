extends SceneTree

const Startup = preload("res://tests/startup_fixture.gd")

func _initialize() -> void:
	call_deferred("run")

func save_view(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://../deliverables/world-correction/" + name + ".png"
	assert(root.get_texture().get_image().save_png(path) == OK)

func run() -> void:
	root.size = Vector2i(1280, 800)
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	await process_frame
	await save_view("small-world-overview")
	world.call("set_overview", false)
	assert(await Startup.wait_roaming(world, self))
	var player: PlanetPlayer = world.get("player")
	assert(is_equal_approx(player.planet_radius, 21.6))
	assert(is_equal_approx(player.walk_speed/player.avatar_scale, 3.8))
	for tick: int in range(20):
		await physics_frame
	await save_view("small-world-roaming")
	var hud: Node = world.get("hud")
	hud.call("open_full_map")
	assert(bool(hud.call("is_full_map_open")) and not player.controls_enabled)
	await save_view("small-world-full-map")
	hud.call("close_full_map")
	assert(not bool(hud.call("is_full_map_open")) and player.controls_enabled)
	print("SMALL_WORLD_VISUAL_CAPTURE_OK radius=21.6 authored_walk=3.8 map-open-close=passed")
	quit()
