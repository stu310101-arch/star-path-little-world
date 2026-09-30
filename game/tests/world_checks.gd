extends SceneTree

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
	var radius: float = player.planet_radius
	check("Six distinct stations", world.get_node("Stations").get_child_count() == 6)
	var build: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
	var all_upright: bool = true
	var building_count: int = 0
	for asset: Dictionary in build.assets:
		all_upright = all_upright and float(asset.up_dot) > 0.999
		if asset.kind == "building":
			building_count += 1
	check("Six planned modern districts have 48 buildings", building_count == 48 and build.districts.size() == 6)
	check("Larger sphere without scaling the player", is_equal_approx(radius,48.0) and player.scale.is_equal_approx(Vector3.ONE))
	check("Faster walk and run",player.walk_speed >= 3.8 and player.run_speed >= 6.4)
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
			road_points.append(PlanetGeometry.surface(up,Vector2(point_data[0],point_data[1]),radius).normalized())
		check("Asphalt covers inner and outer corners " + str(index),joined_surface_covered(world,road_points,radius,.285,4.2,true))
		var path_corners_safe: bool = true
		for path_data: Array in preload("res://scripts/world_routes.gd").district_paths(data,radius):
			var path_points: Array[Vector3] = []
			for point_data: Array in path_data:
				path_points.append(PlanetGeometry.surface(up,Vector2(point_data[0],point_data[1]),radius).normalized())
			path_corners_safe = joined_surface_covered(world,path_points,radius,.26,2.2,false) and path_corners_safe
		check("Full promenade width joins at bends " + str(index),path_corners_safe)
		var visit: Vector2=Vector2(data.visit[0],data.visit[1])
		check("Ecology arrival is dry " + str(index),not player.ground_at(PlanetGeometry.surface(up,visit,radius).normalized()).is_empty())
		var paths_safe: bool=true
		for path: Array in data.paths:
			for j: int in range(path.size()-1):
				var a: Vector2=Vector2(path[j][0],path[j][1])
				var b: Vector2=Vector2(path[j+1][0],path[j+1][1])
				for k: int in range(21):
					paths_safe=paths_safe and not player.ground_at(PlanetGeometry.surface(up,a.lerp(b,float(k)/20.0),radius).normalized()).is_empty()
		check("Promenades and boardwalks continuous " + str(index),paths_safe)
		var wet_probes: int=0
		var water_blocked: bool=true
		for x: int in range(-36,37,2):
			for y: int in range(-34,35,2):
				var p: Vector2=Vector2(x,y)
				if float(ecology.call("water_distance",p,data)) < -.8 and float(ecology.call("path_distance",p,data))>2.0 and float(ecology.call("edge_distance",p,data,index))>1.0:
					wet_probes+=1
					water_blocked=water_blocked and player.ground_at(PlanetGeometry.surface(up,p,radius).normalized()).is_empty()
		check("Lake and river water has no hidden land " + str(index),wet_probes>0 and water_blocked,str(wet_probes))
	check("All six urban arrangements differ",signatures.size()==6)
	var authored_planting: bool = bool(build.ecology.get("authored_planting",false)) and int(build.ecology.districts)==6
	for district_planting: Dictionary in build.ecology.get("planting_groups",[]):
		authored_planting = authored_planting and (district_planting.groups as Array).size()>=3 and not (district_planting.view_windows as Array).is_empty()
	check("Six reserves use authored groves with open view windows and preserved garden specimens",authored_planting and int(build.ecology.get("pocket_specimens_preserved",0))==18,str(build.ecology))
	var life: Node3D = world.get_node("Globe/OceanLife") as Node3D
	var sea_safe: bool = true
	var fish_leap: bool = false
	var fish_dive: bool = false
	var boat_start: Vector3 = (life.get_child(0) as Node3D).position
	for step: int in range(60):
		life.call("update_life",float(step)*0.5)
		for actor: Node in life.get_children():
			var spatial: Node3D = actor as Node3D
			if actor.get_meta("kind","") == "boat":
				sea_safe = sea_safe and player.ground_at(spatial.position.normalized()).is_empty()
			elif actor.get_meta("kind","") == "fish":
				fish_leap = fish_leap or (spatial.visible and spatial.position.length()>radius+1.0)
				fish_dive = fish_dive or not spatial.visible
	check("Boat routes stay over water",sea_safe)
	check("Boats actually travel",(life.get_child(0) as Node3D).position.distance_to(boat_start)>1.0)
	check("Fish schools leap and dive",fish_leap and fish_dive)
	var sources: PackedStringArray = player.animator.get_animation_list()
	check("Character has Walk Run and JumpDown", sources.has("Walk") and sources.has("Run") and sources.has("JumpDown"), str(sources))
	var press: InputEventMouseButton = InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	world.call("_input",press)
	var yaw_before: float = world.get("orbit_yaw")
	var motion: InputEventMouseMotion = InputEventMouseMotion.new()
	motion.relative = Vector2(100,40)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	world.call("_input",motion)
	check("Right drag rotates overview horizontally and vertically",absf(float(world.get("orbit_yaw"))-yaw_before)>0.3 and float(world.get("orbit_pitch"))>0.7)
	press.pressed = false
	world.call("_input",press)
	check("Right release restores cursor",not bool(world.get("dragging_view")))
	world.call("set_overview",false)
	press.pressed = true
	world.call("_input",press)
	var heading_before: Vector3 = player.heading
	world.call("_input",motion)
	check("Right drag rotates character camera and pitch",heading_before.dot(player.heading)<0.95 and float(world.get("near_pitch"))>0.65)
	press.pressed = false
	world.call("_input",press)
	for station: Node in world.get_node("Stations").get_children():
		world.call("teleport_to", str(station.name))
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
		var normal: Vector3 = PlanetGeometry.surface(Vector3(up[0],up[1],up[2]),Vector2(offset[0],offset[1]),radius).normalized()
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal * (radius + 2.0), normal * (radius - 0.5), 1)
		var hit: Dictionary = world.get_world_3d().direct_space_state.intersect_ray(query)
		road_ok = road_ok and not hit.is_empty()
		if not hit.is_empty():
			road_ok = road_ok and (hit.position as Vector3).length() > radius + 0.15
	check("Road tops have matching collisions", road_ok)
	# Test each furnished street with real player collision, not only ray samples.
	player.allow_test_input = true
	player.test_running = true
	for district: Dictionary in world.get("layout").stations:
		var normal_data: Array = district.normal
		var normal: Vector3 = Vector3(normal_data[0],normal_data[1],normal_data[2])
		player.teleport(normal,radius + 0.6)
		player.test_direction = Vector2.ZERO
		for i: int in range(20):
			await physics_frame
		var street_start: Vector3 = player.position
		player.test_direction = Vector2(0,-1)
		for i: int in range(40):
			await physics_frame
		check("Clear street " + str(district.id),player.position.distance_to(street_start) > 3.5 and player.position.length() > radius)
	player.test_direction = Vector2.ZERO
	world.call("teleport_to", "counseling")
	for i: int in range(30):
		await physics_frame
	var before: Vector3 = player.position
	world.call("open_station", "counseling")
	check("Entrance begins the existing jump clip",bool(world.get("entering")) and player.active_clip == &"JumpDown")
	var apex: float = 0.0
	while bool(world.get("entering")):
		await process_frame
		apex = maxf(apex,player.visual.position.y)
	check("Jump rises and disappears before the panel",apex>1.0 and not player.visual.visible and bool(world.get("paused")))
	world.call("resume_world", {})
	check("Panel retains world position", before.distance_to(player.position) < 0.03)
	check("Returning restores character",player.visual.visible and not player.entering and player.visual.position.is_zero_approx())
	world.call("visit_sakura")
	for i: int in range(45):
		await physics_frame
	check("Sakura grove can be visited on foot",player.is_on_floor() and player.position.length()>radius)
	var bridge: Node3D = world.get_node("Globe/SakuraGrove/SakuraBridge") as Node3D
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
			if player.position.normalized().angle_to(to)*radius<.65:
				reached = true
				break
		check("Sakura bridge actual walk " + ("return" if reverse else "outbound"),reached,str(player.position))
		player.test_direction = Vector2.ZERO
	var grove_up: Vector3 = Vector3(.75,1,.85).normalized()
	var town_approach: Vector3 = PlanetGeometry.surface(Vector3.UP,Vector2(10,17.4),radius).normalized()
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
			for i: int in range(220):
				player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
				await physics_frame
				if player.position.normalized().angle_to(target)*radius<.48:
					reached = true
					break
			completed = completed and reached
			player.test_direction = Vector2.ZERO
		check("Continuous city to garden walk " + ("return" if reverse else "outbound"),completed,str(player.position))
	var traffic: Node3D = world.get_node("Neighborhood/counseling/CityTraffic") as Node3D
	var car: Node3D = traffic.get_child(0) as Node3D
	# Traverse an actual wetland boardwalk corner with the normal controller.
	var swamp_normal: Array=world.get("layout").stations[5].normal
	var swamp_up: Vector3=Vector3(swamp_normal[0],swamp_normal[1],swamp_normal[2])
	var wet_route: Array[Vector2]=[Vector2(18,13),Vector2(22,16),Vector2(25,20),Vector2(20,25)]
	player.teleport(PlanetGeometry.surface(swamp_up,wet_route[0],radius).normalized(),radius+.7)
	player.test_direction=Vector2.ZERO
	for j: int in range(24):
		await physics_frame
	var wet_reached: bool=true
	for point: Vector2 in wet_route.slice(1):
		var target: Vector3=PlanetGeometry.surface(swamp_up,point,radius).normalized()
		var reached: bool=false
		player.test_direction=Vector2(0,-1)
		for j: int in range(220):
			player.heading=(target*radius-player.position).slide(player.position.normalized()).normalized()
			await physics_frame
			if player.position.normalized().angle_to(target)*radius<.4:
				reached=true
				break
		wet_reached=wet_reached and reached
	player.test_direction=Vector2.ZERO
	check("Walk through wetland boardwalk turns",wet_reached,str(player.position))
	# Walk the lake-side road bend shown in the seam report in both directions.
	var lake_normal: Array = world.get("layout").stations[4].normal
	var lake_up: Vector3 = Vector3(lake_normal[0],lake_normal[1],lake_normal[2])
	for reverse: bool in [false,true]:
		var route: Array[Vector2] = [Vector2(-3,17.7),Vector2(-8,18),Vector2(-12,14.4)]
		if reverse:
			route.reverse()
		player.teleport(PlanetGeometry.surface(lake_up,route[0],radius).normalized(),radius+.7)
		for j: int in range(24):
			await physics_frame
		var completed: bool = true
		for point: Vector2 in route.slice(1):
			var target: Vector3 = PlanetGeometry.surface(lake_up,point,radius).normalized()
			var reached: bool = false
			player.test_direction = Vector2(0,-1)
			for j: int in range(180):
				player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
				await physics_frame
				if player.position.normalized().angle_to(target)*radius<.35:
					reached = true
					break
			completed = completed and reached
			player.test_direction = Vector2.ZERO
		check("Actual lake road corner traversal " + str(reverse),completed,str(player.position))
	player.teleport(Vector3.DOWN,radius+.8)
	var car_start: Vector3 = car.position
	traffic.call("update_traffic",1.0)
	check("Cars advance along the city route",car.position.distance_to(car_start)>1.0)
	var progress: float = float(car.get_meta("progress"))
	var next_point: Vector2 = traffic.call("sample_route",progress+2.0) as Vector2
	player.position = PlanetGeometry.surface(Vector3.UP,next_point,radius+.4)
	traffic.call("update_traffic",1.0)
	check("Traffic yields to the player",is_equal_approx(progress,float(car.get_meta("progress"))))
	var traffic_on_road: bool = true
	var bridge_clearance: float = INF
	for i: int in range(100):
		var p: Vector2 = traffic.call("sample_route",float(i)*1.1) as Vector2
		var n: Vector3 = PlanetGeometry.surface(Vector3.UP,p,radius).normalized()
		traffic_on_road = traffic_on_road and not player.ground_at(n).is_empty()
		for j: int in range(21):
			bridge_clearance = minf(bridge_clearance,n.angle_to(bridge_a.slerp(bridge_b,float(j)/20.0))*radius)
	check("Traffic route stays on the city surface",traffic_on_road)
	check("Cars do not intersect the Sakura bridge",bridge_clearance>2.2,str(bridge_clearance))
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
	var edge_angle: float = 0.0
	for i: int in range(1,100):
		var angle: float = float(i) * 0.01
		var normal: Vector3 = Vector3.UP * cos(angle) + Vector3(-1,0,-1).normalized() * sin(angle)
		if player.ground_at(normal).is_empty():
			edge_angle = angle
			break
	check("Shore test finds exposed water",edge_angle > 0.3 and edge_angle < 0.8)
	var shore_start: Vector3 = Vector3.UP * cos(edge_angle - 0.04) + Vector3(-1,0,-1).normalized() * sin(edge_angle - 0.04)
	player.teleport(shore_start, radius + 0.6)
	player.heading = Vector3(-1, 0, -1).slide(shore_start).normalized()
	player.test_direction = Vector2(0, -1)
	var shore_safe: bool = true
	for i: int in range(450):
		await physics_frame
		shore_safe = shore_safe and not player.ground_at(player.position.normalized()).is_empty()
	check("Cannot walk from land onto ocean", shore_safe and player.position.normalized().dot(Vector3.UP) > 0.8, str(player.position))
	player.test_direction = Vector2.ZERO
	# Isolate spherical gravity from props: core layer only, one full great circle through both poles.
	player.land_only = false
	player.collision_mask = 2
	player.teleport(Vector3.UP, radius + 0.025)
	player.test_direction = Vector2(0, -1)
	var lowest: float = INF
	var highest: float = 0.0
	var continuity: float = 1.0
	var previous_heading: Vector3 = player.heading
	var orbit_frames: int = ceili(TAU*radius/player.run_speed*30.0)
	for i: int in range(orbit_frames):
		await physics_frame
		lowest = minf(lowest, player.position.length())
		highest = maxf(highest, player.position.length())
		continuity = minf(continuity, previous_heading.dot(player.heading))
		previous_heading = player.heading
	check("Full sphere traversal stays grounded", lowest > radius - 0.1 and highest < radius + 0.15, "min=%f max=%f" % [lowest, highest])
	check("Pole crossing has no heading flip", continuity > 0.99, str(continuity))
	check("Completed a full great circle", player.position.normalized().dot(Vector3.UP) > 0.9, str(player.position))
	# Minimap must follow real station arrivals, including both poles.
	var minimap: Control = (world.get("hud") as CanvasLayer).get("minimap") as Control
	for station: Dictionary in world.get("layout").stations:
		world.call("teleport_to",str(station.id))
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
	press.pressed = true
	world.call("_unhandled_input",press)
	heading_before = player.heading
	world.call("_input",motion)
	check("Left hold rotates roaming camera",heading_before.dot(player.heading)<.95)
	world.call("_notification",MainLoop.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check("Focus loss releases left drag",not bool(world.get("dragging_view")))
	var output: Dictionary = {"passed":failures == 0,"failed":failures,"checks":checks}
	var file: FileAccess = FileAccess.open("res://tests/results.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "\t"))
	print(JSON.stringify(output))
	quit(0 if failures == 0 else 1)

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
