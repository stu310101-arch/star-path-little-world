extends SceneTree

# This exercises the actual station/input/return path. Test positioning only
# chooses a starting point; collision checks retain every authored obstacle.
const OUTPUT: String = "res://../deliverables/training-room/"
var world: Node3D
var world_player: CharacterBody3D
var room: Node3D
var indoor: CharacterBody3D
var checks: Array[Dictionary] = []
var images: Array[Dictionary] = []
var failures: int = 0
var capture_images: bool = false
var saved_position: Vector3
var saved_heading: Vector3
var saved_world_id: int
var saved_music_id: int
var saved_music_state: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))

func run() -> void:
	if capture_images and DisplayServer.get_name() == "headless":
		push_error("Training-room capture requires the native renderer.")
		quit(1)
		return
	root.size = Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world_player = world.get("player") as CharacterBody3D
	await tick(8)
	check("The game starts in the existing world overview",bool(world.get("overview")))
	await press(KEY_TAB)
	check("Tab enters the existing 3D world",not bool(world.get("overview")))
	world.call("teleport_to","wordking")
	await tick(36)
	world.call("update_nearest")
	check("The real training district arrival offers WordKing entry",str(world.get("nearest_id")) == "wordking",world.get("nearest_id"))
	saved_position = world_player.global_position
	saved_heading = world_player.get("heading") as Vector3
	saved_world_id = world.get_instance_id()
	var shared_music: Node = world.get("music") as Node
	saved_music_id = shared_music.get_instance_id()
	saved_music_state = shared_music.call("get_state") as Dictionary
	await take("in-game-01-world-entrance","Normal world roaming camera at the training district")
	await press(KEY_E)
	check("A real E key starts the training district portal transition",bool(world.get("entering")))
	await wait_for_room(true)
	check("The station portal opens the playable training room",is_instance_valid(room))
	if not is_instance_valid(room):
		finish()
		return
	indoor = room.get("player") as CharacterBody3D
	await tick(24)
	check("Room finishes loading before accepting movement",bool(room.get("ready_for_play")))
	check("The indoor player has a supported landing",indoor.is_on_floor(),vec(indoor.position))
	check("Indoor arrival stays at human scale and inside the entrance",indoor.position.distance_to(Vector3(0,.09,6.2)) < .22,vec(indoor.position))
	check("Room camera owns the live viewport",root.get_camera_3d() == room.get("camera"))
	check("World player stops accepting movement while indoors",not bool(world_player.get("controls_enabled")))
	check("Indoor transition preserves the original music controller",(room.get("music") as Node).get_instance_id() == saved_music_id)
	await take("in-game-02-room-arrival","Normal third-person room arrival with the actual graduate player")
	check_assets()
	check_physics_queries()
	await check_movement_and_walls()
	await capture_room_views()
	await check_return_and_reentry()
	finish()

func find_room() -> Node3D:
	for node: Node in root.find_children("*","Node3D",true,false):
		var script: Script = node.get_script() as Script
		if script != null and script.resource_path == "res://scripts/training_room.gd":
			return node as Node3D
	return null

func wait_for_room(expected: bool) -> void:
	for frame: int in range(480):
		room = find_room()
		if expected and room != null and bool(room.get("ready_for_play")):
			return
		if not expected and room == null:
			return
		await physics_frame

func check_assets() -> void:
	var device_anchors: Array[Node] = room.find_children("ANCHOR_WordKing_Device*","Node3D",true,false)
	var sockets: Array[Node] = room.find_children("SOCKET_Genshin_*","Node3D",true,false)
	check("Exactly one authored training device is installed",device_anchors.size() == 1,device_anchors.size())
	check("Six future Genshin display positions are present",sockets.size() == 6,sockets.size())
	var empty_sockets: bool = true
	for socket: Node in sockets:
		empty_sockets = empty_sockets and socket.get_child_count() == 0
	check("Every character display position remains empty",empty_sockets)
	var meshes: Array[Node] = room.find_children("*","MeshInstance3D",true,false)
	var material_ids: Dictionary = {}
	var missing_materials: int = 0
	var transformed_bounds: AABB = AABB()
	var have_bounds: bool = false
	for node: Node in meshes:
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if indoor.is_ancestor_of(mesh_node) or mesh_node.mesh == null:
			continue
		var local_bounds: AABB = (room.global_transform.affine_inverse()*mesh_node.global_transform)*mesh_node.get_aabb()
		transformed_bounds = transformed_bounds.merge(local_bounds) if have_bounds else local_bounds
		have_bounds = true
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var material: Material = mesh_node.get_active_material(surface)
			if material == null:
				missing_materials += 1
			else:
				material_ids[material.get_instance_id()] = material.resource_name
	check("Room loads authored Blender mesh geometry",meshes.size() > 15,meshes.size())
	check("All imported room surfaces have a material",missing_materials == 0,missing_materials)
	check("Room geometry preserves the spacious 20 by 18 metre footprint",have_bounds and transformed_bounds.size.x > 19.5 and transformed_bounds.size.z > 17.5 and transformed_bounds.size.x < 23 and transformed_bounds.size.z < 23,{"position":vec(transformed_bounds.position),"size":vec(transformed_bounds.size)})
	check("Room height remains human-scale",have_bounds and transformed_bounds.size.y > 3 and transformed_bounds.size.y < 5,transformed_bounds.size.y)
	checks.append({"test":"Imported room material inventory","passed":true,"evidence":material_ids.values()})

func check_physics_queries() -> void:
	var clear_route: bool = true
	var supported_route: bool = true
	var blocked: Array[Dictionary] = []
	for index: int in range(22):
		var point: Vector3 = Vector3(0,.05,6.2).lerp(Vector3(0,.05,1.6),float(index)/21.0)
		var ground: Dictionary = ray(point+Vector3.UP*1.0,point-Vector3.UP*.3)
		if ground.is_empty():
			supported_route = false
		var hits: Array[Dictionary] = capsule_hits(point)
		if not hits.is_empty():
			clear_route = false
			blocked.append({"point":vec(point),"collider":str((hits[0].collider as Node).get_path())})
	check("The entrance-to-training route has continuous solid flooring",supported_route)
	check("A full player capsule fits along the entrance-to-training route",clear_route,blocked)
	for sign_value: float in [-1.0,1.0]:
		var hit: Dictionary = ray(Vector3(sign_value*8,.9,0),Vector3(sign_value*11,.9,0))
		check("Side wall " + str(sign_value) + " blocks crossing",not hit.is_empty(),hit_path(hit))
	var back_hit: Dictionary = ray(Vector3(0,.9,-7.0),Vector3(0,.9,-10))
	check("Rear wall blocks leaving the room",not back_hit.is_empty(),hit_path(back_hit))
	var sofa_hit: Dictionary = ray(Vector3(-6,.38,4.55),Vector3(-9.2,.38,4.55))
	check("The lounge sofa has solid collision",not sofa_hit.is_empty(),hit_path(sofa_hit))
	var cabinet_hit: Dictionary = ray(Vector3(6,1.15,-3.6),Vector3(9.65,1.15,-3.6))
	check("The display cabinet has solid collision",not cabinet_hit.is_empty(),hit_path(cabinet_hit))

func check_movement_and_walls() -> void:
	indoor.call("place_at",Vector3(3,.09,4.5),Vector3.FORWARD)
	await tick(15)
	var before: Vector3 = indoor.position
	key_event(KEY_W,true)
	await tick(50)
	key_event(KEY_W,false)
	await tick(5)
	check("Real W input walks the indoor graduate forward",before.distance_to(indoor.position) > 1 and indoor.position.z < before.z-.7,{"before":vec(before),"after":vec(indoor.position)})
	check("Walking remains grounded on the room floor",indoor.is_on_floor(),vec(indoor.position))
	var jump_count: int = int(indoor.get("jump_count"))
	await press(KEY_SPACE)
	await tick(125)
	check("The original graduate jump runs and lands on the indoor floor",int(indoor.get("jump_count")) == jump_count+1 and indoor.is_on_floor(),{"jump_count":indoor.get("jump_count"),"grounded":indoor.is_on_floor(),"height":indoor.get("max_jump_height")})
	await press(KEY_E)
	check("E away from the return portal does not exit the room",find_room() == room)
	indoor.call("place_at",Vector3(8.7,.09,0),Vector3.RIGHT)
	await tick(12)
	key_event(KEY_W,true)
	await tick(70)
	key_event(KEY_W,false)
	await tick(3)
	check("Actual player walking is stopped by the right wall",indoor.position.x > 8.7 and indoor.position.x < 9.8 and indoor.is_on_floor(),vec(indoor.position))

func capture_room_views() -> void:
	if not capture_images:
		return
	var views: Array[Dictionary] = [
		{"file":"in-game-03-lounge","point":Vector3(-3.5,.09,3.4),"face":Vector3(-1,0,.55).normalized(),"purpose":"Normal third-person lounge view; refined sofa and coffee table"},
		{"file":"in-game-04-display","point":Vector3(4.2,.09,-1.7),"face":Vector3(1,0,-.2).normalized(),"purpose":"Normal third-person view of the empty character display"}
	]
	for view: Dictionary in views:
		indoor.call("place_at",view.point,view.face)
		room.set("camera_yaw",atan2(-(view.face as Vector3).x,-(view.face as Vector3).z))
		room.set("camera_pitch",.28)
		room.set("camera_distance",3.4)
		room.call("update_camera",.016,true)
		await tick(15)
		await take(str(view.file),str(view.purpose))
	var room_camera: Camera3D = room.get("camera") as Camera3D
	room.set_process(false)
	room_camera.fov = 72.0
	room_camera.global_position = Vector3(8.7,3.05,8.45)
	room_camera.look_at(Vector3(-1.0,.7,-1.8),Vector3.UP)
	await take("in-game-07-room-wide","Wide interior survey from inside the real enclosure; no roof, wall or furniture hidden")
	room_camera.fov = 66.0
	room.set_process(true)

func check_return_and_reentry() -> void:
	indoor.call("place_at",Vector3(0,.09,6.2),Vector3.BACK)
	room.set("camera_yaw",PI)
	room.set("camera_pitch",.25)
	room.set("camera_distance",3.4)
	room.call("update_camera",.016,true)
	await tick(10)
	key_event(KEY_W,true)
	await tick(22)
	key_event(KEY_W,false)
	await tick(4)
	check("Walking back reaches the actual return portal trigger",bool(room.call("_can_return")),vec(indoor.position))
	await take("in-game-05-return-portal","Player walks to the physical portal before pressing E")
	await press(KEY_E)
	await wait_for_room(false)
	await tick(24)
	check("E at the room portal closes the room and returns to the world",find_room() == null and not bool(world.get("paused")))
	check("Returning resumes the exact same world instance",world.get_instance_id() == saved_world_id and current_scene == world)
	check("Returning preserves the exact world entry location",world_player.global_position.distance_to(saved_position) < .08,{"saved":vec(saved_position),"returned":vec(world_player.global_position)})
	check("Returning preserves the world camera heading",(world_player.get("heading") as Vector3).distance_to(saved_heading) < .02)
	check("World collision and ordinary movement are restored",world_player.is_on_floor() and bool(world_player.get("controls_enabled")) and world_player.collision_mask == 9)
	check("World camera is current after returning",root.get_camera_3d() == world.get("camera"))
	var returned_music: Node = world.get("music") as Node
	var music_state: Dictionary = returned_music.call("get_state") as Dictionary
	check("Music instance and sound preferences survive the round trip",returned_music.get_instance_id() == saved_music_id and music_state.get("muted") == saved_music_state.get("muted") and music_state.get("volume") == saved_music_state.get("volume"),music_state)
	await take("in-game-06-world-return","Real E return restores the original world location")
	await press(KEY_E)
	await wait_for_room(true)
	check("The same station can be entered a second time",is_instance_valid(room))
	if room != null:
		indoor = room.get("player") as CharacterBody3D
		indoor.call("place_at",Vector3(0,.09,7.2),Vector3.BACK)
		await tick(10)
		await press(KEY_E)
		await wait_for_room(false)
		check("Repeated entry and return leaves no duplicate room",find_room() == null)

func capsule_hits(point: Vector3) -> Array[Dictionary]:
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.6
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 9
	query.exclude = [indoor.get_rid()]
	query.transform = room.global_transform*Transform3D(Basis.IDENTITY,point+Vector3.UP*.82)
	return indoor.get_world_3d().direct_space_state.intersect_shape(query,4)

func ray(from_point: Vector3,to_point: Vector3) -> Dictionary:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(room.to_global(from_point),room.to_global(to_point),9)
	query.exclude = [indoor.get_rid()]
	return indoor.get_world_3d().direct_space_state.intersect_ray(query)

func hit_path(hit: Dictionary) -> String:
	return str((hit.collider as Node).get_path()) if not hit.is_empty() else "MISSING"

func key_event(code: Key,down: bool) -> void:
	var event: InputEventKey = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = down
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func press(code: Key) -> void:
	key_event(code,true)
	await process_frame
	key_event(code,false)
	await process_frame

func tick(count: int) -> void:
	for frame: int in range(count):
		await physics_frame

func take(filename: String,purpose: String) -> void:
	if not capture_images:
		return
	for frame: int in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = root.get_texture().get_image()
	var error: Error = pixels.save_png(ProjectSettings.globalize_path(OUTPUT+filename+".png"))
	check("Rendered capture saved: "+filename,error == OK)
	images.append({"file":filename+".png","purpose":purpose,"width":pixels.get_width(),"height":pixels.get_height(),"camera":str(root.get_camera_3d().get_path())})
	print("TRAINING_CAPTURE "+filename)

func vec(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func finish() -> void:
	var result: Dictionary = {"passed":failures == 0,"failures":failures,"checks":checks,"images":images,"renderer":DisplayServer.get_name(),"notes":"Real station path, Input.parse_input_event E/W/Tab, authored collision retained. Test placement selects starting points; views are actual Godot viewport captures."}
	var filename: String = "capture-report.json" if capture_images else "checks.json"
	var file: FileAccess = FileAccess.open(OUTPUT+filename,FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print("TRAINING_ROOM_CHECKS checks=",checks.size()," failures=",failures," images=",images.size())
	quit(1 if failures > 0 else 0)
