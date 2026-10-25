extends RefCounted

## Shared outdoor geography. Coast geometry, bridge endpoints and map outlines
## consume the same signed distance; positive is dry, negative is open sea.
static var _data: Dictionary = {}

static func spec(id: String) -> Dictionary:
	if _data.is_empty():
		_data=JSON.parse_string(FileAccess.get_file_as_string("res://data/biomes.json")) as Dictionary
	return _data.get(id,{}) as Dictionary

static func coast_distance(point: Vector2, info: Dictionary, index: int) -> float:
	var extent: Vector2=Vector2(float(info.extent[0]),float(info.extent[1]))
	var local: Vector2=point/extent
	var angle: float=local.angle()
	var edge: float=1.0+.105*sin(angle*3.0+float(index)*.83)+.063*cos(angle*5.0-float(index)*.64)+.026*sin(angle*7.0+.4)
	var shore: float=(edge-local.length())*minf(extent.x,extent.y)
	if info.has("compact_coast_max"):
		# Keep the human-sized town intact while fitting its coastline between
		# neighbouring faces of the smaller planet.
		var ray: Vector2=point.normalized() if point.length_squared()>.0001 else Vector2.RIGHT
		var coast_radius: float=edge/(ray/extent).length()
		shore=clampf(coast_radius,float(info.get("compact_coast_min",45.0)),float(info.compact_coast_max))-point.length()
	if str(info.station)=="admissions":
		# Open eastern estuary preserves the working 32–41 m harbor. The bay
		# widens seaward into two headlands instead of burying the pier inland.
		var width: float=7.5+maxf(point.x-29.0,0.0)*.32
		shore=minf(shore,maxf(29.0-point.x,absf(point.y-6.0)-width))
	return shore

static func water_distance(point: Vector2, info: Dictionary) -> float:
	var distance: float=INF
	for water: Dictionary in spec(str(info.station)).get("waters",[]):
		if str(water.kind)=="lake":
			var size: Vector2=Vector2(water.size[0],water.size[1])
			var local: Vector2=(point-Vector2(water.center[0],water.center[1]))/size
			var edge: float=1.0+.07*sin(local.angle()*3.0)+.04*cos(local.angle()*5.0)
			distance=minf(distance,(local.length()-edge)*minf(size.x,size.y))
		else:
			for i: int in range(water.points.size()-1):
				var a: Vector2=Vector2(water.points[i][0],water.points[i][1])
				var b: Vector2=Vector2(water.points[i+1][0],water.points[i+1][1])
				distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))-float(water.width)*.5)
	return distance

static func relief(point: Vector2, info: Dictionary) -> float:
	var height: float=0.0
	for ridge: Array in spec(str(info.station)).get("ridges",[]):
		var a: Vector2=Vector2(ridge[0],ridge[1])
		var b: Vector2=Vector2(ridge[2],ridge[3])
		var distance: float=point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b))/float(ridge[4])
		var shape: float=1.0-smoothstep(0.0,1.0,clampf(distance,0.0,1.0))
		height=maxf(height,float(ridge[5])*shape)
	return height

static func smooth_min(a: float,b: float,width: float) -> float:
	var h: float=maxf(width-absf(a-b),0.0)/width
	return minf(a,b)-h*h*width*.25

static func trail_distance(point: Vector2,info: Dictionary) -> float:
	var distance: float=INF
	for trail: Array in spec(str(info.station)).get("trails",[]):
		for i: int in range(trail.size()-1):
			var a: Vector2=Vector2(trail[i][0],trail[i][1])
			var b: Vector2=Vector2(trail[i+1][0],trail[i+1][1])
			distance=minf(distance,point.distance_to(Geometry2D.get_closest_point_to_segment(point,a,b)))
	return distance

static func tree_rows(info: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary]=[]
	var cluster_index: int=0
	for cluster: Array in spec(str(info.station)).get("clusters",[]):
		var count: int=int(cluster[4])
		for i: int in range(count):
			# A designed grove footprint with a soft density falloff and open
			# outside edge; deterministic phyllotaxis, never whole-map scatter.
			var angle: float=float(i)*2.39996323+float(cluster_index)*.71
			var radial: float=sqrt((float(i)+.5)/float(count))
			var p: Vector2=Vector2(cluster[0],cluster[1])+Vector2(cos(angle)*float(cluster[2]),sin(angle)*float(cluster[3]))*radial
			result.append({"p":p,"kind":str(cluster[5]),"scale":float(cluster[6])*(.86+.20*float(i%5)/4.0),"yaw":angle,"group":"Wild grove %02d"%cluster_index})
		cluster_index+=1
	return result
