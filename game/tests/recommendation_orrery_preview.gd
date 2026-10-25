extends SceneTree
## Record the actual full-room instrument, at its normal gameplay speed.
const Room = preload("res://scripts/recommendation_room.gd")
const Fixture = preload("res://tests/recommendation_room_checks.gd")

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	Engine.max_fps = 30
	root.size = Vector2i(960,600)
	root.content_scale_size = Vector2i(960,600)
	root.set_meta("graphics_quality_profile","standard")
	var account: Node = Fixture.OfflineAccount.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var room: Node3D = Room.new()
	root.add_child(room)
	current_scene = room
	while not bool(room.get("ready_for_play")):
		await process_frame
	room.set_process(false)
	(room.get("hud") as CanvasLayer).hide()
	var player: Node3D = room.get("player")
	player.hide()
	player.set_physics_process(false)
	var camera: Camera3D = room.get("camera")
	camera.position = Vector3(1.9,1.85,-1.60)
	camera.look_at(Vector3(.65,1.22,-3.83),Vector3.UP)
	camera.fov = 39.0
	var orrery: Node = room.get("orrery")
	orrery.call("set_motion_enabled",true,false)
	orrery.set("focused",true)
	orrery.call("set_low_quality",false)
	orrery.call("set_presentation_active",true)
	var directory: String = ProjectSettings.globalize_path("res://../build/recommendation-motion-frames")
	DirAccess.make_dir_recursive_absolute(directory)
	for index: int in range(80):
		await create_timer(.10).timeout
		await RenderingServer.frame_post_draw
		var result: Error = root.get_texture().get_image().save_png(directory.path_join("frame-%03d.png"%index))
		if result != OK:
			quit(1)
			return
	print("RECOMMENDATION_MOTION_FRAMES 80")
	room.queue_free()
	account.queue_free()
	await process_frame
	quit(0)
