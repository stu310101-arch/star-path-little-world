extends SceneTree
## Regression criteria: decorations must leave the direct user approaches open.
## This fixture drives the production CharacterBody; it never plans a detour.
const Room = preload("res://scripts/counseling_room.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const VisualFixture = preload("res://tests/interest_visual_review.gd")
const QA_VISUAL_LAYER: int = 1 << 28
var room: Node3D
var player: CharacterBody3D
var camera: Camera3D
var checks: Array[Dictionary] = []
var routes: Array[Dictionary] = []
var sightlines: Array[Dictionary] = []
var failures: int = 0
var output: String = "res://../deliverables/counseling-room/r8/direct-routes.json"
var captures: bool = false
var spawn_facing: Vector3 = Vector3.FORWARD
var initial_camera: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	print("COUNSELING_DIRECT_ROUTE ", label, " ", passed)
	if not passed:
		failures += 1

func tick(frames: int) -> void:
	for frame: int in range(frames):
		await physics_frame
		await process_frame

func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func numbers(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func distance_flat(a: Vector3, b: Vector3) -> float:
	return (a-b).slide(Vector3.UP).length()

func reset_actor(at: Vector3) -> void:
	player.set("allow_test_input",false)
	player.set("test_direction",Vector2.ZERO)
	player.call("place_at",at,spawn_facing)
	await tick(8)

func direct_walk(label: String, start: Vector3, target: Vector3, expected_view: String = "") -> void:
	await reset_actor(start)
	var origin: Vector3 = player.global_position
	var direction: Vector3 = (target-origin).slide(Vector3.UP).normalized()
	var expected_length: float = distance_flat(origin,target)
	var distance_travelled: float = 0.0
	var max_deviation: float = 0.0
	var previous: Vector3 = origin
	var contacts: Array[String] = []
	var max_frames: int = ceili((expected_length / float(player.get("walk_speed")) + 1.5) * 60.0)
	player.set("allow_test_input",true)
	# Keep one fixed direction for the whole leg: contact cannot trigger rerouting.
	player.set("test_direction",Vector2(direction.dot(player.global_basis.x),-direction.dot(player.get("heading") as Vector3)))
	for frame: int in range(max_frames):
		await tick(1)
		var position: Vector3 = player.global_position
		distance_travelled += distance_flat(previous,position)
		previous = position
		var delta: Vector3 = (position-origin).slide(Vector3.UP)
		max_deviation = maxf(max_deviation,(delta-direction*delta.dot(direction)).length())
		for index: int in range(player.get_slide_collision_count()):
			var collision: KinematicCollision3D = player.get_slide_collision(index)
			if absf(collision.get_normal().dot(Vector3.UP)) < .55:
				var collider: Object = collision.get_collider()
				var name: String = str((collider as Node).name) if collider is Node else str(collider)
				if name not in contacts:
					contacts.append(name)
		if not contacts.is_empty() or distance_flat(position,target) <= .12:
			break
	player.set("test_direction",Vector2.ZERO)
	player.set("allow_test_input",false)
	await tick(3)
	var error: float = distance_flat(player.global_position,target)
	room.call("refresh_nearest")
	var interaction: Dictionary = room.get("nearest") as Dictionary
	var nearest: String = str(interaction.get("station_view",interaction.get("view","")))
	var result: Dictionary = {"route":label,"start":numbers(origin),"target":numbers(target),"end":numbers(player.global_position),"end_error_m":error,"expected_length_m":expected_length,"travelled_m":distance_travelled,"maximum_cross_track_m":max_deviation,"horizontal_contacts":contacts,"nearest_view":nearest}
	routes.append(result)
	check(label+": direct walking reaches the approach without furniture contact",error < .20 and contacts.is_empty(),result)
	check(label+": no forced sideways detour",max_deviation < .12 and distance_travelled <= expected_length+.20,{"maximum_cross_track_m":max_deviation,"travelled_m":distance_travelled,"expected_length_m":expected_length})
	if not expected_view.is_empty():
		check(label+": correct interaction is reachable",nearest==expected_view,{"expected":expected_view,"actual":nearest})

func build_visual_query_geometry() -> int:
	# Separate QA-only collision layer mirrors opaque imported triangles. It does
	# not affect the player or production camera and catches non-collidable decor.
	var geometry := Node3D.new()
	geometry.name = "SightlineTestOnly"
	room.add_child(geometry)
	var count: int = 0
	for node: Node in (room.get("room_model") as Node3D).find_children("*","MeshInstance3D",true,false):
		var instance: MeshInstance3D = node as MeshInstance3D
		for surface: int in range(instance.mesh.get_surface_count()):
			var material: Material = instance.get_active_material(surface)
			if material is BaseMaterial3D:
				var base: BaseMaterial3D = material as BaseMaterial3D
				if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED or base.albedo_color.a < .95 or base.resource_name.to_lower().contains("glass"):
					continue
			var surface_mesh := ArrayMesh.new()
			surface_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,instance.mesh.surface_get_arrays(surface))
			var body := StaticBody3D.new()
			body.collision_layer = QA_VISUAL_LAYER
			body.collision_mask = 0
			body.set_meta("source_mesh",str(instance.name))
			body.set_meta("source_material",material.resource_name if material != null else "")
			geometry.add_child(body)
			body.global_transform = instance.global_transform
			var shape := CollisionShape3D.new()
			shape.shape = surface_mesh.create_trimesh_shape()
			body.add_child(shape)
			count += 1
	return count

func inspect_screen(label: String, station: Dictionary) -> void:
	var screen: Dictionary = station.get("screen",{})
	var has_metadata: bool = screen.get("center") is Array and screen.get("normal") is Array and screen.get("right") is Array and float(screen.get("width",0)) > .2 and float(screen.get("height",0)) > .2
	check(label+": screen has measured front-plane metadata",has_metadata,station.get("view"))
	if not has_metadata:
		return
	var center: Vector3 = vector(screen.center)
	var normal: Vector3 = vector(screen.normal).normalized()
	var right: Vector3 = vector(screen.right).normalized()
	var up: Vector3 = normal.cross(right).normalized()
	var anchor_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(center+normal*.05,center-normal*.05,QA_VISUAL_LAYER)
	anchor_query.hit_back_faces = true
	var anchor_hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(anchor_query)
	var anchor_material: String = str((anchor_hit.collider as Node).get_meta("source_material","")) if not anchor_hit.is_empty() else ""
	check(label+": measured anchor intersects the imported screen surface",anchor_material.to_lower().contains("screen"),anchor_material)
	var visible: int = 0
	var samples: Array[Dictionary] = []
	for offset: Vector2 in [Vector2.ZERO,Vector2(-.28,-.25),Vector2(.28,-.25),Vector2(-.28,.25),Vector2(.28,.25)]:
		var target: Vector3 = center + normal*.018 + right*offset.x*float(screen.width) + up*offset.y*float(screen.height)
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(camera.global_position,target,QA_VISUAL_LAYER)
		query.hit_back_faces = true
		var hit: Dictionary = room.get_world_3d().direct_space_state.intersect_ray(query)
		var blocked: bool = not hit.is_empty() and (hit.position as Vector3).distance_to(target) > .035
		if not blocked:
			visible += 1
		var sample: Dictionary = {"target":numbers(target),"clear":not blocked}
		if blocked:
			var body: Node = hit.collider as Node
			sample.merge({"hit":numbers(hit.position),"mesh":str(body.get_meta("source_mesh","")),"material":str(body.get_meta("source_material",""))})
		samples.append(sample)
	var screen_point: Vector2 = camera.unproject_position(center)
	var in_view: bool = not camera.is_position_behind(center) and Rect2(Vector2.ZERO,Vector2(root.size)).has_point(screen_point)
	var result: Dictionary = {"view":label,"station":station.view,"camera":numbers(camera.global_position),"screen_center":numbers(center),"in_view":in_view,"clear_samples":visible,"samples":samples}
	sightlines.append(result)
	check(label+": screen is framed and at least four of five samples are unobstructed",in_view and visible >= 4,result)

func normal_view(label: String, at: Vector3, stations_to_check: Array[Dictionary]) -> void:
	await reset_actor(at)
	room.set("camera_yaw",initial_camera.yaw)
	room.set("camera_pitch",initial_camera.pitch)
	room.set("camera_distance",initial_camera.distance)
	room.call("update_camera",0.0,true)
	await tick(10)
	for station: Dictionary in stations_to_check:
		inspect_screen(label+" / "+str(station.view),station)
	if captures:
		await RenderingServer.frame_post_draw
		var path: String = output.get_base_dir()+"/"+label+".png"
		check(label+": native normal-camera capture",root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))==OK,path)

func run() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	if arguments.has("--output"):
		output = arguments[arguments.find("--output")+1]
	captures = arguments.has("--capture") and DisplayServer.get_name() != "headless"
	Engine.max_fps = 120
	root.size = Vector2i(1440,900)
	root.set_meta("graphics_quality_profile","standard")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var account: Node = VisualFixture.Service.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	room = Room.new()
	root.add_child(room)
	current_scene = room
	check("Production room and character become ready",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	player = room.get("player") as CharacterBody3D
	camera = room.get("camera") as Camera3D
	await tick(12)
	var layout: Dictionary = room.get("layout")
	var spawn: Vector3 = vector(layout.spawn.position)
	spawn_facing = vector(layout.spawn.get("facing",[0,0,-1]))
	initial_camera = {"yaw":room.get("camera_yaw"),"pitch":room.get("camera_pitch"),"distance":room.get("camera_distance")}
	var high1: Dictionary = {}
	var high3: Dictionary = {}
	for station: Dictionary in layout.stations:
		if station.view == "interest_high1": high1 = station
		if station.view == "interest_high3": high3 = station
	var point1: Vector3 = vector(high1.approach)
	var point3: Vector3 = vector(high3.approach)
	check("Room layout supplies distinct entrance and grade device approaches",distance_flat(spawn,point1)>1.0 and distance_flat(spawn,point3)>1.0 and distance_flat(point1,point3)>1.0,{"entrance":numbers(spawn),"high1":numbers(point1),"high3":numbers(point3),"facing":numbers(spawn_facing)})
	await direct_walk("Entrance to high one",spawn,point1,"interest_high1")
	await direct_walk("Entrance to high three",spawn,point3,"interest_high3")
	await direct_walk("High one to high three",point1,point3,"interest_high3")
	await direct_walk("High three to high one",point3,point1,"interest_high1")
	await direct_walk("High one to entrance",point1,spawn)
	await direct_walk("High three to entrance",point3,spawn)
	var exit_point: Vector3 = vector(layout.exit.position)
	await direct_walk("Entrance to exit",spawn,exit_point,"exit")
	await direct_walk("Exit to entrance",exit_point,spawn)
	if not arguments.has("--routes-only"):
		check("Opaque imported geometry is used for visual sightline queries",build_visual_query_geometry()>0)
		await tick(3)
		await normal_view("normal-entrance",spawn,[high1,high3])
		await normal_view("normal-mid-aisle",spawn.lerp((point1+point3)*.5,.55),[high1,high3])
		await normal_view("normal-high1",point1,[high1])
		await normal_view("normal-high3",point3,[high3])
	var report: Dictionary = {"roomRevision":layout.get("revision",""),"passed":failures==0,"failures":failures,"checks":checks,"routes":routes,"sightlines":sightlines,"initialCamera":initial_camera,"method":"Actual production CharacterBody physics using one constant straight direction per leg, derived from the authored entrance, facing and station approaches; no intermediate waypoint, navigation solver or corrective teleport. Separate opaque-mesh QA collision geometry checks device sightlines under the actual initial gameplay camera settings without changing production collision masks.","limits":"Native desktop physics and camera geometry; browser routes and final rendered art are verified separately. Visual queries exclude transparent materials and the player avatar."}
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("COUNSELING_DIRECT_RESULT checks=",checks.size()," failures=",failures," output=",output)
	room.queue_free()
	account.queue_free()
	await process_frame
	quit(1 if failures else 0)
