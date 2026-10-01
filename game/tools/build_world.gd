extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Sakura = preload("res://tools/sakura_garden.gd")
const Ecology = preload("res://tools/ecology_world.gd")
const Urban = preload("res://tools/urban_design.gd")
const Infrastructure = preload("res://tools/world_infrastructure.gd")
const CivicFurniture = preload("res://tools/refine_civic_plazas.gd")
const Frontage = preload("res://tools/building_frontages.gd")
var radius: float = 36.0
var layout: Dictionary = {}
var districts: Array = []
var road_up: Vector3 = Vector3.UP
var active_station: String = "counseling"
var active_palette: String = ""
var report: Dictionary = {"assets": [], "roads": [], "stations": [], "landscapes": [], "districts": []}

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	districts = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	radius = float(layout.radius)
	if OS.get_cmdline_user_args().has("--districts-only"):
		report=JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
		for key: String in ["assets","roads","stations","landscapes","districts"]:
			report[key]=[]
		build_districts()
		build_stations()
		preload("res://tools/streaming_world_builder.gd").new().build()
		var output: FileAccess=FileAccess.open("res://generated/build_report.json",FileAccess.WRITE)
		output.store_string(JSON.stringify(report,"\t"))
		print("DISTRICTS_BUILD_OK")
		quit()
		return
	DirAccess.make_dir_recursive_absolute("res://generated/presets")
	DirAccess.make_dir_recursive_absolute("res://generated/districts")
	var globe: Node3D = Node3D.new()
	globe.name = "Globe"
	root.add_child(globe)
	var ocean: SphereMesh = SphereMesh.new()
	ocean.radius = radius
	ocean.height = radius * 2.0
	ocean.radial_segments = 128
	ocean.rings = 64
	var ocean_material: ShaderMaterial = ShaderMaterial.new()
	ocean_material.shader = load("res://shaders/ocean.gdshader") as Shader
	Geo.mesh_node(globe, "Ocean", ocean, ocean_material)
	var body: StaticBody3D = StaticBody3D.new()
	body.name = "PlanetCore"
	body.collision_layer = 2
	globe.add_child(body)
	var shape: CollisionShape3D = CollisionShape3D.new()
	var sphere: SphereShape3D = SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	body.add_child(shape)
	Ecology.build(self,globe)
	report["aquatic_habitats"] = preload("res://tools/water_ecology.gd").apply(globe,layout,districts)
	Infrastructure.bridges(globe,radius)
	build_sakura_and_sea(globe)
	Geo.save_scene(globe, "res://generated/globe.tscn")
	globe.queue_free()
	build_landscape_presets()
	build_districts()
	build_stations()
	refine_lighting()
	preload("res://tools/streaming_world_builder.gd").new().build()
	var file: FileAccess = FileAccess.open("res://generated/build_report.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("WORLD_BUILD_OK: globe, district, six stations and curved road collisions")
	quit()

func refine_lighting() -> void:
	var scene: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	var environment_node: WorldEnvironment = scene.get_node("Environment") as WorldEnvironment
	var environment: Environment = environment_node.environment.duplicate() as Environment
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(.86,.89,.93)
	environment.ambient_light_energy = .36
	environment_node.environment = environment
	(scene.get_node("Sun") as DirectionalLight3D).light_energy = .45
	(scene.get_node("Sun") as DirectionalLight3D).shadow_enabled = false
	(scene.get_node("Fill") as DirectionalLight3D).light_energy = .12
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(scene)==OK)
	assert(ResourceSaver.save(packed,"res://scenes/world.tscn")==OK)
	scene.free()

func vec(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func scenery_asset(parent: Node3D, file_name: String) -> Node3D:
	var instance: Node3D = (load("res://assets/scenery/"+file_name+".glb") as PackedScene).instantiate() as Node3D
	instance.name = file_name
	parent.add_child(instance)
	if file_name.begins_with("sakura_"):
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 8
		instance.add_child(body)
		var shape: CollisionShape3D = CollisionShape3D.new()
		var trunk: CapsuleShape3D = CapsuleShape3D.new()
		trunk.radius = 0.18
		trunk.height = 2.0
		shape.shape = trunk
		shape.position.y = 1.0
		body.add_child(shape)
	return instance

func build_sakura_and_sea(globe: Node3D) -> void:
	Sakura.build(self,globe)
	var up: Vector3 = Vector3(0.75,1.0,0.85).normalized()
	var life: Node3D = Node3D.new()
	life.name = "OceanLife"
	life.set_script(load("res://scripts/ocean_life.gd"))
	life.set_meta("radius",radius)
	globe.add_child(life)
	var index: int = 0
	for x: float in [-1.0,1.0]:
		for y: float in [-1.0,1.0]:
			for z: float in [-1.0,1.0]:
				if x > 0 and y > 0 and z > 0:
					continue
				var centre: Vector3 = Vector3(x,y,z).normalized()
				var name_list: Array[String] = ["liner","fishing_boat","tugboat"]
				var boat: Node3D = scenery_asset(life,name_list[index%3])
				boat.set_meta("centre",centre)
				boat.set_meta("kind","boat")
				boat.set_meta("phase",float(index)*0.9)
				boat.set_meta("travel",1.2 if index%3==1 else 3.2)
				boat.transform = Transform3D(Geo.frame(centre),centre*(radius+0.1))
				var fish_centre: Vector3 = (centre*radius+Geo.frame(centre).x*5.0).normalized()
				for fish_index: int in range(4):
					var fish: Node3D = scenery_asset(life,"fish_"+str(1+fish_index%2))
					fish.set_meta("centre",fish_centre)
					fish.set_meta("kind","fish")
					fish.set_meta("phase",float(index)*0.8-float(fish_index)*0.18)
					fish.set_meta("lane",float(fish_index)*0.55)
					fish.position = fish_centre*(radius-0.5)
				var ring: TorusMesh = TorusMesh.new()
				ring.inner_radius = 0.72
				ring.outer_radius = 0.75
				ring.rings = 24
				ring.ring_segments = 4
				var ripple: MeshInstance3D = Geo.mesh_node(life,"Wake",ring,Geo.material(Color("a6d4cc")))
				ripple.set_meta("centre",fish_centre)
				ripple.set_meta("kind","ripple")
				ripple.set_meta("phase",float(index)*0.8)
				index += 1
	Sakura.petals(self,life,up)
	report["boats"] = 7
	report["fish"] = 28

func bounds(node: Node, acc: Transform3D = Transform3D.IDENTITY) -> AABB:
	var spatial: Node3D = node as Node3D
	var trans: Transform3D = acc * spatial.transform if spatial != null else acc
	var box: AABB = AABB()
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null:
		box = trans * mi.get_aabb()
	for child: Node in node.get_children():
		var sub: AABB = bounds(child, trans)
		if sub.size.length_squared() > 0.0001:
			box = box.merge(sub) if box.size.length_squared() > 0.0001 else sub
	return box

func place_asset(parent: Node3D, row: Dictionary, up: Vector3 = Vector3.UP) -> void:
	var path: String = "res://assets/kenney/" + str(row.asset)
	var packed: PackedScene = load(path) as PackedScene
	assert(packed != null, path)
	var visual: Node3D = packed.instantiate() as Node3D
	var box: AABB = bounds(visual)
	var factor: float = float(row.height) / maxf(box.size.y, 0.01)
	if row.has("max_width"):
		factor = minf(factor,float(row.max_width)/box.size.x)
	if row.has("max_depth"):
		factor = minf(factor,float(row.max_depth)/box.size.z)
	var frontage: Dictionary = {"applied":false,"height":box.size.y*factor}
	if row.kind=="building":
		frontage=Frontage.refine(visual,box,factor,str(row.asset))
	var offset: Array = row.offset
	var n: Vector3 = Geo.surface(up, Vector2(offset[0], offset[1]), radius).normalized()
	var wrapper: Node3D = Node3D.new()
	wrapper.name = String(row.asset).get_file().get_basename()
	parent.add_child(wrapper)
	var base_height: float = radius + 0.17
	if row.kind == "building":
		base_height = radius + 0.55
		var slab: BoxMesh = BoxMesh.new()
		slab.size = Vector3(box.size.x * factor + 0.5, 0.85, box.size.z * factor + 0.5)
		var pedestal: MeshInstance3D = Geo.mesh_node(wrapper, "Foundation", slab, Geo.material(Color("8c9087")), true)
		pedestal.position.y = -0.425
	wrapper.transform = Transform3D(Basis(Quaternion(up,n))*Geo.frame(up)*Basis(Vector3.UP,deg_to_rad(float(row.yaw))), n * base_height)
	wrapper.add_child(visual)
	visual.scale = Vector3.ONE * factor
	visual.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * factor
	if str(row.asset).begins_with("commercial/"):
		visual.rotation.y = PI
	tint_model(visual, active_palette if str(row.asset).begins_with("suburban/") and row.kind == "building" else "")
	if row.kind == "building" or row.kind == "fence":
		add_model_collisions(visual)
	report.assets.append({"station":active_station,"path": path, "kind": row.kind, "up_dot": wrapper.basis.y.dot(n), "height": float(frontage.height), "scale": factor, "offset": row.offset, "yaw":row.yaw,"footprint":[box.size.x*factor,box.size.z*factor],"frontage":frontage})

func tint_model(node: Node, palette: String = "") -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null:
		for i: int in range(mi.mesh.get_surface_count()):
			var source: StandardMaterial3D = mi.get_active_material(i) as StandardMaterial3D
			if source != null:
				var adjusted: StandardMaterial3D = source.duplicate() as StandardMaterial3D
				# Preserve the source's separation between plaster, glazing and roofs.
				# The old green/black wash made all backlit facades blend together.
				adjusted.albedo_color *= Color(0.76, 0.78, 0.75)
				adjusted.roughness = 0.9
				adjusted.metallic_specular = 0.15
				var palette_path: String = "res://assets/kenney/suburban/Models/Textures/" + palette
				if palette != "" and ResourceLoader.exists(palette_path):
					adjusted.albedo_texture = load(palette_path) as Texture2D
				mi.set_surface_override_material(i, adjusted)
	for child: Node in node.get_children():
		tint_model(child, palette)

func add_model_collisions(node: Node) -> void:
	var mi: MeshInstance3D = node as MeshInstance3D
	if mi != null:
		mi.create_trimesh_collision()
		for child: Node in mi.get_children():
			if child is StaticBody3D:
				(child as StaticBody3D).collision_layer = 8
	for child: Node in node.get_children():
		if child is Node3D and not child is StaticBody3D:
			add_model_collisions(child)

func build_districts() -> void:
	var neighborhood: Node3D = Node3D.new()
	neighborhood.name = "Neighborhood"
	root.add_child(neighborhood)
	for i: int in range(districts.size()):
		var info: Dictionary = districts[i]
		active_station = str(info.station)
		active_palette = str(info.palette)
		road_up = vec(layout.stations[i].normal)
		build_district(i)
		var instance: Node3D = (load("res://generated/districts/" + active_station + ".tscn") as PackedScene).instantiate() as Node3D
		neighborhood.add_child(instance)
		instance.owner = neighborhood
	var packed: PackedScene = PackedScene.new()
	assert(packed.pack(neighborhood) == OK)
	assert(ResourceSaver.save(packed, "res://generated/neighborhood.tscn") == OK)
	neighborhood.queue_free()

func build_district(index: int) -> void:
	var district: Node3D = Node3D.new()
	district.name = active_station
	root.add_child(district)
	var design: RefCounted = Urban.new()
	design.call("build",self,district,index)
	Geo.save_scene(district, "res://generated/districts/" + active_station + ".tscn")
	district.queue_free()

func bend_road(parent: Node3D, tile: int, offset: Vector2, yaw: float) -> void:
	var path: String = "res://assets/kenney/roads/Models/gLTF/roadTile_%03d.gltf" % tile
	var packed: PackedScene = load(path) as PackedScene
	var instance: Node3D = packed.instantiate() as Node3D
	var mesh: ArrayMesh = ArrayMesh.new()
	# The source sidewalk has tapered verges at every tile end. Replace those
	# with a continuous curved bed while retaining the supplied asphalt/markings.
	var bed: SurfaceTool = SurfaceTool.new()
	bed.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = []
	for corner: Vector2 in [Vector2(-1.5,-1.5),Vector2(1.5,-1.5),Vector2(1.5,1.5),Vector2(-1.5,1.5)]:
		corners.append(Vector3(corner.x,0.58,corner.y).rotated(Vector3.UP,yaw) + Vector3(offset.x,0,offset.y))
	subdivide(bed,corners[0],corners[1],corners[2],0)
	subdivide(bed,corners[0],corners[2],corners[3],0)
	bed.set_material(Geo.material(Color("b8baa5")))
	bed.generate_normals()
	bed.commit(mesh)
	var meshes: Array[Node] = instance.find_children("*", "MeshInstance3D", true, false)
	for node: Node in meshes:
		var mi: MeshInstance3D = node as MeshInstance3D
		var trans: Transform3D = relative_transform(mi, instance)
		for surface_index: int in range(mi.mesh.get_surface_count()):
			var source_mat: StandardMaterial3D = mi.get_active_material(surface_index) as StandardMaterial3D
			var material_name: String = source_mat.resource_name.to_lower() if source_mat != null else ""
			if material_name not in ["asphalt", "frontcolor"]:
				continue
			var arrays: Array = mi.mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var st: SurfaceTool = SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			if indices.is_empty():
				for index: int in range(vertices.size()):
					indices.append(index)
			for index: int in range(0, indices.size(), 3):
				var triangle_points: Array[Vector3] = []
				for k: int in range(3):
					var point: Vector3 = trans * vertices[indices[index + k]]
					point += Vector3(-1.5, 0, 1.5)
					point = point.rotated(Vector3.UP, yaw) + Vector3(offset.x, 0, offset.y)
					triangle_points.append(point)
				if minf(triangle_points[0].y,minf(triangle_points[1].y,triangle_points[2].y)) < 0.59:
					continue
				subdivide(st, triangle_points[0], triangle_points[1], triangle_points[2], 0)
			var color: Color = Color("536b70") if material_name == "asphalt" else Color("e9dfc9")
			st.set_material(Geo.material(color))
			st.generate_normals()
			st.commit(mesh)
	Geo.mesh_node(parent, "CurvedRoad_%d_%d" % [int(offset.x), int(offset.y)], mesh, null, true)
	report.roads.append({"station":active_station,"up":[road_up.x,road_up.y,road_up.z],"tile":tile, "offset":[offset.x, offset.y], "yaw":yaw, "surfaces":mesh.get_surface_count(), "max_edge_before_projection":0.45})
	instance.free()

func relative_transform(node: Node3D, ancestor: Node3D) -> Transform3D:
	var result: Transform3D = node.transform
	var parent: Node = node.get_parent()
	while parent != ancestor and parent is Node3D:
		result = (parent as Node3D).transform * result
		parent = parent.get_parent()
	return ancestor.transform * result

func project_road(point: Vector3) -> Vector3:
	return Geo.frame(road_up) * Vector3(point.x, radius, point.z).normalized() * (radius - 0.28 + point.y)

func prefab_asset(parent: Node3D, asset: String, position: Vector3, height: float, yaw: float = 0.0) -> void:
	var packed: PackedScene = load("res://assets/kenney/suburban/Models/GLB format/" + asset + ".glb") as PackedScene
	var model: Node3D = packed.instantiate() as Node3D
	var box: AABB = bounds(model)
	var factor: float = height / maxf(box.size.y, 0.01)
	var anchor: Node3D = Node3D.new()
	anchor.name = asset
	parent.add_child(anchor)
	anchor.position = position
	anchor.rotation.y = yaw
	anchor.add_child(model)
	model.scale = Vector3.ONE * factor
	model.position = -Vector3(box.get_center().x,box.position.y,box.get_center().z) * factor
	tint_model(model)

func small_box(parent: Node3D, node_name: String, position: Vector3, size: Vector3, color: Color, solid: bool = false) -> MeshInstance3D:
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = size
	var node: MeshInstance3D = Geo.mesh_node(parent,node_name,mesh,Geo.material(color))
	node.position = position
	if solid:
		var body: StaticBody3D = StaticBody3D.new()
		body.collision_layer = 8
		node.add_child(body)
		var collision: CollisionShape3D = CollisionShape3D.new()
		var shape: BoxShape3D = BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)
	return node

func bench(parent: Node3D, position: Vector3, yaw: float) -> void:
	var node: Node3D = Node3D.new()
	node.name = "GardenBench"
	parent.add_child(node)
	node.position = position
	node.rotation.y = yaw
	var furniture: SurfaceTool = SurfaceTool.new()
	furniture.begin(Mesh.PRIMITIVE_TRIANGLES)
	CivicFurniture.bench(furniture,Transform3D.IDENTITY,Color("668079"))
	var wood_metal: StandardMaterial3D = Geo.material(Color.WHITE)
	wood_metal.vertex_color_use_as_albedo = true
	var mesh: MeshInstance3D = Geo.mesh_node(node,"SlattedSeat",furniture.commit(),wood_metal)
	CivicFurniture.collision(mesh,"SeatCollision",Transform3D.IDENTITY,Vector3(0,.48,.04),Vector3(1.58,.85,.53))

func flowers(parent: Node3D, position: Vector3, color: Color) -> void:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.075
	sphere.height = 0.09
	sphere.radial_segments = 6
	sphere.rings = 3
	sphere.material = Geo.material(color)
	var mesh: MultiMesh = MultiMesh.new()
	mesh.transform_format = MultiMesh.TRANSFORM_3D
	mesh.mesh = sphere
	mesh.instance_count = 15
	mesh.custom_aabb = AABB(Vector3(-0.8,-0.1,-0.6),Vector3(1.6,0.5,1.2))
	var placements: Array[Transform3D]=[]
	for i: int in range(15):
		var angle: float = float(i) * 2.4
		var distance: float = 0.13 + 0.04 * float(i)
		placements.append(Transform3D(Basis.IDENTITY,Vector3(cos(angle)*distance,0.12 + float(i%3)*0.035,sin(angle)*distance*0.7)))
	var node: MultiMeshInstance3D = MultiMeshInstance3D.new()
	node.name = "FlowerBed"
	node.multimesh = mesh
	node.position = position
	# The dummy headless renderer does not serialize MultiMesh transform buffers.
	# Metadata is authoritative and is uploaded by the real renderer on _ready.
	node.set_meta("placements",placements)
	node.set_script(load("res://scripts/ecology_instances.gd"))
	parent.add_child(node)

func lamp(parent: Node3D, position: Vector3) -> void:
	var node: Node3D = Node3D.new()
	node.name = "PathLantern"
	node.position = position
	parent.add_child(node)
	var pole: CylinderMesh = CylinderMesh.new()
	pole.top_radius = 0.035
	pole.bottom_radius = 0.055
	pole.height = 2.08
	pole.radial_segments = 8
	Geo.mesh_node(node,"Pole",pole,Geo.material(Color("48605b"))).position.y = 1.04
	var glow: CylinderMesh = CylinderMesh.new()
	glow.top_radius = .12
	glow.bottom_radius = .12
	glow.height = .23
	glow.radial_segments = 12
	Geo.mesh_node(node,"Lantern",glow,Geo.material(Color("e0cfab"),.18)).position.y = 2.15
	for level: float in [2.015,2.285]:
		var cap: CylinderMesh = CylinderMesh.new()
		cap.top_radius = .15
		cap.bottom_radius = .15
		cap.height = .055
		cap.radial_segments = 12
		Geo.mesh_node(node,"LanternCap",cap,Geo.material(Color("405550"))).position.y = level

func build_landscape_presets() -> void:
	for kind: String in ["garden","woodland","coast","courtyard"]:
		var preset: Node3D = Node3D.new()
		preset.name = kind
		root.add_child(preset)
		prefab_asset(preset,"tree-large",Vector3(-0.8,0,-0.5),2.7,0.5)
		prefab_asset(preset,"tree-small",Vector3(1.0,0,-0.8),1.8,1.8)
		if kind == "woodland":
			prefab_asset(preset,"tree-large",Vector3(0.8,0,1.0),3.4,2.0)
			flowers(preset,Vector3(-0.8,0,1.1),Color("c5b5df"))
		elif kind == "coast":
			bench(preset,Vector3(0,0,1.1),0)
			flowers(preset,Vector3(-1.3,0,0.5),Color("edd69c"))
		else:
			bench(preset,Vector3(0,0,1.1),0)
			prefab_asset(preset,"planter",Vector3(1.3,0,1.0),0.45)
			flowers(preset,Vector3(-1.25,0,1.0),Color("e9baad"))
			lamp(preset,Vector3(-1.4,0,-0.8))
			if kind == "courtyard":
				lamp(preset,Vector3(1.4,0,-0.8))
		flowers(preset,Vector3(0,0,-0.5),Color("f1e3b2"))
		Geo.save_scene(preset,"res://generated/presets/"+kind+".tscn")
		preset.queue_free()

func apply_landscape(parent: Node3D, kind: String, offset: Vector2, yaw: float, up: Vector3) -> void:
	var preset: PackedScene = load("res://generated/presets/"+kind+".tscn") as PackedScene
	var instance: Node3D = preset.instantiate() as Node3D
	instance.name = kind + "_landscape"
	parent.add_child(instance)
	for child: Node in instance.get_children():
		var spatial: Node3D = child as Node3D
		if spatial == null:
			continue
		var p: Vector3 = spatial.position.rotated(Vector3.UP,yaw)
		var normal: Vector3 = Geo.surface(up,offset+Vector2(p.x,p.z),radius).normalized()
		spatial.transform = Transform3D(Geo.frame(normal)*Basis(Vector3.UP,yaw)*spatial.basis,normal*(radius+0.16+p.y))
	report.landscapes.append({"station":active_station,"preset":kind,"offset":[offset.x,offset.y]})

func add_landmark(parent: Node3D, up: Vector3, accent: Color, index: int) -> void:
	var node: Node3D = Node3D.new()
	node.name = "DistrictLandmark"
	parent.add_child(node)
	var normal: Vector3 = Geo.surface(up,Vector2(4.4,8.6),radius).normalized()
	node.transform = Transform3D(Geo.frame(normal),normal*(radius+0.17))
	var plinth: CylinderMesh = CylinderMesh.new()
	plinth.top_radius = 0.85
	plinth.bottom_radius = 0.95
	plinth.height = 0.16
	plinth.radial_segments = 24
	Geo.mesh_node(node,"Plinth",plinth,Geo.material(Color("e4d2ae"))).position.y = 0.08
	if index in [0,1]:
		var orb: SphereMesh = SphereMesh.new()
		orb.radius = 0.34
		orb.height = 0.68
		orb.radial_segments = 16
		orb.rings = 8
		Geo.mesh_node(node,"Sculpture",orb,Geo.material(accent)).position.y = 1.1
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 0.5
		ring.outer_radius = 0.55
		ring.rings = 32
		ring.ring_segments = 6
		var orbit: MeshInstance3D = Geo.mesh_node(node,"Orbit",ring,Geo.material(Color("c4ac7b")))
		orbit.position.y = 1.1
		orbit.rotation_degrees = Vector3(35,0,25)
		small_box(node,"SculptureStand",Vector3(0,0.47,0),Vector3(0.22,0.7,0.22),Color("5a8077"),true)
	elif index in [2,5]:
		for i: int in range(4):
			var book: MeshInstance3D = small_box(node,"Book",Vector3(0,0.3+float(i)*0.23,0),Vector3(1.15,0.2,0.75),accent if i%2==0 else Color("e8d5a5"),true)
			book.rotation.y = float(i)*0.15
	elif index == 3:
		small_box(node,"ClockColumn",Vector3(0,1.4,0),Vector3(0.65,2.5,0.65),accent,true)
		var clock_face: CylinderMesh = CylinderMesh.new()
		clock_face.top_radius = 0.34
		clock_face.bottom_radius = 0.34
		clock_face.height = 0.06
		var clock: MeshInstance3D = Geo.mesh_node(node,"Clock",clock_face,Geo.material(Color("f3e9ce")))
		clock.position = Vector3(0,2.15,0.35)
		clock.rotation.x = PI*0.5
		small_box(node,"MinuteHand",Vector3(0,2.25,0.4),Vector3(0.035,0.22,0.025),Color("456760"))
		small_box(node,"HourHand",Vector3(0.07,2.15,0.4),Vector3(0.16,0.035,0.025),Color("456760"))
	else:
		for x: float in [-0.7,0.7]:
			for z: float in [-0.55,0.55]:
				small_box(node,"PergolaPost",Vector3(x,0.95,z),Vector3(0.1,1.9,0.1),Color("ad8b61"),true)
		for x: float in [-0.8,-0.4,0.0,0.4,0.8]:
			small_box(node,"PergolaSlat",Vector3(x,1.95,0),Vector3(0.18,0.1,1.5),Color("d0b78d"))

func subdivide(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, depth: int) -> void:
	if depth < 7 and maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) > 0.45:
		var ab: Vector3 = (a + b) * 0.5
		var bc: Vector3 = (b + c) * 0.5
		var ca: Vector3 = (c + a) * 0.5
		subdivide(st, a, ab, ca, depth + 1)
		subdivide(st, ab, b, bc, depth + 1)
		subdivide(st, ca, bc, c, depth + 1)
		subdivide(st, ab, bc, ca, depth + 1)
	else:
		for p: Vector3 in [a, b, c]:
			st.add_vertex(project_road(p))

func build_stations() -> void:
	var stations: Node3D = Node3D.new()
	stations.name = "Stations"
	root.add_child(stations)
	var font: FontVariation = FontVariation.new()
	font.base_font = load("res://assets/fonts/NotoSansTC.ttf") as Font
	font.variation_opentype = {2003265652:550.0}
	for i: int in range(layout.stations.size()):
		var row: Dictionary = layout.stations[i]
		var up: Vector3 = vec(row.normal)
		var normal: Vector3 = Geo.surface(up, Vector2(districts[i].civic[0],districts[i].civic[1]), radius).normalized()
		var station: Node3D = Node3D.new()
		station.name = str(row.id)
		station.set_meta("station_id", row.id)
		station.set_meta("label", row.label)
		stations.add_child(station)
		station.transform = Transform3D(Geo.frame(normal), normal * (radius + 0.18))
		var disk: CylinderMesh = CylinderMesh.new()
		disk.top_radius = 1.25
		disk.bottom_radius = 1.35
		disk.height = 0.12
		disk.radial_segments = 48
		Geo.mesh_node(station, "Platform", disk, Geo.material(Color("8c968d")), true).position.y = 0.06
		var ring: TorusMesh = TorusMesh.new()
		ring.inner_radius = 1.03
		ring.outer_radius = 1.12
		ring.rings = 48
		ring.ring_segments = 8
		Geo.mesh_node(station, "LuminousRing", ring, Geo.material(Color(str(row.color)).darkened(.2), .35)).position.y = 0.15
		var marker: SphereMesh = SphereMesh.new()
		marker.radius = 0.12
		marker.height = 0.24
		Geo.mesh_node(station, "Beacon", marker, Geo.material(Color(str(row.color)), .55)).position.y = 2.1
		var label: Label3D = Label3D.new()
		label.name = "StationLabel"
		label.text = "%02d  %s" % [i + 1, row.label]
		label.font = font
		label.font_size = 40
		label.pixel_size = 0.006
		label.position.y = 2.8
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.modulate = Color("fff4da")
		label.outline_modulate = Color("24494e")
		label.outline_size = 10
		station.add_child(label)
		report.stations.append({"id":row.id, "position":[station.position.x,station.position.y,station.position.z]})
	Geo.save_scene(stations, "res://generated/stations.tscn")
	stations.queue_free()
