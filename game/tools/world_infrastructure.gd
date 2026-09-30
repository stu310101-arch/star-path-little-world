extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Timber = preload("res://scripts/waterfront_routes.gd")

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
	var directions: Array[Vector3] = Routes.directions()
	var limits: Vector2 = Routes.bridge_limits()
	for edge: Vector2i in Routes.bridge_edges():
		var bridge: Node3D = Node3D.new()
		bridge.name = "Bridge_%d_%d" % [edge.x,edge.y]
		parent.add_child(bridge)
		var a: Vector3 = directions[edge.x].slerp(directions[edge.y],limits.x)
		var b: Vector3 = directions[edge.x].slerp(directions[edge.y],limits.y)
		bridge.set_meta("endpoints",PackedVector3Array([a,b]))
		Geo.mesh_node(bridge,"Deck",Geo.ribbon(a,b,radius+.26,2.6),Geo.material(Color("d9c7a6")),true)
		var rails: SurfaceTool = surface_tool()
		var trim: SurfaceTool = surface_tool()
		var steps: int = ceili(a.angle_to(b)*radius/1.45)
		for i: int in range(steps+1):
			var t: float = float(i)/steps
			for side: float in [-1.0,1.0]:
				Timber.beam(rails,bridge_point(a,b,radius,t,side*1.21,.22),bridge_point(a,b,radius,t,side*1.21,1.35),.12,.12,Color("5c706e"))
				if i < steps:
					for height: float in [.66,1.3]:
						Timber.beam(rails,bridge_point(a,b,radius,t,side*1.21,height),bridge_point(a,b,radius,float(i+1)/steps,side*1.21,height),.075,.10,Color("718c85"))
					Timber.beam(trim,bridge_point(a,b,radius,t,side*1.29,.19),bridge_point(a,b,radius,float(i+1)/steps,side*1.29,.19),.14,.25,Color("aa9270"))
			if i > 0 and i < steps:
				Timber.beam(trim,bridge_point(a,b,radius,t,-1.17,.266),bridge_point(a,b,radius,t,1.17,.266),.018,.008,Color("b9a98c"))
		finish(bridge,"ContinuousGuardrails",rails,true)
		finish(bridge,"DeckFasciaAndJoints",trim)

static func anchor(parent: Node3D,up: Vector3,p: Vector2,radius: float,height: float = .26) -> Node3D:
	var n: Vector3 = Geo.surface(up,p,radius).normalized()
	var node: Node3D = Node3D.new()
	parent.add_child(node)
	node.transform = Transform3D(Basis(Quaternion(up,n))*Geo.frame(up),n*(radius+height))
	return node

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
	var boat_anchor: Node3D = anchor(dock,up,Vector2(37,11.1),radius,.06)
	boat_anchor.name = "MooredFishingBoat"
	var boat: Node3D = builder.call("scenery_asset",boat_anchor,"fishing_boat") as Node3D
	var bounds: AABB = builder.call("bounds",boat) as AABB
	var factor: float = 4.2/maxf(bounds.size.x,bounds.size.z)
	boat.scale = Vector3.ONE*factor
	boat.position = -Vector3(bounds.get_center().x,0,bounds.get_center().z)*factor
	boat.rotation.y = PI*.5
	var report: Dictionary = builder.get("report")
	report["marina"] = {"guardrails":true,"moored_boats":1,"benches":2,"deck_width":5.4}
