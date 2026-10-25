extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Timber = preload("res://scripts/waterfront_routes.gd")
const Biome = preload("res://scripts/biome_geography.gd")
const OutdoorScale = preload("res://scripts/outdoor_scale.gd")

static func surface_tool() -> SurfaceTool:
	var result: SurfaceTool = SurfaceTool.new()
	result.begin(Mesh.PRIMITIVE_TRIANGLES)
	return result

static func finish(parent: Node3D,label: String,st: SurfaceTool,guard: bool = false) -> MeshInstance3D:
	var mat: StandardMaterial3D = Geo.material(Color.WHITE)
	mat.vertex_color_use_as_albedo = true
	var node: MeshInstance3D = Geo.mesh_node(parent,label,st.commit(),mat,guard)
	if guard:
		(node.get_node("SurfaceCollision") as StaticBody3D).collision_layer = 8
	return node

static func bridge_point(a: Vector3,b: Vector3,radius: float,t: float,lateral: float,height: float) -> Vector3:
	return (a.slerp(b,t)*radius+a.cross(b).normalized()*lateral).normalized()*(radius+height)

static func bridges(parent: Node3D,radius: float) -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var distance_scale: float = OutdoorScale.factor(layout)
	for edge: Vector2i in Routes.bridge_edges():
		var bridge: Node3D = Node3D.new()
		bridge.name = "Bridge_%d_%d" % [edge.x,edge.y]
		parent.add_child(bridge)
		var endpoints: Array[Vector3] = Routes.bridge_endpoints(edge,radius)
		var a: Vector3 = endpoints[0]
		var b: Vector3 = endpoints[1]
		bridge.set_meta("endpoints",PackedVector3Array([a,b]))
		var deck: MeshInstance3D = Geo.mesh_node(bridge,"Deck",Geo.ribbon(a,b,radius+.26,2.6),Geo.material(Color("999c96")),true)
		deck.set_meta("authored_surface","ConcreteBridgeDeck")
		var rails: SurfaceTool = surface_tool()
		var trim: SurfaceTool = surface_tool()
		var supports: SurfaceTool = surface_tool()
		var steps: int = ceili(a.angle_to(b)*radius/2.4)
		for i: int in range(steps+1):
			var t: float = float(i)/steps
			for side: float in [-1.0,1.0]:
				Timber.beam(rails,bridge_point(a,b,radius,t,side*1.21,.22),bridge_point(a,b,radius,t,side*1.21,1.35),.07,.085,Color("424e51"))
				if i < steps:
					for height: float in [.55,.9,1.3]:
						Timber.beam(rails,bridge_point(a,b,radius,t,side*1.21,height),bridge_point(a,b,radius,float(i+1)/steps,side*1.21,height),.045,.06,Color("5d6a6c"))
					Timber.beam(trim,bridge_point(a,b,radius,t,side*1.29,.10),bridge_point(a,b,radius,float(i+1)/steps,side*1.29,.10),.18,.30,Color("727d7c"))
			if i > 0 and i < steps:
				Timber.beam(trim,bridge_point(a,b,radius,t,-1.17,.266),bridge_point(a,b,radius,t,1.17,.266),.018,.008,Color("535c5b"))
			if i % 5 == 0:
				for side: float in [-1.0,1.0]:
					Timber.beam(supports,bridge_point(a,b,radius,t,side*1.42,-2.6),bridge_point(a,b,radius,t,side*1.42,.19),.46,.46,Color("6c7370"))
				Timber.beam(supports,bridge_point(a,b,radius,t,-1.65,-.14),bridge_point(a,b,radius,t,1.65,-.14),.36,.4,Color("666e6b"))
		finish(bridge,"ContinuousGuardrails",rails,true)
		finish(bridge,"DeckFasciaAndJoints",trim)
		finish(bridge,"MarinePiersAndCrossheads",supports)
		for side_index: int in range(2):
			var normal: Vector3 = a if side_index == 0 else b
			var other: Vector3 = b if side_index == 0 else a
			var direction: Vector3 = (other-normal*normal.dot(other)).normalized()
			var right: Vector3 = direction.cross(normal).normalized()
			var sign_root := Node3D.new()
			bridge.add_child(sign_root)
			sign_root.name = "RouteSign"+str(side_index)
			sign_root.transform = Transform3D(Basis(right,normal,-direction),normal*(radius+.26)+right*1.6)
			var post := BoxMesh.new()
			# End the support at the bottom edge of the board. The old .07 m
			# post protruded through the .055 m plate and in front of its text.
			post.size = Vector3(.07,1.225,.07)
			Geo.mesh_node(sign_root,"Post",post,Geo.material(Color("424e51"))).position.y = .6125
			var plate := BoxMesh.new()
			plate.size = Vector3(1.55,.55,.055)
			Geo.mesh_node(sign_root,"DestinationPlate",plate,Geo.material(Color("273a3d"))).position.y = 1.5
			var label := Label3D.new()
			label.font = load("res://assets/fonts/NotoSansTC.ttf") as Font
			label.text = "%02d  %s\n步行連橋  %d m" % [(edge.y if side_index==0 else edge.x)+1,["生涯諮詢所","落點分析所","選校研究所","大學展覽館","校園生活誌","英文訓練館"][edge.y if side_index==0 else edge.x],roundi(a.angle_to(b)*radius*distance_scale)]
			label.font_size = 40
			label.pixel_size = .0017
			label.position = Vector3(0,1.5,.033)
			label.outline_size = 0
			label.modulate = Color("ece9dc")
			label.no_depth_test = false
			label.double_sided = false
			sign_root.add_child(label)
			var back: Label3D = label.duplicate() as Label3D
			back.name = "ReverseLettering"
			back.position.z = -.033
			back.rotation.y = PI
			sign_root.add_child(back)

static func anchor(parent: Node3D,up: Vector3,p: Vector2,radius: float,height: float = .26) -> Node3D:
	var n: Vector3 = Geo.surface(up,p,radius).normalized()
	var node: Node3D = Node3D.new()
	parent.add_child(node)
	node.transform = Transform3D(Basis(Quaternion(up,n))*Geo.frame(up),n*(radius+height))
	return node

static func marina_mooring(info: Dictionary) -> Vector2:
	# Full-size 7.8 m workboat (8.23 m including its outboard), alongside the
	# outer pier. Reserve 5 m to shore so the stern also clears the dry bank.
	var index: int = Routes.IDS.find(str(info.station))
	var low: float = 32.0
	var high: float = 48.0
	for _i: int in range(24):
		var middle: float = (low+high)*.5
		if Biome.coast_distance(Vector2(middle,11.1),info,index)>-5.0: low=middle
		else: high=middle
	return Vector2(high,11.1)

static func marina(builder: SceneTree,parent: Node3D,up: Vector3,radius: float,info: Dictionary) -> void:
	var dock: Node3D = Node3D.new()
	dock.name = "Marina"
	parent.add_child(dock)
	var path: Array = [[32,6],[41,6]]
	var samples: Array[Dictionary] = Timber.samples(up,path,info,radius,5.4)
	for sample: Dictionary in samples:
		sample.wet = true
	var material: StandardMaterial3D = Geo.material(Color.WHITE)
	material.vertex_color_use_as_albedo = true
	Geo.mesh_node(dock,"TimberDeck",Timber.deck_mesh(samples,radius,.26,5.4,true),material,true)
	var polygon: PackedVector3Array = PackedVector3Array()
	for side: float in [-1.0,1.0]:
		var indices: Array = range(samples.size())
		if side > 0:
			indices.reverse()
		for i: int in indices:
			polygon.append(Timber.at(samples[i],radius,.26,side*2.7).normalized())
	dock.set_meta("map_polygons",[polygon])
	dock.set_meta("entry",samples[0].normal)
	dock.set_meta("end",samples[-1].normal)
	var rails: SurfaceTool = surface_tool()
	var trim: SurfaceTool = surface_tool()
	for side: float in [-1.0,1.0]:
		for i: int in range(samples.size()-1):
			for height: float in [.69,1.28]:
				Timber.beam(rails,Timber.at(samples[i],radius,height,side*2.6),Timber.at(samples[i+1],radius,height,side*2.6),.075,.105,Color("456563"))
			Timber.beam(trim,Timber.at(samples[i],radius,.15,side*2.65),Timber.at(samples[i+1],radius,.15,side*2.65),.16,.25,Color("827052"))
		for i: int in range(0,samples.size(),5):
			Timber.beam(rails,Timber.at(samples[i],radius,-.4,side*2.6),Timber.at(samples[i],radius,1.34,side*2.6),.16,.16,Color("9f835b"))
	var end: Dictionary = samples[-1]
	for height: float in [.69,1.28]:
		Timber.beam(rails,Timber.at(end,radius,height,-2.6),Timber.at(end,radius,height,2.6),.075,.105,Color("456563"))
	for side: float in [-1.0,0.0,1.0]:
		Timber.beam(rails,Timber.at(end,radius,-.4,side*2.6),Timber.at(end,radius,1.34,side*2.6),.16,.16,Color("9f835b"))
	finish(dock,"HarborGuardrails",rails,true)
	finish(dock,"DeckFascia",trim)
	for x: float in [34.5,39.0]:
		var seat: Node3D = anchor(dock,up,Vector2(x,3.85),radius)
		# Backrests sit beside the guard; seat fronts open onto the deck aisle.
		builder.call("bench",seat,Vector3.ZERO,PI)
		var bollard: Node3D = anchor(dock,up,Vector2(x,8.1),radius)
		builder.call("small_box",bollard,"MooringBase",Vector3(0,.06,0),Vector3(.35,.12,.32),Color("4b615e"))
		builder.call("small_box",bollard,"MooringBollard",Vector3(0,.25,0),Vector3(.13,.40,.13),Color("d7c18d"))
		builder.call("small_box",bollard,"MooringCleat",Vector3(0,.44,0),Vector3(.44,.09,.12),Color("d7c18d"))
	var entrance: Node3D = anchor(dock,up,Vector2(31.8,8),radius)
	builder.call("lamp",entrance,Vector3.ZERO)
	var notice: Node3D = Node3D.new()
	notice.name = "HarborNotice"
	entrance.add_child(notice)
	# Keep the existing board centre and lamp position. Rotate only the sign:
	# the real land approach arrives along +X, so its readable front faces -X.
	notice.position = Vector3(.65,1.03,0)
	notice.rotation.y = -PI*.5
	builder.call("small_box",notice,"HarborNoticeFrame",Vector3.ZERO,Vector3(.90,.72,.10),Color("2f5656"))
	var notice_font: Font = load("res://assets/fonts/NotoSansTC.ttf") as Font
	for side: float in [1.0,-1.0]:
		var notice_label: Label3D = Label3D.new()
		notice_label.name = "LandFacingLettering" if side>0.0 else "DockFacingLettering"
		notice_label.text = "曲岸碼頭\n散步 · 休憩 · 停泊"
		notice_label.font = notice_font
		notice_label.font_size = 48
		notice_label.pixel_size = .0015
		notice_label.position = Vector3(0,0,side*.055)
		notice_label.rotation.y = 0.0 if side>0.0 else PI
		notice_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
		notice_label.double_sided = false
		notice_label.no_depth_test = false
		notice_label.outline_size = 0
		notice_label.modulate = Color("f1e0b6")
		notice.add_child(notice_label)
	var ring_anchor: Node3D = anchor(dock,up,Vector2(40.9,6),radius)
	var ring: TorusMesh = TorusMesh.new()
	ring.inner_radius = .18
	ring.outer_radius = .29
	ring.rings = 24
	ring.ring_segments = 8
	var lifesaver: MeshInstance3D = Geo.mesh_node(ring_anchor,"LifeRing",ring,Geo.material(Color("dc914f")))
	lifesaver.position = Vector3(-.10,.76,0)
	lifesaver.rotation.z = PI*.5
	var mooring: Vector2 = marina_mooring(info)
	var boat_anchor: Node3D = anchor(dock,up,mooring,radius,.06)
	boat_anchor.name = "MooredFishingBoat"
	boat_anchor.set_meta("mooring_local",mooring)
	boat_anchor.set_meta("mooring_shore_clearance",5.0)
	var boat: Node3D = builder.call("scenery_asset",boat_anchor,"fishing_boat") as Node3D
	var bounds: AABB = builder.call("bounds",boat) as AABB
	boat.rotation.y = PI*.5
	# Vessels are authored in metres, with a waterline origin. Centre the
	# complete launch including its engine without shrinking human-height doors.
	boat.position = -(boat.basis*Vector3(bounds.get_center().x,0,bounds.get_center().z))
	var mooring_lines: SurfaceTool = surface_tool()
	var boat_cleats: Array[Vector3] = [Vector3(.92,.78,-3.24),Vector3(0,.86,3.10)]
	for i: int in range(2):
		var from: Vector3 = boat_anchor.transform*(boat.transform*boat_cleats[i])
		var to: Vector3 = Geo.surface(up,Vector2(34.5 if i==0 else 39.0,8.1),radius).normalized()*(radius+.70)
		for segment: int in range(8):
			var a_t: float = float(segment)/8.0
			var b_t: float = float(segment+1)/8.0
			var a: Vector3 = from.lerp(to,a_t)-from.normalized()*(sin(a_t*PI)*.11)
			var b: Vector3 = from.lerp(to,b_t)-from.normalized()*(sin(b_t*PI)*.11)
			Timber.beam(mooring_lines,a,b,.023,.023,Color("897b60"))
	finish(dock,"HarborMooringLines",mooring_lines)
	var report: Dictionary = builder.get("report")
	report["marina"] = {"guardrails":true,"moored_boats":1,"benches":2,"deck_width":5.4}
