extends "res://tests/check_counseling_room.gd"
## One short production-room load and visual pass for each resource profile.

func run() -> void:
	output_directory = "res://../deliverables/counseling-room/double-faces-20261025/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_directory))
	root.size = Vector2i(1440, 900)
	Engine.max_fps = 60
	var service: Node = VisualFixture.Service.new()
	service.name = "StarPathAccount"
	root.add_child(service)
	for profile: String in ["full", "low"]:
		root.get_node("ResourceProfile").set("profile", profile)
		room = Room.new()
		root.add_child(room)
		current_scene = room
		check(profile + " production room ready", await Startup.wait_room(room, self))
		if not bool(room.get("ready_for_play")):
			quit(1)
			return
		await tick(15)
		player = room.get("player") as CharacterBody3D
		camera = room.get("camera") as Camera3D
		layout = room.get("layout") as Dictionary
		check(profile + " expected resource loaded", str(room.get("model_path")).contains("/low/") == (profile == "low"))
		check(profile + " player on floor", player.is_on_floor())
		check(profile + " collision and interaction anchors retained", layout.colliders.size() == 17 and layout.interactables.size() == 4 and layout.stations.size() == 3)
		var art: Node3D = room.get("room_model") as Node3D
		check(profile + " both movable chair meshes present", art.find_child("SM_Counseling_HighOneWoodChair", true, false) != null and art.find_child("SM_Counseling_HighThreeWoodChair", true, false) != null)
		room.set_process(false)
		var shots: Array[Dictionary] = [
			{"name":"overview", "position":Vector3(0, 2.95, 3.7), "target":Vector3(0, 1.05, -1.7)},
			{"name":"desktop", "position":Vector3(2.4, 2.1, -.8), "target":Vector3(3.4, .88, -2.8)},
			{"name":"wall", "position":Vector3(2.5, 2.05, 1.2), "target":Vector3(4.95, 1.55, .6)}]
		for shot: Dictionary in shots:
			camera.global_position = shot.position
			camera.look_at(shot.target)
			await tick(3)
			await RenderingServer.frame_post_draw
			check(profile + " capture " + str(shot.name), root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output_directory + profile + "-" + str(shot.name) + ".png")) == OK)
		room.queue_free()
		await tick(2)
	FileAccess.open(output_directory + "brief-checks.json", FileAccess.WRITE).store_string(JSON.stringify({"failures":failures,"checks":checks,"scope":"One full/low native room smoke and visual pass; no broad regression or rollback."}, "\t"))
	print("COUNSELING_FACES_BRIEF checks=", checks.size(), " failures=", failures)
	quit(1 if failures else 0)
