extends RefCounted

## Replace only the known noncolliding decorative planter prefab, and restyle
## the existing physical entrance markers. All arrival and collision stay put.
var _planters: Dictionary = {}
var _metal: StandardMaterial3D
var _soil: StandardMaterial3D
var _leaves: StandardMaterial3D
var _bronze: StandardMaterial3D
var planter_count: int = 0
var station_count: int = 0

func apply(root: Node3D) -> int:
	_prepare_materials()
	var changes: int = 0
	var candidates: Array[Node] = [root]
	candidates.append_array(root.find_children("*","Node3D",true,false))
	for node: Node in candidates:
		if node.has_meta("station_id") and node.has_node("Platform"):
			if int(node.get_meta("street_furniture_version",0)) >= 2: continue
			_station(node as Node3D)
			changes += 1
		elif node.get_class()=="Node3D" and str(node.name)=="planter" and node.has_node("planter2"):
			if node.has_meta("street_furniture_version"): continue
			# Exact source hierarchy, not an ambiguous substring match. A scenic
			# landmark or a colliding planter is never replaced by this rule.
			if not node.find_children("*","CollisionObject3D",true,false).is_empty(): continue
			_replace_planter(node as Node3D)
			changes += 1
	return changes

func _prepare_materials() -> void:
	if _metal != null: return
	_metal = StandardMaterial3D.new()
	_metal.resource_name = "MAT_Street_PowderCoatedBronze"
	_metal.albedo_color = Color("303b38")
	_metal.metallic = .55
	_metal.roughness = .58
	_soil = StandardMaterial3D.new()
	_soil.resource_name = "MAT_Street_PottingEarth"
	_soil.albedo_color = Color("302c23")
	_soil.roughness = 1.0
	_leaves = StandardMaterial3D.new()
	_leaves.resource_name = "MAT_Street_FineEvergreen"
	_leaves.albedo_color = Color.WHITE
	_leaves.vertex_color_use_as_albedo = true
	_leaves.roughness = .83
	_leaves.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bronze = StandardMaterial3D.new()
	_bronze.resource_name = "MAT_Street_AgedBrass"
	_bronze.albedo_color = Color("98866a")
	_bronze.metallic = .65
	_bronze.roughness = .55

func _station(station: Node3D) -> void:
	# The authored EntranceWayfinding already has a foot/post/panel and tested
	# side clearance. Keep that solid footprint; remove the obsolete floaters.
	for name: String in ["Beacon","LuminousRing"]:
		var old: Node3D = station.get_node_or_null(name) as Node3D
		if old != null:
			old.visible = false
			old.set_meta("street_furniture_source_preserved",true)
	var wayfinding: Node3D = station.get_node_or_null("EntranceWayfinding") as Node3D
	if wayfinding != null:
		for mesh: MeshInstance3D in wayfinding.find_children("*","MeshInstance3D",true,false):
			mesh.material_override = _bronze if str(mesh.name)=="MarkerPost" else _metal
	var label: Label3D = station.get_node_or_null("StationLabel") as Label3D
	if label != null:
		label.modulate = Color("e9e4d7")
		label.outline_modulate = Color("293333")
		label.outline_size = 0
		if wayfinding != null:
			for old_label: Label3D in wayfinding.find_children("*","Label3D",true,false):
				old_label.visible = false
				old_label.set_meta("street_furniture_source_preserved",true)
			var words: PackedStringArray = label.text.split("  ",false,1)
			label.text = "%s\n%s\n入口" % [words[0],str(station.get_meta("label",""))]
			label.font_size = 40
			label.pixel_size = .0023
			label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
			label.shaded = true
			label.double_sided = false
			label.no_depth_test = false
			label.transform = wayfinding.transform*Transform3D(Basis.IDENTITY,Vector3(0,1.54,.048))
			label.set_meta("physical_wayfinding_label",true)
			var back: Label3D = label.duplicate() as Label3D
			back.name = "StationLabelReverse"
			back.transform = wayfinding.transform*Transform3D(Basis(Vector3.UP,PI),Vector3(0,1.54,-.048))
			station.add_child(back)
	station.set_meta("street_furniture_version",2)
	station_count += 1

func _replace_planter(source: Node3D) -> void:
	var bounds: AABB = _bounds(source)
	var width: float = maxf(.40,bounds.size.x)
	var depth: float = maxf(.25,bounds.size.z)
	var key: String = "%0.3f:%0.3f" % [width,depth]
	if not _planters.has(key): _planters[key] = _planter_mesh(width,depth)
	var replacement: MeshInstance3D = MeshInstance3D.new()
	replacement.name = "FineLeafStreetPlanter"
	replacement.mesh = _planters[key] as ArrayMesh
	replacement.transform = source.transform
	replacement.set_meta("world_art_authored",true)
	replacement.set_meta("street_furniture_version",1)
	source.get_parent().add_child(replacement)
	source.visible = false
	source.set_meta("street_furniture_source_preserved",true)
	source.set_meta("street_furniture_version",1)
	# The old floating globular flowers share this exact prefab anchor.
	var flowers: Node3D = source.get_parent().get_node_or_null("FlowerBed") as Node3D
	if flowers != null:
		flowers.visible = false
		flowers.set_meta("street_furniture_source_preserved",true)
	planter_count += 1

func _bounds(node: Node, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result: AABB = AABB()
	if node is MeshInstance3D:
		result = transform*(node as MeshInstance3D).get_aabb()
	for child: Node in node.get_children():
		if not child is Node3D: continue
		var box: AABB = _bounds(child,transform*(child as Node3D).transform)
		if box.size.length_squared()>.0001: result = result.merge(box) if result.size.length_squared()>.0001 else box
	return result

func _planter_mesh(width: float, depth: float) -> ArrayMesh:
	var frame: SurfaceTool = SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dirt: SurfaceTool = SurfaceTool.new()
	dirt.begin(Mesh.PRIMITIVE_TRIANGLES)
	var foliage: SurfaceTool = SurfaceTool.new()
	foliage.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wall: float = .035
	for side: float in [-1.0,1.0]:
		_box(frame,Vector3(0,.18,side*(depth*.5-wall*.5)),Vector3(width,.29,wall))
		_box(frame,Vector3(side*(width*.5-wall*.5),.18,0),Vector3(wall,.29,depth-wall*2))
		_box(frame,Vector3(0,.333,side*(depth*.5-wall*.5)),Vector3(width+.006,.026,wall+.006))
		for x: float in [-1.0,1.0]: _box(frame,Vector3(x*width*.37,.025,side*depth*.33),Vector3(.055,.05,.055))
	_box(dirt,Vector3(0,.29,0),Vector3(width-.075,.035,depth-.075))
	# A single indexed foliage surface, shared across all matching planters.
	# Thin bending blades have lit geometry, avoiding extra transparent cards.
	for clump: int in range(7):
		var origin: Vector3 = Vector3((float(clump)/6.0-.5)*(width-.24),.307,sin(clump*2.4)*(depth*.26))
		for leaf: int in range(13):
			var phase: float = float(leaf)*2.399+clump*.4
			var reach: float = .11+.07*sin(leaf*3.1+clump)
			var height: float = .30+.16*(.5+.5*sin(leaf*1.7+clump*2.9))
			var outward: Vector3 = Vector3(cos(phase),0,sin(phase))
			var side: Vector3 = Vector3(-sin(phase),0,cos(phase))
			var color: Color = Color("526747").lightened(.12*sin(leaf*1.9+clump))
			for segment: int in range(3):
				var t0: float = float(segment)/3.0
				var t1: float = float(segment+1)/3.0
				var a: Vector3 = origin+Vector3.UP*height*t0+outward*reach*t0*t0
				var b: Vector3 = origin+Vector3.UP*height*t1+outward*reach*t1*t1
				var w0: float = .022*(1.0-t0)
				var w1: float = .022*(1.0-t1)
				_quad(foliage,a-side*w0,a+side*w0,b+side*w1,b-side*w1,color)
	var mesh: ArrayMesh = ArrayMesh.new()
	frame.set_material(_metal)
	frame.index()
	frame.commit(mesh)
	dirt.set_material(_soil)
	dirt.commit(mesh)
	foliage.set_material(_leaves)
	foliage.index()
	foliage.commit(mesh)
	return mesh

func _box(st: SurfaceTool, point: Vector3, size: Vector3) -> void:
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	st.append_from(box,0,Transform3D(Basis.IDENTITY,point))

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var normal: Vector3 = (c-a).cross(b-a).normalized()
	for point: Vector3 in [a,b,c,a,c,d]:
		st.set_normal(normal)
		st.set_color(color)
		st.add_vertex(point)
