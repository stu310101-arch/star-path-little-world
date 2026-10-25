extends SceneTree
## The real exploration scene, driven through its HUD and normal proximity path.
const Garden = preload("res://scripts/discussion_garden.gd")
const Device = preload("res://scripts/discussion_device.gd")
const Navigation = preload("res://scripts/discussion_navigation.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const OUTPUT := "res://../deliverables/discussion-revision/overhaul-integration.json"

class AccountFixture:
	extends Node
	signal forum_message(packet: Dictionary)
	signal state_changed(user: Dictionary)
	signal closed
	signal failed(message: String)
	var user: Dictionary = {"signedIn":true,"displayName":"探索測試","identity":"high_school","profileReady":true,"sessionGeneration":9}
	var requests: Array[Dictionary] = []
	var contexts: Array[Dictionary] = []
	var opened: bool = false
	var accepts: bool = true
	func request_forum_page(command: Dictionary) -> bool:
		requests.append(command.duplicate())
		return true
	func open_forum(context: Dictionary) -> bool:
		contexts.append(context.duplicate())
		opened = accepts
		return accepts
	func open_view(view: String) -> bool:
		contexts.append({"view":view})
		opened = accepts
		return accepts
	func close_view() -> void:
		opened = false
		closed.emit()

class LowQualityFixture:
	extends Node
	signal state_changed
	var low: bool = true
	func is_low_quality() -> bool:
		return low

var checks: Array[Dictionary] = []
var failures: int = 0
var return_count: int = 0
var fixture: AccountFixture
var room: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var supplied_requests: int = 0
var low_variant_checked: bool = false
var modal_checks_completed: bool = false
var route_checks_completed: bool = false
var focus_checks_completed: bool = false
var camera_checks_completed: bool = false
var camera_probe: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed})
	print("OVERHAUL_CHECK ",label," ",passed)
	if not passed:
		failures += 1

func tick(count: int = 3) -> void:
	for index: int in range(count):
		await process_frame

func packet(command: Dictionary, kind: String) -> Dictionary:
	return {"channel":"starpath-forum","version":1,"requestId":command.requestId,"sessionGeneration":9,"zone":command.zone,"type":kind}

func supply_empty_pages() -> void:
	while supplied_requests < fixture.requests.size():
		var command: Dictionary = fixture.requests[supplied_requests]
		supplied_requests += 1
		var begin := packet(command,"page-begin")
		begin.merge({"itemCount":8,"devicePage":0})
		fixture.forum_message.emit(begin)
		for slot: int in range(8):
			var item := packet(command,"page-empty")
			item.merge({"index":slot,"threadId":Device.thread_for(command.zone,0,slot)})
			fixture.forum_message.emit(item)
		var end := packet(command,"page-end")
		end.merge({"count":8,"hasNext":true,"hasPrevious":false})
		fixture.forum_message.emit(end)

func move_to(at: Vector3, facing: Vector3 = Vector3.FORWARD) -> void:
	player.call("place_at",at,facing)
	room.call("refresh_nearest")
	supply_empty_pages()
	room.call("refresh_nearest")

func escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	room.call("_unhandled_input",event)

func choose_destination(zone: String) -> void:
	if not (hud.get("guide_panel") as Control).visible:
		(hud.get("guide_button") as Button).pressed.emit()
	(hud.get("guide_rows")[zone] as Button).pressed.emit()

func run() -> void:
	fixture = AccountFixture.new()
	fixture.name = "StarPathAccount"
	root.add_child(fixture)
	var quality := LowQualityFixture.new()
	quality.low = not OS.get_cmdline_user_args().has("--standard-art")
	quality.name = "OverhaulLowQuality"
	root.add_child(quality)
	room = Garden.new()
	room.set("graphics_settings",quality)
	room.connect("request_return_to_world",func() -> void: return_count += 1)
	root.add_child(room)
	current_scene = room
	check("Actual garden becomes playable",await Startup.wait_room(room,self,90000))
	if not bool(room.get("ready_for_play")):
		write_report()
		quit(1)
		return
	player = room.get("player")
	hud = room.get("hud")
	# Stop incidental movement while dispatching exact user actions; rendering and
	# the same scene's proximity, route and modal code remain under test.
	room.set_process(false)
	player.set_physics_process(false)
	supply_empty_pages()
	var zones: Dictionary = room.get("zones")
	check("Exploration retains five areas and forty separate devices",zones.size()==5 and zones.values().all(func(zone: Dictionary) -> bool: return zone.devices.size()==8))
	var model_paths: Array = room.get("model_paths")
	# The low-art integration may be supplied after this fixture is first added.
	# --require-low-art turns the deployment requirement into a hard assertion.
	var loaded_low: bool = model_paths.any(func(path: String) -> bool: return path.get_file().contains("low"))
	low_variant_checked = loaded_low or OS.get_cmdline_user_args().has("--require-low-art")
	if low_variant_checked:
		var actual_resource: String = (room.get("models")[0] as PackedScene).resource_path
		check("Minimum preset loads reduced garden instead of both variants",loaded_low and actual_resource.get_file().contains("low") and actual_resource==model_paths[0] and not model_paths.has("res://assets/discussion_garden/garden.glb"))
	if quality.low:
		check("Minimum preset does not draw dynamic sun shadows",not (room.get_node("GardenSun") as DirectionalLight3D).shadow_enabled)
	move_to(Garden.vector((room.get("layout") as Dictionary).get("hub",[0,.06,0])))
	check("Actual central plaza does not claim a discussion district",(hud.get("location_title") as Label).text=="中心廣場" and (hud.get("guide_rows") as Dictionary).values().all(func(row: Button) -> bool: return not row.text.contains("所在地")))
	check_routes(zones)
	check("All twenty route scenarios complete without a runtime error",route_checks_completed)
	check_focus(zones)
	check("All forty device scenarios complete without a runtime error",focus_checks_completed)
	check_camera_clearance(zones)
	check("Near-column camera sweep completes without a runtime error",camera_checks_completed)
	check_modal_and_escape(zones)
	check("All modal scenarios complete without a runtime error",modal_checks_completed)
	write_report()
	room.queue_free()
	fixture.queue_free()
	quality.queue_free()
	await tick()
	print("OVERHAUL_RESULT checks=",checks.size()," failures=",failures," low_variant_checked=",low_variant_checked)
	quit(0 if failures==0 else 1)

func check_routes(zones: Dictionary) -> void:
	for source: String in zones:
		var source_point: Vector3 = Garden.vector(zones[source].center)+Vector3.UP*.06
		if source=="campus":
			source_point.z += 4.0 # Stand on the path beside the central fountain.
		move_to(source_point)
		var local_before: Transform3D = player.global_transform
		choose_destination(source)
		check("%s self-navigation in area clears immediately" % source,str(room.get("destination_zone")).is_empty() and (room.get("route_points") as Array).is_empty() and not (hud.get("route_card") as Control).visible and (hud.get("toast_label") as Label).text.contains("已抵達") and player.global_transform.is_equal_approx(local_before))
		hud.call("_dismiss_notice")
		for destination: String in zones:
			if source == destination:
				continue
			move_to(source_point)
			var before: Transform3D = player.global_transform
			choose_destination(destination)
			var route: Array = (room.get("route_points") as Array).duplicate()
			var route_card: Control = hud.get("route_card")
			var direct: float = player.global_position.distance_to(Garden.vector(zones[destination].walk_path[-1]))
			var status: Dictionary = room.call("_route_status")
			var length_respects_paths: bool = float(status.get("distance",0)) >= direct - 1
			var expected: Array[Vector3] = Navigation.route(room.get("layout"),before.origin,source,destination)
			var same_walkways: bool = route.size()==expected.size()
			if same_walkways:
				for index: int in range(route.size()):
					same_walkways = same_walkways and (route[index] as Vector3).distance_to(expected[index])<.02
			check("%s to %s follows the shortest authored walkways without teleport" % [source,destination],not route.is_empty() and same_walkways and length_respects_paths and player.global_transform.is_equal_approx(before))
			# Resolve each actual route leg as it is reached, like walking along it.
			for point: Vector3 in route:
				move_to(point)
			room.call("_update_hud")
			var notice: Label = hud.get("toast_label")
			check("%s to %s clears navigation on arrival" % [source,destination],str(room.get("destination_zone")).is_empty() and (room.get("route_points") as Array).is_empty() and not route_card.visible and notice.text.contains("已抵達") and notice.text.contains(Garden.TITLES[destination]))
			hud.call("_dismiss_notice")
	move_to(Garden.vector(zones.university.center)+Vector3.UP*.06)
	choose_destination("career")
	(hud.get("route_cancel") as Button).pressed.emit()
	check("Navigation can be cancelled without leaving exploration",str(room.get("destination_zone")).is_empty() and (room.get("route_points") as Array).is_empty() and not (hud.get("route_card") as Control).visible and not bool(room.get("returning")))
	room.call("_select_destination","../outside")
	check("Unknown destination cannot leave a broken active route",str(room.get("destination_zone")).is_empty() and not (hud.get("route_card") as Control).visible)
	route_checks_completed = true

func check_focus(zones: Dictionary) -> void:
	var ring: MeshInstance3D = room.get("selection_ring")
	var ring_id: int = ring.get_instance_id()
	var all_devices: Array[Node3D] = []
	for zone: Dictionary in zones.values():
		for device: Node3D in zone.devices:
			all_devices.append(device)
	var labels_valid: bool = true
	var stable_addresses: Dictionary = {}
	for device: Node3D in all_devices:
		var label: Label3D = device.get("preview_label")
		labels_valid = labels_valid and not label.double_sided and not label.no_depth_test and label.visibility_range_end <= 8.0 and label.visibility_range_end > 0 and label.billboard==BaseMaterial3D.BILLBOARD_DISABLED
		stable_addresses[str(device.get("thread_id"))] = true
		move_to(device.global_position+device.global_basis.z*2.4,-device.global_basis.z)
		var focused: Array[Node3D] = all_devices.filter(func(candidate: Node3D) -> bool: return bool(candidate.get("_focused")))
		var ring_position: bool = Vector2(ring.global_position.x,ring.global_position.z).distance_to(Vector2(device.global_position.x,device.global_position.z)) < .02
		check("%s has one nearby marker and independent action" % device.name,focused.size()==1 and focused[0]==device and ring.visible and ring_position and ring.get_instance_id()==ring_id and not (hud.get("interaction_button") as Button).disabled)
	check("Forty previews use single-sided depth-tested nearby text",labels_valid)
	check("Visual batching preserves forty independent thread addresses",stable_addresses.size()==40)
	check("Only one selection marker exists in the full scene",room.find_children("ActiveDeviceRing*","MeshInstance3D",true,false).size()==1)
	move_to(Vector3(0,.06,0))
	check("Leaving all devices clears the marker and posting action",not ring.visible and all_devices.all(func(device: Node3D) -> bool: return not bool(device.get("_focused"))) and not (hud.get("interaction_card") as Control).visible and (hud.get("interaction_button") as Button).disabled)
	focus_checks_completed = true

func check_camera_clearance(zones: Dictionary) -> void:
	# Probe only narrow architectural columns near the maker-street devices.
	# All offsets and yaw samples are device-local, so moving/rotating whole
	# districts cannot invalidate this shoulder-camera regression test.
	var space := room.get_world_3d().direct_space_state
	var columns: Array[Node3D] = []
	for body: StaticBody3D in room.find_children("*","StaticBody3D",true,false):
		if body.collision_layer & 1 == 0:
			continue
		for collider: CollisionShape3D in body.find_children("*","CollisionShape3D",false,false):
			if collider.shape is BoxShape3D:
				var size: Vector3 = (collider.shape as BoxShape3D).size
				if size.y >= 2.5 and size.x <= 1.4 and size.z <= 1.4:
					columns.append(body)
	var actor_collider: CollisionShape3D = player.find_children("*","CollisionShape3D",false,false)[0]
	var actor_query := PhysicsShapeQueryParameters3D.new()
	actor_query.shape = actor_collider.shape
	actor_query.collision_mask = 1
	actor_query.exclude = [player.get_rid()]
	var lens := SphereShape3D.new()
	lens.radius = .17
	var lens_query := PhysicsShapeQueryParameters3D.new()
	lens_query.shape = lens
	lens_query.collision_mask = 257
	lens_query.exclude = [player.get_rid()]
	var camera: Camera3D = room.get("camera")
	var previous_yaw: float = room.get("camera_yaw")
	var previous_pitch: float = room.get("camera_pitch")
	var tested: int = 0
	var overlap_count: int = 0
	var evidence: Array[Dictionary] = []
	for device: Node3D in zones.major.devices:
		var near_column: bool = columns.any(func(column: Node3D) -> bool: return Vector2(column.global_position.x,column.global_position.z).distance_to(Vector2(device.global_position.x,device.global_position.z)) < 4.2)
		if not near_column:
			continue
		for radius: float in [.7,1.1,2.4,2.75]:
			for around: int in range(32):
				var local_angle: float = float(around)*TAU/32
				var local_position := Vector3(sin(local_angle),0,cos(local_angle))*radius
				var point: Vector3 = device.to_global(local_position)
				point.y = .06
				actor_query.transform = Transform3D(Basis.IDENTITY,point+actor_collider.position)
				if not space.intersect_shape(actor_query,1).is_empty():
					continue
				move_to(point)
				for angle: int in range(16):
					room.set("camera_yaw",device.global_rotation.y + float(angle)*TAU/16)
					room.set("camera_pitch",.28)
					room.call("update_camera",0.0,true)
					lens_query.transform = Transform3D(Basis.IDENTITY,camera.global_position)
					var hits: Array[Dictionary] = space.intersect_shape(lens_query,1)
					tested += 1
					if not hits.is_empty():
						overlap_count += 1
						if evidence.size() < 3:
							evidence.append({"device":device.name,"local_position":local_position,"local_yaw":float(angle)*TAU/16,"camera":camera.global_position,"body":str(hits[0].collider.get_path())})
	room.set("camera_yaw",previous_yaw)
	room.set("camera_pitch",previous_pitch)
	camera_probe = {"tested":tested,"overlap_count":overlap_count,"examples":evidence}
	check("Nearby architectural columns receive valid standing camera samples",tested >= 100)
	check("Shoulder camera stays outside columns from valid standing positions",overlap_count==0)
	if overlap_count > 0:
		print("OVERHAUL_CAMERA_FAILURE ",JSON.stringify(camera_probe))
	camera_checks_completed = true

func check_modal_and_escape(zones: Dictionary) -> void:
	var target: Node3D = zones.university.devices[3]
	move_to(target.global_position+target.global_basis.z*2.4,-target.global_basis.z)
	(hud.get("guide_button") as Button).pressed.emit()
	escape()
	check("Escape closes guide before leaving the garden",not (hud.get("guide_panel") as Control).visible and not bool(room.get("returning")) and return_count==0)
	var before: Transform3D = player.global_transform
	var camera: Camera3D = room.get("camera")
	var camera_before: Transform3D = camera.global_transform
	var heading: Vector3 = player.get("heading")
	var mode: Node.ProcessMode = player.process_mode
	(hud.get("interaction_button") as Button).pressed.emit()
	check("Opening a device marks browser input ownership and freezes the player",bool(room.get("account_view_open")) and fixture.opened and player.process_mode==Node.PROCESS_MODE_DISABLED and not bool(player.get("controls_enabled")) and not hud.visible and fixture.contexts.back()==target.call("context"))
	var contexts_before: int = fixture.contexts.size()
	room.call("activate_nearest")
	check("Repeated interaction cannot open a second device view",fixture.contexts.size()==contexts_before)
	room.call("touch_look",Vector2(100,80))
	check("Touch camera input cannot rotate player through an open discussion",(player.get("heading") as Vector3).is_equal_approx(heading))
	escape()
	check("Escape closes discussion and restores camera position and input ownership",not fixture.opened and not bool(room.get("account_view_open")) and hud.visible and player.process_mode==mode and bool(player.get("controls_enabled")) and player.global_transform.is_equal_approx(before) and camera.global_transform.is_equal_approx(camera_before) and return_count==0)
	supply_empty_pages()
	(hud.get("account_button") as Button).pressed.emit()
	check("Account button uses the same modal input boundary",fixture.opened and bool(room.get("account_view_open")) and fixture.contexts.back()=={"view":"account"} and not hud.visible)
	fixture.close_view()
	check("Closing account restores exploration exactly",not bool(room.get("account_view_open")) and hud.visible and player.global_transform.is_equal_approx(before) and bool(player.get("controls_enabled")))
	supply_empty_pages()
	fixture.accepts = false
	(hud.get("interaction_button") as Button).pressed.emit()
	check("Failed discussion opening cannot strand the player in a locked view",not bool(room.get("account_view_open")) and (room.get("snapshot") as Dictionary).is_empty() and hud.visible and bool(player.get("controls_enabled")) and player.global_transform.is_equal_approx(before) and (hud.get("toast_card") as Control).visible)
	escape()
	check("Escape returns to world once when no overlay is open",return_count==1 and bool(room.get("returning")))
	escape()
	check("Repeated Escape cannot double-return",return_count==1)
	modal_checks_completed = true

func write_report() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	var file := FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"renderer":DisplayServer.get_name(),"low_variant_checked":low_variant_checked,"camera_probe":camera_probe},"  "))
	file.close()
