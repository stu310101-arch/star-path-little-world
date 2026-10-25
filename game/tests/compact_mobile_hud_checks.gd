extends SceneTree

const HUD = preload("res://scripts/world_hud.gd")
const OUTPUT: String = "res://../deliverables/mobile-ui/"
var failures: int = 0
var checks: Array[Dictionary] = []

class MusicFixture:
	extends Node
	signal state_changed
	func get_state() -> Dictionary:
		return {"muted":false,"volume":.4,"unlocked":true,"title":"星球漫遊"}
	func set_music_volume(_value: float) -> void:
		pass

class WorldFixture:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer
	var music: Node
	var benches: Node
	var overview: bool = false
	var paused: bool = false
	var entering: bool = false
	var preparing_roam: bool = false
	var preparing_room: bool = false
	var dragging_view: bool = true
	var last_destination: String = ""
	func finish_view_drag() -> void:
		dragging_view = false
	func set_overview(value: bool) -> void:
		overview = value
	func teleport_to(destination: String) -> void:
		last_destination = destination
	func visit_sakura() -> void:
		last_destination = "sakura"
	func visit_ecology(index: int) -> void:
		last_destination = str(index)

class SafeHud:
	extends "res://scripts/world_hud.gd"
	var safe: Vector4 = Vector4.ZERO
	func _compact_safe_insets() -> Vector4:
		return safe

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":description,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(description + ": " + str(evidence))

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(960,600)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var world := WorldFixture.new()
	root.add_child(world)
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	world.player = PlanetPlayer.new()
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.planet_radius = float(world.layout.radius)
	world.player._visual_stage = 6
	world.add_child(world.player)
	world.player.global_position = Vector3.UP * 24.5
	world.music = MusicFixture.new()
	world.add_child(world.music)
	var stations := Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station := Node3D.new()
		station.name = str(row.id)
		stations.add_child(station)
		station.position = Vector3(row.normal[0],row.normal[1],row.normal[2]) * 24.0
	var hud := SafeHud.new()
	hud.world = world
	hud.set_meta("force_compact_hud",true)
	world.add_child(hud)
	var screen: Control = hud.get_node("Screen") as Control
	check("Phone HUD hides the desktop sidebar area",not hud.get_node("Screen/Margin").visible)
	check("Compact map remains live and detailed full-map data remains available",bool(hud.minimap.get("compact_preview")) and (hud.minimap.get("landmarks") as Array).size()==7)
	check("Mobile text uses a private scalable font",(hud.font as FontVariation).base_font is FontFile and ((hud.font as FontVariation).base_font as FontFile).multichannel_signed_distance_field)
	check("Shared source font remains untouched",not (load("res://assets/fonts/NotoSansTC.ttf") as FontFile).multichannel_signed_distance_field)
	for dimensions: Vector2i in [Vector2i(320,568),Vector2i(390,844),Vector2i(844,390),Vector2i(1024,768)]:
		root.size = dimensions
		for frame: int in range(5):
			await process_frame
		hud._resize_compact_hud()
		hud.update_status(false,"興趣輔導室",0.0)
		for frame: int in range(3):
			await process_frame
		var pixel_scale: float = float(dimensions.x) / root.get_visible_rect().size.x
		var actual_scale: float = screen.scale.x * pixel_scale
		check("Mobile UI text stays at physical CSS size " + str(dimensions),is_equal_approx(actual_scale,1.0),actual_scale)
		check("Menu target is at least 44 screen pixels " + str(dimensions),hud.compact_menu_button.size.y*actual_scale>=44.0)
		check("Small map fits its corner " + str(dimensions),Rect2(Vector2.ZERO,screen.size).encloses(Rect2(hud.compact_map_card.position,hud.compact_map_card.size)),hud.compact_map_card.get_rect())
		check("Center view has no desktop panels " + str(dimensions),not hud.is_compact_menu_open() and not hud.sidebar.is_visible_in_tree() and not hud.compact_start.visible)
		await capture("roaming-%dx%d" % [dimensions.x,dimensions.y])
		hud.open_compact_menu()
		check("Menu pauses and releases movement " + str(dimensions),world.paused and not world.player.controls_enabled and not world.dragging_view)
		await process_frame
		check("Menu close fits viewport " + str(dimensions),Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(hud.compact_menu_close.get_global_rect()),hud.compact_menu_close.get_global_rect())
		await capture("menu-%dx%d" % [dimensions.x,dimensions.y])
		hud.open_graphics_settings()
		for frame: int in range(3):
			await process_frame
		check("Opening settings closes drawer and retains movement lock " + str(dimensions),not hud.is_compact_menu_open() and hud.is_settings_open() and not world.player.controls_enabled)
		check("Settings fits small display " + str(dimensions),Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(hud.settings_panel.get_global_rect()),hud.settings_panel.get_global_rect())
		await capture("settings-%dx%d" % [dimensions.x,dimensions.y])
		hud.close_graphics_settings()
		check("Settings completion restores roaming " + str(dimensions),world.player.controls_enabled and not world.paused)
		hud.minimap.emit_signal("expand_requested")
		for frame: int in range(3):
			await process_frame
		check("Compact minimap opens readable full map " + str(dimensions),hud.is_full_map_open() and hud.full_map_close.size.y*actual_scale>=48.0)
		await capture("map-%dx%d" % [dimensions.x,dimensions.y])
		hud.full_map_close.pressed.emit()
		check("Full map X restores roaming " + str(dimensions),not hud.is_full_map_open() and world.player.controls_enabled)
		hud.set_preparation("正在準備角色與目的地，請稍候…",false)
		for frame: int in range(3):
			await process_frame
		check("Preparation card fits small display " + str(dimensions),Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses((hud.preparation_overlay.get_child(0) as Control).get_global_rect()))
		hud.set_preparation("",false)
	hud.open_compact_menu()
	hud.station_buttons[0].pressed.emit()
	check("Destination selection closes menu before travel",not hud.is_compact_menu_open() and not world.paused and world.last_destination==str(world.layout.stations[0].id))
	hud.open_compact_menu()
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	hud._input(escape)
	check("Escape closes compact menu",not hud.is_compact_menu_open())
	hud.open_compact_menu()
	hud._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("Device Back closes compact menu",not hud.is_compact_menu_open())
	root.size = Vector2i(844,390)
	hud.safe = Vector4(44,0,44,21)
	for frame: int in range(5):
		await process_frame
	hud._resize_compact_hud()
	check("Landscape notch and home indicator remain outside HUD",absf(screen.size.x-756)<1.5 and absf(screen.size.y-369)<1.5,{"css_size":screen.size,"logical_rect":screen.get_rect()})
	hud.update_status(true,"",0.0)
	check("Overview exposes a clear Start Roaming action",hud.compact_start.visible and hud.prompt_label.text.is_empty())
	hud.set_background_download("下載中斷",true)
	check("Background failure remains discoverable in collapsed menu",hud.compact_menu_button.text.contains("!") and hud.background_download_retry.visible)
	var desktop_hud: CanvasLayer = HUD.new() as CanvasLayer
	desktop_hud.set("world",world)
	world.add_child(desktop_hud)
	check("Desktop keeps its existing sidebar and bitmap font",not bool(desktop_hud.get("compact_hud")) and desktop_hud.get_node("Screen/Margin").visible and not (((desktop_hud.get("font") as FontVariation).base_font) as FontFile).multichannel_signed_distance_field)
	FileAccess.open(OUTPUT+"compact-hud-checks.json",FileAccess.WRITE).store_string(JSON.stringify({"checks":checks.size(),"failures":failures,"results":checks},"\t"))
	print("COMPACT_HUD_CHECKS ",checks.size()," failures=",failures)
	world.queue_free()
	await process_frame
	quit(1 if failures else 0)

func capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"):
		return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))
