extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const OUTPUT: String = "res://../deliverables/authored-streets/"
const CAMERA_DISTANCE: float = 7.0
const CAMERA_FOV: float = 42.0
# Each visit is on its district's authored natural promenade. In universities
# and WordKing this selects the scenic branch at a junction, not the town axis.
const NATURE_PATHS: Array[int] = [0,0,2,2,1,1]

var world: Node3D
var player: PlanetPlayer
var camera: Camera3D
var hud: CanvasLayer
var minimap: Control
var layout: Dictionary = {}
var districts: Array = []
var radius: float = 48.0
var records: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Street art review requires the native renderer; run without --headless.")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	root.size = Vector2i(1440,900)
	districts = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	layout = world.get("layout") as Dictionary
	radius = float(layout.radius)
	player = world.get("player") as PlanetPlayer
	camera = world.get("camera") as Camera3D
	hud = world.get("hud") as CanvasLayer
	minimap = hud.get("minimap") as Control
	hud.visible = true
	hud.call("close_panel")
	world.call("set_overview",false)
	world.set("capture_focus",null)
	world.set("near_distance",CAMERA_DISTANCE)
	camera.fov = CAMERA_FOV
	player.controls_enabled = false
	player.allow_test_input = false
	player.test_direction = Vector2.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await physics_frame
	await physics_frame
	for district_index: int in range(districts.size()):
		var info: Dictionary = districts[district_index]
		var up: Vector3 = district_up(district_index)
		var views: Array[Dictionary] = [entrance_view(info,up),nature_view(info,up,district_index)]
		for view_index: int in range(views.size()):
			var view: Dictionary = views[view_index]
			view["name"] = "%02d-%s-%s" % [district_index*2+view_index+1,str(info.station),str(view.kind)]
			view["station"] = str(info.station)
			view["theme"] = str(info.theme)
			await stage_player(view)
			await take(view)
	var output: Dictionary = {
		"passed":failures == 0 and records.size() == 12,
		"failures":failures,
		"images":records,
		"gameplay_camera_distance":CAMERA_DISTANCE,
		"gameplay_camera_fov":CAMERA_FOV,
		"notes":"All twelve frames use the real grounded player and fixed-distance roaming camera with HUD and minimap. No overhead, capture_focus, layout mutation, or hidden scene objects. Life uses the existing building forecourt at [3,-2.9]; counseling's nature view looks back along its lakeside approach toward [-22,15]."
	}
	var file: FileAccess = FileAccess.open(OUTPUT+"capture-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	print("AUTHORED_STREETS_CAPTURE "+JSON.stringify(output))
	quit(0 if bool(output.passed) else 1)

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func district_up(index: int) -> Vector3:
	var data: Array = layout.stations[index].normal
	return Vector3(float(data[0]),float(data[1]),float(data[2]))

func normal_at(up: Vector3,point: Vector2) -> Vector3:
	return Geo.surface(up,point,radius).normalized()

func entrance_view(info: Dictionary,up: Vector3) -> Dictionary:
	var civic: Vector2 = v2(info.civic)
	var desired: Vector2 = civic+Vector2(0,3.0)
	var edges: Array[Dictionary] = []
	for road: Array in info.roads:
		edges.append({"a":v2(road[0]),"b":v2(road[1]),"width":6.3,"surface":"interior street"})
	for index: int in range(info.loop.size()):
		edges.append({"a":v2(info.loop[index]),"b":v2(info.loop[(index+1)%info.loop.size()]),"width":6.3,"surface":"street loop"})
	for path: Array in info.paths:
		for index: int in range(path.size()-1):
			edges.append({"a":v2(path[index]),"b":v2(path[index+1]),"width":2.2,"surface":"authored public promenade"})
	var position: Vector2 = desired
	var selected_surface: String = "MISSING"
	var nearest_distance: float = INF
	for edge: Dictionary in edges:
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(desired,edge.a as Vector2,edge.b as Vector2)
		var distance: float = closest.distance_to(desired)
		if distance >= nearest_distance:
			continue
		nearest_distance = distance
		# Keep the desired 3 m approach when it fits inside real street paving.
		# Otherwise stand on the nearest authored centreline, never on a lawn
		# substituted for a path or beyond the end of a promenade.
		position = desired if distance <= float(edge.width)*.5-.45 else closest
		selected_surface = str(edge.surface)
	if str(info.station) == "life":
		# This is the existing paved connector from x=0 to the civic building's
		# front at [6,-2.9], not a new route or a point on the intervening lawn.
		position = Vector2(3,-2.9)
		selected_surface = "existing civic building forecourt"
	return {
		"kind":"entrance",
		"normal":normal_at(up,position),
		"target":normal_at(up,civic),
		"pitch":.32,
		"planned_local":[position.x,position.y],
		"target_local":[civic.x,civic.y],
		"selected_surface":selected_surface,
		"civic_distance_local":position.distance_to(civic),
		"purpose":"入口街景：以人物尺度檢查目的地辨識、門面比例、人行道、入口前庭與前後景層次"
	}

func nature_view(info: Dictionary,up: Vector3,index: int) -> Dictionary:
	var path_index: int = NATURE_PATHS[index]
	var path: Array = info.paths[path_index]
	var visit: Vector2 = v2(info.visit)
	var position: Vector2 = visit
	var start_distance: float = .0
	var accumulated: float = .0
	var nearest_distance: float = INF
	for segment: int in range(path.size()-1):
		var a: Vector2 = v2(path[segment])
		var b: Vector2 = v2(path[segment+1])
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(visit,a,b)
		var distance: float = closest.distance_to(visit)
		if distance < nearest_distance:
			nearest_distance = distance
			position = closest
			start_distance = accumulated+a.distance_to(closest)
		accumulated += a.distance_to(b)
	# Look forward along the actual next 7 m of trail. At the last junction the
	# selected branch above supplies a real continuation instead of open water.
	var target_distance: float = minf(start_distance+7.0,accumulated)
	if target_distance-start_distance < 2.0:
		target_distance = maxf(.0,start_distance-7.0)
	var target: Vector2 = point_along(path,target_distance)
	if str(info.station) == "counseling":
		# Keep the same grounded visit position and look back toward the lake
		# corner; the other direction only reviewed the city and its back walls.
		target = Vector2(-22,15)
	return {
		"kind":"nature",
		"normal":normal_at(up,position),
		"target":normal_at(up,target),
		"pitch":.38,
		"planned_local":[position.x,position.y],
		"target_local":[target.x,target.y],
		"selected_surface":"authored public promenade "+str(path_index),
		"visit_distance_local":position.distance_to(visit),
		"purpose":"自然步道：從實際可步行路面檢查水岸連續、欄杆、樹冠留白、座椅退讓與前方目的地"
	}

func point_along(path: Array,distance: float) -> Vector2:
	var remaining: float = distance
	for index: int in range(path.size()-1):
		var a: Vector2 = v2(path[index])
		var b: Vector2 = v2(path[index+1])
		var length: float = a.distance_to(b)
		if remaining <= length:
			return a.lerp(b,remaining/maxf(length,.00001))
		remaining -= length
	return v2(path[-1])

func stage_player(view: Dictionary) -> void:
	(world.get("camera_obstruction") as RefCounted).call("reset")
	var normal: Vector3 = view.normal as Vector3
	var target: Vector3 = view.target as Vector3
	player.set_physics_process(true)
	player.teleport(normal,radius+.7)
	player.heading = (target*radius-normal*radius).slide(normal).normalized()
	player.visual.rotation.y = PI
	world.set("near_pitch",float(view.pitch))
	world.set("near_distance",CAMERA_DISTANCE)
	camera.fov = CAMERA_FOV
	for frame: int in range(36):
		await physics_frame
	player.set_physics_process(false)
	var settled_up: Vector3 = player.global_position.normalized()
	player.heading = (target*radius-player.global_position).slide(settled_up).normalized()
	player.previous_up = settled_up
	player.global_basis = Basis(player.heading.cross(settled_up).normalized(),settled_up,-player.heading)
	player.visual.rotation.y = PI
	player.set_clip(&"Idle")
	for frame: int in range(12):
		world.call("update_camera",1.0/30.0)
		update_hud()
		await process_frame

func update_hud() -> void:
	world.call("update_nearest")
	hud.call("update_status",false,str(world.get("nearest_label")),player.global_position.length())
	minimap.call("refresh")

func take(view: Dictionary) -> void:
	update_hud()
	await process_frame
	await RenderingServer.frame_post_draw
	var ground: Dictionary = player.ground_at(player.global_position.normalized())
	var grounded: bool = player.is_on_floor() and not ground.is_empty()
	var ground_path: String = str((ground.collider as Node).get_path()) if not ground.is_empty() else "MISSING"
	var paved: bool = paved_ground(ground)
	var intended: Vector3 = view.normal as Vector3
	var drift: float = intended.angle_to(player.global_position.normalized())*radius
	var aim: Vector3 = world.get("camera_aim") as Vector3
	var distance: float = camera.global_position.distance_to(aim)
	var pixels: Image = root.get_texture().get_image()
	var name: String = str(view.name)
	var error: Error = pixels.save_png(ProjectSettings.globalize_path(OUTPUT+name+".png"))
	var valid: bool = error == OK and grounded and paved and drift < .5 and absf(distance-CAMERA_DISTANCE) < .01 and absf(camera.fov-CAMERA_FOV) < .01 and hud.visible and minimap.visible
	if not valid:
		failures += 1
		push_error("Street review frame failed validation: "+name+" ground="+ground_path+" drift="+str(drift))
	var arrow: Vector2 = minimap.get("arrow_heading_2d") as Vector2
	records.append({
		"file":name+".png","station":view.station,"theme":view.theme,"kind":view.kind,"purpose":view.purpose,
		"overhead":false,"grounded":grounded,"ground_collider":ground_path,"paved_surface":paved,
		"selected_surface":view.selected_surface,"planned_local":view.planned_local,"target_local":view.target_local,
		"settling_drift_m":drift,"player_position":vector_array(player.global_position),"heading":vector_array(player.heading),
		"camera_position":vector_array(camera.global_position),"camera_aim":vector_array(aim),"camera_distance":distance,"camera_fov":camera.fov,"pitch":view.pitch,
		"minimap_location":str(minimap.get("current_location")),"minimap_arrow":[arrow.x,arrow.y],
		"hud_visible":hud.visible,"minimap_visible":minimap.visible,"size":[pixels.get_width(),pixels.get_height()],"passed":valid
	})
	print("STREET_FRAME "+name+" grounded="+str(grounded)+" paved="+str(paved)+" distance="+str(distance)+" fov="+str(camera.fov))

func vector_array(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func paved_ground(ground: Dictionary) -> bool:
	if ground.is_empty():
		return false
	var collider: Node = ground.collider as Node
	var path: String = str(collider.get_path())
	for label: String in ["Asphalt","Sidewalk","DistrictPromenade","BuildingForecourt","CivicPlaza","TimberBoardwalk_"]:
		if path.contains(label):
			return true
	# Repeated generated ribbons can receive anonymous Godot node names. Their
	# actual floor material still identifies the authored paving, unlike grass,
	# bank terrain, water or building foundations beneath a coincident ray.
	var mesh: MeshInstance3D = collider.get_parent() as MeshInstance3D
	if mesh == null:
		return false
	var material: StandardMaterial3D = mesh.material_override as StandardMaterial3D
	if material == null:
		return false
	for color: Color in [Color("8e9893"),Color("34434b"),Color("a1aba0"),Color("929a94")]:
		if material.albedo_color.is_equal_approx(color):
			return true
	return false
