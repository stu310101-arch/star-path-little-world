extends SceneTree

const Stub: Script = preload("res://tests/staged_room_pack_stub.gd")
const Fixture: Script = preload("res://tests/startup_fixture.gd")
var room: Node3D
var stub: Node

func _initialize() -> void:
	call_deferred("run")

func capture(label_text: String) -> void:
	for index: int in range(5):
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../deliverables/low-memory/room-" + label_text + ".png")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/low-memory"))
	var real_packs: Node = root.get_node_or_null("WebPacks")
	if real_packs != null:
		real_packs.name = "OriginalPacks"
	stub = Stub.new()
	stub.name = "WebPacks"
	root.add_child(stub)
	room = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	await Fixture.wait_room(room, self)
	var player: Node3D = room.get("player") as Node3D
	player.call("place_at", Vector3(-5.7, .09, 2.25), Vector3(0, 0, 1))
	room.set("camera_yaw", PI)
	room.call("update_camera", 0.0, true)
	await capture("light-lounge")
	stub.set("pack_complete", true)
	var deadline: int = Time.get_ticks_msec() + 30000
	while str(room.get("detail_state")) != "ready" and Time.get_ticks_msec() < deadline:
		await process_frame
	await capture("detail-lounge")
	player.call("place_at", Vector3(-5.5, .09, -1), Vector3.FORWARD)
	room.set("camera_yaw", -.3)
	room.call("update_camera", 0.0, true)
	await capture("detail-gaming")
	print("STAGED_ROOM_CAPTURE_READY")
	quit()
