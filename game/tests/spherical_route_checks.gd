extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
const Sakura = preload("res://scripts/sakura_routes.gd")
const Outdoor = preload("res://scripts/outdoor_scale.gd")
const AVATAR_SCALE: float = .4
var authoring_radius: float = 60.0
var failures: Array[String] = []
var checks: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")

func check(label: String, passed: bool, details: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"details":details})
	if not passed:
		failures.append(label)
		push_error(label+": "+str(details))

func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var radius: float = float(layout.radius)
	authoring_radius = Outdoor.authored_radius(layout)
	var source_fixture: bool = OS.get_cmdline_user_args().has("--scaled-source-fixture")
	var axes: Array[Vector3] = Routes.directions()
	check("Physically compact globe retains six authored districts",axes.size()==6 and is_equal_approx(radius,21.6) and is_equal_approx(authoring_radius,54.0),{"physical_radius":radius,"authoring_radius":authoring_radius})
	check("Twelve connections cover the complete sphere",Routes.bridge_edges().size()==12)
	for edge: Vector2i in Routes.bridge_edges():
		var angle: float = axes[edge.x].angle_to(axes[edge.y])
		var compact_arc: float = angle * radius
		check("Adjacent centres are 10 percent closer at unchanged asset scale: %d-%d" % [edge.x, edge.y], absf(compact_arc - 21.6 * PI * 0.5) < 0.001 and absf(compact_arc / (angle*24.0) - .9) < 0.00001, {"new_m": compact_arc, "previous_m": angle*24.0, "ideal_normal_cadence_walk_seconds": compact_arc / 1.52})
	var grove_offset: Vector2 = Routes.local_point(Sakura.grove_up(), Vector3.UP, radius)
	var expected_grove_offset: Vector2 = Vector2(radius, radius)
	check("Scaled Sakura garden occupies the three-way sea gap", grove_offset.distance_to(expected_grove_offset) < 0.001, {"offset": str(grove_offset), "expected": str(expected_grove_offset)})
	check_global_graph(axes)
	var field_only: bool = OS.get_cmdline_user_args().has("--field-only")
	var world: Node3D
	var space: PhysicsDirectSpaceState3D
	if not field_only:
		if OS.get_cmdline_user_args().has("--canonical") or source_fixture:
			world = Node3D.new()
			for part: String in ["globe","neighborhood","stations"]:
				var content_path: String = "res://generated/streaming/"+part+"_base.scn" if source_fixture else "res://generated/"+part+".tscn"
				var content: Node3D = (load(content_path) as PackedScene).instantiate() as Node3D
				Outdoor.apply_to_children(content,radius/authoring_radius)
				world.add_child(content)
		else:
			world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
		root.add_child(world)
		world.set_process(false)
		await physics_frame
		await physics_frame
		space = world.get_world_3d().direct_space_state
		for index: int in range(districts.size()):
			var info: Dictionary = districts[index]
			var district_routes: Array = Routes.district_paths(info,authoring_radius)
			district_routes.append_array(info.roads)
			var loop: Array = (info.loop as Array).duplicate(true)
			loop.append(loop[0])
			district_routes.append(loop)
			district_routes.append_array(Biomes.spec(str(info.station)).get("trails",[]))
			for path_index: int in range(district_routes.size()):
				probe_path(space,axes[index],district_routes[path_index],radius,str(info.station)+" route "+str(path_index))
	for edge: Vector2i in Routes.bridge_edges():
		var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge,authoring_radius)
		var tag: String = "%d-%d" % [edge.x,edge.y]
		var centre: Vector3 = endpoints[0].slerp(endpoints[1],.5)
		var open_sea: bool = true
		for i: int in range(6):
			if centre.dot(axes[i]) > .01:
				open_sea = open_sea and Routes.coast_distance(Routes.local_point(centre,axes[i],authoring_radius),districts[i],i)<-.5
		check("Bridge crosses actual open water: "+tag,open_sea,{"span_m":endpoints[0].angle_to(endpoints[1])*radius})
		for side: int in range(2):
			var index: int = edge.x if side==0 else edge.y
			var endpoint: Vector2 = Routes.local_point(endpoints[side],axes[index],authoring_radius)
			check("Bridge head rests on the real bank: "+tag+"/"+str(side),absf(Routes.coast_distance(endpoint,districts[index],index)-.55)<.02,str(endpoint))
			var matching: Array = []
			for path: Array in Routes.district_paths(districts[index],authoring_radius):
				var end: Array = path[-1]
				if Vector2(end[0],end[1]).distance_to(endpoint)<.01: matching=path
			check("Coastal path meets bridge exactly: "+tag+"/"+str(side),not matching.is_empty(),matching)
			if not field_only and not matching.is_empty(): probe_path(space,axes[index],matching,radius,tag+"/"+str(side))
		if not field_only:
			probe_normals(space,endpoints,radius,tag+" bridge",4.0*radius/authoring_radius)
	var output: String = "res://../deliverables/world-redesign/spherical-route-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures.is_empty(),"failures":failures,"checks":checks,"field_only":field_only},"\t"))
	print("SPHERICAL_ROUTES checks=",checks.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func probe_path(space: PhysicsDirectSpaceState3D,up: Vector3,path: Array,radius: float,tag: String) -> void:
	var normals: Array[Vector3] = []
	for p: Array in path: normals.append(Geo.surface(up,Vector2(p[0],p[1]),authoring_radius).normalized())
	probe_normals(space,normals,radius,tag,4.0*radius/authoring_radius)

func check_global_graph(axes: Array[Vector3]) -> void:
	var adjacency: Dictionary = {}
	var pairs: Dictionary = {}
	var sum: Vector3 = Vector3.ZERO
	var antipodes: int = 0
	for i: int in range(axes.size()):
		adjacency[i]=[]
		sum+=axes[i]
		for j: int in range(i+1,axes.size()):
			if axes[i].dot(axes[j])<-.999: antipodes+=1
	check("Districts cover both hemispheres and three antipodal pairs",sum.length()<.001 and antipodes==3,{"antipodes":antipodes,"normal_sum":str(sum)})
	for edge: Vector2i in Routes.bridge_edges():
		var key: String = "%d-%d" % [mini(edge.x,edge.y),maxi(edge.x,edge.y)]
		check("Unique neighbouring globe edge "+key,not pairs.has(key) and absf(axes[edge.x].dot(axes[edge.y]))<.001)
		pairs[key]=true
		(adjacency[edge.x] as Array).append(edge.y)
		(adjacency[edge.y] as Array).append(edge.x)
	for start: int in range(axes.size()):
		var visited: Array[int] = [start]
		var queue: Array[int] = [start]
		while not queue.is_empty():
			var current: int = queue.pop_front()
			for next: int in adjacency[current]:
				if not visited.has(next):
					visited.append(next)
					queue.append(next)
		check("Every district reachable in either direction from "+str(start),visited.size()==6 and (adjacency[start] as Array).size()==4,visited)

func probe_normals(space: PhysicsDirectSpaceState3D,normals: Array[Vector3],radius: float,tag: String,interval: float) -> void:
	var missing: Array[String] = []
	var blocked: Array[Dictionary] = []
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .29 * AVATAR_SCALE
	capsule.height = 1.6 * AVATAR_SCALE
	var probes: int = 0
	for i: int in range(normals.size()-1):
		var a: Vector3 = normals[i]
		var b: Vector3 = normals[i+1]
		var count: int = maxi(1,ceili(a.angle_to(b)*radius/interval))
		for j: int in range(count+1):
			var n: Vector3 = a.slerp(b,float(j)/count).normalized()
			probes+=1
			var hit: Dictionary = Geo.ground_probe(space,n,radius)
			if hit.is_empty():
				if missing.size()<6: missing.append(str(n))
				continue
			var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.collision_mask = 8
			query.transform = Transform3D(Geo.frame(n),(hit.position as Vector3)+n*.84*AVATAR_SCALE)
			var hits: Array[Dictionary] = space.intersect_shape(query,2)
			if not hits.is_empty() and blocked.size()<6:
				blocked.append({"normal":str(n),"body":str((hits[0].collider as Node).get_path())})
	check("Continuous floor at the scaled source sampling interval: "+tag,missing.is_empty(),{"probes":probes,"missing":missing,"maximum_step_m":interval})
	check("Player capsule clears approach and rails: "+tag,blocked.is_empty(),blocked)
