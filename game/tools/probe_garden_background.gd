extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func run() -> void:
	root.size=Vector2i(1440,900)
	var world: Node3D=(load("res://scenes/world.tscn") as PackedScene).instantiate() as Node3D
	root.add_child(world)
	world.set_process(false)
	world.call("set_overview",false)
	var report: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../deliverables/authored-garden/capture-report.json"))
	var record: Dictionary=report.images[5]
	var camera: Camera3D=world.get("camera") as Camera3D
	var player: PlanetPlayer=world.get("player") as PlanetPlayer
	player.set_physics_process(false)
	player.global_position=vector(record.player_position)
	player.heading=vector(record.heading)
	var radial: Vector3=player.global_position.normalized()
	player.global_basis=Basis(player.heading.cross(radial).normalized(),radial,-player.heading)
	player.visual.rotation.y=PI
	world.set("near_distance",7.0)
	world.set("near_pitch",.42)
	for i: int in range(90):
		world.call("update_camera",1.0/30.0)
		world.call("update_nearest")
		await process_frame
	camera.global_transform=Transform3D(Basis.IDENTITY,vector(record.camera_position)).looking_at(vector(record.camera_aim),vector(record.player_position).normalized())
	await process_frame
	print("CAMERA "+str(root.get_visible_rect())+" "+str(camera.fov)+" "+str(camera.global_transform))
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/background-before.png"))
	for node: Node in world.find_children("*","MultiMeshInstance3D",true,false):
		var multi: MultiMeshInstance3D=node as MultiMeshInstance3D
		print("MULTIMESH "+str(multi.get_path())+" "+str(multi.get_aabb()))
		multi.visible=false
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/background-no-multimesh.png"))
	(world.get("camera_obstruction") as RefCounted).call("reset")
	if DisplayServer.get_name()!="headless":
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../deliverables/background-no-fade.png"))
	for pixel: Vector2 in [Vector2(400,160),Vector2(550,50),Vector2(660,250)]:
		var origin: Vector3=camera.project_ray_origin(pixel)
		var direction: Vector3=camera.project_ray_normal(pixel)
		var hits: Array[Dictionary]=[]
		for node: Node in world.find_children("*","MeshInstance3D",true,false):
			var mesh: MeshInstance3D=node as MeshInstance3D
			if not mesh.is_visible_in_tree() or mesh.mesh==null:
				continue
			var local_from: Vector3=mesh.to_local(origin)
			var local_to: Vector3=mesh.to_local(origin+direction*300)
			if mesh.get_aabb().intersects_segment(local_from,local_to)==null:
				continue
			var local_direction: Vector3=(local_to-local_from).normalized()
			var points: PackedVector3Array=mesh.mesh.get_faces()
			var closest: float=INF
			for i: int in range(0,points.size(),3):
				var hit: Variant=Geometry3D.ray_intersects_triangle(local_from,local_direction,points[i],points[i+1],points[i+2])
				if hit!=null:
					closest=minf(closest,origin.distance_to(mesh.to_global(hit as Vector3)))
			if closest<300:
				hits.append({"path":str(mesh.get_path()),"distance":closest,"bounds":str(mesh.get_aabb()),"material":str(mesh.get_active_material(0))})
		hits.sort_custom(func(a: Dictionary,b: Dictionary) -> bool: return float(a.distance)<float(b.distance))
		print("BACKGROUND_PIXEL "+str(pixel)+" "+JSON.stringify(hits.slice(0,8)))
	quit()
