extends RefCounted

## Exact-triangle spatial partitions for mobile roaming frustum/planet culling.
## Never simplify terrain: each source triangle appears once with the same
## positions, normals, UVs, shoreline weights and colors. Overview/desktop keep
## the original material batches to avoid extra distant draw submissions.
const CELL_SIZE: float = 16.0
const MIN_TRIANGLES: int = 8000
var source_meshes: int = 0
var tile_meshes: int = 0
var triangles: int = 0

func prepare(visual: MeshInstance3D) -> void:
	var mesh: Mesh=visual.mesh
	if mesh==null or mesh.get_surface_count()!=1: return
	var arrays: Array=mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] is PackedInt32Array else PackedInt32Array()
	if indices.is_empty():
		indices.resize(vertices.size())
		for i: int in range(indices.size()): indices[i]=i
	if indices.size()/3<MIN_TRIANGLES: return
	var cells: Dictionary={}
	for i: int in range(0,indices.size(),3):
		var center: Vector3=(vertices[indices[i]]+vertices[indices[i+1]]+vertices[indices[i+2]])/3.0
		var key: Vector3i=Vector3i((center/CELL_SIZE).floor())
		if not cells.has(key): cells[key]=PackedInt32Array()
		var subset: PackedInt32Array=cells[key]
		subset.append(indices[i]); subset.append(indices[i+1]); subset.append(indices[i+2])
		cells[key]=subset
	if cells.size()<2: return
	var tiles: Array[Mesh]=[]
	var output_indices: int=0
	for key: Vector3i in cells:
		var data: Array=arrays.duplicate()
		data[Mesh.ARRAY_INDEX]=cells[key]
		var temp: ArrayMesh=ArrayMesh.new()
		temp.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
		var tool: SurfaceTool=SurfaceTool.new()
		tool.create_from(temp,0)
		tool.deindex()
		tool.index()
		tool.set_material(visual.get_active_material(0))
		tiles.append(tool.commit())
		output_indices+=(cells[key] as PackedInt32Array).size()
	assert(output_indices==indices.size(),"Mobile terrain tile must preserve every triangle")
	visual.set_meta("mobile_render_tiles",tiles)
	source_meshes+=1
	tile_meshes+=tiles.size()
	triangles+=indices.size()/3

func statistics() -> Dictionary:
	return {"source_meshes":source_meshes,"tiles":tile_meshes,"triangles_preserved":triangles,"authored_cell_metres":CELL_SIZE,"physical_cell_metres":CELL_SIZE*.4,"geometry_unchanged":true}
