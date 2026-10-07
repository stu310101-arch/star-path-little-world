extends SceneTree

const Streamer = preload("res://scripts/district_streaming.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const OUTPUT: String = "res://../deliverables/performance/streaming-runtime-tests.json"
var checks: Array[Dictionary] = []
var failures: int = 0
var world: Node3D
var streaming: Node
var fixture_paths: Array[String] = []
var loaded_signals: int = 0
var removed_signals: int = 0
var baseline_nodes: int = 0
var a: Vector3 = Vector3(0, 48, 0)
var b: Vector3 = Vector3(100, 48, 0)
var ground_samples: Array[Vector3] = []
var before_ground: Array[Vector3] = []

func _initialize() -> void:
	call_deferred("run")

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":description,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(description + ": " + str(evidence))

func own_children(node: Node, scene_root: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_root
		own_children(child, scene_root)

func fixture_scene(path: String, actors: bool) -> void:
	var scene: Node3D = Node3D.new()
	scene.name = "FixtureDetail"
	if actors:
		var ocean: Node3D = Node3D.new()
		ocean.name = "Ocean"
		ocean.set_script(load("res://scripts/ocean_life.gd"))
		ocean.set_meta("radius", 48.0)
		var boat: Node3D = Node3D.new()
		boat.name = "Boat"
		boat.set_meta("kind", "boat")
		boat.set_meta("centre", Vector3.UP)
		ocean.add_child(boat)
		scene.add_child(ocean)
		var traffic: Node3D = Node3D.new()
		traffic.name = "Traffic"
		traffic.set_script(load("res://scripts/city_traffic.gd"))
		traffic.set_meta("radius", 48.0)
		var car: Node3D = Node3D.new()
		car.name = "Car"
		car.set_meta("district_up", Vector3.UP)
		car.set_meta("progress", 0.0)
		var wheel: Node3D = Node3D.new()
		wheel.name = "wheel-front"
		car.add_child(wheel)
		traffic.add_child(car)
		scene.add_child(traffic)
	own_children(scene, scene)
	var packed: PackedScene = PackedScene.new()
	check("Fixture packs", packed.pack(scene) == OK)
	check("Fixture saves", ResourceSaver.save(packed, path) == OK)
	fixture_paths.append(path)
	scene.free()

func setup_fixture() -> void:
	world = Node3D.new()
	world.name = "StreamingRegression"
	# Scheduler gets a deterministic test clock; child actor _process calls
	# remain paused while testing exact saved phase/progress values.
	world.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(world)
	current_scene = world
	var globe: Node3D = (load("res://generated/streaming/globe_base.scn") as PackedScene).instantiate() as Node3D
	var neighborhood: Node3D = (load("res://generated/streaming/neighborhood_base.scn") as PackedScene).instantiate() as Node3D
	globe.process_mode = Node.PROCESS_MODE_ALWAYS
	neighborhood.process_mode = Node.PROCESS_MODE_ALWAYS
	world.add_child(globe)
	world.add_child(neighborhood)
	for id: String in ["a", "b"]:
		var silhouette: Node3D = Node3D.new()
		silhouette.name = "FixtureOverview_" + id
		silhouette.set_meta("streaming_overview_id", id)
		neighborhood.add_child(silhouette)
	var prefix: String = "user://streaming-regression-" + str(Time.get_ticks_usec())
	fixture_scene(prefix + "-actors.scn", true)
	fixture_scene(prefix + "-empty.scn", false)
	var chunks: Array = [{"path":fixture_paths[0],"nodes":6},{"path":fixture_paths[1],"nodes":1}]
	var catalog: Dictionary = {"radius":48.0,"districts":[{"id":"a","center":[a.x,a.y,a.z],"chunks":chunks},{"id":"b","center":[b.x,b.y,b.z],"chunks":[chunks[1]]}]}
	var catalog_path: String = prefix + ".json"
	FileAccess.open(catalog_path, FileAccess.WRITE).store_string(JSON.stringify(catalog))
	fixture_paths.append(catalog_path)
	streaming = Streamer.new() as Node
	world.add_child(streaming)
	streaming.connect("chunk_added", func(_chunk: Node3D) -> void: loaded_signals += 1)
	streaming.connect("chunk_removing", func(_chunk: Node3D) -> void: removed_signals += 1)
	streaming.call("configure", world, catalog_path)
	streaming.call("set_low_quality", false)
	baseline_nodes = world.find_children("*", "", true, false).size()

func advance(overview: bool, point: Vector3, steps: int, delta: float = .16, camera_distance: float = 177.6) -> void:
	for _step: int in range(steps):
		streaming.call("update_context", overview, point, Vector3.UP * camera_distance, Vector3.ZERO, delta)
		await process_frame

func region(id: String) -> Dictionary:
	return (streaming.get("_regions") as Dictionary)[id] as Dictionary

func actor() -> Node3D:
	for detail: Node3D in region("a").roots:
		if detail.has_node("Ocean"):
			return detail
	return null

func scalar_state(value: Variant) -> bool:
	if value is Dictionary:
		for item: Variant in (value as Dictionary).values():
			if not scalar_state(item):
				return false
		return true
	return value == null or value is float or value is int or value is String or value is bool

func ground_positions() -> Array[Vector3]:
	var positions: Array[Vector3] = []
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for normal: Vector3 in ground_samples:
		var hit: Dictionary = Geo.ground_probe(space, normal, 48.0)
		positions.append(hit.position as Vector3 if not hit.is_empty() else Vector3.ZERO)
	return positions

func check_ground(after: bool) -> void:
	var positions: Array[Vector3] = ground_positions()
	var missing: int = 0
	var changed: int = 0
	for index: int in range(positions.size()):
		if positions[index] == Vector3.ZERO:
			missing += 1
		if after and not positions[index].is_equal_approx(before_ground[index]):
			changed += 1
	check("Continuous bridge/approach samples have permanent walkable support" + (" after unload" if after else " before load"), missing == 0, {"samples":positions.size(),"missing":missing})
	if after:
		check("Streaming does not change crossing ground intersections", changed == 0, changed)
	else:
		before_ground = positions

func run() -> void:
	setup_fixture()
	await physics_frame
	await physics_frame
	var directions: Array[Vector3] = Routes.directions()
	for edge: Vector2i in Routes.bridge_edges():
		for step: int in range(33):
			ground_samples.append(directions[edge.x].slerp(directions[edge.y], .35 + .30 * float(step) / 32.0))
	check_ground(false)
	await advance(true, a, 4)
	check("Initial panorama loads zero high-detail chunks", int(streaming.call("metrics").loaded_chunks) == 0)
	# First-entry preparation pins detail while the view is still panorama.
	# Cancelling it must work without relying on a false-to-true view change.
	streaming.call("pin_position", a)
	await advance(true, a, 1)
	check("Preparation in unchanged panorama queues one detail resource", streaming.get("_pending_scene") != null)
	var preparation_added: int = loaded_signals
	streaming.call("clear_pin")
	await advance(true, a, 1)
	check("Cancelling unchanged panorama preparation prevents pending construction", streaming.get("_pending_scene") == null and not bool(region("a").requested) and loaded_signals == preparation_added)
	streaming.call("pin_position", a)
	await advance(true, a, 8)
	check("Preparation can preload detail with actors still disabled", bool(region("a").ready) and (region("a").roots[0] as Node3D).process_mode == Node.PROCESS_MODE_DISABLED)
	streaming.call("clear_pin")
	streaming.call("clear_pin")
	await advance(true, a, 26, .20)
	check("Cancelled unchanged panorama releases detail after normal unload grace", int(streaming.call("metrics").loaded_chunks) == 0 and world.find_children("*", "", true, false).size() == baseline_nodes)
	streaming.call("pin_position", a)
	await advance(false, a, 8)
	check("Pinned nearby region becomes ready", bool(streaming.call("is_position_ready", a)))
	check("Complete nearby detail replaces its silhouette", bool(region("a").active) and not (region("a").overview as Node3D).visible)
	var first_detail: Node3D = actor()
	check("Real scripted actors are present", first_detail != null)
	if first_detail != null:
		first_detail.get_node("Ocean").set("elapsed", 37.25)
		first_detail.get_node("Traffic").set("elapsed", 19.5)
		first_detail.get_node("Traffic/Car").set_meta("progress", 12.75)
		(first_detail.get_node("Traffic/Car/wheel-front") as Node3D).rotation.x = 1.2
	# Expire the test's pin while still near A, then spend longer than the
	# unload delay in the hysteresis band before crossing its outer edge.
	await advance(false, a, 1, 21.0)
	await advance(false, a + Vector3(52, 0, 0), 1, 8.0)
	check("Hysteresis band retains the loaded region", bool(region("a").ready))
	await advance(false, a + Vector3(58, 0, 0), 1, .16)
	check("Unload grace starts at the outer boundary, not at load-distance exit", bool(region("a").ready))
	await advance(false, a + Vector3(58, 0, 0), 1, 3.0)
	check("Outer-boundary grace retains detail before four seconds", bool(region("a").ready))
	await advance(false, a + Vector3(58, 0, 0), 10, .20)
	check("Leaving the outer boundary unloads all A chunks after grace", (region("a").roots as Array).is_empty())
	streaming.call("pin_position", a)
	await advance(false, a, 8)
	var restored: Node3D = actor()
	check("Re-entry restores scripted detail", restored != null)
	if restored != null:
		check("Ocean scalar phase resumes", is_equal_approx(float(restored.get_node("Ocean").get("elapsed")), 37.25))
		check("Traffic scalar phase resumes", is_equal_approx(float(restored.get_node("Traffic").get("elapsed")), 19.5))
		check("Traffic progress resumes", is_equal_approx(float(restored.get_node("Traffic/Car").get_meta("progress")), 12.75))
		check("Wheel angle resumes", is_equal_approx((restored.get_node("Traffic/Car/wheel-front") as Node3D).rotation.x, 1.2))
	var loaded_before: int = loaded_signals
	await advance(true, a, 1)
	check("Panorama transition cancels a future pin immediately", float(streaming.get("_pin_until")) < float(streaming.get("_clock")))
	check("Panorama disables loaded actor processing immediately", (region("a").roots[0] as Node3D).process_mode == Node.PROCESS_MODE_DISABLED)
	await advance(true, a, 1, 3.0)
	check("Panorama grace retains existing detail without loading new chunks", not (region("a").roots as Array).is_empty() and loaded_signals == loaded_before)
	await advance(true, a, 15, .20)
	check("Panorama unloads all detail after grace", int(streaming.call("metrics").loaded_chunks) == 0)
	check("Node count returns to baseline", world.find_children("*", "", true, false).size() == baseline_nodes)
	var cycle_counts: Array[int] = []
	for _cycle: int in range(4):
		streaming.call("pin_position", a)
		await advance(false, a, 8)
		await advance(true, a, 26, .20)
		cycle_counts.append(world.find_children("*", "", true, false).size())
	check("Four repeated entries/unloads keep node count stable", cycle_counts == [baseline_nodes, baseline_nodes, baseline_nodes, baseline_nodes], cycle_counts)
	streaming.call("pin_position", a)
	await advance(false, a, 1)
	check("Load and instantiate are separate scheduler operations", streaming.get("_pending_scene") != null and int(streaming.call("metrics").loaded_chunks) == 0)
	var added_before_cancel: int = loaded_signals
	await advance(true, a, 1)
	check("Returning to panorama cancels an in-flight chunk before instantiation", streaming.get("_pending_scene") == null and loaded_signals == added_before_cancel)
	streaming.call("pin_position", a)
	await advance(false, a, 8)
	await advance(true, a, 1, .16, 115.2)
	check("Close overview can show detail but never runs animal/traffic scripts", bool(region("a").active) and (region("a").roots[0] as Node3D).visible and (region("a").roots[0] as Node3D).process_mode == Node.PROCESS_MODE_DISABLED)
	await advance(true, a, 26, .20)
	check("Every loaded chunk receives one removal signal", loaded_signals == removed_signals, {"added":loaded_signals,"removed":removed_signals})
	check("Saved actor state contains only scalars and no node/resource references", scalar_state(streaming.get("_actor_state")))
	streaming.call("set_low_quality", true)
	streaming.call("pin_position", a)
	await advance(false, a, 8)
	var low_detail: Node3D = actor()
	check("Low quality keeps nearby scripted actors", low_detail != null)
	if low_detail != null:
		check("Low quality throttles nonessential animation without changing physics ticks", is_equal_approx(float(low_detail.get_node("Ocean").get("quality_update_interval")), .1) and is_equal_approx(float(low_detail.get_node("Traffic").get("quality_update_interval")), .1))
	streaming.call("set_interior_active", true)
	check("Entering low-profile interior disables all outdoor detail immediately", not bool(region("a").requested) and not bool(region("a").active) and streaming.get("_pending_scene") == null)
	current_scene = null
	root.remove_child(world)
	for _step: int in range(8):
		streaming.call("step_suspended_release")
		await process_frame
	check("Indoor suspension releases outdoor instances with bounded per-frame work", bool(streaming.call("is_interior_release_complete")) and world.find_children("*", "", true, false).size() == baseline_nodes)
	root.add_child(world)
	current_scene = world
	streaming.call("set_interior_active", false)
	streaming.call("pin_position", a)
	await advance(false, a, 8)
	check("Returning from interior reloads outdoor detail normally", bool(streaming.call("is_position_ready", a)))
	await advance(true, a, 28, .20, 115.2)
	check("Low-profile close panorama stays on optimized overview with no detail instances", int(streaming.call("metrics").loaded_chunks) == 0 and (region("a").overview as Node3D).visible)
	check_understory_density()
	await physics_frame
	check_ground(true)
	var result: Dictionary = {"checks":checks,"count":checks.size(),"failures":failures,"fixture":"real permanent collision bases; tiny binary detail catalog; deterministic scheduler time","bridge_samples":ground_samples.size()}
	var report_path: String = OUTPUT
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			report_path = argument.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(report_path.get_base_dir()))
	FileAccess.open(report_path, FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	for path: String in fixture_paths:
		DirAccess.remove_absolute(path)
	print("STREAMING_RUNTIME_CHECKS ", JSON.stringify({"checks":checks.size(),"failures":failures,"bridge_samples":ground_samples.size()}))
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func check_understory_density() -> void:
	var plant: MultiMeshInstance3D = MultiMeshInstance3D.new()
	plant.multimesh = MultiMesh.new()
	plant.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	plant.multimesh.mesh = BoxMesh.new()
	plant.multimesh.instance_count = 100
	var placements: Array[Transform3D] = []
	for index: int in range(100):
		placements.append(Transform3D(Basis.IDENTITY, Vector3(index, 0, 0)))
		plant.multimesh.set_instance_transform(index, placements[index])
	plant.set_meta("placements", placements)
	plant.set_meta("aquatic_kind", "water_lily")
	var holder: Node3D = Node3D.new()
	holder.add_child(plant)
	streaming.call("_apply_chunk_quality", holder)
	check("Low-profile noncolliding understory keeps a deterministic 60% prefix", plant.multimesh.visible_instance_count == 60)
	check("Understory optimization retains original instance data", plant.get_meta("placements") == placements)
	streaming.call("set_low_quality", false)
	streaming.call("_apply_chunk_quality", holder)
	check("Standard quality restores authored instance visibility", plant.multimesh.visible_instance_count == -1)
	holder.free()
