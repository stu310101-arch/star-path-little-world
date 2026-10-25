extends SceneTree
const Ecology=preload("res://tools/ecology_world.gd")
const Landforms=preload("res://tools/world_landforms.gd")
const Geo=preload("res://scripts/planet_geometry.gd")
var districts: Array=[]
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var layout: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/world_layout.json"))
	districts=JSON.parse_string(FileAccess.get_file_as_string("res://data/districts.json"))
	var failures: Array=[]
	var scene: Node3D=Node3D.new()
	root.add_child(scene)
	var ecology: RefCounted=Ecology.new()
	ecology.set("radius",float(layout.radius))
	ecology.set("builder",self)
	ecology.set("parent",scene)
	for index: int in range(districts.size()):
		var nd: Array=layout.stations[index].normal
		var up: Vector3=Vector3(nd[0],nd[1],nd[2])
		var field: RefCounted=Landforms.new()
		field.call("configure",districts[index],index,layout.radius,up)
		ecology.set("landforms",field)
		ecology.set("batch_district",index)
		var patch: Node3D=Node3D.new()
		scene.add_child(patch)
		ecology.call("build_biome_rocks",patch,up,districts[index])
		var vertices: int=0
		var minimum_up: float=1.0
		for mesh: MeshInstance3D in patch.find_children("*","MeshInstance3D",true,false):
			var arrays: Array=mesh.mesh.surface_get_arrays(0)
			var positions: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			vertices+=positions.size()
			for i: int in range(positions.size()):
				minimum_up=minf(minimum_up,normals[i].dot(positions[i].normalized()))
		if vertices==0 or minimum_up<-.0001: failures.append([districts[index].station,vertices,minimum_up])
		ecology.call("vegetation",up,districts[index],index)
		print("BIOME_GEOMETRY ",districts[index].station," rock_triangles=",vertices/3," min_outward_normal=",minimum_up)
	ecology.call("flush_batches")
	var rendered_triangles: int=0
	var foliage_cutout_batches: int=0
	for batch: MultiMeshInstance3D in scene.find_children("*","MultiMeshInstance3D",true,false):
		var mesh: Mesh=batch.multimesh.mesh
		var mesh_triangles: int=0
		for surface: int in range(mesh.get_surface_count()):
			var arrays: Array=mesh.surface_get_arrays(surface)
			mesh_triangles+=((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())/3
			var mat: StandardMaterial3D=mesh.surface_get_material(surface) as StandardMaterial3D
			if str(batch.get_meta("ecology_kind")) in ["alder","birch","pine","willow"] and mat.transparency!=BaseMaterial3D.TRANSPARENCY_DISABLED:
				foliage_cutout_batches+=1
				if mat.transparency!=BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or mat.albedo_texture==null:
					failures.append(["tree foliage must retain atlas alpha cutout",batch.name])
		rendered_triangles+=mesh_triangles*(batch.get_meta("placements") as Array).size()
	print("BIOME_RENDER_BUDGET all_six_raw_triangles=",rendered_triangles," foliage_cutout_batches=",foliage_cutout_batches)
	for model: Node3D in (ecology.get("models") as Dictionary).values(): model.free()
	print("BIOME_VEGETATION trees=",ecology.get("tree_count")," understory=",ecology.get("plant_count")," failures=",JSON.stringify(failures))
	scene.free()
	quit(0 if failures.is_empty() else 1)
