extends SceneTree

## Apply a source-authored, noncolliding boat-anchor correction after a full
## generation. Rebuild streaming afterwards so every published view matches.
const Geo = preload("res://scripts/planet_geometry.gd")
const Infrastructure = preload("res://tools/world_infrastructure.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var path: String = "res://generated/districts/admissions.tscn"
	var source: Node3D = (load(path) as PackedScene).instantiate() as Node3D
	var boat: Node3D = source.get_node("Marina/MooredFishingBoat") as Node3D
	assert(boat.find_children("*","CollisionObject3D",true,false).is_empty(),"Mooring patch must never move colliding infrastructure")
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var info: Dictionary = (JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array)[1]
	var n: Array = layout.stations[1].normal
	var up: Vector3 = Vector3(n[0],n[1],n[2]).normalized()
	var radius: float = float(layout.radius)
	var mooring: Vector2 = Infrastructure.marina_mooring(info)
	var normal: Vector3 = Geo.surface(up,mooring,radius).normalized()
	boat.transform = Transform3D(Basis(Quaternion(up,normal))*Geo.frame(up),normal*(radius+.06))
	boat.set_meta("mooring_local",mooring)
	boat.set_meta("mooring_shore_clearance",3.5)
	Geo.save_scene(source,path)
	source.free()
	print("MARINA_MOORING_PATCHED local=",mooring," shore_clearance=3.5; rebuild streaming before shipping")
	quit()
