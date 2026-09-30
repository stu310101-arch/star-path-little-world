extends RefCounted

static func directions() -> Array[Vector3]:
	return [Vector3.UP,Vector3.RIGHT,Vector3.FORWARD,Vector3.LEFT,Vector3.BACK,Vector3.DOWN]

static func bridge_edges() -> Array[Vector2i]:
	return [Vector2i(0,1),Vector2i(0,2),Vector2i(0,3),Vector2i(0,4),Vector2i(5,1),Vector2i(5,2),Vector2i(5,3),Vector2i(5,4),Vector2i(1,2),Vector2i(2,3),Vector2i(3,4),Vector2i(4,1)]

static func bridge_limits() -> Vector2:
	return Vector2(.375,.625)

static func approach_extent(radius: float) -> float:
	return radius*tan(bridge_limits().x*PI*.5)

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
	var end: float = approach_extent(radius)
	var starts: Array[float] = [15.0,15.0,15.0,15.0]
	match str(info.station):
		"counseling": starts[3] = 22.0
		"admissions": starts[1] = 30.0
		"recommendations":
			starts[0] = 17.0
			starts[3] = 13.0
		"universities":
			starts[2] = 26.0
			starts[3] = 29.0
		"life":
			starts[1] = 19.0
			starts[2] = 17.0
	var axes: Array[Vector2] = [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]
	for i: int in range(axes.size()):
		paths.append([[axes[i].x*starts[i],axes[i].y*starts[i]],[axes[i].x*end,axes[i].y*end]])
	return paths
