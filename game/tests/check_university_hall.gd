extends SceneTree

const Catalog = preload("res://scripts/university_catalog.gd")
const GraphicsSettings = preload("res://scripts/graphics_settings.gd")
const OUTPUT: String = "res://../deliverables/university-hall/"
var hall: Node3D
var checks: Array[Dictionary] = []
var failures: int = 0
var capture: bool = false
var floor_motion: bool = false
var samples: Array[Dictionary] = []
var output_dir: String = OUTPUT

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	floor_motion = capture and "--floor-motion" in OS.get_cmdline_user_args()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			output_dir = argument.trim_prefix("--output-dir=").trim_suffix("/") + "/"
	call_deferred("run")

func check(label: String, success: bool, evidence: Variant = null) -> void:
	checks.append({"name":label, "passed":success, "evidence":evidence})
	if not success:
		failures += 1
		push_error(label + ": " + str(evidence))

func tick(count: int = 2) -> void:
	for index: int in range(count):
		await process_frame

func press(key: Key) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await tick(2)
	event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	Input.parse_input_event(event)
	await tick(2)

func blocked_interaction_positions(space: Node3D, player: CharacterBody3D) -> Array[String]:
	var blocked: Array[String] = []
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .28
	capsule.height = 1.7
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	for target: Dictionary in space.get("targets"):
		query.transform = Transform3D(Basis.IDENTITY, (target.position as Vector3) + Vector3.UP * .92)
		if not space.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
			blocked.append(str(target.id))
	return blocked

func check_single_floor(space: Node3D, area: String) -> void:
	var surfaces: int = 0
	var triangles: int = 0
	for node: Node in space.find_children("*", "MeshInstance3D", true, false):
		if not str(node.name).ends_with("_Floor"):
			continue
		var mesh: Mesh = (node as MeshInstance3D).mesh
		for index: int in range(mesh.get_surface_count()):
			surfaces += 1
			var arrays: Array = mesh.surface_get_arrays(index)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += indices.size() / 3
	check(area + " has one two-triangle floor without layered inlay geometry", surfaces == 1 and triangles == 2, {"surfaces":surfaces, "triangles":triangles})

func take(name_value: String) -> void:
	if not capture:
		return
	await tick(8)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_dir + name_value + ".png"))

func sample(name_value: String) -> void:
	if not capture:
		return
	var frame_times: Array[float] = []
	var last: int = Time.get_ticks_usec()
	var deadline: int = Time.get_ticks_msec() + 3000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		frame_times.append(float(now - last) / 1000.0)
		last = now
	frame_times.sort()
	var sum: float = 0
	for frame: float in frame_times:
		sum += frame
	samples.append({"name":name_value, "frames":frame_times.size(), "mean_fps":1000 * frame_times.size() / maxf(sum, 1), "p95_ms":frame_times[mini(frame_times.size() - 1, ceili(frame_times.size() * .95))], "state":hall.call("debug_state")})

func take_floor_motion(name_value: String) -> void:
	if not floor_motion:
		return
	var yaw: float = float(hall.get("camera_yaw"))
	var pitch: float = float(hall.get("camera_pitch"))
	for frame: int in range(12):
		hall.set("camera_yaw", yaw + (float(frame) - 5.5) * .008)
		hall.set("camera_pitch", pitch + .1)
		hall.call("update_camera", 0, true)
		await take("floor-" + name_value + "-%02d" % frame)
	hall.set("camera_yaw", yaw)
	hall.set("camera_pitch", pitch)
	hall.call("update_camera", 0, true)

func run() -> void:
	root.size = Vector2i(1280, 800)
	Engine.max_fps = 30 if capture else 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
	var catalog: RefCounted = Catalog.new()
	check("All university content loads", catalog.load_content(), catalog.error)
	check("138 permanent IDs are indexed", catalog.by_id.size() == 138)
	var entities: Dictionary = {}
	for entry: Dictionary in catalog.entries:
		entities[str(entry.entity_id)] = true
	check("136 school entities preserve NDU academy grouping", entities.size() == 136, entities.size())
	var covered: Dictionary = {}
	for region: String in Catalog.REGION_IDS:
		for page: int in range(catalog.page_count(region)):
			var records: Array[Dictionary] = catalog.page_entries(region, page)
			check("%s page %d has 1–8 exhibits" % [region, page + 1], records.size() > 0 and records.size() <= 8)
			for entry: Dictionary in records:
				check("%s resolves to its correct region/page" % entry.id, catalog.locate(str(entry.id)).region == region and int(catalog.locate(str(entry.id)).page) == page)
				covered[str(entry.id)] = true
	check("Every entry has a reachable unique gallery address", covered.size() == 138)
	check("Taiwan character variants and aliases are searchable", catalog.search("台大").size() > 0 and catalog.search("NTU").size() > 0)
	check("Unknown search gives an empty result", catalog.search("zz-no-such-school-zz").is_empty())
	catalog.save_path = "user://university_exploration_test.json"
	catalog.visited.clear()
	catalog.favorites.clear()
	catalog.visit("001")
	catalog.toggle_favorite("003")
	var restored: RefCounted = Catalog.new()
	restored.load_content()
	restored.save_path = catalog.save_path
	restored.load_progress()
	check("Exploration and manual favorite survive reload", restored.visited.has("001") and restored.favorites.has("003") and not restored.visited.has("003"))
	restored.toggle_favorite("003")
	check("Favorite is reversible without removing exploration", not restored.favorites.has("003") and restored.visited.has("001"))
	hall = (load("res://scenes/university_hall.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hall)
	current_scene = hall
	var data: RefCounted = hall.get("catalog") as RefCounted
	data.save_path = "user://university_exploration_test.json"
	data.visited.clear()
	data.favorites.clear()
	var deadline: int = Time.get_ticks_msec() + 60000
	while not bool(hall.get("ready_for_play")) and Time.get_ticks_msec() < deadline:
		await tick()
	check("Hall finishes model and avatar loading", bool(hall.get("ready_for_play")), hall.get("detail_error"))
	if not bool(hall.get("ready_for_play")):
		finish()
		return
	await tick(20)
	var player: CharacterBody3D = hall.get("player") as CharacterBody3D
	var ui: CanvasLayer = hall.get("ui") as CanvasLayer
	var space: Node3D = hall.get("space") as Node3D
	var settings_probe: Node = GraphicsSettings.new()
	check("Free exploration counts as active gameplay", bool(settings_probe.call("_gameplay_is_active", hall)))
	ui.call("open_directory", "all")
	check("Reading is excluded from adaptive render headroom", not bool(settings_probe.call("_gameplay_is_active", hall)))
	ui.call("close_panel")
	settings_probe.free()
	check("Player starts supported on the atrium floor", player.is_on_floor(), player.position)
	check("All five region portals and map/handbook/exit exist", (space.get("targets") as Array).size() == 8)
	check_single_floor(space, "Atrium")
	var blocked_atrium: Array[String] = blocked_interaction_positions(space, player)
	check("Atrium interaction positions allow full-size player clearance", blocked_atrium.is_empty(), blocked_atrium)
	await take("01-atrium")
	await sample("atrium-low")
	await take_floor_motion("atrium")
	var old_position: Vector3 = player.position
	Input.action_press("move_forward")
	for i: int in range(25):
		await physics_frame
	Input.action_release("move_forward")
	check("WASD actions move the existing graduate player", player.position.distance_to(old_position) > .7)
	hall.call("travel_to_school", "001")
	await tick(12)
	check("Direct navigation opens the school gallery", str(hall.get("region")) == "north" and (space.get("booth_positions") as Dictionary).has("001"))
	check("A gallery instantiates at most eight real booths", space.find_children("School_*", "Node3D", false, false).size() <= 8)
	check_single_floor(space, "Gallery")
	await take("02-ntu-exhibit")
	await sample("gallery-low")
	await take_floor_motion("gallery")
	for section: int in range(5):
		var targets: Array = space.get("targets") as Array
		var selected: Dictionary = {}
		for target: Dictionary in targets:
			if str(target.get("school_id", "")) == "001" and int(target.get("section", -1)) == section:
				selected = target
		player.call("place_at", (selected.position as Vector3) + Vector3.UP * .08, Vector3.LEFT)
		await tick(3)
		await press(KEY_E)
		check("Physical object opens section %s" % Catalog.SECTION_IDS[section], str(ui.get("current_panel")) == "school" and int(ui.get("selected_section")) == section + 1)
		check("Reading stops movement", not bool(player.get("controls_enabled")))
		if section == 2:
			await take("03-reading-food")
		elif section == 1:
			await take("08-nearby-life")
		elif section == 3:
			await take("09-student-reviews")
		await press(KEY_ESCAPE)
		check("Esc closes section and resumes movement", not bool(ui.call("is_open")) and bool(player.get("controls_enabled")))
	check("Reading a school records exploration exactly once", data.visited.size() == 1 and data.visited.has("001"))
	ui.call("open_school", data.by_id["001"], -1)
	await tick()
	var favorite: Button = ui.get("favorite_button") as Button
	favorite.pressed.emit()
	check("Reader collection button saves the school", data.favorites.has("001"))
	await take("04-school-impression")
	ui.call("open_directory", "favorites")
	await tick(5)
	check("Handbook shows the collected school", (ui.get("results") as VBoxContainer).get_child_count() == 1)
	await take("05-collection")
	ui.call("open_directory", "all")
	await tick(5)
	var search: LineEdit = ui.get("search_box") as LineEdit
	search.text = "中興"
	search.text_changed.emit(search.text)
	await tick()
	check("Search UI finds NCHU", (ui.get("results") as VBoxContainer).get_child_count() == 1)
	var go: Button = ui.root.find_child("Travel_003", true, false) as Button
	check("Search results expose direct travel", go != null)
	if go != null:
		go.pressed.emit()
	await tick(5)
	check("Travel button closes UI and reaches selected school", not bool(ui.call("is_open")) and str(hall.get("region")) == "central")
	await take("06-nchu-exhibit")
	var reachable: int = 0
	for region: String in Catalog.REGION_IDS:
		for page: int in range(data.page_count(region)):
			hall.call("show_region", region, page)
			await tick(2)
			await physics_frame
			var blocked: Array[String] = blocked_interaction_positions(space, player)
			check("%s/%d interaction positions have player clearance" % [region, page], blocked.is_empty(), blocked)
			var targets: Array = space.get("targets") as Array
			var school_targets: int = 0
			for target: Dictionary in targets:
				if str(target.kind) == "school":
					school_targets += 1
			var count: int = data.page_entries(region, page).size()
			check("%s/%d supplies five objects per exhibit" % [region, page], school_targets == count * 5)
			reachable += count
	check("Every school is physically instantiated across galleries", reachable == 138)
	hall.call("show_region", "north", 0)
	await tick(3)
	player.call("place_at", Vector3(7, .08, -14.8), Vector3.FORWARD)
	await tick(3)
	await press(KEY_E)
	check("Next-gallery portal is interactive", int(hall.get("page")) == 1)
	player.call("place_at", Vector3(-7, .08, -14.8), Vector3.FORWARD)
	await tick(3)
	await press(KEY_E)
	check("Previous-gallery portal is interactive", int(hall.get("page")) == 0)
	player.call("place_at", Vector3(0, .08, 16.6), Vector3.BACK)
	await tick(3)
	await press(KEY_E)
	check("Gallery return portal restores the atrium", str(hall.get("region")).is_empty())
	if capture:
		root.size = Vector2i(900, 600)
		ui.call("open_school", data.by_id["138"], 3)
		await tick(10)
		await take("07-compact-reading")
		var close: Button = ui.root.find_child("ClosePanel", true, false) as Button
		check("Compact reader close control remains inside viewport", Rect2(Vector2.ZERO, root.get_visible_rect().size).encloses(close.get_global_rect()))
		root.size = Vector2i(1280, 800)
	finish()

func finish() -> void:
	var result: Dictionary = {"passed":failures == 0, "failures":failures, "checks":checks, "samples":samples, "renderer":DisplayServer.get_name(), "method":"Godot native scene/physics/input with test starting positions; captures use actual renderer. Desktop compact window is not physical-phone performance."}
	var file: FileAccess = FileAccess.open(output_dir + ("native-capture-report.json" if capture else "runtime-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	file.close()
	if is_instance_valid(hall):
		for voice: Node in hall.find_children("*", "AudioStreamPlayer", true, false):
			(voice as AudioStreamPlayer).stop()
		# Let the audio mixer release Ogg playback references before CLI exit.
		await create_timer(.15).timeout
		hall.queue_free()
	await tick(6)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://university_exploration_test.json"))
	print("UNIVERSITY_CHECKS total=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
