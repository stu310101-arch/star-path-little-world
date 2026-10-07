extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")

# Real E/keyboard events enter through the room router. Positioning chooses a
# supported, unobstructed starting point; no target action is invoked directly.
const OUTPUT: String = "res://../deliverables/training-room/"
var room: Node3D
var player: CharacterBody3D
var router: Node
var props: Node3D
var checks: Array[Dictionary] = []
var images: Array[String] = []
var failures: int = 0
var capture: bool = false

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func run() -> void:
	capture = OS.get_cmdline_user_args().has("--capture")
	if capture and DisplayServer.get_name() == "headless":
		push_error("Native renderer required for --capture")
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	room = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	check("Indoor preparation completes before interaction checks", await StartupFixture.wait_room(room, self))
	player = room.get("player") as CharacterBody3D
	router = room.get("interactions") as Node
	props = room.get("furniture_actions") as Node3D
	await tick(20)
	check("Room has a grounded actual graduate player", player.is_on_floor())
	check("Three imported computer screen assemblies are interactive", (props.get("screens") as Dictionary).size() == 3, (props.get("screens") as Dictionary).keys())
	check("Six imported cabinet doors have live hinge pivots", (props.get("door_pivots") as Array).size() == 6)
	await check_projector()
	await check_computers()
	await check_cabinet()
	await check_inspection("starry_night", true)
	await check_lamp()
	for id: String in props.get("targets") as Dictionary:
		var target: Dictionary = (props.get("targets") as Dictionary)[id] as Dictionary
		if str(target.kind) in ["decoration", "tea"]:
			await check_inspection(id, false)
	await capture_lounge()
	var report: Dictionary = {"passed":failures == 0,"failures":failures,"checks":checks,"screenshots":images,"renderer":DisplayServer.get_name(),"interaction_path":"Input.parse_input_event -> TrainingRoom -> nearest target -> custom_action"}
	var file: FileAccess = FileAccess.open(OUTPUT + ("props-native-report.json" if capture else "props-checks.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("TRAINING_PROPS_CHECKS ", checks.size(), " failures=", failures)
	room.queue_free()
	await tick(3)
	quit(1 if failures else 0)

func target_for(id: String) -> Dictionary:
	for target: Dictionary in router.get("targets"):
		if str(target.get("id", "")) == id:
			return target
	return {}

func vec(raw: Variant) -> Vector3:
	if raw is Vector3:
		return raw as Vector3
	var values: Array = raw as Array
	return Vector3(float(values[0]), float(values[1]), float(values[2]))

func clear_standing(point: Vector3) -> bool:
	var shape: CapsuleShape3D = CapsuleShape3D.new()
	shape.radius = .28
	shape.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * .84)
	query.collision_mask = 1
	query.exclude = [player.get_rid()]
	if not room.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return false
	var floor_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(point + Vector3.UP * .18, point - Vector3.UP * .2, 1)
	return not room.get_world_3d().direct_space_state.intersect_ray(floor_query).is_empty()

func approach(id: String) -> bool:
	var target: Dictionary = target_for(id)
	check(id + " has a registered E target", not target.is_empty())
	if target.is_empty():
		return false
	var anchor: Vector3 = vec(target.get("approach", target.get("position")))
	anchor.y = float((room.get("layout") as Dictionary).get("floor_y", .0375)) + .055
	var offsets: Array[Vector3] = [Vector3.ZERO]
	var maximum: float = float(target.get("radius", 1.4))
	for distance: float in [.35, .70, 1.05, 1.35, 1.65]:
		if distance >= maximum:
			continue
		for index: int in range(16):
			var angle: float = index * TAU / 16.0
			offsets.append(Vector3(cos(angle), 0, sin(angle)) * distance)
	for offset: Vector3 in offsets:
		var point: Vector3 = anchor + offset
		if not clear_standing(point):
			continue
		var facing: Vector3 = (anchor-point).slide(Vector3.UP).normalized()
		if facing.length_squared() < .2:
			facing = Vector3.FORWARD
		player.call("place_at", point, facing)
		await tick(8)
		router.call("refresh_nearest")
		var nearest: Dictionary = router.get("nearest") as Dictionary
		if str(nearest.get("id", "")) != id or not player.is_on_floor():
			continue
		room.set("camera_yaw", atan2(-facing.x, -facing.z))
		room.set("camera_pitch", .22)
		room.set("camera_distance", 3.3)
		room.call("update_camera", .016, true)
		check(id + " can be reached from a clear grounded position", true, [player.position.x, player.position.y, player.position.z])
		check(id + " displays the real E interaction prompt", str(router.call("prompt")).begins_with("E  "), router.call("prompt"))
		return true
	check(id + " can be reached from a clear grounded position", false, {"anchor":str(anchor),"nearest":router.get("nearest")})
	return false

func check_projector() -> void:
	if not await approach("projector"):
		return
	var initial: bool = bool(props.get("projector_on"))
	await press(KEY_E)
	check("E toggles projector power", bool(props.get("projector_on")) != initial)
	var optics: Node3D = room.get_node_or_null("WordKingProjection") as Node3D
	check("Projector optics follow actual power state", optics != null and optics.visible == bool(props.get("projector_on")))
	var hologram_parts: Array[Node] = (room.get("room_model") as Node).find_children("SM_Device_Hologram*", "MeshInstance3D", true, false)
	var synchronized: bool = not hologram_parts.is_empty()
	for part: Node in hologram_parts:
		synchronized = synchronized and (part as Node3D).visible == bool(props.get("projector_on"))
	check("Imported holographic display follows projector power", synchronized, hologram_parts.size())
	await press(KEY_E)
	check("Second E restores projector power", bool(props.get("projector_on")) == initial)

func check_computers() -> void:
	var screens: Dictionary = props.get("screens") as Dictionary
	for id: String in screens:
		if not await approach(id):
			continue
		var monitor: Node3D = screens[id] as Node3D
		var initial: bool = monitor.visible
		var other_states: Dictionary = {}
		for other: String in screens:
			other_states[other] = (screens[other] as Node3D).visible
		await press(KEY_E)
		check(id + " E toggles its imported monitor", monitor.visible != initial)
		var independent: bool = true
		for other: String in screens:
			if other != id:
				independent = independent and (screens[other] as Node3D).visible == bool(other_states[other])
		check(id + " leaves the other computers unchanged", independent)
		await press(KEY_E)
		check(id + " second E restores the monitor", monitor.visible == initial)

func check_cabinet() -> void:
	var pivots: Array = props.get("door_pivots") as Array
	if pivots.size() != 6 or not await approach("cabinet_01"):
		return
	var closed: Array[Transform3D] = []
	for pivot: Node3D in pivots:
		closed.append((pivot.get_child(0) as Node3D).global_transform)
	await press(KEY_E)
	await tick(52)
	var moved: int = 0
	for index: int in range(pivots.size()):
		var pivot: Node3D = pivots[index] as Node3D
		if not (pivot.get_child(0) as Node3D).global_transform.is_equal_approx(closed[index]):
			moved += 1
	check("One E smoothly opens all six authored cabinet doors", moved == 6 and bool(props.get("cabinet_open")), moved)
	await take("props-cabinet-open")
	await press(KEY_E)
	await tick(52)
	var restored: bool = not bool(props.get("cabinet_open"))
	for index: int in range(pivots.size()):
		restored = restored and ((pivots[index] as Node3D).get_child(0) as Node3D).global_transform.is_equal_approx(closed[index])
	check("Second E closes every door at the original hinge alignment", restored)
	var sockets: Array[Node] = room.find_children("SOCKET_Genshin_*", "Node3D", true, false)
	var empty: bool = sockets.size() == 6
	for socket: Node in sockets:
		empty = empty and socket.get_child_count() == 0
	check("Cabinet keeps all six future character positions empty", empty)

func check_lamp() -> void:
	if not await approach("reading_lamp"):
		return
	var light: OmniLight3D = props.get("lamp_light") as OmniLight3D
	check("Reading lamp has an actual local light", light != null)
	var lamp_parts: Array = props.get("lamp_meshes") as Array
	check("Reading lamp action controls the imported authored lamp", not lamp_parts.is_empty())
	if light == null:
		return
	var initial: bool = light.visible
	await press(KEY_E)
	check("E switches the reading lamp illumination", light.visible != initial and light.visible == bool(props.get("lamp_on")))
	var emissive_surfaces: int = 0
	var emission_matches: bool = true
	for lamp: Node3D in lamp_parts:
		var meshes: Array[Node] = lamp.find_children("*", "MeshInstance3D", true, false)
		if lamp is MeshInstance3D:
			meshes.append(lamp)
		for node: Node in meshes:
			var instance: MeshInstance3D = node as MeshInstance3D
			for surface: int in range(instance.mesh.get_surface_count()):
				var base: StandardMaterial3D = instance.mesh.surface_get_material(surface) as StandardMaterial3D
				if base != null and base.emission_enabled:
					emissive_surfaces += 1
					var active: StandardMaterial3D = instance.get_active_material(surface) as StandardMaterial3D
					emission_matches = emission_matches and active != null and active.emission_enabled == light.visible
	check("Reading lamp visible glow switches with its illumination", emissive_surfaces > 0 and emission_matches, emissive_surfaces)
	await press(KEY_E)
	check("Second E restores reading illumination", light.visible == initial)

func check_inspection(id: String, painting: bool) -> void:
	if not await approach(id):
		return
	await press(KEY_E)
	check(id + " E opens inspection", str(router.get("state")) == "inspection")
	if str(router.get("state")) != "inspection":
		return
	check(id + " inspection locks player and camera drag", not bool(player.get("controls_enabled")) and bool(router.call("camera_blocked")))
	var pictures: Array[Node] = (router.get("content") as Node).find_children("*", "TextureRect", true, false)
	check(id + " inspection shows an actual image or 3D view", pictures.size() == 1)
	if pictures.size() == 1:
		var picture: TextureRect = pictures[0] as TextureRect
		if painting:
			var expected: Image = (load("res://assets/training_room/textures/starry_night.jpg") as Texture2D).get_image()
			var actual: Image = picture.texture.get_image() if picture.texture != null else null
			var image_error: float = 1.0
			if actual != null and expected != null:
				actual.resize(16, 16, Image.INTERPOLATE_LANCZOS)
				expected.resize(16, 16, Image.INTERPOLATE_LANCZOS)
				image_error = 0.0
				for y: int in range(16):
					for x: int in range(16):
						var a: Color = actual.get_pixel(x, y)
						var b: Color = expected.get_pixel(x, y)
						image_error += (absf(a.r-b.r) + absf(a.g-b.g) + absf(a.b-b.b)) / 768.0
			check("Painting viewer preserves Starry Night image content in light/detail resources", image_error < .035, image_error)
		else:
			var viewport: SubViewport = props.get("preview") as SubViewport
			check(id + " has a rendered object inspection viewport", viewport != null and picture.texture is ViewportTexture)
			if viewport != null:
				var turntable: Node3D = props.get("preview_turntable") as Node3D
				var old_rotation: float = turntable.rotation.y
				key_event(KEY_RIGHT, true)
				await tick(20)
				key_event(KEY_RIGHT, false)
				check(id + " arrow input rotates the inspected object", absf(turntable.rotation.y-old_rotation) > .08)
	var before: Vector3 = player.position
	key_event(KEY_W, true)
	await tick(12)
	key_event(KEY_W, false)
	check(id + " movement input cannot move the locked player", player.position.distance_to(before) < .01)
	await take("props-" + id + "-inspection")
	await press(KEY_ESCAPE)
	await tick(4)
	check(id + " Esc closes the viewer and restores play", str(router.get("state")) == "idle" and bool(player.get("controls_enabled")))
	check(id + " closes temporary rendering resources", props.get("preview") == null)

func capture_lounge() -> void:
	if not capture:
		return
	player.call("place_at", Vector3(-3, .1, 3.2), Vector3(-1, 0, .5).normalized())
	await tick(10)
	room.set("camera_yaw", 2.034)
	room.set("camera_pitch", .27)
	room.set("camera_distance", 4.2)
	room.call("update_camera", .016, true)
	await take("props-updated-lounge")

func key_event(code: Key, pressed: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func press(code: Key) -> void:
	key_event(code, true)
	await tick(2)
	key_event(code, false)
	await tick(3)

func tick(frames: int) -> void:
	for index: int in range(frames):
		await physics_frame
		await process_frame

func take(label: String) -> void:
	if not capture:
		return
	await tick(3)
	await RenderingServer.frame_post_draw
	var path: String = OUTPUT + label + ".png"
	check(label + " screenshot saved", root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK)
	images.append(ProjectSettings.globalize_path(path))
