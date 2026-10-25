extends SceneTree

# Small native image fixture: real map geometry, no imported 3D scene.
const Checks = preload("res://tests/minimap_cache_checks.gd")
const Map = preload("res://scripts/world_minimap.gd")
var output: String = "res://../deliverables/performance-20261020/minimap-pixels"
var minimap: Control

func _initialize() -> void:
	call_deferred("run")

func capture(label: String) -> void:
	await process_frame
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var pixels: Transform2D = root.get_final_transform() * minimap.get_global_transform_with_canvas()
	var rect: Rect2i = Rect2i(Vector2i(pixels.origin.floor()), Vector2i((pixels * minimap.size).ceil() - pixels.origin.floor()))
	image.get_region(rect).save_png(output.path_join(label + ".png"))
	print("PIXEL_CAPTURE ", label, " ", pixels, " oversampling ", root.get_oversampling(), " cache ", minimap._cache_viewport.get_oversampling())

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size = Vector2i(1920,1200)
	root.content_scale_size = Vector2i(1280,800)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.disable_3d = true
	Engine.max_fps = 60
	var world: Node3D = Checks.TestWorld.new()
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
	world.player = PlanetPlayer.new()
	world.player.planet_radius = float(world.layout.radius)
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(world.player)
	var stations: Node3D = Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station: Node3D = Node3D.new()
		station.name = str(row.id)
		station.position = Vector3(row.normal[0],row.normal[1],row.normal[2]) * float(world.layout.radius)
		stations.add_child(station)
	root.add_child(world)
	world.player.position = Vector3.UP * (float(world.layout.radius)+.6)
	minimap = Map.new()
	minimap.world = world
	minimap.position = Vector2(44,175)
	minimap.size = Vector2(246,180)
	root.add_child(minimap)
	minimap.set_process(false)
	await create_timer(.4).timeout
	minimap.set_texture_cache_enabled(false)
	await capture("direct")
	minimap.set_texture_cache_enabled(true)
	await capture("cached")
	minimap._cache_viewport.oversampling_override = root.get_oversampling()
	minimap._cache_layer.queue_redraw()
	await capture("oversampled")
	var pixels: Transform2D = root.get_final_transform() * minimap.get_global_transform_with_canvas()
	var root_canvas: Transform2D = root.get_final_transform()
	root_canvas.origin -= pixels.origin.floor()
	minimap._cache_viewport.global_canvas_transform = root_canvas
	minimap._cache_viewport.canvas_transform = Transform2D.IDENTITY
	minimap._cache_layer.position = minimap.position
	minimap._cache_layer.queue_redraw()
	await capture("factored")
	minimap.free()
	world.free()
	quit()
