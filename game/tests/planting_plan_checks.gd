extends SceneTree

const Ecology = preload("res://tools/ecology_world.gd")
const Geo = preload("res://scripts/planet_geometry.gd")
const Routes = preload("res://scripts/world_routes.gd")

var checks: int = 0
var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func run() -> void:
	# Build only the authored transforms and simple trunk proxies. The world,
	# terrain, source models and renderer are deliberately not loaded here.
	var ecology: RefCounted=Ecology.new()
	var container: Node3D=Node3D.new()
	root.add_child(container)
	ecology.set("parent",container)
	ecology.set("radius",48.0)
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var plan: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/ecology_planting.json")) as Dictionary
	var expected_trees: int=0
	var expected_understory: int=0
	for i: int in range(districts.size()):
		var info: Dictionary=districts[i]
		var authored: Dictionary=plan.districts[str(info.station)]
		check(not (authored.groups as Array).is_empty(),str(info.station)+" has no authored grove")
		check(not (authored.view_windows as Array).is_empty(),str(info.station)+" has no protected view window")
		for group: Dictionary in authored.groups:
			check(not str(group.name).is_empty(),"Every planting group needs a reviewable name")
			expected_trees+=(group.trees as Array).size()
			expected_understory+=(group.understory as Array).size()
		expected_trees+=(info.gardens as Array).size()
		ecology.set("batch_district",i)
		ecology.call("vegetation",Routes.directions()[i],info,i)
		var records: Array=ecology.get("planting_groups") as Array
		var record: Dictionary=records[-1]
		check(record.station==info.station,"Planting report station mismatch")
		check(record.groups.size()==authored.groups.size()+1,"Missing group or pocket specimens")
		check(record.view_windows==authored.view_windows,"Build changed authored view windows")
	check(int(ecology.get("tree_count"))==expected_trees,"Authored trees were omitted or duplicated")
	check(int(ecology.get("plant_count"))==expected_understory,"Authored understory was omitted or duplicated")
	check(container.get_child_count()==expected_trees,"One solid trunk proxy is required per authored tree")
	for body: Node3D in container.get_children():
		check(body.has_meta("planting_group") and not str(body.get_meta("planting_group")).is_empty(),"Trunk is missing its group provenance")
		var up: Vector3=Routes.directions()[int(body.get_meta("district_index"))]
		var point: Vector2=body.get_meta("local_position") as Vector2
		var expected: Vector3=Geo.surface(up,point,48.0).normalized()*48.16
		check(body.position.distance_to(expected)<.0001,"Tree was moved from its authored spherical anchor")
		check((body as StaticBody3D).collision_layer==8,"Tree proxy must remain on obstacle layer 8")
	var source: String=FileAccess.get_file_as_string("res://tools/ecology_world.gd")
	var vegetation_source: String=source.get_slice("func vegetation",1).get_slice("func place",0)
	check(not vegetation_source.contains("RandomNumberGenerator") and not vegetation_source.contains("randf"),"Vegetation must not scatter authored plants")
	print("PLANTING_PLAN_CHECKS ",checks," checks, ",failures," failures; ",expected_trees," trees and ",expected_understory," understory clusters")
	container.free()
	quit(1 if failures>0 else 0)
