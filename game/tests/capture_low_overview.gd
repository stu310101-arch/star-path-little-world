extends SceneTree

# Static asset comparison fixture: same current world lighting and camera on
# both saved pre-change bases and regenerated bases; no gameplay or FPS claims.
func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Overview comparison requires a real renderer")
		quit(1)
		return
	root.size = Vector2i(1200, 750)
	root.msaa_3d = Viewport.MSAA_DISABLED
	root.scaling_3d_scale = 1.0
	var base: String = "res://generated/streaming/"
	var prefix: String = "after"
	if "before" in OS.get_cmdline_user_args():
		base = ProjectSettings.globalize_path("res://").path_join("../build/low-end/overview-before/").simplify_path()
		prefix = "before"
	var world: Node3D = (load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	world.set_script(null)
	for node_name: String in ["Globe", "Neighborhood", "Stations"]:
		var old: Node = world.get_node(node_name)
		world.remove_child(old)
		old.free()
		var path: String = base.path_join(node_name.to_lower() + "_base.scn")
		world.add_child((ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate())
	root.add_child(world)
	current_scene = world
	var camera: Camera3D = Camera3D.new()
	camera.fov = 42.0
	camera.far = 336.0
	camera.near = .08
	world.add_child(camera)
	camera.make_current()
	var output: String = ProjectSettings.globalize_path("res://").path_join("../deliverables/low-end/overview").simplify_path()
	DirAccess.make_dir_recursive_absolute(output)
	var poses: Array[Vector3] = [Vector3(.45, .63, 177.6), Vector3(2.0,.45,155), Vector3(3.85,-.25,145)]
	var stats: Dictionary = {"mesh_instances":0,"overview_meshes":0,"surfaces":0,"poses":[],"renderer":"Compatibility","gpu":RenderingServer.get_video_adapter_name(),"viewport":[1200,750],"msaa":"off","scaling_3d":1.0}
	for node: Node in world.find_children("*", "MeshInstance3D", true, false):
		stats.mesh_instances += 1
		stats.surfaces += (node as MeshInstance3D).mesh.get_surface_count()
		if node.get_parent().has_meta("streaming_overview_id"):
			stats.overview_meshes += 1
	for index: int in range(poses.size()):
		var pose: Vector3 = poses[index]
		var basis: Basis = Basis(Vector3.UP, pose.x) * Basis(Vector3.RIGHT, -pose.y)
		camera.global_transform = Transform3D(basis, basis.z * pose.z)
		for _frame: int in range(12):
			await process_frame
		await RenderingServer.frame_post_draw
		var path: String = output.path_join(prefix + "-%d.png" % index)
		var status: Error = root.get_texture().get_image().save_png(path)
		if status != OK:
			push_error("Cannot save comparison " + path)
			quit(1)
			return
		print("OVERVIEW_CAPTURE ", path)
		(stats.poses as Array).append({"index":index,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),"primitives":int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))})
	FileAccess.open(output.path_join(prefix + "-capture.json"), FileAccess.WRITE).store_string(JSON.stringify(stats,"\t"))
	world.queue_free()
	await process_frame
	quit()
