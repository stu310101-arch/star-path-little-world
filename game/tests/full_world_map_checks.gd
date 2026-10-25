extends SceneTree

const HudScript = preload("res://scripts/world_hud.gd")
const MinimapScript = preload("res://scripts/world_minimap.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const OUTPUT: String = "res://../deliverables/tiny-world/full-world-map-checks.json"
var checks: Array[Dictionary] = []
var failures: int = 0

class HudHarness:
	extends "res://scripts/world_hud.gd"
	func _ready() -> void:
		pass

class TestWorld:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer
	var overview: bool = false
	var paused: bool = false
	var entering: bool = false
	var preparing_roam: bool = false
	var preparing_room: bool = false
	var dragging_view: bool = true
	func finish_view_drag() -> void:
		dragging_view = false

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test": title, "passed": passed, "evidence": evidence})
	if not passed:
		failures += 1
		push_error(title + ": " + str(evidence))

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var world: TestWorld = TestWorld.new()
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	root.add_child(world)
	world.player = PlanetPlayer.new()
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.planet_radius = float(world.layout.radius)
	world.player._visual_stage = 6
	world.add_child(world.player)
	world.player.global_position = Vector3.UP * (world.player.planet_radius + 0.6)
	var stations: Node3D = Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station: Node3D = Node3D.new()
		station.name = str(row.id)
		stations.add_child(station)
		station.position = Vector3(row.normal[0], row.normal[1], row.normal[2]) * world.player.planet_radius
	var hud: HudHarness = HudHarness.new()
	hud.world = world
	world.add_child(hud)
	var screen: Control = Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.add_child(screen)
	hud.modal = CenterContainer.new()
	hud.modal.visible = false
	screen.add_child(hud.modal)
	hud.settings_overlay = Control.new()
	hud.settings_overlay.visible = false
	screen.add_child(hud.settings_overlay)
	hud.destination_card = PanelContainer.new()
	hud.destination_card.visible = false
	screen.add_child(hud.destination_card)
	hud.destination_toggle = Button.new()
	screen.add_child(hud.destination_toggle)
	hud.minimap = MinimapScript.new() as Control
	hud.minimap.set("world", world)
	hud.minimap.size = Vector2(224, 180)
	hud.minimap.connect("expand_requested", hud.open_full_map)
	screen.add_child(hud.minimap)
	hud._build_full_map(screen)
	var source_radius: float = float(world.layout.get("authoring_radius", world.layout.radius))
	var authored_point: Vector3 = Geo.surface(Vector3.UP, Vector2(10, 0), source_radius).normalized()
	check("Minimap converts authored coordinates using the authoring radius", (hud.minimap.call("lift", Vector3.UP, Vector2(10, 0)) as Vector3).is_equal_approx(authored_point))
	var projected: Vector2 = hud.minimap.call("project_point", authored_point)
	var expected_pixels: float = atan(10.0 / source_radius) * world.player.planet_radius * float(hud.minimap.call("map_scale"))
	check("Minimap distance scale uses the actual smaller world radius", is_equal_approx(projected.distance_to(hud.minimap.size * 0.5), expected_pixels), {"pixels": projected.distance_to(hud.minimap.size * 0.5), "expected": expected_pixels})
	check("Source road widths scale with the outdoor world", is_equal_approx(float(hud.minimap.call("source_scale")), world.player.planet_radius / source_radius))
	var map_click: InputEventMouseButton = InputEventMouseButton.new()
	map_click.button_index = MOUSE_BUTTON_LEFT
	map_click.pressed = true
	hud.minimap.call("_gui_input", map_click)
	check("Clicking the existing minimap opens the full map", hud.is_full_map_open())
	check("Opening stops movement and an existing camera drag", not world.player.controls_enabled and world.paused and not world.dragging_view)
	check("Overlay and map capture touch/mouse input", hud.full_map_overlay.mouse_filter == Control.MOUSE_FILTER_STOP and hud.full_map.mouse_filter == Control.MOUSE_FILTER_STOP)
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(844, 390), Vector2i(1024, 768), Vector2i(1280, 800)]:
		root.size = dimensions
		await process_frame
		await process_frame
		await process_frame
		hud.full_map.call("configure", hud.minimap)
		var viewport_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(dimensions))
		check("Close button stays visible and touch sized " + str(dimensions), viewport_rect.encloses(hud.full_map_close.get_global_rect()) and hud.full_map_close.size.x >= 48 and hud.full_map_close.size.y >= 48, hud.full_map_close.get_global_rect())
		check("Map remains inside the viewport " + str(dimensions), viewport_rect.encloses(hud.full_map.get_global_rect()) and hud.full_map.size.x > 150 and hud.full_map.size.y > 100, hud.full_map.get_global_rect())
		var hemispheres: Array = hud.full_map.get("hemispheres")
		var map_rect: Rect2 = Rect2(Vector2.ZERO, hud.full_map.size)
		var contained: bool = hemispheres.size() == 2
		for hemisphere: Dictionary in hemispheres:
			var radius: float = hemisphere.radius
			contained = contained and map_rect.encloses(Rect2((hemisphere.center as Vector2) - Vector2.ONE * radius, Vector2.ONE * radius * 2))
		check("Both complete hemispheres fit " + str(dimensions), contained)
		if OS.get_cmdline_user_args().has("--capture-full-map"):
			await RenderingServer.frame_post_draw
			var capture_path: String = ProjectSettings.globalize_path("res://../deliverables/tiny-world/full-map-%dx%d.png" % [dimensions.x, dimensions.y])
			root.get_texture().get_image().save_png(capture_path)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(960, 600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	for dimensions: Vector2i in [Vector2i(390, 844), Vector2i(844, 390)]:
		root.size = dimensions
		for frame: int in range(4):
			await process_frame
		hud._resize_full_map()
		await process_frame
		var logical_width: float = root.get_visible_rect().size.x
		var pixel_scale: float = float(dimensions.x) / logical_width
		var close_width: float = hud.full_map_close.size.x * hud.full_map_content.scale.x * pixel_scale
		check("Expanded mobile canvas keeps the close target at least 48 screen pixels " + str(dimensions), close_width >= 48.0, close_width)
		check("Expanded mobile canvas keeps map text at screen scale " + str(dimensions), is_equal_approx(hud.full_map_content.scale.x * pixel_scale, 1.0))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1280, 800)
	for frame: int in range(4):
		await process_frame
	check("All six districts and Sakura are labeled once", (hud.full_map.get("markers") as Array).size() == 7)
	check("The full map reuses every real connector", (hud.minimap.get("bridges") as Array).size() == 13 and (hud.full_map.get("lines") as Array).size() > 13)
	check("Land and water polygons are available on both hemispheres", (hud.full_map.get("surfaces") as Array).size() >= 7)
	var normal: Vector3 = world.player.global_position.normalized()
	var before_marker: Dictionary = hud.full_map.call("player_marker")
	world.player.global_position = -normal * world.player.planet_radius
	var after_marker: Dictionary = hud.full_map.call("player_marker")
	check("Player indicator changes hemispheres on the far side", before_marker.side != after_marker.side and (after_marker.point as Vector2).is_finite())
	hud.full_map_close.pressed.emit()
	check("Upper-right close restores the previous gameplay state", not hud.is_full_map_open() and world.player.controls_enabled and not world.paused)
	check("Hidden full map stops its player marker refresh", not hud.full_map.is_processing())
	var touch: InputEventScreenTouch = InputEventScreenTouch.new()
	touch.pressed = true
	hud.minimap.call("_gui_input", touch)
	check("Touching the minimap opens the same full map", hud.is_full_map_open())
	var escape: InputEventKey = InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	hud._input(escape)
	check("Escape closes the map and returns controls", not hud.is_full_map_open() and world.player.controls_enabled)
	hud.open_full_map()
	hud._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("Device Back closes the map", not hud.is_full_map_open())
	world.overview = true
	world.player.controls_enabled = false
	hud.open_full_map()
	hud.close_full_map()
	check("Closing from overview does not enable roaming controls", not world.player.controls_enabled)
	var result: Dictionary = {"passed": failures == 0, "failed": failures, "checks": checks, "scope": "Production HUD/map interaction and geometry in a native fixture; browser history and real device touch need browser verification."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	FileAccess.open(OUTPUT, FileAccess.WRITE).store_string(JSON.stringify(result, "\t"))
	print("FULL_WORLD_MAP_CHECKS ", checks.size(), " failures=", failures)
	world.free()
	quit(0 if failures == 0 else 1)
