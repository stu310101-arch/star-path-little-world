extends SceneTree

const Obstruction = preload("res://scripts/camera_obstruction.gd")
const Vegetation = preload("res://scripts/camera_vegetation.gd")
const SpatialIndex = preload("res://scripts/camera_spatial_index.gd")

var checks: int = 0
var failures: int = 0
var world: Node3D
var camera: Camera3D
var aim: Vector3 = Vector3(0, 2, -10)

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func mesh(parent: Node3D, node_name: String, position_value: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = node_name
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(2, 2, 2)
	shape.material = StandardMaterial3D.new()
	node.mesh = shape
	node.position = position_value
	parent.add_child(node)
	return node

func make_batch(parent: Node3D, key: String, prefix: int = -1) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.use_colors = true
	node.multimesh.use_custom_data = true
	node.multimesh.mesh = BoxMesh.new()
	node.multimesh.instance_count = 3
	var placements: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(0, 2, -4)),
		Transform3D(Basis.IDENTITY, Vector3(5, 2, -4)),
		Transform3D(Basis.IDENTITY, Vector3(0, 2, -15))]
	for index: int in range(3):
		node.multimesh.set_instance_transform(index, placements[index])
		node.multimesh.set_instance_color(index, Color(float(index) / 2.0, .3, .7, 1))
		node.multimesh.set_instance_custom_data(index, Color(.2, float(index) / 2.0, .6, 1))
	node.multimesh.visible_instance_count = prefix
	node.set_meta("placements", placements)
	node.set_meta("ecology_kind", "alder")
	node.set_meta("ecology_batch_key", key)
	parent.add_child(node)
	return node

func check_grid() -> void:
	var grid: RefCounted = SpatialIndex.new()
	grid.call("insert", 1, AABB(Vector3(-1, -1, -31), Vector3(2, 2, 2)))
	grid.call("insert", 2, AABB(Vector3(40, -1, -31), Vector3(2, 2, 2)))
	grid.call("insert", 3, AABB(Vector3(-2, -2, -50), Vector3(4, 4, 40)))
	var hits: Array[int] = grid.call("query", Vector3.ZERO, Vector3(0, 0, -70), .35)
	check(hits.has(1) and hits.has(3) and not hits.has(2), "Candidates cover the complete camera-to-player corridor, not just the lens neighborhood")
	check(hits.count(3) == 1, "Large bounds occupying several grid cells produce one candidate")
	grid.call("insert", 1, AABB(Vector3(60, 0, 0), Vector3.ONE))
	hits = grid.call("query", Vector3.ZERO, Vector3(0, 0, -70), .35)
	check(not hits.has(1), "Reinsertion removes obsolete occupied cells")
	grid.call("remove", 3)
	check((grid.call("query", Vector3.ZERO, Vector3(0, 0, -70), .35) as Array).is_empty(), "Removing a region's bounds removes query candidates")
	grid.call("clear")
	check(int(grid.call("size")) == 0, "Clearing the grid releases every entry")

func check_buildings() -> void:
	var region: Node3D = Node3D.new()
	region.set_meta("camera_region", true)
	world.add_child(region)
	var building: Node3D = Node3D.new()
	building.name = "House"
	region.add_child(building)
	var foundation: MeshInstance3D = mesh(building, "Foundation", Vector3(0, 2, 0))
	var roof: MeshInstance3D = mesh(building, "Roof", Vector3(0, 4, 0))
	var original: Material = foundation.get_active_material(0)
	var controller: RefCounted = Obstruction.new()
	controller.call("register_region", region)
	region.visible = false
	controller.call("update", world, camera, aim, .016)
	check((controller.get("faded") as Dictionary).is_empty(), "A staged or inactive invisible chunk is not faded")
	region.visible = true
	controller.call("reset")
	controller.call("update", world, camera, aim, .016)
	var initial_decisions: int = int(controller.get("decision_count"))
	check(initial_decisions == 2, "The first close view makes one immediate visibility decision")
	check((controller.get("faded") as Dictionary).size() == 2, "A lens inside a house fades its complete building group")
	var record: Dictionary = (controller.get("faded") as Dictionary)[foundation.get_instance_id()]
	var alpha_before: float = float(record.opacity)
	var bounds_before: int = int(controller.get("bounds_rebuilds"))
	var material_copy: Material = foundation.get_surface_override_material(0)
	for frame: int in range(4):
		controller.call("update", world, camera, aim, .016)
	check(int(controller.get("decision_count")) == initial_decisions, "Expensive visibility checks do not run during the intervening rendered frames")
	check(float(record.opacity) < alpha_before, "Material fading continues every rendered frame between decision ticks")
	controller.call("update", world, camera, aim, .04)
	check(int(controller.get("decision_count")) == initial_decisions + 1, "The default visibility interval is 0.1 seconds")
	check(int(controller.get("bounds_rebuilds")) == bounds_before, "Unchanged static bounds are reused across decisions")
	check(foundation.get_surface_override_material(0) == material_copy, "Repeated obstruction does not duplicate materials")
	camera.rotation.y += .6
	controller.call("update", world, camera, aim, .001)
	check(int(controller.get("decision_count")) == initial_decisions + 2, "A rapid camera turn immediately recomputes obstruction")
	camera.look_at(aim)
	controller.call("force_update")
	controller.call("update", world, camera, aim, .001)
	check(int(controller.get("decision_count")) == initial_decisions + 3, "Teleport and view transitions can force a decision without waiting")
	controller.call("set_active", false)
	check(foundation.get_active_material(0) == original and foundation.visible and roof.visible, "Overview entry immediately restores original materials and visibility")
	var decisions: int = int(controller.get("decision_count"))
	controller.call("update", world, camera, aim, 1.0)
	check(int(controller.get("decision_count")) == decisions, "Overview performs no expensive decisions")
	controller.call("set_active", true)
	controller.call("update", world, camera, aim, .001)
	check(int(controller.get("decision_count")) == decisions + 1, "Returning to close view performs an immediate decision")
	region.position.x = 20.0
	controller.call("force_update")
	controller.call("update", world, camera, aim, .1)
	check(int(controller.get("bounds_rebuilds")) > bounds_before, "A registered ancestor transform change rebuilds affected cached bounds")
	check(int(controller.get("candidate_count")) == 0, "Moved building bounds leave the old corridor")
	region.position.x = 0.0
	controller.call("invalidate", building)
	controller.call("update", world, camera, aim, .1)
	check(int(controller.get("candidate_count")) == 1, "Explicit child edits invalidate the containing region")
	controller.call("unregister_region", region)
	var stats: Dictionary = controller.call("stats")
	check(int(stats.cached_groups) == 0 and int(stats.faded_meshes) == 0, "Unloading a region removes groups and active fades")
	check((controller.get("_material_cache") as Dictionary).is_empty(), "Unloading releases cached material copies")
	check(foundation.get_active_material(0) == original, "Unloading restores the authored material before releasing a still-live node")
	controller.call("reset")
	controller.call("update", world, camera, aim, .1)
	controller.call("unregister_region", region)
	check(int((controller.call("stats") as Dictionary).cached_groups) == 0, "After indoor detach/reset, automatic world discovery preserves each chunk's unload ownership")
	controller.call("reset")
	region.free()

func check_vegetation() -> void:
	var region: Node3D = Node3D.new()
	region.set_meta("camera_region", true)
	world.add_child(region)
	var node: MultiMeshInstance3D = make_batch(region, "main")
	var prefix: MultiMeshInstance3D = make_batch(region, "prefix", 1)
	var original_transforms: Array[Transform3D] = []
	var original_colors: Array[Color] = []
	var original_custom: Array[Color] = []
	for index: int in range(3):
		original_transforms.append(node.multimesh.get_instance_transform(index))
		original_colors.append(node.multimesh.get_instance_color(index))
		original_custom.append(node.multimesh.get_instance_custom_data(index))
	var controller: RefCounted = Vegetation.new()
	controller.call("register_region", region)
	controller.call("update", world, camera, aim)
	check(node.multimesh.visible_instance_count == 2, "Only obstructing tree instances leave the visible prefix")
	check(prefix.multimesh.visible_instance_count == 0, "Compaction does not reveal instances hidden by the original visible count")
	var writes: int = int(controller.get("transform_writes"))
	var rebuilds: int = int(controller.get("bounds_rebuilds"))
	for decision: int in range(20):
		controller.call("update", world, camera, aim)
	check(int(controller.get("transform_writes")) == writes, "An unchanged visible set causes zero redundant MultiMesh transform writes")
	check(int(controller.get("bounds_rebuilds")) == rebuilds, "Unchanged MultiMesh transforms reuse cached per-tree bounds")
	# On a real rendering server these assertions inspect the actual GPU-facing
	# MultiMesh storage. The headless dummy server has no readable instance data.
	var real_renderer: bool = DisplayServer.get_name() != "headless"
	if real_renderer:
		check(node.multimesh.get_instance_transform(0).is_equal_approx(original_transforms[1]), "Compaction preserves the original surviving instance matrix")
		check(node.multimesh.get_instance_color(0).is_equal_approx(original_colors[1]), "Compaction keeps per-instance colors paired with transforms")
		check(node.multimesh.get_instance_custom_data(0).is_equal_approx(original_custom[1]), "Compaction keeps custom shader data paired with transforms")
	controller.call("set_active", false)
	check(node.multimesh.visible_instance_count == -1 and prefix.multimesh.visible_instance_count == 1, "Overview restores each batch's original visible count")
	if real_renderer:
		for index: int in range(3):
			check(node.multimesh.get_instance_transform(index).is_equal_approx(original_transforms[index]), "Restoration keeps every authored transform")
			check(node.multimesh.get_instance_color(index).is_equal_approx(original_colors[index]), "Restoration keeps every authored color")
			check(node.multimesh.get_instance_custom_data(index).is_equal_approx(original_custom[index]), "Restoration keeps every authored custom value")
	else:
		print("CAMERA_PERFORMANCE_NOTE instance transform/color/custom readback requires a rendered run")
	writes = int(controller.get("transform_writes"))
	controller.call("set_active", false)
	controller.call("update", world, camera, aim)
	check(int(controller.get("transform_writes")) == writes, "Overview restoration runs only on the state change")
	controller.call("set_active", true)
	region.position.x = 20.0
	controller.call("update", world, camera, aim)
	check(int(controller.get("candidate_count")) == 0 and int(controller.get("bounds_rebuilds")) > rebuilds, "A moved region updates tree bounds and removes old candidates")
	region.position.x = 0.0
	controller.call("invalidate", node)
	controller.call("update", world, camera, aim)
	check(int(controller.get("candidate_count")) == 2, "Instance edit invalidation restores the correct candidate corridor")
	var placements: Array = (node.get_meta("placements") as Array).duplicate()
	placements[1] = Transform3D(Basis.IDENTITY, Vector3(7, 2, -4))
	node.set_meta("placements", placements)
	controller.call("invalidate", node)
	controller.call("update", world, camera, aim)
	if real_renderer:
		check(node.multimesh.get_instance_transform(0).is_equal_approx(placements[1] as Transform3D), "Changing canonical matrices refreshes compacted render slots even when the visible source set is unchanged")
	controller.call("unregister_region", region)
	check((controller.get("_trees") as Dictionary).is_empty() and (controller.get("_batches") as Dictionary).is_empty(), "Unregistering frees all tree and batch cache entries")
	for cycle: int in range(12):
		controller.call("register_region", region)
		controller.call("update", world, camera, aim)
		controller.call("unregister_region", region)
	check((controller.get("_trees") as Dictionary).is_empty() and (controller.get("_hidden_batches") as Dictionary).is_empty(), "Repeated region visits do not accumulate hidden sets or cached trees")
	controller.call("register_region", region)
	region.free()
	controller.call("update", world, camera, aim)
	check((controller.get("_batches") as Dictionary).is_empty(), "A freed region is also pruned safely if explicit unregister was missed")
	controller.call("reset")

func check_detached_collision() -> void:
	var region: Node3D = Node3D.new()
	region.set_meta("camera_region", true)
	world.add_child(region)
	var building: Node3D = Node3D.new()
	building.position = Vector3(0, 2, -4)
	building.set_meta("camera_visual_group", "fixture/house")
	region.add_child(building)
	mesh(building, "Foundation", Vector3.ZERO)
	mesh(building, "Roof", Vector3(0, 2, 0))
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	body.position = building.position
	body.set_meta("camera_visual_group", "fixture/house")
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	world.add_child(body)
	await physics_frame
	await physics_frame
	var controller: RefCounted = Obstruction.new()
	controller.call("update", world, camera, aim, .1)
	check((controller.get("faded") as Dictionary).size() == 2, "Permanent detached collision maps back to the complete streamed visual silhouette")
	region.visible = false
	controller.call("force_update")
	controller.call("update", world, camera, aim, .3)
	check((controller.get("faded") as Dictionary).is_empty(), "Permanent collisions do not fade inactive hidden detail")
	controller.call("unregister_region", region)
	check((controller.get("_group_keys") as Dictionary).is_empty(), "Unloading removes stable collision-to-visual mappings")
	controller.call("reset")
	region.free()
	body.free()
	var standalone_region: Node3D = Node3D.new()
	standalone_region.set_meta("camera_region", true)
	world.add_child(standalone_region)
	var railing: MeshInstance3D = mesh(standalone_region, "Railing", Vector3(0, 2, -4))
	railing.set_meta("camera_visual_group", "fixture/railing")
	var railing_body: StaticBody3D = StaticBody3D.new()
	railing_body.collision_layer = 8
	railing_body.collision_mask = 0
	railing_body.position = railing.position
	railing_body.set_meta("camera_visual_group", "fixture/railing")
	var railing_shape: CollisionShape3D = CollisionShape3D.new()
	railing_shape.shape = BoxShape3D.new()
	railing_body.add_child(railing_shape)
	world.add_child(railing_body)
	await physics_frame
	await physics_frame
	controller.call("update", world, camera, aim, .3)
	check(not railing.visible, "Detached single-mesh railing collision still hides its own visual")
	controller.call("update", world, camera, aim, .3)
	check(not railing.visible, "A faded standalone visual does not oscillate between hidden and restored")
	standalone_region.visible = false
	controller.call("update", world, camera, aim, .3)
	check((controller.get("faded") as Dictionary).is_empty(), "Inactive standalone visual groups are released from fade processing")
	controller.call("unregister_region", standalone_region)
	controller.call("reset")
	standalone_region.free()
	railing_body.free()

func run() -> void:
	world = Node3D.new()
	root.add_child(world)
	camera = Camera3D.new()
	world.add_child(camera)
	camera.position = Vector3(0, 2, 0)
	camera.look_at(aim)
	await process_frame
	check_grid()
	check_buildings()
	check_vegetation()
	await check_detached_collision()
	world.free()
	print("CAMERA_PERFORMANCE_CHECKS ", checks, " checks, ", failures, " failures")
	quit(1 if failures > 0 else 0)
