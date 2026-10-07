extends SceneTree

const Geo: Script = preload("res://scripts/planet_geometry.gd")
const OUTPUT: String = "res://../deliverables/low-end/minimap-cpu-probe.json"

class TestWorld:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer

class ProbeMap:
	extends "res://scripts/world_minimap.gd"
	var refresh_usec: Array[int] = []
	var draw_usec: Array[int] = []
	var draw_notifications: int = 0
	var skip_unchanged: bool = false
	var previous_position: Vector3 = Vector3.INF
	var previous_facing: Vector3 = Vector3.INF
	var previous_size: Vector2 = Vector2.INF
	var component_times: Dictionary = {}
	func _notification(what: int) -> void:
		if what == NOTIFICATION_DRAW:
			draw_notifications += 1
	func refresh() -> void:
		var started: int = Time.get_ticks_usec()
		var facing: Vector3 = player.visual.global_basis.z if player.visual != null else player.heading
		if skip_unchanged and previous_position == player.global_position and previous_facing == facing and previous_size == size:
			refresh_usec.append(Time.get_ticks_usec() - started)
			return
		previous_position = player.global_position
		previous_facing = facing
		previous_size = size
		super.refresh()
		refresh_usec.append(Time.get_ticks_usec() - started)
	func _draw() -> void:
		var started: int = Time.get_ticks_usec()
		super._draw()
		draw_usec.append(Time.get_ticks_usec() - started)
	func record_component(label: String, started: int) -> void:
		var elapsed: int = Time.get_ticks_usec() - started
		if not component_times.has(label):
			component_times[label] = {"calls":0,"total_usec":0,"max_usec":0}
		var record: Dictionary = component_times[label] as Dictionary
		record.calls += 1
		record.total_usec += elapsed
		record.max_usec = maxi(int(record.max_usec), elapsed)
	func clean_polygon(points: PackedVector2Array) -> PackedVector2Array:
		var started: int = Time.get_ticks_usec()
		var result: PackedVector2Array = super.clean_polygon(points)
		record_component("clean_polygon", started)
		return result
	func project_polygons(points: PackedVector3Array) -> Array[PackedVector2Array]:
		var started: int = Time.get_ticks_usec()
		var result: Array[PackedVector2Array] = super.project_polygons(points)
		record_component("project_polygons_inclusive", started)
		return result
	func project_line(points: PackedVector3Array) -> PackedVector2Array:
		var started: int = Time.get_ticks_usec()
		var result: PackedVector2Array = super.project_line(points)
		record_component("project_line", started)
		return result
	func triangulate_surface(points: PackedVector2Array) -> PackedInt32Array:
		var started: int = Time.get_ticks_usec()
		var result: PackedInt32Array = super.triangulate_surface(points)
		record_component("triangulate_surface", started)
		return result
	func draw_navigation_overlay(font: Font) -> void:
		var started: int = Time.get_ticks_usec()
		super.draw_navigation_overlay(font)
		record_component("draw_navigation_overlay", started)
	func reset_counters() -> void:
		refresh_usec.clear()
		draw_usec.clear()
		draw_notifications = 0
		component_times.clear()

var world: TestWorld
var map: ProbeMap
var report: Dictionary = {"samples":[], "method":"Headless native GDScript CPU timing: actual CanvasItem redraw notifications invoke super._draw, including projection/clipping/triangulation. Rendering backend is dummy: excludes GPU cost, not Web FPS. Minimal world fixture uses production JSON/route cartography and PlanetPlayer without preparing any avatar assets; no world mesh or audio decoding. Optional Marina nodes are absent. Timed component wrappers add instrumentation overhead."}

func _initialize() -> void:
	call_deferred("run")

func summarize(values: Array[int]) -> Dictionary:
	if values.is_empty():
		return {"count":0,"total_ms":0.0,"mean_ms":0.0,"p95_ms":0.0,"max_ms":0.0}
	var sorted: Array[int] = values.duplicate()
	sorted.sort()
	var total: int = 0
	for value: int in sorted:
		total += value
	return {"count":sorted.size(),"total_ms":total/1000.0,"mean_ms":float(total)/sorted.size()/1000.0,"p95_ms":sorted[mini(sorted.size()-1,ceili(sorted.size()*.95)-1)]/1000.0,"max_ms":sorted.back()/1000.0}

func sample(label: String, normal: Vector3, guarded: bool, moving: bool = false) -> void:
	world.player.global_position = normal.normalized() * 48.6
	map.skip_unchanged = guarded
	map.previous_position = Vector3.INF
	map.refresh()
	await process_frame
	await process_frame
	map.reset_counters()
	var started: int = Time.get_ticks_usec()
	var deadline: int = started + 800000
	while Time.get_ticks_usec() < deadline:
		if moving:
			world.player.global_position = world.player.global_position.rotated(Vector3.RIGHT, .0001)
		await process_frame
	var duration: float = float(Time.get_ticks_usec() - started) / 1000000.0
	var draw: Dictionary = summarize(map.draw_usec)
	var row: Dictionary = {"stage":label,"duration_s":duration,"guarded":guarded,"moving":moving,"size":str(map.size),"patches":map.patches.size(),"draw_notifications":map.draw_notifications,"refresh":summarize(map.refresh_usec),"draw":draw,"draw_script_ms_per_second":float(draw.total_ms)/duration}
	row["components"] = map.component_times.duplicate(true)
	row["component_note"] = "Nested inclusive timing: project_polygons includes project_line and clean_polygon. Do not sum overlapping components; profiling adds stopwatch/dictionary overhead."
	report.samples.append(row)
	print("MINIMAP_CPU_SAMPLE ", JSON.stringify(row))

func run() -> void:
	Engine.max_fps = 120
	root.size = Vector2i(1280, 800)
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
	map = ProbeMap.new()
	map.world = world
	map.size = Vector2(246,180)
	var started: int = Time.get_ticks_usec()
	root.add_child(map)
	report["cartography_ready_ms"] = float(Time.get_ticks_usec() - started)/1000.0
	report["engine"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	report["production_source_sha256"] = FileAccess.get_sha256("res://scripts/world_minimap.gd")
	report["probe_source_sha256"] = FileAccess.get_sha256("res://tests/minimap_performance_probe.gd")
	await sample("stationary_counseling", Vector3.UP, false)
	await sample("stationary_bridge", Vector3(0,1,1), false)
	await sample("stationary_wordking", Vector3.DOWN, false)
	await sample("guarded_stationary_counseling", Vector3.UP, true)
	await sample("guarded_moving_counseling", Vector3.UP, true, true)
	var output_path: String = OUTPUT.trim_suffix(".json") + "-breakdown.json"
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var output_index: int = arguments.find("--output")
	if output_index >= 0 and output_index + 1 < arguments.size():
		output_path = arguments[output_index + 1]
	var output: FileAccess = FileAccess.open(output_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(report,"\t"))
	output.close()
	print("MINIMAP_CPU_RESULT ", output_path)
	quit()
