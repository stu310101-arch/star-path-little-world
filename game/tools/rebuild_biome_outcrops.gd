extends SceneTree

## Targeted iteration tool: replace only the six editable rock ledges. Terrain,
## routes, trees, and their existing collision are untouched by this operation.
const Geo=preload("res://scripts/planet_geometry.gd")
const Ecology=preload("res://tools/ecology_world.gd")
const Landforms=preload("res://tools/world_landforms.gd")
const Art=preload("res://scripts/world_art_direction.gd")
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var globe: Node3D=(load("res://generated/globe.tscn") as PackedScene).instantiate() as Node3D
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
	var districts: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json"))
	var art: RefCounted=Art.new()
	for index: int in range(districts.size()):
		var data: Dictionary=districts[index]
		var nd: Array=layout.stations[index].normal
		var up: Vector3=Vector3(nd[0],nd[1],nd[2])
		var reserve: Node3D=globe.get_node("EcologicalReserves/Reserve_"+str(data.station))
		var old: Node=reserve.get_node_or_null("BiomeRockOutcrops")
		if old!=null:
			reserve.remove_child(old)
			old.free()
		var field: RefCounted=Landforms.new()
		field.call("configure",data,index,layout.radius,up)
		var ecology: RefCounted=Ecology.new()
		ecology.set("radius",layout.radius)
		ecology.set("batch_district",index)
		ecology.set("landforms",field)
		ecology.call("build_biome_rocks",reserve,up,data)
		var outcrop: MeshInstance3D=reserve.get_node_or_null("BiomeRockOutcrops") as MeshInstance3D
		assert(outcrop!=null,"Every biome must retain its authored rock outcrop")
		outcrop.material_override=art.call("material_for","rock") as Material
		print("ROCK_LEDGE_REBUILT ",data.station," triangles=",outcrop.mesh.surface_get_array_len(0)/3)
	Geo.save_scene(globe,"res://generated/globe.tscn")
	globe.free()
	print("CANONICAL_ROCK_LEDGES_SAVED")
	quit()
