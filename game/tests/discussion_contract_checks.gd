extends SceneTree
const Protocol = preload("res://scripts/forum_protocol.gd")
const Garden = preload("res://scripts/discussion_garden.gd")
const Device = preload("res://scripts/discussion_device.gd")
const NativeHost = preload("res://scripts/account_native_host.gd")
const Startup = preload("res://tests/startup_fixture.gd")

class FakeAccount:
	extends Node
	signal forum_message(packet: Dictionary)
	signal state_changed(user: Dictionary)
	signal closed
	signal failed(message: String)
	var user: Dictionary = {"signedIn":true,"displayName":"測試學生","identity":"university","profileReady":true,"sessionGeneration":7}
	var opened: bool = false
	var requests: Array[Dictionary] = []
	var contexts: Array[Dictionary] = []
	func request_forum_page(command: Dictionary) -> bool:
		requests.append(command)
		return true
	func open_forum(context: Dictionary) -> bool:
		contexts.append(context)
		opened = true
		return true
	func open_view(_view: String) -> bool:
		opened = true
		return true
	func close_view() -> void:
		opened = false
		closed.emit()

var failures: int = 0
var checks: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks += 1
	print("DISCUSSION_CHECK ",label," ",passed)
	if not passed:
		failures += 1
func tick(count: int = 3) -> void:
	for index: int in range(count):
		await physics_frame
		await process_frame
func packet(command: Dictionary, kind: String) -> Dictionary:
	return {"channel":"starpath-forum","version":1,"requestId":command.requestId,"sessionGeneration":7,"zone":command.zone,"type":kind}
func feed(room: Node, command: Dictionary, count: int = 8, empty: bool = false, page: int = 0) -> void:
	var begin: Dictionary = packet(command,"page-begin")
	begin.itemCount = count
	begin.devicePage = page
	room.call("receive_packet",begin)
	for index: int in range(count):
		var item: Dictionary = packet(command,"page-empty" if empty else "page-item")
		item.merge({"index":index,"threadId":Device.thread_for(command.zone,page,index),"preview":"第 %d 則校園分享" % index,"authorName":"同學","identity":"university","anonymous":false,"createdAtMillis":100,"updatedAtMillis":100,"deleted":false})
		room.call("receive_packet",item)
	var end: Dictionary = packet(command,"page-end")
	end.merge({"count":count,"hasNext":true,"hasPrevious":false})
	room.call("receive_packet",end)

func run() -> void:
	var user: Dictionary = NativeHost.sanitize_user({"signedIn":true,"displayName":"星","identity":"university","profileReady":true,"sessionGeneration":3,"uid":"secret","idToken":"secret"})
	check("Profile transport keeps public state without UID/token",user.size()==5 and user.identity=="university" and not user.has("uid") and not user.has("idToken"))
	var native: Node = NativeHost.new()
	var surface := Control.new()
	native.set("webview",surface)
	native.set("trusted_document",true)
	var states: Array[Dictionary] = []
	native.connect("state_changed",func(state: Dictionary) -> void: states.append(state))
	var auth: Dictionary = {"channel":"starpath-account","version":1,"type":"auth-state","sessionGeneration":1790000000123,"user":{"signedIn":true,"displayName":"星","identity":"university","profileReady":true,"sessionGeneration":1790000000123}}
	native.call("_receive_message",JSON.stringify(auth))
	check("Native auth supports monotonic timestamp-sized generation",states.size()==1 and states[0].sessionGeneration==1790000000123)
	auth.sessionGeneration = 1790000000122
	auth.user = null
	native.call("_receive_message",JSON.stringify(auth))
	check("Native ignores delayed authentication from an older host epoch",states.size()==1)
	auth.sessionGeneration = 1790000000124
	native.call("_receive_message",JSON.stringify(auth))
	check("Current native signout clears account state",states.size()==2 and states.back().is_empty())
	native.set("webview",null)
	native.free()
	surface.free()
	var example: Dictionary = {"channel":"starpath-forum","version":1,"requestId":"req_1","sessionGeneration":7,"zone":"campus","type":"page-item","index":0,"threadId":"post1","preview":"匿名留言","authorName":"secret","identity":"university","anonymous":true,"uid":"hidden"}
	var clean: Dictionary = Protocol.sanitize_packet(example)
	check("Anonymous transport retains selected identity but strips author identifiers",clean.authorName=="匿名" and clean.identity=="university" and not clean.has("uid"))
	example.preview = "字".repeat(1400)
	check("Oversized Unicode packet is rejected",Protocol.sanitize_packet(example).is_empty())
	check("Invalid document IDs cannot navigate host",not Protocol.valid_id("../other") and not Protocol.valid_id("x?token=1"))
	check("Device variants resolve only within their authored zone",Garden.device_model_path({"id":"campus","device_model":"message_device_campus.glb"}).ends_with("/message_device_campus.glb") and Garden.device_model_path({"id":"campus","device_model":"../message_device_campus.glb"}).is_empty() and Garden.device_model_path({"id":"campus","device_model":"message_device_career.glb"}).is_empty())
	var fixture := FakeAccount.new()
	fixture.name = "StarPathAccount"
	root.add_child(fixture)
	var room: Node3D = Garden.new()
	root.add_child(room)
	current_scene = room
	check("Actual authored layout is valid",Garden.valid_layout(JSON.parse_string(FileAccess.get_file_as_string(Garden.LAYOUT)) as Dictionary))
	check("Actual garden + shared avatar become ready",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	await tick(5)
	var zones: Dictionary = room.get("zones")
	check("Five zones instantiate exactly eight physical devices",zones.size()==5 and zones.values().all(func(z: Dictionary) -> bool: return z.devices.size()==8))
	var player: CharacterBody3D = room.get("player")
	check("Shared player stands on authored floor",player.is_on_floor())
	var authored_variant_paths: Array[String] = []
	for authored_zone: Dictionary in room.get("layout").zones:
		authored_variant_paths.append(Garden.device_model_path(authored_zone))
	check("All layout-selected device models were loaded",authored_variant_paths.all(func(path: String) -> bool: return path in room.get("model_paths")))
	var cull_zone: Dictionary = zones.university
	var probe := MeshInstance3D.new()
	room.add_child(probe)
	cull_zone.art.append(probe)
	var saved_position: Vector3 = player.position
	var zone_center: Vector3 = Garden.vector(cull_zone.center)
	player.position = zone_center+Vector3(60,0,0)
	room.call("_update_zone_visibility",true)
	check("Zone art culls from authored center even when mesh origin is hub",not probe.visible)
	player.position = zone_center
	room.call("_update_zone_visibility")
	check("Approaching zone restores visible art",probe.visible)
	cull_zone.art.erase(probe)
	probe.queue_free()
	player.position = saved_position
	room.call("_update_zone_visibility",true)
	var command: Dictionary = fixture.requests[0]
	feed(room,command)
	check("Complete page swaps eight visible post slots",(room.get("pages") as Dictionary)[command.zone].items.size()==8)
	room.call("request_page",command.zone,"refresh")
	var refresh: Dictionary = fixture.requests.back()
	var begin: Dictionary = packet(refresh,"page-begin")
	begin.itemCount = 8
	room.call("receive_packet",begin)
	check("Partial refresh preserves prior page",(room.get("pages") as Dictionary)[command.zone].items.size()==8)
	var end: Dictionary = packet(refresh,"page-end")
	end.merge({"count":8,"hasNext":false,"hasPrevious":false})
	room.call("receive_packet",end)
	check("Incomplete page cannot overwrite visible posts",(room.get("pages") as Dictionary)[command.zone].items.size()==8)
	var zone: Dictionary = zones[command.zone]
	var device: Node3D = zone.devices[0]
	player.call("place_at",device.position+device.basis.z*1.1, -device.basis.z)
	await tick(4)
	room.call("refresh_nearest")
	room.call("activate_nearest")
	check("Approached device opens its exact thread",not fixture.contexts.is_empty() and fixture.contexts.back().get("deviceId")==Device.thread_for(command.zone,0,0))
	check("Forum freezes player and hides HUD",player.process_mode==Node.PROCESS_MODE_DISABLED and not (room.get("hud") as CanvasLayer).visible)
	var before: Transform3D = player.global_transform
	fixture.close_view()
	check("Close restores player and HUD",player.global_transform.is_equal_approx(before) and player.process_mode==Node.PROCESS_MODE_INHERIT and (room.get("hud") as CanvasLayer).visible)
	check("Closing device refreshes its zone",fixture.requests.back().zone==command.zone and fixture.requests.back().direction=="refresh")
	var addresses: Dictionary = {}
	for zone_id: String in zones:
		for empty: bool in [true,false]:
			(room.get("pending") as Dictionary).clear()
			room.call("request_page",zone_id,"refresh")
			feed(room,fixture.requests.back(),8,empty)
			for index: int in range(8):
				var target: Node3D = zones[zone_id].devices[index]
				player.call("place_at",target.position+target.basis.z*2.4,-target.basis.z)
				room.call("refresh_nearest")
				var actionable: bool = not (room.get("action_button") as Button).disabled and not (room.get("compose_button") as Button).disabled
				room.call("activate_nearest")
				var expected: String = Device.thread_for(zone_id,0,index)
				check("%s device %d %s responds at 2.4 m" % [zone_id,index+1,"empty" if empty else "occupied"],actionable and fixture.opened and fixture.contexts.back()=={"zone":zone_id,"deviceId":expected})
				addresses[expected] = true
				fixture.close_view()
				feed(room,fixture.requests.back(),8,empty)
	check("All forty devices own distinct addresses",addresses.size()==40)
	player.call("place_at",Vector3(0,0,0))
	room.call("refresh_nearest")
	check("Cannot post from a distant point",(room.get("compose_button") as Button).disabled)
	if OS.get_cmdline_user_args().has("--capture"):
		var shown: Node3D = zones.university.devices[0]
		shown.call("apply_slot",0,{})
		player.call("place_at",shown.position+shown.basis.z*2.4,-shown.basis.z)
		room.set("camera_yaw",shown.rotation.y)
		await tick(4)
		room.call("update_camera",0.0,true)
		room.call("refresh_nearest")
		(room.get("pending") as Dictionary).clear()
		room.set("notice_until",0)
		room.call("refresh_nearest")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://../deliverables/discussion-forum/independent-device-in-game.png")
	room.call("_account_changed",{})
	check("Account change clears pages and in-flight payloads",(room.get("pages") as Dictionary).is_empty() and (room.get("pending") as Dictionary).is_empty())
	room.queue_free()
	fixture.queue_free()
	await tick()
	print("DISCUSSION_RESULT checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
