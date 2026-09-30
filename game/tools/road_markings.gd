extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")

# Paint follows the same projected strips and corner miters as the road surface.
# All lines of one colour share a mesh, rather than one node per short dash.
static func build(builder: SceneTree, parent: Node3D, up: Vector3, radius: float, info: Dictionary) -> void:
	var roads: Array[Dictionary] = road_edges(up,radius,info)
	var crossings: Array[Dictionary] = pedestrian_crossings(roads,info,radius)
	var edge_paint: SurfaceTool = SurfaceTool.new()
	var centre_paint: SurfaceTool = SurfaceTool.new()
	var crossing_paint: SurfaceTool = SurfaceTool.new()
	var paving_joints: SurfaceTool = SurfaceTool.new()
	edge_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	centre_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	crossing_paint.begin(Mesh.PRIMITIVE_TRIANGLES)
	paving_joints.begin(Mesh.PRIMITIVE_TRIANGLES)
	var edge_quads: int = 0
	var centre_quads: int = 0
	var crossing_quads: int = 0
	var joint_quads: int = 0
	for index: int in range(roads.size()):
		var road: Dictionary = roads[index]
		var length: float = float(road.length)
		# Fine construction joints give the human-scale sidewalk a clear rhythm.
		# They stay within the sidewalk band and stop before crossing approaches.
		for joint: int in range(1,floori(length/1.8)):
			var along: float = float(joint)*1.8
			var at: Vector2 = (road.a as Vector2).lerp(road.b as Vector2,along/length)
			if not crossing_free(at,index,crossings,1.65):
				continue
			for side_sign: float in [-1.0,1.0]:
				var edge_at: Vector2 = at-(road.perpendicular as Vector2)*side_sign*2.62
				if junction_free(edge_at,index,roads,3.35):
					strip_quad(paving_joints,road,(along-.01)/length,(along+.01)/length,radius+.278,side_sign*2.62,.99)
					joint_quads+=1
		var steps: int = maxi(1,ceili(length/.28))
		for step: int in range(steps):
			var t0: float = float(step)/steps
			var t1: float = float(step+1)/steps
			var distance: float = (t0+t1)*.5*length
			var p: Vector2 = (road.a as Vector2).lerp(road.b as Vector2,(t0+t1)*.5)
			for side_sign: float in [-1.0,1.0]:
				# a.cross(b) points opposite the 2D left-normal in Geo.frame.
				var edge_at: Vector2 = p-(road.perpendicular as Vector2)*side_sign*1.96
				if junction_free(edge_at,index,roads,2.28) and crossing_free(p,index,crossings,1.55):
					strip_quad(edge_paint,road,t0,t1,radius+.305,side_sign*1.96,.075)
					edge_quads+=1
			# A regular 1.5 m cadence survives district shape and direction changes.
			# Ends are clear, so dashes cannot collide around a bend or a T junction.
			if distance>1.25 and distance<length-1.25 and fposmod(distance,1.5)<.66:
				if junction_free(p,index,roads,2.6) and crossing_free(p,index,crossings,1.65):
					strip_quad(centre_paint,road,t0,t1,radius+.31,0.0,.085)
					centre_quads+=1
	for crossing: Dictionary in crossings:
		var road: Dictionary = roads[int(crossing.road)]
		var p: Vector2 = crossing.point as Vector2
		var direction: Vector2 = road.direction as Vector2
		var across: Vector2 = road.perpendicular as Vector2
		for stripe: int in range(6):
			var centre: Vector2 = p+direction*(float(stripe)-2.5)*.39
			var from: Vector2 = centre-across*1.87
			var to: Vector2 = centre+across*1.87
			planar_strip(crossing_paint,up,radius,from,to,.20,radius+.322)
			crossing_quads+=1
	if edge_quads>0:
		Geo.mesh_node(parent,"RoadEdgePaint",edge_paint.commit(),Geo.material(Color("87958c")))
	if centre_quads>0:
		Geo.mesh_node(parent,"RoadCentrePaint",centre_paint.commit(),Geo.material(Color("b5a17a")))
	if crossing_quads>0:
		Geo.mesh_node(parent,"PedestrianCrossingPaint",crossing_paint.commit(),Geo.material(Color("aeb4a7")))
	if joint_quads>0:
		Geo.mesh_node(parent,"SidewalkConstructionJoints",paving_joints.commit(),Geo.material(Color("6d7d76")))
	var report: Dictionary = builder.get("report")
	if not report.has("road_markings"):
		report["road_markings"] = []
	var crossing_positions: Array = []
	for crossing: Dictionary in crossings:
		var crossing_point: Vector2 = crossing.point as Vector2
		crossing_positions.append([crossing_point.x,crossing_point.y])
	report.road_markings.append({"station":info.station,"crossings":crossings.size(),"crossing_positions":crossing_positions,"mesh_batches":int(edge_quads>0)+int(centre_quads>0)+int(crossing_quads>0),"junction_aware":true})

static func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

static func road_edges(up: Vector3,radius: float,info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var normals: Array[Vector3] = []
	for point: Array in info.loop:
		normals.append(Geo.surface(up,v2(point),radius).normalized())
	var sides: Array[Vector3] = Geo.path_sides(normals,true)
	for index: int in range(normals.size()):
		var next: int = (index+1)%normals.size()
		var row: Dictionary = edge(v2(info.loop[index]),v2(info.loop[next]),normals[index],normals[next],sides[index],sides[next],radius)
		row["loop"] = true
		result.append(row)
	for row: Array in info.roads:
		var a: Vector2 = v2(row[0])
		var b: Vector2 = v2(row[1])
		var normal_a: Vector3 = Geo.surface(up,a,radius).normalized()
		var normal_b: Vector3 = Geo.surface(up,b,radius).normalized()
		var side: Vector3 = normal_a.cross(normal_b).normalized()
		result.append(edge(a,b,normal_a,normal_b,side,side,radius))
	return result

static func edge(a: Vector2,b: Vector2,normal_a: Vector3,normal_b: Vector3,side_a: Vector3,side_b: Vector3,radius: float) -> Dictionary:
	var direction: Vector2 = (b-a).normalized()
	return {"a":a,"b":b,"normal_a":normal_a,"normal_b":normal_b,"side_a":side_a,"side_b":side_b,"length":normal_a.angle_to(normal_b)*radius,"direction":direction,"perpendicular":Vector2(-direction.y,direction.x),"loop":false}

static func pedestrian_crossings(roads: Array[Dictionary],info: Dictionary,radius: float) -> Array[Dictionary]:
	var paths: Array[Array] = []
	# Give the civic entrance priority, then the authored public routes. The
	# same forecourt endpoints are used by Urban.nearest_walk when it builds.
	var civic: Vector2 = v2(info.civic)
	paths.append([civic-Vector2(0,2.5),civic+Vector2(0,1.6)])
	for path: Array in Routes.district_paths(info,radius):
		for index: int in range(path.size()-1):
			paths.append([v2(path[index]),v2(path[index+1])])
	for building: Dictionary in info.urban_buildings:
		var forward: Vector2 = Vector2(sin(deg_to_rad(float(building.yaw))),cos(deg_to_rad(float(building.yaw))))
		var front: Vector2 = v2(building.offset)+forward*float(building.get("front",2.8))
		var destination: Vector2 = nearest_walk(front,roads,info)
		if front.distance_to(destination)>.25:
			paths.append([front,destination])
	var result: Array[Dictionary] = []
	for path: Array in paths:
		for road_index: int in range(roads.size()):
			var road: Dictionary = roads[road_index]
			var a: Vector2 = road.a as Vector2
			var b: Vector2 = road.b as Vector2
			var path_a: Vector2 = path[0] as Vector2
			var path_b: Vector2 = path[1] as Vector2
			var hit: Variant = Geometry2D.segment_intersects_segment(a,b,path_a,path_b)
			# Many authored paths end at the sidewalk, rather than the asphalt
			# centreline. Continue that same heading only across the road verge.
			if hit == null:
				var path_direction: Vector2 = (path_b-path_a).normalized()
				if absf(path_direction.dot(road.direction as Vector2))<.82:
					hit=Geometry2D.segment_intersects_segment(a,b,path_a-path_direction*3.25,path_b+path_direction*3.25)
			if hit == null:
				continue
			var crossing: Variant = safe_crossing(hit as Vector2,road_index,roads)
			if crossing == null:
				continue
			var p: Vector2 = crossing as Vector2
			var duplicate: bool = false
			for existing: Dictionary in result:
				if p.distance_to(existing.point as Vector2)<7.0:
					duplicate=true
			if not duplicate:
				result.append({"road":road_index,"point":p})
				if result.size()>=5:
					return result
	return result

static func safe_crossing(point: Vector2,index: int,roads: Array[Dictionary]) -> Variant:
	var road: Dictionary = roads[index]
	var a: Vector2 = road.a as Vector2
	var b: Vector2 = road.b as Vector2
	var direction: Vector2 = road.direction as Vector2
	# A path ending at an outside road bend joins its sidewalk naturally.
	# Do not manufacture two zebras on the neighbouring sides of that corner.
	if minf(point.distance_to(a),point.distance_to(b))<2.2:
		return null
	# A path often arrives at a T junction. Place its zebra crossing just
	# beside that junction, reached along the already existing wide sidewalk.
	# Rejecting the entire junction otherwise erases all four civic entries.
	for step: int in range(10):
		for sign_value: float in [1.0,-1.0]:
			var candidate: Vector2 = point+direction*float(step)*.5*sign_value
			if (candidate-a).dot(direction)<3.15 or (b-candidate).dot(direction)<3.15:
				continue
			if junction_free(candidate,index,roads,4.0):
				return candidate
	return null

static func nearest_walk(point: Vector2,roads: Array[Dictionary],info: Dictionary) -> Vector2:
	var edges: Array[Array] = []
	for road: Dictionary in roads:
		edges.append([road.a as Vector2,road.b as Vector2])
	for path: Array in info.paths:
		for index: int in range(path.size()-1):
			edges.append([v2(path[index]),v2(path[index+1])])
	var best: Vector2 = point
	var distance: float = INF
	for row: Array in edges:
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point,row[0] as Vector2,row[1] as Vector2)
		if point.distance_to(candidate)<distance:
			distance=point.distance_to(candidate)
			best=candidate
	return best

static func junction_free(point: Vector2,index: int,roads: Array[Dictionary],clearance: float) -> bool:
	for other: int in range(roads.size()):
		if other==index:
			continue
		var a: Vector2 = roads[other].a as Vector2
		var b: Vector2 = roads[other].b as Vector2
		if bool(roads[index].loop) and bool(roads[other].loop):
			var own_a: Vector2 = roads[index].a as Vector2
			var own_b: Vector2 = roads[index].b as Vector2
			if own_a.is_equal_approx(a) or own_a.is_equal_approx(b) or own_b.is_equal_approx(a) or own_b.is_equal_approx(b):
				continue
		var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(point,a,b)
		if point.distance_to(nearest)<clearance:
			return false
	return true

static func crossing_free(point: Vector2,index: int,crossings: Array[Dictionary],clearance: float) -> bool:
	for crossing: Dictionary in crossings:
		if int(crossing.road)==index and point.distance_to(crossing.point as Vector2)<clearance:
			return false
	return true

static func strip_quad(st: SurfaceTool,road: Dictionary,t0: float,t1: float,radius: float,offset: float,width: float) -> void:
	var a: Vector3 = road.normal_a as Vector3
	var b: Vector3 = road.normal_b as Vector3
	var side_a: Vector3 = road.side_a as Vector3
	var side_b: Vector3 = road.side_b as Vector3
	var n0: Vector3 = a.slerp(b,t0).normalized()
	var n1: Vector3 = a.slerp(b,t1).normalized()
	var s0: Vector3 = side_a.lerp(side_b,t0)
	var s1: Vector3 = side_a.lerp(side_b,t1)
	var p0: Vector3 = (n0*radius+s0*(offset-width*.5)).normalized()*radius
	var p1: Vector3 = (n0*radius+s0*(offset+width*.5)).normalized()*radius
	var p2: Vector3 = (n1*radius+s1*(offset+width*.5)).normalized()*radius
	var p3: Vector3 = (n1*radius+s1*(offset-width*.5)).normalized()*radius
	Geo.triangle(st,p0,p1,p2,Color.WHITE)
	Geo.triangle(st,p0,p2,p3,Color.WHITE)

static func planar_strip(st: SurfaceTool,up: Vector3,projection_radius: float,a: Vector2,b: Vector2,width: float,height: float) -> void:
	var normal_a: Vector3 = Geo.surface(up,a,projection_radius).normalized()
	var normal_b: Vector3 = Geo.surface(up,b,projection_radius).normalized()
	var side: Vector3 = normal_a.cross(normal_b).normalized()
	Geo.joined_strip(st,normal_a,normal_b,side,side,height,width)
