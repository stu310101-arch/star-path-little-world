extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const WIDTH: float = 2.4
const LAYOUT_VERSION: int = 4

static func grove_up() -> Vector3:
	return Vector3(.75,1.0,.85).normalized()

static func bridge_start() -> Vector3:
	return Vector3.UP.slerp(grove_up(),.70)

static func bridge_finish() -> Vector3:
	return Vector3.UP.slerp(grove_up(),.90)

static func town_endpoint(radius: float = 48.0) -> Vector3:
	return Geo.surface(Vector3.UP,Vector2(10,17.4),radius).normalized()

static func garden_endpoint() -> Vector3:
	return grove_up()

static func entry_offset(radius: float = 48.0) -> Vector2:
	var up: Vector3 = grove_up()
	var axes: Basis = Geo.frame(up)
	var normal: Vector3 = bridge_finish()
	return Vector2(normal.dot(axes.x),normal.dot(axes.z))*radius/normal.dot(up)

static func rounded_outline(points: Array[Vector2],steps: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for i: int in range(points.size()):
		var a: Vector2 = points[(i-1+points.size())%points.size()]
		var b: Vector2 = points[i]
		var c: Vector2 = points[(i+1)%points.size()]
		var d: Vector2 = points[(i+2)%points.size()]
		for j: int in range(steps):
			result.append(b.cubic_interpolate(c,a,d,float(j)/steps))
	return result

static func island_outline() -> PackedVector2Array:
	# A hand-shaped bank follows the two overlooks and the northern blossom lawn.
	return rounded_outline([Vector2(-8.6,-3.6),Vector2(-4.5,-7.6),Vector2(1.8,-7.7),Vector2(7.0,-5.2),Vector2(9.0,0.0),Vector2(7.2,5.8),Vector2(1.0,8.2),Vector2(-5.9,7.1),Vector2(-9.0,2.0)],16)

static func paths(radius: float = 48.0) -> Array:
	var entry: Vector2 = entry_offset(radius)
	var ring: PackedVector2Array = rounded_outline([Vector2(0,0),Vector2(3,0),Vector2(4.8,2.2),Vector2(3.6,4.8),Vector2(0,5.5),Vector2(-3.6,4.8),Vector2(-4.8,2.2),Vector2(-3,0)],8)
	var loop: Array = []
	for point: Vector2 in ring:
		loop.append([point.x,point.y])
	loop.append(loop[0].duplicate())
	return [[[entry.x,entry.y],[0.0,0.0]],loop]

static func platforms() -> Array[PackedVector2Array]:
	var east: PackedVector2Array = PackedVector2Array([Vector2(5.55,.8),Vector2(7.9,.8),Vector2(8.25,1.15),Vector2(8.25,3.2),Vector2(7.9,3.55),Vector2(5.55,3.55)])
	var west: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in east:
		west.append(Vector2(-point.x,point.y))
	return [east,west]

static func destinations() -> Array[Dictionary]:
	return [{"id":"EastWaterView","kind":"viewpoint","position":Vector2(6.1,2.15),"label":"海景觀景台"},{"id":"WestCanopyView","kind":"viewpoint","position":Vector2(-6.1,2.15),"label":"樹影休憩台"}]

static func overlook_guard_paths() -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for platform: PackedVector2Array in platforms():
		var guard: PackedVector2Array = platform.duplicate()
		# Guard the outer drop with only short corner returns. Long returns made
		# each small terrace read like a cage and squeezed the bench side aisles.
		# The complete 2.75 m path-facing edge stays visibly open.
		guard[0].x = signf(guard[0].x)*7.8
		guard[-1].x = signf(guard[-1].x)*7.8
		result.append(guard)
	return result

static func seats() -> Array[Dictionary]:
	# The bench front is local -Z. Put the backs near the outer guards so the
	# seat fronts, standing space and garden loop form one direct approach.
	return [{"id":"EastViewBench","position":Vector2(7.65,2.15),"yaw":PI*.5,"approach":Vector2(6.55,2.15)},{"id":"WestViewBench","position":Vector2(-7.65,2.15),"yaw":-PI*.5,"approach":Vector2(-6.55,2.15)}]

static func lights(radius: float = 48.0) -> Array[Vector2]:
	var entry: Vector2 = entry_offset(radius)
	var along: Vector2 = -entry.normalized()
	var side: Vector2 = Vector2(-along.y,along.x)
	return [entry+side*1.9,entry-side*1.9,Vector2(6.6,3.15),Vector2(-6.6,3.15),Vector2(2.9,6.95),Vector2(-2.9,6.95)]

static func trees() -> Array[Dictionary]:
	# An open arrival lawn separates the southern and northern blossom groups.
	# The central specimen stays tall with a narrower crown clear of the exit view.
	return [
		{"position":Vector2(-1.6,-5.2),"yaw":1.1,"scale":.88,"variant":1},
		{"position":Vector2(1.4,-5.6),"yaw":-.35,"scale":.94,"variant":2},
		{"position":Vector2(4.7,-4.7),"yaw":.7,"scale":.9,"variant":0},
		{"position":Vector2(7.0,-2.4),"yaw":1.4,"scale":.80,"variant":1},
		{"position":Vector2(-7.2,-1.1),"yaw":-.8,"scale":.9,"variant":2},
		{"position":Vector2(-7.3,5.0),"yaw":.4,"scale":.82,"variant":0},
		{"position":Vector2(-4.5,6.8),"yaw":1.0,"scale":.86,"variant":1},
		{"position":Vector2(-1.8,7.5),"yaw":-.2,"scale":.88,"variant":2},
		{"position":Vector2(1.5,7.3),"yaw":.8,"scale":.90,"variant":0},
		{"position":Vector2(4.8,6.4),"yaw":-.5,"scale":.84,"variant":1},
		{"position":Vector2(7.3,4.9),"yaw":1.2,"scale":.80,"variant":2},
		{"position":Vector2(-.6,3.15),"yaw":-.4,"scale":.9,"width_scale":.8,"variant":1}
	]
