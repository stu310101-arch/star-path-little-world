extends SceneTree

const Landforms=preload("res://tools/world_landforms.gd")
const Biomes=preload("res://scripts/biome_geography.gd")
const Geo=preload("res://scripts/planet_geometry.gd")
var failures: Array[String]=[]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var baked: bool=OS.get_cmdline_user_args().has("--baked")
	var globe: Node3D
	var space: PhysicsDirectSpaceState3D
	if baked:
		globe=(load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
		root.add_child(globe)
		await physics_frame
		await physics_frame
		space=globe.get_world_3d().direct_space_state
	var report: Dictionary={"districts":[],"baked":baked,"radius":layout.radius}
	for index: int in range(districts.size()):
		var data: Dictionary=districts[index]
		var nd: Array=layout.stations[index].normal
		var up: Vector3=Vector3(nd[0],nd[1],nd[2])
		var field: RefCounted=Landforms.new()
		field.call("configure",data,index,float(layout.radius),up)
		var maximum: float=0.0
		var max_slope: float=0.0
		var samples: int=0
		var missing_ground: int=0
		var max_error: float=0.0
		var mesh_height_probe: float=float(field.call("mesh_height_at",Vector2(112.3,101.9)))
		if not is_finite(mesh_height_probe): failures.append(str(data.station)+": invalid terrain interpolation")
		for x: int in range(-260,261,8):
			for y: int in range(-260,261,8):
				var p: Vector2=Vector2(float(x)+.19,float(y)+.27)
				if p.length()<48.0 or float(field.call("dry_distance",p))<6.0: continue
				var height: float=float(field.call("height_at",p))
				var n: Vector3=Geo.surface(up,p,float(layout.radius)).normalized()
				maximum=maxf(maximum,height)
				max_slope=maxf(max_slope,rad_to_deg(n.angle_to(field.call("normal_at",p) as Vector3)))
				if baked:
					var hit: Dictionary=Geo.ground_probe(space,n,float(layout.radius))
					if hit.is_empty(): missing_ground+=1
					elif not str((hit.collider as Node).get_path()).contains("Boardwalk"):
						max_error=maxf(max_error,absf((hit.position as Vector3).length()-float(layout.radius)-float(field.call("mesh_height_at",p))))
				samples+=1
		var trees: int=0
		for row: Dictionary in Biomes.tree_rows(data):
			var p: Vector2=row.p
			if float(field.call("dry_distance",p))>=7.0 and float(field.call("clearance",p))>=4.0 and Biomes.trail_distance(p,data)>=3.0: trees+=1
		if maximum<7.0: failures.append(str(data.station)+": missing outdoor landform height")
		if max_slope>35.0: failures.append(str(data.station)+": slope exceeds 35 degrees "+str(max_slope))
		if trees<55: failures.append(str(data.station)+": insufficient authored grove trees "+str(trees))
		if missing_ground>0: failures.append(str(data.station)+": missing ground "+str(missing_ground))
		if max_error>.18: failures.append(str(data.station)+": mesh/collision discrepancy "+str(max_error))
		report.districts.append({"station":data.station,"samples":samples,"maximum_height":maximum,"maximum_slope_degrees":max_slope,"authored_outdoor_trees":trees,"missing_ground":missing_ground,"max_collision_error":max_error,"mesh_height_probe":mesh_height_probe})
		print("BIOME_CHECK ",JSON.stringify(report.districts[-1]))
	report["passed"]=failures.is_empty()
	report["failures"]=failures
	FileAccess.open("res://../deliverables/world-redesign/biome-"+("baked" if baked else "source")+"-checks.json",FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	for failure: String in failures: push_error(failure)
	if globe!=null: globe.free()
	quit(0 if failures.is_empty() else 1)
