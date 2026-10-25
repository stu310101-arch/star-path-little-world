extends RefCounted

## Offline render copies only. No colliders, path surfaces, avatar deformation,
## instance placements, camera obstruction keys, or gameplay nodes are altered.
const Foliage = preload("res://tools/overview_foliage_lod.gd")
const KEEP_FRACTION: float = .40
var foliage: RefCounted = Foliage.new()
var cache: Dictionary = {}
var source_triangles: int = 0
var mobile_triangles: int = 0
var changed_meshes: int = 0

func _init() -> void:
	foliage.set("keep_fraction",.42)

func prepare(node: Node, builder: RefCounted, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	if node is Node3D and not (node as Node3D).visible: return
	var transform: Transform3D = parent_transform*((node as Node3D).transform if node is Node3D else Transform3D.IDENTITY)
	var mesh: Mesh
	var kind: String = ""
	var copies: int = 1
	# Disconnected facade panels are not safe to decimate even at 40%: keep
	# every building, prop, vehicle and interactive landmark exactly authored.
	if node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
		mesh = (node as MultiMeshInstance3D).multimesh.mesh
		kind = str(node.get_meta("ecology_kind",node.get_meta("aquatic_kind","")))
		copies = (node.get_meta("placements",[]) as Array).size()
		if kind not in ["alder","birch","willow","pine","fern","cattail","water_lily"]: mesh=null
	if mesh != null and mesh is ArrayMesh and (mesh as ArrayMesh).get_blend_shape_count()==0:
		var skinned: bool = false
		for surface: int in range(mesh.get_surface_count()):
			skinned = skinned or (mesh.surface_get_format(surface)&Mesh.ARRAY_FORMAT_BONES)!=0
		if not skinned:
			var source_count: int = count(mesh)
			if source_count>=120:
				var result: Mesh = reduce(mesh,kind)
				source_triangles+=source_count*copies
				mobile_triangles+=count(result)*copies
				if result!=mesh:
					node.set_meta("mobile_render_mesh",result)
					changed_meshes+=1
	for child: Node in node.get_children(): prepare(child,builder,transform)

func reduce(mesh: Mesh, kind: String) -> Mesh:
	var key: String = str(mesh.get_instance_id())+":"+kind
	if cache.has(key): return cache[key] as Mesh
	var input: Mesh = foliage.call("reduce",mesh) as Mesh if kind in ["alder","birch","willow","pine","fern","cattail","water_lily"] else mesh
	var importer: ImporterMesh = ImporterMesh.new()
	for surface: int in range(input.get_surface_count()):
		var arrays: Array = input.surface_get_arrays(surface)
		if not arrays[Mesh.ARRAY_INDEX] is PackedInt32Array or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			var indices: PackedInt32Array = PackedInt32Array()
			indices.resize((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for index: int in range(indices.size()): indices[index]=index
			arrays[Mesh.ARRAY_INDEX]=indices
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},input.surface_get_material(surface))
	importer.generate_lods(60.0,60.0,[])
	var result: ArrayMesh = ArrayMesh.new()
	for surface: int in range(importer.get_surface_count()):
		var arrays: Array = importer.get_surface_arrays(surface)
		var original: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var selected: PackedInt32Array = original
		for level: int in range(importer.get_surface_lod_count(surface)):
			var candidate: PackedInt32Array = importer.get_surface_lod_indices(surface,level)
			if candidate.size()>=maxi(36,int(original.size()*KEEP_FRACTION)): selected=candidate
		arrays[Mesh.ARRAY_INDEX]=selected
		var temp: ArrayMesh = ArrayMesh.new()
		temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var tool: SurfaceTool = SurfaceTool.new()
		tool.create_from(temp,0)
		tool.deindex()
		tool.index()
		tool.set_material(mesh.surface_get_material(surface))
		tool.commit(result)
	result.custom_aabb=mesh.get_aabb()
	cache[key]=result if count(result)<count(mesh) else mesh
	return cache[key] as Mesh

func count(mesh: Mesh) -> int:
	var total: int = 0
	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
		total+=(indices.size() if not indices.is_empty() else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())/3
	return total

func statistics() -> Dictionary:
	return {"changed_meshes":changed_meshes,"source_instanced_triangles":source_triangles,"mobile_instanced_triangles":mobile_triangles,"connected_lod_floor":KEEP_FRACTION,"foliage":foliage.call("statistics"),"collision_changed":false,"walkable_surface_geometry_changed":false}
