extends RefCounted

const Geo = preload("res://scripts/planet_geometry.gd")
const Biomes = preload("res://scripts/biome_geography.gd")
const Landforms = preload("res://tools/world_landforms.gd")
const OutdoorScale = preload("res://scripts/outdoor_scale.gd")

static func marker_position(tip: Vector2,forward: Vector2,info: Dictionary,terrain: RefCounted) -> Vector2:
	var side:=Vector2(-forward.y,forward.x)
	var original:=tip+side*2.1
	var campus_entrance: bool = str(info.station)=="universities" and tip.is_equal_approx(Vector2(-18,-16))
	var wetland_entrance: bool = str(info.station)=="wordking" and tip.is_equal_approx(Vector2(4,14))
	var harbor_entrance: bool = str(info.station)=="admissions" and tip.is_equal_approx(Vector2(16.5,-17))
	if not info.has("compact_coast_max") or not (campus_entrance or wetland_entrance or harbor_entrance): return original
	# A trail's side may be an existing town road on a small globe. Select a
	# dry shoulder for this campus entrance outside every protected road,
	# building and nature trail. Other previously verified markers stay put.
	var along_offsets: Array[float] = [0.0,2.5,-2.5]
	if wetland_entrance:
		along_offsets.append_array([5.0,7.5])
	for offset: float in [2.1,3.3,4.5,5.7,6.9,8.1]:
		for along: float in along_offsets:
			for direction: float in [1.0,-1.0]:
				var candidate:=tip+side*offset*direction+forward*along
				if float(terrain.call("dry_distance",candidate))<1.0: continue
				if float(terrain.call("clearance",candidate))<.6: continue
				if Biomes.trail_distance(candidate,info)<1.8: continue
				return candidate
	push_error("No clear trail marker shoulder for "+str(info.station)+" at "+str(tip))
	return original

static func build(builder: SceneTree, globe: Node3D) -> void:
	var layout: Dictionary = builder.get("layout")
	var districts: Array = builder.get("districts")
	var radius: float = float(layout.radius)
	var font: Font = load("res://assets/fonts/NotoSansTC.ttf") as Font
	for index: int in range(districts.size()):
		var info: Dictionary = districts[index]
		var spec: Dictionary = Biomes.spec(str(info.station))
		var values: Array = layout.stations[index].normal
		var up := Vector3(values[0],values[1],values[2]).normalized()
		var terrain: RefCounted = Landforms.new()
		terrain.call("configure",info,index,radius,up)
		var reserve: Node3D = globe.get_node("EcologicalReserves/Reserve_"+str(info.station)) as Node3D
		for trail: Array in spec.get("trails",[]):
			var length: float = 0.0
			for segment: int in range(trail.size()-1):
				length += Vector2(trail[segment][0],trail[segment][1]).distance_to(Vector2(trail[segment+1][0],trail[segment+1][1]))
			for end: bool in [false,true]:
				var tip: Array = trail[-1] if end else trail[0]
				var neighbor: Array = trail[-2] if end else trail[1]
				var point := Vector2(tip[0],tip[1])
				var forward := (Vector2(neighbor[0],neighbor[1])-point).normalized()
				point = marker_position(point,forward,info,terrain)
				var normal: Vector3 = Geo.surface(up,point,radius).normalized()
				var height: float = float(terrain.call("mesh_height_at",point))
				var z: Vector3 = (Geo.frame(up)*Vector3(forward.x,0,forward.y)).slide(normal).normalized()
				var sign_root := Node3D.new()
				sign_root.name = "TrailWaymarker"
				sign_root.transform = Transform3D(Basis(normal.cross(z),normal,z),normal*(radius+height-.10))
				reserve.add_child(sign_root)
				builder.call("small_box",sign_root,"SteelPost",Vector3(0,.6025,0),Vector3(.065,1.205,.065),Color("424a43"),true)
				builder.call("small_box",sign_root,"TrailNotice",Vector3(0,1.53,0),Vector3(1.25,.65,.07),Color("34483c"))
				var label := Label3D.new()
				label.text = "%s\n%s  ·  %d m" % [str(spec.name),"返程步道" if end else "自然步道",roundi(length*OutdoorScale.factor(layout))]
				label.font = font
				label.font_size = 36
				label.pixel_size = .0014
				label.position = Vector3(0,1.53,.041)
				label.outline_size = 0
				label.modulate = Color("e5e1ce")
				label.no_depth_test = false
				label.double_sided = false
				sign_root.add_child(label)
				var back: Label3D = label.duplicate() as Label3D
				back.name = "ReverseLettering"
				back.position.z = -.041
				back.rotation.y = PI
				sign_root.add_child(back)
