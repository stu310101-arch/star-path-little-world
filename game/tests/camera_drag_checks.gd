extends SceneTree

var checks: Array[Dictionary] = []
var failures: int = 0

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
	var shell: Array[Node]=[]
	for candidate: Node in world.get_node("Neighborhood/counseling").get_children():
		if candidate.has_node("Foundation"):
			shell=candidate.find_children("*","MeshInstance3D",true,false)
			break
	var shell_mesh: MeshInstance3D=shell[-1] as MeshInstance3D
	camera.global_position=shell_mesh.to_global(shell_mesh.get_aabb().get_center())
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
	var file: FileAccess = FileAccess.open("res://../deliverables/camera-drag-checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures},"\t"))
	print("CAMERA_DRAG_CHECKS ",checks.size()," failures=",failures)
	quit(1 if failures else 0)
