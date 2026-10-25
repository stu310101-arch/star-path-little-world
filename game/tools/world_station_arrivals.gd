extends RefCounted

## A separate, level arrival bay joins each entrance from the side. The bay
## avoids spawning into the road directly in front of the public buildings.
## These positions are shared by the authored geometry and runtime teleport.
const Geo = preload("res://scripts/planet_geometry.gd")
const ARRIVAL_SIDES: Dictionary = {"admissions": -1.0, "life": -1.0}
const BAY_OFFSET: float = 3.05
const BAY_RADIUS: float = 1.02
const FLOOR_HEIGHT: float = .305

static func side_for(id: String) -> float:
	return float(ARRIVAL_SIDES.get(id, 1.0))

static func arrival_offset(id: String) -> Vector2:
	return Vector2(BAY_OFFSET * side_for(id), 0.0)

static func reserves_circulation(point: Vector2, clearance: float, centre: Vector2, id: String) -> bool:
	var arrival: Vector2 = centre + arrival_offset(id)
	# The clear corridor includes the full arrival disk, player capsule, and
	# approach to the entrance. Nearby rest seats remain in the pocket gardens.
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, centre, arrival)) < BAY_RADIUS + .65 + clearance

static func build(station: Node3D, up: Vector3, radius: float, info: Dictionary, row: Dictionary, number: int, font: Font) -> Dictionary:
	var centre: Vector2 = Vector2(float(info.civic[0]), float(info.civic[1]))
	var arrival: Vector2 = centre + arrival_offset(str(row.id))
	var local_from_world: Transform3D = station.transform.affine_inverse()
	var stone: StandardMaterial3D = Geo.material(Color("706f64"))
	stone.roughness = .92
	var edging: StandardMaterial3D = Geo.material(Color("a88b55"))
	edging.roughness = .57
	edging.metallic = .32
	var core: StandardMaterial3D = Geo.material(Color("333f42"))
	core.roughness = .88
	var approach_points: Array[Vector3] = [Geo.surface(up, centre, radius).normalized(), Geo.surface(up, arrival, radius).normalized()]
	var approach_mesh: ArrayMesh = Geo.path_ribbon(approach_points, radius + FLOOR_HEIGHT, 1.55)
	var approach: MeshInstance3D = Geo.mesh_node(station, "ArrivalWalkway", approach_mesh, stone, true)
	approach.transform = local_from_world
	var paving: MeshInstance3D = Geo.mesh_node(station, "ArrivalPaving", disk(up, radius, arrival, 0.0, BAY_RADIUS, FLOOR_HEIGHT), stone, true)
	paving.transform = local_from_world
	var border: MeshInstance3D = Geo.mesh_node(station, "ArrivalBrassBorder", disk(up, radius, arrival, BAY_RADIUS - .065, BAY_RADIUS, FLOOR_HEIGHT + .005), edging)
	border.transform = local_from_world
	var inset: MeshInstance3D = Geo.mesh_node(station, "ArrivalStoneInset", disk(up, radius, arrival, 0.0, .67, FLOOR_HEIGHT + .007), core)
	inset.transform = local_from_world
	var marker: Marker3D = Marker3D.new()
	marker.name = "Arrival"
	marker.position = local_from_world * Geo.surface(up, arrival, radius + FLOOR_HEIGHT + .18)
	station.add_child(marker)
	station.set_meta("arrival_local", arrival)
	station.set_meta("arrival_height", radius + FLOOR_HEIGHT + .18)
	station.set_meta("arrival_clear_radius", BAY_RADIUS)
	var floor_text: Label3D = Label3D.new()
	floor_text.name = "ArrivalInlay"
	floor_text.text = "%02d\n抵達區" % number
	floor_text.font = font
	floor_text.font_size = 42
	floor_text.pixel_size = .0045
	floor_text.modulate = Color("d5c49c")
	floor_text.outline_size = 0
	floor_text.shaded = true
	var n: Vector3 = Geo.surface(up, arrival, radius).normalized()
	var frame: Basis = Basis(Quaternion(up, n)) * Geo.frame(up)
	var lettering: Transform3D = Transform3D(frame, n * (radius + FLOOR_HEIGHT + .014))
	floor_text.transform = local_from_world * lettering * Transform3D(Basis(Vector3.RIGHT, -PI * .5), Vector3.ZERO)
	station.add_child(floor_text)
	# A slim marker at the rear of the entrance reads as a destination, without
	# columns, benches or planting inside the arrival corridor.
	var sign: Node3D = Node3D.new()
	sign.name = "EntranceWayfinding"
	sign.position = Vector3(-side_for(str(row.id)) * 1.28, .05, -.15)
	station.add_child(sign)
	var foot: BoxMesh = BoxMesh.new()
	foot.size = Vector3(.32, .10, .30)
	var marker_foot: MeshInstance3D = Geo.mesh_node(sign, "MarkerFoot", foot, core, true)
	marker_foot.position.y = .05
	(marker_foot.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
	var stem: BoxMesh = BoxMesh.new()
	stem.size = Vector3(.08, 1.13, .08)
	var marker_post: MeshInstance3D = Geo.mesh_node(sign, "MarkerPost", stem, edging, true)
	marker_post.position.y = .665
	(marker_post.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
	var panel: BoxMesh = BoxMesh.new()
	panel.size = Vector3(.63, .62, .085)
	var marker_panel: MeshInstance3D = Geo.mesh_node(sign, "EntranceMarker", panel, core, true)
	marker_panel.position.y = 1.54
	(marker_panel.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
	var number_label: Label3D = Label3D.new()
	number_label.text = "%02d\n入口" % number
	number_label.font = font
	number_label.font_size = 40
	number_label.pixel_size = .0038
	number_label.position = Vector3(0, 1.55, .047)
	number_label.modulate = Color("dfcda3")
	number_label.outline_size = 0
	number_label.shaded = true
	sign.add_child(number_label)
	return {"station": row.id, "portal_local": [centre.x, centre.y], "arrival_local": [arrival.x, arrival.y], "arrival_radius_m": BAY_RADIUS, "walkway_width_m": 1.55}

static func disk(up: Vector3, radius: float, centre: Vector2, inner: float, outer: float, height: float) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index: int in range(64):
		var angle_a: float = TAU * float(index) / 64.0
		var angle_b: float = TAU * float(index + 1) / 64.0
		var a: Vector2 = Vector2(cos(angle_a), sin(angle_a))
		var b: Vector2 = Vector2(cos(angle_b), sin(angle_b))
		var p0: Vector3 = Geo.surface(up, centre + a * inner, radius).normalized() * (radius + height)
		var p1: Vector3 = Geo.surface(up, centre + a * outer, radius).normalized() * (radius + height)
		var p2: Vector3 = Geo.surface(up, centre + b * outer, radius).normalized() * (radius + height)
		var p3: Vector3 = Geo.surface(up, centre + b * inner, radius).normalized() * (radius + height)
		Geo.triangle(st, p0, p1, p2, Color.WHITE)
		if inner > 0.0:
			Geo.triangle(st, p0, p2, p3, Color.WHITE)
	return st.commit()
