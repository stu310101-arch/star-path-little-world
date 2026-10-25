extends SceneTree

const StartupFixture: Script = preload("res://tests/startup_fixture.gd")
const Outdoor = preload("res://scripts/outdoor_scale.gd")
var authoring_radius: float = 60.0
var outdoor_scale: float = .4

var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String, passed: bool, detail: String = "") -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label + ": " + detail)

func run_checks() -> void:
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 120
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	check("Character preparation completes before animation inspection", await StartupFixture.prepare_player(player, self))
	var radius: float = player.planet_radius
	var raw_layout: Dictionary = world.get("layout") as Dictionary
	authoring_radius = Outdoor.authored_radius(raw_layout)
	outdoor_scale = Outdoor.factor(raw_layout)
	check("Six distinct stations", world.get_node("Stations").get_child_count() == 6)
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
	var all_upright: bool = true
	var building_count: int = 0
	for asset: Dictionary in build.assets:
		all_upright = all_upright and float(asset.up_dot) > 0.999
		if asset.kind == "building":
			building_count += 1
	check("Six planned modern districts have 48 buildings", building_count == 48 and build.districts.size() == 6)
	check("Physical world radius stays 24 m with an unscaled physics body", is_equal_approx(radius,float(world.get("layout").radius)) and is_equal_approx(radius,24.0) and player.scale.is_equal_approx(Vector3.ONE))
	check("Outdoor avatar matches world scale without changing movement speed",is_equal_approx(player.avatar_scale,.4) and player.visual.scale.is_equal_approx(Vector3.ONE*.4))
	check("Outdoor walking and running preserve the original character speeds",is_equal_approx(player.walk_speed,3.8) and is_equal_approx(player.run_speed,6.4))
	check("Props align to radial up", all_upright)
	check("Connected city roads cover all six districts", build.roads.size() >= 300)
	check("Landscaping occupies designated courtyards", build.landscapes.size() == 18)
	check("Authored sakura and sea content built",build.sakura_trees == preload("res://scripts/sakura_routes.gd").trees().size() and int(build.sakura_layout_version)==preload("res://scripts/sakura_routes.gd").LAYOUT_VERSION and build.boats == 7 and build.fish == 28)
	var district_data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var signatures: Dictionary={}
	var ecology: RefCounted=(load("res://tools/ecology_world.gd") as Script).new() as RefCounted
	for index: int in range(district_data.size()):
		var data: Dictionary=district_data[index]
		signatures[JSON.stringify(data.loop)+JSON.stringify(data.urban_buildings)]=true
		var entry: Vector2=Vector2(data.civic[0],data.civic[1])
		var carriageways: Array=data.roads.duplicate()
		for k: int in range(data.loop.size()):
			carriageways.append([data.loop[k],data.loop[(k+1)%data.loop.size()]])
		var entrance_clear: bool=true
		for road: Array in carriageways:
			var a: Vector2=Vector2(road[0][0],road[0][1])
			var b: Vector2=Vector2(road[1][0],road[1][1])
			var q: Vector2=a+(b-a)*clampf((entry-a).dot(b-a)/(b-a).length_squared(),0,1)
			entrance_clear=entrance_clear and entry.distance_to(q)>3.5
		check("Entrance platform clears moving traffic " + str(index),entrance_clear)
		var nd: Array=world.get("layout").stations[index].normal
		var up: Vector3=Vector3(nd[0],nd[1],nd[2])
		# Probe both sides of every bend, not just its centreline. Separate
		# butt-ended strips passed centreline tests while exposing large wedges.
		var road_points: Array[Vector3] = []
		for point_data: Array in data.loop:
			road_points.append(authored_surface(up,Vector2(point_data[0],point_data[1]),radius).normalized())
		check("Asphalt covers inner and outer corners " + str(index),joined_surface_covered(world,road_points,radius,.285*outdoor_scale,4.2*outdoor_scale,true))
		var path_corners_safe: bool = true
		for path_data: Array in preload("res://scripts/world_routes.gd").district_paths(data,authoring_radius):
			var path_points: Array[Vector3] = []
			for point_data: Array in path_data:
				path_points.append(authored_surface(up,Vector2(point_data[0],point_data[1]),radius).normalized())
			path_corners_safe = joined_surface_covered(world,path_points,radius,.26*outdoor_scale,2.2*outdoor_scale,false) and path_corners_safe
		check("Full promenade width joins at bends " + str(index),path_corners_safe)
		var visit: Vector2=Vector2(data.visit[0],data.visit[1])
		check("Ecology arrival is dry " + str(index),not player.ground_at(authored_surface(up,visit,radius).normalized()).is_empty())
		var paths_safe: bool=true
		for path: Array in data.paths:
			for j: int in range(path.size()-1):
				var a: Vector2=Vector2(path[j][0],path[j][1])
				var b: Vector2=Vector2(path[j+1][0],path[j+1][1])
				for k: int in range(21):
					paths_safe=paths_safe and not player.ground_at(authored_surface(up,a.lerp(b,float(k)/20.0),radius).normalized()).is_empty()
		check("Promenades and boardwalks continuous " + str(index),paths_safe)
		var wet_probes: int=0
		var water_blocked: bool=true
		for x: int in range(-36,37,2):
			for y: int in range(-34,35,2):
				var p: Vector2=Vector2(x,y)
				if float(ecology.call("water_distance",p,data)) < -.8 and float(ecology.call("path_distance",p,data))>2.0 and float(ecology.call("edge_distance",p,data,index))>1.0:
					wet_probes+=1
					water_blocked=water_blocked and player.ground_at(authored_surface(up,p,radius).normalized()).is_empty()
		check("Lake and river water has no hidden land " + str(index),wet_probes>0 and water_blocked,str(wet_probes))
	check("All six urban arrangements differ",signatures.size()==6)
	var authored_planting: bool = bool(build.ecology.get("authored_planting",false)) and int(build.ecology.districts)==6
	for district_planting: Dictionary in build.ecology.get("planting_groups",[]):
		authored_planting = authored_planting and (district_planting.groups as Array).size()>=3 and not (district_planting.view_windows as Array).is_empty()
	check("Six reserves use authored groves with open view windows and preserved garden specimens",authored_planting and int(build.ecology.get("pocket_specimens_preserved",0))==18,str(build.ecology))
	check_ocean_chunks(world, player, radius)
	var sources: PackedStringArray = player.animator.get_animation_list()
	check("Character has Walk Run and JumpDown", sources.has("Walk") and sources.has("Run") and sources.has("JumpDown"), str(sources))
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	world.call("_input",press)
	var yaw_before: float = world.get("orbit_yaw")
	var pitch_before: float = world.get("orbit_pitch")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(100,40)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	world.call("_input",motion)
	check("Right drag rotates overview horizontally and vertically",absf(float(world.get("orbit_yaw"))-yaw_before)>0.3 and absf(float(world.get("orbit_pitch"))-pitch_before)>.1)
	press.pressed = false
	world.call("_input",press)
	check("Right release restores cursor",not bool(world.get("dragging_view")))
	world.call("set_overview",false)
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	press.pressed = true
	world.call("_input",press)
	var heading_before: Vector3 = player.heading
	world.call("_input",motion)
	check("Right drag rotates character camera and pitch",heading_before.dot(player.heading)<0.95 and float(world.get("near_pitch"))>0.65)
	press.pressed = false
	world.call("_input",press)
	for station: Node in world.get_node("Stations").get_children():
		world.call("teleport_to", str(station.name))
		check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
		for i: int in range(45):
			await physics_frame
		check("Station landing " + str(station.name), player.is_on_floor() and player.position.length() > radius and player.position.length() < radius + 1.0, str(player.position.length()))
		check("Radial orientation " + str(station.name), player.basis.y.dot(player.position.normalized()) > 0.998)
		var toward: Vector3 = ((station as Node3D).position - player.position).slide(player.position.normalized()).normalized()
		check("Arrival faces entrance " + str(station.name), player.heading.dot(toward) > 0.99)
	# Sample every road's visible top against the actual physics collider.
	var road_ok: bool = true
	for road: Dictionary in build.roads:
		var offset: Array = road.offset
		var up: Array = road.up
		var normal: Vector3 = authored_surface(Vector3(up[0],up[1],up[2]),Vector2(offset[0],offset[1]),radius).normalized()
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal * (radius + 2.0), normal * (radius - 0.5), 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		road_ok = road_ok and not hit.is_empty()
		if not hit.is_empty():
			road_ok = road_ok and (hit.position as Vector3).length() > radius + 0.15*outdoor_scale
	check("Road tops have matching collisions", road_ok)
	# Test each furnished street with real player collision, not only ray samples.
	player.allow_test_input = true
	player.test_running = true
	for index: int in range(district_data.size()):
		var district: Dictionary = world.get("layout").stations[index]
		var info: Dictionary = district_data[index]
		var normal_data: Array = district.normal
		var normal: Vector3 = Vector3(normal_data[0],normal_data[1],normal_data[2])
		var road: Array = info.roads[0] if not (info.roads as Array).is_empty() else [info.loop[0],info.loop[1]]
		var road_a: Vector2 = Vector2(road[0][0],road[0][1])
		var road_b: Vector2 = Vector2(road[1][0],road[1][1])
		var arrival: Vector3 = authored_surface(normal,road_a.lerp(road_b,.25),radius).normalized()
		var target: Vector3 = authored_surface(normal,road_b,radius)
		player.teleport(arrival,radius + 0.6)
		player.heading = (target-player.position).slide(arrival).normalized()
		player.test_direction = Vector2.ZERO
		for i: int in range(20):
			await physics_frame
		var street_start: Vector3 = player.position
		var street_trial_m: float = minf(3.5,arrival.angle_to(target.normalized())*radius*.65)
		var street_frames: int = maxi(1,ceili(street_trial_m/player.run_speed*Engine.physics_ticks_per_second/Engine.time_scale))
		player.test_direction = Vector2(0,-1)
		for i: int in range(street_frames):
			await physics_frame
		check("Clear street " + str(district.id),player.position.distance_to(street_start) > street_trial_m*.9 and player.position.length() > radius)
	player.test_direction = Vector2.ZERO
	world.call("teleport_to", "counseling")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	for i: int in range(30):
		await physics_frame
	var before: Vector3 = player.position
	world.call("open_station", "counseling")
	check("Entrance begins the existing jump clip",bool(world.get("entering")) and player.active_clip == &"JumpDown")
	var apex: float = 0.0
	while bool(world.get("entering")):
		await process_frame
		apex = maxf(apex,player.visual.position.y)
	check("Scaled entry jump rises and disappears before the panel",apex>1.0*player.avatar_scale and not player.visual.visible and bool(world.get("paused")),"height=%f avatar_scale=%f" % [apex,player.avatar_scale])
	world.call("resume_world", {})
	check("Panel retains world position", before.distance_to(player.position) < 0.03)
	check("Returning restores character",player.visual.visible and not player.entering and player.visual.position.is_zero_approx())
	world.call("visit_sakura")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	for i: int in range(45):
		await physics_frame
	check("Sakura grove can be visited on foot",player.is_on_floor() and player.position.length()>radius)
	await wait_for_detail(world, "sakura")
	var bridge: Node3D = detail_node(world, "sakura", "SakuraBridge")
	check("Sakura bridge detail is available after its streaming region loads", bridge != null)
	if bridge == null:
		finish_checks(world)
		return
	var bridge_a: Vector3 = bridge.get_meta("start") as Vector3
	var bridge_b: Vector3 = bridge.get_meta("finish") as Vector3
	var bridge_grounded: bool = true
	for i: int in range(101):
		bridge_grounded = bridge_grounded and not player.ground_at(bridge_a.slerp(bridge_b,float(i)/100.0)).is_empty()
	check("Sakura bridge has continuous walkable collision",bridge_grounded)
	for reverse: bool in [false,true]:
		var from: Vector3 = bridge_b if reverse else bridge_a
		var to: Vector3 = bridge_a if reverse else bridge_b
		player.teleport(from,radius+.8)
		player.test_direction = Vector2.ZERO
		for i: int in range(25):
			await physics_frame
		var reached: bool = false
		player.test_direction = Vector2(0,-1)
		for i: int in range(240):
			player.heading = (to*radius-player.position).slide(player.position.normalized()).normalized()
			await physics_frame
			if player.position.normalized().angle_to(to)*radius<.65*outdoor_scale:
				reached = true
				break
		check("Sakura bridge actual walk " + ("return" if reverse else "outbound"),reached,str(player.position))
		player.test_direction = Vector2.ZERO
	var grove_up: Vector3 = preload("res://scripts/sakura_routes.gd").grove_up()
	var town_approach: Vector3 = preload("res://scripts/sakura_routes.gd").town_endpoint(authoring_radius)
	var garden_approach: Vector3 = grove_up
	for reverse: bool in [false,true]:
		var route: Array[Vector3] = [town_approach,bridge_a,bridge_b,garden_approach]
		if reverse:
			route.reverse()
		player.teleport(route[0],radius+.8)
		player.test_direction = Vector2.ZERO
		for i: int in range(25):
			await physics_frame
		var completed: bool = true
		for target: Vector3 in route.slice(1):
			var reached: bool = false
			player.test_direction = Vector2(0,-1)
			for i: int in range(maxi(220,ceili(player.position.normalized().angle_to(target)*radius/player.run_speed*45.0))):
				player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
				await physics_frame
				if player.position.normalized().angle_to(target)*radius<.48*outdoor_scale:
					reached = true
					break
			completed = completed and reached
			player.test_direction = Vector2.ZERO
		check("Continuous city to garden walk " + ("return" if reverse else "outbound"),completed,str(player.position))
	# Traverse an actual wetland boardwalk corner with the normal controller.
	var swamp_normal: Array=world.get("layout").stations[5].normal
	var swamp_up: Vector3=Vector3(swamp_normal[0],swamp_normal[1],swamp_normal[2])
	var wet_route: Array[Vector2]=[Vector2(18,13),Vector2(22,16),Vector2(25,20),Vector2(20,25)]
	player.teleport(authored_surface(swamp_up,wet_route[0],radius).normalized(),radius+.7)
	player.test_direction=Vector2.ZERO
	for j: int in range(24):
		await physics_frame
	var wet_reached: bool=true
	var wet_evidence: Array[Dictionary] = []
	for point: Vector2 in wet_route.slice(1):
		var target: Vector3=authored_surface(swamp_up,point,radius).normalized()
		var reached: bool=false
		player.test_direction=Vector2(0,-1)
		for j: int in range(220):
			player.heading=(target*radius-player.position).slide(player.position.normalized()).normalized()
			await physics_frame
			if player.position.normalized().angle_to(target)*radius<.4*outdoor_scale:
				reached=true
				break
		wet_reached=wet_reached and reached
		wet_evidence.append({"target":str(point),"reached":reached,"distance":player.position.normalized().angle_to(target)*radius,"position":str(player.position)})
	player.test_direction=Vector2.ZERO
	check("Walk through wetland boardwalk turns",wet_reached,JSON.stringify(wet_evidence))
	# Walk the lake-side road bend shown in the seam report in both directions.
	var lake_normal: Array = world.get("layout").stations[4].normal
	var lake_up: Vector3 = Vector3(lake_normal[0],lake_normal[1],lake_normal[2])
	for reverse: bool in [false,true]:
		var route: Array[Vector2] = [Vector2(-3,17.7),Vector2(-8,18),Vector2(-12,14.4)]
		if reverse:
			route.reverse()
		player.teleport(authored_surface(lake_up,route[0],radius).normalized(),radius+.7)
		for j: int in range(24):
			await physics_frame
		var completed: bool = true
		for point: Vector2 in route.slice(1):
			var target: Vector3 = authored_surface(lake_up,point,radius).normalized()
			var reached: bool = false
			player.test_direction = Vector2(0,-1)
			for j: int in range(180):
				player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
				await physics_frame
				if player.position.normalized().angle_to(target)*radius<.35*outdoor_scale:
					reached = true
					break
			completed = completed and reached
			player.test_direction = Vector2.ZERO
		check("Actual lake road corner traversal " + str(reverse),completed,str(player.position))
	# Resolve traffic only when needed. Holding its node while visiting other
	# districts would correctly become invalid after the original chunk unloads.
	world.call("teleport_to", "counseling")
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	await wait_for_detail(world, "counseling")
	var traffic: Node3D = detail_node(world, "counseling", "CityTraffic")
	check("City traffic is available after its streaming region reloads", traffic != null)
	if traffic == null or traffic.get_child_count() == 0:
		finish_checks(world)
		return
	var car: Node3D = traffic.get_child(0) as Node3D
	player.teleport(preload("res://scripts/world_routes.gd").directions()[5],radius+.8)
	var car_start: Vector3 = car.position
	traffic.call("update_traffic",1.0)
	check("Cars advance along the city route",car.position.distance_to(car_start)>1.0)
	var progress: float = float(car.get_meta("progress"))
	var next_point: Vector2 = traffic.call("sample_route",progress+2.0) as Vector2
	player.position = authored_surface(Vector3.UP,next_point,radius+.4)
	traffic.call("update_traffic",1.0)
	check("Traffic yields to the player",is_equal_approx(progress,float(car.get_meta("progress"))))
	var traffic_on_road: bool = true
	var bridge_clearance: float = INF
	for i: int in range(100):
		var p: Vector2 = traffic.call("sample_route",float(i)*1.1) as Vector2
		var n: Vector3 = authored_surface(Vector3.UP,p,radius).normalized()
		traffic_on_road = traffic_on_road and not player.ground_at(n).is_empty()
		for j: int in range(21):
			bridge_clearance = minf(bridge_clearance,n.angle_to(bridge_a.slerp(bridge_b,float(j)/20.0))*radius)
	check("Traffic route stays on the city surface",traffic_on_road)
	check("Cars do not intersect the Sakura bridge",bridge_clearance>2.2*outdoor_scale,str(bridge_clearance))
	player.teleport(Vector3.UP, radius + 0.4)
	player.allow_test_input = true
	player.test_direction = Vector2(0, -1)
	player.test_running = true
	var start: Vector3 = player.position
	for i: int in range(100):
		await physics_frame
	check("Walk/run advances through street seams", player.position.distance_to(start) > 8.0 and player.position.length() >= radius, str(player.position))
	player.test_direction = Vector2.ZERO
	for i: int in range(30):
		await physics_frame
	var idle_position: Vector3 = player.position
	for i: int in range(180):
		await physics_frame
	check("Standing still does not drift", player.position.distance_to(idle_position) < 0.002, str(player.position.distance_to(idle_position)))
	# Test the southwest coast; the northeast now has the Sakura bridge.
	var edge_meters: float = 0.0
	for i: int in range(1,601):
		var meters: float = float(i) * .5*outdoor_scale
		var angle: float = meters / radius
		var normal: Vector3 = Vector3.UP * cos(angle) + Vector3(-1,0,-1).normalized() * sin(angle)
		if player.ground_at(normal).is_empty():
			edge_meters = meters
			break
	check("Shore test finds a real water boundary outside the town core",edge_meters > 15.0*outdoor_scale and edge_meters < 300.0*outdoor_scale)
	var shore_angle: float = (edge_meters - 2.0) / radius
	var shore_start: Vector3 = Vector3.UP * cos(shore_angle) + Vector3(-1,0,-1).normalized() * sin(shore_angle)
	var shore_ground: Dictionary = player.ground_at(shore_start)
	player.teleport(shore_start, (shore_ground.position as Vector3).length()+.6 if not shore_ground.is_empty() else radius+.6)
	player.heading = Vector3(-1, 0, -1).slide(shore_start).normalized()
	player.test_direction = Vector2(0, -1)
	var shore_safe: bool = true
	for i: int in range(450):
		await physics_frame
		shore_safe = shore_safe and not player.ground_at(player.position.normalized()).is_empty()
	check("Cannot walk from land onto ocean", shore_safe and player.position.normalized().angle_to(Vector3.UP)*radius <= edge_meters+.5, str(player.position))
	player.test_direction = Vector2.ZERO
	# Isolate gravity over the same quarter-globe arc as adjacent district
	# centres. Real roads and bridge collisions have a separate timed fixture.
	player.land_only = false
	var original_mask: int = player.collision_mask
	player.collision_mask = 2
	player.teleport(Vector3.UP, radius + 0.025)
	player.test_direction = Vector2(0, -1)
	var lowest: float = INF
	var highest: float = 0.0
	var continuity: float = 1.0
	var previous_heading: Vector3 = player.heading
	var travel_meters: float = radius * PI * .5
	var route_frames: int = ceili(travel_meters/player.run_speed*30.0)
	for i: int in range(route_frames):
		await physics_frame
		lowest = minf(lowest, player.position.length())
		highest = maxf(highest, player.position.length())
		continuity = minf(continuity, previous_heading.dot(player.heading))
		previous_heading = player.heading
	check("Long tiny-world traversal stays grounded", lowest > radius - 0.1 and highest < radius + 0.15, "min=%f max=%f" % [lowest, highest])
	check("Long tiny-world traversal has no heading flip", continuity > 0.9999, str(continuity))
	var traversed: float = player.position.normalized().angle_to(Vector3.UP)*radius
	var maximum_tick_meters: float = player.run_speed * Engine.time_scale / Engine.physics_ticks_per_second
	check("Completed one adjacent-centre arc through the tiny globe's curved horizon", absf(traversed-travel_meters)<2.0 and player.position.normalized().angle_to(Vector3.UP)<(travel_meters+maximum_tick_meters)/radius+.0001, "actual=%f expected=%f maximum_tick=%f" % [traversed,travel_meters,maximum_tick_meters])
	player.test_direction = Vector2.ZERO
	player.land_only = true
	player.collision_mask = original_mask
	# Minimap must follow every real station arrival on the complete sphere.
	var minimap: Control = (world.get("hud") as CanvasLayer).get("minimap") as Control
	for station: Dictionary in world.get("layout").stations:
		world.call("teleport_to",str(station.id))
		check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
		minimap.call("refresh")
		var projected: Vector2 = minimap.call("project_point",player.position.normalized()) as Vector2
		check("Minimap centres player at " + str(station.id),projected.distance_to(minimap.size*.5)<.01)
		var reference: Vector3 = (minimap.get("map_forward") as Vector3)
		var arrow_before: Vector2 = minimap.get("arrow_heading_2d") as Vector2
		player.visual.rotation.y += PI*.5
		minimap.call("refresh")
		var arrow_after: Vector2 = minimap.get("arrow_heading_2d") as Vector2
		check("Minimap frame stays fixed and arrow follows character at " + str(station.id),reference.dot(minimap.get("map_forward") as Vector3)>.9999 and absf(arrow_before.dot(arrow_after))<.01)
	world.call("set_overview",true)
	press.button_index = MOUSE_BUTTON_LEFT
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.pressed = true
	world.call("_unhandled_input",press)
	yaw_before = float(world.get("orbit_yaw"))
	world.call("_input",motion)
	check("Left hold rotates overview",bool(world.get("dragging_view")) and absf(float(world.get("orbit_yaw"))-yaw_before)>.3)
	press.pressed = false
	world.call("_input",press)
	yaw_before = float(world.get("orbit_yaw"))
	world.call("_input",motion)
	check("Left release stops rotation",not bool(world.get("dragging_view")) and is_equal_approx(yaw_before,float(world.get("orbit_yaw"))))
	world.call("set_overview",false)
	check("Requested destination becomes ready for roaming", await StartupFixture.wait_roaming(world, self))
	press.pressed = true
	world.call("_unhandled_input",press)
	heading_before = player.heading
	world.call("_input",motion)
	check("Left hold rotates roaming camera",heading_before.dot(player.heading)<.95)
	world.call("_notification",MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("Focus loss releases left drag",not bool(world.get("dragging_view")))
	finish_checks(world)

func finish_checks(world: Node3D) -> void:
	var output: Dictionary = {"passed":failures == 0,"failed":failures,"checks":checks}
	var output_path: String = "res://../deliverables/performance/world-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var file: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	file.close()
	print(JSON.stringify(output))
	for audio: Node in world.find_children("*","AudioStreamPlayer",true,false):
		(audio as AudioStreamPlayer).stop()
	await create_timer(.15).timeout
	world.free()
	# Region switches release obsolete chunks with queue_free. Let the final
	# deferred deletions drain before shutting down the test's SceneTree.
	await process_frame
	await process_frame
	quit(0 if failures == 0 else 1)

func wait_for_detail(world: Node3D, id: String) -> void:
	var streaming: Node = world.get("streaming") as Node
	var player: Node3D = world.get("player") as Node3D
	streaming.call("pin_position", player.global_position)
	var frames: int = 0
	var regions: Dictionary = streaming.get("_regions") as Dictionary
	while not bool(regions[id].ready) and frames < 2400:
		await process_frame
		frames += 1
	check("Streaming region ready: " + id, bool(regions[id].ready), str(frames) + " frames")

func detail_node(world: Node3D, id: String, pattern: String) -> Node3D:
	var streaming: Node = world.get("streaming") as Node
	var regions: Dictionary = streaming.get("_regions") as Dictionary
	for chunk: Node3D in regions[id].roots:
		var found: Node3D = chunk.find_child(pattern, true, false) as Node3D
		if found != null:
			return found
	return null

func check_ocean_chunks(world: Node3D, player: PlanetPlayer, radius: float) -> void:
	# Audit the generated animated actors one chunk at a time. This test does
	# not reintroduce the removed all-ocean dependency into the production world.
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/streaming/catalog.json")) as Dictionary
	var sea_safe: bool = true
	var hulls_safe: bool = true
	var boats_travel: bool = true
	var fish_underwater: bool = true
	var fish_move: bool = false
	var boat_shore_errors: Array[Dictionary] = []
	var hull_shore_errors: Array[Dictionary] = []
	var boats: int = 0
	var fish: int = 0
	for region: Dictionary in catalog.districts:
		if not str(region.id).begins_with("ocean_"):
			continue
		for row: Dictionary in region.chunks:
			var packed: PackedScene = ResourceLoader.load(str(row.path), "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
			var chunk: Node3D = packed.instantiate() as Node3D
			chunk.process_mode = Node.PROCESS_MODE_DISABLED
			Outdoor.apply_to_root(chunk,outdoor_scale)
			world.add_child(chunk)
			for life: Node3D in chunk.get_children():
				if not life.has_method("update_life"):
					continue
				var starts: Dictionary = {}
				var maximum_travel: Dictionary = {}
				var hull_samples: Dictionary = {}
				for actor: Node3D in life.get_children():
					if str(actor.get_meta("kind", "")) == "boat":
						boats += 1
						starts[actor.get_instance_id()] = actor.position
						maximum_travel[actor.get_instance_id()] = 0.0
						hull_samples[actor.get_instance_id()] = boat_footprint_samples(actor)
					elif str(actor.get_meta("kind", "")) == "fish":
						fish += 1
				# Cover a complete offshore orbit, not only the first 30 seconds.
				# Shrinking the globe can otherwise hide a late shore intersection.
				for step: int in range(120):
					var sample_time: float = float(step) / 120.0 * TAU / 0.009
					life.call("update_life", sample_time)
					for actor: Node3D in life.get_children():
						if str(actor.get_meta("kind", "")) == "boat":
							var hit: Dictionary = player.ground_at(actor.global_position.normalized())
							sea_safe = sea_safe and hit.is_empty()
							if not hit.is_empty() and boat_shore_errors.size() < 8:
								boat_shore_errors.append({"actor": str(actor.name), "time": sample_time, "position": str(actor.global_position), "ground": str((hit.collider as Node).get_path())})
							maximum_travel[actor.get_instance_id()] = maxf(float(maximum_travel[actor.get_instance_id()]), actor.position.distance_to(starts[actor.get_instance_id()] as Vector3))
							# A centre safely offshore does not prove the full-sized
							# bow and stern fit the tiny world's narrow sea gaps.
							for local_point: Vector3 in hull_samples[actor.get_instance_id()]:
								var hull_hit: Dictionary = player.ground_at(actor.to_global(local_point).normalized())
								hulls_safe = hulls_safe and hull_hit.is_empty()
								if not hull_hit.is_empty() and hull_shore_errors.size()<8:
									hull_shore_errors.append({"actor":str(actor.name),"time":sample_time,"local_footprint_point":str(local_point),"ground":str((hull_hit.collider as Node).get_path())})
						elif str(actor.get_meta("kind", "")) == "fish":
							fish_underwater = fish_underwater and actor.visible and actor.global_position.length() < radius-.3*outdoor_scale and actor.global_position.length() > radius-1.0*outdoor_scale
							fish_move = fish_move or actor.global_position.distance_to((actor.get_meta("centre") as Vector3)*radius)>1.0*outdoor_scale
				for actor: Node3D in life.get_children():
					if starts.has(actor.get_instance_id()):
						boats_travel = boats_travel and float(maximum_travel[actor.get_instance_id()]) > 1.0
			chunk.free()
	check("Generated ocean chunks retain seven boats and twenty-eight fish", boats == 7 and fish == 28, str([boats, fish]))
	check("Boat routes stay over water for one full motion cycle", sea_safe and boats == 7, JSON.stringify(boat_shore_errors))
	check("Full-sized boat bows sterns and sides clear land for one motion cycle", hulls_safe and boats == 7, JSON.stringify(hull_shore_errors))
	check("Boats actually travel", boats_travel and boats == 7)
	check("Fish schools swim below the ocean surface", fish_underwater and fish_move and fish == 28)

func boat_footprint_samples(actor: Node3D) -> Array[Vector3]:
	var footprint: Rect2
	var initialized: bool = false
	for mesh: MeshInstance3D in actor.find_children("*","MeshInstance3D",true,false):
		if mesh.mesh == null:
			continue
		var relative: Transform3D = actor.global_transform.affine_inverse()*mesh.global_transform
		var bounds: AABB = relative*mesh.get_aabb()
		var flat: Rect2 = Rect2(Vector2(bounds.position.x,bounds.position.z),Vector2(bounds.size.x,bounds.size.z))
		footprint = footprint.merge(flat) if initialized else flat
		initialized = true
	var samples: Array[Vector3] = [Vector3.ZERO]
	# Nine conservative footprint points include both ends, port/starboard
	# sides and corners. Height is the waterline, not the mast's bounding box.
	for x: float in [footprint.position.x,footprint.get_center().x,footprint.end.x]:
		for z: float in [footprint.position.y,footprint.get_center().y,footprint.end.y]:
			samples.append(Vector3(x,0.0,z))
	return samples

func joined_surface_covered(world: Node3D,points: Array[Vector3],radius: float,height: float,width: float,closed: bool) -> bool:
	var sides: Array[Vector3] = PlanetGeometry.path_sides(points,closed)
	var covered: bool = true
	for i: int in range(0 if closed else 1,points.size() if closed else points.size()-1):
		for fraction: float in [-.9,-.6,-.3,.3,.6,.9]:
			var normal: Vector3 = (points[i]*(radius+height)+sides[i]*width*.5*fraction).normalized()
			var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal*(radius+1),normal*radius,1)
			var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or (hit.position as Vector3).length()<radius+height-.003:
				print("CORNER_MISS vertex=",i," fraction=",fraction," expected=",radius+height," actual=",-1.0 if hit.is_empty() else (hit.position as Vector3).length())
				covered = false
	return covered

func authored_surface(up: Vector3, offset: Vector2, physical_radius: float) -> Vector3:
	return PlanetGeometry.surface(up,offset,authoring_radius).normalized()*physical_radius
