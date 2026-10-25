extends SceneTree

const Architecture = preload("res://scripts/world_architecture.gd")
const Furniture = preload("res://scripts/world_street_furniture.gd")
const Startup = preload("res://tests/startup_fixture.gd")
var kit: RefCounted = Architecture.new()
var furniture: RefCounted = Furniture.new()
var world: Node3D

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	root.size = Vector2i(1440,900)
	world = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	current_scene = world
	furniture.call("apply",world.get_node("Stations"))
	(world.get("streaming") as Node).connect("chunk_added",func(chunk: Node3D):
		kit.call("apply",chunk)
		furniture.call("apply",chunk)
	)
	world.call("teleport_to","life")
	if not await Startup.wait_roaming(world,self):
		quit(1)
		return
	for _i: int in range(40): await physics_frame
	world.set_process(false)
	(world.get("camera_obstruction") as RefCounted).call("set_active",false)
	(world.get("player") as Node3D).set_physics_process(false)
	(world.get("hud") as CanvasLayer).visible = false
	var camera: Camera3D = world.get("camera") as Camera3D
	var candidates: Array[Node] = world.find_children("ArchitecturalEnvelope","MeshInstance3D",true,false)
	var taken: int = 0
	for envelope: MeshInstance3D in candidates:
		var wrapper: Node3D = envelope.get_parent() as Node3D
		if wrapper.global_position.z < 35.0: continue
		var bounds: AABB = envelope.mesh.get_aabb()
		var target: Vector3 = wrapper.to_global(Vector3(0,bounds.size.y*.43,0))
		var eye: Vector3 = wrapper.to_global(Vector3(bounds.size.x*1.2,bounds.size.y*.54,bounds.size.z*.5+maxf(7.0,bounds.size.y*1.4)))
		camera.fov = 48.0
		camera.h_offset = 0.0
		camera.global_transform = Transform3D(Basis.IDENTITY,eye).looking_at(target,wrapper.global_basis.y)
		for _frame: int in range(5): await process_frame
		await RenderingServer.frame_post_draw
		var path: String = "res://../deliverables/world-revision/architecture-%02d.png" % taken
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
		print("ARCHITECTURE_CAPTURE ",path," ",wrapper.name)
		taken += 1
		if taken == 3: break
	quit()
