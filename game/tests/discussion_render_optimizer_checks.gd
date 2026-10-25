extends SceneTree
const Optimizer = preload("res://scripts/discussion_render_optimizer.gd")
const Device = preload("res://scripts/discussion_device.gd")
class Fixture:
	extends Node3D
	var zones: Dictionary = {}
var failures: int = 0
var checks: int = 0
func _initialize() -> void: run.call_deferred()
func check(title: String, passed: bool) -> void:
	checks += 1
	print("DISCUSSION_RENDER_CHECK ",title," ",passed)
	if not passed: failures += 1
func run() -> void:
	var garden := Fixture.new()
	root.add_child(garden)
	var originals: Array[MeshInstance3D] = []
	var transforms: Dictionary = {}
	var context_ids: Dictionary = {}
	for id: String in ["university","major","career","high_school","campus"]:
		garden.zones[id] = {"devices":[]}
		var packed: PackedScene = load("res://assets/discussion_garden/message_device_"+id+".glb")
		for index: int in range(8):
			var device := Device.new()
			garden.add_child(device)
			device.position = Vector3(index*2.0,0,garden.zones.size()*8.0)
			device.rotation.y = float(index)*.3
			device.add_child(packed.instantiate())
			var label := Label3D.new()
			device.add_child(label)
			device.configure(id,index,label)
			var collider := StaticBody3D.new()
			device.add_child(collider)
			garden.zones[id].devices.append(device)
			context_ids[device.context().deviceId] = true
			for candidate: Node in device.find_children("*","MeshInstance3D",true,false):
				var visual: MeshInstance3D = candidate as MeshInstance3D
				originals.append(visual)
				transforms[visual.get_instance_id()] = visual.global_transform
	var optimizer := Optimizer.new()
	garden.add_child(optimizer)
	optimizer.configure(garden)
	var metrics: Dictionary = optimizer.metrics()
	check("Forty visual instances become five material-preserving batches",metrics.instances==40 and metrics.batches==5 and metrics.source_surfaces==200 and metrics.batch_surfaces==25)
	check("All forty independent thread addresses are retained",context_ids.size()==40)
	var transforms_valid: bool = true
	var bounds_valid: bool = true
	for batch: MultiMeshInstance3D in optimizer.find_children("*","MultiMeshInstance3D",true,false):
		var members: Array = garden.zones[batch.get_meta("discussion_zone")].devices
		var placements: Array = batch.get_meta("placements")
		for i: int in range(8):
			var visual: MeshInstance3D = members[i].find_children("*","MeshInstance3D",true,false)[0]
			var placement: Transform3D = placements[i]
			transforms_valid = transforms_valid and (batch.global_transform*placement).is_equal_approx(transforms[visual.get_instance_id()])
			var box: AABB = placement * visual.get_aabb()
			bounds_valid = bounds_valid and batch.multimesh.custom_aabb.grow(.001).encloses(box)
			check("Independent device "+str(members[i].context().deviceId)+" keeps label and collider",members[i].preview_label.visible and members[i].find_children("*","StaticBody3D",true,false).size()==1 and not visual.visible)
	check("Batch transforms preserve original positions, scales and rotations",transforms_valid)
	check("Every authored mesh is enclosed by batch culling bounds",bounds_valid)
	optimizer.configure(garden)
	check("Repeat configuration is idempotent",optimizer.metrics()==metrics)
	optimizer.restore()
	var restored: bool = true
	for original: MeshInstance3D in originals: restored = restored and original.visible
	check("Restore exposes all source visuals again",restored)
	await process_frame
	await process_frame
	check("Restore releases all five batch nodes",optimizer.get_child_count()==0)
	optimizer.configure(garden)
	check("A new configuration after restore contains exactly forty instances",optimizer.metrics().instances==40)
	garden.queue_free()
	await process_frame
	print("DISCUSSION_RENDER_RESULT ",checks," checks, ",failures," failures")
	quit(0 if failures==0 else 1)
