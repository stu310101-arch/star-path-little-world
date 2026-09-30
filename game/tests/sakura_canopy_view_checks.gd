extends SceneTree

const Geo = preload("res://scripts/planet_geometry.gd")
const Plan = preload("res://scripts/sakura_routes.gd")

func _initialize() -> void:
	var captures: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../deliverables/authored-garden/capture-report.json")) as Dictionary
	var boxes: Array[AABB]=[]
	var failures: int=0
	for variant: int in range(3):
		var raw: PackedByteArray=FileAccess.get_file_as_bytes("res://assets/scenery/sakura_"+str(variant)+".glb")
		var json_size: int=raw.decode_u32(12)
		var gltf: Dictionary=JSON.parse_string(raw.slice(20,20+json_size).get_string_from_utf8()) as Dictionary
		var mesh: Dictionary=gltf.meshes[1]
		var accessor: Dictionary=gltf.accessors[mesh.primitives[0].attributes.POSITION]
		var minimum: Vector3=vec(accessor.min)
		boxes.append(AABB(minimum,vec(accessor.max)-minimum))
	for index: int in [0,1]:
		var capture: Dictionary=captures.images[index]
		var blockers: Array=[]
		var camera: Vector3=vec(capture.camera_position)
		var target: Vector3=vec(capture.camera_aim)
		for tree: Dictionary in Plan.trees():
			var normal: Vector3=Geo.surface(Plan.grove_up(),tree.position,48.0).normalized()
			var scale_value: float=float(tree.scale)
			var width: float=scale_value*float(tree.get("width_scale",1.0))
			var facing: Basis=Geo.frame(normal)*Basis(Vector3.UP,float(tree.yaw))
			var transform: Transform3D=Transform3D(Basis(facing.x*width,facing.y*scale_value,facing.z*width),normal*48.16)
			var inverse: Transform3D=transform.affine_inverse()
			if boxes[int(tree.variant)].intersects_segment(inverse*camera,inverse*target)!=null:
				blockers.append(tree.position)
		failures+=blockers.size()
		print(capture.file," camera-to-character canopy boxes: ",blockers)
	print("SAKURA_CANOPY_VIEWS ",failures," obstructions, ",Plan.trees().size()," authored trees")
	quit(1 if failures>0 else 0)

func vec(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])
