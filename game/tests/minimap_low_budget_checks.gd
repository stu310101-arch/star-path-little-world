extends SceneTree

# Same process A/B/A, same authored cartography and 4 s / 3.8 m/s route.
# Legacy mode reproduces the former 10 Hz full-detail low desktop minimap.
# Actual CanvasItem draw notifications run both implementations. Headless
# timings include script/native canvas work, not GPU, browser FPS or thermals.
class TestWorld:
	extends Node3D
	var layout: Dictionary
	var player: PlanetPlayer

class QualityStub:
	extends Node
	var low: bool = true
	var constrained: bool = false
	func is_low_quality() -> bool:
		return low
	func is_constrained_runtime() -> bool:
		return constrained

class BudgetMap:
	extends "res://scripts/world_minimap.gd"
	var legacy: bool = false
	var samples: Array[float] = []
	func _uses_lightweight_cartography() -> bool:
		return compact_preview if legacy else super._uses_lightweight_cartography()
	func _process(delta: float) -> void:
		if not legacy:
			super._process(delta)
			return
		refresh_clock += delta
		if refresh_clock >= .10 and is_visible_in_tree():
			refresh_clock = 0.0
			refresh()
	func _draw_cartography(target: Control) -> void:
		var started: int = Time.get_ticks_usec()
		super._draw_cartography(target)
		samples.append(float(Time.get_ticks_usec() - started) / 1000.0)

var checks: Array[Dictionary] = []
var report: Dictionary = {"samples": [], "method": "Controlled same-process A/B/A using actual CanvasItem draws. Each stage drives the same 80 navigation ticks, 4 simulated seconds at 3.8 m/s; native CPU draw times exclude GPU and are not phone FPS or temperature evidence."}
var failures: int = 0
var world: TestWorld
var map: BudgetMap
var quality: QualityStub

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"passed":passed})
	if not passed:
		failures += 1
		push_error(label)

func settle() -> void:
	await process_frame
	await process_frame

func summary(samples: Array[float]) -> Dictionary:
	var values: Array[float] = samples.duplicate()
	values.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	return {"draws":values.size(),"total_cpu_ms":total,"median_draw_ms":values[values.size()/2] if not values.is_empty() else 0.0,"p95_draw_ms":values[mini(values.size()-1,ceili(values.size()*.95)-1)] if not values.is_empty() else 0.0}

func sample(label: String, legacy: bool) -> void:
	map.legacy = legacy
	world.player.position = Vector3.UP * (map.radius + .6)
	map.frame_ready = false
	map._cartography_dirty = true
	map.refresh_clock = 0.0
	map._cartography_clock = 0.0
	map.refresh()
	await settle()
	# Finish font-atlas invalidations before counting the controlled route.
	await create_timer(.15).timeout
	await settle()
	map.samples.clear()
	var deferred_before: int = map._deferred_map_refreshes
	for tick: int in range(80):
		world.player.position = (Vector3.UP.rotated(Vector3.RIGHT, (tick + 1) * .05 * 3.8 / map.radius)) * (map.radius + .6)
		map._process(.050001)
		await settle()
	var result: Dictionary = summary(map.samples)
	result["stage"] = label
	result["compact_preview"] = map.compact_preview
	result["deferred_refreshes"] = map._deferred_map_refreshes - deferred_before
	result["size"] = [map.size.x,map.size.y]
	(report.samples as Array).append(result)
	print("MINIMAP_LOW_BUDGET_SAMPLE ",JSON.stringify(result))
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/low-end-20261021/minimap-" + label + ".png"))
	if not legacy:
		check(label + " rebuilds no more than five times per second", map.samples.size() <= 20)

func run() -> void:
	Engine.max_fps = 240
	root.size = Vector2i(640,400)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../deliverables/low-end-20261021"))
	quality = QualityStub.new()
	root.add_child(quality)
	quality.add_to_group("graphics_settings")
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
		station.position = Vector3(row.normal[0],row.normal[1],row.normal[2]) * float(world.layout.radius)
		stations.add_child(station)
	root.add_child(world)
	world.player.position = Vector3.UP * (float(world.layout.radius)+.6)
	map = BudgetMap.new()
	map.world = world
	map.size = Vector2(246,180)
	root.add_child(map)
	map.set_process(false)
	await create_timer(.2).timeout
	await settle()
	for compact: bool in [false,true]:
		map.compact_preview = compact
		map.size = Vector2(128,90) if compact else Vector2(246,180)
		var prefix: String = "compact" if compact else "desktop"
		await sample(prefix + "_legacy_A0",true)
		await sample(prefix + "_budget_B",false)
		await sample(prefix + "_legacy_A1",true)
	map.legacy = false
	map.compact_preview = false
	map.size = Vector2(246,180)
	world.player.position = Vector3.UP * (map.radius + .6)
	map.refresh()
	await settle()
	var count: int = map._map_draws
	map.refresh_clock = 0.0
	map._cartography_clock = 0.0
	world.player.position = world.player.position.rotated(Vector3.RIGHT,.001)
	map._process(.050001)
	await settle()
	check("Subpixel motion keeps cached cartography", map._map_draws == count)
	check("Navigation projects the actual moved player on the retained map", map._player_map_position.distance_to(map.project_point(world.player.position.normalized())) < .00001 and map._player_map_position.distance_to(map.size*.5) > .01)
	var previous_position: Vector2 = map._player_map_position
	world.player.position *= 1.1
	map._process(.050001)
	await settle()
	check("Radial jumps keep projected navigation position", map._player_map_position.distance_to(previous_position) < .0001)
	world.player.position = Vector3.RIGHT * (map.radius + .6)
	map._process(.050001)
	await settle()
	check("Teleport bypasses refresh budget and recentres immediately", map.centre_up.distance_to(Vector3.RIGHT) < .00001 and map._player_map_position.distance_to(map.size*.5) < .001)
	count = map._map_draws
	map.size += Vector2(20,20)
	map._process(.050001)
	await settle()
	check("Resize bypasses refresh budget", map._map_draws > count)
	quality.low = false
	map._process(.050001)
	await settle()
	check("Switching to standard restores complete detail", not map._uses_lightweight_cartography())
	quality.constrained = true
	map._process(.050001)
	await settle()
	check("Runtime pressure under standard activates lightweight cartography", not quality.is_low_quality() and map._uses_lightweight_cartography())
	count = map._map_draws
	world.player.position = world.player.position.rotated(Vector3.UP,.001)
	map._process(.050001)
	await settle()
	check("Standard runtime pressure also defers costly subpixel redraws", map._map_draws == count)
	quality.constrained = false
	map._process(.050001)
	await settle()
	check("Cleared runtime pressure restores standard cartography", not map._uses_lightweight_cartography())
	quality.low = true
	map._process(.050001)
	await settle()
	check("Switching to low restores bounded detail", map._uses_lightweight_cartography())
	check("Source coastline retained for full map and navigation", (map.patches[0].coast as PackedVector3Array).size() > map.compact_source_line(map.patches[0].coast).size())
	map.build_cartography()
	check("Cartography rebuild releases simplified geometry cache", map._compact_lines.is_empty())
	report["checks"] = checks
	report["passed"] = failures == 0
	report["failures"] = failures
	report["source_sha256"] = FileAccess.get_sha256("res://scripts/world_minimap.gd")
	report["engine"] = Engine.get_version_info()
	report["display"] = DisplayServer.get_name()
	var directory: String = ProjectSettings.globalize_path("res://../deliverables/low-end-20261021")
	DirAccess.make_dir_recursive_absolute(directory)
	var file: FileAccess = FileAccess.open(directory + ("/minimap-budget.json" if DisplayServer.get_name() == "headless" else "/minimap-budget-rendered.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	map.free()
	world.free()
	quality.free()
	print("MINIMAP_LOW_BUDGET_RESULT ", failures)
	quit(0 if failures == 0 else 1)
