extends RefCounted

## Runtime facade kit for existing authored parcels. Source models remain in
## their original hierarchy; navigation, foundations and building addresses are
## never moved. Only verified human-scale building wrappers are replaced.
const TEXTURES: String = "res://assets/university_hall/textures/"
const STYLE_VERSION: int = 2
var _materials: Dictionary = {}
var _meshes: Dictionary = {}
var building_count: int = 0

func apply(root: Node3D) -> int:
	var changed: int = 0
	# Snapshot before mutation so the new kit cannot become an input candidate.
	var candidates: Array[Node] = [root]
	candidates.append_array(root.find_children("*", "Node3D", true, false))
	for node: Node in candidates:
		var wrapper: Node3D = node as Node3D
		if wrapper == null or wrapper.has_meta("world_architecture_version") or not wrapper.has_node("Foundation"):
			continue
		var foundation: MeshInstance3D = wrapper.get_node("Foundation") as MeshInstance3D
		if foundation == null or not foundation.mesh is BoxMesh:
			continue
		for child: Node in wrapper.get_children():
			if child is Node3D and child.has_meta("human_scale_frontage"):
				var frontage: Dictionary = child.get_meta("human_scale_frontage") as Dictionary
				var asset: String = str(frontage.get("asset", ""))
				if not bool(frontage.get("applied",false)) or not (asset.begins_with("commercial/") or asset.begins_with("suburban/") or asset.begins_with("suburban-edited/")):
					continue
				_replace(wrapper, child as Node3D, foundation, frontage)
				changed += 1
				break
	building_count += changed
	return changed

func _replace(wrapper: Node3D, source: Node3D, foundation: MeshInstance3D, frontage: Dictionary) -> void:
	# Width/depth come from the authored foundation, NOT the potentially broken
	# source mesh. Height is the source recipe's human-scale envelope. Disjoint
	# pieces from the old frontage remap therefore cannot infect this new shell.
	var parcel: Vector3 = (foundation.mesh as BoxMesh).size
	var width: float = maxf(1.5,parcel.x-.5)
	var depth: float = maxf(1.5,parcel.z-.5)
	var height: float = clampf(float(frontage.get("height",5.4)),2.8,13.0)
	var asset: String = str(frontage.asset)
	var residential: bool = asset.begins_with("suburban")
	var door_values: Array = frontage.get("refined_door_centre",[0.0,0.0,0.0])
	var original_door: Vector3 = source.transform*Vector3(door_values[0],door_values[1],door_values[2])
	var door_x: float = clampf(original_door.x,-width*.5+.66,width*.5-.66)
	var palette: int = _district_palette(wrapper)*3+posmod(asset.hash()+roundi(wrapper.position.x*3.0),3)
	var door_depth: float = clampf(depth*.5-.055-original_door.z,.10,depth*.8)
	var key: String = "%0.3f:%0.3f:%0.3f:%0.3f:%0.3f:%d:%d" % [width,depth,height,door_x,door_depth,int(residential),palette]
	if not _meshes.has(key):
		_meshes[key] = _building_mesh(width,depth,height,door_x,door_depth,residential,palette)
	var replacement: MeshInstance3D = MeshInstance3D.new()
	replacement.name = "ArchitecturalEnvelope"
	replacement.mesh = _meshes[key] as ArrayMesh
	replacement.set_meta("world_art_authored",true)
	replacement.set_meta("world_architecture_envelope",Vector3(width,height,depth))
	replacement.set_meta("original_door_position",original_door)
	replacement.set_meta("architecture_family","slate_roof_residence" if residential else "masonry_civic")
	replacement.set_meta("camera_visual_group",wrapper.get_meta("camera_visual_group",""))
	# The entire wall/window/roof kit is a single mesh, so obstruction fades can
	# never remove a floor while leaving a detached roof floating in space.
	wrapper.add_child(replacement)
	source.visible = false
	source.set_meta("world_architecture_source_preserved",true)
	foundation.material_override = _material("stone_dark",Color("66665f"),.88)
	wrapper.set_meta("world_architecture_version",STYLE_VERSION)

func _district_palette(wrapper: Node3D) -> int:
	var position: Vector3 = wrapper.global_position if wrapper.is_inside_tree() else wrapper.position
	var axes: Array[Vector3] = preload("res://scripts/world_routes.gd").directions()
	var best: float = -INF
	var result: int = 0
	for i: int in range(axes.size()):
		var score: float = position.dot(axes[i])
		if score > best:
			best = score
			result = i
	return result

func _material(kind: String, color: Color, roughness: float) -> StandardMaterial3D:
	var key: String = kind+color.to_html()+str(roughness)
	if _materials.has(key): return _materials[key] as StandardMaterial3D
	var result: StandardMaterial3D = StandardMaterial3D.new()
	result.resource_name = "MAT_Architecture_"+kind
	result.albedo_color = color
	result.roughness = roughness
	result.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if kind in ["stone","stone_dark","plaster"]:
		result.albedo_texture = load(TEXTURES+kind+"_base.png") as Texture2D
		result.roughness_texture = load(TEXTURES+kind+"_rough.png") as Texture2D
		result.normal_enabled = true
		result.normal_texture = load(TEXTURES+kind+"_normal.png") as Texture2D
		result.normal_scale = .14
		result.uv1_triplanar = true
		result.uv1_scale = Vector3.ONE*.55
	elif kind == "metal":
		result.metallic = .68
		result.metallic_specular = .5
	elif kind == "glass":
		# Opaque reflective panes keep the Web compatibility renderer stable.
		result.metallic = .45
		result.metallic_specular = .8
	_materials[key] = result
	return result

func _building_mesh(width: float, depth: float, height: float, door_x: float, door_depth: float, residential: bool, palette: int) -> ArrayMesh:
	# Six distinct but related mineral palettes: civic limestone, harbour slate,
	# warm terracotta research quarter, campus grey, woodland sage, sandstone.
	var colors: Array[Color] = [Color("aaa496"),Color("849698"),Color("a07160"),Color("b1b0a4"),Color("8a9681"),Color("a88e6a")]
	var district: int = palette/3
	var tint: Color = colors[district].lightened(float(palette%3-1)*.065)
	var plaster: Color = tint.lerp(Color("b9b4a7"),.22)
	var materials: Array[Material] = [_material("stone",tint,.92),_material("plaster",plaster,.94),_material("metal",Color("303b3c"),.48),_material("glass",Color("3c5058"),.21),_material("stone_dark",Color("515957"),.88)]
	var tools: Array[SurfaceTool] = []
	for _i: int in range(materials.size()):
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools.append(st)
	var roof_height: float = clampf(height*.17,.6,1.25) if residential else .3
	var wall_top: float = height-roof_height
	var floors: int = maxi(1,roundi(wall_top/2.85))
	var floor_height: float = wall_top/float(floors)
	# Load-bearing walls are continuous from the plinth to the roof. Openings
	# are explicitly framed, rather than cutting/displacing source triangles.
	for side: int in range(4):
		var yaw: float = float(side)*PI*.5
		var face_basis: Basis = Basis(Vector3.UP,yaw)
		var face_width: float = width if side%2 == 0 else depth
		var face_depth: float = depth if side%2 == 0 else width
		var face: Transform3D = Transform3D(face_basis,face_basis*Vector3(0,0,face_depth*.5-.055))
		_facade(tools,face,face_width-.11,wall_top,floors,floor_height,side==0,door_x,door_depth,residential,palette)
	# Heavy stone foot and a thin shadow course tie all elevations together.
	_box(tools[4],Vector3(0,.10,0),Vector3(width-.025,.20,depth-.025))
	_box(tools[0],Vector3(0,wall_top-.10,0),Vector3(width,.20,depth))
	if residential:
		_roof(tools[4],width,depth,wall_top,height)
		# A restrained ridge and chimney have a physical connection to the roof.
		_box(tools[2],Vector3(0,height-.028,0),Vector3(.08,.056,depth-.05))
		var chimney_height: float = roof_height*.62
		_box(tools[0],Vector3(-width*.29,wall_top+chimney_height*.5,-depth*.27),Vector3(.30,chimney_height,.35))
	else:
		_box(tools[4],Vector3(0,wall_top+.04,0),Vector3(width-.20,.08,depth-.20))
		for side: float in [-1.0,1.0]:
			_box(tools[0],Vector3(0,height-.11,side*(depth*.5-.07)),Vector3(width,.22,.14))
			_box(tools[0],Vector3(side*(width*.5-.07),height-.11,0),Vector3(.14,.22,depth-.28))
			_box(tools[2],Vector3(0,height-.012,side*(depth*.5-.07)),Vector3(width,.024,.145))
		# Setback rooftop equipment is low and enclosed by the parapet.
		_box(tools[2],Vector3(-width*.2,wall_top+.13,-depth*.18),Vector3(width*.22,.18,depth*.27))
	var mesh: ArrayMesh = ArrayMesh.new()
	for i: int in range(tools.size()):
		tools[i].set_material(materials[i])
		tools[i].index()
		tools[i].generate_tangents()
		tools[i].commit(mesh)
	return mesh

func _facade(tools: Array[SurfaceTool], face: Transform3D, width: float, height: float, floors: int, floor_height: float, front: bool, door_x: float, door_depth: float, residential: bool, style: int) -> void:
	var columns: int = maxi(1,floori(width/1.75))
	for floor_index: int in range(floors):
		var bottom: float = floor_index*floor_height
		var wall: SurfaceTool = tools[0] if floor_index==0 or not residential else tools[1]
		var bays: Array[Vector2] = []
		if front and floor_index==0:
			# A dedicated, nonuniform entrance bay preserves the existing door X;
			# other windows are subordinate to that real street-facing address.
			bays = [Vector2(-width*.5,door_x-.65),Vector2(door_x-.65,door_x+.65),Vector2(door_x+.65,width*.5)]
		else:
			for column: int in range(columns):
				bays.append(Vector2(-width*.5+column*width/columns,-width*.5+(column+1)*width/columns))
		for bay_index: int in range(bays.size()):
			var bay: Vector2 = bays[bay_index]
			var bay_width: float = bay.y-bay.x
			var x: float = (bay.x+bay.y)*.5
			var entrance: bool = front and floor_index==0 and bay_index==1
			if bay_width < .75 and not entrance:
				_box(wall,Vector3(x,bottom+floor_height*.5,-.11),Vector3(bay_width,floor_height,.22),face)
				continue
			var opening_width: float = minf(bay_width-.34,1.15 if entrance else 1.12)
			var opening_bottom: float = .04 if entrance else bottom+.83
			var opening_height: float = 2.16 if entrance else minf(1.45,floor_height-1.25)
			var opening_top: float = opening_bottom+opening_height
			# Each bay retains two jambs plus lintel/sill panels. All walls have
			# thickness and the dark window is recessed 8 cm into the opening.
			var pier: float = (bay_width-opening_width)*.5
			for sign_value: float in [-1.0,1.0]:
				_box(wall,Vector3(x+sign_value*(opening_width*.5+pier*.5),bottom+floor_height*.5,-.11),Vector3(pier,floor_height,.22),face)
			if opening_bottom > bottom:
				_box(wall,Vector3(x,(bottom+opening_bottom)*.5,-.11),Vector3(opening_width,opening_bottom-bottom,.22),face)
			_box(wall,Vector3(x,(opening_top+bottom+floor_height)*.5,-.11),Vector3(opening_width,bottom+floor_height-opening_top,.22),face)
			var pane_z: float = -door_depth if entrance else -.10
			_box(tools[2],Vector3(x,opening_bottom+opening_height*.5,pane_z),Vector3(opening_width,opening_height,.075),face)
			_box(tools[3],Vector3(x,opening_bottom+opening_height*.5,pane_z+.043),Vector3(opening_width-.105,opening_height-.10,.014),face)
			_box(tools[2],Vector3(x,opening_bottom+opening_height*.5,pane_z+.063),Vector3(.042,opening_height,.043),face)
			_box(tools[2],Vector3(x,opening_bottom+opening_height*.58,pane_z+.063),Vector3(opening_width,.038,.043),face)
			_box(tools[0],Vector3(x,maxf(.035,opening_bottom-.035),.003),Vector3(opening_width+.16,.07,.105),face)
			if entrance:
				for sign_value: float in [-1.0,1.0]:
					_box(wall,Vector3(x+sign_value*(opening_width*.5+.055),opening_height*.5,-door_depth*.5),Vector3(.11,opening_height,door_depth),face)
				_box(wall,Vector3(x,opening_top+.055,-door_depth*.5),Vector3(opening_width,.11,door_depth),face)
				# Compact cantilever entirely inside the original parcel envelope.
				_box(tools[2],Vector3(x,opening_top+.12,-.06),Vector3(opening_width+.30,.08,.21),face)
				_box(tools[2],Vector3(x+.14,1.06,pane_z+.081),Vector3(.025,.29,.026),face)
			else:
				_box(tools[0],Vector3(x,opening_top+.035,.003),Vector3(opening_width+.12,.07,.10),face)
				# Separate architectural families through practical facade details:
				# residential shutters, civic brise-soleil and recessed sill courses.
				if residential and style%3!=1:
					for side: float in [-1.0,1.0]:
						var shutter_x: float = x+side*(opening_width*.5+.13)
						_box(tools[2],Vector3(shutter_x,opening_bottom+opening_height*.5,.025),Vector3(.18,opening_height,.055),face)
						for slat: int in range(8):
							_box(tools[4],Vector3(shutter_x,opening_bottom+.1+slat*(opening_height-.2)/7.0,.063),Vector3(.155,.035,.035),face)
				elif not residential and style%3==0 and floor_index>0:
					for slat: int in range(3):
						_box(tools[2],Vector3(x,opening_top+.10+slat*.065,.055+slat*.055),Vector3(opening_width+.20,.025,.055),face)
				elif not residential and style%3==2:
					for side: float in [-1.0,1.0]:
						_box(tools[1],Vector3(x+side*(opening_width*.5+.10),opening_bottom+opening_height*.5,.025),Vector3(.045,opening_height+.14,.10),face)
			if floors == 1 and floor_height > 3.35:
				# Tall single-storey residences get a clerestory rather than a
				# featureless oversized upper wall above human-height windows.
				var high_width: float = minf(bay_width-.25,opening_width)
				var high_y: float = floor_height-.64
				_box(tools[2],Vector3(x,high_y,.009),Vector3(high_width,.58,.074),face)
				_box(tools[3],Vector3(x,high_y,.049),Vector3(high_width-.09,.49,.009),face)
				_box(tools[2],Vector3(x,high_y,.050),Vector3(.032,.54,.009),face)
		# Mortar-coloured belt and a darker recessed joint give a readable floor.
		if floor_index > 0:
			_box(tools[4],Vector3(0,bottom+.035,.005),Vector3(width,.055,.06),face)
	_box(tools[1],Vector3(-width*.5+.055,height*.5,-.015),Vector3(.11,height,.06),face)
	_box(tools[1],Vector3(width*.5-.055,height*.5,-.015),Vector3(.11,height,.06),face)

func _box(st: SurfaceTool, center: Vector3, size: Vector3, transform: Transform3D = Transform3D.IDENTITY) -> void:
	if minf(size.x,minf(size.y,size.z)) <= .0001: return
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	st.append_from(box,0,transform*Transform3D(Basis.IDENTITY,center))

func _roof(st: SurfaceTool, width: float, depth: float, bottom: float, top: float) -> void:
	# SurfaceTool.append_from(BoxMesh) uses indices. Append a separately indexed
	# roof surface; raw unindexed vertices after boxes would never be drawn.
	var roof: SurfaceTool = SurfaceTool.new()
	roof.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left: float = -width*.5
	var right: float = width*.5
	var back: float = -depth*.5
	var front: float = depth*.5
	_quad(roof,Vector3(left,bottom,back),Vector3(left,bottom,front),Vector3(0,top,front),Vector3(0,top,back))
	_quad(roof,Vector3(0,top,back),Vector3(0,top,front),Vector3(right,bottom,front),Vector3(right,bottom,back))
	_quad(roof,Vector3(left,bottom,front),Vector3(right,bottom,front),Vector3(0,top,front),Vector3(0,top,front))
	_quad(roof,Vector3(right,bottom,back),Vector3(left,bottom,back),Vector3(0,top,back),Vector3(0,top,back))
	roof.index()
	st.append_from(roof.commit(),0,Transform3D.IDENTITY)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var normal: Vector3 = (b-a).cross(c-a).normalized()
	var points: Array[Vector3] = [a,c,b,a,d,c]
	var uv: Array[Vector2] = [Vector2(0,0),Vector2(1,1),Vector2(0,1),Vector2(0,0),Vector2(1,0),Vector2(1,1)]
	for i: int in range(points.size()):
		st.set_normal(normal)
		st.set_uv(uv[i])
		st.add_vertex(points[i])
