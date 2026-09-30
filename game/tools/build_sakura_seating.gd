extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")
const Garden = preload("res://tools/sakura_garden.gd")

func _initialize() -> void:
	call_deferred("build")

func build() -> void:
	# Keep the authored ecology, bridge, trees and imported MultiMesh metadata.
	# This patch never enters the scene tree or regenerates the wider world.
	var globe: Node3D = (load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	var grove: Node3D = globe.get_node("SakuraGrove") as Node3D
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var radius: float = float(layout.radius)
	var up: Vector3 = Plan.grove_up()
	var seats: Array[Dictionary] = []
	for placement: Dictionary in Plan.seats():
		var anchor: Node3D = grove.get_node(str(placement.id)) as Node3D
		var bench: Node3D = anchor.get_node("GardenBench") as Node3D
		var normal: Vector3 = Geo.surface(up,placement.position,radius).normalized()
		anchor.transform = Transform3D(Basis(Quaternion(up,normal))*Geo.frame(up),normal*(radius+.26))
		anchor.set_meta("garden_position",placement.position)
		anchor.set_meta("garden_approach",placement.approach)
		bench.rotation.y = float(placement.yaw)
		seats.append({"id":str(placement.id),"position":[placement.position.x,placement.position.y],"approach":[placement.approach.x,placement.approach.y],"yaw":float(placement.yaw)})
	var old_rails: Node = grove.get_node("OverlookGuardrails")
	grove.remove_child(old_rails)
	old_rails.free()
	Garden.build_overlook_rails(grove,up,radius)
	grove.set_meta("layout_version",Plan.LAYOUT_VERSION)
	grove.set_meta("seating_access","Bench fronts face the garden loop; open 2.75 m paved mouths; short outer corner guards")
	Geo.save_scene(globe,"res://generated/globe.tscn")
	var report: Dictionary = {"layout_version":Plan.LAYOUT_VERSION,"seats":seats,"open_entrance_width":2.75,"outer_guard_x":8.25,"guard_return_x":7.8,"changed_nodes":["SakuraGrove/EastViewBench","SakuraGrove/WestViewBench","SakuraGrove/OverlookGuardrails"]}
	report["marina_benches_turned_inward"] = patch_marina()
	var build_report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://generated/build_report.json")) as Dictionary
	build_report["sakura_layout_version"] = Plan.LAYOUT_VERSION
	build_report["sakura_seating"] = report
	FileAccess.open("res://generated/build_report.json",FileAccess.WRITE).store_string(JSON.stringify(build_report,"\t"))
	globe.free()
	print("SAKURA_SEATING_BUILT "+JSON.stringify(report))
	quit()

func patch_marina() -> int:
	var district: Node3D = (load("res://generated/districts/admissions.tscn") as PackedScene).instantiate() as Node3D
	var marina: Node3D = district.get_node("Marina") as Node3D
	var benches: Array[Node] = marina.find_children("GardenBench","Node3D",true,false)
	assert(benches.size()==2,"Expected the two existing marina benches")
	for bench: Node3D in benches:
		bench.rotation.y = PI
	marina.set_meta("seating_access","Both benches face the clear central deck aisle")
	Geo.save_scene(district,"res://generated/districts/admissions.tscn")
	district.free()
	return benches.size()
