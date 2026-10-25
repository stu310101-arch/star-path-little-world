extends SceneTree
## Validate routes against Godot's real capsule sweep, not the planner's boxes.
const Garden = preload("res://scripts/discussion_garden.gd")
const Navigation = preload("res://scripts/discussion_navigation.gd")
const Startup = preload("res://tests/startup_fixture.gd")
class Quality:
	extends Node
	signal state_changed
	func is_low_quality() -> bool: return true
class Account:
	extends Node
	signal forum_message(packet: Dictionary)
	signal state_changed(user: Dictionary)
	signal closed
	var user: Dictionary = {"profileReady":true,"sessionGeneration":9}
	func request_forum_page(_command: Dictionary) -> bool: return false
var room: Node3D
var checks: Array[Dictionary] = []
var cases: Array[Dictionary] = []
var failures: int = 0
var query := PhysicsShapeQueryParameters3D.new()
var space: PhysicsDirectSpaceState3D
var case_count: int = 0
func _initialize() -> void:
	run.call_deferred()
func check(title: String, passed: bool) -> void:
	checks.append({"name":title,"pass":passed})
	if not passed: failures += 1
	print("OBSTACLE_NAV_CHECK ",title," ",passed)
func at(point: Vector3) -> Transform3D:
	return Transform3D(Basis.IDENTITY,point+Vector3.UP*.82)
func run() -> void:
	var account := Account.new()
	account.name = "StarPathAccount"
	root.add_child(account)
	var quality := Quality.new()
	root.add_child(quality)
	room = Garden.new()
	room.set("graphics_settings",quality)
	root.add_child(room)
	current_scene = room
	check("Actual final garden becomes playable",await Startup.wait_room(room,self))
	if not bool(room.get("ready_for_play")):
		quit(1)
		return
	room.set_process(false)
	var player: CharacterBody3D = room.get("player")
	player.set_physics_process(false)
	space = room.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.6
	query.shape = capsule
	query.collision_mask = 1
	var excluded: Array[RID] = [player.get_rid()]
	# Floor support is intentionally traversable; furniture and walls remain.
	for body: StaticBody3D in room.find_children("*","StaticBody3D",true,false):
		for collider: CollisionShape3D in body.find_children("*","CollisionShape3D",false,false):
			if collider.shape is BoxShape3D and collider.global_position.y+(collider.shape as BoxShape3D).size.y*.5<=.15:
				excluded.append(body.get_rid())
	query.exclude = excluded
	var layout: Dictionary = room.get("layout")
	var rear_wall: Dictionary = {}
	for box: Dictionary in layout.colliders:
		if box.get("name")=="LearningGrove_WestCabin_RearWall":
			rear_wall = box
	var close_wall: Vector3 = Garden.vector(rear_wall.center)+Vector3(0,0,-float(rear_wall.size[2])*.5-.29).rotated(Vector3.UP,float(rear_wall.rotation_y))
	close_wall.y = .06
	for test: Dictionary in [
		{"name":"behind west cabin","start":Vector3(25,.06,-25),"zone":"high_school","blocked":true},
		{"name":"inside west cabin","start":Vector3(22.35204,.06,-19.09231),"zone":"high_school","blocked":true},
		{"name":"inside east cabin","start":Vector3(35.33808,.06,-6.71642),"zone":"high_school","blocked":true},
		{"name":"beside wall within comfort margin","start":close_wall,"zone":"high_school","blocked":true},
		{"name":"behind maker studio","start":Vector3(-32,.06,3),"zone":"major","blocked":true},
		{"name":"behind courtyard fountain","start":Vector3(0,.06,-40),"zone":"campus","blocked":true},
		{"name":"outside career glazing","start":Vector3(37,.06,13),"zone":"career","blocked":true},
		{"name":"open grass beside ring","start":Vector3(6,.06,-7),"zone":"high_school","blocked":false}
	]:
		inspect_case(layout,test)
	check("All eight exploration cases complete",case_count==8)
	# Recovery from an invalid spawn must not claim that another area was reached.
	player.call("place_at",Vector3(0,.06,-33))
	room.set("current_zone","campus")
	room.call("_select_destination","university")
	var hud: CanvasLayer = room.get("hud")
	check("An obstructed start shows recovery guidance instead of false arrival",str(room.get("destination_zone")).is_empty() and (room.get("route_points") as Array).is_empty() and not (hud.get("route_card") as Control).visible and (hud.get("toast_label") as Label).text.contains("找不到可通行") and not (hud.get("toast_label") as Label).text.contains("已抵達"))
	var output := "res://../deliverables/discussion-revision/navigation-obstacles.json"
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"cases":cases,"layout_sha256":FileAccess.get_sha256(Garden.LAYOUT)},"  "))
	file.close()
	room.queue_free()
	await process_frame
	print("OBSTACLE_NAV_RESULT checks=",checks.size()," failures=",failures)
	quit(0 if failures==0 else 1)

func inspect_case(layout: Dictionary, test: Dictionary) -> void:
	var start: Vector3 = test.start
	query.transform = at(start)
	query.motion = Vector3.ZERO
	check(test.name+" starts in a valid standing space",space.intersect_shape(query,1).is_empty())
	var began: int = Time.get_ticks_usec()
	var route: Array[Vector3] = Navigation.route(layout,start,test.zone,"university")
	var elapsed: int = Time.get_ticks_usec()-began
	check(test.name+" obtains a route to the target area",not route.is_empty() and route[-1].distance_to(Vector3(-14.00071,.06,14.00071))<.02)
	var physical_clear: bool = not route.is_empty()
	var all_legs_clear: bool = not route.is_empty()
	var before: Vector3 = start
	var length: float = 0
	var blocked_legs: Array[Dictionary] = []
	for point: Vector3 in route:
		query.transform = at(before)
		query.motion = point-before
		var fraction := space.cast_motion(query)
		var passed: bool = fraction.size()==2 and fraction[0]>.9999
		physical_clear = physical_clear and passed
		all_legs_clear = all_legs_clear and Navigation.segment_clear(layout,before,point)
		if not passed:
			blocked_legs.append({"from":before,"to":point,"fraction":fraction[0] if fraction.size()==2 else -1})
		length += before.distance_to(point)
		before = point
	check(test.name+" clears every wall and device with the real capsule",physical_clear)
	check(test.name+" can advance each navigation turn safely",all_legs_clear)
	var entry: Vector3
	for zone: Dictionary in layout.zones:
		if zone.id==test.zone:
			entry = Garden.vector(zone.walk_path[-1])
	if bool(test.blocked):
		check(test.name+" refuses the old straight shortcut",not Navigation.segment_clear(layout,start,entry))
	check(test.name+" avoids an excessive full-map detour",length<start.distance_to(route[-1])+55 if not route.is_empty() else false)
	if test.name=="behind west cabin":
		inspect_corner_guidance(layout,start,route)
	cases.append({"name":test.name,"start":start,"points":route,"length_m":length,"plan_usec":elapsed,"blocked_legs":blocked_legs})
	case_count += 1

func inspect_corner_guidance(layout: Dictionary, start: Vector3, route: Array[Vector3]) -> void:
	var before: Vector3 = start
	var found: bool = false
	for index: int in range(route.size()-1):
		var corner: Vector3 = route[index]
		var next: Vector3 = route[index+1]
		var incoming: Vector3 = corner-before
		if incoming.length()<.5:
			before = corner
			continue
		for backoff: float in [.25,.5,1.0,1.8]:
			if backoff>=incoming.length():
				continue
			var nearby: Vector3 = corner-incoming.normalized()*backoff
			if Navigation.segment_clear(layout,nearby,next):
				continue
			var remaining: Array[Vector3] = []
			for point: Vector3 in route.slice(index):
				remaining.append(point)
			(room.get("player") as Node3D).call("place_at",nearby)
			room.set("destination_zone","university")
			room.set("route_points",remaining)
			room.call("_route_status")
			var after: Array = room.get("route_points")
			check("Near a cabin corner the guide does not cut through the wall",not after.is_empty() and (after[0] as Vector3).distance_to(corner)<.001)
			(room.get("player") as Node3D).call("place_at",corner)
			room.call("_route_status")
			after = room.get("route_points")
			check("Reaching the clear cabin corner advances guidance",after.is_empty() or (after[0] as Vector3).distance_to(corner)>.01)
			room.set("destination_zone","")
			room.set("route_points",[] as Array[Vector3])
			found = true
			break
		if found:
			break
		before = corner
	check("Cabin regression exercises a real obstructed short-corner skip",found)
