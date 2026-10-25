extends SceneTree

## Measures underlying world curvature independently of the authored hills.
## Arc distance is metres walked on level ground, not a camera zoom metric.
const Geo = preload("res://scripts/planet_geometry.gd")

func _initialize() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var radius: float = float(layout.radius)
	var samples: Array[Dictionary] = []
	var failures: Array[String] = []
	for distance: float in [10.0,20.0]:
		var angle: float = distance/radius
		var tangent_offset: float = radius*tan(angle)
		var point: Vector3 = Geo.surface(Vector3.UP,Vector2(tangent_offset,0.0),radius)
		var actual_drop: float = radius-point.y
		var actual_angle: float = rad_to_deg(Vector3.UP.angle_to(point.normalized()))
		var expected_drop: float = radius*(1.0-cos(angle))
		var passed: bool = actual_angle<2.0 and actual_drop<.34 and absf(actual_drop-expected_drop)<.0005
		if not passed:
			failures.append("Walking curvature too high at "+str(distance)+" m")
		samples.append({"walking_distance_m":distance,"height_drop_from_start_tangent_m":expected_drop,"normal_change_degrees":rad_to_deg(angle),"generated_position_drop_m":actual_drop,"generated_normal_change_degrees":actual_angle,"previous_48m_radius_drop_m":48.0*(1.0-cos(distance/48.0)),"previous_48m_radius_normal_change_degrees":rad_to_deg(distance/48.0),"passed":passed})
	var report: Dictionary = {"radius_m":radius,"passed":failures.is_empty(),"failures":failures,"samples":samples,"scope":"Curvature of the underlying ground over 10 m and 20 m walking arcs, relative to the tangent plane at the start. Authored hills are measured separately by landform checks. World retains gentle curvature; it is not mathematically flat."}
	var output: String = ProjectSettings.globalize_path("res://../deliverables/world-redesign/spherical-curvature-checks.json")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("SPHERICAL_CURVATURE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
