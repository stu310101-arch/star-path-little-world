extends SceneTree
## Focused university-hall failure/input regressions, independent of art export.
## Run: Godot --headless --path game --script res://tests/university_edge_checks.gd
## Only unique user:// fixtures are written. The real player's save is read-only.
## Expected loader parse errors come from deliberately broken fixture scenes.

const Catalog = preload("res://scripts/university_catalog.gd")
const Hall = preload("res://scripts/university_hall.gd")
const Reaper = preload("res://scripts/university_load_reaper.gd")
const BROKEN_SCENE: String = "[gd_scene format=3]\n[node name=\"BrokenFixture\" type=\"Node3D\"]\nbroken = unknown_identifier\n"
const FIXED_SCENE: String = "[gd_scene format=3]\n[node name=\"RepairedFixture\" type=\"Node3D\"]\n"

var checks: Array[Dictionary] = []
var failures: int = 0
var fixture_prefix: String = ""
var fixtures: Array[String] = []
var actual_save_existed: bool = false
var actual_save_before: PackedByteArray = PackedByteArray()
var hall: Node3D

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"name":label, "passed":passed, "evidence":evidence})
	if not passed:
		failures += 1
		print("EDGE_FAILURE ", label, " evidence=", evidence)

func tick(count: int = 2) -> void:
	for index: int in range(count):
		await process_frame

func fixture(suffix: String) -> String:
	var path: String = fixture_prefix + suffix
	assert(not FileAccess.file_exists(path), "Fixture paths must be unique and cannot replace existing files")
	fixtures.append(path)
	return path

func write_fixture(path: String, text_value: String) -> void:
	assert(path.begins_with(fixture_prefix) and path in fixtures)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "Cannot write isolated test fixture")
	file.store_string(text_value)
	file.close()

func isolated_catalog(path: String) -> RefCounted:
	assert(path.begins_with(fixture_prefix))
	var catalog: RefCounted = Catalog.new()
	catalog.save_path = path
	check("Fixture catalogue loads", catalog.load_content(), catalog.error)
	return catalog

func press_escape() -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	Input.parse_input_event(event)
	await tick()
	event = InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	Input.parse_input_event(event)
	await tick()

func wait_for_thread(path: String) -> int:
	var deadline: int = Time.get_ticks_msec() + 5000
	while ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS and Time.get_ticks_msec() < deadline:
		await tick()
	return ResourceLoader.load_threaded_get_status(path)

func check_progress() -> void:
	var path: String = fixture("progress.json")
	var catalog: RefCounted = isolated_catalog(path)
	catalog.load_progress()
	check("Absent progress starts empty without warning", catalog.visited.is_empty() and catalog.favorites.is_empty() and catalog.save_error.is_empty())
	catalog.visit("001")
	catalog.toggle_favorite("003")
	var restored: RefCounted = isolated_catalog(path)
	restored.load_progress()
	check("Isolated progress round-trip preserves explored and favorite IDs", restored.visited.keys() == ["001"] and restored.favorites.keys() == ["003"])
	var before_unknown: String = FileAccess.get_file_as_string(path)
	restored.visit("not-a-school")
	restored.toggle_favorite("999")
	check("Unknown IDs never modify existing progress", FileAccess.get_file_as_string(path) == before_unknown)
	write_fixture(path, JSON.stringify({"schema_version":1, "visited_ids":["001", "001", "999", 72, null, {"id":"003"}], "favorite_ids":["003", "003", "not-a-school"]}))
	restored.load_progress()
	check("Duplicate and unknown saved IDs are filtered", restored.visited.keys() == ["001"] and restored.favorites.keys() == ["003"])
	write_fixture(path, JSON.stringify({"schema_version":1, "visited_ids":{"invalid":"001"}, "favorite_ids":["003"]}))
	restored.load_progress()
	check("Malformed progress arrays do not discard the other valid field", restored.visited.is_empty() and restored.favorites.keys() == ["003"])
	for payload: String in ["{truncated", "[]", JSON.stringify({"schema_version":99,"visited_ids":["001"]}), JSON.stringify({"schema_version":"unknown"}), JSON.stringify({"schema_version":[]}), JSON.stringify({"schema_version":{}})]:
		write_fixture(path, payload)
		restored.load_progress()
		check("Broken/unknown save is handled with a visible warning", restored.visited.is_empty() and restored.favorites.is_empty() and not restored.save_error.is_empty(), payload)
		check("Loading malformed progress leaves original bytes untouched", FileAccess.get_file_as_string(path) == payload)
	var unavailable: String = fixture("missing-parent/progress.json")
	restored.save_path = unavailable
	restored.toggle_favorite("001")
	check("Save-open failure leaves session favorites usable and shows warning", restored.favorites.has("001") and not restored.save_error.is_empty() and not FileAccess.file_exists(unavailable))

func check_hall_failure_and_retry() -> void:
	var scene_path: String = fixture("hall-model.tscn")
	write_fixture(scene_path, BROKEN_SCENE)
	# Dependency injection only: compile the CURRENT production script with its
	# first model URI changed to a unique fixture. No production method is copied,
	# replaced or reimplemented, and no project/model file is modified.
	var source: String = FileAccess.get_file_as_string("res://scripts/university_hall.gd")
	var original_path: String = str(Hall.MODEL_PATHS.atrium)
	check("Hall model dependency is present for safe fixture injection", source.count(original_path) == 1)
	var injected: GDScript = GDScript.new()
	injected.source_code = source.replace(original_path, scene_path)
	var compile_error: Error = injected.reload()
	check("Current hall script compiles with isolated model dependency", compile_error == OK, compile_error)
	if compile_error != OK:
		return
	hall = injected.new() as Node3D
	var progress_path: String = fixture("hall-progress.json")
	(hall.get("catalog") as RefCounted).save_path = progress_path
	root.add_child(hall)
	hall.set_process(false)
	var deadline: int = Time.get_ticks_msec() + 5000
	while str(hall.get("detail_state")) != "error" and Time.get_ticks_msec() < deadline:
		hall.call("_step_loading")
		await tick()
	check("Broken model reaches hall error UI state", str(hall.get("detail_state")) == "error" and not str(hall.get("detail_error")).is_empty())
	check("Hall clears failed request ownership/path", not bool(hall.get("requested_model")) and str(hall.get("loading_path")).is_empty())
	check("Hall consumes failed threaded task instead of poisoning retry", ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
	write_fixture(scene_path, FIXED_SCENE)
	hall.call("retry_loading")
	deadline = Time.get_ticks_msec() + 5000
	while int(hall.get("model_index")) == 0 and str(hall.get("detail_state")) != "error" and Time.get_ticks_msec() < deadline:
		hall.call("_step_loading")
		await tick()
	check("Actual hall Retry loads repaired resource at the same URI", int(hall.get("model_index")) == 1 and (hall.get("models") as Dictionary).get("atrium") is PackedScene, hall.get("detail_error"))
	check("Successful retry also consumes the threaded task", ResourceLoader.load_threaded_get_status(scene_path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)

func check_reaper_failure_recovery() -> void:
	var path: String = fixture("abandoned-model.tscn")
	write_fixture(path, BROKEN_SCENE)
	check("Abandoned fixture request starts", ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK)
	var terminal: int = await wait_for_thread(path)
	check("Abandoned fixture reaches failed terminal state", terminal == ResourceLoader.THREAD_LOAD_FAILED, terminal)
	var reaper: Node = Reaper.new()
	reaper.set("path", path)
	root.add_child(reaper)
	await tick(4)
	check("Reaper consumes FAILED terminal tasks and frees itself", not is_instance_valid(reaper) and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE)
	write_fixture(path, FIXED_SCENE)
	check("Reaped URI can start another request", ResourceLoader.load_threaded_request(path, "PackedScene", true) == OK)
	terminal = await wait_for_thread(path)
	check("Reaped URI recovers after the fixture is repaired", terminal == ResourceLoader.THREAD_LOAD_LOADED, terminal)
	if terminal in [ResourceLoader.THREAD_LOAD_LOADED, ResourceLoader.THREAD_LOAD_FAILED]:
		var result: Resource = ResourceLoader.load_threaded_get(path)
		check("Repaired abandoned scene is a valid PackedScene", result is PackedScene)

func check_navigation_and_escape() -> void:
	if not is_instance_valid(hall):
		return
	hall.call("travel_to_school", "001")
	hall.call("show_region", "south")
	check("Latest loading choice region supersedes school", str(hall.get("pending_school")).is_empty() and str(hall.get("pending_region")) == "south")
	# The first model was validated above. Skip unrelated art dependencies;
	# production loading completion, player readiness, navigation and UI still run.
	hall.set("model_index", Hall.MODEL_PATHS.size())
	var deadline: int = Time.get_ticks_msec() + 30000
	while not bool(hall.get("ready_for_play")) and Time.get_ticks_msec() < deadline:
		hall.call("_process", .01)
		await tick()
	check("Hall finishes readiness with the fixture model", bool(hall.get("ready_for_play")), hall.get("detail_error"))
	if not bool(hall.get("ready_for_play")):
		return
	check("Loading completion actually travels to the last selected region", str(hall.get("region")) == "south" and str(hall.get("pending_region")).is_empty())
	hall.set("ready_for_play", false)
	hall.call("show_region", "south")
	hall.call("travel_to_school", "003")
	check("Latest loading choice school supersedes region", str(hall.get("pending_region")).is_empty() and str(hall.get("pending_school")) == "003")
	hall.call("_process", .01)
	check("Loading completion actually reaches the last selected school", str(hall.get("region")) == "central" and str(hall.get("pending_school")).is_empty() and ((hall.get("space") as Node3D).get("booth_positions") as Dictionary).has("003"))
	hall.set("ready_for_play", false)
	hall.call("travel_to_school", "001")
	hall.call("show_atrium")
	check("Atrium cancels pending travel while only avatar readiness remains", str(hall.get("pending_school")).is_empty() and str(hall.get("pending_region")).is_empty())
	hall.call("_process", .01)
	check("Readiness cannot override the user's final atrium choice", str(hall.get("region")).is_empty())
	var ui: CanvasLayer = hall.get("ui") as CanvasLayer
	ui.call("open_directory", "all")
	await tick(4)
	var search: LineEdit = ui.get("search_box") as LineEdit
	search.grab_focus()
	search.text = "中興"
	search.text_changed.emit(search.text)
	await tick()
	check("Search owns focus before Escape regression", root.gui_get_focus_owner() == search)
	await press_escape()
	check("Escape closes directory even while the search box owns focus", not bool(ui.call("is_open")) and str(ui.get("current_panel")).is_empty())
	check("Escape restores the player's movement controls", bool((hall.get("player") as Node).get("controls_enabled")))
	ui.call("open_directory", "all")
	await tick(3)
	var filter: OptionButton = ui.get("region_filter") as OptionButton
	filter.grab_focus()
	await press_escape()
	check("Escape closes directory with region filter focused", not bool(ui.call("is_open")))
	ui.call("open_directory", "all")
	await tick(3)
	filter = ui.get("region_filter") as OptionButton
	filter.get_popup().popup()
	await tick(2)
	await press_escape()
	check("Escape dismisses an open filter popup", not filter.get_popup().visible, {"panel_open":ui.call("is_open"),"popup_open":filter.get_popup().visible})
	# PopupMenu is a subwindow and may consume the first Escape itself. Both
	# one-step closure and the normal popup-then-panel sequence are acceptable.
	if bool(ui.call("is_open")):
		await press_escape()
	check("Escape closes the directory after dismissing its filter popup", not bool(ui.call("is_open")))
	ui.call("open_directory", "all")
	await tick(3)
	filter = ui.get("region_filter") as OptionButton
	filter.get_popup().popup()
	await tick(2)
	ui.call("close_panel")
	check("Closing directory also hides its filter popup", not filter.get_popup().visible)

func finish() -> void:
	if is_instance_valid(hall):
		hall.queue_free()
	await tick(6)
	for path: String in fixtures:
		assert(path.begins_with(fixture_prefix) and path != Catalog.SAVE_PATH)
		if FileAccess.file_exists(path):
			var result: Error = DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
			check("Exact fixture file removed", result == OK, path)
	check("Player's real progress existence is unchanged", FileAccess.file_exists(Catalog.SAVE_PATH) == actual_save_existed)
	if actual_save_existed:
		check("Player's real progress bytes are unchanged", FileAccess.get_file_as_bytes(Catalog.SAVE_PATH) == actual_save_before)
	print("UNIVERSITY_EDGE_CHECKS ", JSON.stringify({"passed":failures == 0,"failures":failures,"checks":checks}))
	quit(0 if failures == 0 else 1)

func run() -> void:
	root.size = Vector2i(1280, 800)
	Engine.max_fps = 120
	fixture_prefix = "user://university_edge_%d_%d_" % [OS.get_process_id(), Time.get_ticks_usec()]
	actual_save_existed = FileAccess.file_exists(Catalog.SAVE_PATH)
	if actual_save_existed:
		actual_save_before = FileAccess.get_file_as_bytes(Catalog.SAVE_PATH)
	check_progress()
	await check_hall_failure_and_retry()
	await check_reaper_failure_recovery()
	await check_navigation_and_escape()
	await finish()
