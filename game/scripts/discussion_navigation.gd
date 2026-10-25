extends RefCounted
## Routes use authored walkways only. Build on selection, never on a frame tick.
const MERGE_DISTANCE: float = .015
const INTERSECTION_TOLERANCE: float = .06
const PLAYER_RADIUS: float = .27
const WALK_CLEARANCE: float = PLAYER_RADIUS + .08
const CORNER_MARGIN: float = .015
static var _cached_layout: int = 0
static var _cached_obstacles: Array[PlanarObstacle] = []

class PlanarObstacle:
	extends RefCounted
	var center: Vector2
	var raw_half: Vector2
	var half: Vector2
	var cosine: float
	var sine: float
	var corners: Array[Vector2] = []
	var bounds: Rect2
	func local(point: Vector2) -> Vector2:
		var relative := point-center
		return Vector2(cosine*relative.x-sine*relative.y,sine*relative.x+cosine*relative.y)
	func contains(point: Vector2) -> bool:
		var relative := local(point)
		return absf(relative.x)<half.x and absf(relative.y)<half.y
	func blocks(first: Vector2, last: Vector2, leaving_start: bool) -> bool:
		var a := local(first)
		var movement := local(last)-a
		if leaving_start and absf(a.x)<half.x and absf(a.y)<half.y:
			# A real player can stand in the extra comfort margin or beside a
			# rounded capsule corner. Permit moving away, never through the wall.
			var outward := a-a.clamp(-raw_half,raw_half)
			if outward.length_squared()>=PLAYER_RADIUS*PLAYER_RADIUS-.00001 and outward.dot(movement)>=-.00001:
				return false
		var enter: float = 0.0
		var leave: float = 1.0
		for axis: int in range(2):
			if absf(movement[axis])<.000001:
				if absf(a[axis])>half[axis]:
					return false
				continue
			var near: float = (-half[axis]-a[axis])/movement[axis]
			var far: float = (half[axis]-a[axis])/movement[axis]
			enter = maxf(enter,minf(near,far))
			leave = minf(leave,maxf(near,far))
			if enter>leave:
				return false
		return true

static func route(layout: Dictionary, start: Vector3, current_zone: String, destination_zone: String) -> Array[Vector3]:
	var empty: Array[Vector3] = []
	if not start.is_finite():
		return empty
	var paths: Dictionary = {}
	for zone: Dictionary in layout.get("zones", []):
		var points: Array[Vector3] = _vectors(zone.get("walk_path", []))
		if points.size() >= 2:
			paths[str(zone.get("id", ""))] = points
	if not paths.has(destination_zone):
		return empty
	var destination: Vector3 = (paths[destination_zone] as Array[Vector3])[-1]
	start.y = destination.y
	if _at_destination(start,current_zone,destination_zone,paths[destination_zone]):
		return empty
	var navigation: Dictionary = layout.get("navigation", {})
	var ring: Array[Vector3] = _vectors(navigation.get("ring_points", []))
	var graph: Dictionary = {"points":[], "edges":[], "segments":[]}
	var spokes: Dictionary = {}
	for spoke: Dictionary in navigation.get("spokes", []):
		var ring_index: int = int(spoke.get("ring_index", -1))
		if ring_index >= 0 and ring_index < ring.size():
			spokes[str(spoke.get("zone_id", ""))] = ring[ring_index]
	for zone: String in paths:
		var points: Array[Vector3] = paths[zone]
		for index: int in range(points.size()-1):
			var first: Vector3 = points[index]
			var last: Vector3 = points[index+1]
			if spokes.has(zone):
				var joint: Vector3 = spokes[zone]
				var projection: Vector3 = Geometry3D.get_closest_point_to_segment(joint, first, last)
				if projection.distance_to(joint) <= INTERSECTION_TOLERANCE and joint.distance_to(first) > MERGE_DISTANCE and joint.distance_to(last) > MERGE_DISTANCE:
					_connect(graph, first, joint, "radial", zone)
					_connect(graph, joint, last, "radial", zone)
					continue
			_connect(graph, first, last, "radial", zone)
	for index: int in range(ring.size()-1):
		_connect(graph, ring[index], ring[index+1], "ring", "")
	if bool(navigation.get("ring_closed", false)) and ring.size() > 2:
		_connect(graph, ring[-1], ring[0], "ring", "")
	var radial: Dictionary = _closest(graph, start, "radial", current_zone)
	if radial.is_empty():
		radial = _closest(graph, start, "radial", "")
	var circular: Dictionary = _closest(graph, start, "ring", "")
	var origin: Dictionary = radial
	# An offset inside the ring's walkable width remains on that same segment;
	# it must not be sent across a planting bed to the nearest district spoke.
	if not circular.is_empty() and float(circular.distance) <= float(navigation.get("ring_width",3.6))*.5 and (origin.is_empty() or float(circular.distance)+.02 < float(origin.distance)):
		origin = circular
	if origin.is_empty():
		return empty
	var approach: Array[Vector3] = _approach(layout,start,origin.point)
	if approach.is_empty() and start.distance_to(origin.point)>MERGE_DISTANCE:
		return empty
	var source: int = _node(graph, start)
	var projected: int = _node(graph, origin.point)
	var previous: int = source
	for point: Vector3 in approach:
		var next: int = _node(graph,point)
		_link(graph,previous,next)
		previous = next
	_link(graph,previous,projected)
	_link(graph, projected, int(origin.a))
	_link(graph, projected, int(origin.b))
	var target: int = _node(graph, destination)
	var ids: Array[int] = _shortest(graph, source, target)
	var result: Array[Vector3] = []
	for id: int in ids:
		var point: Vector3 = graph.points[id]
		if point.distance_to(start) > MERGE_DISTANCE and (result.is_empty() or point.distance_to(result[-1]) > MERGE_DISTANCE):
			result.append(point)
	return result

static func _approach(layout: Dictionary, start: Vector3, target: Vector3) -> Array[Vector3]:
	var result: Array[Vector3] = []
	if start.distance_to(target)<=MERGE_DISTANCE:
		return result
	var first := Vector2(start.x,start.z)
	var last := Vector2(target.x,target.z)
	var obstacles: Array[PlanarObstacle] = _obstacles(layout)
	for obstacle: PlanarObstacle in obstacles:
		if obstacle.bounds.has_point(first):
			var local := obstacle.local(first)
			if local.distance_squared_to(local.clamp(-obstacle.raw_half,obstacle.raw_half))<PLAYER_RADIUS*PLAYER_RADIUS-.00001:
				return result
	if _clear(first,last,obstacles,true):
		result.append(target)
		return result
	# Most selections are already on an open path. Only a blocked first leg
	# needs this local visibility search; no navigation work runs per frame.
	var direct_bounds := Rect2(first,Vector2.ZERO).expand(last)
	for padding: float in [3.0,10.0,32.0,128.0]:
		var search_bounds := direct_bounds.grow(padding)
		var local_obstacles: Array[PlanarObstacle] = []
		var point_bounds := direct_bounds
		for obstacle: PlanarObstacle in obstacles:
			if not obstacle.bounds.intersects(search_bounds,true):
				continue
			local_obstacles.append(obstacle)
			point_bounds = point_bounds.merge(obstacle.bounds.grow(CORNER_MARGIN*2))
		# Every candidate edge stays inside this rectangle. Retain all blockers
		# that could touch it, including a neighbour outside the initial search.
		var blockers: Array[PlanarObstacle] = []
		for obstacle: PlanarObstacle in obstacles:
			if obstacle.bounds.intersects(point_bounds,true):
				blockers.append(obstacle)
		var points: Array[Vector2] = [first,last]
		for obstacle: PlanarObstacle in local_obstacles:
			for corner: Vector2 in obstacle.corners:
				if blockers.any(func(other: PlanarObstacle) -> bool: return other.bounds.has_point(corner) and other.contains(corner)):
					continue
				if not points.any(func(existing: Vector2) -> bool: return existing.distance_squared_to(corner)<.0001):
					points.append(corner)
		var path: Array[Vector2] = _visible_path(points,blockers)
		if path.is_empty():
			continue
		for point: Vector2 in path:
			result.append(Vector3(point.x,target.y,point.y))
		return result
	return result

## Also used when advancing route hints: never skip a corner into a wall.
static func segment_clear(layout: Dictionary, from: Vector3, to: Vector3) -> bool:
	if not from.is_finite() or not to.is_finite():
		return false
	return _clear(Vector2(from.x,from.z),Vector2(to.x,to.z),_obstacles(layout),true)

## An empty route can also mean unreachable; callers must not announce arrival
## until this predicate confirms that the player is actually in the destination.
static func arrived(layout: Dictionary, start: Vector3, current_zone: String, destination_zone: String) -> bool:
	if not start.is_finite():
		return false
	for zone: Dictionary in layout.get("zones",[]):
		if str(zone.get("id",""))==destination_zone:
			return _at_destination(start,current_zone,destination_zone,_vectors(zone.get("walk_path",[])))
	return false

static func _at_destination(start: Vector3, current_zone: String, destination_zone: String, path: Array[Vector3]) -> bool:
	if path.size()<2:
		return false
	start.y = path[-1].y
	if start.distance_to(path[-1])<.15:
		return true
	if current_zone!=destination_zone:
		return false
	return (start-path[-1]).dot((path[-1]-path[-2]).normalized())>=-.15

static func _obstacles(layout: Dictionary) -> Array[PlanarObstacle]:
	var key: int = hash(layout)
	if key==_cached_layout and not _cached_obstacles.is_empty():
		return _cached_obstacles
	_cached_layout = key
	_cached_obstacles = []
	for box: Dictionary in layout.get("colliders",[]):
		if not bool(box.get("camera_only",false)):
			_add_obstacle(box)
	var device: Dictionary = layout.get("device",{}).get("collider",{})
	if not device.is_empty():
		for zone: Dictionary in layout.get("zones",[]):
			for slot: Dictionary in zone.get("slots",[]):
				var yaw: float = float(slot.get("rotation_y",0))
				var center: Vector3 = _vectors([slot.position])[0]+_vectors([device.center])[0].rotated(Vector3.UP,yaw)
				_add_obstacle({"center":[center.x,center.y,center.z],"size":device.size,"rotation_y":yaw})
	return _cached_obstacles

static func _add_obstacle(box: Dictionary) -> void:
	var centers := _vectors([box.get("center",[])])
	var sizes := _vectors([box.get("size",[])])
	if centers.is_empty() or sizes.is_empty():
		return
	var center: Vector3 = centers[0]
	var size: Vector3 = sizes[0]
	# Ignore ground slabs and overhead camera proxies, retain low planters,
	# furniture and walls that intersect a standing character's body.
	if center.y+size.y*.5<=.15 or center.y-size.y*.5>=1.68:
		return
	var obstacle := PlanarObstacle.new()
	obstacle.center = Vector2(center.x,center.z)
	obstacle.raw_half = Vector2(size.x,size.z)*.5
	obstacle.half = obstacle.raw_half+Vector2.ONE*WALK_CLEARANCE
	var yaw: float = float(box.get("rotation_y",0))
	obstacle.cosine = cos(yaw)
	obstacle.sine = sin(yaw)
	var corner_half := obstacle.half+Vector2.ONE*CORNER_MARGIN
	for signs: Vector2 in [Vector2(-1,-1),Vector2(-1,1),Vector2(1,1),Vector2(1,-1)]:
		var point := obstacle.center+(corner_half*signs).rotated(-yaw)
		obstacle.corners.append(point)
		obstacle.bounds = Rect2(point,Vector2.ZERO) if obstacle.corners.size()==1 else obstacle.bounds.expand(point)
	_cached_obstacles.append(obstacle)

static func _clear(first: Vector2, last: Vector2, obstacles: Array[PlanarObstacle], leaving_start: bool = false) -> bool:
	var bounds := Rect2(first,Vector2.ZERO).expand(last)
	for obstacle: PlanarObstacle in obstacles:
		if bounds.intersects(obstacle.bounds,true) and obstacle.blocks(first,last,leaving_start):
			return false
	return true

static func _visible_path(points: Array[Vector2], obstacles: Array[PlanarObstacle]) -> Array[Vector2]:
	var distances := PackedFloat64Array()
	var previous := PackedInt32Array()
	var visited := PackedByteArray()
	distances.resize(points.size())
	distances.fill(INF)
	previous.resize(points.size())
	previous.fill(-1)
	visited.resize(points.size())
	visited.fill(0)
	distances[0] = 0
	for step: int in range(points.size()):
		var current: int = -1
		var best: float = INF
		for index: int in range(points.size()):
			var estimate: float = distances[index]+points[index].distance_to(points[1])
			if visited[index]==0 and estimate<best:
				best = estimate
				current = index
		if current<0 or current==1:
			break
		visited[current] = 1
		for next: int in range(1,points.size()):
			if visited[next]!=0:
				continue
			var candidate: float = distances[current]+points[current].distance_to(points[next])
			if candidate>=distances[next] or candidate+points[next].distance_to(points[1])>distances[1]:
				continue
			if _clear(points[current],points[next],obstacles,current==0):
				distances[next] = candidate
				previous[next] = current
	var result: Array[Vector2] = []
	if not is_finite(distances[1]):
		return result
	var cursor: int = 1
	while cursor>0:
		result.push_front(points[cursor])
		cursor = previous[cursor]
	return result

static func _vectors(values: Array) -> Array[Vector3]:
	var result: Array[Vector3] = []
	for value: Variant in values:
		var point: Vector3 = value if value is Vector3 else Vector3(float(value[0]),float(value[1]),float(value[2])) if value is Array and value.size()==3 else Vector3(INF,INF,INF)
		if point.is_finite():
			result.append(point)
	return result

static func _node(graph: Dictionary, point: Vector3) -> int:
	for index: int in range(graph.points.size()):
		if (graph.points[index] as Vector3).distance_to(point) <= MERGE_DISTANCE:
			return index
	graph.points.append(point)
	graph.edges.append({})
	return graph.points.size()-1

static func _link(graph: Dictionary, left: int, right: int) -> void:
	if left == right:
		return
	var distance: float = (graph.points[left] as Vector3).distance_to(graph.points[right])
	graph.edges[left][right] = distance
	graph.edges[right][left] = distance

static func _connect(graph: Dictionary, first: Vector3, last: Vector3, kind: String, zone: String) -> void:
	var left: int = _node(graph, first)
	var right: int = _node(graph, last)
	_link(graph, left, right)
	if left != right:
		graph.segments.append({"a":left,"b":right,"kind":kind,"zone":zone})

static func _closest(graph: Dictionary, start: Vector3, kind: String, zone: String) -> Dictionary:
	var best: Dictionary = {}
	var distance: float = INF
	for segment: Dictionary in graph.segments:
		if segment.kind != kind or (not zone.is_empty() and segment.zone != zone):
			continue
		var point: Vector3 = Geometry3D.get_closest_point_to_segment(start,graph.points[segment.a],graph.points[segment.b])
		var separation: float = point.distance_to(start)
		if separation < distance:
			distance = separation
			best = {"point":point,"distance":distance,"a":segment.a,"b":segment.b}
	return best

static func _shortest(graph: Dictionary, source: int, target: int) -> Array[int]:
	var count: int = graph.points.size()
	var distances := PackedFloat64Array()
	distances.resize(count)
	distances.fill(INF)
	var previous := PackedInt32Array()
	previous.resize(count)
	previous.fill(-1)
	var visited := PackedByteArray()
	visited.resize(count)
	visited.fill(0)
	distances[source] = 0
	for step: int in range(count):
		var next: int = -1
		var best: float = INF
		for index: int in range(count):
			if visited[index] == 0 and distances[index] < best:
				next = index
				best = distances[index]
		if next < 0 or next == target:
			break
		visited[next] = 1
		for neighbor: int in graph.edges[next]:
			var candidate: float = distances[next]+float(graph.edges[next][neighbor])
			if candidate < distances[neighbor]:
				distances[neighbor] = candidate
				previous[neighbor] = next
	var result: Array[int] = []
	if not is_finite(distances[target]):
		return result
	var cursor: int = target
	while cursor >= 0:
		result.push_front(cursor)
		if cursor == source:
			break
		cursor = previous[cursor]
	return result
