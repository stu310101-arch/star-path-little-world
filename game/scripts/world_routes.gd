extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
const IDS: Array[String] = ["counseling","admissions","recommendations","universities","life","wordking"]
static var _layout_cache: Dictionary = {}
static var _district_cache: Array = []
static var _limit_cache: Dictionary = {}

static func _layout_data() -> Dictionary:
	if _layout_cache.is_empty():
		_layout_cache = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	return _layout_cache

static func _district_data() -> Array:
	if _district_cache.is_empty():
		_district_cache = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	return _district_cache

static func directions() -> Array[Vector3]:
	var layout: Dictionary = _layout_data()
	var result: Array[Vector3] = []
	for station: Dictionary in layout.stations:
		var n: Array = station.normal
		result.append(Vector3(float(n[0]),float(n[1]),float(n[2])).normalized())
	return result

static func bridge_edges() -> Array[Vector2i]:
	return [Vector2i(0,1),Vector2i(0,2),Vector2i(0,3),Vector2i(0,4),Vector2i(5,1),Vector2i(5,2),Vector2i(5,3),Vector2i(5,4),Vector2i(1,2),Vector2i(2,3),Vector2i(3,4),Vector2i(4,1)]

static func local_point(normal: Vector3, up: Vector3, radius: float) -> Vector2:
	var axes: Basis = Geo.frame(up)
	return Vector2(normal.dot(axes.x),normal.dot(axes.z))*radius/maxf(.0001,normal.dot(up))

static func coast_distance(point: Vector2, info: Dictionary, index: int) -> float:
	return Biomes.coast_distance(point,info,index)

static func bridge_limits(edge: Vector2i = Vector2i(-1,-1), radius: float = 0.0) -> Vector2:
	if edge.x < 0: edge = bridge_edges()[0]
	if radius <= 0.0:
		var layout: Dictionary = _layout_data()
		radius = float(layout.get("authoring_radius",layout.radius))
	var key: String = "%d:%d:%f" % [edge.x,edge.y,radius]
	if _limit_cache.has(key): return _limit_cache[key] as Vector2
	var axes: Array[Vector3] = directions()
	var districts: Array = _district_data()
	var result: Vector2 = Vector2.ZERO
	for side: int in range(2):
		var index: int = edge.x if side == 0 else edge.y
		var other: int = edge.y if side == 0 else edge.x
		var low: float = 0.0
		var high: float = .49
		for _step: int in range(24):
			var middle: float = (low+high)*.5
			var point: Vector2 = local_point(axes[index].slerp(axes[other],middle),axes[index],radius)
			if coast_distance(point,districts[index],index) > .55: low = middle
			else: high = middle
		if side == 0: result.x = low
		else: result.y = 1.0-low
	_limit_cache[key] = result
	return result

static func bridge_endpoints(edge: Vector2i, radius: float) -> Array[Vector3]:
	var axes: Array[Vector3] = directions()
	var limits: Vector2 = bridge_limits(edge,radius)
	return [axes[edge.x].slerp(axes[edge.y],limits.x),axes[edge.x].slerp(axes[edge.y],limits.y)]

static func approach_extent(radius: float) -> float:
	var edge: Vector2i = bridge_edges()[0]
	var axes: Array[Vector3] = directions()
	return radius*tan(bridge_limits(edge,radius).x*axes[edge.x].angle_to(axes[edge.y]))

static func district_paths(info: Dictionary,radius: float) -> Array:
	var paths: Array = (info.paths as Array).duplicate(true)
	# Authored boardwalk sections that share an endpoint must share its miter.
	# Keeping them as separate ribbons leaves an outside wedge at the turn.
	if str(info.station) == "wordking" and paths.size() >= 2:
		var joined: Array = paths[0]
		joined.append_array((paths[1] as Array).slice(1))
		paths[0] = joined
		paths.remove_at(1)
	elif str(info.station) == "life" and paths.size() >= 3:
		var joined: Array = paths[1]
		var returning: Array = paths[2]
		returning.reverse()
		joined.append_array(returning.slice(1))
		paths[1] = joined
		paths.remove_at(2)
	# Short town-centre links keep ordinary interdistrict walks near ten
	# seconds on the 60 m globe. The existing buildings, water and outer
	# promenades stay in place; bends avoid their real collision footprints.
	if radius <= 64.0:
		match str(info.station):
			"universities":
				# The east/west roads stop at +/-3 m. Their widths do not cover
				# the centre gap; a flush paved link avoids climbing the road lip.
				paths.append([[-4.0,0.0],[4.0,0.0]])
			"life":
				paths.append([[-19.0,0.0],[0.0,0.0]])
				# Pass below the civic seats and around the east-side house.
				paths.append([[0.0,0.0],[0.0,-2.0],[8.4,-2.0],[9.0,-5.5],[14.0,-5.5],[19.0,-3.0],[19.0,0.0]])
				paths.append([[0.0,0.0],[.8,3.0],[.8,17.482353]])
			"wordking":
				# The x=0 axis contains civic furniture; use the clear east aisle.
				paths.append([[1.5,-16.0],[1.5,14.112903]])
			"admissions":
				# A west aisle bypasses the central building and links the harbor
				# promenade without the former east-side perimeter detour.
				paths.append([[-2.5,-16.891304],[-2.5,15.0],[0.0,26.0]])
	var index: int = IDS.find(str(info.station))
	if index < 0: return paths
	var axes: Array[Vector3] = directions()
	for edge: Vector2i in bridge_edges():
		if index != edge.x and index != edge.y: continue
		var endpoints: Array[Vector3] = bridge_endpoints(edge,radius)
		var end: Vector2 = local_point(endpoints[0 if index == edge.x else 1],axes[index],radius)
		var connection: Array = _coastal_connection(info,end,paths)
		connection.append([end.x,end.y])
		paths.append(connection)
	return paths

static func _coastal_connection(info: Dictionary, end: Vector2, paths: Array) -> Array:
	# The harbor access runs parallel at z=6. The eastbound intercontinental
	# bridge joins the city's axis directly, so its rails never cross the quay
	# approach in the estuary beside (30,0).
	if str(info.station) == "admissions" and end.x>0.0 and absf(end.y)<.01:
		return [[18.0,0.0]]
	# Campus side houses sit close to the east/west axis. Use their forecourt.
	if str(info.station) == "universities" and absf(end.x) > absf(end.y):
		var sign_x: float = signf(end.x)
		return [[sign_x*17.0,0.0],[sign_x*19.0,2.8],[sign_x*30.0,2.8]]
	var edges: Array = (info.roads as Array).duplicate(true)
	for i: int in range(info.loop.size()): edges.append([info.loop[i],info.loop[(i+1)%info.loop.size()]])
	# A route may join an existing boardwalk only through its open endpoints.
	# Projecting onto arbitrary rail-lined segments would form a side entrance
	# through a solid guardrail (the eastern wetland is a concrete example).
	for path: Array in paths:
		edges.append([path[0],path[0]])
		edges.append([path[-1],path[-1]])
	var nearest: Vector2 = Vector2.ZERO
	var best: float = INF
	for edge: Array in edges:
		var a: Vector2 = Vector2(edge[0][0],edge[0][1])
		var b: Vector2 = Vector2(edge[1][0],edge[1][1])
		var p: Vector2 = Geometry2D.get_closest_point_to_segment(end,a,b)
		if p.distance_squared_to(end) < best:
			best = p.distance_squared_to(end)
			nearest = p
	return [[nearest.x,nearest.y]]
