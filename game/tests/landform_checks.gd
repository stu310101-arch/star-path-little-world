extends SceneTree

const Landforms = preload("res://tools/world_landforms.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var radius: float = float(layout.radius)
	var field_only: bool = OS.get_cmdline_user_args().has("--field-only")
	var globe: Node3D
	var space: PhysicsDirectSpaceState3D
	if not field_only:
		globe = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
		root.add_child(globe)
		await physics_frame
		await physics_frame
		space = globe.get_world_3d().direct_space_state
	var fingerprints: Dictionary = {}
	for path: String in ["res://data/world_layout.json","res://data/districts.json","res://scripts/world_routes.gd","res://tools/world_landforms.gd","res://tools/ecology_world.gd"]:
		fingerprints[path]=FileAccess.get_sha256(path)
	var report: Dictionary = {"districts": [], "field_only":field_only,"tested_unix_time":Time.get_unix_time_from_system(),"source_fingerprints":fingerprints}
	for index: int in range(districts.size()):
		var data: Dictionary = districts[index]
		var values: Array = layout.stations[index].normal
		var up: Vector3 = Vector3(values[0],values[1],values[2])
		var field: RefCounted = Landforms.new()
		field.call("configure",data,index,radius,up)
		var samples: int = 0
		var protected_samples: int = 0
		var maximum: float = 0.0
		var maximum_slope: float = 0.0
		var max_collision_error: float = 0.0
		var max_terrain_collision_error: float = 0.0
		var max_mesh_collision_error: float = 0.0
		var walkway_samples: int = 0
		var walkway_colliders: Dictionary = {}
		for x: int in range(-34,35):
			for z: int in range(-34,35):
				var p: Vector2 = Vector2(float(x)+.19,float(z)+.27)
				var shore: float = float(field.call("dry_distance",p))
				if shore < .5:
					continue
				var height: float = float(field.call("height_at",p))
				var base: float = .09+.075*smoothstep(0.0,1.1,shore)
				maximum = maxf(maximum,height)
				var normal: Vector3 = Geo.surface(up,p,radius).normalized()
				var slope: float = rad_to_deg(normal.angle_to(field.call("normal_at",p) as Vector3))
				maximum_slope = maxf(maximum_slope,slope)
				if float(field.call("clearance",p)) <= 0.0:
					protected_samples += 1
					if absf(height-base)>.0001:
						failures.append(str(data.station)+": raised protected road/building at "+str(p))
				if not field_only:
					var ground: Dictionary = Geo.ground_probe(space,normal,radius)
					if ground.is_empty():
						failures.append(str(data.station)+": no generated collision at "+str(p))
					else:
						var actual: float = (ground.position as Vector3).length()-radius
						var error: float = absf(actual-height)
						max_collision_error=maxf(max_collision_error,error)
						var collider_path: String = str((ground.collider as Node).get_path())
						var walkway: bool = collider_path.contains("Boardwalk") or collider_path.contains("/TownApproach/")
						if walkway:
							walkway_samples+=1
							walkway_colliders[collider_path]=int(walkway_colliders.get(collider_path,0))+1
						else:
							max_terrain_collision_error=maxf(max_terrain_collision_error,error)
						# Curved planar triangles interpolate the analytical field.
						# Authored timber and stone approaches sit above the ground.
						# The physics surface must match the visible triangle plane.
						# Comparing a curved analytic field directly to a planar cell
						# falsely failed a 0.8 m cell near life's tightly curved ridge.
						if not walkway:
							if shore>1.2:
								var mesh_error: float=absf(actual-float(field.call("mesh_height_at",p)))
								max_mesh_collision_error=maxf(max_mesh_collision_error,mesh_error)
								if mesh_error>.005: failures.append(str(data.station)+": visible mesh/collision mismatch "+str(mesh_error)+" at "+str(p))
							elif error>.07:
								failures.append(str(data.station)+": clipped shoreline interpolation mismatch "+str(error)+" at "+str(p))
				samples+=1
		if maximum<.38:
			failures.append(str(data.station)+": authored relief was completely suppressed")
		if maximum>=1.3:
			failures.append(str(data.station)+": relief exceeded ground probe height budget")
		if maximum_slope>44.0:
			failures.append(str(data.station)+": walking hillside exceeds 44 degrees")
		report.districts.append({"station":data.station,"samples":samples,"protected_samples":protected_samples,"maximum_height_m":maximum,"maximum_slope_degrees":maximum_slope,"max_collision_error_m":max_collision_error,"max_terrain_collision_error_m":max_terrain_collision_error,"max_visible_mesh_collision_error_m":max_mesh_collision_error,"walkway_samples_above_terrain":walkway_samples,"walkway_colliders":walkway_colliders})
		report["failures"]=failures
		report["passed"]=failures.is_empty()
		print("LANDFORM_DISTRICT ",JSON.stringify(report.districts[-1]))
	var output: String = ProjectSettings.globalize_path("res://../deliverables/world-redesign")
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output.path_join("landform-field-checks.json" if field_only else "landform-collision-checks.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	if globe!=null:
		globe.queue_free()
		await process_frame
	print("LANDFORM_CHECKS passed=",failures.is_empty()," failures=",failures.size())
	for failure: String in failures.slice(0,15):
		push_error(failure)
	quit(0 if failures.is_empty() else 1)
