extends SceneTree
## Verifies the shipped exhibit kit against every curated school profile.
## --capture records ordinary third-person travel views with the real renderer.

const OUTPUT: String = "res://../deliverables/university-hall/diversity/"
const HERO_NAMES: Array[String] = ["國立臺灣大學", "國立中興大學", "國立政治大學", "國立臺灣海洋大學", "東海大學", "國立臺北藝術大學", "臺北醫學大學", "國立臺灣科技大學"]
var hall: Node3D
var failures: int = 0
var checks: Array[Dictionary] = []
var captures: Array[Dictionary] = []
var capture: bool = false

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"name":label, "passed":passed, "evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func tick(count: int = 2) -> void:
	for frame: int in range(count):
		await process_frame

func detail_sample() -> Dictionary:
	var times: Array[float] = []
	var last: int = Time.get_ticks_usec()
	var deadline: int = Time.get_ticks_msec() + 2000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		var now: int = Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
	times.sort()
	var elapsed: float = 0
	for interval: float in times:
		elapsed += interval
	return {"mean_fps":1000.0 * times.size() / maxf(elapsed, 1), "p95_ms":times[mini(times.size() - 1, ceili(times.size() * .95))], "frames":times.size(), "draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), "primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)}

func run() -> void:
	root.size = Vector2i(1440, 900)
	Engine.max_fps = 30 if capture else 0
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	hall = (load("res://scenes/university_hall.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(hall)
	current_scene = hall
	var deadline: int = Time.get_ticks_msec() + 60000
	while not bool(hall.get("ready_for_play")) and Time.get_ticks_msec() < deadline:
		await tick()
	check("Hall and new exhibit kit load", bool(hall.get("ready_for_play")), hall.get("detail_error"))
	if not bool(hall.get("ready_for_play")):
		await finish()
		return
	var space: Node3D = hall.get("space") as Node3D
	var catalog: RefCounted = hall.get("catalog") as RefCounted
	var kit: Node3D = (hall.models.exhibit_kit as PackedScene).instantiate() as Node3D
	var invalid_modules: Array[String] = []
	for module: Node in kit.get_children():
		if not module is MeshInstance3D or module.get_child_count() != 0 or (module as MeshInstance3D).mesh == null or not (module as Node3D).transform.is_equal_approx(Transform3D.IDENTITY):
			invalid_modules.append(str(module.name))
	check("Kit modules are standalone meshes with applied transforms", invalid_modules.is_empty(), invalid_modules)
	check("Kit contains eight display forms and at least 32 miniature components", kit.get_child_count() >= 40, kit.get_child_count())
	kit.free()
	var visited_before: Dictionary = catalog.visited.duplicate()
	var favorites_before: Dictionary = catalog.favorites.duplicate()
	var designs: Dictionary = {}
	var entries_seen: int = 0
	for region: String in catalog.REGION_IDS:
		for page: int in range(catalog.page_count(region)):
			hall.call("show_region", region, page)
			await tick(3)
			check("%s/%d has no missing exhibit components" % [region, page + 1], space.exhibit_errors.is_empty(), space.exhibit_errors.duplicate())
			for entry: Dictionary in catalog.page_entries(region, page):
				var booth: Node3D = space.get_node_or_null("School_" + str(entry.id)) as Node3D
				var miniature: Node3D = booth.get_node_or_null("Diorama") if booth != null else null
				var profile: Dictionary = entry.get("art_profile", {})
				check(str(entry.id) + " instantiates its curated composition", miniature != null and miniature.get_child_count() == profile.get("modules", []).size() and miniature.get_child_count() >= 3)
				designs[str(entry.id)] = {"name":entry.name, "display":profile.get("display_variant", ""), "composition":profile.get("composition", ""), "modules":profile.get("modules", []).size()}
				entries_seen += 1
	check("Every school receives an authored exhibit profile", entries_seen == 138, entries_seen)
	for school_name: String in HERO_NAMES:
		var selected: Dictionary = {}
		for entry: Dictionary in catalog.entries:
			if str(entry.name) == school_name:
				selected = entry
		check(school_name + " is present", not selected.is_empty())
		if selected.is_empty():
			continue
		hall.call("travel_to_school", str(selected.id))
		await tick(15)
		for settled_frame: int in range(8):
			await physics_frame
		hall.call("update_camera", 0, true)
		var filename: String = "%s-exhibit.png" % str(selected.id)
		if capture:
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + filename))
		var view: Dictionary = {"id":selected.id, "name":selected.name, "design":designs[str(selected.id)], "state":hall.call("debug_state")}
		if capture:
			view["image"] = filename
		var original_position: Vector3 = hall.player.position
		var original_camera: Transform3D = hall.camera.global_transform
		hall.call("inspect_school", str(selected.id))
		await tick(12)
		check(str(selected.id) + " close viewing locks movement and hides the avatar", not hall.player.controls_enabled and not hall.player.visible and not hall.call("can_player_jump"))
		if capture:
			await RenderingServer.frame_post_draw
			var closeup: String = "%s-detail.png" % str(selected.id)
			root.get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT + closeup))
			view["detail_image"] = closeup
			view["detail_performance"] = await detail_sample()
		if str(selected.id) == "001":
			Input.action_press("move_forward")
			await tick(6)
			Input.action_release("move_forward")
			check("Inspection does not move the player", hall.player.position.distance_to(original_position) < .01)
			var heading: Vector3 = hall.player.heading
			hall.call("touch_look", Vector2(80, 25))
			hall.call("zoom_inspection", -.7)
			await tick(3)
			check("Close view rotates and zooms without changing heading", hall.inspection_angle < .15 and hall.inspection_distance < 3.65 and hall.player.heading.is_equal_approx(heading))
			hall.call("reset_inspection")
			var touch: InputEventScreenTouch = InputEventScreenTouch.new()
			touch.position = Vector2(500, 400)
			touch.pressed = true
			Input.parse_input_event(touch)
			await tick(2)
			var finger_drag: InputEventScreenDrag = InputEventScreenDrag.new()
			finger_drag.position = Vector2(520, 400)
			finger_drag.relative = Vector2(20, 0)
			finger_drag.screen_relative = Vector2(20, 0)
			Input.parse_input_event(finger_drag)
			await tick(2)
			touch.pressed = false
			Input.parse_input_event(touch)
			await tick(2)
			check("Touch inspection counts one rotation, excluding emulated mouse events", is_equal_approx(float(hall.inspection_angle), .07), hall.inspection_angle)
			var escape: InputEventKey = InputEventKey.new()
			escape.keycode = KEY_ESCAPE
			escape.pressed = true
			Input.parse_input_event(escape)
		else:
			hall.call("close_inspection")
		await tick(3)
		check(str(selected.id) + " closing restores third-person controls and camera", hall.inspection_id.is_empty() and hall.player.visible and hall.player.controls_enabled and hall.camera.global_position.distance_to(original_camera.origin) < .005 and hall.camera.global_basis.get_rotation_quaternion().angle_to(original_camera.basis.get_rotation_quaternion()) < .002, {"camera_delta":hall.camera.global_position.distance_to(original_camera.origin), "visible":hall.player.visible, "controls":hall.player.controls_enabled})
		captures.append(view)
	check("Art navigation does not alter exploration or favorites", catalog.visited == visited_before and catalog.favorites == favorites_before)
	await finish()

func finish() -> void:
	var file: FileAccess = FileAccess.open(OUTPUT + ("native-art-report.json" if capture else "art-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":failures == 0, "failures":failures, "checks":checks, "captures":captures, "renderer":DisplayServer.get_name(), "method":"Real runtime third-person school travel views; no substitute concept renders."}, "\t"))
	file.close()
	if is_instance_valid(hall):
		for voice: Node in hall.find_children("*", "AudioStreamPlayer", true, false):
			(voice as AudioStreamPlayer).stop()
		await create_timer(.15).timeout
		hall.queue_free()
	await tick(6)
	print("UNIVERSITY_ART_CHECKS total=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)
