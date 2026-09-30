extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Timber = preload("res://scripts/waterfront_routes.gd")
const BRIDGE_RAIL_OFFSET: float = 1.46

static func build(builder: SceneTree, globe: Node3D) -> void:
	var radius: float = float(builder.get("radius"))
	var up: Vector3 = Plan.grove_up()
	var grove: Node3D = Node3D.new()
	grove.name = "SakuraGrove"
	globe.add_child(grove)
	build_garden_surfaces(grove,up,radius)
	var placements: Array[Dictionary] = Plan.trees()
	for i: int in range(placements.size()):
		var placement: Dictionary = placements[i]
		var n: Vector3 = Geo.surface(up,placement.position,radius).normalized()
		var tree: Node3D = builder.call("scenery_asset",grove,"sakura_"+str(placement.variant)) as Node3D
		tree.name = "SakuraTree_"+str(i)
		var height_scale: float=float(placement.scale)
		var width_scale: float=float(placement.get("width_scale",1.0))
		if not is_equal_approx(width_scale,1.0):
			# Shape the specimen's visual crown in its local axes. Its capsule
			# keeps uniform scaling, so the physics body remains well-defined.
			var visual_children: Array[Node]=tree.get_children()
			var profile: Node3D=Node3D.new()
			profile.name="AuthoredCrownProfile"
			tree.add_child(profile)
			for child: Node in visual_children:
				if not child is PhysicsBody3D:
					child.reparent(profile,false)
			profile.scale=Vector3(width_scale,1.0,width_scale)
		tree.transform = Transform3D((Geo.frame(n)*Basis(Vector3.UP,float(placement.yaw))).scaled(Vector3.ONE*height_scale),n*(radius+0.16))
		tree.set_meta("garden_position",placement.position)
		refine_materials(tree)
	for placement: Dictionary in Plan.seats():
		var seat: Node3D = garden_anchor(grove,up,placement.position,radius,.26)
		seat.name = str(placement.id)
		seat.set_meta("garden_position",placement.position)
		seat.set_meta("garden_approach",placement.approach)
		builder.call("bench",seat,Vector3.ZERO,float(placement.yaw))
	for point: Vector2 in Plan.lights(radius):
		var lamp: Node3D = garden_anchor(grove,up,point,radius,.26)
		lamp.name = "GardenLantern"
		builder.call("lamp",lamp,Vector3.ZERO)
	build_overlook_rails(grove,up,radius)
	build_entry_sign(builder,grove,up,radius)
	build_bridge(builder,grove,up,radius)
	var report: Dictionary = builder.get("report")
	report["sakura_trees"] = placements.size()
	report["sakura_design"] = "authored blossom garden: accessible loop, open bridge arrival, two recessed scenic seating terraces"
	report["sakura_layout_version"] = Plan.LAYOUT_VERSION
	grove.set_meta("authored_tree_count",placements.size())
	grove.set_meta("arrival_view","open south bank; central crown clear of the bridge exit camera")
	grove.set_meta("seating_access","Bench fronts face the garden loop; open 2.75 m paved mouths; short outer corner guards")

static func garden_anchor(parent: Node3D,up: Vector3,point: Vector2,radius: float,height: float) -> Node3D:
	var normal: Vector3 = Geo.surface(up,point,radius).normalized()
	var node: Node3D = Node3D.new()
	parent.add_child(node)
	node.transform = Transform3D(Basis(Quaternion(up,normal))*Geo.frame(up),normal*(radius+height))
	return node

static func lift_path(path: Array,up: Vector3,radius: float) -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for point: Array in path:
		points.append(Geo.surface(up,Vector2(point[0],point[1]),radius).normalized())
	return points

static func polygon_field(point: Vector2,polygon: PackedVector2Array) -> float:
	var distance: float = INF
	for i: int in range(polygon.size()):
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i+1)%polygon.size()]
		var nearest: Vector2 = a+(b-a)*clampf((point-a).dot(b-a)/(b-a).length_squared(),0.0,1.0)
		distance = minf(distance,point.distance_to(nearest))
	return distance if Geometry2D.is_point_in_polygon(point,polygon) else -distance

static func path_field(point: Vector2,paths: Array[PackedVector3Array],platforms: Array[PackedVector2Array],up: Vector3,radius: float) -> float:
	var world_point: Vector3 = Geo.surface(up,point,radius)
	var distance: float = INF
	for path: PackedVector3Array in paths:
		for i: int in range(path.size()-1):
			var a: Vector3 = path[i]*radius
			var b: Vector3 = path[i+1]*radius
			var axis: Vector3 = b-a
			var nearest: Vector3 = a+axis*clampf((world_point-a).dot(axis)/axis.length_squared(),0.0,1.0)
			distance = minf(distance,world_point.distance_to(nearest))
	var field: float = Plan.WIDTH*.5-distance
	for polygon: PackedVector2Array in platforms:
		field = maxf(field,polygon_field(point,polygon))
	return field

static func field_triangle(st: SurfaceTool,points: Array[Vector2],values: Array[float],up: Vector3,radius: float,height: float,color: Color) -> void:
	var clipped: Array[Vector2] = []
	for i: int in range(3):
		var next: int = (i+1)%3
		if values[i] >= 0:
			clipped.append(points[i])
		if (values[i] >= 0) != (values[next] >= 0):
			clipped.append(points[i].lerp(points[next],values[i]/(values[i]-values[next])))
	for i: int in range(1,clipped.size()-1):
		Geo.triangle(st,Geo.surface(up,clipped[0],radius).normalized()*(radius+height),Geo.surface(up,clipped[i],radius).normalized()*(radius+height),Geo.surface(up,clipped[i+1],radius).normalized()*(radius+height),color)

static func build_garden_surfaces(grove: Node3D,up: Vector3,radius: float) -> void:
	var paths: Array[PackedVector3Array] = []
	for path: Array in Plan.paths(radius):
		paths.append(lift_path(path,up,radius))
	var platforms: Array[PackedVector2Array] = Plan.platforms()
	var coast: PackedVector2Array = Plan.island_outline()
	var ground: SurfaceTool = SurfaceTool.new()
	var shore: SurfaceTool = SurfaceTool.new()
	var edging: SurfaceTool = SurfaceTool.new()
	var paving: SurfaceTool = SurfaceTool.new()
	for st: SurfaceTool in [ground,shore,edging,paving]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var fields: Dictionary = {}
	var step: float = .28
	for x: int in range(-36,37):
		for y: int in range(-32,34):
			var point: Vector2 = Vector2(x,y)*step
			fields[Vector2i(x,y)] = Vector2(polygon_field(point,coast),path_field(point,paths,platforms,up,radius))
	for x: int in range(-36,36):
		for y: int in range(-32,33):
			var coordinates: Array[Vector2i] = [Vector2i(x,y),Vector2i(x+1,y),Vector2i(x+1,y+1),Vector2i(x,y+1)]
			for triangle: Array in [[0,1,2],[0,2,3]]:
				var points: Array[Vector2] = []
				var ground_values: Array[float] = []
				var shore_values: Array[float] = []
				var paving_values: Array[float] = []
				var edging_values: Array[float] = []
				for index: int in triangle:
					var coordinate: Vector2i = coordinates[index]
					var values: Vector2 = fields[coordinate]
					points.append(Vector2(coordinate)*step)
					ground_values.append(values.x)
					shore_values.append(values.x+.34)
					paving_values.append(values.y)
					edging_values.append(values.y+.14)
				field_triangle(ground,points,ground_values,up,radius,.16,Color("758c77"))
				field_triangle(shore,points,shore_values,up,radius,.08,Color("b3a890"))
				field_triangle(edging,points,edging_values,up,radius,.215,Color("82776f"))
				field_triangle(paving,points,paving_values,up,radius,.26,Color("9b9385"))
	Geo.mesh_node(grove,"Sand",shore.commit(),vertex_material())
	Geo.mesh_node(grove,"Land",ground.commit(),vertex_material(),true)
	Geo.mesh_node(grove,"StoneWalkEdging",edging.commit(),vertex_material(),true)
	Geo.mesh_node(grove,"StoneWalk",paving.commit(),vertex_material(),true)
	var map_platforms: Array[PackedVector3Array] = []
	for polygon: PackedVector2Array in platforms:
		var lifted: PackedVector3Array = PackedVector3Array()
		for point: Vector2 in polygon:
			lifted.append(Geo.surface(up,point,radius).normalized())
		map_platforms.append(lifted)
	var map_coast: PackedVector3Array = PackedVector3Array()
	for point: Vector2 in coast:
		map_coast.append(Geo.surface(up,point,radius).normalized())
	grove.set_meta("layout_version",Plan.LAYOUT_VERSION)
	grove.set_meta("cartography_paths",paths)
	grove.set_meta("cartography_platforms",map_platforms)
	grove.set_meta("cartography_coast",map_coast)

static func vertex_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = Geo.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	return material

static func build_overlook_rails(grove: Node3D,up: Vector3,radius: float) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for polygon: PackedVector2Array in Plan.overlook_guard_paths():
		# The final edge is the fully open connection to the loop, not a railing.
		for i: int in range(polygon.size()-1):
			var a: Vector3 = Geo.surface(up,polygon[i],radius).normalized()
			var b: Vector3 = Geo.surface(up,polygon[i+1],radius).normalized()
			for height: float in [.72,1.24]:
				Timber.beam(st,a*(radius+height),b*(radius+height),.075,.09,Color("7d6158"))
		for point: Vector2 in polygon:
			var normal: Vector3 = Geo.surface(up,point,radius).normalized()
			Timber.beam(st,normal*(radius+.18),normal*(radius+1.33),.105,.105,Color("9b7965"))
	var rails: MeshInstance3D = Geo.mesh_node(grove,"OverlookGuardrails",st.commit(),vertex_material(),true)
	(rails.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8

static func build_entry_sign(builder: SceneTree,grove: Node3D,up: Vector3,radius: float) -> void:
	var position: Vector2 = Plan.lights(radius)[0]
	var sign_anchor: Node3D = garden_anchor(grove,up,position+Vector2(-.35,.35),radius,.16)
	sign_anchor.name = "GardenArrivalSign"
	# Aim the board from its own offset toward the arriving reader. The entry
	# route's direction is different from this sign-to-reader direction.
	var normal: Vector3=sign_anchor.position.normalized()
	var arrival: Vector3=Plan.bridge_finish().slerp(Plan.bridge_start(),.30).normalized()
	var near_reader: Vector3=(Plan.bridge_finish()*radius-sign_anchor.position).slide(normal).normalized()
	var far_reader: Vector3=(Plan.bridge_finish().slerp(Plan.bridge_start(),.60)*radius-sign_anchor.position).slide(normal).normalized()
	var facing: Vector3=(near_reader+far_reader).normalized()
	sign_anchor.basis=Basis(normal.cross(facing).normalized(),normal,facing)
	sign_anchor.set_meta("front_reader_normal",arrival)
	sign_anchor.set_meta("lettering","櫻花庭園")
	builder.call("small_box",sign_anchor,"SignPost",Vector3(0,.62,0),Vector3(.085,1.24,.085),Color("705c53"))
	builder.call("small_box",sign_anchor,"GardenNameBoard",Vector3(0,1.18,0),Vector3(.96,.40,.10),Color("70584b"))
	var font: Font=load("res://assets/fonts/NotoSansTC.ttf") as Font
	for side: float in [1.0,-1.0]:
		var label: Label3D = Label3D.new()
		label.name="BridgeFacingLettering" if side>0.0 else "GardenFacingLettering"
		label.text = "櫻花庭園"
		label.font=font
		label.font_size = 64
		label.pixel_size = .0022
		label.position = Vector3(0,1.18,side*.053)
		label.rotation.y=0.0 if side>0.0 else PI
		label.billboard=BaseMaterial3D.BILLBOARD_DISABLED
		label.double_sided=false
		label.no_depth_test=false
		label.outline_size=0
		label.modulate = Color("f4e8cb")
		sign_anchor.add_child(label)

static func refine_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node as MeshInstance3D
		for i: int in range(mi.mesh.get_surface_count()):
			var src: StandardMaterial3D = mi.get_active_material(i) as StandardMaterial3D
			if src != null and src.albedo_texture != null:
				var mat: StandardMaterial3D = src.duplicate() as StandardMaterial3D
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
				mat.alpha_scissor_threshold = 0.38
				mat.cull_mode = BaseMaterial3D.CULL_DISABLED
				mat.albedo_color = Color(1.0,.97,1.0)
				# Botanical texture already carries fine petal shading. Uniform soft
				# lighting avoids dark card backs and preserves its pale blossom color.
				mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mat.roughness = 1.0
				mat.metallic_specular = 0.1
				mat.backlight_enabled = true
				mat.backlight = Color(.32,.19,.23)
				mi.set_surface_override_material(i,mat)
			elif src != null:
				var mat: StandardMaterial3D = src.duplicate() as StandardMaterial3D
				mat.vertex_color_use_as_albedo = true
				mat.albedo_color = Color.WHITE
				mi.set_surface_override_material(i,mat)
	for child: Node in node.get_children():
		refine_materials(child)

static func beam(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color, solid: bool = false) -> void:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = Vector3(width,width,a.distance_to(b))
	var node: MeshInstance3D = Geo.mesh_node(parent,"BridgeTimber",mesh,Geo.material(color))
	var middle: Vector3 = (a+b)*.5
	var hint: Vector3 = middle.normalized()
	if absf((b-a).normalized().dot(hint))>.95:
		hint = Geo.frame(hint).x
	node.transform = Transform3D(Basis.IDENTITY,middle).looking_at(b,hint)
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 8
		node.add_child(body)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var box: BoxShape3D = BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		body.add_child(shape)

static func bridge_height(t: float) -> float:
	# The deck height belongs to shared vertices, not to separate flat planks.
	# A gentle continuous arch meets both landings at precisely 0.26 m.
	return .26+1.12*t*(1.0-t)

static func bridge_sample(a: Vector3,b: Vector3,side_a: Vector3,side_b: Vector3,t: float,radius: float,lateral: float,offset: float = 0.0) -> Vector3:
	var normal: Vector3 = a.slerp(b,t).normalized()
	var side: Vector3 = side_a.lerp(side_b,t)
	return (normal*radius+side*lateral).normalized()*(radius+bridge_height(t)+offset)

static func bridge_strip(st: SurfaceTool,a: Vector3,b: Vector3,side_a: Vector3,side_b: Vector3,t0: float,t1: float,radius: float,count: int,color: Color) -> void:
	for j: int in range(count):
		var left: float = 2.7*(float(j)/count-.5)
		var right: float = 2.7*(float(j+1)/count-.5)
		var p0: Vector3 = bridge_sample(a,b,side_a,side_b,t0,radius,left)
		var p1: Vector3 = bridge_sample(a,b,side_a,side_b,t0,radius,right)
		var p2: Vector3 = bridge_sample(a,b,side_a,side_b,t1,radius,right)
		var p3: Vector3 = bridge_sample(a,b,side_a,side_b,t1,radius,left)
		Geo.triangle(st,p0,p1,p2,color)
		Geo.triangle(st,p0,p2,p3,color)

static func town_sidewalk_polygons(radius: float) -> Array[Dictionary]:
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var city: Dictionary={}
	for district: Dictionary in districts:
		if str(district.station)=="counseling":
			city=district
			break
	var routes: Array=[city.loop]
	routes.append_array(city.roads)
	var polygons: Array[Dictionary]=[]
	for route_index: int in range(routes.size()):
		var route: Array=routes[route_index]
		var closed: bool=route_index==0
		var normals: Array[Vector3]=[]
		for point: Array in route:
			normals.append(Geo.surface(Vector3.UP,Vector2(point[0],point[1]),radius).normalized())
		var sides: Array[Vector3]=Geo.path_sides(normals,closed)
		for i: int in range(normals.size() if closed else normals.size()-1):
			var next: int=(i+1)%normals.size()
			var count: int=maxi(1,ceili(normals[i].angle_to(normals[next])*radius/.3))
			var boundary: PackedVector3Array=PackedVector3Array()
			for sign_value: float in [-1.0,1.0]:
				for step: int in range(count+1):
					var t: float=float(step if sign_value<0.0 else count-step)/count
					var sample: Dictionary={"normal":normals[i].slerp(normals[next],t).normalized(),"side":sides[i].lerp(sides[next],t)}
					boundary.append(Timber.at(sample,radius,0.0,sign_value*3.15))
			var flat: PackedVector2Array=PackedVector2Array()
			for point: Vector3 in boundary:
				flat.append(Vector2(point.x,point.z)*radius/point.y)
			polygons.append({"flat":flat,"boundary":boundary})
	return polygons

static func town_rail_clear_of_sidewalk(sample: Dictionary,polygons: Array[Dictionary],radius: float) -> bool:
	# Test the actual mitered sidewalk footprint, not distance to its centreline:
	# the outside of the city corner extends beyond a round endpoint capsule.
	for sign_value: float in [-1.0,1.0]:
		var point: Vector3=Timber.at(sample,radius,0.0,sign_value*BRIDGE_RAIL_OFFSET)
		var local: Vector2=Vector2(point.x,point.z)*radius/point.y
		for polygon: Dictionary in polygons:
			if Geometry2D.is_point_in_polygon(local,polygon.flat as PackedVector2Array):
				return false
			var boundary: PackedVector3Array=polygon.boundary as PackedVector3Array
			for i: int in range(boundary.size()):
				var closest: Vector3=Geometry3D.get_closest_point_to_segment(point,boundary[i],boundary[(i+1)%boundary.size()])
				if point.distance_to(closest)<.22:
					return false
	return true

static func build_bridge(builder: SceneTree, grove: Node3D, up: Vector3, radius: float) -> void:
	var bridge: Node3D = Node3D.new()
	bridge.name = "SakuraBridge"
	grove.add_child(bridge)
	var start: Vector3 = Plan.bridge_start()
	var finish: Vector3 = Plan.bridge_finish()
	var town: Vector3 = Plan.town_endpoint(radius)
	var normals: Array[Vector3] = [town,start,finish,up]
	var sides: Array[Vector3] = Geo.path_sides(normals)
	var cross_steps: int = ceili(2.7*maxf(sides[1].length(),sides[2].length())/.28)
	var count: int = ceili(start.angle_to(finish)*radius/.28)
	var deck: SurfaceTool = SurfaceTool.new()
	var structure: SurfaceTool = SurfaceTool.new()
	var rail: SurfaceTool = SurfaceTool.new()
	for st: SurfaceTool in [deck,structure,rail]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(count):
		var t0: float = float(i)/count
		var t1: float = float(i+1)/count
		var joint: float = lerpf(t0,t1,.96)
		var color: Color = Color("be9c79") if i%3 else Color("b39270")
		bridge_strip(deck,start,finish,sides[1],sides[2],t0,joint,radius,cross_steps,color)
		bridge_strip(deck,start,finish,sides[1],sides[2],joint,t1,radius,cross_steps,Color("8b735c"))
		for sign_value: float in [-1.0,1.0]:
			var p0: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t0,radius,sign_value*1.35)
			var p1: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t1,radius,sign_value*1.35)
			var p2: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t1,radius,sign_value*1.35,-.18)
			var p3: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t0,radius,sign_value*1.35,-.18)
			Timber.face(structure,p0,p1,p2,p3,Color("785f50"),sides[1]*sign_value)
	var post_count: int = ceili(start.angle_to(finish)*radius/1.4)
	for i: int in range(post_count+1):
		var t: float = float(i)/post_count
		for sign_value: float in [-1.0,1.0]:
			var bottom: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t,radius,sign_value*BRIDGE_RAIL_OFFSET,-.18)
			var top: Vector3 = bridge_sample(start,finish,sides[1],sides[2],t,radius,sign_value*BRIDGE_RAIL_OFFSET,1.08)
			Timber.beam(rail,bottom,top,.12,.12,Color("98765f"))
			Timber.beam(rail,top,top.normalized()*(top.length()+.045),.15,.15,Color("ccb18a"))
			Timber.beam(structure,bridge_sample(start,finish,sides[1],sides[2],t,radius,sign_value*1.30,-.10),bottom,.10,.10,Color("785f50"))
			if i < post_count:
				var next: float = float(i+1)/post_count
				for height: float in [.46,.97]:
					Timber.beam(rail,bridge_sample(start,finish,sides[1],sides[2],t,radius,sign_value*BRIDGE_RAIL_OFFSET,height),bridge_sample(start,finish,sides[1],sides[2],next,radius,sign_value*BRIDGE_RAIL_OFFSET,height),.075,.09,Color("795b52"))
	Geo.mesh_node(bridge,"Deck",deck.commit(),vertex_material(),true)
	Geo.mesh_node(bridge,"DeckFascia",structure.commit(),vertex_material())
	# One connected stone causeway shares the wooden bridge's entry miter.
	var approach: Array[Dictionary] = []
	var approach_count: int = ceili(town.angle_to(start)*radius/.28)
	for i: int in range(approach_count+1):
		var t: float = float(i)/approach_count
		approach.append({"normal":town.slerp(start,t).normalized(),"side":sides[0].lerp(sides[1],t),"cross_steps":cross_steps,"wet":false})
	Geo.mesh_node(bridge,"TownApproach",Timber.deck_mesh(approach,radius,.26,2.7,false),Geo.material(Color("c8bda8")),true)
	var sidewalks: Array[Dictionary]=town_sidewalk_polygons(radius)
	var rail_start_t: float=1.0
	for i: int in range(approach.size()):
		if town_rail_clear_of_sidewalk(approach[i],sidewalks,radius):
			rail_start_t=float(i)/approach_count
			break
	# The causeway begins inside a broad city sidewalk. Its dry landing stays
	# open across the street; paired guards begin only beyond both outer edges.
	var approach_posts: int = maxi(1,ceili(town.angle_to(start)*radius*(1.0-rail_start_t)/1.45))
	for i: int in range(approach_posts+1):
		var t: float = lerpf(rail_start_t,1.0,float(i)/approach_posts)
		var sample: Dictionary = {"normal":town.slerp(start,t).normalized(),"side":sides[0].lerp(sides[1],t)}
		for sign_value: float in [-1.0,1.0]:
			if i < approach_posts:
				Timber.beam(rail,Timber.at(sample,radius,.08,sign_value*BRIDGE_RAIL_OFFSET),Timber.at(sample,radius,1.34,sign_value*BRIDGE_RAIL_OFFSET),.12,.12,Color("98765f"))
				Timber.beam(rail,Timber.at(sample,radius,.10,sign_value*1.30),Timber.at(sample,radius,.08,sign_value*BRIDGE_RAIL_OFFSET),.10,.10,Color("98765f"))
				var next: float = lerpf(rail_start_t,1.0,float(i+1)/approach_posts)
				var next_sample: Dictionary = {"normal":town.slerp(start,next).normalized(),"side":sides[0].lerp(sides[1],next)}
				for height: float in [.72,1.23]:
					Timber.beam(rail,Timber.at(sample,radius,height,sign_value*BRIDGE_RAIL_OFFSET),Timber.at(next_sample,radius,height,sign_value*BRIDGE_RAIL_OFFSET),.075,.09,Color("795b52"))
	var rails: MeshInstance3D = Geo.mesh_node(bridge,"ContinuousGardenBridgeRails",rail.commit(),vertex_material(),true)
	(rails.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
	# GardenApproach is already part of the unioned StoneWalk mesh. This marker
	# preserves the authored connection without drawing a second overlapping slab.
	var garden_approach: Node3D = Node3D.new()
	garden_approach.name = "GardenApproach"
	garden_approach.set_meta("path_points",PackedVector3Array([finish,up]))
	bridge.add_child(garden_approach)
	bridge.set_meta("start",start)
	bridge.set_meta("finish",finish)
	bridge.set_meta("town",town)
	bridge.set_meta("garden",up)
	bridge.set_meta("deck_width",2.7)
	bridge.set_meta("usable_width",2.7)
	bridge.set_meta("guardrail_mounting","outside fascia with short brackets")
	bridge.set_meta("town_guardrail_start",town.slerp(start,rail_start_t).normalized())
	bridge.set_meta("town_guardrail_start_fraction",rail_start_t)
	bridge.set_meta("town_guardrail_clearance",.22)
	var report: Dictionary = builder.get("report")
	report["sakura_bridge"] = {"deck_width":2.7,"segments":count,"start":[start.x,start.y,start.z],"finish":[finish.x,finish.y,finish.z],"continuous_arch":true,"town_open_landing_length":town.angle_to(start)*radius*rail_start_t,"town_sidewalk_clearance":.22}
static func petals(builder: SceneTree, life: Node3D, up: Vector3) -> void:
	var radius: float = float(builder.get("radius"))
	var model: Node3D = (load("res://assets/scenery/sakura_petal.glb") as PackedScene).instantiate() as Node3D
	refine_materials(model)
	var source: MeshInstance3D = model.find_children("*","MeshInstance3D",true,false)[0] as MeshInstance3D
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "SakuraPetals"
	node.set_meta("centre",up)
	node.multimesh = MultiMesh.new()
	node.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	node.multimesh.mesh = source.mesh
	node.material_override = source.get_active_material(0)
	node.multimesh.instance_count = 128
	node.custom_aabb = AABB(Vector3.ONE*(-radius-6),Vector3.ONE*(radius+6)*2)
	life.add_child(node)
	# A light accumulation at the path margins anchors the falling petals.
	var ground: MultiMeshInstance3D = MultiMeshInstance3D.new()
	ground.name = "SettledBlossoms"
	ground.multimesh = MultiMesh.new()
	ground.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	ground.multimesh.mesh = source.mesh
	ground.material_override = source.get_active_material(0)
	ground.multimesh.instance_count = 180
	var placements: Array[Transform3D]=[]
	var walk_paths: Array[PackedVector3Array] = []
	for path: Array in Plan.paths(radius):
		walk_paths.append(lift_path(path,up,radius))
	var loop: Array = Plan.paths(radius)[1]
	for i: int in range(180):
		var progress: float = float(i)*(loop.size()-1)/180.0
		var index: int = mini(floori(progress),loop.size()-2)
		var a: Vector2 = Vector2(loop[index][0],loop[index][1])
		var b: Vector2 = Vector2(loop[index+1][0],loop[index+1][1])
		var tangent: Vector2 = (b-a).normalized()
		var side: Vector2 = Vector2(-tangent.y,tangent.x)
		var point: Vector2 = a.lerp(b,progress-index)+side*(1.34+float(i%3)*.06)*(-1.0 if i%2==0 else 1.0)
		var field: float = path_field(point,walk_paths,Plan.platforms(),up,radius)
		var height: float = .268 if field >= 0 else (.223 if field >= -.14 else .168)
		var n: Vector3 = Geo.surface(up,point,radius).normalized()
		placements.append(Transform3D(Geo.frame(n)*Basis(Vector3.UP,float(i)*.618),n*(radius+height)))
	ground.custom_aabb = node.custom_aabb
	ground.set_meta("placements",placements)
	ground.set_script(load("res://scripts/ecology_instances.gd"))
	life.get_parent().get_node("SakuraGrove").add_child(ground)
	model.free()

