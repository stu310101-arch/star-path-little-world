extends Control

signal expand_requested

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const SakuraRoutes = preload("res://scripts/sakura_routes.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const GEOMETRY_PATH: String = "res://data/minimap_geometry.json"
const SEA: Color = Color("173f4b")
const WATER: Color = Color("4a8990")
const WALK: Color = Color("e9d4a7")
const NAVIGATION_INTERVAL: float = .05
const LOW_CARTOGRAPHY_INTERVAL: float = .20
const LOW_RECENTER_PIXELS: float = 2.0

class NavigationOverlay:
	extends Control
	var map: Control
	func _draw() -> void:
		map.call("_draw_navigation_on", self, map.get_theme_default_font())

class CartographyLayer:
	extends Control
	var map: Control
	func _draw() -> void:
		# Font/theme invalidations can redraw this CanvasItem independently.
		# Render that new command list once, then retain the resulting texture.
		if not map.get("_cache_supported"):
			return
		map.call("_draw_cartography", self)
		(get_viewport() as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

var world: Node3D
var player: PlanetPlayer
var radius: float = 48.0
var authoring_radius: float = 0.0
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
var _navigation: NavigationOverlay
var _quality_settings: Node
var _low_quality: bool = false
var _cartography_clock: float = 0.0
var _scheduled_refresh: bool = false
var _deferred_map_refreshes: int = 0
var _player_map_position: Vector2 = Vector2.ZERO
var _last_map_size: Vector2 = Vector2.INF
var _last_view_range: float = -1.0
var _cartography_dirty: bool = true
var _projected_lines: Dictionary = {}
var _drawing_map: bool = false
var _map_draws: int = 0
var _skipped_refreshes: int = 0
var _last_map_draw_ms: float = 0.0
var _max_map_draw_ms: float = 0.0
var _built_geometry: Dictionary = {}
var _line_bounds: Dictionary = {}
var compact_preview: bool = false:
	set(value):
		if compact_preview == value:
			return
		compact_preview = value
		_cartography_dirty = true
		queue_redraw()
var _compact_lines: Dictionary = {}
var _compact_source_points: int = 0
var _compact_draw_points: int = 0
var texture_cache_enabled: bool = true
var _cache_viewport: SubViewport
var _cache_layer: CartographyLayer
var _cache_image: Sprite2D
var _cache_pixel_transform: Transform2D = Transform2D.IDENTITY
var _cache_logical_size: Vector2 = Vector2.ZERO
var _cache_supported: bool = false
var _cache_rebuilds: int = 0
var _cartography_target: Control
var _cache_source_viewport: Viewport

func built_geometry() -> Dictionary:
	if _built_geometry.is_empty() and FileAccess.file_exists(GEOMETRY_PATH):
		_built_geometry = JSON.parse_string(FileAccess.get_file_as_string(GEOMETRY_PATH)) as Dictionary
	return _built_geometry

func unpack_polygon(values: Array) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for value: Array in values:
		points.append(Vector3(float(value[0]), float(value[1]), float(value[2])).normalized())
	return points

func path_sections(up: Vector3, source: Array, row: Dictionary) -> Array[Dictionary]:
	# The mesh generator partitions each path into paved and timber spans with
	# these exact samples. A single generic line concealed the small bridges.
	var samples: Array[Dictionary] = Waterfront.samples(up, source, row, source_radius())
	var sections: Array[Dictionary] = []
	for index: int in range(samples.size() - 1):
		var wet: bool = bool(samples[index].wet)
		if sections.is_empty() or bool(sections[-1].wet) != wet:
			sections.append({"wet": wet, "points": PackedVector3Array([samples[index].normal])})
		var points: PackedVector3Array = sections[-1].points
		points.append(samples[index + 1].normal)
		sections[-1].points = points
	return sections

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	focus_mode = Control.FOCUS_ALL
	tooltip_text = "點擊查看完整世界地圖"
	clip_contents = true
	player = world.get("player") as PlanetPlayer
	radius = player.planet_radius
	_quality_settings = get_tree().get_first_node_in_group("graphics_settings")
	texture_cache_enabled = not OS.get_cmdline_user_args().has("--minimap-direct")
	if OS.has_feature("web"):
		texture_cache_enabled = not bool(JavaScriptBridge.eval("(() => { const q = new URLSearchParams(location.search); return q.has('performance') && q.get('minimap_direct') === '1'; })()"))
	_create_texture_cache()
	set_notify_transform(true)
	_connect_cache_viewport()
	_navigation = NavigationOverlay.new()
	_navigation.name = "NavigationOverlay"
	_navigation.map = self
	_navigation.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_navigation)
	_navigation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	build_cartography()
	refresh()

func _create_texture_cache() -> void:
	_cache_viewport = SubViewport.new()
	_cache_viewport.name = "CartographyCache"
	_cache_viewport.disable_3d = true
	_cache_viewport.transparent_bg = true
	_cache_viewport.gui_disable_input = true
	_cache_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_cache_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	add_child(_cache_viewport)
	_cache_layer = CartographyLayer.new()
	_cache_layer.name = "Cartography"
	_cache_layer.map = self
	_cache_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_viewport.add_child(_cache_layer)
	_cache_image = Sprite2D.new()
	_cache_image.name = "CachedCartography"
	_cache_image.centered = false
	# Control snaps its local position independently of the parent stretch.
	# Sprite2D preserves a fractional offset needed to land on physical pixels.
	# The destination quad is aligned to physical pixel edges. Nearest avoids
	# adding a second filtering pass to the already antialiased canvas image.
	_cache_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cache_image.texture = _cache_viewport.get_texture()
	add_child(_cache_image)
	_update_texture_cache_geometry()

func set_texture_cache_enabled(value: bool) -> void:
	# Explicit diagnostic A/B switch; it changes no geometry or graphics setting.
	if texture_cache_enabled == value:
		return
	texture_cache_enabled = value
	_update_texture_cache_geometry()
	queue_redraw()

func _update_texture_cache_geometry() -> bool:
	if _cache_viewport == null or not is_inside_tree() or not _cache_viewport.is_inside_tree() or not _cache_layer.is_inside_tree():
		return false
	var pixels: Transform2D = get_viewport().get_final_transform() * get_global_transform_with_canvas()
	var supported: bool = texture_cache_enabled and size.x > 0.0 and size.y > 0.0 and pixels.x.x > 0.0 and pixels.y.y > 0.0 and is_zero_approx(pixels.x.y) and is_zero_approx(pixels.y.x)
	var changed: bool = pixels != _cache_pixel_transform or size != _cache_logical_size or supported != _cache_supported
	_cache_supported = supported
	_cache_image.visible = supported
	if not supported:
		_cache_pixel_transform = pixels
		_cache_logical_size = size
		_cache_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return changed
	var parent_viewport: Viewport = get_viewport()
	changed = changed or _cache_viewport.msaa_2d != parent_viewport.msaa_2d
	changed = changed or not is_equal_approx(_cache_viewport.oversampling_override, parent_viewport.get_oversampling())
	if not changed:
		return false
	_cache_pixel_transform = pixels
	_cache_logical_size = size
	var first_pixel: Vector2 = pixels.origin.floor()
	var last_pixel: Vector2 = (pixels * size).ceil()
	var pixel_size: Vector2i = Vector2i(last_pixel - first_pixel)
	_cache_viewport.size = Vector2i(maxi(1,pixel_size.x), maxi(1,pixel_size.y))
	_cache_viewport.msaa_2d = parent_viewport.msaa_2d
	_cache_viewport.oversampling_override = parent_viewport.get_oversampling()
	_cache_viewport.canvas_item_default_texture_filter = parent_viewport.canvas_item_default_texture_filter
	_cache_viewport.canvas_item_default_texture_repeat = parent_viewport.canvas_item_default_texture_repeat
	# Keep the same subpixel phase as the direct screen-space canvas, including
	# stretched 960px mobile canvases and device-pixel-sized Web root viewports.
	_cache_viewport.canvas_transform = Transform2D(pixels.x,pixels.y,pixels.origin-first_pixel)
	_cache_layer.size = size
	var scale_pixels: Vector2 = Vector2(pixels.x.x,pixels.y.y)
	_cache_image.position = (first_pixel-pixels.origin)/scale_pixels
	_cache_image.scale = Vector2.ONE/scale_pixels
	return true

func _on_cache_geometry_changed() -> void:
	if _cache_viewport != null and _update_texture_cache_geometry():
		queue_redraw()

func _connect_cache_viewport() -> void:
	_cache_source_viewport = get_viewport()
	if not _cache_source_viewport.size_changed.is_connected(_on_cache_geometry_changed):
		_cache_source_viewport.size_changed.connect(_on_cache_geometry_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE and is_instance_valid(_cache_source_viewport):
		_cache_source_viewport.size_changed.disconnect(_on_cache_geometry_changed)
		_cache_source_viewport = null
	elif what == NOTIFICATION_ENTER_TREE and _cache_viewport != null:
		_connect_cache_viewport()
		_on_cache_geometry_changed.call_deferred()
	elif what == NOTIFICATION_THEME_CHANGED and _cache_layer != null:
		_cache_layer.queue_redraw()
	elif what == NOTIFICATION_TRANSFORM_CHANGED or what == NOTIFICATION_RESIZED:
		_on_cache_geometry_changed()
	elif what == NOTIFICATION_VISIBILITY_CHANGED and _cache_layer != null and is_visible_in_tree():
		if _update_texture_cache_geometry():
			queue_redraw()

func _gui_input(event: InputEvent) -> void:
	var activate: bool = event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and event.is_pressed()
	activate = activate or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) or event.is_action_pressed("ui_accept")
	if activate:
		accept_event()
		expand_requested.emit()

func source_radius() -> float:
	return authoring_radius if authoring_radius > 0.0 else radius

func source_scale() -> float:
	return radius / source_radius()

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func lift(up: Vector3, point: Vector2) -> Vector3:
	return Geo.surface(up, point, source_radius()).normalized()

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
	for j: int in range(720):
		var angle: float = TAU*float(j)/720.0
		var direction: Vector2 = Vector2(cos(angle),sin(angle))
		var low: float = 0.0
		var high: float = v2(row.extent).length()*1.3
		for _i: int in range(22):
			var middle: float = (low+high)*.5
			if Routes.coast_distance(direction*middle,row,index)>0: low=middle
			else: high=middle
		result.append(direction*((low+high)*.5))
	return result

func water_contours(row: Dictionary, coast: PackedVector2Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	var waters: Array = (row.water as Array).duplicate(true)
	for source: Dictionary in preload("res://scripts/biome_geography.gd").spec(str(row.station)).get("waters",[]):
		var water: Dictionary = source.duplicate(true)
		water["biome"] = true
		waters.append(water)
	for water: Dictionary in waters:
		var outlines: Array[PackedVector2Array] = []
		if str(water.kind) == "lake":
			var lake: PackedVector2Array = PackedVector2Array()
			for j: int in range(96):
				var angle: float = TAU * float(j) / 96.0
				var edge: float = 1.0 + (.07 if water.get("biome",false) else .10)*sin(angle*3.0)+(.04 if water.get("biome",false) else .055)*cos(angle*5.0)
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
	var patch: Dictionary = {"up": up, "station_id": str(row.station), "name": str(row.theme), "local_coast": coast, "coast": lift_polygon(up, coast), "land": Color(str(row.land)).lightened(.08), "water": [], "roads": [], "paths": [], "boardwalks": [], "path_width": Waterfront.WIDTH, "forecourts": [], "buildings": [], "gardens": []}
	for contour: PackedVector2Array in water_contours(row, coast):
		var inner: Array[PackedVector3Array] = []
		for inset: PackedVector2Array in Geometry2D.offset_polygon(contour, -.5, Geometry2D.JOIN_ROUND):
			inner.append(lift_polygon(up, inset))
		patch.water.append({"points": lift_polygon(up, contour), "inner": inner})
	patch.roads.append(route(up, row.loop, true))
	for road: Array in row.roads:
		patch.roads.append(route(up, road))
	for path: Array in Routes.district_paths(row, source_radius()):
		for section: Dictionary in path_sections(up, path, row):
			if bool(section.wet):
				patch.boardwalks.append(section.points)
			else:
				patch.paths.append(section.points)
	for trail: Array in preload("res://scripts/biome_geography.gd").spec(str(row.station)).get("trails",[]):
		patch.paths.append(route(up,trail))
	var built: Dictionary = built_geometry().get("districts", {}).get(str(row.station), {})
	var built_buildings: Array = built.get("buildings", [])
	var building_index: int = 0
	for building: Dictionary in row.urban_buildings:
		if bool(get_node("/root/ResourceProfile").call("is_low")) and building_index >= 5:
			break
		var yaw: float = deg_to_rad(float(building.yaw))
		var at: Vector2 = v2(building.offset)
		# max_width/max_depth are fitting limits, not the final mesh dimensions.
		# Bake the real foundation footprint once instead of loading house scenes
		# into the HUD, including when their visual chunks are not resident.
		if building_index < built_buildings.size():
			var points: PackedVector3Array = unpack_polygon(built_buildings[building_index].points)
			patch.buildings.append({"points": points, "civic": str(building.get("role", "")) == "civic"})
		else:
			push_error("Missing baked minimap footprint for " + str(row.station) + "; rebuild streaming world geometry.")
		building_index += 1
		var front: Vector2 = at + Vector2(sin(yaw), cos(yaw)) * float(building.get("front", 2.8))
		var walk: Vector2 = nearest_walk(front, row)
		patch.forecourts.append(route(up, [[front.x, front.y], [walk.x, walk.y]]))
	for garden: Array in row.gardens:
		patch.gardens.append(lift(up, v2(garden)))
	return patch

func build_cartography() -> void:
	_cartography_dirty = true
	_line_bounds.clear()
	_compact_lines.clear()
	_compact_source_points = 0
	_compact_draw_points = 0
	patches.clear()
	bridges.clear()
	landmarks.clear()
	platforms.clear()
	var layout: Dictionary = world.get("layout")
	authoring_radius = float(layout.get("authoring_radius", radius))
	view_range = 36.0 * source_scale()
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	for index: int in range(data.size()):
		var row: Dictionary = data[index]
		var normal: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(normal[0], normal[1], normal[2])
		patches.append(build_patch(row, index, up))
		var station: Node3D = world.get_node("Stations/" + str(row.station)) as Node3D
		landmarks.append({"point": station.global_position.normalized(), "station_id": str(row.station), "label": str(layout.stations[index].label), "number": str(index + 1), "color": Color(str(layout.stations[index].color))})
	for edge: Vector2i in Routes.bridge_edges():
		var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge, source_radius())
		var points: PackedVector3Array = PackedVector3Array()
		for j: int in range(33):
			points.append(endpoints[0].slerp(endpoints[1], float(j) / 32.0))
		bridges.append(points)
	if not get_node("/root/ResourceProfile").call("is_low"):
		build_sakura_cartography()
	# The marina is streamed after this HUD is created, so a startup node scan
	# silently omitted it. Its baked footprint is available at every load state.
	for polygon: Array in built_geometry().get("platforms", []):
		platforms.append(unpack_polygon(polygon))

func build_sakura_patch() -> Dictionary:
	var up: Vector3 = SakuraRoutes.grove_up()
	var paths: Array[PackedVector3Array] = []
	for source: Array in SakuraRoutes.paths(source_radius()):
		paths.append(route(up, source))
	var coast: PackedVector2Array = SakuraRoutes.island_outline()
	return {"up": up, "name": "櫻花林", "layout_version": SakuraRoutes.LAYOUT_VERSION, "local_coast": coast, "coast": lift_polygon(up, coast), "land": Color("829580"), "water": [], "roads": [], "paths": paths, "path_width": SakuraRoutes.WIDTH, "forecourts": [], "buildings": [], "gardens": []}

func sakura_connection() -> PackedVector3Array:
	var start: Vector3 = SakuraRoutes.bridge_start()
	var finish: Vector3 = SakuraRoutes.bridge_finish()
	var connection: PackedVector3Array = PackedVector3Array([SakuraRoutes.town_endpoint(source_radius())])
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
	_cartography_clock += delta
	if refresh_clock >= NAVIGATION_INTERVAL and is_visible_in_tree():
		refresh_clock = 0.0
		_scheduled_refresh = true
		refresh()
		_scheduled_refresh = false

func _uses_lightweight_cartography() -> bool:
	# A large desktop HUD previously retained all dense outlines even at the
	# lowest 3D quality. Reuse bounded preview geometry on low presets or when
	# the runtime detects sustained pressure even under a standard preference;
	# the complete source arrays still drive the full map and location queries.
	return compact_preview or _low_quality

func update_map_frame(normal: Vector3) -> void:
	var next_up: Vector3 = normal.normalized()
	if not frame_ready or centre_up.distance_to(next_up) * radius > view_range:
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
	var normal: Vector3 = player.global_position.normalized()
	var cache_changed: bool = _update_texture_cache_geometry()
	var low_quality: bool = is_instance_valid(_quality_settings) and bool(_quality_settings.call("is_low_quality"))
	if is_instance_valid(_quality_settings) and _quality_settings.has_method("is_constrained_runtime"):
		low_quality = low_quality or bool(_quality_settings.call("is_constrained_runtime"))
	if low_quality != _low_quality:
		_low_quality = low_quality
		_cartography_dirty = true
	# Radial jumping and camera motion do not change the map projection. Keep
	# its retained canvas commands until the surface position or map size changes.
	var invalidated: bool = _cartography_dirty or not frame_ready or size != _last_map_size or view_range != _last_view_range
	var moved: bool = centre_up.distance_squared_to(normal) > 1e-12
	var map_changed: bool = invalidated or moved
	# Navigation is cheap and follows the real player at 20 Hz. The expensive
	# projection/clipping/triangulation is capped at 5 Hz on low presets, and
	# sub-two-pixel walking keeps the retained texture. Teleports and layout or
	# quality changes bypass the budget. Explicit refresh() stays synchronous.
	if map_changed and _scheduled_refresh and _low_quality and not invalidated:
		var displacement: float = centre_up.distance_to(normal) * radius
		if displacement < view_range * .5 and (_cartography_clock < LOW_CARTOGRAPHY_INTERVAL or displacement * map_scale() < LOW_RECENTER_PIXELS):
			map_changed = false
			_deferred_map_refreshes += 1
	if map_changed:
		update_map_frame(normal)
		_cartography_clock = 0.0
	# The graduate faces model-local +Z. Camera heading alone is wrong
	# while sidestepping or walking backwards, when VisualPivot turns.
	var facing: Vector3 = player.visual.global_basis.z if player.visual != null else player.heading
	var arrow: Vector2 = direction_on_map(facing)
	var arrow_changed: bool = not arrow.is_equal_approx(arrow_heading_2d)
	arrow_heading_2d = arrow
	# The arrow must move on the retained projection while its centre is held;
	# otherwise the map would report a stale position between cache rebuilds.
	var player_at: Vector2 = project_point(normal)
	var position_changed: bool = not player_at.is_equal_approx(_player_map_position)
	_player_map_position = player_at
	if map_changed:
		current_location = location_at(centre_up)
		if location_label != null:
			location_label.text = current_location
		_last_map_size = size
		_last_view_range = view_range
		_cartography_dirty = false
		queue_redraw()
	else:
		_skipped_refreshes += 1
		if cache_changed:
			queue_redraw()
	if _navigation != null and (map_changed or arrow_changed or position_changed):
		_navigation.queue_redraw()

func metrics() -> Dictionary:
	return {"map_draws":_map_draws,"skipped_refreshes":_skipped_refreshes,"last_draw_ms":_last_map_draw_ms,"max_draw_ms":_max_map_draw_ms,"compact_preview":compact_preview,"lightweight_cartography":_uses_lightweight_cartography(),"deferred_map_refreshes":_deferred_map_refreshes,"compact_source_points":_compact_source_points,"compact_draw_points":_compact_draw_points,"texture_cache_enabled":_cache_supported,"texture_cache_rebuilds":_cache_rebuilds,"texture_cache_pixels":[_cache_viewport.size.x,_cache_viewport.size.y] if _cache_viewport != null else []}

func patch_contains_normal(patch: Dictionary,normal: Vector3) -> bool:
	var up: Vector3 = patch.up as Vector3
	var denominator: float = normal.dot(up)
	if denominator <= .00001:
		return false
	# Invert the same gnomonic placement used to build the real terrain. The
	# small Sakura island must not claim nearby points on a larger district just
	# because its centre happens to be slightly closer than the town centre.
	var axes: Basis = Geo.frame(up)
	var point: Vector2 = Vector2(normal.dot(axes.x),normal.dot(axes.z))*source_radius()/denominator
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
	# atan2 retains sub-meter detail on a large, nearly flat world. acos(dot)
	# rounds short arcs to zero in float32 and makes the map jump while walking.
	var distance: float = atan2(tangent.length(), cosine) * radius
	var direction: Vector3 = tangent.normalized() if tangent.length_squared() > 1e-14 else Vector3.ZERO
	return size * .5 + Vector2(direction.dot(map_right), -direction.dot(map_forward)) * distance * map_scale()

func map_scale() -> float:
	return minf(size.x, size.y) / (2.0 * view_range)

func compact_source_line(points: PackedVector3Array) -> PackedVector3Array:
	# A small HUD cannot show the source's centimetre-scale sampling. Low
	# presets simplify only the render copy once, preserving endpoints and
	# bounding error to 0.003 unit-sphere units (0.072m on R24, less than
	# 0.4 logical pixels near the centre of the 246x180 desktop HUD).
	# Original coast/route data remains intact for the full map and navigation.
	if not _uses_lightweight_cartography() or points.size() <= 4:
		return points
	# A packed-array dictionary key hashes every point. Fetch once rather than
	# hashing the same dense coastline separately for has() and operator[].
	var cached: Variant = _compact_lines.get(points)
	if cached != null:
		return cached as PackedVector3Array
	var keep: PackedByteArray = PackedByteArray()
	keep.resize(points.size())
	keep[0] = 1
	keep[points.size() - 1] = 1
	var pending: Array[Vector2i] = [Vector2i(0, points.size() - 1)]
	while not pending.is_empty():
		var span: Vector2i = pending.pop_back()
		var furthest: int = -1
		var error_squared: float = 0.003 * 0.003
		for index: int in range(span.x + 1, span.y):
			var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(points[index], points[span.x], points[span.y])
			var distance_squared: float = points[index].distance_squared_to(nearest)
			if distance_squared > error_squared:
				error_squared = distance_squared
				furthest = index
		if furthest >= 0:
			keep[furthest] = 1
			pending.append(Vector2i(span.x, furthest))
			pending.append(Vector2i(furthest, span.y))
	var simplified: PackedVector3Array = PackedVector3Array()
	for index: int in range(points.size()):
		if keep[index]:
			simplified.append(points[index])
	# A tiny closed polygon still needs its topology even below preview size.
	if simplified.size() < 4:
		simplified = points
	_compact_lines[points] = simplified
	_compact_source_points += points.size()
	_compact_draw_points += simplified.size()
	return simplified

func project_line(points: PackedVector3Array) -> PackedVector2Array:
	# Within one redraw the same coast/water is used by both fill and outline.
	# Packed array keys retain their original immutable data; the cache is cleared
	# after this draw, never accumulated across camera positions or districts.
	if _drawing_map:
		var cached: Variant = _projected_lines.get(points)
		if cached != null:
			return cached as PackedVector2Array
	var result: PackedVector2Array = PackedVector2Array()
	var centre: Vector2 = size * .5
	var projection_scale: float = map_scale()
	for point: Vector3 in compact_source_line(points):
		var cosine: float = clampf(centre_up.dot(point), -1.0, 1.0)
		var tangent: Vector3 = point - centre_up * cosine
		var distance: float = atan2(tangent.length(), cosine) * radius
		var direction: Vector3 = tangent.normalized() if tangent.length_squared() > 1e-14 else Vector3.ZERO
		result.append(centre + Vector2(direction.dot(map_right), -direction.dot(map_forward)) * distance * projection_scale)
	if _drawing_map:
		_projected_lines[points] = result
	return result

func line_visible(points: PackedVector3Array, margin_m: float = 4.0) -> bool:
	if points.is_empty():
		return false
	# A spherical cap conservatively contains both the sampled boundary and its
	# interior. Test it before projecting hundreds of off-screen coast vertices.
	# The real geometry stays intact: this only rejects wholly invisible features.
	var bounds: Dictionary = _line_bounds.get(points, {})
	if bounds.is_empty():
		var axis: Vector3 = Vector3.ZERO
		for point: Vector3 in points:
			axis += point
		if axis.length_squared() < .000001:
			bounds = {"up": Vector3.UP, "angle": PI}
		else:
			axis = axis.normalized()
			var angle: float = 0.0
			for point: Vector3 in points:
				angle = maxf(angle, atan2(axis.cross(point).length(), axis.dot(point)))
			bounds = {"up": axis, "angle": angle}
		_line_bounds[points] = bounds
	var view_angle: float = (size.length() * .5 / map_scale() + margin_m) / radius
	var limit: float = float(bounds.angle) + view_angle
	return limit >= PI * .5 or centre_up.dot(bounds.up as Vector3) >= cos(limit)

func redundant_vertex(before: Vector2, current: Vector2, after: Vector2) -> bool:
	var span: Vector2 = after - before
	return span.length_squared() > .00000001 and absf(span.cross(current - before)) / span.length() < .0005 and (current - before).dot(after - current) >= 0.0

func clean_polygon(points: PackedVector2Array) -> PackedVector2Array:
	var result: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in points:
		if not result.is_empty() and point.distance_squared_to(result[-1]) <= .00000001:
			continue
		# Each vertex enters and leaves this stack once. Restarting a full scan
		# after each deletion made dense, accurate coastlines cost >100ms/draw.
		while result.size() >= 2 and redundant_vertex(result[-2], result[-1], point):
			result.resize(result.size() - 1)
		result.append(point)
	if result.size() > 1 and result[0].distance_squared_to(result[-1]) <= .00000001:
		result.remove_at(result.size() - 1)
	# Complete the two cyclic joins without shifting the whole packed array.
	var first: int = 0
	var last: int = result.size() - 1
	while last - first >= 3:
		if redundant_vertex(result[last], result[first], result[first + 1]):
			first += 1
		elif redundant_vertex(result[last - 1], result[last], result[first]):
			last -= 1
		else:
			break
	return result.slice(first, last + 1)

func project_polygons(points: PackedVector3Array) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if not line_visible(points):
		return result
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
		if not indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(_draw_target().get_canvas_item(), indices, polygon, PackedColorArray([color]))

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

func draw_planar_surface(points: PackedVector2Array, color: Color) -> void:
	var polygon: PackedVector2Array = clean_polygon(points)
	var indices: PackedInt32Array = triangulate_surface(polygon)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(_draw_target().get_canvas_item(), indices, polygon, PackedColorArray([color]))

func outline(points: PackedVector2Array, color: Color, width: float) -> void:
	var closed: PackedVector2Array = points.duplicate()
	closed.append(points[0])
	_draw_target().draw_polyline(closed, color, width, true)

func draw_water(contour: Dictionary) -> void:
	var points: PackedVector2Array = project_line(contour.points)
	draw_surface(contour.points, WATER.lightened(.12))
	if _uses_lightweight_cartography():
		return
	for inset: PackedVector3Array in contour.inner:
		draw_surface(inset, WATER)
	outline(points, Color("96b5a5"), .8)

func draw_walk(points: PackedVector2Array, width: float = 2.1, is_bridge: bool = false) -> void:
	var target: Control = _draw_target()
	if _uses_lightweight_cartography():
		target.draw_polyline(points, WALK, maxf(1.3, width * source_scale() * map_scale()), true)
		return
	target.draw_polyline(points, Color("645e4f") if is_bridge else Color("62766a"), maxf(2.4, (width + .65) * source_scale() * map_scale()), true)
	target.draw_polyline(points, WALK if is_bridge else Color("d7c9aa"), maxf(1.8, width * source_scale() * map_scale()), true)
	if is_bridge:
		target.draw_polyline(points, Color("fff1cf"), .7, true)

func _draw() -> void:
	_update_texture_cache_geometry()
	if _cache_supported:
		_cache_layer.queue_redraw()
		_cache_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	else:
		_draw_cartography(self)

func _draw_target() -> Control:
	return _cartography_target if _cartography_target != null else self

func _draw_cartography(target: Control) -> void:
	_cartography_target = target
	target.draw_rect(Rect2(Vector2.ZERO, size), SEA)
	if player == null:
		_cartography_target = null
		return
	if target == _cache_layer:
		_cache_rebuilds += 1
	var started: int = Time.get_ticks_usec()
	_drawing_map = true
	_projected_lines.clear()
	var visible_patches: Array[Dictionary] = []
	for patch: Dictionary in patches:
		if not line_visible(patch.coast):
			continue
		visible_patches.append(patch)
		var coast: PackedVector2Array = project_line(patch.coast)
		if not _uses_lightweight_cartography():
			outline(coast, Color("254e57"), 5.5)
		draw_surface(patch.coast, patch.land as Color)
		outline(coast, Color("a7baa0"), 1.3)
	for patch: Dictionary in visible_patches:
		for water: Dictionary in patch.water:
			if line_visible(water.points):
				draw_water(water)
		for garden: Vector3 in patch.gardens:
			if _uses_lightweight_cartography():
				break
			var at: Vector2 = project_point(garden)
			target.draw_circle(at, 2.8 * source_scale() * map_scale(), Color("658569"))
			target.draw_circle(at + Vector2(-1, -1), 1.5 * source_scale() * map_scale(), Color("88a27c"))
		for road: PackedVector3Array in patch.roads:
			if not line_visible(road):
				continue
			var points: PackedVector2Array = project_line(road)
			if not _uses_lightweight_cartography():
				target.draw_polyline(points, Color("b9c5ae"), maxf(1.6, 6.3 * source_scale() * map_scale()), true)
			target.draw_polyline(points, Color("3b5051"), maxf(1.0, 4.2 * source_scale() * map_scale()), true)
		for path: PackedVector3Array in patch.forecourts:
			if _uses_lightweight_cartography():
				break
			if line_visible(path):
				target.draw_polyline(project_line(path), Color("d1c9b0"), maxf(1.1, 1.4 * source_scale() * map_scale()), true)
		for path: PackedVector3Array in patch.paths:
			if line_visible(path):
				draw_walk(project_line(path), float(patch.get("path_width", 2.1)))
		for boardwalk: PackedVector3Array in patch.get("boardwalks", []):
			if line_visible(boardwalk):
				draw_walk(project_line(boardwalk), Waterfront.WIDTH, true)
		for building: Dictionary in patch.buildings:
			if _uses_lightweight_cartography() and not bool(building.civic):
				continue
			if not line_visible(building.points):
				continue
			var footprint: PackedVector2Array = project_line(building.points)
			var shadow: PackedVector2Array = footprint.duplicate()
			for j: int in range(shadow.size()):
				shadow[j] += Vector2(1.2, 1.6)
			if not _uses_lightweight_cartography():
				draw_planar_surface(shadow, Color("536c62"))
			draw_planar_surface(footprint, Color("f0dab1") if bool(building.civic) else Color("d6dbc6"))
			outline(footprint, Color("ecedda"), .6)
	for platform: PackedVector3Array in platforms:
		if line_visible(platform):
			var points: PackedVector2Array = project_line(platform)
			draw_planar_surface(points, WALK)
			outline(points, Color("f2e5c4"), 1.1)
	for bridge: PackedVector3Array in bridges:
		if line_visible(bridge):
			draw_walk(project_line(bridge), 2.4, true)
	var font: Font = get_theme_default_font()
	for landmark: Dictionary in landmarks:
		var point: Vector3 = landmark.point as Vector3
		if centre_up.dot(point) < .4:
			continue
		var at: Vector2 = project_point(point)
		if not Rect2(Vector2.ONE * 10, size - Vector2.ONE * 20).has_point(at):
			continue
		target.draw_circle(at + Vector2(0, 1), 8.5, Color("15343e"))
		target.draw_circle(at, 6.8, landmark.color as Color)
		var text: String = str(landmark.number)
		var text_width: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		target.draw_string(font, at + Vector2(-text_width * .5, 3.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("163440"))
	_drawing_map = false
	_projected_lines.clear()
	_map_draws += 1
	_last_map_draw_ms = float(Time.get_ticks_usec() - started) / 1000.0
	_max_map_draw_ms = maxf(_max_map_draw_ms, _last_map_draw_ms)
	if _navigation == null:
		draw_navigation_overlay(font)
	_cartography_target = null

func draw_navigation_overlay(font: Font) -> void:
	_draw_navigation_on(_draw_target(), font)

func _draw_navigation_on(target: Control, font: Font) -> void:
	var centre: Vector2 = project_point(player.global_position.normalized()) if is_instance_valid(player) else size * .5
	var rotation_angle: float = arrow_heading_2d.angle() + PI * .5
	var arrow: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in [Vector2(0, -9), Vector2(6.5, 7), Vector2(0, 3.5), Vector2(-6.5, 7)]:
		arrow.append(centre + point.rotated(rotation_angle))
	target.draw_circle(centre, 11, Color(.04, .12, .16, .92))
	target.draw_arc(centre, 11, 0, TAU, 32, Color("fff0c4"), 1.0, true)
	target.draw_colored_polygon(arrow, Color("ffe1a4"))
	# This rose marks the transported district reference, not camera heading.
	var compass: Vector2 = Vector2(size.x - 18, 21)
	target.draw_circle(compass, 12, Color(.06, .19, .23, .88))
	target.draw_line(compass + Vector2(-7, 0), compass + Vector2(7, 0), Color("93aba4"), 1, true)
	target.draw_line(compass + Vector2(0, -8), compass + Vector2(0, 7), Color("93aba4"), 1, true)
	target.draw_colored_polygon(PackedVector2Array([compass + Vector2(0, -9), compass + Vector2(-3, -2), compass + Vector2(3, -2)]), Color("efdcac"))
	target.draw_string(font, Vector2(size.x - 38, 46), "定向", HORIZONTAL_ALIGNMENT_LEFT, 34, 10, Color("e1e5cf"))
	var scale_start: Vector2 = Vector2(10, size.y - 12)
	var scale_width: float = 10 * map_scale()
	target.draw_rect(Rect2(scale_start + Vector2(-4, -17), Vector2(scale_width + 9, 23)), Color(.06, .19, .23, .8))
	target.draw_line(scale_start, scale_start + Vector2(scale_width, 0), Color("e6edda"), 1.4)
	for end: Vector2 in [scale_start, scale_start + Vector2(scale_width, 0)]:
		target.draw_line(end + Vector2(0, -3), end + Vector2(0, 2), Color("e6edda"), 1.2)
	target.draw_string(font, scale_start + Vector2(0, -5), "10 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("e6edda"))
