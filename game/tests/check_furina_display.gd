extends "res://tests/check_training_room.gd"

func run() -> void:
	capture_images = DisplayServer.get_name() != "headless"
	root.size = Vector2i(1280, 800)
	room = load("res://scenes/training_room.tscn").instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	check("Room becomes playable", await StartupFixture.wait_room(room, self))
	indoor = room.get("player") as CharacterBody3D
	var display: Node3D = room.get("character_display") as Node3D
	var deadline: int = Time.get_ticks_msec() + 120000
	while Time.get_ticks_msec() < deadline and (str(display.get("state")) == "waiting" or str(display.get("state")) == "instantiating" or str(room.get("detail_state")) in ["waiting", "preparing"]):
		await process_frame
	check("Furina finishes loading", str(display.get("state")) == "ready", display.get("error"))
	check("Exhibit belongs to the middle lower cabinet socket", str(display.get_parent().name) == "SOCKET_Genshin_181")
	var figure: Node3D = display.get("figure") as Node3D
	check("Character and sword are real mesh geometry", figure != null and figure.find_child("SM_Furina_Display", true, false) != null and figure.find_child("SM_Splendor", true, false) != null)
	if figure == null:
		quit(1)
		return
	var bounds: AABB
	var first: bool = true
	var textured: bool = true
	for node: Node in figure.find_children("*", "MeshInstance3D", true, false):
		var mesh: MeshInstance3D = node as MeshInstance3D
		var local_box: AABB = (figure.global_transform.affine_inverse() * mesh.global_transform) * mesh.get_aabb()
		bounds = local_box if first else bounds.merge(local_box)
		first = false
		for surface: int in range(mesh.mesh.get_surface_count()):
			var material: StandardMaterial3D = mesh.get_active_material(surface) as StandardMaterial3D
			textured = textured and material != null and material.albedo_texture != null
	check("All five surfaces retain their packed textures", textured)
	check("Feet rest on pad and full figure fits below the next shelf", absf(bounds.position.y) < .001 and absf(bounds.size.y - 1.12) < .005, str(bounds))
	check("Weapon and clothing fit within cabinet depth and bay width", bounds.size.z < .70 and bounds.size.x < 1.5, str(bounds.size))
	check("Playable avatar remains the existing graduate", str(indoor.get("_walk_model_path")).contains("graduate.glb"))
	check_assets()
	var props: Node3D = room.get("furniture_actions") as Node3D
	var before: Transform3D = figure.global_transform
	props.call("_activate", "cabinet_01")
	await create_timer(.9).timeout
	check("Cabinet opening is disabled", not bool(props.get("cabinet_open")) and (props.get("door_pivots") as Array).is_empty() and figure.global_transform.is_equal_approx(before))
	check("Exhibit has no nameplate or caption", display.get_node_or_null("Nameplate") == null and display.get_node_or_null("ExhibitCaption") == null)
	# Stop orbit updates for reproducible views of the actual production room.
	room.set_process(false)
	indoor.call("place_at", Vector3(5.8, .09, -1.7), Vector3.RIGHT)
	await tick(8)
	var cam: Camera3D = room.get("camera") as Camera3D
	var center: Vector3 = display.global_position + Vector3.UP * .61
	var front: Vector3 = display.global_basis.z.normalized()
	cam.fov = 43.0
	cam.global_position = center + front * 2.5 + Vector3.UP * .14
	cam.look_at(center)
	await take("furina-fixed-close", "Fixed closed cabinet with complete sword pose and no nameplate")
	props.call("_activate", "cabinet_01")
	await create_timer(.9).timeout
	check("Cabinet doors close without moving the exhibit", not bool(props.get("cabinet_open")) and figure.global_transform.is_equal_approx(before))
	await take("furina-closed-close", "Actual cabinet with closed glass; verify face and weapon through the glass")
	cam.fov = 58.0
	indoor.call("place_at", Vector3(2.0, .09, 2.0), Vector3.RIGHT)
	await tick(4)
	cam.global_position = Vector3(3.6, 2.25, -.1)
	cam.look_at(Vector3(7.9, 1.6, -3.6))
	await take("furina-cabinet", "All six cabinet bays, one occupied and five empty")
	var report: Dictionary = {"passed": failures == 0, "failures": failures, "checks": checks, "images": images}
	var file: FileAccess = FileAccess.open("res://../deliverables/furina/integration-report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("FURINA_DISPLAY checks=", checks.size(), " failures=", failures)
	quit(1 if failures else 0)
