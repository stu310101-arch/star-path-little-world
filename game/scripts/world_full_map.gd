extends Control

# Two orthographic hemispheres show the complete sphere without hiding the
# opposite districts. All outlines and routes come from the live minimap.
const SEA: Color = Color("173f4b")
const INK: Color = Color("edf1df")
var source: Control
var hemispheres: Array[Dictionary] = []
var surfaces: Array[Dictionary] = []
var lines: Array[Dictionary] = []
var markers: Array[Dictionary] = []
var _refresh_clock: float = 0.0
var _last_player_position: Vector3 = Vector3.INF
var _last_player_heading: Vector3 = Vector3.INF
var _marker_label_background: StyleBoxFlat

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_rebuild_geometry)
	visibility_changed.connect(_visibility_changed)
	set_process(false)

func configure(minimap: Control) -> void:
	source = minimap
	_rebuild_geometry()
	set_process(is_visible_in_tree())

func _visibility_changed() -> void:
	set_process(is_visible_in_tree() and source != null)
	if is_visible_in_tree():
		queue_redraw()

func _process(delta: float) -> void:
	_refresh_clock += delta
	if _refresh_clock < 0.2 or source == null:
		return
	_refresh_clock = 0.0
	var player: Node3D = source.get("player") as Node3D
	if is_instance_valid(player) and (player.global_position != _last_player_position or (player.get("heading") as Vector3) != _last_player_heading):
		_last_player_position = player.global_position
		_last_player_heading = player.get("heading") as Vector3
		queue_redraw()

func _rebuild_geometry() -> void:
	hemispheres.clear()
	surfaces.clear()
	lines.clear()
	markers.clear()
	if source == null or size.x < 1.0 or size.y < 1.0:
		return
	var stacked: bool = size.y > size.x * 0.9
	var cell: Vector2 = Vector2(size.x, size.y * 0.5) if stacked else Vector2(size.x * 0.5, size.y)
	var map_radius: float = maxf(18.0, minf((cell.x - 30.0) * 0.5, (cell.y - 45.0) * 0.5))
	for side: int in range(2):
		var normal: Vector3 = Vector3(1, 1, 1).normalized() * (1.0 if side == 0 else -1.0)
		var right: Vector3 = Vector3.UP.cross(normal).normalized()
		var top: Vector3 = normal.cross(right).normalized()
		var origin: Vector2 = Vector2(0, cell.y * side) if stacked else Vector2(cell.x * side, 0)
		var centre: Vector2 = origin + Vector2(cell.x * 0.5, cell.y * 0.5 + 8.0)
		hemispheres.append({"normal": normal, "right": right, "top": top, "center": centre, "radius": map_radius, "title": "正面" if side == 0 else "背面", "title_position": origin + Vector2(cell.x * 0.5, 20.0)})
	for hemisphere: Dictionary in hemispheres:
		for patch: Dictionary in source.get("patches"):
			_add_surface(patch.coast, patch.land as Color, hemisphere)
			_add_line(patch.coast, Color("a7baa0"), 1.1, hemisphere, true)
			for water: Dictionary in patch.water:
				_add_surface(water.points, Color("4a8990"), hemisphere)
			for road: PackedVector3Array in patch.roads:
				_add_line(road, Color("3a5554"), 2.0, hemisphere)
			for path: PackedVector3Array in patch.paths:
				_add_line(path, Color("d7c9aa"), 1.1, hemisphere)
			for boardwalk: PackedVector3Array in patch.get("boardwalks", []):
				_add_line(boardwalk, Color("ecd7ad"), 1.4, hemisphere)
		for bridge: PackedVector3Array in source.get("bridges"):
			_add_line(bridge, Color("ffe1a6"), 2.0, hemisphere)
	for landmark: Dictionary in source.get("landmarks"):
		var point: Vector3 = landmark.point as Vector3
		var side: int = 0 if point.dot(hemispheres[0].normal as Vector3) >= 0.0 else 1
		markers.append({"point": project_normal(point, side), "number": str(landmark.number), "label": str(landmark.get("label", "櫻花林")), "color": landmark.color, "side": side})
	queue_redraw()

func project_normal(point: Vector3, side: int) -> Vector2:
	var hemisphere: Dictionary = hemispheres[side]
	return (hemisphere.center as Vector2) + Vector2(point.dot(hemisphere.right as Vector3), -point.dot(hemisphere.top as Vector3)) * float(hemisphere.radius)

func _project(point: Vector3, hemisphere: Dictionary) -> Vector2:
	return (hemisphere.center as Vector2) + Vector2(point.dot(hemisphere.right as Vector3), -point.dot(hemisphere.top as Vector3)) * float(hemisphere.radius)

func _horizon_point(a: Vector3, b: Vector3, normal: Vector3) -> Vector3:
	var from: float = a.dot(normal)
	return a.lerp(b, from / (from - b.dot(normal))).normalized()

func _add_surface(points: PackedVector3Array, color: Color, hemisphere: Dictionary) -> void:
	if points.size() < 3:
		return
	var normal: Vector3 = hemisphere.normal as Vector3
	var polygon: PackedVector2Array = PackedVector2Array()
	var previous: Vector3 = points[-1]
	var previous_inside: bool = previous.dot(normal) >= 0.0
	for point: Vector3 in points:
		var inside: bool = point.dot(normal) >= 0.0
		if inside != previous_inside:
			polygon.append(_project(_horizon_point(previous, point, normal), hemisphere))
		if inside:
			polygon.append(_project(point, hemisphere))
		previous = point
		previous_inside = inside
	if polygon.size() < 3:
		return
	var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
	if not indices.is_empty():
		surfaces.append({"points": polygon, "indices": indices, "color": color})

func _add_line(points: PackedVector3Array, color: Color, width: float, hemisphere: Dictionary, closed: bool = false) -> void:
	if points.size() < 2:
		return
	var normal: Vector3 = hemisphere.normal as Vector3
	var run: PackedVector2Array = PackedVector2Array()
	var count: int = points.size() + (1 if closed else 0)
	for index: int in range(count - 1):
		var a: Vector3 = points[index % points.size()]
		var b: Vector3 = points[(index + 1) % points.size()]
		var a_inside: bool = a.dot(normal) >= 0.0
		var b_inside: bool = b.dot(normal) >= 0.0
		if not a_inside and not b_inside:
			continue
		if run.is_empty():
			run.append(_project(a if a_inside else _horizon_point(a, b, normal), hemisphere))
		run.append(_project(b if b_inside else _horizon_point(a, b, normal), hemisphere))
		if not b_inside:
			lines.append({"points": run, "color": color, "width": width})
			run = PackedVector2Array()
	if run.size() >= 2:
		lines.append({"points": run, "color": color, "width": width})

func player_marker() -> Dictionary:
	if source == null or hemispheres.size() != 2:
		return {}
	var player: Node3D = source.get("player") as Node3D
	if not is_instance_valid(player):
		return {}
	var normal: Vector3 = player.global_position.normalized()
	var side: int = 0 if normal.dot(hemispheres[0].normal as Vector3) >= 0.0 else 1
	var hemisphere: Dictionary = hemispheres[side]
	var heading: Vector3 = player.get("heading") as Vector3
	var direction: Vector2 = Vector2(heading.dot(hemisphere.right as Vector3), -heading.dot(hemisphere.top as Vector3)).normalized()
	return {"point": project_normal(normal, side), "heading": direction, "side": side}

func _draw() -> void:
	var font: Font = get_theme_default_font()
	for hemisphere: Dictionary in hemispheres:
		var centre: Vector2 = hemisphere.center as Vector2
		var map_radius: float = float(hemisphere.radius)
		draw_circle(centre, map_radius + 3.0, Color("0d2c36"))
		draw_circle(centre, map_radius, SEA)
		draw_arc(centre, map_radius, 0, TAU, 96, Color("47717a"), 1.0, true)
		var title: String = str(hemisphere.title)
		var title_width: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, (hemisphere.title_position as Vector2) - Vector2(title_width * 0.5, 0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("a9c2be"))
	for surface: Dictionary in surfaces:
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), surface.indices, surface.points, PackedColorArray([surface.color]))
	for line: Dictionary in lines:
		draw_polyline(line.points, line.color, float(line.width), true)
	for marker: Dictionary in markers:
		var at: Vector2 = marker.point as Vector2
		draw_circle(at, 10.0, Color("102d37"))
		draw_circle(at, 8.0, marker.color as Color)
		var number: String = str(marker.number)
		var number_width: float = font.get_string_size(number, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, at + Vector2(-number_width * 0.5, 4), number, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("173b45"))
		var text: String = str(marker.label)
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var text_start: Vector2 = at + Vector2(-text_width * 0.5, 24)
		text_start.x = clampf(text_start.x, 4.0, maxf(4.0, size.x - text_width - 4.0))
		draw_style_box(_label_backdrop(), Rect2(text_start + Vector2(-4, -13), Vector2(text_width + 8, 18)))
		draw_string(font, text_start, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, INK)
	var player: Dictionary = player_marker()
	if not player.is_empty():
		var centre: Vector2 = player.point as Vector2
		var rotation: float = (player.heading as Vector2).angle() + PI * 0.5
		var arrow: PackedVector2Array = PackedVector2Array()
		for point: Vector2 in [Vector2(0, -11), Vector2(7, 8), Vector2(0, 4), Vector2(-7, 8)]:
			arrow.append(centre + point.rotated(rotation))
		draw_circle(centre, 14, Color("0d2935"))
		draw_arc(centre, 14, 0, TAU, 32, Color("fff1c5"), 1.5, true)
		draw_colored_polygon(arrow, Color("ffe2a2"))

func _label_backdrop() -> StyleBoxFlat:
	if _marker_label_background == null:
		_marker_label_background = StyleBoxFlat.new()
		_marker_label_background.bg_color = Color(0.04, 0.12, 0.16, 0.86)
		_marker_label_background.set_corner_radius_all(4)
	return _marker_label_background
