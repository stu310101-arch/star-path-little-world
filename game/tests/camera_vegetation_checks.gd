extends SceneTree

const Controller = preload("res://scripts/camera_vegetation.gd")
const Instances = preload("res://scripts/ecology_instances.gd")

var world: Node3D
var checks: int=0
var failures: int=0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func batch(name_value: String,key: String,kind: String,size: Vector3,placements: Array[Transform3D]) -> MultiMeshInstance3D:
	var node: MultiMeshInstance3D=MultiMeshInstance3D.new()
	node.name=name_value
	node.multimesh=MultiMesh.new()
	node.multimesh.transform_format=MultiMesh.TRANSFORM_3D
	var mesh: BoxMesh=BoxMesh.new()
	mesh.size=size
	node.multimesh.mesh=mesh
	node.set_meta("ecology_batch_key",key)
	node.set_meta("ecology_kind",kind)
	node.set_meta("placements",placements)
	node.set_script(Instances)
	world.add_child(node)
	return node

func run() -> void:
	# Tiny real MultiMesh resources; no world scene, tree models or renderer.
	world=Node3D.new()
	root.add_child(world)
	var authored: Array[Transform3D]=[
		Transform3D(Basis.IDENTITY,Vector3(0,2,-4)),
		Transform3D(Basis.IDENTITY,Vector3(4,2,-4)),
		Transform3D(Basis.IDENTITY,Vector3(0,2,-15))]
	var bark: MultiMeshInstance3D=batch("Bark","alder_0","alder",Vector3(.2,4,.2),authored)
	var leaves: MultiMeshInstance3D=batch("Leaves","alder_0","alder",Vector3(2,2,2),authored)
	var shoulder: MultiMeshInstance3D=batch("ShoulderTree","willow_0","willow",Vector3(.10,2,.10),[Transform3D(Basis.IDENTITY,Vector3(.3,2,-6))])
	var fern: MultiMeshInstance3D=batch("Fern","fern_0","fern",Vector3(2,2,2),[authored[0]])
	var flowers: MultiMeshInstance3D=batch("FlowerBed","","",Vector3(2,2,2),[authored[0]])
	var trunk: StaticBody3D=StaticBody3D.new()
	trunk.position=Vector3(0,0,-4)
	trunk.collision_layer=8
	world.add_child(trunk)
	var trunk_before: Transform3D=trunk.transform
	var camera: Camera3D=Camera3D.new()
	world.add_child(camera)
	camera.position=Vector3(0,2,0)
	camera.look_at(Vector3(0,2,-10))
	await process_frame
	var controller: RefCounted=Controller.new()
	controller.call("update",world,camera,Vector3(0,2,-10))
	var records: Dictionary=controller.get("_batches") as Dictionary
	check(records.size()==2,"Only the four allowed tree species are tracked")
	check((records.alder_0.visible as PackedInt32Array)==PackedInt32Array([1,2]),"Only the foreground tree is removed; off-axis and background trees stay visible")
	check(bark.multimesh.visible_instance_count==2 and leaves.multimesh.visible_instance_count==2,"Bark and foliage must compact together by the same tree index")
	check(shoulder.multimesh.visible_instance_count==0,"The .3 m shoulder ray catches narrow foliage beside the centre ray")
	check(fern.multimesh.visible_instance_count==-1 and flowers.multimesh.visible_instance_count==-1,"Low planting and flower batches are untouched")
	check(trunk.transform==trunk_before and trunk.collision_layer==8,"Camera visibility must not move or alter tree collision")
	for node: MultiMeshInstance3D in [bark,leaves]:
		check((node.get_meta("placements") as Array)==authored,"Original metadata transforms must remain unchanged")
		check(node.multimesh.instance_count==3 and node.visible,"Keep the full allocation and the batch node visible")
	camera.position=Vector3(4,2,-4)
	camera.look_at(Vector3(4,2,-10))
	controller.call("update",world,camera,Vector3(4,2,-10))
	records=controller.get("_batches") as Dictionary
	check((records.alder_0.visible as PackedInt32Array)==PackedInt32Array([0,2]),"Moving into a different crown must change the compacted indices even when its count stays the same")
	check(shoulder.multimesh.visible_instance_count==-1,"A cleared view automatically restores the original full batch")
	camera.position=Vector3(10,2,0)
	camera.look_at(Vector3(10,2,-10))
	controller.call("update",world,camera,Vector3(10,2,-10))
	check(bark.multimesh.visible_instance_count==-1 and leaves.multimesh.visible_instance_count==-1,"A clear camera restores all original transforms and full visibility")
	camera.position=Vector3(0,2,0)
	camera.look_at(Vector3(0,2,-10))
	controller.call("update",world,camera,Vector3(0,2,-10))
	controller.call("reset")
	check(bark.multimesh.visible_instance_count==-1 and leaves.multimesh.visible_instance_count==-1 and shoulder.multimesh.visible_instance_count==-1,"Overview reset restores every tracked tree batch")
	check((controller.get("_batches") as Dictionary).is_empty(),"Reset releases all world-specific camera state")
	check((bark.get_meta("placements") as Array)==authored and (leaves.get_meta("placements") as Array)==authored,"Overview preserves every authored matrix")
	controller.call("update",world,camera,Vector3(0,2,-10))
	var next_world: Node3D=Node3D.new()
	root.add_child(next_world)
	var next_camera: Camera3D=Camera3D.new()
	next_world.add_child(next_camera)
	controller.call("update",next_world,next_camera,Vector3(0,0,-10))
	check(bark.multimesh.visible_instance_count==-1 and leaves.multimesh.visible_instance_count==-1,"Changing worlds restores the previous world's batches")
	world.free()
	next_world.free()
	controller.call("reset")
	print("CAMERA_VEGETATION_CHECKS ",checks," checks, ",failures," failures")
	quit(1 if failures>0 else 0)
