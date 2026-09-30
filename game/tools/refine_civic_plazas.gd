extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")

# A small entrance court, kept inside the existing civic paving footprint.
# Furniture is placed only where road, path, portal and building clearances hold.
static func build(builder: SceneTree,parent: Node3D,up: Vector3,radius: float,info: Dictionary) -> void:
	var centre: Vector2 = v2(info.civic)
	var accent: Color = Color(str(info.accent))
	var paving: SurfaceTool = SurfaceTool.new()
	paving.begin(Mesh.PRIMITIVE_TRIANGLES)
	var furniture: SurfaceTool = SurfaceTool.new()
	furniture.begin(Mesh.PRIMITIVE_TRIANGLES)
	var stone: Color = Color("a8ab9c").lerp(accent,.10)
	for column: int in range(5):
		for row: int in range(6):
			var a: Vector2 = centre+Vector2(-1.70+float(column)*.68,-2.44+float(row)*.67)
			var b: Vector2 = a+Vector2(.654,.644)
			var tint: Color = stone.lightened(float((column+row*3)%4)*.012)
			paver(paving,up,radius,a,b,.278,tint)
	# Narrow contrasting inlays make the entrance legible without creating
	# a giant new platform or consuming the existing central access strip.
	for sign_value: float in [-1.0,1.0]:
		var x: float = centre.x+sign_value*1.68
		paver(paving,up,radius,Vector2(x-.022,centre.y-2.44),Vector2(x+.022,centre.y+1.55),.281,accent.darkened(.24))
	var vertex_material: StandardMaterial3D = Geo.material(Color.WHITE)
	vertex_material.vertex_color_use_as_albedo=true
	Geo.mesh_node(parent,"CivicStonePaving",paving.commit(),vertex_material)
	var occupied: Array[Vector2] = []
	var seats: int = 0
	var planters: int = 0
	for side_sign: float in [-1.0,1.0]:
		var candidates: Array[Vector2] = [centre+Vector2(side_sign*2.55,.1),centre+Vector2(side_sign*3.15,.6),centre+Vector2(side_sign*2.55,1.5),centre+Vector2(side_sign*4.1,-.65)]
		for location: Vector2 in candidates:
			if not clear_for_prop(location,.78,centre,info,radius,occupied):
				continue
			var transform: Transform3D = anchor_transform(up,radius,location)
			# Local +Z is the backrest; the seat faces toward the entrance.
			transform.basis=transform.basis*Basis(Vector3.UP,side_sign*PI*.5)
			bench(furniture,transform,accent)
			collision(parent,"CivicSeatCollision",transform,Vector3(0,.48,.04),Vector3(1.58,.85,.53))
			occupied.append(location)
			seats+=1
			for end_sign: float in [-1.0,1.0]:
				var planter_position: Vector2 = location+Vector2(0,end_sign*1.32)
				if not clear_for_prop(planter_position,.42,centre,info,radius,[]):
					continue
				var planter_transform: Transform3D = anchor_transform(up,radius,planter_position)
				planter(furniture,planter_transform,accent)
				collision(parent,"CivicPlanterCollision",planter_transform,Vector3(0,.24,0),Vector3(.58,.48,.58))
				occupied.append(planter_position)
				planters+=1
			break
	if seats+planters>0:
		Geo.mesh_node(parent,"CivicFurniture",furniture.commit(),vertex_material)
	var report: Dictionary = builder.get("report")
	if not report.has("civic_refinements"):
		report["civic_refinements"] = []
	report.civic_refinements.append({"station":info.station,"seats":seats,"planters":planters,"paving_size":[3.4,4.02],"clear_centre":true})

static func v2(row: Array) -> Vector2:
	return Vector2(float(row[0]),float(row[1]))

static func anchor_transform(up: Vector3,radius: float,point: Vector2) -> Transform3D:
	var n: Vector3 = Geo.surface(up,point,radius).normalized()
	return Transform3D(Basis(Quaternion(up,n))*Geo.frame(up),n*(radius+.20))

static func clear_for_prop(point: Vector2,clearance: float,centre: Vector2,info: Dictionary,radius: float,occupied: Array[Vector2]) -> bool:
	if point.distance_to(centre)<1.5+clearance:
		return false
	for existing: Vector2 in occupied:
		if point.distance_to(existing)<1.2+clearance:
			return false
	var roads: Array = (info.roads as Array).duplicate()
	for index: int in range(info.loop.size()):
		roads.append([info.loop[index],info.loop[(index+1)%info.loop.size()]])
	for road: Array in roads:
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,v2(road[0]),v2(road[1])))<3.15+clearance:
			return false
	for path: Array in Routes.district_paths(info,radius):
		for index: int in range(path.size()-1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point,v2(path[index]),v2(path[index+1])))<1.05+clearance:
				return false
	for building: Dictionary in info.urban_buildings:
		var delta: Vector2 = (point-v2(building.offset)).rotated(deg_to_rad(float(building.yaw)))
		if absf(delta.x)<float(building.get("max_width",5.4))*.5+clearance and absf(delta.y)<float(building.get("max_depth",5.5))*.5+clearance:
			return false
		# Keep the building's actual front-door connector unobstructed.
		var forward: Vector2 = Vector2(sin(deg_to_rad(float(building.yaw))),cos(deg_to_rad(float(building.yaw))))
		var doorway: Vector2 = v2(building.offset)+forward*float(building.get("front",2.8))
		if point.distance_to(doorway)<.75+clearance:
			return false
		var connectors: Array = roads.duplicate()
		for path: Array in info.paths:
			for index: int in range(path.size()-1):
				connectors.append([path[index],path[index+1]])
		var landing: Vector2 = doorway
		var nearest_distance: float = INF
		for edge: Array in connectors:
			var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(doorway,v2(edge[0]),v2(edge[1]))
			if candidate.distance_to(doorway)<nearest_distance:
				nearest_distance=candidate.distance_to(doorway)
				landing=candidate
		# A front door's whole approach is circulation, including the section
		# beyond the door itself that can cross this civic court.
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point,doorway,landing))<.82+clearance:
			return false
	return true

static func paver(st: SurfaceTool,up: Vector3,radius: float,a: Vector2,b: Vector2,height: float,color: Color) -> void:
	var nx: int = maxi(1,ceili((b.x-a.x)/.28))
	var nz: int = maxi(1,ceili((b.y-a.y)/.28))
	for x: int in range(nx):
		for z: int in range(nz):
			var x0: float = lerpf(a.x,b.x,float(x)/nx)
			var x1: float = lerpf(a.x,b.x,float(x+1)/nx)
			var z0: float = lerpf(a.y,b.y,float(z)/nz)
			var z1: float = lerpf(a.y,b.y,float(z+1)/nz)
			var p0: Vector3 = Geo.surface(up,Vector2(x0,z0),radius).normalized()*(radius+height)
			var p1: Vector3 = Geo.surface(up,Vector2(x1,z0),radius).normalized()*(radius+height)
			var p2: Vector3 = Geo.surface(up,Vector2(x1,z1),radius).normalized()*(radius+height)
			var p3: Vector3 = Geo.surface(up,Vector2(x0,z1),radius).normalized()*(radius+height)
			Geo.triangle(st,p0,p1,p2,color)
			Geo.triangle(st,p0,p2,p3,color)

static func bench(st: SurfaceTool,transform: Transform3D,accent: Color) -> void:
	var metal: Color = Color("40565a")
	for x: float in [-.56,.56]:
		box(st,transform,Vector3(x,.225,0),Vector3(.075,.45,.45),metal)
		box(st,transform,Vector3(x,.65,.24),Vector3(.065,.62,.065),metal)
	for z: float in [-.16,0,.16]:
		box(st,transform,Vector3(0,.47,z),Vector3(1.55,.10,.135),Color("b39673"))
	for y: float in [.68,.84]:
		box(st,transform,Vector3(0,y,.245),Vector3(1.55,.12,.065),Color("c2a787"))
	for x: float in [-.72,.72]:
		box(st,transform,Vector3(x,.66,.025),Vector3(.055,.055,.47),metal.lerp(accent,.2))

static func planter(st: SurfaceTool,transform: Transform3D,accent: Color) -> void:
	box(st,transform,Vector3(0,.22,0),Vector3(.59,.44,.59),Color("8c968c").lerp(accent,.16))
	box(st,transform,Vector3(0,.405,0),Vector3(.62,.065,.62),accent.darkened(.16))
	box(st,transform,Vector3(0,.447,0),Vector3(.48,.025,.48),Color("594f3e"))
	var foliage: SphereMesh = SphereMesh.new()
	foliage.radius=.22
	foliage.height=.35
	foliage.radial_segments=8
	foliage.rings=4
	var crown: Transform3D = transform
	crown.origin=transform*Vector3(0,.58,0)
	append_mesh(st,foliage,crown,Color("526e42"))
	var bloom: SphereMesh = SphereMesh.new()
	bloom.radius=.055
	bloom.height=.075
	bloom.radial_segments=6
	bloom.rings=3
	for offset: Vector3 in [Vector3(-.12,.70,.03),Vector3(.08,.73,-.09),Vector3(.11,.68,.12)]:
		var petal: Transform3D = transform
		petal.origin=transform*offset
		append_mesh(st,bloom,petal,accent.lightened(.15))

static func box(st: SurfaceTool,transform: Transform3D,centre: Vector3,size: Vector3,color: Color) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size=size
	var shifted: Transform3D = transform
	shifted.origin=transform*centre
	append_mesh(st,mesh,shifted,color)

static func append_mesh(st: SurfaceTool,mesh: Mesh,transform: Transform3D,color: Color) -> void:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for index: int in indices:
		st.set_color(color)
		st.set_normal((transform.basis*normals[index]).normalized())
		st.add_vertex(transform*vertices[index])

static func collision(parent: Node3D,label: String,transform: Transform3D,centre: Vector3,size: Vector3) -> void:
	var body: StaticBody3D = StaticBody3D.new()
	body.name=label
	body.collision_layer=8
	if label in ["SeatCollision", "CivicSeatCollision"]:
		body.set_meta("rest_seat", true)
	parent.add_child(body)
	body.transform=transform
	var shape: BoxShape3D = BoxShape3D.new()
	shape.size=size
	var node: CollisionShape3D = CollisionShape3D.new()
	node.shape=shape
	node.position=centre
	body.add_child(node)
