extends RefCounted

## Build-time freshwater holes, with no per-pixel district/river loop at runtime.
## Only the visual Ocean mesh changes; PlanetCore and all walkable collisions stay intact.
const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const NEAR_WATER_MARGIN: float = 5.0
const OPENING_MARGIN: float = .10
const DETAIL_LEVELS: int = 2

static func apply(globe: Node3D, layout: Dictionary, districts: Array) -> void:
	var ocean: MeshInstance3D = globe.get_node_or_null("Ocean") as MeshInstance3D
	if ocean == null:
		push_error("Freshwater openings require the existing Globe/Ocean mesh.")
		return
	var radius: float = float(layout.radius)
	var material: Material = ocean.get_active_material(0)
	# Always rebuild from the same base sphere. Reapplying to a saved ArrayMesh
	# must not repeatedly subdivide it or accumulate opening/rounding errors.
	var source: SphereMesh = SphereMesh.new()
	source.radius = radius
	source.height = radius * 2.0
	source.radial_segments = 128
	source.rings = 64
	var arrays: Array = source.get_mesh_arrays()
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var regions: Array[Dictionary] = []
	for index: int in range(districts.size()):
		var data: Dictionary = districts[index]
		if (data.water as Array).is_empty():
			continue
		var normal_data: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(float(normal_data[0]),float(normal_data[1]),float(normal_data[2])).normalized()
		regions.append({"index":index,"data":data,"up":up,"axes":Geo.frame(up)})
	var output: SurfaceTool = SurfaceTool.new()
	output.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stats: Dictionary = {"source_triangles":0,"near_water_triangles":0,"output_triangles":0,"removed_leaf_triangles":0,"clipped_leaf_triangles":0,"detail_levels":DETAIL_LEVELS}
	for start: int in range(0,indices.size(),3):
		var a: Vector3 = positions[indices[start]]
		var b: Vector3 = positions[indices[start+1]]
		var c: Vector3 = positions[indices[start+2]]
		if (b-a).cross(c-a).length_squared() < .000000000001:
			continue
		stats.source_triangles += 1
		if _near_freshwater((a+b+c)/3.0,regions,radius):
			stats.near_water_triangles += 1
			_subdivide_and_clip(output,a,b,c,regions,radius,DETAIL_LEVELS,stats)
		else:
			_emit(output,a,b,c,stats)
	# Shared positions/normals are indexed, while the original seam and shoreline
	# geometry are retained exactly. All shading remains radial and world-space.
	output.index()
	var result: ArrayMesh = output.commit()
	if result == null:
		push_error("Freshwater opening builder did not produce an Ocean mesh.")
		return
	ocean.mesh = result
	ocean.material_override = material
	ocean.set_meta("freshwater_openings",true)
	ocean.set_meta("freshwater_opening_report",stats)
	if int(stats.output_triangles) >= 40000:
		push_warning("Freshwater Ocean mesh exceeded its 40000-triangle review budget: "+str(stats.output_triangles))
	print("FRESHWATER_OCEAN_OPENINGS "+JSON.stringify(stats))

static func _local(point: Vector3, region: Dictionary, radius: float) -> Vector2:
	var axes: Basis = region.axes as Basis
	var up: Vector3 = region.up as Vector3
	return Vector2(point.dot(axes.x),point.dot(axes.z))*radius/point.dot(up)

static func _island_edge_distance(point: Vector2, data: Dictionary, index: int) -> float:
	# Matches Ecology.edge_distance(), including its district-index coastline phase.
	var extent: Vector2 = Waterfront.v2(data.extent)
	var local: Vector2 = point/extent
	var angle: float = local.angle()
	var edge: float = 1.0+.045*sin(angle*3.0+float(index))+.035*cos(angle*5.0-float(index))
	return (edge-local.length())*minf(extent.x,extent.y)

static func _near_freshwater(point: Vector3, regions: Array[Dictionary], radius: float) -> bool:
	for region: Dictionary in regions:
		var up: Vector3 = region.up as Vector3
		if point.dot(up) < radius*.60:
			continue
		var p: Vector2 = _local(point,region,radius)
		var data: Dictionary = region.data
		if _island_edge_distance(p,data,int(region.index)) < -NEAR_WATER_MARGIN:
			continue
		if Waterfront.water_distance(p,data) < NEAR_WATER_MARGIN:
			return true
	return false

static func _outside_distance(point: Vector3, regions: Array[Dictionary], radius: float) -> float:
	# Intersection of lake/river interior and island interior, then union across
	# districts. Positive retains the ocean; negative opens a freshwater basin.
	var distance: float = INF
	for region: Dictionary in regions:
		var up: Vector3 = region.up as Vector3
		if point.dot(up) < radius*.60:
			continue
		var p: Vector2 = _local(point,region,radius)
		var data: Dictionary = region.data
		var coast: float = _island_edge_distance(p,data,int(region.index))
		var water: float = Waterfront.water_distance(p,data)-OPENING_MARGIN
		distance = minf(distance,maxf(water,-coast))
	return distance

static func _subdivide_and_clip(output: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, regions: Array[Dictionary], radius: float, levels: int, stats: Dictionary) -> void:
	if levels > 0:
		# Linear midpoint interpolation deliberately preserves the source triangle
		# planes. Renormalizing midpoints to the sphere would create curved cracks
		# where a refined triangle meets an unrefined neighbour (a T junction).
		var ab: Vector3 = (a+b)*.5
		var bc: Vector3 = (b+c)*.5
		var ca: Vector3 = (c+a)*.5
		_subdivide_and_clip(output,a,ab,ca,regions,radius,levels-1,stats)
		_subdivide_and_clip(output,ab,b,bc,regions,radius,levels-1,stats)
		_subdivide_and_clip(output,ca,bc,c,regions,radius,levels-1,stats)
		_subdivide_and_clip(output,ab,bc,ca,regions,radius,levels-1,stats)
		return
	var polygon: Array[Vector3] = [a,b,c]
	var distances: Array[float] = [_outside_distance(a,regions,radius),_outside_distance(b,regions,radius),_outside_distance(c,regions,radius)]
	var clipped: Array[Vector3] = []
	for index: int in range(3):
		var next: int = (index+1)%3
		var keep: bool = distances[index] >= 0.0
		var keep_next: bool = distances[next] >= 0.0
		if keep:
			clipped.append(polygon[index])
		if keep != keep_next:
			clipped.append(_boundary(polygon[index],polygon[next],keep,regions,radius))
	if clipped.size() < 3:
		stats.removed_leaf_triangles += 1
		return
	if clipped.size() != 3 or distances.min() < 0.0:
		stats.clipped_leaf_triangles += 1
	for index: int in range(1,clipped.size()-1):
		_emit(output,clipped[0],clipped[index],clipped[index+1],stats)

static func _boundary(a: Vector3, b: Vector3, a_is_outside: bool, regions: Array[Dictionary], radius: float) -> Vector3:
	# Solve the shared nonlinear contour along the original straight mesh edge.
	# A linear distance ratio alone visibly drifts at wavy shores and river bends.
	var low: float = 0.0
	var high: float = 1.0
	for _iteration: int in range(18):
		var middle: float = (low+high)*.5
		var outside: bool = _outside_distance(a.lerp(b,middle),regions,radius) >= 0.0
		if outside == a_is_outside:
			low = middle
		else:
			high = middle
	return a.lerp(b,(low+high)*.5)

static func _emit(output: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, stats: Dictionary) -> void:
	if (b-a).cross(c-a).length_squared() < .000000000001:
		return
	Geo.triangle(output,a,b,c,Color.WHITE)
	stats.output_triangles += 1
