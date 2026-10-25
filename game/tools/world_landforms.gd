extends RefCounted

## Editable, authored relief for the six reserves. These are broad land masses,
## not random object scatter. All protected urban surfaces retain their height.
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const Arrivals = preload("res://tools/world_station_arrivals.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
const RIDGES: Dictionary = {
	"counseling": [[-25.0,-18.0,9.0,6.0,1.7],[-31.0,-1.0,3.8,7.0,.8]],
	"admissions": [[30.0,12.0,5.0,12.0,1.7],[-25.0,21.0,8.0,5.0,.9]],
	"recommendations": [[-17.0,-24.0,12.0,5.0,1.6],[28.0,3.0,4.5,8.0,1.2]],
	"universities": [[-16.0,29.0,11.0,4.5,1.9],[24.0,-19.0,6.0,7.0,1.0]],
	"life": [[-29.0,2.0,4.5,11.0,2.1],[-13.0,29.0,10.0,4.5,1.6]],
	"wordking": [[29.0,9.0,6.0,7.0,1.5],[12.0,26.0,8.0,4.5,1.1]]
}
var data: Dictionary
var district_index: int
var radius: float
var up: Vector3
var axes: Basis
var protected_edges: Array[Dictionary] = []
var buildings: Array[Dictionary] = []
var height_cache: Dictionary = {}
var normal_cache: Dictionary = {}
var maximum_height: float = .165
var raised_vertices: int = 0

func configure(info: Dictionary, index: int, planet_radius: float, normal: Vector3) -> void:
	data = info
	district_index = index
	radius = planet_radius
	up = normal
	axes = Geo.frame(up)
	for path: Array in Routes.district_paths(data, radius):
		for segment: int in range(path.size()-1):
			protect(v2(path[segment]), v2(path[segment+1]), 1.75)
	var road_edges: Array = (data.roads as Array).duplicate(true)
	for index_in_loop: int in range(data.loop.size()):
		road_edges.append([data.loop[index_in_loop], data.loop[(index_in_loop+1)%data.loop.size()]])
	for edge: Array in road_edges:
		protect(v2(edge[0]), v2(edge[1]), 3.85)
	for building: Dictionary in data.urban_buildings:
		var centre: Vector2 = v2(building.offset)
		var yaw: float = deg_to_rad(float(building.yaw))
		buildings.append({"centre": centre, "yaw": yaw, "half": Vector2(float(building.get("max_width",5.4)), float(building.get("max_depth",5.5))) * .5 + Vector2.ONE * .8})
		var forward: Vector2 = Vector2(sin(yaw), cos(yaw))
		var door: Vector2 = centre + forward * float(building.get("front",2.8))
		var nearest: Vector2 = door
		var best: float = INF
		for edge: Dictionary in protected_edges:
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(door, edge.a, edge.b)
			if candidate.distance_to(door) < best:
				best = candidate.distance_to(door)
				nearest = candidate
		protect(door, nearest, 1.35)
	var civic: Vector2 = v2(data.civic)
	protect(civic + Vector2(0,-2.6), civic + Vector2(0,1.8), 2.2)
	protect(civic, civic + Arrivals.arrival_offset(str(data.station)), 1.9)
	# Furniture is authored on the original level ground; preserve its full bay.
	for garden: Array in data.gardens:
		protect(v2(garden), v2(garden)+Vector2(2,0), 2.1)
	if str(data.station) == "admissions":
		protect(Vector2(30,6), Vector2(42,6), 3.5)
	if str(data.station) == "counseling":
		# Sakura's stone approach is a level route all the way to the outer coast.
		# Its tangent line is the same great-circle arc as SakuraRoutes.plan.
		protect(Vector2(10,17.4), preload("res://scripts/sakura_routes.gd").grove_offset(), 2.0)

func protect(a: Vector2, b: Vector2, half_width: float) -> void:
	protected_edges.append({"a":a, "b":b, "half_width":half_width})

static func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func dry_distance(point: Vector2) -> float:
	return minf(Biomes.coast_distance(point,data,district_index),Waterfront.water_distance(point,data))

func clearance(point: Vector2) -> float:
	var result: float = INF
	for edge: Dictionary in protected_edges:
		result = minf(result, point.distance_to(Geometry2D.get_closest_point_to_segment(point,edge.a,edge.b)) - float(edge.half_width))
	for building: Dictionary in buildings:
		var local: Vector2 = (point - (building.centre as Vector2)).rotated(float(building.yaw))
		var q: Vector2 = local.abs() - (building.half as Vector2)
		result = minf(result, q.max(Vector2.ZERO).length() + minf(maxf(q.x,q.y),0.0))
	return result

func height_at(point: Vector2) -> float:
	if height_cache.has(point):
		return float(height_cache[point])
	var shore: float = dry_distance(point)
	var original: float = .09 + .075*smoothstep(0.0,1.1,shore)
	var reserve_weight: float = smoothstep(0.0,3.1,clearance(point))
	var rise: float = .34 * (1.0-smoothstep(1.2,5.0,shore))
	for ridge: Array in RIDGES[str(data.station)]:
		var local: Vector2 = (point-Vector2(ridge[0],ridge[1])) / Vector2(ridge[2],ridge[3])
		var distance: float = local.length()
		if distance < 1.0:
			var shape: float = 1.0 - smoothstep(0.0,1.0,distance)
			rise += float(ridge[4]) * shape
	# A smooth cap preserves broad silhouettes while staying below the current
	# 1.4 m ground-probe ceiling, without flat-topping the authored ridges.
	var h: float = original + 1.1 * (1.0-exp(-rise*reserve_weight/1.1))
	# The 45 m city stays intact. Broad outdoor ridges grow from its edge and
	# taper along shores and roads with height-dependent, walkable shoulders.
	var outer: float=Biomes.relief(point,data)
	var margin: float=minf(maxf(point.length()-45.0,0.0),minf(maxf(clearance(point),0.0),maxf(shore-.15,0.0)))
	var shoulder_limit: float=margin*.28
	var outdoor_height: float=maxf(0.0,Biomes.smooth_min(outer,shoulder_limit,2.4))
	h+=outdoor_height
	height_cache[point] = h
	maximum_height = maxf(maximum_height,h)
	if h > original + .08:
		raised_vertices += 1
	return h

func point_at(point: Vector2, h: float) -> Vector3:
	return Geo.surface(up,point,radius).normalized() * (radius+h)

func mesh_height_at(point: Vector2) -> float:
	# Plant roots use the exact coarse terrain triangle, not the smooth field
	# above its chord. This prevents floating trees on 4.8 m outdoor cells.
	var bounds: Array[Vector2]=[]
	for value: float in [point.x,point.y]:
		var origin: float=48.0 if value>48.0 else -48.0 if value< -48.0 else 0.0
		var step: float=4.8 if absf(value)>48.0 else .8
		var low: float=origin+floor((value-origin)/step)*step
		bounds.append(Vector2(low,low+step))
	var a: Vector2=Vector2(bounds[0].x,bounds[1].x)
	var b: Vector2=Vector2(bounds[0].y,bounds[1].x)
	var c: Vector2=Vector2(bounds[0].y,bounds[1].y)
	var d: Vector2=Vector2(bounds[0].x,bounds[1].y)
	var fraction: Vector2=(point-a)/Vector2(bounds[0].y-bounds[0].x,bounds[1].y-bounds[1].x)
	var triangle: Array[Vector2]=[a,b,c]
	if fraction.x<fraction.y:
		triangle=[a,c,d]
	var pa: Vector3=point_at(triangle[0],height_at(triangle[0]))
	var pb: Vector3=point_at(triangle[1],height_at(triangle[1]))
	var pc: Vector3=point_at(triangle[2],height_at(triangle[2]))
	var normal: Vector3=(pb-pa).cross(pc-pa)
	var radial: Vector3=Geo.surface(up,point,radius).normalized()
	return normal.dot(pa)/normal.dot(radial)-radius

func normal_at(point: Vector2) -> Vector3:
	if normal_cache.has(point):
		return normal_cache[point] as Vector3
	var epsilon: float = .08
	var xa: Vector2 = point-Vector2(epsilon,0)
	var xb: Vector2 = point+Vector2(epsilon,0)
	var za: Vector2 = point-Vector2(0,epsilon)
	var zb: Vector2 = point+Vector2(0,epsilon)
	# Differentiate the projection before converting to world-space positions.
	# Subtracting nearly equal positions around a 1200 m radius lost precision
	# in the 8 cm samples and made otherwise smooth slopes shade unevenly.
	var projected: Vector3 = up*radius+axes.x*point.x+axes.z*point.y
	var radial: Vector3 = projected.normalized()
	var scale: float = (radius+height_at(point))/projected.length()
	var dx: float = (height_at(xb)-height_at(xa))/(epsilon*2.0)
	var dz: float = (height_at(zb)-height_at(za))/(epsilon*2.0)
	var x_axis: Vector3 = (axes.x-radial*radial.dot(axes.x))*scale+radial*dx
	var z_axis: Vector3 = (axes.z-radial*radial.dot(axes.z))*scale+radial*dz
	var normal: Vector3 = z_axis.cross(x_axis).normalized()
	normal_cache[point] = normal
	return normal

func surface_blend_at(point: Vector2) -> Vector2:
	# Continuous channels are interpolated through one shared ground mesh.
	# Damp soil follows shoreline distance even on a raised bank. Rock fades
	# into it over metres; no height/triangle threshold creates a material seam.
	var shore: float = dry_distance(point)
	var soil: float = 1.0-smoothstep(.15,2.6,shore)
	var bank: float = (1.0-smoothstep(.5,3.6,shore))*smoothstep(.02,.32,height_at(point)-.165)
	var rock: float = bank*smoothstep(.1,1.8,clearance(point))*.68
	var outer_weight: float=smoothstep(42.0,72.0,point.length())
	var route_soil: float=1.0-smoothstep(1.2,2.4,Biomes.trail_distance(point,data))
	soil=maxf(soil,route_soil*outer_weight)
	var ridge_rock: float=smoothstep(8.0,22.0,height_at(point))*.6
	if str(data.station) in ["admissions","recommendations"]:
		ridge_rock=maxf(ridge_rock,.38*outer_weight)
	rock=maxf(rock,ridge_rock*outer_weight)
	return Vector2(soil,rock)

func add_shore_wall(st: SurfaceTool, a: Vector2, b: Vector2) -> void:
	if a.distance_to(b) < .015:
		return
	var middle: Vector2 = (a+b)*.5
	var delta: float = .04
	var gradient: Vector2 = Vector2(dry_distance(middle+Vector2(delta,0))-dry_distance(middle-Vector2(delta,0)), dry_distance(middle+Vector2(0,delta))-dry_distance(middle-Vector2(0,delta))).normalized()
	var outward: Vector3 = -(axes.x*gradient.x + axes.z*gradient.y).normalized()
	var top_a: float = height_at(a)
	var top_b: float = height_at(b)
	for band: int in range(3):
		var ta: float = float(band)/3.0
		var tb: float = float(band+1)/3.0
		var color: Color = [Color("8d8777"),Color("706e64"),Color("525d58")][band]
		var p0: Vector3 = point_at(a,lerpf(top_a,-.45,ta))
		var p1: Vector3 = point_at(b,lerpf(top_b,-.45,ta))
		var p2: Vector3 = point_at(b,lerpf(top_b,-.45,tb))
		var p3: Vector3 = point_at(a,lerpf(top_a,-.45,tb))
		face(st,p0,p1,p2,outward,color)
		face(st,p0,p2,p3,outward,color)

func face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, color: Color) -> void:
	if (b-a).cross(c-a).dot(normal) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
	for point: Vector3 in [a,b,c]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(point)

func statistics() -> Dictionary:
	return {"station":data.station,"authored_ridges":RIDGES[str(data.station)],"maximum_height_m":maximum_height,"raised_samples":raised_vertices,"protected_edges":protected_edges.size(),"same_visual_and_collision_mesh":true}
