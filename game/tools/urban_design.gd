extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const Markings = preload("res://tools/road_markings.gd")
const Infrastructure = preload("res://tools/world_infrastructure.gd")
const Civic = preload("res://tools/refine_civic_plazas.gd")
var builder: SceneTree
var district: Node3D
var up: Vector3
var radius: float
var index: int
var info: Dictionary

func build(owner_builder: SceneTree, parent: Node3D, district_index: int) -> void:
	builder = owner_builder
	district = parent
	index = district_index
	up = builder.get("road_up") as Vector3
	radius = float(builder.get("radius"))
	info = (builder.get("districts") as Array)[index]
	# Each district owns an authored street graph and independent parcel plan.
	var loop: Array = info.loop
	joined_path(loop,.27,6.3,Color("8e9893"),"Sidewalk",true)
	joined_path(loop,.285,4.2,Color("34434b"),"Asphalt",true)
	for i: int in range(loop.size()):
		street(v2(loop[i]),v2(loop[(i+1)%loop.size()]),false)
	for road: Array in info.roads:
		street(v2(road[0]),v2(road[1]))
	for path: Array in Routes.district_paths(info,radius):
		var samples: Array[Dictionary] = Waterfront.samples(up,path,info,radius)
		var mesh: ArrayMesh = Waterfront.deck_mesh(samples,radius,.26,2.2,false)
		if mesh != null:
			Geo.mesh_node(district,"DistrictPromenade",mesh,Geo.material(Color("a1aba0")),true)
	Markings.build(builder,district,up,radius,info)
	if index == 1:
		Infrastructure.marina(builder,district,up,radius,info)
	for row: Dictionary in info.urban_buildings:
		builder.call("place_asset",district,row,up)
		var p: Vector2 = Vector2(row.offset[0],row.offset[1])
		var forward: Vector2 = Vector2(sin(deg_to_rad(float(row.yaw))),cos(deg_to_rad(float(row.yaw))))
		var front: Vector2 = p+forward*float(row.get("front",2.8))
		var lane: Vector2 = nearest_walk(front)
		walk(front,lane,1.4,"BuildingForecourt")
		# Every building has an address, a front path and a street-facing entrance.
		var address: Node3D = anchor(front+Vector2(-forward.y,forward.x)*1.25)
		builder.call("prefab_asset",address,"planter",Vector3.ZERO,.48)
		if p.y<0 and absf(p.x)<10:
			builder.call("flowers",address,Vector3(0,.48,0),Color(str(info.accent)))
	var civic: Vector2 = v2(info.civic)
	walk(civic-Vector2(0,2.5),civic+Vector2(0,1.6),3.5,"CivicPlaza")
	Civic.build(builder,district,up,radius,info)
	for p_data: Array in info.gardens:
		var p: Vector2 = v2(p_data)
		var rest: Node3D = anchor(p)
		builder.call("bench",rest,Vector3.ZERO,0.0)
		builder.call("lamp",rest,Vector3(1.2,0,1.2))
		var garden_report: Dictionary = builder.get("report")
		garden_report.landscapes.append({"station":info.station,"preset":"planned pocket garden","offset":p_data})
	# Fixed street-light positions are reviewed against the complete road width,
	# public promenades and actual house forecourts. Short concave road edges do
	# not receive an extra pair of lamps inside the adjoining street.
	var lighting: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/street_lighting.json")) as Dictionary
	var lamp_positions: Array = lighting[str(info.station)]
	for lamp_index: int in range(lamp_positions.size()):
		var p: Vector2 = v2(lamp_positions[lamp_index])
		var lamp_node: Node3D = anchor(p)
		lamp_node.name="StreetLight_%02d" % (lamp_index+1)
		lamp_node.set_meta("authored_offset",p)
		builder.call("lamp",lamp_node,Vector3.ZERO)
	traffic()
	var report: Dictionary = builder.get("report")
	report.districts.append({"id":info.station,"theme":info.theme,"buildings":info.urban_buildings.size(),"plan":info.theme,"loop":info.loop,"civic":info.civic})

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]),float(value[1]))

func anchor(p: Vector2) -> Node3D:
	var n: Vector3 = Geo.surface(up,p,radius).normalized()
	var node: Node3D = Node3D.new()
	district.add_child(node)
	node.transform=Transform3D(Basis(Quaternion(up,n))*Geo.frame(up),n*(radius+.22))
	return node

func path_mesh(a: Vector2,b: Vector2,height: float,width: float,color: Color,label: String,solid: bool=false) -> void:
	Geo.mesh_node(district,label,Geo.ribbon(Geo.surface(up,a,radius).normalized(),Geo.surface(up,b,radius).normalized(),radius+height,width),Geo.material(color),solid)

func walk(a: Vector2,b: Vector2,width: float,label: String) -> void:
	path_mesh(a,b,.24,width,Color("929a94"),label,true)

func joined_path(path: Array,height: float,width: float,color: Color,label: String,closed: bool=false) -> void:
	var points: Array[Vector3] = []
	for point: Array in path:
		points.append(Geo.surface(up,v2(point),radius).normalized())
	Geo.mesh_node(district,label,Geo.path_ribbon(points,radius+height,width,closed),Geo.material(color),true)

func street(a: Vector2,b: Vector2,surfaces: bool=true) -> void:
	if surfaces:
		path_mesh(a,b,.27,6.3,Color("8e9893"),"Sidewalk",true)
		path_mesh(a,b,.285,4.2,Color("34434b"),"Asphalt",true)
	var count: int = ceili(a.distance_to(b)/2.0)
	var report: Dictionary = builder.get("report")
	for i: int in range(count):
		var p: Vector2 = a.lerp(b,(float(i)+.5)/count)
		report.roads.append({"station":info.station,"up":[up.x,up.y,up.z],"offset":[p.x,p.y],"surfaces":1,"max_edge_before_projection":.4})

func traffic() -> void:
	var node: Node3D = Node3D.new()
	node.name = "CityTraffic"
	node.set_script(load("res://scripts/city_traffic.gd"))
	node.set_meta("radius",radius)
	var route_points: PackedVector2Array = PackedVector2Array()
	for point: Array in info.loop:
		route_points.append(v2(point))
	node.set_meta("route_points",route_points)
	district.add_child(node)
	var models: Array[String] = ["sedan","hatchback-sports","suv"]
	for i: int in range(3):
		var body: Node3D = Node3D.new()
		body.name = "Car_"+str(i)
		body.set_meta("district_up",up)
		body.set_meta("progress",float(i)*35.0+float(index)*4.0)
		body.set_meta("speed",1.65)
		node.add_child(body)
		var visual: Node3D = (load("res://assets/urban/"+models[(index+i)%3]+".glb") as PackedScene).instantiate() as Node3D
		var box: AABB = builder.call("bounds",visual) as AABB
		var scale_factor: float = 2.25/maxf(box.size.x,box.size.z)
		body.add_child(visual)
		visual.scale=Vector3.ONE*scale_factor
		visual.position=-Vector3(box.get_center().x,box.position.y,box.get_center().z)*scale_factor
		builder.call("tint_model",visual)

func nearest_walk(p: Vector2) -> Vector2:
	var edges: Array=[]
	for i: int in range(info.loop.size()):
		edges.append([info.loop[i],info.loop[(i+1)%info.loop.size()]])
	for road: Array in info.roads:
		edges.append(road)
	for path: Array in info.paths:
		for i: int in range(path.size()-1):
			edges.append([path[i],path[i+1]])
	var nearest: Vector2=p
	var distance: float=INF
	for edge: Array in edges:
		var a: Vector2=v2(edge[0])
		var b: Vector2=v2(edge[1])
		var q: Vector2=a+(b-a)*clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
		if p.distance_to(q)<distance:
			distance=p.distance_to(q)
			nearest=q
	return nearest
