extends "res://tests/check_training_room.gd"

# Fixed native-rendered comparisons for the September wall / projector revision.
# No art, light, collision or material is hidden or replaced by this fixture.
var revision: String = "before"

func _initialize() -> void:
	capture_images = true
	if "after" in OS.get_cmdline_user_args():
		revision = "after"
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Revision captures require the native renderer.")
		quit(1)
		return
	root.size = Vector2i(1280,800)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	room = (load("res://scenes/training_room.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(room)
	current_scene = room
	indoor = room.get("player") as CharacterBody3D
	await tick(20)
	check("Revision room loads and places a grounded player",bool(room.get("ready_for_play")) and indoor.is_on_floor())
	check_assets()
	check_physics_queries()
	check_revision_clearance()
	if revision == "after":
		await check_revision_walk()
		check_projector_optics()
		var titles: Array[String] = []
		for node: Node in room.find_children("*","Label",true,false):
			titles.append((node as Label).text)
		check("Area HUD is named 練功區, independent of its WordKing device","練功區" in titles and not "單字練功區" in titles and not "單字王 / 練功區" in titles,titles)
	room.set_process(false)
	var room_camera: Camera3D = room.get("camera") as Camera3D
	indoor.call("place_at",Vector3(8.5,.09,4.4),Vector3.RIGHT)
	await tick(5)
	room_camera.fov = 67.0
	room_camera.global_position = Vector3(5.10,2.35,5.0)
	room_camera.look_at(Vector3(9.85,1.3,4.6),Vector3.UP)
	await take("revision-"+revision+"-wall","Fixed east wall view matching the reported empty wall; camera and assets unchanged between captures")
	indoor.call("place_at",Vector3(4.2,.09,3.0),Vector3.FORWARD)
	await tick(5)
	room_camera.fov = 48.0
	room_camera.global_position = Vector3(.65,1.70,3.65)
	room_camera.look_at(Vector3(.65,1.4,-.8),Vector3.UP)
	await take("revision-"+revision+"-device","Fixed frontal projector view; live game lights, imported materials, and enclosing walls retained")
	(room.get("ui_root") as Control).visible = false
	await take("revision-"+revision+"-device-clean","Same frontal device camera with only the HUD hidden for unobscured lighting inspection")
	(room.get("ui_root") as Control).visible = true
	room_camera.fov = 70.0
	room_camera.global_position = Vector3(2.4,2.65,7.8)
	room_camera.look_at(Vector3(4.4,1.2,1.0),Vector3.UP)
	await take("revision-"+revision+"-east-wide","Room entrance sightline toward the projector and east wall")
	finish_revision()

func check_revision_clearance() -> void:
	# The central circulation route and the approach to the east wall must fit the
	# actual 0.54 m wide capsule. Shallow built-ins may occupy x > 8.6 only.
	var routes: Array[Dictionary] = [
		{"name":"Central entry route","start":Vector3(0,.06,6.2),"end":Vector3(0,.06,1.6)},
		{"name":"East wall approach","start":Vector3(3,.06,5.5),"end":Vector3(8.40,.06,5.5)},
		{"name":"East wall circulation","start":Vector3(8.35,.06,2.0),"end":Vector3(8.35,.06,7.0)}
	]
	for route: Dictionary in routes:
		var blocked: Array[Dictionary] = []
		for index: int in range(25):
			var point: Vector3 = (route.start as Vector3).lerp(route.end as Vector3,float(index)/24.0)
			var hits: Array[Dictionary] = capsule_hits(point)
			if not hits.is_empty():
				blocked.append({"position":vec(point),"body":str((hits[0].collider as Node).name)})
		check(str(route.name)+" admits a full player capsule",blocked.is_empty(),blocked)

func check_revision_walk() -> void:
	indoor.call("place_at",Vector3(8.35,.09,2.0),Vector3.BACK)
	await tick(12)
	var start_point: Vector3 = indoor.position
	key_event(KEY_W,true)
	await tick(72)
	key_event(KEY_W,false)
	await tick(4)
	check("Real W input walks the clear corridor beside the east wall",indoor.position.z > 6.3 and absf(indoor.position.x-8.35) < .06 and indoor.is_on_floor(),{"from":vec(start_point),"to":vec(indoor.position)})
	var required_proxies: Dictionary = {"Reading_Bookcase":Vector3(8.2,1.15,1.9),"Reading_Bench":Vector3(8.2,.38,4.5),"Reading_Wayfinding":Vector3(8.2,1.5,6.8)}
	for proxy_name: String in required_proxies:
		var origin: Vector3 = required_proxies[proxy_name] as Vector3
		var contact: Dictionary = ray(origin,Vector3(10,origin.y,origin.z))
		check("Authored "+proxy_name+" blocks walking through its physical surface",not contact.is_empty() and str((contact.get("collider") as Node).name) == proxy_name,hit_path(contact))

func check_projector_optics() -> void:
	var expected_roles: Array[String] = ["Hologram_Beam","Hologram_Glass","Hologram_Cyan","Hologram_Type","Hologram_Grid","Projector_Blue_Inlay"]
	var found_roles: Array[String] = []
	var optical_meshes: int = 0
	var shadowless: bool = true
	var physical_shadow_meshes: int = 0
	var field_shaders: Dictionary = {}
	for node: Node in room.find_children("*","MeshInstance3D",true,false):
		var mesh_node: MeshInstance3D = node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		if bool(mesh_node.get_meta("projector_optical",false)):
			optical_meshes += 1
			shadowless = shadowless and mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for surface: int in range(mesh_node.mesh.get_surface_count()):
			var authored: Material = mesh_node.mesh.surface_get_material(surface)
			if authored == null:
				continue
			var role: String = authored.resource_name.trim_prefix("MAT_Game_")
			if role in expected_roles:
				if not role in found_roles:
					found_roles.append(role)
				var applied: Material = mesh_node.get_active_material(surface)
				if applied is ShaderMaterial:
					field_shaders[role] = (applied as ShaderMaterial).shader.resource_path
			elif str(mesh_node.name).begins_with("SM_Device_") and mesh_node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				physical_shadow_meshes += 1
	check("All six separate optical roles survived Blender export and Godot import",found_roles.size() == expected_roles.size(),found_roles)
	check("Projected light geometry never casts solid shadows",optical_meshes >= expected_roles.size() and shadowless,optical_meshes)
	check("Beam fan and hologram sheet use their intended runtime fields",field_shaders.get("Hologram_Beam","") == "res://shaders/training_projection.gdshader" and field_shaders.get("Hologram_Glass","") == "res://shaders/training_hologram.gdshader",field_shaders)
	check("Physical projector housing retains grounded contact shadows",physical_shadow_meshes > 0,physical_shadow_meshes)
	var spill: OmniLight3D = room.find_child("BlueLensSpill",true,false) as OmniLight3D
	check("Emitter adds a local blue light to the physical housing",spill != null and spill.light_energy > 0.0 and spill.light_color.b > spill.light_color.g and spill.omni_range < 3.0,{"energy":spill.light_energy if spill else 0.0,"range":spill.omni_range if spill else 0.0})

func finish_revision() -> void:
	var report: Dictionary = {"revision":revision,"passed":failures == 0,"failures":failures,"checks":checks,"images":images,"renderer":DisplayServer.get_name(),"capture_note":"Actual native Godot OpenGL3 viewport with production room art, materials, lighting and collision. Camera placements select reproducible views; no production scene edits made by this fixture."}
	var file: FileAccess = FileAccess.open(OUTPUT+"revision-"+revision+"-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	print("TRAINING_REVISION ",revision," checks=",checks.size()," failures=",failures)
	quit(1 if failures > 0 else 0)
