extends Control

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const SakuraRoutes = preload("res://scripts/sakura_routes.gd")
const SEA: Color = Color("173f4b")
const WATER: Color = Color("4a8990")
const WALK: Color = Color("e9d4a7")
var world: Node3D
var player: PlanetPlayer
var radius: float = 48.0
var view_range: float = 36.0
var patches: Array[Dictionary] = []
var bridges: Array[PackedVector3Array] = []
var landmarks: Array[Dictionary] = []
var platforms: Array[PackedVector3Array] = []
var centre_up: Vector3 = Vector3.UP
var map_forward: Vector3 = Vector3.FORWARD
var map_right: Vector3 = Vector3.RIGHT
var arrow_heading_2d: Vector2 = Vector2.UP
var frame_ready: bool = false
var refresh_clock: float = 0.0
var location_label: Label
var current_location: String = "附近地圖"

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	player = world.get("player") as PlanetPlayer
	radius = player.planet_radius
	build_cartography()
	refresh()

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func lift(up: Vector3, point: Vector2) -> Vector3:
	return Geo.surface(up, point, radius).normalized()

func lift_polygon(up: Vector3, points: PackedVector2Array) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	# A long straight edge in district coordinates becomes a curve under the
	# sphere/map projections. Connecting only its endpoints can make opposite
	# river banks cross when viewed from an adjacent island. Sample the actual
	# boundary before either projection, just as the world terrain is tessellated.
	for index: int in range(points.size()):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[(index + 1) % points.size()]
		var steps: int = maxi(1, ceili(start.distance_to(finish) / .8))
		for step: int in range(steps):
			result.append(lift(up, start.lerp(finish, float(step) / steps)))
	return result

func route(up: Vector3, source: Array, closed: bool = false) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for i: int in range(source.size() if closed else source.size() - 1):
		var a: Vector2 = v2(source[i])
		var b: Vector2 = v2(source[(i + 1) % source.size()])
		var steps: int = maxi(1, ceili(a.distance_to(b) / 1.4))
		for j: int in range(steps):
			result.append(lift(up, a.lerp(b, float(j) / steps)))
	result.append(lift(up, v2(source[0] if closed else source[-1])))
	return result

func coastline(row: Dictionary, index: int) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for j: int in range(128):
		var angle: float = TAU * float(j) / 128.0
		# Same contour as ecology_world.edge_distance, including its seed.
		var edge: float = 1.0 + .045 * sin(angle * 3.0 + index) + .035 * cos(angle * 5.0 - index)
		result.append(Vector2(cos(angle), sin(angle)) * v2(row.extent) * edge)
	return result

func water_contours(row: Dictionary, coast: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	for water: Dictionary in row.water:
		var outlines: Array[PackedVector2Array] = []
		if str(water.kind) == "lake":
			var lake: PackedVector2Array = PackedVector2Array()
			for j: int in range(96):
				var angle: float = TAU * float(j) / 96.0
				var edge: float = 1.0 + .10 * sin(angle * 3.0) + .055 * cos(angle * 5.0)
				lake.append(v2(water.center) + Vector2(cos(angle), sin(angle)) * v2(water.size) * edge)
			outlines.append(lake)
		else:
			var centre_line: PackedVector2Array = PackedVector2Array()
			for point: Array in water.points:
				centre_line.append(v2(point))
			# Rivers are filled, rounded bank contours in world units, clipped
			# at the island edge. They never become a blue screen-space stroke.
			outlines = Geometry2D.offset_polyline(centre_line, float(water.width) * .5, Geometry2D.JOIN_ROUND, Geometry2D.END_ROUND)
		for water_outline: PackedVector2Array in outlines:
			for clipped: PackedVector2Array in Geometry2D.intersect_polygons(water_outline, coast):
				if clipped.size() >= 3:
					result.append(clipped)
	return result

func nearest_walk(point: Vector2, row: Dictionary) -> Vector2:
	var sources: Array = [row.loop]
	sources.append_array(row.roads)
	sources.append_array(row.paths)
	var best: Vector2 = point
	var distance: float = INF
	for index: int in range(sources.size()):
		var source: Array = sources[index]
		for j: int in range(source.size() if index == 0 else source.size() - 1):
			var nearest: Vector2 = Geometry2D.get_closest_point_to_segment(point, v2(source[j]), v2(source[(j + 1) % source.size()]))
			if point.distance_squared_to(nearest) < distance:
				distance = point.distance_squared_to(nearest)
				best = nearest
	return best

func build_patch(row: Dictionary, index: int, up: Vector3) -> Dictionary:
	var coast: PackedVector2Array = coastline(row, index)
	var patch: Dictionary = {"up": up, "station_id": str(row.station), "name": str(row.theme), "local_coast": coast, "coast": lift_polygon(up, coast), "land": Color(str(row.land)).lightened(.08), "water": [], "roads": [], "paths": [], "forecourts": [], "buildings": [], "gardens": []}
	for contour: PackedVector2Array in water_contours(row, coast):
		var inner: Array[PackedVector3Array] = []
		for inset: PackedVector2Array in Geometry2D.offset_polygon(contour, -.5, Geometry2D.JOIN_ROUND):
			inner.append(lift_polygon(up, inset))
		patch.water.append({"points": lift_polygon(up, contour), "inner": inner})
	patch.roads.append(route(up, row.loop, true))
	for road: Array in row.roads:
		patch.roads.append(route(up, road))
	for path: Array in Routes.district_paths(row, radius):
		patch.paths.append(route(up, path))
	for building: Dictionary in row.urban_buildings:
		var footprint: PackedVector2Array = PackedVector2Array()
		var yaw: float = deg_to_rad(float(building.yaw))
		var at: Vector2 = v2(building.offset)
		for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			var offset: Vector2 = corner * Vector2(float(building.max_width), float(building.max_depth)) * .5
			footprint.append(offset.rotated(-yaw) + at)
		patch.buildings.append({"points": lift_polygon(up, footprint), "civic": str(building.get("role", "")) == "civic"})
		var front: Vector2 = at + Vector2(sin(yaw), cos(yaw)) * float(building.get("front", 2.8))
		var walk: Vector2 = nearest_walk(front, row)
		patch.forecourts.append(route(up, [[front.x, front.y], [walk.x, walk.y]]))
	for garden: Array in row.gardens:
		patch.gardens.append(lift(up, v2(garden)))
	return patch

func build_cartography() -> void:
	patches.clear()
	bridges.clear()
	landmarks.clear()
	platforms.clear()
	var layout: Dictionary = world.get("layout")
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for index: int in range(data.size()):
		var row: Dictionary = data[index]
		var normal: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(normal[0], normal[1], normal[2])
		patches.append(build_patch(row, index, up))
		var station: Node3D = world.get_node("Stations/" + str(row.station)) as Node3D
		landmarks.append({"point": station.position.normalized(), "number": str(index + 1), "color": Color(str(layout.stations[index].color))})
	var directions: Array[Vector3] = Routes.directions()
	var limits: Vector2 = Routes.bridge_limits()
	for edge: Vector2i in Routes.bridge_edges():
		var points: PackedVector3Array = PackedVector3Array()
		for j: int in range(33):
			points.append(directions[edge.x].slerp(directions[edge.y], lerpf(limits.x, limits.y, float(j) / 32.0)))
		bridges.append(points)
	build_sakura_cartography()
	for marina: Node in world.find_children("Marina", "Node3D", true, false):
		var polygons: Array = marina.get_meta("map_polygons", [])
		for polygon: PackedVector3Array in polygons:
			platforms.append(polygon)
		var paths: Array = marina.get_meta("map_paths", [])
		for path: PackedVector3Array in paths:
			bridges.append(path)

func build_sakura_patch() -> Dictionary:
	var up: Vector3 = SakuraRoutes.grove_up()
	var paths: Array[PackedVector3Array] = []
	for source: Array in SakuraRoutes.paths(radius):
		paths.append(route(up, source))
	var coast: PackedVector2Array = SakuraRoutes.island_outline()
	return {"up": up, "name": "櫻花林", "layout_version": SakuraRoutes.LAYOUT_VERSION, "local_coast": coast, "coast": lift_polygon(up, coast), "land": Color("829580"), "water": [], "roads": [], "paths": paths, "path_width": SakuraRoutes.WIDTH, "forecourts": [], "buildings": [], "gardens": []}

func sakura_connection() -> PackedVector3Array:
	var start: Vector3 = SakuraRoutes.bridge_start()
	var finish: Vector3 = SakuraRoutes.bridge_finish()
	var connection: PackedVector3Array = PackedVector3Array([SakuraRoutes.town_endpoint(radius)])
	for j: int in range(33):
		connection.append(start.slerp(finish, float(j) / 32.0))
	# The shared garden entry path owns finish -> centre. Drawing that segment
	# here too would create an obsolete duplicate connector over the new loop.
	return connection

func build_sakura_cartography() -> void:
	var up: Vector3 = SakuraRoutes.grove_up()
	patches.append(build_sakura_patch())
	landmarks.append({"point": up, "number": "✿", "color": Color("e8b6c8")})
	bridges.append(sakura_connection())
	for polygon: PackedVector2Array in SakuraRoutes.platforms():
		platforms.append(lift_polygon(up, polygon))

func _process(delta: float) -> void:
	refresh_clock += delta
	if refresh_clock >= .05 and is_visible_in_tree():
		refresh_clock = 0.0
		refresh()

func update_map_frame(normal: Vector3) -> void:
	var next_up: Vector3 = normal.normalized()
	if not frame_ready or centre_up.dot(next_up) < .94:
		# Initialise to district north after a teleport. Continuous walking
		# parallel-transports this frame, including through either pole.
		var reference: Vector3 = next_up
		var alignment: float = -1.0
		for patch: Dictionary in patches:
			var candidate: Vector3 = patch.up as Vector3
			if next_up.dot(candidate) > alignment:
				alignment = next_up.dot(candidate)
				reference = candidate
		map_forward = (Quaternion(reference, next_up) * -Geo.frame(reference).z).normalized()
		frame_ready = true
	else:
		map_forward = (Quaternion(centre_up, next_up) * map_forward).slide(next_up).normalized()
	centre_up = next_up
	map_right = map_forward.cross(centre_up).normalized()

func direction_on_map(direction: Vector3) -> Vector2:
	var tangent: Vector3 = direction.slide(centre_up).normalized()
	return Vector2(tangent.dot(map_right), -tangent.dot(map_forward)).normalized()

func refresh() -> void:
	update_map_frame(player.global_position.normalized())
	# The graduate faces model-local +Z. Camera heading alone is wrong
	# while sidestepping or walking backwards, when VisualPivot turns.
	var facing: Vector3 = player.visual.global_basis.z if player.visual != null else player.heading
	arrow_heading_2d = direction_on_map(facing)
	current_location = location_at(centre_up)
	if location_label != null:
		location_label.text = current_location
	queue_redraw()

func patch_contains_normal(patch: Dictionary,normal: Vector3) -> bool:
	var up: Vector3 = patch.up as Vector3
	var denominator: float = normal.dot(up)
	if denominator <= .00001:
		return false
	# Invert the same gnomonic placement used to build the real terrain. The
	# small Sakura island must not claim nearby points on a larger district just
	# because its centre happens to be slightly closer than the town centre.
	var axes: Basis = Geo.frame(up)
	var point: Vector2 = Vector2(normal.dot(axes.x),normal.dot(axes.z))*radius/denominator
	return Geometry2D.is_point_in_polygon(point,patch.local_coast as PackedVector2Array)

func station_at(normal: Vector3) -> String:
	# Music uses the real island polygon; bridges and Sakura keep the world theme.
	for patch: Dictionary in patches:
		if patch_contains_normal(patch, normal.normalized()):
			return str(patch.get("station_id", "world"))
	return "world"

func location_at(normal: Vector3) -> String:
	var location_normal: Vector3 = normal.normalized()
	for patch: Dictionary in patches:
		if patch_contains_normal(patch,location_normal):
			return str(patch.name)
	# Bridges and marina platforms may lie outside every coastline. Compare
	# distance to the actual densely sampled coast instead of island centres,
	# so the nearest shore determines the label on these connecting structures.
	var nearest_name: String = "附近地圖"
	var nearest_distance: float = INF
	for patch: Dictionary in patches:
		var coast: PackedVector3Array = patch.coast as PackedVector3Array
		for index: int in range(coast.size()):
			var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(location_normal,coast[index],coast[(index+1)%coast.size()]).normalized()
			var distance: float = location_normal.distance_squared_to(nearest)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_name = str(patch.name)
	return nearest_name

func project_point(point: Vector3) -> Vector2:
	var cosine: float = clampf(centre_up.dot(point), -1.0, 1.0)
	var tangent: Vector3 = point - centre_up * cosine
	var distance: float = acos(cosine) * radius
	var direction: Vector3 = tangent.normalized() if tangent.length_squared() > .0000001 else Vector3.ZERO
	return size * .5 + Vector2(direction.dot(map_right), -direction.dot(map_forward)) * distance * map_scale()

func map_scale() -> float:
	return minf(size.x, size.y) / (2.0 * view_range)

func project_line(points: PackedVector3Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector3 in points:
		result.append(project_point(point))
	return result

func clean_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		if result.is_empty() or point.distance_squared_to(result[-1]) > .00000001:
			result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[-1]) <= .00000001:
		result.remove_at(result.size() - 1)
	# Clipping can introduce repeated and nearly collinear vertices. Remove
	# only subpixel redundancies, preserving even narrow visible river sections.
	var changed: bool = true
	while changed and result.size() > 3:
		changed = false
		for index: int in range(result.size()):
			var before: Vector2 = result[(index - 1 + result.size()) % result.size()]
			var current: Vector2 = result[index]
			var after: Vector2 = result[(index + 1) % result.size()]
			var span: Vector2 = after - before
			if span.length_squared() > .00000001 and absf(span.cross(current - before)) / span.length() < .0005 and (current - before).dot(after - current) >= 0.0:
				result.remove_at(index)
				changed = true
				break
	return result

func project_polygons(points: PackedVector3Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var projected: PackedVector2Array = clean_polygon(project_line(points))
	if projected.size() < 3:
		return result
	var bounds: Rect2 = Rect2(projected[0], Vector2.ZERO)
	for point: Vector2 in projected:
		bounds = bounds.expand(point)
	var viewport: Rect2 = Rect2(Vector2.ZERO, size).grow(1.0)
	if not viewport.intersects(bounds, true):
		return result
	var border: PackedVector2Array = PackedVector2Array([viewport.position, Vector2(viewport.end.x, viewport.position.y), viewport.end, Vector2(viewport.position.x, viewport.end.y)])
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(projected, border):
		var clean: PackedVector2Array = clean_polygon(clipped)
		if clean.size() >= 3:
			result.append(clean)
	return result

func draw_surface(points: PackedVector3Array, color: Color) -> void:
	for polygon: PackedVector2Array in project_polygons(points):
		# Triangulate in a normalized local coordinate system. A legitimate
		# subpixel sliver at a clipping edge otherwise falls below Godot's
		# ear-clipping tolerance even though it is still a valid triangle.
		var indices: PackedInt32Array = triangulate_surface(polygon)
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), indices, polygon, PackedColorArray([color]))

func triangulate_surface(polygon: PackedVector2Array) -> PackedInt32Array:
	if polygon.size() < 3:
		return PackedInt32Array()
	var bounds: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		bounds = bounds.expand(point)
	var largest: float = maxf(bounds.size.x, bounds.size.y)
	if largest <= 0.0:
		return PackedInt32Array()
	var normalized: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in polygon:
		normalized.append((point - bounds.position) * (1000.0 / largest))
	return Geometry2D.triangulate_polygon(normalized)

func outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, color, width, true)

func draw_water(contour: Dictionary) -> void:
	var points: PackedVector2Array = project_line(contour.points)
	draw_surface(contour.points, WATER.lightened(.12))
	for inset: PackedVector3Array in contour.inner:
		draw_surface(inset, WATER)
	outline(points, Color("96b5a5"), .8)

func draw_walk(points: PackedVector2Array, width: float = 2.1, is_bridge: bool = false) -> void:
	draw_polyline(points, Color("645e4f") if is_bridge else Color("62766a"), maxf(2.4, (width + .65) * map_scale()), true)
	draw_polyline(points, WALK if is_bridge else Color("d7c9aa"), maxf(1.8, width * map_scale()), true)
	if is_bridge:
		draw_polyline(points, Color("fff1cf"), .7, true)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if player == null:
		return
	var visible_patches: Array[Dictionary] = []
	for patch: Dictionary in patches:
		if centre_up.dot(patch.up as Vector3) < .35:
			continue
		visible_patches.append(patch)
		var coast: PackedVector2Array = project_line(patch.coast)
		outline(coast, Color("254e57"), 5.5)
		draw_surface(patch.coast, patch.land as Color)
		outline(coast, Color("a7baa0"), 1.3)
	for patch: Dictionary in visible_patches:
		for water: Dictionary in patch.water:
			draw_water(water)
		for garden: Vector3 in patch.gardens:
			var at: Vector2 = project_point(garden)
			draw_circle(at, 2.8 * map_scale(), Color("658569"))
			draw_circle(at + Vector2(-1, -1), 1.5 * map_scale(), Color("88a27c"))
		for road: PackedVector3Array in patch.roads:
			var points: PackedVector2Array = project_line(road)
			draw_polyline(points, Color("b9c5ae"), 6.3 * map_scale(), true)
			draw_polyline(points, Color("3b5051"), 4.2 * map_scale(), true)
		for path: PackedVector3Array in patch.forecourts:
			draw_polyline(project_line(path), Color("d1c9b0"), maxf(1.1, 1.4 * map_scale()), true)
		for path: PackedVector3Array in patch.paths:
			draw_walk(project_line(path), float(patch.get("path_width", 2.1)))
		for building: Dictionary in patch.buildings:
			var footprint: PackedVector2Array = project_line(building.points)
			var shadow: PackedVector2Array = footprint.duplicate()
			for j: int in range(shadow.size()):
				shadow[j] += Vector2(1.2, 1.6)
			draw_colored_polygon(shadow, Color("536c62"))
			draw_colored_polygon(footprint, Color("f0dab1") if bool(building.civic) else Color("d6dbc6"))
			outline(footprint, Color("ecedda"), .6)
	for platform: PackedVector3Array in platforms:
		if centre_up.dot(platform[0]) > .4:
			var points: PackedVector2Array = project_line(platform)
			draw_colored_polygon(points, WALK)
			outline(points, Color("f2e5c4"), 1.1)
	for bridge: PackedVector3Array in bridges:
		if centre_up.dot(bridge[floori(bridge.size() * .5)]) > .4:
			draw_walk(project_line(bridge), 2.4, true)
	var font: Font = get_theme_default_font()
	for landmark: Dictionary in landmarks:
		var point: Vector3 = landmark.point as Vector3
		if centre_up.dot(point) < .4:
			continue
		var at: Vector2 = project_point(point)
		if not Rect2(Vector2.ONE * 10, size - Vector2.ONE * 20).has_point(at):
			continue
		draw_circle(at + Vector2(0, 1), 8.5, Color("15343e"))
		draw_circle(at, 6.8, landmark.color as Color)
		var text: String = str(landmark.number)
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(font, at + Vector2(-text_width * .5, 3.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("163440"))
	draw_navigation_overlay(font)

func draw_navigation_overlay(font: Font) -> void:
	var centre: Vector2 = size * .5
	var rotation_angle: float = arrow_heading_2d.angle() + PI * .5
	var arrow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [Vector2(0, -9), Vector2(6.5, 7), Vector2(0, 3.5), Vector2(-6.5, 7)]:
		arrow.append(centre + point.rotated(rotation_angle))
	draw_circle(centre, 11, Color(.04, .12, .16, .92))
	draw_arc(centre, 11, 0, TAU, 32, Color("fff0c4"), 1.0, true)
	draw_colored_polygon(arrow, Color("ffe1a4"))
	# This rose marks the transported district reference, not camera heading.
	var compass: Vector2 = Vector2(size.x - 18, 21)
	draw_circle(compass, 12, Color(.06, .19, .23, .88))
	draw_line(compass + Vector2(-7, 0), compass + Vector2(7, 0), Color("93aba4"), 1, true)
	draw_line(compass + Vector2(0, -8), compass + Vector2(0, 7), Color("93aba4"), 1, true)
	draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -9), compass + Vector2(-3, -2), compass + Vector2(3, -2)]), Color("efdcac"))
	draw_string(font, Vector2(size.x - 38, 46), "定向", HORIZONTAL_ALIGNMENT_LEFT, 34, 10, Color("e1e5cf"))
	var scale_start: Vector2 = Vector2(10, size.y - 12)
	var scale_width: float = 10 * map_scale()
	draw_rect(Rect2(scale_start + Vector2(-4, -17), Vector2(scale_width + 9, 23)), Color(.06, .19, .23, .8))
	draw_line(scale_start, scale_start + Vector2(scale_width, 0), Color("e6edda"), 1.4)
	for end: Vector2 in [scale_start, scale_start + Vector2(scale_width, 0)]:
		draw_line(end + Vector2(0, -3), end + Vector2(0, 2), Color("e6edda"), 1.2)
	draw_string(font, scale_start + Vector2(0, -5), "10 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e6edda"))
