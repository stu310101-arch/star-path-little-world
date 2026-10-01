extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

const Geo = preload("res://scripts/planet_geometry.gd")
const Sakura = preload("res://scripts/sakura_routes.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var world: Node3D
var player: PlanetPlayer
var music: Node
var hud: CanvasLayer

func _initialize() -> void:
	call_deferred("run")

func check(title: String, passed: bool, detail: String = "") -> void:
	checks.append({"name": title, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		print("MUSIC_REGION_FAILURE ", title, " ", detail)

func place(normal: Vector3) -> void:
	player.global_position = normal.normalized() * (player.planet_radius + 0.65)

func state() -> Dictionary:
	return music.call("get_state") as Dictionary

func context_is(expected: String) -> bool:
	return str(world.call("desired_music_context")) == expected

func check_region_boundaries() -> void:
	var minimap: Control = hud.get("minimap") as Control
	var patches: Array = minimap.get("patches") as Array
	for index: int in range(6):
		var patch: Dictionary = patches[index] as Dictionary
		var region: String = str(patch.station_id)
		var up: Vector3 = patch.up as Vector3
		place(up)
		world.call("refresh_music_context", 0.0, true)
		check("District center requests " + region, context_is(region) and str(state().requested_context) == region)
		var coast: PackedVector2Array = patch.local_coast as PackedVector2Array
		var inside_matches: bool = true
		var outside_matches: bool = true
		var away_from_portals: bool = true
		# Sample all quadrants across the authored coast; nearby portal radius is
		# deliberately irrelevant to which island supplies background music.
		for point_index: int in [0, 32, 64, 96]:
			var point: Vector2 = coast[point_index]
			place(Geo.surface(up, point * 0.96, player.planet_radius))
			world.call("update_nearest")
			inside_matches = inside_matches and context_is(region)
			away_from_portals = away_from_portals and str(world.get("nearest_id")).is_empty()
			place(Geo.surface(up, point * 1.06, player.planet_radius))
			outside_matches = outside_matches and context_is("world")
		check("Music covers coast beyond portal range: " + region, inside_matches and away_from_portals)
		check("Crossing actual coast returns world music: " + region, outside_matches)

func check_debounce_and_entry() -> void:
	world.call("set_overview", true)
	place(Vector3.RIGHT)
	check("Overview overrides a district", context_is("world") and str(state().requested_context) == "world")
	world.set("overview", false)
	world.call("refresh_music_context", 0.0)
	world.call("refresh_music_context", 0.74)
	check("Walking boundary waits before 0.75 seconds", str(state().requested_context) == "world")
	world.call("refresh_music_context", 0.02)
	check("Stable district switches after 0.75 seconds", str(state().requested_context) == "admissions")
	place(Vector3.UP)
	world.call("refresh_music_context", 0.0)
	world.call("refresh_music_context", 0.4)
	place(Vector3.RIGHT)
	world.call("refresh_music_context", 0.0)
	place(Vector3.UP)
	world.call("refresh_music_context", 0.0)
	world.call("refresh_music_context", 0.5)
	check("Boundary jitter resets the dwell timer", str(state().requested_context) == "admissions")
	world.call("refresh_music_context", 0.26)
	check("Settled boundary eventually switches", str(state().requested_context) == "counseling")
	place(Vector3.RIGHT)
	world.call("refresh_music_context", 0.0, true)
	var return_position: Vector3 = player.global_position
	world.call("open_station", "counseling")
	check("Station entry immediately overrides region", bool(world.get("entering")) and bool(world.get("paused")) and context_is("counseling") and str(state().requested_context) == "counseling")
	world.call("_process", 1.5)
	place(Vector3.RIGHT)
	check("Open station keeps its theme while world is paused", not bool(world.get("entering")) and bool(world.get("paused")) and context_is("counseling"))
	world.call("resume_world", {})
	check("Resume restores actual region and return position", not bool(world.get("paused")) and str(world.get("entry_station")).is_empty() and context_is("admissions") and str(state().requested_context) == "admissions" and player.global_position.is_equal_approx(return_position))
	world.call("visit_sakura")
	place(Sakura.grove_up())
	world.call("refresh_music_context", 0.0, true)
	check("Sakura grove uses world theme", context_is("world") and str(state().requested_context) == "world")

func check_audio_controls() -> void:
	var button: Button = hud.get("music_button") as Button
	var slider: HSlider = hud.get("music_slider") as HSlider
	var percent: Label = hud.get("music_percent") as Label
	var title: Label = hud.get("music_title") as Label
	var original_path: String = str(music.get("settings_path"))
	var original_exists: bool = FileAccess.file_exists(original_path)
	var original_bytes: PackedByteArray = FileAccess.get_file_as_bytes(original_path) if original_exists else PackedByteArray()
	var original_volume: float = float(state().volume)
	var original_mute: bool = bool(state().muted)
	var temporary_path: String = "user://music_region_test_%d.cfg" % OS.get_process_id()
	music.set("settings_path", temporary_path)
	button.pressed.emit()
	check("Mute button updates bus and HUD", bool(state().muted) != original_mute and AudioServer.is_bus_mute(AudioServer.get_bus_index("Music")) == (bool(state().muted) or float(state().volume) <= 0.0) and button.text == ("音樂：靜音" if bool(state().muted) else "音樂：開"))
	var test_volume: float = 0.63 if not is_equal_approx(original_volume, 0.63) else 0.37
	slider.value = test_volume
	check("Volume slider updates bus and percent", is_equal_approx(float(state().volume), test_volume) and absf(db_to_linear(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))) - test_volume) < 0.0001 and percent.text == "%d%%" % roundi(test_volume * 100.0))
	var settings: ConfigFile = ConfigFile.new()
	var settings_loaded: bool = settings.load(temporary_path) == OK
	check("UI changes persist volume and mute", settings_loaded and is_equal_approx(float(settings.get_value("music", "volume", -1.0)), test_volume) and bool(settings.get_value("music", "muted", original_mute)) != original_mute and int(state().settings_error) == OK)
	check("HUD displays current track title", title.text == str(state().title))
	music.call("set_music_volume", original_volume)
	music.call("set_muted", original_mute)
	music.set("settings_path", original_path)
	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temporary_path))
	var original_unchanged: bool = FileAccess.file_exists(original_path) == original_exists
	if original_exists:
		original_unchanged = original_unchanged and FileAccess.get_file_as_bytes(original_path) == original_bytes
	check("Tests preserve the user's original settings", original_unchanged and not FileAccess.file_exists(temporary_path))

func check_layout(viewport_size: Vector2i) -> void:
	root.content_scale_size = viewport_size
	root.size = viewport_size
	for frame: int in range(5):
		await process_frame
	var screen: Control = hud.get_node("Screen") as Control
	var music_controls: Control = screen.find_child("MusicControls", true, false) as Control
	var top: Control = music_controls.get_parent() as Control
	var viewport_rect: Rect2 = Rect2(Vector2.ZERO, Vector2(viewport_size))
	var all_inside: bool = true
	var audio_nodes: Array[Control] = [music_controls, hud.get("music_button") as Control, hud.get("music_slider") as Control, hud.get("music_title") as Control, hud.get("music_percent") as Control]
	for control: Control in audio_nodes:
		var rect: Rect2 = control.get_global_rect()
		all_inside = all_inside and rect.size.x > 0.0 and rect.size.y > 0.0 and viewport_rect.encloses(rect)
	var no_overlap: bool = true
	for sibling: Node in top.get_children():
		var control: Control = sibling as Control
		if control != null and control != music_controls and control.visible:
			no_overlap = no_overlap and not music_controls.get_global_rect().intersects(control.get_global_rect())
	for index: int in range(1, audio_nodes.size()):
		for other: int in range(index + 1, audio_nodes.size()):
			no_overlap = no_overlap and not audio_nodes[index].get_global_rect().intersects(audio_nodes[other].get_global_rect())
	check("Audio controls fit viewport " + str(viewport_size), all_inside, str(music_controls.get_global_rect()))
	check("Audio controls do not overlap siblings " + str(viewport_size), no_overlap)

func run() -> void:
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	player = world.get("player") as PlanetPlayer
	check("Region fixture prepares station entry animations", await StartupFixture.prepare_player(player, self))
	player.set_physics_process(false)
	music = world.get("music") as Node
	music.set_process(false)
	music.call("begin_prepare_music")
	music.call("_process", 0.0)
	hud = world.get("hud") as CanvasLayer
	await process_frame
	world.set("overview", false)
	check_region_boundaries()
	check_debounce_and_entry()
	check_audio_controls()
	await check_layout(Vector2i(960, 640))
	await check_layout(Vector2i(1280, 800))
	var result: Dictionary = {"passed": failures == 0, "failures": failures, "checks": checks, "audio_available_ids": state().available_ids, "audio_missing_ids": state().missing_ids}
	var output_path: String = "res://../deliverables/music-integration/music-regions-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var report: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	report.store_string(JSON.stringify(result, "\t"))
	report.close()
	print("MUSIC_REGION_CHECKS ", checks.size(), " failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)
