extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const RADIUS: float = 48.0
const POLE_RADIUS: float = .055
var failures: Array[Dictionary] = []
var checked_sections: int = 0

func _initialize() -> void:
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var lighting: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/street_lighting.json")) as Dictionary
	var report: Array[Dictionary] = []
	for info: Dictionary in districts:
		var route_rows: Array[Dictionary] = [{"name":"street loop","points":info.loop,"width":6.3,"closed":true}]
		for index: int in range(info.roads.size()):
			route_rows.append({"name":"street "+str(index),"points":info.roads[index],"width":6.3,"closed":false})
		var paths: Array = Routes.district_paths(info,RADIUS)
		for index: int in range(paths.size()):
			route_rows.append({"name":"public path "+str(index),"points":paths[index],"width":2.2,"closed":false})
		for index: int in range(info.urban_buildings.size()):
			var building: Dictionary = info.urban_buildings[index]
			var forward: Vector2 = Vector2(sin(deg_to_rad(float(building.yaw))),cos(deg_to_rad(float(building.yaw))))
			var front: Vector2 = v2(building.offset)+forward*float(building.front)
			var lane: Vector2 = nearest_walk(front,info)
			route_rows.append({"name":"building forecourt "+str(index),"points":[[front.x,front.y],[lane.x,lane.y]],"width":1.4,"closed":false})
		var sections: Array[Dictionary] = []
		for row: Dictionary in route_rows:
			sections.append_array(cross_sections(row))
		var district_lights: Array = lighting[str(info.station)]
		for index: int in range(district_lights.size()):
			var local: Vector2 = v2(district_lights[index])
			var point: Vector3 = Geo.surface(Vector3.UP,local,RADIUS)
			var clearance: float = INF
			var nearest_route: String = ""
			for section: Dictionary in sections:
				if point.distance_squared_to(section.centre)>pow(float(section.extent)+1.5,2.0):
					continue
				var a: Vector3 = section.a
				var b: Vector3 = section.b
				var closest: Vector3 = a+(b-a)*clampf((point-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
				var gap: float = point.distance_to(closest)-POLE_RADIUS
				if gap<clearance:
					clearance=gap
					nearest_route=str(section.name)
				checked_sections+=1
			var detail: Dictionary = {"station":info.station,"light":index+1,"offset":district_lights[index],"paving_edge_clearance":clearance,"nearest_route":nearest_route}
			report.append(detail)
			# .10 m longitudinal sampling leaves at most .05 m between sections.
			# A .07 m minimum margin therefore keeps the entire pole outside the
			# actual spherical pavement, including mitered corners/full road width.
			if clearance<.07:
				failures.append(detail)
	var output: FileAccess = FileAccess.open("res://../deliverables/street-lighting-clearance-results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"lights":report.size(),"sections_checked":checked_sections,"failures":failures,"results":report},"\t"))
	print("STREET_LIGHTING_CLEARANCE ",JSON.stringify({"lights":report.size(),"sections_checked":checked_sections,"failures":failures}))
	quit(0 if failures.is_empty() else 1)

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func cross_sections(row: Dictionary) -> Array[Dictionary]:
	var normals: Array[Vector3] = []
	for point: Array in row.points:
		normals.append(Geo.surface(Vector3.UP,v2(point),RADIUS).normalized())
	var closed: bool = bool(row.closed)
	var sides: Array[Vector3] = Geo.path_sides(normals,closed)
	var sections: Array[Dictionary] = []
	for index: int in range(normals.size() if closed else normals.size()-1):
		var next: int = (index+1)%normals.size()
		var count: int = maxi(1,ceili(normals[index].angle_to(normals[next])*RADIUS/.10))
		for step: int in range(count+1):
			var weight: float = float(step)/count
			var centre: Vector3 = normals[index].slerp(normals[next],weight).normalized()*RADIUS
			var side: Vector3 = sides[index].lerp(sides[next],weight)
			var width: float = float(row.width)
			var strips: int = maxi(1,ceili(width*side.length()/.4))
			for strip: int in range(strips):
				var a: Vector3 = (centre+side*width*(float(strip)/strips-.5)).normalized()*RADIUS
				var b: Vector3 = (centre+side*width*(float(strip+1)/strips-.5)).normalized()*RADIUS
				sections.append({"a":a,"b":b,"centre":centre,"extent":width*.5*side.length(),"name":row.name})
	return sections

func nearest_walk(point: Vector2,info: Dictionary) -> Vector2:
	var edges: Array = []
	for index: int in range(info.loop.size()):
		edges.append([info.loop[index],info.loop[(index+1)%info.loop.size()]])
	for road: Array in info.roads:
		edges.append(road)
	for path: Array in info.paths:
		for index: int in range(path.size()-1):
			edges.append([path[index],path[index+1]])
	var result: Vector2 = point
	var nearest: float = INF
	for edge: Array in edges:
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(point,v2(edge[0]),v2(edge[1]))
		if candidate.distance_to(point)<nearest:
			nearest=candidate.distance_to(point)
			result=candidate
	return result
