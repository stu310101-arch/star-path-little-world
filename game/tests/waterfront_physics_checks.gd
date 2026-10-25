extends SceneTree

## Exercise the shipped scene and controller, including permanent streamed
## collision. A mathematically correct source mesh is insufficient: the detail
## chunks, base collisions and authored map must occupy the SAME coordinates.
## Run with --fixed-fps 60: the production controller still receives 1/60 s
## physics steps, while long ocean crossings are not paced by wall-clock time.
const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
const Outdoor = preload("res://scripts/outdoor_scale.gd")
const OUTPUT: String = "res://../deliverables/world-revision/waterfront-physics.json"
var world: Node3D
var player: PlanetPlayer
var radius: float
var authoring_radius: float = 60.0
var outdoor_scale: float = .4
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label + ": " + str(evidence))
	elif label.begins_with("Actual bridge crossing"):
		print("CROSSING_OK ",label," ",evidence)

func run() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	for name: String in ["Globe", "Neighborhood", "Stations"]:
		check("Saved scene uses canonical coordinates: " + name, (world.get_node(name) as Node3D).transform.is_equal_approx(Transform3D.IDENTITY))
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	# HUD rendering is independent of physics and can invalidate headless
	# timing through full-world minimap projection. Keep the shipped collision
	# and controller; stop only presentation while exercising movement.
	(world.get("hud") as Node).process_mode=Node.PROCESS_MODE_DISABLED
	# World._ready applies the saved 90 FPS display cap. Remove it only after
	# that initialization; --fixed-fps supplies deterministic 1/60 s deltas.
	Engine.max_fps = 0
	player = world.get("player") as PlanetPlayer
	radius = player.planet_radius
	authoring_radius = Outdoor.authored_radius(world.get("layout") as Dictionary)
	outdoor_scale = Outdoor.factor(world.get("layout") as Dictionary)
	# Animation assets are deliberately unnecessary: the unmodified production
	# movement/capsule run on every physics tick without any manual movement.
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	player.controls_enabled = false
	player.allow_test_input = true
	player.set_physics_process(true)
	await ticks(2)
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var layout: Dictionary = world.get("layout") as Dictionary
	var bridges_only: bool=OS.get_cmdline_user_args().has("--bridges-only")
	if not bridges_only:
		for index: int in range(districts.size()):
			var data: Dictionary = districts[index]
			var up: Vector3 = Vector3(layout.stations[index].normal[0],layout.stations[index].normal[1],layout.stations[index].normal[2])
			check_water(data, up)
			await check_shore(data, up)
			await check_boardwalks(data, up)
	await check_interdistrict_bridges()
	check_ocean()
	player.test_direction = Vector2.ZERO
	var report: Dictionary = {"passed":failures == 0,"failures":failures,"checks":checks,"physics_hz":60,"bridges_only":bridges_only,"global_bridge_sampling":"Three sections per bridge (each bank and midpoint), capped at 15 m or 20% of the span, in both directions: 72 controller traversals. Entire floor continuity is separately probed at <=4 m intervals by spherical_route_checks.","fixture":"Actual world.tscn permanent collision and production PlanetPlayer; no added floor or obstacle, no manual movement. HUD presentation disabled for the headless physics fixture."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT.get_base_dir()))
	FileAccess.open(OUTPUT,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WATERFRONT_PHYSICS checks=", checks.size(), " failures=", failures)
	quit(1 if failures > 0 else 0)

func ticks(count: int) -> void:
	for _i: int in range(count):
		await physics_frame

func normal_at(up: Vector3, p: Vector2) -> Vector3:
	return Geo.surface(up,p,authoring_radius).normalized()

func path_distance(p: Vector2, paths: Array) -> float:
	var result: float = INF
	for path: Array in paths:
		for i: int in range(path.size()-1):
			var a: Vector2 = Waterfront.v2(path[i])
			var b: Vector2 = Waterfront.v2(path[i+1])
			var q: Vector2 = a+(b-a)*clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
			result = minf(result,p.distance_to(q))
	return result

func water_regions(data: Dictionary) -> Array[Dictionary]:
	var regions: Array[Dictionary] = [{"label":"city","bounds":Rect2(-36,-32,72,64),"step":1}]
	var index: int = 0
	for water: Dictionary in Biomes.spec(str(data.station)).get("waters",[]):
		var bounds: Rect2
		var step: float=2.0
		if str(water.kind)=="lake":
			var centre: Vector2 = Waterfront.v2(water.center)
			var size: Vector2 = Waterfront.v2(water.size)
			bounds=Rect2(centre-size,size*2.0).grow(5.0)
			# A 2 m lattice can miss the safe entry of a 3 m-wide small lake.
			if minf(size.x,size.y)<3.0: step=.5
		else:
			bounds=Rect2(Waterfront.v2(water.points[0]),Vector2.ZERO)
			for point: Array in water.points: bounds=bounds.expand(Waterfront.v2(point))
			bounds=bounds.grow(float(water.width)+4.0)
			if float(water.width)<1.5: step=.5
		regions.append({"label":"biome-water-"+str(index),"bounds":bounds,"step":step})
		index+=1
	return regions

func region_points(region: Dictionary) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var bounds: Rect2 = region.bounds
	var step: float=float(region.step)
	var start:=Vector2(floorf(bounds.position.x),floorf(bounds.position.y))
	for x: int in range(floori((ceilf(bounds.end.x)-start.x)/step)+1):
		for y: int in range(floori((ceilf(bounds.end.y)-start.y)/step)+1):
			points.append(start+Vector2(x,y)*step)
	return points

func check_water(data: Dictionary, up: Vector3) -> void:
	var paths: Array = Routes.district_paths(data,authoring_radius)
	for region: Dictionary in water_regions(data):
		var count: int = 0
		var unexpected: Array[Dictionary] = []
		for point: Vector2 in region_points(region):
			if Waterfront.water_distance(point,data) >= -.6 or path_distance(point,paths) < 2.0:
				continue
			count += 1
			var hit: Dictionary = player.ground_at(normal_at(up,point))
			if not hit.is_empty() and unexpected.size() < 8:
				unexpected.append({"point":[point.x,point.y],"collider":str((hit.collider as Node).get_path())})
		check("Freshwater has no hidden walkable ground: " + str(data.station)+"/"+str(region.label), count > 0 and unexpected.is_empty(), {"probes":count,"unexpected":unexpected})

func prepare(normal: Vector3) -> void:
	player.test_direction = Vector2.ZERO
	player.test_running = false
	var ground: Dictionary = player.ground_at(normal)
	var feet_radius: float = (ground.position as Vector3).length()+.44 if not ground.is_empty() else radius+.7
	player.teleport(normal,feet_radius)
	await ticks(35)

func steer(target: Vector3) -> void:
	player.heading = (target*radius-player.global_position).slide(player.global_position.normalized()).normalized()
	player.test_direction = Vector2(0,-1)

func check_shore(data: Dictionary, up: Vector3) -> void:
	# Pick a shoreline using authored contours, then approach it from the dry
	# bank. Selection does not depend on the collider being correct.
	for region: Dictionary in water_regions(data):
		await check_shore_region(data,up,region)

func check_shore_region(data: Dictionary,up: Vector3,region: Dictionary) -> void:
	var paths: Array = Routes.district_paths(data,authoring_radius)
	var candidate: Dictionary = {}
	var label: String = str(data.station)+"/"+str(region.label)
	for wet: Vector2 in region_points(region):
		if Waterfront.water_distance(wet,data) > -.75 or path_distance(wet,paths) < 3.0:
			continue
		for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
			var dry: Vector2 = wet+direction*3.0
			if Waterfront.water_distance(dry,data) < .7 or path_distance(dry,paths) < 2.0:
				continue
			if player.ground_at(normal_at(up,dry)).is_empty():
				continue
			candidate = {"start":dry,"target":wet}
			break
		if not candidate.is_empty(): break
	check("Locate unbridged freshwater bank: " + label, not candidate.is_empty())
	if candidate.is_empty(): return
	await prepare(normal_at(up,candidate.start))
	player.test_running = true
	var target: Vector3 = normal_at(up,candidate.target)
	var stays_dry: bool = true
	for _frame: int in range(110):
		steer(target)
		await physics_frame
		stays_dry = stays_dry and not player.ground_at(player.global_position.normalized()).is_empty()
	player.test_direction = Vector2.ZERO
	check("Running toward water stops on the real bank: " + label, stays_dry and player.is_on_floor() and player.global_position.normalized().angle_to(target)*radius > .5*player.avatar_scale, {"dry_all_frames":stays_dry,"grounded":player.is_on_floor(),"distance_to_water_target":player.global_position.normalized().angle_to(target)*radius,"minimum_clearance_m":.5*player.avatar_scale})

func check_boardwalks(data: Dictionary, up: Vector3) -> void:
	var run_index: int = 0
	for path: Array in Routes.district_paths(data,authoring_radius):
		var route: Array[Dictionary] = Waterfront.samples(up,path,data,authoring_radius)
		var start: int = -1
		for i: int in range(route.size()):
			var wet: bool = i < route.size()-1 and bool(route[i].wet)
			if wet and start < 0: start = i
			if not wet and start >= 0:
				var deepest: int = start
				for j: int in range(start,i):
					if Waterfront.water_distance(route[j].p,data) < Waterfront.water_distance(route[deepest].p,data): deepest = j
				if Waterfront.water_distance(route[deepest].p,data) < -.3:
					var label: String = str(data.station)+"/"+str(run_index)
					var waypoints: Array[Vector3] = [route[start].normal]
					for j: int in range(start+1,i):
						if bool(route[j].corner): waypoints.append(route[j].normal)
					waypoints.append(route[i].normal)
					for reverse: bool in [false,true]:
						var walk: Array[Vector3] = waypoints.duplicate()
						if reverse: walk.reverse()
						await walk_route(label+(" return" if reverse else " outbound"),walk)
					await check_rail(label,route[deepest])
					run_index += 1
				start = -1

func walk_route(label: String, waypoints: Array[Vector3]) -> void:
	await prepare(waypoints[0])
	var completed: bool = player.is_on_floor()
	var floor_frames: int = 0
	var total_frames: int = 0
	var travelled: float = 0.0
	var maximum_floor_step: float = 0.0
	for target: Vector3 in waypoints.slice(1):
		var reached: bool = false
		var distance: float = player.global_position.normalized().angle_to(target)*radius
		var frame_budget: int = ceili(distance/player.walk_speed*60.0*1.6)+120
		for _frame: int in range(frame_budget):
			var old: Vector3 = player.global_position
			steer(target)
			await physics_frame
			travelled+=player.global_position.distance_to(old)
			maximum_floor_step=maxf(maximum_floor_step,absf(player.global_position.length()-old.length()))
			total_frames += 1
			if player.is_on_floor(): floor_frames += 1
			if player.global_position.normalized().angle_to(target)*radius < .25*outdoor_scale:
				reached = true
				break
		completed = completed and reached
		if not reached: break
	player.test_direction = Vector2.ZERO
	check("Actual bridge crossing " + label, completed and floor_frames >= total_frames-2, {"grounded_frames":floor_frames,"total_frames":total_frames,"position":str(player.global_position),"travelled_m":travelled,"maximum_radial_step_m":maximum_floor_step})

func check_rail(label: String, sample: Dictionary) -> void:
	var normal: Vector3 = sample.normal
	var side: Vector3 = (sample.side as Vector3).slide(normal).normalized()
	for direction: float in [-1.0,1.0]:
		await prepare(normal)
		# Turn off only the shore guard so this proves physical rail contact;
		# otherwise a missing rail could be hidden by the dry-ground boundary.
		player.land_only = false
		player.test_running = true
		var target: Vector3 = (normal*radius+side*direction*3.0).normalized()
		var start_position: Vector3 = player.global_position
		for _frame: int in range(70):
			steer(target)
			await physics_frame
		player.test_direction = Vector2.ZERO
		var lateral: float = absf(player.global_position.normalized().dot(side)*radius/player.global_position.normalized().dot(normal))
		# Keep the authored ray's angular span when scaling the whole world.
		# A three-physical-metre chord dips below the now .04 m rail beam.
		var rail_target: Vector3 = (normal*radius+side*direction*3.0*outdoor_scale).normalized()
		var rail_query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(normal*(radius+(Waterfront.HEIGHT+.47)*outdoor_scale),rail_target*(radius+(Waterfront.HEIGHT+.47)*outdoor_scale),8)
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(rail_query)
		var rail_edge: Vector3 = Waterfront.at(sample,authoring_radius,Waterfront.HEIGHT,direction*(Waterfront.WIDTH*.5+.11))
		# The centre can approach a rail more closely with the smaller capsule.
		# Retain the original relative padding and physical contact checks.
		var expected_limit: float = normal.angle_to(rail_edge.normalized())*radius-.15*player.avatar_scale
		check("Visible boardwalk rail is solid " + label+" side "+str(direction), not hit.is_empty() and lateral < expected_limit and player.is_on_floor(), {"lateral_metres":lateral,"expected_limit":expected_limit,"grounded":player.is_on_floor(),"rail_hit":str((hit.collider as Node).name) if not hit.is_empty() else "none","travelled":player.global_position.distance_to(start_position)})
		player.land_only = true

func check_interdistrict_bridges() -> void:
	check("Twelve global bridges exercised in both directions",Routes.bridge_edges().size()==12)
	for edge: Vector2i in Routes.bridge_edges():
		var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge,authoring_radius)
		var span: float=endpoints[0].angle_to(endpoints[1])*radius
		var fraction: float=minf(15.0/span,.2)
		var section: int=0
		for start: float in [0.0,(1.0-fraction)*.5,1.0-fraction]:
			var sample: Array[Vector3]=[endpoints[0].slerp(endpoints[1],start),endpoints[0].slerp(endpoints[1],start+fraction)]
			await walk_route("interdistrict %d-%d section %d outbound" % [edge.x,edge.y,section],sample)
			sample.reverse()
			await walk_route("interdistrict %d-%d section %d return" % [edge.x,edge.y,section],sample)
			section+=1
		await check_sea_bridge_rail(edge,endpoints)

func check_sea_bridge_rail(edge: Vector2i,endpoints: Array[Vector3]) -> void:
	var normal: Vector3=endpoints[0].slerp(endpoints[1],.5).normalized()
	var side: Vector3=endpoints[0].cross(endpoints[1]).normalized()
	for direction: float in [-1.0,1.0]:
		await prepare(normal)
		player.land_only=false
		player.test_running=true
		var target: Vector3=(normal*radius+side*direction*4.0).normalized()
		for _frame: int in range(90):
			steer(target)
			await physics_frame
		player.test_direction=Vector2.ZERO
		var lateral: float=absf(player.global_position.normalized().dot(side)*radius/player.global_position.normalized().dot(normal))
		var rail_target: Vector3=(normal*radius+side*direction*4.0*outdoor_scale).normalized()
		var ray: PhysicsRayQueryParameters3D=PhysicsRayQueryParameters3D.create(normal*(radius+.9*outdoor_scale),rail_target*(radius+.9*outdoor_scale),8)
		var hit: Dictionary=player.get_world_3d().direct_space_state.intersect_ray(ray)
		check("Global bridge rail holds without shore guard %d-%d side %d" % [edge.x,edge.y,int(direction)],not hit.is_empty() and lateral<1.3*outdoor_scale-.18*player.avatar_scale and player.is_on_floor(),{"lateral_m":lateral,"grounded":player.is_on_floor(),"collider":str((hit.collider as Node).get_path()) if not hit.is_empty() else "none"})
		player.land_only=true

func check_ocean() -> void:
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var axes: Array[Vector3]=Routes.directions()
	var absent: bool=true
	for x: float in [-1.0,1.0]:
		for y: float in [-1.0,1.0]:
			for z: float in [-1.0,1.0]:
				if x>0.0 and y>0.0 and z>0.0:
					continue
				absent=absent and player.ground_at(Vector3(x,y,z).normalized()).is_empty()
	check("Open ocean in the seven uninhabited globe gaps is unwalkable",absent)
	check("The eighth globe gap contains the walkable Sakura garden",not player.ground_at(Vector3.ONE.normalized()).is_empty())
	for edge: Vector2i in Routes.bridge_edges():
		var endpoints: Array[Vector3]=Routes.bridge_endpoints(edge,authoring_radius)
		var middle: Vector3=endpoints[0].slerp(endpoints[1],.5).normalized()
		var side: Vector3=endpoints[0].cross(endpoints[1]).normalized()
		for sign_side: float in [-1.0,1.0]:
			# Eight metres sideways can reach the opposite headland beside a
			# short estuary bridge. Select sea from the authored coastline, never
			# from an absent collider, so hidden walkable water still fails.
			var selected: Vector3=Vector3.ZERO
			var selected_offset: float=0.0
			var selected_clearance: float=INF
			for offset: float in [3.5,4.5,6.0,8.0]:
				var n: Vector3=(middle*radius+side*sign_side*offset*outdoor_scale).normalized()
				var clearance: float=INF
				for i: int in range(districts.size()):
					if n.dot(axes[i])>.55:
						clearance=minf(clearance,-Routes.coast_distance(Routes.local_point(n,axes[i],authoring_radius),districts[i],i))
				if clearance>1.0:
					selected=n;selected_offset=offset*outdoor_scale;selected_clearance=clearance
					break
			var hit: Dictionary={} if selected.is_zero_approx() else player.ground_at(selected)
			check("Sea beside global bridge has no floor %d-%d side %d" % [edge.x,edge.y,int(sign_side)],not selected.is_zero_approx() and hit.is_empty(),{"lateral_offset_m":selected_offset,"authored_sea_clearance":selected_clearance,"collider":str((hit.collider as Node).get_path()) if not hit.is_empty() else "none"})
