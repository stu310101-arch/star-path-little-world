extends SceneTree

const Streamer = preload("res://scripts/district_streaming.gd")
const Quality = preload("res://scripts/mobile_render_quality.gd")
const Art = preload("res://scripts/world_art_direction.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Bench = preload("res://scripts/bench_interaction.gd")
var checks: Array[Dictionary] = []
var samples: Array[Dictionary] = []
var failures: int = 0
var world: Node3D
var streamer: Node
var camera: Camera3D
var art: RefCounted
var output: String
var rendered: bool
var focus: Vector3
var radius: float
var baseline_nodes: int
var baseline_colliders: int
var baseline_seats: int
var baseline_arrivals: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func advance(count: int) -> void:
	for _index: int in range(count):
		streamer.call("update_context", false, focus, camera.global_position, focus, .16)
		await process_frame

func drain() -> void:
	streamer.call("set_constrained_runtime", true)
	await advance(95)

func setup() -> void:
	rendered = DisplayServer.get_name() != "headless"
	output = ProjectSettings.globalize_path("res://../deliverables/low-end-20261021/constrained-streaming-" + ("rendered" if rendered else "headless"))
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_scale = .5
	if rendered:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	Engine.max_fps = 0
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	# Isolate the production world/streamer from HUD, input and account modals.
	# Production art, bases, detail chunks and render settings are unchanged.
	world.set_script(null)
	root.add_child(world)
	current_scene = world
	art = Art.new()
	art.call("set_mobile_quality", true)
	art.call("configure", world)
	(world.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	streamer = Streamer.new() as Node
	world.add_child(streamer)
	streamer.connect("chunk_added", func(chunk: Node3D) -> void: art.call("apply", chunk))
	streamer.call("configure", world)
	streamer.call("set_low_quality", true)
	streamer.get("_mobile_render").call("set_enabled", true)
	camera = Camera3D.new()
	camera.fov = 55.0
	camera.near = .1
	camera.far = 160.0
	world.add_child(camera)
	camera.make_current()
	radius = float(JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")).radius)
	baseline_nodes = world.find_children("*", "", true, false).size()
	baseline_colliders = world.find_children("*", "StaticBody3D", true, false).size()
	for body: StaticBody3D in world.find_children("*", "StaticBody3D", true, false):
		if Bench.is_bench(body): baseline_seats += 1
	for station: Node3D in world.get_node("Stations").get_children():
		if station.has_node("Arrival"):
			baseline_arrivals[str(station.name)] = (station.get_node("Arrival") as Marker3D).global_transform
	focus = Vector3.UP * radius
	camera.position = focus + Vector3(0, 3, 4)

func place_at(id: String) -> void:
	var station: Node3D = world.get_node("Stations/" + id) as Node3D
	focus = (station.get_node("Arrival") as Marker3D).global_position
	var up: Vector3 = focus.normalized()
	var heading: Vector3 = (station.global_position - focus).slide(up).normalized()
	var aim: Vector3 = focus + up * .4
	var eye: Vector3 = aim + (-heading * cos(.58) + up * sin(.58)) * 2.8
	camera.global_transform = Transform3D(Basis.IDENTITY, eye).looking_at(aim, up)
	art.call("update", up, false)

func capture_sample(label: String) -> void:
	await advance(6)
	var frame_times: Array[float] = []
	var cpu: Array[float] = []
	var gpu: Array[float] = []
	var previous: int = Time.get_ticks_usec()
	if rendered:
		for _frame: int in range(60):
			await process_frame
			var now: int = Time.get_ticks_usec()
			frame_times.append(float(now - previous) / 1000.0)
			previous = now
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()))
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join(label + ".png"))
	var row: Dictionary = {"stage":label, "nodes":world.find_children("*", "", true, false).size(),
		"streaming":streamer.call("metrics"), "camera":str(camera.global_transform),
		"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		"render_buffer_bytes":Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED),
		"render_texture_bytes":Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)}
	if rendered:
		frame_times.sort(); cpu.sort(); gpu.sort()
		row["frame_median_ms"] = frame_times[frame_times.size() / 2]
		row["render_cpu_median_ms"] = cpu[cpu.size() / 2]
		row["gpu_median_ms"] = gpu[gpu.size() / 2]
	samples.append(row)
	print("CONSTRAINED_STREAMING_SAMPLE ", JSON.stringify(row))

func verify_ground() -> void:
	var missing: int = 0
	var total: int = 0
	for edge: Vector2i in Routes.bridge_edges():
		var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge, radius)
		for index: int in range(33):
			total += 1
			var normal: Vector3 = endpoints[0].slerp(endpoints[1], float(index) / 32.0)
			if Geo.ground_probe(world.get_world_3d().direct_space_state, normal, radius).is_empty(): missing += 1
	check("Baked roaming keeps permanent bridge/approach support", missing == 0, {"samples":total,"missing":missing})

func verify_material_lifetime() -> void:
	var helper: RefCounted = Quality.new()
	var source: StandardMaterial3D = StandardMaterial3D.new()
	var material: Material = helper.call("mobile_material", source) as Material
	var reference: WeakRef = weakref(material)
	check("Live users still share one mobile material", helper.call("mobile_material", source) == material)
	material = null
	check("Mobile material cache does not keep unloaded resources alive", reference.get_ref() == null)
	helper.call("_prune_material_cache")
	check("Dead material cache entries are removed", (helper.get("_materials") as Dictionary).is_empty())

func run() -> void:
	setup()
	await physics_frame
	await physics_frame
	check("All six permanent station arrivals exist", baseline_arrivals.size() == 6, baseline_arrivals.size())
	check("Production permanent collision and seats exist", baseline_colliders >= 491 and baseline_seats > 0, {"colliders":baseline_colliders,"seats":baseline_seats})
	for id: String in baseline_arrivals:
		await drain()
		place_at(id)
		# A is the previous lowest-profile behavior: full nearby detail loaded,
		# with the same cheap materials, viewport and pixel scale as B.
		streamer.call("set_constrained_runtime", false)
		streamer.call("pin_position", focus)
		await advance(180)
		check(id + " original detail readiness", bool(streamer.call("is_position_ready", focus)), streamer.call("metrics"))
		var retained_chunks: int = int(streamer.call("metrics").loaded_chunks)
		streamer.call("set_constrained_runtime", true)
		streamer.call("set_constrained_runtime", false)
		await advance(1)
		check(id + " immediate switch-back safely reuses unfreed detail", bool(streamer.call("is_position_ready", focus)) and int(streamer.call("metrics").loaded_chunks) == retained_chunks and int(streamer.call("metrics").active_regions) > 0)
		await capture_sample(id + "-detail")
		streamer.call("set_constrained_runtime", true)
		check(id + " constrained readiness is immediate", bool(streamer.call("is_position_ready", focus)))
		await drain()
		streamer.call("pin_position", focus)
		await advance(6)
		check(id + " constrained roaming has no loaded/pending detail", int(streamer.call("metrics").loaded_chunks) == 0 and int(streamer.call("metrics").pending_regions) == 0 and streamer.get("_pending_scene") == null)
		check(id + " releases detail nodes back to the permanent baseline", world.find_children("*", "", true, false).size() == baseline_nodes)
		await capture_sample(id + "-baked")
	# Cancel a resource between load and instantiate, the worst point to change.
	streamer.call("set_constrained_runtime", false)
	streamer.call("pin_position", focus)
	await advance(1)
	check("Fixture queues an in-flight detail resource", streamer.get("_pending_scene") != null)
	streamer.call("set_constrained_runtime", true)
	await advance(1)
	check("Budget change cancels in-flight load before instantiation", streamer.get("_pending_scene") == null and int(streamer.call("metrics").loaded_chunks) == 0)
	streamer.call("set_constrained_runtime", false)
	streamer.call("pin_position", focus)
	await advance(180)
	check("Detail is present before pressure-triggered indoor suspension", int(streamer.call("metrics").loaded_chunks) > 0)
	# Runtime pressure can constrain the standard preset too, independently of
	# its original low-quality flag. It must still release while detached.
	streamer.call("set_low_quality", false)
	streamer.call("set_constrained_runtime", true)
	# Indoor transitions retain a detached outdoor instance. No absolute path
	# lookups, waits or detail requests may survive that suspension.
	streamer.call("set_interior_active", true)
	current_scene = null
	root.remove_child(world)
	for _step: int in range(95):
		streamer.call("step_suspended_release")
		await process_frame
	check("Detached constrained world has completed release", bool(streamer.call("is_interior_release_complete")))
	root.add_child(world)
	current_scene = world
	streamer.call("set_interior_active", false)
	streamer.call("pin_position", focus)
	await advance(2)
	check("Returning from interior remains ready without detail loading", bool(streamer.call("is_position_ready", focus)) and int(streamer.call("metrics").loaded_chunks) == 0)
	check("Constrained readiness ignores failures in optional detail packs", str(streamer.call("position_error", focus)).is_empty())
	var visible_bases: bool = true
	for region: Dictionary in (streamer.get("_regions") as Dictionary).values():
		if is_instance_valid(region.overview): visible_bases = visible_bases and (region.overview as Node3D).visible
	check("Every baked district stays visible while detail is disabled", visible_bases)
	check("All permanent collision bodies survive profile/room switches", world.find_children("*", "StaticBody3D", true, false).size() == baseline_colliders)
	for id: String in baseline_arrivals:
		check(id + " arrival transform is unchanged", (world.get_node("Stations/" + id + "/Arrival") as Marker3D).global_transform == baseline_arrivals[id])
	await physics_frame
	verify_ground()
	verify_material_lifetime()
	var report: Dictionary = {"checks":checks,"failures":failures,"samples":samples,
		"engine":Engine.get_version_info(),"rendered":rendered,"gpu":RenderingServer.get_video_adapter_name(),
		"method":"Same production bases, detail chunks, art, fixed camera and cheap materials. Isolated streamer; no HUD/avatar or user-input automation. Rendered numbers are desktop diagnostics, not iPhone FPS or heat measurements.",
		"viewport":[1280,800],"scaling_3d_scale":root.scaling_3d_scale,"msaa":"off"}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("CONSTRAINED_STREAMING_CHECKS checks=", checks.size(), " failures=", failures, " output=", output)
	world.free()
	quit(1 if failures > 0 else 0)
