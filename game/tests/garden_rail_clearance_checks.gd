extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Garden = preload("res://tools/sakura_garden.gd")
const Timber = preload("res://scripts/waterfront_routes.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Ecology = preload("res://tools/ecology_world.gd")

var radius: float = 48.0
var report: Dictionary = {}
var fixture: Node3D
var capsule: CapsuleShape3D
var failures: int = 0
var sweeps: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	# Only generated paths/railings: no complete world, buildings or model assets.
	fixture=Node3D.new()
	fixture.name="RailClearanceFixture"
	root.add_child(fixture)
	Garden.build_garden_surfaces(fixture,Plan.grove_up(),radius)
	Garden.build_overlook_rails(fixture,Plan.grove_up(),radius)
	Garden.build_bridge(self,fixture,Plan.grove_up(),radius)
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var counseling_loop: Array[Vector3]=normals(Vector3.UP,districts[0].loop)
	Geo.mesh_node(fixture,"CounselingSidewalk",Geo.path_ribbon(counseling_loop,radius+.27,6.3,true),null,true)
	counseling_loop.append(counseling_loop[0])
	var info: Dictionary=districts[1]
	if OS.get_cmdline_user_args().has("--inspect-admissions"):
		var debug_route: Array[Dictionary]=Timber.samples(Vector3.RIGHT,info.paths[1],info,radius)
		for i: int in range(debug_route.size()):
			var row: Dictionary=debug_route[i]
			if (row.p as Vector2).x>27.5 and (row.p as Vector2).y<2.2:
				var edges: Array=[]
				for sign_value: float in [-1.0,1.0]:
					var edge: Vector3=Timber.at(row,radius,.26,sign_value*1.035).normalized()
					edges.append(Vector2(-edge.y,edge.z)*radius/edge.x)
				print("ADMISSIONS_SAMPLE ",row.p," wet=",row.wet," edges=",edges)
	var ecology: RefCounted=Ecology.new()
	ecology.set("radius",radius)
	var town_fraction: float=float(fixture.get_node("SakuraBridge").get_meta("town_guardrail_start_fraction"))
	var town_sides: Array[Vector3]=Geo.path_sides([Plan.town_endpoint(radius),Plan.bridge_start(),Plan.bridge_finish(),Plan.grove_up()])
	var dry_margin: float=INF
	for step: int in range(21):
		var t: float=town_fraction*float(step)/20.0
		var sample: Dictionary={"normal":Plan.town_endpoint(radius).slerp(Plan.bridge_start(),t).normalized(),"side":town_sides[0].lerp(town_sides[1],t)}
		for lateral: float in [-1.35,0.0,1.35]:
			var point: Vector3=Timber.at(sample,radius,0.0,lateral)
			var local: Vector2=Vector2(point.x,point.z)*radius/point.y
			dry_margin=minf(dry_margin,float(ecology.call("dry_distance",local,districts[0],0)))
	if dry_margin<.34:
		failures+=1
	print("Open town landing dry-bank margin: ",dry_margin," m; rail start fraction=",town_fraction)
	for district_index: int in range(districts.size()):
		var district: Dictionary=districts[district_index]
		var up: Vector3=Routes.directions()[district_index]
		ecology.set("district_routes",Routes.district_paths(district,radius))
		ecology.call("build_boardwalks",fixture,up,district)
		for path: Array in Routes.district_paths(district,radius):
			var route: Array[Dictionary]=Timber.samples(up,path,district,radius)
			var dry: ArrayMesh=Timber.deck_mesh(route,radius,.26,2.2,false)
			if dry!=null:
				Geo.mesh_node(fixture,"DryPaving",dry,null,true)
	capsule=CapsuleShape3D.new()
	capsule.radius=.27
	capsule.height=1.6
	await physics_frame
	await physics_frame
	probe("Town approach",[Plan.town_endpoint(radius),Plan.bridge_start()],.95)
	probe("Arch bridge",[Plan.bridge_start(),Plan.bridge_finish()],.95)
	probe("Connected bridge route",[Plan.town_endpoint(radius),Plan.bridge_start(),Plan.bridge_finish(),Plan.grove_up()],.95)
	probe("Bridge usable width",[Plan.town_endpoint(radius),Plan.bridge_start(),Plan.bridge_finish()],1.04)
	probe("Counseling city sidewalk across garden entrance",counseling_loop,2.75)
	probe("Counseling city full usable sidewalk",counseling_loop,2.84)
	var paths: Array=Plan.paths(radius)
	probe("Garden closed loop",normals(Plan.grove_up(),paths[1]),.8)
	probe("Garden usable width",normals(Plan.grove_up(),paths[1]),.89)
	probe("Admissions turn",normals(Vector3.RIGHT,info.paths[1]),.65)
	probe("Admissions usable width",normals(Vector3.RIGHT,info.paths[1]),.78)
	for district_index: int in range(districts.size()):
		var district: Dictionary=districts[district_index]
		var up: Vector3=Routes.directions()[district_index]
		var route_index: int=0
		for path: Array in Routes.district_paths(district,radius):
			var wet: bool=false
			for sample: Dictionary in Timber.samples(up,path,district,radius):
				wet=wet or bool(sample.wet)
			if wet:
				probe(str(district.station)+" wet route "+str(route_index),normals(up,path),.78)
			route_index+=1
	print("GARDEN_RAIL_CLEARANCE ",sweeps," sweeps, ",failures," failed corridors")
	fixture.free()
	quit(1 if failures>0 else 0)

func normals(up: Vector3,path: Array) -> Array[Vector3]:
	var result: Array[Vector3]=[]
	for point: Array in path:
		result.append(Geo.surface(up,Vector2(point[0],point[1]),radius).normalized())
	return result

func samples(normals_in: Array[Vector3]) -> Array[Dictionary]:
	var points: Array[Vector3]=normals_in.duplicate()
	var closed: bool=points.size()>2 and points[0].angle_to(points[-1])<.000001
	if closed:
		points.pop_back()
	var sides: Array[Vector3]=Geo.path_sides(points,closed)
	var result: Array[Dictionary]=[]
	for i: int in range(points.size() if closed else points.size()-1):
		var next: int=(i+1)%points.size()
		var count: int=maxi(1,ceili(points[i].angle_to(points[next])*radius/.30))
		for j: int in range(count):
			var t: float=float(j)/count
			result.append({"normal":points[i].slerp(points[next],t).normalized(),"side":sides[i].lerp(sides[next],t)})
	result.append({"normal":points[0] if closed else points[-1],"side":sides[0] if closed else sides[-1]})
	return result

func blocked(a: Vector3,b: Vector3) -> Array[String]:
	var query: PhysicsShapeQueryParameters3D=PhysicsShapeQueryParameters3D.new()
	query.shape=capsule
	query.collision_mask=8
	query.margin=.015
	query.transform=Transform3D(Geo.frame(a.normalized()),a+a.normalized()*.82)
	var state: PhysicsDirectSpaceState3D=fixture.get_world_3d().direct_space_state
	var hits: Array[Dictionary]=state.intersect_shape(query,8)
	if hits.is_empty():
		query.motion=b+b.normalized()*.82-query.transform.origin
		var fractions: PackedFloat32Array=state.cast_motion(query)
		if fractions.size()<2 or fractions[0]>=.9999:
			return []
		query.transform.origin+=query.motion*minf(1.0,fractions[1]+.01)
		query.motion=Vector3.ZERO
		hits=state.intersect_shape(query,8)
		if hits.is_empty():
			return ["Shape sweep contact"]
	var nodes: Array[String]=[]
	for hit: Dictionary in hits:
		nodes.append(str((hit.collider as Node).get_path()))
	return nodes

func probe(label: String,route: Array[Vector3],outer_lane: float) -> void:
	var problems: Array[Dictionary]=[]
	var points: Array[Dictionary]=samples(route)
	for ratio: float in [-1.0,-.5,0.0,.5,1.0]:
		var previous: Vector3=Vector3.ZERO
		for point: Dictionary in points:
			var normal: Vector3=((point.normal as Vector3)*radius+(point.side as Vector3)*(outer_lane*ratio)).normalized()
			var ground: Dictionary=fixture.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(normal*(radius+2),normal*(radius-.35),1))
			# Adjacent city ground and the marina are outside this rail-only
			# fixture. Their exact endpoint planes use the known flush height;
			# full-scene tests separately require a real floor at every point.
			var feet: Vector3=normal*(radius+.285) if ground.is_empty() else (ground.position as Vector3)+normal*.025
			if previous!=Vector3.ZERO:
				for reverse: bool in [false,true]:
					var collisions: Array[String]=blocked(feet if reverse else previous,previous if reverse else feet)
					sweeps+=1
					if not collisions.is_empty() and problems.size()<8:
						problems.append({"lane":outer_lane*ratio,"normal":normal,"nodes":collisions,"reverse":reverse})
			previous=feet
	if not problems.is_empty():
		failures+=1
	print(label,": ","PASS" if problems.is_empty() else JSON.stringify(problems))
