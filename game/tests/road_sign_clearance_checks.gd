extends SceneTree

var checks: Array[Dictionary] = []
var failures: int = 0
const OUTPUT: String = "res://../deliverables/world-correction/"

func _initialize() -> void:
	call_deferred("run")

func check(label: String, passed: bool, evidence: Variant = null) -> void:
	checks.append({"test":label,"passed":passed,"evidence":evidence})
	if not passed:
		failures += 1
		push_error(label+": "+str(evidence))

func check_sign(sign_node: Node3D, post_name: String, plate_name: String) -> void:
	var post: MeshInstance3D = sign_node.get_node(post_name)
	var plate: MeshInstance3D = sign_node.get_node(plate_name)
	var post_box: AABB = post.transform*post.get_aabb()
	var plate_box: AABB = plate.transform*plate.get_aabb()
	check(str(sign_node.get_path())+" support ends below lettering panel",post_box.end.y<=plate_box.position.y+.0001,{"post_top":post_box.end.y,"board_bottom":plate_box.position.y})
	var faces: Array[Label3D] = []
	for child: Node in sign_node.get_children():
		if child is Label3D and (child as Label3D).visible: faces.append(child as Label3D)
	if post_name=="MarkerPost":
		for child: Node in sign_node.get_parent().get_children():
			if child is Label3D and str(child.name).begins_with("StationLabel") and (child as Label3D).visible: faces.append(child as Label3D)
	var front: bool = false
	var back: bool = false
	for label: Label3D in faces:
		var local: Transform3D = sign_node.global_transform.affine_inverse()*label.global_transform
		front = front or (local.origin.z>plate_box.end.z and local.basis.z.z>.99)
		back = back or (local.origin.z<plate_box.position.z and local.basis.z.z<-.99)
	check(str(sign_node.get_path())+" two readable faces outside solid panel",front and back)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate()
	root.add_child(world)
	current_scene = world
	world.set_process(false)
	(world.get("hud") as CanvasLayer).visible = false
	var signs: Array[Node] = world.find_children("RouteSign*","Node3D",true,false)
	check("All 24 shipped bridge signs are inspected",signs.size()==24,signs.size())
	for sign_node: Node in signs: check_sign(sign_node,"Post","DestinationPlate")
	for sign_node: Node in world.find_children("EntranceWayfinding","Node3D",true,false): check_sign(sign_node,"MarkerPost","EntranceMarker")
	if OS.get_cmdline_user_args().has("--capture"):
		root.size = Vector2i(1280,800)
		var camera: Camera3D = world.get("camera")
		camera.near = .01
		camera.fov = 45
		var sign_node: Node3D = signs[0] as Node3D
		for side: float in [1.0,-1.0]:
			camera.global_position = sign_node.to_global(Vector3(.3,1.55,side*2.6))
			camera.look_at(sign_node.to_global(Vector3(0,1.2,0)),sign_node.global_basis.y.normalized())
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OUTPUT+("bridge-sign-front.png" if side>0 else "bridge-sign-back.png"))
	world.free()
	# Trail signs stream with reserves, so inspect their canonical scene too.
	var source: Node3D = (load("res://generated/globe.tscn") as PackedScene).instantiate()
	root.add_child(source)
	var trails: Array[Node] = []
	for node: Node in source.find_children("*","Node3D",true,false):
		if node.has_node("SteelPost") and node.has_node("TrailNotice"): trails.append(node)
	var expected_trails: int = 0
	var biomes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/biomes.json")) as Dictionary
	for key: String in biomes:
		if biomes[key] is Dictionary: expected_trails += (biomes[key].get("trails",[]) as Array).size()*2
	check("Every authored nature trail endpoint has a sign",trails.size()==expected_trails and expected_trails>=12,trails.size())
	for sign_node: Node in trails: check_sign(sign_node,"SteelPost","TrailNotice")
	source.free()
	FileAccess.open(OUTPUT+"sign-checks.json",FileAccess.WRITE).store_string(JSON.stringify({"passed":failures==0,"checks":checks},"\t"))
	print("ROAD_SIGN_CHECKS count=",checks.size()," failures=",failures)
	quit(1 if failures else 0)
