extends SceneTree

## Real gameplay-camera review of all six districts. Run without --headless:
## Godot --path game --script res://tools/capture_world_redesign.gd -- --before
## Optional: --profile=low, --shot=counseling-waterfront (or overview).
## Readiness is checked from the production streaming and avatar contracts.
## Nothing is hidden or replaced for the capture; normal camera occlusion applies.
const Geo = preload("res://scripts/planet_geometry.gd")
const Fixture = preload("res://tests/startup_fixture.gd")
const TIMEOUT_MS: int = 120000
var world: Node3D
var player: PlanetPlayer
var camera: Camera3D
var hud: CanvasLayer
var streaming: Node
var settings: Node
var layout: Dictionary = {}
var districts: Array = []
var output: String
var profile: String = "standard"
var only_shot: String = ""
var report: Dictionary = {"images": [], "errors": []}

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("World art capture requires the real native renderer, not --headless.")
		quit(1)
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for arg: String in args:
		if arg.begins_with("--profile="):
			profile = arg.trim_prefix("--profile=")
		elif arg.begins_with("--shot="):
			only_shot = arg.trim_prefix("--shot=")
	if profile not in ["standard", "low", "balanced", "mobile"]:
		push_error("Unknown capture quality profile: " + profile)
		quit(1)
		return
	var label: String = "before" if args.has("--before") else "after"
	output = ProjectSettings.globalize_path("res://../deliverables/world-redesign/" + label)
	if profile != "standard":
		output = output.path_join(profile)
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 900)
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	districts = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	player = world.get("player") as PlanetPlayer
	camera = world.get("camera") as Camera3D
	hud = world.get("hud") as CanvasLayer
	streaming = world.get("streaming") as Node
	settings = hud.get("graphics_settings") as Node
	settings.set("settings_path", "user://world_redesign_capture.cfg")
	settings.call("set_quality_profile", profile)
	settings.call("set_frame_limit", 30)
	player.allow_test_input = false
	player.test_direction = Vector2.ZERO
	player.controls_enabled = false
	hud.visible = true
	hud.call("close_panel")
	(hud.get("destination_card") as Control).visible = false
	report.merge({"phase": label, "profile": profile, "engine": Engine.get_version_info(),
		"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
		"source": "res://scenes/world.tscn", "selected_shot": only_shot,
		"method": "Unmodified game scene; production avatar preparation, district chunk readiness and activation, grounded real player, production roaming camera and HUD. No screenshot-only lighting or geometry."})
	var transforms: Dictionary = {}
	for node_name: String in ["Globe", "Neighborhood", "Stations"]:
		transforms[node_name] = var_to_str((world.get_node(node_name) as Node3D).transform)
	report["saved_world_transforms"] = transforms
	var startup_deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while not bool(world.get("startup_presented")) and Time.get_ticks_msec() < startup_deadline:
		await process_frame
	if not bool(world.get("startup_presented")):
		report.errors.append("Startup presentation timed out")
	if wanted("overview"):
		world.call("set_overview", true)
		world.set("orbit_yaw", .45)
		world.set("orbit_pitch", .9)
		world.set("orbit_distance", float(world.layout.radius)*world.OVERVIEW_DISTANCE)
		world.call("update_camera", 0.0)
		await take("00-overview", "overview", -1, true)
	for index: int in range(layout.stations.size()):
		var id: String = str(layout.stations[index].id)
		if wanted(id + "-city"):
			print("WORLD_REDESIGN_PREPARE ", id, " city")
			world.call("teleport_to", id)
			world.set("near_distance", 7.0)
			world.set("near_pitch", .28)
			camera.fov = 48.0
			var city_ready: bool = await wait_for_scene(id)
			await take("%02d-%s-city" % [index * 2 + 1, id], "city", index, city_ready)
		if wanted(id + "-waterfront"):
			print("WORLD_REDESIGN_PREPARE ", id, " waterfront")
			world.call("setup_water_review", index, false)
			camera.fov = 48.0
			var water_ready: bool = await wait_for_scene(id)
			await take("%02d-%s-waterfront" % [index * 2 + 2, id], "waterfront", index, water_ready)
		if wanted(id + "-biome"):
			var positions: Array[Vector2] = [Vector2(-120,-65),Vector2(125,-112),Vector2(-116,-123),Vector2(116,107),Vector2(109,106),Vector2(75,119)]
			var normals: Array = layout.stations[index].normal
			var up := Vector3(normals[0],normals[1],normals[2]).normalized()
			var normal: Vector3 = Geo.surface(up,positions[index],float(layout.radius)).normalized()
			player.finish_entry()
			var ground: Dictionary = player.ground_at(normal)
			var height: float = (ground.position as Vector3).length()+.1 if not ground.is_empty() else float(layout.radius)+35.0
			player.teleport(normal,height)
			var view_direction := Vector2(1,-.3) if index==1 else Vector2(.8,-.6)
			player.heading = (Geo.frame(up).x*view_direction.x+Geo.frame(up).z*view_direction.y).slide(normal).normalized()
			world.call("set_overview",false)
			world.set("near_distance",7.0)
			world.set("near_pitch",.18)
			camera.fov = 60.0
			var ready: bool = await wait_for_scene(id)
			await take("%02d-%s-biome" % [index+13,id],"biome",index,ready)
	if wanted("overview-back"):
		world.call("set_overview",true)
		world.set("orbit_yaw",3.6)
		world.set("orbit_pitch",-.65)
		world.set("orbit_distance",float(layout.radius)*world.OVERVIEW_DISTANCE)
		camera.fov = 42.0
		world.call("update_camera",0.0)
		await take("19-overview-back","overview",-1,true)
	report["passed"] = (report.errors as Array).is_empty() and ((report.images as Array).size() == 20 if only_shot.is_empty() else (report.images as Array).size() == 1)
	write_report()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://world_redesign_capture.cfg"))
	print("WORLD_REDESIGN_CAPTURE_COMPLETE ", output, " passed=", report.passed, " images=", (report.images as Array).size())
	current_scene = null
	world.queue_free()
	await process_frame
	quit(0 if bool(report.passed) else 1)

func wanted(shot: String) -> bool:
	return only_shot.is_empty() or only_shot == shot

func wait_for_scene(id: String) -> bool:
	if not await Fixture.wait_roaming(world, self, TIMEOUT_MS):
		report.errors.append(id + ": production roaming preparation failed")
		return false
	player.controls_enabled = false
	player.allow_test_input = false
	var deadline: int = Time.get_ticks_msec() + TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		var region: Dictionary = (streaming.get("_regions") as Dictionary).get(id, {}) as Dictionary
		var ready: bool = bool(region.get("ready", false)) and bool(region.get("active", false))
		if ready and bool(streaming.call("is_position_ready", player.global_position)) and player.visuals_ready():
			break
		var error: String = str(streaming.call("position_error", player.global_position))
		if not error.is_empty():
			report.errors.append(id + ": " + error)
			return false
		await process_frame
	if Time.get_ticks_msec() >= deadline:
		report.errors.append(id + ": district chunks were not ready and active before timeout")
		return false
	# Wait for actual physics stability, never infer grounding from a frame count.
	var stable_since: int = -1
	var floor_deadline: int = Time.get_ticks_msec() + 8000
	var previous: Vector3 = player.global_position
	while Time.get_ticks_msec() < floor_deadline:
		await physics_frame
		var ground: Dictionary = player.ground_at(player.global_position.normalized())
		var stable: bool = player.is_on_floor() and not ground.is_empty() and not player.needs_settle and previous.distance_to(player.global_position) < .003
		previous = player.global_position
		if stable:
			if stable_since < 0:
				stable_since = Time.get_ticks_msec()
			if Time.get_ticks_msec() - stable_since >= 350:
				world.call("update_camera", 1.0 / 30.0)
				return true
		else:
			stable_since = -1
	report.errors.append(id + ": player did not settle on walkable ground")
	return false

func take(label: String, kind: String, index: int, ready: bool) -> void:
	world.call("update_camera", 1.0 / 30.0)
	if kind != "overview":
		world.call("update_nearest")
		(hud.get("minimap") as Control).call("refresh")
	# The render barrier is after the readiness gates and final camera update.
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var error: Error = pixels.save_png(output.path_join(label + ".png"))
	var ground: Dictionary = player.ground_at(player.global_position.normalized()) if kind != "overview" else {}
	var active_regions: Array[Dictionary] = []
	for id: String in streaming.get("_regions") as Dictionary:
		var region: Dictionary = (streaming.get("_regions") as Dictionary)[id]
		if bool(region.active) or bool(region.requested):
			active_regions.append({"id": id, "ready": region.ready, "active": region.active,
				"loaded_chunks": region.next, "total_chunks": (region.chunks as Array).size()})
	var row: Dictionary = {"file": label + ".png", "kind": kind, "ready": ready, "saved": error == OK,
		"station": str(layout.stations[index].id) if index >= 0 else "all", "theme": str(districts[index].theme) if index >= 0 else "world",
		"player_position": vector_array(player.global_position), "heading": vector_array(player.heading),
		"camera_position": vector_array(camera.global_position), "camera_basis": var_to_str(camera.global_basis),
		"camera_aim": vector_array(world.get("camera_aim") as Vector3), "fov": camera.fov,
		"distance": world.get("near_distance"), "pitch": world.get("near_pitch"),
		"avatar_ready": player.visuals_ready(), "on_floor": player.is_on_floor(),
		"ground_collider": str((ground.collider as Node).get_path()) if not ground.is_empty() else "none",
		"active_regions": active_regions, "hud_visible": hud.visible,
		"graphics": settings.call("get_state"), "draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "resolution": [pixels.get_width(), pixels.get_height()]}
	(report.images as Array).append(row)
	if error != OK:
		report.errors.append("Could not save " + label)
	write_report()
	print("WORLD_REDESIGN_FRAME ", label, " ready=", ready, " grounded=", row.on_floor, " output=", output.path_join(label + ".png"))

func vector_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func write_report() -> void:
	var file_name: String = "capture-report.json" if only_shot.is_empty() else "capture-" + only_shot + ".json"
	FileAccess.open(output.path_join(file_name), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
