extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Arrivals = preload("res://tools/world_station_arrivals.gd")

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
		var candidates: Array[Vector2] = [centre+Vector2(side_sign*4.9,-1.0),centre+Vector2(side_sign*5.8,-.8),centre+Vector2(side_sign*4.9,2.2)]
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
	if Arrivals.reserves_circulation(point, clearance, centre, str(info.station)):
		return false
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

static func planter(st: SurfaceTool,transform: Transform3D,_accent: Color) -> void:
	# Retain the existing pedestal and collider envelope. Fine evergreen blades
	# replace the solid spherical crown and floating coloured flower balls.
	box(st,transform,Vector3(0,.22,0),Vector3(.59,.44,.59),Color("353f3b"))
	box(st,transform,Vector3(0,.421,0),Vector3(.62,.033,.62),Color("5a6358"))
	box(st,transform,Vector3(0,.447,0),Vector3(.48,.025,.48),Color("302c23"))
	for clump: int in range(5):
		var phase: float = TAU*float(clump)/5.0
		var origin: Vector3 = Vector3(cos(phase)*.105,.464,sin(phase)*.105)
		for leaf: int in range(9):
			var angle: float = float(leaf)*2.399+phase
			var outward: Vector3 = Vector3(cos(angle),0,sin(angle))
			var side: Vector3 = Vector3(-sin(angle),0,cos(angle))
			var height: float = .28+.13*(.5+.5*sin(leaf*1.7+clump))
			var reach: float = .08+.035*sin(leaf*2.1+clump)
			var color: Color = Color("506344").lightened(.08*sin(leaf*1.9+clump))
			for segment: int in range(3):
				var t0: float = float(segment)/3.0
				var t1: float = float(segment+1)/3.0
				var a: Vector3 = origin+Vector3.UP*height*t0+outward*reach*t0*t0
				var b: Vector3 = origin+Vector3.UP*height*t1+outward*reach*t1*t1
				var w0: float = .017*(1.0-t0)
				var w1: float = .017*(1.0-t1)
				leaf_blade(st,transform,a-side*w0,a+side*w0,b+side*w1,b-side*w1,color)

static func leaf_blade(st: SurfaceTool,transform: Transform3D,a: Vector3,b: Vector3,c: Vector3,d: Vector3,color: Color) -> void:
	var normal: Vector3 = (b-a).cross(c-a).normalized()
	# Both sides share the existing civic material and mesh batch; no alpha
	# textures, added per-leaf nodes or extra draw surfaces are introduced.
	for side: float in [1.0,-1.0]:
		var points: Array[Vector3] = [a,c,b,a,d,c]
		if side<0.0: points = [a,b,c,a,c,d]
		for point: Vector3 in points:
			st.set_normal((transform.basis*normal*side).normalized())
			st.set_color(color)
			st.add_vertex(transform*point)

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
