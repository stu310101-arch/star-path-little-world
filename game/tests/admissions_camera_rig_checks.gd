extends SceneTree

const Rig = preload("res://scripts/admissions_camera_rig.gd")
const Bridge = preload("res://scripts/account_room_bridge.gd")
const Fixtures = preload("res://tests/account_contract_checks.gd")
var failures: int = 0
var checks: int = 0

class Actor:
	extends CharacterBody3D
	var heading: Vector3 = Vector3.FORWARD
	var controls_enabled: bool = true
	var direction: Vector3 = Vector3.ZERO
	func _physics_process(delta: float) -> void:
		velocity = direction * 3.8 if controls_enabled else Vector3.ZERO
		velocity.y = -.8 if is_on_floor() else velocity.y - 20 * delta
		move_and_slide()

class Room:
	extends Node3D
	var camera: Camera3D
	var player: CharacterBody3D
	var rig: Node
	var focus: Dictionary = {"focus_camera":Vector3(0,1.8,-2.4),"focus_target":Vector3(0,1.7,-5.4),"fov":48.0}
	func begin_account_focus(_view: String) -> bool:
		return await rig.focus_to(focus)
	func end_account_focus() -> void:
		rig.reset_follow()

func _initialize() -> void:
	run.call_deferred()

func check(description: String, passed: bool, evidence: Variant = null) -> void:
	checks += 1
	print("CAMERA_RIG_CHECK ", description, " passed=", passed, " evidence=", evidence)
	if not passed:
		failures += 1

func box(room: Node3D, at: Vector3, size: Vector3, layer: int) -> void:
	var body := StaticBody3D.new()
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	room.add_child(body)

func run() -> void:
	var account := Fixtures.FakeAccount.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var room := Room.new()
	root.add_child(room)
	box(room,Vector3(0,-.1,0),Vector3(18,.2,16),1)
	box(room,Vector3(3.5,2,0),Vector3(.15,4,14),1)
	box(room,Vector3(0,3.55,3),Vector3(.8,.6,.8),256)
	var actor := Actor.new()
	actor.collision_layer = 4
	actor.collision_mask = 9
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.7
	capsule.radius = .3
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position.y = .85
	actor.add_child(collider)
	room.add_child(actor)
	actor.position = Vector3(0,.02,5.8)
	room.player = actor
	room.camera = Camera3D.new()
	room.add_child(room.camera)
	room.rig = Rig.new()
	room.add_child(room.rig)
	room.rig.configure(room,room.camera,actor,AABB(Vector3(-8,.25,-7),Vector3(16,3.8,15)))
	var probe := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = .175
	probe.shape = sphere
	probe.collision_mask = 257
	probe.exclude = [actor.get_rid()]
	var penetrations: int = 0
	var shortened: int = 0
	actor.direction = Vector3.FORWARD
	var start: Vector3 = actor.position
	for tick: int in range(150):
		await physics_frame
		var aim: Vector3 = actor.position + Vector3.UP * 1.15
		var desired: Vector3 = aim + Vector3(0,2.4,4.1)
		room.rig.follow(aim,desired,1.0/60.0,tick==0)
		probe.transform = Transform3D(Basis.IDENTITY,room.camera.position)
		if not room.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty():
			penetrations += 1
		if room.camera.position.distance_to(aim) < desired.distance_to(aim)-.3:
			shortened += 1
	actor.direction = Vector3.ZERO
	check("Continuous physics walk passes under pendant",start.z-actor.position.z>8.5,{"start":start,"end":actor.position})
	check("Volume sweep detects hanging camera-only blocker",shortened>8,shortened)
	check("No lens overlap while walking under blocker",penetrations==0,penetrations)
	check("Camera-only layer stays outside player mask",(actor.collision_mask & 256)==0)
	var aim: Vector3 = actor.position+Vector3.UP*1.15
	room.rig.follow(aim,aim+Vector3(6,1,0),1.0/60.0,true)
	probe.transform.origin = room.camera.position
	check("Side orbit respects thin wall volume",room.camera.position.x<3.25 and room.get_world_3d().direct_space_state.intersect_shape(probe,1).is_empty(),room.camera.position)
	var hud := CanvasLayer.new()
	room.add_child(hud)
	var bridge := Bridge.new()
	room.add_child(bridge)
	bridge.configure(room,actor,hud)
	var camera_before: Transform3D = room.camera.global_transform
	var fov_before: float = room.camera.fov
	var player_before: Transform3D = actor.global_transform
	check("Focus begins before browser host",bridge.open_view("general") and account.views.is_empty())
	await create_timer(.1).timeout
	check("Focus moves toward actual workstation",not room.camera.global_transform.is_equal_approx(camera_before) and account.views.is_empty())
	bridge.close_view()
	await create_timer(.4).timeout
	check("Cancelling focus never opens delayed browser",account.views.is_empty() and not bridge.is_open())
	check("Cancel restores camera and player exactly",room.camera.global_transform.is_equal_approx(camera_before) and room.camera.fov==fov_before and actor.global_transform.is_equal_approx(player_before))
	check("Second focus can reopen",bridge.open_view("general"))
	await create_timer(.5).timeout
	check("Browser opens after focus reaches workstation",account.views==["general"] and room.camera.position.distance_to(room.focus.focus_camera)<.01 and absf(room.camera.fov-48.0)<.01)
	bridge.close_view()
	check("Close restores pre-focus view exactly",room.camera.global_transform.is_equal_approx(camera_before) and room.camera.fov==fov_before and hud.visible)
	room.queue_free()
	account.queue_free()
	await process_frame
	print("CAMERA_RIG_CHECKS checks=",checks," failures=",failures)
	quit(1 if failures else 0)
