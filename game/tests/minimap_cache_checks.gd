extends SceneTree

# Exercise the real retained CanvasItem commands without decoding world/avatar
# meshes. These are correctness checks, not a rendered Web FPS benchmark.
class TestWorld:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer

class QualityStub:
	extends Node
	var low: bool = true
	func is_low_quality() -> bool:
		return low

class ObservedMap:
	extends "res://scripts/world_minimap.gd"
	var draw_notifications: int = 0
	var refresh_calls: int = 0
	var cache_hits: int = 0
	var projected_points: int = 0
	var projection_error: float = 0.0
	var cache_not_cleared: bool = false
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW:
			draw_notifications += 1
	func refresh() -> void:
		refresh_calls += 1
		super.refresh()
	func _draw() -> void:
		super._draw()
		cache_not_cleared = cache_not_cleared or not _projected_lines.is_empty() or _drawing_map
	func project_line(points: PackedVector3Array) -> PackedVector2Array:
		if _drawing_map and _projected_lines.has(points):
			cache_hits += 1
		var projected: PackedVector2Array = super.project_line(points)
		# project_point retains the pre-optimization scalar projection. Compare
		# every actual submitted line, including both cache hits and misses.
		for index: int in range(points.size()):
			projection_error = maxf(projection_error, projected[index].distance_to(project_point(points[index])))
		projected_points += points.size()
		return projected

var checks: Array[Dictionary] = []
var failures: int = 0
var world: TestWorld
var minimap: ObservedMap
var quality: QualityStub
var navigation_draws: int = 0

func check(title: String, passed: bool, detail: String = "") -> void:
	checks.append({"name":title,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(title + ": " + detail)

func _initialize() -> void:
	call_deferred("run")

func settle_draw() -> void:
	await process_frame
	await process_frame

func observe_navigation_draw() -> void:
	navigation_draws += 1

func check_redrawn(title: String, map_before: int, navigation_before: int) -> void:
	check(title + " redraws retained map", minimap.draw_notifications > map_before)
	check(title + " redraws navigation child", navigation_draws > navigation_before)
	check(title + " releases per-draw projection cache", minimap._projected_lines.is_empty() and not minimap._drawing_map)

func run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280,800)
	quality = QualityStub.new()
	root.add_child(quality)
	quality.add_to_group("graphics_settings")
	world = TestWorld.new()
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	world.player = PlanetPlayer.new()
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(world.player)
	var stations: Node3D = Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station: Node3D = Node3D.new()
		station.name = str(row.id)
		var normal: Array = row.normal as Array
		station.position = Vector3(normal[0],normal[1],normal[2]) * 48.0
		stations.add_child(station)
	root.add_child(world)
	world.player.global_position = Vector3.UP * 48.6
	minimap = ObservedMap.new()
	minimap.world = world
	minimap.size = Vector2(246,180)
	root.add_child(minimap)
	minimap.set_process(false)
	minimap._navigation.draw.connect(observe_navigation_draw)
	await settle_draw()
	check("Initial map receives actual CanvasItem DRAW", minimap.draw_notifications > 0)
	check("Initial navigation receives actual CanvasItem draw signal", navigation_draws > 0)
	check("Graphics settings group is resolved", minimap._quality_settings == quality)
	check("Fill and outline actually reuse projected lines", minimap.cache_hits > 0, str(minimap.cache_hits))
	check("Cache is empty after initial draw", minimap._projected_lines.is_empty())

	var map_before: int = minimap.draw_notifications
	var navigation_before: int = navigation_draws
	var frame_before: Vector3 = minimap.map_forward
	for repeat: int in range(10):
		minimap.refresh()
		await settle_draw()
	check("Stationary refresh produces zero full-map redraws", minimap.draw_notifications == map_before)
	check("Stationary refresh produces zero navigation redraws", navigation_draws == navigation_before)
	check("Stationary refresh preserves map frame", minimap.map_forward == frame_before)

	var arrow_before: Vector2 = minimap.arrow_heading_2d
	world.player.visual.rotate_y(.7)
	minimap.refresh()
	await settle_draw()
	check("Facing change updates arrow bearing", minimap.arrow_heading_2d.distance_to(arrow_before) > .1)
	check("Facing change redraws only navigation child", minimap.draw_notifications == map_before and navigation_draws > navigation_before)
	check("Facing change leaves cartography frame unchanged", minimap.map_forward == frame_before)

	map_before = minimap.draw_notifications
	navigation_before = navigation_draws
	world.player.global_position = world.player.global_position.rotated(Vector3.RIGHT, .07)
	minimap.refresh()
	await settle_draw()
	check_redrawn("Surface movement", map_before, navigation_before)
	check("Movement updates centre to actual normalized player position", minimap.centre_up.distance_to(world.player.global_position.normalized()) < .000001)
	check("Moved player is still centred on minimap", minimap.project_point(world.player.global_position.normalized()).distance_to(minimap.size * .5) < .001)

	map_before = minimap.draw_notifications
	navigation_before = navigation_draws
	frame_before = minimap.map_forward
	for distance: float in [49.0, 50.3, 53.2, 48.6]:
		world.player.global_position = world.player.global_position.normalized() * distance
		minimap.refresh()
		await settle_draw()
	check("Radial jumping produces zero map redraws", minimap.draw_notifications == map_before)
	check("Radial jumping preserves map frame", minimap.map_forward == frame_before)
	check("Radial jumping preserves navigation commands", navigation_draws == navigation_before)

	map_before = minimap.draw_notifications
	navigation_before = navigation_draws
	minimap.size = Vector2(280,224)
	minimap.refresh()
	await settle_draw()
	check_redrawn("Map resize", map_before, navigation_before)
	check("Navigation child follows resized map bounds", minimap._navigation.size == minimap.size)
	var sample_point: Vector3 = world.player.global_position.normalized().rotated(Vector3.RIGHT,.15)
	var extent_before: float = minimap.project_point(sample_point).distance_to(minimap.size * .5)
	map_before = minimap.draw_notifications
	navigation_before = navigation_draws
	minimap.view_range *= 2.0
	minimap.refresh()
	await settle_draw()
	check_redrawn("Map view-range change", map_before, navigation_before)
	check("View-range change updates projection scale", is_equal_approx(minimap.project_point(sample_point).distance_to(minimap.size * .5), extent_before * .5))

	map_before = minimap.draw_notifications
	navigation_before = navigation_draws
	var previous_patch_count: int = minimap.patches.size()
	minimap.build_cartography()
	check("Cartography rebuild invalidates retained map", minimap._cartography_dirty)
	minimap.refresh()
	await settle_draw()
	check_redrawn("Cartography rebuild", map_before, navigation_before)
	check("Cartography rebuild replaces rather than accumulates patches", minimap.patches.size() == previous_patch_count and not minimap._cartography_dirty)

	# Repeat moves/teleports; every completed draw must release both packed
	# array keys and projected values, and match the scalar projection reference.
	for normal: Vector3 in [Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK,Vector3.UP]:
		world.player.global_position = normal * 48.6
		minimap.refresh()
		await settle_draw()
		check("Teleport centres player at " + str(normal), minimap.centre_up.distance_to(normal) < .000001)
		check("Teleport clears projection cache at " + str(normal), minimap._projected_lines.is_empty())
	var lines: PackedVector3Array = PackedVector3Array([Vector3.UP,Vector3.DOWN,Vector3(1,.0001,.5).normalized()])
	var first: PackedVector2Array = minimap.project_line(lines)
	var first_copy: PackedVector2Array = first.duplicate()
	minimap.size += Vector2(16,12)
	var second: PackedVector2Array = minimap.project_line(lines)
	check("Projection outside draw never retains stale cache", minimap._projected_lines.is_empty() and first != second)
	check("Projection leaves previous returned line intact", first == first_copy)
	check("All cached/uncached projected coordinates match old scalar formula", minimap.projected_points > 1000 and minimap.projection_error <= .00001, "points=" + str(minimap.projected_points) + " max_error=" + str(minimap.projection_error))
	check("Every draw exits with cache empty and drawing flag reset", not minimap.cache_not_cleared)
	await settle_draw()

	# Deterministic synthetic elapsed time tests the production scheduling code,
	# rather than depending on variable headless wall-clock frame pacing.
	quality.low = true
	minimap.refresh_clock = 0.0
	var refresh_before: int = minimap.refresh_calls
	minimap._process(.05)
	check("Low profile does not refresh at 50 ms", minimap.refresh_calls == refresh_before)
	minimap._process(.049)
	check("Low profile waits until 100 ms", minimap.refresh_calls == refresh_before)
	minimap._process(.00101)
	check("Low profile refreshes at 100 ms", minimap.refresh_calls == refresh_before + 1)
	quality.low = false
	minimap.refresh_clock = 0.0
	refresh_before = minimap.refresh_calls
	minimap._process(.049)
	check("Standard profile waits until 50 ms", minimap.refresh_calls == refresh_before)
	minimap._process(.00101)
	check("Standard profile refreshes at 50 ms", minimap.refresh_calls == refresh_before + 1)
	minimap.hide()
	refresh_before = minimap.refresh_calls
	minimap._process(1.0)
	check("Hidden minimap does not refresh", minimap.refresh_calls == refresh_before)
	minimap.show()
	minimap._process(.001)
	check("Reopened minimap can refresh immediately", minimap.refresh_calls == refresh_before + 1)
	quality.free()
	minimap.refresh_clock = 0.0
	refresh_before = minimap.refresh_calls
	minimap._process(.05001)
	check("Removed settings node safely uses standard interval", minimap.refresh_calls == refresh_before + 1)
	await settle_draw()
	var result: Dictionary = {"passed":failures == 0,"failed":failures,"checks":checks,"method":"Headless CanvasItem DRAW correctness; no GPU/FPS claim, no full world/avatar resources.","source_sha256":FileAccess.get_sha256("res://scripts/world_minimap.gd"),"map_draws":minimap.draw_notifications,"navigation_draws":navigation_draws,"cache_hits":minimap.cache_hits,"projected_points":minimap.projected_points,"max_projection_error":minimap.projection_error}
	var output: FileAccess = FileAccess.open("res://../deliverables/low-end/minimap-cache-checks.json", FileAccess.WRITE)
	output.store_string(JSON.stringify(result,"\t"))
	output.close()
	print(JSON.stringify(result))
	minimap.free()
	world.free()
	quit(0 if failures == 0 else 1)
