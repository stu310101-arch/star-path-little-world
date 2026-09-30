extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")

var checks: Array[Dictionary] = []
var failures: int = 0
var ray_count: int = 0
var world: Node3D
var radius: float = 48.0
var districts: Array = []
var layout: Dictionary = {}

func _initialize() -> void:
	call_deferred("run_checks")

func check(label: String,passed: bool,detail: String = "") -> void:
	checks.append({"test":label,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error(label+": "+detail)

func run_checks() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	districts = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	radius = float(layout.radius)
	check_route_meshes()
	if OS.get_cmdline_user_args().has("--geometry-only"):
		finish()
		return
	Engine.time_scale = 4.0
	Engine.physics_ticks_per_second = 120
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	await physics_frame
	await physics_frame
	(world.get("player") as Node3D).set_physics_process(false)
	check_bridges()
	await check_bridge_walks()
	check_marina()
	check_built_route_transitions()
	finish()

func finish() -> void:
	var output: Dictionary = {"passed":failures == 0,"failed":failures,"ray_probes":ray_count,"checks":checks}
	var file: FileAccess = FileAccess.open("res://tests/infrastructure_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"))
	print(JSON.stringify(output))
	quit(0 if failures == 0 else 1)

func key(point: Vector3) -> Vector3i:
	return Vector3i(roundi(point.x*100000.0),roundi(point.y*100000.0),roundi(point.z*100000.0))

func vertex_set(mesh: ArrayMesh) -> Dictionary:
	var result: Dictionary = {}
	if mesh == null:
		return result
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for vertex: Vector3 in vertices:
		result[key(vertex)] = true
	return result

func district_up(index: int) -> Vector3:
	var values: Array = layout.stations[index].normal
	return Vector3(values[0],values[1],values[2])

func path_has_point(path: Array,point: Vector2) -> bool:
	# JSON numbers are floats; Array.has([20,25]) compares Variant element types.
	# Geometry compares numeric coordinates, not their serialization type.
	for value: Array in path:
		if Vector2(float(value[0]),float(value[1])).is_equal_approx(point):
			return true
	return false

func tangent_offset(normal: Vector3,up: Vector3) -> Vector2:
	var axes: Basis = Geo.frame(up)
	return Vector2(normal.dot(axes.x),normal.dot(axes.z))*radius/normal.dot(up)

func check_route_meshes() -> void:
	var all_transitions: int = 0
	for index: int in range(districts.size()):
		var info: Dictionary = districts[index]
		var transitions: int = 0
		var missing: Array[String] = []
		for path: Array in Routes.district_paths(info,radius):
			var route: Array[Dictionary] = Waterfront.samples(district_up(index),path,info,radius)
			var dry_vertices: Dictionary = vertex_set(Waterfront.deck_mesh(route,radius,Waterfront.HEIGHT,Waterfront.WIDTH,false))
			var wet_vertices: Dictionary = vertex_set(Waterfront.deck_mesh(route,radius,Waterfront.HEIGHT,Waterfront.WIDTH,true))
			for i: int in range(1,route.size()-1):
				if bool(route[i-1].wet) == bool(route[i].wet):
					continue
				transitions += 1
				var count: int = int(route[i].cross_steps)
				for cross: int in range(count+1):
					var lateral: float = Waterfront.WIDTH*(float(cross)/count-.5)
					var point: Vector3 = Waterfront.at(route[i],radius,Waterfront.HEIGHT,lateral)
					if not dry_vertices.has(key(point)) or not wet_vertices.has(key(point)):
						missing.append(str(route[i].p)+" / "+str(lateral))
		all_transitions += transitions
		check("Dry and timber meshes share every threshold vertex: "+str(info.station),missing.is_empty(),"thresholds="+str(transitions)+" mismatches="+str(missing.slice(0,5)))
	check("Geometry probe includes actual wet/dry transitions",all_transitions >= 12,str(all_transitions))
	var wordking: Array = Routes.district_paths(districts[5],radius)
	var life: Array = Routes.district_paths(districts[4],radius)
	check("WordKing wetland paths share a joined corner",path_has_point(wordking[0],Vector2(20,25)) and path_has_point(wordking[0],Vector2(10,27)) and wordking.size() == 5)
	check("Lake path return shares a joined corner",path_has_point(life[1],Vector2(-29,18)) and path_has_point(life[1],Vector2(-23,11)) and life.size() == 6)

func ray(from: Vector3,to: Vector3,mask: int) -> Dictionary:
	ray_count += 1
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from,to,mask)
	return world.get_world_3d().direct_space_state.intersect_ray(query)

func ground(normal: Vector3) -> Dictionary:
	return ray(normal*(radius+1.5),normal*(radius-.1),1)

func is_from(hit: Dictionary,ancestor: Node) -> bool:
	if hit.is_empty() or ancestor == null:
		return false
	var collider: Node = hit.get("collider") as Node
	return collider != null and (collider == ancestor or ancestor.is_ancestor_of(collider))

func height_is_walkable(hit: Dictionary) -> bool:
	return not hit.is_empty() and (hit.position as Vector3).length() >= radius+.245

func capsule_guard_probe(from_feet: Vector3,to_feet: Vector3,rails: Node) -> Dictionary:
	# The player is a 0.27 m radius / 1.6 m capsule. A point ray placed exactly
	# on two rail end caps can miss their shared numerical edge; sweeping the
	# real walking volume checks that the joint still blocks the character.
	var capsule: CapsuleShape3D = CapsuleShape3D.new()
	capsule.radius = .27
	capsule.height = 1.6
	var up: Vector3 = from_feet.normalized()
	var origin: Vector3 = from_feet+up*.82
	var destination: Vector3 = to_feet+to_feet.normalized()*.82
	var query: PhysicsShapeQueryParameters3D = PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 8
	query.margin = .015
	query.transform = Transform3D(Geo.frame(up),origin)
	# cast_motion deliberately ignores shapes already touching the initial
	# capsule. At the final joint the capsule can already meet the end rail;
	# that is a blocked start, not permission to pass through the guardrail.
	var initial_hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query,12)
	var initial_paths: Array[String] = []
	var initially_blocked: bool = false
	for hit: Dictionary in initial_hits:
		initial_paths.append(str((hit.collider as Node).get_path()))
		initially_blocked = is_from(hit,rails) or initially_blocked
	if initially_blocked:
		return {"blocked":true,"safe_fraction":0.0,"initial_overlap":true,"colliders":initial_paths}
	query.motion = destination-origin
	var fractions: PackedFloat32Array = world.get_world_3d().direct_space_state.cast_motion(query)
	if fractions.size() < 2 or fractions[0] >= .999:
		return {"blocked":false,"safe_fraction":1.0,"colliders":[]}
	# Confirm the blocking shape is the guardrail, rather than nearby furniture.
	var contact: Transform3D = query.transform
	contact.origin += query.motion*minf(fractions[1]+.02,1.0)
	query.transform = contact
	query.motion = Vector3.ZERO
	var hits: Array[Dictionary] = world.get_world_3d().direct_space_state.intersect_shape(query,12)
	var collider_paths: Array[String] = []
	var blocked_by_rail: bool = false
	for hit: Dictionary in hits:
		blocked_by_rail = is_from(hit,rails) or blocked_by_rail
		collider_paths.append(str((hit.collider as Node).get_path()))
	return {"blocked":blocked_by_rail,"safe_fraction":float(fractions[0]),"colliders":collider_paths}

func bridge_point(a: Vector3,b: Vector3,t: float,lateral: float,height: float) -> Vector3:
	return (a.slerp(b,t)*radius+a.cross(b).normalized()*lateral).normalized()*(radius+height)

func check_bridges() -> void:
	var globe: Node3D = world.get_node("Globe") as Node3D
	var directions: Array[Vector3] = Routes.directions()
	var limits: Vector2 = Routes.bridge_limits()
	var bridge_count: int = 0
	for child: Node in globe.get_children():
		if String(child.name).begins_with("Bridge_"):
			bridge_count += 1
	check("All twelve island connections exist",bridge_count == 12,str(bridge_count))
	for edge: Vector2i in Routes.bridge_edges():
		var label: String = "Bridge_%d_%d" % [edge.x,edge.y]
		var bridge: Node3D = globe.get_node_or_null(label) as Node3D
		check(label+" has a deck and guardrails",bridge != null)
		if bridge == null:
			continue
		var a: Vector3 = directions[edge.x]
		var b: Vector3 = directions[edge.y]
		var missing: Array[String] = []
		# Continue beyond both bridge ends onto the adjoining district paths.
		# Five probes across the width catch gaps hidden by centreline-only tests.
		for along: int in range(101):
			var t: float = lerpf(limits.x-.018,limits.y+.018,float(along)/100.0)
			for cross: float in [-.96,-.5,0.0,.5,.96]:
				var point: Vector3 = bridge_point(a,b,t,cross,0.0)
				if not height_is_walkable(ground(point.normalized())) and missing.size() < 8:
					missing.append("t=%.5f lateral=%.2f" % [t,cross])
		check(label+" is grounded across width and both bank joins",missing.is_empty(),str(missing))
		var rails: Node3D = bridge.get_node_or_null("ContinuousGuardrails") as Node3D
		var body: StaticBody3D = rails.get_node_or_null("SurfaceCollision") as StaticBody3D if rails != null else null
		check(label+" rails collide on layer 8",body != null and body.collision_layer == 8)
		var rail_misses: Array[String] = []
		for i: int in range(1,20):
			var t: float = lerpf(limits.x,limits.y,float(i)/20.0)
			for side: float in [-1.0,1.0]:
				var hit: Dictionary = ray(bridge_point(a,b,t,side*.8,1.30),bridge_point(a,b,t,side*1.6,1.30),8)
				if not is_from(hit,rails) and rail_misses.size() < 8:
					rail_misses.append("t=%.5f side=%.0f" % [t,side])
		check(label+" protects both exposed sides continuously",rail_misses.is_empty(),str(rail_misses))

func check_marina() -> void:
	var marina: Node3D = world.get_node_or_null("Neighborhood/admissions/Marina") as Node3D
	check("Admissions has a furnished marina",marina != null)
	if marina == null:
		return
	var info: Dictionary = districts[1]
	var up: Vector3 = district_up(1)
	var entry_offset: Vector2 = tangent_offset(marina.get_meta("entry") as Vector3,up)
	var end_offset: Vector2 = tangent_offset(marina.get_meta("end") as Vector3,up)
	var route: Array[Dictionary] = Waterfront.samples(up,[[entry_offset.x,entry_offset.y],[end_offset.x,end_offset.y]],info,radius,5.4)
	var misses: Array[String] = []
	for i: int in range(route.size()-1):
		var sample: Dictionary = Waterfront.between(route[i],route[i+1],.5)
		for cross: float in [-2.3,-1.0,0.0,1.0,2.3]:
			var hit: Dictionary = ground(Waterfront.at(sample,radius,.26,cross).normalized())
			if not height_is_walkable(hit) and misses.size() < 8:
				misses.append(str(i)+" / "+str(cross))
	check("Marina deck has collision across its full usable width",misses.is_empty(),str(misses))
	var entry_clear: bool = true
	var entry: Dictionary = route[0]
	var entry_normal: Vector3 = entry.normal
	var entry_side: Vector3 = entry.side
	var forward: Vector3 = ((route[1].normal as Vector3)-entry_normal).slide(entry_normal).normalized()
	for height: float in [.68,1.22]:
		for cross: float in [-.80,0.0,.80]:
			var from: Vector3 = (entry_normal*radius-forward*.7+entry_side*cross).normalized()*(radius+height)
			var to: Vector3 = (entry_normal*radius+forward*.7+entry_side*cross).normalized()*(radius+height)
			entry_clear = ray(from,to,8).is_empty() and entry_clear
	check("Marina entrance stays open across a usable walking corridor",entry_clear)
	var rails: Node3D = marina.get_node_or_null("HarborGuardrails") as Node3D
	var body: StaticBody3D = rails.get_node_or_null("SurfaceCollision") as StaticBody3D if rails != null else null
	check("Marina guardrail has layer 8 collision",body != null and body.collision_layer == 8)
	var side_safe: bool = true
	var side_misses: Array[String] = []
	# Ray-probe every solid rail segment, then capsule-sweep every shared joint.
	# Neither changing the rail's expected height nor skipping joins is needed.
	for i: int in range(route.size()-1):
		var middle: Dictionary = Waterfront.between(route[i],route[i+1],.5)
		for side: float in [-1.0,1.0]:
			var hit: Dictionary = ray(Waterfront.at(middle,radius,1.28,side*2.3),Waterfront.at(middle,radius,1.28,side*3.0),8)
			if not is_from(hit,rails):
				side_safe = false
				if side_misses.size() < 8:
					side_misses.append("segment="+str(i)+" side="+str(side))
	for i: int in range(1,route.size()-1):
		for side: float in [-1.0,1.0]:
			var probe: Dictionary = capsule_guard_probe(Waterfront.at(route[i],radius,.26,side*2.05),Waterfront.at(route[i],radius,.26,side*3.2),rails)
			if not bool(probe.blocked):
				side_safe = false
				if side_misses.size() < 8:
					side_misses.append("joint="+str(i)+" side="+str(side)+" "+JSON.stringify(probe))
	check("Marina has continuous collision on both long sides",side_safe,"segment rays="+str((route.size()-1)*2)+" player capsule sweeps="+str((route.size()-2)*2)+" misses="+str(side_misses))
	var end: Dictionary = route[-1]
	var end_normal: Vector3 = end.normal
	var end_side: Vector3 = end.side
	var end_forward: Vector3 = (end_normal-(route[-2].normal as Vector3)).slide(end_normal).normalized()
	var end_safe: bool = true
	for cross: float in [-2.2,-1.2,0.0,1.2,2.2]:
		var from: Vector3 = (end_normal*radius-end_forward*.65+end_side*cross).normalized()*(radius+1.23)
		var to: Vector3 = (end_normal*radius+end_forward*.65+end_side*cross).normalized()*(radius+1.23)
		end_safe = is_from(ray(from,to,8),rails) and end_safe
	check("Marina closes the exposed seaward end",end_safe)
	check("Marina includes a moored boat and lifesaving equipment",marina.find_child("MooredFishingBoat",true,false) != null and marina.find_child("LifeRing",true,false) != null)

func check_bridge_walks() -> void:
	var player: PlanetPlayer = world.get("player") as PlanetPlayer
	var directions: Array[Vector3] = Routes.directions()
	player.set_physics_process(true)
	player.allow_test_input = true
	player.test_running = true
	player.land_only = true
	player.collision_mask = 9
	# Start roughly twelve metres back from each bridge, so these walks include
	# the district approaches, waterfront crossings, and both guardrail mouths.
	for edge: Vector2i in Routes.bridge_edges():
		var a: Vector3 = directions[edge.x]
		var b: Vector3 = directions[edge.y]
		for reverse: bool in [false,true]:
			var from: Vector3 = a.slerp(b,.75 if reverse else .25)
			var target: Vector3 = a.slerp(b,.25 if reverse else .75)
			player.test_direction = Vector2.ZERO
			player.teleport(from,radius+.65)
			for i: int in range(20):
				await physics_frame
			var reached: bool = false
			var grounded: bool = true
			var previous: Vector3 = player.position
			var stalled_frames: int = 0
			var distance: float = from.angle_to(target)*radius
			var budget: int = ceili(distance/player.run_speed*30.0)+100
			var frames: int = 0
			player.test_direction = Vector2(0,-1)
			for i: int in range(budget):
				player.heading = (target*radius-player.position).slide(player.position.normalized()).normalized()
				await physics_frame
				frames = i+1
				grounded = not player.ground_at(player.position.normalized()).is_empty() and grounded
				if player.position.normalized().angle_to(target)*radius < .32:
					reached = true
					break
				stalled_frames = stalled_frames+1 if player.position.distance_to(previous) < .004 else 0
				previous = player.position
				if stalled_frames >= 45:
					break
			player.test_direction = Vector2.ZERO
			var label: String = "Actual bridge and approaches walk %d to %d" % [edge.y if reverse else edge.x,edge.x if reverse else edge.y]
			check(label,reached and grounded,"remaining=%.3fm frames=%d stalled=%d position=%s" % [player.position.normalized().angle_to(target)*radius,frames,stalled_frames,str(player.position)])
	player.allow_test_input = false
	player.set_physics_process(false)

func check_built_route_transitions() -> void:
	for index: int in range(districts.size()):
		var info: Dictionary = districts[index]
		var missing: Array[String] = []
		var ownership_errors: Array[String] = []
		var wet_probes: int = 0
		for path: Array in Routes.district_paths(info,radius):
			var route: Array[Dictionary] = Waterfront.samples(district_up(index),path,info,radius)
			for i: int in range(route.size()-1):
				if not bool(route[i].wet) and (i == 0 or not bool(route[i-1].wet)):
					continue
				var sample: Dictionary = Waterfront.between(route[i],route[i+1],.5)
				for cross: float in [-.93,0.0,.93]:
					var hit: Dictionary = ground(Waterfront.at(sample,radius,.26,cross).normalized())
					if not height_is_walkable(hit):
						if missing.size() < 8:
							missing.append(str(route[i].p)+" / "+str(cross))
						continue
					var collider: Node = hit.collider as Node
					var is_timber: bool = collider.get_parent().get_meta("surface_owner","") == "wet_route_only"
					if bool(route[i].wet):
						wet_probes += 1
					if bool(route[i].wet) != is_timber and ownership_errors.size() < 8:
						ownership_errors.append(str(route[i].p)+" hit "+str(collider.get_parent().name))
		check("Built boardwalks and thresholds carry collision: "+str(info.station),missing.is_empty(),str(missing))
		check("Actual wet route tops belong to timber only: "+str(info.station),ownership_errors.is_empty(),"wet probes="+str(wet_probes)+" errors="+str(ownership_errors))
