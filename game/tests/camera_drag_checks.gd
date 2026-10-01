extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

var checks: Array[Dictionary] = []
var failures: int = 0
var vegetation_probe: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String,passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func run() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	world.set_process(false)
	var camera: Camera3D = world.get("camera") as Camera3D
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	player.set_physics_process(false)
	var globe: Node3D = world.get_node("Globe") as Node3D
	var original_globe: Transform3D = globe.global_transform
	var fov: float = camera.fov
	var center: Vector2 = root.get_visible_rect().size*.5
	for axis: String in ["orbit_yaw","orbit_pitch"]:
		var stable: bool = true
		for step: int in range(73):
			world.set(axis,float(step)*TAU/36.0)
			world.call("update_camera",.016)
			stable = stable and absf(camera.global_position.length()-float(world.get("orbit_distance")))<.0001
			stable = stable and camera.unproject_position(Vector3.ZERO).distance_to(center)<.001
			stable = stable and camera.global_basis.is_finite() and is_equal_approx(camera.fov,fov)
			stable = stable and globe.global_transform.is_equal_approx(original_globe)
		check("Two complete turns keep center radius FOV and globe fixed: "+axis,stable)
	for button: MouseButton in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT]:
		world.call("begin_view_drag",button)
		check("Cursor remains visible while holding "+str(button),Input.mouse_mode==Input.MOUSE_MODE_VISIBLE)
		var yaw: float = world.get("orbit_yaw")
		var motion: InputEventMouseMotion = InputEventMouseMotion.new()
		motion.relative = Vector2(90,20)
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT if button==MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
		world.call("_input",motion)
		check("Drag follows displacement "+str(button),is_equal_approx(float(world.get("orbit_yaw")),yaw-.45))
		var distance_before: float = world.get("orbit_distance")
		var wheel: InputEventMouseButton = InputEventMouseButton.new()
		wheel.button_index=MOUSE_BUTTON_WHEEL_UP
		wheel.pressed=true
		world.call("_unhandled_input",wheel)
		check("Concurrent wheel input cannot zoom a held drag "+str(button),is_equal_approx(float(world.get("orbit_distance")),distance_before))
		motion.button_mask = 0
		world.call("_input",motion)
		check("Release outside ends drag without moving "+str(button),not bool(world.get("dragging_view")) and is_equal_approx(float(world.get("orbit_yaw")),yaw-.45))
		world.call("_input",motion)
		check("Unheld pointer does not rotate "+str(button),is_equal_approx(float(world.get("orbit_yaw")),yaw-.45))
	world.call("set_overview",false)
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	var original_position: Vector3 = player.global_position
	var near_stable: bool = true
	for step: int in range(73):
		player.rotate_heading(TAU/36.0)
		world.call("update_camera",.016)
		var aim: Vector3 = world.get("camera_aim") as Vector3
		near_stable = near_stable and absf(camera.global_position.distance_to(aim)-float(world.get("near_distance")))<.0001
		near_stable = near_stable and player.global_position.is_equal_approx(original_position) and is_equal_approx(camera.fov,fov)
	check("Roaming turns maintain selected distance FOV and player position",near_stable)
	# A real wall on the view ray must fade without reducing the orbit radius.
	var wall: MeshInstance3D = MeshInstance3D.new()
	wall.mesh = BoxMesh.new()
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color(.3,.4,.5,1)
	wall.material_override = material
	world.add_child(wall)
	wall.global_position = camera.global_position.lerp(world.get("camera_aim") as Vector3,.5)
	var body: StaticBody3D = StaticBody3D.new()
	body.collision_layer = 8
	body.collision_mask = 0
	wall.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	body.add_child(shape)
	await physics_frame
	await physics_frame
	var fade: RefCounted = world.get("camera_obstruction") as RefCounted
	fade.call("update",world,camera,world.get("camera_aim"),.2)
	var active: BaseMaterial3D = wall.get_active_material(0) as BaseMaterial3D
	check("Occluding wall fades while original material stays intact",active!=material and active.albedo_color.a<.2 and is_equal_approx(material.albedo_color.a,1))
	fade.call("reset")
	check("Leaving obstruction restores exact shared materials and visibility",wall.material_override==material and wall.get_surface_override_material(0)==null and wall.visible)
	# Use a real imported concave building, rather than treating a primitive
	# solid-box test as proof that a lens inside a GLB house remains readable.
	var streaming: Node = world.get("streaming") as Node
	streaming.call("pin_position", player.global_position)
	var load_frames: int = 0
	while not bool(streaming.call("is_position_ready", player.global_position)) and load_frames < 2400:
		streaming.call("update_context", false, player.global_position, camera.global_position, world.get("camera_aim") as Vector3, 1.0 / 60.0)
		load_frames += 1
		await process_frame
	# A ready signal precedes the next context tick that activates its chunks.
	streaming.call("update_context", false, player.global_position, camera.global_position, world.get("camera_aim") as Vector3, .2)
	check("Required district details load incrementally before the real shell check", bool(streaming.call("is_position_ready", player.global_position)))
	var shell: Array[Node]=[]
	var shell_key: String = ""
	var regions: Dictionary = streaming.get("_regions") as Dictionary
	for chunk: Node3D in regions.counseling.roots:
		for candidate: Node in chunk.get_children():
			if candidate.has_node("Foundation"):
				shell = candidate.find_children("*", "MeshInstance3D", true, false)
				shell_key = str(candidate.get_meta("camera_visual_group", ""))
				break
		if not shell.is_empty():
			break
	var has_concave: bool = false
	for collider: Node in world.find_children("*", "StaticBody3D", true, false):
		if str(collider.get_meta("camera_visual_group", "")) != shell_key or shell_key.is_empty():
			continue
		for collision: Node in collider.get_children():
			if collision is CollisionShape3D and (collision as CollisionShape3D).shape is ConcavePolygonShape3D:
				has_concave = true
	check("Streamed real building retains its matching permanent concave collision", not shell.is_empty() and has_concave)
	if not shell.is_empty():
		var shell_mesh: MeshInstance3D=shell[-1] as MeshInstance3D
		camera.global_position=shell_mesh.to_global(shell_mesh.get_aabb().get_center())
		fade.call("force_update")
		fade.call("update",world,camera,camera.global_position+Vector3.UP*8,.25)
		var shell_hidden: bool=true
		for node: MeshInstance3D in shell:
			shell_hidden=shell_hidden and not node.visible
		check("Lens inside a real concave building hides the complete obstructing shell",shell_hidden)
		fade.call("reset")
		var shell_restored: bool=true
		for node: MeshInstance3D in shell:
			shell_restored=shell_restored and node.visible
		check("Leaving a building restores its original complete silhouette",shell_restored)
	check_generated_vegetation(world, camera, fade, regions.counseling.roots as Array)
	var file: FileAccess = FileAccess.open("res://../deliverables/camera-drag-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"vegetation_probe":vegetation_probe},"\t"))
	file.close()
	print("CAMERA_DRAG_CHECKS ",checks.size()," failures=",failures)
	world.free()
	quit(1 if failures else 0)

func check_generated_vegetation(world: Node3D, camera: Camera3D, fade: RefCounted, chunks: Array) -> void:
	var members: Array[MultiMeshInstance3D] = []
	var key: String = ""
	for chunk: Node3D in chunks:
		for candidate: Node in chunk.find_children("*", "MultiMeshInstance3D", true, false):
			var node: MultiMeshInstance3D = candidate as MultiMeshInstance3D
			if not node.is_visible_in_tree() or str(node.get_meta("ecology_kind", "")) not in ["alder", "birch", "willow", "pine"]:
				continue
			if key.is_empty():
				key = str(node.get_meta("ecology_batch_key", ""))
			if str(node.get_meta("ecology_batch_key", "")) == key:
				members.append(node)
	check("Real generated tree keeps paired bark and canopy in an active streamed chunk", members.size() >= 2 and not key.is_empty())
	if members.is_empty():
		return
	var originals: Array[Dictionary] = []
	var canopy_bounds: AABB = AABB()
	var largest_volume: float = -1.0
	for node: MultiMeshInstance3D in members:
		var placements: Array = node.get_meta("placements", []) as Array
		check("Real tree metadata retains every original instance: " + str(node.name), placements.size() == node.multimesh.instance_count and not placements.is_empty())
		if placements.is_empty():
			return
		var bounds: AABB = node.global_transform * (placements[0] as Transform3D) * node.multimesh.mesh.get_aabb()
		if bounds.get_volume() > largest_volume:
			canopy_bounds = bounds
			largest_volume = bounds.get_volume()
		var transforms: Array[Transform3D] = []
		for index: int in range(node.multimesh.instance_count):
			transforms.append(node.multimesh.get_instance_transform(index))
		originals.append({"visible":node.multimesh.visible_instance_count,"transforms":transforms,"placements":placements.duplicate()})
	var vegetation: RefCounted = fade.get("vegetation") as RefCounted
	camera.global_position = canopy_bounds.get_center()
	var outward: Vector3 = camera.global_position.normalized()
	var tangent: Vector3 = outward.cross(Vector3.RIGHT).normalized()
	camera.look_at(camera.global_position + tangent * 8.0, outward)
	fade.call("force_update")
	fade.call("update", world, camera, camera.global_position + tangent * 8.0, .016)
	var candidates: int = int(vegetation.get("candidate_count"))
	var hidden: bool = true
	for node: MultiMeshInstance3D in members:
		hidden = hidden and node.multimesh.visible_instance_count >= 0 and node.multimesh.visible_instance_count < node.multimesh.instance_count
	check("Lens inside a real generated canopy finds nearby candidates and hides matching bark and leaves", candidates > 0 and hidden)
	var decisions: int = int(fade.get("decision_count"))
	camera.rotate(outward, TAU / 3.0)
	fade.call("update", world, camera, camera.global_position + tangent * 8.0, .016)
	check("Fast turn beside real generated vegetation immediately reevaluates before the interval", int(fade.get("decision_count")) == decisions + 1 and int(vegetation.get("candidate_count")) > 0)
	fade.call("set_active", false)
	var restored: bool = true
	var restored_transforms: bool = true
	var real_renderer: bool = DisplayServer.get_name() != "headless"
	for member_index: int in range(members.size()):
		var node: MultiMeshInstance3D = members[member_index]
		var original: Dictionary = originals[member_index]
		restored = restored and node.multimesh.visible_instance_count == int(original.visible) and (node.get_meta("placements") as Array) == (original.placements as Array)
		if real_renderer:
			for index: int in range(node.multimesh.instance_count):
				restored_transforms = restored_transforms and node.multimesh.get_instance_transform(index).is_equal_approx(original.transforms[index] as Transform3D)
	check("Leaving real tree obstruction restores original visibility and canonical placement metadata", restored)
	if real_renderer:
		check("Real renderer restores all original generated tree instance matrices", restored_transforms)
	vegetation_probe = {"batch":key,"members":members.size(),"instances":members[0].multimesh.instance_count,"candidates":candidates,"fast_turn_decisions":int(fade.get("decision_count")) - decisions,"renderer":DisplayServer.get_name(),"matrix_readback_measured":real_renderer}
	fade.call("reset")
