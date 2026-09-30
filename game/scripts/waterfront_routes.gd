extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const WIDTH: float = 2.2
const HEIGHT: float = .26
const SAMPLE_LENGTH: float = .28
const BANK_LANDING: float = .9

static func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

static func water_distance(point: Vector2, data: Dictionary) -> float:
	var distance: float = INF
	for water: Dictionary in data.water:
		if str(water.kind) == "lake":
			var size: Vector2 = v2(water.size)
			var local: Vector2 = (point-v2(water.center))/size
			var angle: float = local.angle()
			var edge: float = 1.0+.10*sin(angle*3.0)+.055*cos(angle*5.0)
			distance = minf(distance,(local.length()-edge)*minf(size.x,size.y))
		else:
			for i: int in range(water.points.size()-1):
				var a: Vector2 = v2(water.points[i])
				var b: Vector2 = v2(water.points[i+1])
				var nearest: Vector2 = a+(b-a)*clampf((point-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
				distance = minf(distance,point.distance_to(nearest)-float(water.width)*.5)
	return distance

# Both paving and timber consume this exact partition. A span has one owner;
# there is no independently sampled grey ribbon hidden under the boardwalk.
static func samples(up: Vector3, path: Array, data: Dictionary, radius: float, width: float = WIDTH) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if path.size() < 2:
		return result
	var normals: Array[Vector3] = []
	for point: Array in path:
		normals.append(Geo.surface(up,v2(point),radius).normalized())
	var sides: Array[Vector3] = Geo.path_sides(normals)
	var maximum_miter: float = 1.0
	for side: Vector3 in sides:
		maximum_miter = maxf(maximum_miter,side.length())
	var cross_steps: int = maxi(1,ceili(width*maximum_miter/.28))
	var distance: float = 0.0
	for j: int in range(path.size()-1):
		var a: Vector2 = v2(path[j])
		var b: Vector2 = v2(path[j+1])
		var count: int = maxi(1,ceili(a.distance_to(b)/SAMPLE_LENGTH))
		for k: int in range(count):
			var t: float = float(k)/count
			result.append({"p":a.lerp(b,t),"normal":Geo.surface(up,a.lerp(b,t),radius).normalized(),"side":sides[j].lerp(sides[j+1],t),"distance":distance+a.distance_to(b)*t,"cross_steps":cross_steps,"corner":k == 0,"wet":false})
		distance += a.distance_to(b)
	result.append({"p":v2(path[-1]),"normal":normals[-1],"side":sides[-1],"distance":distance,"cross_steps":cross_steps,"corner":true,"wet":false})
	for i: int in range(result.size()-1):
		var p: Vector2 = result[i].p
		var q: Vector2 = result[i+1].p
		var middle: Vector2 = (p+q)*.5
		var side: Vector2 = Vector2(-(q-p).y,(q-p).x).normalized()*width*.5
		var bank_distance: float = minf(water_distance(middle,data),minf(water_distance(middle-side,data),water_distance(middle+side,data)))
		result[i].wet = bank_distance < BANK_LANDING
	return result

static func at(sample: Dictionary, radius: float, height: float, lateral: float) -> Vector3:
	# Lateral placement always uses the same base radius, irrespective of height.
	# Projecting once at each material's height shifts the edges on a tiny planet.
	var normal: Vector3 = sample.normal
	var side: Vector3 = sample.side
	return (normal*radius+side*lateral).normalized()*(radius+height)

static func between(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var a_normal: Vector3 = a.normal
	var b_normal: Vector3 = b.normal
	var a_side: Vector3 = a.side
	var b_side: Vector3 = b.side
	return {"normal":a_normal.slerp(b_normal,t).normalized(),"side":a_side.lerp(b_side,t),"cross_steps":a.cross_steps}

static func strip(st: SurfaceTool, a: Dictionary, b: Dictionary, radius: float, height: float, width: float, color: Color) -> void:
	var count: int = int(a.cross_steps)
	for i: int in range(count):
		var left: float = width*(float(i)/count-.5)
		var right: float = width*(float(i+1)/count-.5)
		var p0: Vector3 = at(a,radius,height,left)
		var p1: Vector3 = at(a,radius,height,right)
		var p2: Vector3 = at(b,radius,height,right)
		var p3: Vector3 = at(b,radius,height,left)
		Geo.triangle(st,p0,p1,p2,color)
		Geo.triangle(st,p0,p2,p3,color)

static func deck_mesh(route: Array[Dictionary], radius: float, height: float, width: float, wet: bool) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var span_count: int = 0
	for i: int in range(route.size()-1):
		if bool(route[i].wet) != wet:
			continue
		span_count += 1
		if not wet:
			strip(st,route[i],route[i+1],radius,height,width,Color.WHITE)
			continue
		var joint: Dictionary = between(route[i],route[i+1],.955)
		var wood: Color = Color("b69b76").lightened(sin(float(i)*2.73)*.055)
		strip(st,route[i],joint,radius,height,width,wood)
		strip(st,joint,route[i+1],radius,height,width,Color("786852"))
	return st.commit() if span_count > 0 else null

static func face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color, outward: Vector3) -> void:
	var vertices: Array[Vector3] = [a,b,c,a,c,d]
	if (b-a).cross(c-a).dot(outward) > 0.0:
		vertices = [a,c,b,a,d,c]
	for i: int in [0,3]:
		# A triangular cap uses its first point again as d; omit the empty half.
		if (vertices[i+1]-vertices[i]).cross(vertices[i+2]-vertices[i]).length_squared() < .000000000001:
			continue
		for j: int in range(3):
			st.set_color(color)
			st.set_normal(outward.normalized())
			st.add_vertex(vertices[i+j])

# Eight-sided rectangular timber has a restrained chamfer, without one node or
# material per plank, post and rail. Hardware shares one mesh per reserve.
static func beam(st: SurfaceTool, a: Vector3, b: Vector3, width: float, height: float, color: Color) -> void:
	var direction: Vector3 = (b-a).normalized()
	var hint: Vector3 = (a+b).normalized()
	if absf(direction.dot(hint)) > .95:
		hint = Geo.frame(hint).x
	var right: Vector3 = direction.cross(hint).normalized()
	var top: Vector3 = right.cross(direction).normalized()
	var bevel: float = minf(width,height)*.17
	var w: float = width*.5
	var h: float = height*.5
	var profile: Array[Vector2] = [Vector2(-w+bevel,-h),Vector2(w-bevel,-h),Vector2(w,-h+bevel),Vector2(w,h-bevel),Vector2(w-bevel,h),Vector2(-w+bevel,h),Vector2(-w,h-bevel),Vector2(-w,-h+bevel)]
	for i: int in range(profile.size()):
		var p: Vector2 = profile[i]
		var q: Vector2 = profile[(i+1)%profile.size()]
		var offset_a: Vector3 = right*p.x+top*p.y
		var offset_b: Vector3 = right*q.x+top*q.y
		face(st,a+offset_a,b+offset_a,b+offset_b,a+offset_b,color,(offset_a+offset_b).normalized())
		face(st,a,a+offset_b,a+offset_a,a,color,-direction)
		face(st,b,b+offset_a,b+offset_b,b,color,direction)
