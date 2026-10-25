extends RefCounted

## Rejected experimental fixture: CPU cost exceeded the native AA savings.
## Not connected to world_minimap and intentionally kept outside scripts/.
## Coordinates and positive width must use the same local canvas space.
## Returns original contiguous slices, never new intersections or resampling.
const SHORT_LINE_POINTS: int = 24

static func visible_runs(points: PackedVector2Array, viewport: Rect2, width: float) -> Array[PackedVector2Array]:
	var count: int = points.size()
	if count < 2:
		return []
	# Negative width uses device-pixel hairlines, whose local extent depends on
	# the caller's transform. Unknown/non-finite inputs are never culled.
	if count <= SHORT_LINE_POINTS or not is_finite(width) or width < 0.0 or not viewport.position.is_finite() or not viewport.size.is_finite() or viewport.size.x <= 0.0 or viewport.size.y <= 0.0:
		return [points]
	# Verified against local Godot 4.7.2 renderer_canvas_cull.cpp:
	# FEATHER_SIZE=1.25; compensated AA width never exceeds input width;
	# edge_offset_clamped has length <=3, including the feather offset.
	# 3*max(width,1)+6 exceeds 3*(width/2+1.25), with extra cap slack.
	var margin: float = maxf(width, 1.0) * 3.0 + 6.0
	var padded: Rect2 = viewport.grow(margin)
	if not padded.position.is_finite() or not padded.end.is_finite():
		return [points]
	var lower: Vector2 = padded.position
	var upper: Vector2 = padded.end
	var intervals: Array[Vector2i] = []
	var first_segment: int = -1
	for index: int in range(count - 1):
		var a: Vector2 = points[index]
		var b: Vector2 = points[index + 1]
		# The renderer carries previous direction across coincident points.
		# A local cut could change that history, so preserve the whole stroke.
		if not a.is_finite() or not b.is_finite() or (b - a).is_zero_approx():
			return [points]
		# Inclusive AABB intersection deliberately admits false positives, e.g.
		# a diagonal missing a corner. It must not reject a crossing segment.
		var selected: bool = not (maxf(a.x,b.x) < lower.x or minf(a.x,b.x) > upper.x or maxf(a.y,b.y) < lower.y or minf(a.y,b.y) > upper.y)
		if selected and first_segment < 0:
			first_segment = index
		elif not selected and first_segment >= 0:
			_append_interval(intervals, maxi(0,first_segment-1), mini(count-1,index+1))
			first_segment = -1
	if first_segment >= 0:
		_append_interval(intervals, maxi(0,first_segment-1), count-1)
	if intervals.is_empty():
		return []
	var closed: bool = points[0].is_equal_approx(points[count-1])
	if closed and (intervals[0].x == 0 or intervals[-1].y == count-1):
		# Never rebuild a closed seam or turn its join into two end caps.
		return [points]
	if intervals.size() == 1 and intervals[0] == Vector2i(0,count-1):
		return [points]
	var result: Array[PackedVector2Array] = []
	for interval: Vector2i in intervals:
		if points[interval.x].is_equal_approx(points[interval.y]):
			# A cut that accidentally looks closed changes Godot's cap policy.
			return [points]
		result.append(points.slice(interval.x, interval.y+1))
	return result

static func _append_interval(intervals: Array[Vector2i], first: int, last: int) -> void:
	# Expanded runs share their original neighbour segments. Merge touching
	# slices rather than drawing them twice (AA/alpha would otherwise change).
	if not intervals.is_empty() and first <= intervals[-1].y + 1:
		intervals[-1] = Vector2i(intervals[-1].x,last)
	else:
		intervals.append(Vector2i(first,last))
