extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const WorldRoutes = preload("res://scripts/world_routes.gd")
var radius: float
var builder: SceneTree
var parent: Node3D
var batches: Dictionary = {}
var models: Dictionary = {}
var batch_district: int = 0
var district_routes: Array = []
var tree_count: int = 0
var plant_count: int = 0
var planting_layout: Dictionary = {}
var planting_groups: Array[Dictionary] = []
var pocket_specimens: int = 0

static func build(owner_builder: SceneTree, globe: Node3D) -> void:
	var ecology: RefCounted = load("res://tools/ecology_world.gd").new() as RefCounted
	ecology.call("generate",owner_builder,globe)

func generate(owner_builder: SceneTree, globe: Node3D) -> void:
	builder=owner_builder
	radius=float(builder.get("radius"))
	parent=Node3D.new()
	parent.name="EcologicalReserves"
	globe.add_child(parent)
	var layout: Dictionary=builder.get("layout")
	var districts: Array=builder.get("districts")
	for i: int in range(districts.size()):
		var data: Dictionary=districts[i]
		var nd: Array=layout.stations[i].normal
		var up: Vector3=Vector3(nd[0],nd[1],nd[2])
		batch_district=i
		district_routes=WorldRoutes.district_paths(data,radius)
		terrain(up,data,i)
		vegetation(up,data,i)
	flush_batches()
	parent.set_meta("authored_planting",true)
	parent.set_meta("planting_groups",planting_groups)
	var report: Dictionary=builder.get("report")
	report["ecology"]={"trees":tree_count,"understory_clusters":plant_count,"districts":districts.size(),"radius":radius,"water_collision":false,"authored_planting":true,"planting_version":int(planting_layout.version),"planting_groups":planting_groups,"pocket_specimens_preserved":pocket_specimens,"pocket_specimens_omitted":0}
	for model: Node3D in models.values():
		model.free()

func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]),float(a[1]))

func water_distance(p: Vector2,data: Dictionary) -> float:
	return Waterfront.water_distance(p,data)

func edge_distance(p: Vector2,data: Dictionary,index: int) -> float:
	var local: Vector2=p/v2(data.extent)
	var angle: float=local.angle()
	var edge: float=1.0+.045*sin(angle*3.0+float(index))+.035*cos(angle*5.0-float(index))
	return (edge-local.length())*minf(data.extent[0],data.extent[1])

func dry_distance(p: Vector2,data: Dictionary,index: int) -> float:
	return minf(edge_distance(p,data,index),water_distance(p,data))

func terrain(up: Vector3,data: Dictionary,index: int) -> void:
	var patch: Node3D=Node3D.new()
	patch.name="Reserve_"+str(data.station)
	patch.set_meta("biome",data.biome)
	parent.add_child(patch)
	var st: SurfaceTool=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wet: SurfaceTool=SurfaceTool.new()
	wet.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Clip each triangle to the lake/river and coastline contour. Water has no
	# hidden land collision underneath it. Fine vertices keep curved shores smooth.
	var step: float=.8
	var limit: int=51
	for x: int in range(-limit,limit):
		for y: int in range(-limit,limit):
			var a: Vector2=Vector2(x,y)*step
			var b: Vector2=a+Vector2(step,0)
			var c: Vector2=a+Vector2(step,step)
			var d: Vector2=a+Vector2(0,step)
			clip_triangle(st,[a,b,c],up,data,index)
			clip_triangle(st,[a,c,d],up,data,index)
			clip_triangle(wet,[a,b,c],up,data,index,true)
			clip_triangle(wet,[a,c,d],up,data,index,true)
	var mat: StandardMaterial3D=Geo.material(Color.WHITE)
	mat.vertex_color_use_as_albedo=true
	Geo.mesh_node(patch,"ContouredBanksAndGround",st.commit(),mat,true)
	var water_mat: ShaderMaterial=ShaderMaterial.new()
	water_mat.shader=load("res://shaders/freshwater.gdshader") as Shader
	water_mat.set_shader_parameter("water_color",Color("456e61") if index==5 else Color("457f87"))
	Geo.mesh_node(patch,"FreshwaterContours",wet.commit(),water_mat)
	build_boardwalks(patch,up,data)

func build_boardwalks(patch: Node3D,up: Vector3,data: Dictionary) -> void:
	var wood_mat: StandardMaterial3D = Geo.material(Color.WHITE)
	wood_mat.vertex_color_use_as_albedo = true
	var structure: SurfaceTool = SurfaceTool.new()
	structure.begin(Mesh.PRIMITIVE_TRIANGLES)
	var run_count: int = 0
	var route_index: int = 0
	for path: Array in district_routes:
		var route: Array[Dictionary] = Waterfront.samples(up,path,data,radius)
		var deck: ArrayMesh = Waterfront.deck_mesh(route,radius,Waterfront.HEIGHT,Waterfront.WIDTH,true)
		if deck == null:
			continue
		var deck_node: MeshInstance3D = Geo.mesh_node(patch,"TimberBoardwalk_"+str(route_index),deck,wood_mat,true)
		deck_node.set_meta("surface_owner","wet_route_only")
		route_index += 1
		var run_start: int = -1
		for i: int in range(route.size()):
			var is_wet: bool = i < route.size()-1 and bool(route[i].wet)
			if is_wet and run_start < 0:
				run_start = i
			if not is_wet and run_start >= 0:
				boardwalk_structure(structure,route,run_start,i,up,data)
				run_count += 1
				run_start = -1
	if run_count > 0:
		var rails: MeshInstance3D = Geo.mesh_node(patch,"BoardwalkRailsAndSupports",structure.commit(),wood_mat,true)
		(rails.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
		patch.set_meta("protected_boardwalk_runs",run_count)
		patch.set_meta("boardwalk_usable_width",Waterfront.WIDTH)

func boardwalk_bank_clear(sample: Dictionary,up: Vector3,data: Dictionary) -> bool:
	var axes: Basis=Geo.frame(up)
	for lateral: float in [-Waterfront.WIDTH*.5,0.0,Waterfront.WIDTH*.5]:
		var normal: Vector3=Waterfront.at(sample,radius,Waterfront.HEIGHT,lateral).normalized()
		var local: Vector2=Vector2(normal.dot(axes.x),normal.dot(axes.z))*radius/normal.dot(up)
		if water_distance(local,data)<.25:
			return false
	return true

func boardwalk_structure(st: SurfaceTool,route: Array[Dictionary],start: int,finish: int,up: Vector3,data: Dictionary) -> void:
	var deck_height: float = Waterfront.HEIGHT
	var half_width: float = Waterfront.WIDTH*.5
	var timber: Color = Color("79674f")
	var handrail: Color = Color("465d58")
	# Continuous fascia encloses the thin deck edge; both bank thresholds are
	# flush with the paving and remain completely open for the player to enter.
	for i: int in range(start,finish):
		for sign_value: float in [-1.0,1.0]:
			var a: Vector3 = Waterfront.at(route[i],radius,deck_height,half_width*sign_value)
			var b: Vector3 = Waterfront.at(route[i+1],radius,deck_height,half_width*sign_value)
			var c: Vector3 = Waterfront.at(route[i+1],radius,deck_height-.16,half_width*sign_value)
			var d: Vector3 = Waterfront.at(route[i],radius,deck_height-.16,half_width*sign_value)
			var side: Vector3 = route[i].side
			Waterfront.face(st,a,b,c,d,timber,side*sign_value)
	for endpoint: int in [start,finish]:
		var a: Vector3 = Waterfront.at(route[endpoint],radius,deck_height,-half_width)
		var b: Vector3 = Waterfront.at(route[endpoint],radius,deck_height,half_width)
		var c: Vector3 = Waterfront.at(route[endpoint],radius,deck_height-.16,half_width)
		var d: Vector3 = Waterfront.at(route[endpoint],radius,deck_height-.16,-half_width)
		var inside: int = start+1 if endpoint == start else finish-1
		var normal: Vector3 = route[endpoint].normal
		var inner_normal: Vector3 = route[inside].normal
		Waterfront.face(st,a,b,c,d,timber,(normal-inner_normal).normalized())
	# Timber continues onto dry land to form a flush landing. End the rail where
	# its full width is already safely ashore, so a return path at the landing
	# never catches the last post. The water-facing part stays fully guarded.
	var rail_start: int=start
	var rail_finish: int=finish
	while rail_start+1<rail_finish and boardwalk_bank_clear(route[rail_start+1],up,data):
		var travelled: float=(route[start].normal as Vector3).angle_to(route[rail_start+1].normal as Vector3)*radius
		if travelled>.7:
			break
		rail_start+=1
	while rail_finish-1>rail_start and boardwalk_bank_clear(route[rail_finish-1],up,data):
		var travelled: float=(route[finish].normal as Vector3).angle_to(route[rail_finish-1].normal as Vector3)*radius
		if travelled>.7:
			break
		rail_finish-=1
	# Outboard posts leave the complete 2.2 m deck width available to the body.
	var rail_lateral: float=half_width+.11
	var corners: Array[int] = [rail_start]
	for i: int in range(rail_start+1,rail_finish):
		if bool(route[i].corner):
			corners.append(i)
	corners.append(rail_finish)
	var posts: Array[int] = [rail_start]
	for section: int in range(corners.size()-1):
		var first: int = corners[section]
		var last: int = corners[section+1]
		var length: float = float(route[last].distance)-float(route[first].distance)
		var count: int = maxi(1,ceili(length/1.4))
		for j: int in range(1,count+1):
			var sample_index: int = roundi(lerpf(first,last,float(j)/count))
			if sample_index > posts[-1]:
				posts.append(sample_index)
	var previous: int = rail_start
	for i: int in posts:
		for sign_value: float in [-1.0,1.0]:
			var lateral: float = rail_lateral*sign_value
			var bottom: Vector3 = Waterfront.at(route[i],radius,-.38,lateral)
			var top: Vector3 = Waterfront.at(route[i],radius,deck_height+1.08,lateral)
			Waterfront.beam(st,bottom,top,.12,.12,timber)
			Waterfront.beam(st,top,top.normalized()*(radius+deck_height+1.13),.15,.15,Color("b6a17a"))
			Waterfront.beam(st,Waterfront.at(route[i],radius,deck_height-.10,(half_width-.04)*sign_value),Waterfront.at(route[i],radius,deck_height-.17,lateral),.10,.10,timber)
			if i > rail_start:
				for rail_height: float in [.47,.98]:
					var rail_from: Vector3 = Waterfront.at(route[previous],radius,deck_height+rail_height,lateral)
					var rail_to: Vector3 = Waterfront.at(route[i],radius,deck_height+rail_height,lateral)
					Waterfront.beam(st,rail_from,rail_to,.085,.105,handrail)
				var a: Vector3 = Waterfront.at(route[previous],radius,deck_height-.09,lateral)
				var b: Vector3 = Waterfront.at(route[i],radius,deck_height-.09,lateral)
				Waterfront.beam(st,a,b,.16,.13,timber)
		previous = i

func clip_triangle(st: SurfaceTool,polygon: Array[Vector2],up: Vector3,data: Dictionary,index: int,wet: bool=false) -> void:
	var clipped: Array[Vector2]=[]
	for j: int in range(3):
		var a: Vector2=polygon[j]
		var b: Vector2=polygon[(j+1)%3]
		var da: float=minf(edge_distance(a,data,index),-water_distance(a,data)+.2) if wet else dry_distance(a,data,index)
		var db: float=minf(edge_distance(b,data,index),-water_distance(b,data)+.2) if wet else dry_distance(b,data,index)
		if da>=0:
			clipped.append(a)
		if (da>=0)!=(db>=0):
			clipped.append(a.lerp(b,clampf(da/(da-db),0.0,1.0)))
	if clipped.size()<3:
		return
	for j: int in range(1,clipped.size()-1):
		# XY grid wound clockwise when lifted onto the sphere.
		for p: Vector2 in [clipped[0],clipped[j],clipped[j+1]]:
			var shore: float=dry_distance(p,data,index)
			var h: float=.055 if wet else .09+.075*smoothstep(0.0,1.1,shore)
			var noise_value: float=sin(p.x*1.3+sin(p.y*.7))*sin(p.y*.83+p.x*.24)
			var land_color: Color=Color(str(data.land))
			var color: Color=Color("a29871").lerp(land_color,smoothstep(.1,1.7,shore))
			color=color.lightened(noise_value*.035)
			var point: Vector3=Geo.surface(up,p,radius+h)
			st.set_color(color)
			st.set_normal(point.normalized())
			st.add_vertex(point)

func path_distance(p: Vector2,data: Dictionary) -> float:
	var distance: float=999.0
	# Independent callers also use this geometric query without running generate.
	# Authored paths plus the four protected axes cover the shared route network.
	for path: Array in data.paths:
		for i: int in range(path.size()-1):
			var a: Vector2=v2(path[i])
			var b: Vector2=v2(path[i+1])
			var q: Vector2=a+(b-a)*clampf((p-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
			distance=minf(distance,p.distance_to(q))
	# Protect the four inter-island approach axes as well.
	if absf(p.x)<1.7 or absf(p.y)<1.7:
		return 0.0
	return distance

func marina_vegetation_clearance(p: Vector2,data: Dictionary) -> float:
	if str(data.station) != "admissions":
		return INF
	# Measure in metres on the sphere, rather than treating the district's
	# tangent coordinates as physical widths near the island edge. The full
	# 5.4 m deck and the moored boat reserve their footprint before foliage.
	var point: Vector3 = Geo.surface(Vector3.UP,p,radius)
	var a: Vector3 = Geo.surface(Vector3.UP,Vector2(31.5,6),radius)
	var b: Vector3 = Geo.surface(Vector3.UP,Vector2(41,6),radius)
	var axis: Vector3 = b-a
	var nearest: Vector3 = a+axis*clampf((point-a).dot(axis)/axis.length_squared(),0.0,1.0)
	var boat: Vector3 = Geo.surface(Vector3.UP,Vector2(37,11.1),radius)
	return minf(point.distance_to(nearest)-2.7,point.distance_to(boat)-2.8)

func vegetation(up: Vector3,data: Dictionary,index: int) -> void:
	if planting_layout.is_empty():
		planting_layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/ecology_planting.json")) as Dictionary
	var plan: Dictionary=planting_layout.districts[str(data.station)]
	var groups: Array[Dictionary]=[]
	# Each crown and bank accent has an authored position, scale and rotation.
	# Empty shores are intentional view windows, never failed scatter attempts.
	for group: Dictionary in plan.groups:
		var group_name: String=str(group.name)
		for row: Array in group.trees:
			place(str(row[0]),up,Vector2(float(row[1]),float(row[2])),float(row[3]),deg_to_rad(float(row[4])),true,group_name)
		for row: Array in group.understory:
			place(str(row[0]),up,Vector2(float(row[1]),float(row[2])),float(row[3]),deg_to_rad(float(row[4])),false,group_name)
		groups.append({"name":group_name,"trees":group.trees.size(),"understory_clusters":group.understory.size(),"tree_positions":group.trees,"understory_positions":group.understory})
	# These three specimens belong to the authored bench/lamp assemblies. Keep
	# their previously checked placement when replacing the reserve vegetation.
	var garden_trees: Array=[]
	for point: Array in data.gardens:
		var tree_point: Vector2 = v2(point)+Vector2(2.0,0)
		place("birch",up,tree_point,.65,float(index),true,"Pocket garden specimens")
		garden_trees.append(["birch",tree_point.x,tree_point.y,.65,rad_to_deg(float(index))])
		pocket_specimens+=1
	groups.append({"name":"Pocket garden specimens","trees":garden_trees.size(),"understory_clusters":0,"tree_positions":garden_trees,"understory_positions":[],"source":"authored district garden assemblies"})
	planting_groups.append({"station":str(data.station),"groups":groups,"view_windows":plan.view_windows})

func place(kind: String,up: Vector3,p: Vector2,size: float,yaw: float,solid: bool=false,group_name: String="") -> void:
	var n: Vector3=Geo.surface(up,p,radius).normalized()
	var transform: Transform3D=Transform3D(Geo.frame(n)*Basis(Vector3.UP,yaw),n*(radius+.16))
	transform.basis=transform.basis.scaled(Vector3.ONE*size)
	var key: String=kind+"_"+str(batch_district)
	if not batches.has(key):
		batches[key]={"kind":kind,"placements":[],"groups":[]}
	(batches[key].placements as Array).append(transform)
	(batches[key].groups as Array).append(group_name)
	if solid:
		tree_count+=1
		var body: StaticBody3D=StaticBody3D.new()
		body.name="TreeTrunk"
		body.collision_layer=8
		body.set_meta("planting_group",group_name)
		body.set_meta("district_index",batch_district)
		body.set_meta("local_position",p)
		body.set_meta("species",kind)
		parent.add_child(body)
		body.transform=transform
		var shape: CollisionShape3D=CollisionShape3D.new()
		var capsule: CapsuleShape3D=CapsuleShape3D.new()
		capsule.radius=.22
		capsule.height=1.8
		shape.shape=capsule
		shape.position.y=.9
		body.add_child(shape)
	else:
		plant_count+=1

func flush_batches() -> void:
	for key: String in batches:
		var kind: String=str(batches[key].kind)
		if not models.has(kind):
			models[kind]=(load("res://assets/ecology/"+kind+".glb") as PackedScene).instantiate() as Node3D
		var model: Node3D=models[kind] as Node3D
		for source: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var node: MultiMeshInstance3D=MultiMeshInstance3D.new()
			node.name=key+"_instances"
			var mesh: Mesh=source.mesh.duplicate() as Mesh
			for i: int in range(mesh.get_surface_count()):
				var mat: StandardMaterial3D=source.get_active_material(i).duplicate() as StandardMaterial3D
				mat.vertex_color_use_as_albedo=true
				mat.albedo_color=Color.WHITE
				mat.cull_mode=BaseMaterial3D.CULL_DISABLED
				mat.roughness=1.0
				mesh.surface_set_material(i,mat)
			node.multimesh=MultiMesh.new()
			node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
			node.multimesh.mesh=mesh
			var placements: Array[Transform3D]=[]
			for placement: Transform3D in batches[key].placements:
				placements.append(placement*source.transform)
			node.set_meta("placements",placements)
			node.set_meta("planting_groups",batches[key].groups)
			# Bark and foliage meshes share the same authored tree indices.
			node.set_meta("ecology_batch_key",key)
			node.set_meta("ecology_kind",kind)
			node.set_script(load("res://scripts/ecology_instances.gd"))
			if kind in ["fern","cattail","bank_stones"]:
				node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			parent.add_child(node)
