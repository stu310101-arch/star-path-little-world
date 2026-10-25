extends SceneTree

## Rebuild only the merged civic visual after a procedural foliage repair.
## Existing paving, props, collision objects and placement stay untouched.
const Geo = preload("res://scripts/planet_geometry.gd")
const Civic = preload("res://tools/refine_civic_plazas.gd")
var report: Dictionary = {}

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json")) as Dictionary
	var districts: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var count: int = 0
	for i: int in range(districts.size()):
		var info: Dictionary = districts[i]
		var path: String = "res://generated/districts/"+str(info.station)+".tscn"
		var source: Node3D = (load(path) as PackedScene).instantiate() as Node3D
		var original: MeshInstance3D = source.get_node_or_null("CivicFurniture") as MeshInstance3D
		if original == null:
			source.free()
			continue
		var values: Array = layout.stations[i].normal
		var up: Vector3 = Vector3(values[0],values[1],values[2]).normalized()
		var fresh: Node3D = Node3D.new()
		Civic.build(self,fresh,up,float(layout.radius),info)
		var replacement: MeshInstance3D = fresh.get_node_or_null("CivicFurniture") as MeshInstance3D
		assert(replacement != null,"Civic visual must keep its existing authored placement recipe")
		original.mesh = replacement.mesh
		Geo.save_scene(source,path)
		print("CIVIC_FOLIAGE_PATCHED ",info.station," triangles=",original.mesh.get_faces().size()/3)
		count+=1
		fresh.free()
		source.free()
	print("CIVIC_FOLIAGE_PATCH_OK districts=",count,"; rebuild streaming")
	quit()
