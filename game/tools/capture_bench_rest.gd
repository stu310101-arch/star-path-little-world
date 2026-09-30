extends SceneTree

const OUTPUT: String = "res://../deliverables/bench-rest/"
const Plan = preload("res://scripts/sakura_routes.gd")

var world: Node3D
var player: PlanetPlayer
var camera: Camera3D
var hud: CanvasLayer
var benches: Node
var records: Array[Dictionary] = []
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, detail: String = "") -> void:
	checks.append({"name":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+detail)

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Bench captures require the native renderer; run without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1280,800)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	player = world.get("player") as PlanetPlayer
	camera = world.get("camera") as Camera3D
	hud = world.get("hud") as CanvasLayer
	benches = world.get("benches") as Node
	hud.visible = true
	hud.call("close_panel")
	world.call("set_overview",false)
	world.set("capture_focus",null)
	player.controls_enabled = false
	player.allow_test_input = false
	player.test_direction = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(4)
	check("All 34 authored benches registered",(benches.get("seats") as Array).size()==34)
	var grove: Node3D = world.get_node("Globe/SakuraGrove") as Node3D
	check("Sakura seating patch is current",int(grove.get_meta("layout_version",0))==Plan.LAYOUT_VERSION)
	var east: StaticBody3D = seat_under("EastViewBench")
	var west: StaticBody3D = seat_under("WestViewBench")
	var marina: StaticBody3D = seat_under("Marina")
	var civic: StaticBody3D = civic_seat()
	for item: Dictionary in [{"id":"01-east","seat":east,"detail":true},{"id":"02-west","seat":west,"detail":false},{"id":"03-marina","seat":marina,"detail":false},{"id":"04-civic","seat":civic,"detail":false}]:
		var seat: StaticBody3D = item.seat as StaticBody3D
		check(str(item.id)+" representative seat exists",seat != null)
		if seat != null:
			await sequence(str(item.id),seat,bool(item.detail))
	for item: Dictionary in [{"id":"05-east-entrance","seat":east},{"id":"06-west-entrance","seat":west}]:
		var seat: StaticBody3D = item.seat as StaticBody3D
		if seat == null:
			continue
		var staged: bool = await stage(seat)
		if staged:
			# This wider front view exposes the complete open mouth, the short
			# outer guards and the bench's direct connection to the garden loop.
			set_review_camera(seat,Vector3(3.5,3.0,-6.5),Vector3(0,.55,-.4))
			await frames(4)
			await capture(str(item.id),seat,"entrance review","idle")
	var report: Dictionary = {"passed":failures==0,"failures":failures,"checks":checks,"images":records,"renderer":RenderingServer.get_video_adapter_name(),"notes":"All poses come from the actual world interaction controller. Gameplay images use the normal roaming camera; review images use explicitly placed native cameras for access and clothing inspection."}
	FileAccess.open(OUTPUT+"capture-report.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BENCH_CAPTURE_COMPLETE "+JSON.stringify({"passed":failures==0,"images":records.size(),"failures":failures}))
	quit(0 if failures==0 else 1)

func frames(count: int) -> void:
	for frame: int in range(count):
		await physics_frame

func has_ancestor(node: Node, label: String) -> bool:
	var current: Node = node
	while current != null:
		if str(current.name)==label:
			return true
		current=current.get_parent()
	return false

func seat_under(label: String) -> StaticBody3D:
	for seat: StaticBody3D in benches.get("seats"):
		if has_ancestor(seat,label):
			return seat
	return null

func civic_seat() -> StaticBody3D:
	for seat: StaticBody3D in benches.get("seats"):
		if str(seat.name).begins_with("CivicSeatCollision") and not (benches.call("safe_stand",seat) as Dictionary).is_empty():
			return seat
	return null

func stage(seat: StaticBody3D) -> bool:
	if benches.get("state") != &"idle":
		benches.call("cancel")
	var safe: Dictionary = benches.call("safe_stand",seat) as Dictionary
	check("Safe front approach "+str(seat.get_path()),not safe.is_empty())
	if safe.is_empty():
		return false
	var point: Vector3 = safe.point
	player.teleport(point.normalized(),point.length()+.15)
	player.heading = (seat.global_position-point).slide(point.normalized()).normalized()
	player.visual.rotation.y = PI
	world.set("review_mode",false)
	world.set("near_pitch",.46)
	world.set("near_distance",7.0)
	# A teleport can complete floor contact before its landing animation ends.
	# Wait for the real interaction-ready state instead of assuming 42 frames.
	for frame: int in range(180):
		await physics_frame
		if player.is_on_floor() and not player.needs_settle and player.jump_state==&"grounded":
			break
	world.call("update_nearest")
	var detail: String = JSON.stringify({"on_floor":player.is_on_floor(),"needs_settle":player.needs_settle,"jump_state":str(player.jump_state),"local_player":vector_array(seat.to_local(player.global_position)),"can_approach":bool(benches.call("can_approach",seat)),"nearest_station":str(world.get("nearest_id"))})
	check("Approach is grounded "+str(seat.get_path()),player.is_on_floor() and not player.needs_settle and player.jump_state==&"grounded",detail)
	check("E selects this bench "+str(seat.get_path()),benches.get("nearest")==seat,detail)
	return player.is_on_floor() and benches.get("nearest")==seat

func sequence(label: String, seat: StaticBody3D, detail: bool) -> void:
	var staged: bool = await stage(seat)
	if not staged:
		return
	await capture(label+"-approach",seat,"gameplay","idle")
	world.call("interact_nearest")
	check(label+" E begins sitting",benches.get("state")==&"sitting" and player.is_resting)
	if detail:
		await frames(30)
		# Hold only the sampled transition while the renderer reads its frame.
		# This prevents a slow capture from silently advancing to the final pose.
		benches.set_physics_process(false)
		set_review_camera(seat,close_eye(seat),Vector3(0,.85,-.05))
		await capture(label+"-sitting-transition",seat,"front three-quarter review","sitting")
		benches.set_physics_process(true)
		await frames(60)
	else:
		await frames(90)
	check(label+" settles into rest",benches.get("state")==&"resting" and player.is_resting)
	world.set("review_mode",false)
	await frames(3)
	await capture(label+"-seated",seat,"gameplay","resting")
	set_review_camera(seat,close_eye(seat),Vector3(0,.8,-.04))
	await frames(3)
	await capture(label+"-seated-close",seat,"front three-quarter review","resting")
	if detail:
		set_review_camera(seat,Vector3(3.25,1.45,.5),Vector3(0,.72,-.08))
		await frames(3)
		await capture(label+"-seated-side",seat,"side and backrest review","resting")
	world.call("interact_nearest")
	check(label+" E begins standing",benches.get("state")==&"standing")
	await frames(78)
	check(label+" stands on clear ground",benches.get("state")==&"idle" and not player.is_resting and player.is_on_floor() and bool(benches.call("capsule_clear",player.global_position)))
	world.set("review_mode",false)
	await frames(3)
	await capture(label+"-standing",seat,"gameplay","idle")

func close_eye(seat: StaticBody3D) -> Vector3:
	# The two terrace lamps are mirrored. View each bench from its clear side
	# so the near lamp cannot cover the gown, hands or bench backrest.
	return Vector3(-2.6 if has_ancestor(seat,"WestViewBench") else 2.6,1.65,-3.5)

func set_review_camera(seat: StaticBody3D, eye_offset: Vector3, aim_offset: Vector3) -> void:
	world.set("review_mode",true)
	(world.get("camera_obstruction") as RefCounted).call("reset")
	var frame: Transform3D = seat.global_transform.orthonormalized()
	var aim: Vector3 = frame*aim_offset
	camera.global_transform = Transform3D(Basis.IDENTITY,frame*eye_offset).looking_at(aim,frame.basis.y)
	world.set("camera_aim",aim)

func capture(label: String, seat: StaticBody3D, view: String, expected_state: String) -> void:
	world.call("update_nearest")
	hud.call("update_status",false,str(world.get("nearest_label")),player.global_position.length())
	(hud.get("minimap") as Control).call("refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	var error: Error = image.save_jpg(ProjectSettings.globalize_path(OUTPUT+label+".jpg"),.96)
	var state: String = str(benches.get("state"))
	var valid: bool = error==OK and state==expected_state
	check("Capture "+label,valid,"state="+state+" expected="+expected_state+" image_error="+str(error))
	var rest_button: Button = hud.get("rest_button") as Button
	records.append({"file":label+".jpg","view":view,"seat":str(seat.get_path()),"state":state,"is_resting":player.is_resting,"player_position":vector_array(player.global_position),"camera_position":vector_array(camera.global_position),"camera_aim":vector_array(world.get("camera_aim") as Vector3),"prompt":str(benches.call("prompt")),"button_visible":rest_button.visible,"button_disabled":rest_button.disabled,"grounded":player.is_on_floor(),"size":[image.get_width(),image.get_height()],"passed":valid})
	print("BENCH_FRAME "+label+" state="+state+" valid="+str(valid))

func vector_array(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]
