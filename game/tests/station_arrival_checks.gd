extends SceneTree

## Checks the exact shipped static collision graph. It does not create a safe
## test-only floor or remove real objects around the six arrival bays.
const Geo = preload("res://scripts/planet_geometry.gd")
const Outdoor = preload("res://scripts/outdoor_scale.gd")
const AVATAR_SCALE: float = .4
var checks: Array[Dictionary] = []
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	world.set_script(null)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var diagnostic: bool = OS.get_cmdline_user_args().has("--scaled-source-fixture")
	var scale_factor: float = .4 if diagnostic else Outdoor.factor(layout)
	for name: String in ["Globe","Neighborhood","Stations"]:
		Outdoor.apply_to_children(world.get_node(name) as Node3D,scale_factor)
	root.add_child(world)
	await physics_frame
	await physics_frame
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	var radius: float = 24.0 if diagnostic else Outdoor.physical_radius(layout)
	for station: Node3D in world.get_node("Stations").get_children():
		var marker: Marker3D = station.get_node_or_null("Arrival") as Marker3D
		record(str(station.name) + " arrival marker", marker != null)
		if marker == null:
			continue
		var arrival: Vector3 = marker.global_position.normalized()
		var portal: Vector3 = station.global_position.normalized()
		for index: int in range(17):
			var n: Vector3 = arrival.slerp(portal, float(index) / 16.0).normalized()
			var hit: Dictionary = Geo.ground_probe(space, n, radius)
			record("%s lane sample %02d ground" % [station.name, index], not hit.is_empty())
			if hit.is_empty():
				continue
			var shape: CapsuleShape3D = CapsuleShape3D.new()
			# Production radius .27 / height 1.6, with extra clearance padding.
			shape.radius = .30 * AVATAR_SCALE
			shape.height = 1.64 * AVATAR_SCALE
			var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.collision_mask = 8
			query.margin = .015 * AVATAR_SCALE
			query.transform = Transform3D(Geo.frame(n), (hit.position as Vector3) + n * .845 * AVATAR_SCALE)
			var overlaps: Array[Dictionary] = space.intersect_shape(query, 16)
			var blocking: Array[String] = []
			for overlap: Dictionary in overlaps:
				blocking.append(str((overlap.collider as Node).get_path()))
			record("%s lane sample %02d capsule clearance" % [station.name, index], blocking.is_empty(), blocking)
		# Check the arrival disk's usable cross-section, not only its centre.
		var axes: Basis = Geo.frame(arrival)
		for side: float in [-.55, .55]:
			var probe: Vector3 = (marker.global_position + axes.z * side).normalized()
			record(str(station.name) + " arrival paving " + str(side), not Geo.ground_probe(space, probe, radius).is_empty())
	var output: String = ProjectSettings.globalize_path("res://../deliverables/world-redesign")
	DirAccess.make_dir_recursive_absolute(output)
	var report: Dictionary = {"passed": failures == 0, "failures": failures, "count": checks.size(), "checks": checks,"avatar_scale":AVATAR_SCALE,"probe_capsule_radius_m":.30*AVATAR_SCALE,"probe_capsule_height_m":1.64*AVATAR_SCALE,
		"scope": "Exact world static colliders; six arrival markers, 17 floor/capsule probes on every arrival-to-portal lane, lateral paving probes. Render appearance is checked separately."}
	FileAccess.open(output.path_join("station-arrival-checks.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	print("STATION_ARRIVAL_CHECKS ", checks.size(), " failures=", failures)
	world.queue_free()
	await process_frame
	quit(0 if failures == 0 else 1)

func record(label: String, passed: bool, details: Variant = null) -> void:
	checks.append({"name": label, "passed": passed, "details": details})
	if not passed:
		failures += 1
		push_error(label + " " + str(details))
