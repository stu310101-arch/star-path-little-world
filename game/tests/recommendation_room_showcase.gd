extends SceneTree
## Actual native-renderer presentation captures; no compositor or painted additions.
const Room = preload("res://scripts/recommendation_room.gd")
const Checks = preload("res://tests/recommendation_room_checks.gd")
const Startup = preload("res://tests/startup_fixture.gd")
var room: Node3D
var camera: Camera3D
var output: String = "res://../deliverables/recommendation-room/showcase/"

func _initialize() -> void:
	run.call_deferred()

func capture(filename: String) -> void:
	for frame: int in range(8): await process_frame
	await RenderingServer.frame_post_draw
	var error: Error = root.get_texture().get_image().save_png(ProjectSettings.globalize_path(output+filename+".png"))
	print("RECOMMENDATION_SHOWCASE ",filename," ",error)
	assert(error==OK)

func run() -> void:
	assert(DisplayServer.get_name()!="headless")
	root.size=Vector2i(1600,1000)
	root.set_meta("graphics_quality_profile","standard")
	Engine.max_fps=60
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var account:=Checks.OfflineAccount.new()
	account.name="StarPathAccount"
	root.add_child(account)
	room=Room.new()
	root.add_child(room)
	current_scene=room
	assert(await Startup.wait_room(room,self))
	(room.get("player") as Node3D).hide()
	(room.get("hud") as CanvasLayer).hide()
	# A separate presentation camera leaves the real room and its animation running.
	camera=Camera3D.new()
	root.add_child(camera)
	camera.make_current()
	camera.fov=68
	camera.position=Vector3(0,3.12,4.55)
	camera.look_at(Vector3(0,.95,-1.4))
	await capture("roomwide")
	for label: Node in room.find_children("*","Label3D",true,false): (label as Label3D).hide()
	camera.fov=49
	camera.position=Vector3(1.30,2.0,-1.2)
	camera.look_at(Vector3(.05,1.0,-3.75))
	await capture("orrery-closeup")
	print("RECOMMENDATION_SHOWCASE_MOTION ",JSON.stringify(room.get("orrery").call("get_state")))
	await create_timer(4.0).timeout
	await capture("orrery-closeup-later")
	print("RECOMMENDATION_SHOWCASE_MOTION ",JSON.stringify(room.get("orrery").call("get_state")))
	camera.fov=55
	camera.position=Vector3(-1.65,2.15,1.85)
	camera.look_at(Vector3(-3.8,.85,-.65))
	await capture("data-clear-workspace")
	camera.fov=68
	camera.position=Vector3(0,2.75,-2.8)
	camera.look_at(Vector3(0,1.0,3.55))
	await capture("reading-corners")
	room.queue_free()
	await process_frame
	quit()
