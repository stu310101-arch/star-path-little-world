@tool
extends MultiMeshInstance3D

func _ready() -> void:
	# The headless scene builder has a dummy rendering server. Persist authored
	# transforms as metadata and upload them when the real renderer is available.
	var placements: Array=get_meta("placements",[])
	var source_mesh: Mesh=multimesh.mesh
	multimesh=MultiMesh.new()
	multimesh.transform_format=MultiMesh.TRANSFORM_3D
	multimesh.mesh=source_mesh
	multimesh.instance_count=placements.size()
	var bounds: AABB=AABB()
	for i: int in range(placements.size()):
		var placement: Transform3D=placements[i] as Transform3D
		multimesh.set_instance_transform(i,placement)
		var box: AABB=placement*multimesh.mesh.get_aabb()
		bounds=box if i==0 else bounds.merge(box)
	custom_aabb=bounds.grow(.2)
