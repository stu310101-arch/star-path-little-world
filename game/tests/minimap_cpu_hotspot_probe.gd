extends SceneTree

# CPU-only real cartography probe. No world meshes, avatar preparation or GPU.
const SourceMap = preload("res://scripts/world_minimap.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")

class TestWorld:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer

class TimedMap:
	extends "res://scripts/world_minimap.gd"
	var samples: Array[int] = []
	var bounds_usec: int = 0
	var bounds_calls: int = 0
	var components: Dictionary = {}
	func record_component(label: String, started: int) -> void:
		components[label] = int(components.get(label,0)) + Time.get_ticks_usec() - started
	func _draw_cartography(target: Control) -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_cartography(target)
		samples.append(Time.get_ticks_usec() - started)
	func line_visible(points: PackedVector3Array, margin_m: float = 4.0) -> bool:
		var started: int = Time.get_ticks_usec()
		var answer: bool = super.line_visible(points, margin_m)
		bounds_usec += Time.get_ticks_usec() - started
		bounds_calls += 1
		return answer
	func outline(points: PackedVector2Array, color: Color, width: float) -> void:
		var started: int = Time.get_ticks_usec()
		super.outline(points,color,width)
		record_component("outline",started)
	func draw_walk(points: PackedVector2Array, width: float = 2.1, is_bridge: bool = false) -> void:
		var started: int = Time.get_ticks_usec()
		super.draw_walk(points,width,is_bridge)
		record_component("draw_walk",started)
	func draw_surface(points: PackedVector3Array, color: Color) -> void:
		var started: int = Time.get_ticks_usec()
		super.draw_surface(points,color)
		record_component("draw_surface",started)
	func draw_planar_surface(points: PackedVector2Array, color: Color) -> void:
		var started: int = Time.get_ticks_usec()
		super.draw_planar_surface(points,color)
		record_component("draw_planar_surface",started)
	func project_line(points: PackedVector3Array) -> PackedVector2Array:
		var started: int = Time.get_ticks_usec()
		var result: PackedVector2Array = super.project_line(points)
		record_component("project_line_inclusive",started)
		return result

var report: Dictionary = {"scope": "Native headless CPU script/canvas submission only; not GPU or Web FPS. line_visible timer instrumentation is included."}
var world: TestWorld
var map: TimedMap

func _initialize() -> void:
	call_deferred("run")

func stats(samples: Array[int]) -> Dictionary:
	var ordered: Array[int] = samples.duplicate()
	ordered.sort()
	var total: int = 0
	for value: int in ordered:
		total += value
	return {"count":ordered.size(), "mean_ms":float(total)/maxi(ordered.size(),1)/1000.0, "p95_ms":ordered[maxi(0,ceili(ordered.size()*.95)-1)]/1000.0, "max_ms":ordered.back()/1000.0}

func sample(label: String, normal: Vector3) -> void:
	world.player.position = normal * (float(world.layout.radius) + .6)
	map.refresh()
	await process_frame
	await process_frame
	map.samples.clear()
	map.bounds_usec = 0
	map.bounds_calls = 0
	map.components.clear()
	for index: int in range(24):
		world.player.position = world.player.position.rotated(Vector3.RIGHT, .0001)
		map.refresh()
		await process_frame
		await process_frame
	var result: Dictionary = stats(map.samples)
	result["stage"] = label
	result["bounds_ms_per_draw"] = float(map.bounds_usec)/maxi(map.samples.size(),1)/1000.0
	result["bounds_calls_per_draw"] = float(map.bounds_calls)/maxi(map.samples.size(),1)
	result["nested_component_ms_per_draw"] = {}
	for label_key: String in map.components:
		result.nested_component_ms_per_draw[label_key] = float(map.components[label_key])/maxi(map.samples.size(),1)/1000.0
	(report.samples as Array).append(result)
	print("MINIMAP_HOTSPOT ", JSON.stringify(result))

func lookup_microbench() -> void:
	var points: PackedVector3Array = map.patches[0].coast
	var copied: PackedVector3Array = points.duplicate()
	var values: Dictionary = {points:42}
	var sink: int = 0
	var start: int = Time.get_ticks_usec()
	for repeat: int in range(10000):
		if values.has(points):
			sink += int(values[points])
	var hash_usec: int = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for repeat: int in range(10000):
		if is_same(points, points):
			sink += 42
	var identity_usec: int = Time.get_ticks_usec() - start
	var retained: PackedVector3Array = copied
	copied[2] += Vector3(.001,0,0)
	report["cache_microbench"] = {"points":points.size(),"iterations":10000,"array_key_has_get_ms":hash_usec/1000.0,"identity_check_ms":identity_usec/1000.0,"duplicate_has_distinct_identity":not is_same(points,copied),"mutation_has_distinct_identity":not is_same(retained,copied),"sink":sink}

func run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("This diagnostic must use --headless.")
		quit(1)
		return
	Engine.max_fps = 120
	root.size = Vector2i(1280,800)
	world = TestWorld.new()
	world.layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	world.player = PlanetPlayer.new()
	world.player.planet_radius = float(world.layout.radius)
	world.player.process_mode = Node.PROCESS_MODE_DISABLED
	world.add_child(world.player)
	var stations: Node3D = Node3D.new()
	stations.name = "Stations"
	world.add_child(stations)
	for row: Dictionary in world.layout.stations:
		var station: Node3D = Node3D.new()
		station.name = str(row.id)
		var normal: Array = row.normal
		station.position = Vector3(normal[0],normal[1],normal[2]) * float(world.layout.radius)
		stations.add_child(station)
	root.add_child(world)
	world.player.position = Vector3.UP * (float(world.layout.radius)+.6)
	map = TimedMap.new()
	map.world = world
	map.size = Vector2(246,180)
	root.add_child(map)
	map.set_process(false)
	await create_timer(.2).timeout
	report["samples"] = []
	report["renderer"] = DisplayServer.get_name()
	report["engine"] = Engine.get_version_info()
	report["source_sha256"] = FileAccess.get_sha256("res://scripts/world_minimap.gd")
	await sample("moving_counseling", Vector3.UP)
	await sample("moving_bridge", Routes.directions()[0].slerp(Routes.directions()[1],.5))
	map.compact_preview = true
	map.size = Vector2(128,90)
	await sample("compact_moving_counseling", Vector3.UP)
	await sample("compact_moving_bridge", Routes.directions()[0].slerp(Routes.directions()[1],.5))
	lookup_microbench()
	var path: String = "res://../deliverables/performance-20261020/minimap-hotspot-before.json"
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var output_index: int = args.find("--output")
	if output_index >= 0 and output_index + 1 < args.size():
		path = args[output_index + 1]
	var output: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	print("MINIMAP_HOTSPOT_RESULT ", path)
	quit()
