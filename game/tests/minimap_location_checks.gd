extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Minimap = preload("res://scripts/world_minimap.gd")
const Routes = preload("res://scripts/world_routes.gd")
const Sakura = preload("res://scripts/sakura_routes.gd")
var failures: int = 0
var checks: Array[Dictionary] = []

func check(title: String,passed: bool,detail: String = "") -> void:
	checks.append({"name":title,"passed":passed,"detail":detail})
	if not passed:
		failures += 1

func normal_at(up: Vector3,point: Vector2) -> Vector3:
	return Geo.surface(up,point,48.0).normalized()

func _initialize() -> void:
	var minimap: Control = Minimap.new() as Control
	minimap.size = Vector2(224,180)
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var directions: Array[Vector3] = Routes.directions()
	var patches: Array[Dictionary] = []
	for index: int in range(districts.size()):
		patches.append(minimap.call("build_patch",districts[index],index,directions[index]))
	var grove: Dictionary = minimap.call("build_sakura_patch")
	patches.append(grove)
	minimap.set("patches",patches)
	for index: int in range(districts.size()):
		var district: Dictionary = districts[index]
		var expected: String = str(district.theme)
		check("District centre keeps its region "+str(index),str(minimap.call("location_at",directions[index])) == expected)
		var visit: Vector2 = Vector2(float(district.visit[0]),float(district.visit[1]))
		check("Authored nature visit keeps its district "+str(index),str(minimap.call("location_at",normal_at(directions[index],visit))) == expected)
		var coast: PackedVector2Array = patches[index].local_coast as PackedVector2Array
		var boundaries_match: bool = true
		var tested: int = 0
		for point: Vector2 in coast:
			var position: Vector3 = normal_at(directions[index],point*.96)
			boundaries_match = boundaries_match and str(minimap.call("location_at",position)) == expected
			tested += 1
		check("Every near-coast sample retains district "+str(index),boundaries_match,str(tested)+" boundary samples")
	var life_visit: Vector3 = normal_at(directions[4],Vector2(-12,23))
	check("Life [-12,23] is inside life coast",bool(minimap.call("patch_contains_normal",patches[4],life_visit)))
	check("Life [-12,23] is outside Sakura coast",not bool(minimap.call("patch_contains_normal",grove,life_visit)))
	check("Life [-12,23] is never labelled Sakura",str(minimap.call("location_at",life_visit)) == str(districts[4].theme))
	check("Actual Sakura centre is Sakura",str(minimap.call("location_at",Sakura.grove_up())) == "櫻花林")
	check("Actual Sakura bridge garden landing is Sakura",str(minimap.call("location_at",Sakura.bridge_finish())) == "櫻花林")
	var sakura_edges_match: bool = true
	for point: Vector2 in Sakura.island_outline():
		sakura_edges_match = sakura_edges_match and str(minimap.call("location_at",normal_at(Sakura.grove_up(),point*.96))) == "櫻花林"
	check("All actual Sakura edge samples remain Sakura",sakura_edges_match)
	check("Sakura bridge town landing stays in counseling",str(minimap.call("location_at",Sakura.town_endpoint(48.0))) == str(districts[0].theme))
	for edge: Vector2i in Routes.bridge_edges():
		var start: String = str(minimap.call("location_at",directions[edge.x].slerp(directions[edge.y],Routes.bridge_limits().x)))
		var finish: String = str(minimap.call("location_at",directions[edge.x].slerp(directions[edge.y],Routes.bridge_limits().y)))
		var middle: String = str(minimap.call("location_at",directions[edge.x].slerp(directions[edge.y],.5)))
		check("Bridge labels follow its two real shores "+str(edge),start == str(districts[edge.x].theme) and finish == str(districts[edge.y].theme) and middle in [str(districts[edge.x].theme),str(districts[edge.y].theme)],start+" / "+middle+" / "+finish)
	minimap.call("update_map_frame",life_visit)
	var frame_before: Vector3 = minimap.get("map_forward") as Vector3
	var right_before: Vector3 = minimap.get("map_right") as Vector3
	var arrow_before: Vector2 = minimap.get("arrow_heading_2d") as Vector2
	for normal: Vector3 in directions:
		minimap.call("location_at",normal)
	check("Region queries do not change map frame or arrow",frame_before == (minimap.get("map_forward") as Vector3) and right_before == (minimap.get("map_right") as Vector3) and arrow_before == (minimap.get("arrow_heading_2d") as Vector2))
	minimap.free()
	var result: Dictionary = {"passed":failures == 0,"failed":failures,"checks":checks}
	var file: FileAccess = FileAccess.open("res://tests/minimap_location_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"\t"))
	print(JSON.stringify(result))
	quit(0 if failures == 0 else 1)
