extends SceneTree
## Deterministic local visual fixture. Uses no remote account or user posts.
const Garden = preload("res://scripts/discussion_garden.gd")
const Device = preload("res://scripts/discussion_device.gd")
const Startup = preload("res://tests/startup_fixture.gd")
const OUTPUT = "res://../deliverables/discussion-overhaul/visual/"
class Quality:
	extends Node
	signal state_changed
	var low: bool = false
	func is_low_quality() -> bool: return low
	func is_constrained_runtime() -> bool: return low
class Account:
	extends Node
	signal forum_message(packet: Dictionary)
	signal closed
	signal state_changed(user: Dictionary)
	var user: Dictionary = {"profileReady":true,"sessionGeneration":7}
	func request_forum_page(command: Dictionary) -> bool:
		feed.call_deferred(command)
		return true
	func feed(command: Dictionary) -> void:
		var base: Dictionary = {"channel":"starpath-forum","version":1,"requestId":command.requestId,"sessionGeneration":7,"zone":command.zone}
		var begin: Dictionary = base.duplicate()
		begin.merge({"type":"page-begin","itemCount":8,"devicePage":0})
		forum_message.emit(begin)
		for index: int in range(8):
			var item: Dictionary = base.duplicate()
			item.merge({"type":"page-empty","index":index,"threadId":Device.thread_for(command.zone,0,index)})
			forum_message.emit(item)
		var end: Dictionary = base.duplicate()
		end.merge({"type":"page-end","count":8,"hasNext":false,"hasPrevious":false})
		forum_message.emit(end)
var room: Node3D
var player: CharacterBody3D
var prefix: String = "standard"
func _initialize() -> void:
	run.call_deferred()
func capture(name: String, point: Vector3, facing: Vector3) -> void:
	player.call("place_at",point,facing)
	room.set("camera_yaw",atan2(-facing.x,-facing.z))
	room.call("_update_zone_visibility",true)
	room.call("update_camera",0,true)
	room.call("refresh_nearest")
	for index: int in range(12):
		await physics_frame
		await process_frame
	RenderingServer.force_draw(false)
	var path: String = OUTPUT+prefix+"-"+name+".png"
	if root.get_texture().get_image().save_png(path) != OK:
		quit(1)
	print("GARDEN_VISUAL ",path)
func run() -> void:
	if DisplayServer.get_name()=="headless":
		quit(1)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1440,900)
	Engine.max_fps = 60
	var low: bool = OS.get_cmdline_user_args().has("--low")
	prefix = "minimum" if low else "standard"
	root.msaa_3d = Viewport.MSAA_DISABLED if low else Viewport.MSAA_2X
	if low:
		root.scaling_3d_scale = .6
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var quality := Quality.new()
	quality.low = low
	root.add_child(quality)
	room = Garden.new()
	room.set("graphics_settings",quality)
	root.add_child(room)
	current_scene = room
	if not await Startup.wait_room(room,self):
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--no-shadows"):
		room.get_node("GardenSun").shadow_enabled = false
		prefix += "-no-shadows"
	player = room.get("player")
	player.set("controls_enabled",false)
	await capture("arrival",Garden.vector(room.get("layout").spawn.position),Vector3.FORWARD)
	for zone: Dictionary in room.get("layout").zones:
		var point: Vector3 = Garden.vector(zone.controls.point)
		var facing: Vector3 = (Garden.vector(zone.center)-point).normalized()
		await capture(str(zone.id),point,facing)
		if OS.get_cmdline_user_args().has("--single-university"):
			quit()
			return
		var device: Node3D = room.get("zones")[zone.id].devices[3]
		var front: Vector3 = device.global_basis.z.normalized()
		await capture(str(zone.id)+"-device",device.global_position+front*2.1,-front)
	player.call("place_at",Vector3(0,.06,6),Vector3.FORWARD)
	room.call("refresh_nearest")
	room.call("_select_destination","campus")
	await capture("guide",Vector3(0,.06,6),Vector3.FORWARD)
	room.get("hud").call("toggle_guide")
	await capture("guide-open",Vector3(0,.06,6),Vector3.FORWARD)
	root.size = Vector2i(390,844)
	room.set_meta("force_touch_controls",true)
	room.call("_resize_hud")
	await capture("mobile-guide",Vector3(0,.06,6),Vector3.FORWARD)
	quit()
