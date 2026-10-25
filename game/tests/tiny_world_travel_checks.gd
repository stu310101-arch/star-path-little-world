extends SceneTree

## Run with --headless --fixed-fps 60. This measures simulation seconds at the
## production 60 Hz physics step, never accelerated movement or wall time.
## Only the initial placement teleports. Every road, bank and bridge thereafter
## uses the shipped PlanetPlayer, capsule, shore guard and permanent collision.
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Outdoor = preload("res://scripts/outdoor_scale.gd")
const OUTPUT: String = "res://../deliverables/world-correction/travel-after.json"
const PHYSICS_HZ: int = 60
const MAX_TRAVEL_SECONDS: float = 30.0
const DIAGNOSTIC_TIMEOUT_SECONDS: float = 45.0
const WAYPOINT_RADIUS: float = .08
const EXPECTED_AVATAR_SCALE: float = .4
var world: Node3D
var player: PlanetPlayer
var radius: float
var authoring_radius: float = 60.0
var scaled_source_fixture: bool = false
var districts: Array
var axes: Array[Vector3]
var checks: Array[Dictionary] = []
var journeys: Array[Dictionary] = []
var failures: int = 0
var previous_routes: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label+": "+str(evidence))

func run() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = PHYSICS_HZ
	var config: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var previous: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://../deliverables/world-correction/travel-before.json")) as Dictionary
	for journey: Dictionary in previous.journeys:
		previous_routes[str(journey.route)] = journey
	authoring_radius = float(config.get("authoring_radius",60.0))
	scaled_source_fixture = OS.get_cmdline_user_args().has("--scaled-source-fixture")
	if scaled_source_fixture:
		if not InputMap.has_action("jump"):
			InputMap.add_action("jump")
		world = Node3D.new()
		for part: String in ["globe","neighborhood","stations"]:
			var content: Node3D = (load("res://generated/streaming/"+part+"_base.scn") as PackedScene).instantiate() as Node3D
			Outdoor.apply_to_children(content,.4)
			world.add_child(content)
		root.add_child(world)
		player = (load("res://scripts/planet_player.gd") as Script).new() as PlanetPlayer
		player.planet_radius = float(config.radius)
		player.walk_speed = float(config.outdoor_walk_speed)*EXPECTED_AVATAR_SCALE
		player.run_speed = float(config.outdoor_run_speed)*EXPECTED_AVATAR_SCALE
		player.avatar_scale = EXPECTED_AVATAR_SCALE
		world.add_child(player)
	else:
		world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
		root.add_child(world)
		world.set_process(false)
		(world.get("hud") as Node).process_mode = Node.PROCESS_MODE_DISABLED
		player = world.get("player") as PlanetPlayer
	current_scene = world
	Engine.max_fps = 0
	radius = player.planet_radius
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.controls_enabled = false
	player.allow_test_input = true
	player.test_running = false
	player.set_physics_process(true)
	await ticks(2)
	districts = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	axes = Routes.directions()
	check("World is physically smaller while character-relative movement stays original",is_equal_approx(radius,21.6) and is_equal_approx(authoring_radius,54.0) and is_equal_approx(player.walk_speed/player.avatar_scale,3.8) and is_equal_approx(player.run_speed/player.avatar_scale,6.4) and player.global_basis.get_scale().is_equal_approx(Vector3.ONE) and not player.test_running,{"physical_radius_m":radius,"authoring_radius":authoring_radius,"walk_mps":player.walk_speed,"run_mps":player.run_speed,"body_scale":str(player.global_basis.get_scale())})
	var indoor: PlanetPlayer = (load("res://scripts/indoor_player.gd") as Script).new()
	check("Walking and running cadence match the original indoor character",is_equal_approx(player._locomotion_rate(player.walk_speed,&"Walk"),indoor._locomotion_rate(indoor.walk_speed,&"Walk")) and is_equal_approx(player._locomotion_rate(player.run_speed,&"Run"),indoor._locomotion_rate(indoor.run_speed,&"Run")) and not player.speed_matched_locomotion)
	indoor.free()
	var collision: CollisionShape3D = player.find_children("*","CollisionShape3D",true,false)[0] as CollisionShape3D
	var capsule: CapsuleShape3D = collision.shape as CapsuleShape3D
	check("Outdoor avatar and visual subtree match the world at 0.4 scale",is_equal_approx(player.avatar_scale,EXPECTED_AVATAR_SCALE) and player.visual.scale.is_equal_approx(Vector3.ONE*EXPECTED_AVATAR_SCALE),{"avatar_scale":player.avatar_scale,"visual_scale":str(player.visual.scale)})
	check("Real capsule dimensions match the smaller avatar",capsule!=null and is_equal_approx(capsule.radius,.27*EXPECTED_AVATAR_SCALE) and is_equal_approx(capsule.height,1.6*EXPECTED_AVATAR_SCALE) and is_equal_approx(collision.position.y,.82*EXPECTED_AVATAR_SCALE) and collision.global_basis.get_scale().is_equal_approx(Vector3.ONE),{"radius_m":capsule.radius if capsule else null,"height_m":capsule.height if capsule else null,"centre_height_m":collision.position.y})
	check("All twelve adjacent district pairs are exercised",Routes.bridge_edges().size()==12)
	for edge: Vector2i in Routes.bridge_edges():
		if OS.get_cmdline_user_args().has("--campus-diagnostic") and edge!=Vector2i(0,3): continue
		await travel(edge)
		await travel(Vector2i(edge.y,edge.x))
	player.test_direction = Vector2.ZERO
	var seconds: Array[float] = []
	for journey: Dictionary in journeys:
		if bool(journey.arrived):
			seconds.append(float(journey.seconds))
	seconds.sort()
	var expected_journeys: int = 2 if OS.get_cmdline_user_args().has("--campus-diagnostic") else 24
	check("All requested pairs complete in both directions",journeys.size()==expected_journeys and seconds.size()==expected_journeys)
	var report: Dictionary = {"passed":failures==0,"failures":failures,"checks":checks,"journeys":journeys,"physics_hz":PHYSICS_HZ,"time_scale":Engine.time_scale,"ordinary_movement":true,"maximum_seconds":MAX_TRAVEL_SECONDS,"expected_journeys":24,"completed":seconds.size(),"median_seconds":(seconds[(seconds.size()-1)/2]+seconds[seconds.size()/2])*.5 if not seconds.is_empty() else null,"fastest_seconds":seconds[0] if not seconds.is_empty() else null,"slowest_seconds":seconds[-1] if not seconds.is_empty() else null,"fixture":"Actual world.tscn permanent collision and production PlanetPlayer at 60 Hz. Both directions of all twelve district pairs. Start and finish are district centres. Routes follow authored roads, paths, coastal connectors and the complete bridge. No running, added floor, mid-route teleport, manual position movement, or scaled physics time. HUD presentation is disabled."}
	report["scaled_source_diagnostic"] = scaled_source_fixture
	report["physical_radius_m"] = radius
	report["authoring_radius"] = authoring_radius
	report["walk_speed_mps"] = player.walk_speed
	report["run_speed_mps"] = player.run_speed
	report["avatar_scale"] = player.avatar_scale
	report["capsule_radius_m"] = capsule.radius
	report["capsule_height_m"] = capsule.height
	var output_path: String = OUTPUT.get_base_dir()+"/travel-scaled-source-diagnostic.json" if scaled_source_fixture else OUTPUT
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	FileAccess.open(output_path,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TINY_WORLD_TRAVEL completed=",seconds.size()," failures=",failures," seconds=",seconds)
	world.free()
	await process_frame
	await process_frame
	quit(0 if failures==0 else 1)

func ticks(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func normal_at(index: int, point: Vector2) -> Vector3:
	return Geo.surface(axes[index],point,authoring_radius).normalized()

func metres(a: Vector3, b: Vector3) -> float:
	return atan2(a.cross(b).length(),clampf(a.dot(b),-1.0,1.0))*radius

func travel(edge: Vector2i) -> void:
	var tag: String = str(districts[edge.x].station)+" -> "+str(districts[edge.y].station)
	var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge,authoring_radius)
	var departure: Array[Vector3] = city_route(edge.x,Routes.local_point(endpoints[0],axes[edge.x],authoring_radius))
	var arrival: Array[Vector3] = city_route(edge.y,Routes.local_point(endpoints[1],axes[edge.y],authoring_radius))
	check("Authored streets connect both centres to the bridge: "+tag,departure.size()>1 and arrival.size()>1,{"departure_waypoints":departure.size(),"arrival_waypoints":arrival.size()})
	if departure.size()<2 or arrival.size()<2:
		journeys.append({"route":tag,"arrived":false,"seconds":0.0,"error":"Disconnected authored route graph"})
		return
	arrival.reverse()
	var route: Array[Vector3] = departure.duplicate()
	route.append_array(arrival)
	var route_metres: float = 0.0
	for index: int in range(route.size()-1):
		route_metres += metres(route[index],route[index+1])
	var ground: Dictionary = player.ground_at(route[0])
	check("Centre has real floor before the timed journey: "+tag,not ground.is_empty())
	player.test_direction = Vector2.ZERO
	player.test_running = false
	player.teleport(route[0],(ground.position as Vector3).length()+.44 if not ground.is_empty() else radius+.7)
	await ticks(45)
	check("Controller settles on the departure centre: "+tag,player.is_on_floor() and metres(player.position.normalized(),route[0])<.1,{"grounded":player.is_on_floor(),"offset_m":metres(player.position.normalized(),route[0])})
	var frame_count: int = 0
	var grounded_frames: int = 0
	var consecutive_airborne: int = 0
	var maximum_airborne: int = 0
	var missing_floor: int = 0
	var maximum_error: float = 0.0
	var distance_walked: float = 0.0
	var completed: bool = true
	var legs: Array[Dictionary] = []
	var previous: Vector3 = player.position.normalized()
	for index: int in range(1,route.size()):
		var target: Vector3 = route[index]
		var leg_frames: int = 0
		var reached: bool = metres(player.position.normalized(),target)<=WAYPOINT_RADIUS
		while not reached and frame_count<ceili(DIAGNOSTIC_TIMEOUT_SECONDS*PHYSICS_HZ):
			player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
			player.test_direction = Vector2(0,-1)
			await physics_frame
			frame_count += 1
			leg_frames += 1
			var current: Vector3 = player.position.normalized()
			if OS.get_cmdline_user_args().has("--campus-diagnostic") and frame_count%120==0:
				var contacts: Array[String] = []
				for c: int in range(player.get_slide_collision_count()): contacts.append(str((player.get_slide_collision(c).get_collider() as Node).get_path()))
				print("CAMPUS_STEP leg=",index," frame=",frame_count," local=",Routes.local_point(current,axes[edge.x],authoring_radius)," contacts=",contacts)
			distance_walked += metres(previous,current)
			previous = current
			if player.is_on_floor():
				grounded_frames += 1
				consecutive_airborne = 0
			else:
				consecutive_airborne += 1
				maximum_airborne = maxi(maximum_airborne,consecutive_airborne)
			if player.ground_at(current).is_empty():
				missing_floor += 1
			maximum_error = maxf(maximum_error,segment_error(current,route[index-1],target))
			reached = metres(current,target)<=WAYPOINT_RADIUS
		var blockers: Array[String] = []
		if not reached:
			for collision_index: int in range(player.get_slide_collision_count()):
				var collision: KinematicCollision3D = player.get_slide_collision(collision_index)
				if collision.get_normal().dot(player.up_direction)<.5:
					blockers.append(str((collision.get_collider() as Node).get_path()))
		legs.append({"index":index,"kind":"sea_bridge" if index==departure.size() else "city_path","seconds":float(leg_frames)/PHYSICS_HZ,"reached":reached,"remaining_m":metres(player.position.normalized(),target),"start_normal":vector_array(route[index-1]),"target_normal":vector_array(target),"blockers":blockers})
		if not reached:
			completed = false
			break
	player.test_direction = Vector2.ZERO
	var elapsed: float = float(frame_count)/PHYSICS_HZ
	var end_error: float = metres(player.position.normalized(),axes[edge.y])
	var grounded_ratio: float = float(grounded_frames)/maxi(1,frame_count)
	var evidence: Dictionary = {"route":tag,"edge":[edge.x,edge.y],"arrived":completed and end_error<=WAYPOINT_RADIUS,"seconds":elapsed,"planned_m":route_metres,"walked_m":distance_walked,"ideal_seconds":route_metres/player.walk_speed,"geodesic_m":metres(axes[edge.x],axes[edge.y]),"grounded_ratio":grounded_ratio,"longest_airborne_seconds":float(maximum_airborne)/PHYSICS_HZ,"missing_floor_frames":missing_floor,"maximum_path_error_m":maximum_error,"arrival_error_m":end_error,"running":player.test_running,"legs":legs,"final_position":vector_array(player.position)}
	journeys.append(evidence)
	print("TINY_TRAVEL ",tag," seconds=",elapsed," arrived=",evidence.arrived," grounded=",grounded_ratio," max_error=",maximum_error)
	check("Normal-cadence walking reaches the adjacent centre without running: "+tag,bool(evidence.arrived) and elapsed<=MAX_TRAVEL_SECONDS and not player.test_running,{"seconds":elapsed,"planned_m":route_metres,"arrival_error_m":end_error})
	var previous_journey: Dictionary = previous_routes.get(tag,{})
	check("Travel is shorter because the actual route is shorter: "+tag,not previous_journey.is_empty() and route_metres<float(previous_journey.get("planned_m",0)) and is_equal_approx(player.walk_speed,1.52),{"before_metres":previous_journey.get("planned_m"),"after_metres":route_metres,"normal_pace_seconds_before":float(previous_journey.get("planned_m",0))/player.walk_speed,"normal_pace_seconds_after":route_metres/player.walk_speed})
	check("Whole journey remains supported by real road and bridge floor: "+tag,missing_floor==0 and grounded_ratio>=.98 and maximum_airborne<=3,{"grounded_ratio":grounded_ratio,"missing_floor_frames":missing_floor,"longest_airborne_frames":maximum_airborne})
	check("Controller stays within the authored path corridor: "+tag,maximum_error<.55,maximum_error)

func vector_array(value: Vector3) -> Array[float]:
	return [value.x,value.y,value.z]

func segment_error(point: Vector3, a: Vector3, b: Vector3) -> float:
	var plane: Vector3 = a.cross(b)
	if plane.length_squared()<.000000001:
		return metres(point,a)
	var closest: Vector3 = point.slide(plane.normalized()).normalized()
	if metres(a,closest)+metres(closest,b)<=metres(a,b)+.001:
		return metres(point,closest)
	return minf(metres(point,a),metres(point,b))

func city_route(index: int, coast: Vector2) -> Array[Vector3]:
	var info: Dictionary = districts[index]
	var segments: Array[Dictionary] = []
	for road: Array in info.roads:
		append_segments(segments,road,4.2,true)
	var loop: Array = (info.loop as Array).duplicate(true)
	loop.append(loop[0])
	append_segments(segments,loop,4.2,true)
	for path: Array in Routes.district_paths(info,authoring_radius):
		append_segments(segments,path,2.2,false)
	var links: Array[Dictionary] = []
	for i: int in range(segments.size()):
		var a: Dictionary = segments[i]
		for j: int in range(i+1,segments.size()):
			var b: Dictionary = segments[j]
			var intersection: Variant = Geometry2D.segment_intersects_segment(a.a,a.b,b.a,b.b)
			if intersection!=null:
				(a.cuts as Array).append(intersection)
				(b.cuts as Array).append(intersection)
			# Campus road ends stop at x=+/-3, while its central footpath is
			# x=0. Their visible widths meet even though the centrelines do not.
			# Link only overlapping road/path widths; never enter a boardwalk
			# through the side of another rail-lined path.
			for pair: Array in [[a,b],[b,a]]:
				var from: Dictionary = pair[0]
				var to: Dictionary = pair[1]
				for point: Vector2 in [from.a,from.b]:
					var projected: Vector2 = Geometry2D.get_closest_point_to_segment(point,to.a,to.b)
					var separation: float = point.distance_to(projected)
					var joined: bool = separation<.025 or ((bool(from.road) or bool(to.road)) and separation<=(float(from.width)+float(to.width))*.5)
					if joined:
						(to.cuts as Array).append(projected)
						links.append({"a":point,"b":projected})
	# The exact geographic centre must lie inside an authored road/path.
	for segment: Dictionary in segments:
		var projected: Vector2 = Geometry2D.get_closest_point_to_segment(Vector2.ZERO,segment.a,segment.b)
		if projected.length()<=float(segment.width)*.5:
			(segment.cuts as Array).append(projected)
			links.append({"a":Vector2.ZERO,"b":projected})
	var graph: AStar3D = AStar3D.new()
	var ids: Dictionary = {}
	for segment: Dictionary in segments:
		var start: Vector2 = segment.a
		var cuts: Array = segment.cuts
		cuts.sort_custom(func(a: Vector2,b: Vector2) -> bool: return start.distance_squared_to(a)<start.distance_squared_to(b))
		for i: int in range(cuts.size()-1):
			connect_graph(graph,ids,index,cuts[i],cuts[i+1])
	for link: Dictionary in links:
		connect_graph(graph,ids,index,link.a,link.b)
	var start_id: int = graph_point(graph,ids,index,Vector2.ZERO)
	var finish_id: int = graph_point(graph,ids,index,coast)
	var result: Array[Vector3] = []
	for point: Vector3 in graph.get_point_path(start_id,finish_id):
		var normal: Vector3 = point.normalized()
		if result.is_empty() or metres(result[-1],normal)>.025:
			result.append(normal)
	return simplify_straight(result)

func append_segments(segments: Array[Dictionary], path: Array, width: float, road: bool) -> void:
	for index: int in range(path.size()-1):
		var a: Vector2 = Vector2(path[index][0],path[index][1])
		var b: Vector2 = Vector2(path[index+1][0],path[index+1][1])
		if a.distance_to(b)>.001:
			segments.append({"a":a,"b":b,"width":width,"road":road,"cuts":[a,b]})

func graph_point(graph: AStar3D, ids: Dictionary, index: int, point: Vector2) -> int:
	var key: String = "%d:%d" % [roundi(point.x*1000),roundi(point.y*1000)]
	if not ids.has(key):
		var id: int = ids.size()
		ids[key] = id
		graph.add_point(id,normal_at(index,point)*radius)
	return int(ids[key])

func connect_graph(graph: AStar3D, ids: Dictionary, index: int, a: Vector2, b: Vector2) -> void:
	var from: int = graph_point(graph,ids,index,a)
	var to: int = graph_point(graph,ids,index,b)
	if from!=to and not graph.are_points_connected(from,to):
		graph.connect_points(from,to)

func simplify_straight(points: Array[Vector3]) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Vector3 in points:
		while result.size()>1 and absf(metres(result[-2],result[-1])+metres(result[-1],point)-metres(result[-2],point))<.001:
			result.pop_back()
		result.append(point)
	return result
