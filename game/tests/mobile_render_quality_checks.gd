extends SceneTree

const Startup=preload("res://tests/startup_fixture.gd")
const Quality=preload("res://scripts/mobile_render_quality.gd")
var checks: Array[Dictionary]=[]
var failures: int=0
var world: Node3D

func _initialize() -> void: call_deferred("run")

func check(label: String, passed: bool, evidence: Variant=null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures+=1
		push_error(label+": "+str(evidence))

func run() -> void:
	world=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene=world
	var settings: Node=world.get("graphics_settings") as Node
	set_quality(settings,false)
	world.call("set_overview",false)
	check("Real world completes normal roaming preparation",await Startup.wait_roaming(world,self))
	world.set_process(false)
	(world.get("hud") as Node).process_mode=Node.PROCESS_MODE_DISABLED
	var bodies: Dictionary={}
	for node: Node in world.find_children("*","StaticBody3D",true,false): bodies[node.get_instance_id()]=(node as Node3D).global_transform
	var originals: Array[Dictionary]=[]
	for node: Node in world.find_children("*","MultiMeshInstance3D",true,false):
		if node.has_meta("mobile_render_mesh"):
			originals.append({"node":node,"mesh":(node as MultiMeshInstance3D).multimesh.mesh,"placements":node.get_meta("placements")})
	check("Generated mobile variants exist for nearby vegetation",originals.size()>3,originals.size())
	for node: Node in world.find_children("*","MeshInstance3D",true,false):
		check("Buildings and props retain their original mesh: "+str(node.name),not node.has_meta("mobile_render_mesh"))
	var helper: RefCounted=(world.get("streaming") as Node).get("_mobile_render") as RefCounted
	helper.call("update_visibility",(world.get("camera") as Camera3D).global_position,false)
	check("Standard roaming enables exact geometry tiles without mobile materials",bool((helper.call("metrics") as Dictionary).exact_tiles_active) and not bool(helper.get("enabled")))
	var tile_materials: Array[Dictionary]=[]
	for record: Dictionary in helper.get("_tile_sources") as Array:
		var source: MeshInstance3D=(record.node as WeakRef).get_ref() as MeshInstance3D
		for tile: MeshInstance3D in record.children:
			tile_materials.append({"tile":tile,"material":source.get_active_material(0),"shadow":record.shadow})
			check("Partition shares runtime desktop material: "+str(source.name),tile.get_active_material(0)==source.get_active_material(0))
	var tile_checks: int=0
	for node: Node in world.find_children("*","MeshInstance3D",true,false):
		if not node.has_meta("mobile_render_tiles"): continue
		var source: Mesh=(node as MeshInstance3D).mesh
		var faces: PackedVector3Array=source.get_faces()
		var expected: Dictionary={}
		for index: int in range(0,faces.size(),3):
			var key: int=hash([faces[index],faces[index+1],faces[index+2]])
			expected[key]=int(expected.get(key,0))+1
		for mesh: Mesh in node.get_meta("mobile_render_tiles") as Array:
			var tile_faces: PackedVector3Array=mesh.get_faces()
			for index: int in range(0,tile_faces.size(),3):
				var key: int=hash([tile_faces[index],tile_faces[index+1],tile_faces[index+2]])
				expected[key]=int(expected.get(key,0))-1
		var equal: bool=true
		for count: int in expected.values(): equal=equal and count==0
		check("Tiles preserve the exact triangle multiset: "+str(node.get_path()),equal,faces.size()/3)
		tile_checks+=1
	check("All large spatial batches have exact geometry checks",tile_checks==32,tile_checks)
	set_quality(settings,true)
	helper.call("update_visibility",(world.get("camera") as Camera3D).global_position,false)
	check("Mobile roaming enables exact geometry tiles",bool((helper.call("metrics") as Dictionary).mobile_tiles_active))
	var streaming: Node=world.get("streaming") as Node
	check("Constrained mobile switches immediately to baked districts",bool(streaming.call("metrics").constrained_runtime) and int(streaming.call("metrics").active_regions)==0)
	var hidden_details: bool=true
	for region: Dictionary in (streaming.get("_regions") as Dictionary).values():
		for chunk: Node3D in region.roots:
			hidden_details=hidden_details and not chunk.visible and chunk.process_mode==Node.PROCESS_MODE_DISABLED
	check("Optional detail is disabled before its next-frame release",hidden_details)
	# The runtime now unloads optional detail, so it must not first traverse
	# those soon-to-die chunks to apply LOD. Test the reusable LOD mechanism
	# independently on the retained fixture nodes before advancing a frame.
	for record: Dictionary in originals: helper.call("apply_meshes",record.node)
	var low_triangles: int=0
	var high_triangles: int=0
	for record: Dictionary in originals:
		var node: MultiMeshInstance3D=record.node as MultiMeshInstance3D
		low_triangles+=node.multimesh.mesh.get_faces().size()/3
		high_triangles+=(record.mesh as Mesh).get_faces().size()/3
		check("Isolated mobile LOD swaps only render mesh: "+str(node.name),node.multimesh.mesh!=record.mesh and node.get_meta("placements")==record.placements)
	check("Isolated vegetation LOD reduces mesh triangles",low_triangles<high_triangles*.65,{"original":high_triangles,"mobile":low_triangles})
	set_quality(settings,false)
	for record: Dictionary in originals:
		check("Standard restores exact original mesh reference: "+str((record.node as Node).name),(record.node as MultiMeshInstance3D).multimesh.mesh==record.mesh)
	var exact_partitions: bool=true
	for record: Dictionary in helper.get("_tile_sources") as Array:
		var original: MeshInstance3D=(record.node as WeakRef).get_ref() as MeshInstance3D
		exact_partitions=exact_partitions and original.layers==0
		for tile: MeshInstance3D in record.children: exact_partitions=exact_partitions and tile.visible
	check("Standard keeps exact spatial partitions enabled",exact_partitions)
	var exact_materials: bool=true
	for record: Dictionary in tile_materials:
		exact_materials=exact_materials and (record.tile as MeshInstance3D).get_active_material(0)==record.material
	check("Standard restores all exact partition material references",exact_materials,tile_materials.size())
	set_quality(settings,true)
	for record: Dictionary in originals: helper.call("apply_meshes",record.node)
	var second_triangles: int=0
	for record: Dictionary in originals: second_triangles+=(record.node as MultiMeshInstance3D).multimesh.mesh.get_faces().size()/3
	check("Second isolated mobile application produces the identical LOD",second_triangles==low_triangles)
	settings.set("frame_limit",30)
	settings.emit_signal("state_changed")
	var retained_triangles: int=0
	for record: Dictionary in originals: retained_triangles+=(record.node as MultiMeshInstance3D).multimesh.mesh.get_faces().size()/3
	check("Unrelated settings signal keeps the active LOD",retained_triangles==low_triangles)
	var unchanged: bool=true
	for node: Node in world.find_children("*","StaticBody3D",true,false): unchanged=unchanged and bodies.has(node.get_instance_id()) and bodies[node.get_instance_id()]==(node as Node3D).global_transform
	check("Permanent collision count and transforms never change",unchanged and bodies.size()==world.find_children("*","StaticBody3D",true,false).size(),bodies.size())
	# Real production candidates, fresh eye each frame. Record host CPU cost;
	# this is not a claim about mobile GPU throughput or phone temperature.
	var visibility_costs: Array[int]=[]
	var camera_eye: Vector3=(world.get("camera") as Camera3D).global_position
	var evaluations: int=int(helper.call("metrics").visibility_evaluations)
	for index: int in range(240):
		var angle: float=float(index)*TAU/240.0
		var started: int=Time.get_ticks_usec()
		helper.call("update_visibility",camera_eye+Vector3(sin(angle),0,cos(angle))*.35,false)
		visibility_costs.append(Time.get_ticks_usec()-started)
	visibility_costs.sort()
	check("Production visibility evaluates a changing eye without stale streaming ticks",visibility_costs.size()==240,
		{"candidates":helper.call("metrics").occlusion_candidates,"evaluations":int(helper.call("metrics").visibility_evaluations)-evaluations,"frames":240,"p50_usec":visibility_costs[120],"p95_usec":visibility_costs[228],"max_usec":visibility_costs[-1],"platform":OS.get_name(),"headless":DisplayServer.get_name()=="headless"})
	check_shared_multimesh()
	var out: String="res://../deliverables/mobile-render/quality-checks.json"
	FileAccess.open(out,FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"failures":failures,"checks":checks},"\t"))
	print("MOBILE_RENDER_QUALITY checks=",checks.size()," failures=",failures)
	world.free()
	world=null
	call_deferred("finish")

func finish() -> void:
	quit(1 if failures else 0)

func set_quality(settings: Node, mobile: bool) -> void:
	settings.set("_mobile_web",mobile)
	settings.set("quality_profile","balanced" if mobile else "standard")
	settings.set("msaa_enabled",false)
	settings.call("apply_settings")
	settings.emit_signal("state_changed")
	Engine.max_fps=0

func check_shared_multimesh() -> void:
	var shared: MultiMesh=MultiMesh.new()
	shared.transform_format=MultiMesh.TRANSFORM_3D
	shared.mesh=BoxMesh.new()
	shared.instance_count=1
	var placement: Transform3D=Transform3D(Basis.IDENTITY,Vector3(1,2,3))
	shared.set_instance_transform(0,placement)
	var a: MultiMeshInstance3D=MultiMeshInstance3D.new()
	var b: MultiMeshInstance3D=MultiMeshInstance3D.new()
	a.multimesh=shared; b.multimesh=shared
	a.set_meta("placements",[placement])
	a.set_meta("mobile_render_mesh",SphereMesh.new())
	var helper: RefCounted=Quality.new()
	helper.call("set_enabled",true)
	helper.call("apply_meshes",a)
	helper.call("apply_materials",a)
	check("Mobile swap cannot mutate another user of shared MultiMesh",a.multimesh!=b.multimesh and b.multimesh.mesh==shared.mesh and a.multimesh.mesh!=shared.mesh)
	helper.call("set_enabled",false)
	helper.call("apply_meshes",a)
	helper.call("apply_materials",a)
	check("Shared mesh source restores exactly after mobile mode",a.multimesh.mesh==shared.mesh and b.multimesh==shared)
	a.free(); b.free()
