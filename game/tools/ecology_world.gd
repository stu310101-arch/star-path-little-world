extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Waterfront = preload("res://scripts/waterfront_routes.gd")
const WorldRoutes = preload("res://scripts/world_routes.gd")
const Landforms = preload("res://tools/world_landforms.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
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
var landforms: RefCounted
var shore_walls: SurfaceTool
var landform_reports: Array[Dictionary] = []

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
		landforms=Landforms.new()
		landforms.call("configure",data,i,radius,up)
		terrain(up,data,i)
		vegetation(up,data,i)
		landform_reports.append(landforms.call("statistics") as Dictionary)
	flush_batches()
	parent.set_meta("authored_planting",true)
	parent.set_meta("planting_groups",planting_groups)
	var report: Dictionary=builder.get("report")
	report["landforms"]=landform_reports
	report["ecology"]={"trees":tree_count,"understory_clusters":plant_count,"districts":districts.size(),"radius":radius,"water_collision":false,"authored_planting":true,"planting_version":int(planting_layout.version),"planting_groups":planting_groups,"pocket_specimens_preserved":pocket_specimens,"pocket_specimens_omitted":0}
	for model: Node3D in models.values():
		model.free()

func v2(a: Array) -> Vector2:
	return Vector2(float(a[0]),float(a[1]))

func water_distance(p: Vector2,data: Dictionary) -> float:
	return Waterfront.water_distance(p,data)

func edge_distance(p: Vector2,data: Dictionary,index: int) -> float:
	return Biomes.coast_distance(p,data,index)

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
	shore_walls=SurfaceTool.new()
	shore_walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Clip each triangle to the lake/river and coastline contour. Water has no
	# hidden land collision underneath it. Fine vertices keep curved shores smooth.
	var coordinates: Array[float]=[]
	for cell: int in range(-60,-10): coordinates.append(float(cell)*4.8)
	for cell: int in range(-60,61): coordinates.append(float(cell)*.8)
	for cell: int in range(11,61): coordinates.append(float(cell)*4.8)
	var chunk_index: int=0
	for x: int in range(coordinates.size()-1):
		for y: int in range(coordinates.size()-1):
			var a: Vector2=Vector2(coordinates[x],coordinates[y])
			var b: Vector2=Vector2(coordinates[x+1],coordinates[y])
			var c: Vector2=Vector2(coordinates[x+1],coordinates[y+1])
			var d: Vector2=Vector2(coordinates[x],coordinates[y+1])
			clip_triangle(st,[a,b,c],up,data,index)
			clip_triangle(st,[a,c,d],up,data,index)
			clip_triangle(wet,[a,b,c],up,data,index,true)
			clip_triangle(wet,[a,c,d],up,data,index,true)
		if (x+1)%32==0 or x==coordinates.size()-2:
			finish_ground_chunk(patch,st,data,chunk_index)
			chunk_index+=1
			st=SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rock_material: StandardMaterial3D=Geo.material(Color("858476"))
	rock_material.vertex_color_use_as_albedo=true
	var wall_mesh: ArrayMesh=shore_walls.commit()
	if wall_mesh!=null and wall_mesh.get_surface_count()>0:
		var wall: MeshInstance3D=Geo.mesh_node(patch,"ShoreRockStrata",wall_mesh,rock_material,true)
		(wall.get_node("SurfaceCollision") as StaticBody3D).collision_layer=8
	var water_mat: ShaderMaterial=ShaderMaterial.new()
	water_mat.shader=load("res://shaders/freshwater.gdshader") as Shader
	water_mat.set_shader_parameter("water_color",Color("456e61") if index==5 else Color("457f87"))
	Geo.mesh_node(patch,"FreshwaterContours",wet.commit(),water_mat)
	build_boardwalks(patch,up,data)
	build_biome_rocks(patch,up,data)

func finish_ground_chunk(patch: Node3D,st: SurfaceTool,data: Dictionary,index: int) -> void:
	var mesh: ArrayMesh=st.commit()
	if mesh==null or mesh.get_surface_count()==0: return
	var mat: StandardMaterial3D=Geo.material(Color.WHITE)
	mat.vertex_color_use_as_albedo=true
	var label: String="ContouredBanksAndGround" if index==0 else "ContouredBanksAndGround_"+str(index)
	var ground: MeshInstance3D=Geo.mesh_node(patch,label,mesh,mat,true)
	ground.set_meta("terrain_blend_channels","uv2: damp_soil, exposed_rock")
	ground.set_meta("continuous_terrain_material",true)
	ground.set_meta("biome_station",str(data.station))
	ground.set_meta("terrain_chunk_triangles",mesh.surface_get_array_len(0)/3)

func build_biome_rocks(patch: Node3D,up: Vector3,data: Dictionary) -> void:
	# Continuous fractured ledges follow authored geological spines. Every foot
	# samples the actual terrain, so a ridge cannot hover above a hillside.
	var st: SurfaceTool=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count: int=0
	for spine: Array in Biomes.spec(str(data.station)).get("rocks",[]):
		var a: Vector2=Vector2(spine[0],spine[1])
		var b: Vector2=Vector2(spine[2],spine[3])
		var side: Vector2=(b-a).normalized().orthogonal()
		var steps: int=maxi(4,ceili(a.distance_to(b)/4.2))
		var previous: PackedVector3Array=[]
		for i: int in range(steps+1):
			var t: float=float(i)/float(steps)
			var p: Vector2=a.lerp(b,t)
			var width: float=float(spine[4])*1.35*(.75+.13*sin(float(i)*1.72)+.11*cos(float(i)*.71))
			if dry_distance(p,data,batch_district)<width+1.0 or float(landforms.call("clearance",p))<width+1.0 or Biomes.trail_distance(p,data)<width+2.5:
				previous=[]
				continue
			var taper: float=smoothstep(0.0,.12,t)*(1.0-smoothstep(.86,1.0,t))
			var height: float=float(spine[5])*.45*(.64+.21*sin(float(i)*1.17)+.15*cos(float(i)*.53))*taper
			var centre_height: float=float(landforms.call("mesh_height_at",p))
			var ring: PackedVector3Array=[]
			var cross_positions: Array[float]=[-1.0,-.68,-.30,.17,.66,1.0]
			var cross_heights: Array[float]=[-.32,.30,1.0,.82,.24,-.32]
			for j: int in range(cross_positions.size()):
				var local: Vector2=p+side*(cross_positions[j]*width*.55+.18*sin(float(i)*1.4+float(j)))
				var floor_height: float=float(landforms.call("mesh_height_at",local))
				var elevated: float=maxf(floor_height,centre_height)+height*cross_heights[j]
				if j==0 or j==cross_positions.size()-1: elevated=floor_height-.45
				ring.append(Geo.surface(up,local,radius).normalized()*(radius+elevated))
			if not previous.is_empty():
				for j: int in range(ring.size()-1):
					rock_triangle(st,previous[j],ring[j],ring[j+1])
					rock_triangle(st,previous[j],ring[j+1],previous[j+1])
				count+=1
			previous=ring
	if count>0:
		var mesh: MeshInstance3D=Geo.mesh_node(patch,"BiomeRockOutcrops",st.commit(),Geo.material(Color("837a66")),true)
		(mesh.get_node("SurfaceCollision") as StaticBody3D).collision_layer=8
		mesh.set_meta("authored_outcrop_count",count)
		mesh.set_meta("landform_style","fractured continuous ledge with terrain-embedded feet")

func rock_triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	var normal: Vector3=(c-a).cross(b-a).normalized()
	if normal.dot((a+b+c).normalized())<0.0:
		var swap: Vector3=b
		b=c
		c=swap
		normal=-normal
	for p: Vector3 in [a,b,c]:
		st.set_color(Color.WHITE)
		st.set_normal(normal)
		st.add_vertex(p)

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

func boardwalk_meets_global_bridge(sample: Dictionary,data: Dictionary) -> bool:
	var district_index: int=WorldRoutes.IDS.find(str(data.station))
	var normal: Vector3=sample.normal
	for edge: Vector2i in WorldRoutes.bridge_edges():
		if district_index!=edge.x and district_index!=edge.y: continue
		var endpoints: Array[Vector3]=WorldRoutes.bridge_endpoints(edge,radius)
		var endpoint: Vector3=endpoints[0 if district_index==edge.x else 1]
		if normal.distance_to(endpoint)*radius<.05: return true
	return false

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
		# The concrete bridge already closes this joined deck edge. An internal
		# vertical fascia here becomes a low wall across its open entrance.
		if boardwalk_meets_global_bridge(route[endpoint],data): continue
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
	var shoreline: Array[Vector2]=[]
	for j: int in range(3):
		var a: Vector2=polygon[j]
		var b: Vector2=polygon[(j+1)%3]
		var da: float=minf(edge_distance(a,data,index),-water_distance(a,data)+.2) if wet else dry_distance(a,data,index)
		var db: float=minf(edge_distance(b,data,index),-water_distance(b,data)+.2) if wet else dry_distance(b,data,index)
		if da>=0:
			clipped.append(a)
		if (da>=0)!=(db>=0):
			var intersection: Vector2=a.lerp(b,clampf(da/(da-db),0.0,1.0))
			clipped.append(intersection)
			shoreline.append(intersection)
	if clipped.size()<3:
		return
	if not wet and shoreline.size()==2:
		landforms.call("add_shore_wall",shore_walls,shoreline[0],shoreline[1])
	for j: int in range(1,clipped.size()-1):
		# XY grid wound clockwise when lifted onto the sphere.
		# Soil/rock coverage belongs to shared vertices, never whole triangles.
		# The former centroid material split made every bank a sawtooth cutout.
		for p: Vector2 in [clipped[0],clipped[j],clipped[j+1]]:
			var shore: float=dry_distance(p,data,index)
			var h: float=.055 if wet else float(landforms.call("height_at",p))
			var noise_value: float=sin(p.x*1.3+sin(p.y*.7))*sin(p.y*.83+p.x*.24)
			var land_color: Color=Color(str(data.land))
			var color: Color=Color("a29871").lerp(land_color,smoothstep(.1,1.7,shore))
			color=color.lightened(noise_value*.035)
			var point: Vector3=Geo.surface(up,p,radius).normalized()*(radius+h)
			st.set_color(color)
			st.set_uv2(Vector2.ZERO if wet else landforms.call("surface_blend_at",p) as Vector2)
			st.set_normal(point.normalized() if wet else landforms.call("normal_at",p) as Vector3)
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
	var mooring: Vector2 = preload("res://tools/world_infrastructure.gd").marina_mooring(data)
	var boat: Vector3 = Geo.surface(Vector3.UP,mooring,radius)
	return minf(point.distance_to(nearest)-2.7,point.distance_to(boat)-4.8)

func vegetation(up: Vector3,data: Dictionary,index: int) -> void:
	if landforms==null or str((landforms.get("data") as Dictionary).station)!=str(data.station):
		landforms=Landforms.new()
		landforms.call("configure",data,index,radius,up)
	if planting_layout.is_empty():
		planting_layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/ecology_planting.json")) as Dictionary
	var plan: Dictionary=planting_layout.districts[str(data.station)]
	var groups: Array[Dictionary]=[]
	# Each crown and bank accent has an authored position, scale and rotation.
	# Empty shores are intentional view windows, never failed scatter attempts.
	for group: Dictionary in plan.groups:
		var group_name: String=str(group.name)
		for row: Array in group.trees:
			var tree_point:=Vector2(float(row[1]),float(row[2]))
			# Keep this authored birch beside the shortened reserve trail. The
			# original (20,-19) trunk falls on its new first segment at R=60.
			if data.has("compact_coast_max") and str(data.station)=="recommendations" and group_name=="Southeast birch room" and tree_point.is_equal_approx(Vector2(20,-19)):
				tree_point=Vector2(22,-17)
			place(str(row[0]),up,tree_point,float(row[3]),deg_to_rad(float(row[4])),true,group_name)
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
	var outdoor_trees: Array=[]
	var outdoor_understory: Array=[]
	var tree_shore_clearance: float=2.5 if data.has("compact_coast_max") else 7.0
	for row: Dictionary in Biomes.tree_rows(data):
		var p: Vector2=row.p
		if dry_distance(p,data,index)<tree_shore_clearance or float(landforms.call("clearance",p))<4.0 or Biomes.trail_distance(p,data)<3.0: continue
		place(str(row.kind),up,p,float(row.scale),float(row.yaw),true,str(row.group))
		outdoor_trees.append([row.kind,p.x,p.y,row.scale,rad_to_deg(float(row.yaw))])
		for accent: int in range(3 if index==2 else 8):
			var angle: float=float(accent)*2.399+float(row.yaw)
			var shrub: Vector2=p+Vector2(cos(angle),sin(angle))*(1.5+float(accent%3)*.65)
			if Biomes.trail_distance(shrub,data)<2.0 or dry_distance(shrub,data,index)<1.0 or float(landforms.call("clearance",shrub))<2.0: continue
			place("fern",up,shrub,.56 if index==2 else .72+float(accent%3)*.12,angle,false,str(row.group))
			outdoor_understory.append(["fern",shrub.x,shrub.y])
	# Reed belts follow authored wetland shores, leaving the town and paths open.
	for water: Dictionary in Biomes.spec(str(data.station)).get("waters",[]):
		if str(water.kind)!="lake": continue
		var belt_count: int=112 if index==5 else 34
		for i: int in range(belt_count):
			var angle: float=TAU*float(i)/float(belt_count)
			# Three long reed beds retain deliberate open windows across each lake.
			if sin(angle*3.0+.6)<-.40: continue
			for band: int in range(2 if index==5 else 1):
				var p: Vector2=Vector2(water.center[0],water.center[1])+Vector2(cos(angle)*float(water.size[0]),sin(angle)*float(water.size[1]))*(1.02+float(band)*.075)
				if Biomes.trail_distance(p,data)<2.5 or float(landforms.call("clearance",p))<3.0: continue
				if dry_distance(p,data,index)<.1: continue
				place("cattail",up,p,.64+float(i%4)*.075,angle,false,"Outer wetland reed belt")
	groups.append({"name":"Authored outdoor groves","trees":outdoor_trees.size(),"understory_clusters":outdoor_understory.size(),"tree_positions":outdoor_trees,"understory_positions":outdoor_understory,"source":"res://data/biomes.json"})
	planting_groups.append({"station":str(data.station),"groups":groups,"view_windows":plan.view_windows})

func place(kind: String,up: Vector3,p: Vector2,size: float,yaw: float,solid: bool=false,group_name: String="") -> void:
	if kind in ["alder","birch","pine","willow"] and FileAccess.file_exists("res://assets/vegetation_rebuilt/"+kind+".glb"):
		# New authored trees have metre-scale bounds; preserve each grove's
		# intended height instead of multiplying a larger replacement twice.
		size*=float({"alder":.626,"birch":.716,"pine":.815,"willow":.604}[kind])
	var n: Vector3=Geo.surface(up,p,radius).normalized()
	var ground_height: float=float(landforms.call("height_at",p)) if float(landforms.call("dry_distance",p))>=0.0 else .16
	if maxf(absf(p.x),absf(p.y))>48.0 and float(landforms.call("dry_distance",p))>6.0:
		ground_height=float(landforms.call("mesh_height_at",p))
	var transform: Transform3D=Transform3D(Geo.frame(n)*Basis(Vector3.UP,yaw),n*(radius+ground_height-.005))
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
		var rebuilt: bool=kind in ["alder","birch","pine","willow"] and FileAccess.file_exists("res://assets/vegetation_rebuilt/"+kind+".glb")
		if not models.has(kind):
			var optimized: bool=FileAccess.file_exists("res://assets/vegetation_rebuilt/"+kind+".glb")
			models[kind]=(load(("res://assets/vegetation_rebuilt/" if optimized else "res://assets/ecology/")+kind+".glb") as PackedScene).instantiate() as Node3D
		var model: Node3D=models[kind] as Node3D
		for source: MeshInstance3D in model.find_children("*","MeshInstance3D",true,false):
			var node: MultiMeshInstance3D=MultiMeshInstance3D.new()
			node.name=key+"_instances"
			var mesh: Mesh=source.mesh.duplicate() as Mesh
			for i: int in range(mesh.get_surface_count()):
				var mat: StandardMaterial3D=source.get_active_material(i).duplicate() as StandardMaterial3D
				if not rebuilt:
					mat.vertex_color_use_as_albedo=true
					mat.albedo_color=Color.WHITE
				if str(source.name).to_lower().contains("leav") or str(source.name).to_lower().contains("foliage"):
					var id: String=str((builder.get("districts") as Array)[int(key.get_slice("_",key.get_slice_count("_")-1))].station)
					var tone: Array=Biomes.spec(id).get("leaf_tint",[1.0,1.0,1.0])
					mat.albedo_color*=Color(float(tone[0]),float(tone[1]),float(tone[2]))
				if not rebuilt:
					mat.cull_mode=BaseMaterial3D.CULL_DISABLED
				mat.roughness=1.0
				mat.metallic_specular=.12
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
