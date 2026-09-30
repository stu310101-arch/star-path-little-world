extends SceneTree
## Native, fixed-step review of the actual PlanetPlayer and imported animations.
## Run after the new GLB has been imported, without --headless:
## godot --path game -d --ignore-error-breaks --script res://tools/capture_refined_frontflip.gd
## Optional user args: --sequence=standing|moving|both --view=front|side|both
## --samples-only captures selected poses instead of the complete 30 FPS strip.
## Default: both sequences, full front-threequarter strip, selected side poses.

const PlayerScript = preload("res://scripts/planet_player.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const OUTPUT: String = "res://../deliverables/frontflip-refined/studio/"
const RADIUS: float = 48.0
const DT: float = 1.0 / 60.0
const CAPTURE_EVERY: int = 2
const JUMP_TICK: int = 24
const STANDING_TICKS: int = 192
const MOVING_TICKS: int = 228

var player: PlanetPlayer
var camera: Camera3D
var caption: Label
var arena: Node3D
var sequence_option: String = "both"
var view_option: String = "front"
var samples_only: bool = false
var requested_sequences: Array[String] = []
var reports: Array[Dictionary] = []
var errors: Array[String] = []
var records: Array[Dictionary] = []
var trace: Array[Dictionary] = []
var frame_counts: Dictionary = {}
var seen_phases: Dictionary = {}
var output_directory: String = ""

func _initialize() -> void:
	call_deferred("run")

func fail(message: String) -> void:
	errors.append(message)
	push_error(message)

func parse_options() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--sequence="):
			sequence_option = argument.trim_prefix("--sequence=")
		elif argument.begins_with("--view="):
			view_option = argument.trim_prefix("--view=")
		elif argument == "--samples-only":
			samples_only = true
		else:
			fail("Unknown frontflip capture argument: " + argument)
	if sequence_option not in ["standing", "moving", "both"]:
		fail("--sequence must be standing, moving, or both")
	if view_option not in ["front", "side", "both"]:
		fail("--view must be front, side, or both")
	if not errors.is_empty():
		return false
	requested_sequences = ["standing", "moving"] if sequence_option == "both" else [sequence_option]
	return true

func surface_material(color: Color) -> StandardMaterial3D:
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.92
	return result

func build_stage() -> void:
	arena = Node3D.new()
	arena.name = "FrontflipClothReviewStage"
	root.add_child(arena)
	current_scene = arena
	var environment_node: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("34454d")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("e4eaf1")
	environment.ambient_light_energy = 0.70
	environment_node.environment = environment
	arena.add_child(environment_node)
	var key_light: DirectionalLight3D = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-42.0, -32.0, 0.0)
	key_light.light_color = Color("fff2df")
	key_light.light_energy = 1.15
	key_light.shadow_enabled = true
	arena.add_child(key_light)
	var fill_light: DirectionalLight3D = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-28.0, 145.0, 0.0)
	fill_light.light_color = Color("dce9ff")
	fill_light.light_energy = 0.40
	fill_light.shadow_enabled = false
	arena.add_child(fill_light)
	# A plain patch of the player's actual radial ground keeps the moving
	# sequence supported, with no railings or props hiding the garment.
	var surface: SurfaceTool = SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: int in range(-18, 18):
		for z: int in range(-18, 18):
			var a: Vector3 = Geo.surface(Vector3.UP, Vector2(x, z), RADIUS)
			var b: Vector3 = Geo.surface(Vector3.UP, Vector2(x + 1, z), RADIUS)
			var c: Vector3 = Geo.surface(Vector3.UP, Vector2(x + 1, z + 1), RADIUS)
			var d: Vector3 = Geo.surface(Vector3.UP, Vector2(x, z + 1), RADIUS)
			Geo.triangle(surface, a, b, c, Color.WHITE)
			Geo.triangle(surface, a, c, d, Color.WHITE)
	Geo.mesh_node(arena, "UnobstructedReviewFloor", surface.commit(), surface_material(Color("a4aaa5")), true)
	player = PlayerScript.new() as PlanetPlayer
	player.planet_radius = RADIUS
	player.controls_enabled = false
	player.allow_test_input = true
	arena.add_child(player)
	# No automatic player tick is allowed, even during PNG writes or a
	# secondary camera render. AnimationPlayer is manual in PlanetPlayer.
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 4.15
	camera.near = 0.05
	camera.far = 120.0
	arena.add_child(camera)
	camera.make_current()
	var overlay: CanvasLayer = CanvasLayer.new()
	arena.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(26.0, 20.0)
	caption.add_theme_font_size_override("font_size", 21)
	caption.add_theme_color_override("font_color", Color("f7f2e7"))
	caption.add_theme_color_override("font_shadow_color", Color("24333b"))
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	overlay.add_child(caption)

func fixed_step() -> void:
	# move_and_slide selects the engine physics delta while this signal is
	# executing. Calling the player from a render coroutine without awaiting
	# physics_frame would instead allow variable process time into movement.
	await physics_frame
	if not Engine.is_in_physics_frame():
		fail("Manual player step was not scheduled inside a physics frame")
		return
	player._physics_process(DT)

func stage_player() -> void:
	player.test_direction = Vector2.ZERO
	player.test_running = false
	player.jump_button_held = false
	player.teleport(Vector3.UP, RADIUS + 0.35)
	player.visual.rotation.y = PI
	player.set_clip(&"Idle")
	for _warmup: int in range(40):
		await fixed_step()
	if not player.is_on_floor() or player.needs_settle:
		fail("Capture could not establish a grounded starting pose")

func position_camera(view_name: String) -> void:
	var up: Vector3 = player.global_position.normalized()
	var forward: Vector3 = player.heading.normalized()
	var right: Vector3 = forward.cross(up).normalized()
	# Track the ground horizontally, not the airborne feet: the fixed vertical
	# composition displays the full flight and makes its height readable.
	var target: Vector3 = up * RADIUS + up * 1.72
	var offset: Vector3 = right * 7.0 if view_name == "side" else forward * 5.5 + right * 3.8
	camera.global_transform = Transform3D(Basis.IDENTITY, target + offset + up * 0.15).looking_at(target, up)

func vector_data(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

func player_state(tick: int) -> Dictionary:
	return {
		"tick": tick, "seconds": float(tick) * DT,
		"state": str(player.jump_state), "clip": str(player.active_clip),
		"position": vector_data(player.global_position),
		"velocity": vector_data(player.velocity), "grounded": player.is_on_floor(),
		"jump_clock": player.jump_clock, "landing_clock": player.landing_clock,
		"flip_progress": player.flip_progress, "jump_height": player.jump_height,
		"jump_count": player.jump_count, "landing_count": player.landing_count,
		"recovery_clip": str(player.recovery_clip), "recovery_clock": player.recovery_clock,
		"jump_model_visible": player.jump_model != null and player.jump_model.visible,
		"locomotion_model_visible": player.locomotion_model.visible,
		"automatic_player_physics": player.is_physics_processing()
	}

func selected_phase(tick: int) -> String:
	var candidates: Array[String] = []
	if tick == 0:
		candidates.append("01-before-jump")
	if player.jump_state == &"anticipation" and tick >= JUMP_TICK + 3:
		candidates.append("02-anticipation")
	if player.jump_state == &"airborne":
		candidates.append("03-takeoff")
		if player.flip_progress >= 0.25:
			candidates.append("04-tuck")
		if player.flip_progress >= 0.50:
			candidates.append("05-inverted")
		if player.flip_progress >= 0.83:
			candidates.append("06-opening")
	if player.jump_state == &"landing":
		candidates.append("07-contact")
		if player.landing_clock >= 0.20:
			candidates.append("08-settle-020")
		if player.landing_clock >= 0.60:
			candidates.append("09-settle-060")
		if player.landing_clock >= 1.00:
			candidates.append("10-settle-100")
	if tick > JUMP_TICK and player.jump_state == &"grounded" and player.landing_count > 0:
		candidates.append("11-recovered")
	for candidate: String in candidates:
		if not seen_phases.has(candidate):
			seen_phases[candidate] = tick
			return candidate
	return ""

func capture_frame(sequence_name: String, view_name: String, tick: int, phase: String) -> void:
	position_camera(view_name)
	var description: String = "Standing frontflip" if sequence_name == "standing" else "Moving frontflip and recovery"
	caption.text = description + "  /  " + ("Side" if view_name == "side" else "Front three-quarter")
	caption.text += "\n%s  |  %.2f s" % [str(player.active_clip), float(tick) * DT]
	if player.jump_state == &"landing":
		caption.text += "  |  cloth settle %.2f / %.2f s" % [player.landing_clock, PlanetPlayer.JUMP_LAND_DURATION]
	var before_render: Dictionary = player_state(tick)
	await process_frame
	await RenderingServer.frame_post_draw
	# The two views must describe the exact same pose, regardless of how many
	# automatic engine frames elapsed while the renderer or PNG encoder ran.
	if player_state(tick) != before_render:
		fail("Player advanced while a review pose was being rendered")
	var image_data: Image = root.get_texture().get_image()
	var frame_index: int = int(frame_counts.get(view_name, 0))
	var relative_file: String = view_name + "/frame_%04d.png" % frame_index
	var save_error: Error = image_data.save_png(output_directory + relative_file)
	if save_error != OK:
		fail("Cannot write " + relative_file + ": " + error_string(save_error))
	var record: Dictionary = before_render.duplicate(true)
	record.merge({"frame": frame_index, "view": view_name, "file": relative_file,
		"phase": phase, "width": image_data.get_width(), "height": image_data.get_height(),
		"camera_position": vector_data(camera.global_position), "saved": save_error == OK})
	records.append(record)
	frame_counts[view_name] = frame_index + 1

func write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		fail("Cannot write manifest " + path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()

func run_sequence(sequence_name: String) -> void:
	await stage_player()
	if not errors.is_empty():
		return
	output_directory = ProjectSettings.globalize_path(OUTPUT + sequence_name + "/")
	for view_name: String in ["front", "side"]:
		var directory_error: Error = DirAccess.make_dir_recursive_absolute(output_directory + view_name)
		if directory_error != OK:
			fail("Cannot create capture directory: " + error_string(directory_error))
	records = []
	trace = []
	frame_counts = {}
	seen_phases = {}
	var starting_jumps: int = player.jump_count
	var starting_landings: int = player.landing_count
	var total_ticks: int = STANDING_TICKS if sequence_name == "standing" else MOVING_TICKS
	var accepted: bool = false
	for tick: int in range(total_ticks + 1):
		if tick == JUMP_TICK:
			# request_jump is the same guarded gameplay path as a Space press;
			# invoking it here fixes its timing independently of OS input latency.
			accepted = player.request_jump()
			if not accepted:
				fail("PlanetPlayer rejected the staged " + sequence_name + " jump")
		if sequence_name == "moving":
			player.test_direction = Vector2(0.0, -1.0) if tick >= 12 and tick < 196 else Vector2.ZERO
		if tick > 0:
			await fixed_step()
		var state: Dictionary = player_state(tick)
		trace.append(state)
		var phase: String = selected_phase(tick)
		var regular_frame: bool = tick % CAPTURE_EVERY == 0 and not samples_only
		if (view_option in ["front", "both"]) and (regular_frame or (samples_only and phase != "")):
			await capture_frame(sequence_name, "front", tick, phase)
		# Default front mode also records selected side poses. Explicit side or
		# both mode produces a complete side strip for another fixed-FPS video.
		if ((view_option in ["side", "both"]) and (regular_frame or (samples_only and phase != ""))) or (view_option == "front" and phase != ""):
			await capture_frame(sequence_name, "side", tick, phase)
		if tick % 60 == 0:
			print("REFINED_FRONTFLIP_CAPTURE sequence=", sequence_name, " tick=", tick, "/", total_ticks, " clip=", player.active_clip)
		if not errors.is_empty():
			break
	player.test_direction = Vector2.ZERO
	var full_settle: bool = seen_phases.has("10-settle-100") and seen_phases.has("11-recovered") and player.landing_clock >= PlanetPlayer.JUMP_LAND_DURATION
	var recovery_seen: bool = false
	var landing_visible: bool = true
	for row: Dictionary in trace:
		if str(row.state) == "landing":
			landing_visible = landing_visible and bool(row.jump_model_visible) and str(row.clip) == "JumpLand"
			if str(row.recovery_clip) == "Walk" and float(row.landing_clock) < PlanetPlayer.JUMP_LAND_DURATION:
				recovery_seen = true
	var passed: bool = accepted and player.jump_count == starting_jumps + 1 and player.landing_count == starting_landings + 1 and player.is_on_floor() and player.jump_state == &"grounded" and full_settle and landing_visible and (sequence_name != "moving" or recovery_seen) and errors.is_empty()
	var report: Dictionary = {
		"sequence": sequence_name, "passed": passed, "simulation_fps": 60, "capture_fps": 30,
		"samples_only": samples_only, "view_option": view_option, "total_ticks": total_ticks,
		"jump_request_tick": JUMP_TICK, "jump_request_accepted": accepted,
		"full_landing_settle": full_settle, "landing_model_remained_visible": landing_visible,
		"walking_recovery_during_cloth_settle": recovery_seen, "phase_ticks": seen_phases,
		"frame_counts": frame_counts, "frames": records, "trace": trace,
		"final_state": player_state(total_ticks), "errors": errors,
		"video_note": "Continuous views are numbered from 0000 at 30 FPS; selected side views and --samples-only use each frame's seconds/tick from this manifest. Only files listed here belong to this run."
	}
	write_json(output_directory + "capture.json", report)
	reports.append({"sequence": sequence_name, "passed": passed, "manifest": sequence_name + "/capture.json", "frame_counts": frame_counts.duplicate(), "full_landing_settle": full_settle, "walking_recovery_during_cloth_settle": recovery_seen})
	if not passed:
		fail("Refined frontflip capture validation failed for " + sequence_name)

func run() -> void:
	if not parse_options():
		quit(1)
		return
	if DisplayServer.get_name() == "headless":
		fail("Refined frontflip capture requires native rendering; remove --headless")
		quit(1)
		return
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
	Engine.max_fps = 60
	root.size = Vector2i(1100, 900)
	root.title = "Refined Frontflip - Native Cloth Review"
	for action: String in ["move_left", "move_right", "move_forward", "move_back", "run", "jump"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	build_stage()
	if player.jump_animator == null:
		fail("Imported frontflip asset has no AnimationPlayer")
	for sequence_name: String in requested_sequences:
		if not errors.is_empty():
			break
		await run_sequence(sequence_name)
	var summary: Dictionary = {
		"passed": errors.is_empty() and reports.size() == requested_sequences.size(),
		"jump_asset": PlanetPlayer.JUMP_MODEL,
		"jump_asset_sha256": FileAccess.get_sha256(PlanetPlayer.JUMP_MODEL),
		"engine_version": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"simulation_dt": DT, "capture_fps": 30, "sequences": reports, "errors": errors,
		"method": "Actual PlanetPlayer request_jump, physics and imported animation. Automatic player physics disabled; one explicit 1/60-second step inside each requested physics_frame. Rendering waits never step the player. Plain spherical ground, no occluding obstacles."
	}
	write_json(ProjectSettings.globalize_path(OUTPUT + "capture.json"), summary)
	print("REFINED_FRONTFLIP_STUDIO ", JSON.stringify(summary))
	quit(0 if errors.is_empty() else 1)
