extends SceneTree

const Infrastructure=preload("res://tools/world_infrastructure.gd")
const Routes=preload("res://scripts/world_routes.gd")
const Biome=preload("res://scripts/biome_geography.gd")
var failures: Array[String]=[]

func check(ok: bool,message: String) -> void:
	if not ok: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var total: int=0
	for id: String in ["fishing_boat","tugboat","liner"]:
		var packed: PackedScene=load("res://assets/vessels/"+id+".glb") as PackedScene
		check(packed!=null,id+" imports")
		if packed==null: continue
		var vessel: Node3D=packed.instantiate() as Node3D
		var meshes: Array[Node]=vessel.find_children("*","MeshInstance3D",true,false)
		check(meshes.size()==1,id+" is one batched multi-material mesh")
		var triangles: int=0
		for child: Node in meshes:
			var instance: MeshInstance3D=child as MeshInstance3D
			var bounds: AABB=instance.mesh.get_aabb()
			check(bounds.position.y<-.5 and bounds.end.y>3,id+" waterline origin and draft")
			check(bounds.size.z>7.5,id+" realistic metre scale")
			for s: int in range(instance.mesh.get_surface_count()):
				var material: Material=instance.mesh.surface_get_material(s)
				check(material!=null,id+" material "+str(s))
				var arrays: Array=instance.mesh.surface_get_arrays(s)
				triangles+=(arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
		total+=triangles
		print("VESSEL ",id," triangles=",triangles)
		vessel.free()
	check(total<100000,"combined budget below 100k triangles")
	var data: Array=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json")) as Array
	var info: Dictionary=data[1]
	var point: Vector2=Infrastructure.marina_mooring(info)
	# Boat lies along the pier (local X), with a beam under 3 m.
	for dx: float in [-4.13,4.13]:
		for dz: float in [-1.49,1.49]:
			check(Biome.coast_distance(point+Vector2(dx,dz),info,1)<-.4,"entire berth bounds afloat")
	print("VESSEL_ASSET_CHECKS ","PASS" if failures.is_empty() else "FAIL"," total_triangles=",total," mooring=",point)
	for failure: String in failures: push_error(failure)
	quit(0 if failures.is_empty() else 1)
