extends SceneTree
const Navigation = preload("res://scripts/discussion_navigation.gd")
const LAYOUT := "res://assets/discussion_garden/layout.json"
var checks: Array[Dictionary] = []
var failures: int = 0
var routes: Array[Dictionary] = []
func _initialize() -> void:
	run.call_deferred()
func check(label: String, passed: bool) -> void:
	checks.append({"name":label,"pass":passed})
	print("NAVIGATION_CHECK ",label," ",passed)
	if not passed: failures += 1
func point(value: Variant) -> Vector3:
	return value if value is Vector3 else Vector3(value[0],value[1],value[2])
func distance(start: Vector3, path: Array) -> float:
	var total: float = 0
	var before: Vector3 = start
	for value: Variant in path:
		var position: Vector3 = point(value)
		total += before.distance_to(position)
		before = position
	return total
func segment_matches(first: Vector3, last: Vector3, lines: Array[Dictionary]) -> bool:
	for line: Dictionary in lines:
		if Geometry3D.get_closest_point_to_segment(first,line.a,line.b).distance_to(first) < .025 and Geometry3D.get_closest_point_to_segment(last,line.a,line.b).distance_to(last) < .025:
			return true
	return false
func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT))
	var zones: Dictionary = {}
	var lines: Array[Dictionary] = []
	for zone: Dictionary in layout.zones:
		zones[zone.id] = zone
		for index: int in range(zone.walk_path.size()-1):
			lines.append({"a":point(zone.walk_path[index]),"b":point(zone.walk_path[index+1])})
	var ring: Array = layout.get("navigation",{}).get("ring_points",[])
	check("Final layout supplies the open north ring",ring.size()>5 and not bool(layout.get("navigation",{}).get("ring_closed",true)))
	if ring.size()<2:
		quit(1)
		return
	for index: int in range(ring.size()-1):
		lines.append({"a":point(ring[index]),"b":point(ring[index+1])})
	var adjacent: Array[String] = ["university:major","major:university","major:campus","campus:major","campus:high_school","high_school:campus","high_school:career","career:high_school"]
	for source: String in zones:
		var start: Vector3 = point(zones[source].center)
		if source=="campus":
			start.z += 4.0 # The authored center is inside the fountain collider.
		start.y = .06
		check("%s already-inside navigation completes immediately" % source,Navigation.route(layout,start,source,source).is_empty())
		for target: String in zones:
			if target==source: continue
			var route: Array[Vector3] = Navigation.route(layout,start,source,target)
			var expected: Vector3 = point(zones[target].walk_path[-1])
			check("%s to %s ends at its authored entrance" % [source,target],not route.is_empty() and route[-1].distance_to(expected)<.02)
			var on_walkways: bool = true
			for index: int in range(route.size()-1):
				on_walkways = on_walkways and segment_matches(route[index],route[index+1],lines)
			check("%s to %s stays on built walkway segments" % [source,target],on_walkways)
			var legacy: Array = zones[source].walk_path.duplicate()
			legacy.reverse()
			legacy.append_array(zones[target].walk_path)
			var via_hub: float = distance(start,legacy)
			var routed: float = distance(start,route)
			var uses_hub: bool = route.any(func(value: Vector3) -> bool: return Vector2(value.x,value.z).length()<.02)
			check("%s to %s is no longer than the center route" % [source,target],routed<=via_hub+.03)
			if source+":"+target in adjacent:
				check("%s to %s takes the shorter adjacent ring" % [source,target],not uses_hub and routed<via_hub*.85)
			if source+":"+target in ["university:career","career:university"]:
				check("South-side %s to %s uses the open plaza" % [source,target],uses_hub and absf(routed-via_hub)<.03)
			routes.append({"source":source,"target":target,"distance_m":routed,"center_route_m":via_hub,"uses_hub":uses_hub,"points":route.size()})
	var ring_a: Vector3 = point(ring[4])
	var ring_b: Vector3 = point(ring[5])
	var midpoint: Vector3 = ring_a.lerp(ring_b,.5)
	var offset: Vector3 = (ring_b-ring_a).normalized().cross(Vector3.UP)*.8
	var ring_start: Vector3 = midpoint+offset
	var ring_route := Navigation.route(layout,ring_start,"career","high_school")
	check("An explorer already on the ring joins its nearest segment",not ring_route.is_empty() and ring_route[0].distance_to(midpoint)<.02)
	check("Ring navigation avoids returning to a district spoke first",not ring_route.is_empty() and ring_route[0].distance_to(ring_start)<.81 and not ring_route.any(func(value: Vector3) -> bool: return Vector2(value.x,value.z).length()<.02))
	var old_layout: Dictionary = layout.duplicate(true)
	old_layout.erase("navigation")
	var old_route := Navigation.route(old_layout,point(zones.university.center),"university","major")
	check("Older layouts retain a valid center route",not old_route.is_empty() and old_route.any(func(value: Vector3) -> bool: return Vector2(value.x,value.z).length()<.02))
	check("Unknown destinations produce no unsafe route",Navigation.route(layout,Vector3.ZERO,"university","missing").is_empty())
	check("Selecting the current nearest district from the hub still guides outward",not Navigation.route(layout,Vector3(0,.06,0),"university","university").is_empty())
	check("The hub is not already inside its nearest district",not Navigation.arrived(layout,Vector3(0,.06,0),"university","university"))
	check("A completed local route is distinguishable from failure",Navigation.arrived(layout,point(zones.high_school.center),"high_school","high_school"))
	var sealed: Dictionary = {"zones":[{"id":"inside","walk_path":[[3,.06,0],[5,.06,0]]},{"id":"outside","walk_path":[[3,.06,0],[10,.06,0]]}],"colliders":[]}
	for box: Dictionary in [{"center":[-1,.85,0],"size":[.2,1.7,2.2]},{"center":[1,.85,0],"size":[.2,1.7,2.2]},{"center":[0,.85,-1],"size":[2.2,1.7,.2]},{"center":[0,.85,1],"size":[2.2,1.7,.2]}]:
		sealed.colliders.append(box)
	check("An enclosed standing space never gets a route through a wall",Navigation.route(sealed,Vector3(0,.06,0),"inside","outside").is_empty())
	check("An unreachable area is never reported as arrival",not Navigation.arrived(sealed,Vector3(0,.06,0),"inside","outside"))
	var output := "res://../deliverables/discussion-revision/navigation-checks.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"routes":routes,"layout_sha256":FileAccess.get_sha256(LAYOUT)},"  "))
	file.close()
	print("NAVIGATION_RESULT checks=",checks.size()," failures=",failures)
	quit(0 if failures==0 else 1)
