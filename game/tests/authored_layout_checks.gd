extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Sakura = preload("res://scripts/sakura_routes.gd")

var layout: Dictionary = {}
var districts: Array = []
var radius: float = 48.0
var checks: Array[Dictionary] = []
var failures: int = 0
var world: Node3D
var capsule: CapsuleShape3D
var capsule_centre: float = .82
var capsule_margin: float = .015
var sweeps: int = 0
var floor_probes: int = 0
var lamp_poles: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String,passed: bool,detail: Variant = "") -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures+=1
		push_error(label+": "+JSON.stringify(detail))

func run_checks() -> void:
	layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	districts=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	radius=float(layout.radius)
	check_endpoint_meaning()
	if OS.get_cmdline_user_args().has("--semantic-only"):
		finish()
		return
	world=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene=world
	await physics_frame
	await physics_frame
	freeze(world)
	var player: Node3D = world.get("player") as Node3D
	for child: Node in player.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape is CapsuleShape3D:
			capsule=(child as CollisionShape3D).shape.duplicate() as CapsuleShape3D
			capsule_centre=(child as CollisionShape3D).position.y
	check("Use the actual player's capsule",capsule != null)
	if capsule == null:
		finish()
		return
	capsule_margin=float(player.get("safe_margin"))
	collect_lamps()
	check_inventory()
	for index: int in range(districts.size()):
		var info: Dictionary = districts[index]
		var up: Vector3 = district_up(index)
		var paths: Array = Routes.district_paths(info,radius)
		for path_index: int in range(paths.size()):
			probe_route(str(info.station)+" public path "+str(path_index),normals_for(up,paths[path_index]),2.2,up)
		# Sidewalks include both shoulders and every real corner, so moving a
		# garden off a centreline cannot hide a bench/tree intruding into its edge.
		var road_loop: Array[Vector3] = normals_for(up,info.loop)
		road_loop.append(road_loop[0])
		probe_route(str(info.station)+" street loop and sidewalks",road_loop,6.3,up)
		for road_index: int in range(info.roads.size()):
			probe_route(str(info.station)+" interior street "+str(road_index),normals_for(up,info.roads[road_index]),6.3,up)
		for building_index: int in range(info.urban_buildings.size()):
			var connector: Array = building_connector(info.urban_buildings[building_index],info)
			if v2(connector[0]).distance_to(v2(connector[1]))>.3:
				probe_route(str(info.station)+" building forecourt "+str(building_index),normals_for(up,connector),1.4,up)
	probe_global_links()
	probe_sakura()
	finish()

func finish() -> void:
	var result: Dictionary = {"passed":failures==0,"failed":failures,"capsule_sweeps":sweeps,"floor_probes":floor_probes,"lamp_poles":lamp_poles.size(),"checks":checks}
	var output: FileAccess = FileAccess.open("res://tests/authored_layout_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures==0 else 1)

func freeze(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	for child: Node in node.get_children():
		freeze(child)

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func district_up(index: int) -> Vector3:
	var raw: Array = layout.stations[index].normal
	return Vector3(raw[0],raw[1],raw[2])

func normals_for(up: Vector3,path: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for point: Array in path:
		result.append(Geo.surface(up,v2(point),radius).normalized())
	return result

func road_edges(info: Dictionary) -> Array:
	var result: Array = (info.roads as Array).duplicate(true)
	for index: int in range(info.loop.size()):
		result.append([info.loop[index],info.loop[(index+1)%info.loop.size()]])
	return result

func building_connector(row: Dictionary,info: Dictionary) -> Array:
	var forward: Vector2 = Vector2(sin(deg_to_rad(float(row.yaw))),cos(deg_to_rad(float(row.yaw))))
	var from: Vector2 = v2(row.offset)+forward*float(row.get("front",2.8))
	var edges: Array = road_edges(info)
	for path: Array in info.paths:
		for index: int in range(path.size()-1):
			edges.append([path[index],path[index+1]])
	var nearest: Vector2 = from
	var distance: float = INF
	for edge: Array in edges:
		var point: Vector2 = Geometry2D.get_closest_point_to_segment(from,v2(edge[0]),v2(edge[1]))
		if from.distance_to(point)<distance:
			distance=from.distance_to(point)
			nearest=point
	return [[from.x,from.y],[nearest.x,nearest.y]]

func endpoint_reason(point: Vector2,path_index: int,paths: Array,info: Dictionary,up: Vector3) -> String:
	var normal: Vector3 = Geo.surface(up,point,radius).normalized()
	for road: Array in road_edges(info):
		var a: Vector3 = Geo.surface(up,v2(road[0]),radius)
		var b: Vector3 = Geo.surface(up,v2(road[1]),radius)
		if (normal*radius).distance_to(Geometry3D.get_closest_point_to_segment(normal*radius,a,b))<3.1:
			return "street sidewalk"
	for other: int in range(paths.size()):
		if other==path_index:
			continue
		var path: Array = paths[other]
		for index: int in range(path.size()-1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,v2(path[index]),v2(path[index+1])))<.35:
				return "joined public path "+str(other)
	var directions: Array[Vector3] = Routes.directions()
	for edge: Vector2i in Routes.bridge_edges():
		for fraction: float in [Routes.bridge_limits().x,Routes.bridge_limits().y]:
			if normal.angle_to(directions[edge.x].slerp(directions[edge.y],fraction))*radius<.35:
				return "inter-island bridge mouth"
	for row: Dictionary in info.urban_buildings:
		var connector: Array = building_connector(row,info)
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(point,v2(connector[0]),v2(connector[1]))
		if point.distance_to(nearest)<.68 and v2(connector[0]).distance_to(v2(connector[1]))>.3:
			return "actual building forecourt: "+str(row.asset)
	# This is the existing built Marina.TimberDeck entry, not a generic waiver.
	if str(info.station)=="admissions" and point.distance_to(Vector2(32,6))<.35:
		return "Marina timber deck entrance"
	return "UNRESOLVED"

func check_endpoint_meaning() -> void:
	var gardens: int = 0
	for index: int in range(districts.size()):
		var info: Dictionary = districts[index]
		gardens+=info.gardens.size()
		var paths: Array = Routes.district_paths(info,radius)
		var ends: Array[Dictionary] = []
		var resolved: bool = true
		for path_index: int in range(paths.size()):
			var path: Array = paths[path_index]
			for end: Array in [path[0],path[-1]]:
				var reason: String = endpoint_reason(v2(end),path_index,paths,info,district_up(index))
				resolved=reason!="UNRESOLVED" and resolved
				ends.append({"path":path_index,"point":end,"destination":reason})
		check("Every public path has a real destination: "+str(info.station),resolved,ends)
	check("All eighteen authored pocket gardens retained",gardens==18,gardens)
	var sakura_paths: Array = Sakura.paths(radius)
	check("Sakura promenade returns to its entrance",v2(sakura_paths[1][0]).is_equal_approx(v2(sakura_paths[1][-1])))
	check("Sakura entrance joins the loop",v2(sakura_paths[0][-1]).is_equal_approx(v2(sakura_paths[1][0])))
	check("Sakura has two deliberate overlooks",Sakura.destinations().size()==2 and Sakura.platforms().size()==2)

func sample_route(normals: Array[Vector3]) -> Array[Dictionary]:
	var points: Array[Vector3] = normals.duplicate()
	var closed: bool = points.size()>2 and points[0].angle_to(points[-1])<.000001
	if closed:
		points.pop_back()
	var sides: Array[Vector3] = Geo.path_sides(points,closed)
	var result: Array[Dictionary] = []
	for index: int in range(points.size() if closed else points.size()-1):
		var next: int = (index+1)%points.size()
		var steps: int = maxi(1,ceili(points[index].angle_to(points[next])*radius/.30))
		for step: int in range(steps):
			var t: float = float(step)/steps
			result.append({"normal":points[index].slerp(points[next],t).normalized(),"side":sides[index].lerp(sides[next],t)})
	result.append({"normal":points[0] if closed else points[-1],"side":sides[0] if closed else sides[-1]})
	return result

func collect_lamps() -> void:
	for node: Node in world.find_children("*","MeshInstance3D",true,false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if not mesh_node.mesh is CylinderMesh or String(mesh_node.name)!="Pole":
			continue
		var cylinder: CylinderMesh = mesh_node.mesh as CylinderMesh
		if cylinder.height<1.0 or maxf(cylinder.top_radius,cylinder.bottom_radius)>.12:
			continue
		var vertical: Vector3 = mesh_node.global_basis.y*cylinder.height*.5
		var scale: float = maxf(mesh_node.global_basis.x.length(),mesh_node.global_basis.z.length())
		lamp_poles.append({"from":mesh_node.global_position-vertical,"to":mesh_node.global_position+vertical,"radius":maxf(cylinder.top_radius,cylinder.bottom_radius)*scale,"path":str(mesh_node.get_path())})

func check_inventory() -> void:
	var benches: int = world.find_children("GardenBench*","Node3D",true,false).size()
	var tree_capsules: int = 0
	for node: Node in world.find_children("*","CollisionShape3D",true,false):
		var shape: CollisionShape3D = node as CollisionShape3D
		var body: StaticBody3D = shape.get_parent() as StaticBody3D
		if body != null and body.collision_layer==8 and shape.shape is CapsuleShape3D:
			tree_capsules+=1
	check("Actual scene contains garden seats and visible lamp poles",benches>=18 and lamp_poles.size()>=18,{"garden_bench_nodes":benches,"lamp_poles":lamp_poles.size(),"tree_capsules":tree_capsules})
	var grove: Node3D = world.get_node("Globe/SakuraGrove") as Node3D
	var minimap: Control = (world.get("hud") as CanvasLayer).get("minimap") as Control
	var drawn: Dictionary = minimap.call("build_sakura_patch")
	var actual_paths: Array = grove.get_meta("cartography_paths",[]) as Array
	var matches: bool = actual_paths.size()==drawn.paths.size() and int(grove.get_meta("layout_version",0))==Sakura.LAYOUT_VERSION
	for index: int in range(actual_paths.size()):
		var shown: PackedVector3Array = drawn.paths[index]
		for point: Vector3 in actual_paths[index]:
			var found: bool = false
			for candidate: Vector3 in shown:
				found=found or point.distance_to(candidate)<.00001
			matches=matches and found
	var actual_coast: PackedVector3Array = grove.get_meta("cartography_coast",PackedVector3Array()) as PackedVector3Array
	matches=matches and actual_coast.size()==(drawn.coast as PackedVector3Array).size()
	for index: int in range(actual_coast.size()):
		matches=matches and actual_coast[index].distance_to(drawn.coast[index])<.00001
	check("Minimap matches the actual built Sakura paths and coastline",matches)

func feet_at(normal: Vector3) -> Dictionary:
	floor_probes+=1
	return Geo.ground_probe(world.get_world_3d().direct_space_state,normal,radius)

func local_point(point: Vector3,up: Vector3) -> Array:
	var n: Vector3 = point.normalized()
	var axes: Basis = Geo.frame(up)
	var denominator: float = n.dot(up)
	if absf(denominator)<.01:
		return [point.x,point.y,point.z]
	return [snappedf(n.dot(axes.x)*radius/denominator,.01),snappedf(n.dot(axes.z)*radius/denominator,.01)]

func capsule_block(from_feet: Vector3,to_feet: Vector3) -> Array[String]:
	sweeps+=1
	var up: Vector3 = from_feet.normalized()
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=8
	query.margin=capsule_margin
	query.transform=Transform3D(Geo.frame(up),from_feet+up*capsule_centre)
	var state: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var hits: Array[Dictionary] = state.intersect_shape(query,12)
	var paths: Array[String] = []
	for hit: Dictionary in hits:
		paths.append(str((hit.collider as Node).get_path()))
	if not paths.is_empty():
		return paths
	query.motion=to_feet+to_feet.normalized()*capsule_centre-query.transform.origin
	var fractions: PackedFloat32Array = state.cast_motion(query)
	if fractions.size()<2 or fractions[0]>=.9999:
		return paths
	query.transform.origin+=query.motion*minf(1.0,fractions[1]+.01)
	query.motion=Vector3.ZERO
	for hit: Dictionary in state.intersect_shape(query,12):
		paths.append(str((hit.collider as Node).get_path()))
	if paths.is_empty():
		paths.append("shape collision at safe fraction "+str(fractions[0]))
	return paths

func lamp_block(feet: Vector3) -> Array[String]:
	var up: Vector3 = feet.normalized()
	var half_segment: float = capsule.height*.5-capsule.radius
	var bottom: Vector3 = feet+up*(capsule_centre-half_segment)
	var top: Vector3 = feet+up*(capsule_centre+half_segment)
	var result: Array[String] = []
	for pole: Dictionary in lamp_poles:
		if feet.distance_squared_to(pole.from as Vector3)>7.0:
			continue
		var nearest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(bottom,top,pole.from as Vector3,pole.to as Vector3)
		if nearest[0].distance_to(nearest[1])<capsule.radius+float(pole.radius)+capsule_margin:
			result.append(str(pole.path))
	return result

func probe_route(label: String,normals: Array[Vector3],width: float,up: Vector3) -> void:
	var samples: Array[Dictionary] = sample_route(normals)
	var lane_limit: float = width*.5-.40
	# The 2.2 m boardwalk includes 0.12 m posts inset from its edges. Its
	# 0.27 m body plus physics margin fits at +/-0.65 m; +/-0.70 touches posts.
	if is_equal_approx(width,2.2):
		lane_limit=.65
	var failures_here: Array[Dictionary] = []
	var tested: int = 0
	for ratio: float in [-1.0,-.5,0.0,.5,1.0]:
		var lateral: float = lane_limit*ratio
		var previous: Vector3 = Vector3.ZERO
		for index: int in range(samples.size()):
			var normal: Vector3 = ((samples[index].normal as Vector3)*radius+(samples[index].side as Vector3)*lateral).normalized()
			var ground: Dictionary = feet_at(normal)
			if ground.is_empty():
				if failures_here.size()<12:
					failures_here.append({"lane":lateral,"local":local_point(normal,up),"issue":"missing walkable floor"})
				previous=Vector3.ZERO
				continue
			var feet: Vector3 = (ground.position as Vector3)+normal*.025
			var lamp_hits: Array[String] = lamp_block(feet)
			if not lamp_hits.is_empty() and failures_here.size()<12:
				failures_here.append({"lane":lateral,"local":local_point(normal,up),"issue":"visible lamp occupies body corridor","nodes":lamp_hits})
			if previous!=Vector3.ZERO:
				for reverse: bool in [false,true]:
					var blockers: Array[String] = capsule_block(feet if reverse else previous,previous if reverse else feet)
					tested+=1
					if not blockers.is_empty() and failures_here.size()<12:
						failures_here.append({"lane":lateral,"local":local_point(normal,up),"reverse":reverse,"nodes":blockers})
			previous=feet
	check("Full body corridor: "+label,failures_here.is_empty(),{"width":width,"five_lanes":true,"both_directions":true,"sweeps":tested,"obstructions":failures_here})

func probe_global_links() -> void:
	var directions: Array[Vector3] = Routes.directions()
	for edge: Vector2i in Routes.bridge_edges():
		# Both bridge mouths and 8 m of their island approaches are included.
		probe_route("bridge mouths %d-%d" % [edge.x,edge.y],[directions[edge.x].slerp(directions[edge.y],.27),directions[edge.x].slerp(directions[edge.y],.73)],2.2,directions[edge.x])
	var up: Vector3 = district_up(1)
	probe_route("marina approach and central usable aisle",normals_for(up,[[30,6],[32,6],[39.8,6]]),2.2,up)

func probe_sakura() -> void:
	var up: Vector3 = Sakura.grove_up()
	probe_route("Sakura town approach",[Sakura.town_endpoint(radius),Sakura.bridge_start()],2.7,Vector3.UP)
	probe_route("Sakura arch bridge",[Sakura.bridge_start(),Sakura.bridge_finish()],2.7,up)
	var paths: Array = Sakura.paths(radius)
	for index: int in range(paths.size()):
		probe_route("Sakura garden route "+str(index),normals_for(up,paths[index]),Sakura.WIDTH,up)
	for destination: Dictionary in Sakura.destinations():
		var point: Vector2 = destination.position as Vector2
		var from: Vector2 = Vector2(signf(point.x)*4.8,2.2)
		probe_route("Sakura overlook entrance "+str(destination.id),normals_for(up,[[from.x,from.y],[point.x,point.y]]),1.5,up)
