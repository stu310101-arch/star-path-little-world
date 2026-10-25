extends SceneTree

const HUD = preload("res://scripts/world_hud.gd")
const Fixtures = preload("res://tests/compact_mobile_hud_checks.gd")
var failures: int = 0
var checks: int = 0

func _initialize() -> void:
	run.call_deferred()

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks += 1
	print("DESTINATION_CHECK ", description, " passed=", passed, " evidence=", evidence)
	if not passed:
		failures += 1

func settle() -> void:
	for frame: int in range(5):
		await process_frame

func run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_size = Vector2i(1440, 900)
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	var world := Fixtures.WorldFixture.new()
	root.add_child(world)
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	world.player = PlanetPlayer.new()
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.player.planet_radius = float(world.layout.radius)
	world.player._visual_stage = 6
	world.add_child(world.player)
	world.player.position = Vector3.UP * 24.5
	world.music = Fixtures.MusicFixture.new()
	world.add_child(world.music)
	var stations := Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station := Node3D.new()
		station.name = str(row.id)
		stations.add_child(station)
		station.position = Vector3(row.normal[0], row.normal[1], row.normal[2]) * 24.0
	var hud := HUD.new()
	hud.world = world
	world.add_child(hud)
	for dimensions: Vector2i in [Vector2i(1920,855), Vector2i(1280,800), Vector2i(1024,768)]:
		root.size = dimensions
		for signed_in: bool in [false, true]:
			hud.refresh_account({"signedIn":true, "displayName":"星途測試"} if signed_in else {})
			await settle()
			check("Collapsed menu keeps account/settings " + str(dimensions), hud.account_controls.visible and hud.settings_button.visible)
			hud.destination_toggle.pressed.emit()
			await settle()
			var scroll: ScrollContainer = hud.destination_card.get_node("DestinationScroll") as ScrollContainer
			var visible_rows: int = 0
			for entry: Button in hud.station_buttons:
				if scroll.get_global_rect().encloses(entry.get_global_rect()):
					visible_rows += 1
			check("At least three destinations visible before scrolling " + str(dimensions) + " signed_in=" + str(signed_in), visible_rows >= 3 and scroll.scroll_vertical == 0, {"rows":visible_rows,"scroll_height":scroll.size.y})
			check("Expanded destinations remain inside viewport", root.get_visible_rect().encloses(hud.destination_card.get_global_rect()), hud.destination_card.get_global_rect())
			check("Expanded list frees secondary rows", not hud.account_controls.visible and not hud.settings_button.visible)
			hud.destination_toggle.pressed.emit()
			await settle()
			check("Collapse restores account including correct sign-out state", hud.account_controls.visible and hud.settings_button.visible and hud.sign_out_button.visible == signed_in)
	# Full-map/settings/roaming close the list via visibility too.
	hud.destination_toggle.pressed.emit()
	hud.update_status(false, "", 0)
	await settle()
	check("Changing world mode restores secondary controls", not hud.destination_card.visible and hud.account_controls.visible and hud.settings_button.visible)
	world.queue_free()
	await process_frame
	print("DESTINATION_NAVIGATION_CHECKS checks=", checks, " failures=", failures)
	quit(1 if failures else 0)
