extends SceneTree

var failures: int = 0
var checks: Array[Dictionary] = []
var measurements: Dictionary = {}

func _initialize() -> void:
	call_deferred("run")

func check(label: String,passed: bool) -> void:
	checks.append({"test":label,"passed":passed})
	if not passed:
		failures+=1
		push_error(label)

func run() -> void:
	for key: String in ["alder","birch","pine","willow"]:
		var model: Node3D = (load("res://assets/vegetation_rebuilt/"+key+".glb") as PackedScene).instantiate() as Node3D
		root.add_child(model)
		var bounds: AABB
		var first: bool = true
		var triangles: int = 0
		var materials: int = 0
		var foliage_valid: bool = false
		var bark_valid: bool = false
		var root_width: float = 0.0
		for child: Node in model.find_children("*","MeshInstance3D",true,false):
			var mesh: MeshInstance3D = child as MeshInstance3D
			var transform: Transform3D = model.global_transform.affine_inverse()*mesh.global_transform
			var box: AABB = transform*mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
			for surface: int in range(mesh.mesh.get_surface_count()):
				var arrays: Array = mesh.mesh.surface_get_arrays(surface)
				triangles += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size()/3
				materials += 1
				var mat: StandardMaterial3D = mesh.mesh.surface_get_material(surface) as StandardMaterial3D
				if str(mesh.name).contains("Foliage"):
					foliage_valid = mat!=null and mat.albedo_texture!=null and mat.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and mat.cull_mode==BaseMaterial3D.CULL_DISABLED
				else:
					bark_valid = mat!=null and mat.albedo_texture!=null and mat.normal_enabled and mat.normal_texture!=null and mat.roughness>.7
					for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array:
						var point: Vector3 = transform*vertex
						if point.y<.3:
							root_width = maxf(root_width,Vector2(point.x,point.z).length())
		check(key+" exported whole tree fits the 12000 triangle budget",triangles<=12000 and triangles>4000)
		check(key+" uses exactly two draw surfaces",materials==2)
		check(key+" imports double-sided alpha-cutout leaf atlas",foliage_valid)
		check(key+" imports bark colour and tangent normal textures",bark_valid)
		check(key+" retains 4-8 metre world scale",bounds.size.y>=4.0 and bounds.size.y<=8.0 and model.scale.is_equal_approx(Vector3.ONE))
		check(key+" root base is buried without giant exposed feet",bounds.position.y>-.2 and bounds.position.y<-.1 and root_width<.4)
		measurements[key]={"triangles":triangles,"dimensions":var_to_str(bounds.size),"root_base":bounds.position.y,"root_radius":root_width}
		model.queue_free()
		await process_frame
	var file: FileAccess = FileAccess.open("res://../deliverables/vegetation/asset_checks.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"failures":failures,"measurements":measurements},"\t"))
	print("VEGETATION_ASSET_CHECKS ",checks.size()-failures,"/",checks.size())
	quit(1 if failures>0 else 0)
