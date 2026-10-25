extends SceneTree
const Biomes=preload("res://scripts/biome_geography.gd")
const Landforms=preload("res://tools/world_landforms.gd")
const Geo=preload("res://scripts/planet_geometry.gd")
func _initialize() -> void:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json"))
	var failures: Array=[]
	for index: int in range(data.size()):
		var nd: Array=layout.stations[index].normal
		var field: RefCounted=Landforms.new()
		field.call("configure",data[index],index,layout.radius,Vector3(nd[0],nd[1],nd[2]))
		for trail: Array in Biomes.spec(data[index].station).trails:
			for segment: int in range(trail.size()-1):
				var a: Vector2=Vector2(trail[segment][0],trail[segment][1])
				var b: Vector2=Vector2(trail[segment+1][0],trail[segment+1][1])
				for step: int in range(ceili(a.distance_to(b))+1):
					var p: Vector2=a.lerp(b,float(step)/float(ceili(a.distance_to(b))))
					if float(field.call("dry_distance",p))<.5: failures.append([data[index].station,p])
		if index==0:
			for step: int in range(101):
				var p: Vector2=Vector2(10,17.4).lerp(Vector2(205,205),float(step)/100.0)
				if float(field.call("dry_distance",p))>0 and float(field.call("height_at",p))>.18: failures.append(["Sakura approach height",p])
		if index==5:
			for p: Vector2 in [Vector2(31,4),Vector2(31,12),Vector2(29,5),Vector2(32,10),Vector2(33,4)]:
				print("TREE_CANDIDATE ",p," dry=",field.call("dry_distance",p)," clearance=",field.call("clearance",p))
	print("BIOME_ROUTE_FIELD ",JSON.stringify(failures))
	quit(0 if failures.is_empty() else 1)
